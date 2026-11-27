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
        assert(here and here:find("~1%.1%.2~12$"), "HERE should end with the counting floor then the build: " .. tostring(here))
        -- from a build that doesn't send one (10 to 15)
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~WHO~1.1.4", "WHISPER", "Older")
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~HERE~1.1.4~3~1458~H~100~~50~1.1.2", "WHISPER", "Older")
        c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE2~1~?~HERE~1.1.4~3~1458~H~100~~50~1.1.2~15", "WHISPER", "Newer")
        assert(heard[2] == "Older=nil" and heard[3] == "Older=nil" and heard[4] == "Newer=15", table.concat(heard, " "))
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
