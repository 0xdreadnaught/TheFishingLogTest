-- Profile: Angler's Journal, XP and ranks, and the profile codec.
--
-- The beta client wrote saved variables and never loaded them, so anglers
-- used to keep copies of each other's profiles and hand them back at login.
-- Saving has worked since launch and that peer backup is gone; the codec
-- stays, for /tfl export, /tfl import and the save macros.
local _, MF = ...

-- Two ladders, and a date
--
-- Six ranks topping out at 20,000 XP was about thirty hours of fishing, half
-- of it spent in the final rank with nothing happening. The new one runs Fry
-- to Legend of the Deep over twenty titles, starting quick - promoted inside
-- your first twenty minutes - and slowing honestly, each step about half
-- again as long as the last.
--
-- It doesn't start today. Anglers who have already made Legend of the Deep
-- keep it until the wipe takes it, rather than opening the addon one evening
-- to find themselves demoted to Trophy Hunter by a patch. On 4 November
-- every character goes with the realm anyway, so the new ladder begins where
-- everybody begins: at nothing.
--
-- The hour comes from the server rather than the machine, so every client on
-- the realm turns over together whatever their clock says.
-- The wipe (see MF.FRESH_START in Core.lua). Not a date of its own: the
-- ladder turns over when the realm does, and two dates that must agree
-- are one date too many.

local BETA = {
    { xp = 0,     name = "Minnow" },
    { xp = 300,   name = "Guppy" },
    { xp = 1000,  name = "Angler" },
    { xp = 3000,  name = "Seasoned Angler" },
    { xp = 8000,  name = "Master Angler" },
    { xp = 20000, name = "Legend of the Deep" },
}

local LIVE = {
    { xp = 0,      name = "Fry" },
    { xp = 100,    name = "Minnow" },
    { xp = 300,    name = "Guppy" },
    { xp = 700,    name = "Bait Thief" },
    { xp = 1400,   name = "Shore Angler" },
    { xp = 2600,   name = "Angler" },
    { xp = 4500,   name = "Keen Angler" },
    { xp = 7500,   name = "Seasoned Angler" },
    { xp = 12000,  name = "Old Hand" },
    { xp = 19000,  name = "Master Angler" },
    { xp = 29000,  name = "Trophy Hunter" },
    { xp = 44000,  name = "Deep Water Angler" },
    { xp = 65000,  name = "Netmaster" },
    { xp = 94000,  name = "Tidemaster" },
    { xp = 133000, name = "Leviathan Hunter" },
    { xp = 185000, name = "Abyssal Angler" },
    { xp = 255000, name = "Stormfisher" },
    { xp = 345000, name = "Fathomless" },
    { xp = 465000, name = "Myth of the Deep" },
    { xp = 620000, name = "Legend of the Deep" },
}

-- Which ladder is in force. Read fresh every time rather than chosen at
-- load, so a client left logged in over the turnover follows it across
-- without a reload.
function MF:Ladder()
    return (GetServerTime() >= self.FRESH_START) and LIVE or BETA
end

local XP_JUNK, XP_NEW_SPECIES, XP_SPECIMEN = 1, 25, 100
local XP_CATCH_BASE, XP_CATCH_MAX_BONUS = 5, 20 -- plus 1 XP per 2 lb, capped

------------------------------------------------------------------------
-- Ranks
------------------------------------------------------------------------

-- Returns index, name, xp needed for the next rank (nil at max).
function MF:RankFor(xp)
    local ranks = self:Ladder()
    local idx = 1
    for i, r in ipairs(ranks) do
        if xp >= r.xp then idx = i end
    end
    local nextRank = ranks[idx + 1]
    return idx, ranks[idx].name, nextRank and nextRank.xp
end

function MF:RankName(idx)
    local ranks = self:Ladder()
    local r = ranks[tonumber(idx) or 1]
    return r and r.name or ranks[1].name
end

-- A rank index means whatever the sender's ladder said it meant, and this
-- ladder is going to keep changing. An older client handed index 17 would
-- find nothing there and call a Stormfisher a Fry. XP doesn't move, so when
-- it's on the message we work the rank out from our own table and ignore
-- theirs - receivers deciding with their own data, the same as records.
--
-- Clients older than today send no XP at all, so their index is used as it
-- always was. They're the ones who'll read a high rank wrongly and nothing
-- shipped now can reach back and fix that; what this buys is every change
-- made after today.
function MF:RankFromWire(rank, xp)
    xp = tonumber(xp)
    if xp then return (self:RankFor(xp)) end
    return tonumber(rank) or 1
end

function MF:MyRank()
    return (self:RankFor(self.cdb.profile.xp))
end

-- The profile changed: back it up to peers and macros when they next run.
function MF:MarkProfileChanged()
    self.macroDirty = true
end

function MF:AddXP(amount)
    if amount <= 0 then return end
    self:EnsureSeason()
    local p = self.cdb.profile
    local old = self:RankFor(p.xp)
    p.xp = p.xp + amount
    p.season = p.season or self:SeasonID()
    p.seasonXP = (p.seasonXP or 0) + amount
    p.updated = GetServerTime()
    self:MarkProfileChanged()
    local new, name = self:RankFor(p.xp)
    self:Debug(("+%d XP (%d)"):format(amount, p.xp))
    if new > old then
        self:Print(("|cffffd100Rank up! You are now a %s.|r"):format(name))
        self:Toast("Interface\\Icons\\Trade_Fishing", "RANK UP!", name,
            ("%d XP"):format(p.xp), 0.4, 0.8, 1, SOUNDKIT.UI_EPICLOOT_TOAST)
    end
end

MF:Command("rank", "Progress", "/tfl rank - your angler rank", function(self)
    local xp = self.cdb.profile.xp
    local _, name, nextXP = self:RankFor(xp)
    if nextXP then
        self:Print(("%s - %d XP (%d to next rank)"):format(name, xp, nextXP - xp))
    else
        self:Print(("%s - %d XP (max rank)"):format(name, xp))
    end
end)

------------------------------------------------------------------------
-- Journal + progress from a catch
------------------------------------------------------------------------

function MF:JournalEntry(itemID)
    return self.cdb.profile.journal[itemID]
end

------------------------------------------------------------------------
-- Where you've caught each fish
--
-- One number per fish: a bit per entry in that fish's native zone list, so
-- it costs a couple of characters in the save macros. Entries from before
-- 0.4.1 have no zones recorded; those count as caught everywhere they live,
-- so nobody's journal appears to empty itself.
------------------------------------------------------------------------

local function ZoneIndex(self, itemID, zone)
    local f = self.FISH[itemID]
    if not f or not f.zones or not zone then return end
    for i, z in ipairs(f.zones) do
        if z == zone then return i end
    end
end

-- Where a fish sits in its own native zone list (nil if it isn't native there).
function MF:ZoneIndexFor(itemID, zone)
    return ZoneIndex(self, itemID, zone)
end

-- Two records of the same fish, kept apart: every zone either of them knows.
function MF:MergeZoneMasks(a, b)
    a, b = a or 0, b or 0
    local merged, bit = 0, 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then merged = merged + bit end
        a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return merged
end

function MF:MarkCaughtIn(mask, itemID, zone)
    mask = mask or 0
    local index = ZoneIndex(self, itemID, zone)
    if not index then return mask end
    local bit = 2 ^ (index - 1)
    if math.floor(mask / bit) % 2 == 0 then mask = mask + bit end
    return mask
end

-- Have we caught this fish in this zone? (Entry, its zone-list index.)
function MF:CaughtInZone(j, index)
    if not j then return false end
    if (j.z or 0) == 0 then return true end -- recorded before zones were tracked
    return math.floor(j.z / 2 ^ (index - 1)) % 2 == 1
end

-- Everything a real (non-test) catch feeds into.
function MF:OnCatchProgress(c)
    if c.test then return end
    self:EnsureSeason()
    local p = self.cdb.profile
    p.value = (p.value or 0) + (self:FishValue(c.itemID) or 0)
    if c.junk then
        self:AddXP(XP_JUNK)
        return
    end

    local journal = p.journal
    local j = journal[c.itemID]
    local isNew = not j
    if isNew then
        j = { c = 0, b = 0, s = 0 }
        -- Only a genuinely new entry has a known first catch. An old or
        -- recovered journal must never acquire today's date as its origin.
        j.firstCatch={at=c.at or GetServerTime(),key=c.spot.key,name=c.spot.name,
            map=c.spot.mapID,x=c.spot.x,y=c.spot.y}
        journal[c.itemID] = j
    end
    j.c = j.c + 1
    j.b = math.max(j.b, c.weight)
    if c.specimen then
        j.s = math.max(j.s, c.weight)
        p.latestSpecimen = { id = c.itemID, weight = c.weight, at = c.at or GetServerTime(), spot = c.spot.name }
    end
    j.z = self:MarkCaughtIn(j.z, c.itemID, c.zone)
    -- What this fish has weighed in this particular water. The bitmask above
    -- only remembers whether you've caught one here; the journal used to show
    -- your best from anywhere beside it, which read like a lie.
    if c.zone and c.zone ~= "" then
        local byZone = self.cdb.caughtIn[c.itemID] or {}
        self.cdb.caughtIn[c.itemID] = byZone
        local here = byZone[c.zone] or { c = 0, b = 0, s = 0 }
        byZone[c.zone] = here
        here.c = here.c + 1
        if c.weight > here.b then
            here.b, here.spot = c.weight, c.spot and c.spot.key or nil
        end
        if c.specimen then here.s = math.max(here.s or 0, c.weight) end
    end
    -- Forever's new zones and new fish aren't in the fish data yet; note what
    -- turns up so it can be reported and added (see /tfl report).
    if c.zone and c.zone ~= "" and (not self:ZoneCovered(c.zone) or not self.FISH[c.itemID]) then
        local zone = self.db.newZones[c.zone] or {}
        self.db.newZones[c.zone] = zone
        zone[c.itemID] = (zone[c.itemID] or 0) + 1
    end

    local xp = XP_CATCH_BASE + math.min(XP_CATCH_MAX_BONUS, math.floor(c.weight / 2))
    if isNew then
        self:Print(("New journal entry: |cffffd100%s|r! +%d XP"):format(c.name, XP_NEW_SPECIES))
        xp = xp + XP_NEW_SPECIES
    end
    if c.specimen then xp = xp + XP_SPECIMEN end

    self:CheckPersonalBest(c)
    xp = xp + self:CheckSpotRecord(c)
    xp = xp + self:CheckBounty(c)
    self:AddXP(xp)
    self:RefreshJournal()
end

MF:On("TFL_CATCH", MF.OnCatchProgress)

------------------------------------------------------------------------
-- Codec: one text format for macros, /tfl export and peer backups.
--
--   "1:<xp>:<updated>:<journal>:<records>:<champion until>"
--     journal: <id>.<count>.<best>.<specimen>,...
--     records: <area>.<map>.<id>.<weight>.<time>.<specimen>,...  (spot
--              records you hold, so they survive a relog; optional, and
--              ignored by versions before 0.3.3)
--     champion until: server time the Tournament Champion title runs out
--              (0 if none; ignored by versions before 0.4.0)
--     optional tenth field: last settled daily.weekly.monthly reward periods
--              (base 36); older clients ignore it, current merges keep maxima.
--
-- Base 36 and lowercase so it survives the slash command, with weights in
-- hundredths of a pound. DecodeProfile also reads the pre-0.3.1 peer backup
-- format ("xp;id,count,best,specimen;...") that older clients still relay.
------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function B36(n)
    n = math.floor(n or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = DIGITS:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

local function FromB36(s) return tonumber(s or "", 36) end

MF.MAX_SAVED_RECORDS = 15 -- heaviest first; ~26 characters each in the macros

local function EncodeRecords(self, limit)
    local entries = {}
    if limit <= 0 then return "" end
    for _, r in ipairs(self:MyRecords(limit)) do
        local area = tonumber(r.key:match("^a(%d+)$"))
        if area then -- grid-cell spots aren't worth the space
            entries[#entries + 1] = table.concat({ B36(area), B36(r.mapID), B36(r.id),
                B36(MF.Hundredths(r.w)), B36(r.t), r.s and "1" or "0" }, ".")
        end
    end
    return table.concat(entries, ",")
end

-- recordLimit: how many of our spot records to include. Macros are tight on
-- space and pass a limit; everything else keeps them all.
function MF:EncodeProfile(p, recordLimit)
    recordLimit = recordLimit or math.huge
    local ids = {}
    for id in pairs(p.journal) do ids[#ids + 1] = id end
    table.sort(ids)
    local entries = {}
    for _, id in ipairs(ids) do
        local j = p.journal[id]
        entries[#entries + 1] = table.concat({
            B36(id), B36(j.c), B36(MF.Hundredths(j.b)), B36(MF.Hundredths(j.s)), B36(j.z or 0) }, ".")
    end
    local fields = { "1", B36(p.xp), B36(p.updated), table.concat(entries, ","),
        EncodeRecords(self, recordLimit), B36(p.champUntil or 0),
        B36(p.value or 0), B36(p.season or 0), B36(p.seasonXP or 0) }
    if p.bountyRewardThrough then
        local claimed = p.bountyRewardThrough
        fields[10] = B36(claimed.day) .. "." .. B36(claimed.week) .. "." .. B36(claimed.month)
    end
    local data=table.concat(fields,":")
    if GetServerTime()>=self.FRESH_START and self.cdb.launchReset==self.FRESH_START then
        return "2:" .. self:Pack36(self.FRESH_START) .. ":" .. data
    end
    return data
end

local function DecodeV1(str)
    local version, xp, updated, entries, recordText, champUntil, value, season, seasonXP, rewardText =
        strsplit(":", str)
    if version ~= "1" or not FromB36(xp) then return end
    local journal = {}
    for entry in (entries or ""):gmatch("[^,]+") do
        local id, c, b, s, z = strsplit(".", entry)
        id = FromB36(id)
        if id then
            journal[id] = { c = FromB36(c) or 0, b = (FromB36(b) or 0) / 100,
                s = (FromB36(s) or 0) / 100, z = FromB36(z) or 0 }
        end
    end
    local records = {}
    for entry in (recordText or ""):gmatch("[^,]+") do
        local area, mapID, id, w, t, s = strsplit(".", entry)
        area, id = FromB36(area), FromB36(id)
        if area and id then
            records[#records + 1] = { key = "a" .. area, mapID = FromB36(mapID) or 0, id = id,
                w = (FromB36(w) or 0) / 100, t = FromB36(t) or 0, s = s == "1" }
        end
    end
    local rewards
    if rewardText and rewardText ~= "" then
        local day, week, month = strsplit(".", rewardText)
        rewards = { day = FromB36(day), week = FromB36(week), month = FromB36(month) }
    end
    return FromB36(xp), journal, FromB36(updated) or 0, records, FromB36(champUntil) or 0,
        FromB36(value) or 0, FromB36(season), FromB36(seasonXP) or 0, rewards
end

local function DecodeLegacy(str)
    local fields = { strsplit(";", str) }
    local xp = tonumber(fields[1])
    if not xp then return end
    local journal = {}
    for i = 2, #fields do
        local id, c, b, s = strsplit(",", fields[i])
        id = tonumber(id)
        if id then
            if id~=id or id<1 or id>2147483647 or id~=math.floor(id) then return end
            journal[id] = { c = tonumber(c) or 0, b = MF:DecodeWeight(b), s = MF:DecodeWeight(s) }
        end
    end
    return xp, journal, 0
end

-- Returns xp, journal, updated - or nil if the text isn't a profile.
function MF:IsLiveProfileSave(str)
    if type(str)~="string" then return false end
    str=str:gsub("%s",""):lower()
    local prefix="2:" .. self:Pack36(self.FRESH_START) .. ":"
    return str:sub(1,#prefix)==prefix
end

function MF:DecodeProfile(str)
    if type(str)~="string" or #str>65536 then return end
    str = (str or ""):gsub("%s", ""):lower()
    if str:sub(1,2)=="2:" then
        local epoch,data=str:match("^2:([%da-z]+):(.*)$")
        if not epoch or epoch~=self:Pack36(self.FRESH_START) then return end
        str=data
    end
    local xp,journal,updated,records,champ,value,season,seasonXP,rewards
    if str:find(":", 1, true) then
        if str:find("[^%da-z:.,]") then return end
        for field in str:gmatch("[%da-z]+") do if #field>10 then return end end
        xp,journal,updated,records,champ,value,season,seasonXP,rewards=DecodeV1(str)
    else xp,journal,updated=DecodeLegacy(str) end
    local function Number(n)
        return type(n)=="number" and n==n and n>=0 and n<=9007199254740991
    end
    if not Number(xp) then return end
    for _,n in pairs({updated,champ,value,season,seasonXP}) do if not Number(n) then return end end
    for id,j in pairs(journal) do
        if not Number(id) or id<1 or id>2147483647 or id~=math.floor(id) then return end
        for _,field in ipairs({"c","b","s","z"}) do
            local n=j[field] or 0
            if not Number(n) or (field=="z" and n~=math.floor(n)) then return end
        end
    end
    for _,r in ipairs(records or {}) do
        for _,field in ipairs({"id","mapID","w","t"}) do if not Number(r[field]) then return end end
    end
    for _,n in pairs(rewards or {}) do if not Number(n) then return end end
    return xp,journal,updated,records,champ,value,season,seasonXP,rewards
end

------------------------------------------------------------------------
-- Merging (macros, imports and peer backups all come through here)
------------------------------------------------------------------------

-- Merge never loses progress: take the best of both. records (optional) are
-- spot records we hold, restored as our own.
function MF:MergeProfile(xp, journal, updated, records, champUntil, value, season, seasonXP, rewardThrough)
    if GetServerTime()>=self.FRESH_START and (updated or 0)<self.FRESH_START then return end
    for _, r in ipairs(records or {}) do
        self:MergeRecord(r.key, r.mapID, r.id, r.w, self.me, r.t, r.s)
    end
    local p = self.cdb.profile
    if type(rewardThrough) == "table" then
        p.bountyRewardThrough = p.bountyRewardThrough or {}
        for _, kind in ipairs(self.BOUNTY_KINDS) do
            local period = rewardThrough[kind]
            if type(period) == "number" and period > 0 and period == math.floor(period)
                and period < self:BountyPeriod(kind) then
                p.bountyRewardThrough[kind] = math.max(p.bountyRewardThrough[kind] or 0, period)
            end
        end
    end
    p.champUntil = math.max(p.champUntil or 0, champUntil or 0)
    p.value = math.max(p.value or 0, value or 0)
    -- Season XP only carries over within the same season.
    if season and season == self:SeasonID() then
        p.season = season
        p.seasonXP = math.max(p.seasonXP or 0, seasonXP or 0)
    end
    p.xp = math.max(p.xp, xp)
    for id, other in pairs(journal) do
        local mine = p.journal[id]
        if not mine then
            p.journal[id] = other
        else
            mine.c = math.max(mine.c, other.c)
            mine.b = math.max(mine.b, other.b)
            mine.s = math.max(mine.s, other.s)
            -- Zones are a bitmask: keep every zone either copy knows about.
            local a, b2, merged, bit = mine.z or 0, other.z or 0, 0, 1
            while a > 0 or b2 > 0 do
                if a % 2 == 1 or b2 % 2 == 1 then merged = merged + bit end
                a, b2, bit = math.floor(a / 2), math.floor(b2 / 2), bit * 2
            end
            mine.z = merged
        end
    end
    p.updated = math.max(p.updated, updated or 0)
    self:MarkProfileChanged()
    self:RefreshJournal()
end
