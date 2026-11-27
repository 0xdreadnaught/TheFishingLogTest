-- The fishing board, rebuilt.
--
-- The Fishing Log's board keeps running underneath, invisible: it still owns being opened and closed,
-- hiding itself in combat (a secure state driver), its position and scale, and the hidden buttons that
-- make double right-click cast. Ours is drawn as a child of it, so it shows, hides and moves with it.
-- Its two secure buttons, Cast and Apply lure, are handed to our board (out of combat, which is when
-- addons may do that). Everything else is drawn here from The Fishing Log's data, every time it
-- updates its own board.
--
--   header   where you are, the clock, running or stopped
--   frenzy   a banner (and the board glowing) only while this water is in frenzy
--   numbers  fish, weight, best  (or your score in a match)
--   feed     the last catches, newest on top, sliding in as you land them; the match standings
--   skill    one slim gauge;  next frenzy here
--   notes    today's bounty, the King of this spot, an event that's about to start, your goal
--   actions  Cast, Lure (with its time running down), pole; share, stop, journal
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local B = {}
ns.Board = B

local MF, old, f
local WIDTH = 300
local MAX_FEED = 8
local function FeedRows() return math.max(3, math.min(MAX_FEED, ns.db.feedRows or 6)) end
local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:13:13|t "
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"
local GLOW = "Interface\\AddOns\\" .. TFL.ADDON .. "\\Media\\FrenzyGlow.tga"
local MEDAL = { { 1, 0.82, 0 }, { 0.82, 0.82, 0.88 }, { 0.80, 0.50, 0.20 } }

local function HexColor(code)
    local r, g, b = (code or ""):match("|cff(%x%x)(%x%x)(%x%x)")
    if not r then return 1, 1, 1 end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------
local function Border(button, size)
    local b = button:CreateTexture(nil, "OVERLAY")
    b:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b:SetPoint("CENTER")
    b:SetSize(size * 1.72, size * 1.72)
    return b
end

local BUTTON, GAP = 26, 8 -- every button in the board's bottom row

local function StyleSecure(button, size)
    button:SetSize(size, size)
    local nt = button:GetNormalTexture()
    if nt then nt:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    if not button.lodgeBorder then
        button.lodgeBorder = Border(button, size)
        -- The Fishing Log resets the icon on every update; keep it cropped
        hooksecurefunc(button, "SetNormalTexture", function(self)
            local t = self:GetNormalTexture()
            if t then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end)
    end
end

local function SmallButton(parent, icon, title, tip, onClick)
    local b = W:IconButton(parent, 26, icon, onClick, title, tip)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Border(b, 26)
    return b
end

local function Cell(parent)
    local c = CreateFrame("Frame", nil, parent)
    c.value = W:Label(c, "GameFontHighlightLarge")
    c.value:SetPoint("TOP", 0, -4)
    c.label = W:Label(c, "GameFontDisableSmall")
    c.label:SetPoint("TOP", c.value, "BOTTOM", 0, -2)
    c:EnableMouse(true)
    return c
end

local function FeedRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(WIDTH - 24, 22)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.glow = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.glow:SetAllPoints()
    r.glow:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    r.glow:SetBlendMode("ADD")
    r.glow:SetAlpha(0)
    r.iconBack = r:CreateTexture(nil, "ARTWORK")
    r.iconBack:SetSize(20, 20)
    r.iconBack:SetPoint("LEFT", 2, 0)
    r.iconBack:SetColorTexture(0, 0, 0, 0.9)
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetPoint("TOPLEFT", r.iconBack, 1, -1)
    r.icon:SetPoint("BOTTOMRIGHT", r.iconBack, -1, 1)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = W:Label(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.iconBack, "RIGHT", 8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.tag = W:Label(r, "GameFontNormalSmall")
    r.score = W:Label(r, "GameFontHighlight")
    r.score:SetPoint("RIGHT", -6, 0)
    r.score:SetJustifyH("RIGHT")
    r.tag:SetPoint("RIGHT", r.score, "LEFT", -8, 0)
    return r
end

local function SetFeed(r, icon, name, score, opts)
    opts = opts or {}
    r.iconBack:SetShown(icon ~= nil)
    r.icon:SetShown(icon ~= nil)
    if icon then r.icon:SetTexture(icon) end
    r.name:ClearAllPoints()
    if icon then r.name:SetPoint("LEFT", r.iconBack, "RIGHT", 8, 0) else r.name:SetPoint("LEFT", 8, 0) end
    r.name:SetText(name or "")
    r.name:SetTextColor(opts.r or 1, opts.g or 1, opts.b or 1)
    r.score:SetText(score or "")
    r.tag:SetText(opts.tag or "")
    r.name:SetWidth(math.max(60, WIDTH - 24 - (icon and 30 or 8) - (r.score:GetStringWidth() or 0)
        - ((opts.tag and opts.tag ~= "") and ((r.tag:GetStringWidth() or 0) + 12) or 0) - 16))
    r.bg:SetColorTexture(opts.hr or 1, opts.hg or 1, opts.hb or 1, opts.ha or 0.03)
    r:Show()
end

-- An orange glow around the whole board while the water is in frenzy
local function FrenzyGlow(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetAllPoints(parent)
    g:EnableMouse(false)
    local function Piece(u1, u2, v1, v2)
        local t = g:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW)
        t:SetTexCoord(u1, u2, v1, v2)
        t:SetBlendMode("ADD")
        return t
    end
    for _, c in ipairs({ { "TOPLEFT", -14, 14, 0, 0.25, 0, 0.25 }, { "TOPRIGHT", 14, 14, 0.75, 1, 0, 0.25 },
        { "BOTTOMLEFT", -14, -14, 0, 0.25, 0.75, 1 }, { "BOTTOMRIGHT", 14, -14, 0.75, 1, 0.75, 1 } }) do
        local t = Piece(c[4], c[5], c[6], c[7])
        t:SetSize(16, 16)
        t:SetPoint(c[1], parent, c[1], c[2], c[3])
    end
    for _, top in ipairs({ true, false }) do
        local t = Piece(0.25, 0.75, top and 0 or 0.75, top and 0.25 or 1)
        local e = top and "TOP" or "BOTTOM"
        t:SetHeight(16)
        t:SetPoint(e .. "LEFT", parent, e .. "LEFT", 2, top and 14 or -14)
        t:SetPoint(e .. "RIGHT", parent, e .. "RIGHT", -2, top and 14 or -14)
    end
    for _, left in ipairs({ true, false }) do
        local t = Piece(left and 0 or 0.75, left and 0.25 or 1, 0.25, 0.75)
        local e = left and "LEFT" or "RIGHT"
        t:SetWidth(16)
        t:SetPoint("TOP" .. e, parent, "TOP" .. e, left and -14 or 14, -2)
        t:SetPoint("BOTTOM" .. e, parent, "BOTTOM" .. e, left and -14 or 14, 2)
    end
    g.age = 0
    g:SetScript("OnUpdate", function(self, elapsed)
        if ns.db.animations == false or (MF.db and MF.db.settings.reducedMotion) then self:SetAlpha(0.6) return end
        self.age = self.age + elapsed
        self:SetAlpha(0.6 + math.sin(self.age * math.pi / 1.5) * 0.15)
    end)
    g:Hide()
    return g
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------
local function Build()
    f = CreateFrame("Frame", "AnglersLodgeBoard", old, "BackdropTemplate")
    f:SetWidth(WIDTH)
    f:SetPoint("TOPLEFT", old, "TOPLEFT", 0, 0)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 20, insets = { left = 5, right = 5, top = 5, bottom = 5 } })
    f:SetBackdropColor(0.04, 0.05, 0.09, ns.db.boardAlpha or 0.9)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if InCombatLockdown() or not old:IsMovable() then return end
        old:StartMoving()
    end)
    f:SetScript("OnDragStop", function() old:StopMovingOrSizing() end)
    f.glow = FrenzyGlow(f)

    -- Header
    f.badge = W:FramedIcon(f, 30, FISHING_ICON)
    f.badge:SetPoint("TOPLEFT", 14, -12)
    f.title = W:Label(f, "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f.badge, "TOPRIGHT", 10, -1)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.sub = W:Label(f, "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    f.sub:SetTextColor(0.75, 0.75, 0.75)
    f.clock = W:Label(f, "GameFontHighlightLarge")
    f.clock:SetPoint("TOPRIGHT", -50, -14)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -2, -2)
    f.close:SetScale(0.8)
    f.close:SetScript("OnClick", function()
        if MF:IsSessionRunning() then MF:StopSession() end
        MF:ShowBoard(false)
    end)
    W:Tip(f.close, "Close", "Stops your fishing log and hides the board.")

    -- Background opacity: a small button beside the close button, with a slider under it
    local opacity = CreateFrame("Button", nil, f)
    opacity:SetSize(16, 16)
    opacity:SetPoint("RIGHT", f.close, "LEFT", 2, 0)
    opacity:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    opacity:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    W:Tip(opacity, "Background", "Change how see-through the board's background is.")
    f.opacityButton = opacity

    local pop = CreateFrame("Frame", nil, f, "BackdropTemplate")
    pop:SetSize(190, 52)
    pop:SetPoint("TOPRIGHT", opacity, "BOTTOMRIGHT", 8, -4)
    pop:SetFrameLevel(f:GetFrameLevel() + 30)
    pop:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    pop:SetBackdropColor(0.03, 0.03, 0.06, 0.96)
    pop:SetBackdropBorderColor(0.95, 0.78, 0.35, 1)
    pop:EnableMouse(true)
    pop.label = W:Label(pop, "GameFontNormalSmall", "Background")
    pop.label:SetPoint("TOPLEFT", 12, -9)
    pop.value = W:Label(pop, "GameFontHighlightSmall")
    pop.value:SetPoint("TOPRIGHT", -12, -9)
    local slider = CreateFrame("Slider", nil, pop, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(164, 17)
    slider:SetPoint("BOTTOM", 0, 8)
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(0.05)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouseWheel(true)
    local function Apply(v) B:SetBackgroundAlpha(v) end
    slider:SetScript("OnValueChanged", function(_, v) Apply(v) end)
    slider:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * 0.05) end)
    pop:Hide()
    f.opacityPop = pop
    opacity:SetScript("OnClick", function()
        W:Sound("click")
        if pop:IsShown() then pop:Hide() return end
        slider:SetValue(ns.db.boardAlpha or 0.9)
        Apply(ns.db.boardAlpha or 0.9)
        pop:Show()
    end)
    -- Mouse wheel on the button itself works too
    opacity:EnableMouseWheel(true)
    opacity:SetScript("OnMouseWheel", function(_, d)
        Apply((ns.db.boardAlpha or 0.9) + d * 0.05)
        if pop:IsShown() then slider:SetValue(ns.db.boardAlpha) end
    end)
    f.headRule = W:Divider(f, WIDTH - 24)
    f.headRule:SetPoint("TOPLEFT", 12, -50)

    -- Frenzy banner
    local banner = CreateFrame("Frame", nil, f)
    banner:SetSize(WIDTH - 20, 22)
    banner.bg = banner:CreateTexture(nil, "BACKGROUND")
    banner.bg:SetAllPoints()
    banner.bg:SetColorTexture(1, 0.5, 0.1, 1)
    if CreateColor and banner.bg.SetGradient then
        banner.bg:SetGradient("HORIZONTAL", CreateColor(0.9, 0.35, 0.05, 0.05), CreateColor(0.95, 0.5, 0.1, 0.5))
    else
        banner.bg:SetAlpha(0.3)
    end
    banner.text = W:Label(banner, "GameFontNormal")
    banner.text:SetPoint("LEFT", 8, 0)
    banner.text:SetTextColor(1, 0.6, 0.15)
    banner.time = W:Label(banner, "GameFontHighlight")
    banner.time:SetPoint("RIGHT", -8, 0)
    banner:EnableMouse(true)
    W:Tip(banner, "Feeding frenzy", function()
        return ("Fish here run %d%% heavier and specimens are %s as likely, while it lasts."):format(
            math.floor(((MF.FRENZY_WEIGHT or 1.2) - 1) * 100 + 0.5),
            (MF.FRENZY_SPECIMEN or 2) == 2 and "twice" or tostring(MF.FRENZY_SPECIMEN))
    end)
    banner:Hide()
    f.banner = banner

    -- Numbers
    f.cells = {}
    for i = 1, 3 do f.cells[i] = Cell(f) f.cells[i]:SetSize((WIDTH - 24) / 3, 38) end
    f.cells[1]:SetScript("OnEnter", function(self)
        if MF:InMatch() or not MF.session then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Cast outcomes", 1, 0.82, 0)
        GameTooltip:AddLine(MF:CastOutcomeSummary(MF.session), 1, 1, 1, true)
        GameTooltip:AddLine("One landed cast can contain several fish. Unknown is not an escape.", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    f.cells[1]:SetScript("OnLeave", function(self) W:HideTip(self) end)
    f.numRule = W:Divider(f, WIDTH - 24)

    -- Feed
    f.feed = {}
    for i = 1, MAX_FEED + 1 do f.feed[i] = FeedRow(f) end
    f.idle = W:Label(f, "GameFontHighlightSmall")
    f.idle:SetWidth(WIDTH - 40)
    f.idle:SetTextColor(0.7, 0.7, 0.7)

    -- Skill
    f.skill = W:Bar(f, WIDTH - 24, 12, 0.35, 0.7, 0.9)
    f.skill.text:SetFontObject("GameFontHighlightSmall")
    f.skill:EnableMouse(true)
    f.skill:SetScript("OnEnter", function(self)
        local old_bar = old and old.barS
        local fn = old_bar and old_bar:GetScript("OnEnter")
        if fn then fn(self) end -- The Fishing Log's full skill tooltip
    end)
    f.skill:SetScript("OnLeave", function(self) W:HideTip(self) end)
    f.nextFrenzy = W:Label(f, "GameFontDisableSmall")
    f.nextFrenzy:SetJustifyH("LEFT")
    f.nextFrenzy:SetWidth(WIDTH - 24)
    f.nextFrenzyHit = CreateFrame("Frame", nil, f)
    f.nextFrenzyHit:SetAllPoints(f.nextFrenzy)
    f.nextFrenzyHit:EnableMouse(true)
    f.nextFrenzyHit:SetScript("OnEnter", function(self)
        local fn = old and old.barB and old.barB:GetScript("OnEnter")
        if fn then fn(self) end -- The Fishing Log's full frenzy explanation and this water's clock
    end)
    f.nextFrenzyHit:SetScript("OnLeave", function(self) W:HideTip(self) end)

    -- Notes
    f.noteRule = W:Divider(f, WIDTH - 24)
    f.notes = {}
    for i = 1, 4 do
        local n = CreateFrame("Frame", nil, f)
        n:SetSize(WIDTH - 24, 16)
        n.icon = n:CreateTexture(nil, "ARTWORK")
        n.icon:SetSize(14, 14)
        n.icon:SetPoint("LEFT", 2, 0)
        n.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- A figure at the right (a bounty's best weight) keeps its place; the
        -- words beside it are what gets cut short when the line is too long.
        n.value = W:Label(n, "GameFontHighlightSmall")
        n.value:SetPoint("RIGHT", 0, 0)
        n.value:SetJustifyH("RIGHT")
        n.text = W:Label(n, "GameFontHighlightSmall")
        n.text:SetPoint("LEFT", 22, 0)
        n.text:SetPoint("RIGHT", n.value, "LEFT", -6, 0)
        n.text:SetJustifyH("LEFT")
        n.text:SetWordWrap(false)
        n:EnableMouse(true)
        n:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        n:SetScript("OnLeave", function(self) W:HideTip(self) end)
        f.notes[i] = n
    end

    -- Actions
    f.actRule = W:Divider(f, WIDTH - 24)
    f.pole = SmallButton(f, FISHING_ICON, "Fishing gear", "Left-click: swap pole. Right-click: Fishing Outfit wardrobe.",
        function(_, button) if button == "RightButton" then MF:OpenFishingOutfit() else MF:TogglePole() end end)
    f.journal = SmallButton(f, "Interface\\Icons\\INV_Misc_Book_09", "Angler's Journal", "Left-click: journal. Right-click: Fishing here.",
        function(_, button)
            if button == "RightButton" then MF:OpenFishingHere()
            elseif MF.current and MF:NoticeForMatch(MF.current.id) then MF:OpenMatchEvent(MF.current)
            else MF:ToggleJournal() end
        end)
    f.stop = SmallButton(f, "Interface\\Icons\\INV_Misc_PocketWatch_01", "Stop the log", "Ends this session and prints a summary.",
        function() MF:StopSession() end)
    f.share = SmallButton(f, "Interface\\Icons\\INV_Letter_15", "Share", "Posts your log or match result to chat.",
        function() MF:Share() end)
    f.volume = SmallButton(f, "Interface\\Icons\\INV_Misc_Horn_01", "Volume",
        "Every game volume on a slider, to change while the line is out.",
        function(self) if MF.ToggleVolumePanel then MF:ToggleVolumePanel(self) end end)
    f.lureTime = W:Label(f, "GameFontHighlightSmall")
    f:Hide()
    return f
end

-- Hand The Fishing Log's secure Cast and Lure buttons to our board (out of combat only)
local function Adopt()
    if InCombatLockdown() then B.pendingAdopt = true return end
    B.pendingAdopt = nil
    local cast, lure = old.cast or MF.castButton, old.lure or MF.lureButton
    if cast then
        cast:SetParent(f)
        cast:SetFrameLevel(f:GetFrameLevel() + 3)
        StyleSecure(cast, BUTTON)
        f.cast = cast
    end
    if lure then
        lure:SetParent(f)
        lure:SetFrameLevel(f:GetFrameLevel() + 3)
        StyleSecure(lure, BUTTON)
        if not f.lureCD then
            f.lureCD = CreateFrame("Cooldown", nil, lure, "CooldownFrameTemplate")
            f.lureCD:SetAllPoints()
            if f.lureCD.SetHideCountdownNumbers then f.lureCD:SetHideCountdownNumbers(true) end
            if f.lureCD.SetReverse then f.lureCD:SetReverse(true) end
            f.lureCD:EnableMouse(false)
        end
        -- The time left sits on the icon, as a cooldown does on an action button
        if not f.lureTimeHost then
            f.lureTimeHost = CreateFrame("Frame", nil, lure)
            f.lureTimeHost:SetAllPoints()
            f.lureTimeHost:SetFrameLevel(lure:GetFrameLevel() + 6)
            f.lureTimeHost:EnableMouse(false)
            f.lureTime:SetParent(f.lureTimeHost)
            f.lureTime:SetFontObject("NumberFontNormalSmall")
            f.lureTime:ClearAllPoints()
            f.lureTime:SetPoint("BOTTOM", lure, "BOTTOM", 0, 1)
        end
        f.lure = lure
    end
end

-- Make The Fishing Log's own board invisible and let clicks through it (it stays "shown" underneath)
local function Silence()
    if old.ClearBackdrop then old:ClearBackdrop() end
    for _, r in ipairs({ old:GetRegions() }) do r:SetAlpha(0) end
    for _, child in ipairs({ old:GetChildren() }) do
        if child ~= f and child ~= old.cast and child ~= old.lure and child ~= MF.castButton and child ~= MF.lureButton then
            local name = child.GetName and child:GetName()
            -- The hidden cast-binding buttons stay exactly as they are
            if name ~= "TheFishingLogCastGuard" and name ~= "TheFishingLogCastBind" then
                child:SetAlpha(0)
                if child.EnableMouse then child:EnableMouse(false) end
                for _, sub in ipairs({ child:GetChildren() }) do
                    if sub.EnableMouse then sub:EnableMouse(false) end
                end
            end
        end
    end
    old:EnableMouse(false)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function CountUp(fs, key, from, to, format)
    if ns.db.animations == false or not from or from == to then fs:SetText(format(to)) return end
    W:Tween(key, 0.45, function(e) fs:SetText(format(from + (to - from) * e)) end)
end

local function Place(region, y, x)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", x or 12, y)
end

function B:DrawSession(s, y)
    local running = MF:IsSessionRunning()
    local elapsed = MF:SessionElapsed(s)
    f.badge.icon:SetTexture(FISHING_ICON)
    f.title:SetText(MF:SessionWhere(s))
    f.sub:SetText(running and "|cff3ee63eSolo log|r  |cffa0a0a0running|r" or "|cffa0a0a0Solo log, stopped|r")
    f.clock:SetText((running and "|cffffffff" or "|cffa0a0a0") .. MF:FormatClock(elapsed) .. "|r")

    local perHour = elapsed > 30 and (s.count / elapsed * 3600) or 0
    local last = self.lastSession == s and self.last or nil
    CountUp(f.cells[1].value, "lodgeCount", last and last.count, s.count, function(v) return tostring(math.floor(v + 0.5)) end)
    local finds = MF.FindsText and MF:FindsText(s.finds)
    f.cells[1].label:SetText(finds and ("fish, " .. finds) or perHour > 0 and ("fish, %.0f/hr"):format(perHour) or "fish")
    CountUp(f.cells[2].value, "lodgeTotal", last and last.total, s.total, function(v) return MF:Weight(v) end)
    f.cells[2].label:SetText((MF:ValueEnabled() and (s.value or 0) > 0) and ("total, " .. MF:ShortMoney(s.value)) or "total")
    f.cells[3].value:SetText(s.biggest > 0 and MF:Weight(s.biggest) or "-")
    f.cells[3].label:SetText("best")

    -- The feed
    local newCatch = last and #s.catches > last.n
    local rows = 0
    local nRows = FeedRows()
    for i = nRows + 1, MAX_FEED + 1 do f.feed[i]:Hide() end
    for i = 1, nRows do
        local c = s.catches[i]
        local r = f.feed[i]
        if c then
            rows = i
            if c.find then
                SetFeed(r, MF:FishIcon(c.itemID), c.name or "Find", "find", { r = 0.9, g = 0.75, b = 0.4 })
            elseif c.junk then
                SetFeed(r, MF:FishIcon(c.itemID), c.name or "Junk", "junk", { r = 0.6, g = 0.6, b = 0.6 })
            else
                local _, colour = MF:WeightGradeShort(c.itemID, c.weight)
                local cr, cg, cb = HexColor(colour)
                local best = s.biggest > 0 and c.weight == s.biggest and s.count > 1
                if c.specimen then
                    SetFeed(r, MF:FishIcon(c.itemID), c.name, MF:Weight(c.weight),
                        { r = 1, g = 0.5, b = 0, tag = STAR, hr = 1, hg = 0.5, hb = 0, ha = 0.14 })
                else
                    SetFeed(r, MF:FishIcon(c.itemID), c.name, MF:Weight(c.weight),
                        { r = cr, g = cg, b = cb, tag = best and "|cffffd100best|r" or nil })
                end
            end
            Place(r, y - (i - 1) * 23)
        else
            r:Hide()
        end
    end
    if rows == 0 then
        f.idle:SetText(running and "Line's in. Your catches land here." or "Stopped. Cast again for a new log.")
        Place(f.idle, y - 4, 20)
        f.idle:Show()
        rows = 1
    else
        f.idle:Hide()
    end
    if newCatch and ns.db.animations ~= false then
        -- The new catch slides in, the rest step down
        local r = f.feed[1]
        local c = s.catches[1]
        r:SetAlpha(0)
        local glowA = (c and c.specimen) and 0.8 or 0.45
        if c and c.specimen then r.glow:SetVertexColor(1, 0.5, 0) else r.glow:SetVertexColor(1, 0.85, 0.45) end
        W:Tween(r, 0.35, function(e)
            r:SetAlpha(e)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 12 - 14 * (1 - e), y)
        end)
        W:Tween(r.glow, 1.4, function(e) r.glow:SetAlpha(glowA * (1 - e)) end)
    end
    self.lastSession = s
    self.last = { count = s.count, total = s.total, n = #s.catches }
    return y - rows * 23 - 4
end

function B:DrawMatch(m, y)
    f.badge.icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_09")
    f.title:SetText(m.name or "Match")
    f.sub:SetText((MF.MODES[m.mode] or "") .. (m.fish and ("  |cffa0a0a0" .. MF:FishName(m.fish) .. "|r") or ""))
    local now = GetServerTime()
    if m.finished then
        f.clock:SetText("|cffff8000Final|r")
    elseif now < m.startsAt then
        -- Not a negative time: how long until it starts.
        -- The last ten seconds pulse, yellow and white, so the start is coming.
        local wait = m.startsAt - now
        local colour = (wait <= 10 and wait % 2 == 1) and "|cffffffff" or "|cffffd100"
        f.clock:SetText(colour .. "in " .. MF:FormatClock(wait) .. "|r")
    else
        -- Running is blue, the last minute orange.
        local left = m.endsAt - now
        f.clock:SetText((left <= 60 and "|cffff8040" or "|cff66ccff") .. MF:FormatClock(left) .. "|r")
    end
    local mine = m.players and m.players[MF.me]
    f.cells[1].value:SetText(mine and tostring(mine.count) or "0")
    f.cells[1].label:SetText("your fish")
    f.cells[2].value:SetText(mine and ("%.2f"):format(MF:WeightNumber(mine.total)) or "0.00")
    f.cells[2].label:SetText(MF:WeightUnit() .. " total")
    -- The format's full name is on the line under the title; the cell has
    -- room for two words.
    local SHORT = { weight = "total bag", biggest = "single fish", count = "most fish", specimen = "specimen" }
    f.cells[3].value:SetText(SHORT[m.mode] or "")
    f.cells[3].label:SetText(m.hcp and "format (hcp)" or "format")

    local rows = {}
    if m.team then
        for i, t in ipairs(MF:TeamStandings(m)) do
            if i > 3 then break end
            local fish, spec = MF:StandingFish(t.p, m)
            rows[#rows + 1] = { place = t.place or i, name = MF:TeamLabel(t.name), score = MF:FormatScore(t.p, m), team = true,
                fish = fish, spec = spec }
        end
    end
    local king = MF:King(m.spot)
    for i, s in ipairs(MF:Standings(m)) do
        -- The board is narrow: the fish is its icon, and a specimen gets the mark.
        local fish, spec = MF:StandingFish(s.p, m)
        rows[#rows + 1] = { place = s.place or i, name = MF:ShortName(s.name), score = MF:FormatScore(s.p, m),
            me = MF:IsMe(s.name), king = king and king.h == s.name, fish = fish, spec = spec }
    end
    local n = 0
    for i = 1, MAX_FEED + 1 do
        local row, r = rows[i], f.feed[i]
        if i > FeedRows() + 1 then row = nil end
        if row then
            n = i
            local medal = (not row.team) and MEDAL[row.place] or nil
            if row.team then medal = { 1, 0.82, 0 } end
            local placeText = ("%d."):format(row.place)
            SetFeed(r, row.fish and MF:FishIcon(row.fish) or nil,
                ("%s%s  %s"):format(row.king and CROWN or "", placeText, row.name), row.score, {
                tag = row.spec and m.mode ~= "specimen" and "|cffffd100specimen|r" or nil,
                r = row.me and 0.25 or (medal and medal[1] or 1), g = row.me and 0.9 or (medal and medal[2] or 1),
                b = row.me and 0.25 or (medal and medal[3] or 1),
                hr = 1, hg = 0.82, hb = 0, ha = row.me and 0.12 or 0.03 })
            Place(r, y - (i - 1) * 23)
        else
            r:Hide()
        end
    end
    f.idle:Hide()
    if n == 0 then
        f.idle:SetText("Waiting for anglers...")
        Place(f.idle, y - 4, 20)
        f.idle:Show()
        n = 1
    end
    return y - n * 23 - 4
end

-- The background's opacity (the gear on the board, and the options panel)
function B:SetBackgroundAlpha(v)
    v = math.max(0, math.min(1, math.floor((v or 0.9) * 20 + 0.5) / 20))
    ns.db.boardAlpha = v
    if not f then return end
    f:SetBackdropColor(0.04, 0.05, 0.09, v)
    if f.opacityPop then f.opacityPop.value:SetText(("%d%%"):format(v * 100 + 0.5)) end
end

function B:Update()
    if not f or not old or not MF:BoardOpen() or InCombatLockdown() then return end
    if self.pendingAdopt then Adopt() end
    local m = MF.current
    local matchNotice = m and MF:NoticeForMatch(m.id)
    local s = MF.session
    local y = -56

    -- Frenzy here
    local here = MF:SpotKey()
    local key = m and m.spot or here
    local active, secs = MF:FrenzyPresentationState(key)
    local hereActive = MF:FrenzyPresentationState(here)
    f.glow:SetShown(hereActive and true or false)
    if active then
        f.banner:ClearAllPoints()
        f.banner:SetPoint("TOPLEFT", 10, y)
        f.banner.text:SetText("FEEDING FRENZY")
        f.banner.time:SetText(MF:FormatClock(secs or 0))
        f.banner:Show()
        y = y - 26
    else
        f.banner:Hide()
    end

    local compact = (m == nil and s == nil) or matchNotice ~= nil
    for _, c in ipairs(f.cells) do c:SetShown(not compact) end
    f.numRule:SetShown(not compact)
    if not compact then
        for i, c in ipairs(f.cells) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 12 + (i - 1) * (WIDTH - 24) / 3, y)
        end
        y = y - 42
        f.numRule:ClearAllPoints()
        f.numRule:SetPoint("TOPLEFT", 12, y)
        y = y - 6
    end

    if m and not matchNotice then
        y = self:DrawMatch(m, y)
        f.stop:Hide()
        f.share:Show()
    elseif s and not m then
        y = self:DrawSession(s, y)
        f.stop:SetShown(MF:IsSessionRunning())
        f.share:Show()
    else
        for _, r in ipairs(f.feed) do r:Hide() end
        local where = select(2, MF:SpotInfo())
        f.badge.icon:SetTexture(FISHING_ICON)
        f.title:SetText(matchNotice and ("Match: " .. (MF.MODES[m.mode] or "")) or "Ready to fish")
        f.sub:SetText(where or (GetZoneText and GetZoneText()) or "")
        f.clock:SetText("")
        f.idle:SetText(matchNotice and "Open the journal's Events page for the standings." or "Cast to start a log. Each catch lands here.")
        Place(f.idle, y - 2, 20)
        f.idle:Show()
        y = y - 22
        f.stop:Hide()
        f.share:Hide()
        self.lastSession, self.last = nil, nil
    end

    -- Skill
    local skill, maxSkill, bonus = MF:FishingSkill()
    Place(f.skill, y - 4)
    if skill and maxSkill and maxSkill > 0 then
        bonus = math.max(0, bonus or 0)
        local capped = skill >= maxSkill
        -- The skill this water asks for, as The Fishing Log's own bar shows it
        local here = MF.SkillHereTag and MF:SkillHereTag(skill + bonus) or ""
        f.skill:Set(skill, maxSkill, (bonus > 0 and ("Fishing %d  |cff66ccff+%d|r"):format(skill, bonus)
            or ("Fishing %d / %d"):format(skill, maxSkill)) .. here)
        if capped then f.skill:SetColor(0.9, 0.75, 0.2) else f.skill:SetColor(0.3, 0.6, 0.9) end
    else
        f.skill:Set(0, 1, "Fishing not learned")
        f.skill:SetColor(0.35, 0.35, 0.35)
    end
    y = y - 20
    if not active then
        f.nextFrenzy:SetText(secs and ("Next frenzy here in |cffffffff%s|r"):format(MF:FormatClock(secs)) or "No frenzy water nearby")
        Place(f.nextFrenzy, y - 2)
        f.nextFrenzy:Show()
        f.nextFrenzyHit:Show()
        y = y - 16
    else
        f.nextFrenzy:Hide()
        f.nextFrenzyHit:Hide()
    end

    -- Notes
    f.noteRule:ClearAllPoints()
    f.noteRule:SetPoint("TOPLEFT", 12, y - 4)
    y = y - 10
    local notes = {}
    local event = MF:NextSignedEvent()
    local untilEvent = event and event.startsAt - GetServerTime()
    if untilEvent and untilEvent <= 3600 and not matchNotice then
        notes[#notes + 1] = { "Interface\\Icons\\INV_Misc_Note_02", ("Event |cff66ccff%s|r in %s"):format(event.title,
            MF:FormatClock(math.max(0, untilEvent))) }
    end
    local _, bountyID, bountyZone = MF:TodayBounty()
    -- Only where it counts: in the bounty's own zone (the same test a catch has
    -- to pass to enter it), or anywhere when it has no zone. Elsewhere the line
    -- was a reminder you could do nothing about, taking the King's room.
    local bountyHere = bountyID and (not bountyZone or bountyZone == MF:ZoneEnglish())
    if bountyHere then
        local best = MF:MyBountyBest() or 0
        local progress = MF:BountyFormat("day") == "top3" and MF:BountyProgressText("day") or nil
        notes[#notes + 1] = { MF:FishIcon(bountyID), ("Bounty: |cffffffff%s|r  |cffa0a0a0%s|r"):format(MF:FishName(bountyID),
            progress or bountyZone or "anywhere"),
            "Today's bounty. Open the journal's Bounty page for the standings.",
            best > 0 and ("|cff3ee63e" .. MF:Weight(best) .. "|r") or nil }
    end
    local spotKey, _, mapID
    if m then spotKey, mapID = m.spot, m.mapID else spotKey, _, mapID = MF:SpotInfo() end
    local king = MF:King(spotKey)
    -- A match can be on a map this client never synced (your own map is
    -- asked about at login and on every zone change), so it asks; and
    -- "checking" is only said while an answer can actually come.
    local checking = not MF:RecordsReady(mapID)
    if checking and m then checking = MF:RequestRecords(mapID) end
    if checking then
        notes[#notes + 1] = { "Interface\\GroupFrame\\UI-Group-LeaderIcon", "|cffa0a0a0Checking this spot's records...|r" }
    elseif king then
        notes[#notes + 1] = { "Interface\\GroupFrame\\UI-Group-LeaderIcon", ("King: |cffffd100%s|r  %s"):format(MF:ShortName(king.h), MF:Weight(king.w)),
            ("King of this spot: %s, %s %s"):format(MF:ShortName(king.h), MF:FishName(king.id), MF:Weight(king.w)) }
    else
        notes[#notes + 1] = { "Interface\\GroupFrame\\UI-Group-LeaderIcon", "|cffa0a0a0No King here yet. Set a record!|r" }
    end
    -- Your first goal, with how far along it is; every goal on mouse-over
    local goals = MF.FishingGoals and MF:FishingGoals() or {}
    if goals[1] then
        local lines = {}
        for _, g in ipairs(goals) do
            lines[#lines + 1] = MF:GoalTitle(g) .. "  |cffa0a0a0" .. (MF:GoalProgress(g).short or "") .. "|r"
        end
        notes[#notes + 1] = { MF:GoalIcon(goals[1]), MF:FishingGoalText(),
            "Fishing goals|n" .. table.concat(lines, "|n") .. "|n|cff99ccffThe journal's Goals page has the detail.|r",
            "|cffffd100" .. (MF:GoalProgress(goals[1]).short or "") .. "|r" }
    end
    for i, n in ipairs(f.notes) do
        local note = notes[i]
        if note then
            n.icon:SetTexture(note[1])
            -- Item and spell icons have a dark rim worth cropping; interface art doesn't
            local crop = type(note[1]) == "number" or tostring(note[1]):find("Icons") ~= nil
            if crop then n.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else n.icon:SetTexCoord(0, 1, 0, 1) end
            n.text:SetText(note[2])
            n.value:SetText(note[4] or "")
            n.tip = note[3]
            Place(n, y - (i - 1) * 17)
            n:Show()
        else
            n:Hide()
        end
    end
    y = y - #notes * 17 - 4

    -- Actions
    f.actRule:ClearAllPoints()
    f.actRule:SetPoint("TOPLEFT", 12, y - 2)
    y = y - 10
    -- One row of same-sized buttons: cast, lure, gear on the left; the rest on the right
    if f.cast then f.cast:ClearAllPoints() f.cast:SetPoint("TOPLEFT", 16, y - 10) end
    if f.lure then
        f.lure:ClearAllPoints()
        f.lure:SetPoint("LEFT", f.cast or f, f.cast and "RIGHT" or "LEFT", GAP, 0)
        local left = MF:LureTimeLeft()
        if left and left > 0 and f.lureCD then
            -- A fresh lure: its time jumps up. Remember the full length so the ring runs down from it
            if not self.lureDur or left > (self.lureLeft or 0) + 2 then self.lureDur = math.max(600, left) end
            self.lureLeft = left
            local dur = math.max(self.lureDur, left)
            if math.abs((self.lureStart or 0) - (GetTime() - (dur - left))) > 1 then
                self.lureStart = GetTime() - (dur - left)
                f.lureCD:SetCooldown(self.lureStart, dur)
            end
            f.lureCD:Show()
            f.lureTime:SetText(MF:FormatClock(left))
            f.lureTime:SetTextColor(left < 60 and 1 or 0.4, left < 60 and 0.4 or 0.9, 0.4)
        else
            if f.lureCD then f.lureCD:Hide() end
            self.lureDur, self.lureLeft, self.lureStart = nil, nil, nil
            f.lureTime:SetText("")
        end
    end
    f.pole:ClearAllPoints()
    f.pole:SetPoint("LEFT", f.lure or f.cast or f, "RIGHT", GAP, 0)
    local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", 16)
    f.pole.icon:SetTexture(tex or FISHING_ICON)
    local x = -16
    for _, b in ipairs({ f.journal, f.volume, f.stop, f.share }) do
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, y - 10)
            x = x - BUTTON - GAP
        end
    end
    y = y - 46
    f:SetHeight(-y + 4)
    -- The Fishing Log's board stays the same size as ours, underneath: things it anchors to its
    -- edges (the cast feedback strip below it) then sit beside ours
    if math.abs((old:GetHeight() or 0) - f:GetHeight()) > 0.5 then
        local left, top = old:GetLeft(), old:GetTop()
        if left and top and old:GetNumPoints() > 0 and select(1, old:GetPoint(1)) ~= "TOPLEFT" then
            old:ClearAllPoints()
            old:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        old:SetHeight(f:GetHeight())
    end
    if math.abs((old:GetWidth() or 0) - WIDTH) > 0.5 then old:SetWidth(WIDTH) end
    f.title:SetWidth(WIDTH - 140)
    f.sub:SetWidth(WIDTH - 140)
    f:Show()
end

ns:OnSetup("board", function(tfl)
    MF = tfl
    old = MF.boardFrame or _G.TheFishingLogBoard
    if not (old and MF.UpdateBoard and MF.BoardOpen and MF.FishingSkill and MF.SessionElapsed) then return end
    local function Go()
        Build()
        Silence()
        Adopt()
        -- The Fishing Log stops drawing its own board (and so its frenzy bubbles) and asks us instead
        MF.boardPresenter = function() B:Update() end
        MF.boardVolume = f.volume
        if old.frenzyEffect then
            old.frenzyEffect:SetScript("OnUpdate", nil)
            old.frenzyEffect:Hide()
        end
        if MF:BoardOpen() then B:Update() end
    end
    if InCombatLockdown() then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(self) self:UnregisterAllEvents() Go() end)
    else
        Go()
    end
end)
