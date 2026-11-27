-- Logbook: a water is listed for a log only if a fish was landed there.
-- The real Session.lua against a mock client. Run from the repository root.
local F = assert(loadfile("tests/fishing-sync-fixture.lua"))()
local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print("PASS: " .. name) else failures = failures + 1; print("FAIL: " .. name .. ": " .. tostring(err)) end
end
local c = F.Client("Local", false)
assert(loadfile("Session.lua"))("TheFishingLogTest", c)

local function water(name, count, seconds) return { name = name, count = count, total = count * 2, seconds = seconds or 0, junk = 0, finds = 0 } end
local function names(list) local out = {} for i, e in ipairs(list) do out[i] = e.name end return table.concat(out, ",") end

test("waters with no fish are left out, order kept", function()
    local saved = { water("Trade Quarter", 12, 600), water("Undercity", 0, 40), water("Tarren Mill", 0, 5), water("Canals", 3, 90), water("Sewers", 0) }
    assert(names(c:FishedWaters(saved)) == "Trade Quarter,Canals", names(c:FishedWaters(saved)))
    assert(#saved == 5, "the saved list itself must not be changed")
    assert(#c:FishedWaters(nil) == 0 and #c:FishedWaters({}) == 0)
    assert(#c:FishedWaters({ { name = "old entry with no count" } }) == 0)
end)

test("junk or a find alone does not make a water fished", function()
    local junkOnly = water("Canals", 0); junkOnly.junk = 4; junkOnly.finds = 1
    assert(#c:FishedWaters({ junkOnly }) == 0)
end)

test("a log's waters, as saved and as named on the board, are the fished ones, busiest first", function()
    local s = { sub = "Trade Quarter", spotOrder = { water("Undercity", 0, 400), water("Canals", 3, 90), water("Trade Quarter", 12, 600), water("Dalaran", 0, 2) } }
    assert(names(c:SessionSpots(s)) == "Trade Quarter,Canals", names(c:SessionSpots(s)))
    assert(c:SessionWaters(s) == "Trade Quarter and 1 other water", c:SessionWaters(s))
    s.spotOrder = { water("Undercity", 0, 400), water("Trade Quarter", 12, 600) }
    assert(c:SessionWaters(s) == "Trade Quarter", c:SessionWaters(s))
    s.spotOrder = { water("Undercity", 0, 400) } -- nothing landed yet: fall back to where the log began
    assert(#c:SessionSpots(s) == 0 and c:SessionWaters(s) == "Trade Quarter", c:SessionWaters(s))
end)

if failures > 0 then error(failures .. " logbook check(s) failed") end
print("All logbook checks passed")
