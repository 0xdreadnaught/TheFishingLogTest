-- Waters: where you fish. One page for what The Fishing Log splits over "Fishing here", "Local waters"
-- and its "Records" tab.
--   tiles   this zone at a glance: how many of its fish you have, waters known, the next frenzy
--   map     the zone's own map art with a pin on every water you know: yours glows gold, a frenzy
--           glows orange, a crown marks a water with a King; your arrow shows where you stand
--   detail  the chosen water (yours unless you pick another): its frenzy clock, its King, every record
--           there with your best and how far behind you are, and the bounties you can enter there
-- Selection is The Fishing Log's own (MF.localWaterSelected); clicking a pin shows that water here.
-- From Godfall's UI Rework 0.7.4 (MIT); here it draws the Records tab (shown as Waters) and Local waters.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.Waters = P
local PIN = 22
local DETAIL_W = 340
local STACK_BELOW = 460     -- map narrower than this beside the detail: stack them instead
local STACK_LIST_MIN = 140  -- when stacked, the map fills the width unless that leaves the records less than this
local STACK_HEADER = 80     -- the water's name, frenzy and King, above the map when stacked
local FRENZY_EXTRA = 22     -- a frenzy's bar and what it does, under the water's name
local RIPPLES = 2           -- rings spreading from a water in a frenzy, like a bobber landing
local RIPPLE_TIME = 2.2     -- seconds for one ring to spread and fade
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"

-- ---------------------------------------------------------------------------
-- The map
-- ---------------------------------------------------------------------------
-- The zone's art, as the world map lays it out: layer 1's tiles, row by row
local function MapArt(mapID)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    if not ok or type(layers) ~= "table" or not layers[1] then return end
    local L = layers[1]
    local ok2, tiles = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not ok2 or type(tiles) ~= "table" or #tiles == 0 then return end
    if not (L.layerWidth and L.layerHeight and L.tileWidth and L.tileHeight) then return end
    return { w = L.layerWidth, h = L.layerHeight, tw = L.tileWidth, th = L.tileHeight,
        cols = math.ceil(L.layerWidth / L.tileWidth), tiles = tiles }
end

local function SelectWater(key)
    MF.localWaterSelected = key
    -- Remember where you stood: walking to new water hands the Waters tab back to it
    local cur = MF.CurrentSpot and MF:CurrentSpot()
    P.selAt = cur and cur.key
    local st = J:State()
    if st.tab == "records" or (st.tab == "journal" and st.view == "tools" and (MF.anglingToolsView or "waters") == "waters") then
        MF:RedrawJournal()
    else
        -- Local waters lives on the Waters tab now, not under the Journal
        MF:OpenJournal("records")
    end
end

local function Pin(parent)
    local p = CreateFrame("Button", nil, parent)
    p:SetSize(PIN, PIN)
    -- You are here: a soft round gold glow that pulses, as a frenzy's does (a square border
    -- glow read as a box on the map)
    p.glow = p:CreateTexture(nil, "BACKGROUND")
    p.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    p.glow:SetBlendMode("ADD")
    p.glow:SetPoint("CENTER")
    p.glow:SetSize(PIN * 2.6, PIN * 2.6)
    p.glow:SetVertexColor(1, 0.82, 0.2)
    p.fire = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    -- Round, like the gold one: the action-button border read as a square box under the ripples
    p.fire:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    p.fire:SetBlendMode("ADD")
    p.fire:SetPoint("CENTER")
    p.fire:SetSize(PIN * 2.6, PIN * 2.6)
    p.fire:SetVertexColor(1, 0.45, 0.05)
    -- A frenzy: orange rings spread from the pin, so your eye finds it from across the map
    p.ripples = {}
    for i = 1, RIPPLES do
        local ring = p:CreateTexture(nil, "BACKGROUND", nil, 2)
        if W:Atlas(ring, "communities-ring-gold") then
            ring:SetDesaturated(true)
        else
            ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            ring:SetTexCoord(0, 0.6, 0, 0.6)
        end
        ring:SetBlendMode("ADD")
        ring:SetVertexColor(1, 0.5, 0.1)
        ring:SetPoint("CENTER")
        ring:SetSize(PIN, PIN)
        ring:Hide()
        p.ripples[i] = ring
    end
    p.round = W:RoundIcon(p, PIN, "Interface\\Icons\\Trade_Fishing")
    p.round:SetPoint("CENTER")
    p.round:EnableMouse(false)
    p.sel = p:CreateTexture(nil, "OVERLAY", nil, 3)
    -- The chosen water: a round highlight that hugs the pin's ring, not a square
    p.sel:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    p.sel:SetBlendMode("ADD")
    p.sel:SetPoint("CENTER")
    p.sel:SetSize(PIN + 8, PIN + 8)
    p.crown = p:CreateTexture(nil, "OVERLAY", nil, 4)
    p.crown:SetTexture(CROWN)
    p.crown:SetSize(12, 12)
    p.crown:SetPoint("BOTTOM", p, "TOP", 0, -4)
    p:SetScript("OnEnter", function(self)
        -- Grow the icon, not the pin: scaling the pin itself scales its place on the map too, so it
        -- would jump out from under the cursor, lose the hover and flicker back
        self.round:SetScale(1.18)
        local r = self.r
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.name, 1, 0.82, 0)
        local conf, colour = MF:LocationConfidence(r.key)
        GameTooltip:AddLine((colour or "") .. conf .. "|r", 1, 1, 1)
        if r.current then GameTooltip:AddLine("You are here", 1, 0.82, 0) end
        if r.active then
            GameTooltip:AddLine(("Feeding frenzy, %s left"):format(MF:FormatClock(r.left or 0)), 1, 0.5, 0)
        elseif r.left then
            GameTooltip:AddLine(("Next frenzy in %s"):format(MF:FormatClock(r.left)), 0.8, 0.8, 0.8)
        end
        local king = MF:King(r.key)
        if king then
            GameTooltip:AddDoubleLine("King", ("%s  %s"):format(MF:ShortName(king.h), MF:Weight(king.w)), 0.7, 0.7, 0.7, 1, 0.82, 0)
        end
        local n = 0
        for _ in pairs(MF.cdb.records[r.key] or {}) do n = n + 1 end
        GameTooltip:AddLine(n > 0 and (n .. (n == 1 and " of your bests is from here" or " of your bests are from here")) or "You haven't fished here yet", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function(self) self.round:SetScale(1) W:HideTip(self) end)
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta) P:Zoom(delta) end)
    p:SetScript("OnClick", function(self)
        if not self.r then return end
        W:Sound("row")
        SelectWater(self.r.key)
    end)
    return p
end

local function ZoneTile(parent)
    local t = CreateFrame("Button", nil, parent)
    t.shade = t:CreateTexture(nil, "BACKGROUND")
    t.shade:SetAllPoints()
    t.shade:SetColorTexture(0, 0, 0, 0.25)
    t.value = W:Label(t, "GameFontHighlightLarge")
    t.value:SetPoint("TOP", 0, -7)
    t.label = W:Label(t, "GameFontNormalSmall")
    t.label:SetPoint("TOP", t.value, "BOTTOM", 0, -3)
    t.label:SetTextColor(0.8, 0.8, 0.8)
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    t:SetScript("OnClick", function(self) if self.go then W:Sound("row") self.go() end end)
    t:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.tip[1], 1, 0.82, 0)
        for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return t
end

-- ---------------------------------------------------------------------------
-- The detail: a short head, then a scrolling list of records and bounties
-- ---------------------------------------------------------------------------
local function MakeRow(kind)
    if kind == "head" then
        local fr = CreateFrame("Frame")
        fr.text = W:Label(fr, "GameFontNormal")
        fr.text:SetPoint("BOTTOMLEFT", 2, 6)
        fr.rule = W:Divider(fr, 100)
        fr.rule:SetPoint("BOTTOMLEFT", 0, 2)
        fr.rule:SetPoint("BOTTOMRIGHT", 0, 2)
        return fr
    end
    if kind == "note" then
        local fr = CreateFrame("Frame")
        fr.text = W:Label(fr, "GameFontDisableSmall")
        fr.text:SetPoint("TOPLEFT", 4, -4)
        fr.text:SetPoint("TOPRIGHT", -4, -4)
        fr.text:SetJustifyH("LEFT")
        return fr
    end
    local fr = CreateFrame("Button")
    fr.shade = fr:CreateTexture(nil, "BACKGROUND")
    fr.shade:SetAllPoints()
    local hl = fr:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    fr.icon = fr:CreateTexture(nil, "ARTWORK")
    fr.icon:SetSize(24, 24)
    fr.icon:SetPoint("TOPLEFT", 4, -5)
    fr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    fr.name = W:Label(fr, "GameFontHighlight")
    fr.name:SetPoint("TOPLEFT", 36, -5)
    fr.name:SetJustifyH("LEFT")
    fr.name:SetWordWrap(false)
    fr.right = W:Label(fr, "GameFontNormal")
    fr.right:SetPoint("TOPRIGHT", -6, -5)
    fr.sub = W:Label(fr, "GameFontDisableSmall")
    fr.sub:SetPoint("TOPLEFT", fr.name, "BOTTOMLEFT", 0, -3)
    fr.sub:SetJustifyH("LEFT")
    fr.sub:SetWordWrap(false)
    fr.subRight = W:Label(fr, "GameFontHighlightSmall")
    fr.subRight:SetPoint("TOPRIGHT", fr.right, "BOTTOMRIGHT", 0, -3)
    fr:SetScript("OnClick", function(self) if self.item and self.item.go then W:Sound("row") self.item.go() end end)
    W:Tip(fr, function(self) return self.item and self.item.tipTitle end, function(self) return self.item and self.item.tipBody end)
    return fr
end

local function FillRow(fr, it)
    if it.kind == "head" or it.kind == "note" then fr.text:SetText(it.text) return end
    fr.icon:SetTexture(it.icon)
    fr.name:SetText(it.name)
    fr.right:SetText(it.right or "")
    fr.sub:SetText(it.sub or "")
    fr.subRight:SetText(it.subRight or "")
    local w = fr:GetWidth() or DETAIL_W
    fr.name:SetWidth(math.max(60, w - 36 - (fr.right:GetStringWidth() or 60) - 14))
    fr.sub:SetWidth(math.max(60, w - 36 - (fr.subRight:GetStringWidth() or 60) - 14))
    if it.mine then fr.shade:SetColorTexture(1, 0.62, 0, 0.12) else fr.shade:SetColorTexture(1, 1, 1, it.index % 2 == 0 and 0.035 or 0) end
end

function P:BuildDetail(frame)
    local d = CreateFrame("Frame", nil, frame)
    d:SetWidth(DETAIL_W)
    d.name = W:Label(d, "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", 0, 0)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.show = W:Card(d, true)
    d.show:SetSize(96, 20)
    d.show:SetPoint("TOPRIGHT", 0, 0)
    d.show:SetBackdropColor(0.12, 0.09, 0.04, 0.9)
    d.show:SetEdge(0.7, 0.58, 0.3, 1)
    d.show.text = W:Label(d.show, "GameFontNormalSmall", "Show on map")
    d.show.text:SetPoint("CENTER")
    d.show:SetScript("OnClick", function()
        if not P.chosen then return end
        W:Sound("click")
        -- Opens the world map on the water (The Fishing Log 1.1.1+); older ones just mark it
        if MF.ShowSpotOnMap then MF:ShowSpotOnMap(P.chosen.key)
        elseif MF.PointToSpot then MF:PointToSpot(P.chosen.key) end
    end)
    W:Tip(d.show, "Show on map", "Opens your world map on this water.")
    d.tag = W:Label(d, "GameFontHighlightSmall")
    d.tag:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.tag:SetWidth(DETAIL_W)
    d.tag:SetJustifyH("LEFT")
    d.frenzy = W:Label(d, "GameFontHighlight")
    d.frenzy:SetPoint("TOPLEFT", d.tag, "BOTTOMLEFT", 0, -8)
    -- In a frenzy, a bar that drains as it runs out, and a line on what it's worth
    d.bar = CreateFrame("StatusBar", nil, d)
    d.bar:SetPoint("TOPLEFT", d.tag, "BOTTOMLEFT", 0, -7)
    d.bar:SetSize(DETAIL_W - 14, 16)
    d.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    d.bar:SetStatusBarColor(1, 0.5, 0.08)
    d.bar:SetMinMaxValues(0, 1)
    d.bar.bg = d.bar:CreateTexture(nil, "BACKGROUND")
    d.bar.bg:SetAllPoints()
    d.bar.bg:SetColorTexture(0.25, 0.1, 0, 0.6)
    d.bar.edge = CreateFrame("Frame", nil, d.bar, "BackdropTemplate")
    d.bar.edge:SetPoint("TOPLEFT", -2, 2)
    d.bar.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    d.bar.edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
    d.bar.edge:SetBackdropBorderColor(1, 0.55, 0.15, 0.9)
    d.bar.text = d.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.bar.text:SetPoint("CENTER", 0, 0)
    d.bar:Hide()
    d.effect = W:Label(d, "GameFontHighlightSmall")
    d.effect:SetPoint("TOPLEFT", d.bar, "BOTTOMLEFT", 0, -5)
    d.effect:SetWidth(DETAIL_W - 14)
    d.effect:SetJustifyH("LEFT")
    d.effect:Hide()
    d.king = W:Label(d, "GameFontHighlight")
    d.king:SetPoint("TOPLEFT", d.frenzy, "BOTTOMLEFT", 0, -6)
    d.king:SetWidth(DETAIL_W)
    d.king:SetJustifyH("LEFT")
    d.king:SetWordWrap(false)
    d.none = W:Label(d, "GameFontDisable", "No water to show yet. Fish anywhere in this zone and it appears here, with its records.")
    d.none:SetPoint("TOPLEFT", 0, -8)
    d.none:SetWidth(DETAIL_W)
    d.none:SetJustifyH("LEFT")
    d.none:Hide()
    d.list = W:VList(d, MakeRow, FillRow)
    d.list:SetPoint("TOPLEFT", d.king, "BOTTOMLEFT", 0, -10)
    d.list:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -14, 0)
    self.detail = d
end

-- Bounties you can enter at this water (the test The Fishing Log's own "Fishing here" uses)
local function Bounties(zone, key)
    local out = {}
    local bests = MF.cdb.records[key] or {}
    for _, kind in ipairs(MF.BOUNTY_KINDS or {}) do
        local _, id, target = MF:Bounty(kind)
        if id and (not target or target == zone) then
            local mode = MF:BountyFormat(kind)
            local collection = mode == "species" or mode == "zone" or mode == "specimenSpecies"
            local native = false
            local f = MF.FISH[id]
            for _, home in ipairs(f and f.zones or {}) do if home == zone then native = true end end
            if collection or target == zone or native or bests[id] or ((MF.cdb.caughtIn[id] or {})[zone] ~= nil) then
                out[#out + 1] = kind
            end
        end
    end
    return out
end

function P:FillDetail(r, zone)
    local d = self.detail
    self.chosen = r
    d:Show()
    for _, region in ipairs({ d.name, d.show, d.tag, d.frenzy, d.king, d.list }) do region:SetShown(r ~= nil) end
    d.none:SetShown(r == nil)
    d.bar:Hide()
    d.effect:Hide()
    if not r then return end
    d.name:SetText(r.name)
    d.name:SetWidth(DETAIL_W - 104)
    local conf, colour = MF:LocationConfidence(r.key)
    if r.unplaced then
        d.tag:SetText("|cffffd100You are here|r   |cffa0a0a0position not saved yet|r")
    else
        d.tag:SetText((r.current and "|cffffd100You are here|r   " or "") .. (colour or "") .. conf .. "|r   |cffa0a0a0" ..
            ("%.1f, %.1f"):format(r.where.x * 100, r.where.y * 100) .. "|r")
    end
    self.frenzyActive = r.active
    self.frenzyAt = r.left and (GetTime() + r.left) or nil
    local burning = r.active and self.frenzyAt and true or false
    d.frenzy:SetShown(not burning)
    d.bar:SetShown(burning)
    d.effect:SetShown(burning)
    d.king:ClearAllPoints()
    d.king:SetPoint("TOPLEFT", burning and d.effect or d.frenzy, "BOTTOMLEFT", 0, burning and -7 or -6)
    if burning then
        local heavier = math.floor(((MF.FRENZY_WEIGHT or 1.2) - 1) * 100 + 0.5)
        local spec = MF.FRENZY_SPECIMEN or 2
        d.effect:SetText(("|cffffb060Fish run %d%% heavier  ·  specimens %s as likely|r"):format(
            heavier, spec == 2 and "twice" or (spec .. " times")))
    end
    self:TickFrenzy()
    local king = MF:King(r.key)
    if king then
        local you = MF:IsMe(king.h)
        d.king:SetText(("|T%s:14:14|t King  %s  |cffffffff%s|r  |cffa0a0a0%s|r"):format(CROWN,
            you and "|cffff9d00You|r" or ("|cffffd100" .. MF:ShortName(king.h) .. "|r"), MF:Weight(king.w), MF:FishName(king.id)))
    else
        d.king:SetText(("|T%s:14:14|t |cffa0a0a0No King yet. The throne is yours to take.|r"):format(CROWN))
    end

    -- Every record here, with your best and the gap; and your bests where there's no record yet
    local items = {}
    local ready = MF:RecordsReady(MF:MapID()) or MF:MapID() == 0
    if not ready and MF.RequestRecords then MF:RequestRecords(MF:MapID()) end
    local bests = MF.cdb.records[r.key] or {}
    local seen, list = {}, {}
    if ready then
        for _, rec in ipairs(MF:SpotRecords(r.key)) do seen[rec.id] = true list[#list + 1] = { id = rec.id, rec = rec } end
    end
    for id in pairs(bests) do if not seen[id] then list[#list + 1] = { id = id } end end
    table.sort(list, function(a, b)
        local wa = a.rec and a.rec.all and a.rec.all.w or (bests[a.id] and bests[a.id].weight) or 0
        local wb = b.rec and b.rec.all and b.rec.all.w or (bests[b.id] and bests[b.id].weight) or 0
        if wa ~= wb then return wa > wb end
        return a.id < b.id
    end)
    if r.current and MF.session and MF.session.outcomes and MF.CastOutcomeSummary then
        items[#items + 1] = { kind = "note", h = 22, text = "This session: " .. MF:CastOutcomeSummary(MF.session) }
    end
    items[#items + 1] = { kind = "head", h = 28, text = ("Records here  |cffa0a0a0%d|r"):format(#list) }
    if not ready then
        items[#items + 1] = { kind = "note", h = 30, text = "Asking other anglers for this water's records..." }
    elseif #list == 0 then
        items[#items + 1] = { kind = "note", h = 30, text = "No records here yet. Be the first!" }
    end
    for i, e in ipairs(list) do
        local all = e.rec and e.rec.all
        local mine = bests[e.id]
        local holder = all and MF:IsMe(all.h)
        local sub, gap
        if holder then
            sub = "|cffff9d00You hold this record|r"
        elseif mine then
            local grade, gc = MF:WeightGradeShort(e.id, mine.weight)
            if mine.specimen then grade, gc = "specimen", "|cffff8000" end
            local you = ("|cff3ee63eyou %s|r%s"):format(MF:Weight(mine.weight), grade and ("  " .. (gc or "") .. grade .. "|r") or "")
            if all then
                gap = all.w - mine.weight
                sub = you .. ("   |cffa0a0a0%s behind|r"):format(MF:Weight(gap))
            else
                sub = you
            end
        else
            sub = "|cff858585you haven't landed one here|r"
        end
        local id = e.id
        items[#items + 1] = { kind = "rec", h = 40, index = i, icon = MF:FishIcon(id), name = MF:FishName(id),
            right = all and ((all.s and (STAR .. " ") or "") .. MF:Weight(all.w)) or "|cff858585no record|r",
            sub = sub, subRight = all and not holder and MF:ShortName(all.h) or nil,
            mine = holder, go = function() MF:ShowCard(id) end, tipTitle = MF:FishName(id),
            tipBody = (gap and (MF:Weight(gap) .. " to beat the record. ") or "") .. "Click for its card." }
    end

    -- Bounties you can enter, at the water you're standing at
    do
        local kinds = Bounties(zone, r.key)
        if #kinds > 0 then items[#items + 1] = { kind = "head", h = 34, text = "Bounties you can enter in this zone" } end
        for i, kind in ipairs(kinds) do
            local standings = MF:BountyStandings(kind)
            local entry = MF:MyBountyBest(kind) or 0
            local lead = standings[1] and standings[1].weight or 0
            local label = kind == "day" and "Daily" or kind == "week" and "Weekly" or "Monthly"
            items[#items + 1] = { kind = "rec", h = 40, index = i, icon = MF:BountyIcon(kind), name = MF:BountyTitle(kind),
                right = label, subRight = MF:FormatSpan(MF:BountyTimeLeft(kind)),
                sub = entry > 0 and ("you " .. MF:BountyScoreText(kind, entry) .. (lead > 0 and ("   lead " .. MF:BountyScoreText(kind, lead)) or ""))
                    or ("not entered" .. (lead > 0 and ("   lead " .. MF:BountyScoreText(kind, lead)) or "")),
                go = function()
                    MF:OpenJournal("bounty")
                    local host = J:Host()
                    for si, k in ipairs(MF.BOUNTY_KINDS) do
                        if k == kind and host.subs and host.subs[si] and host.subs[si]:IsEnabled() then host.subs[si]:Click() end
                    end
                end, tipTitle = MF:BountyTitle(kind), tipBody = "Click for the standings on the Bounties page." }
        end
    end
    d.list:SetItems(items, self.lastKey == r.key)
    self.lastKey = r.key
end

function P:TickFrenzy()
    local d = self.detail
    if not self.frenzyAt then d.frenzy:SetText("|cffa0a0a0No frenzy schedule for this water|r") return end
    local left = math.max(0, self.frenzyAt - GetTime())
    if self.frenzyActive then
        d.frenzy:SetText(("|cffff8000FEEDING FRENZY|r  %s left"):format(MF:FormatClock(left)))
        d.bar:SetValue(math.min(1, left / (MF.FRENZY_LENGTH or 1500)))
        d.bar.text:SetText(("|cffffffffFEEDING FRENZY  %s left|r"):format(MF:FormatClock(left)))
    else
        d.frenzy:SetText(("Next frenzy here in |cffffffff%s|r"):format(MF:FormatClock(left)))
    end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
function P:Build(frame)
    self.frame = frame
    self.title = W:Label(frame, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 4, -2)
    self.tiles = {}
    for i = 1, 3 do self.tiles[i] = ZoneTile(frame) end

    local map = CreateFrame("Frame", nil, frame)
    map.tiles = {}
    if map.SetClipsChildren then map:SetClipsChildren(true) end
    -- The zone's art on a layer of its own, so zooming scales it as one piece
    map.art = CreateFrame("Frame", nil, map)
    map.art:SetFrameLevel(map:GetFrameLevel())
    map.ground = map:CreateTexture(nil, "BACKGROUND", nil, -2)
    map.ground:SetAllPoints()
    map.ground:SetColorTexture(0, 0, 0, 0.35)
    map.edge = CreateFrame("Frame", nil, map, "BackdropTemplate")
    map.edge:SetPoint("TOPLEFT", -4, 4)
    map.edge:SetPoint("BOTTOMRIGHT", 4, -4)
    map.edge:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 16 })
    map.edge:SetFrameLevel(map:GetFrameLevel() + 1)
    map.pins = {}
    map.none = W:Label(map, "GameFontHighlight")
    map.none:SetPoint("CENTER")
    map.none:SetWidth(320)
    map.none:SetText("No waters with a saved position here yet. A genuine catch records where you're standing.")
    -- Your arrow, on a layer above the pins
    map.top = CreateFrame("Frame", nil, map)
    map.top:SetAllPoints()
    map.top:SetFrameLevel(map:GetFrameLevel() + 20)
    map.me = map.top:CreateTexture(nil, "OVERLAY")
    map.me:SetTexture("Interface\\WorldMap\\WorldMapArrow")
    map.me:SetSize(28, 28)
    self.map = map

    -- Scroll to zoom (around the cursor), drag to move, right-click to see the whole zone again
    map.hint = W:Label(map.top, "GameFontHighlightSmall")
    map.hint:SetPoint("BOTTOMRIGHT", -10, 8)
    map.hint:SetAlpha(0.85)
    map.hint:Hide()
    map:EnableMouse(true)
    map:EnableMouseWheel(true)
    map:SetScript("OnMouseWheel", function(_, delta) P:Zoom(delta) end)
    map:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            if (P.zoom or 1) > 1 then W:Sound("click") end
            P.zoom, P.panU, P.panV = 1, 0, 0
            P:LayoutMap()
        elseif button == "LeftButton" and (P.zoom or 1) > 1 then
            local x, y = GetCursorPosition()
            local _, _, _, px, py = P:MapView()
            P.drag = { x = x, y = y, px = px, py = py }
        end
    end)
    map:SetScript("OnMouseUp", function() P.drag = nil end)
    map:SetScript("OnHide", function() P.drag = nil end)
    map:SetScript("OnUpdate", function()
        map.hint:SetShown(P.mapW ~= nil and map:IsMouseOver())
        local d = P.drag
        if not d then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then P.drag = nil return end
        local x, y = GetCursorPosition()
        local s = map:GetEffectiveScale()
        P:Pan(d.px - (x - d.x) / s, d.py + (y - d.y) / s)
    end)

    self.legend = W:Label(frame, "GameFontDisableSmall",
        "|cffffd100Gold glow|r  you are here      |cffff8000Orange ripples|r  frenzy now      |TInterface\\GroupFrame\\UI-Group-LeaderIcon:11:11|t  has a King      |TInterface\\WorldMap\\WorldMapArrow:14:14|t  you")
    self.legend:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -9)

    self:BuildDetail(frame)

    -- Frenzy glows pulse; clocks count down; your arrow follows you
    frame:SetScript("OnUpdate", function(_, elapsed)
        self.age = (self.age or 0) + elapsed
        local a = (ns.db.animations ~= false) and (0.65 + 0.35 * math.sin(self.age * 3)) or 1
        local moving = ns.db.animations ~= false
        for _, p in ipairs(self.map.pins) do
            if p:IsShown() and p.r and p.r.active then
                p.fire:SetAlpha(a)
                for i, ring in ipairs(p.ripples) do
                    if moving then
                        -- Each ring starts small at the pin, spreads to three times its size and fades
                        local k = ((self.age / RIPPLE_TIME) + (i - 1) / RIPPLES) % 1
                        ring:SetSize(PIN * (1 + 2.2 * k), PIN * (1 + 2.2 * k))
                        ring:SetAlpha(0.85 * (1 - k) * (1 - k))
                        ring:Show()
                    else
                        ring:Hide()
                    end
                end
            end
            if p:IsShown() and p.r and p.r.current then p.glow:SetAlpha(a) end
        end
        if self.detail.bar:IsShown() then self.detail.bar:SetAlpha(0.85 + 0.15 * (a - 0.65) / 0.35) end
        self.tick = (self.tick or 0) + elapsed
        if self.tick >= 0.5 then
            self.tick = 0
            self:TickFrenzy()
            self:PlaceMe()
            if self.zoneFrenzyAt then
                local left = self.zoneFrenzyAt - GetTime()
                self.tiles[3].value:SetText(MF:FormatClock(math.max(0, left)))
                -- A frenzy starting or ending changes the glows: rebuild on the next redraw
                if left <= 0 then self.dirty = true end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Zoom. The art scales as one frame; the pins and your arrow keep their size and move with it.
-- The view is kept as the zoom and the top-left corner as a share of the zone, so it survives
-- the window being resized.
-- ---------------------------------------------------------------------------
local ZOOM_MAX = 5

function P:MapView()
    local z = self.zoom or 1
    local cw, ch = (self.mapW or 1) * z, (self.mapH or 1) * z
    return z, cw, ch, (self.panU or 0) * cw, (self.panV or 0) * ch
end

-- A spot on the zone (0-1) to a point on the map frame
function P:ToMap(x, y)
    local _, cw, ch, px, py = self:MapView()
    return x * cw - px, -(y * ch - py)
end

function P:LayoutMap()
    local map = self.map
    if not (map and self.mapW) then return end
    local z, _, _, px, py = self:MapView()
    map.art:SetScale(z)
    map.art:ClearAllPoints()
    map.art:SetPoint("TOPLEFT", map, "TOPLEFT", -px / z, py / z)
    map.art:SetSize(self.mapW, self.mapH)
    for _, p in ipairs(map.pins) do
        if p:IsShown() and p.r then
            p:ClearAllPoints()
            p:SetPoint("CENTER", map, "TOPLEFT", self:ToMap(p.r.where.x, p.r.where.y))
        end
    end
    map.hint:SetText(z > 1 and "Drag to move   Right-click: whole zone" or "Scroll to zoom")
    self:PlaceMe()
end

function P:Pan(px, py)
    if not self.mapW then return end
    local z = self.zoom or 1
    local cw, ch = self.mapW * z, self.mapH * z
    px = math.max(0, math.min(cw - self.mapW, px))
    py = math.max(0, math.min(ch - self.mapH, py))
    self.panU, self.panV = px / cw, py / ch
    self:LayoutMap()
end

-- Zooms in or out about the cursor: the spot under it stays under it
function P:Zoom(delta)
    local map, mw, mh = self.map, self.mapW, self.mapH
    if not (map and mw) then return end
    local x, y = GetCursorPosition()
    local s = map:GetEffectiveScale()
    local cx = math.max(0, math.min(mw, x / s - (map:GetLeft() or 0)))
    local cy = math.max(0, math.min(mh, (map:GetTop() or 0) - y / s))
    local z, cw, ch, px, py = self:MapView()
    local u, v = (px + cx) / cw, (py + cy) / ch
    local nz = math.max(1, math.min(ZOOM_MAX, z * (delta > 0 and 1.25 or 0.8)))
    if nz < 1.05 then nz = 1 end
    if nz == z then return end
    self.zoom = nz
    self:Pan(u * mw * nz - cx, v * mh * nz - cy)
end

function P:PlaceMe()
    local map, me = self.map, self.map.me
    -- ("a and f()" would keep only f's first value)
    local x, y
    if MF.PlayerPos then x, y = MF:PlayerPos(self.mapID) end
    if not self.mapW or type(x) ~= "number" or type(y) ~= "number" or x <= 0 or y <= 0 then me:Hide() return end
    me:ClearAllPoints()
    me:SetPoint("CENTER", map, "TOPLEFT", self:ToMap(x, y))
    local facing = GetPlayerFacing and GetPlayerFacing()
    if type(facing) == "number" and me.SetRotation then me:SetRotation(facing) end
    me:Show()
end

-- This zone's fish: how many of its natives you have, and which are missing
local function ZoneFish(zone)
    local have, total, missing = 0, 0, {}
    local journal = MF.cdb.profile.journal or {}
    for id, f in pairs(MF.FISH) do
        for _, home in ipairs(f.zones or {}) do
            if home == zone then
                total = total + 1
                if journal[id] then have = have + 1 else missing[#missing + 1] = MF:FishName(id) end
                break
            end
        end
    end
    table.sort(missing)
    return have, total, missing
end

function P:Refresh(state)
    local frame, map = self.frame, self.map
    local W0, H0 = frame:GetWidth() or 860, frame:GetHeight() or 460
    local mapID = MF:MapID()
    -- The page is live (The Fishing Log redraws every second), but the clocks, your arrow and the
    -- glows already move on their own (OnUpdate). A full rebuild walks every water on the realm,
    -- so it waits for something to change, or ten seconds (records, Kings and frenzies arriving).
    local cur = MF.CurrentSpot and MF:CurrentSpot()
    local key = table.concat({ tostring(mapID), W0, H0, tostring(MF.localWaterSelected), tostring(state.tab),
        tostring(state.view), tostring(cur and cur.key), tostring(state.MF and state.MF.anglingToolsView) }, "|")
    local now = GetTime()
    if key == self.lastKey and now - (self.lastFull or 0) < 10 and not self.dirty then return end
    self.lastKey, self.lastFull, self.dirty = key, now, nil
    self.mapID = mapID
    -- A new zone starts zoomed out
    if self.zoomMap ~= mapID then self.zoomMap, self.zoom, self.panU, self.panV, self.drag = mapID, 1, 0, 0, nil end
    local rows = MF:LocalWaters(mapID)
    local zoneLabel = MF:ZoneNameFor(mapID) or (GetZoneText and GetZoneText()) or "This zone"
    local zone = MF.ZoneEnglish and MF:ZoneEnglish() or zoneLabel
    self.title:SetText(zoneLabel)

    -- The chosen water: in "Fishing here" or "Records", the one you're at; else The Fishing Log's choice
    local atWater = state.tab == "records" or state.view == "here"
    -- On the Waters tab a clicked pin wins over where you stand, until you move to new water
    local curKey = cur and cur.key
    if state.tab == "records" then
        if MF.localWaterSelected and self.selAt ~= curKey then MF.localWaterSelected = nil end
        if MF.localWaterSelected then
            for _, r in ipairs(rows) do
                if r.key == MF.localWaterSelected then atWater = false break end
            end
        end
    end
    local chosen
    for _, r in ipairs(rows) do
        if (atWater and r.current) or (not atWater and r.key == MF.localWaterSelected) then chosen = r end
    end
    if atWater and not chosen then
        local cur = MF:CurrentSpot()
        if cur and cur.key then
            local active, left = MF:FrenzyPresentationState(cur.key)
            local pos = MF.SpotPosition and MF:SpotPosition(cur.key)
            chosen = { key = cur.key, name = cur.name or "Here", where = pos or { x = 0, y = 0 }, current = true,
                active = active, left = left, unplaced = pos == nil }
        end
    end
    chosen = chosen or rows[1]
    local header = STACK_HEADER + ((chosen and chosen.active) and FRENZY_EXTRA or 0)

    -- Zone tiles
    local have, total, missing = ZoneFish(zone)
    local soon, soonActive, soonRow
    for _, r in ipairs(rows) do
        if r.left and (not soonRow or (r.active and not soonActive) or (r.active == soonActive and r.left < soon)) then
            soon, soonActive, soonRow = r.left, r.active, r
        end
    end
    -- Narrow window: the map beside the detail would be postage-stamp sized, so stack them,
    -- the map across the full width and the water's detail underneath
    -- (and only when that really gives a bigger map: a short window is better side by side)
    local art = MapArt(mapID)
    local aw, ah = art and art.w or 1002, art and art.h or 668
    local sideW = math.min(W0 - DETAIL_W - 36, (H0 - 112) * aw / ah)
    local stackW = math.min(W0 - 12, (H0 - 116 - header - STACK_LIST_MIN) * aw / ah)
    local stacked = W0 - DETAIL_W - 36 < STACK_BELOW and stackW > sideW
    self.stacked = stacked
    local mapW0 = stacked and (W0 - 12) or (W0 - DETAIL_W - 36)
    local tw = (mapW0 - 16) / 3
    for i, t in ipairs(self.tiles) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", 4 + (i - 1) * (tw + 8), -28)
        t:SetSize(tw, 46)
        t.label:SetWidth(tw - 10)
        t.label:SetWordWrap(false)
    end
    local t1 = self.tiles[1]
    t1.value:SetText(("%d / %d"):format(have, total))
    if total > 0 and have >= total then t1.value:SetTextColor(0.25, 0.9, 0.25) else t1.value:SetTextColor(1, 1, 1) end
    t1.label:SetText("fish of this zone")
    t1.tip = { "Fish of " .. zoneLabel, total == 0 and "No native fish list for this zone yet."
        or (#missing == 0 and "You have every one of them." or ("Still to catch: " .. table.concat(missing, ", "))) }
    t1.go = ns.ShowZoneFish and function() ns.ShowZoneFish(zone) end or nil
    local t2 = self.tiles[2]
    t2.value:SetText(tostring(#rows))
    t2.label:SetText(#rows == 1 and "water known" or "waters known")
    t2.tip = { "Waters known", "Waters with a saved position in this zone. Your catches add the ones you fish; other anglers share theirs." }
    t2.go = nil
    local t3 = self.tiles[3]
    if soonRow then
        self.zoneFrenzyAt = GetTime() + soon
        t3.value:SetText(MF:FormatClock(soon))
        if soonActive then t3.value:SetTextColor(1, 0.55, 0.1) else t3.value:SetTextColor(1, 1, 1) end
        t3.label:SetText((soonActive and "frenzy now: " or "next frenzy: ") .. soonRow.name)
        t3.tip = { "Feeding frenzy", ("Every water gets %d minutes in every %d hours, on its own schedule."):format(
            math.floor((MF.FRENZY_LENGTH or 900) / 60), math.floor((MF.FRENZY_CYCLE or 7200) / 3600)),
            "Fish run heavier and specimens are twice as likely while it lasts." }
        local key = soonRow.key
        t3.go = function() SelectWater(key) end
    else
        self.zoneFrenzyAt = nil
        t3.value:SetText("|cffa0a0a0-|r")
        t3.value:SetTextColor(1, 1, 1)
        t3.label:SetText("no frenzy water known here")
        t3.tip, t3.go = nil, nil
    end

    -- Size the map to the room, keeping the zone's shape
    local roomH = stacked and (H0 - 116 - header - STACK_LIST_MIN) or (H0 - 112)
    local mapW = math.min(mapW0, roomH * aw / ah)
    local mapH = mapW * ah / aw
    map:ClearAllPoints()
    map:SetPoint("TOPLEFT", 6, -84)
    map:SetSize(mapW, mapH)
    self.mapW, self.mapH = mapW, mapH
    local k = mapW / aw
    local used = 0
    if art then
        for i, file in ipairs(art.tiles) do
            local t = map.tiles[i]
            if not t then t = map.art:CreateTexture(nil, "BACKGROUND", nil, -1) map.tiles[i] = t end
            t:SetTexture(file)
            t:SetSize(art.tw * k, art.th * k)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", ((i - 1) % art.cols) * art.tw * k, -math.floor((i - 1) / art.cols) * art.th * k)
            t:Show()
            used = i
        end
    end
    for i = used + 1, #map.tiles do map.tiles[i]:Hide() end

    -- Every overlay of the zone on top, so the map is fully explored whatever you've walked
    map.reveal = map.reveal or {}
    local shown = 0
    local okArt, artID = false, nil
    if art and ns.MapRevealData and C_Map.GetMapArtID then okArt, artID = pcall(C_Map.GetMapArtID, mapID) end
    local overlays = okArt and ns.MapRevealData[artID]
    if overlays then
        local function FileSize(px) local s = 16 while s < px do s = s * 2 end return s end
        for _, o in ipairs(overlays) do
            local w, h, ox, oy = o[1], o[2], o[3], o[4]
            local cols, rowsN = math.ceil(w / art.tw), math.ceil(h / art.th)
            for row = 0, rowsN - 1 do
                for col = 0, cols - 1 do
                    local file = o[5 + row * cols + col]
                    if file then
                        local pw = col == cols - 1 and (w - col * art.tw) or art.tw
                        local ph = row == rowsN - 1 and (h - row * art.th) or art.th
                        local fw = col == cols - 1 and FileSize(pw) or art.tw
                        local fh = row == rowsN - 1 and FileSize(ph) or art.th
                        shown = shown + 1
                        local t = map.reveal[shown]
                        if not t then t = map.art:CreateTexture(nil, "BACKGROUND", nil, 0) map.reveal[shown] = t end
                        t:SetTexture(file)
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t:SetSize(pw * k, ph * k)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", (ox + col * art.tw) * k, -(oy + row * art.th) * k)
                        t:Show()
                    end
                end
            end
        end
    end
    for i = shown + 1, #map.reveal do map.reveal[i]:Hide() end

    for i, r in ipairs(rows) do
        local p = map.pins[i]
        if not p then p = Pin(map) map.pins[i] = p end
        p.r = r
        p:SetFrameLevel(map:GetFrameLevel() + (r.current and 8 or (r == chosen and 7 or 5)))
        p.glow:SetShown(r.current and true or false)
        p.fire:SetShown(r.active and true or false)
        if not r.active then for _, ring in ipairs(p.ripples) do ring:Hide() end end
        p.sel:SetShown(r == chosen)
        p.crown:SetShown(MF:King(r.key) ~= nil)
        -- The ring wears the glow's colour: orange in a frenzy (that wins), bright gold where you are
        if r.active then p.round.ring:SetVertexColor(1, 0.5, 0.1)
        elseif r.current then p.round.ring:SetVertexColor(1, 0.9, 0.3)
        else p.round.ring:SetVertexColor(1, 1, 1) end
        p:Show()
    end
    for i = #rows + 1, #map.pins do map.pins[i]:Hide() map.pins[i].r = nil end
    map.none:SetShown(#rows == 0)
    self:LayoutMap()

    local d = self.detail
    d:ClearAllPoints()
    d.list:ClearAllPoints()
    if stacked then
        -- The water's heading (name, frenzy, King) above the map, the map centred in the
        -- width it was given, and the records and bounties below its legend
        d:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -84)
        d:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 0)
        map:ClearAllPoints()
        map:SetPoint("TOP", frame, "TOPLEFT", 6 + mapW0 / 2, -84 - header)
        d.list:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -84 - header - mapH - 32)
        d.list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 0)
    else
        d:SetWidth(DETAIL_W)
        d:SetPoint("TOPLEFT", frame, "TOPLEFT", mapW0 + 30, -2)
        d:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", mapW0 + 30, 0)
        d.list:SetPoint("TOPLEFT", d.king, "BOTTOMLEFT", 0, -10)
        d.list:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -14, 0)
    end
    self:FillDetail(chosen, zone)
    self.count = #rows
end

J:AddPage({
    key = "waters",
    live = true, -- frenzy clocks, your position
    match = function(state)
        if state.recap then return false end
        if state.tab == "records" then return true end
        if state.tab ~= "journal" then return false end
        return state.view == "tools" and (state.MF.anglingToolsView or "waters") == "waters"
    end,
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function(_, state) P:Refresh(state) end,
    subheading = function() return "" end, -- (the zone's name is the page's title)
    count = function() return P.count and ((P.count == 1) and "1 water" or (P.count .. " waters")) or "" end,
})
