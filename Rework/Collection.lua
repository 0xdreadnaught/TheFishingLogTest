-- The Collection: the journal's fish, as a collections journal would show them.
--   left    waters (all, trophies, then every zone, the one you're in marked), with how many you have
--   middle  a grid of fish: caught in full colour with their edition's rim, missing ones as shadows
--   right   the fish you picked: best, specimen, where it came from, where it lives, the realm's best
-- Replaces The Fishing Log's zone / fish / album lists. Search, "Fishing here", tools and goals are
-- still its own pages (the footer buttons go there).
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local TILE_W, TILE_H, GAP = 84, 100, 6
-- No detail column any more: a fish's card opens beside the journal instead.
local SIDE_W = 176
local STAR_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local SPEC = { 1, 0.5, 0 }

local FILTERS = { { "all", "All" }, { "caught", "Caught" }, { "missing", "Missing" }, { "specimens", "Specimens" } }

-- ---------------------------------------------------------------------------
-- Data: every fish worth collecting, the waters they live in, what you have
-- ---------------------------------------------------------------------------
local data -- rebuilt on every refresh (cheap: tens of fish)

local function HexColor(code)
    local r, g, b = (code or ""):match("|cff(%x%x)(%x%x)(%x%x)")
    if not r then return 0.73, 0.73, 0.73 end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function Collect()
    local journal = MF.cdb.profile.journal or {}
    local caughtIn = MF.cdb.caughtIn or {}
    local fish, byId, zones = {}, {}, {}
    local function Add(id, trophy)
        if byId[id] then return end
        local spec = MF.FISH[id]
        local j = journal[id]
        local e = {
            id = id, trophy = trophy, info = spec, j = j, caught = j ~= nil,
            -- j.s is the weight of your best specimen (0 / nil: none yet)
            count = j and j.c or 0, best = j and j.b or 0, specimens = j and tonumber(j.s) or 0,
            order = spec and spec.max or (trophy and (MF.TROPHY[id] or 50)) or 99,
            zones = {},
        }
        for _, z in ipairs(spec and spec.zones or {}) do e.zones[z] = true end
        for _, z in ipairs(MF.FISH_LISTED_IN[id] or {}) do e.zones[z] = true end
        -- No zone list: it bites almost anywhere, so it's one of every water's fish
        e.anywhere = not trophy and MF:BitesAnywhere(id)
        for z in pairs(caughtIn[id] or {}) do e.zones[z] = true end
        for z in pairs(e.zones) do zones[z] = true end
        if e.caught then
            local _, colour = MF:Edition(id, e.best, e.specimens > 0)
            e.r, e.g, e.b = HexColor(colour)
            if e.specimens > 0 then e.r, e.g, e.b = SPEC[1], SPEC[2], SPEC[3] end
        end
        byId[id] = e
        fish[#fish + 1] = e
    end
    for id in pairs(MF.FISH) do Add(id, false) end
    for id in pairs(MF.TROPHY or {}) do Add(id, true) end
    -- Anything else you've landed that the addon counts as a fish
    for id in pairs(journal) do
        if not byId[id] and not (MF.IsJunkItem and MF:IsJunkItem(id)) then Add(id, false) end
    end
    for _, e in ipairs(fish) do e.name = MF:FishName(e.id) end
    table.sort(fish, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    local zoneList = {}
    for z in pairs(zones) do zoneList[#zoneList + 1] = z end
    table.sort(zoneList)
    data = { fish = fish, byId = byId, zones = zoneList }
end

local function InZone(e, zone)
    if zone == "all" then return not e.trophy end
    if zone == "trophy" then return e.trophy end
    return e.zones[zone] == true or (e.anywhere and not e.trophy) or false
end

local function Matches(e, filter, query)
    if filter == "caught" and not e.caught then return false end
    if filter == "missing" and e.caught then return false end
    if filter == "specimens" and e.specimens == 0 then return false end
    if query ~= "" then
        if e.name:lower():find(query, 1, true) then return true end
        for z in pairs(e.zones) do if z:lower():find(query, 1, true) then return true end end
        return false
    end
    return true
end

-- How many of each water's fish you have: every water in one pass over the fish
local function Tallies()
    local t = { all = { 0, 0 }, trophy = { 0, 0 } }
    for _, e in ipairs(data.fish) do
        local bucket = e.trophy and t.trophy or t.all
        bucket[2] = bucket[2] + 1
        if e.caught then bucket[1] = bucket[1] + 1 end
        if not e.trophy then
            local function Count(z)
                local zt = t[z]
                if not zt then zt = { 0, 0 } t[z] = zt end
                zt[2] = zt[2] + 1
                if e.caught then zt[1] = zt[1] + 1 end
            end
            if e.anywhere then
                for _, z in ipairs(data.zones) do Count(z) end
            else
                for z in pairs(e.zones) do Count(z) end
            end
        end
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Building blocks
-- ---------------------------------------------------------------------------
local P = {}
ns.Collection = P

local function ZoneRow(row)
    W:Row(row)
    row.label = W:Label(row, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", -44, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.tally = W:Label(row, "GameFontHighlightSmall")
    row.tally:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnClick", function(self)
        if not self.item then return end
        W:Sound("tab")
        ns.db.collectionZone = self.item.key
        P.scroll = 0
        P:Refresh()
    end)
end

local function FillZone(row, item)
    row.label:SetText(item.label)
    local here = item.key == P.here
    if item.key == "all" or item.key == "trophy" then
        row.label:SetTextColor(1, 0.82, 0)
    elseif here then
        row.label:SetTextColor(0.4, 0.8, 1)
    else
        row.label:SetTextColor(1, 1, 1)
    end
    local done = item.total > 0 and item.have >= item.total
    row.tally:SetText(("%d/%d"):format(item.have, item.total))
    if done then row.tally:SetTextColor(0.25, 0.9, 0.25) else row.tally:SetTextColor(0.7, 0.7, 0.7) end
    row.sel:SetShown(item.key == (ns.db.collectionZone or "all"))
end

local function NewTile(parent)
    local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
    t:SetSize(TILE_W, TILE_H)
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    t:SetBackdropColor(0, 0, 0, 0.45)
    t.sel = t:CreateTexture(nil, "BACKGROUND", nil, 1)
    t.sel:SetPoint("TOPLEFT", 2, -2)
    t.sel:SetPoint("BOTTOMRIGHT", -2, 2)
    t.sel:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    t.sel:SetBlendMode("ADD")
    t.sel:SetVertexColor(1, 0.82, 0.3)
    t.sel:SetAlpha(0.35)
    t.sel:Hide()
    t.icon = W:FramedIcon(t, 42)
    t.icon:SetPoint("TOP", 0, -12)
    t.name = W:Label(t, "GameFontHighlightSmall")
    t.name:SetPoint("TOP", t.icon, "BOTTOM", 0, -9)
    t.name:SetWidth(TILE_W - 8)
    t.name:SetHeight(22)
    t.name:SetJustifyV("TOP")
    t.name:SetMaxLines(2)
    t.weight = W:Label(t, "GameFontNormalSmall")
    t.weight:SetPoint("BOTTOM", 0, 6)
    t.star = t:CreateTexture(nil, "OVERLAY", nil, 3)
    t.star:SetTexture(STAR_TEX)
    t.star:SetSize(14, 14)
    t.star:SetPoint("TOPRIGHT", -4, -4)
    t.flash = t:CreateTexture(nil, "OVERLAY", nil, 4)
    t.flash:SetPoint("TOPLEFT", 2, -2)
    t.flash:SetPoint("BOTTOMRIGHT", -2, 2)
    t.flash:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    t.flash:SetBlendMode("ADD")
    t.flash:SetAlpha(0)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t:SetScript("OnClick", function(self, button)
        local e = self.entry
        if not e then return end
        W:Sound("row")
        -- The card is this page's detail view: click a fish for it, click
        -- the same fish again to put it away.
        if P.selected == e.id and MF.CardFish and MF:CardFish() == e.id then
            MF:HideCard()
            return
        end
        P:Select(e.id)
        MF:ShowCard(e.id)
    end)
    t:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- A glance without a click: the card has the rest
        if e.caught then
            GameTooltip:SetText(e.name, e.r or 1, e.g or 1, e.b or 1)
            GameTooltip:AddDoubleLine("Caught", tostring(e.count), 0.8, 0.8, 0.8, 1, 1, 1)
            -- Your best already counts your specimens, so it is nearly always
            -- the specimen itself: one line, starred. Only a frenzy catch of a
            -- night or day fish at its hour can outweigh a light specimen, and
            -- then both are worth showing.
            local starred = e.specimens > 0 and e.specimens >= e.best
            GameTooltip:AddDoubleLine("Your best", MF:Weight(e.best) .. (starred and "  |T" .. STAR_TEX .. ":12:12|t" or ""),
                0.8, 0.8, 0.8, 1, starred and 0.5 or 0.82, 0)
            if e.specimens > 0 and not starred then
                GameTooltip:AddDoubleLine("Best specimen", MF:Weight(e.specimens), 0.8, 0.8, 0.8, 1, 0.5, 0)
            end
        else
            GameTooltip:SetText("Not caught yet", 0.6, 0.6, 0.6)
            local n = 0
            for _ in pairs(e.zones) do n = n + 1 end
            if e.anywhere then GameTooltip:AddLine("Bites almost anywhere.", 1, 1, 1)
            elseif n > 0 then GameTooltip:AddLine(("Lives in %d %s."):format(n, n == 1 and "water" or "waters"), 1, 1, 1) end
        end
        GameTooltip:AddLine("Click for its card", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function(self) W:HideTip(self) end)
    W:Glow(t, 0) -- after SetScript: it hooks OnEnter/OnLeave
    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(_, d) P:Wheel(d) end)
    return t
end

local function FillTile(t, e)
    t.entry = e
    local icon = MF:FishIcon(e.id)
    t.icon.icon:SetTexture(icon)
    t.icon.icon:SetDesaturated(not e.caught)
    if e.caught then
        t.icon.icon:SetVertexColor(1, 1, 1)
        -- The rim wears the fish's edition, as its card does. The gold art is
        -- greyed first so the tint comes out true rather than muddied by the gold.
        t.icon.rim:SetDesaturated(true)
        t.icon.rim:SetVertexColor(e.r or 0.7, e.g or 0.7, e.b or 0.7)
        t.name:SetText(e.name)
        t.name:SetTextColor(1, 1, 1)
        -- With a water chosen, your best from that water (as The Fishing Log's zone view showed)
        local zone = ns.db.collectionZone
        local here = zone and zone ~= "all" and zone ~= "trophy" and MF.cdb.caughtIn[e.id] and MF.cdb.caughtIn[e.id][zone]
        if zone and zone ~= "all" and zone ~= "trophy" then
            t.weight:SetText(here and here.b and MF:Weight(here.b) or "|cff858585not here yet|r")
        else
            t.weight:SetText(MF:Weight(e.best))
        end
        -- The rim carries the edition now; the tile's edge stays quiet
        t:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        t:SetBackdropColor(0, 0, 0, 0.45)
    else
        -- A shadow of the fish: you can see its shape, not what it is
        t.icon.icon:SetVertexColor(0.12, 0.12, 0.14)
        -- Tiles are reused as the grid scrolls, so the grey must be set both ways
        t.icon.rim:SetDesaturated(true)
        t.icon.rim:SetVertexColor(0.45, 0.45, 0.45)
        t.name:SetText("???")
        t.name:SetTextColor(0.45, 0.45, 0.45)
        t.weight:SetText("")
        t:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        t:SetBackdropColor(0, 0, 0, 0.3)
    end
    t.star:SetShown(e.specimens > 0)
    t.sel:SetShown(P.selected == e.id)
    -- Newly caught since you last looked: a flash
    if e.caught and P.known and not P.known[e.id] and ns.db.animations ~= false then
        W:Tween(t.flash, 1.2, function(x) t.flash:SetAlpha(0.9 * (1 - x)) end)
    end
    t:Show()
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
function P:Select(id)
    self.selected = id
    for _, t in ipairs(self.tiles) do
        if t.entry then t.sel:SetShown(t.entry.id == id) end
    end
end

function P:Wheel(delta)
    local maxS = math.max(0, (self.contentH or 0) - (self.clip:GetHeight() or 0))
    self.target = math.max(0, math.min(maxS, (self.target or 0) - delta * (TILE_H + GAP) * 0.75))
end

function P:Build(frame)
    self.frame = frame
    -- Waters
    local side = W:Panel(frame, 0.75)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDE_W)
    local sideTitle = W:Header(side, "Waters", SIDE_W - 24)
    sideTitle:SetPoint("TOPLEFT", 12, -10)
    self.zones = W:List(side, 22, ZoneRow, FillZone)
    self.zones:SetPoint("TOPLEFT", 6, -32)
    self.zones:SetPoint("BOTTOMRIGHT", -6, 6)

    -- Top bar: search, filters, progress
    local top = CreateFrame("Frame", nil, frame)
    top:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(26)
    self.search = W:Search(top, 150, function(text)
        self.query = strtrim(text or ""):lower()
        self.scroll, self.target = 0, 0
        if self.built then self:Refresh() end
    end, "Search")
    self.search:SetPoint("LEFT", 6, 0)
    -- A boxed four-way switch (a filter, so it doesn't look like another row of tabs)
    local box = CreateFrame("Frame", nil, top, "BackdropTemplate")
    box:SetHeight(20)
    box:SetPoint("LEFT", self.search, "RIGHT", 10, 0)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    box:SetBackdropColor(0, 0, 0, 0.5)
    box:SetBackdropBorderColor(0.55, 0.47, 0.3, 1)
    self.filters = {}
    local prev
    local boxW = 4
    for i, f in ipairs(FILTERS) do
        local b = CreateFrame("Button", nil, box)
        b:SetHeight(16)
        b.text = W:Label(b, "GameFontHighlightSmall", f[2])
        b.text:SetPoint("CENTER")
        b:SetWidth((b.text:GetStringWidth() or 40) + 16)
        boxW = boxW + b:GetWidth()
        b.line = b:CreateTexture(nil, "BACKGROUND")
        b.line:SetAllPoints()
        b.line:SetColorTexture(1, 0.82, 0, 0.22)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        if i > 1 then
            local sep = box:CreateTexture(nil, "ARTWORK")
            sep:SetWidth(1)
            sep:SetColorTexture(0.55, 0.47, 0.3, 1)
            sep:SetPoint("TOP", b, "TOPLEFT", 0, 0)
            sep:SetPoint("BOTTOM", b, "BOTTOMLEFT", 0, 0)
        end
        b.key = f[1]
        b:SetScript("OnClick", function()
            W:Sound("tab")
            ns.db.collectionFilter = f[1]
            self.scroll, self.target = 0, 0
            self:Refresh()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("LEFT", box, "LEFT", 2, 0) end
        prev = b
        self.filters[i] = b
    end
    box:SetWidth(boxW)

    -- Your collection in brief, at the right of the Waters heading. It was a
    -- bar across the top of the detail column, which ran into the filters on
    -- a narrow journal - and its species count is "All waters" just below.
    -- Hover for the whole tally and your latest specimen, click for its card.
    self.progress = CreateFrame("Button", nil, side)
    self.progress:SetHeight(16)
    self.progress:SetPoint("TOPRIGHT", -12, -10)
    self.progress.text = W:Label(self.progress, "GameFontHighlightSmall")
    self.progress.text:SetPoint("RIGHT")
    self.progress.text:SetJustifyH("RIGHT")
    function self.progress:Set(text)
        self.text:SetText(text)
        self:SetWidth(math.max(20, (self.text:GetStringWidth() or 60) + 2))
    end
    self.progress:SetScript("OnEnter", function(bar)
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:SetText("Your collection", 1, 0.82, 0)
        GameTooltip:AddLine(bar.full or "", 1, 1, 1)
        local latest = MF.cdb.profile.latestSpecimen
        if latest and latest.id then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Latest specimen", MF:FishName(latest.id), 1, 0.5, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine(latest.spot or "", latest.at and date("%d %b %H:%M", latest.at) or "", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Click for its card", 0.4, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    self.progress:SetScript("OnLeave", function(bar) W:HideTip(bar) end)
    self.progress:SetScript("OnMouseUp", function()
        local latest = MF.cdb.profile.latestSpecimen
        if latest and latest.id then MF:ShowCard(latest.id) end
    end)

    -- Grid
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, -34)
    clip:SetPoint("BOTTOMRIGHT", -14, 0) -- room for the scroll bar
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(_, d) self:Wheel(d) end)
    self.clip = clip
    local content = CreateFrame("Frame", nil, clip)
    content:SetPoint("TOPLEFT")
    content:SetSize(10, 10)
    self.content = content
    self.tiles = {}
    self.scroll, self.target = 0, 0
    local bar = CreateFrame("Slider", nil, frame)
    bar:SetWidth(10)
    bar:SetPoint("TOPLEFT", clip, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", clip, "BOTTOMRIGHT", 4, 0)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.45)
    bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetSize(16, 24) end
    bar:SetScript("OnValueChanged", function(_, v)
        if self.updating then return end
        self.scroll, self.target = v, v
        self:PlaceContent()
    end)
    self.bar = bar
    clip:SetScript("OnUpdate", function(_, elapsed)
        if math.abs((self.target or 0) - (self.scroll or 0)) < 0.5 then
            if self.scroll ~= self.target then self.scroll = self.target self:PlaceContent() end
            return
        end
        local k = (ns.db.animations ~= false) and math.min(1, elapsed * 16) or 1
        self.scroll = self.scroll + (self.target - self.scroll) * k
        self:PlaceContent()
    end)
    clip:SetScript("OnSizeChanged", function() if self.built then self:Layout() end end)

    self.empty = W:Label(clip, "GameFontDisable")
    self.empty:SetPoint("TOP", 0, -60)
    self.empty:SetWidth(300)

    -- The "older log waiting" banner, over the grid when there is one
    local claim = CreateFrame("Button", nil, frame, "BackdropTemplate")
    claim:SetHeight(26)
    claim:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
    claim:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    claim:SetFrameLevel(clip:GetFrameLevel() + 10)
    claim:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    claim:SetBackdropColor(0.2, 0.1, 0.02, 0.95)
    claim:SetBackdropBorderColor(1, 0.5, 0.1, 1)
    claim.text = W:Label(claim, "GameFontHighlightSmall")
    claim.text:SetPoint("CENTER")
    claim:SetScript("OnClick", function() W:Sound("click") if MF.OfferClaim then MF:OfferClaim() end end)
    claim:Hide()
    self.claim = claim

    self.built = true
end

function P:PlaceContent()
    local maxS = math.max(0, (self.contentH or 0) - (self.clip:GetHeight() or 0))
    self.scroll = math.max(0, math.min(maxS, self.scroll or 0))
    self.target = math.max(0, math.min(maxS, self.target or 0))
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", 0, self.scroll)
    self.updating = true
    self.bar:SetMinMaxValues(0, maxS)
    self.bar:SetValue(self.scroll)
    self.bar:SetShown(maxS > 0)
    self.updating = false
end

-- Lay the shown fish out in rows that fit the grid's width
function P:Layout()
    local w = self.clip:GetWidth() or 300
    local cols = math.max(1, math.floor((w + GAP) / (TILE_W + GAP)))
    local pad = math.max(0, math.floor((w - (cols * TILE_W + (cols - 1) * GAP)) / 2))
    local shown = self.shown or {}
    for i, e in ipairs(shown) do
        local t = self.tiles[i]
        if not t then t = NewTile(self.content) self.tiles[i] = t end
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", pad + col * (TILE_W + GAP), -row * (TILE_H + GAP))
        FillTile(t, e)
    end
    for i = #shown + 1, #self.tiles do self.tiles[i]:Hide() self.tiles[i].entry = nil end
    local rows = math.ceil(#shown / cols)
    self.contentH = rows > 0 and (rows * (TILE_H + GAP) - GAP + 4) or 0
    self.content:SetSize(w, math.max(1, self.contentH))
    self.empty:SetShown(#shown == 0)
    self:PlaceContent()
end

function P:Refresh()
    if not self.built then return end
    Collect()
    self.here = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText())
    local zone = ns.db.collectionZone or "all"
    if zone ~= "all" and zone ~= "trophy" then
        local known = false
        for _, z in ipairs(data.zones) do if z == zone then known = true break end end
        if not known then zone = "all" ns.db.collectionZone = "all" end
    end
    local filter = ns.db.collectionFilter or "all"
    local query = self.query or ""

    -- Waters list
    local items = {}
    local tally = Tallies()
    items[1] = { key = "all", label = "All waters", have = tally.all[1], total = tally.all[2] }
    if tally.trophy[2] > 0 then
        items[#items + 1] = { key = "trophy", label = "Trophies", have = tally.trophy[1], total = tally.trophy[2] }
    end
    -- The zone you're in goes first, then the rest alphabetically
    local list = {}
    for _, z in ipairs(data.zones) do
        local zt = tally[z] or { 0, 0 }
        list[#list + 1] = { key = z, label = z, have = zt[1], total = zt[2] }
    end
    table.sort(list, function(a, b)
        if (a.key == self.here) ~= (b.key == self.here) then return a.key == self.here end
        return a.label < b.label
    end)
    for _, it in ipairs(list) do items[#items + 1] = it end
    self.zones:SetItems(items, true)

    -- Filters
    for _, b in ipairs(self.filters) do
        local on = b.key == filter
        b.line:SetShown(on)
        if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.75, 0.75, 0.75) end
    end

    -- Grid
    local shown = {}
    for _, e in ipairs(data.fish) do
        if InZone(e, zone) and Matches(e, filter, query) then shown[#shown + 1] = e end
    end
    self.shown = shown
    local visible = false
    for _, e in ipairs(shown) do if e.id == self.selected then visible = true break end end
    -- Only a fish you picked is marked: with no panel to fill, nothing is
    -- chosen for you.
    if not visible then self.selected = nil end
    self.empty:SetText(query ~= "" and "No fish match that search." or
        (filter == "specimens" and "No specimens here yet. One fish in a hundred, in its native waters." or
        filter == "caught" and "Nothing caught here yet." or "Nothing to find here."))
    self:Layout()

    -- What you have now, so the next refresh can flash what's new
    self.known = {}
    for _, e in ipairs(data.fish) do if e.caught then self.known[e.id] = true end end

    local sh, st = tally.all[1], tally.all[2]
    local specs = 0
    for _, e in ipairs(data.fish) do if e.specimens > 0 then specs = specs + 1 end end
    local landed = (MF:ValueEnabled() and (MF.cdb.profile.value or 0) > 0) and ("   " .. MF:ShortMoney(MF.cdb.profile.value)) or ""
    self.progress.full = ("%d / %d species   |cffff8000%d|r with a specimen%s"):format(sh, st, specs, landed)
    self.progress:Set(("|cffff8000%d|r specimen%s%s"):format(specs, specs == 1 and "" or "s", landed))
    if J.count then J.count:SetText(#shown == 1 and "1 fish shown" or (#shown .. " fish shown")) end

    -- A log from before (the beta, another character) waiting to be claimed: say so here, where
    -- someone wondering why their journal is empty is looking
    local waiting = MF.LegacyWaiting and MF:LegacyWaiting()
    local show = waiting and (waiting.xp or 0) > (MF.cdb.profile.xp or 0)
    self.claim:SetShown(show and true or false)
    if show then
        self.claim.text:SetText(("|cffff8000An older log is waiting|r  %d XP, %d entries. |cffffd100Click to claim it.|r"):format(
            waiting.xp or 0, MF.Count and MF.Count(waiting.journal or {}) or 0))
    end
end

J:AddPage({
    key = "collection",
    match = function(state)
        if state.recap or state.tab ~= "journal" then return false end
        local v = state.view
        if not (v == nil or v == "zones" or v == "fish" or v == "cards") then return false end
        if v == "cards" and state.MF.albumFinds then return false end -- its fishing finds page
        -- The Fishing Log's own search is running: let its results page show
        local host = state.MF.journalWindow or _G.TheFishingLogJournal
        local edit = host and host.searchBar and host.searchBar.edit
        return not (edit and (edit:GetText() or "") ~= "")
    end,
    build = function(frame, tfl)
        MF = tfl
        P:Build(frame)
    end,
    refresh = function() P:Refresh() end,
    subheading = function() return "Collection" end,
    count = function()
        if not P.shown then return "" end
        return #P.shown == 1 and "1 fish shown" or (#P.shown .. " fish shown")
    end,
})
