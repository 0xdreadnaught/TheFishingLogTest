-- Fishing here (1.1.4): the water you're at, as a dashboard to glance at between casts.
--   header   the water, its zone, and its frenzy clock
--   tiles    landed this session, how many got away, the zone's fish you have, your best here,
--            and how reliable catches are at your skill in this zone
--   chase    the nearest spot record above your best, with a bar for the gap and who holds it,
--            and the personal best most worth improving
--   bounties each bounty you can enter here: time left, and your entry against the lead on a bar
--   to catch the zone's fish you haven't caught, as icons (gone once you have them all)
--   catches  your best of each fish at this water, in a grid, coloured by grade
-- The Fishing Log's own line view (FishingHereLines) still builds underneath for its tests.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.HerePage = P

local GOLD = "|cffffd100"
local GREEN = "|cff3ee63e"
local ORANGE = "|cffff9d00"
local RED = "|cffff5a5a"
local MUTED = "|cff8f8f8f"
local WHITE = "|cffffffff"
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"

local TILE_N = 5
local CELLS = 3          -- catches per grid row
local ICONS_MAX = 12     -- fish to catch per row of icons

local function Pct(rate) return math.floor((rate or 0) * 100 + 0.5) .. "%" end

-- ---------------------------------------------------------------------------
-- What the page shows, from The Fishing Log's own figures
-- ---------------------------------------------------------------------------
function P:Data()
    local d = {}
    local spot, zone = MF:CurrentSpot(), MF:ZoneEnglish()
    d.spot, d.zone = spot, zone
    local journal = MF.cdb.profile.journal or {}
    local bests = (MF.cdb.records or {})[spot.key] or {}
    d.bests = bests
    d.active, d.secs = MF:FrenzyPresentationState(spot.key)

    -- The session's casts
    local c = MF.session and MF.session.outcomes
    if type(c) == "table" and type(c.casts) == "number" then d.outcomes = c end

    -- The zone's fish
    d.native, d.missing, d.why = {}, {}, MF:ZoneFish(zone)
    for id in pairs(d.why) do
        d.native[#d.native + 1] = id
        if not journal[id] then d.missing[#d.missing + 1] = id end
    end
    local function ByName(a, b) return (MF:FishName(a) or "") < (MF:FishName(b) or "") end
    table.sort(d.missing, ByName)

    -- Your best here, and the fish behind it
    for id, b in pairs(bests) do
        if not d.best or b.weight > d.best.weight then d.best = { id = id, weight = b.weight } end
    end

    -- How catches go at your skill in this zone
    local rank, _, bonus = MF:FishingSkill()
    d.skill = rank and rank + (bonus or 0)
    if spot.mapID and spot.mapID ~= 0 and MF.CatchSkillRating then
        d.rating, d.escape = MF:CatchSkillRating(spot.mapID, d.skill)
    end

    -- The nearest spot record above your best
    d.recordsReady = MF:RecordsReady(spot.mapID) or spot.mapID == 0
    if not d.recordsReady then MF:RequestRecords(spot.mapID) end
    if d.recordsReady then
        for _, r in ipairs(MF:SpotRecords(spot.key)) do
            local personal = bests[r.id]
            if personal and r.all and not MF:IsMe(r.all.h) and r.all.w > personal.weight then
                local gap = r.all.w - personal.weight
                if not d.chase or gap < d.chase.gap or (gap == d.chase.gap and r.id < d.chase.id) then
                    d.chase = { id = r.id, gap = gap, mine = personal.weight, record = r.all.w, holder = r.all.h }
                end
            end
        end
    end

    -- The personal best most worth improving: the lowest-graded of the zone's fish you've had here
    local worst
    for _, id in ipairs(d.native) do
        local personal = bests[id]
        local p = personal and MF:WeightPercentile(id, personal.weight)
        if p and p < 0.98 and (not worst or p < worst) then
            worst = p
            local grade, colour = MF:WeightGradeShort(id, personal.weight)
            d.improve = { id = id, weight = personal.weight, grade = grade, colour = colour }
        end
    end

    -- Bounties you can enter here (the same test as The Fishing Log's own page)
    d.bounties = {}
    for _, kind in ipairs(MF.BOUNTY_KINDS or {}) do
        local _, id, targetZone = MF:Bounty(kind)
        if id and (not targetZone or targetZone == zone) then
            local mode = MF:BountyFormat(kind)
            local collection = mode == "species" or mode == "zone" or mode == "specimenSpecies"
            local possible = collection or targetZone == zone or bests[id] ~= nil
                or ((MF.cdb.caughtIn or {})[id] or {})[zone] ~= nil
            for _, fid in ipairs(d.native) do if fid == id then possible = true end end
            if possible then
                local standings = MF:BountyStandings(kind)
                local lead = standings[1]
                -- The best entry that isn't yours, to tell a lead from a tie
                local rival = 0
                for _, e in ipairs(standings) do
                    if not MF:IsMe(e.name) then rival = e.weight break end
                end
                d.bounties[#d.bounties + 1] = { kind = kind, id = id, mode = mode, collection = collection,
                    title = (mode ~= "heaviest" and mode ~= "count") and MF:BountyTitle(kind) or MF:FishName(id),
                    icon = MF:BountyIcon(kind), left = MF:BountyTimeLeft(kind), entry = MF:MyBountyBest(kind),
                    lead = lead and lead.weight or 0, leader = lead and lead.name, rival = rival }
            end
        end
    end

    -- Your best of each fish here
    d.catches = {}
    for id, b in pairs(bests) do
        local grade, colour = MF:WeightGradeShort(id, b.weight)
        d.catches[#d.catches + 1] = { id = id, weight = b.weight, specimen = b.specimen, grade = grade, colour = colour,
            name = MF:FishName(id) or "" }
    end
    table.sort(d.catches, function(a, b) return a.name < b.name end)
    return d
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function CardTip(frame, id)
    frame:SetScript("OnEnter", function(self)
        local fish = self.fishID or id
        local title = self.tipTitle or (fish and MF:FishName(fish))
        if not title then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if self.tipLine then GameTooltip:AddLine(self.tipLine, 1, 1, 1, true) end
        GameTooltip:AddLine(self.onClick and "Click to open the Bounty tab." or "Click for its card.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self) W:HideTip(self) end)
    frame:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() return end
        local fish = self.fishID or id
        if fish and (MF.FISH[fish] or (MF.TROPHY and MF.TROPHY[fish])) then MF:ShowCard(fish) end
    end)
end

local function HeadRow()
    local r = CreateFrame("Frame")
    r.name = W:Label(r, "GameFontNormalLarge")
    r.name:SetPoint("TOPLEFT", 8, -8)
    r.zone = W:Label(r, "GameFontHighlightSmall")
    r.zone:SetPoint("LEFT", r.name, "RIGHT", 10, -1)
    r.frenzy = W:Label(r, "GameFontHighlight")
    r.frenzy:SetPoint("TOPRIGHT", -10, -10)
    return r
end

local function TilesRow()
    local r = CreateFrame("Frame")
    r.tiles = {}
    for i = 1, TILE_N do
        local t = CreateFrame("Frame", nil, r)
        t.bg = t:CreateTexture(nil, "BACKGROUND")
        t.bg:SetAllPoints()
        t.bg:SetColorTexture(0, 0, 0, 0.35)
        t.value = W:Label(t, "GameFontNormalLarge")
        t.value:SetPoint("TOP", 0, -9)
        t.label = W:Label(t, "GameFontDisableSmall")
        t.label:SetPoint("TOP", t.value, "BOTTOM", 0, -4)
        t:EnableMouse(true)
        t:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tip[1], 1, 0.82, 0)
            for i2 = 2, #self.tip do GameTooltip:AddLine(self.tip[i2], 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self) W:HideTip(self) end)
        r.tiles[i] = t
    end
    return r
end

local function BarRow()
    local r = CreateFrame("Button")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    r.icon = W:Icon(r, 22)
    r.icon:SetPoint("TOPLEFT", 8, -6)
    r.title = W:Label(r, "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.right = W:Label(r, "GameFontHighlightSmall")
    r.right:SetPoint("TOPRIGHT", -10, -8)
    r.bar = W:Bar(r, 200, 10)
    r.bar:SetPoint("TOPLEFT", r.icon, "BOTTOMRIGHT", 8, 2)
    r.sub = W:Label(r, "GameFontDisableSmall")
    r.sub:SetPoint("TOPLEFT", r.bar, "BOTTOMLEFT", 0, -4)
    r.sub:SetJustifyH("LEFT")
    CardTip(r)
    return r
end

local function LineRow()
    local r = CreateFrame("Button")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    r.icon = W:Icon(r, 18)
    r.icon:SetPoint("LEFT", 10, 0)
    r.title = W:Label(r, "GameFontHighlight")
    r.title:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.right = W:Label(r, "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -10, 0)
    CardTip(r)
    return r
end

local function IconsRow()
    local r = CreateFrame("Frame")
    r.buttons = {}
    for i = 1, ICONS_MAX do
        local b = CreateFrame("Button", nil, r)
        b:SetSize(30, 30)
        b.icon = W:Icon(b, 28)
        b.icon:SetPoint("CENTER")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        CardTip(b)
        r.buttons[i] = b
    end
    return r
end

local function GridRow()
    local r = CreateFrame("Frame")
    r.cells = {}
    for i = 1, CELLS do
        local c = CreateFrame("Button", nil, r)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.bg:SetColorTexture(0, 0, 0, 0.3)
        local hl = c:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        c.icon = W:Icon(c, 18)
        c.icon:SetPoint("LEFT", 5, 0)
        c.name = W:Label(c, "GameFontHighlightSmall")
        c.name:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
        c.name:SetJustifyH("LEFT")
        c.name:SetWordWrap(false)
        c.weight = W:Label(c, "GameFontHighlightSmall")
        c.weight:SetPoint("RIGHT", -6, 0)
        CardTip(c)
        r.cells[i] = c
    end
    return r
end

local function Make(kind)
    if kind == "header" then return HeadRow() end
    if kind == "tiles" then return TilesRow() end
    if kind == "bar" then return BarRow() end
    if kind == "line" then return LineRow() end
    if kind == "icons" then return IconsRow() end
    if kind == "grid" then return GridRow() end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, kind == "note" and "GameFontDisableSmall" or "GameFontNormal")
    fr.text:SetPoint("TOPLEFT", 8, kind == "note" and -4 or -10)
    fr.text:SetPoint("TOPRIGHT", -8, kind == "note" and -4 or -10)
    fr.text:SetJustifyH("LEFT")
    fr.right = W:Label(fr, "GameFontDisableSmall")
    fr.right:SetPoint("TOPRIGHT", -8, -11)
    if kind == "section" then
        fr.rule = W:Divider(fr, 100)
        fr.rule:SetPoint("BOTTOMLEFT", 0, 1)
        fr.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    end
    return fr
end

local function FillTiles(fr, it)
    local width = fr:GetWidth() or 600
    local gap = 8
    local tw = math.max(60, (width - 16 - gap * (TILE_N - 1)) / TILE_N)
    for i, t in ipairs(fr.tiles) do
        local data = it.tiles[i]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fr, "TOPLEFT", 8 + (i - 1) * (tw + gap), -2)
        t:SetSize(tw, (it.h or 56) - 6)
        t.value:SetText(data and data.value or "")
        t.label:SetText(data and data.label or "")
        t.label:SetWidth(tw - 8)
        t.tip = data and data.tip
        t:SetShown(data ~= nil)
    end
end

local function FillBar(fr, it)
    fr.fishID, fr.tipTitle, fr.onClick = it.fishID, it.tipTitle, it.onClick
    fr.tipLine = it.tipLine
    fr.icon:SetTexture(it.icon)
    fr.title:SetText(it.title)
    fr.right:SetText(it.right or "")
    local width = fr:GetWidth() or 600
    fr.title:SetWidth(math.max(80, width - 200))
    fr.bar:SetWidth(math.max(80, width - 50))
    fr.bar:Set(it.value or 0, it.max or 1, "")
    fr.bar:SetColor(it.r or 1, it.g or 0.75, it.b or 0.1)
    fr.sub:SetText(it.sub or "")
end

local function FillIcons(fr, it)
    for i, b in ipairs(fr.buttons) do
        local id = it.ids[i]
        if id then
            b:ClearAllPoints()
            b:SetPoint("LEFT", fr, "LEFT", 8 + (i - 1) * 34, 0)
            b.icon:SetTexture(MF:FishIcon(id))
            b.fishID = id
            b.tipLine = it.why and it.why[id] == "anywhere"
                and "Not caught yet. It bites almost anywhere, this zone included."
                or "Not caught yet. It lives in this zone, though not every water holds every fish."
            b:Show()
        else
            b:Hide()
        end
    end
end

local function FillGrid(fr, it)
    local width = fr:GetWidth() or 600
    local gap = 6
    local cw = (width - 16 - gap * (CELLS - 1)) / CELLS
    for i, c in ipairs(fr.cells) do
        local e = it.cells[i]
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", fr, "TOPLEFT", 8 + (i - 1) * (cw + gap), -2)
        c:SetSize(cw, (it.h or 26) - 4)
        if e then
            c.fishID = e.id
            c.icon:SetTexture(MF:FishIcon(e.id))
            c.name:SetText(MF.ShortFishName and MF:ShortFishName(e.id) or e.name)
            c.name:SetWidth(math.max(40, cw - 90))
            local colour = e.specimen and (MF.C and MF.C.spec or GOLD) or e.colour or WHITE
            c.weight:SetText(colour .. MF:Weight(e.weight) .. "|r" .. (e.specimen and (" " .. STAR) or ""))
            c.tipLine = "Your best here: " .. MF:Weight(e.weight)
                .. (e.specimen and ", a specimen" or e.grade and (", graded " .. e.grade) or "") .. "."
            c:Show()
        else
            c:Hide()
        end
    end
end

local function Fill(fr, it)
    if it.kind == "header" then
        fr.name:SetText(it.name)
        fr.zone:SetText(it.zone)
        fr.frenzy:SetText(it.frenzy)
    elseif it.kind == "tiles" then FillTiles(fr, it)
    elseif it.kind == "bar" then FillBar(fr, it)
    elseif it.kind == "line" then
        fr.fishID, fr.tipLine = it.fishID, it.tipLine
        fr.icon:SetTexture(it.icon)
        fr.title:SetText(it.title)
        fr.right:SetText(it.right or "")
    elseif it.kind == "icons" then FillIcons(fr, it)
    elseif it.kind == "grid" then FillGrid(fr, it)
    else
        fr.text:SetText(it.text or "")
        fr.right:SetText(it.right or "")
    end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
local function RatingTile(d)
    local zone = d.zone or "this zone"
    if d.rating == "reliable" then
        return { value = GREEN .. "Reliable|r", label = "at your skill",
            tip = { "Catches at your skill", ("Anglers at your effective skill (%s) land nearly everything in %s: %s get away."):format(
                tostring(d.skill or "?"), zone, Pct(d.escape)) } }
    elseif d.rating == "possible" or d.rating == "yours" then
        return { value = GOLD .. Pct(d.escape) .. "|r", label = "get away at your skill",
            tip = { "Catches at your skill", d.rating == "yours" and "From your own casts here; other anglers' figures show once two agree."
                or "From anglers' logged casts in this zone. More skill (lures, gear, food) lands more." } }
    elseif d.rating == "below" then
        return { value = ORANGE .. "Low|r", label = "skill for this zone",
            tip = { "Catches at your skill", "Anglers have only landed fish here at a higher skill so far." } }
    end
    return { value = MUTED .. "?|r", label = "at your skill",
        tip = { "Catches at your skill", "Nobody has logged enough casts in this zone yet. Every cast you make here adds to it." } }
end

function P:Items(d)
    local items = {}
    local frenzy
    if d.secs then
        frenzy = d.active and (ORANGE .. "Frenzy now: " .. MF:FormatClock(d.secs) .. " left|r")
            or ("Next frenzy here in " .. WHITE .. MF:FormatClock(d.secs) .. "|r")
    else
        frenzy = MUTED .. "No frenzy water here|r"
    end
    items[#items + 1] = { kind = "header", h = 36, name = d.spot.name or "", zone = MUTED .. (d.zone or "") .. "|r", frenzy = frenzy }

    -- Tiles
    local tiles = {}
    local c = d.outcomes
    if c then
        local pending = math.max(0, c.casts - c.landed - c.escaped - c.cancelled - c.unknown)
        local tip = { "This session", ("%d casts: %d landed, %d got away, %d cancelled, %d not known%s."):format(
            c.casts, c.landed, c.escaped, c.cancelled, c.unknown, pending > 0 and (", " .. pending .. " still out") or "") }
        tiles[1] = { value = WHITE .. c.landed .. "|r", label = "landed this session", tip = tip }
        local tried = c.landed + c.escaped
        tiles[2] = { value = (c.escaped > 0 and ORANGE or WHITE) .. (tried > 0 and Pct(c.escaped / tried) or "0%") .. "|r",
            label = "got away", tip = tip }
    else
        local tip = { "This session", "Start fishing and your casts show here." }
        tiles[1] = { value = MUTED .. "-|r", label = "landed this session", tip = tip }
        tiles[2] = { value = MUTED .. "-|r", label = "got away", tip = tip }
    end
    local have = #d.native - #d.missing
    tiles[3] = { value = (#d.native > 0 and #d.missing == 0 and GREEN or WHITE) .. have .. "/" .. #d.native .. "|r",
        label = "zone fish caught", tip = { "The zone's fish", #d.native == 0 and "No fish list for this zone yet."
            or #d.missing == 0 and "You've caught every fish listed for this zone."
            or (#d.missing .. " still to catch. A zone's fish aren't promised at every water.") } }
    tiles[4] = d.best and { value = WHITE .. MF:Weight(d.best.weight) .. "|r", label = "your best here",
        tip = { "Your best at this water", MF:FishName(d.best.id) or "" } }
        or { value = MUTED .. "-|r", label = "your best here", tip = { "Your best at this water", "Nothing landed here yet." } }
    tiles[5] = RatingTile(d)
    items[#items + 1] = { kind = "tiles", h = 58, tiles = tiles }

    -- Fish still to catch
    if #d.missing > 0 then
        items[#items + 1] = { kind = "section", h = 32, text = "Still to catch in " .. (d.zone or "this zone"),
            right = #d.missing .. (#d.missing == 1 and " fish" or " fish") }
        for i = 1, #d.missing, ICONS_MAX do
            local ids = {}
            for k = i, math.min(#d.missing, i + ICONS_MAX - 1) do ids[#ids + 1] = d.missing[k] end
            items[#items + 1] = { kind = "icons", h = 38, ids = ids, why = d.why }
        end
    end

    -- A record to chase
    items[#items + 1] = { kind = "section", h = 32, text = "A record to chase" }
    if d.chase then
        local ch = d.chase
        items[#items + 1] = { kind = "bar", h = 54, fishID = ch.id, icon = MF:FishIcon(ch.id), title = MF:FishName(ch.id) or "",
            right = GOLD .. MF:Weight(ch.gap) .. " short|r", value = ch.mine, max = ch.record,
            sub = ("You %s%s|r   record %s%s|r, %s"):format(WHITE, MF:Weight(ch.mine), WHITE, MF:Weight(ch.record), MF:ShortName(ch.holder or "?")),
            tipLine = "The nearest spot record above your best at this water." }
    else
        items[#items + 1] = { kind = "note", h = 24, text = d.recordsReady
            and "No spot record here above your own best. Every record at this water is yours, or still to be set."
            or "Checking spot records with other anglers. This updates when they arrive." }
    end
    if d.improve then
        local im = d.improve
        items[#items + 1] = { kind = "line", h = 26, fishID = im.id, icon = MF:FishIcon(im.id),
            title = "Improve: " .. (MF:FishName(im.id) or ""),
            right = MF:Weight(im.weight) .. (im.grade and ("  " .. (im.colour or "") .. im.grade .. "|r") or ""),
            tipLine = "Your lowest-graded best here among the zone's fish. A heavier one lifts this water's personal best." }
    end

    -- Bounties
    items[#items + 1] = { kind = "section", h = 32, text = "Bounties you can enter here" }
    if #d.bounties == 0 then
        items[#items + 1] = { kind = "note", h = 24, text = "No current bounty takes the fish of this zone." }
    end
    for _, b in ipairs(d.bounties) do
        local label = b.kind == "day" and "Daily" or b.kind == "week" and "Weekly" or "Monthly"
        local function Score(v) return MF:BountyScoreText(b.kind, v, nil, false) end
        local sub, r, g, bl
        if b.entry <= 0 then
            sub = MUTED .. "Not entered yet|r" .. (b.lead > 0 and ("   lead " .. WHITE .. Score(b.lead) .. "|r") or "")
            r, g, bl = 0.4, 0.4, 0.4
        elseif b.entry > b.rival then
            sub = GREEN .. "You're in the lead|r   with " .. WHITE .. Score(b.entry) .. "|r"
                .. (b.rival > 0 and ("   next " .. WHITE .. Score(b.rival) .. "|r") or "")
            r, g, bl = 0.25, 0.85, 0.3
        elseif b.entry == b.rival then
            sub = GOLD .. "Level with the lead|r   at " .. WHITE .. Score(b.entry) .. "|r"
            r, g, bl = 1, 0.75, 0.1
        else
            sub = ("You %s%s|r   lead %s%s|r   %s behind"):format(WHITE, Score(b.entry), WHITE, Score(b.lead), Score(b.lead - b.entry))
            r, g, bl = 0.3, 0.6, 1
        end
        items[#items + 1] = { kind = "bar", h = 54, fishID = not b.collection and b.id or nil, icon = b.icon,
            title = label .. ": " .. (b.title or ""), right = MUTED .. MF:FormatSpan(b.left) .. " left|r",
            value = b.entry, max = math.max(b.lead, b.entry, 0.01), sub = sub, r = r, g = g, b = bl,
            tipLine = MF:BountyRule(b.kind),
            tipTitle = b.collection and (label .. ": " .. (b.title or "")) or nil,
            onClick = b.collection and function() MF:OpenJournal("bounty") end or nil }
    end

    -- Your catches here
    items[#items + 1] = { kind = "section", h = 32, text = "Your catches at this water", right = #d.catches > 0 and "your best of each" or nil }
    if #d.catches == 0 then
        items[#items + 1] = { kind = "note", h = 24, text = "Nothing landed here yet." }
    end
    for i = 1, #d.catches, CELLS do
        local cells = {}
        for k = i, math.min(#d.catches, i + CELLS - 1) do cells[#cells + 1] = d.catches[k] end
        items[#items + 1] = { kind = "grid", h = 28, cells = cells }
    end
    return items
end

function P:Build(frame)
    self.frame = frame
    self.list = W:VList(frame, Make, Fill)
    self.list:SetPoint("TOPLEFT", 0, -2)
    self.list:SetPoint("BOTTOMRIGHT", -16, 0)
end

function P:Refresh()
    if not self.list then return end
    local d = self:Data()
    self.data = d
    local items = self:Items(d)
    -- The page redraws every few seconds for the frenzy clock: keep the scroll when nothing moved
    local sig = {}
    for _, it in ipairs(items) do sig[#sig + 1] = it.kind .. (it.fishID or "") .. (it.text or "") end
    sig = table.concat(sig, "\1")
    self.list:SetItems(items, sig == self.sig)
    self.sig = sig
end

J:AddPage({
    key = "here",
    match = function(state)
        return not state.recap and state.tab == "journal" and state.view == "here"
    end,
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function() P:Refresh() end,
    subheading = function() return "Fishing here" end,
    count = function()
        local d = P.data
        return d and (#d.catches == 1 and "1 fish caught here" or (#d.catches .. " fish caught here")) or ""
    end,
})
