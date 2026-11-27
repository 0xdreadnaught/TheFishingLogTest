-- Shared Fishing Log pool atlas, independent of other gathering addons.
-- Pins are historical locations, not evidence that a pool is currently present.
local _, MF = ...
local function print(...) MF:PrintChat(...) end
local pins, frames = nil, {}

function MF:PoolNodes(mapID)
    local out = {}
    for _, node in ipairs(self.db.poolAtlas or {}) do
        if node.map == mapID then out[#out + 1] = node end
    end
    table.sort(out, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
    return out
end

local function Library()
    if not LibStub or type(LibStub.GetLibrary) ~= "function" then return end
    local ok, library = pcall(LibStub.GetLibrary, LibStub, "HereBeDragons-Pins-2.0", true)
    if ok and library and type(library.AddMinimapIconMap) == "function"
        and type(library.AddWorldMapIconMap) == "function" then return library end
end

function MF:PoolPinDiagnostics()
    return ("library ready=%s; renderer=%s; nodes queued=%s; frames=%d"):format(
        tostring(Library()~=nil),tostring(pins~=nil),tostring(self.poolPinCount or 0),#frames)
end

-- One pin per spawn point
--
-- A pool spawn point picks a school at random each time it comes back,
-- so one stretch of shore is saved as Firefin, then Oily Blackmouth, then
-- Stonescale, then wreckage - four pins on top of each other, and a coast
-- that reads as a smear. Every pool within SPOT_YARDS is one place, drawn
-- as one pin: the newest school's icon, a count when more than one has
-- been seen there, and the whole list on hover. Only the drawing groups
-- them; the atlas, and what is shared, keep every sighting as it was.
local SPOT_YARDS = 30

local function Spots(self, nodes)
    local order = {}
    for i, node in ipairs(nodes) do order[i] = node end
    table.sort(order, function(a, b) return (a.at or 0) > (b.at or 0) end)
    local spots = {}
    for _, node in ipairs(order) do
        local into
        for _, spot in ipairs(spots) do
            if self:PoolGap(node.map, spot.lead.x, spot.lead.y, node.x, node.y, SPOT_YARDS) <= 1 then
                into = spot break
            end
        end
        if not into then
            into = { map = node.map, lead = node, members = {}, types = {}, sx = 0, sy = 0 }
            spots[#spots + 1] = into
        end
        into.members[#into.members + 1] = node
        into.sx, into.sy = into.sx + node.x, into.sy + node.y
        local key = node.name:lower()
        local seen = into.types[key]
        if not seen or (node.at or 0) > (seen.at or 0) then into.types[key] = node end
    end
    for _, spot in ipairs(spots) do
        spot.x, spot.y = spot.sx / #spot.members, spot.sy / #spot.members
        local list = {}
        for _, node in pairs(spot.types) do list[#list + 1] = node end
        table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
        spot.list = list
        spot.mine = false
        for _, node in ipairs(spot.members) do spot.mine = spot.mine or node.mine end
    end
    return spots
end

local function Tooltip(self)
    local spot = self.spot
    if not spot then return end
    MF:SetMapMarkerHover(self, true)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local grey = 0.63
    if #spot.list == 1 then
        local node = spot.list[1]
        GameTooltip:AddLine("|T" .. MF:PoolTooltipIcon(node.name) .. ":18:18|t " .. node.name, 1, 0.82, 0)
        GameTooltip:AddLine("Known pool location", MF:MapMarkerColor(self.markerType))
        GameTooltip:AddLine("Last observed: " .. date("%d %b %Y %H:%M", node.at), grey, grey, grey)
    else
        GameTooltip:AddLine("Pool spawn point", 1, 0.82, 0)
        GameTooltip:AddLine(("%d kinds of pool seen here, newest first"):format(#spot.list),
            MF:MapMarkerColor(self.markerType))
        for _, node in ipairs(spot.list) do
            GameTooltip:AddDoubleLine("|T" .. MF:PoolTooltipIcon(node.name) .. ":16:16|t " .. node.name,
                date("%d %b %H:%M", node.at), 1, 1, 1, grey, grey, grey)
        end
    end
    GameTooltip:AddLine(spot.mine and "Observed here by you" or "Shared by Fishing Log anglers", grey, grey, grey)
    GameTooltip:AddLine("Availability unknown. Position may be approximate.", grey, grey, grey, true)
    GameTooltip:Show()
end

local function Frame(index, spot, surface)
    local kind = MF:PoolMarkerType(spot.lead.name)
    local f = frames[index]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        MF:StyleMapMarker(f, kind, surface)
        f.badge = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.badge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -3)
        f:SetScript("OnEnter", Tooltip)
        f:SetScript("OnLeave", function(self) MF:LeaveMapMarker(self) end)
        f:SetScript("OnHide", function(self)
            if self.markerHovered then MF:LeaveMapMarker(self) end
        end)
        frames[index] = f
    end
    f.spot, f.node = spot, spot.lead
    MF:StyleMapMarker(f, kind, surface)
    -- The count is for the world map; on the minimap it's clutter.
    f.badge:SetText(surface == "world" and #spot.list > 1 and tostring(#spot.list) or "")
    return f
end

function MF:RefreshPoolPins()
    if pins then
        pins:RemoveAllMinimapIcons(self)
        pins:RemoveAllWorldMapIcons(self)
    end
    for _, f in ipairs(frames) do f:Hide(); f.node = nil end
    pins = Library()
    self.poolPinCount = 0
    if not pins then return end
    local settings, index = self.db.settings, 0
    local playerMap = self:MapID()
    local map = _G.WorldMapFrame
    local shownMap = map and type(map.GetMapID) == "function" and map:GetMapID() or playerMap
    local maps = {}
    if settings.poolMinimap then maps[playerMap or 0] = true end
    if settings.poolWorldMap then maps[shownMap or 0] = true end
    for mapID in pairs(maps) do
        local nodes = self:PoolNodes(mapID)
        self.poolPinCount = self.poolPinCount + #nodes
        for _, spot in ipairs(Spots(self, nodes)) do
            if settings.poolMinimap and mapID == playerMap then
                index = index + 1
                pins:AddMinimapIconMap(self, Frame(index, spot, "minimap"), mapID, spot.x, spot.y, false, false)
            end
            if settings.poolWorldMap and mapID == shownMap then
                index = index + 1
                pins:AddWorldMapIconMap(self, Frame(index, spot, "world"), mapID, spot.x, spot.y, 0, "PIN_FRAME_LEVEL_AREA_POI")
            end
        end
    end
end

MF:On("TFL_LOGIN", function(self) self:RefreshPoolPins() end)
MF:On("ZONE_CHANGED_NEW_AREA", function(self) self.poolRefreshAt = nil end)
MF:OnTick(function(self)
    local map = _G.WorldMapFrame
    local shown = map and type(map.GetMapID) == "function" and map:GetMapID() or nil
    if self.poolShownMap == shown and self.poolRefreshAt and GetTime() - self.poolRefreshAt < 10 then return end
    self.poolShownMap, self.poolRefreshAt = shown, GetTime()
    self:RefreshPoolPins()
end)

MF:Command("pools", "Other", "/tfl pools [on|off|status|sync|horde|alliance] - shared fishing pool atlas", function(self, args)
    if args[1] == "horde" or args[1] == "alliance" then
        local side = args[1] == "horde" and "H" or "A"
        local label = side == "H" and "Horde" or "Alliance"
        local total, seen, zones = 0, 0, {}
        for _, node in ipairs(self.db.poolAtlas or {}) do
            local h, a = self:PoolWitnesses(node)
            if (side == "H" and h or a) > 0 then
                seen = seen + 1
                zones[node.map] = (zones[node.map] or 0) + 1
            end
            if type(node.by) == "table" and next(node.by) then total = total + 1 end
        end
        self:Print(("%d pool locations seen first-hand by %s anglers (%d with any first-hand report)."):format(seen, label, total))
        local list = {}
        for map, n in pairs(zones) do list[#list + 1] = { map = map, n = n } end
        table.sort(list, function(p, q) return p.n > q.n end)
        for i = 1, math.min(8, #list) do
            print(("  %-24s %d"):format(self:FrenzyZoneLabel(list[i].map), list[i].n))
        end
        local shown = 0
        for _, c in ipairs(self:PoolFrenzyCandidates()) do
            if (side == "H" and c.horde or c.alliance) > 0 and shown < 5 then
                shown = shown + 1
                if shown == 1 then print("  |cffffd100Possible frenzy waters from their sightings:|r") end
                print(("  %s %.2f, %.2f - %d sightings, %s"):format(self:FrenzyZoneLabel(c.map),
                    c.x * 100, c.y * 100, c.sightings, self:PoolCandidateWitnessText(c)))
            end
        end
        if seen == 0 then
            print("  |cff858585First-hand tags start with this version, so they fill in as anglers fish pools.|r")
        end
        return
    end
    if args[1] == "on" or args[1] == "off" then
        local on = args[1] == "on"
        self.db.settings.poolWorldMap, self.db.settings.poolMinimap = on, on
    elseif args[1] == "sync" then
        self:RequestPools(0)
        if not self.CUSTOM_CHANNEL_SUPPORTED then
            local count=0
            for _,p in pairs(self:RecentCensusPlayers()) do
                if count>=2 then break end
                self:RequestPools(self:MapID(),p.name) count=count+1
            end
            self:Fire("TFL_ROSTER_SYNC")
            self:Print(count>0 and "Requested current-zone pools from recent peers; other available routes also requested."
                or "No recent peers for a direct pool request yet. Discovery requested; available guild/group routes also checked.")
        end
    elseif args[1] and args[1] ~= "status" then self:Print("Use /tfl pools on, off, status or sync.") return end
    self:RefreshPoolPins()
    self:Print(("Shared pool atlas: %d / 3000 saved locations; pin library %s; %d locations in displayed/player maps."):format(
        #(self.db.poolAtlas or {}), pins and "available" or "missing", self.poolPinCount or 0))
    self:Print("Hover a named pool before casting to record it on a catch. Sharing: " .. (self.db.settings.poolSharing ~= false and "on" or "off"))
    self:Print("These are known locations, not live pools. /tfl config has separate map switches.")
end)
