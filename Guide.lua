-- Guide: where fishing skill actually comes up, learned rather than looked up.
--
-- Forever is Classic+ on a client that doesn't behave like stock Classic, with
-- zones the vanilla data never covered. A levelling guide copied from a wiki
-- would be plausible and quite possibly wrong, and wrong is worse than absent
-- in an addon people trust about numbers.
--
-- So nothing is assumed. Every time your fishing skill goes up we write down
-- where you were and what skill you were at, and anglers swap those notes the
-- same way they swap records. What comes out the other end is the real curve
-- for this server, observed rather than asserted: "anglers have gained skill
-- here between 1 and 68."
--
-- No interface yet. This half only collects, because the collecting has a
-- deadline the guide doesn't - the beta caps at 225 and wipes on 4 November,
-- so the 1-225 half of the curve can only be watched now. Zones survive a
-- wipe even though characters don't, which is what makes this worth gathering
-- before the slate is cleaned.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

local SKILL_CEILING = 300    -- nothing above this is a fishing skill
local ASK_COOLDOWN = 900     -- seconds before asking the realm again

------------------------------------------------------------------------
-- Watching
------------------------------------------------------------------------

-- The skill you were at when you earned the gain, not the one you landed on:
-- a zone that takes you from 60 to 61 is a zone worth fishing at 60.
function MF:NoteSkillUp(atSkill, mapID)
    mapID = mapID or self:MapID()
    if not mapID or mapID == 0 then return end
    if not atSkill or atSkill < 1 or atSkill > SKILL_CEILING then return end

    local own = self:OwnSkillUps()
    local seen = own[mapID]
    if not seen then
        seen = { lo = atSkill, hi = atSkill, n = 0 }
        own[mapID] = seen
    end
    if atSkill < seen.lo then seen.lo = atSkill end
    if atSkill > seen.hi then seen.hi = atSkill end
    seen.n = seen.n + 1
    self:Debug(("skill up at %d in map %d"):format(atSkill, mapID))
end

-- CHAT_MSG_SKILL fires for every profession, so rather than read the message
-- we re-read the fishing rank and act only if that is what moved. Nothing to
-- translate, and nothing to get wrong on a client we keep being surprised by.
local lastRank

local function Check(self, mapID)
    self:InvalidateSkill()
    local rank = self:FishingSkill()
    if not rank then return end
    local before = lastRank
    lastRank = rank
    if before and rank > before then
        self:NoteSkillUp(before, mapID)
    end
end

MF:On("CHAT_MSG_SKILL", function(self) Check(self) end)

-- And again on every catch, because a gain can only arrive with one. This
-- isn't belt and braces for its own sake: CHAT_MSG_SKILL is an event we
-- can't verify on this client until someone below the cap goes fishing,
-- and the window for collecting any of this closes on 4 November. A second
-- look costs nothing and the comparison is idempotent - whichever notices
-- first, the other finds the rank already where it left it.
MF:On("TFL_CATCH", function(self, c)
    if c.test then return end
    Check(self, c.spot and c.spot.mapID)
end)

-- Learning a rank from a trainer or the Booty Bay book raises the ceiling
-- rather than the rank, so it can't be mistaken for a gain. Starting the
-- count at login only costs us a player's very first catch of the session.
MF:On("TFL_LOGIN", function(self)
    lastRank = self:FishingSkill()
end)

------------------------------------------------------------------------
-- Swapping notes
--
-- One angler sees their own levelling and no one else's, which is a thin
-- curve and a slow one. These travel like records do: ask once in a while,
-- one angler answers, everybody widens what they hold. Ranges only ever
-- widen, so it doesn't matter who hears what in which order.
------------------------------------------------------------------------

local lastAsk = -math.huge

-- What other anglers told us is kept per angler, apart from what we saw.
-- Ranges only widen, so a single merged range was one bad message away from
-- reading 1-300 everywhere for good. Only our own notes are passed on, and a
-- reported range is believed once two anglers agree on it.
local MAX_HEARD = 30 -- anglers remembered per map

-- Before 1.0.5 every reply was folded into the receiver's own notes, so what
-- each angler held - and passed on as theirs - was the same realm-wide merge.
-- That merge can't be pulled apart again. It is kept as a baseline we go on
-- believing but never pass on, and our own notes start clean from here, so
-- what we share really is only what we saw.
local SPLIT = 1
local OLD = "~older versions" -- every report without the own-notes marker
local OWN_MARK = "o"          -- first entry of a reply holding only own notes

local function Split(self)
    local db = self.db
    if db.skillUpsSplit == SPLIT then return end
    local base = db.skillUpsBaseline or {}
    for mapID, r in pairs(db.skillUps or {}) do
        local b = base[mapID]
        if not b then
            base[mapID] = { lo = r.lo, hi = r.hi, n = r.n }
        else
            b.lo, b.hi = math.min(b.lo, r.lo), math.max(b.hi, r.hi)
            b.n = math.max(b.n or 0, r.n or 0)
        end
    end
    db.skillUpsBaseline, db.skillUps = base, {}
    -- Everything heard so far came from older versions: copies of one merge.
    db.skillUpsHeard = {}
    db.skillUpsSplit = SPLIT
end

function MF:OwnSkillUps()
    Split(self)
    return self.db.skillUps
end

local function Heard(self)
    Split(self)
    self.db.skillUpsHeard = self.db.skillUpsHeard or {}
    return self.db.skillUpsHeard
end

-- { lo, hi, n } for a map, or nil: ours and the pre-1.0.5 baseline, widened
-- by reports from at least two independent sources.
function MF:SkillUpRange(mapID)
    local mine = self:OwnSkillUps()[mapID]
    local base = self.db.skillUpsBaseline and self.db.skillUpsBaseline[mapID]
    local own
    if mine and base then
        own = { lo = math.min(mine.lo, base.lo), hi = math.max(mine.hi, base.hi),
            n = (base.n or 0) + (mine.n or 0) }
    else
        own = mine or base
    end
    local los, his, ns, n = {}, {}, {}, own and own.n or 0
    for _, r in pairs(Heard(self)[mapID] or {}) do
        los[#los + 1], his[#his + 1], ns[#ns + 1] = r.lo, r.hi, r.n or 1
    end
    local lo, hi = own and own.lo, own and own.hi
    if #los >= 2 then
        local down = function(a, b) return a > b end
        table.sort(los)
        table.sort(his, down)
        table.sort(ns, down)
        lo, hi = math.min(lo or los[2], los[2]), math.max(hi or his[2], his[2])
        -- The count is corroborated the same way, so one report can't inflate it.
        n = math.max(n, ns[2])
    end
    if not lo then return nil end
    return { lo = lo, hi = hi, n = n }
end

-- Older versions skip the marker (it isn't a map number) and read the rest.
local function Pack(self)
    local out = {}
    for mapID, seen in pairs(self:OwnSkillUps()) do
        out[#out + 1] = ("%d,%d,%d,%d"):format(mapID, seen.lo, seen.hi, math.min(seen.n, 9999))
    end
    if #out == 0 then return "" end
    return OWN_MARK .. ";" .. table.concat(out, ";")
end

function MF:RequestCurve(force)
    if not force and GetTime() - lastAsk < ASK_COOLDOWN then return end
    lastAsk = GetTime()
    self:SendWide("SKREQ")
end

-- Everyone answers, with their own notes only: one answer can no longer
-- stand in for the rest, because nobody relays anybody else's. A note is
-- one short message, and each asker is answered at most every few minutes.
local REPLY_COOLDOWN = 300
local repliedTo = {}

function MF.handlers.SKREQ(self, sender)
    local who = self:AnglerKey(sender)
    if who == "" or self:IsMe(sender) then return end
    if GetTime() - (repliedTo[who] or -math.huge) < REPLY_COOLDOWN then return end
    repliedTo[who] = GetTime()
    self:ReplySoon(2, 12, function()
        local packed = Pack(self)
        if packed ~= "" then self:SendWide("SKUP", packed) end
    end)
end

function MF.handlers.SKUP(self, sender, packed)
    local who = self:AnglerKey(sender)
    if who == "" or self:IsMe(sender) then return end
    packed = packed or ""
    -- Without the marker this is an older version passing on the realm-wide
    -- merge. Every such angler holds the same copy, so together they count
    -- as one source: the latest of them replaces the last.
    if packed:sub(1, #OWN_MARK + 1) == OWN_MARK .. ";" then
        packed = packed:sub(#OWN_MARK + 2)
    else
        who = OLD
    end
    local learned = 0
    local heard = Heard(self)
    for entry in packed:gmatch("[^;]+") do
        local mapID, lo, hi, n = strsplit(",", entry)
        mapID, lo, hi, n = tonumber(mapID), tonumber(lo), tonumber(hi), tonumber(n)
        if mapID and lo and hi and mapID > 0 and mapID<=3000 and mapID==math.floor(mapID)
            and lo >= 1 and lo <= hi and hi <= SKILL_CEILING and lo==math.floor(lo) and hi==math.floor(hi)
            and (not n or (n>=1 and n<=9999 and n==math.floor(n))) then
            local byAngler = heard[mapID] or {}
            heard[mapID] = byAngler
            if not byAngler[who] then
                local count, oldest = 0, nil
                for k, r in pairs(byAngler) do
                    count = count + 1
                    if not oldest or (r.at or 0) < (byAngler[oldest].at or 0) then oldest = k end
                end
                if count >= MAX_HEARD and oldest then byAngler[oldest] = nil end
                learned = learned + 1
            end
            -- Their latest word replaces their last; it never adds to it.
            byAngler[who] = { lo = lo, hi = hi, n = n or 1, at = GetServerTime() }
        end
    end
    if learned > 0 then
        self:Debug(("curve from %s: %d widened"):format(self:ShortName(sender), learned))
    end
end

MF:On("TFL_SYNC", function(self) self:RequestCurve() end)

------------------------------------------------------------------------
-- Looking at what we have
------------------------------------------------------------------------

-- Every zone we know gains in, lowest first: { mapID, name, lo, hi, n }.
function MF:SkillCurve()
    local list, maps = {}, {}
    for mapID in pairs(self:OwnSkillUps()) do maps[mapID] = true end
    for mapID in pairs(self.db.skillUpsBaseline or {}) do maps[mapID] = true end
    for mapID in pairs(Heard(self)) do maps[mapID] = true end
    for mapID in pairs(maps) do
        local seen = self:SkillUpRange(mapID)
        if seen then
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
            list[#list + 1] = { mapID = mapID, name = info and info.name or ("map " .. mapID),
                lo = seen.lo, hi = seen.hi, n = seen.n or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.lo ~= b.lo then return a.lo < b.lo end
        return a.hi < b.hi
    end)
    return list
end

MF:Command("curve", "Other", nil, function(self, args)
    if args[1] == "ask" then
        self:Print("Asking the realm where skill comes up...")
        self:RequestCurve(true)
        return
    end
    local list = self:SkillCurve()
    if #list == 0 then
        self:Print("No skill-ups seen yet. Fish somewhere you can still gain, "
            .. "or wait for another angler to share what they've seen.")
        return
    end
    self:Print(("Where fishing skill has been seen to go up (%d %s):"):format(
        #list, #list == 1 and "zone" or "zones"))
    for _, z in ipairs(list) do
        print(("  %-28s %3d - %-3d  |cff858585%d seen|r"):format(z.name, z.lo, z.hi, z.n))
    end
    print("  |cffffd100/tfl curve ask|r swaps notes with everyone online.")
end)
