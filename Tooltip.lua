-- Tooltip: Fishing Log details on fish item tooltips and player tooltips.
--
-- Fish items: your best, catch count and today's bounty; hold Shift for the
-- specimen range, native waters, the record where you're standing and your
-- journal progress.
--
-- Players: angler rank and title, and what they're doing right now; hold
-- Shift for their best catch. Other players' details come from messages we
-- already receive (census, matches) plus a small whisper lookup (INFOQ ->
-- INFO) the first time you hover someone.
local _, MF = ...

local ASK_COOLDOWN = 60    -- seconds before asking the same player again
local STALE_AFTER = 120    -- seconds before a player's details count as old
local REPLY_COOLDOWN = 10  -- seconds between our answers to the same asker
local TITLE_CACHE = 15     -- seconds to reuse the King scan
local SPECIMEN_HUNTER = 3  -- species with a specimen needed for the title
local MAX_ZONES_SHOWN = 3

-- Small fishing icon (borders cropped) so our block is easy to spot among
-- other addons' tooltip lines.
local ICON = "|TInterface\\Icons\\Trade_Fishing:14:14:0:0:64:64:5:59:5:59|t "
local LABEL = ICON .. MF.C.brand .. "Fishing Log:|r "
local GOLD, GREY, WHITE = "|cffffd100", "|cff9d9d9d", "|cffffffff"

-- A place on the realm wears the colour of the medal it would have won.
-- There was a trophy here too, but the icon isn't in this client's art and
-- a missing texture draws as a silent hole, so the colour does the work.
local PLACE_COLOUR = { MF.C.gold, MF.C.silver, MF.C.bronze }

local function Ordinal(n)
    local last, tens = n % 10, n % 100
    if tens >= 11 and tens <= 13 then return n .. "th" end
    if last == 1 then return n .. "st" end
    if last == 2 then return n .. "nd" end
    if last == 3 then return n .. "rd" end
    return n .. "th"
end

-- Keyed by angler, not by name: the same player reaches us as "Julise Regen"
-- from the game and "Julise-Regen" from their own client, and details filed
-- under one spelling are no use to a tooltip looking under the other.
MF.anglers = {}

function MF:NoteAngler(name, fields)
    if not name then return end
    local key = self:AnglerKey(name)
    if key == "" then return end
    local a = self.anglers[key]
    if not a then
        a = { name = name }
        self.anglers[key] = a
    end
    for k, v in pairs(fields) do a[k] = v end
    a.at = GetTime()
end

function MF:AnglerInfo(name)
    return name and self.anglers[self:AnglerKey(name)] or nil
end

------------------------------------------------------------------------
-- Titles
------------------------------------------------------------------------

local kingsCache, kingsAt = {}, -math.huge

-- name -> list of spot names they're King of. Rebuilt at most every 15s.
local function Kings(self)
    if GetTime() - kingsAt < TITLE_CACHE then return kingsCache end
    kingsCache, kingsAt = {}, GetTime()
    for key in pairs(self.db.spots) do
        local king = self:King(key)
        if king then
            local holder = self:AnglerKey(king.h)
            kingsCache[holder] = kingsCache[holder] or {}
            table.insert(kingsCache[holder], self:SpotName(key))
        end
    end
    return kingsCache
end

local function Title(self, name, specSpecies, champUntil)
    if self:IsChampion(name, champUntil) then return "Tournament Champion" end
    local spots = Kings(self)[self:AnglerKey(name)]
    if spots then
        table.sort(spots)
        return "King of " .. spots[1] .. (#spots > 1 and (" +" .. (#spots - 1)) or "")
    end
    if (specSpecies or 0) >= SPECIMEN_HUNTER then return "Specimen Hunter" end
end

------------------------------------------------------------------------
-- What we tell others about ourselves (and show on our own tooltip)
------------------------------------------------------------------------

function MF:MyAnglerInfo()
    local p = self.cdb.profile
    local info = { rank = self:MyRank(), xp = p.xp, bestW = 0, specSpecies = 0, champUntil = p.champUntil }
    for id, j in pairs(p.journal) do
        if j.b > info.bestW then
            info.bestID, info.bestW, info.bestSpec = id, j.b, j.s > 0 and j.s >= j.b
        end
        if j.s > 0 then info.specSpecies = info.specSpecies + 1 end
    end
    if self:InMatch() then
        local m = self.current
        local standings = self:Standings(m)
        info.status, info.spotName, info.players = "m", m.name, #standings
        for i, s in ipairs(standings) do
            if self:IsMe(s.name) then info.place = i end
        end
    elseif self:IsSessionRunning() then
        info.status, info.spotName, info.count = "f", self.session.sub, self.session.count
    end
    return info
end

local function Clean(s) return (tostring(s or ""):gsub("~", " ")) end

local lastReply = {} -- asker -> GetTime()

function MF.handlers.INFOQ(self, sender)
    if GetTime() - (lastReply[sender] or -math.huge) < REPLY_COOLDOWN then return end
    lastReply[sender] = GetTime()
    local i = self:MyAnglerInfo()
    self:Whisper(sender, "INFO", i.rank, i.xp, i.status or "", Clean(i.spotName), i.count or 0,
        i.place or 0, i.players or 0, i.bestID or 0, self:EncodeWeight(i.bestW),
        i.bestSpec and 1 or 0, i.specSpecies, i.champUntil or 0)
end

local hoveredName -- the player whose tooltip is showing, to refresh it

local function RefreshTooltip()
    -- Rebuilding a Blizzard tooltip from addon execution can propagate
    -- taint into secret colour tables. Let the client rebuild on hover.
    if InCombatLockdown() or type(issecretvalue) == "function" then return end
    if GameTooltip:IsShown() and GameTooltip.RefreshData then
        GameTooltip:RefreshData()
    end
end

function MF.handlers.INFO(self, sender, rank, xp, status, spotName, count, place, players,
                          bestID, bestW, bestSpec, specSpecies, champUntil)
    local anglerRank = self:RankFromWire(rank, xp)
    if not anglerRank then return end
    self:NoteAngler(sender, {
        rank = anglerRank, xp = tonumber(xp), status = status ~= "" and status or nil,
        spotName = spotName, count = tonumber(count), place = tonumber(place),
        players = tonumber(players), bestID = tonumber(bestID) ~= 0 and tonumber(bestID) or nil,
        bestW = self:DecodeWeight(bestW), bestSpec = bestSpec == "1",
        specSpecies = tonumber(specSpecies) or 0, champUntil = tonumber(champUntil) or 0, full = true,
    })
    self:NoteCensusReply(sender)
    if self:SameAngler(sender, hoveredName) then RefreshTooltip() end
end

------------------------------------------------------------------------
-- Player tooltips
------------------------------------------------------------------------

local asked = {} -- angler key -> GetTime() we last asked

function MF:RequestAnglerInfo(name, nearby)
    local now = GetTime()
    local key = self:AnglerKey(name)
    local known = self:AnglerInfo(name)
    if nearby and now < (self.nextNameplateLookup or 0) then return end
    if known and known.full and now - known.at < STALE_AFTER then return end
    if now - (asked[key] or -math.huge) < ASK_COOLDOWN then return end
    asked[key] = now
    if nearby then self.nextNameplateLookup = now + 3 end
    self.infoAsks = self.infoAsks or {}
    self.infoAsks[key] = { at = now, to = self:WhisperName(name) }
    self:Whisper(name, "INFOQ")
end

function MF:AnglerUnitIdentity(unit)
    if not unit or self:IsSecret(unit) then return end
    local player = UnitIsPlayer(unit)
    if self:IsSecret(player) or not player then return end
    local name, realm = UnitFullName(unit)
    if self:IsSecret(name) or self:IsSecret(realm) or type(name) ~= "string" or name == "" then return end
    local plain, embeddedRealm = self:SplitName(name)
    realm = embeddedRealm or (realm ~= "" and realm) or self:RealmName()
    return self:FullName(plain, realm), plain, realm
end

local function AddPlayerLines(self, tt, name, info)
    local rankName = info.rank and self:RankName(info.rank)
    if not rankName then return end
    local title = Title(self, name, info.specSpecies, info.champUntil)
    tt:AddLine(" ") -- keep our block apart from other addons' lines
    tt:AddLine(LABEL .. WHITE .. rankName .. "|r" .. (title and (" - " .. GOLD .. title .. "|r") or ""))

    -- Where they stand among everyone whose records we've heard about.
    local place, total = self:RealmRank(name)
    if place then
        local colour = PLACE_COLOUR[place] or (place <= 10 and WHITE or GREY)
        local crown = place == 1 and (" " .. GOLD .. "- top angler|r") or ""
        tt:AddLine(("%s%s of %d on the realm|r%s"):format(colour, Ordinal(place), total, crown))
    end

    if info.status == "m" then
        local placeText = (info.place or 0) > 0 and (" (%d of %d)"):format(info.place, info.players or 0) or ""
        tt:AddLine(("In a match at %s%s"):format(info.spotName or "?", placeText), 0.6, 0.9, 1)
    elseif info.status == "f" then
        tt:AddLine(("Fishing at %s - %d fish"):format(info.spotName or "?", info.count or 0), 0.6, 0.9, 1)
    end

    if not info.bestID then return end
    if IsShiftKeyDown() then
        tt:AddLine(("Best: %s %s%s"):format(MF:Weight(info.bestW), self:FishName(info.bestID),
            info.bestSpec and (" " .. GOLD .. "(specimen)|r") or ""), 0.8, 0.8, 0.8)
        if (info.specSpecies or 0) > 0 then
            tt:AddLine(("Specimens: %d species"):format(info.specSpecies), 0.8, 0.8, 0.8)
        end
    else
        tt:AddLine(GREY .. "Hold Shift for more|r")
    end
end

local function OnUnitTooltip(self, tt, data)
    if not self.db.settings.tooltipPlayers or not self.me then return end
    local _, unit = tt:GetUnit()
    if not self:IsSecret(unit) and not unit and tt == GameTooltip and not self:IsSecret(data) and type(data) == "table" then
        local guid, mouseover = data.guid, UnitGUID("mouseover")
        if not self:IsSecret(guid) and not self:IsSecret(mouseover) and guid and guid == mouseover then
            unit = "mouseover"
        end
    end
    local name = self:AnglerUnitIdentity(unit)
    if not name then return end
    hoveredName = name

    if self:IsMe(name) then
        AddPlayerLines(self, tt, name, self:MyAnglerInfo())
        return
    end
    -- Only players who could be running the addon with us: same faction.
    local faction, ours = UnitFactionGroup(unit), UnitFactionGroup("player")
    if self:IsSecret(faction) or self:IsSecret(ours) or not faction or faction ~= ours then return end
    local known = self:AnglerInfo(name)
    self:RequestAnglerInfo(name)
    if known then AddPlayerLines(self, tt, name, known) end
end

------------------------------------------------------------------------
-- Fish item tooltips
------------------------------------------------------------------------

local function ZoneList(zones)
    local shown = {}
    for i = 1, math.min(MAX_ZONES_SHOWN, #zones) do shown[i] = zones[i] end
    local text = table.concat(shown, ", ")
    if #zones > MAX_ZONES_SHOWN then
        text = text .. (" +%d more"):format(#zones - MAX_ZONES_SHOWN)
    end
    return text
end

-- Counts only fish you've caught in this zone, like the journal does.
local function JournalProgress(self, zone)
    local total, caught = 0, 0
    for id, f in pairs(self.FISH) do
        local index = self:ZoneIndexFor(id, zone)
        if index then
            total = total + 1
            if self:CaughtInZone(self:JournalEntry(id), index) then caught = caught + 1 end
        end
    end
    return caught, total
end

local function AddItemLines(self, tt, itemID)
    local f = self.FISH[itemID]
    local j = self:JournalEntry(itemID)
    local trophy = self.TROPHY[itemID]
    local _, bountyID, bountyZone = self:TodayBounty()
    if not f and not j and not trophy and itemID ~= bountyID then return end

    tt:AddLine(" ") -- keep our block apart from other addons' lines
    if j then
        tt:AddLine(LABEL .. WHITE .. ("Your best %s - caught %d|r"):format(MF:Weight(j.b), j.c)
            .. (j.s > 0 and (" " .. GOLD .. "(specimen)|r") or ""))
    else
        tt:AddLine(LABEL .. GREY .. "not in your journal yet|r")
    end
    if itemID == bountyID then
        tt:AddLine(("Today's bounty fish (%s)"):format(bountyZone), 1, 0.82, 0)
    end
    if trophy then
        tt:AddLine(("A trophy fish - always %d lb and a few ounces"):format(trophy), 0.8, 0.8, 0.8)
    end
    if not f then return end

    if not IsShiftKeyDown() then
        tt:AddLine(GREY .. "Hold Shift for more|r")
        return
    end

    if self:ValueEnabled() then
        local copper, source = self:FishValue(itemID)
        if copper then
            tt:AddLine(("Worth about %s (%s)"):format(self:Money(copper), source), 0.8, 0.8, 0.8)
        end
    end
    if j and j.s > 0 then
        local lo, hi = self:SpecimenRange(f)
        tt:AddLine(("Specimens: %s"):format(MF:WeightRange(lo, hi)), 1, 0.82, 0)
    else
        tt:AddLine("Specimen: ???", 0.6, 0.6, 0.6)
    end
    if f.zones then
        tt:AddLine("Native to: " .. ZoneList(f.zones), 0.8, 0.8, 0.8, true)
    end

    local spot = self:CurrentSpot()
    local s = self:Spot(spot.key)
    local rec = s and s.fish[itemID]
    if rec then
        tt:AddLine(("Record at %s: %s by %s"):format(spot.name, MF:Weight(rec.w), self:ShortName(rec.h)),
            0.8, 0.8, 0.8)
    end

    local zone = self:ZoneEnglish()
    if self:IsNative(itemID, zone) and f.zones then
        local caught, total = JournalProgress(self, zone)
        tt:AddLine(("Journal: %d/%d in %s"):format(caught, total, zone), 0.8, 0.8, 0.8)
    end
end

local function OnItemTooltip(self, tt, itemID)
    if not self.db.settings.tooltipItems or not itemID then return end
    AddItemLines(self, tt, itemID)
end

------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------

local SHOWN_ON = {} -- tooltips we decorate (not comparison/shopping tooltips)

-- Tooltip contents can be restricted ("secret") in combat or instances on
-- Midnight-era clients; if reading them fails, skip quietly.
local function Safe(fn)
    return function(tt, ...)
        if InCombatLockdown() then return end
        if not SHOWN_ON[tt] then return end
        pcall(fn, MF, tt, ...)
    end
end

MF:On("TFL_INIT", function(self)
    SHOWN_ON[GameTooltip] = true
    if ItemRefTooltip then SHOWN_ON[ItemRefTooltip] = true end

    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
            Safe(function(_, tt, data)
                if self:IsSecret(data) or type(data) ~= "table" then return end
                local id = data.id
                if not self:IsSecret(id) then OnItemTooltip(self, tt, id) end
            end))
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,
            Safe(function(_, tt, data) OnUnitTooltip(self, tt, data) end))
    else
        GameTooltip:HookScript("OnTooltipSetItem", Safe(function(_, tt)
            local _, link = tt:GetItem()
            OnItemTooltip(self, tt, link and tonumber(link:match("item:(%d+)")))
        end))
        GameTooltip:HookScript("OnTooltipSetUnit", Safe(function(_, tt) OnUnitTooltip(self, tt) end))
    end
end)

-- Pressing or releasing Shift redraws the tooltip with more or less detail.
MF:On("MODIFIER_STATE_CHANGED", function(_, key)
    if key == "LSHIFT" or key == "RSHIFT" then RefreshTooltip() end
end)

GameTooltip:HookScript("OnHide", function() hoveredName = nil end)

function MF:ResetAnglerState()
    self.anglers={}
    self.nextNameplateLookup = nil
    asked,lastReply,kingsCache={},{},{}
    kingsAt,hoveredName=-math.huge,nil
end
