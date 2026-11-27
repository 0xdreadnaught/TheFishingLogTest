-- History: your fishing as a logbook. Days as headings, each session a card - where, how long, how many,
-- the best fish with its icon - matches with their medal, season ends as banners. A card opens the
-- session's report, as The Fishing Log's own rows did. Its "By spot" view is still its own page.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"
local MEDAL = { { 1, 0.82, 0 }, { 0.82, 0.82, 0.88 }, { 0.80, 0.50, 0.20 } }

local iconByName, iconCount, iconPartial, iconAt = nil, nil, false, -math.huge
local function IconForName(name)
    if not name then return nil end
    -- Built once, and again when a new species joins the journal, or (every few seconds) while some
    -- item names hadn't loaded yet ("Item 12345") so their icons would be missing
    local now = GetTime()
    if now - iconAt > (iconPartial and 3 or 1) then
        iconAt = now
        local n = 0
        for _ in pairs(MF.cdb.profile.journal or {}) do n = n + 1 end
        if n ~= iconCount or iconPartial then iconByName, iconCount = nil, n end
    end
    if not iconByName then
        iconByName, iconPartial = {}, false
        local function Add(id)
            local fishName = MF:FishName(id)
            if type(fishName) == "string" then
                if fishName:find("^Item %d") then iconPartial = true end
                iconByName[fishName] = id
            end
        end
        for id in pairs(MF.FISH) do Add(id) end
        for id in pairs(MF.cdb.profile.journal or {}) do Add(id) end
    end
    local id = iconByName[name]
    return id and MF:FishIcon(id) or nil
end

local function DayLabel(t)
    local today = date("*t")
    local d = date("*t", t)
    if d.year == today.year and d.yday == today.yday then return "Today" end
    local y = date("*t", time() - 86400)
    if d.year == y.year and d.yday == y.yday then return "Yesterday" end
    return date("%A, %d %B", t)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function MakeRow(kind)
    if kind == "day" then
        local fr = CreateFrame("Frame")
        fr.text = W:Label(fr, "GameFontNormal")
        fr.text:SetPoint("BOTTOMLEFT", 4, 6)
        fr.right = W:Label(fr, "GameFontDisableSmall")
        fr.right:SetPoint("BOTTOMRIGHT", -4, 7)
        fr.rule = W:Divider(fr, 100)
        fr.rule:SetPoint("BOTTOMLEFT", 0, 2)
        fr.rule:SetPoint("BOTTOMRIGHT", 0, 2)
        return fr
    end
    if kind == "season" then
        local fr = W:Panel(UIParent, 0.85)
        fr.icon = W:FramedIcon(fr, 30, "Interface\\Icons\\INV_Misc_Book_09")
        fr.icon:SetPoint("LEFT", 14, 0)
        fr.text = W:Label(fr, "GameFontNormal")
        fr.text:SetPoint("LEFT", fr.icon, "RIGHT", 12, 6)
        fr.sub = W:Label(fr, "GameFontHighlightSmall")
        fr.sub:SetPoint("TOPLEFT", fr.text, "BOTTOMLEFT", 0, -3)
        return fr
    end
    -- A session or a match: a card
    local fr = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    fr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    fr:SetBackdropColor(0.03, 0.04, 0.08, 0.7)
    fr:SetBackdropBorderColor(0.5, 0.42, 0.25, 0.9)
    fr.time = W:Label(fr, "GameFontHighlight")
    fr.time:SetPoint("TOPLEFT", 14, -12)
    fr.ago = W:Label(fr, "GameFontDisableSmall")
    fr.ago:SetPoint("TOPLEFT", fr.time, "BOTTOMLEFT", 0, -4)
    fr.sep = fr:CreateTexture(nil, "ARTWORK")
    fr.sep:SetColorTexture(1, 0.82, 0, 0.25)
    fr.sep:SetWidth(1)
    fr.sep:SetPoint("TOPLEFT", 66, -8)
    fr.sep:SetPoint("BOTTOMLEFT", 66, 8)
    fr.place = W:Label(fr, "GameFontNormal")
    fr.place:SetPoint("TOPLEFT", 80, -11)
    fr.place:SetJustifyH("LEFT")
    fr.place:SetWordWrap(false)
    fr.stats = W:Label(fr, "GameFontHighlightSmall")
    fr.stats:SetPoint("TOPLEFT", fr.place, "BOTTOMLEFT", 0, -6)
    fr.stats:SetJustifyH("LEFT")
    fr.stats:SetWordWrap(false)
    fr.best = W:FramedIcon(fr, 32)
    fr.best:SetPoint("RIGHT", -16, 0)
    fr.bestW = W:Label(fr, "GameFontNormal")
    fr.bestW:SetPoint("TOPRIGHT", fr.best, "TOPLEFT", -10, -1)
    fr.bestN = W:Label(fr, "GameFontHighlightSmall")
    fr.bestN:SetPoint("TOPRIGHT", fr.bestW, "BOTTOMRIGHT", 0, -4)
    fr.bestN:SetJustifyH("RIGHT")
    fr.bestN:SetWordWrap(false)
    fr.medal = W:Label(fr, "GameFontNormalLarge")
    fr.medal:SetPoint("RIGHT", -20, 0)
    fr:SetScript("OnClick", function(self)
        local h = self.item and self.item.hist
        if h and h.solo and MF.OpenSessionReport then
            W:Sound("row")
            MF:OpenSessionReport(h)
        end
    end)
    fr:SetScript("OnEnter", function(self)
        local h = self.item and self.item.hist
        if not h then return end
        self:SetBackdropBorderColor(1, 0.82, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(h.sub or "Fishing", 1, 0.82, 0)
        if h.zone then GameTooltip:AddLine(h.zone, 0.8, 0.8, 0.8) end
        if h.solo then
            if h.outcomes and MF.CastOutcomeSummary then GameTooltip:AddLine(MF:CastOutcomeSummary(h), 1, 1, 1, true) end
            GameTooltip:AddDoubleLine("Fishing time", MF:FormatClock(h.duration or 0), 0.63, 0.63, 0.63, 1, 1, 1)
            if h.elapsed then GameTooltip:AddDoubleLine("Session length", MF:FormatClock(h.elapsed), 0.63, 0.63, 0.63, 1, 1, 1) end
            local waters = h.spots and (MF.FishedWaters and MF:FishedWaters(h.spots) or h.spots) -- no "0 fish" waters
            if waters and #waters > 1 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Waters fished", 1, 0.82, 0)
                for _, e in ipairs(waters) do
                    GameTooltip:AddDoubleLine(e.name or "?", ("%d fish, %s"):format(e.count or 0, MF:Weight(e.total or 0)),
                        1, 1, 1, 0.8, 0.8, 0.8)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click for the report you can copy", 0.4, 0.8, 1)
        else
            GameTooltip:AddLine(h.place and ("Placed %d of %d"):format(h.place, h.players or 0) or "Match", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    fr:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.5, 0.42, 0.25, 0.9)
        W:HideTip(self)
    end)
    return fr
end

local function Ago(t)
    local s = math.max(0, (GetServerTime and GetServerTime() or time()) - t)
    if s < 3600 then return ("%d min ago"):format(math.max(1, math.floor(s / 60))) end
    if s < 86400 then return ("%d hr ago"):format(math.floor(s / 3600)) end
    return ("%d days ago"):format(math.floor(s / 86400))
end

local function FillRow(fr, it)
    if it.kind == "day" then
        fr.text:SetText(it.label)
        fr.right:SetText(it.right or "")
        return
    end
    if it.kind == "season" then
        local h = it.hist
        fr.text:SetText(("%s ended"):format(MF.SeasonName and MF:SeasonName(h.season) or "The season"))
        fr.sub:SetText(("%d XP   %d records   %d Kings"):format(h.xp or 0, h.records or 0, h.kings or 0))
        return
    end
    local h = it.hist
    fr.time:SetText(date("%H:%M", h.when))
    fr.ago:SetText(Ago(h.when))
    local right = 0
    if h.solo then
        fr.medal:Hide()
        fr.place:SetText((h.sub or "Somewhere") .. (h.zone and h.zone ~= h.sub and ("  |cffa0a0a0" .. h.zone .. "|r") or ""))
        local parts = {
            ("|cffffffff%d|r fish"):format(h.count or 0),
            "|cffffffff" .. MF:Weight(h.total or 0) .. "|r",
            "|cffa0a0a0" .. MF:FormatClock(h.duration or 0) .. "|r",
        }
        if MF:ValueEnabled() and (h.value or 0) > 0 then parts[#parts + 1] = MF:ShortMoney(h.value) end
        if (h.specimens or 0) > 0 then parts[#parts + 1] = STAR .. " |cffff8000" .. h.specimens .. "|r" end
        if (h.finds or 0) > 0 then parts[#parts + 1] = "|cffe6c066" .. MF:FindsText(h.finds) .. "|r" end
        fr.stats:SetText(table.concat(parts, "     "))
        local has = (h.biggest or 0) > 0
        fr.best:SetShown(has)
        fr.bestW:SetShown(has)
        fr.bestN:SetShown(has)
        if has then
            fr.best.icon:SetTexture(IconForName(h.biggestName) or MF:FishIcon(0) or 134400)
            fr.bestW:SetText(MF:Weight(h.biggest))
            fr.bestN:SetText(h.biggestName or "")
            fr.bestN:SetWidth(math.min(170, (fr.bestN:GetStringWidth() or 0) + 2))
            right = 32 + 16 + 10 + math.max(fr.bestN:GetWidth() or 0, fr.bestW:GetStringWidth() or 0) + 10
        end
        if (h.count or 0) == 0 and (h.finds or 0) == 0 then fr:SetBackdropColor(0.03, 0.04, 0.08, 0.45) else fr:SetBackdropColor(0.03, 0.04, 0.08, 0.7) end
    else
        fr.best:Hide() fr.bestW:Hide() fr.bestN:Hide()
        fr.place:SetText("Match at " .. (h.sub or "?"))
        fr.stats:SetText(h.players and ("%d anglers"):format(h.players) or "")
        local m = MEDAL[h.place or 0]
        fr.medal:Show()
        fr.medal:SetText(h.place and (h.place == 1 and "1st" or h.place == 2 and "2nd" or h.place == 3 and "3rd" or ("#" .. h.place)) or "")
        if m then fr.medal:SetTextColor(m[1], m[2], m[3]) else fr.medal:SetTextColor(0.8, 0.8, 0.8) end
        right = 60
    end
    local w = (fr:GetWidth() or 500) - 80 - right - 12
    fr.place:SetWidth(math.max(80, w))
    fr.stats:SetWidth(math.max(80, w))
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
local function Totals()
    local t = { sessions = 0, fish = 0, seconds = 0, best = 0, bestName = nil, specimens = 0, weight = 0,
        value = 0, matches = 0, wins = 0 }
    for _, h in ipairs(MF.cdb.history or {}) do
        if not h.solo and not h.season then
            t.matches = t.matches + 1
            if h.place == 1 then t.wins = t.wins + 1 end
        end
        if h.solo then
            t.value = t.value + (h.value or 0)
            if not t.bestHaul or (h.count or 0) > (t.bestHaul.count or 0) then t.bestHaul = h end
            if (h.biggest or 0) > t.best then t.bestWhen = h end
            t.sessions = t.sessions + 1
            t.fish = t.fish + (h.count or 0)
            t.seconds = t.seconds + (h.duration or 0)
            t.weight = t.weight + (h.total or 0)
            t.specimens = t.specimens + (h.specimens or 0)
            if (h.biggest or 0) > t.best then t.best, t.bestName = h.biggest, h.biggestName end
        end
    end
    return t
end

function P:Build(frame)
    self.frame = frame
    -- Four big numbers across the top
    local band = CreateFrame("Frame", nil, frame)
    band:SetPoint("TOPLEFT")
    band:SetPoint("TOPRIGHT")
    band:SetHeight(62)
    local bg = band:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    local rule = W:Divider(band, 100)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    band.cells = {}
    for i = 1, 4 do
        local c = CreateFrame("Frame", nil, band)
        c.value = W:Label(c, "GameFontHighlightHuge")
        c.value:SetPoint("TOP", 0, -9)
        c.label = W:Label(c, "GameFontNormalSmall")
        c.label:SetPoint("TOP", c.value, "BOTTOM", 0, -3)
        c.label:SetTextColor(0.8, 0.8, 0.8)
        -- The rest of "your log so far", on hover
        c:EnableMouse(true)
        c:SetScript("OnEnter", function(self)
            local t = P.totals
            if not t then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Your log so far", 1, 0.82, 0)
            GameTooltip:AddDoubleLine("Caught", ("%d fish, %s"):format(t.fish, MF:Weight(t.weight)), 0.7, 0.7, 0.7, 1, 1, 1)
            if t.specimens > 0 then GameTooltip:AddDoubleLine("Specimens landed", tostring(t.specimens), 0.7, 0.7, 0.7, 1, 0.5, 0) end
            if MF:ValueEnabled() and t.value > 0 then GameTooltip:AddDoubleLine("Your haul was worth", MF:ShortMoney(t.value), 0.7, 0.7, 0.7, 1, 1, 1) end
            if t.matches > 0 then GameTooltip:AddDoubleLine("Matches fished", ("%d, won %d"):format(t.matches, t.wins), 0.7, 0.7, 0.7, 1, 1, 1) end
            if t.bestWhen then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Biggest catch", ("%s %s"):format(MF:Weight(t.best), t.bestName or "fish"), 0.7, 0.7, 0.7, 1, 0.82, 0)
                GameTooltip:AddLine(("at %s, %s"):format(t.bestWhen.sub or "?", date("%d %b", t.bestWhen.when)), 0.6, 0.6, 0.6)
            end
            if t.bestHaul and (t.bestHaul.count or 0) > 0 then
                GameTooltip:AddDoubleLine("Best haul", ("%d fish, %s"):format(t.bestHaul.count, MF:Weight(t.bestHaul.total or 0)), 0.7, 0.7, 0.7, 1, 0.82, 0)
                GameTooltip:AddLine(("at %s, %s"):format(t.bestHaul.sub or "?", date("%d %b", t.bestHaul.when)), 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function(self) W:HideTip(self) end)
        band.cells[i] = c
    end
    band:SetScript("OnSizeChanged", function(b)
        local w = (b:GetWidth() or 600) / 4
        for i, c in ipairs(b.cells) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", (i - 1) * w, 0)
            c:SetSize(w, 62)
        end
    end)
    self.band = band
    self.list = W:VList(frame, MakeRow, FillRow)
    self.list:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, -8)
    self.list:SetPoint("BOTTOMRIGHT", -16, 0)
    self.empty = W:Label(frame, "GameFontDisable", "No logs or matches yet. Cast a line and this fills in.")
    self.empty:SetPoint("CENTER", 0, -20)
end

function P:Refresh()
    local t = Totals()
    self.totals = t
    local hours = t.seconds / 3600
    local cells = self.band.cells
    cells[1].value:SetText(t.sessions)
    cells[1].label:SetText("sessions")
    cells[2].value:SetText(t.fish)
    cells[2].label:SetText(hours > 0.05 and ("fish, %.1f an hour"):format(t.fish / hours) or "fish")
    cells[3].value:SetText(hours >= 1 and ("%.1fh"):format(hours) or ("%dm"):format(math.floor(t.seconds / 60)))
    cells[3].label:SetText("on the water")
    cells[4].value:SetText(t.best > 0 and MF:Weight(t.best) or "-")
    cells[4].label:SetText(t.bestName and ("best: " .. t.bestName) or "best catch")
    local w = (self.band:GetWidth() or 0)
    if w > 0 then self.band:GetScript("OnSizeChanged")(self.band) end

    local hideEmpty = MF.db.settings.historyHideEmpty
    local items, lastDay = {}, nil
    local dayIndex
    local history = MF.cdb.history or {}
    for i = #history, 1, -1 do
        local h = history[i]
        local show = h.season or (h.solo and not (hideEmpty and (h.count or 0) == 0 and (h.finds or 0) == 0)) or (not h.solo and h.sub)
        if show and h.when then
            local day = date("%Y-%j", h.when)
            if day ~= lastDay then
                lastDay = day
                items[#items + 1] = { kind = "day", h = 30, label = DayLabel(h.when), fish = 0 }
                dayIndex = #items
            end
            items[#items + 1] = { kind = h.season and "season" or "card", h = 52, gap = 6, hist = h }
            local dayItem = items[dayIndex]
            if h.solo then dayItem.fish = dayItem.fish + (h.count or 0) end
            dayItem.right = dayItem.fish > 0 and (dayItem.fish .. " fish") or ""
        end
    end
    self.items = items
    self.list:SetItems(items, true)
    self.empty:SetShown(#items == 0)
end

J:AddPage({
    key = "history",
    match = function(state)
        if state.recap or state.tab ~= "history" then return false end
        -- Its sessions view offers "By spot"; its spots view offers "Sessions"
        for _, a in ipairs(state.actions or {}) do if a.label == "By spot" then return true end end
        return false
    end,
    build = function(frame, tfl)
        MF = tfl
        P:Build(frame)
    end,
    refresh = function() P:Refresh() end,
    subheading = function() return "Your logbook" end,
    count = function()
        local n = 0
        for _, it in ipairs(P.items or {}) do if it.kind ~= "day" then n = n + 1 end end
        return n == 1 and "1 entry" or (n .. " entries")
    end,
})
