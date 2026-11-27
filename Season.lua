-- Season: a calendar month of competition. Spot records are kept for the
-- season as well as all-time, so every month there's something to win back.
--
-- Seasons are worked out from UTC so every player rolls over at the same
-- moment, whatever their time zone. There's nothing to sync: each client
-- derives the season from a catch's timestamp, exactly as it did for weeks.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

local ROLLOVER_CHECK = 60 -- seconds between checks (a month is not urgent)
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function IsLeap(year)
    return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

local function MonthLength(year, month)
    if month == 2 and IsLeap(year) then return 29 end
    return DAYS_IN_MONTH[month]
end

-- A season number that every client agrees on: months since year 0, UTC.
function MF:SeasonID(t)
    local utc = date("!*t", t or GetServerTime())
    return utc.year * 12 + (utc.month - 1)
end

-- The Pre-Season
--
-- The realm opens on 4 November with everyone back at nothing, so the
-- first season is four days short and spent levelling. Judging a month's
-- board on that would crown whoever could play the first weekend, which is
-- not what a season is for - so it is named for what it is, and the first
-- proper month is December.
--
-- Named rather than special-cased: it runs and scores exactly like any
-- other season, it is simply honest about being the warm-up.
function MF:PreSeasonID()
    return self:SeasonID(self.FRESH_START)
end

function MF:IsPreSeason(id)
    return (id or self:SeasonID()) == self:PreSeasonID()
end

function MF:SeasonName(id)
    id = id or self:SeasonID()
    if self:IsPreSeason(id) then return "The Pre-Season" end
    local year, month = math.floor(id / 12), id % 12 + 1
    return ("%s %d"):format(date("%B", time({ year = 2000, month = month, day = 1, hour = 12 })), year)
end

-- Said where the season is, because "why is this one called that" is asked
-- once per player and answered best in the place that prompts it.
function MF:SeasonNote()
    if not self:IsPreSeason() then return end
    return "The realm is new and everyone is levelling, so this first short season "
        .. "doesn't count as a month. December is the first proper one."
end

function MF:SeasonEndsIn()
    local utc = date("!*t", GetServerTime())
    local daysLeft = MonthLength(utc.year, utc.month) - utc.day
    return daysLeft * 86400 + (23 - utc.hour) * 3600 + (59 - utc.min) * 60 + (60 - utc.sec)
end

function MF:SeasonLeft()
    local seconds = self:SeasonEndsIn()
    if seconds >= 86400 then return ("%dd"):format(math.floor(seconds / 86400)) end
    return self:FormatClock(seconds)
end

------------------------------------------------------------------------
-- What you've done this season
------------------------------------------------------------------------

-- The one place that knows where a season's records are kept at a spot:
-- the running table, or the month kept when the spot rolled over (see
-- MF:Spot). A spot nobody has touched since the month turned still holds
-- last month in its running table, which this also answers correctly.
function MF:SeasonTable(s, id)
    if s.seasonID == id then return s.season end
    if s.lastSeasonID == id then return s.lastSeason end
end

function MF:HasSeasonRecords(id)
    for _, s in pairs(self.db.spots) do
        local fish = self:SeasonTable(s, id)
        if fish and next(fish) then return true end
    end
    return false
end

-- Returns records held, spots you're King of, and your best catch of a
-- season. Defaults to the one running; the rollover asks about the one that
-- has just ended, when the clock has already moved on but the spots haven't.
function MF:SeasonStanding(id)
    local season = id or self:SeasonID()
    local records, kings, bestW, bestID, bestSpot = 0, 0, 0, nil, nil
    for key, s in pairs(self.db.spots) do
        local fish = self:SeasonTable(s, season)
        if fish then
            for id, rec in pairs(fish) do
                if self:IsMe(rec.h) then
                    records = records + 1
                    if rec.w > bestW then bestW, bestID, bestSpot = rec.w, id, key end
                end
            end
        end
        local king = self:King(key)
        if king and self:IsMe(king.h) then kings = kings + 1 end
    end
    return records, kings, bestW, bestID, bestSpot
end

function MF:PrintSeason()
    local p = self.cdb.profile
    local records, kings, bestW, bestID, bestSpot = self:SeasonStanding()
    self:Print(("%s - %s left."):format(self:SeasonName(), self:SeasonLeft()))
    local note = self:SeasonNote()
    if note then print("  |cff858585" .. note .. "|r") end
    print(("  Season records held: %d   Spots you're King of: %d"):format(records, kings))
    print(("  XP this season: %d"):format(p.seasonXP or 0))
    if bestID then
        print(("  Best this season: %s %s at %s"):format(MF:Weight(bestW), self:FishName(bestID),
            self:SpotName(bestSpot)))
    else
        print("  No season records yet - the board is wide open.")
    end
end

MF:Command("season", "Progress", "/tfl season - how your season is going", MF.PrintSeason)

------------------------------------------------------------------------
-- Rollover
------------------------------------------------------------------------

local function EndSeason(self, p, endedID)
    local records, kings = self:SeasonStanding(endedID)
    self:Print(("|cffffd100%s has ended.|r You finished with %d XP, %d season records and %d Kings.")
        :format(self:SeasonName(endedID), p.seasonXP or 0, records, kings))
    self:Toast("Interface\\Icons\\Trade_Fishing", "SEASON OVER", self:SeasonName(endedID),
        ("%d XP - %d records"):format(p.seasonXP or 0, records), 1, 0.82, 0, SOUNDKIT.UI_EPICLOOT_TOAST)
    table.insert(self.cdb.history, {
        when = time(), season = endedID, xp = p.seasonXP or 0, records = records, kings = kings,
    })
end

function MF:EnsureSeason()
    local p, season = self.cdb.profile, self:SeasonID()
    if p.season == season then return end
    -- A season we actually played gets a send-off; a fresh profile doesn't.
    if p.season and (p.seasonXP or 0) > 0 then
        EndSeason(self, p, p.season)
    end
    p.season, p.seasonXP = season, 0
    self:MarkProfileChanged()
    self:RefreshJournal()
end

local sinceCheck = 0
MF:OnTick(function(self)
    sinceCheck = sinceCheck + 1
    if sinceCheck < ROLLOVER_CHECK or not self.me then return end
    sinceCheck = 0
    self:EnsureSeason()
end)
