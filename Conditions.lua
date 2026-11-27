-- Conditions: feeding frenzies, day/night, and the daily bounty.
-- Frenzies and bounties are derived from server time, so every client agrees
-- on them without sending a single message.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

-- Each catalogue location gets one frenzy every two hours, for twenty-five
-- minutes. Which two hours is decided by a hash of the spot itself, so no
-- two waters run together and every client works out the same schedule
-- from the same arithmetic. On MF so the board can explain itself.
MF.FRENZY_CYCLE = 2 * 60 * 60
MF.FRENZY_LENGTH = 25 * 60
local FRENZY_CYCLE, FRENZY_LENGTH = MF.FRENZY_CYCLE, MF.FRENZY_LENGTH
local DAY = 24 * 60 * 60
local XP_FIRST_BOUNTY = 30

------------------------------------------------------------------------
-- Feeding frenzy
------------------------------------------------------------------------

-- Returns active, seconds (left if active, until next if not), window number.
-- Raw clock arithmetic. Gameplay and UI must resolve an eligible static ID first.
function MF:FrenzyState(key)
    local offset = self:Hash(tostring(key or "")) % FRENZY_CYCLE
    local shifted = GetServerTime() - offset
    local t = shifted % FRENZY_CYCLE
    local window = math.floor(shifted / FRENZY_CYCLE)
    if t < FRENZY_LENGTH then
        return true, FRENZY_LENGTH - t, window
    end
    return false, FRENZY_CYCLE - t, window
end

function MF:IsFrenzy(key)
    local water=self:ResolveFrenzyLocation(key)
    return water and (self:FrenzyState(water.id)) or false
end

-- The static catalogue, rather than learned catch records, establishes eligibility.
function MF:KnownFishingWater(key)
    return self:ResolveFrenzyLocation(key)~=nil
end

function MF:FrenzyPresentationState(key)
    local water=self:ResolveFrenzyLocation(key)
    if not water then return false,nil end
    return self:FrenzyState(water.id)
end

function MF:IsNight()
    local hour = GetGameTime()
    return hour >= 20 or hour < 6
end

-- Announce an active frenzy at your location, including when arriving before
-- starting a fishing session. Remember each window to avoid boundary spam.
local alerted = {} -- spot key -> frenzy window we already announced
function MF:CheckFrenzyAlert()
    -- Do not consume the arrival alert while flying; landing at the water
    -- should still announce its active frenzy.
    if type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then return end
    local spot = self:CurrentSpot()
    local water=self:ResolveFrenzyLocation()
    if not water then return end
    local active, left, window = self:FrenzyState(water.id)
    if active and alerted[water.id] ~= window then
        alerted[water.id] = window
        self:Print(("|cffff8000Feeding frenzy at %s!|r Heavier fish and double specimen chance for %s.")
            :format(water.name, self:FormatClock(left)))
        self:Toast("Interface\\Icons\\Trade_Fishing", "FEEDING FRENZY", water.name,
            "Heavier fish for " .. self:FormatClock(left), 1, 0.5, 0, SOUNDKIT.RAID_WARNING,
            { spot = spot.key, expires = GetTime() + math.min(left, 30) })
    end
end
MF:OnTick(function(self) self:CheckFrenzyAlert() end)

------------------------------------------------------------------------
-- Bounties: daily, weekly and monthly
--
-- The daily used to pick from every (fish, zone) pair in the data: 205
-- of them across 36 zones. 118 of those zones are places a levelling
-- character never goes, so 58% of days the bounty landed somewhere
-- nobody was and the standings read "no entries yet" because there
-- genuinely were none. A bounty in Western Plaguelands is not a contest.
--
-- So the pool is the waters people are actually at, taken from the realm
-- records rather than guessed. And because the records show the traffic
-- splitting clean down the middle - Alliance in Stormwind, Elwynn,
-- Darkshore; Horde in Undercity, Orgrimmar, the Barrens - the daily is
-- drawn per faction. One bounty for the whole realm is always worthless
-- to half of it.
--
-- Three cadences, deliberately different in kind rather than the same
-- thing at three speeds, which would only split a small realm's
-- attention three ways:
--
--   daily    heaviest <fish> in <zone>   - an errand, go and do it
--   weekly   heaviest <fish> anywhere    - no travel gate, everyone can enter
--   monthly  most <fish> caught anywhere - rewards playing, not one lucky cast
--
-- All three score the same shape - a number per angler, highest wins -
-- so they share one set of standings machinery. The monthly's number is
-- a tally rather than a weight, which is the only place that shows.
------------------------------------------------------------------------

-- A city has no fish of its own in the data, and people fish in cities
-- more than anywhere: Undercity turned up seven times in one afternoon's
-- records. In the game a city's water holds the surrounding zone's fish,
-- so that is what a bounty there asks for.
--
-- Used only for choosing a bounty. What actually bites in a city is the
-- game's business, and IsNative is deliberately left alone - changing it
-- would move specimen chances and record validation for everybody.
MF.CITY_FISHES_AS = {
    ["Stormwind City"] = "Elwynn Forest",
    ["Ironforge"] = "Dun Morogh",
    ["Darnassus"] = "Teldrassil",
    ["Undercity"] = "Tirisfal Glades",
    ["Orgrimmar"] = "Durotar",
    ["Thunder Bluff"] = "Mulgore",
}

-- Where the realm actually fishes, read off the Realm tab rather than
-- guessed at. A = Alliance side, H = Horde, C = contested, everyone.
-- Forever's own zones are absent on purpose: no fish data exists for
-- Riverglades or Zephras Isle and inventing some would be worse than
-- leaving them out until the catches say what lives there.
MF.BOUNTY_ZONES = {
    ["Elwynn Forest"] = "A", ["Westfall"] = "A", ["Redridge Mountains"] = "A",
    ["Duskwood"] = "A", ["Dun Morogh"] = "A", ["Loch Modan"] = "A",
    ["Wetlands"] = "A", ["Darkshore"] = "A", ["Teldrassil"] = "A",
    ["Stormwind City"] = "A", ["Ironforge"] = "A", ["Darnassus"] = "A",

    ["Durotar"] = "H", ["Mulgore"] = "H", ["The Barrens"] = "H",
    ["Tirisfal Glades"] = "H", ["Silverpine Forest"] = "H",
    ["Orgrimmar"] = "H", ["Undercity"] = "H", ["Thunder Bluff"] = "H",

    ["Stranglethorn Vale"] = "C", ["Ashenvale"] = "C",
    ["Hillsbrad Foothills"] = "C", ["Stonetalon Mountains"] = "C",
    ["Arathi Highlands"] = "C", ["Desolace"] = "C", ["Tanaris"] = "C",
}

local WEEK, MONTH = 7 * DAY, 28 * DAY

MF.BOUNTY_KINDS = { "day", "week", "month" }
local SPAN = { day = DAY, week = WEEK, month = MONTH }

-- How many periods are kept: this one and the one before it. The
-- second is what lets a client say who won, and answer somebody else
-- asking. Anything older is weight - a bounty nobody can still see.
local KEEP_PERIODS = 2

------------------------------------------------------------------------
-- A bounty, once set, does not change until it ticks over
--
-- Deriving a bounty from the period number means every client agrees
-- without a message being sent. The price is that the arithmetic's
-- inputs are part of that agreement, and nothing was stopping them from
-- moving. Taking twelve fish out of the pool renumbered the list the
-- draw indexes into, so the same hash landed somewhere else: halfway
-- through a Tuesday the daily went from Oily Blackmouth to Firefin
-- Snapper, and fourteen of the previous thirty dailies changed with it.
-- Scores already banked stayed banked, now answering a question nobody
-- had been asked.
--
-- Three things in this section stop that. They are worth reading
-- together, because each of them only closes part of it.
--
-- ONE: the roster below is frozen. The draw does not read MF.FISH at
-- all, so fish can be added for Riverglades and Zephras Isle, weights
-- can be tuned, zones can be corrected, and no bounty moves. Only ALL
-- and IN decide, and the golden test in test/cases/bounty.lua pins what
-- they decide to written-down answers - so editing them is a thing you
-- have to mean, not something you do by accident while doing something
-- else.
--
-- TWO: a change to the roster takes effect from a date, not from an
-- install. An era says what the rules became and when, periods are
-- judged by the era that had begun when the period started, and earlier
-- eras are never touched again. That is what makes "until it ticks
-- over" literally true: the day, the week and the month each keep the
-- rules they opened under, and each picks the new ones up at its own
-- next rollover rather than mid-contest.
--
-- THREE: a client writes down what it drew the first time it sees a
-- period, and reads that back for as long as it keeps it. This is the
-- backstop for the other two being wrong - a mistake in here, or a
-- roster edited without an era, cannot move a bounty somebody is
-- already fishing.
--
-- What none of this can do is make a client agree about a rule invented
-- after it shipped: 0.10.0 cannot know what era 2 says. So an era's
-- date is set far enough ahead that the build announcing it is live
-- before it arrives, and a score now travels with the fish it answers,
-- so a client that disagrees anyway shows you nothing instead of
-- quietly crediting the wrong fish.
------------------------------------------------------------------------

-- Every fish, sorted, as the weekly and monthly draw from it.
local ALL = {
    1467, 4603, 6289, 6291, 6299, 6303, 6308, 6317, 6358, 6359,
    6360, 6361, 6362, 6458, 6522, 6643, 6645, 6647, 8365, 8366,
    12238, 13422, 13754, 13755, 13756, 13757, 13758, 13759, 13760, 13881,
    13888, 13889, 13890, 13891, 13893, 16967, 16968, 16969, 16970, 19803,
    19805, 19806, 19807, 19808, 19975, 21071, 21153,
}

-- What is native to each zone a bounty can name, sorted, with the cities
-- already resolved through CITY_FISHES_AS above. Written out rather than
-- worked out, because a bounty must not move when the fish data does.
local IN = {
    ["Arathi Highlands"] = { 6308, 6359, 6362, 6647, 8365, 8366, 21153 },
    ["Ashenvale"] = { 6289, 6308, 6645, 6647, 21071 },
    ["Darkshore"] = { 6289, 6303, 6358, 6361, 6645, 12238 },
    ["Darnassus"] = { 6291, 6303, 6643 },
    ["Desolace"] = { 6359, 6362, 8365, 8366, 16968, 21153 },
    ["Dun Morogh"] = { 6291, 6643 },
    ["Durotar"] = { 6291, 6303, 6643 },
    ["Duskwood"] = { 6289, 6308, 6645, 6647 },
    ["Elwynn Forest"] = { 6291, 6643 },
    ["Hillsbrad Foothills"] = { 6289, 6308, 6358, 6359, 6645, 6647, 21071 },
    ["Ironforge"] = { 6291, 6643 },
    ["Loch Modan"] = { 6289, 6317, 6645 },
    ["Mulgore"] = { 6291, 6643 },
    ["Orgrimmar"] = { 6291, 6303, 6643 },
    ["Redridge Mountains"] = { 6289, 6308, 6645, 6647 },
    ["Silverpine Forest"] = { 6289, 6303, 6358, 6645 },
    ["Stonetalon Mountains"] = { 6308, 6647, 21071 },
    ["Stormwind City"] = { 6291, 6643 },
    ["Stranglethorn Vale"] = { 4603, 6359, 6362, 8365, 8366, 13422, 13754,
        13755, 13756, 13757, 13888, 13890, 13893, 16969, 19803, 19805,
        19806, 19807, 19808, 19975, 21153 },
    ["Tanaris"] = { 4603, 6362, 13422, 13754, 13755, 13756, 13757, 13888, 13890, 13893 },
    ["Teldrassil"] = { 6291, 6303, 6643 },
    ["The Barrens"] = { 6289, 6303, 6358, 6361, 6522, 6645 },
    ["Thunder Bluff"] = { 6291, 6643 },
    ["Tirisfal Glades"] = { 6291, 6643 },
    ["Undercity"] = { 6291, 6643 },
    ["Westfall"] = { 6289, 6303, 6358, 6361, 6645 },
    ["Wetlands"] = { 6289, 6308, 6358, 6359, 6361, 6645, 6647, 21071 },
}

-- The eras, oldest first.
--
-- Era 1 is how 0.10.0 drew and is finished: it is the rules the live
-- realm is playing under and must not be edited again for any reason.
-- Era 2 drops the fish MF.NOT_BOUNTY names - the bloated six, which are
-- too rare to be a contest, and the six that cannot be caught at all on
-- most days. Its date is a day boundary chosen to be comfortably after
-- the build carrying it is out, so by the time it matters everybody
-- agrees. The daily picks it up that morning, the weekly and the
-- monthly at their own next rollover.
--
-- Adding to the roster later means a new era, never an edit to one that
-- has begun. An era with an `add` would be the shape for the Riverglades
-- and Zephras Isle fish when there is data for them.
local ERAS = {
    { from = 0 },
    { from = 1792108800, out = MF.NOT_BOUNTY }, -- 16 Oct 2026
}
MF.BOUNTY_ERAS = ERAS

-- Which rules a period plays by: the last era that had begun when the
-- period started. By the period's start and not by the clock now, so a
-- contest keeps what it opened with for the whole of its run.
local function EraAt(startedAt)
    local era = ERAS[1]
    for i = 2, #ERAS do
        if ERAS[i].from <= startedAt then era = ERAS[i] else break end
    end
    return era
end

-- The same answer as a number, for BountyPool: which era a period opened under.
function MF:BountyEraIndex(startedAt)
    local index = 1
    for i = 2, #ERAS do
        if ERAS[i].from <= startedAt then index = i else break end
    end
    return index
end

-- The lists an era draws from, built once each. Order is the frozen
-- order with the era's exclusions taken out, which is what keeps era 1
-- identical to the build that shipped it.
local rosters = {}

local function Roster(era)
    local r = rosters[era]
    if r then return r end
    r = { fish = {}, zones = {}, all = {} }
    local out, add = era.out or {}, era.add or {}
    for _, id in ipairs(ALL) do
        if not out[id] then r.all[#r.all + 1] = id end
    end
    for _, id in ipairs(add.ALL or {}) do r.all[#r.all + 1] = id end
    for zone, list in pairs(IN) do
        local keep = {}
        for _, id in ipairs(list) do
            if not out[id] then keep[#keep + 1] = id end
        end
        for _, id in ipairs(add[zone] or {}) do keep[#keep + 1] = id end
        r.fish[zone] = keep
    end
    -- A zone an era brings in for the first time (Riverglades, say) is in
    -- `add` and nowhere in IN, so it needs its own pass or it never appears.
    for zone, ids in pairs(add) do
        if zone ~= "ALL" and not IN[zone] then
            local keep = {}
            for _, id in ipairs(ids) do
                if not out[id] then keep[#keep + 1] = id end
            end
            r.fish[zone] = keep
        end
    end
    for _, side in ipairs({ "A", "H" }) do
        local list = {}
        for zone, owner in pairs(MF.BOUNTY_ZONES) do
            -- A zone with nothing an era will name can never be answered.
            if (owner == "C" or owner == side) and #(r.fish[zone] or {}) > 0 then
                list[#list + 1] = zone
            end
        end
        table.sort(list)
        r.zones[side] = list
    end
    rosters[era] = r
    return r
end

-- Built once and kept, so a test that changes the fish data underneath
-- to prove a bounty does not follow it has to say so. Nothing in the
-- game calls this; the roster cannot go stale, because it is a literal.
function MF:ForgetBountyRosters()
    rosters = {}
end

-- What an era would ask for, for anyone measuring the pool rather than
-- fishing it: the test that counts how many fish can still come up, and
-- the one that checks none of them is a fish nobody can catch.
function MF:BountyPool(era, zone)
    local r = Roster(ERAS[era or #ERAS])
    if zone then return r.fish[zone] or {} end
    return r.all
end

function MF:MySide()
    return (UnitFactionGroup and UnitFactionGroup("player")) == "Horde" and "H" or "A"
end

function MF:BountyPeriod(kind)
    return math.floor(GetServerTime() / (SPAN[kind] or DAY))
end

function MF:BountyTimeLeft(kind)
    local span = SPAN[kind] or DAY
    return span - GetServerTime() % span
end

-- What we drew, the first time we drew it
--
-- Kept by faction as well as cadence: the daily is per side and two
-- characters on one realm share this table, so an Alliance draw must not
-- be handed to a Horde character as theirs.
--
-- Nothing is written for a period that has not started yet, or a client
-- running fast would pin an answer the rest of the realm works out
-- differently. Pruned on the way in, alongside the scores it belongs to.
local function SeenKey(kind, side)
    return kind == "day" and ("day" .. tostring(side)) or kind
end

local function Remembered(self, kind, period, side)
    local db = self.db
    local held = db and db.bountySeen and db.bountySeen[SeenKey(kind, side)]
    local kept = held and held[period]
    if kept and kept.id then return kept end
    return nil
end

local function Remember(self, kind, period, side, id, zone)
    local db = self.db
    if not db or not id then return end
    db.bountySeen = db.bountySeen or {}
    local key = SeenKey(kind, side)
    local held = db.bountySeen[key]
    if not held then
        held = {}
        db.bountySeen[key] = held
    end
    local now = self:BountyPeriod(kind)
    for at in pairs(held) do
        if type(at) ~= "number" or at <= now - KEEP_PERIODS then held[at] = nil end
    end
    if period > now then return end
    held[period] = { id = id, zone = zone }
end

-- Returns period, itemID, zone (nil for the cadences that are anywhere).
-- period is optional: the objective for any period is arithmetic on it,
-- which is how last time's can be shown without ever having been sent.
function MF:Bounty(kind, period)
    kind = kind or "day"
    period = period or self:BountyPeriod(kind)
    local side = self:MySide()
    local kept = Remembered(self, kind, period, side)
    if kept then return period, kept.id, kept.zone end

    local r = Roster(EraAt(period * (SPAN[kind] or DAY)))
    local id, zone
    if kind == "day" then
        local zones = r.zones[side]
        if #zones == 0 then return period end
        zone = zones[self:Hash("bzone" .. side .. period) % #zones + 1]
        local fishes = r.fish[zone]
        if #fishes == 0 then return period end
        id = fishes[self:Hash("bfish" .. side .. period) % #fishes + 1]
    else
        id = r.all[self:Hash(kind .. "bounty" .. period) % #r.all + 1]
    end
    Remember(self, kind, period, side, id, zone)
    return period, id, zone
end
-- Kept for anything still asking the old question.
function MF:TodayBounty()
    return self:Bounty("day")
end

function MF:BountyDay()
    return self:BountyPeriod("day")
end

function MF:BountyText(kind)
    local _, id, zone = self:Bounty(kind)
    if not id then return "nothing this time" end
    if kind == "month" then
        return ("most |cffffd100%s|r caught anywhere"):format(self:FishName(id))
    elseif kind == "week" then
        return ("heaviest |cffffd100%s|r caught anywhere"):format(self:FishName(id))
    end
    return ("heaviest |cffffd100%s|r caught in |cffffd100%s|r")
        :format(self:FishName(id), zone or "?")
end

------------------------------------------------------------------------
-- Standings
--
-- One number per angler, highest wins, which is true of a heaviest fish
-- and of a tally of them alike. The monthly counts; the others weigh.
------------------------------------------------------------------------

-- Standings outlive the anglers being online
--
-- They used to be held in memory only, on the reasoning that asking
-- brings them back. Asking only brings back what somebody online can
-- answer, so an angler who logged off vanished from the board - a
-- bounty you were winning on Tuesday evening had no winner by Tuesday
-- night, and a reload lost everyone at once.
--
-- They are realm knowledge, the same as records and spots, and they are
-- kept the same way: written down, validated on arrival rather than on
-- the way out, pruned with the periods they belong to, and taken by the
-- wipe along with everything else the realm told us.
-- Bounty boards already aggregate realm-labelled relays. Identity must
-- remove the sender's realm as well as ours, not just whitespace/hyphens.
local function BountyIdentity(self, name)
    local plain = self:SplitName(name)
    return plain:gsub("[%s%-]", ""):lower()
end

local function Scores(self, kind, period)
    period = period or self:BountyPeriod(kind)
    local now = self:BountyPeriod(kind)
    self.db.bountyBoard = self.db.bountyBoard or {}
    local byKind = self.db.bountyBoard[kind]
    if not byKind then
        byKind = {}
        self.db.bountyBoard[kind] = byKind
    end
    for held in pairs(byKind) do
        if type(held) ~= "number" or held <= now - KEEP_PERIODS then byKind[held] = nil end
    end
    local held = byKind[period]
    if not held then
        held = {}
        byKind[period] = held
    end
    -- Direct messages and relays can spell one name differently. Fold the
    -- saved board too, so an old duplicate cannot keep travelling. Keep the
    -- maximum: monthly scores are snapshots of one tally, not extra catches.
    local identities, folded = {}, {}
    for name, score in pairs(held) do
        local key = BountyIdentity(self, name)
        local label = key == BountyIdentity(self, self.me) and self.me or self:FullName(self:WhisperName(name))
        if key ~= "" then
            local old = identities[key]
            if not old then
                identities[key] = { name = label, score = score }
            else
                old.score = math.max(old.score, score)
                if label < old.name then old.name = label end
            end
        end
    end
    for _, entry in pairs(identities) do folded[entry.name] = entry.score end
    held = folded
    byKind[period] = held
    -- And your own, every time rather than once: it is kept on your
    -- character and the board is kept on the realm, so the two have to
    -- be brought together somewhere.
    local ours = self:MyBountyBest(kind, period)
    if self.me and ours > (held[self.me] or 0) then held[self.me] = ours end
    return held
end

-- Your score is yours, not your account's
--
-- It was kept account-wide, so logging in on an alt handed that alt the
-- main's score - and announcing where you stand on login then put the
-- same catch on the board twice, once under each name. Two Hawks, both
-- 11.73 lb, one fish.
--
-- Core.lua drew this line in 0.6.4 and says why: rank, journal and
-- personal bests follow the character who earned them, and what the
-- realm told us is the same whoever you are playing. A bounty score is
-- a personal best. It landed on the wrong side of the line in 0.10.0.
local function Mine(self, kind, period)
    period = period or self:BountyPeriod(kind)
    self.cdb.bounties = self.cdb.bounties or {}
    local byKind = self.cdb.bounties[kind]
    if not byKind then
        byKind = {}
        self.cdb.bounties[kind] = byKind
    end

    local now = self:BountyPeriod(kind)
    for held in pairs(byKind) do
        if type(held) ~= "number" or held <= now - KEEP_PERIODS then
            byKind[held] = nil
        end
    end
    if byKind[period] == nil then byKind[period] = 0 end
    return byKind, period
end

-- Claiming what the account-wide table was holding
--
-- It cannot say which character earned what, so nobody is simply handed
-- it: a character claims a score only if its own catch tally shows it
-- could have set it. Both alts claiming means both really did catch
-- that fish that heavy, which is a tie worth having. Anything unclaimed
-- sits until its period lapses and then goes with it.
--
-- The same shape 0.6.4 used for the log itself, for the same reason -
-- losing a standing somebody is in the middle of fishing for is the
-- thing this release exists to stop.
local function CouldHave(self, kind, period, score)
    if score <= 0 then return false end
    local _, id, zone = self:Bounty(kind, period)
    if not id then return false end
    local where = self.cdb.caughtIn and self.cdb.caughtIn[id]
    if not where then return false end
    -- The monthly counts rather than weighs, and an all-time tally can
    -- only be the larger of the two, so this asks the weaker question:
    -- has this character ever caught the fish enough times at all.
    if kind == "month" then
        local caught = 0
        for _, e in pairs(where) do caught = caught + (e.c or 0) end
        return caught >= score
    end
    if zone then
        local e = where[zone]
        return e ~= nil and (e.b or 0) >= score - 0.005
    end
    for _, e in pairs(where) do
        if (e.b or 0) >= score - 0.005 then return true end
    end
    return false
end

function MF:ClaimSharedBounties()
    local shared = self.db.bounties
    if not shared then return end
    self.cdb.bounties = self.cdb.bounties or {}
    local left = false
    for _, kind in ipairs(MF.BOUNTY_KINDS) do
        local byKind = shared[kind]
        -- 0.10.0 saved one period as { period = n, best = w }.
        if byKind and byKind.period ~= nil then
            byKind = { [byKind.period] = byKind.best or 0 }
            shared[kind] = byKind
        end
        local now = self:BountyPeriod(kind)
        for held, score in pairs(byKind or {}) do
            if type(held) ~= "number" or held <= now - KEEP_PERIODS then
                byKind[held] = nil
            elseif CouldHave(self, kind, held, score) then
                local ours = self.cdb.bounties[kind] or {}
                self.cdb.bounties[kind] = ours
                if (ours[held] or 0) < score then ours[held] = score end
                left = true -- an alt of yours may be able to claim it too
            else
                left = true
            end
        end
    end
    if not left then self.db.bounties = nil end
end

-- TFL_LOGIN rather than TFL_INIT: the daily is per faction and
-- UnitFactionGroup is not reliable until the world is up, so claiming
-- any earlier would check a Horde character's score against the
-- Alliance objective and refuse it. It still lands before TFL_SYNC,
-- which is what announces where you stand.
MF:On("TFL_LOGIN", MF.ClaimSharedBounties)

function MF:MyBountyBest(kind, period)
    local held, at = Mine(self, kind or "day", period)
    return held[at] or 0
end

function MF:BountyStandings(kind, period)
    local list = {}
    for name, w in pairs(Scores(self, kind or "day", period)) do
        list[#list + 1] = { name = name, weight = w }
    end
    table.sort(list, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.name < b.name
    end)
    return list
end

function MF:BountyPlace(name, kind, period)
    local place, last = 0, nil
    for i, s in ipairs(self:BountyStandings(kind or "day", period)) do
        if s.weight ~= last then place, last = i, s.weight end
        if BountyIdentity(self, s.name) == BountyIdentity(self, name) then return place end
    end
end

-- One question, one answer: which period is being asked about.
local function Topic(kind, period)
    return ("bounty:%s:%s"):format(tostring(kind), tostring(period))
end

-- A score travels with the fish it answers
--
-- Without it a stale client's entry lands in a contest it was not
-- fishing: 0.10.0 cannot know what a later era asks for, so it would
-- send a perfectly good Oily Blackmouth weight into a Firefin Snapper
-- bounty and be believed. The field is appended rather than replacing
-- anything, so an older client simply ignores it.
local function Say(self, kind, period, score)
    local _, id = self:Bounty(kind, period)
    self:SendChannel("BNTY2", kind, period, self:EncodeWeight(score), self:MySide(), id)
end

-- Called for every real catch; returns bonus XP.
function MF:CheckBounty(c)
    local xp = 0
    for _, kind in ipairs(MF.BOUNTY_KINDS) do
        local period, id, zone = self:Bounty(kind)
        if c.itemID == id and (not zone or c.zone == zone) then
            local held, at = Mine(self, kind)
            local was = held[at] or 0
            if kind == "day" and was == 0 then
                xp = xp + XP_FIRST_BOUNTY
                self:Print(("You caught today's bounty fish! +%d XP"):format(XP_FIRST_BOUNTY))
            end
            -- The monthly counts catches; the others take the heaviest.
            local score = kind == "month" and (was + 1) or math.max(was, c.weight)
            if score > was then
                held[at] = score
                Scores(self, kind)[self.me] = score
                Say(self, kind, period, score)
                if kind ~= "day" then
                    self:Print(("%s bounty: you're #%d."):format(
                        kind == "week" and "Weekly" or "Monthly",
                        self:BountyPlace(self.me, kind) or 1))
                end
            end
        end
    end
    return xp
end

function MF:RequestBounty()
    for _, kind in ipairs(MF.BOUNTY_KINDS) do
        local now = self:BountyPeriod(kind)
        self:SendChannel("BREQ2", kind, now)
        -- And the one that just finished, which is how somebody who was
        -- away over the rollover finds out who won it.
        self:SendChannel("BREQ2", kind, now - 1)
    end
end

-- Who took the last one, what it was for, and what they took it with.
-- Nil until the first period has finished, and until somebody has
-- actually entered one.
function MF:BountyWinner(kind)
    kind = kind or "day"
    local last = self:BountyPeriod(kind) - 1
    local standings = self:BountyStandings(kind, last)
    local top = standings[1]
    if not top then return nil end
    local _, id, zone = self:Bounty(kind, last)
    return { name = top.name, score = top.weight, specimen = top.specimen, id = id, zone = zone, period = last }
end

-- Say where you stand, as well as asking where everybody else does.
--
-- Asking alone leaves a one-way gap. TFL_SYNC fires once, a few seconds
-- after login, and never again - so whoever logs in second asks and is
-- answered, while whoever logged in first never asks again and hears
-- nothing until the other improves their score. Two guildmates fishing
-- the same bounty saw exactly that: she had his entry and he did not
-- have hers.
--
-- Records already announce themselves on sync for the same reason. The
-- jitter is so twenty people logging in after a server restart do not
-- all speak at once.
function MF:AnnounceMyBounties()
    for _, kind in ipairs(MF.BOUNTY_KINDS) do
        local period = self:BountyPeriod(kind)
        local best = self:MyBountyBest(kind, period)
        if best > 0 then
            self:ReplySoon(2, 6, function()
                Say(self, kind, period, best)
            end)
        end
    end
end

MF:On("TFL_SYNC", MF.RequestBounty)
MF:On("TFL_SYNC", MF.AnnounceMyBounties)

-- A daily is per faction, so the other side's entries are a different
-- contest and must not land in this one. The weekly and monthly are the
-- whole realm.
-- One place to take a score in, whoever is carrying it.
local function Take(self, holder, kind, period, weight, side, answering)
    if not SPAN[kind] then return end
    period = tonumber(period)
    local now = self:BountyPeriod(kind)
    if not period or period > now or period <= now - KEEP_PERIODS then return end
    if not holder or holder == "" then return end
    if kind == "day" and side and side ~= self:MySide() then return end
    if not self:AnglerCounts(holder) then return end -- Eligibility.lua
    local _, id = self:Bounty(kind, period)
    -- A score for a different fish is not a score in this contest. The
    -- sender has to say which, and one too old to say is taken at its
    -- word: refusing those would empty the standings of everybody who
    -- has not updated yet, which looks far more broken than it is.
    answering = tonumber(answering)
    if answering and id and answering ~= id then return end
    local w = self:DecodeWeight(weight)
    -- A tally has no weight ceiling to check against; a fish does.
    if kind ~= "month" and id and w > self:MaxWeight(id) then return end
    local scores = Scores(self, kind, period)
    holder = BountyIdentity(self, holder) == BountyIdentity(self, self.me) and self.me or self:FullName(self:WhisperName(holder))
    for name in pairs(scores) do
        if BountyIdentity(self, name) == BountyIdentity(self, holder) then holder = name break end
    end
    if w > (scores[holder] or 0) then
        scores[holder] = w
        self:RefreshJournal()
    end
end

function MF.handlers.BNTY2(self, sender, kind, period, weight, side, answering)
    Take(self, sender, kind, period, weight, side, answering)
end

-- Somebody else's standing, passed on
--
-- BNTY2 says only "this is mine", so the board could never outlive the
-- people on it: whoever logged off took their entry with them for
-- anybody who had not already heard it. This carries the holder, the
-- way a record always has, so a client that was away can be told who
-- stands where by whoever was there at the time.
function MF.handlers.BNTY3(self, sender, kind, period, holder, weight, side, answering)
    Take(self, holder, kind, period, weight, side, answering)
    -- Somebody has answered for this period, so whoever else was about
    -- to need not.
    self:MarkAnswered(Topic(kind, period))
end

-- Answering with the whole board, not just your own line
--
-- Whoever answers sends everything they hold for that period, so one
-- reply is enough and the rest of the realm stays quiet - which is why
-- it goes through ReplyOnce rather than ReplySoon. Without it, twenty
-- clients each sending twenty entries is four hundred messages for one
-- question.
function MF.handlers.BREQ2(self, sender, kind, period)
    if not SPAN[kind] then return end
    period = tonumber(period)
    local now = self:BountyPeriod(kind)
    -- This period or the one before it: the finished one is how a client
    -- that was away learns who won while it was.
    if not period or period > now or period <= now - KEEP_PERIODS then return end
    local scores = Scores(self, kind, period)
    if not next(scores) then return end
    self:ReplyOnce(Topic(kind, period), 1, 4, function()
        local _, id = self:Bounty(kind, period)
        for holder, w in pairs(Scores(self, kind, period)) do
            self:SendChannel("BNTY3", kind, period, holder,
                self:EncodeWeight(w), self:MySide(), id)
        end
    end)
end

MF:Command("bounty", "Progress", "/tfl bounty - the bounties on offer", function(self)
    for _, kind in ipairs(MF.BOUNTY_KINDS) do
        local label = kind == "day" and "Today" or (kind == "week" and "This week" or "This month")
        self:Print(("%s: %s. Resets in %s."):format(
            label, self:BountyText(kind), self:FormatSpan(self:BountyTimeLeft(kind))))
        local standings = self:BountyStandings(kind)
        if #standings == 0 then
            print("  No entries yet.")
        else
            local place, last = 0, nil
            for i = 1, math.min(3, #standings) do
                local s = standings[i]
                if s.weight ~= last then place, last = i, s.weight end
                print(("  %d. %s - %s"):format(place, self:ShortName(s.name),
                    self:BountyScoreText(kind, s.weight, nil, s.specimen)))
            end
        end
    end
end)

------------------------------------------------------------------------
-- The Stranglethorn Fishing Extravaganza
--
-- Riggle Bassbait's contest in Booty Bay. It is the one fishing thing in
-- the week that happens whether you turn up or not, and missing it because
-- you were in a different zone is the sort of thing an addon should stop
-- happening to you.
--
-- Everything about when it runs lives in this one table, because it is the
-- part most likely to be wrong: Forever is Classic+, and a server that
-- changes a quest chain can change a contest time. Nothing else in the file
-- needs to know.
--
-- The hour comes from the realm, never the machine. A weekly event at 2pm
-- is 2pm where the server lives, and an angler three time zones away must
-- be told the same thing as everyone else.
------------------------------------------------------------------------

MF.EXTRAVAGANZA = {
    weekday = 1,    -- 1 = Sunday, as the game counts them
    hour = 14,      -- realm time
    runs = 120,     -- minutes
    remind = 15,    -- minutes of warning
}

local function RealmNow()
    local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
        and C_DateAndTime.GetCurrentCalendarTime()
    if type(t) == "table" and t.weekday and t.hour then
        return t.weekday, t.hour, t.minute or 0
    end
    -- Older clients give the realm's clock but not its calendar, so the day
    -- has to come from the machine. Wrong only for anyone whose own date has
    -- rolled over and the realm's hasn't.
    local hour, minute = GetGameTime()
    return (tonumber(date("%w")) or 0) + 1, hour or 0, minute or 0
end

-- Returns running, seconds (left if running, until the next if not).
function MF:ExtravaganzaState()
    local e = self.EXTRAVAGANZA
    local day, hour, minute = RealmNow()
    local now = (day - 1) * 1440 + hour * 60 + minute
    local opens = (e.weekday - 1) * 1440 + e.hour * 60
    if now >= opens and now < opens + e.runs then
        return true, (opens + e.runs - now) * 60
    end
    local wait = opens - now
    if wait <= 0 then wait = wait + 7 * 1440 end
    return false, wait * 60
end

function MF:ExtravaganzaLine()
    local running, secs = self:ExtravaganzaState()
    if running then
        return ("|cffff8000The Fishing Extravaganza is running in Booty Bay|r - %s left.")
            :format(self:FormatClock(secs))
    end
    if secs < 86400 then
        return ("The Fishing Extravaganza starts in Booty Bay in %s."):format(self:FormatClock(secs))
    end
    return ("The Fishing Extravaganza is %d days away."):format(math.floor(secs / 86400 + 0.5))
end

-- Said once per contest, not once per tick.
local told, toldStart = nil, nil

MF:OnTick(function(self)
    if not self.db.settings.eventReminders then return end
    local e = self.EXTRAVAGANZA
    local running, secs = self:ExtravaganzaState()
    local week = math.floor(GetServerTime() / 604800)

    if running then
        if toldStart ~= week then
            toldStart = week
            self:Print("|cffff8000The Fishing Extravaganza has started|r - Riggle Bassbait is "
                .. "taking entries in Booty Bay.")
            self:Toast([[Interface\Icons\Trade_Fishing]], "EXTRAVAGANZA", "Booty Bay",
                ("Running for %s"):format(self:FormatClock(secs)), 1, 0.5, 0, SOUNDKIT.RAID_WARNING)
        end
        return
    end
    if secs <= e.remind * 60 and told ~= week then
        told = week
        self:Print(("|cffffd100%s|r Get to Stranglethorn."):format(self:ExtravaganzaLine()))
    end
end)

MF:Command({ "contest", "extravaganza" }, "Progress",
    "/tfl contest - when the Booty Bay fishing contest runs", function(self)
        self:Print(self:ExtravaganzaLine())
        local e = self.EXTRAVAGANZA
        print(("  |cff858585Every %s at %d:00 realm time, for %d minutes.|r"):format(
            date("%A", time({ year = 2026, month = 11, day = 1 + (e.weekday - 1), hour = 12 })),
            e.hour, e.runs))
    end)
