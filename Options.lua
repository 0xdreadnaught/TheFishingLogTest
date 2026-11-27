-- Options: the settings panel (Esc > Options > AddOns > The Fishing Log)
-- and the minimap button.
local _, MF = ...

local minimapButton

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------

local function PositionMinimapButton()
    local angle = math.rad(MF.db.settings.minimapAngle or 220)
    local radius = Minimap:GetWidth() / 2 + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function MinimapTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("The Fishing Log")
    local xp = MF.cdb.profile.xp
    local _, rank = MF:RankFor(xp)
    GameTooltip:AddDoubleLine("Rank", ("%s (%d XP)"):format(rank, xp), 1, 1, 1, 1, 0.82, 0)

    local spot = MF:CurrentSpot()
    local active, secs = MF:FrenzyPresentationState(spot.key)
    GameTooltip:AddDoubleLine(spot.name, active and ("Frenzy! %s left"):format(MF:FormatClock(secs))
        or (secs and ("Frenzy in %s"):format(MF:FormatClock(secs)) or "No fishing location recorded"), 1, 1, 1, 1, 0.5, 0)
    local king = MF:King(spot.key)
    if king then
        GameTooltip:AddDoubleLine("King", ("%s (%s)"):format(MF:ShortName(king.h), MF:Weight(king.w)), 1, 1, 1, 1, 0.82, 0)
    end
    GameTooltip:AddDoubleLine("Bounty", MF:BountyText("day"), 1, 1, 1, 1, 1, 1)
    local event = MF:NextSignedEvent()
    if event then
        GameTooltip:AddDoubleLine("Next event", ("%s - %s"):format(event.title,
            date("%a %H:%M", event.startsAt)), 1, 1, 1, 0.4, 0.8, 1)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100Click|r board   |cffffd100Right-click|r journal   |cffffd100Shift-click|r options",
        0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "TheFishingLogMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\Trade_Fishing")
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            MF:ToggleJournal()
        elseif IsShiftKeyDown() then
            MF:OpenOptions()
        else
            MF:ToggleBoard()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            MF.db.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PositionMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", MinimapTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b.icon = icon
    minimapButton = b
    PositionMinimapButton()
end

function MF:UpdateMinimapButton()
    if minimapButton then minimapButton:SetShown(self.db.settings.minimap) end
end

-- The icon glows orange while a feeding frenzy is on at your spot.
MF:OnTick(function(self)
    if not minimapButton or not minimapButton:IsShown() then return end
    local active = self:FrenzyPresentationState(self:SpotKey())
    if active ~= minimapButton.frenzy then
        minimapButton.frenzy = active
        minimapButton.icon:SetVertexColor(active and 1 or 1, active and 0.6 or 1, active and 0.2 or 1)
    end
end)

------------------------------------------------------------------------
-- Settings panel
------------------------------------------------------------------------

-- Names shown in Esc > Options > Key Bindings.
BINDING_HEADER_THEFISHINGLOG = "The Fishing Log"
BINDING_NAME_THEFISHINGLOG_JOURNAL = "Toggle the Angler's Journal"
BINDING_NAME_THEFISHINGLOG_BOARD = "Toggle the board"
BINDING_NAME_THEFISHINGLOG_SETTINGS = "Toggle settings"
BINDING_NAME_THEFISHINGLOG_HERE = "Open Fishing here"
BINDING_NAME_THEFISHINGLOG_FINDER = "Open Find waters"
_G["BINDING_NAME_CLICK TheFishingLogLureButton:LeftButton"] = "Put your best lure on"
BINDING_NAME_THEFISHINGLOG_LUREMENU = "Open the lure menu"
BINDING_NAME_THEFISHINGLOG_POLE = "Swap fishing pole / weapon"
BINDING_NAME_THEFISHINGLOG_STOP = "Stop the fishing log"

-- The settings window from a key: shut if it's open
function MF:ToggleSettings()
    local S = self.Rework and self.Rework.Settings
    if S then S:Toggle() else self:OpenOptions() end
end

-- The game's AddOns options keep an entry for The Fishing Log, so it's found where people look.
-- The settings themselves are in their own window (Rework/Settings.lua): this page says so and
-- opens it. It used to hold every switch in one long column, and the Appearance page beside it.
local function CreatePanel()
    local panel = CreateFrame("Frame")
    panel.name = "The Fishing Log"
    local title = MF:CreateText(panel, "GameFontNormalLarge", "TOPLEFT", 16, -16)
    title:SetText("The Fishing Log")
    local note = MF:CreateText(panel, "GameFontHighlight", "TOPLEFT", 16, -46)
    note:SetWidth(520)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText("The Fishing Log's settings have a window of their own, with a search box and a page "
        .. "for each part: fishing, the board, alerts, sounds, matches, maps and more.")
    local open = MF:CreateButton(panel, "Open settings", 160, function()
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then
            pcall(HideUIPanel, SettingsPanel)
        end
        MF:OpenOptions()
    end)
    open:SetPoint("TOPLEFT", 16, -96)
    local how = MF:CreateText(panel, "GameFontDisableSmall", "TOPLEFT", 16, -132)
    how:SetWidth(520)
    how:SetJustifyH("LEFT")
    how:SetText("Also /tfl config, or shift-click the minimap button. Type /tfl for every command.")
    panel.open = open
    return panel
end

-- Optional: if another addon supplies LibDataBroker, offer a launcher so
-- broker bars can host us instead of the minimap button.
local function RegisterBroker()
    if not LibStub then return end
    local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb then return end
    ldb:NewDataObject("TheFishingLog", {
        type = "launcher",
        icon = "Interface\\Icons\\Trade_Fishing",
        label = "The Fishing Log",
        OnClick = function(_, button)
            if button == "RightButton" then
                MF:ToggleJournal()
            else
                MF:ToggleBoard()
            end
        end,
        OnTooltipShow = function(tooltip)
            local xp = MF.cdb.profile.xp
            local _, rank = MF:RankFor(xp)
            tooltip:AddLine("The Fishing Log")
            tooltip:AddLine(("%s - %d XP"):format(rank, xp), 1, 0.82, 0)
            tooltip:AddLine("Click: board   Right-click: journal", 0.8, 0.8, 0.8)
        end,
    })
end

MF:On("TFL_INIT", function(self)
    CreateMinimapButton()
    self:UpdateMinimapButton()
    pcall(RegisterBroker)

    local panel = CreatePanel()
    self.optionsPanel = panel
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        self.optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        self.optionsPanel = panel
    end
end)

-- The settings window, on a page if one is named ("sounds", "maps"...)
function MF:OpenOptions(page)
    local S = self.Rework and self.Rework.Settings
    if S then S:Show(page) return end
    if self.optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.optionsCategory:GetID())
    else
        self:Print("Options: Esc > Options > AddOns > The Fishing Log")
    end
end

MF:Command({ "config", "options", "settings" }, "Other", "/tfl config - settings", function(self) self:OpenOptions() end)
