-- Session: the solo fishing log. Starts on your first cast, runs a timer
-- up from 0:00, and ends when you press Stop (or /tfl stop).
local _, MF = ...
local function print(...) MF:PrintChat(...) end

MF.session = nil

-- Sync may settle after Stop; the saved summary retains the same tally.
function MF:CreditSessionRecord(c)
    local stats=c.sessionRecordStats
    if not stats or c.test then return end
    if c.recordAllTime and not c.sessionAllCounted then
        stats.all=(stats.all or 0)+1 c.sessionAllCounted=true
    end
    if c.recordSeason and not c.sessionSeasonCounted then
        stats.season=(stats.season or 0)+1 c.sessionSeasonCounted=true
    end
end

------------------------------------------------------------------------
-- Where a log actually happened
--
-- A session used to record the water you started at and nothing else, so a
-- log that followed you to the next lake went on claiming the first one.
-- The board said the wrong place, and worse, History's "By spot" - the view
-- whose whole job is answering where is worth fishing - credited every fish
-- to wherever you happened to cast first.
--
-- So the log keeps a tally per water, and time goes to the one you were
-- standing at rather than the one you began at. Three hours across three
-- lakes is an hour each, not three hours at the first.
------------------------------------------------------------------------

local function SpotStats(s, name)
    local e = s.spots[name]
    if not e then
        e = { name = name, count = 0, junk = 0, finds = 0, total = 0, biggest = 0,
              specimens = 0, value = 0, seconds = 0 }
        s.spots[name] = e
        s.spotOrder[#s.spotOrder + 1] = e
    end
    return e
end

-- Time fished, rather than time elapsed
--
-- A log used to run on the wall clock, so somebody who cast once and
-- went to make dinner came back to a two hour session with four fish in
-- it. The rate on the board is fish an hour, which made it nonsense,
-- and History's "By spot" inherited the same lie - an afternoon stood
-- idle at one lake made it look like the best water on the realm.
--
-- What counts is time with the rod in the water. The addon already
-- knows when that happens: TFL_FISHING_CAST fires on the channel and a
-- fish on the hook says the same thing. So the clock is the sum of the
-- gaps between those moments, and a gap longer than the grace below is
-- worth only the grace.
--
-- Grace rather than the channel exactly, because reeling in, looting
-- and casting again is real fishing: a channel-only clock would
-- undercount an honest hour as badly as the wall clock overcounts an
-- idle one.
--
-- Counted at those moments rather than on a timer, which means it does
-- not care whether a tick was missed, whether the client was asleep, or
-- that GetTime starts again from zero after a UI reload.
local IDLE_AFTER = 120

-- What the stretch since the last sign of life was worth.
local function Worth(s, now)
    local since = now - (s.lastActive or now)
    if since < 0 then return 0 end          -- the clock went backwards
    return math.min(since, IDLE_AFTER)
end

-- Bank it, and to whichever water we were stood at while it passed.
local function Credit(s, now)
    now = now or GetTime()
    local since = Worth(s, now)
    s.lastActive = now
    if since <= 0 then return end
    s.fished = (s.fished or 0) + since
    if s.at then
        local e = SpotStats(s, s.at)
        e.seconds = e.seconds + since
    end
end

local function MoveTo(s, name, now)
    if not name or name == s.at then return end
    -- Settle what the old water is owed before the new one starts.
    Credit(s, now)
    s.at = name
end

-- The waters of a log, busiest first.
function MF:SessionSpots(s)
    local list = {}
    for _, e in ipairs(s.spotOrder or {}) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.seconds > b.seconds
    end)
    return list
end

-- Where the log is now, for the board. Falls back to where it began, which
-- is all an older saved session knows.
function MF:SessionWhere(s)
    return (s and (s.at or s.sub)) or "?"
end

function MF:StartSession()
    if self:InMatch() then
        return -- the match board takes over
    end
    self.current = nil -- a finished match gives the board back to the log
    local zone, sub = self:Location()
    self.session = {
        startedAt = GetTime(), zone = zone, sub = sub,
        -- A log begins because you cast, so the clock starts running.
        fished = 0, lastActive = GetTime(),
        catches = {}, count = 0, junk = 0, finds = 0, findItems = {}, total = 0, biggest = 0, specimens = 0, value = 0,
        recordStats = {all=0,season=0},
        spots = {}, spotOrder = {},
    }
    MoveTo(self.session, sub, GetTime())
    self:Print(("Started a fishing log at %s. Press Stop on the board or /tfl stop to end it."):format(sub))
    if self.db.settings.autoBoard then
        self:ShowBoard(true)
    end
end

function MF:SessionElapsed(s)
    s = s or self.session
    if not s then return 0 end
    -- Logs saved before this ran on the wall clock and have no other
    -- answer to give.
    if s.fished == nil then
        return math.floor((s.stoppedAt or GetTime()) - s.startedAt)
    end
    -- A running log is owed whatever the current stretch is worth, or
    -- the board would sit still between casts and jump on each fish.
    local pending = s.stoppedAt and 0 or Worth(s, GetTime())
    return math.floor(s.fished + pending)
end

-- Is the clock running, or has the rod been out of the water too long?
function MF:SessionIdle(s)
    s = s or self.session
    if not s or s.stoppedAt or not s.lastActive then return false end
    return GetTime() - s.lastActive > IDLE_AFTER
end

function MF:IsSessionRunning()
    return self.session ~= nil and not self.session.stoppedAt
end

function MF:LogCatch(c)
    if self:InMatch() then return end
    if not self:IsSessionRunning() then
        self:StartSession()
    end
    local s = self.session
    -- A fish on the hook says the rod was in the water, whether or not
    -- we saw the cast that put it there.
    Credit(s)
    c.sessionRecordStats = s.recordStats
    self:CreditSessionRecord(c)
    MoveTo(s, c.spot.name, GetTime())
    local here = SpotStats(s, self:SessionWhere(s))
    local worth = self:FishValue(c.itemID) or 0
    -- Trunks, chests, crates and bottles are finds, not junk: eight trunks
    -- and one fish is a good haul, and the log should say so.
    local find = c.junk and self.IsFishingFind and self:IsFishingFind(c.itemID) or nil
    if find then
        here.finds = (here.finds or 0) + 1
    elseif c.junk then
        here.junk = here.junk + 1
    else
        here.count = here.count + 1
        here.total = here.total + c.weight
        here.specimens = here.specimens + (c.specimen and 1 or 0)
        here.value = here.value + worth
        if c.weight > here.biggest then
            here.biggest, here.biggestName = c.weight, c.name
        end
    end
    s.value = s.value + worth
    table.insert(s.catches, 1, {
        itemID = c.itemID, name = c.name, weight = c.weight,
        specimen = c.specimen, junk = c.junk, find = find, sub = c.spot.name, at = self:SessionElapsed(s),
    })
    if find then
        s.finds = (s.finds or 0) + 1
        s.findItems = s.findItems or {}
        local name = c.name or self:FishName(c.itemID) or "?"
        s.findItems[name] = (s.findItems[name] or 0) + 1
    elseif c.junk then
        s.junk = s.junk + 1
    else
        s.count = s.count + 1
        s.total = s.total + c.weight
        if c.weight > s.biggest then
            s.biggest, s.biggestName = c.weight, c.name
        end
        if c.specimen then s.specimens = s.specimens + 1 end
    end
    self:UpdateBoard()
end

MF:On("TFL_CATCH", MF.LogCatch)

-- Walking to the next lake counts even before you cast there, or an hour
-- spent moving between waters lands on whichever one you left.
local function Followed(self)
    local s = self.session
    if not s or s.stoppedAt then return end
    MoveTo(s, self:CurrentSpot().name, GetTime())
    self:UpdateBoard()
end

MF:On("ZONE_CHANGED", Followed)
MF:On("ZONE_CHANGED_INDOORS", Followed)
MF:On("ZONE_CHANGED_NEW_AREA", Followed)

MF:On("TFL_FISHING_CAST", function(self)
    if not self:IsSessionRunning() then
        self:StartSession()
        return
    end
    Credit(self.session)
end)

-- "at Mirror Lake", or "at Mirror Lake and 2 other waters" - naming the one
-- that gave you the most rather than the one you happened to start at.
function MF:SessionWaters(s)
    local list = self:SessionSpots(s)
    if #list == 0 then return s.sub or "?" end
    if #list == 1 then return list[1].name end
    return ("%s and %d other water%s"):format(list[1].name, #list - 1, #list == 2 and "" or "s")
end

-- "8 finds" / "1 find", or nil for none
function MF:FindsText(n)
    n = tonumber(n) or 0
    if n <= 0 then return nil end
    return n .. (n == 1 and " find" or " finds")
end

-- "8 x Mithril Bound Trunk, 1 x Sealed Crate", most first
function MF:FindItemsText(items)
    if type(items) ~= "table" then return nil end
    local list = {}
    for name, n in pairs(items) do list[#list + 1] = { name = name, n = n } end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    for i, e in ipairs(list) do list[i] = e.n .. " x " .. e.name end
    return table.concat(list, ", ")
end

function MF:SessionSummary(s)
    local finds = self:FindsText(s.finds)
    return ("%s at %s: %d fish%s, %s total, biggest %s%s%s%s"):format(
        self:FormatClock(self:SessionElapsed(s)), self:SessionWaters(s), s.count,
        finds and (" and " .. finds) or "", MF:Weight(s.total), MF:Weight(s.biggest),
        s.biggestName and (" (" .. s.biggestName .. ")") or "",
        (self:ValueEnabled() and s.value > 0) and (", worth about " .. self:Money(s.value)) or "",
        s.specimens > 0 and (", " .. s.specimens .. " specimen(s)!") or "")
end

function MF:StopSession(quiet, saving)
    local s = self.session
    if not self:IsSessionRunning() then
        if not quiet then self:Print("No fishing log running.") end
        return
    end
    -- Bank the last stretch before the clock is stopped for good.
    Credit(s, GetTime())
    s.stoppedAt = GetTime()
    -- sub stays the water it started at, so history written before this
    -- still reads; spots is where it actually went.
    table.insert(self.cdb.history, {
        when = time(), solo = true, zone = s.zone, sub = s.sub,
        duration = self:SessionElapsed(s), count = s.count, total = s.total,
        elapsed = math.max(0, math.floor(s.stoppedAt - s.startedAt)),
        biggest = s.biggest, biggestName = s.biggestName, specimens = s.specimens,
        finds = (s.finds or 0) > 0 and s.finds or nil, findItems = (s.finds or 0) > 0 and s.findItems or nil,
        value = s.value, spots = self:SessionSpots(s),
        recordStats = s.recordStats,
        outcomes = s.outcomes,
    })
    if not quiet then self:Print("Log stopped. " .. self:SessionSummary(s)) end
    if not saving then
        self:UpdateBoard()
        self:RefreshJournal()
    end
end

-- Registered before Storage's logout backup: finalise once, without touching
-- protected UI during logout/combat. Personal catches were already credited.
MF:On("PLAYER_LOGOUT", function(self) self:StopSession(true, true) end)

MF:Command("stop", "Solo", "/tfl stop - stop the log", function(self) self:StopSession() end)

MF:Command("log", "Solo", "/tfl log - list its catches", function(self)
    local s = self.session
    if not s or #s.catches == 0 then
        self:Print("Nothing in the log yet.")
        return
    end
    self:Print("Fishing log (" .. s.sub .. "):")
    for i = #s.catches, 1, -1 do
        local c = s.catches[i]
        local w = c.find and "find" or c.junk and "junk" or MF:Weight(c.weight)
        print(("  [%s] %s - %s%s"):format(self:FormatClock(c.at), c.name or "?", w,
            c.specimen and " |cffffd100SPECIMEN|r" or ""))
    end
end)
