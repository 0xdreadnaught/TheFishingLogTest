-- World.lua: knowing the region and rule set, and keeping each world's shared data apart.
-- Real addon files against a mock client; no game needed. Run from the repository root.
local F = assert(loadfile("tests/fishing-sync-fixture.lua"))()
local source = ""
local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print("PASS: " .. name) else failures = failures + 1; print("FAIL: " .. name .. ": " .. tostring(err)) end
end

-- A client that reports the given region and rule set. Passing nothing makes it say nothing.
local function Client(region, code, rules)
    GetCurrentRegion = region and function() return region end or nil
    GetCurrentRegionName = code and function() return code end or nil
    if rules then
        Enum = { GameRule = { PvPRuleset = 11, RPRuleset = 12, HardcoreRuleset = 13, Unrelated = 14 } }
        local on = {}
        for _, name in ipairs(rules) do on[Enum.GameRule[name]] = true end
        C_GameRules = { IsGameRuleActive = function(id) return on[id] == true end,
            IsHardcoreActive = function() return on[13] == true end,
            GetCurrentGameModeRecordID = function() return 14 end }
    else
        Enum, C_GameRules = nil, nil
    end
end
local function Addon()
    local c = { listeners = {}, said = {} }
    function c:On(event, fn) self.listeners[event] = self.listeners[event] or {}; table.insert(self.listeners[event], fn) end
    function c:Print(msg) self.said[#self.said + 1] = msg end
    function c:IsSecret() return false end
    assert(loadfile(source .. "World.lua"))("TheFishingLogTest", c)
    return c
end
local function Enter(region, code, rules)
    Client(region, code, rules)
    local c = Addon()
    c:EnterWorld()
    return c
end

test("the key names region and rule set for every combination", function()
    local cases = {
        { 1, "US", {}, "US-Normal", "Americas & Oceania, Normal", "0" },
        { 1, "US", { "PvPRuleset" }, "US-PvP", "Americas & Oceania, PvP", "1" },
        { 3, "EU", { "RPRuleset" }, "EU-RP", "Europe, Roleplay", "i" },
        { 2, "KR", { "RPRuleset", "PvPRuleset" }, "KR-RP-PvP", "Korea, Roleplay PvP", "b" },
        { 4, "TW", { "HardcoreRuleset" }, "TW-HC", "Taiwan, Hardcore", "s" },
        { 4, "TW", { "HardcoreRuleset", "RPRuleset", "PvPRuleset" }, "TW-HC-RP-PvP", "Taiwan, Hardcore Roleplay PvP", "v" },
        { 1, "US", { "HardcoreRuleset", "PvPRuleset" }, "US-HC-PvP", "Americas & Oceania, Hardcore PvP", "5" },
        { 3, nil, { "PvPRuleset" }, "EU-PvP", "Europe, PvP", "h" },
        { 3, "Europe!", { "PvPRuleset" }, "EU-PvP", "Europe, PvP", "h" }, -- the key comes from the region number, not its name
        { 7, nil, {}, "R7-Normal", "R7, Normal", "1c" }, -- a region this build has no name for
    }
    local codes = {}
    for _, case in ipairs(cases) do
        TheFishingLogDB, TheFishingLogChar = nil, nil
        local c = Enter(case[1], case[2], case[3])
        assert(c.worldKey == case[4], ("expected %s, got %s"):format(case[4], tostring(c.worldKey)))
        assert(c:WorldLabel() == case[5], ("expected %s, got %s"):format(case[5], c:WorldLabel()))
        assert(TheFishingLogChar.world == case[4], "the character should remember its world")
        assert(c.worldCode == case[6], ("%s should be sent as %s, got %s"):format(case[4], case[6], tostring(c.worldCode)))
        assert(c.worldCode:find("^[0-9a-z]+$"), "the code goes on the wire: base 36 only")
        assert(codes[c.worldCode] == nil or codes[c.worldCode] == case[4], "two worlds share the code " .. c.worldCode)
        codes[c.worldCode] = case[4]
    end
    -- every region x rule set Forever has gets its own single character
    local c, seen, count = Addon(), {}, 0
    for _, region in ipairs({ "US", "KR", "EU", "TW" }) do
        for _, rule in ipairs({ "Normal", "PvP", "RP", "RP-PvP", "HC", "HC-PvP", "HC-RP", "HC-RP-PvP" }) do
            local code = c:WorldCode(region .. "-" .. rule)
            assert(#code == 1 and code ~= "?" and not seen[code], region .. "-" .. rule .. " -> " .. code)
            seen[code] = true; count = count + 1
        end
    end
    assert(count == 32)
    for _, bad in ipairs({ "?", "", "US", "US-", "US-Arena", "US-PvP-Arena", "xx-PvP" }) do
        assert(c:WorldCode(bad) == "?", bad .. " -> " .. c:WorldCode(bad))
    end
end)

test("first run takes the existing data as this world's and moves nothing", function()
    TheFishingLogChar = {}
    local spots = { a1 = { key = "a1" } }
    TheFishingLogDB = { spots = spots, settings = { sounds = false } }
    local c = Enter(1, "US", { "PvPRuleset" })
    assert(TheFishingLogDB.world == "US-PvP" and TheFishingLogDB.spots == spots and TheFishingLogDB.worlds == nil)
    assert(c.worldSwapped == false)
end)

test("another world's character gets its own shared data; settings stay; going back restores", function()
    TheFishingLogChar = {}
    local pvpSpots, pvpBoard, settings = { a1 = { key = "a1" } }, { day = {} }, { sounds = false }
    TheFishingLogDB = { world = "US-PvP", spots = pvpSpots, spotFormat = 3, bountyBoard = pvpBoard, anglersSeen = { bob = {} },
        settings = settings, lastVersion = "1.1.4", fishNames = { [6291] = "Brilliant Smallfish" } }

    local c = Enter(1, "US", {}) -- a Normal character logs in
    local db = TheFishingLogDB
    assert(c.worldSwapped == true and db.world == "US-Normal")
    for _, k in ipairs(c.WORLD_KEYS) do assert(db[k] == nil, k .. " from the other world is still on show") end
    assert(db.settings == settings and db.lastVersion == "1.1.4" and db.fishNames[6291], "account data must stay")
    assert(db.worlds["US-PvP"].spots == pvpSpots and db.worlds["US-PvP"].bountyBoard == pvpBoard and db.worlds["US-PvP"].spotFormat == 3)

    db.spots = { n9 = { key = "n9" } } -- what the Normal world learns
    TheFishingLogChar = {}
    Enter(1, "US", { "PvPRuleset" }) -- back to the PvP character
    assert(db.world == "US-PvP" and db.spots == pvpSpots and db.bountyBoard == pvpBoard and db.spotFormat == 3)
    assert(db.worlds["US-PvP"] == nil and db.worlds["US-Normal"].spots.n9, "the Normal world's data should now be the parked one")
    assert(db.settings == settings)
end)

test("the same rule set in another region is a different world", function()
    TheFishingLogChar = {}
    TheFishingLogDB = { world = "US-PvP", spots = { a1 = {} } }
    Enter(3, "EU", { "PvPRuleset" })
    assert(TheFishingLogDB.world == "EU-PvP" and TheFishingLogDB.spots == nil and TheFishingLogDB.worlds["US-PvP"].spots.a1)
end)

test("a client that can't say yet uses what the character was last time", function()
    TheFishingLogChar = { world = "US-Normal" }
    TheFishingLogDB = { world = "US-PvP", spots = { a1 = {} } }
    local c = Enter(nil, nil, nil)
    assert(c.worldKey == "US-Normal" and TheFishingLogDB.world == "US-Normal" and TheFishingLogDB.spots == nil)
    assert(c.worldCode == "0", "the code must come from the remembered key too")
end)

test("with nothing to go on it changes nothing, then sorts itself out once in the world", function()
    TheFishingLogChar = { world = "not a key ~" }
    local spots = { a1 = {} }
    TheFishingLogDB = { spots = spots }
    local c = Enter(nil, nil, nil)
    assert(c.worldKey == "?" and c.worldCode == "?" and TheFishingLogDB.world == nil and TheFishingLogDB.spots == spots)
    assert(c:WorldLabel() == "an unknown world")

    -- unsorted data: adopt it without a reload
    c.db, c.cdb = TheFishingLogDB, TheFishingLogChar
    Client(1, "US", { "PvPRuleset" })
    c.listeners.PLAYER_ENTERING_WORLD[1](c)
    assert(c.worldKey == "US-PvP" and c.worldCode == "1" and c.db.world == "US-PvP" and c.cdb.world == "US-PvP" and #c.said == 0)

    -- data loaded is another world's: ask for one reload, once, and leave the data alone
    TheFishingLogChar, TheFishingLogDB = {}, { world = "US-Normal", spots = spots }
    Client(nil, nil, nil)
    local d = Addon(); d:EnterWorld()
    d.db, d.cdb = TheFishingLogDB, TheFishingLogChar
    Client(1, "US", { "PvPRuleset" })
    d.listeners.PLAYER_ENTERING_WORLD[1](d)
    d.listeners.PLAYER_ENTERING_WORLD[1](d)
    assert(#d.said == 1 and d.said[1]:find("/reload", 1, true) and d.said[1]:find("Americas & Oceania, PvP", 1, true), tostring(d.said[1]))
    assert(d.db.world == "US-Normal" and d.db.spots == spots and d.cdb.world == "US-PvP")
    -- and the reload then swaps, from the remembered world, even if the client is silent again
    Client(nil, nil, nil)
    local e = Addon(); e:EnterWorld()
    assert(e.worldKey == "US-PvP" and TheFishingLogDB.world == "US-PvP" and TheFishingLogDB.spots == nil)
end)

test("messages carry the world, and another world's messages are dropped and counted", function()
    F.setTime(100); F.clear()
    Enum = { SendAddonMessageResult = { AddonMessageThrottle = 3 } } -- the earlier tests replaced the fixture's
    GetChannelName = function() return 0 end
    local wire = {}
    InCombatLockdown = function() return false end
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, msg, road, to) wire[#wire + 1] = msg return 0 end }
    local c = F.Client("Local", false)
    assert(loadfile(source .. "Comm.lua"))("TheFishingLogTest", c)
    c.listeners.TFL_INIT[1](c)
    local pump = F.pump()
    c.worldCode = "1" -- US-PvP
    local heard = 0
    c.handlers.TESTPING = function() heard = heard + 1 end
    local function hear(text) c:Fire("CHAT_MSG_ADDON", c.PREFIX, text, "WHISPER", "Peer") end

    hear("LIVE2~1~0~TESTPING~1") -- US-Normal
    hear("LIVE2~1~h~TESTPING~1") -- EU-PvP
    hear("LIVE2~1~?~TESTPING~1")
    hear("LIVE2~1~US-PvP~TESTPING~1") -- builds 8 and 9 sent the name
    hear("LIVE1~1~TESTPING~1") -- a build before 8
    assert(heard == 0, "handled a message from another world")
    assert(c.otherWorldsHeard == 4, "expected 4 counted, got " .. tostring(c.otherWorldsHeard))
    hear("LIVE2~1~1~TESTPING~1")
    assert(heard == 1, "did not handle a message from its own world")
    -- a chunked message from another world is put together and then dropped
    local body = "LIVE2~1~0~TESTPING~" .. ("x"):rep(300)
    hear("P~7~1~2~" .. body:sub(1, 220)); hear("P~7~2~2~" .. body:sub(221))
    assert(heard == 1 and c.otherWorldsHeard == 5)

    c:Whisper("Peer", "TESTPING", "1")
    for _ = 1, 5 do F.advance(1); pump() end
    assert(#wire == 1 and wire[1] == "LIVE2~1~1~TESTPING~1", tostring(wire[1]))
    assert(c:CommunicationStatus():find("5 dropped from other worlds", 1, true), c:CommunicationStatus())
end)

if failures > 0 then error(failures .. " world check(s) failed") end
print("All world checks passed")
