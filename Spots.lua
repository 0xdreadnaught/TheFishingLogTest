-- Spots: locale-independent fishing spot identity.
--
-- Zone and subzone text is translated, so "Brightwater Lake" and
-- "Klarwassersee" are the same water to different players. Keys are built
-- from the map ID plus the numeric area ID instead, and the translated name
-- is only ever used for display. If we can't resolve an area ID we fall back
-- to a coarse grid cell on the map.
local _, MF = ...

local MAX_AREA_ID = 15000
local MAX_MAP_ID = 3000
local CACHE_SECONDS = 1 -- the ticker, board and catch code share one lookup

-- Zone names by map ID, dumped from an English client (/tfl dumpzones).
-- Fish data and bounties use English zone names, so this is what makes
-- them work on translated clients too.
MF.ZONE_IDS = {
    [1411] = "Durotar",
    [1412] = "Mulgore",
    [1413] = "The Barrens",
    [1416] = "Alterac Mountains",
    [1417] = "Arathi Highlands",
    [1418] = "Badlands",
    [1419] = "Blasted Lands",
    [1420] = "Tirisfal Glades",
    [1421] = "Silverpine Forest",
    [1422] = "Western Plaguelands",
    [1423] = "Eastern Plaguelands",
    [1424] = "Hillsbrad Foothills",
    [1425] = "The Hinterlands",
    [1426] = "Dun Morogh",
    [1427] = "Searing Gorge",
    [1428] = "Burning Steppes",
    [1429] = "Elwynn Forest",
    [1430] = "Deadwind Pass",
    [1431] = "Duskwood",
    [1432] = "Loch Modan",
    [1433] = "Redridge Mountains",
    [1434] = "Stranglethorn Vale",
    [1435] = "Swamp of Sorrows",
    [1436] = "Westfall",
    [1437] = "Wetlands",
    [1438] = "Teldrassil",
    [1439] = "Darkshore",
    [1440] = "Ashenvale",
    [1441] = "Thousand Needles",
    [1442] = "Stonetalon Mountains",
    [1443] = "Desolace",
    [1444] = "Feralas",
    [1445] = "Dustwallow Marsh",
    [1446] = "Tanaris",
    [1447] = "Azshara",
    [1448] = "Felwood",
    [1449] = "Un'Goro Crater",
    [1450] = "Moonglade",
    [1451] = "Silithus",
    [1452] = "Winterspring",
    [1453] = "Stormwind City",
    [1454] = "Orgrimmar",
    [1455] = "Ironforge",
    [1456] = "Thunder Bluff",
    [1457] = "Darnassus",
    [1458] = "Undercity",
    [1459] = "Alterac Valley",
    [1460] = "Warsong Gulch",
    [1461] = "Arathi Basin",
    [2482] = "Mount Hyjal",
    [2521] = "Zephras Isle",
    [2524] = "Darkspear Islands",
    [2548] = "Riverglades",
    [2652] = "Shen'dralas",
    [2665] = "Zephras Isle",
}

------------------------------------------------------------------------
-- Area name -> area ID
------------------------------------------------------------------------

local areaByName -- localized area name -> areaID
local areaCandidates
local lastBuild = -math.huge
local REBUILD = 60 -- seconds before trying again, if the client wasn't ready
local labelEvidence
local function Evidence(self)
    if labelEvidence and labelEvidence.source == self.db.spots then return labelEvidence end
    local index={source=self.db.spots,times={},holders={}}
    for _,spot in pairs(self.db.spots or {}) do
        for _,records in ipairs({spot.fish or {},spot.season or {}}) do
            for _,record in pairs(records) do
                if type(record.t)=="number" then index.times[record.t]=true end
                if type(record.h)=="string" then index.holders[self:Hash(self:AnglerKey(record.h))]=true end
            end
        end
    end
    labelEvidence=index
    return index
end

function MF:NoteSpotLabelEvidence(holder,at)
    local index=Evidence(self)
    if type(at)=="number" then index.times[at]=true end
    if type(holder)=="string" then index.holders[self:Hash(self:AnglerKey(holder))]=true end
end

function MF:EncodedSpotLabel(name)
    if type(name)~="string" or #name<5 or #name>8 or not name:match("^[a-z0-9]+$") then return end
    local value=tonumber(name,36)
    if not value or self:Pack36(value)~=name then return end
    local index=Evidence(self)
    if index.times[value+1700000000] then return "packed timestamp" end
    if index.holders[value] then return "packed angler hash" end
end

function MF:SpotLabelProblem(key)
    local saved=self.db.quarantinedSpotNames and self.db.quarantinedSpotNames[key]
    local name=self.db.spotNames[key] or saved
    local problem=self:EncodedSpotLabel(name)
    if not problem and saved and saved==name then problem="quarantined encoded label" end
    if not problem then return end
    local area=key:match("^a(%d+)$")
    local localName=area and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(tonumber(area))
    if type(localName)=="string" and localName~="" and not self:EncodedSpotLabel(localName) then return end
    return problem
end

-- One pass over every area ID. Done while the loading screen is up
-- (TFL_INIT), where a short stall can't be felt.
--
-- Built into a local and published only if it found something. The old
-- version assigned the empty table first, so a client that wasn't answering
-- yet left an empty lookup behind that nothing ever rebuilt - and an empty
-- lookup fails silently. Every water then falls through to the grid below,
-- and one canal becomes six spots in the record book. Failing loudly isn't
-- an option here, so it has to be failing temporarily instead.
local function BuildAreaLookup()
    if areaByName or GetTime() - lastBuild < REBUILD then return end
    lastBuild = GetTime()
    if not C_Map or not C_Map.GetAreaInfo then return end
    local found, candidates, n = {}, {}, 0
    for id = 1, MAX_AREA_ID do
        local name = C_Map.GetAreaInfo(id)
        if name and name ~= "" then
            candidates[name] = candidates[name] or {}
            candidates[name][#candidates[name]+1] = id
        end
        if name and name ~= "" and not found[name] then
            found[name] = id
            n = n + 1
        end
    end
    if n == 0 then return end
    areaByName, areaCandidates, MF.areaNames = found, candidates, n
end

-- Zone text and the area table don't always word things the same way:
-- Undercity's subzone reads "War Quarter" while the area is "The War
-- Quarter", so try the obvious variants before giving up.
local function AreaID(name,mapID)
    if not name or name == "" then return end
    BuildAreaLookup()
    if not areaByName then return end
    if mapID then
        local candidates = {}
        for _,variant in ipairs({name,"The " .. name,name:gsub("^The ","")}) do
            for _,id in ipairs(areaCandidates[variant] or {}) do
                candidates[#candidates+1] = id
            end
        end
        return MF:AreaCandidateForMap(candidates,mapID)
    end
    return areaByName[name]
        or areaByName["The " .. name]
        or areaByName[name:gsub("^The ", "")]
end

MF:On("TFL_INIT", BuildAreaLookup)

------------------------------------------------------------------------
-- Where the player is
------------------------------------------------------------------------

function MF:MapID()
    return (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 0
end

function MF:PlayerPos(mapID)
    mapID = mapID or self:MapID()
    if mapID == 0 or not C_Map.GetPlayerMapPosition then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then return pos:GetXY() end
end

-- A named water the client won't give an area ID for. Keyed on the name
-- rather than the position, because a canal, a harbour or a long shoreline
-- runs across several cells of the grid below, and a spot is a body of
-- water rather than a square of map. Without this, The Canals is six
-- entries in the record book, each the heaviest fish of one tenth of
-- Stormwind - which is what sent us looking.
--
-- The name is the client's own wording, so two locales key the same water
-- differently. That cost is smaller than it looks: the grid only agreed
-- across locales when both anglers happened to stand in the same tenth of
-- the zone, which on a long water they mostly didn't.
function MF:NamedKey(mapID, name)
    mapID = tonumber(mapID)
    if not mapID or mapID == 0 or type(name) ~= "string" or name == "" then return end
    return ("n%d:%d"):format(mapID, self:Hash(name))
end

-- The one key a water should be filed under, given everything we know about
-- it now. Grid keys saved before named waters existed, and grid keys still
-- arriving from clients that haven't updated, name the same water several
-- times over; this is what folds them together instead of letting them
-- stack up.
--
-- It will only move a key whose name we know and which isn't simply the
-- zone's own name. Without the zone's name to compare against we leave the
-- key alone, because the mistake available here is merging every grid cell
-- in Duskwood into one spot called Duskwood.
-- The lowest nameless named-key we hold for a map
--
-- Folding at login was not enough. It emptied the board and the board
-- filled straight back up, because every copy that arrives during a
-- session carries a key of its own and Spot() made a new water for each
-- one. The fold has to happen as they land, not once a day.
--
-- Cached because CanonicalKey runs on every read and write of a spot
-- and this would otherwise walk the whole table each time. Anything
-- that could change the answer clears it: a new spot, a name arriving,
-- or the login fold rearranging everything.
local namelessLow = {}

-- Confirmed aliases are scoped to their map. Proximity alone is not a match.
local WATER_ALIASES = {
    -- Labels may be the 24-byte cut a name arrives as over the wire (Russian runs two bytes a
    -- letter, so "Порт Штормгр" is all of Порт Штормграда anyone else ever sees).
    [1412] = {
        ["Plateau de Guette-ciel"] = "Skywatcher Plateau",
    },
    [1414] = {
        ["Caverna Vaharada"] = "Cavern of Mists",
        ["Caverne des Brumes"] = "Cavern of Mists",
        ["Höhle der Nebel"] = "Cavern of Mists",
    },
    [1416] = {
        ["Anciennes ruines de Dala"] = "Old Dalaran Ruins",
        ["Die Ruinen des alten Dal"] = "Old Dalaran Ruins",
        ["Ruinas del antiguo Dalar"] = "Old Dalaran Ruins",
        ["Руины старог"] = "Old Dalaran Ruins",
        ["El Manto de la Noche"] = "The Eventide",
        ["Die Abendruh"] = "The Eventide",
        ["Caboulot des corbeaux"] = "Cantrips & Crows",
        ["Zur Zauberkrähe"] = "Cantrips & Crows",
        ["Los Bajos Fondos"] = "The Underbelly",
        ["Die Schattenseite"] = "The Underbelly",
    },
    [1420] = {
        ["Bosque Susurrante"] = "Whispering Forest",
        ["Forêt des Murmures"] = "Whispering Forest",
    },
    [1453] = {
        ["The Canals"] = "The Canals",
        ["Die Kanäle"] = "The Canals",
        ["Les canaux"] = "The Canals",
        ["Los Canales"] = "The Canals",
        ["Каналы"] = "The Canals",
        ["Stormwind Harbor"] = "Stormwind Harbor",
        ["Hafen von Stormwind"] = "Stormwind Harbor",
        ["Port de Hurlevent"] = "Stormwind Harbor",
        ["Puerto de Ventormenta"] = "Stormwind Harbor",
        ["Порт Штормгр"] = "Stormwind Harbor",
        ["Vallée des Héros"] = "Valley of Heroes",
    },
    [1454] = {
        ["Valley of Honor"] = "Valley of Honor",
        ["Valle del Honor"] = "Valley of Honor",
        ["Vallée de l’Honneur"] = "Valley of Honor",
        ["Vallée de l'Honneur"] = "Valley of Honor",
        ["Das Tal der Ehre"] = "Valley of Honor",
        ["Аллея Чести"] = "Valley of Honor",
        ["Valley of Spirits"] = "Valley of Spirits",
        ["Vallée des Esprits"] = "Valley of Spirits",
        ["Das Tal der Geister"] = "Valley of Spirits",
        ["Valle de los Espíritus"] = "Valley of Spirits",
    },
    [1455] = {
        ["The Forlorn Cavern"] = "The Forlorn Cavern",
        ["La caverne Lugubre"] = "The Forlorn Cavern",
        ["La Caverna Abandonada"] = "The Forlorn Cavern",
        ["Das Düstere Viertel"] = "The Forlorn Cavern",
        ["Заброшенный "] = "The Forlorn Cavern",
        ["The Mystic Ward"] = "The Mystic Ward",
        ["Das Mystikerviertel"] = "The Mystic Ward",
        ["La Garde mystique"] = "The Mystic Ward",
    },
    [1458] = {
        ["Magic Quarter"] = "Magic Quarter",
        ["Das Magieviertel"] = "Magic Quarter",
        ["Barrio de la Magia"] = "Magic Quarter",
        ["Quartier de la Magie"] = "Magic Quarter",
        ["Квартал маго"] = "Magic Quarter",
        ["War Quarter"] = "War Quarter",
        ["Barrio de la Guerra"] = "War Quarter",
        ["Trade Quarter"] = "Trade Quarter",
        ["Barrio del Comercio"] = "Trade Quarter",
        ["Quartier des marchands"] = "Trade Quarter",
        ["Das Handwerksviertel"] = "Trade Quarter",
        ["Rogues' Quarter"] = "Rogues' Quarter",
        ["Quartier des Voleurs"] = "Rogues' Quarter",
        ["Canals"] = "Canals",
        ["Canaux"] = "Canals",
        ["The Apothecarium"] = "The Apothecarium",
        ["Квартал апте"] = "The Apothecarium",
    },
    [2482] = {
        ["Berceau de la tranquilli"] = "Cradle of Tranquility",
        ["Retraite de Malorne"] = "Malorne's Retreat",
    },
    [2521] = {
        ["Windsong Lake"] = "Windsong Lake",
        ["Lac Chantevent"] = "Windsong Lake",
        ["Lago Canzalvaje"] = "Windsong Lake",
        ["Windweisensee"] = "Windsong Lake",
        ["Shen'dar Highlands"] = "Shen'dar Highlands",
        ["Shen'darhochland"] = "Shen'dar Highlands",
        ["Tierras Altas de Shen'da"] = "Shen'dar Highlands",
        ["Shen'dar Village"] = "Shen'dar Village",
        ["Деревня Шен'д"] = "Shen'dar Village",
        ["Valanaar"] = "Valanaar",
        ["Валанаар"] = "Valanaar",
    },
    [2548] = {
        ["Farholde Keep"] = "Farholde Keep",
        ["Burg Farholde"] = "Farholde Keep",
        ["Castillo de Farholde"] = "Farholde Keep",
        ["Donjon de Fort-Lointain"] = "Farholde Keep",
        ["Turner's Logging Camp"] = "Turner's Logging Camp",
        ["Camp de bûcherons de Tu"] = "Turner's Logging Camp",
        ["Sunnyglade"] = "Sunnyglade",
        ["Clairsoleil"] = "Sunnyglade",
        ["Sonnengrund"] = "Sunnyglade",
        ["Светогладь"] = "Sunnyglade",
        ["Eastwind Shore"] = "Eastwind Shore",
        ["Costa Viento del Este"] = "Eastwind Shore",
        ["Ostwindküste"] = "Eastwind Shore",
        ["Rivage d’Estevent"] = "Eastwind Shore",
        ["Rivage d'Estevent"] = "Eastwind Shore",
        ["Побережье Во"] = "Eastwind Shore",
        ["Krol'dok Stronghold"] = "Krol'dok Stronghold",
        ["Feste Krol'dok"] = "Krol'dok Stronghold",
        ["Windstead"] = "Windstead",
        ["Finca del Viento"] = "Windstead",
        ["Windhof"] = "Windstead",
        ["Powderfuse Port"] = "Powderfuse Port",
        ["Hafen von Powderfuse"] = "Powderfuse Port",
        ["Port de Poudremèche"] = "Powderfuse Port",
        ["Puerto Polvofusil"] = "Powderfuse Port",
        ["Puerto Polvomecha"] = "Powderfuse Port",
        ["Пороховой по"] = "Powderfuse Port",
        ["Rog'mar"] = "Rog'mar",
        ["Rog’mar"] = "Rog'mar",
        ["Рог'мар"] = "Rog'mar",
    },
}

-- A translation whose English water the client files under its area ID: the alias has to land
-- on that key, not mint a named one beside it
local ALIAS_AREAS = {
    [1453] = { ["Valley of Heroes"] = 1617 },
}

local NamePrefix

local function WaterAlias(mapID, name)
    local aliases = WATER_ALIASES[mapID]
    if not aliases or type(name) ~= "string" then return end
    if aliases[name] then return aliases[name] end
    -- Our own client's full name, against a label kept as the wire's cut
    if #name > 24 then
        local cut = NamePrefix(name, 24)
        if aliases[cut] then return aliases[cut] end
    end
end

function NamePrefix(name, limit)
    local index = 1
    while index <= limit do
        local first = name:byte(index)
        local width
        if first < 128 then width = 1
        elseif first >= 194 and first <= 223 then width = 2
        elseif first >= 224 and first <= 239 then width = 3
        elseif first >= 240 and first <= 244 then width = 4
        else break end
        local last = index + width - 1
        if last > limit or not name:sub(index + 1, last):match("^[\128-\191]*$") then break end
        index = last + 1
    end
    return name:sub(1, index - 1)
end

local function AliasTarget(self, mapID, alias)
    local area = ALIAS_AREAS[mapID] and ALIAS_AREAS[mapID][alias]
    if area then return "a" .. area end
    return self:NamedKey(mapID, alias)
end

local function AliasKey(self, mapID, key, name)
    local alias = WaterAlias(mapID, name)
    if alias then return AliasTarget(self, mapID, alias), alias end
    -- Another character may already have removed the old label.
    for label, canonical in pairs(WATER_ALIASES[mapID] or {}) do
        if self:NamedKey(mapID, label) == key then
            return AliasTarget(self, mapID, canonical), canonical
        end
    end
end

function MF:ForgetNamelessLow()
    namelessLow = {}
end

function MF:LowestNameless(mapID)
    local cached = namelessLow[mapID]
    if cached ~= nil then return cached or nil end
    local pattern = "^n" .. mapID .. ":%d+$"
    local low = false
    for other in pairs(self.db.spots) do
        if other:match(pattern) and not self:SpotLabelProblem(other) and self:KnownSpotName(other) == nil then
            if not low or other < low then low = other end
        end
    end
    namelessLow[mapID] = low
    return low or nil
end

-- Confirmed west/central Loch fishing locations. Only generic zone/grid
-- fallbacks qualify; explicitly named neighbouring waters stay separate.
local function LochWater(mapID, name, x, y)
    if mapID ~= 1432 then return false end
    if name == "The Loch" then return true end
    if name and name ~= "Loch Modan" and name ~= "" then return false end
    return x and y and x >= 0.44 and x <= 0.59 and y >= 0.18 and y <= 0.65
end

function MF:CanonicalKey(key)
    if type(key) ~= "string" then return key end
    if self:SpotLabelProblem(key) then return key end
    if key:match("^a%d+$") then return key end -- already the best kind there is
    -- A z key carries no map, so it falls out of the match below and is
    -- returned untouched - which is what it wants. Folding is for keys
    -- naming one water twice over; two of those are two different places.
    local mapID = tonumber(key:match("^(%d+)@%d+,%d+$") or key:match("^n(%d+):%d+$"))
    if not mapID then return key end
    local where = self.db.spotWhere[key]
    if LochWater(mapID, self.db.spotNames[key], where and where.x, where and where.y)
        and (not where or where.map == mapID) then return "a556" end
    local canonical = AliasKey(self, mapID, key, self.db.spotNames[key])
    if canonical then return canonical end
    local name = self:KnownSpotName(key)
    if not name then
        -- An n key is minted from a name, so one nobody can name is a
        -- copy. The lowest we hold for this map is the one they all
        -- gather on, which is the same answer the login fold reaches.
        if key:match("^n%d+:%d+$") then
            local low = self:LowestNameless(mapID)
            if low and low < key then return low end
        end
        return key
    end
    local zone = self:ZoneNameFor(mapID) or self.ZONE_IDS[mapID]
    if not zone or name == zone then return key end
    local area = AreaID(name,mapID)
    if area then return "a" .. area end
    return self:NamedKey(mapID, name) or key
end

local cachedSpot, cachedAt = nil, -math.huge

local function ComputeSpot(self)
    local mapID = self:MapID()
    local zone, sub = self:Location()
    local x, y = self:PlayerPos(mapID)

    local named = sub ~= zone and sub or nil
    if named and self:NameFitsMap(named,mapID) == false then
        -- Zone transitions can briefly pair an old subzone with the new map.
        named,sub = nil,zone
    end
    if LochWater(mapID, named or zone, x, y) then
        return { key = "a556", name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(556) or "The Loch",
            mapID = mapID, x = x, y = y }
    end
    local alias = WaterAlias(mapID, named)
    if alias then
        return { key = AliasTarget(self, mapID, alias), name = alias, mapID = mapID, x = x, y = y }
    end
    local area = AreaID(named,mapID)
    local key
    if area then
        -- Area IDs are unique across the game, so a lake on the border of two
        -- maps (Lordamere Lake) is one spot whichever shore you stand on.
        key = "a" .. area
    elseif named then
        key = self:NamedKey(mapID, named)
    end
    -- Somewhere the client cannot place at all
    --
    -- A dungeon the game has no map entry for gives MapID() 0 and no
    -- position, and every one of them used to come out as the key "0" -
    -- so two of them would have shared one set of records, under
    -- whichever name was heard first. The place's own name is the only
    -- thing left that tells them apart, and one spot for the whole
    -- dungeon is the right grain: "King of the Excavation Site" is the
    -- thing worth saying, and without coordinates there is nothing finer
    -- to divide it by anyway.
    if not key and mapID == 0 and zone ~= "" then
        return { key = "z" .. self:Hash(zone), name = zone, mapID = mapID }
    end
    if not key then
        if x and y then
            -- Somewhere we already fish, if we're standing at it. Without
            -- this, walking round a pond to the other bank starts a second
            -- set of records for the same water - and the grid below can't
            -- tell, because a cell is a tenth of the zone whatever size the
            -- water is.
            key = self:SpotNear(mapID, x, y, named or zone)
            -- 10x10 grid over the zone: near enough for one lake or riverbank.
                or ("%d@%d,%d"):format(mapID, math.floor(x * 10), math.floor(y * 10))
        else
            key = tostring(mapID)
        end
    end
    return { key = key, name = sub, mapID = mapID, x = x, y = y }
end

-- The player's current spot: { key, name, mapID, x, y }. Shared for a
-- second at a time; treat the table as read-only.
function MF:CurrentSpot()
    local now = GetTime()
    if not cachedSpot or now - cachedAt >= CACHE_SECONDS then
        cachedSpot, cachedAt = ComputeSpot(self), now
    end
    return cachedSpot
end

-- Returns key, display name, mapID, x, y.
function MF:SpotInfo()
    local s = self:CurrentSpot()
    return s.key, s.name, s.mapID, s.x, s.y
end

function MF:SpotKey()
    return self:CurrentSpot().key
end

function MF:ForgetCurrentSpot() cachedSpot=nil end

-- Spot keys in the current format: "a<areaID>", "n<mapID>:<nameHash>" (a
-- named water with no area ID), "z<nameHash>" (a place the client has no
-- map for at all), "<mapID>@<x>,<y>" (grid fallback) or "<mapID>". Keys
-- from before 0.3.3 ("<mapID>:<areaID>") are ignored so old clients'
-- records don't show up as duplicate spots.
--
-- A client too old to know the "z" form will refuse those records rather
-- than mangle them, which is the same way it already treats pre-0.3.3
-- keys: dungeon records simply do not reach it until it updates.
function MF:IsSpotKey(key)
    return type(key) == "string"
        and (key:match("^a%d+$") or key:match("^n%d+:%d+$") or key:match("^z%d+$")
            or key:match("^%d+@%d+,%d+$") or key:match("^%d+$")) ~= nil
end

local function Invalidate() cachedSpot = nil end
MF:On("ZONE_CHANGED", Invalidate)
MF:On("ZONE_CHANGED_INDOORS", Invalidate)
MF:On("ZONE_CHANGED_NEW_AREA", Invalidate)

------------------------------------------------------------------------
-- Names and distances
------------------------------------------------------------------------

-- Remember a readable name for every spot we hear about, preferring our own
-- client's wording over a name sent by someone on another locale.
function MF:RememberSpotName(key, name, mine)
    if not key or type(name) ~= "string" then return end
    name = NamePrefix(name, #name)
    if name == "" then return end
    -- A key is not a name. Letting one in here is what turned one record
    -- into nine: stored as a name, it becomes the seed of the next key.
    if self:IsSpotKey(name) then return end
    if self:EncodedSpotLabel(name) then
        self.db.quarantinedSpotNames=self.db.quarantinedSpotNames or {}
        self.db.quarantinedSpotNames[key]=name
        return
    end
    local names = self.db.spotNames
    name = WaterAlias(self:MapOfKey(key), name) or name
    if mine or not names[key] or self:EncodedSpotLabel(names[key]) then
        names[key] = name
        -- Naming a water takes it out of the nameless pool, so it can
        -- no longer be the one the copies gather on.
        self:ForgetNamelessLow()
        -- And the name has to follow the key it is about to become. A
        -- named water moves to the key its name mints, and the name was
        -- being left behind on the old one - so the spot arrived at its
        -- proper key with no name, which made it look like wreckage and
        -- put it in line to be folded into the copies.
        local canon = self:CanonicalKey(key)
        if canon ~= key and (mine or not names[canon]) then
            names[canon] = name
            self:ForgetNamelessLow()
        end
    end
end

------------------------------------------------------------------------
-- Folding duplicates together
--
-- Everything above decides what a water is called from now on. This deals
-- with what is already saved: records filed under a grid cell when the
-- water they were caught in has a name, which is how ten separate records
-- came to sit in the book all saying "The Canals".
--
-- It runs every login rather than once, because the answer can change. A
-- client that couldn't name an area yesterday may name it today, and when
-- it does, the named key and the area key are the same water again and want
-- putting back together. Running it twice does nothing, which is what makes
-- that safe.
--
-- Nothing is thrown away: where two keys hold a record for the same fish,
-- the heavier one survives, which is the same rule the record would have
-- been judged by if the water had been one spot all along.
------------------------------------------------------------------------

local function Heavier(old, rec)
    return not old or rec.w > old.w or (rec.w == old.w and rec.t < old.t)
end

local function FoldSpot(into, from)
    for mapID in pairs(from.maps or {}) do into.maps[mapID] = true end
    for id, rec in pairs(from.fish or {}) do
        if Heavier(into.fish[id], rec) then into.fish[id] = rec end
    end
    -- Season records only travel if both spots are keeping the same season;
    -- a stale one is cleared by MF:Spot on the next touch anyway.
    if from.seasonID == into.seasonID then
        for id, rec in pairs(from.season or {}) do
            if Heavier(into.season[id], rec) then into.season[id] = rec end
        end
    end
    -- The kept month travels the same way, and to a spot with none of its own.
    if from.lastSeason and (into.lastSeasonID == nil or into.lastSeasonID == from.lastSeasonID) then
        into.lastSeason, into.lastSeasonID = into.lastSeason or {}, from.lastSeasonID
        for id, rec in pairs(from.lastSeason) do
            if Heavier(into.lastSeason[id], rec) then into.lastSeason[id] = rec end
        end
    end
end

-- Returns how many keys moved and how many of those merged into a spot that
-- already existed - the second number is the duplicates that were showing.
-- Water that nothing can tell apart but distance
--
-- Where the game gives no subzone, a spot falls back to one cell of a ten
-- by ten grid over the zone - and a pond wider than a cell becomes two
-- spots, with the far bank a third. That is four sets of records for one
-- pond in Thunder Bluff, which is where this came from.
--
-- Name can't separate them: the only name any of them has is the zone's,
-- and folding on that would make one angler King of Duskwood. So position
-- is all that's left, and the question is "could you cast from one to the
-- other", which is a distance in yards rather than in map units.
--
-- Map units are a fraction of the zone, so the same number is a few paces
-- in a city and half a mile in Duskwood. The client will convert when it
-- can; the fallback is deliberately tight, because merging two real ponds
-- can't be undone by fishing and leaving them apart can.
local NEAR_YARDS = 50
local NEAR_UNITS = 0.04

local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and type(pos) == "table" and pos.GetXY then return pos:GetXY() end
end

local function SamePlace(mapID, ax, ay, bx, by)
    local a1, a2 = WorldPos(mapID, ax, ay)
    local b1, b2 = WorldPos(mapID, bx, by)
    if a1 and b1 then
        local dx, dy = a1 - b1, a2 - b2
        return dx * dx + dy * dy <= NEAR_YARDS * NEAR_YARDS
    end
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy <= NEAR_UNITS * NEAR_UNITS
end

-- A spot we already know at this point on this map, if there is one. Only
-- ever one that reads as the same water: a different name means a
-- different place however close the two banks are.
function MF:SpotNear(mapID, x, y, name, skip)
    if not mapID or mapID == 0 or not x or not y then return end
    for key, where in pairs(self.db.spotWhere) do
        if self:SpotLabelProblem(key) then
            self.db.quarantinedSpotNames=self.db.quarantinedSpotNames or {}
            self.db.quarantinedSpotNames[key]=self.db.spotNames[key] or self.db.quarantinedSpotNames[key]
        end
        if key ~= skip and where.map == mapID and where.x and where.y
            and (name == nil or self:SpotName(key) == name)
            and SamePlace(mapID, x, y, where.x, where.y) then
            return key
        end
    end
end

-- Grid spots that turned out to be the same water as one we already keep.
-- Sorted so every client folds the same pond onto the same key, whatever
-- order its saved variables happen to come out in.
local function NeighbourMoves(self)
    local keys, moves = {}, {}
    for key in pairs(self.db.spots) do
        -- Grid cells, and named keys nobody has ever given a name to. The
        -- second kind are the wreckage of records that multiplied: each
        -- copy has a key of its own and no name at all, so distance is the
        -- only thing left that can tell they are one water.
        local gridded = key:match("^%d+@%d+,%d+$") ~= nil
        local nameless = key:match("^n%d+:%d+$") ~= nil and self:KnownSpotName(key) == nil
        if (gridded or nameless) and not self:SpotLabelProblem(key) and self.db.spotWhere[key] then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local kept = {}
    for _, key in ipairs(keys) do
        local where = self.db.spotWhere[key]
        -- Two waters nobody can name are compared on position alone; a
        -- named one is never folded into an unnamed one beside it.
        local name, onto = self:KnownSpotName(key), nil
        for _, other in ipairs(kept) do
            local theirs = self.db.spotWhere[other]
            if theirs and self:KnownSpotName(other) == name
                and SamePlace(where.map, where.x, where.y, theirs.x, theirs.y) then
                onto = other
                break
            end
        end
        if onto then moves[key] = onto else kept[#kept + 1] = key end
    end
    return moves
end

-- Nameless named-keys: the wreckage, wherever it says it is
--
-- An n key is minted from a name. One that nobody can name has lost it -
-- to the multiplying bug, or relayed by a client that never knew it - so
-- a nameless n key should not exist at all, and several in one zone are
-- one water however they are scattered.
--
-- Distance cannot sort these out, and two rounds of trying taught that
-- the hard way. A copy with no position is invisible to a fold that
-- measures. A copy that *does* carry a position is worse: each one
-- arrived with wherever its sender happened to be standing, so thirteen
-- copies of a Stranglethorn trout land more than fifty yards apart and
-- read as thirteen separate waters. Same fish, same weight, thirteen
-- rows on the board.
--
-- So position is not consulted. The map is in the key itself, and the
-- name - or the absence of one - is the whole signal.
local function NamelessMoves(self)
    local byMap, moves = {}, {}
    for key in pairs(self.db.spots) do
        local map = key:match("^n(%d+):%d+$")
        if map and not self:SpotLabelProblem(key) and self:KnownSpotName(key) == nil then
            byMap[map] = byMap[map] or {}
            table.insert(byMap[map], key)
        end
    end
    -- Sorted, so every client folds them onto the same one of themselves.
    for _, keys in pairs(byMap) do
        table.sort(keys)
        for i = 2, #keys do moves[keys[i]] = keys[1] end
    end
    return moves
end

function MF:FoldSpotKeys()
    -- Names that are really keys, saved before we knew to refuse them.
    -- They have to go first: while one is in there it is a name as far as
    -- everything below is concerned, and the next fold would mint yet
    -- another key from it.
    for key, name in pairs(self.db.spotNames) do
        local clean = type(name) == "string" and NamePrefix(name, #name) or ""
        if clean == "" or self:IsSpotKey(clean) then
            self.db.spotNames[key] = nil
        else
            self.db.spotNames[key] = clean
        end
    end

    local moves = {}
    for key in pairs(self.db.spots) do
        local canon = self:CanonicalKey(key)
        if canon ~= key then moves[key] = canon end
    end
    for key in pairs(self.db.spotNames) do
        if not moves[key] then
            local canon = self:CanonicalKey(key)
            if canon ~= key then moves[key] = canon end
        end
    end
    for key in pairs(self.cdb and self.cdb.records or {}) do
        if not moves[key] then
            local canon = AliasKey(self, self:MapOfKey(key), key, self.db.spotNames[key])
            if canon and canon ~= key then moves[key] = canon end
        end
    end
    for key, onto in pairs(NeighbourMoves(self)) do
        if not moves[key] then moves[key] = onto end
    end
    for key, onto in pairs(NamelessMoves(self)) do
        if not moves[key] then moves[key] = onto end
    end

    self:ForgetNamelessLow()
    local moved, merged = 0, 0
    for key, canon in pairs(moves) do
        moved = moved + 1
        local from = self.db.spots[key]
        if from then
            local into = self.db.spots[canon]
            if into then
                merged = merged + 1
                FoldSpot(into, from)
            else
                from.key = canon
                self.db.spots[canon] = from
            end
            self.db.spots[key] = nil
        end

        local name = self.db.spotNames[key]
        if name and not self.db.spotNames[canon] then
            self.db.spotNames[canon] = WaterAlias(self:MapOfKey(key), name) or name
        end
        self.db.spotNames[key] = nil

        -- Somewhere we've stood ourselves still beats a position that came
        -- in with someone else's record.
        local where = self.db.spotWhere[key]
        local have = self.db.spotWhere[canon]
        if where and (not have or (where.mine and not have.mine)) then
            if where.observed and where.observed.key == key then where.observed.key = canon end
            self.db.spotWhere[canon] = where
        end
        self.db.spotWhere[key] = nil

        local mine = self.cdb and self.cdb.records and self.cdb.records[key]
        if mine then
            local keep = self.cdb.records[canon]
            if not keep then
                self.cdb.records[canon] = mine
            else
                for id, rec in pairs(mine) do
                    local old = keep[id]
                    if not old or rec.weight > old.weight then keep[id] = rec end
                end
            end
            self.cdb.records[key] = nil
        end
    end
    self:ForgetNamelessLow()
    return moved, merged
end

MF:On("TFL_INIT", function(self)
    self:SweepSpotPositions()
    local moved, merged = self:FoldSpotKeys()
    self:SweepSpotPositions()
    if merged > 0 then
        self:Debug(("folded %d spot keys, %d of them duplicates"):format(moved, merged))
    end
end)

------------------------------------------------------------------------
-- Where a spot is
--
-- A spot is a whole body of water keyed by its area ID, so one position is
-- only ever "somewhere on this water" - enough to know which zone to fly to
-- and roughly where the bank is. Somewhere we've stood ourselves beats a
-- position that arrived with a record, so ours overwrites.
------------------------------------------------------------------------

-- The name to put on the wire: blank when we don't actually know one.
-- Sending SpotName's fallback would be sending a key as a name, which is
-- the thing that multiplied records in the first place.
function MF:SpotNameForWire(key)
    local name = self:KnownSpotName(key)
    if not name then return "" end
    if self:EncodedSpotLabel(name) then return "" end
    name = name:gsub("[,;~|]", " ")
    return NamePrefix(name, math.min(24, #name))
end

function MF:MarkSpotPosition(key, mapID, x, y, mine, caughtAt)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not self:ValidSpotPosition(key, mapID, x, y) then return end
    if x <= 0 and y <= 0 then return end
    key = AliasKey(self, self:MapOfKey(key), key, self.db.spotNames[key]) or key
    local where = self.db.spotWhere[key]
    if where and where.mine and not mine then return end
    local observed = mine and tonumber(caughtAt) and {key=key,map=mapID,x=x,y=y,at=tonumber(caughtAt)} or nil
    if not observed and where and where.map==mapID and where.x==x and where.y==y then observed=where.observed end
    self.db.spotWhere[key] = { map = mapID, x = x, y = y, mine = mine or nil, observed=observed }
end

function MF:SpotLocallyObserved(key)
    local w=self:SpotPosition(key)
    local o=w and w.observed
    return type(o)=="table" and o.key==key and o.map==w.map and o.x==w.x and o.y==w.y
        and type(o.at)=="number" and o.at>0 or false
end

-- Verified geography for reported area-ID contamination. Unknown areas
-- remain accepted; exploration APIs returning nil cannot prove absence.
-- Include containing continents and the adjacent Undercity map.
local AREA_MAPS = {
    [391] = { [1413] = true, [1414] = true }, -- The Merchant Coast
    [272] = { [1424] = true, [1415] = true }, -- Tarren Mill
    [153] = { [1420] = true, [1458] = true, [1415] = true }, -- Ruins of Lordaeron
    [2097] = { [1441] = true, [1414] = true }, -- Darkcloud Pinnacle
}
MF.AREA_MAP_OVERRIDES = AREA_MAPS

local geographicNames
function MF:NameFitsMap(name,mapID)
    if not name then return nil end
    if self:EncodedSpotLabel(name) then return false end
    if not geographicNames then
        geographicNames = {}
        for id,row in pairs(self.AREA_GEOGRAPHY) do
            geographicNames[row[3]] = geographicNames[row[3]] or {}
            geographicNames[row[3]][#geographicNames[row[3]]+1] = id
        end
    end
    local candidates = (areaCandidates and areaCandidates[name]) or geographicNames[name] or self.GEOGRAPHY_NAME_ALIASES[name]
    if not candidates then return nil end
    local unknown = false
    for _,id in ipairs(candidates) do
        local fits = self:AreaFitsMap(id,mapID)
        if fits then return true end
        if fits == nil then unknown = true end
    end
    if unknown then return nil end
    return false
end

function MF:SpotMapFits(key,mapID)
    if type(key) ~= "string" then return nil end
    if type(mapID) ~= "number" or mapID ~= mapID or mapID < 1 or mapID > MAX_MAP_ID
        or mapID ~= math.floor(mapID) then return false end
    local encoded = tonumber(key:match("^n(%d+):%d+$") or key:match("^(%d+)@%d+,%d+$") or key:match("^(%d+)$"))
    if encoded and encoded ~= mapID then return false end
    local area = tonumber(key:match("^a(%d+)$"))
    if self:SpotLabelProblem(key) then return false end
    if area then
        if AREA_MAPS[area] then return AREA_MAPS[area][mapID] == true end
        return self:AreaFitsMap(area,mapID)
    end
    return self:NameFitsMap(self.db and self.db.spotNames and self.db.spotNames[key],mapID)
end

function MF:ValidSpotPosition(key, mapID, x, y)
    if not self:IsSpotKey(key) or type(mapID) ~= "number" or mapID < 1 or mapID > MAX_MAP_ID
        or mapID ~= math.floor(mapID) or type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return false end
    if x == 0 and y == 0 then return false end
    -- Area keys can cross zone borders; named/grid keys explicitly name
    -- their map and must never acquire coordinates from another one.
    return self:SpotMapFits(key,mapID) ~= false
end

function MF:SweepSpotPositions()
    self.db.quarantinedSpotPositions = self.db.quarantinedSpotPositions or {}
    local removed = 0
    for key, where in pairs(self.db.spotWhere) do
        if type(where) ~= "table" or not self:ValidSpotPosition(key, where.map, where.x, where.y) then
            self.db.quarantinedSpotPositions[key] = where
            self.db.spotWhere[key] = nil
            removed = removed + 1
        end
    end
    self.db.quarantinedSpotMaps = self.db.quarantinedSpotMaps or {}
    for key,spot in pairs(self.db.spots or {}) do
        for mapID in pairs(spot.maps or {}) do
            if self:SpotMapFits(key,mapID) == false then
                self.db.quarantinedSpotMaps[key] = self.db.quarantinedSpotMaps[key] or {}
                self.db.quarantinedSpotMaps[key][mapID] = true
                spot.maps[mapID] = nil
            end
        end
    end
    self.spotPositionsRemoved = (self.spotPositionsRemoved or 0) + removed
    return removed
end

function MF:SpotPosition(key)
    local where = self.db.spotWhere[key]
    if type(where) == "table" and self:ValidSpotPosition(key,where.map,where.x,where.y) then return where end
end

-- Record identities never create frenzy geography; use the common catalogue resolver.
function MF:FrenzyLocationUsable(key)
    return self:ResolveFrenzyLocation(key)~=nil
end

function MF:SpotRecordMap(key)
    local where = self:SpotPosition(key)
    if where then return where.map end
    local spot,best = self.db.spots[key],nil
    local function Rank(mapID) return (mapID == 1414 or mapID == 1415) and mapID+10000 or mapID end
    for mapID in pairs(spot and spot.maps or {}) do
        if self:SpotMapFits(key,mapID) ~= false and (not best or Rank(mapID)<Rank(best)) then best=mapID end
    end
    return best or 0
end

MF:Command("mapaudit","Other","/tfl mapaudit - inspect all saved spot positions",function(self)
    local rows,good,bad,unknown,observed = {},0,0,0,0
    for key,where in pairs(self.db.spotWhere) do
        local valid = self:ValidSpotPosition(key,where.map,where.x,where.y)
        local fits = self:SpotMapFits(key,where.map)
        if not valid then bad=bad+1
        elseif fits == true then good=good+1
        elseif self:SpotLocallyObserved(key) then observed=observed+1
        else unknown=unknown+1 end
        if not valid or (fits == nil and not self:SpotLocallyObserved(key)) then
            rows[#rows+1] = ("%s | %s | map %s | %s"):format(key,self:SpotName(key),tostring(where.map),valid and "UNVERIFIED" or "INVALID")
        end
    end
    table.sort(rows)
    local lines={("TFL %s geography audit: %d zone-consistent, %d invalid, %d unverified, %d locally observed.")
        :format(self.Version(),good,bad,unknown,observed),
        "Zone consistency does not certify exact water coordinates. Locally observed means a genuine catch at that saved point."}
    local current=self:CurrentSpot()
    if current then
        local saved=self:SpotPosition(current.key)
        local status=self:SpotLocallyObserved(current.key) and "LOCALLY OBSERVED" or
            (saved and self:SpotMapFits(current.key,saved.map)==true and "ZONE-CONSISTENT" or "UNVERIFIED")
        lines[#lines+1]=("Current: %s | %s | map %s | %.2f, %.2f | %s"):format(
            current.key,current.name or self:SpotName(current.key),tostring(current.mapID),
            (current.x or 0)*100,(current.y or 0)*100,status)
    end
    local quarantined,associations=0,0
    for _ in pairs(self.db.quarantinedSpotPositions or {}) do quarantined=quarantined+1 end
    for _,maps in pairs(self.db.quarantinedSpotMaps or {}) do for _ in pairs(maps) do associations=associations+1 end end
    lines[#lines+1]=("Quarantined: %d positions, %d map associations. Fish records preserved."):format(quarantined,associations)
    for i=1,math.min(#rows,200) do lines[#lines+1]=rows[i] end
    if #rows>200 then lines[#lines+1]="Further entries omitted; the offline saved-data audit exports every point." end
    self:ShowDiagnosticText(table.concat(lines,"\n"))
end)

MF:Command("mapcheck", "Other", "/tfl mapcheck [mapID] - inspect area-marker map APIs", function(self, args)
    local map = tonumber(args[1]) or self:MapID()
    local exploration = _G.C_MapExplorationInfo
    local probe = exploration and exploration.GetExploredAreaIDsAtPosition
    self:Print(("Map check %s: explored-area probe %s; point-map probe %s."):format(tostring(map),
        type(probe) == "function" and "available" or "missing",
        C_Map and type(C_Map.GetMapInfoAtPosition) == "function" and "available" or "missing"))
    local count = 0
    for key, where in pairs(self.db.spotWhere) do
        local area = tonumber(key:match("^a(%d+)$"))
        if area and where.map == map then
            count = count + 1
            if count > 20 then self:Print("Further markers omitted.") break end
            local result = "unavailable"
            if type(probe) == "function" and type(CreateVector2D) == "function" then
                local ok, ids = pcall(probe, map, CreateVector2D(where.x, where.y))
                if ok and type(ids) == "table" then
                    local labels = {}
                    for i, id in ipairs(ids) do
                        if i > 8 then break end
                        labels[#labels + 1] = tostring(id) .. ":" .. tostring(C_Map.GetAreaInfo(id) or "?")
                    end
                    result = #labels > 0 and table.concat(labels, ", ") or "empty"
                else result = ok and "no result" or "API error" end
            end
            self:Print(("%s [%s] at %.1f, %.1f; probe: %s"):format(self:SpotName(key), key,
                where.x * 100, where.y * 100, result))
        end
    end
    self:Print("Diagnostic only: no coordinates or records changed.")
end)

function MF:ZoneNameFor(mapID)
    local info = mapID and mapID ~= 0 and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

-- "Crystal Lake, Durotar (42, 68)", with whatever parts we actually know.
function MF:SpotWhere(key)
    local name = self:SpotName(key)
    local where = self:SpotPosition(key)
    if not where then return name end
    local zone = self:ZoneNameFor(where.map)
    return ("%s%s (%.0f, %.0f)"):format(name, zone and (", " .. zone) or "",
        where.x * 100, where.y * 100)
end

-- Point the player at a spot: a tracked waypoint where the client has them,
-- the world map otherwise, and the coordinates in chat either way.
function MF:PointToSpot(key)
    local where = self:SpotPosition(key)
    if not where then
        self:Print(("%s - nobody has recorded where that is yet."):format(self:SpotName(key)))
        return
    end
    self:Print(self:SpotWhere(key))
    self:PointToCoordinates(where)
end

-- Show a spot on the world map without a word in chat: the map opens on its
-- zone, with a waypoint on the water where the client allows one.
function MF:ShowSpotOnMap(key)
    local where = self:SpotPosition(key)
    if not where then
        self:Print(("%s - nobody has recorded where that is yet."):format(self:SpotName(key)))
        return
    end
    self:PointToCoordinates(where)
    if OpenWorldMap then
        pcall(OpenWorldMap, where.map)
    elseif WorldMapFrame then
        pcall(ShowUIPanel, WorldMapFrame)
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, where.map) end
    end
end

function MF:PointToCoordinates(where)
    local point = UiMapPoint and UiMapPoint.CreateFromCoordinates
        and UiMapPoint.CreateFromCoordinates(where.map, where.x, where.y)
    if point and C_Map and C_Map.SetUserWaypoint and (not C_Map.CanSetUserWaypointOnMap
        or C_Map.CanSetUserWaypointOnMap(where.map)) then
        local ok, result = pcall(C_Map.SetUserWaypoint, point)
        ok = ok and result ~= false
        if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        if ok then return true end
    end

    if OpenWorldMap then
        pcall(OpenWorldMap, where.map)
    elseif WorldMapFrame then
        pcall(ShowUIPanel, WorldMapFrame)
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, where.map) end
    end
end

MF:Command("map", "Other", "/tfl map mapID x y - show coordinates on the world map", function(self, args)
    local map, x, y
    if type(args) == "table" and #args == 3 then map, x, y = args[1], args[2], args[3] end
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not map or not self.ZONE_IDS[map] or not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
        self:Print("Use /tfl map 1424 62.84 41.42 (map ID, x and y from 0 to 100).")
        return
    end
    local marked = self:PointToCoordinates({ map = map, x = x / 100, y = y / 100 })
    if OpenWorldMap then pcall(OpenWorldMap, map)
    elseif WorldMapFrame then
        pcall(ShowUIPanel, WorldMapFrame)
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, map) end
    end
    self:Print(("%s: %.2f, %.2f"):format(self:ZoneNameFor(map) or self.ZONE_IDS[map], x, y))
    if not marked then self:Print("Map opened. This client could not place a waypoint; use the coordinates above.") end
end)

-- Names arrive with other players' records, but our own records restored
-- from the save macros only carry the area ID. Ask the game for the name
-- in that case; it's the right one for this client's language too.
-- A name somebody actually told us, or the game did. nil when nobody has.
--
-- Kept apart from SpotName, and that separation is the whole of a nasty
-- bug: SpotName falls back to the key so there is always something to put
-- on screen, that fallback went out on the wire as the spot's name, the
-- receiver stored it, and the next fold derived a brand new key from it.
-- One record multiplied every time it went round the realm - nine copies
-- of the same catfish in Duskwood, each at a key made from the last.
--
-- So anything that decides identity, or travels, asks this. Only display
-- may have the fallback.
function MF:KnownSpotName(key)
    if not key then return nil end
    -- Our own lookup first, for anything keyed by area.
    --
    -- A name travels with a record, in whatever language the angler who
    -- caught it plays in - which is how "Die vergessenen Teiche" turned
    -- up on an English board. An area ID is the same number on every
    -- client, so for those keys this client can always answer in its own
    -- language and should: the name that arrived is only worth having
    -- when we cannot work it out ourselves.
    local area = tonumber(key:match("^a(%d+)$"))
    if area and C_Map and C_Map.GetAreaInfo then
        local mine = C_Map.GetAreaInfo(area)
        if mine and mine ~= "" then
            self.db.spotNames[key] = mine
            return mine
        end
    end
    if key == "a556" then return "The Loch" end
    local known = self.db.spotNames[key]
    if self:SpotLabelProblem(key) then return nil end
    -- A shared Stormwind label from Russian clients. Keep the original
    -- metadata, but display the client's area label when available.
    local map = tonumber(key:match("^n(%d+):")) or (self.db.spotWhere[key] and self.db.spotWhere[key].map)
    if known == "Парк" and map == 1453 then
        local park = AreaID("The Park")
        return park and C_Map.GetAreaInfo(park) or "The Park"
    end
    local _, alias = AliasKey(self, map, key, known)
    if alias then return alias end
    if known and known ~= "" and not self:IsSpotKey(known) then return known end
    return nil
end

-- Every kind of spot key but the area one carries the map it is on, so
-- a spot nobody has placed can still say which zone it is in.
function MF:MapOfKey(key)
    if type(key) ~= "string" then return nil end
    return tonumber(key:match("^n(%d+):%d+$")
        or key:match("^(%d+)@%d+,%d+$")
        or key:match("^(%d+)$"))
end

function MF:SpotName(key)
    if not key then return "?" end
    local known = self:KnownSpotName(key)
    if known then return known end
    -- Nobody has told us what this water is called. The zone it's in is
    -- worth more to a reader than the key - and reading the map out of
    -- the key covers the spots that arrived with no position at all,
    -- which were the ones showing a raw n1434:1867096699 on the board.
    local where = self.db.spotWhere[key]
    local zone = self:ZoneNameFor(where and where.map or self:MapOfKey(key))
    return zone or key
end

-- The zone's English name, for fish data and bounties. Falls back to the
-- client's own wording, which is correct on English clients.
function MF:ZoneEnglish()
    return self.ZONE_IDS[self:MapID()] or (self:Location())
end

-- How far the player is from a point, in map units (0-1 across the zone).
-- Returns nil if we can't tell. Always uses a fresh position.
function MF:DistanceFrom(mapID, x, y)
    if not mapID or not x or not y then return end
    if self:MapID() ~= mapID then return end
    local px, py = self:PlayerPos()
    if not px then return end
    local dx, dy = px - x, py - y
    return math.sqrt(dx * dx + dy * dy)
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

MF:Command("where", "Other", "/tfl where [spot] - where you are, or how to find a spot",
    function(self, args, raw)
        if raw and raw ~= "" then
            local wanted = raw:lower()
            local best
            for key, name in pairs(self.db.spotNames) do
                local at = name:lower():find(wanted, 1, true)
                -- The closest thing to a match: the name that starts with
                -- what was typed, else the shortest name containing it.
                if at and (not best or at < best.at or (at == best.at and #name < best.len)) then
                    best = { key = key, at = at, len = #name }
                end
            end
            if not best then
                self:Print(("No spot called \"%s\" - the addon only knows the waters it has heard about.")
                    :format(raw))
                return
            end
            self:PointToSpot(best.key)
            return
        end

        local zone, sub = self:Location()
        self:Print(("You are at %s (%s)."):format(sub, zone))
        self:Debug(("spot key %s, map %d"):format(self:SpotKey(), self:MapID()))
    end)

-- Writes this client's zone list to saved variables so the English name <->
-- map ID table can be filled in.
MF:Command("dumpzones", "Other", nil, function(self)
    local dump = {}
    for id = 1, MAX_MAP_ID do
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        if info and info.name and info.name ~= "" then
            dump[id] = info.name .. "|" .. (info.mapType or 0)
        end
    end
    self.db.mapDump = dump
    self:Print(("Dumped %d maps to saved variables. Log out, then the table can be read from "
        .. "WTF\\Account\\<id>\\SavedVariables\\TheFishingLog.lua"):format(self.Count(dump)))
end)
