-- Small, static ripple markers shared by both map implementations.
local _, MF = ...
local MEDIA = "Interface\\AddOns\\" .. MF.ADDON .. "\\Media\\Markers\\"
local FISH = { ["firefin snapper school"] = 6359, ["greater sagefish school"] = 21153,
    ["oily blackmouth school"] = 6358, ["sagefish school"] = 21071,
    ["school of deviate fish"] = 6522, ["stonescale eel swarm"] = 13422,
    ["school of whimsyfin"] = 251524 }
local COLORS = { Fish = {0.36,0.84,0.85}, Wreckage = {0.88,0.76,0.51},
    Oil = {0.74,0.65,0.91}, Frenzy = {1,0.66,0.24} }

function MF:MapMarkerSize(surface)
    local mini = surface == "minimap"
    local value = self.db.settings[mini and "poolMinimapSize" or "mapMarkerSize"]
    local fallback, low, high = mini and 12 or 16, mini and 8 or 12, mini and 18 or 24
    if type(value) ~= "number" or value ~= value then value = fallback end
    return math.max(low, math.min(high, math.floor(value + 0.5)))
end

function MF:PoolMarkerType(name)
    local lower = strtrim(name or ""):lower()
    if lower:find("wreckage", 1, true) or lower:find("debris", 1, true) then return "Wreckage" end
    if lower:find("oil spill", 1, true) then return "Oil" end
    return "Fish"
end

function MF:PoolTooltipIcon(name)
    local id = FISH[(name or ""):lower()]
    return id and self:FishIcon(id) or (MEDIA .. self:PoolMarkerType(name) .. "Marker.tga")
end

function MF:MapMarkerColor(kind)
    return unpack(COLORS[kind] or COLORS.Fish)
end

function MF:LeaveMapMarker(pin)
    self:SetMapMarkerHover(pin, false)
    if GameTooltip and type(GameTooltip.GetOwner) == "function" and GameTooltip:GetOwner() == pin then
        GameTooltip:Hide()
    end
end

function MF:MapMarkerLegend()
    local parts = {}
    for _, kind in ipairs({ "Fish", "Wreckage", "Oil", "Frenzy" }) do
        parts[#parts + 1] = "|T" .. MEDIA .. kind .. "Marker.tga:16:16|t " .. kind
    end
    return table.concat(parts, "   ")
end

function MF:SetMapMarkerHover(pin, hovered)
    pin.markerHovered = hovered and true or false
    -- Map frame pools can reset a newly created pin before OnLoad/OnAcquired.
    -- Cleanup must work before decoration has allocated its textures.
    local c = COLORS[pin.markerType] or COLORS.Fish
    if pin.ring and hovered then
        pin.ring:SetVertexColor(math.min(1,c[1]*0.45+0.55), math.min(1,c[2]*0.45+0.55), math.min(1,c[3]*0.45+0.55))
    elseif pin.ring then pin.ring:SetVertexColor(unpack(c)) end
    if pin.glow then pin.glow:SetAlpha(hovered and 0.35 or 0) end
end

function MF:StyleMapMarker(pin, kind, surface)
    if not pin.markerDisc then
        pin.markerDisc = pin:CreateTexture(nil, "BACKGROUND")
        pin.markerDisc:SetAllPoints()
        pin.markerDisc:SetTexture(MEDIA .. "Disc.tga")
        pin.ring = pin:CreateTexture(nil, "BORDER")
        pin.ring:SetAllPoints()
        pin.ring:SetTexture(MEDIA .. "Ring.tga")
        pin.art = pin:CreateTexture(nil, "ARTWORK")
        pin.art:SetAllPoints()
        pin.art:SetVertexColor(1,0.96,0.84)
        pin.glow = pin:CreateTexture(nil, "OVERLAY")
        pin.glow:SetAllPoints()
        pin.glow:SetTexture(MEDIA .. "Ring.tga")
        pin.glow:SetBlendMode("ADD")
        pin:EnableMouse(true)
        -- A little more room to hover, without a larger visible marker.
        if pin.SetHitRectInsets then pin:SetHitRectInsets(-2,-2,-2,-2) end
    end
    pin.markerType, pin.markerSurface = COLORS[kind] and kind or "Fish", surface
    -- Active bonuses must remain prominent beside the smaller historical pools.
    local size = pin.markerType == "Frenzy" and 33 or self:MapMarkerSize(surface)
    pin:SetSize(size,size)
    pin.art:SetTexture(MEDIA .. pin.markerType .. ".tga")
    self:SetMapMarkerHover(pin, pin.markerHovered)
    self:UpdateMapMarkerEffects(pin)
end

function MF:UpdateMapMarkerEffects(pin)
    local active = pin.markerType == "Frenzy" and not self.db.settings.reducedMotion
    if active and not pin.frenzyPulse then
        local aura = pin:CreateTexture(nil, "OVERLAY")
        aura:SetPoint("TOPLEFT", pin, "TOPLEFT", -3, 3)
        aura:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 3, -3)
        aura:SetTexture(MEDIA .. "Ring.tga")
        aura:SetVertexColor(unpack(COLORS.Frenzy))
        aura:SetBlendMode("ADD")
        local pulse = aura:CreateAnimationGroup()
        pulse:SetLooping("REPEAT")
        for i, values in ipairs({{0.08,0.55},{0.55,0.08}}) do
            local fade = pulse:CreateAnimation("Alpha")
            fade:SetOrder(i)
            fade:SetDuration(1.1)
            fade:SetFromAlpha(values[1])
            fade:SetToAlpha(values[2])
            fade:SetSmoothing("IN_OUT")
        end
        pin.frenzyAura, pin.frenzyPulse = aura, pulse
    end
    if pin.frenzyPulse then
        pin.frenzyPulse:Stop()
        pin.frenzyAura:SetShown(active)
        if active then pin.frenzyPulse:Play() end
    end
end

function MF:SetMapMarkerSize(surface, value)
    local key = surface == "minimap" and "poolMinimapSize" or "mapMarkerSize"
    self.db.settings[key] = value
    self.db.settings[key] = self:MapMarkerSize(surface)
    self:RefreshPoolPins()
    self:RefreshMapPins()
end

MF:Command("markers", "Other", "/tfl markers [world|minimap] [pixels] - map marker sizes", function(self, args)
    if args[1] == "reset" then
        self:SetMapMarkerSize("world",16) self:SetMapMarkerSize("minimap",12)
    elseif (args[1] == "world" or args[1] == "minimap") and tonumber(args[2]) then
        self:SetMapMarkerSize(args[1],tonumber(args[2]))
    end
    self:Print(("Map markers: world %d px, minimap %d px. /tfl config has size controls; /tfl markers reset restores defaults.")
        :format(self:MapMarkerSize("world"),self:MapMarkerSize("minimap")))
end)
