local _, MF = ...

------------------------------------------------------------------------
-- Volume, on the fly
--
-- The game's own volume sliders are four clicks deep, behind a window that
-- covers the water you're watching. Fishing is where you most often want
-- the sound changed - a boat goes by, a guildmate starts talking, the bite
-- is lost under the music - so the board carries a small panel with every
-- volume and its switch, which you can drag while the line is out.
--
-- It writes the game's own settings, nothing of ours. A volume you change
-- here mid-cast is yours: Louder splash sees it changed and leaves it be
-- when the line comes in, just as if you'd used the game's window.
------------------------------------------------------------------------

local ROWS = {
    { label = "Master",        volume = "Sound_MasterVolume",   switch = "Sound_EnableAllSound" },
    { label = "Sound effects", volume = "Sound_SFXVolume",      switch = "Sound_EnableSFX",
      tip = "The splash when a fish bites is a sound effect." },
    { label = "Music",         volume = "Sound_MusicVolume",    switch = "Sound_EnableMusic" },
    { label = "Ambience",      volume = "Sound_AmbienceVolume", switch = "Sound_EnableAmbience",
      tip = "Wind, water, crowds." },
    { label = "Dialog",        volume = "Sound_DialogVolume",   switch = "Sound_EnableDialog",
      tip = "Characters and creatures speaking." },
}

local WIDTH, ROW_HEIGHT, TOP = 270, 30, -40
local panel

local function Read(cvar)
    local value = GetCVar(cvar)
    if value == nil or MF:IsSecret(value) then return nil end
    return tonumber(value)
end

local function Write(cvar, value)
    pcall(SetCVar, cvar, value)
end

-- The bar is drawn the way the journal's scroll bar is: a flat track and a
-- flat thumb. The stock slider templates error on this client when they
-- aren't inside the frames they expect.
local function CreateBar(parent)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("HORIZONTAL")
    bar:SetHeight(14)
    bar:SetMinMaxValues(0, 100)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(8, 14)
    thumb:SetColorTexture(0.85, 0.72, 0.38, 1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.15)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("LEFT", track, "LEFT")
    bar.fill:SetHeight(4)
    bar.fill:SetColorTexture(0.85, 0.72, 0.38, 0.6)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.max(0, math.min(100, (self:GetValue() or 0) + delta * 5)))
    end)
    return bar
end

local function ShowFill(bar, value)
    local width = (bar:GetWidth() or 0) * (value or 0) / 100
    bar.fill:SetWidth(math.max(0.01, width))
end

-- What the game says now. A slider being dragged is left alone, so the
-- refresh can't snatch it back from under the mouse.
local function Refresh()
    if not panel then return end
    panel.refreshing = true
    for _, row in ipairs(panel.rows) do
        local on = Read(row.def.switch)
        row.check:SetChecked(on ~= 0)
        local volume = Read(row.def.volume)
        if volume and not row.bar.held then
            local value = math.floor(volume * 100 + 0.5)
            if math.abs((row.bar:GetValue() or -1) - value) >= 1 then row.bar:SetValue(value) end
            ShowFill(row.bar, value)
            row.number:SetText(value .. "%")
        end
        local dim = on == 0 and 0.45 or 1
        row.label:SetAlpha(dim)
        row.bar:SetAlpha(dim)
        row.number:SetAlpha(dim)
    end
    local music = panel.rows[3]
    music.label:SetText(MF.db and MF.db.musicVolumeRestore ~= nil
        and "Music |cff808080(pole)|r" or "Music")
    if panel.splash then panel.splash:SetChecked(MF.db and MF.db.settings.loudSplash == true) end
    panel.refreshing = nil
end
MF.RefreshVolumePanel = Refresh

local function Tip(frame, title, line)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        if line then GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateRow(index, def)
    local y = TOP - (index - 1) * ROW_HEIGHT
    local row = { def = def }

    row.check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("TOPLEFT", 10, y + 4)
    row.check:SetScript("OnClick", function(self)
        Write(def.switch, self:GetChecked() and "1" or "0")
        Refresh()
    end)
    Tip(row.check, def.label .. " on or off", def.tip)

    row.label = MF:CreateText(panel, "GameFontHighlightSmall", "TOPLEFT", 34, y)
    row.label:SetText(def.label)

    row.number = MF:CreateText(panel, "GameFontHighlightSmall")
    row.number:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, y)
    row.number:SetJustifyH("RIGHT")
    row.number:SetWidth(36)

    row.bar = CreateBar(panel)
    row.bar:SetPoint("TOPLEFT", 128, y + 1)
    row.bar:SetPoint("TOPRIGHT", -52, y + 1)
    row.bar:SetScript("OnMouseDown", function(self) self.held = true end)
    row.bar:SetScript("OnMouseUp", function(self) self.held = nil end)
    row.bar:SetScript("OnValueChanged", function(self, value)
        value = math.floor((value or 0) + 0.5)
        ShowFill(self, value)
        row.number:SetText(value .. "%")
        if panel.refreshing then return end
        Write(def.volume, ("%.2f"):format(value / 100))
    end)
    return row
end

local function CreateVolumePanel()
    local height = -TOP + #ROWS * ROW_HEIGHT + 34
    panel = MF:CreatePanel("TheFishingLogVolume", WIDTH, height,
        { backdrop = "tooltip", strata = "DIALOG", escCloses = true, close = true, title = "Volume" })
    panel:SetClampedToScreen(true)
    panel.rows = {}
    for i, def in ipairs(ROWS) do panel.rows[i] = CreateRow(i, def) end

    -- The one TFL switch that belongs with the volumes.
    panel.splash = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.splash:SetSize(22, 22)
    panel.splash:SetPoint("BOTTOMLEFT", 10, 8)
    panel.splash.text = MF:CreateText(panel, "GameFontNormalSmall")
    panel.splash.text:SetPoint("LEFT", panel.splash, "RIGHT", 2, 0)
    panel.splash.text:SetText("Louder splash while the line is out")
    panel.splash:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        MF.db.settings.loudSplash = on
        if not on and MF.RestoreSplashVolume then MF:RestoreSplashVolume() end
        Refresh()
    end)
    Tip(panel.splash, "Louder splash",
        "While you're casting, switches sound effects on and turns sound effects and master "
        .. "up to full, then puts them back. More under Options.")

    -- The game's volumes can change under us: Louder splash, the music
    -- going quiet with a pole, the game's own window. Twice a second while
    -- the panel is open is plenty and costs nothing while it's shut.
    local since = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.5 then return end
        since = 0
        Refresh()
    end)
    panel:SetScript("OnShow", Refresh)
end

function MF:ToggleVolumePanel(anchor)
    if not panel then CreateVolumePanel() end
    if panel:IsShown() then panel:Hide() return end
    panel:ClearAllPoints()
    if anchor then
        panel:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 12, 14)
    else
        panel:SetPoint("CENTER")
    end
    panel:Show()
    Refresh()
end

MF:Command({ "volume", "vol" }, "Solo", "/tfl volume - open the volume sliders",
    function(self) self:ToggleVolumePanel(self.BoardVolumeButton and self:BoardVolumeButton()) end)
