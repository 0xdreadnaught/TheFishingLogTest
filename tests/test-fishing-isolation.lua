-- The test build talks only to itself: the real Comm module, no game or network access.
-- Run from the repository root:  node tests/lua-parser/node_modules/fengari-node-cli/src/lua-cli.js tests/test-fishing-isolation.lua
local F = assert(loadfile("tests/fishing-sync-fixture.lua"))()
local source = ""
local UPSTREAM_PREFIX, UPSTREAM_CHANNEL = "FishingLog", "TheFishingLog"
local failures = 0
local wire, registered = {}, {}
InCombatLockdown = function() return false end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) registered[#registered + 1] = prefix end,
    SendAddonMessage = function(prefix, msg, road, to) wire[#wire + 1] = { prefix = prefix, msg = msg, road = road, to = to } return 0 end,
}
local function Client()
    F.setTime(100); F.clear(); wire, registered = {}, {}
    local c = F.Client("Local", false)
    assert(loadfile(source .. "Comm.lua"))("TheFishingLogTest", c)
    c.listeners.TFL_INIT[1](c)
    return c, F.pump()
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print("PASS: " .. name) else failures = failures + 1; print("FAIL: " .. name .. ": " .. tostring(err)) end
end

test("prefix and channel differ from upstream and fit the client's limits", function()
    local c = Client()
    assert(c.PREFIX ~= UPSTREAM_PREFIX and #c.PREFIX <= 16, "prefix " .. tostring(c.PREFIX))
    assert(c.CHANNEL ~= UPSTREAM_CHANNEL and c.CHANNEL:lower() ~= UPSTREAM_CHANNEL:lower(), "channel " .. tostring(c.CHANNEL))
    assert(#registered == 1 and registered[1] == c.PREFIX, "registered " .. table.concat(registered, ","))
end)

test("a message on the upstream prefix is ignored; the same message on ours is handled", function()
    local c = Client()
    local heard = 0
    c.handlers.TESTPING = function() heard = heard + 1 end
    c:Fire("CHAT_MSG_ADDON", UPSTREAM_PREFIX, "LIVE2~1~?~TESTPING~1", "WHISPER", "Peer")
    assert(heard == 0, "handled a message from the upstream network")
    c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~TESTPING~1", "WHISPER", "Peer")
    assert(heard == 1, "did not handle a message on its own prefix")
end)

test("everything sent goes out on our prefix only", function()
    local c, pump = Client()
    c:Whisper("Peer", "TESTPING", "1")
    c:SendGuild("TESTPING", "2")
    for _ = 1, 10 do F.advance(1); pump() end
    assert(#wire >= 1, "nothing was sent")
    for _, m in ipairs(wire) do assert(m.prefix == c.PREFIX, "sent on " .. tostring(m.prefix)) end
end)

test("login shows the test-build notice with the build number", function()
    -- Only TestBuild.lua, on a bare stand-in for the addon table.
    local c, said = { listeners = {}, ADDON = "TheFishingLogTest" }, {}
    function c:On(event, fn) self.listeners[event] = self.listeners[event] or {}; table.insert(self.listeners[event], fn) end
    function c:Print(msg) said[#said + 1] = msg end
    local timer, meta = C_Timer, GetAddOnMetadata
    local waited
    C_Timer = { After = function(seconds, fn) waited = seconds; fn() end }
    GetAddOnMetadata = function(addon, field) return addon == "TheFishingLogTest" and field == "X-Build" and "5" or nil end
    local ok, err = pcall(function()
        assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
        assert(#c.listeners.TFL_LOGIN == 1, "no login listener")
        c.listeners.TFL_LOGIN[1](c)
    end)
    C_Timer, GetAddOnMetadata = timer, meta
    assert(ok, err)
    assert(waited and waited > 0, "notice should wait for the login chatter to pass")
    assert(said[1]:find("TEST BUILD 5", 1, true) and said[1]:find("not the main addon", 1, true), said[1])
    -- no world known: the second line says nothing will sync and what to do about it
    assert(#said == 2 and said[2]:find("Couldn't tell", 1, true) and said[2]:find("/tfl clientdiag", 1, true), tostring(said[2]))
    -- world known: the second line names it
    said = {}
    c.worldKey = "US-PvP"; function c:WorldLabel() return "Americas & Oceania, PvP" end
    c:TestBuildNotice()
    assert(#said == 2 and said[2]:find("You are on Americas & Oceania, PvP", 1, true), tostring(said[2]))
end)

test("a newer build heard from another tester is announced once; older, equal and junk are not", function()
    local c, said = { listeners = {}, ADDON = "TheFishingLogTest" }, {}
    function c:On(event, fn) self.listeners[event] = self.listeners[event] or {}; table.insert(self.listeners[event], fn) end
    function c:Print(msg) said[#said + 1] = msg end
    function c:IsMe(name) return name == "Me" end
    function c:AnglerKey(name) return name:lower() end
    function c.BuildNumber() return "12" end
    local timer = C_Timer
    C_Timer = { After = function(_, fn) fn() end }
    local ok, err = pcall(function()
        assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
        assert(c:BuildsHeardText() == "none yet")
        for _, junk in ipairs({ "", "abc", "1.1.4", "-3", "0", "123456", "12x" }) do c:NoteBuild("Peer", junk) end
        c:NoteBuild("Peer", nil); c:NoteBuild("Me", "99")
        assert(#said == 0 and c:BuildsHeardText() == "none yet", "junk or my own build counted: " .. c:BuildsHeardText())
        c:NoteBuild("Old", "10"); c:NoteBuild("Same", "12")
        assert(#said == 0, "an older or equal build is nothing to announce")
        c:NoteBuild("New", "14")
        assert(#said == 1 and said[1]:find("Test build 14 is out; you have 12", 1, true) and said[1]:find("git pull", 1, true), tostring(said[1]))
        c:NoteBuild("Newer", "15"); c:NoteBuild("New", "14")
        assert(#said == 1, "announced more than once in a session")
        assert(c:BuildsHeardText() == "15 x1, 14 x1, 12 x1, 10 x1", c:BuildsHeardText())
    end)
    C_Timer = timer
    assert(ok, err)
end)

test("WHO and HERE end with the build number, and a WHO or HERE without one is still handled", function()
    local c, pump = Client()
    local meta = GetAddOnMetadata
    GetAddOnMetadata = function(_, field) return field == "X-Build" and "12" or field == "Version" and "1.1.4" or nil end
    local heard = {}
    local ok, err = pcall(function()
        c.ADDON = "TheFishingLogTest"
        c.census = c.census or { players = {} }
        function c:NoteBuild(sender, build) heard[#heard + 1] = sender .. "=" .. tostring(build) end
        function c:ReplyOnce(_, _, _, fn) fn() end
        function c:MyRank() return 3 end
        function c:MapID() return 1458 end
        function c:MyFaction() return "H" end
        function c:MyGuild() return "" end
        function c:CountingFloor() return "1.1.2" end
        function c:NoteCountingFloor() end
        function c:RankFromWire(rank) return rank end
        function c:NoteAngler() end
        function c:NoteGuild() end
        c.ValidVersion = function(v) return type(v) == "string" and v:match("^%d+%.%d+%.%d+$") ~= nil end
        time = time or os.time
        assert(loadfile(source .. "Census.lua"))("TheFishingLogTest", c)
        assert(c.BuildNumber() == "12")
        -- a whispered WHO from a tester: their build is noted, and our HERE goes back with ours on the end
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~WHO~1.1.4~14", "WHISPER", "Peer")
        assert(heard[1] == "Peer=14", tostring(heard[1]))
        for _ = 1, 10 do F.advance(1); pump() end
        local here
        for _, m in ipairs(wire) do if m.msg:find("~HERE~", 1, true) then here = m.msg end end
        assert(here and here:find("~1%.1%.2~12~~$"), "HERE should end with the counting floor, the build, the channel and the refusals (none here): " .. tostring(here))
        -- the channel a peer says it is in reaches the lock code, from WHO and from HERE
        local told = {}
        function c:NotePeerChannel(sender, field) told[#told + 1] = sender .. "=" .. tostring(field) end
        function c:NotePeerRefusals(sender, field, theirs) told[#told + 1] = sender .. " refused by " .. tostring(field) .. " now in " .. tostring(theirs) end
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~WHO~1.1.4~24~3~3", "WHISPER", "Asker")
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~HERE~1.1.4~3~1458~H~100~~50~1.1.2~24~xkqzpab~mh33", "WHISPER", "Teller")
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~WHO~1.1.4~24~1", "WHISPER", "Build24") -- a build that sends no refusals
        assert(told[1] == "Asker refused by 3 now in 3" and told[2] == "Asker=3" and told[3] == "Teller refused by mh33 now in xkqzpab"
            and told[4] == "Teller=xkqzpab" and told[5] == "Build24 refused by nil now in 1" and told[6] == "Build24=1", table.concat(told, " | "))
        c.NotePeerChannel, c.NotePeerRefusals = nil, nil
        -- from a build that doesn't send one (10 to 15)
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~WHO~1.1.4", "WHISPER", "Older")
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~HERE~1.1.4~3~1458~H~100~~50~1.1.2", "WHISPER", "Older")
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~HERE~1.1.4~3~1458~H~100~~50~1.1.2~15", "WHISPER", "Newer")
        assert(heard[5] == "Older=nil" and heard[6] == "Older=nil" and heard[7] == "Newer=15", table.concat(heard, " "))
    end)
    GetAddOnMetadata = meta
    assert(ok, err)
end)

test("/tfl channeltest sends exactly one message and reports refused, came back, or silent", function()
    local saved = { CreateFrame, C_ChatInfo, GetChannelName, C_Timer, Enum, GetTime }
    local ok, err = pcall(function()
        local clock, frames, sent, timers = 1000, {}, {}, {}
        GetTime = function() return clock end
        CreateFrame = function()
            local f = { events = {} }
            function f:RegisterEvent(e) self.events[e] = true end
            function f:SetScript(_, fn) self.handler = fn end
            frames[#frames + 1] = f
            return f
        end
        local function deliver(prefix, text, dist, sender)
            for _, f in ipairs(frames) do if f.handler then f.handler(f, "CHAT_MSG_ADDON", prefix, text, dist, sender) end end
        end
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
        local function finish() local run = timers; timers = {}; for _, fn in ipairs(run) do fn() end end
        Enum = { SendAddonMessageResult = { Success = 0, InvalidChannel = 4 } }
        local joined, answer, echo = 0, 0, false
        GetChannelName = function() return joined end
        C_ChatInfo = { SendAddonMessage = function(prefix, msg, dist, target)
            sent[#sent + 1] = { prefix = prefix, msg = msg, dist = dist, target = target }
            if echo then deliver(prefix, msg, "CHANNEL", "Me") end
            return answer
        end }
        local c, said, commands = { listeners = {}, ADDON = "TheFishingLogTest", PREFIX = "FishingLogTest", CHANNEL = "TheFishingLogTest" }, {}, {}
        function c:On() end
        function c:Print(msg) said[#said + 1] = msg end
        function c:IsMe(name) return name == "Me" end
        function c:Command(name, _, _, fn) commands[name] = fn end
        assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
        assert(commands.channeltest, "command not registered")
        local function try() said = {}; clock = clock + 60; commands.channeltest(c); finish(); return table.concat(said, " | ") end

        local text = try()
        assert(#sent == 0 and text:find("not in the TheFishingLogTest channel", 1, true), text)
        joined = 6
        answer = 4
        text = try()
        assert(#sent == 1 and sent[1].dist == "CHANNEL" and sent[1].target == 6 and sent[1].prefix == "FishingLogTest", "one send to our channel")
        assert(sent[1].msg:find("^CHTEST~%d+$") and text:find("answered: 4 (InvalidChannel)", 1, true) and text:find("refused it", 1, true), text)
        answer, echo = 0, true
        text = try()
        assert(#sent == 2 and text:find("(Success)", 1, true) and text:find("DO travel over a custom channel", 1, true), text)
        echo = false
        text = try()
        assert(#sent == 3 and text:find("accepted it but nothing came back", 1, true), text)
        -- typed twice in a row: the second is not sent
        said = {}; commands.channeltest(c)
        assert(#sent == 3 and said[1]:find("wait", 1, true), tostring(said[1]))
        -- another player's test heard on the channel is counted; ours and other traffic are not
        deliver("FishingLogTest", "CHTEST~123456", "CHANNEL", "Peer")
        deliver("FishingLogTest", "CHTEST~123456", "CHANNEL", "Me")
        deliver("FishingLogTest", "CHTEST~123456", "WHISPER", "Peer")
        deliver("FishingLog", "CHTEST~123456", "CHANNEL", "Peer")
        assert(c.channelTestsHeard == 1, tostring(c.channelTestsHeard))
    end)
    CreateFrame, C_ChatInfo, GetChannelName, C_Timer, Enum, GetTime = saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
    assert(ok, err)
end)

test("/tfl channeltest slots counts how many channels fit and leaves every test channel again", function()
    local names = { "CreateFrame", "C_ChatInfo", "GetChannelName", "C_Timer", "GetTime", "JoinTemporaryChannel", "LeaveChannelByName",
        "GetChannelList", "MAX_WOW_CHAT_CHANNELS", "ChatFrame_AddMessageEventFilter" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local ok, err = pcall(function()
        local timers, filters = {}, {}
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
        local function settle() for _ = 1, 200 do if #timers == 0 then return end local fn = table.remove(timers, 1); fn() end error("never settled") end
        GetTime = function() return 1000 end
        CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
        ChatFrame_AddMessageEventFilter = function(event, fn) filters[event] = fn end
        MAX_WOW_CHAT_CHANNELS = 10
        local slots = { [1] = "General", [2] = "Trade", [6] = "TheFishingLogTest" } -- number -> name
        local function count() local n = 0 for _ in pairs(slots) do n = n + 1 end return n end
        GetChannelName = function(name) for id, n in pairs(slots) do if n == name then return id end end return 0 end
        GetChannelList = function() local out = {} for id, n in pairs(slots) do out[#out + 1] = id; out[#out + 1] = n; out[#out + 1] = false end return table.unpack(out) end
        JoinTemporaryChannel = function(name) if count() >= 10 then return end for id = 1, 10 do if not slots[id] then slots[id] = name return end end end
        LeaveChannelByName = function(name) for id, n in pairs(slots) do if n == name then slots[id] = nil end end end
        local c, said, commands = { listeners = {}, ADDON = "TheFishingLogTest", PREFIX = "FishingLogTest", CHANNEL = "TheFishingLogTest" }, {}, {}
        function c:On() end
        function c:Print(msg) said[#said + 1] = msg end
        function c:Command(name, _, _, fn) commands[name] = fn end
        assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
        commands.channeltest(c, { "slots" })
        commands.channeltest(c, { "slots" }) -- typed again while running
        settle()
        local text = table.concat(said, " | ")
        assert(text:find("stated limit is 10. You are in 3 now; ours is number 6", 1, true), text)
        assert(text:find("already running", 1, true), text)
        assert(text:find("joined 7 more before the client stopped taking them, so 10 at once", 1, true), text)
        assert(text:find("given the numbers 3 4 5 7 8 9 10", 1, true), text)
        assert(text:find("left 8 of 8 test channels. Ours was number 6 and is now 6", 1, true), text)
        assert(count() == 3, "test channels left behind: " .. count())
        -- the join and leave notices for the test channels are kept out of chat; others are not
        assert(filters.CHAT_MSG_CHANNEL_NOTICE(nil, nil, "YOU_JOINED", "", "", "7. TFLTestProbe4") == true)
        assert(not filters.CHAT_MSG_CHANNEL_NOTICE(nil, nil, "YOU_JOINED", "", "", "2. Trade"))
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    assert(ok, err)
end)

test("/tfl channeltest rate sends 45 messages, counts accepted, throttled and returned, and hears others' runs", function()
    local names = { "CreateFrame", "C_ChatInfo", "GetChannelName", "C_Timer", "GetTime", "Enum" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local ok, err = pcall(function()
        local timers, frames, sent, clock = {}, {}, {}, 1000
        C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = delay, fn = fn, order = #timers } end }
        local function settle()
            table.sort(timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.order < b.order end)
            local run = timers; timers = {}
            for _, t in ipairs(run) do t.fn() end
        end
        GetTime = function() return clock end
        CreateFrame = function() local f = {} function f:RegisterEvent() end function f:SetScript(_, fn) self.handler = fn end frames[#frames + 1] = f return f end
        local function deliver(text, sender) for _, f in ipairs(frames) do if f.handler then f.handler(f, "CHAT_MSG_ADDON", "FishingLogTest", text, "CHANNEL", sender) end end end
        Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
        GetChannelName = function() return 6 end
        C_ChatInfo = { SendAddonMessage = function(_, msg, dist, target)
            sent[#sent + 1] = msg
            assert(dist == "CHANNEL" and target == 6)
            local step = tonumber(msg:match("^CHRATE~%d+~(%d)~"))
            if step == 3 and #sent % 2 == 0 then return 3 end -- the fastest step is throttled half the time
            deliver(msg, "Somebody Else") -- our own echo, with a sender name the addon wouldn't recognise as us
            return 0
        end }
        local c, said, commands = { listeners = {}, ADDON = "TheFishingLogTest", PREFIX = "FishingLogTest", CHANNEL = "TheFishingLogTest" }, {}, {}
        function c:On() end
        function c:Print(msg) said[#said + 1] = msg end
        function c:IsMe() return false end
        function c:Command(name, _, _, fn) commands[name] = fn end
        assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
        commands.channeltest(c, { "rate" })
        commands.channeltest(c, { "rate" }) -- again straight away: refused
        settle()
        local text = table.concat(said, " | ")
        assert(#sent == 45, "sent " .. #sent)
        assert(sent[1]:find("^CHRATE~%d+~1~1~45$") and sent[45]:find("^CHRATE~%d+~3~20~45$"), sent[1] .. " .. " .. sent[45])
        assert(text:find("wait a minute between runs", 1, true), text)
        assert(text:find("2 a second: 10 sent, 10 accepted, 0 throttled, 0 refused, 10 came back", 1, true), text)
        assert(text:find("5 a second: 15 sent, 15 accepted, 0 throttled, 0 refused, 15 came back", 1, true), text)
        assert(text:find("10 a second: 20 sent, 10 accepted, 10 throttled, 0 refused, 10 came back", 1, true), text)
        assert(c.rateTestHeard == nil, "our own run was counted as someone else's")
        -- another player's run: 3 of their 45 reach us
        for seq = 1, 3 do deliver("CHRATE~424242~1~" .. seq .. "~45", "Peer") end
        assert(c.rateTestHeard.n == 3 and c.rateTestHeard.total == 45)
        assert(table.concat(c:WorldProbeLines(), "\n"):find("last rate test heard: 3 of 45", 1, true))
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    assert(ok, err)
end)

test("/tfl channeltest join asks for one of our channels and records how the client says it is locked", function()
    local names = { "CreateFrame", "GetChannelName", "C_Timer", "JoinTemporaryChannel", "LeaveChannelByName", "StaticPopup_Visible", "GetChannelList" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local ok, err = pcall(function()
        local timers, frames, asked, left = {}, {}, {}, {}
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
        local function settle() for _ = 1, 50 do if #timers == 0 then return end local fn = table.remove(timers, 1); fn() end end
        CreateFrame = function()
            local f = { events = {} }
            function f:RegisterEvent(e) if e == "NO_SUCH_EVENT" then error("unknown event") end self.events[e] = true end
            function f:SetScript(_, fn) self.handler = fn end
            frames[#frames + 1] = f
            return f
        end
        local function fire(event, ...) for _, f in ipairs(frames) do if f.events[event] and f.handler then f.handler(f, event, ...) end end end
        local inside = {}
        GetChannelName = function(name) return inside[name] or 0 end
        GetChannelList = function() return end
        local popup = false
        StaticPopup_Visible = function(which) return which == "CHAT_CHANNEL_PASSWORD" and popup and "StaticPopup1" or nil end
        JoinTemporaryChannel = function(name)
            asked[#asked + 1] = name
            if name == "TFLLockTest" then popup = true; fire("CHANNEL_PASSWORD_REQUEST", name); fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "TFLLockTest", "", "", 0, 0, "TFLLockTest")
            else inside[name] = 7; fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "7. " .. name, "", "", 0, 7, name) end
        end
        LeaveChannelByName = function(name) left[#left + 1] = name; inside[name] = nil end
        local c, said, commands = { listeners = {}, ADDON = "TheFishingLogTest", PREFIX = "FishingLogTest", CHANNEL = "TheFishingLogTest" }, {}, {}
        function c:On() end
        function c:Print(msg) said[#said + 1] = msg end
        function c:IsSecret() return false end
        function c:Command(name, _, _, fn) commands[name] = fn end
        assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
        local function try(rest) said = {}; commands.channeltest(c, { "join" }, rest); settle(); return table.concat(said, " | ") end
        -- only our own channel names can be asked for
        for _, bad in ipairs({ "join", "join Trade", "join General", "join TFL Lock", "join TFL-x" }) do
            local n = #asked; assert(try(bad):find("starting with TFL", 1, true) or #asked > n and false, bad)
            assert(#asked == n, "asked to join for: " .. bad)
        end
        local text = try("join TFLLockTest")
        assert(#asked == 1 and text:find("did not get in. Password box on screen: yes", 1, true), text)
        popup = false
        text = try("join TFLOpenTest")
        assert(text:find("got in, as channel 7", 1, true) and text:find("Password box on screen: no", 1, true), text)
        assert(left[1] == "TFLOpenTest", "should leave a channel it got into")
        -- someone else's channel being locked is none of our business
        fire("CHANNEL_PASSWORD_REQUEST", "SomeGuildChannel")
        fire("CHAT_MSG_CHANNEL_NOTICE", "BANNED", "", "", "4. TheFishingLogTest", "", "", 0, 4, "TheFishingLogTest")
        local line
        for _, l in ipairs(c:WorldProbeLines()) do if l:find("lock signals", 1, true) then line = l end end
        assert(line == "World lock signals: password-request event exists | seen: PASSWORD_REQUEST event TFLLockTest; WRONG_PASSWORD notice TFLLockTest; BANNED notice TheFishingLogTest", tostring(line))
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    assert(ok, err)
end)

test("a locked channel: the password box is closed, the next name is used, and it moves back when the lock goes", function()
    local names = { "GetChannelName", "JoinTemporaryChannel", "LeaveChannelByName", "StaticPopup_Visible", "StaticPopup_Hide", "StaticPopup1" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local ok, err = pcall(function()
        local c = Client()
        c.db.settings.channel = true
        local said = {}
        function c:Print(msg) said[#said + 1] = msg end
        local lockedNames, inside, asked, left, nextID = { TheFishingLogTest = true, TheFishingLogTest2 = true }, {}, {}, {}, 5
        -- the game's password box, as the numbered popup frame older clients use
        local dialog = { which = "CHAT_CHANNEL_PASSWORD", shown = false }
        function dialog:IsShown() return self.shown end
        function dialog:Hide() self.shown = false end
        local function show(name) dialog.shown, dialog.data = true, name end
        StaticPopup1 = dialog
        StaticPopup_Visible, StaticPopup_Hide = nil, nil
        GetChannelName = function(name) return inside[name] or 0, name end
        JoinTemporaryChannel = function(name)
            asked[#asked + 1] = name
            if lockedNames[name] then
                -- the server's answer arrives after the call returns, as it does in the game
                C_Timer.After(0, function()
                    show(name)
                    c:Fire("CHANNEL_PASSWORD_REQUEST", name)
                    c:Fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", name, "", "", 0, 0, name)
                end)
            else nextID = nextID + 1; inside[name] = nextID end
        end
        LeaveChannelByName = function(name) left[#left + 1] = name; inside[name] = nil end
        local function settle(seconds)
            for _ = 1, seconds do F.advance(1); F.flush(); for _, fn in ipairs(c.ticks) do fn(c) end end
        end
        assert(c:IsOurChannelName("TheFishingLogTest") and c:IsOurChannelName("6. TheFishingLogTest2") and c:IsOurChannelName("thefishinglogtest20"))
        for _, other in ipairs({ "TheFishingLog", "TheFishingLogTest1", "TheFishingLogTest21", "TheFishingLogTestX", "Trade", "TheFishingLogTest2b" }) do
            assert(not c:IsOurChannelName(other), other .. " is not one of ours")
        end

        c.discoveryJoin = { attempts = 0, last = -math.huge, nextAt = 0, readyAt = 0 }
        c:JoinChannel(true)
        settle(10)
        assert(table.concat(asked, ",") == "TheFishingLogTest,TheFishingLogTest2,TheFishingLogTest3", table.concat(asked, ","))
        assert(c.CHANNEL == "TheFishingLogTest3" and inside.TheFishingLogTest3, "should have settled in the first open name")
        assert(c.db.finderChannel == "TheFishingLogTest3" and c:FinderChannelForWire() == "3", "remembered, and told to others as 3")
        assert(not dialog.shown and c.passwordBoxesClosed == 2 and c.passwordBoxClosedBy == "numbered frame", "a password box was left on screen")
        assert(c.channelLocks == 2 and #said == 1 and said[1]:find("locked the channel", 1, true), "told once: " .. #said)
        assert(c:DiscoveryJoinStatus():find("TheFishingLogTest3", 1, true), c:DiscoveryJoinStatus())
        -- the chat lines about our other names stay hidden, and so does nothing else
        assert(c:IsDiscoveryChannelNotice("WRONG_PASSWORD", "TheFishingLogTest", "TheFishingLogTest") == true)
        assert(c:IsDiscoveryChannelNotice("WRONG_PASSWORD", "Trade", "Trade") == false)

        -- a password box for a channel of the player's own is left alone
        show("MyGuildChannel")
        c:ChannelLocked("TheFishingLogTest", "WRONG_PASSWORD"); F.flush()
        assert(dialog.shown, "closed a password box that was not ours")
        dialog.shown = false

        -- /tfl channeltest base: the same walk against a stand-in name, leaving the real channel alone
        local timer = C_Timer
        assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
        lockedNames.TFLLockTest = true
        said, asked = {}, {}
        c:ChannelBaseTest("Trade"); assert(#asked == 0 and said[1]:find("starting with TFL", 1, true))
        said = {}
        c:ChannelBaseTest("TFLLockTest")
        settle(15)
        assert(table.concat(asked, ",") == "TFLLockTest,TFLLockTest2" and c.CHANNEL == "TFLLockTest2" and not dialog.shown, table.concat(asked, ",") .. " / " .. c.CHANNEL)
        assert(left[1] == "TheFishingLogTest3", "leaves the real channel it was in")
        -- (the fixture runs every timer on the next tick, so the 12-second report comes early here; only its shape is checked)
        local report = table.concat(said, " | ")
        assert(report:find("for this session the finder channel is TFLLockTest", 1, true) and report:find("Channel fallback: ended up in TFLLockTest", 1, true)
            and report:find("Box on screen now: no", 1, true), report)
        -- back to the real names for the rest of this test
        LeaveChannelByName("TFLLockTest2"); left = {}
        assert(c.db.finderChannel == "TheFishingLogTest3", "a stand-in name must not be remembered as the real channel: " .. tostring(c.db.finderChannel))
        c.CHANNEL_BASE, c.CHANNEL, c.channelBaseOverridden = "TheFishingLogTest", "TheFishingLogTest3", nil
        inside.TheFishingLogTest3 = 9
        said = { "told once" }

        -- half an hour on, the first name opens again: ask, get in, leave the later one
        lockedNames.TheFishingLogTest = nil
        asked = {}
        settle(1900)
        assert(#asked == 1, "one earlier name per half hour, asked: " .. table.concat(asked, ","))
        settle(1900)
        assert(c.CHANNEL == "TheFishingLogTest" and inside.TheFishingLogTest, "should have moved back, is in " .. c.CHANNEL)
        settle(6)
        assert(c.db.finderChannel == nil, "back in the usual channel: nothing to remember")
        assert(left[1] == "TheFishingLogTest3" and not inside.TheFishingLogTest3, "should leave the name it no longer needs")
        assert(table.concat(asked, ",") == "TheFishingLogTest2,TheFishingLogTest", "the one not asked for longest goes first: " .. table.concat(asked, ","))
        assert(#said == 1, "moving back is not announced")
        assert(not dialog.shown)
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    assert(ok, err)
end)

test("when the whole list is locked it makes a spare; if even spares are refused it stops, and no box is left up", function()
    local names = { "GetChannelName", "JoinTemporaryChannel", "StaticPopup_Visible", "StaticPopup_Hide", "StaticPopup1" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local ok, err = pcall(function()
        local c = Client()
        c.db.settings.channel = true
        function c:Print() end
        -- a client with no numbered frames: only StaticPopup_Visible and StaticPopup_Hide
        local asked, box = 0, nil
        StaticPopup1 = nil
        StaticPopup_Visible = function() if box then return "SomePopup", { which = "CHAT_CHANNEL_PASSWORD", data = box } end end
        StaticPopup_Hide = function(which) if which == "CHAT_CHANNEL_PASSWORD" then box = nil end end
        GetChannelName = function(name) return 0, name end
        JoinTemporaryChannel = function(name)
            asked = asked + 1
            C_Timer.After(0, function() box = name; c:Fire("CHANNEL_PASSWORD_REQUEST", name) end)
        end
        c.discoveryJoin = { attempts = 0, last = -math.huge, nextAt = 0, readyAt = 0 }
        c:JoinChannel(true)
        for _ = 1, 120 do F.advance(1); F.flush(); for _, fn in ipairs(c.ticks) do fn(c) end end
        assert(asked == 22, "asked " .. asked .. " times in two minutes; expected the 20 names once each, then two spares")
        assert(c.CHANNEL:find("^TheFishingLogTestx%l%l%l%l%l%l$") and c:IsOurChannelName(c.CHANNEL) and box == nil, c.CHANNEL)
        assert(c.discoveryJoin.error == "every channel name is locked", tostring(c.discoveryJoin.error))
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    assert(ok, err)
end)

test("the password box is closed as it opens, on a client that only has the dialog walker", function()
    local names = { "GetChannelName", "StaticPopup_Visible", "StaticPopup_Hide", "StaticPopup1", "StaticPopup_Show", "StaticPopup_ForEachShownDialog", "hooksecurefunc" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local ok, err = pcall(function()
        local dialogs = {}
        local function open(name)
            local d = { which = "CHAT_CHANNEL_PASSWORD", data = name, shown = true }
            function d:IsShown() return self.shown end
            function d:Hide() self.shown = false end
            dialogs[#dialogs + 1] = d
            return d
        end
        StaticPopup1, StaticPopup_Visible, StaticPopup_Hide = nil, nil, nil
        StaticPopup_ForEachShownDialog = function(fn) for _, d in ipairs(dialogs) do if d.shown then fn(d) end end end
        local shownFor
        StaticPopup_Show = function(which, text) shownFor = open(text); shownFor.which = which; shownFor.data = nil; return shownFor end -- data is set by the caller, after
        hooksecurefunc = function(name, post) local real = _G[name]; _G[name] = function(...) local r = real(...); post(...); return r end end
        GetChannelName = function(name) return 0, name end
        local c = Client()
        function c:Print() end
        assert(c.passwordBoxHook == true, "the show hook was not installed")
        -- the game opens the box for one of our names: gone before the call returns
        local d = StaticPopup_Show("CHAT_CHANNEL_PASSWORD", "TheFishingLogTest2")
        assert(not d.shown and c.passwordBoxClosedBy == "dialog walker", "our box survived the hook")
        -- for a channel of the player's own, and for any other popup: untouched
        local mine = StaticPopup_Show("CHAT_CHANNEL_PASSWORD", "MyGuildChannel"); mine.data = "MyGuildChannel"
        local other = StaticPopup_Show("CONFIRM_SOMETHING", "TheFishingLogTest")
        assert(mine.shown and other.shown, "closed a box that was not ours")
        c:ChannelLocked("TheFishingLogTest", "PASSWORD_REQUEST")
        assert(mine.shown and other.shown and c.passwordBoxesClosed == 1)
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    assert(ok, err)
end)

-- A client for the channel tests: some names locked, joins answered a moment later as in the game.
local function ChannelWorld(c, locked)
    local w = { inside = {}, asked = {}, left = {}, locked = locked or {}, nextID = 5, said = {}, whispers = {} }
    c.db.settings.channel = true
    function c:Print(msg) w.said[#w.said + 1] = msg end
    GetChannelName = function(name) return w.inside[name] or 0, name end
    JoinTemporaryChannel = function(name)
        w.asked[#w.asked + 1] = name
        if w.locked[name] or w.locked.all then C_Timer.After(0, function() c:Fire("CHANNEL_PASSWORD_REQUEST", name) end)
        else w.nextID = w.nextID + 1; w.inside[name] = w.nextID end
    end
    LeaveChannelByName = function(name) w.left[#w.left + 1] = name; w.inside[name] = nil end
    local whisper = c.Whisper
    function c:Whisper(to, ...) w.whispers[#w.whispers + 1] = to .. ":" .. table.concat({ ... }, "~"); return whisper(self, to, ...) end
    function w.settle(seconds) for _ = 1, seconds do F.advance(1); F.flush(); for _, fn in ipairs(c.ticks) do fn(c) end end end
    function w.start() c.discoveryJoin = { attempts = 0, last = -math.huge, nextAt = 0, readyAt = 0 }; c:JoinChannel(true); w.settle(4) end
    return w
end
local CHANNEL_GLOBALS = { "GetChannelName", "JoinTemporaryChannel", "LeaveChannelByName", "StaticPopup1", "StaticPopup_Visible", "StaticPopup_Hide" }
local function WithChannelGlobals(fn)
    local saved = {}
    for _, n in ipairs(CHANNEL_GLOBALS) do saved[n] = _G[n] end
    StaticPopup1, StaticPopup_Visible, StaticPopup_Hide = nil, nil, nil
    local ok, err = pcall(fn)
    for _, n in ipairs(CHANNEL_GLOBALS) do _G[n] = saved[n] end
    assert(ok, err)
end

test("a peer's channel: a better one is joined and moved to, a worse or refused one is not", function()
    WithChannelGlobals(function()
        local c = Client()
        local w = ChannelWorld(c, { TheFishingLogTest = true, TheFishingLogTest2 = true })
        w.start(); w.settle(6)
        assert(c.CHANNEL == "TheFishingLogTest3" and c:FinderChannelForWire() == "3")
        w.asked = {}
        -- junk, our own channel, a later list name and a spare are all no reason to move
        for _, field in ipairs({ "", "0", "21", "abc", "x", "xABCDEF", "xabcde", "xabcdefg", "3", "7", "xaaaaaa" }) do c:NotePeerChannel("Peer", field) end
        c:NotePeerChannel("Local", "1") -- something we said ourselves
        assert(#w.asked == 0, "asked to join for a channel that is no better: " .. table.concat(w.asked, ","))
        -- an earlier list name we were refused a moment ago: not asked again yet
        c:NotePeerChannel("Peer", "2")
        assert(#w.asked == 0, "asked again for a name that just refused us")
        assert(c.peerChannels == 4, "the four well-formed ones (3, 7, a spare, 2) are counted, got " .. tostring(c.peerChannels))

        -- from a spare, with the list locked: a peer in a list name that has opened is worth joining
        local d = Client()
        local locked = {}
        for i = 1, 20 do locked[i == 1 and "TheFishingLogTest" or ("TheFishingLogTest" .. i)] = true end
        local w2 = ChannelWorld(d, locked)
        w2.start(); w2.settle(60)
        local spare = d.CHANNEL
        assert(spare:find("x%l%l%l%l%l%l$") and w2.inside[spare], spare)
        locked.TheFishingLogTest5 = nil
        w2.settle(1800) -- past the half hour in which a refused name is left alone
        assert(d.CHANNEL == spare, "the addon's own half-hourly look starts at the top of the list and has not reached 5")
        w2.asked = {}
        d:NotePeerChannel("Peer", "5")
        assert(w2.asked[1] == "TheFishingLogTest5" and d.CHANNEL == spare, "asks without giving up the channel it has")
        w2.settle(4)
        assert(d.CHANNEL == "TheFishingLogTest5" and w2.left[#w2.left] == spare and not w2.inside[spare], "should have moved, is in " .. d.CHANNEL)
        w2.settle(6)
        assert(d:FinderChannelForWire() == "5" and d.db.finderChannel == "TheFishingLogTest5")
    end)
end)

test("suggestions that turn out locked are tried at most three times a session, 30 seconds apart", function()
    WithChannelGlobals(function()
        local c = Client()
        local w = ChannelWorld(c, { TheFishingLogTest = true, TheFishingLogTest2 = true, TheFishingLogTest3 = true, TheFishingLogTest4 = true, TheFishingLogTest5 = true })
        w.start(); w.settle(12)
        assert(c.CHANNEL == "TheFishingLogTest6", c.CHANNEL)
        -- a liar names channels on the list... (all refused moments ago: never asked)
        w.asked = {}
        for n = 1, 5 do c:NotePeerChannel("Liar", tostring(n)); w.settle(31) end
        assert(#w.asked == 0, table.concat(w.asked, ","))
        -- ...we move to a spare, and the liar names locked spares that sort before ours
        w.locked.TheFishingLogTest6 = true
        for i = 7, 20 do w.locked["TheFishingLogTest" .. i] = true end
        w.inside.TheFishingLogTest6 = nil -- a ban puts you out
        c:ChannelLocked("TheFishingLogTest6", "BANNED"); w.settle(60)
        assert(c.CHANNEL:find("x%l%l%l%l%l%l$") and w.inside[c.CHANNEL], "should be in a spare of its own: " .. c.CHANNEL)
        w.locked.all = true
        w.asked = {}
        c:NotePeerChannel("Liar", "xaaaaaa"); c:NotePeerChannel("Liar", "xaaaaab")
        assert(#w.asked == 1, "two asks inside 30 seconds")
        for _, suffix in ipairs({ "xaaaaab", "xaaaaac", "xaaaaad", "xaaaaae", "xaaaaaf" }) do w.settle(31); c:NotePeerChannel("Liar", suffix) end
        assert(#w.asked == 3, "expected three tries in all, got " .. #w.asked .. ": " .. table.concat(w.asked, ","))
        assert(w.inside[c.CHANNEL], "and it kept the channel it had")
    end)
end)

test("the whole list locked: a spare is made, remembered for next login, and anglers met are asked where everyone is", function()
    WithChannelGlobals(function()
        local c = Client()
        local locked = {}
        for i = 1, 20 do locked[i == 1 and "TheFishingLogTest" or ("TheFishingLogTest" .. i)] = true end
        local w = ChannelWorld(c, locked)
        c.db.anglersSeen = { a = { name = "Old Friend", at = 10 }, b = { name = "New Friend", at = 30 }, c = { name = "Mid Friend", at = 20 }, d = { name = "Ancient", at = 1 } }
        c:Fire("TFL_LOGIN")
        w.start(); w.settle(60)
        assert(#w.asked == 21, "20 list names and one spare, asked " .. #w.asked)
        local spare = c.CHANNEL
        assert(spare:find("^TheFishingLogTestx%l%l%l%l%l%l$") and w.inside[spare], spare)
        assert(c.db.finderChannel == spare and c:FinderChannelForWire() == spare:match("x%l+$"))
        assert(#w.said == 1, "the lock is mentioned once: " .. #w.said)
        -- on a spare of its own making it asks the anglers it meets, once each, not faster than one in 10 seconds
        w.whispers = {}
        c:MetPeer("Stranger"); c:MetPeer("Stranger"); c:MetPeer("Second")
        assert(#w.whispers == 1 and w.whispers[1]:find("^Stranger:WHO~1%.1%.4~") and w.whispers[1]:find("~" .. spare:match("x%l+$") .. "~mh33$"), table.concat(w.whispers, " | "))
        -- two minutes in, the three anglers heard from most recently are asked too
        w.settle(60)
        local who = table.concat(w.whispers, " | ")
        assert(who:find("New Friend:WHO", 1, true) and who:find("Mid Friend:WHO", 1, true) and who:find("Old Friend:WHO", 1, true) and not who:find("Ancient", 1, true), who)
        -- nobody answers: suggest a city, once
        w.settle(120)
        assert(#w.said == 2 and w.said[2]:find("major city", 1, true), tostring(w.said[2]))
        w.settle(600); assert(#w.said == 2)
        -- an angler met in the city is in another spare that sorts first: join them
        c:NotePeerChannel("City Angler", "xaaaaaa")
        w.settle(4)
        assert(c.CHANNEL == "TheFishingLogTestxaaaaaa" and w.left[#w.left] == spare, c.CHANNEL)
        w.settle(6)
        assert(c.db.finderChannel == "TheFishingLogTestxaaaaaa")

        -- next login: the remembered name is tried first, with no walk through the locked list
        local d = Client()
        d.db.finderChannel = "TheFishingLogTestxaaaaaa"
        local w2 = ChannelWorld(d, locked)
        d:Fire("TFL_LOGIN")
        w2.start()
        assert(w2.asked[1] == "TheFishingLogTestxaaaaaa" and d.CHANNEL == w2.asked[1] and w2.inside[d.CHANNEL], table.concat(w2.asked, ","))
        w2.settle(120)
        assert(table.concat(w2.asked, ",") == "TheFishingLogTestxaaaaaa,TheFishingLogTest", "then one look at the top of the list, not a walk: " .. table.concat(w2.asked, ","))
        -- and a remembered name that is somebody else's, or junk, is ignored
        for _, bad in ipairs({ "Trade", "TheFishingLogTest21", "TheFishingLogTestxABC", 7 }) do
            local e = Client(); e.db.finderChannel = bad; e:Fire("TFL_LOGIN")
            assert(e.CHANNEL == "TheFishingLogTest", tostring(bad) .. " -> " .. e.CHANNEL)
        end
    end)
end)

test("locked behind us: when newcomers say our channel refused them, we go where they are", function()
    WithChannelGlobals(function()
        -- what a newcomer sends: the list names that refused it, as one number
        local n = Client()
        local wn = ChannelWorld(n, { TheFishingLogTest = true, TheFishingLogTest2 = true })
        assert(n:RefusedChannelsForWire() == "")
        wn.start(); wn.settle(6)
        assert(n.CHANNEL == "TheFishingLogTest3" and n:RefusedChannelsForWire() == "3", n:RefusedChannelsForWire())
        -- half an hour on: the second name's refusal has lapsed; the first was looked at again and still refuses
        wn.settle(1800); assert(n:RefusedChannelsForWire() == "1", "only refusals from the last half hour are passed on: " .. n:RefusedChannelsForWire())

        -- an old hand, in the usual channel since before somebody locked it
        local c = Client()
        local w = ChannelWorld(c, {})
        w.start(); w.settle(6)
        assert(c.CHANNEL == "TheFishingLogTest" and w.inside.TheFishingLogTest)
        w.locked.TheFishingLogTest = true
        w.asked = {}
        c.lastRoad = "WHISPER"
        -- claims about other names, and junk, are nothing to act on
        for _, field in ipairs({ "", "2", "a", "mh34x", "ZZ", "3.xabc", ".", "1.", "zzzzz" }) do c:NotePeerRefusals("Stranger", field, "3") end
        assert(#w.asked == 0 and c.CHANNEL == "TheFishingLogTest", "moved on a claim that does not name our channel: " .. table.concat(w.asked, ","))
        -- one stranger says ours refused them: not enough
        c:NotePeerRefusals("Stranger", "1", "2"); c:NotePeerRefusals("Stranger", "1", "2"); c:NotePeerRefusals("Local", "1", "2")
        assert(#w.asked == 0, "one stranger's word (or our own) is not enough")
        -- a second one does it: join where they are, then leave ours
        c:NotePeerRefusals("Another", "3", "2")
        assert(w.asked[1] == "TheFishingLogTest2" and c.CHANNEL == "TheFishingLogTest", "joins before leaving")
        w.settle(4)
        assert(c.CHANNEL == "TheFishingLogTest2" and w.left[1] == "TheFishingLogTest" and c.movedOnOthersWord == 1, c.CHANNEL)
        assert(c:RefusedChannelsForWire() == "", "it was told, not refused: it passes nothing on")
        -- the people still inside the old one advertise it, and it is the earlier name: not for half an hour
        w.asked = {}
        c:NotePeerChannel("Insider", "1"); w.settle(60)
        assert(#w.asked == 0 and c.CHANNEL == "TheFishingLogTest2", "went straight back: " .. table.concat(w.asked, ","))
        -- and nobody can chase it onwards inside that half hour either
        c:NotePeerRefusals("Stranger", "2", "5"); c:NotePeerRefusals("Another", "2", "5"); w.settle(4)
        assert(#w.asked == 0 and c.CHANNEL == "TheFishingLogTest2", "moved twice in half an hour")
        -- half an hour on it looks at the old one itself, is refused, and from then on says so
        w.settle(1800)
        assert(w.asked[1] == "TheFishingLogTest" and c.CHANNEL == "TheFishingLogTest2" and c:RefusedChannelsForWire() == "1", table.concat(w.asked, ",") .. " / " .. c:RefusedChannelsForWire())

        -- one guildmate's or party member's word is enough
        local g = Client()
        local wg = ChannelWorld(g, {})
        wg.start(); wg.settle(6)
        g.lastRoad = "GUILD"
        g:NotePeerRefusals("Guildmate", "1", "4"); wg.settle(4)
        assert(g.CHANNEL == "TheFishingLogTest4", g.CHANNEL)
        -- if they say where they were refused but not where they are, the next list name is used
        local p = Client()
        local wp = ChannelWorld(p, {})
        wp.start(); wp.settle(6)
        p.lastRoad = "PARTY"
        p:NotePeerRefusals("Friend", "1", ""); wp.settle(4)
        assert(p.CHANNEL == "TheFishingLogTest2", p.CHANNEL)
        -- a lie costs half an hour: the old channel is open, so the next look moves it back
        wp.settle(1830)
        assert(p.CHANNEL == "TheFishingLogTest", "should be back in the usual channel, is in " .. p.CHANNEL)

        -- on a spare: named by its letters
        local sp = Client()
        local locked = {}
        for i = 1, 20 do locked[i == 1 and "TheFishingLogTest" or ("TheFishingLogTest" .. i)] = true end
        local ws = ChannelWorld(sp, locked)
        ws.start(); ws.settle(60)
        local spare = sp.CHANNEL
        local letters = spare:match("x%l%l%l%l%l%l$")
        assert(letters and sp:RefusedChannelsForWire() == "mh33", sp:RefusedChannelsForWire())
        sp.lastRoad = "GUILD"
        sp:NotePeerRefusals("Guildmate", "mh33.xzzzzzz", "xbbbbbb"); ws.settle(4)
        assert(sp.CHANNEL == spare, "another spare's refusal is not ours")
        sp:NotePeerRefusals("Guildmate", "mh33." .. letters, "xzzzzzy"); ws.settle(4)
        assert(sp.CHANNEL == "TheFishingLogTestxzzzzzy" and not ws.inside[spare], sp.CHANNEL)
    end)
end)

test("a copy that is in the usual channel asks nobody and suggests nothing", function()
    WithChannelGlobals(function()
        local c = Client()
        local w = ChannelWorld(c, {})
        c.db.anglersSeen = { a = { name = "Friend", at = 10 } }
        c:Fire("TFL_LOGIN")
        w.start(); w.settle(8)
        assert(c.CHANNEL == "TheFishingLogTest" and c:FinderChannelForWire() == "1")
        w.whispers = {}
        c:MetPeer("Stranger"); w.settle(400)
        assert(#w.whispers == 0 and #w.said == 0 and #w.asked == 1, #w.whispers .. " whispers, " .. #w.said .. " lines")
        -- with the channel setting off, nothing is said about channels at all
        c.db.settings.channel = false
        assert(c:FinderChannelForWire() == "")
    end)
end)

test("world probe reports what the client says and survives a client that says nothing", function()
    local c = { listeners = {}, ADDON = "TheFishingLogTest", cdb = { realm = "Kept" } }
    function c:On(event, fn) self.listeners[event] = self.listeners[event] or {}; table.insert(self.listeners[event], fn) end
    function c:Print() end
    function c:IsSecret() return false end
    assert(loadfile(source .. "TestBuild.lua"))("TheFishingLogTest", c)
    local function text() return table.concat(c:WorldProbeLines(), "\n") end

    -- nothing defined: every line is still produced, none is a Lua error
    local bare = text()
    assert(bare:find("World region: absent | name absent", 1, true), bare)
    assert(bare:find('kept "Kept"', 1, true), bare)
    assert(not bare:find("attempt to", 1, true), bare)

    GetCurrentRegion = function() return 1 end
    GetCurrentRegionName = function() return "US" end
    GetNormalizedRealmName = function() return "" end
    UnitFullName = function() return "First Last", "Realm7" end
    UnitGUID = function() return "Player-91-0ABCDEF0" end
    Enum = { GameRule = { HardcoreRuleset = 1, PvpRuleset = 2 } }
    C_GameRules = { IsGameRuleActive = function(id) return id == 2 end, GetGameRuleAsFloat = function(id) return id * 10 end,
        GetForeverExperiencePreset = function() return 3 end, GetNumDisplayedGameModes = function() return 1 end,
        GetDisplayedGameModeRecordIDAtIndex = function(i) return 40 + i end,
        GetGameModeDisplayInfoByRecordID = function(id) return { name = "Mode" .. id } end }
    GetChannelName = function(name) return name == 1 and 1 or 7 end
    C_ChatInfo = { IsChannelRegionalForChannelID = function(id) return id == 1 end }
    C_FakeThing = { GetRealmFlavor = function() end, Unrelated = function() end }
    local full = text()
    GetCurrentRegion, GetCurrentRegionName, GetNormalizedRealmName, UnitFullName, UnitGUID, Enum, C_GameRules, C_FakeThing =
        nil, nil, nil, nil, nil, nil, nil, nil
    GetChannelName, C_ChatInfo = nil, nil
    assert(full:find('World region: 1 | name "US"', 1, true), full)
    assert(full:find('normalized ""', 1, true), full)
    assert(full:find('World guid realm: "91"', 1, true), full)
    assert(full:find("World active game rules: 1 of 2: PvpRuleset", 1, true), full)
    assert(full:find("World C_FakeThing: GetRealmFlavor", 1, true), full)
    assert(full:find("World C_GameRules.GetForeverExperiencePreset: 3", 1, true), full)
    assert(full:find("World game mode 1: record 41 | info {name=Mode41}", 1, true), full)
    assert(full:find("World active rule values: PvpRuleset=20", 1, true), full)
    assert(full:find("World all game rules: HardcoreRuleset PvpRuleset", 1, true), full)
    assert(full:find("World channel finder: id 7 | ruleset absent | regional false", 1, true), full)
    assert(full:find("World channel 1: id 1 | ruleset absent | regional true", 1, true), full)
    assert(not full:find("First", 1, true) and not full:find("Last", 1, true) and not full:find("Realm7", 1, true)
        and not full:find("0ABCDEF0", 1, true), "probe must not print any part of the character name or the full GUID")
end)

if failures > 0 then error(failures .. " isolation check(s) failed") end
print("All isolation checks passed")
