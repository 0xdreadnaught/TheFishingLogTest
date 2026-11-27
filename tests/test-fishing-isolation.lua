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
    c:Fire("CHAT_MSG_ADDON", UPSTREAM_PREFIX, "LIVE1~1~TESTPING~1", "WHISPER", "Peer")
    assert(heard == 0, "handled a message from the upstream network")
    c:Fire("CHAT_MSG_ADDON", c.PREFIX, "LIVE1~1~TESTPING~1", "WHISPER", "Peer")
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
    assert(#said == 1, "expected one notice, got " .. #said)
    assert(said[1]:find("TEST BUILD 5", 1, true) and said[1]:find("not the main addon", 1, true), said[1])
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
