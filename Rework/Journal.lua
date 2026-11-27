-- The journal, redrawn.
--
-- The Fishing Log's journal builds each page as a list of "lines" (text, columns, icon, click handler,
-- tooltip) plus up to five action buttons and four sub-tabs, then draws them as a plain table. We keep
-- all of that machinery running exactly as it is:
--   * its window stays "shown" while ours is open, but lives under a hidden parent, so nothing of it is
--     drawn and none of its buttons take clicks;
--   * every page build is wrapped so we receive the same lines it drew;
--   * every tab, sub-tab, filter and action we show simply clicks its own hidden button.
-- So every feature keeps working, and pages The Fishing Log adds in future appear here by themselves.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = {}
ns.Journal = J

local MF, win            -- The Fishing Log's namespace and its own (hidden) journal window
local f                  -- our window
local built = {}         -- the last page The Fishing Log built: lines, actions, subs
local host = CreateFrame("Frame")
host:Hide()

local ROW_H, FEATURED_H, HEADER_H, SPACER_H = 22, 26, 30, 10
local MIN_W, MIN_H, MAX_W, MAX_H = 760, 500, 1400, 1200
local CONTENT_TOP = -60
-- Our rows use a 12pt font where The Fishing Log's used 10pt. It wraps its notes to fit the width it
-- thinks it has, so it is told it has a little less room than we really do.
local FONT_RATIO = 0.83

local VIEW_NAMES = {
    zones = "Waters, zone by zone", fish = "Every fish", cards = "Card album",
    here = "Fishing here", tools = "Angling tools", goals = "Fishing goals",
}

function J:MF() return MF end
function J:Frame() return f end
function J:Host() return win end

local function Reading(text)
    if not text then return "" end
    return (tostring(text):gsub("|cff858585", "|cffa0a0a0"))
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function Kind(line)
    if line.header then return "header", HEADER_H end
    local hasText = line.text and line.text ~= ""
    if not hasText and not line.icon and not line.columns and not (line.right and line.right ~= "") then
        return "spacer", SPACER_H
    end
    if line.featured then return "featured", FEATURED_H end
    return "line", ROW_H
end

local function RowTooltip(row)
    local line = row.line
    if not line or line.header then return end
    local text = line.text and line.text ~= "" and Reading(line.text)
    if not text then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    local labels = row.columnLabels or {}
    local any = false
    if line.columns then
        for n, value in ipairs(line.columns) do
            if value and value ~= "" then
                any = true
                local label = labels[n]
                if label and label ~= "" then
                    GameTooltip:AddDoubleLine(Reading(label), Reading(value), 0.63, 0.63, 0.63, 1, 1, 1)
                else
                    GameTooltip:AddLine(Reading(value), 1, 1, 1, true)
                end
            end
        end
    end
    if not any and line.right and line.right ~= "" then GameTooltip:AddLine(Reading(line.right), 1, 1, 1, true) end
    for _, help in ipairs(line.tooltip or {}) do GameTooltip:AddLine(Reading(help), 1, 1, 1, true) end
    if line.onClick then GameTooltip:AddLine("Click to open", 0.4, 0.8, 1) end
    GameTooltip:Show()
end

local function NewRow(list)
    local row = CreateFrame("Button", nil, list)
    row:RegisterForClicks("LeftButtonUp")
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.035)
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetAllPoints()
    if not W:Atlas(row.sel, "PetList-ButtonSelect") then row.sel:SetColorTexture(1, 0.82, 0, 0.16) end
    row.sel:SetAlpha(0.55)
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT", 0, -1)
    row.mark:SetPoint("BOTTOMLEFT", 0, 1)
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(1, 0.82, 0, 0.9)
    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.hl:SetAllPoints()
    row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.hl:SetBlendMode("ADD")
    row.hl:SetAlpha(0)

    row.iconBack = row:CreateTexture(nil, "ARTWORK")
    row.iconBack:SetSize(20, 20)
    row.iconBack:SetColorTexture(0, 0, 0, 0.9)
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon:SetPoint("TOPLEFT", row.iconBack, "TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", row.iconBack, "BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.text:SetShadowOffset(1, -1)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWordWrap(false)
    row.right:SetShadowOffset(1, -1)
    row.cols = {}
    for n = 1, 4 do
        local c = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        c:SetJustifyH("RIGHT")
        c:SetWordWrap(false)
        c:SetShadowOffset(1, -1)
        row.cols[n] = c
    end
    row.rule = W:Divider(row, 100)
    row.rule:SetPoint("BOTTOMLEFT", 0, 2)
    row.rule:SetPoint("BOTTOMRIGHT", 0, 2)

    row:SetScript("OnEnter", function(self)
        if self.line and self.line.onClick then
            W:Tween(self.hl, 0.12, function(e) self.hl:SetAlpha(0.55 * e) end)
        end
        RowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        -- Always replace the fade-in, even before it has drawn a frame: left
        -- running, it finished after the mouse had gone and the row stayed lit.
        local a = self.hl:GetAlpha()
        if a > 0 then
            W:Tween(self.hl, 0.2, function(e) self.hl:SetAlpha(a * (1 - e)) end)
        else
            W:StopTween(self.hl)
        end
        W:HideTip(self)
    end)
    row:SetScript("OnClick", function(self)
        local line = self.line
        if line and line.onClick then
            W:Sound("row")
            line.onClick()
        end
    end)
    row:SetScript("OnMouseWheel", function(_, d) J:Wheel(d) end)
    row:EnableMouseWheel(true)
    return row
end

-- Cached on the line, per width: rows are refilled every frame while scrolling
local function ColumnWidths(line, rowW)
    local c = line.__lodgeCols
    if c and c.w == rowW then return c, c.total end
    local widths = line.columnWidths or { 70, 70, 46, 88 }
    local scale = math.min(1.3, math.max(1.1, rowW / 600))
    c = { w = rowW, total = 0 }
    for n = 1, 4 do
        c[n] = math.floor((widths[n] or 0) * scale)
        c.total = c.total + c[n]
    end
    line.__lodgeCols = c
    return c, c.total
end

local function FillRow(row, line, kind, h, rowW, group, labels)
    row.line = line
    row.columnLabels = labels
    row:SetHeight(h)
    row:SetWidth(rowW)
    local header, featured = kind == "header", kind == "featured"
    local spacer = kind == "spacer"
    row.rule:SetShown(header)
    row:EnableMouse(not spacer and not header)

    -- Shading: alternate groups (a session and its detail rows read as one), gold for yours
    -- The gold band marks your own entries only. Each section's first
    -- ("featured") row used to wear it too, and read as a stuck highlight.
    local mine = line.mine
    row.stripe:SetShown(not header and not spacer and group % 2 == 1)
    row.sel:SetShown(mine and not header and not spacer and true or false)
    row.mark:SetShown(line.mine and true or false)
    -- A refill (scrolling, a refresh) may hand this row a different line:
    -- lit only if the mouse is on it and the new line can be clicked.
    W:StopTween(row.hl)
    row.hl:SetAlpha(line.onClick and row:IsMouseOver() and 0.55 or 0)

    local x = 6
    if line.icon and not header then
        local size = featured and 22 or 18
        row.iconBack:SetSize(size + 2, size + 2)
        row.iconBack:ClearAllPoints()
        row.iconBack:SetPoint("LEFT", x, 0)
        row.icon:SetTexture(line.icon)
        row.iconBack:Show()
        row.icon:Show()
        x = x + size + 8
    else
        row.iconBack:Hide()
        row.icon:Hide()
    end

    row.text:SetFontObject(header and "GameFontNormal" or featured and "GameFontNormalLarge" or "GameFontHighlight")
    row.text:SetText(Reading(line.text))
    if header then
        row.text:SetTextColor(1, 0.82, 0)
    elseif featured then
        row.text:SetTextColor(1, 0.82, 0)
    else
        row.text:SetTextColor(1, 1, 1)
    end
    row.text:ClearAllPoints()
    row.text:SetPoint(header and "BOTTOMLEFT" or "LEFT", x, header and 7 or 0)

    local widths, total = ColumnWidths(line, rowW)
    local cols = line.columns
    local edge = 6
    for n = 4, 1, -1 do
        local c = row.cols[n]
        local wN = widths[n]
        c:ClearAllPoints()
        c:SetPoint(header and "BOTTOMRIGHT" or "RIGHT", -edge, header and 7 or 0)
        c:SetWidth(math.max(1, wN - 8))
        edge = edge + wN
        local show = cols ~= nil and wN > 0
        c:SetShown(show)
        if show then
            c:SetFontObject(header and "GameFontHighlightSmall" or "GameFontHighlight")
            c:SetText(Reading(cols[n]))
            if header then c:SetTextColor(0.63, 0.63, 0.63) else c:SetTextColor(1, 1, 1) end
        end
    end

    local right = line.right and line.right ~= "" and not cols and Reading(line.right) or nil
    row.right:SetShown(right ~= nil)
    local rightW = 0
    if right then
        row.right:SetFontObject(header and "GameFontHighlightSmall" or "GameFontHighlight")
        row.right:ClearAllPoints()
        row.right:SetPoint(header and "BOTTOMRIGHT" or "RIGHT", -6, header and 7 or 0)
        row.right:SetWidth(0)
        row.right:SetText(right)
        rightW = math.min(row.right:GetStringWidth() or 0, rowW * 0.55)
        row.right:SetWidth(rightW + 2)
        if header then row.right:SetTextColor(0.63, 0.63, 0.63) else row.right:SetTextColor(1, 1, 1) end
    end
    local room = rowW - x - 8 - (cols and total or 0) - (right and (rightW + 14) or 0)
    row.text:SetWidth(math.max(40, room))
    row:Show()
end

-- ---------------------------------------------------------------------------
-- The list: rows of different heights, only the visible ones exist, smooth scrolling
-- ---------------------------------------------------------------------------
local function BuildList(parent)
    local list = CreateFrame("Frame", nil, parent)
    if list.SetClipsChildren then list:SetClipsChildren(true) end
    list.rows, list.layout = {}, {}
    list.scroll, list.target, list.total = 0, 0, 0
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) J:Wheel(d) end)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetWidth(10)
    bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 14, 0)
    bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 14, 0)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.45)
    bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetSize(16, 24) end
    bar:SetScript("OnValueChanged", function(_, v)
        if list.updating then return end
        list.scroll, list.target = v, v
        J:Place()
    end)
    list.bar = bar

    -- Easing toward the wheel's target, a frame at a time
    list:SetScript("OnUpdate", function(self, elapsed)
        if math.abs(self.target - self.scroll) < 0.5 then
            if self.scroll ~= self.target then self.scroll = self.target J:Place() end
            return
        end
        local k = (ns.db.animations ~= false) and math.min(1, elapsed * 16) or 1
        self.scroll = self.scroll + (self.target - self.scroll) * k
        J:Place()
    end)
    return list
end

function J:Wheel(delta)
    local list = self.list
    if not list then return end
    local maxS = math.max(0, list.total - list:GetHeight())
    list.target = math.max(0, math.min(maxS, list.target - delta * ROW_H * 3))
end

-- Lay out every line (positions only; cheap)
function J:Layout()
    local list = self.list
    local lines = built.lines or {}
    local layout, y, group = {}, 0, 0
    for i, line in ipairs(lines) do
        local kind, h = Kind(line)
        if line.header then group = 0 end
        if line.group then group = group + 1 end
        if kind == "header" and i == 1 then h = h - 6 end
        layout[i] = { y = y, h = h, kind = kind, group = group }
        y = y + h
    end
    list.layout, list.total = layout, y + 6
    list.gen = (list.gen or 0) + 1
    -- The column labels each row inherits from the last header above it, and the entry count
    local labels, n = {}, 0
    for i, line in ipairs(lines) do
        if line.header then labels = line.columns or {} end
        layout[i].labels = labels
        if not line.header and layout[i].kind ~= "spacer" then n = n + 1 end
    end
    list.entries = n
end

-- Put the rows that are on screen in place
function J:Place()
    local list = self.list
    if not list or not f or not f:IsShown() then return end
    local lines, layout = built.lines or {}, list.layout
    local viewH, rowW = list:GetHeight() or 0, (list:GetWidth() or 0)
    local maxS = math.max(0, list.total - viewH)
    if list.scroll > maxS then list.scroll = maxS end
    if list.target > maxS then list.target = maxS end
    list.updating = true
    list.bar:SetMinMaxValues(0, maxS)
    list.bar:SetValue(list.scroll)
    list.bar:SetShown(maxS > 0)
    list.updating = false

    local used = 0
    local top, bottom = list.scroll, list.scroll + viewH
    -- First line in view (binary search: lines are laid out top to bottom)
    local lo, hi = 1, #lines
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local L = layout[mid]
        if L.y + L.h <= top then lo = mid + 1 else hi = mid end
    end
    for i = lo, #lines do
        local L, line = layout[i], lines[i]
        if L.y >= bottom then break end
        used = used + 1
        local row = list.rows[used]
        if not row then row = NewRow(list) list.rows[used] = row end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(L.y - list.scroll))
        if row.line ~= line or row.gen ~= list.gen or row.w ~= rowW then
            FillRow(row, line, L.kind, L.h, rowW, L.group, L.labels)
            row.gen, row.w = list.gen, rowW
        end
        if not row:IsShown() then row:Show() end
    end
    for i = used + 1, #list.rows do
        list.rows[i]:Hide()
        list.rows[i].line = nil
        list.rows[i].gen = nil
    end
    if self.count then
        local n = list.entries or 0
        self.count:SetText(n > 0 and (n == 1 and "1 entry" or (n .. " entries")) or "")
    end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local function CurrentContext()
    local tab = MF.recapActive and "recap" or (win and win.tab) or "journal"
    local view = tab == "journal" and MF.db.settings.journalView or ""
    local sub = built.subs and built.subs.current or ""
    return tab .. ":" .. tostring(view) .. ":" .. tostring(sub)
end

-- What a bottom tab is called here: Records is drawn by the Waters page, and History is the
-- Logbook (its sessions, by spot, and the session reports)
local RENAMED = { history = "Logbook" }
local function TabName(key, label)
    if key == "records" and ns.Waters then return "Waters" end
    return RENAMED[key] or label
end

local function TabLabel(key)
    for _, tab in ipairs(MF.JOURNAL_TABS) do if tab.key == key then return TabName(key, tab.label) end end
    return "Journal"
end

-- The bottom tab that's lit: the session reports live in The Fishing Log's Angling tools, but
-- they belong to the Logbook here
local function ShownTab()
    local key = win.tab
    if key == "journal" and MF.db.settings.journalView == "tools" and (MF.anglingToolsView or "waters") == "reports" then
        return "history"
    end
    return key
end

local function Stat(parent)
    local s = CreateFrame("Frame", nil, parent)
    s.value = W:Label(s, "GameFontHighlightHuge")
    s.value:SetPoint("TOP", 0, -8)
    s.label = W:Label(s, "GameFontNormalSmall")
    s.label:SetPoint("TOP", s.value, "BOTTOM", 0, -3)
    s.label:SetTextColor(0.8, 0.8, 0.8)
    return s
end

-- A small tab along the top of the page (sub-pages, search filters): gold text and an underline when chosen
local function TopTab(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetShadowOffset(1, -1)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT", 2, 0)
    b.line:SetPoint("BOTTOMRIGHT", -2, 0)
    b.line:SetHeight(2)
    b.line:SetColorTexture(1, 0.82, 0, 1)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetAllPoints()
    b.glow:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.85, 0.45)
    b.glow:SetAlpha(0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 1, 1)
    hl:SetAlpha(0.12)
    function b:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(math.max(56, (self.text:GetStringWidth() or 40) + 22))
    end
    function b:SetCurrent(on)
        self.current = on
        self.line:SetShown(on)
        self.glow:SetAlpha(on and 0.22 or 0)
        if on then self.text:SetTextColor(1, 0.82, 0) else self.text:SetTextColor(0.75, 0.75, 0.75) end
    end
    b:SetScript("OnClick", function(self)
        if self.current then return end
        W:Sound("tab")
        onClick(self)
    end)
    b:SetCurrent(false)
    return b
end

local function SavePosition()
    local p, _, rp, x, y = f:GetPoint()
    if p then ns.db.journalPos = { p, rp, x, y } end
end

function J:ApplySize(reset)
    if not f then return end
    local w = math.max(MIN_W, math.min(MAX_W, ns.db.journalW or 900))
    local h = math.max(MIN_H, math.min(MAX_H, ns.db.journalH or 620))
    f:SetSize(w, h)
    if reset or not ns.db.journalPos then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    else
        local p = ns.db.journalPos
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    self:SyncHost()
end

-- Keep The Fishing Log's own window the right size for its notes to wrap to our width, and sitting
-- where ours is, so things it opens "beside the journal" (the fish card) land beside ours.
function J:SyncHost()
    if not (f and win and self.list) or f.sizing then return end
    local rowW = self.list:GetWidth()
    if not rowW or rowW <= 0 then rowW = f:GetWidth() - 60 end
    local want = math.max(540, math.floor(rowW * FONT_RATIO + 56))
    win:ClearAllPoints()
    win:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    if math.abs((win:GetWidth() or 0) - want) > 1 or math.abs((win:GetHeight() or 0) - f:GetHeight()) > 1 then
        win:SetSize(want, f:GetHeight())
    end
end

function J:Build()
    if f then return f end
    f = W:Window("AnglersLodgeJournal", "The Fishing Log", 780, 580, ns.ICON)
    f:SetScale(ns.db.scale or 1)
    f:SetFrameStrata("HIGH")
    f.onMoved = SavePosition

    -- Rank and experience, top right
    f.rank = W:Label(f, "GameFontNormal")
    f.rank:SetPoint("TOPRIGHT", -16, -30)
    f.rank:SetJustifyH("RIGHT")
    f.xp = W:Bar(f, 200, 12, 0.58, 0.0, 0.55)
    f.xp:SetPoint("TOPRIGHT", -14, -45)
    f.xp.text:SetFontObject("GameFontHighlightSmall")
    f.xp:EnableMouse(true)
    W:Tip(f.xp, "Angler rank", function()
        local xp = MF.cdb.profile.xp or 0
        local _, name, nextXP = MF:RankFor(xp)
        return ("%s, %d XP%s"):format(name, xp, nextXP and ("\n%d XP to the next rank."):format(nextXP - xp) or "\nThe top of the ladder.")
    end)

    -- (No header buttons: the options and board toggle that sat by the XP bar
    -- are removed. Settings are on the minimap button, /tfl options and
    -- the settings window; the fishing board opens when you fish, and has its key
    -- binding and the minimap button.)

    local ground = W:Ground(f)
    ground:SetPoint("TOPLEFT", 4, CONTENT_TOP)
    ground:SetPoint("BOTTOMRIGHT", -4, 4)
    f.ground = ground
    W:HideTopCorners(ground) -- they sat right under the sub-page tabs

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", ground, "TOPLEFT", 12, -8)
    body:SetPoint("BOTTOMRIGHT", ground, "BOTTOMRIGHT", -12, 8)
    f.body = body

    -- Top strip: sub-pages on the left, search and filters on the right
    local strip = CreateFrame("Frame", nil, body)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(26)
    f.strip = strip
    strip.rule = W:Divider(strip, 100)
    strip.rule:SetPoint("BOTTOMLEFT", 0, -2)
    strip.rule:SetPoint("BOTTOMRIGHT", 0, -2)
    f.subs = {}
    for i = 1, 4 do
        local b = TopTab(strip, function(self)
            local s = win.subs[self.index]
            if s and s:IsEnabled() then s:Click() end
        end)
        b.index = i
        b:Hide()
        f.subs[i] = b
    end
    f.filters = {}
    for i = 1, 3 do
        local b = TopTab(strip, function(self)
            local fb = win.searchBar.filters[self.index]
            if fb and fb:IsEnabled() then fb:Click() end
        end)
        b.index = i
        b:Hide()
        f.filters[i] = b
    end
    f.search = W:Search(strip, 220, function(text)
        if J.syncingSearch or not win then return end
        local edit = win.searchBar.edit
        if (edit:GetText() or "") ~= text then edit:SetText(text) end
    end, "Search fish or zones")
    f.search:Hide()

    -- Hero banner (the recap) and the three big numbers
    local hero = W:Panel(body, 0.85)
    hero:SetHeight(84)
    hero.icon = W:FramedIcon(hero, 48, ns.ICON)
    hero.icon:SetPoint("LEFT", 18, 2)
    hero.title = W:Label(hero, "GameFontNormalLarge")
    hero.title:SetPoint("TOPLEFT", 84, -14)
    hero.title:SetPoint("TOPRIGHT", -16, -14)
    hero.title:SetJustifyH("LEFT")
    hero.note = W:Label(hero, "GameFontHighlight")
    hero.note:SetPoint("TOPLEFT", hero.title, "BOTTOMLEFT", 0, -5)
    hero.note:SetPoint("TOPRIGHT", hero.title, "BOTTOMRIGHT", 0, -5)
    hero.note:SetJustifyH("LEFT")
    hero.note:SetTextColor(0.85, 0.85, 0.85)
    hero.status = W:Label(hero, "GameFontDisableSmall")
    hero.status:SetPoint("BOTTOMRIGHT", -12, 8)
    hero:Hide()
    f.hero = hero

    local summary = CreateFrame("Frame", nil, body)
    summary:SetHeight(60)
    summary.cells = {}
    for i = 1, 3 do
        local s = Stat(summary)
        summary.cells[i] = s
        if i > 1 then
            local sep = summary:CreateTexture(nil, "ARTWORK")
            sep:SetColorTexture(1, 0.82, 0, 0.25)
            sep:SetWidth(1)
            sep:SetPoint("TOP", s, "TOPLEFT", 0, -10)
            sep:SetPoint("BOTTOM", s, "BOTTOMLEFT", 0, 10)
        end
    end
    summary.bg = summary:CreateTexture(nil, "BACKGROUND")
    summary.bg:SetAllPoints()
    summary.bg:SetColorTexture(0, 0, 0, 0.35)
    summary.rule = W:Divider(summary, 100)
    summary.rule:SetPoint("BOTTOMLEFT", 0, 0)
    summary.rule:SetPoint("BOTTOMRIGHT", 0, 0)
    summary:Hide()
    f.summary = summary

    -- Footer: the page's actions, and how much is on it
    local footer = CreateFrame("Frame", nil, body)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(14)
    f.actions = {}
    for i = 1, 5 do
        local b = W:Button(footer, "", 100, 22, function(self)
            if self.fn then self.fn() end
        end)
        b.index = i
        if i == 1 then b:SetPoint("BOTTOMLEFT", 0, 0) else b:SetPoint("LEFT", f.actions[i - 1], "RIGHT", 6, 0) end
        b:Hide()
        f.actions[i] = b
    end
    self.count = W:Label(footer, "GameFontDisableSmall")
    self.count:SetPoint("BOTTOMRIGHT", -4, 6)
    f.footer = footer

    -- The list
    local list = BuildList(body)
    self.list = list
    list:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -16, 6)
    list:SetScript("OnSizeChanged", function() J:SyncHost() J:Layout() J:Place() end)

    -- Nothing to show yet
    local empty = CreateFrame("Frame", nil, body)
    empty:SetSize(400, 220)
    empty:SetPoint("CENTER", 0, 10)
    empty.icon = W:FramedIcon(empty, 56, ns.ICON)
    empty.icon:SetPoint("TOP", 0, -6)
    empty.title = W:Label(empty, "GameFontNormalLarge")
    empty.title:SetPoint("TOP", empty.icon, "BOTTOM", 0, -18)
    empty.note = W:Label(empty, "GameFontHighlight")
    empty.note:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
    empty.note:SetWidth(380)
    empty.note:SetTextColor(0.8, 0.8, 0.8)
    empty.action = W:Button(empty, "", 160, 24, function()
        local a = win.actions[1]
        if a then local fn = a:GetScript("OnClick") if fn then fn(a) end end
    end)
    empty.action:SetPoint("TOP", empty.note, "BOTTOM", 0, -18)
    empty:Hide()
    f.empty = empty

    -- The recap's way out: one big red button at the bottom, impossible to miss
    local go = W:Button(body, "Continue", 240, 36, function()
        if not J:PressAction("Continue") then MF.recapActive = false MF:RedrawJournal() end
    end, "Continue", "On to your journal.")
    go:SetPoint("BOTTOM", footer, "TOP", 0, 6)
    local fs = go:GetFontString()
    if fs then fs:SetFontObject("GameFontNormalLarge") end
    go:Hide()
    f.bigAction = go

    -- Bottom tabs: one per Fishing Log page
    f.tabs = {}
    for i, tab in ipairs(MF.JOURNAL_TABS) do
        local b = W:Make("Button", "AnglersLodgeJournalTab" .. i, f, "PanelTabButtonTemplate")
        if not b then
            b = CreateFrame("Button", "AnglersLodgeJournalTab" .. i, f, "UIPanelButtonTemplate")
            b:SetSize(100, 24)
        end
        b:SetID(i)
        b:SetText(TabName(tab.key, tab.label))
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
        if i == 1 then b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
        else b:SetPoint("TOPLEFT", f.tabs[i - 1], "TOPRIGHT", 3, 0) end
        b:SetScript("OnClick", function()
            W:Sound("tab")
            J.recapPending = false
            if tab.key == win.tab and MF.recapActive then
                MF.recapActive = false
                MF:RedrawJournal()
            elseif tab.key == win.tab then
                -- Already here: from a sub-view (here, tools, goals, album, by spot), back to the start
                if not J:PressAction("Journal", "Back", "Sessions") and tab.key == "journal" then
                    -- Angling tools has no way straight back: through "Fishing here", which has one
                    MF:OpenFishingHere()
                    J:PressAction("Journal")
                end
            elseif tab.button and tab.button:IsEnabled() then
                tab.button:Click()
            else
                MF:OpenJournal(tab.key)
            end
        end)
        b.key = tab.key
        f.tabs[i] = b
    end
    f.numTabs = #f.tabs
    if f.Tabs == nil then f.Tabs = f.tabs end

    -- Resizing from the corner
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if not f.StartSizing then return end
        f.sizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        if not f.sizing then return end
        f.sizing = nil
        f:StopMovingOrSizing()
        ns.db.journalW, ns.db.journalH = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
        SavePosition()
        J:SyncHost()
    end)

    -- OnShow/OnHide also fire when the whole interface hides and returns (Alt-Z, cinematics):
    -- only a real open or close plays its sound, and only a real close closes The Fishing Log's journal
    f:SetScript("OnShow", function()
        if f.lodgeOpen then return end
        f.lodgeOpen = true
        W:Sound("open")
        if ns.db.animations ~= false then
            f:SetAlpha(0)
            W:Tween(f, 0.16, function(e) f:SetAlpha(e) end)
        end
    end)
    f:SetScript("OnHide", function()
        if f:IsShown() then return end -- the interface hid, not us
        f.lodgeOpen = false
        W:Sound("close")
        if win and win:IsShown() and not J.closing then win:Hide() end
    end)

    self:ApplySize()
    return f
end

-- Arrange the page's furniture around the list
function J:Arrange()
    local lines, subs, actions = built.lines or {}, built.subs, built.actions or {}
    local searching = win.searchBar and win.searchBar:IsShown()
    local nSubs = subs and #subs or 0

    -- Views, filters and commands are in the navigation strip (Nav.lua). This strip below it only
    -- carries The Fishing Log's own search box, on its search results page.
    local navH = self.navH or 0
    f.strip:ClearAllPoints()
    f.strip:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -navH)
    f.strip:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -navH)
    local x = 0
    for _, b in ipairs(f.subs) do b:Hide() end
    for i, b in ipairs(f.filters) do
        local fb = win.searchBar.filters[i]
        b:SetShown(searching and fb ~= nil)
        if searching and fb then
            b:SetLabel(fb:GetText() or "")
            b:SetCurrent(not fb:IsEnabled())
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", f.strip, "BOTTOMLEFT", x, 0)
            x = x + b:GetWidth() + 4
        end
    end
    f.search:SetShown(searching)
    if searching then
        f.search:ClearAllPoints()
        f.search:SetPoint("RIGHT", f.strip, "RIGHT", -2, 2)
        if not f.search:HasFocus() then
            local text = win.searchBar.edit:GetText() or ""
            if (f.search:GetText() or "") ~= text then
                self.syncingSearch = true
                f.search:SetText(text)
                self.syncingSearch = false
            end
        end
    end
    f.strip:SetShown(searching and true or false)
    local top = -navH - (searching and 36 or 0)
    local hero = lines.hero
    f.hero:SetShown(hero ~= nil)
    if hero then
        f.hero:ClearAllPoints()
        f.hero:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, top)
        f.hero:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, top)
        f.hero.title:SetText(Reading(hero.title))
        f.hero.note:SetText(Reading(hero.subtitle))
        f.hero.status:SetText(Reading(hero.status))
        top = top - 84 - 8
    end
    local summary = lines.summary
    f.summary:SetShown(summary ~= nil)
    if summary then
        f.summary:ClearAllPoints()
        f.summary:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, top)
        f.summary:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, top)
        local w = (f.body:GetWidth() or 600) / 3
        for i, cell in ipairs(f.summary.cells) do
            local stat = summary[i]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", f.summary, "TOPLEFT", (i - 1) * w, 0)
            cell:SetSize(w, 60)
            cell.value:SetText(stat and Reading(stat.value) or "")
            cell.label:SetText(stat and Reading(stat.label) or "")
        end
        top = top - 60 - 6
    end
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, top)
    local recapGo = MF.recapActive and true or false
    f.bigAction:SetShown(recapGo)
    self.list:SetPoint("BOTTOMRIGHT", f.footer, "TOPRIGHT", -16, recapGo and 50 or 6)

    -- When the page is empty, its first action is the big button in the middle
    local empty = lines.empty
    f.empty:SetShown(empty ~= nil)
    self.list:SetShown(empty == nil)
    if empty then
        f.empty.title:SetText(Reading(empty.title))
        f.empty.note:SetText(Reading(empty.note))
        local a = actions[1]
        f.empty.action:SetShown(a ~= nil)
        if a then f.empty.action:SetText(a.label) end
    end

    -- Heading, tabs, rank
    local key = win.tab
    self:Header()
    if not MF.recapActive then
        local sub = ""
        if key == "journal" then
            local view = MF.db.settings.journalView
            sub = VIEW_NAMES[view] or ""
            if searching and (win.searchBar.edit:GetText() or "") ~= "" then sub = "Search results" end
        end
        f.subheading:SetText(sub)
    end
end

-- ---------------------------------------------------------------------------
-- The recap, as a banner on the page you land on (not a page to click past)
-- ---------------------------------------------------------------------------
-- A popup that sits just above the window (it takes no room inside it)
function J:BuildBanner()
    local b = CreateFrame("Frame", nil, f, "BackdropTemplate")
    b:SetHeight(60)
    b:SetFrameLevel(f:GetFrameLevel() + 30)
    b:SetClampedToScreen(true)
    b:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", tile = true, tileSize = 32, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 } })
    b.shade = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.shade:SetPoint("TOPLEFT", 5, -5)
    b.shade:SetPoint("BOTTOMRIGHT", -5, 5)
    b.shade:SetColorTexture(0, 0, 0, 0.6)
    b.icon = W:FramedIcon(b, 34, "Interface\\Icons\\INV_Misc_Book_09")
    b.icon:SetPoint("LEFT", 16, 0)
    b.title = W:Label(b, "GameFontNormal")
    b.title:SetPoint("TOPLEFT", 62, -14)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.note = W:Label(b, "GameFontHighlightSmall")
    b.note:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -3)
    b.note:SetJustifyH("LEFT")
    b.note:SetWordWrap(false)
    b.note:SetTextColor(0.8, 0.8, 0.8)
    b.close = CreateFrame("Button", nil, b, "UIPanelCloseButton")
    b.close:SetPoint("RIGHT", -6, 0)
    b.close:SetScale(0.8)
    b.close:SetScript("OnClick", function() W:Sound("close") J.recapPending = false MF:RedrawJournal() end)
    b.open = W:Button(b, "See what changed", 140, 22, function()
        J.recapPending = false
        if MF.ShowRecap then MF:ShowRecap() end
    end)
    b.open:SetPoint("RIGHT", b.close, "LEFT", -4, 0)
    b:Hide()
    f.banner = b
end

-- The noticeboard and the recap's changes, worked out at most once a second (The Fishing Log
-- redraws every second, and both the banner and the header ask)
function J:Notices()
    local now = GetTime()
    if not self.noticesCache or now - (self.noticesAt or 0) >= 1 then
        local ok, list = pcall(function() return MF.BoardNotices and MF:BoardNotices() or {} end)
        self.noticesCache, self.noticesAt = ok and type(list) == "table" and list or {}, now
    end
    return self.noticesCache
end

function J:RecapChanges()
    local now = GetTime()
    if not self.changesAt or now - self.changesAt >= 1 then
        local ok, ch = pcall(MF.RecapChanges, MF)
        self.changesCache, self.changesAt = ok and type(ch) == "table" and ch or nil, now
    end
    return self.changesCache
end

-- Shows or hides it; returns the room it takes
function J:Banner()
    if not f.banner then self:BuildBanner() end
    local b = f.banner
    if MF.recapActive then self.recapPending = false end
    if not self.recapPending or not self.recapLines then b:Hide() return 0 end
    -- Nothing changed after all (the first half-minute after login always asks): no banner
    if MF.RecapChanges and GetTime() >= (MF.recapReadyAt or 0) then
        local ch = self:RecapChanges()
        local signed = false
        for _, n in ipairs(self:Notices()) do
            if n.status == "open" and MF:IsSignedUp(n) then signed = true break end
        end
        if ch and #(ch.records or {}) + #(ch.kings or {}) + #(ch.ended or {}) == 0 and not signed then
            self.recapPending = false
            b:Hide()
            return 0
        end
        self.recapKings = ch and #(ch.kings or {}) or 0
    end
    -- Built at most once a second (live pages redraw every tick)
    local lines = self.recapCache
    if not lines or GetTime() - (self.recapAt or 0) > 1 then
        local ok, got = pcall(self.recapLines, MF)
        lines = ok and type(got) == "table" and got or nil
        self.recapCache, self.recapAt = lines, GetTime()
    end
    local hero = lines and lines.hero
    if not hero then b:Hide() return 0 end
    local bw = math.min(640, (f:GetWidth() or 800) - 40)
    b:ClearAllPoints()
    -- Above the window; under its tabs when the window is too near the top of the screen for it
    local scale = f:GetEffectiveScale() or 1
    local room = ((UIParent:GetTop() or 768) * (UIParent:GetEffectiveScale() or 1)) - ((f:GetTop() or 0) * scale)
    if room >= (b:GetHeight() + 10) * scale then
        b:SetPoint("BOTTOM", f, "TOP", 0, 6)
    else
        b:SetPoint("TOP", f, "BOTTOM", 0, -40)
    end
    b:SetWidth(bw)
    b.title:SetText(Reading(hero.title))
    local parts = {}
    for _, stat in ipairs(lines.summary or {}) do
        if stat.value and tostring(stat.value) ~= "0" then parts[#parts + 1] = Reading(stat.value) .. " " .. Reading(stat.shortLabel or stat.label):lower() end
    end
    if (self.recapKings or 0) > 0 then parts[#parts + 1] = self.recapKings .. (self.recapKings == 1 and " King changed" or " Kings changed") end
    local note = #parts > 0 and table.concat(parts, "   ") or Reading(hero.subtitle)
    if hero.status and hero.status ~= "" then note = note .. "   |cffa0a0a0" .. Reading(hero.status) .. "|r" end
    b.note:SetText(note)
    local w = bw - 62 - 200
    b.title:SetWidth(w)
    b.note:SetWidth(w)
    if not b:IsShown() then
        b:Show()
        if ns.db.animations ~= false then W:FadeIn(b, 0.25) end
    end
    return 0 -- (outside the window: the page keeps all its room)
end

function J:SetAction(b, label, fn)
    b.fn = fn
    b:SetText(label)
    b:SetWidth(math.max(90, (b:GetFontString() and b:GetFontString():GetStringWidth() or 60) + 28))
    b:Show()
end

-- ---------------------------------------------------------------------------
-- Redesigned pages. A page claims The Fishing Log's state when it can draw it better:
--   J:AddPage{ key, match = function(state) -> bool, build = function(frame, MF), refresh = function(frame, state),
--              actions = function(state) -> { {label, fn}, ... } | nil (nil = The Fishing Log's own),
--              subheading = function(state) -> text, count = function(frame, state) -> text }
-- state: { tab, view, recap, actions = The Fishing Log's actions for the page, lines, subs, MF }
-- ---------------------------------------------------------------------------
J.pages = {}
function J:AddPage(page) self.pages[#self.pages + 1] = page end

function J:State()
    return { tab = win.tab, view = MF.db.settings.journalView, recap = MF.recapActive and true or false,
        actions = built.actions or {}, lines = built.lines or {}, subs = built.subs, MF = MF }
end

-- Find one of The Fishing Log's own actions on this page by its label, and press it
function J:PressAction(...)
    local want = {}
    for _, label in ipairs({ ... }) do want[label] = true end
    for i, a in ipairs(built.actions or {}) do
        if want[a.label] then
            local b = win.actions[i]
            if b and b:IsShown() then b:Click() return true end
            if a.onClick then a.onClick() return true end
        end
    end
    return false
end

local function HideFallback()
    f.bigAction:Hide()
    f.strip:Hide()
    f.hero:Hide()
    f.summary:Hide()
    J.list:Hide()
    J.list.bar:Hide()
    f.empty:Hide()
    J.count:SetText("")
end

function J:ShowPage(page, state)
    HideFallback()
    for _, p in ipairs(self.pages) do
        if p ~= page and p.frame then p.frame:Hide() end
    end
    if not page.frame then
        page.frame = CreateFrame("Frame", nil, f.body)
        page.build(page.frame, MF)
    end
    page.frame:ClearAllPoints()
    page.frame:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(self.navH or 0))
    page.frame:SetPoint("BOTTOMRIGHT", f.footer, "TOPRIGHT", 0, 4)
    page.frame:Show()
    page.refresh(page.frame, state)
    self.count:SetText(page.count and page.count(page.frame, state) or "")
end

-- A bottom tab drawn as chosen without disabling it, so clicking the tab you're on still works
-- (back from a sub-view, out of the recap). Same pieces PanelTemplates_SelectTab shows and hides.
local function PaintTab(b, on)
    if type(b.LeftActive) == "table" and type(b.Left) == "table" then
        b.Left:SetShown(not on) b.Middle:SetShown(not on) b.Right:SetShown(not on)
        b.LeftActive:SetShown(on) b.MiddleActive:SetShown(on) b.RightActive:SetShown(on)
        local text = b.Text or b:GetFontString()
        if text then
            text:ClearAllPoints()
            text:SetPoint("CENTER", b, "CENTER", 0, on and (b.selectedTextY or -3) or (b.deselectedTextY or 2))
        end
        b:SetNormalFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall")
    elseif b.LockHighlight then
        if on then b:LockHighlight() else b:UnlockHighlight() end
    end
end

function J:Header()
    local key = ShownTab()
    if MF.recapActive then
        f.heading:SetText("Your Recap")
        f.subheading:SetText("since you were last here")
    else
        f.heading:SetText(TabLabel(key))
    end
    for _, b in ipairs(f.tabs) do PaintTab(b, b.key == key) end
    local xp = MF.cdb and MF.cdb.profile and MF.cdb.profile.xp or 0
    local idx, name, nextXP = MF:RankFor(xp)
    f.rank:SetText(name or "")
    local ladder = MF.Ladder and MF:Ladder()
    local floor = ladder and ladder[idx] and ladder[idx].xp or 0
    if nextXP then
        f.xp:Set(xp - floor, nextXP - floor, ("%d / %d XP"):format(xp, nextXP))
    else
        f.xp:Set(1, 1, ("%d XP"):format(xp))
    end
end

-- The Fishing Log just drew a page: draw ours
function J:Render()
    if not f or not f:IsShown() or not built.lines then return end
    local context = CurrentContext()
    local list = self.list
    local state = self:State()
    local page
    for _, p in ipairs(self.pages) do
        local ok, yes = pcall(p.match, state)
        if ok and yes then page = p break end
    end
    local changed = context ~= self.context or page ~= self.page
    self.navH = ns.Nav and ns.Nav:Apply(state, MF) or 0
    self.navH = self.navH + self:Banner()
    -- The Fishing Log redraws some pages every second (an open event ticks its clock, and it keeps
    -- ticking on other tabs too). A page whose content hasn't changed isn't rebuilt, unless it is live.
    local sig
    if page and not page.live then
        local parts = {}
        for _, line in ipairs(state.lines) do
            parts[#parts + 1] = line.text or ""
            parts[#parts + 1] = line.right or ""
            if line.columns then parts[#parts + 1] = table.concat(line.columns, "\1") end
        end
        for _, a in ipairs(state.actions) do parts[#parts + 1] = a.label end
        parts[#parts + 1] = tostring(state.subs and state.subs.current)
        sig = table.concat(parts, "\2")
        if not changed and sig == self.lastSig then return end
    end
    self.lastSig = sig
    if page then
        local ok, err = pcall(self.ShowPage, self, page, state)
        if not ok then
            -- Never a blank window: show The Fishing Log's own page instead
            geterrorhandler()(err)
            if page.frame then page.frame:Hide() end
            page = nil
        end
    end
    if page then
        if self.context and not self.page then self.scrolls = self.scrolls or {} self.scrolls[self.context] = list.target end
        self.context, self.page = context, page
        self:Header()
        if page.subheading then f.subheading:SetText(page.subheading(state) or "") end
        if changed and ns.db.animations ~= false and self.shownOnce then
            W:FadeIn(page.frame, 0.18)
            W:Sound("page")
        end
        self.shownOnce = true
        return
    end
    if self.page then
        if self.page.frame then self.page.frame:Hide() end
        self.page = nil
    end
    list:Show()
    self.scrolls = self.scrolls or {}
    if changed then
        if self.context and context ~= self.context then self.scrolls[self.context] = list.target end
        self.context = context
        list.scroll = self.scrolls[context] or 0
        list.target = list.scroll
    end
    self:Arrange()
    self:Layout()
    self:Place()
    if changed and ns.db.animations ~= false and self.shownOnce then
        list:SetAlpha(0)
        W:Tween(list, 0.18, function(e) list:SetAlpha(e) end)
        W:Sound("page")
    end
    self.shownOnce = true
end

function J:Open()
    self:Build()
    self.lastSig = nil
    self:SyncHost()
    if not f:IsShown() then
        self.shownOnce = false
        -- A page may start afresh each time the journal opens (Records opens on Here)
        for _, p in ipairs(self.pages or {}) do
            if p.onOpen then pcall(p.onOpen) end
        end
        f:Show()
    end
end

function J:Close()
    if f and f:IsShown() then
        self.closing = true
        f:Hide()
        self.closing = false
    end
end

-- ---------------------------------------------------------------------------
-- Taking over
-- ---------------------------------------------------------------------------
ns:OnSetup("journal", function(tfl)
    MF = tfl
    win = MF.journalWindow or _G.TheFishingLogJournal
    if not (win and MF.JOURNAL_TABS and win.searchBar and win.subs and win.actions and win.scrollHint) then
        ns.Print("This version of The Fishing Log's journal isn't one I know; keeping its own window.")
        return
    end

    -- Each page as The Fishing Log built it, every time it draws one (a click, a refresh, a scroll)
    MF:On("TFL_JOURNAL_DRAWN", function(self)
        local page = self.journalPage
        if page then built.lines, built.actions, built.subs = page.lines, page.actions, page.subs end
        J:Render()
    end)

    -- The recap that would open in place of the journal becomes a banner on the page you land on
    -- (from Godfall's 0.7.4): one line above the window, with "See what changed" for the full page
    if MF.RecapLines then J.recapLines = MF.RecapLines end
    if MF.ShouldOpenRecap then
        local should = MF.ShouldOpenRecap
        MF.ShouldOpenRecap = function(self, ...)
            if should(self, ...) then J.recapPending = true end
            return false
        end
    end

    -- Its window lives on, out of sight
    local wasShown = win:IsShown()
    local savedW, savedH = MF.db.settings.journalWidth, MF.db.settings.journalHeight
    win:SetParent(host)
    win:SetClampedToScreen(false)
    hooksecurefunc(win, "Show", function() J:Open() end)
    hooksecurefunc(win, "Hide", function()
        -- It saves its size as it hides. If that's the size we gave it, put the player's back;
        -- if it's anything else (/tfl journalsize), that is the player's now.
        local st = MF.db.settings
        local forcedW, forcedH = math.floor((win:GetWidth() or 0) + 0.5), math.floor((win:GetHeight() or 0) + 0.5)
        if st.journalWidth and math.abs(st.journalWidth - forcedW) < 2 and st.journalHeight and math.abs(st.journalHeight - forcedH) < 2 then
            st.journalWidth, st.journalHeight = savedW, savedH
        else
            savedW, savedH = st.journalWidth, st.journalHeight
        end
        J:Close()
    end)
    hooksecurefunc(win, "SetShown", function(_, on) if on then J:Open() else J:Close() end end)

    J:Build()
    if wasShown then J:Open() MF:RedrawJournal() end
end)
