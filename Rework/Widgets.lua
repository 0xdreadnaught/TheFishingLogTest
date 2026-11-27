-- UI building blocks in the game's own style (as Curator and Total RP 3 use it): the portrait window,
-- the dark collections ground, navy panels with a gold rim, pet-journal rows, gold headings.
-- (Shared with Guild Hall.)
local _, TFL = ...
local ns = TFL.Rework
local W = {}
ns.W = W

-- ---------------------------------------------------------------------------
-- Sounds: the game's own interface clicks
-- ---------------------------------------------------------------------------
local SOUNDS = {
    open = "IG_SPELLBOOK_OPEN", close = "IG_SPELLBOOK_CLOSE", tab = "IG_CHARACTER_INFO_TAB",
    click = "IG_MAINMENU_OPTION_CHECKBOX_ON", page = "IG_ABILITY_PAGE_TURN", row = "U_CHAT_SCROLL_BUTTON",
}
local FALLBACK = { open = 829, close = 830, tab = 841, click = 856, page = 836, row = 1115 }
function W:Sound(kind)
    if ns.db and ns.db.sounds == false then return end
    -- The Fishing Log's own "Play sounds" silences these too
    if TFL.db and TFL.db.settings and TFL.db.settings.sounds == false then return end
    local id = SOUNDKIT and SOUNDKIT[SOUNDS[kind] or ""] or FALLBACK[kind]
    if id and PlaySound then pcall(PlaySound, id) end
end

-- ---------------------------------------------------------------------------
-- Tweens: one OnUpdate drives them all; a key replaces an older tween on the same thing
-- ---------------------------------------------------------------------------
local tweens, byKey = {}, {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    local now = GetTime()
    local i = 1
    while i <= #tweens do
        local tw = tweens[i]
        local t = math.min(1, (now - tw.start) / tw.dur)
        local e = 1 - (1 - t) * (1 - t) * (1 - t) -- ease out
        local ok, err = pcall(tw.fn, e)
        if not ok then t = 1 geterrorhandler()(err) end
        if t >= 1 then
            table.remove(tweens, i)
            if byKey[tw.key] == tw then byKey[tw.key] = nil end
        else
            i = i + 1
        end
    end
    if #tweens == 0 then driver:Hide() end
end)

function W:Tween(key, dur, fn)
    if not (ns.db and ns.db.animations ~= false) then fn(1) return end
    local old = byKey[key]
    if old then for i = #tweens, 1, -1 do if tweens[i] == old then table.remove(tweens, i) end end end
    local tw = { key = key, start = GetTime(), dur = math.max(dur, 0.01), fn = fn }
    byKey[key] = tw
    tweens[#tweens + 1] = tw
    driver:Show()
end

-- Drop whatever tween is running on this key, so it can't finish later and
-- undo a value set since.
function W:StopTween(key)
    local old = byKey[key]
    if not old then return end
    for i = #tweens, 1, -1 do if tweens[i] == old then table.remove(tweens, i) end end
    byKey[key] = nil
end

-- A page or panel coming into view: fades up and settles a few pixels
function W:FadeIn(frame, dur)
    frame:SetAlpha(0)
    self:Tween(frame, dur or 0.18, function(e) frame:SetAlpha(e) end)
end

-- A soft gold glow behind a frame on mouse-over
function W:Glow(frame, inset)
    inset = inset or 4
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetPoint("TOPLEFT", -inset, inset)
    glow:SetPoint("BOTTOMRIGHT", inset, -inset)
    glow:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0.45)
    glow:SetAlpha(0)
    frame:HookScript("OnEnter", function() W:Tween(glow, 0.15, function(e) glow:SetAlpha(0.35 * e) end) end)
    frame:HookScript("OnLeave", function()
        local a = glow:GetAlpha()
        W:Tween(glow, 0.2, function(e) glow:SetAlpha(a * (1 - e)) end)
    end)
    return glow
end

-- ---------------------------------------------------------------------------
-- Templates and atlases, each checked so a client without one falls back to older art
-- ---------------------------------------------------------------------------
local hasTemplate, hasAtlas = {}, {}
function W:HasTemplate(t)
    if hasTemplate[t] == nil then
        local ok, info = pcall(function() return C_XMLUtil and C_XMLUtil.GetTemplateInfo(t) end)
        hasTemplate[t] = (ok and info ~= nil) and true or false
    end
    return hasTemplate[t]
end
function W:HasAtlas(a)
    if hasAtlas[a] == nil then
        local ok, info = pcall(function() return C_Texture and C_Texture.GetAtlasInfo(a) end)
        hasAtlas[a] = (ok and info ~= nil) and true or false
    end
    return hasAtlas[a]
end
function W:Atlas(tex, atlas, useSize)
    if self:HasAtlas(atlas) then tex:SetAtlas(atlas, useSize and true or false) return true end
    return false
end
function W:Make(kind, name, parent, template)
    if self:HasTemplate(template) then
        local ok, f = pcall(CreateFrame, kind, name, parent, template)
        if ok then return f end
    end
end

W.GOLD, W.WHITE, W.SOFT, W.DIM = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.8, 0.8, 0.8 }, { 0.6, 0.6, 0.6 }

-- ---------------------------------------------------------------------------
-- The window: the game's portrait frame (metal rim, round portrait, title bar, close button)
-- ---------------------------------------------------------------------------
function W:Window(name, title, w, h, icon)
    local f = self:Make("Frame", name, UIParent, "PortraitFrameTemplate")
    local portrait = f ~= nil
    if not f then
        f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        f:SetBackdrop(BACKDROP_DARK_DIALOG_32_32 or BACKDROP_DIALOG_32_32)
    end
    f:SetSize(w, h)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", 56, 0)
    drag:SetPoint("TOPRIGHT", -28, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if f.canMove and not f.canMove() then return end
        if f.onDragStart then f.onDragStart(f) end
        f:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if f.onMoved then f.onMoved(f) end
    end)
    f.drag = drag
    if portrait then
        f:SetTitle(title)
        f:SetPortraitToAsset(icon or ns.ICON)
        f.close = f.CloseButton
    else
        local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOP", 0, -16)
        text:SetText(title)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        f.close = close
    end
    f.heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.heading:SetPoint("TOPLEFT", 64, -32)
    f.heading:SetShadowOffset(1, -1)
    f.subheading = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.subheading:SetPoint("LEFT", f.heading, "RIGHT", 10, -1)
    f.subheading:SetTextColor(0.8, 0.8, 0.8)
    tinsert(UISpecialFrames, name)
    f:Hide()
    return f
end

-- The dark stone ground of the collections journal
function W:Ground(parent)
    local g = self:Make("Frame", nil, parent, "CollectionsBackgroundTemplate")
    if g then g:SetFrameLevel(parent:GetFrameLevel()) return g end
    g = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    g:SetBackdrop({ bgFile = "Interface\\Collections\\CollectionsBackgroundTile", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 256, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    g:SetBackdropBorderColor(0.48, 0.39, 0.32)
    g:SetFrameLevel(parent:GetFrameLevel())
    return g
end

-- The stone's two top filigree corners sit under whatever a window puts
-- along its top (tabs, buttons) and make it hard to read; the bottom two
-- stay. Only small top-anchored art in the upper layers is touched: the
-- stone, its edges and its shadows are left alone.
function W:HideTopCorners(g)
    for _, r in ipairs({ g:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and r:GetNumPoints() > 0 then
            local point = r:GetPoint(1)
            local layer = r:GetDrawLayer()
            local w, h = r:GetSize()
            if (point == "TOPLEFT" or point == "TOPRIGHT") and (layer == "OVERLAY" or layer == "ARTWORK")
                and (w or 0) > 0 and (w or 0) < 160 and (h or 0) < 160 then
                r:Hide()
            end
        end
    end
end

-- A navy panel with a thin gold rim, a little lighter at the top
function W:Panel(parent, alpha)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0.06, 0.08, 0.15, alpha or 0.94)
    p:SetBackdropBorderColor(0.9, 0.72, 0.3)
    local sheen = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetPoint("TOPLEFT", 3, -3)
    sheen:SetPoint("TOPRIGHT", -3, -3)
    sheen:SetHeight(40)
    sheen:SetColorTexture(0.25, 0.3, 0.5, 1)
    if CreateColor then
        sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.22))
    else
        sheen:SetAlpha(0.12)
    end
    return p
end

function W:Divider(parent, width)
    local d = parent:CreateTexture(nil, "ARTWORK")
    if not self:Atlas(d, "Options_HorizontalDivider") then d:SetColorTexture(1, 0.82, 0, 0.35) end
    d:SetSize(width or 300, 1)
    return d
end

-- A gold heading with a rule under it
function W:Header(parent, text, width)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetText(text)
    h:SetShadowOffset(1, -1)
    local rule = self:Divider(parent, width or 300)
    rule:SetPoint("TOPLEFT", h, "BOTTOMLEFT", -4, -4)
    h.rule = rule
    return h
end

function W:Label(parent, font, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    if text then fs:SetText(text) end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs:SetShadowOffset(1, -1)
    return fs
end

-- A list row like the pet journal's: background, selected glow, hover highlight
function W:Row(row)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    if not self:Atlas(row.bg, "PetList-ButtonBackground") then row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.85) end
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetAllPoints()
    if not self:Atlas(row.sel, "PetList-ButtonSelect") then row.sel:SetColorTexture(1, 0.82, 0, 0.18) end
    row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if not self:Atlas(hl, "PetList-ButtonHighlight") then hl:SetColorTexture(1, 1, 1, 0.08) end
    return row
end

-- A plain striped table row: faint alternate shading, gold hover
function W:TableRow(row)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.035)
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.16)
    row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.45)
    return row
end

-- An icon in the achievement frame's ring
function W:FramedIcon(parent, size, icon)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local bk = f:CreateTexture(nil, "BACKGROUND")
    bk:SetPoint("TOPLEFT", 2, -2)
    bk:SetPoint("BOTTOMRIGHT", -2, 2)
    bk:SetColorTexture(0, 0, 0, 1)
    local ic = f:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 3, -3)
    ic:SetPoint("BOTTOMRIGHT", -3, 3)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if icon then ic:SetTexture(icon) end
    local rim = f:CreateTexture(nil, "OVERLAY")
    rim:SetPoint("CENTER", -1, 2)
    rim:SetSize(size * 1.38, size * 1.38)
    if not self:Atlas(rim, "ui-achievement-iconframe") then
        rim:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
        rim:SetTexCoord(0, 0.5625, 0, 0.5625)
    end
    f.icon, f.rim = ic, rim
    return f
end

-- A small square icon with a thin dark edge (badges, profession icons in rows)
function W:Icon(parent, size, icon)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if icon then t:SetTexture(icon) end
    return t
end

-- Icon with a round mask in a gold ring
function W:RoundIcon(parent, size, icon)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER")
    tex:SetSize(size * 0.76, size * 0.76)
    if icon then tex:SetTexture(icon) end
    local mask = f:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("CENTER")
    if self:Atlas(ring, "communities-ring-gold") then
        ring:SetSize(size, size)
    else
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetTexCoord(0, 0.6, 0, 0.6)
        ring:SetPoint("CENTER", size * 0.08, -size * 0.08)
        ring:SetSize(size * 1.18, size * 1.18)
    end
    f.icon, f.ring = tex, ring
    return f
end

-- A skill bar: the game's status bar texture in a thin rim, with text on it
function W:Bar(parent, w, h, r, g, b)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h or 12)
    f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f:SetBackdropBorderColor(0.55, 0.5, 0.4)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0, 0, 0, 0.6)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r or 0.0, g or 0.55, b or 0.15)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", 0, 0)
    text:SetShadowOffset(1, -1)
    f.bar, f.text = bar, text
    function f:Set(value, max, label)
        max = (max and max > 0) and max or 1
        bar:SetMinMaxValues(0, max)
        bar:SetValue(math.min(value or 0, max))
        text:SetText(label or ("%d / %d"):format(value or 0, max))
    end
    function f:SetColor(rr, gg, bb) bar:SetStatusBarColor(rr, gg, bb) end
    return f
end

function W:Button(parent, text, w, h, onClick, tip, body)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, h or 22)
    b:SetText(text)
    b:SetScript("OnClick", function(self, ...)
        W:Sound("click")
        if onClick then onClick(self, ...) end
    end)
    if tip then self:Tip(b, tip, body) end
    return b
end

-- A square icon button (row actions, the addons strip on profiles)
function W:IconButton(parent, size, icon, onClick, tip, body)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetTexture(icon)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    border:SetAlpha(0)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetScript("OnClick", function(self, ...)
        W:Sound("click")
        if onClick then onClick(self, ...) end
    end)
    if tip then self:Tip(b, tip, body) end
    return b
end

function W:Tip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        local t = title
        if type(t) == "function" then t = t(self) end
        if type(t) ~= "string" or t == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(t, 1, 0.82, 0)
        local b = body
        if type(b) == "function" then b = b(self) end
        if type(b) == "string" and b ~= "" then GameTooltip:AddLine(b, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(self) W:HideTip(self) end)
end

function W:HideTip(owner)
    if GameTooltip.IsOwned and not GameTooltip:IsOwned(owner) then return end
    GameTooltip:Hide()
end

function W:Check(parent, label, get, set, tip)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    local fs = c.text or c.Text
    if type(fs) ~= "table" then fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
    c.text = fs
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", c, "RIGHT", 1, 1)
    fs:SetFontObject("GameFontHighlightSmall")
    fs:SetText(label)
    c:SetChecked(get())
    c:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    c:SetScript("OnClick", function(self)
        W:Sound("click")
        set(self:GetChecked() and true or false)
    end)
    if tip then self:Tip(c, label, tip) end
    return c
end

-- A search box (the game's, with the magnifier and clear button)
function W:Search(parent, w, onChange, instructions)
    local e = self:Make("EditBox", nil, parent, "SearchBoxTemplate")
    if not e then
        e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    end
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    if type(e.Instructions) == "table" and instructions then e.Instructions:SetText(instructions) end
    e:HookScript("OnTextChanged", function(self) onChange(self:GetText() or "") end)
    return e
end

-- A dropdown button that opens a menu of choices: choices() -> { {value, label}, ... }
function W:Choice(parent, w, get, set, choices, prefix)
    local b = self:Make("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if b and b.SetupMenu then
        b:SetWidth(w)
        b:SetupMenu(function(_, root)
            for _, c in ipairs(choices()) do
                root:CreateRadio(c[2], function() return get() == c[1] end, function() set(c[1]) end)
            end
        end)
        if b.SetDefaultText then b:SetDefaultText(prefix or "") end
        return b
    end
    -- Without the modern dropdown: a button that cycles
    local btn = self:Button(parent, "", w, 22)
    local function Label()
        for _, c in ipairs(choices()) do if c[1] == get() then return (prefix and (prefix .. ": ") or "") .. c[2] end end
        return prefix or ""
    end
    btn:SetText(Label())
    btn:SetScript("OnClick", function()
        local list = choices()
        for i, c in ipairs(list) do
            if c[1] == get() then set(list[i % #list + 1][1]) break end
        end
        btn:SetText(Label())
    end)
    function btn:GenerateMenu() btn:SetText(Label()) end
    return btn
end

-- ---------------------------------------------------------------------------
-- A scrolling list of rows, built once (only the rows on screen exist)
--   list = W:List(parent, rowHeight, build(row), fill(row, item, index))
--   list:SetItems(items)  list:Refresh()
-- ---------------------------------------------------------------------------
function W:List(parent, rowHeight, build, fill)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.items, list.offset = {}, {}, 0
    list:EnableMouseWheel(true)

    local bar = CreateFrame("Slider", nil, list)
    bar:SetWidth(10)
    bar:SetPoint("TOPRIGHT", 0, -2)
    bar:SetPoint("BOTTOMRIGHT", 0, 2)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.45)
    bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetSize(16, 24) end
    list.bar = bar

    local function Visible()
        return math.max(1, math.floor((list:GetHeight() or rowHeight) / rowHeight))
    end

    function list:Refresh()
        local n = Visible()
        for i = #self.rows + 1, n do
            local row = CreateFrame("Button", nil, self)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("RIGHT", bar, "LEFT", -3, 0)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, d) self:Scroll(-d) end)
            build(row, i)
            self.rows[i] = row
        end
        local maxOff = math.max(0, #self.items - n)
        if self.offset > maxOff then self.offset = maxOff end
        bar:SetMinMaxValues(0, maxOff)
        bar:SetShown(maxOff > 0)
        self.updating = true
        bar:SetValue(self.offset)
        self.updating = false
        for i, row in ipairs(self.rows) do
            local item = i <= n and self.items[self.offset + i]
            if item then
                row.item = item
                fill(row, item, self.offset + i)
                row:Show()
            else
                row.item = nil
                row:Hide()
            end
        end
        if self.empty then self.empty:SetShown(#self.items == 0) end
    end

    -- Compact or roomy rows: move the rows already made, make more if they now fit
    function list:SetRowHeight(h)
        if h == rowHeight then return end
        rowHeight = h
        for i, row in ipairs(self.rows) do
            row:SetHeight(h)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * h)
        end
        self:Refresh()
    end

    function list:SetItems(items, keep)
        self.items = items or {}
        if not keep then self.offset = 0 end
        self:Refresh()
    end

    function list:Scroll(d)
        local maxOff = math.max(0, #self.items - Visible())
        self.offset = math.max(0, math.min(maxOff, self.offset + d * 3))
        self:Refresh()
    end

    bar:SetScript("OnValueChanged", function(_, v)
        if list.updating then return end
        list.offset = math.floor(v + 0.5)
        list:Refresh()
    end)
    list:SetScript("OnMouseWheel", function(_, d) list:Scroll(-d) end)
    list:SetScript("OnSizeChanged", function() list:Refresh() end)

    -- "Nothing here" text
    list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    list.empty:SetPoint("TOP", 0, -40)
    list.empty:SetWidth(320)
    list.empty:Hide()
    return list
end

-- ---------------------------------------------------------------------------
-- A scrolling list of mixed rows (headers, cards...) of different heights, eased scrolling.
--   v = W:VList(parent, make(kind) -> frame, fill(frame, item))
--   v:SetItems({ { kind = "card", h = 60, ... }, ... }, keepScroll)
-- Only the rows in view exist; frames are pooled per kind.
-- ---------------------------------------------------------------------------
function W:VList(parent, make, fill)
    local v = CreateFrame("Frame", nil, parent)
    if v.SetClipsChildren then v:SetClipsChildren(true) end
    v.items, v.pools = {}, {}
    v.scroll, v.target, v.total = 0, 0, 0
    v:EnableMouseWheel(true)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetWidth(10)
    bar:SetPoint("TOPLEFT", v, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", v, "BOTTOMRIGHT", 4, 0)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.45)
    bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetSize(16, 24) end
    v.bar = bar

    -- Rows keep their frame while they stay in view (no hide/show, so no tooltip flicker),
    -- and are only refilled when the items changed or the list was resized
    v.bound = {}
    function v:Place()
        local viewH = self:GetHeight() or 0
        local maxS = math.max(0, self.total - viewH)
        self.scroll = math.max(0, math.min(maxS, self.scroll))
        self.target = math.max(0, math.min(maxS, self.target))
        self.updating = true
        bar:SetMinMaxValues(0, maxS)
        bar:SetValue(self.scroll)
        bar:SetShown(maxS > 0 and self:IsShown())
        self.updating = false
        local top, bottom = self.scroll, self.scroll + viewH
        local w = self:GetWidth() or 100
        local dirty = self.dirty
        local keep = {}
        -- First item in view (items are laid out top to bottom)
        local items = self.items
        local lo, hi = 1, #items
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            local it = items[mid]
            if it.y + it.h <= top then lo = mid + 1 else hi = mid end
        end
        local wanted = {}
        for i = lo, #items do
            local it = items[i]
            if it.y >= bottom then break end
            wanted[#wanted + 1] = it
            if self.bound[it] then keep[self.bound[it]] = it end
        end
        -- Free the frames whose item left the view
        local free = {}
        for fr, it in pairs(self.frames or {}) do
            if not keep[fr] then
                self.bound[it] = nil
                local pool = free[fr.kind]
                if not pool then pool = {} free[fr.kind] = pool end
                pool[#pool + 1] = fr
            end
        end
        local frames = {}
        for _, it in ipairs(wanted) do
            local fr = self.bound[it]
            local fresh = false
            if not fr then
                local pool = free[it.kind]
                fr = pool and table.remove(pool)
                if not fr then
                    local spare = self.pools[it.kind]
                    fr = spare and table.remove(spare)
                end
                if not fr then
                    fr = make(it.kind, self)
                    fr:SetParent(self)
                    fr:EnableMouseWheel(true)
                    fr:SetScript("OnMouseWheel", function(_, d) self:Wheel(d) end)
                end
                fr.kind = it.kind
                self.bound[it] = fr
                fresh = true
            end
            frames[fr] = it
            fr:ClearAllPoints()
            fr:SetPoint("TOPLEFT", 0, -(it.y - self.scroll))
            if fresh or dirty then
                fr:SetSize(w, it.h)
                fr.item = it
                fill(fr, it)
            end
            if not fr:IsShown() then fr:Show() end
        end
        for kind, pool in pairs(free) do
            local spare = self.pools[kind]
            if not spare then spare = {} self.pools[kind] = spare end
            for _, fr in ipairs(pool) do fr:Hide() fr.item = nil spare[#spare + 1] = fr end
        end
        self.frames = frames
        self.dirty = false
    end

    function v:SetItems(items, keep)
        local y = 0
        for _, it in ipairs(items) do it.h = it.h or 20 it.y = y y = y + it.h + (it.gap or 0) end
        self.items, self.total = items, y + 4
        -- New items: every frame lets go of its old one
        wipe(self.bound)
        self.dirty = true
        if not keep then self.scroll, self.target = 0, 0 end
        self:Place()
    end

    function v:Wheel(d)
        local maxS = math.max(0, self.total - (self:GetHeight() or 0))
        self.target = math.max(0, math.min(maxS, self.target - d * 66))
    end

    bar:SetScript("OnValueChanged", function(_, val)
        if v.updating then return end
        v.scroll, v.target = val, val
        v:Place()
    end)
    v:SetScript("OnMouseWheel", function(self, d) self:Wheel(d) end)
    v:SetScript("OnSizeChanged", function(self) self.dirty = true self:Place() end)
    v:SetScript("OnHide", function() bar:Hide() end)
    v:SetScript("OnShow", function(self) self:Place() end)
    v:SetScript("OnUpdate", function(self, elapsed)
        if math.abs(self.target - self.scroll) < 0.5 then
            if self.scroll ~= self.target then self.scroll = self.target self:Place() end
            return
        end
        local k = (ns.db and ns.db.animations ~= false) and math.min(1, elapsed * 16) or 1
        self.scroll = self.scroll + (self.target - self.scroll) * k
        self:Place()
    end)
    return v
end

-- ---------------------------------------------------------------------------
-- A card: a dark plate with a thin bronze edge that turns gold under the mouse
-- ---------------------------------------------------------------------------
W.MEDAL = { { 1, 0.82, 0 }, { 0.82, 0.82, 0.88 }, { 0.80, 0.50, 0.20 } }
W.MEDAL_TEXT = { "1st", "2nd", "3rd" }
function W:Card(parent, clickable)
    local c = CreateFrame(clickable and "Button" or "Frame", nil, parent or UIParent, "BackdropTemplate")
    c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    c:SetBackdropColor(0.03, 0.04, 0.08, 0.72)
    c.edge = { 0.5, 0.42, 0.25, 0.9 }
    c:SetBackdropBorderColor(unpack(c.edge))
    function c:SetEdge(r, g, b, a)
        self.edge = { r, g, b, a or 1 }
        if not self.hovered then self:SetBackdropBorderColor(r, g, b, a or 1) end
    end
    if clickable then
        c:HookScript("OnEnter", function(self) self.hovered = true self:SetBackdropBorderColor(1, 0.82, 0.3, 1) end)
        c:HookScript("OnLeave", function(self) self.hovered = nil self:SetBackdropBorderColor(unpack(self.edge)) end)
    end
    return c
end

-- "1st" in gold, "2nd" in silver, "3rd" in bronze, "#4" plain
function W:Place(fs, place)
    local m = self.MEDAL[place or 0]
    fs:SetText(self.MEDAL_TEXT[place or 0] or (place and ("#" .. place) or ""))
    if m then fs:SetTextColor(m[1], m[2], m[3]) else fs:SetTextColor(0.8, 0.8, 0.8) end
end
