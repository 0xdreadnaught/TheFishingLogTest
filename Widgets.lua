-- Widgets: the few frame shapes the addon uses, built one way.
--
-- One place decides what a panel looks like, because the alternative was
-- tried: CreatePanel used to hand back a frame and leave the fill, the
-- position and the chrome to whoever called it. What that produced was
-- two addons' worth of look in one addon - a dark board and toast on one
-- side, five untinted Blizzard dialogs on the other, three different dark
-- tints among the three that were tinted at all, and a card that opened
-- flush against a window it shared nothing with. Every one of those was a
-- caller doing its own thing correctly.
--
-- So the fill, the border and the chrome live here now. A panel can still
-- say which weight of frame it wants and how solid it is; it cannot be
-- born looking like it came from somewhere else.
local _, MF = ...

------------------------------------------------------------------------
-- The palette
--
-- Six greys, two greens and two reds had accumulated, each picked at the
-- call site it was needed at and none of them next to each other. These
-- are the whole set, chosen together and against the dark fill below -
-- the old values were tuned for a pale stone background, where a dim grey
-- reads as dim rather than as absent.
--
-- test/cases/style.lua fails if a colour turns up outside this table, so
-- the next one has to be added here on purpose rather than typed into a
-- format string at midnight.
------------------------------------------------------------------------

MF.C = {
    gold  = "|cffffd100",   -- headings, keys, anything the eye should find
    text  = "|cffffffff",   -- said plainly
    label = "|cffa0a0a0",   -- field names beside a value
    muted = "|cff858585",   -- asides, hints, the small print
    faint = "|cff6a6a6a",   -- deliberately absent: "none yet", "not caught"
    spec  = "|cffff8000",   -- a specimen, and nothing else
    good  = "|cff3ee63e",   -- yes, on, working
    bad   = "|cffff5a5a",   -- no, off, broken
    hint  = "|cff66ccff",   -- a thing you can click or type, and a bonus
    brand = "|cff33ccff",   -- the addon saying its own name
    me    = "|cffff9d00",   -- you, in a list of other people

    -- Meanings the game already has, which we borrow rather than invent.
    silver = "|cffd0d0e0",
    bronze = "|cffcd7f32",
    alliance = "|cff5080ff",
    horde    = "|cffff4040",
}

-- Item quality colours are the game's, not ours: grades borrow them so a
-- "cracker" is the blue every player already reads as better than green.
-- They are listed so the style test knows them, and must not be restyled.
MF.QUALITY = {
    "|cff808080", "|cff9d9d9d", "|cffbbbbbb", "|cff1eff00", "|cff0070dd", "|cffa335ee",
}

------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------

local BACKDROPS = {
    -- Thin border: things that sit over the world while you fish - the
    -- board, a toast, a card.
    tooltip = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    -- Heavy border: windows you stop and read. The weight is the only
    -- thing that separates the two families now that the fill is shared.
    dialog = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    },
}

-- One fill, everywhere. The board is the same colour a little thinner,
-- because it is the one panel you leave up while you are playing.
MF.FILL = { 0.10, 0.12, 0.16, 0.95 }
MF.FILL_OVERLAY = { 0.10, 0.12, 0.16, 0.82 }
MF.FILL_READING = { 0.10, 0.12, 0.16, 1 }

-- opts: backdrop ("tooltip" | "dialog"), strata, movable, escCloses,
--       fill (a {r,g,b,a} for the rare panel that earns its own),
--       title (a heading at the top left), close (the X at the top right).
function MF:CreatePanel(name, width, height, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetBackdrop(BACKDROPS[opts.backdrop or "dialog"])
    f:SetBackdropColor(unpack(opts.fill or (opts.backdrop == "tooltip" and self.FILL or self.FILL_READING)))
    if opts.strata then f:SetFrameStrata(opts.strata) end
    -- Most windows share the DIALOG layer, and inside one layer the game
    -- draws by frame level, not by which opened last. A window opened over
    -- the journal could sit level with the journal's own text and buttons,
    -- and the two drew through each other. So a window comes to the front
    -- when it opens and when it's clicked. The raise is a child's OnShow,
    -- which fires whenever the window appears, rather than a hook on the
    -- window's own OnShow, which a later SetScript would quietly remove.
    f:SetToplevel(true)
    f.raiser = CreateFrame("Frame", nil, f)
    f.raiser:SetScript("OnShow", function() f:Raise() end)
    f:EnableMouse(true)
    if opts.movable then
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
    end
    if opts.escCloses and name then
        tinsert(UISpecialFrames, name)
    end
    -- Six copies of these two lines were spread over five files, which is
    -- five chances for one window's X to end up four pixels off.
    if opts.close then
        f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.close:SetPoint("TOPRIGHT", -4, -4)
    end
    -- A string is the heading; true is a heading whose words arrive
    -- later, which is how the news and losses panels work.
    if opts.title then
        f.title = self:CreateText(f, "GameFontNormalLarge", "TOPLEFT", 16, -14)
        if type(opts.title) == "string" then f.title:SetText(opts.title) end
    end
    f:Hide()
    if self.panelSkin then
        local ok, err = pcall(self.panelSkin, f, name, opts)
        if not ok then geterrorhandler()(err) end
    end
    return f
end

-- Buttons
--
-- UIPanelButtonTemplate is Blizzard's gold-on-parchment button, and it
-- looked fine while the panels behind it were Blizzard's parchment too.
-- Against the dark fill it reads as a row of red alert buttons - the
-- tabs worst of all, because there are six of them in a line. Darkening
-- the panels without bringing the buttons was half a job.
--
-- So this is a flat button in the panel's own colours: a fill one step
-- lighter than the panel so it still reads as something you press, a
-- hairline border, and the game's own fonts.
-- Buttons
--
-- UIPanelButtonTemplate is Blizzard's gold-on-parchment button, and it
-- looked fine while the panels behind it were parchment too. Against the
-- dark fill it reads as a row of red alert buttons.
--
-- Two passes to get here. The first leaned blue, which went muddy under
-- gold text. The second gave tabs a transparent rest state on the theory
-- that a tab is not a box - which turned the tab bar into six floating
-- words and lost the thing that made the row legible. Tabs are boxes.
-- They are the same box as everything else, and what marks the one you
-- are reading is that it is lighter and wearing a gold edge.
local BUTTON = {
    rest    = { 0.16, 0.17, 0.19, 1 },
    hover   = { 0.24, 0.25, 0.28, 1 },
    pushed  = { 0.10, 0.11, 0.12, 1 },
    -- The only thing in the addon that disables a button is the tab bar,
    -- and a tab you cannot click is the tab you are reading. So the
    -- disabled state is painted as the one you are on, not as dead.
    current = { 0.34, 0.33, 0.30, 1 },
    -- Bronze, which is what the rest of the game's furniture is edged
    -- with, so the frame and the gold text belong to each other.
    edge    = { 0.44, 0.37, 0.22, 1 },
    edgeOn  = { 0.78, 0.65, 0.34, 1 },
}

local function Paint(b)
    local fill, edge = BUTTON.rest, BUTTON.edge
    if not b:IsEnabled() then
        fill, edge = BUTTON.current, BUTTON.edgeOn
    elseif b.pushed then
        fill = BUTTON.pushed
    elseif b.hovered then
        fill, edge = BUTTON.hover, BUTTON.edgeOn
    end
    b:SetBackdropColor(unpack(fill))
    b:SetBackdropBorderColor(unpack(edge))
end

function MF:CreateButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 22)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    -- SetFontString rather than our own label, so SetText stays the one
    -- the game and the simulator already know how to use.
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    b:SetFontString(label)
    b:SetNormalFontObject("GameFontNormalSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontNormalSmall")

    b:SetScript("OnEnter", function(self) self.hovered = true Paint(self) end)
    b:SetScript("OnLeave", function(self) self.hovered = nil Paint(self) end)
    b:SetScript("OnMouseDown", function(self) self.pushed = true Paint(self) end)
    b:SetScript("OnMouseUp", function(self) self.pushed = nil Paint(self) end)
    b:SetScript("OnEnable", Paint)
    b:SetScript("OnDisable", Paint)
    b:SetScript("OnShow", Paint)
    Paint(b)

    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    if self.buttonSkin then
        local ok, err = pcall(self.buttonSkin, b)
        if not ok then geterrorhandler()(err) end
    end
    return b
end

function MF:CreateText(parent, font, point, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    if point then fs:SetPoint(point, x or 0, y or 0) end
    return fs
end
