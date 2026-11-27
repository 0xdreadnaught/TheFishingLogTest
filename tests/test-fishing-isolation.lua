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

if failures > 0 then error(failures .. " isolation check(s) failed") end
print("All isolation checks passed")
