-- Versioned scoring. Current periods stay on their opening rules; format
-- messages never enter the legacy heaviest/count protocol.
local _, MF = ...
MF.BOUNTY_FORMAT_START = 1792195200 -- 17 October 2026, 00:00 UTC
MF.BOUNTY_TARGET_START = 1792454400 -- 20 October UTC; active periods keep their rules
MF.BOUNTY_CITY_START = 1792800000 -- 24 October 2026 UTC; earlier daily targets stay unchanged
-- Frozen city-water lists from the existing Forever fishing reference.
-- Surrounding-zone coastlines are not city water. Do not read mutable
-- MF.FISH guidance here: later data edits must not reroll a live contest.
local CITY_TARGETS = {
    ["Darnassus"] = {6289,6291,6308},
    ["Ironforge"] = {6289,6291,6308},
    ["Orgrimmar"] = {6289,6291,6308},
    ["Stormwind City"] = {6289,6291,6303,6308,6358,6361},
    ["Thunder Bluff"] = {6289,6291,6308},
    ["Undercity"] = {6289,6291,6308},
}
MF.BOUNTY_FORMATS = {
    day = { "heaviest", "top3" },
    week = { "heaviest", "specimens", "total", "species", "zone", "top3" },
    month = { "count", "specimens", "species", "specimenSpecies" },
}
local SPAN = { day = 86400, week = 604800, month = 2419200 }
-- Does a collection in this period count bloated fish?
local function BloatedCount(self, kind, period)
    return (period or self:BountyPeriod(kind)) * (SPAN[kind] or SPAN.day) >= self.BOUNTY_BLOATED_START
end
MF.BountyCountsBloated = function(self, kind, period) return BloatedCount(self, kind or "day", period) end
local ZONES = { "Ashenvale", "Darkshore", "Hillsbrad Foothills", "Loch Modan", "The Barrens", "Wetlands" }
local DESCRIPTIONS = {
    heaviest = "Heaviest fish", count = "Most caught", specimens = "Most specimens",
    total = "Combined weight", species = "Species collection", zone = "Zone challenge",
    top3 = "Three-fish haul", specimenSpecies = "Specimen collection",
}
-- Fish a modern bounty may name. A new zone's fish must be added here as
-- well as to an era's `add`, or the era names them and this filters them
-- straight back out. Careful: the collection formats (species, zone,
-- specimenSpecies) count any fish on this list, so adding one changes a
-- collection contest already running. Add new fish in the same release as
-- their era, and date the era so it begins after this month's rollover.
-- The order is part of the wire too: a species entry travels as one bit per fish, in this order
-- (see "What an entry is made of" below). Add new fish at the end, never in the middle.
local ORDINARY_ORDER = { 6291, 6303, 6289, 6317, 6522, 6358, 6361, 6308, 6359, 6362,
    21071, 21153, 8365, 4603, 13422, 13754, 13755, 13756, 13758, 13759, 13760,
    13889, 13888, 13893, 13757, 13890, 6360, 1467, 6458, 6299 }
local ORDINARY = {}
for _, id in ipairs(ORDINARY_ORDER) do ORDINARY[id] = true end
-- Bloated fish count in the collections (species, zone, specimen collection) from the first period
-- that opens on or after this, the week after 1.1.4 is out. Earlier periods keep the rules they
-- opened with, so 1.1.3 and 1.1.4 never score the same week differently. They're never a target
-- fish: ORDINARY alone decides those. Move this if 1.1.4 ships later than 3 December.
MF.BOUNTY_BLOATED_START = 1796860800 -- Thursday 10 December 2026, 00:00 UTC (a week's start)
local BLOATED = { [6643] = true, [6645] = true, [6647] = true, [8366] = true, [13881] = true, [13891] = true }
-- A collection entry's bits: the ordinary fish, then the bloated ones. Append only, never reorder.
local COLLECTED_ORDER = {}
for _, id in ipairs(ORDINARY_ORDER) do COLLECTED_ORDER[#COLLECTED_ORDER + 1] = id end
for _, id in ipairs({ 6643, 6645, 6647, 8366, 13881, 13891 }) do COLLECTED_ORDER[#COLLECTED_ORDER + 1] = id end
local originalBounty, originalBest, originalStandings, originalCheck, originalText =
    MF.Bounty, MF.MyBountyBest, MF.BountyStandings, MF.CheckBounty, MF.BountyText
local originalSend, originalRequest = MF.SendChannel, MF.RequestBounty

function MF:BountyFormat(kind, period)
    kind = kind or "day"
    period = period or self:BountyPeriod(kind)
    if not SPAN[kind] or period * SPAN[kind] < self.BOUNTY_FORMAT_START then return kind == "month" and "count" or "heaviest" end
    local pool = self.BOUNTY_FORMATS[kind]
    return pool[self:Hash("bformat1:" .. kind .. ":" .. period) % #pool + 1]
end
local function New(self, kind, period)
    local mode = self:BountyFormat(kind, period)
    return (mode ~= "heaviest" and mode ~= "count")
        or ((period or self:BountyPeriod(kind)) * (SPAN[kind] or 86400) >= self.BOUNTY_TARGET_START), mode
end
function MF:Bounty(kind, period)
    kind = kind or "day"
    local at, id, zone = originalBounty(self, kind, period)
    local modern, mode = New(self, kind, at)
    if self.bountyLegacyScoring and modern then return at, nil, zone end
    if mode == "zone" then zone = ZONES[self:Hash("bchallenge1:" .. at) % #ZONES + 1] end
    if modern then
        local candidates = {}
        -- The era the period opened under, never the clock now: eras are
        -- frozen in Conditions.lua, so fish-data edits cannot reroll these
        -- targets, and a later era with new zones' fish starts at its own
        -- rollover. Every modern period so far opened under era 2.
        -- Quest, contest and bloated fish are absent.
        local city = kind == "day" and at * SPAN.day >= self.BOUNTY_CITY_START and CITY_TARGETS[zone]
        local era = self:BountyEraIndex(at * (SPAN[kind] or SPAN.day))
        for _, candidate in ipairs(city or self:BountyPool(era, kind == "day" and zone or nil)) do
            if ORDINARY[candidate] then candidates[#candidates + 1] = candidate end
        end
        if #candidates > 0 then id = candidates[self:Hash("btarget1:" .. kind .. ":" .. at) % #candidates + 1] end
    end
    return at, id, zone
end
local function Identity(self, name)
    return (self:SplitName(name)):gsub("[%s%-]", ""):lower()
end
local function Board(self, kind, period)
    local _, mode = New(self, kind, period)
    self.db.bountyBoard = self.db.bountyBoard or {}
    local key = kind .. "@" .. mode
    local held = self.db.bountyBoard[key] or {}
    self.db.bountyBoard[key] = held
    local now = self:BountyPeriod(kind)
    for at in pairs(held) do if at < now - 1 then held[at] = nil end end
    held[period] = held[period] or {}
    return held[period]
end
local function Progress(self, kind, period)
    local p = self.cdb.profile
    p.bountyProgress = p.bountyProgress or {}
    local held = p.bountyProgress[kind] or {}
    p.bountyProgress[kind] = held
    for at in pairs(held) do if at < self:BountyPeriod(kind) - 1 then held[at] = nil end end
    held[period] = held[period] or { score = 0, top = {}, species = {} }
    return held[period]
end
function MF:MyBountyBest(kind, period)
    kind = kind or "day" period = period or self:BountyPeriod(kind)
    if not New(self, kind, period) then return originalBest(self, kind, period) end
    return Progress(self, kind, period).score
end
function MF:BountyStandings(kind, period)
    kind = kind or "day" period = period or self:BountyPeriod(kind)
    if not New(self, kind, period) then return originalStandings(self, kind, period) end
    local board = Board(self, kind, period)
    local own = self:MyBountyBest(kind, period)
    if own > 0 then board[Identity(self, self.me)] = { name = self.me, score = own, specimen = self:BountySpecimenStatus(kind,self.me,period,own) } end
    local out = {}
    for _, entry in pairs(board) do out[#out + 1] = { name = entry.name, weight = entry.score, specimen = entry.specimen } end
    table.sort(out, function(a, b) if a.weight ~= b.weight then return a.weight > b.weight end return a.name < b.name end)
    return out
end
-- Infer only above the rounded maximum ordinary roll, allowing every
-- applicable bonus. Never guess within overlapping ranges or for trophies.
function MF:GuaranteedSpecimenWeight(itemID,weight,count)
    count=count or 1
    if count~=1 and count~=3 then return end
    local fish=self.FISH[itemID]
    if not fish or self:TrophyWeight(itemID) or type(weight)~="number"
        or weight~=weight or weight<=0 or weight>self:MaxWeight(itemID)*count then return end
    local multiplier=self.FRENZY_WEIGHT
    if fish.day or fish.night then multiplier=multiplier*self.TIME_BONUS end
    local ceiling=self.RoundWeight(fish.max*multiplier)*count
    if self.Hundredths(weight)>self.Hundredths(ceiling) then return true end
end

function MF:BountySpecimenStatus(kind,holder,period,score)
    period=period or self:BountyPeriod(kind)
    local mode=self:BountyFormat(kind,period)
    if not New(self,kind,period) or (mode~="heaviest" and mode~="top3") then return end
    local own=self:IsMe(holder)
    local entry=own and Progress(self,kind,period) or Board(self,kind,period)[Identity(self,holder)]
    if entry and entry.score==score then
        if entry.specimen~=nil then return entry.specimen end
        if own and mode=="top3" then
            local haul=self:BountyHaul(kind,period)
            if #haul==3 then
                local known=true
                for _,fish in ipairs(haul) do
                    if fish.specimen==true or (fish.specimen==nil and self:GuaranteedSpecimenWeight(select(2,self:Bounty(kind,period)),fish.weight)) then return true end
                    if fish.legacy or fish.specimen==nil then known=false end
                end
                if known then return false end
            end
        end
    end
    local _,id=self:Bounty(kind,period)
    return self:GuaranteedSpecimenWeight(id,score,mode=="top3" and 3 or 1)
end
function MF:BountyScoreText(kind, score, period, specimen)
    local mode = self:BountyFormat(kind, period)
    if (mode=="heaviest" or mode=="top3") and specimen==nil then
        local _,id=self:Bounty(kind,period)
        specimen=self:GuaranteedSpecimenWeight(id,score,mode=="top3" and 3 or 1)
    end
    if mode == "top3" or mode == "total" or mode == "heaviest" then
        return self:Weight(score) .. ((mode=="heaviest" or mode=="top3") and specimen==true
            and "  |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:13:13|t" or "")
    end
    return (mode == "species" or mode == "zone" or mode == "specimenSpecies")
        and (math.floor(score) .. " species") or ("x" .. math.floor(score))
end
function MF:BountyTitle(kind, period)
    local _, id = self:Bounty(kind, period)
    local mode = self:BountyFormat(kind, period)
    local collection = mode == "species" or mode == "zone" or mode == "specimenSpecies"
    return DESCRIPTIONS[mode] .. (collection and "" or (": " .. self:FishName(id)))
end
function MF:BountyIcon(kind, period)
    local mode = self:BountyFormat(kind, period)
    if mode == "species" or mode == "zone" or mode == "specimenSpecies" then
        return "Interface\\Icons\\Trade_Fishing"
    end
    local _, id = self:Bounty(kind, period)
    return self:FishIcon(id)
end
function MF:BountyRule(kind, period)
    local mode = self:BountyFormat(kind, period)
    local rules = {
        top3 = "Your three heaviest target fish are added together. Catch three to enter; better catches replace the lightest.",
        total = "Every eligible target fish adds its weight. Highest combined weight wins.",
        specimens = "Only specimens of the target fish count. Most specimens wins.",
        species = "Each eligible species counts once. Catch the most different species.",
        zone = "Each eligible species caught in the specified zone counts once.",
        specimenSpecies = "Each species with a specimen caught during this bounty counts once.",
        count = "Each target fish counts once. Most caught wins.", heaviest = "Your heaviest eligible target fish counts.",
    }
    if mode == "species" or mode == "zone" or mode == "specimenSpecies" then
        return rules[mode] .. (BloatedCount(self, kind, period) and " Bloated fish count; quest and contest fish don't."
            or " Bloated, quest and contest fish don't count.")
    end
    return rules[mode]
end
function MF:BountyProgressText(kind)
    if self:BountyFormat(kind) == "top3" then
        return math.min(3, #Progress(self, kind, self:BountyPeriod(kind)).top) .. "/3 fish"
    end
end
function MF:BountyHaul(kind, period)
    period = period or self:BountyPeriod(kind)
    if self:BountyFormat(kind, period) ~= "top3" then return {} end
    local p, fish = Progress(self, kind, period), {}
    for i, weight in ipairs(p.top) do
        local saved = p.topFish and p.topFish[i]
        fish[i] = saved and saved.weight == weight and saved or { weight = weight, legacy = true }
    end
    return fish
end
function MF:BountyText(kind)
    kind = kind or "day"
    if not New(self, kind) then return originalText(self, kind) end
    local _, _, zone = self:Bounty(kind)
    return self:BountyTitle(kind) .. (zone and (" in " .. zone) or " anywhere")
end
-- What an entry is made of (1.1.4)
--
-- A score used to travel alone: "10.45 lb", "5 species". The standings could say who led but
-- not with what. Now it can carry a short detail beside it, for the formats where there's
-- something to show:
--   Three-fish haul   the three weights in hundredths, heaviest first, * on a specimen: "495*.278.272"
--   species, zone, specimen collection   one bit per fish in ORDINARY_ORDER, in base 36
-- It rides as one more field on the end of a score message, where older clients never look,
-- and is only kept when it adds up to the score it came with.
local function Collection(mode) return mode == "species" or mode == "zone" or mode == "specimenSpecies" end

local function ToBase36(n)
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    repeat
        local d = n % 36
        out = digits:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    until n == 0
    return out
end

-- tonumber(s, 36) stops at 32 bits on this client, and the bloated fish sit past bit 32
local function FromBase36(s)
    local n = 0
    for i = 1, #s do
        local d = ("0123456789abcdefghijklmnopqrstuvwxyz"):find(s:sub(i, i), 1, true)
        if not d then return end
        n = n * 36 + (d - 1)
    end
    return n
end

local function OwnDetail(self, kind, period)
    local mode = self:BountyFormat(kind, period)
    if mode == "top3" then
        local haul = self:BountyHaul(kind, period)
        if #haul ~= 3 then return end
        local parts = {}
        for i, fish in ipairs(haul) do parts[i] = self:EncodeWeight(fish.weight) .. (fish.specimen == true and "*" or "") end
        return table.concat(parts, ".")
    elseif Collection(mode) then
        local species, bits = Progress(self, kind, period).species or {}, 0
        for i, id in ipairs(COLLECTED_ORDER) do if species[id] then bits = bits + 2 ^ (i - 1) end end
        if bits > 0 then return ToBase36(bits) end
    end
end

-- The detail as a table, or nil when it doesn't belong with this score
local function ReadDetail(self, kind, period, score, detail)
    if type(detail) ~= "string" or detail == "" or #detail > 40 then return end
    local mode = self:BountyFormat(kind, period)
    if mode == "top3" then
        if not detail:match("^%d+%*?%.%d+%*?%.%d+%*?$") then return end
        local fish, sum = {}, 0
        for raw, star in detail:gmatch("(%d+)(%*?)") do
            local hundredths = tonumber(raw)
            if not hundredths or hundredths <= 0 then return end
            sum = sum + hundredths
            fish[#fish + 1] = { weight = hundredths / 100, specimen = star == "*" }
        end
        if #fish ~= 3 or sum ~= self.Hundredths(score) then return end
        return { fish = fish }
    elseif Collection(mode) then
        if not detail:match("^[0-9a-z]+$") or #detail > 12 then return end
        local bits = FromBase36(detail)
        local bloated = BloatedCount(self, kind, period)
        if not bits or bits >= 2 ^ (bloated and #COLLECTED_ORDER or #ORDINARY_ORDER) then return end
        local species = {}
        for i, id in ipairs(COLLECTED_ORDER) do
            if math.floor(bits / 2 ^ (i - 1)) % 2 == 1 then species[#species + 1] = id end
        end
        if #species ~= math.floor(score) then return end
        return { species = species }
    end
end

-- The fish behind an angler's entry: { fish = { {weight, specimen} x3 } } for a haul,
-- { species = { itemID, ... } } for a collection, or nil while it isn't known
function MF:BountyDetail(kind, name, period)
    kind = kind or "day" period = period or self:BountyPeriod(kind)
    if not New(self, kind, period) then return end
    if self:IsMe(name) then
        local score = self:MyBountyBest(kind, period)
        return score > 0 and ReadDetail(self, kind, period, score, OwnDetail(self, kind, period)) or nil
    end
    local entry = Board(self, kind, period)[Identity(self, name)]
    return entry and ReadDetail(self, kind, period, entry.score, entry.detail) or nil
end

-- The detail to send with a score: ours, or what we heard with someone else's
local function DetailFor(self, kind, period, holder, score)
    if self:IsMe(holder) then return OwnDetail(self, kind, period) end
    local entry = Board(self, kind, period)[Identity(self, holder)]
    if entry and entry.score == score then return entry.detail end
end

local function Signature(self, kind, period)
    local _, id, zone = self:Bounty(kind, period)
    return self:BountyFormat(kind, period) .. ":" .. tostring(id) .. ":" .. (zone or "*")
end
local function Publish(self, kind, period, holder, score, recipient)
    local encoded, side, signature = self:EncodeWeight(score), self:MySide(), Signature(self, kind, period)
    local specimen=self:BountySpecimenStatus(kind,holder,period,score)
    local flag=specimen==true and "1" or specimen==false and "0" or ""
    -- The detail goes last, and only when there is one: an older client reads the fields it knows
    local args = { "BNTY4", kind, period, holder, encoded, side, signature, flag }
    local detail = DetailFor(self, kind, period, holder, score)
    if detail then args[#args + 1] = detail end
    if recipient then
        self:Whisper(recipient, unpack(args))
    else
        self:SendChannel(unpack(args))
        -- Our own score goes to the guild too. On this realm the channel
        -- carries no addon messages, so "the channel" meant the party, and
        -- guildmates only ever met each other's scores when a record swap
        -- happened to pick them - a new week could sit empty for hours.
        -- Only our own: relaying everyone's to the whole guild is a flood.
        if self:IsMe(holder) and IsInGuild() then
            self:SendGuild(unpack(args))
        end
    end
end

-- The whole board, passed hand to hand
--
-- On this realm there is no addon channel, so a bounty board can only
-- spread by whisper: each record swap (a few anglers every five minutes)
-- used to pass on your own score and the top three. A score below the top
-- three only ever reached the anglers its owner swapped with directly, and
-- a new week's board sat empty for hours.
--
-- So a swap with a client that understands it now carries the board itself,
-- packed into one message. Every swap spreads everything either side has
-- heard, and a score reaches the whole realm in a handful of rounds rather
-- than never. Capped, so a board of hundreds doesn't stall the queue: the
-- leaders always, then a window at a random place in the rest, which over
-- repeated swaps covers it all.
local BOOK_LEADERS, BOOK_MAX = 10, 40
local BOOK_SINCE = "1.0.8"

local function PackBoard(self, kind, period)
    local standings, rows, sent = self:BountyStandings(kind, period), {}, {}
    local function Row(entry)
        local name = entry.name
        if type(name) ~= "string" or name == "" or name:find("[,;:~|%c]") or sent[name] then return end
        sent[name] = true
        local specimen = self:BountySpecimenStatus(kind, name, period, entry.weight)
        local detail = DetailFor(self, kind, period, name, entry.weight)
        rows[#rows + 1] = ("%s,%s,%s"):format(name, self:EncodeWeight(entry.weight),
            specimen == true and "1" or specimen == false and "0" or "") .. (detail and ("," .. detail) or "")
    end
    for i = 1, math.min(BOOK_LEADERS, #standings) do Row(standings[i]) end
    local rest = #standings - BOOK_LEADERS
    if rest > 0 then
        local room, start = BOOK_MAX - BOOK_LEADERS, math.random(rest)
        for i = 0, math.min(room, rest) - 1 do
            Row(standings[BOOK_LEADERS + (start + i - 1) % rest + 1])
        end
    end
    -- Our own line always goes, wherever it stands.
    local own = self:MyBountyBest(kind, period)
    if own > 0 then Row({ name = self.me, weight = own }) end
    return table.concat(rows, ";"), #rows
end

function MF.handlers.BBOOK1(self, sender, kind, period, signature, side, packed)
    if not SPAN[kind] or type(packed) ~= "string" or #packed > 8000 then return end
    local n = 0
    for row in packed:gmatch("[^;]+") do
        n = n + 1
        if n > BOOK_MAX * 2 then break end
        local holder, encoded, flag, detail = strsplit(",", row)
        self.handlers.BNTY4(self, sender, kind, period, holder, encoded, side, signature, flag, detail)
    end
end

local function TakesBook(self, recipient)
    local v = self:AnglerVersion(recipient)
    return v ~= nil and not self:VersionNewer(BOOK_SINCE, v)
end

function MF:ShareCurrentBounties(recipient)
    local book = recipient and TakesBook(self, recipient)
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        local period = self:BountyPeriod(kind)
        if book and New(self, kind, period) then
            local packed, rows = PackBoard(self, kind, period)
            if rows > 0 then
                self:Whisper(recipient, "BBOOK1", kind, period, Signature(self, kind, period), self:MySide(), packed)
            end
        elseif New(self, kind, period) then
            local own = self:MyBountyBest(kind, period)
            if own > 0 then Publish(self, kind, period, self.me, own, recipient) end
            -- Relay leaders too so two anglers can discover a third's score.
            -- Always send our own score, even when it is below the leaders.
            local standings = self:BountyStandings(kind, period)
            for i = 1, math.min(3, #standings) do
                local entry = standings[i]
                if not self:IsMe(entry.name) and not self:SameAngler(entry.name, recipient) then
                    Publish(self, kind, period, entry.name, entry.weight, recipient)
                end
            end
        end
    end
end
function MF:SendChannel(...)
    local message, kind, period = ...
    if (message == "BNTY2" or message == "BNTY3" or message == "BREQ2") and New(self, kind, tonumber(period)) then return end
    return originalSend(self, ...)
end
for _, message in ipairs({ "BNTY2", "BNTY3", "BREQ2" }) do
    local handler = MF.handlers[message]
    MF.handlers[message] = function(self, sender, kind, period, ...)
        if New(self, kind, tonumber(period)) then return end
        return handler(self, sender, kind, period, ...)
    end
end
local function Eligible(self, id, kind, period)
    return ORDINARY[id] == true or (BLOATED[id] == true and BloatedCount(self, kind, period))
end
function MF:CheckBounty(c)
    if c.test or c.junk then return 0 end
    self.bountyLegacyScoring = true
    local xp = originalCheck(self, c)
    self.bountyLegacyScoring = nil
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        local modern, mode = New(self, kind)
        if modern then
            local period, id, zone = self:Bounty(kind)
            local collection = mode == "species" or mode == "zone" or mode == "specimenSpecies"
            if (collection and Eligible(self, c.itemID, kind, period) or not collection and c.itemID == id)
                and (not zone or zone == c.zone) then
                local p = Progress(self, kind, period)
                local was, wasSpecimen = p.score, p.specimen
                if mode == "heaviest" then
                    if c.weight>p.score then p.score=c.weight p.specimen=c.specimen==true
                    elseif c.weight==p.score and c.specimen then p.specimen=true end
                elseif mode == "count" then p.score = p.score + 1
                elseif mode == "specimens" then p.score = p.score + (c.specimen and 1 or 0)
                elseif mode == "total" then p.score = self.RoundWeight(p.score + c.weight)
                elseif mode == "top3" then
                    local fish = self:BountyHaul(kind, period)
                    fish[#fish + 1] = { weight = c.weight, specimen = c.specimen or false, at = c.at }
                    table.sort(fish, function(a, b)
                        if a.weight ~= b.weight then return a.weight > b.weight end
                        if (a.specimen == true) ~= (b.specimen == true) then return a.specimen == true end
                        if (a.legacy == true) ~= (b.legacy == true) then return a.legacy ~= true end
                        return (a.at or 0) < (b.at or 0)
                    end)
                    while #fish > 3 do table.remove(fish) end
                    p.top, p.topFish = {}, fish
                    for i, entry in ipairs(fish) do p.top[i] = entry.weight end
                    if #p.top == 3 then
                        p.score = self.RoundWeight(p.top[1] + p.top[2] + p.top[3])
                        p.specimen=nil
                        local known=true
                        for _,entry in ipairs(fish) do
                            if entry.specimen==true then p.specimen=true end
                            if entry.legacy or entry.specimen==nil then known=false end
                        end
                        if p.specimen==nil and known then p.specimen=false end
                    end
                elseif mode ~= "specimenSpecies" or c.specimen then
                    p.species[c.itemID] = true
                    p.score = self.Count(p.species)
                end
                if p.score > was or ((mode=="heaviest" or mode=="top3") and p.specimen~=wasSpecimen) then
                    if kind == "day" and was == 0 then
                        xp = xp + 30
                        self:Print("You entered today's bounty! +30 XP")
                    end
                    Publish(self, kind, period, self.me, p.score)
                end
                -- A partial haul must also survive logout and update its n/3 label.
                self:MarkProfileChanged()
                self:RefreshJournal()
            end
        end
    end
    return xp
end
function MF.handlers.BNTY4(self, sender, kind, period, holder, encoded, side, signature, specimen, detail)
    period = tonumber(period)
    local raw = tonumber(encoded)
    if not SPAN[kind] or not period or period ~= math.floor(period) or period > self:BountyPeriod(kind)
        or period < self:BountyPeriod(kind) - 1 or not New(self, kind, period)
        or type(holder) ~= "string" or #holder < 1 or #holder > 100 or holder:find("[%c~]")
        or not raw or raw ~= raw or raw <= 0 or raw ~= math.floor(raw) or raw == math.huge
        or signature ~= Signature(self, kind, period) or (kind == "day" and side ~= self:MySide()) then return end
    local score, mode = raw / 100, self:BountyFormat(kind, period)
    local _, id = self:Bounty(kind, period)
    local ceiling = math.floor(SPAN[kind] / 3) + 1
    if mode == "heaviest" then ceiling = self:MaxWeight(id)
    elseif mode == "top3" then ceiling = self:MaxWeight(id) * 3
    elseif mode == "total" then ceiling = ceiling * self:MaxWeight(id)
    elseif mode == "species" or mode == "zone" or mode == "specimenSpecies" then
        ceiling = self.Count(ORDINARY) + (BloatedCount(self, kind, period) and self.Count(BLOATED) or 0)
    end
    if score > ceiling then return end
    if mode ~= "heaviest" and mode ~= "top3" and mode ~= "total" and score ~= math.floor(score) then return end
    -- Handled, not stored: a sync that asked for it shouldn't ask again.
    if not self:AnglerCounts(holder) then return true end
    local board, key = Board(self, kind, period), Identity(self, holder)
    if key == "" then return end
    local flag
    if mode=="heaviest" or mode=="top3" then if specimen=="1" then flag=true elseif specimen=="0" then flag=false end end
    detail = ReadDetail(self, kind, period, score, detail) and detail or nil
    if not board[key] or score > board[key].score then
        board[key] = { name = holder, score = score, specimen = flag, detail = detail }
        if not self:IsMe(holder) then
            self.syncDiagnostics.bounties = self.syncDiagnostics.bounties + 1
        end
        self:RefreshJournal()
    end
    if board[key] and board[key].score==score and flag~=nil
        and (board[key].specimen==nil or flag==true) then
        if board[key].specimen~=flag then board[key].specimen=flag self:RefreshJournal() end
    end
    -- The same score heard again, this time with its fish
    if board[key] and board[key].score == score and detail and not board[key].detail then
        board[key].detail = detail
        self:RefreshJournal()
    end
    return true
end
function MF.handlers.BREQ4(self, sender, kind, period, signature)
    period = tonumber(period)
    if not SPAN[kind] or not period or period ~= math.floor(period) or period > self:BountyPeriod(kind)
        or period < self:BountyPeriod(kind) - 1 or not New(self, kind, period)
        or signature ~= Signature(self, kind, period) then return end
    if self.lastRoad == "GUILD" then
        local own = self:MyBountyBest(kind, period)
        if own <= 0 then return end
        self:ReplyOnce("bounty4g:" .. kind .. ":" .. period, 1, 8, function()
            Publish(self, kind, period, self.me, own)
        end)
        return
    end
    self:ReplyOnce("bounty4:" .. kind .. ":" .. period, 1, 4, function()
        for _, entry in ipairs(self:BountyStandings(kind, period)) do Publish(self, kind, period, entry.name, entry.weight) end
    end)
end
local quietBounty, quietReplyAt, quietSerial, quietKnown = {}, {}, 0, {}
function MF:ResetQuietBounties() quietBounty, quietReplyAt, quietSerial, quietKnown = {}, {}, 0, {} end
function MF:RequestQuietBounties(peer)
    if self.CUSTOM_CHANNEL_SUPPORTED or not peer or self:IsMe(peer) then return end
    local now, key = GetTime(), self:AnglerKey(peer)
    if key=="" then return end
    quietKnown[key]={name=peer,at=now}
    for old,p in pairs(quietKnown) do if now-p.at>1800 then quietKnown[old]=nil end end
    if self.Count(quietKnown)>8 then
        local oldest
        for k,p in pairs(quietKnown) do
            if k~=key and (not oldest or p.at<quietKnown[oldest].at) then oldest=k end
        end
        if oldest then quietKnown[oldest]=nil end
    end
    for topic in pairs(quietBounty) do
        local kind,period=topic:match("^(%a+):(%d+)$")
        if not kind or tonumber(period)~=self:BountyPeriod(kind)-1 then quietBounty[topic]=nil end
    end
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        local period = self:BountyPeriod(kind)-1
        if New(self,kind,period) and self:MyBountyBest(kind,period)>0 then
            local topic=kind..":"..period
            local state=quietBounty[topic] or { peers={} }
            quietBounty[topic]=state
            local old=state.peers[key]
            if not old or now-old.at>=300 then
                -- At most four peers per period in a window; do not fan out indefinitely.
                local count=0
                for k,p in pairs(state.peers) do
                    if now-p.at>=600 then state.peers[k]=nil else count=count+1 end
                end
                if count<4 or state.peers[key] then
                    quietSerial=quietSerial+1
                    local nonce=tostring(quietSerial)
                    state.peers[key]={at=now,nonce=nonce,received={}}
                    self:Whisper(peer,"QBASK1",kind,period,nonce,Signature(self,kind,period))
                end
            end
        end
    end
end
function MF:QuietBountyReady(kind,period)
    local state=quietBounty[kind..":"..period]
    if not state then return false end
    local now, complete = GetTime(), false
    for _,p in pairs(state.peers) do
        if now-p.at<600 then
            if not p.done and now-p.at<120 then return false end
            if p.done then complete=true end
        end
    end
    return complete
end
function MF.handlers.QBASK1(self,sender,kind,period,nonce,signature)
    period=tonumber(period)
    if not SPAN[kind] or period~=self:BountyPeriod(kind)-1 or not New(self,kind,period)
        or signature~=Signature(self,kind,period) or type(nonce)~="string"
        or not nonce:match("^%d+$") or #nonce>12 then return end
    local key=self:AnglerKey(sender)
    if key=="" or self:IsMe(sender) then return end
    local topic=key..":"..kind..":"..period
    local now=GetTime()
    if now-(quietReplyAt[topic] or -math.huge)<60 then return end
    for old,at in pairs(quietReplyAt) do if now-at>600 then quietReplyAt[old]=nil end end
    if not quietReplyAt[topic] and self.Count(quietReplyAt)>=500 then return end
    quietReplyAt[topic]=now
    local sent=0
    local function Send(holder,score)
        sent=sent+1
        self:Whisper(sender,"QBDAT1",kind,period,nonce,sent,holder,self:EncodeWeight(score),
            self:MySide(),signature,
            self:BountySpecimenStatus(kind,holder,period,score)==true and "1"
            or self:BountySpecimenStatus(kind,holder,period,score)==false and "0" or "")
    end
    local own=self:MyBountyBest(kind,period)
    if own>0 then Send(self.me,own) end
    local standings=self:BountyStandings(kind,period)
    for i=1,math.min(3,#standings) do
        local a=standings[i]
        if not self:IsMe(a.name) and not self:SameAngler(a.name,sender) then
            Send(a.name,a.weight)
        end
    end
    -- Same queue priority as score messages: completion follows the scores.
    self:Whisper(sender,"QBEND1",kind,period,nonce,signature,sent)
end
function MF.handlers.QBDAT1(self,sender,kind,period,nonce,sequence,holder,encoded,side,signature,specimen)
    period,sequence=tonumber(period),tonumber(sequence)
    if not SPAN[kind] or period~=self:BountyPeriod(kind)-1 or not sequence
        or sequence<1 or sequence>4 or sequence~=math.floor(sequence) then return end
    local state=quietBounty[kind..":"..period]
    local peer=state and state.peers[self:AnglerKey(sender)]
    if not peer or peer.nonce~=nonce or GetTime()-peer.at>=120 then return end
    if self.handlers.BNTY4(self,sender,kind,period,holder,encoded,side,signature,specimen) then
        peer.received[sequence]=true
    end
end
function MF.handlers.QBEND1(self,sender,kind,period,nonce,signature,count)
    period=tonumber(period)
    if not SPAN[kind] or period~=self:BountyPeriod(kind)-1
        or signature~=Signature(self,kind,period) then return end
    local state=quietBounty[kind..":"..period]
    local peer=state and state.peers[self:AnglerKey(sender)]
    if not peer or peer.nonce~=nonce or GetTime()-peer.at>=120 then return end
    count=tonumber(count)
    if not count or count<0 or count>4 or count~=math.floor(count) then return end
    for i=1,count do if not peer.received[i] then return end end
    peer.done=true
end
MF:On("TFL_LOGIN",MF.ResetQuietBounties)

function MF:RequestBounty()
    if not self.CUSTOM_CHANNEL_SUPPORTED then
        self:Fire("TFL_ROSTER_SYNC")
        local peers={}
        for _,p in pairs(quietKnown) do if GetTime()-p.at<=1800 then peers[#peers+1]=p end end
        table.sort(peers,function(a,b) return a.at>b.at end)
        for i=1,math.min(2,#peers) do self:RequestQuietBounties(peers[i].name) end
    end
    originalRequest(self)
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        for period = self:BountyPeriod(kind) - 1, self:BountyPeriod(kind) do
            if New(self, kind, period) then
                self:SendChannel("BREQ4", kind, period, Signature(self, kind, period))
                if period == self:BountyPeriod(kind) and IsInGuild() then
                    self:SendGuild("BREQ4", kind, period, Signature(self, kind, period))
                end
            end
        end
    end
end
MF:On("TFL_SYNC", function(self)
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        -- Conditions registered its original request function before this module
        -- loaded; ask for the new protocol here as well as on explicit refresh.
        for period = self:BountyPeriod(kind) - 1, self:BountyPeriod(kind) do
            if New(self, kind, period) then
                self:SendChannel("BREQ4", kind, period, Signature(self, kind, period))
                if period == self:BountyPeriod(kind) and IsInGuild() then
                    self:SendGuild("BREQ4", kind, period, Signature(self, kind, period))
                end
            end
        end
        if New(self, kind) then
            local score = self:MyBountyBest(kind)
            if score > 0 then Publish(self, kind, self:BountyPeriod(kind), self.me, score) end
        end
    end
end)
