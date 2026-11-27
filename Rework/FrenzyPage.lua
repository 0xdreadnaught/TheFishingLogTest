-- Frenzies: every frenzy water, searchable, and the next two hours of them.
--   top      a search box (water or zone), Active / Next hour / All, Favourites, List / Timeline
--   strip    how many are on, and the next frenzy where you are, with Remind me
--   list     waters under their zones (yours first), one line each: a bar for how long it has left or
--            how soon it starts, how far away it is in your zone, a star for favourites. A click opens
--            the water: its access point, your best fish there, Show on map, Remind me, Favourite
--   timeline the next two hours across the page, one row per water, its frenzy shaded
--   discoveries  unnamed waters gathering evidence, and pool waters worth a look, searchable too
-- Planner / Discoveries and All zones / Zone only stay The Fishing Log's own toggles on the top row.
--
-- The page this replaced is tagged frenzies-classic in the repo; taking this file out of the .toc
-- brings it straight back, since The Fishing Log still builds its own frenzy list underneath.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.FrenzyPage = P

local SPAN = 2 * 3600       -- the timeline's reach
local NAME_W = 250          -- the timeline's name column
local TIMER_W = 96
local STRIP_TIMER_W = 104   -- test build: room for "starts in 1:02:11" in the strip
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01"

local ORANGE = "|cffff9d00"
local MUTED = "|cff8f8f8f"
local HINT = "|cff9ec9ff"

-- What the viewer last chose, kept on the character
local function Prefs()
    local cdb = MF.cdb
    if type(cdb.frenzyPage) ~= "table" then cdb.frenzyPage = {} end
    local p = cdb.frenzyPage
    p.when = (p.when == "active" or p.when == "hour") and p.when or "all"
    p.view = p.view == "timeline" and "timeline" or "list"
    return p
end

local function Discoveries() return MF.frenzyListView == "discoveries" end

local function Timer(r)
    if r.active then return ORANGE .. "ends in " .. MF:FormatClock(r.left) .. "|r" end
    local colour = r.left <= 600 and "|cffffd100" or HINT
    return colour .. "starts in " .. MF:FormatClock(r.left) .. "|r"
end

local function Yards(y)
    if not y then return "" end
    if y < 10 then return "here" end
    return ("%d yd"):format(math.floor(y / 5 + 0.5) * 5)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function ZoneRow()
    local r = CreateFrame("Button")
    r.arrow = W:Label(r, "GameFontNormal")
    r.arrow:SetPoint("LEFT", 4, 0)
    r.text = W:Label(r, "GameFontNormal")
    r.text:SetPoint("LEFT", 22, 0)
    r.right = W:Label(r, "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r.rule = W:Divider(r, 100)
    r.rule:SetPoint("BOTTOMLEFT", 0, 1)
    r.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    r:SetScript("OnClick", function(self)
        local zone = self.item and self.item.zone
        if not zone then return end
        P.collapsed[zone] = not P.collapsed[zone] or nil
        W:Sound("click")
        P:Refresh()
    end)
    return r
end

local function WaterRow()
    local r = CreateFrame("Button")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("LEFT", 14, 0)
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", 30, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.star = W:IconButton(r, 14, STAR, function(self)
        local it = self:GetParent().item
        if not it then return end
        MF:SetFrenzyFavourite(it.row.water.id, not it.row.favourite)
        P:Refresh()
    end, "Favourite", "Starred waters can be shown on their own with Favourites.")
    r.star:SetPoint("RIGHT", -8, 0)
    r.timer = W:Label(r, "GameFontHighlightSmall")
    r.timer:SetPoint("RIGHT", r.star, "LEFT", -10, 0)
    r.timer:SetWidth(TIMER_W)
    r.timer:SetJustifyH("RIGHT")
    r.bar = W:Bar(r, 140, 12)
    r.bar:SetPoint("RIGHT", r.timer, "LEFT", -12, 0)
    r.clock = r:CreateTexture(nil, "ARTWORK")
    r.clock:SetSize(14, 14)
    r.clock:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.clock:SetTexture(CLOCK)
    r.clock:SetPoint("RIGHT", r.bar, "LEFT", -10, 0)
    r.yards = W:Label(r, "GameFontDisableSmall")
    r.yards:SetPoint("RIGHT", r.clock, "LEFT", -8, 0)
    r.yards:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
        local it = self.item
        if not it then return end
        local id = it.row.water.id
        P.open = P.open ~= id and id or nil
        W:Sound("click")
        P:Refresh()
    end)
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        local w = it.row.water
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(w.name, 1, 0.82, 0)
        GameTooltip:AddLine(it.row.zone, 1, 1, 1)
        GameTooltip:AddLine(("Access point %.2f, %.2f, within %d yards"):format(w.x * 100, w.y * 100, w.radius), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Click for more, and to set a reminder.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return r
end

local function DetailRow()
    local r = CreateFrame("Frame")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.35)
    r.line1 = W:Label(r, "GameFontHighlightSmall")
    r.line1:SetPoint("TOPLEFT", 30, -8)
    r.line2 = W:Label(r, "GameFontDisableSmall")
    r.line2:SetPoint("TOPLEFT", r.line1, "BOTTOMLEFT", 0, -4)
    r.line2:SetWidth(420)
    r.line2:SetJustifyH("LEFT")
    r.line3 = W:Label(r, "GameFontHighlightSmall")
    r.line3:SetPoint("TOPLEFT", r.line2, "BOTTOMLEFT", 0, -4)
    local function Water(self) local it = self:GetParent().item return it and it.row end
    r.fav = W:Button(r, "Favourite", 110, 22, function(self)
        local row = Water(self)
        if row then MF:SetFrenzyFavourite(row.water.id, not row.favourite) P:Refresh() end
    end)
    r.fav:SetPoint("RIGHT", -10, 0)
    r.remind = W:Button(r, "Remind me", 130, 22, function(self)
        local row = Water(self)
        if row then MF:SetFrenzyReminder(row.water.id, not row.remind) P:Refresh() end
    end, "Remind me", "A pop-up and a sound two minutes before every frenzy here, until you turn it off.")
    r.remind:SetPoint("RIGHT", r.fav, "LEFT", -8, 0)
    r.map = W:Button(r, "Show on map", 120, 22, function(self)
        local row = Water(self)
        if row then MF:InspectFrenzyPoint(row.water.map, row.water.x, row.water.y) end
    end, "Show on map", "Opens the map there, with a waypoint where your client supports one.")
    r.map:SetPoint("RIGHT", r.remind, "LEFT", -8, 0)
    return r
end

local function TimelineHead()
    local r = CreateFrame("Frame")
    r.ticks = {}
    for i = 1, 5 do
        r.ticks[i] = W:Label(r, "GameFontDisableSmall")
        r.ticks[i].line = r:CreateTexture(nil, "ARTWORK")
        r.ticks[i].line:SetColorTexture(1, 1, 1, 0.12)
        r.ticks[i].line:SetSize(1, 6)
    end
    r.rule = W:Divider(r, 100)
    r.rule:SetPoint("BOTTOMLEFT", 0, 1)
    r.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    return r
end

local function TimelineRow()
    local r = CreateFrame("Button")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r.name = W:Label(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 10, 0)
    r.name:SetWidth(NAME_W - 16)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.track = r:CreateTexture(nil, "BORDER")
    r.track:SetColorTexture(1, 1, 1, 0.05)
    r.segs = {}
    for i = 1, 3 do
        local s = r:CreateTexture(nil, "ARTWORK")
        s:SetColorTexture(1, 0.55, 0.1, 0.85)
        r.segs[i] = s
    end
    r.timer = W:Label(r, "GameFontHighlightSmall")
    r.timer:SetPoint("RIGHT", -8, 0)
    r.timer:SetWidth(TIMER_W)
    r.timer:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
        local it = self.item
        if not it then return end
        local w = it.row.water
        MF:InspectFrenzyPoint(w.map, w.x, w.y)
    end)
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(it.row.water.name, 1, 0.82, 0)
        GameTooltip:AddLine(it.row.zone, 1, 1, 1)
        for _, win in ipairs(it.windows) do
            GameTooltip:AddLine(("Frenzy %s - %s"):format(date("%H:%M", win[1]), date("%H:%M", win[2])), 1, 0.6, 0.2)
        end
        GameTooltip:AddLine("Click to show it on the map.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return r
end

-- Discoveries and pool waters: a name, where, a bar of how close it is, and its state
local function EvidenceRow()
    local r = CreateFrame("Button")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", 14, 0)
    r.where = W:Label(r, "GameFontDisableSmall")
    r.where:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
    r.status = W:Label(r, "GameFontHighlightSmall")
    r.status:SetPoint("RIGHT", -10, 0)
    r.status:SetWidth(150)
    r.status:SetJustifyH("RIGHT")
    r.bar = W:Bar(r, 140, 12, 0.2, 0.6, 1)
    r.bar:SetPoint("RIGHT", r.status, "LEFT", -12, 0)
    r:SetScript("OnClick", function(self)
        local it = self.item
        if it then MF:InspectFrenzyPoint(it.map, it.x, it.y) end
    end)
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not (it and it.tip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i, line in ipairs(it.tip) do
            if i == 1 then GameTooltip:SetText(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return r
end

local function Make(kind)
    if kind == "zone" then return ZoneRow() end
    if kind == "water" then return WaterRow() end
    if kind == "detail" then return DetailRow() end
    if kind == "tlhead" then return TimelineHead() end
    if kind == "tl" then return TimelineRow() end
    if kind == "evidence" then return EvidenceRow() end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, kind == "head" and "GameFontNormal" or "GameFontDisableSmall")
    fr.text:SetPoint("LEFT", 6, 0)
    fr.text:SetPoint("RIGHT", -6, 0)
    fr.text:SetJustifyH("LEFT")
    if kind == "head" then
        fr.rule = W:Divider(fr, 100)
        fr.rule:SetPoint("BOTTOMLEFT", 0, 1)
        fr.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    end
    return fr
end

local function FillWater(fr, it)
    local r = it.row
    local w = r.water
    fr.bg:SetColorTexture(1, 0.62, 0, r.here and 0.16 or (it.index % 2 == 0 and 0.035 or 0))
    if r.active then fr.dot:SetColorTexture(1, 0.55, 0.1, 1) else fr.dot:SetColorTexture(0.35, 0.45, 0.6, 1) end
    local name = MF:FrenzyShortName(w)
    fr.name:SetText((r.here and "|cff3ee63e" or "|cffffffff") .. name .. "|r"
        .. (r.here and "  |cff3ee63eyou are here|r" or ""))
    fr.yards:SetText(MUTED .. Yards(r.yards) .. "|r")
    fr.clock:SetShown(r.remind)
    if r.active then
        fr.bar:Set(r.left, MF.FRENZY_LENGTH, "")
        fr.bar:SetColor(1, 0.55, 0.1)
    else
        local wait = MF.FRENZY_CYCLE - MF.FRENZY_LENGTH
        fr.bar:Set(wait - r.left, wait, "")
        fr.bar:SetColor(0.3, 0.5, 0.8)
    end
    fr.timer:SetText(Timer(r))
    fr.star.icon:SetDesaturated(not r.favourite)
    fr.star.icon:SetAlpha(r.favourite and 1 or 0.35)
    -- The name has what the right-hand side leaves
    local width = (fr:GetWidth() or 0) - 30 - 8 - 14 - 10 - TIMER_W - 12 - 140 - 10 - 14 - 8 - 60 - 10
    fr.name:SetWidth(math.max(120, width))
end

local function FillDetail(fr, it)
    local r = it.row
    local w = r.water
    fr.line1:SetText(("Access point |cffffffff%.2f, %.2f|r, within %d yards - %s"):format(
        w.x * 100, w.y * 100, w.radius, r.zone))
    fr.line2:SetText(w.source or "")
    -- Looking it up means checking every record you hold, so not every second
    local cached = P.best and P.best.id == w.id and GetTime() - P.best.at < 10 and P.best
    if not cached then
        local weight, item = MF:FrenzyBestCatch(w)
        cached = { id = w.id, at = GetTime(), weight = weight, item = item }
        P.best = cached
    end
    local best, id = cached.weight, cached.item
    if best then
        fr.line3:SetText(("Your best here: |cffffffff%s|r %s"):format(MF:Weight(best), MF:ShortFishName(id)))
    else
        fr.line3:SetText(MUTED .. "You haven't landed anything here yet.|r")
    end
    fr.fav:SetText(r.favourite and "Unfavourite" or "Favourite")
    fr.remind:SetText(r.remind and "Stop reminding" or "Remind me")
end

local function FillHead(fr)
    local width = fr:GetWidth() or 0
    local track = width - NAME_W - TIMER_W - 16
    local now = GetServerTime()
    for i, tick in ipairs(fr.ticks) do
        local frac = (i - 1) / 4
        tick:ClearAllPoints()
        tick:SetPoint("BOTTOM", fr, "BOTTOMLEFT", NAME_W + frac * track, 6)
        tick:SetText(i == 1 and "now" or date("%H:%M", now + frac * SPAN))
        tick.line:ClearAllPoints()
        tick.line:SetPoint("BOTTOM", fr, "BOTTOMLEFT", NAME_W + frac * track, 0)
    end
end

local function FillTimeline(fr, it)
    local r = it.row
    local width = fr:GetWidth() or 0
    local track = math.max(10, width - NAME_W - TIMER_W - 16)
    fr.bg:SetColorTexture(1, 0.62, 0, r.here and 0.16 or (it.index % 2 == 0 and 0.035 or 0))
    fr.name:SetText((r.here and "|cff3ee63e" or "|cffffffff") .. MF:FrenzyShortName(r.water) .. "|r  "
        .. MUTED .. r.zone .. "|r")
    fr.track:ClearAllPoints()
    fr.track:SetPoint("TOPLEFT", NAME_W, -4)
    fr.track:SetPoint("BOTTOMLEFT", NAME_W, 4)
    fr.track:SetWidth(track)
    for i, seg in ipairs(fr.segs) do
        local win = it.windows[i]
        if win then
            local x0 = (win[1] - it.now) / SPAN * track
            local x1 = (win[2] - it.now) / SPAN * track
            seg:ClearAllPoints()
            seg:SetPoint("TOPLEFT", NAME_W + x0, -4)
            seg:SetPoint("BOTTOMLEFT", NAME_W + x0, 4)
            seg:SetWidth(math.max(2, x1 - x0))
            seg:Show()
        else
            seg:Hide()
        end
    end
    fr.timer:SetText(Timer(r))
end

local function FillEvidence(fr, it)
    fr.bg:SetColorTexture(1, 1, 1, it.index % 2 == 0 and 0.035 or 0)
    fr.name:SetText(it.name)
    fr.where:SetText(it.where)
    fr.bar:Set(it.value, it.max, it.barText or "")
    fr.bar:SetColor(it.r or 0.2, it.g or 0.6, it.b or 1)
    fr.status:SetText(it.status)
end

local function Fill(fr, it)
    if it.kind == "zone" then
        fr.arrow:SetText(P.collapsed[it.zone] and "+" or "-")
        fr.text:SetText(it.zone .. (it.localZone and "  |cff3ee63eyour zone|r" or ""))
        fr.right:SetText((it.active > 0 and (ORANGE .. it.active .. " active|r   ") or "") .. MUTED .. it.count
            .. (it.count == 1 and " water" or " waters") .. "|r")
    elseif it.kind == "water" then FillWater(fr, it)
    elseif it.kind == "detail" then FillDetail(fr, it)
    elseif it.kind == "tlhead" then FillHead(fr)
    elseif it.kind == "tl" then FillTimeline(fr, it)
    elseif it.kind == "evidence" then FillEvidence(fr, it)
    else fr.text:SetText(it.text or "") end
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------
-- A row of buttons where one is chosen
local function Segments(parent, choices, get, set)
    local buttons = {}
    local prev
    for _, c in ipairs(choices) do
        local b = W:Button(parent, c[2], c[3] or 90, 22, function()
            set(c[1])
            P:Refresh()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
        b.value = c[1]
        buttons[#buttons + 1] = b
        prev = b
    end
    function buttons.Update()
        local on = get()
        for _, b in ipairs(buttons) do
            -- On this client every panel button is red, so the chosen one is lit and the rest dimmed
            if b.value == on then b:LockHighlight() else b:UnlockHighlight() end
            b:SetAlpha(b.value == on and 1 or 0.55)
            local fs = b.GetFontString and b:GetFontString()
            if fs then
                if b.value == on then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.85, 0.85, 0.85) end
            end
        end
    end
    return buttons
end

function P:Build(frame)
    self.collapsed = {}
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(26)
    self.bar = bar

    self.search = W:Search(bar, 230, function(text)
        if P.text == text then return end
        P.text = text
        P:Refresh()
    end, "Search waters or zones")
    self.search:SetPoint("LEFT", 6, 0)

    self.when = Segments(bar, { { "active", "Active" }, { "hour", "Next hour" }, { "all", "All", 60 } },
        function() return Prefs().when end, function(v) Prefs().when = v end)
    self.when[1]:SetPoint("LEFT", self.search, "RIGHT", 16, 0)

    self.favs = W:Check(bar, "Favourites", function() return Prefs().favs == true end, function(on)
        Prefs().favs = on or nil
        P:Refresh()
    end, "Only the waters you've starred.")
    self.favs:SetPoint("LEFT", self.when[#self.when], "RIGHT", 14, 0)

    self.view = Segments(bar, { { "list", "List", 70 }, { "timeline", "Timeline", 90 } },
        function() return Prefs().view end, function(v) Prefs().view = v end)
    self.view[1]:SetPoint("RIGHT", bar, "RIGHT", -(90 + 2 + 6), 0)
    bar:HookScript("OnSizeChanged", function() P:LayoutBar() end)

    -- The strip: what's on, and the next one where you are
    local strip = W:Panel(frame, 0.85)
    strip:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    strip:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    strip:SetHeight(38)
    -- Test build: three slots that never overlap. The count on the left; the countdown in a
    -- fixed-width slot beside the button, so the text beside it does not shift as the digits
    -- change; the place in between, cut short if it does not fit.
    strip.left = W:Label(strip, "GameFontHighlight")
    strip.left:SetPoint("LEFT", 14, 0)
    strip.remind = W:Button(strip, "Remind me", 130, 22, function()
        local w = P.nextHere
        if w then MF:SetFrenzyReminder(w.id, not MF:IsFrenzyReminder(w.id)) P:Refresh() end
    end, "Remind me", "A pop-up and a sound two minutes before every frenzy there, until you turn it off.")
    strip.remind:SetPoint("RIGHT", -10, 0)
    strip.timer = W:Label(strip, "GameFontHighlightSmall")
    strip.timer:SetPoint("RIGHT", strip.remind, "LEFT", -12, 0)
    strip.timer:SetWidth(STRIP_TIMER_W)
    strip.timer:SetJustifyH("RIGHT")
    strip.timer:SetWordWrap(false)
    strip.right = W:Label(strip, "GameFontHighlightSmall")
    strip.right:SetPoint("LEFT", strip.left, "RIGHT", 16, 0)
    strip.right:SetPoint("RIGHT", strip.timer, "LEFT", -8, 0)
    strip.right:SetJustifyH("LEFT")
    strip.right:SetWordWrap(false)
    self.strip = strip

    self.list = W:VList(frame, Make, Fill)
    self.list:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -6)
    self.list:SetPoint("BOTTOMRIGHT", -16, 0)

    -- The clocks count down whether or not anything else redraws the journal
    local ticker = CreateFrame("Frame", nil, frame)
    ticker.wait = 0
    ticker:SetScript("OnUpdate", function(t, elapsed)
        t.wait = t.wait + (elapsed or 0)
        if t.wait < 1 then return end
        t.wait = 0
        P:Refresh()
    end)
    self:LayoutBar()
end

-- Test build: the filter row was laid out for the full width of the window and its buttons
-- ran over each other beside the character. Below FULL_BAR_W the buttons are narrower and
-- the search box takes whatever is left. Returns the width used, for the tests.
local FULL_BAR_W = 880
function P:LayoutBar()
    local bar = self.bar
    if not (bar and self.search and self.when and self.view) then return end
    local width = bar:GetWidth() or 0
    if width <= 0 then return end
    local full = width >= FULL_BAR_W
    local whenW = full and { 70, 90, 60 } or { 58, 80, 40 }
    local viewW = full and { 70, 90 } or { 46, 76 }
    local gap = full and 14 or 8
    local label = self.favs.text
    local favW = 22 + 1 + math.ceil(label and label:GetStringWidth() or 60)
    local fixed = 6 + gap + (whenW[1] + 2 + whenW[2] + 2 + whenW[3]) + gap + favW + gap + (viewW[1] + 2 + viewW[2]) + 6
    local searchW = math.max(90, math.min(230, width - fixed))
    self.search:SetWidth(searchW)
    -- The hint in the empty box wrapped onto a second line when the box was narrow.
    local hint = self.search.Instructions
    if type(hint) == "table" and hint.SetText then
        if hint.SetWordWrap then hint:SetWordWrap(false) end
        hint:SetText(searchW >= 190 and "Search waters or zones" or "Search waters")
    end
    for i, b in ipairs(self.when) do b:SetWidth(whenW[i]) end
    for i, b in ipairs(self.view) do b:SetWidth(viewW[i]) end
    self.when[1]:ClearAllPoints()
    self.when[1]:SetPoint("LEFT", self.search, "RIGHT", gap, 0)
    self.favs:ClearAllPoints()
    self.favs:SetPoint("LEFT", self.when[#self.when], "RIGHT", gap, 0)
    self.view[1]:ClearAllPoints()
    self.view[1]:SetPoint("RIGHT", bar, "RIGHT", -(viewW[2] + 2 + 6), 0)
    return fixed + searchW
end

-- A water in the strip. A water with no name of its own is stored as "Desolace water
-- (59.07, 82.33)": the strip shows the coordinates, and never the word "water".
local function StripPlace(r, withZone)
    local name = r.water.name or ""
    local at = name:match("^.- water %((.-)%)$")
    if at then return withZone and (r.zone .. " " .. at) or at end
    return withZone and (name .. ", " .. r.zone) or name
end

-- What the strip says for these rows: the count, the place, the countdown, and the row the
-- Remind me button is for.
--   at a frenzy water        You're at <name>              ends in / starts in
--   one coming in your zone  Next here  <name or coords>   starts in
--   otherwise                Next  <zone coords>           starts in
function P.StripText(all)
    local active = 0
    for _, r in ipairs(all) do if r.active then active = active + 1 end end
    local here, nextHere, nextAnywhere
    for _, r in ipairs(all) do
        if r.here then here = r end
        if r.localZone and not nextHere then nextHere = r end
        -- Rows run active first, then soonest: the first one not on yet is the next to start
        if not r.active and not nextAnywhere then nextAnywhere = r end
    end
    local shown = here or nextHere or nextAnywhere
    local count = ORANGE .. active .. " active|r"
    if here then
        local named = not (here.water.name or ""):match("^.- water %(.-%)$")
        return count, "|cff3ee63eYou're at " .. (named and StripPlace(here) or "a frenzy water") .. "|r", Timer(here), shown
    elseif nextHere then
        return count, MUTED .. "Next here|r  |cffffffff" .. StripPlace(nextHere) .. "|r", Timer(nextHere), shown
    elseif nextAnywhere then
        -- None where you are: the next one to start anywhere, to plan a trip around
        return count, MUTED .. "Next|r  |cffffffff" .. StripPlace(nextAnywhere, true) .. "|r", Timer(nextAnywhere), shown
    end
    return count, MUTED .. "No frenzy waters in this zone|r", "", nil
end

local function Strip(self, all)
    local count, place, timer, shown = P.StripText(all)
    self.strip.left:SetText(count)
    self.strip.right:SetText(place)
    self.strip.timer:SetText(timer)
    self.nextHere = shown and shown.water or nil
    self.strip.remind:SetShown(shown ~= nil)
    if shown then self.strip.remind:SetText(shown.remind and "Stop reminding" or "Remind me") end
end

function P:PlannerItems()
    local prefs = Prefs()
    local all = MF:FrenzyRows({ localOnly = MF.frenzyLocalOnly })
    local rows = MF:FrenzyRows({ text = self.text, when = prefs.when, localOnly = MF.frenzyLocalOnly,
        favourites = prefs.favs })
    self.total, self.shown, self.activeCount = #all, #rows, 0
    for _, r in ipairs(all) do if r.active then self.activeCount = self.activeCount + 1 end end
    Strip(self, all)

    local items = {}
    if #rows == 0 then
        local why = (self.text or "") ~= "" and ("No frenzy waters match \"" .. self.text .. "\".")
            or prefs.favs and "No favourites here yet: open a water and press Favourite, or click its star."
            or prefs.when == "active" and "No frenzies on right now in this view."
            or "No frenzy waters in this view."
        items[1] = { kind = "note", h = 40, text = why }
        return items
    end
    if prefs.view == "timeline" then
        local now = GetServerTime()
        items[1] = { kind = "tlhead", h = 22 }
        for i, r in ipairs(rows) do
            items[#items + 1] = { kind = "tl", h = 22, row = r, index = i, now = now,
                windows = MF:FrenzyWindows(r.water.id, now, SPAN) }
        end
        return items
    end
    -- A search or a filter shows everything it found, collapsed or not
    local filtering = (self.text or "") ~= ""
    for _, g in ipairs(MF:FrenzyGroups(rows)) do
        items[#items + 1] = { kind = "zone", h = 26, zone = g.zone, localZone = g.localZone,
            active = g.active, count = #g.rows }
        if filtering or not self.collapsed[g.zone] then
            for i, r in ipairs(g.rows) do
                items[#items + 1] = { kind = "water", h = 26, row = r, index = i }
                if self.open == r.water.id then
                    items[#items + 1] = { kind = "detail", h = 70, row = r }
                end
            end
        end
    end
    return items
end

function P:DiscoveryItems()
    self.strip.left:SetText("Unnamed waters gathering evidence: three anglers, five casts each, then a review.")
    self.strip.right:SetText("")
    self.strip.remind:Hide()
    local text = (self.text or ""):lower()
    local here = MF:CurrentSpot().mapID
    local function Keep(map)
        if MF.frenzyLocalOnly and map ~= here then return false end
        if text == "" then return true end
        local zone = MF:FrenzyZoneLabel(map):lower()
        for word in text:gmatch("%S+") do if not zone:find(word, 1, true) then return false end end
        return true
    end
    local items = { { kind = "head", h = 28, text = "Community discoveries" } }
    local found = 0
    -- Still collecting first (the ones fishing can help), closest to ready at the top; then the
    -- approved, and the rejected last
    local ORDER = { Collecting = 1, Approved = 3, Rejected = 4 }
    local list = {}
    for _, n in ipairs(MF:FrenzyDiscoveryStore()) do
        local ready, qualified = MF:FrenzyDiscoveryProgress(n)
        list[#list + 1] = { n = n, ready = ready, qualified = qualified,
            order = ORDER[MF:FrenzyDiscoveryStatus(n)] or 2 }
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.ready ~= b.ready then return a.ready end
        if a.qualified ~= b.qualified then return a.qualified > b.qualified end
        return a.n.id < b.n.id
    end)
    for _, entry in ipairs(list) do
        local n = entry.n
        if Keep(n.map) then
            local ready, qualified, total = MF:FrenzyDiscoveryProgress(n)
            local status = MF:FrenzyDiscoveryStatus(n)
            found = found + 1
            local tip = { "Unnamed water - " .. MF:FrenzyZoneLabel(n.map),
                ("%.2f, %.2f - %d anglers taking part"):format(n.x * 100, n.y * 100, total) }
            -- Each angler's own progress: what a review is decided on
            local names, recent = {}, GetServerTime() - 30 * 86400
            for _, a in pairs(n.anglers or {}) do
                if (a.at or 0) >= recent then names[#names + 1] = MF:ShortName(a.name) .. ": " .. a.count .. "/5 catches" end
            end
            table.sort(names)
            for _, line in ipairs(names) do tip[#tip + 1] = line end
            tip[#tip + 1] = "Sender-reported, from the last 30 days; character names, not verified accounts. Click to show it on the map."
            items[#items + 1] = { kind = "evidence", h = 26, index = found, map = n.map, x = n.x, y = n.y, tip = tip,
                name = (ready and "|cffffd100" or "|cffffffff") .. "Unnamed water|r",
                where = ("%s  %.2f, %.2f"):format(MF:FrenzyZoneLabel(n.map), n.x * 100, n.y * 100),
                -- Past the three it needs, the bar is simply full and says how many
                value = math.min(qualified, 3), max = 3,
                barText = qualified >= 3 and (qualified .. " anglers") or (qualified .. " / 3 anglers"),
                status = status == "Collecting" and (MUTED .. "collecting|r")
                    or status == "Approved" and "|cff3ee63ein the catalogue|r"
                    or status == "Rejected" and "|cffff5a5arejected|r" or ("|cffffd100" .. status:lower() .. "|r") }
        end
    end
    if found == 0 then items[#items + 1] = { kind = "note", h = 34,
        text = "No unnamed waters reported yet. Genuine fishing casts build the evidence." } end
    self.discoveries = found

    items[#items + 1] = { kind = "head", h = 32, text = "Suggested by pool sightings" }
    items[#items + 1] = { kind = "note", h = 26,
        text = "Busy pool waters with no frenzy water nearby. Not reviewed: fish there so evidence can build." }
    local pools = 0
    local candidates = MF.PoolFrenzyCandidates and MF:PoolFrenzyCandidates() or {}
    local most = 1
    for _, c in ipairs(candidates) do most = math.max(most, c.sightings or 1) end
    for _, c in ipairs(candidates) do
        if Keep(c.map) then
            pools = pools + 1
            items[#items + 1] = { kind = "evidence", h = 26, index = pools, map = c.map, x = c.x, y = c.y,
                tip = (function()
                    local seen = {}
                    for name, k in pairs(c.names or {}) do seen[#seen + 1] = name .. (k > 1 and (" x" .. k) or "") end
                    table.sort(seen)
                    return { "Pool water - " .. MF:FrenzyZoneLabel(c.map),
                        ("%.2f, %.2f"):format(c.x * 100, c.y * 100),
                        "Pools seen: " .. table.concat(seen, ", "),
                        "First-hand: " .. MF:PoolCandidateWitnessText(c),
                        "Last seen " .. (c.newest and date("%d %b", c.newest) or "-"),
                        "Catches count toward a discovery only where TFL shows the water as unnamed.",
                        "Pool sightings alone never add a water to the catalogue." }
                end)(),
                name = "Pool water", where = ("%s  %.2f, %.2f"):format(MF:FrenzyZoneLabel(c.map), c.x * 100, c.y * 100),
                value = c.sightings, max = most, barText = c.sightings .. (c.sightings == 1 and " sighting" or " sightings"),
                r = 0.3, g = 0.75, b = 0.5, status = MUTED .. "unchecked|r" }
        end
    end
    if pools == 0 then items[#items + 1] = { kind = "note", h = 30, text = "No busy pool waters away from known frenzy waters yet." } end
    return items
end

function P:Refresh()
    if not self.list then return end
    local disc = Discoveries()
    for _, b in ipairs(self.when) do b:SetShown(not disc) end
    for _, b in ipairs(self.view) do b:SetShown(not disc) end
    self.favs:SetShown(not disc)
    if not disc then
        self.when.Update()
        self.view.Update()
        self.favs:SetChecked(Prefs().favs == true)
    end
    local items = disc and self:DiscoveryItems() or self:PlannerItems()
    -- The journal writes the footer only when it redraws; our own buttons and clock don't go
    -- through it, so keep the count true here
    if J.count and J.page and J.page.key == "frenzies" then J.count:SetText(self:Count()) end
    -- The same rows in the same order (the clock ticking, nothing else): update them where they
    -- stand, so a row keeps its frame under the mouse and a click across a tick still lands.
    local sig = {}
    for _, it in ipairs(items) do
        sig[#sig + 1] = it.kind .. ":" .. tostring(it.row and it.row.water.id or it.zone or it.text or it.name or "")
            .. ":" .. tostring(it.map or "") .. tostring(it.x or "")
    end
    sig = table.concat(sig, "\1")
    if sig == self.sig and self.items and #self.items == #items then
        for i, it in ipairs(items) do
            local old = self.items[i]
            for k, v in pairs(it) do if k ~= "y" and k ~= "h" then old[k] = v end end
        end
        for fr, it in pairs(self.list.frames or {}) do Fill(fr, it) end
        return
    end
    self.sig, self.items = sig, items
    self.list:SetItems(items, true)
end

function P:Count()
    if Discoveries() then
        local n = self.discoveries or 0
        return n == 1 and "1 discovery" or (n .. " discoveries")
    end
    if (self.shown or 0) ~= (self.total or 0) then return ("%d of %d waters"):format(self.shown or 0, self.total or 0) end
    return ("%d waters - %d active"):format(self.total or 0, self.activeCount or 0)
end

J:AddPage({
    key = "frenzies",
    match = function(state)
        return not state.recap and state.tab == "journal" and state.view == "tools"
            and (state.MF.anglingToolsView or "waters") == "frenzies"
    end,
    live = true, -- its clocks count down
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function() P:Refresh() end,
    subheading = function() return Discoveries() and "Frenzy discoveries" or "Frenzy planner" end,
    count = function() return P:Count() end,
})
