-- FrenzyPlanner: the frenzy waters, ready to search, plan around and be
-- reminded of.
--
-- Every catalogue water's frenzy runs on a fixed clock - 25 minutes in
-- every two hours, offset by its ID - so the planner knows not just what's
-- on now but the whole of the next two hours, for every water, without
-- asking anyone. That is what the Frenzies page is drawn from: a search, a
-- grouped list and a timeline.
--
-- Favourites and reminders are kept on the character. A reminder repeats:
-- it fires two minutes before every frenzy at that water until it's turned
-- off, because the water you want to fish is the same one tomorrow.
--
-- The frenzy list the classic journal drew (FrenzyListLines) is untouched;
-- the page in Rework\FrenzyPage.lua replaces only how it's shown.
local _, MF = ...

local REMIND_BEFORE = 120 -- seconds' notice a reminder gives
local HOUR = 3600

local function Store(self, key)
    local cdb = self.cdb
    if type(cdb[key]) ~= "table" then cdb[key] = {} end
    return cdb[key]
end

function MF:IsFrenzyFavourite(id) return Store(self, "frenzyFavourites")[id] == true end
function MF:SetFrenzyFavourite(id, on) Store(self, "frenzyFavourites")[id] = on and true or nil end
function MF:IsFrenzyReminder(id) return Store(self, "frenzyReminders")[id] == true end
function MF:SetFrenzyReminder(id, on) Store(self, "frenzyReminders")[id] = on and true or nil end

-- "Riverglades water (56.54, 85.41)" under a Riverglades heading reads
-- better as "Water at 56.54, 85.41"; a named water keeps its name.
function MF:FrenzyShortName(w)
    local at = w.name:match("^.- water %((.-)%)$")
    return at and ("Water at " .. at) or w.name
end

-- Searching: any word of the name or zone, as typed, case aside. Every
-- word has to match somewhere, so "wet 61" finds Wetlands water (61.48...).
local function Matches(text, hay)
    for word in text:lower():gmatch("%S+") do
        if not hay:find(word, 1, true) then return false end
    end
    return true
end

-- Yards from where you stand, on the same map; nil anywhere else.
function MF:FrenzyYards(w, current)
    current = current or self:CurrentSpot()
    if not current or current.mapID ~= w.map then return end
    local best
    for _, a in ipairs(w.anchors or { { w.x, w.y } }) do
        local d = self:FrenzyDistance(w.map, current.x, current.y, a[1], a[2])
        if d and (not best or d < best) then best = d end
    end
    return best
end

-- The rows the page draws. opts: text (search), when ("active", "hour" or
-- "all"), localOnly, favourites. Each row: water, zone, active, left,
-- yards, here, localZone, favourite, remind.
function MF:FrenzyRows(opts)
    opts = opts or {}
    local current = self:CurrentSpot()
    local here = self:ResolveFrenzyLocation()
    local text = (opts.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local rows = {}
    for _, w in ipairs(self.FRENZY_LOCATIONS) do
        local zone = self:FrenzyZoneLabel(w.map)
        local active, left = self:FrenzyState(w.id)
        local keep = (not opts.localOnly or w.map == current.mapID)
            and (not opts.favourites or self:IsFrenzyFavourite(w.id))
            and (opts.when ~= "active" or active)
            and (opts.when ~= "hour" or active or left <= HOUR)
            and (text == "" or Matches(text, (w.name .. " " .. zone):lower()))
        if keep then
            rows[#rows + 1] = { water = w, zone = zone, active = active, left = left,
                yards = self:FrenzyYards(w, current), here = here and here.id == w.id or false,
                localZone = w.map == current.mapID, favourite = self:IsFrenzyFavourite(w.id),
                remind = self:IsFrenzyReminder(w.id) }
        end
    end
    table.sort(rows, function(a, b)
        if a.here ~= b.here then return a.here end
        if a.active ~= b.active then return a.active end
        if a.left ~= b.left then return a.left < b.left end
        return a.water.id < b.water.id
    end)
    return rows
end

-- The same rows in zones: your zone first, then whichever zone has the
-- soonest thing happening. Returns { { zone, localZone, active, rows }, ... }.
function MF:FrenzyGroups(rows)
    local byZone, groups = {}, {}
    for _, r in ipairs(rows) do
        local g = byZone[r.zone]
        if not g then
            g = { zone = r.zone, localZone = r.localZone, active = 0, rows = {}, first = #groups + 1 }
            byZone[r.zone] = g
            groups[#groups + 1] = g
        end
        if r.active then g.active = g.active + 1 end
        g.rows[#g.rows + 1] = r
    end
    -- Rows arrive in time order, so a zone's place is its first row's.
    table.sort(groups, function(a, b)
        if a.localZone ~= b.localZone then return a.localZone end
        return a.first < b.first
    end)
    return groups
end

-- Every stretch a water is in frenzy between from and from + span:
-- { { start, stop }, ... }, clipped to the span.
function MF:FrenzyWindows(id, from, span)
    local cycle, length = self.FRENZY_CYCLE, self.FRENZY_LENGTH
    local offset = self:Hash(tostring(id or "")) % cycle
    local into = (from - offset) % cycle
    local start = from - into
    local out = {}
    while start < from + span do
        local stop = start + length
        if stop > from then
            out[#out + 1] = { math.max(start, from), math.min(stop, from + span) }
        end
        start = start + cycle
    end
    return out
end

-- Your best fish at a water, from your records at any spot inside it.
-- Returns weight, itemID, or nil.
function MF:FrenzyBestCatch(w)
    local best, bestID
    for key, fish in pairs(self.cdb.records or {}) do
        local p = self:SpotPosition(key)
        if p and p.map == w.map and self:StaticFrenzyAt(p.map, p.x, p.y) == w then
            for itemID, r in pairs(fish) do
                if type(r) == "table" and (r.weight or 0) > (best or 0) then best, bestID = r.weight, itemID end
            end
        end
    end
    return best, bestID
end

------------------------------------------------------------------------
-- Reminders
------------------------------------------------------------------------

local reminded = {} -- water id -> the start time we've already reminded for

function MF:CheckFrenzyReminders(now)
    now = now or GetServerTime()
    for id in pairs(Store(self, "frenzyReminders")) do
        local w = self:StaticFrenzyByID(id)
        if not w then
            -- Gone from the catalogue: nothing to remind about.
            self:SetFrenzyReminder(id, false)
        else
            local active, left = self:FrenzyState(id)
            local startsAt = now + left
            if not active and left <= REMIND_BEFORE and reminded[id] ~= startsAt then
                reminded[id] = startsAt
                local zone = self:FrenzyZoneLabel(w.map)
                self:Print(("|cffff8000Frenzy soon:|r %s, %s, starts in %s."):format(
                    w.name, zone, self:FormatClock(left)))
                self:Toast("Interface\\Icons\\Trade_Fishing", "FRENZY SOON", w.name,
                    ("%s - starts in %s"):format(zone, self:FormatClock(left)), 1, 0.5, 0,
                    SOUNDKIT.RAID_WARNING)
            end
        end
    end
end

MF:OnTick(function(self) self:CheckFrenzyReminders() end)
