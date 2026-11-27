-- Panels and buttons: everything The Fishing Log builds through MF:CreatePanel / MF:CreateButton after
-- we load (the fish card, card sharing, welcome, news, the wardrobe, the event form, export boxes...)
-- comes out in the game's own frame art instead of flat grey boxes.
--
-- Its buttons repaint themselves on every hover and press by calling SetBackdropColor. We take their
-- backdrop away (those calls then quietly do nothing, as the game's Backdrop code allows) and use the
-- same calls as our cue to show the matching state of the game's red panel-button art. A disabled
-- button is how The Fishing Log marks "the one you're on", so that is drawn pressed with gold text.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local P = {}
ns.Panels = P

local FILE = {
    up = "Interface\\Buttons\\UI-Panel-Button-Up",
    down = "Interface\\Buttons\\UI-Panel-Button-Down",
    hl = "Interface\\Buttons\\UI-Panel-Button-Highlight",
}
-- The art's three slices: left cap, stretchable middle, right cap
local SLICES = {
    { 0, 0.09375, 12 },
    { 0.09375, 0.53125, nil },
    { 0.53125, 0.625, 12 },
}

local function Slices(b, layer, sub)
    local t = {}
    for i, s in ipairs(SLICES) do
        local tex = b:CreateTexture(nil, layer, nil, sub)
        tex:SetTexCoord(s[1], s[2], 0, 0.6875)
        if s[3] then tex:SetWidth(s[3]) end
        t[i] = tex
    end
    t[1]:SetPoint("TOPLEFT")
    t[1]:SetPoint("BOTTOMLEFT")
    t[3]:SetPoint("TOPRIGHT")
    t[3]:SetPoint("BOTTOMRIGHT")
    t[2]:SetPoint("TOPLEFT", t[1], "TOPRIGHT")
    t[2]:SetPoint("BOTTOMRIGHT", t[3], "BOTTOMLEFT")
    return t
end

local function SetFile(slices, file)
    for _, tex in ipairs(slices) do tex:SetTexture(file) end
end

local function Repaint(b)
    local skin = b.lodgeSkin
    if not skin then return end
    local enabled = b:IsEnabled()
    local down = (not enabled) or b.pushed
    local file = down and FILE.down or FILE.up
    if skin.file ~= file then
        SetFile(skin.base, file)
        skin.file = file
    end
    local fs = b:GetFontString()
    if fs then
        if not enabled then
            fs:SetTextColor(1, 0.82, 0)
        elseif b.hovered then
            fs:SetTextColor(1, 1, 1)
        else
            fs:SetTextColor(1, 0.82, 0)
        end
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", down and 1 or 0, down and -1 or 0)
    end
end

function P:SkinButton(b)
    if b.lodgeSkin or not b.ClearBackdrop then return end
    b:ClearBackdrop()
    local skin = { base = Slices(b, "BACKGROUND", 0), hl = Slices(b, "HIGHLIGHT", 0) }
    SetFile(skin.hl, FILE.hl)
    for _, tex in ipairs(skin.hl) do tex:SetBlendMode("ADD") end
    b.lodgeSkin = skin
    if b:GetHeight() < 22 then b:SetHeight(22) end
    hooksecurefunc(b, "SetBackdropColor", Repaint)
    b:HookScript("OnClick", function() W:Sound("click") end)
    Repaint(b)
end

-- ---------------------------------------------------------------------------
-- Panels
-- ---------------------------------------------------------------------------
-- Heavy windows: the dark dialog with a gold rim and the collections stone inside.
-- Thin ones (the card, the cast strip): a tooltip-weight edge in gold.
-- The stone comes from the game's own collections template, as a frame of
-- its own (see LayGround below): on this client the tile isn't a plain file,
-- and asking for it by path drew the whole window white.
local HEAVY = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}
local THIN = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local THIN_FILL = { 0.04, 0.05, 0.09 }
local HEAVY_FILL = { 0.10, 0.09, 0.08 }

-- The journal's own ground under a heavy window: the game's collections
-- stone with its bottom corner ornaments, kept one level under the window
-- so everything the window draws stays on top of it. The window's own fill
-- goes (it would hide the stone) and its gold rim stays. Without the
-- template, the dark fill above is what you get.
local HEAVY_RIM = {
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

local function LayGround(f)
    if f.lodgeGround or not W:HasTemplate("CollectionsBackgroundTemplate") then return false end
    local g = W:Ground(f)
    g:SetPoint("TOPLEFT", 6, -6)
    g:SetPoint("BOTTOMRIGHT", -6, 6)
    W:HideTopCorners(g) -- they'd sit under the title and the close button
    local function Under() g:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1)) end
    Under()
    -- Opening brings a window to the front, which moves its level
    f:HookScript("OnShow", function() Under() C_Timer.After(0, Under) end)
    f.lodgeGround = g
    return true
end
local GOLD_EDGE = { 0.95, 0.78, 0.35 }

local function Recolor(f)
    if f.lodgeRecolor then return end
    f.lodgeRecolor = true
    local s = f.lodgeStyle
    -- Keep the caller's opacity (the board-style panels are see-through on purpose)
    local a = f.lodgeAlpha or 1
    if s == "heavy" then
        f:SetBackdropColor(HEAVY_FILL[1], HEAVY_FILL[2], HEAVY_FILL[3], a)
    else
        f:SetBackdropColor(THIN_FILL[1], THIN_FILL[2], THIN_FILL[3], math.max(0.85, a))
    end
    f.lodgeRecolor = nil
end

local function RecolorEdge(f, r, g, b)
    if f.lodgeRecolor then return end
    -- White is The Fishing Log's "no colour"; anything else (an edition colour, a frenzy) is meant
    if r and r > 0.99 and g > 0.99 and b > 0.99 then
        f.lodgeRecolor = true
        f:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], 1)
        f.lodgeRecolor = nil
    end
end

function P:SkinPanel(f, opts)
    if f.lodgeStyle or not f.SetBackdrop then return end
    local heavy = not (opts and opts.backdrop == "tooltip")
    f.lodgeStyle = heavy and "heavy" or "thin"
    local fill = opts and opts.fill
    f.lodgeAlpha = fill and fill[4] or 1
    f:SetBackdrop(heavy and HEAVY or THIN)
    if heavy and LayGround(f) then f:SetBackdrop(HEAVY_RIM) end
    hooksecurefunc(f, "SetBackdropColor", function(self, _, _, _, a)
        if self.lodgeRecolor then return end
        if a then self.lodgeAlpha = a end
        Recolor(self)
    end)
    hooksecurefunc(f, "SetBackdropBorderColor", RecolorEdge)
    Recolor(f)
    f:SetBackdropBorderColor(1, 1, 1, 1)
    if f.title and f.title.SetShadowOffset then f.title:SetShadowOffset(1, -1) end
    if heavy and f.close then
        f.close:ClearAllPoints()
        f.close:SetPoint("TOPRIGHT", -6, -6)
    end
    -- Opening a window: the game's sound and a short fade
    -- Only real opens and closes (not the interface hiding and coming back with Alt-Z)
    f:HookScript("OnShow", function(self)
        if self.lodgeOpen then return end
        self.lodgeOpen = true
        W:Sound("open")
        if ns.db.animations ~= false then
            self:SetAlpha(0)
            W:Tween(self, 0.15, function(e) self:SetAlpha(e) end)
        end
    end)
    f:HookScript("OnHide", function(self)
        if self:IsShown() then return end
        self.lodgeOpen = false
        W:Sound("close")
    end)
end

ns:OnSetup("panels", function(MF)
    -- The board, the toast and the journal already exist and have their own treatment
    local skip = { TheFishingLogBoard = true, TheFishingLogToast = true, TheFishingLogJournal = true }
    MF.panelSkin = function(f, name, opts)
        if not (name and skip[name]) then P:SkinPanel(f, opts) end
    end
    MF.buttonSkin = function(b) P:SkinButton(b) end
end)
