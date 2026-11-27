-- Records: the water you're at, as a trophy wall.
--   top    the King of this spot: crown, holder, fish and weight (or an open throne)
--   Here         every record here as a card: the record and who holds it, your best and how far
--                behind you are (a bar), this season's record when it's someone else's
--   Other spots  the zone's other spots: each one's King, its records and how many are yours;
--                click one to find it on the map
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.Records = P
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"

local function RecordCard(parent)
    local c = W:Card(parent)
    c.icon = W:FramedIcon(c, 34)
    c.icon:SetPoint("LEFT", 12, 0)
    c.name = W:Label(c, "GameFontNormal")
    c.name:SetPoint("TOPLEFT", 58, -9)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.weight = W:Label(c, "GameFontHighlightLarge")
    c.weight:SetPoint("TOPRIGHT", -14, -8)
    c.holder = W:Label(c, "GameFontHighlightSmall")
    c.holder:SetPoint("TOPRIGHT", c.weight, "BOTTOMRIGHT", 0, -3)
    c.mine = W:Label(c, "GameFontHighlightSmall")
    c.mine:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5)
    c.mine:SetJustifyH("LEFT")
    c.bar = W:Bar(c, 120, 8, 0.25, 0.8, 0.25)
    c.bar.text:SetText("")
    c.bar:SetPoint("LEFT", c.mine, "RIGHT", 8, 0)
    c.season = W:Label(c, "GameFontDisableSmall")
    c.season:SetPoint("BOTTOMRIGHT", -14, 7)
    return c
end

local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t"

-- One spot in the zone, the width of the page: where it is and its King on
-- the left, how many records it holds (and how many are yours) on the right.
local function SpotRow(parent)
    local r = W:Card(parent, true)
    r:SetBackdropColor(0.03, 0.04, 0.08, 0.5)
    r.pin = r:CreateTexture(nil, "ARTWORK")
    r.pin:SetSize(16, 16)
    r.pin:SetPoint("LEFT", 12, 0)
    r.pin:SetTexture("Interface\\Minimap\\Tracking\\None")
    if not W:Atlas(r.pin, "Waypoint-MapPin-Untracked") then r.pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01") r.pin:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    r.count = W:Label(r, "GameFontHighlight")
    r.count:SetPoint("TOPRIGHT", -14, -8)
    r.count:SetJustifyH("RIGHT")
    r.yours = W:Label(r, "GameFontHighlightSmall")
    r.yours:SetPoint("TOPRIGHT", r.count, "BOTTOMRIGHT", 0, -3)
    r.yours:SetJustifyH("RIGHT")
    r.name = W:Label(r, "GameFontNormal")
    r.name:SetPoint("TOPLEFT", 38, -8)
    r.name:SetPoint("RIGHT", r, "RIGHT", -110, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.king = W:Label(r, "GameFontHighlightSmall")
    r.king:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.king:SetPoint("RIGHT", r, "RIGHT", -110, 0)
    r.king:SetJustifyH("LEFT")
    r.king:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
        local it = self.item
        if it and it.key then W:Sound("row") MF:PointToSpot(it.key) end
    end)
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(it.label, 1, 0.82, 0)
        if it.label:find("location unknown", 1, true) then
            GameTooltip:AddLine("Nobody has shared where this water is yet.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Click to mark it on your map.", 0.4, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return r
end

local function Make(kind)
    if kind == "record" then return RecordCard() end
    if kind == "spot" then return SpotRow() end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, "GameFontHighlight")
    fr.text:SetPoint("CENTER")
    fr.text:SetTextColor(0.6, 0.6, 0.6)
    fr.text:SetWidth(360)
    return fr
end

local function FillSpot(fr, it)
    fr.item = it
    fr.name:SetText(it.label)
    local k = it.king
    if k then
        local you = MF:IsMe(k.h)
        fr.king:SetText(("%s %s  |cffa0a0a0%s|r  |cffffd100%s|r"):format(CROWN,
            you and "|cffff9d00You|r" or ("|cffffffff" .. MF:ShortName(k.h) .. "|r"), MF:FishName(k.id), MF:Weight(k.w)))
        fr:SetEdge(you and 1 or 0.5, you and 0.62 or 0.42, you and 0.1 or 0.25, you and 0.95 or 0.6)
    else
        fr.king:SetText("|cff858585No King yet|r")
        fr:SetEdge(0.5, 0.42, 0.25, 0.6)
    end
    fr.count:SetText(it.records == 1 and "1 record" or (it.records .. " records"))
    fr.yours:SetText(it.yours > 0 and ("|cffff9d00%d yours|r"):format(it.yours) or "")
end

local function Fill(fr, it)
    if it.kind == "note" then fr.text:SetText(it.text) return end
    if it.kind == "spot" then FillSpot(fr, it) return end
    local r, mine = it.r, it.mine
    fr.icon.icon:SetTexture(MF:FishIcon(r.id))
    fr.name:SetText(MF:FishName(r.id))
    local all = r.all
    if all then
        fr.weight:SetText((all.s and (STAR .. " ") or "") .. "|cffffd100" .. MF:Weight(all.w) .. "|r")
        local you = MF:IsMe(all.h)
        fr.holder:SetText(you and "|cffff9d00yours|r" or MF:ShortName(all.h))
        fr:SetEdge(you and 1 or 0.5, you and 0.62 or 0.42, you and 0.1 or 0.25, 0.95)
    else
        fr.weight:SetText("|cff858585open|r")
        fr.holder:SetText("")
        fr:SetEdge(0.5, 0.42, 0.25, 0.9)
    end
    if mine and all and not MF:IsMe(all.h) then
        fr.mine:SetText(("|cff3ee63eyou %s|r  |cffa0a0a0%s behind|r"):format(MF:Weight(mine.weight), MF:Weight(all.w - mine.weight)))
        fr.bar:Show()
        fr.bar:Set(mine.weight, all.w, "")
    elseif all and MF:IsMe(all.h) then
        fr.mine:SetText("|cffff9d00You hold this record|r")
        fr.bar:Hide()
    else
        fr.mine:SetText("|cff858585You haven't landed one here|r")
        fr.bar:Hide()
    end
    if r.seasonDiffers and r.season then
        fr.season:SetText(("this season: %s, %s"):format(MF:Weight(r.season.w), MF:ShortName(r.season.h)))
    else
        fr.season:SetText("")
    end
end

function P:Build(frame)
    local hero = W:Panel(frame, 0.85)
    hero:SetPoint("TOPLEFT")
    hero:SetPoint("TOPRIGHT")
    hero:SetHeight(86)
    hero.icon = W:FramedIcon(hero, 50, "Interface\\Icons\\INV_Crown_01")
    hero.icon:SetPoint("LEFT", 18, 0)
    hero.kicker = W:Label(hero, "GameFontNormalSmall")
    hero.kicker:SetPoint("TOPLEFT", 84, -14)
    hero.kicker:SetTextColor(0.8, 0.8, 0.8)
    hero.title = W:Label(hero, "GameFontNormalLarge")
    hero.title:SetPoint("TOPLEFT", hero.kicker, "BOTTOMLEFT", 0, -4)
    hero.line = W:Label(hero, "GameFontHighlight")
    hero.line:SetPoint("TOPLEFT", hero.title, "BOTTOMLEFT", 0, -5)
    hero.season = W:Label(hero, "GameFontDisableSmall")
    hero.season:SetPoint("TOPRIGHT", -16, -14)
    hero.count = W:Label(hero, "GameFontHighlightHuge")
    hero.count:SetPoint("RIGHT", -16, -6) -- one right edge with the season line
    hero.countLabel = W:Label(hero, "GameFontDisableSmall")
    hero.countLabel:SetPoint("TOPRIGHT", hero.count, "BOTTOMRIGHT", 0, -2)
    self.hero = hero

    -- One list, the page's full width: this water's records, or the zone's other spots
    self.list = W:VList(frame, Make, Fill)
    self.list:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -8)
    self.list:SetPoint("BOTTOMRIGHT", -14, 0)
end

-- Which list: "here" (this water's records) or "spots" (the zone's other
-- spots). The journal opens on Here each time; within a visit it stays put.
P.view = "here"

function P:SetView(view)
    if self.view == view then return end
    self.view = view
    J.lastSig = nil
    J:Render()
end

local function HereView(self, key, sub, mapID, ready)
    local hero = self.hero
    hero.kicker:SetText("RECORDS AT")
    hero.title:SetText(sub or "Here")
    local king = ready and MF:King(key)
    if not ready then
        hero.line:SetText("|cffa0a0a0Asking other anglers for this water's records...|r")
        hero.icon.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    elseif king then
        hero.icon.icon:SetTexture("Interface\\Icons\\INV_Crown_01")
        local you = MF:IsMe(king.h)
        hero.line:SetText(("%s King %s  |cffa0a0a0%s|r  |cffffd100%s|r"):format(CROWN,
            you and "|cffff9d00You|r" or ("|cffffffff" .. MF:ShortName(king.h) .. "|r"), MF:FishName(king.id), MF:Weight(king.w)))
    else
        hero.icon.icon:SetTexture("Interface\\Icons\\INV_Crown_01")
        hero.line:SetText("|cffa0a0a0No King here yet. The throne is yours to take.|r")
    end

    local items, held = {}, 0
    if ready then
        local myBests = MF.cdb.records[key] or {}
        for _, r in ipairs(MF:SpotRecords(key)) do
            items[#items + 1] = { kind = "record", h = 54, gap = 6, r = r, mine = myBests[r.id] }
            if r.all and MF:IsMe(r.all.h) then held = held + 1 end
        end
        if #items == 0 then items[1] = { kind = "note", h = 80, text = "No records here yet. Be the first!" } end
    else
        items[1] = { kind = "note", h = 80, text = "Waiting for records from other anglers..." }
    end
    local n = (#items > 0 and items[1].kind == "record") and #items or 0
    hero.count:SetText(ready and tostring(n) or "")
    hero.countLabel:SetText(ready and (held > 0 and ("records, " .. held .. " yours") or "records") or "")
    self.counted = n == 1 and "1 record" or (n .. " records")
    return items
end

local function SpotsView(self, key, sub, mapID, ready)
    local hero = self.hero
    local zone = MF:MapName(mapID)
    hero.kicker:SetText("OTHER SPOTS IN")
    hero.title:SetText(zone)
    hero.icon.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")

    local items, kings = {}, 0
    if ready then
        for _, o in ipairs(MF:OtherSpots(key, mapID)) do
            local records, yours = 0, 0
            for _, r in ipairs(MF:SpotRecords(o.key)) do
                if r.all then
                    records = records + 1
                    if MF:IsMe(r.all.h) then yours = yours + 1 end
                end
            end
            local king = MF:King(o.key)
            if king and MF:IsMe(king.h) then kings = kings + 1 end
            items[#items + 1] = { kind = "spot", h = 46, gap = 5, key = o.key, label = o.label,
                king = king, records = records, yours = yours }
        end
        if #items == 0 then items[1] = { kind = "note", h = 80, text = "No other spots in this zone heard of yet." } end
    else
        items[1] = { kind = "note", h = 80, text = "Waiting for records from other anglers..." }
    end
    local n = (#items > 0 and items[1].kind == "spot") and #items or 0
    if not ready then
        hero.line:SetText("|cffa0a0a0Asking other anglers for this zone's records...|r")
    elseif n == 0 then
        hero.line:SetText("|cffa0a0a0Nowhere else here has a record yet.|r")
    else
        hero.line:SetText(kings > 0 and ("%s You're King of |cffff9d00%d|r of them"):format(CROWN, kings)
            or "|cffa0a0a0You aren't King anywhere else here yet.|r")
    end
    hero.count:SetText(ready and tostring(n) or "")
    hero.countLabel:SetText(ready and (n == 1 and "spot" or "spots") or "")
    self.counted = n == 1 and "1 spot" or (n .. " spots")
    return items
end

function P:Refresh(state)
    local key, sub, mapID = MF:SpotInfo()
    self.hero.season:SetText(("%s, %s left"):format(MF:SeasonName(), MF:SeasonLeft()))
    local ready = MF:RecordsReady(mapID)
    local view = self.view == "spots" and SpotsView or HereView
    local items = view(self, key, sub, mapID, ready)
    self.items = items
    self.list:SetItems(items, true)
end

J:AddPage({
    key = "records",
    match = function(state) return not state.recap and state.tab == "records" end,
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function(_, state) P:Refresh(state) end,
    subheading = function() return P.view == "spots" and "Other spots" or "This water" end,
    count = function() return P.counted or "" end,
    onOpen = function() P.view = "here" end,
})
