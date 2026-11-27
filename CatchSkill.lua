-- CatchSkill: how often fish get away, by zone and effective skill.
--
-- Classic doesn't lock a low-skill angler out of a zone; the fish simply
-- get away more often. CastOutcomes already decides whether each accepted
-- cast was landed or escaped, so this files that answer under the zone and
-- the skill it was cast at (lure, gear and food included), and the finder
-- reads it back as "possible" and "reliable" skill for each zone.
--
-- Same trust rules as the skill curve (Guide.lua): only our own counts are
-- sent, each angler's latest counts replace their last, no one angler can
-- outweigh the rest, and nothing anyone else says is shown until a second
-- angler agrees. Pool casts are kept apart from open water.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

local BAND = 25               -- skill points per band
local MAX_BAND = 24           -- 0-624: past any skill plus every bonus
local MAX_HEARD = 30          -- anglers remembered per map
local MAX_MAPS_SENT = 40      -- busiest maps first
local MAX_COUNT = 99999
local SOURCE_CAP = 50         -- casts one angler can contribute to a band
local RELIABLE_CASTS = 20
local RELIABLE_ESCAPES = 0.10
local ASK_COOLDOWN = 900
local REPLY_COOLDOWN = 300
local KINDS = { o = true, p = true } -- open water, pool

MF.CATCH_SKILL_BAND = BAND

function MF:SkillBand(skill)
    skill = tonumber(skill)
    if not skill or skill ~= skill or skill < 0 then return end
    return math.min(MAX_BAND, math.floor(skill / BAND))
end

function MF:SkillBandLabel(band)
    return ("%d-%d"):format(band * BAND, band * BAND + BAND - 1)
end

local function Own(self)
    self.db.catchSkill = self.db.catchSkill or {}
    return self.db.catchSkill
end

local function Heard(self)
    self.db.catchSkillHeard = self.db.catchSkillHeard or {}
    return self.db.catchSkillHeard
end

------------------------------------------------------------------------
-- Watching
------------------------------------------------------------------------

-- What a cast is filed under, taken when the line goes out: the skill you
-- cast with and the map you cast on, not wherever you were when it ended.
function MF:CatchSkillCastContext(cast)
    if type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then return end
    local rank, _, bonus = self:FishingSkill()
    local map = self:MapID()
    if not rank or not map or map <= 0 then return end
    cast.skillBand, cast.map = self:SkillBand(rank + (bonus or 0)), map
end

-- Called by CastOutcomes whenever a cast's outcome is decided or revised:
-- `was` is what we last counted it as, so a late correction moves the
-- count rather than adding a second one.
function MF:NoteCastSkill(cast, was, now)
    if not cast or not cast.skillBand or not cast.map then return end
    -- Whether a pool was hovered is only known after our cast handler has
    -- run, so it is read the first time the outcome is.
    if cast.kind == nil then cast.kind = self:PoolCastPending() and "p" or "o" end
    local function Bump(status, by)
        local field = status == "landed" and "l" or status == "escaped" and "e" or nil
        if not field then return end
        local own = Own(self)
        local map = own[cast.map] or {}
        own[cast.map] = map
        local kind = map[cast.kind] or {}
        map[cast.kind] = kind
        local band = kind[cast.skillBand] or { l = 0, e = 0 }
        kind[cast.skillBand] = band
        band[field] = math.max(0, math.min(MAX_COUNT, band[field] + by))
    end
    if was ~= "pending" then Bump(was, -1) end
    Bump(now, 1)
end

------------------------------------------------------------------------
-- Reading it back
------------------------------------------------------------------------

-- { possible, reliable, bands = { [band] = { l, e, sources, ownL, ownE } } }
-- possible: the lowest band where two anglers have landed fish.
-- reliable: the lowest band with two anglers, enough casts and few escapes.
function MF:CatchSkillSummary(map, kind)
    kind = kind or "o"
    local bands = {}
    local function Add(counts, own)
        for band, c in pairs(counts or {}) do
            local l, e = c.l or 0, c.e or 0
            if l + e > 0 then
                local b = bands[band] or { l = 0, e = 0, sources = 0 }
                bands[band] = b
                -- One angler's thousand casts must not drown out everyone else.
                local scale = l + e > SOURCE_CAP and SOURCE_CAP / (l + e) or 1
                b.l, b.e = b.l + l * scale, b.e + e * scale
                b.sources = b.sources + 1
                if own then b.ownL, b.ownE = l, e end
            end
        end
    end
    local own = Own(self)[map]
    Add(own and own[kind], true)
    for _, angler in pairs(Heard(self)[map] or {}) do Add(angler[kind], false) end

    local possible, reliable
    for band = 0, MAX_BAND do
        local b = bands[band]
        if b and b.sources >= 2 then
            local total = b.l + b.e
            if not possible and b.l > 0 then possible = band end
            if not reliable and total >= RELIABLE_CASTS and b.e / total < RELIABLE_ESCAPES then
                reliable = band
            end
        end
    end
    return { possible = possible, reliable = reliable, bands = bands }
end

-- The escape rate nearest at or below a band, preferring what two anglers
-- agree on and falling back to our own. Returns rate, casts, sources.
local function EscapeNear(summary, band)
    for b = band, 0, -1 do
        local row = summary.bands[b]
        if row and row.sources >= 2 and row.l + row.e > 0 then
            return row.e / (row.l + row.e), row.l + row.e, row.sources
        end
    end
    local row = summary.bands[band]
    if row and row.ownL then
        local total = row.ownL + row.ownE
        if total > 0 then return row.ownE / total, total, 1 end
    end
end

-- "reliable", "possible", "yours" (only our own casts), "below" or
-- "unknown", then the escape rate behind it and the summary.
function MF:CatchSkillRating(map, skill)
    local summary = self:CatchSkillSummary(map, "o")
    local band = self:SkillBand(skill)
    if not band then return "unknown", nil, summary end
    local rate = EscapeNear(summary, band)
    if summary.reliable and band >= summary.reliable then return "reliable", rate, summary end
    if summary.possible and band >= summary.possible then return "possible", rate, summary end
    if summary.possible then return "below", rate, summary end
    local row = summary.bands[band]
    if row and row.ownL then return "yours", rate, summary end
    return "unknown", rate, summary
end

-- The skill this zone asks for, from what anglers have logged here: the
-- band where catches became reliable, or failing that where they became
-- possible. Returns the skill, "reliable" or "possible", and how the
-- given effective skill rates against it; nil when nobody has logged
-- enough here to say.
function MF:SkillHere(map, skill)
    map = map or self:MapID()
    local rating, rate, summary = self:CatchSkillRating(map, skill)
    if summary.reliable then return summary.reliable * BAND, "reliable", rating, rate end
    if summary.possible then return summary.possible * BAND, "possible", rating, rate end
end

-- Rows for the finder's zone view.
function MF:CatchSkillLines(map, out, skill)
    out[#out + 1] = { text = self.C.gold .. "Catch success by skill|r", header = true }
    local any = false
    for _, kind in ipairs({ "o", "p" }) do
        local summary = self:CatchSkillSummary(map, kind)
        local rows = {}
        for band = 0, MAX_BAND do
            local b = summary.bands[band]
            if b then
                local total = b.l + b.e
                local right
                if b.sources >= 2 then
                    right = ("%d casts, %d%% escaped, %d anglers"):format(
                        math.floor(total + 0.5), math.floor(b.e / total * 100 + 0.5), b.sources)
                elseif b.ownL then
                    right = ("your %d casts, %d%% escaped"):format(b.ownL + b.ownE,
                        math.floor(b.ownE / (b.ownL + b.ownE) * 100 + 0.5))
                end
                if right then
                    local mine = self:SkillBand(skill) == band
                    rows[#rows + 1] = { text = (mine and self.C.good or self.C.text) .. "    Skill "
                        .. self:SkillBandLabel(band) .. "|r", right = self.C.label .. right .. "|r" }
                end
            end
        end
        if #rows > 0 then
            any = true
            out[#out + 1] = { text = kind == "p" and "  At pools" or "  Open water" }
            for _, row in ipairs(rows) do out[#out + 1] = row end
            if kind == "o" then
                local parts = {}
                if summary.possible then parts[#parts + 1] = "possible from " .. summary.possible * BAND end
                if summary.reliable then parts[#parts + 1] = "reliable from " .. summary.reliable * BAND end
                if #parts > 0 then self:NoteRows(out, "Observed: " .. table.concat(parts, ", ") .. " effective skill.") end
            end
        end
    end
    if not any then
        self:NoteRows(out, "No catch outcomes recorded here yet. Every accepted cast in a fishing log adds to this.")
    else
        self:NoteRows(out, "Other anglers' figures show once two of them agree. Effective skill includes lures, gear and food.")
    end
end

------------------------------------------------------------------------
-- Swapping notes
------------------------------------------------------------------------

local lastAsk, repliedTo = -math.huge, {}

local function Pack(self)
    local maps = {}
    for map, kinds in pairs(Own(self)) do
        local entries, total = {}, 0
        for kind, bands in pairs(kinds) do
            if KINDS[kind] then
                local parts = {}
                for band, c in pairs(bands) do
                    if (c.l or 0) + (c.e or 0) > 0 then
                        parts[#parts + 1] = ("%d:%d:%d"):format(band, c.l or 0, c.e or 0)
                        total = total + (c.l or 0) + (c.e or 0)
                    end
                end
                if #parts > 0 then
                    table.sort(parts)
                    entries[#entries + 1] = ("%d,%s,%s"):format(map, kind, table.concat(parts, "|"))
                end
            end
        end
        if #entries > 0 then maps[#maps + 1] = { total = total, entries = entries } end
    end
    table.sort(maps, function(a, b) return a.total > b.total end)
    local out = {}
    for i = 1, math.min(MAX_MAPS_SENT, #maps) do
        for _, entry in ipairs(maps[i].entries) do out[#out + 1] = entry end
    end
    return table.concat(out, ";")
end

function MF:RequestCatchSkill(force)
    if not force and GetTime() - lastAsk < ASK_COOLDOWN then return end
    lastAsk = GetTime()
    self:SendWide("CSREQ1")
end

-- Everyone answers with their own counts: only ours ever travel, so one
-- answer can't stand in for the rest the way a relayed list could.
function MF.handlers.CSREQ1(self, sender)
    local who = self:AnglerKey(sender)
    if who == "" or self:IsMe(sender) then return end
    if GetTime() - (repliedTo[who] or -math.huge) < REPLY_COOLDOWN then return end
    repliedTo[who] = GetTime()
    self:ReplySoon(2, 18, function()
        local packed = Pack(self)
        if packed ~= "" then self:SendWide("CSKILL1", packed) end
    end)
end

local function Count(value)
    local n = tonumber(value)
    return n and n == n and n >= 0 and n <= MAX_COUNT and n == math.floor(n) and n or nil
end

function MF.handlers.CSKILL1(self, sender, packed)
    local who = self:AnglerKey(sender)
    if who == "" or self:IsMe(sender) or type(packed) ~= "string" or #packed > 16000 then return end
    local received = {}
    for entry in packed:gmatch("[^;]+") do
        local map, kind, bands = strsplit(",", entry)
        map = Count(map)
        if map and map >= 1 and map <= 3000 and KINDS[kind] and bands then
            local parsed = {}
            for part in bands:gmatch("[^|]+") do
                local band, l, e = strsplit(":", part)
                band, l, e = Count(band), Count(l), Count(e)
                if band and band <= MAX_BAND and l and e then parsed[band] = { l = l, e = e } end
            end
            if next(parsed) then
                received[map] = received[map] or {}
                received[map][kind] = parsed
            end
        end
    end
    local heard, now = Heard(self), GetServerTime()
    for map, kinds in pairs(received) do
        local byAngler = heard[map] or {}
        heard[map] = byAngler
        if not byAngler[who] then
            local count, oldest = 0, nil
            for key, r in pairs(byAngler) do
                count = count + 1
                if not oldest or (r.at or 0) < (byAngler[oldest].at or 0) then oldest = key end
            end
            if count >= MAX_HEARD and oldest then byAngler[oldest] = nil end
        end
        -- Their latest word replaces their last; it never adds to it.
        byAngler[who] = { at = now, o = kinds.o, p = kinds.p }
    end
    if next(received) then self:RefreshJournal() end
end

MF:On("TFL_SYNC", function(self) self:RequestCatchSkill() end)

MF:Command("escapes", "Solo", "/tfl escapes - how often fish get away here, by skill", function(self, args)
    local map = tonumber(args[1]) or self:MapID()
    local rank, _, bonus = self:FishingSkill()
    local skill = rank and rank + (bonus or 0)
    local rating, rate = self:CatchSkillRating(map, skill)
    self:Print(("%s at effective skill %s: %s%s."):format(self:ZoneNameFor(map) or ("map " .. tostring(map)),
        tostring(skill or "?"), rating, rate and (", about %d%% escape"):format(math.floor(rate * 100 + 0.5)) or ""))
    local lines = {}
    self:CatchSkillLines(map, lines, skill)
    for i = 2, #lines do
        local line = lines[i]
        print("  " .. line.text .. (line.right and ("  " .. line.right) or ""))
    end
    if args[1] == "ask" then self:RequestCatchSkill(true) end
end)

function MF:ResetCatchSkill()
    lastAsk, repliedTo = -math.huge, {}
end
