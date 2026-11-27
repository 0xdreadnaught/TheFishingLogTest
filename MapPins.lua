-- MapPins: which water is worth walking to, on the map you're looking at.
--
-- A frenzy is 1.2x weight and double the specimen chance, and specimens
-- are how records get set - so it is worth knowing about, and until now
-- the only way to find out was to stand at the water with the board open.
-- That tells the person already fishing, who did not need telling.
--
-- "Is a frenzy up near me" is the wrong question and the arithmetic says
-- so: a water is live 25 minutes in every 120, so in a zone with ten
-- known waters something is in frenzy 97% of the time. The answer is
-- always yes and it carries nothing. *Which* water, and how long it has
-- left, is the whole of the information.
--
-- So this is pull, not push. Nothing is announced; the map you open says
-- what is happening on it. Open Stonetalon from Ashenvale and you are
-- looking at Stonetalon's frenzies, because the question is always about
-- the place you are thinking of going.
local _, MF = ...

local PIN_SIZE = 33
local REFRESH = 10            -- seconds; a frenzy turns over slowly

-- Zones you have fished (used by geography tools, not static frenzy visibility)
--
-- A position is only ours when we caught something at it - a position
-- that arrived with somebody else's record is not marked - so this is a
-- precise answer to "have I been there", and the addon already had it.
--
-- Zone rather than water, deliberately. Marking only the exact waters
-- you have stood at would hide a frenzy on the far side of a zone you
-- know perfectly well, and "areas I've discovered" is a zone-sized idea.
-- Fish anywhere in the Wetlands and the Wetlands opens up.
function MF:FishedMaps()
    local maps = {}
    if not self.db then return maps end
    for key, where in pairs(self.db.spotWhere) do
        if where.mine and where.map and self:ValidSpotPosition(key,where.map,where.x,where.y) then maps[where.map] = true end
    end
    return maps
end

function MF:FrenziesOnMap(map)
    local out = {}
    if not map or not self.db then return out end
    -- Shipped locations are available on a clean launch profile. Shared
    -- records and community candidates cannot add or move these pins.
    for _,where in ipairs(self.FRENZY_LOCATIONS) do
        if where.map == map then
            local active, left = self:FrenzyState(where.id)
            if active then
                out[#out + 1] = { key = where.id, left = left, x = where.x, y = where.y }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.left ~= b.left then return a.left < b.left end
        return a.key < b.key
    end)
    return out
end

-- Drawing, the way the map wants it done
--
-- The first two attempts parented a frame to the map's canvas and placed
-- it by arithmetic on the canvas width. It very nearly worked: pins sat
-- in the right place and answered the mouse. They were also invisible in
-- about half the zones, because the map keeps its own stack of overlays
-- and a hand-made child sits among them rather than above them. Raising
-- the frame level by hand did nothing, because the map re-applies levels
-- itself every time it refreshes and overwrites yours.
--
-- The map has a system for this and it has to be used. A pin template is
-- registered with WorldMapFrame.pinPools, a data provider is added to the
-- map, and a pin asks for a named frame level - PIN_FRAME_LEVEL_AREA_POI,
-- the one Blizzard's own points of interest use. The map then owns the
-- placing, the scaling and the layering, which is the whole of what kept
-- going wrong. (The technique is how HereBeDragons-Pins does it, which is
-- what GatherLite and most of the gathering addons run on.)
local TEMPLATE = "TheFishingLogFrenzyPin"
local provider, pinMixin
local layerControls

local function ClampMapPosition(value)
    return math.max(0, math.min(1, value))
end

local function PlaceLayerControls(controls, viewport, position)
    controls:ClearAllPoints()
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number"
        and position.x == position.x and position.y == position.y then
        local width = math.max(0, viewport:GetWidth() - controls:GetWidth())
        local height = math.max(0, viewport:GetHeight() - controls:GetHeight())
        controls:SetPoint("BOTTOMLEFT", viewport, "BOTTOMLEFT",
            ClampMapPosition(position.x) * width, ClampMapPosition(position.y) * height)
    else
        controls:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", -36, 12)
    end
end

local function StopLayerDrag()
    if not layerControls.dragging then return end
    layerControls.dragging = nil
    layerControls:StopMovingOrSizing()
    local viewport = layerControls:GetParent()
    local left, bottom = layerControls:GetLeft(), layerControls:GetBottom()
    local mapLeft, mapBottom = viewport:GetLeft(), viewport:GetBottom()
    if left and bottom and mapLeft and mapBottom then
        local width = math.max(1, viewport:GetWidth() - layerControls:GetWidth())
        local height = math.max(1, viewport:GetHeight() - layerControls:GetHeight())
        MF.db.settings.mapLayerPosition = {
            x = ClampMapPosition((left - mapLeft) / width),
            y = ClampMapPosition((bottom - mapBottom) / height),
        }
    end
    PlaceLayerControls(layerControls, viewport, MF.db.settings.mapLayerPosition)
end

function MF:RefreshMapLayerControls()
    local map = _G.WorldMapFrame
    if not map or type(map.HookScript) ~= "function" or not self.db then return end
    -- The outer map frame includes the quest pane in compact mode. Use
    -- the visible map viewport, not its zooming/panning canvas or outer frame.
    local viewport = map.ScrollContainer or map
    -- Off in options: no Frenzies/Pools box on the map at all (the marks keep their own settings)
    if self.db.settings.mapLayerButtons == false then
        if layerControls then layerControls:Hide() end
        return
    end
    if layerControls then layerControls:Show() end
    if not layerControls then
        layerControls = CreateFrame("Frame", nil, viewport, "BackdropTemplate")
        layerControls:SetSize(210, 34)
        layerControls:SetFrameStrata("HIGH")
        layerControls:SetMovable(true)
        layerControls:SetClampedToScreen(true)
        layerControls:SetScript("OnHide", StopLayerDrag)
        layerControls:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        layerControls:SetBackdropColor(unpack(self.FILL_READING))
        local function Button(label, key, x, refresh)
            local button = MF:CreateButton(layerControls, label, 96, function()
                MF.db.settings[key] = MF.db.settings[key] == false
                refresh()
                MF:RefreshMapLayerControls()
            end)
            button:SetPoint("LEFT", x, 0)
            button:RegisterForDrag("RightButton")
            button:SetScript("OnDragStart", function()
                GameTooltip:Hide()
                layerControls.dragging = true
                layerControls:StartMoving()
            end)
            button:SetScript("OnDragStop", StopLayerDrag)
            button:SetScript("OnEnter", function()
                GameTooltip:SetOwner(button, "ANCHOR_TOP")
                GameTooltip:AddLine(label .. " on the world map")
                GameTooltip:AddLine("Toggle visibility. Recorded data is kept.", 0.63, 0.63, 0.63, true)
                GameTooltip:AddLine("Right-drag either button to move both.", 0.63, 0.63, 0.63, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return button
        end
        layerControls.frenzy = Button("Frenzies", "mapFrenzy", 6, function() MF:RefreshMapPins() end)
        layerControls.pools = Button("Pools", "poolWorldMap", 108, function() MF:RefreshPoolPins() end)
        map:HookScript("OnShow", function() MF:RefreshMapLayerControls() end)
        viewport:HookScript("OnSizeChanged", function() MF:RefreshMapLayerControls() end)
    end
    if not layerControls.dragging then
        if layerControls:GetParent() ~= viewport then layerControls:SetParent(viewport) end
        PlaceLayerControls(layerControls, viewport, self.db.settings.mapLayerPosition)
    end
    layerControls.frenzy:SetText("Frenzies: " .. (self.db.settings.mapFrenzy ~= false and "On" or "Off"))
    layerControls.pools:SetText("Pools: " .. (self.db.settings.poolWorldMap ~= false and "On" or "Off"))
end

-- Everything the map provides is checked for before it is used: this
-- addon runs on a client that is Classic content on a Midnight-era API,
-- and a frenzy mark is not worth an error on login if any of it moves.
local function MapReady()
    local map = _G.WorldMapFrame
    return type(map) == "table"
        and type(map.AddDataProvider) == "function"
        and type(map.pinPools) == "table"
        and type(_G.CreateFromMixins) == "function"
        and type(_G.MapCanvasDataProviderMixin) == "table"
        and type(_G.MapCanvasPinMixin) == "table"
end

function MF:MapPinDiagnostics()
    return ("API ready=%s; provider=%s; last refresh error=%s"):format(
        tostring(MapReady()),tostring(provider~=nil),tostring(self.mapPinLastError or "none"))
end

local function Decorate(pin)
    MF:StyleMapMarker(pin, "Frenzy", "world")
    if pin.markerTooltip then return end
    pin.markerTooltip = true
    pin:SetScript("OnShow", function(self) MF:UpdateMapMarkerEffects(self) end)
    pin:SetScript("OnHide", function(self)
        if self.frenzyPulse then self.frenzyPulse:Stop() end
        MF:LeaveMapMarker(self)
    end)

    pin:SetScript("OnEnter", function(self)
        if not self.key then return end
        local active, remaining = MF:FrenzyState(self.key)
        local water=MF:StaticFrenzyByID(self.key)
        if not active or not water then MF:RefreshMapPins() return end
        self.left = remaining
        MF:SetMapMarkerHover(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(water.name, 1, 0.82, 0)
        GameTooltip:AddLine(("Feeding frenzy - %s left"):format(
            MF:FormatClock(self.left or 0)), 1, 0.5, 0)
        GameTooltip:AddLine("Heavier fish and double the specimen chance.",
            0.63, 0.63, 0.63, true)
        GameTooltip:AddLine("Fish within 25 yards of the documented access point.",0.63,0.63,0.63,true)
        local where=MF:SpotPosition(self.key)
        if where and MF:SpotMapFits(self.key,where.map) == nil then
            GameTooltip:AddLine(MF:SpotLocallyObserved(self.key) and "Locally observed fishing location." or "Reported location; geography unverified.",0.63,0.63,0.63,true)
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function(self) MF:LeaveMapMarker(self) end)
end

local function Setup()
    if provider or not MapReady() then return provider end
    local map = _G.WorldMapFrame

    pinMixin = CreateFromMixins(_G.MapCanvasPinMixin)

    function pinMixin:OnLoad()
        -- The named level is the entire point. Asking for the one the
        -- game's own points of interest use puts the mark above the
        -- overlays that were burying it.
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end
        Decorate(self)
    end

    function pinMixin:OnAcquired(live)
        Decorate(self)
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        self.key, self.left = live.key, live.left
        self:SetPosition(live.x, live.y)
        self:Show()
    end

    function pinMixin:OnReleased()
        MF:LeaveMapMarker(self)
        self.key, self.left = nil, nil
    end

    -- Blizzard calls this on pins in combat on some versions; a frenzy
    -- mark has nothing to pass through.
    pinMixin.SetPassThroughButtons = function() end

    local pool
    if _G.CreateUnsecuredRegionPoolInstance then
        pool = _G.CreateUnsecuredRegionPoolInstance(TEMPLATE)
    elseif _G.CreateFramePool then
        pool = _G.CreateFramePool("FRAME")
    end
    if not pool then return nil end

    local canvas = type(map.GetCanvas) == "function" and map:GetCanvas() or nil
    pool.parent = canvas
    pool.createFunc = function()
        local pin = CreateFrame("Frame", nil, canvas)
        pin:SetSize(PIN_SIZE, PIN_SIZE)
        return Mixin(pin, pinMixin)
    end
    pool.resetFunc = function(_, pin)
        pin:Hide()
        pin:ClearAllPoints()
        if pin.OnReleased then pin:OnReleased() end
        pin.pinTemplate, pin.owningMap = nil, nil
    end
    -- The names these two had before 11.x, since this client is neither.
    pool.creationFunc, pool.resetterFunc = pool.createFunc, pool.resetFunc
    map.pinPools[TEMPLATE] = pool

    provider = CreateFromMixins(_G.MapCanvasDataProviderMixin)

    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    end

    function provider:RefreshAllData()
        self:RemoveAllData()
        if not MF.db or MF.db.settings.mapFrenzy == false then return end
        local shown = self:GetMap():GetMapID()
        for _, live in ipairs(MF:FrenziesOnMap(shown)) do
            self:GetMap():AcquirePin(TEMPLATE, live)
        end
    end

    map:AddDataProvider(provider)
    return provider
end

-- The map redraws itself on open and on every zone change, so there is
-- nothing to hook: asking the provider to refresh is the whole of it.
function MF:RefreshMapPins()
    if not Setup() then return end
    local ok,err=pcall(provider.RefreshAllData, provider)
    self.mapPinLastError=not ok and tostring(err):sub(1,240) or nil
end

-- A frenzy runs 25 minutes, so this only has to keep up slowly, and only
-- while somebody is actually looking at the map.
MF:OnTick(function(self)
    local map = _G.WorldMapFrame
    if type(map) ~= "table" or type(map.IsShown) ~= "function" then return end
    local ok, shown = pcall(map.IsShown, map)
    if not ok or not shown then return end
    self:RefreshMapLayerControls()
    local now = GetTime()
    if self.mapPinsAt and now - self.mapPinsAt < REFRESH then return end
    self.mapPinsAt = now
    self:RefreshMapPins()
end)

MF:On("TFL_INIT", function(self)
    Setup()
    self:RefreshMapLayerControls()
end)

MF:Command({ "mappins", "pins" }, "Other",
    "/tfl mappins - frenzy marks on the world map",
    function(self)
        local s = self.db.settings
        s.mapFrenzy = s.mapFrenzy == false
        self:Print(("Frenzy marks on the world map are |cffffd100%s|r."):format(
            s.mapFrenzy and "on" or "off"))
        self:RefreshMapPins()
    end)
