-- Social catch reports are transient messages, never TFL_CATCH events.
-- They cannot award progress or write another player's fish into our log.
local _, MF = ...
local serial = 0
local seen, lastShown, whisperPeers = {}, {}, {}
local PEER_LIFETIME, MAX_WHISPER_PEERS = 1200, 2

function MF:NearbyPeerMap()
    return self.db.settings.nearbyCatches and self:MapID() or 0
end

function MF:NoteNearbyPeer(sender, map)
    map = tonumber(map)
    if not map or map ~= math.floor(map) or map < 0 or map > 3000 or self:IsMe(sender) then return end
    local key = self:AnglerKey(sender)
    if key == "" then return end
    if map == 0 then whisperPeers[key] = nil return end
    whisperPeers[key] = { name = sender, map = map, at = GetTime() }
end

function MF:NearbyWhisperPeers(map)
    local names, now = {}, GetTime()
    if not self.db.settings.nearbyCatches or not map or map <= 0 then return names end
    for key, peer in pairs(whisperPeers) do
        if now - peer.at >= PEER_LIFETIME then
            whisperPeers[key] = nil
        elseif peer.map == map and #names < MAX_WHISPER_PEERS then
            local target = self:WhisperName(peer.name)
            if target and target ~= "" then names[#names + 1] = target end
        end
    end
    return names
end
MF.nearbyDiag = { attempted = 0, sent = 0, received = 0, shown = 0 }

function MF:CatchIsNearby(key, map, x, y)
    local ours = self:CurrentSpot()
    if not (x and y and ours.x and ours.y) then
        return map == ours.mapID and self:CanonicalKey(key) == self:CanonicalKey(ours.key)
    end
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local okA, continentA, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
        local okB, continentB, b = pcall(C_Map.GetWorldPosFromMapPos, ours.mapID, CreateVector2D(ours.x, ours.y))
        if okA and okB and continentA == continentB and a and b and a.GetXY and b.GetXY then
            local ax, ay = a:GetXY()
            local bx, by = b:GetXY()
            if type(ax) == "number" and type(ay) == "number" and type(bx) == "number" and type(by) == "number" then
                return (ax-bx)^2 + (ay-by)^2 <= 100^2
            end
        end
    end
    return map == ours.mapID and (x-ours.x)^2 + (y-ours.y)^2 <= 0.02^2
end

function MF:ShareNearbyCatch(c)
    self.nearbyDiag.attempted = self.nearbyDiag.attempted + 1
    if not self.db.settings.nearbyCatches or c.test or c.junk or self:InMatch() then return end
    serial = serial + 1
    local spot = c.spot
    local roads = self:SendNearby("NCATCH1", c.at or GetServerTime(), serial, c.itemID,
        self:EncodeWeight(c.weight), c.specimen and 1 or 0, spot.key, spot.mapID,
        spot.x and math.floor(spot.x * 10000 + 0.5) or "",
        spot.y and math.floor(spot.y * 10000 + 0.5) or "", self:MyFaction())
    if roads and roads > 0 then self.nearbyDiag.sent = self.nearbyDiag.sent + 1
    else self.nearbyDiag.lastReject = "no channel, guild, group or confirmed nearby peer route available" end
end
MF:On("TFL_CATCH", MF.ShareNearbyCatch)

function MF.handlers.NCATCH1(self, sender, at, seq, item, weight, specimen, key, map, x, y, faction)
    self.nearbyDiag.received = self.nearbyDiag.received + 1
    local function Reject(reason) self.nearbyDiag.lastReject = reason end
    if not self.db.settings.nearbyCatches then Reject("nearby sharing is disabled") return end
    if self:IsMe(sender) then return end
    if faction ~= self:MyFaction() then Reject("different faction") return end
    local function Integer(value)
        local n = tonumber(value)
        return n and n >= 0 and n < math.huge and n == math.floor(n) and n or nil
    end
    at, seq, item, weight, map = Integer(at), Integer(seq), Integer(item), Integer(weight), Integer(map)
    if not at or not seq or seq == 0 or not item or item == 0 or not weight or weight == 0 or not map
        or not self:IsSpotKey(key) or #key > 80 or (specimen ~= "0" and specimen ~= "1") then Reject("invalid catch fields") return end
    if at < GetServerTime() - 10 or at > GetServerTime() + 5 then Reject("catch message expired or clock differs") return end
    if (x == "") ~= (y == "") then return end
    if x ~= "" then
        x, y = Integer(x), Integer(y)
        if not x or not y or x > 10000 or y > 10000 then return end
        x, y = x / 10000, y / 10000
    else x, y = nil, nil end
    local w = weight / 100
    if w > self:MaxWeight(item) or self:IsKnownJunk(item) then return end
    if not self:CatchIsNearby(key, map, x, y) then Reject("too far away or missing compatible location") return end
    local identity = self:AnglerKey(sender)
    local token = identity .. ":" .. at .. ":" .. seq
    local now = GetTime()
    if seen[token] then return end
    seen[token] = now
    local _, _, percentile = self:WeightGrade(item, w)
    if self.db.settings.nearbyNotableOnly and specimen ~= "1" and (not percentile or percentile < 0.9) then Reject("notable-only filter") return end
    -- Distinct bonus fish may share a timestamp. Dedupe by catch identity,
    -- never by the angler's last display time (which could hide specimens).
    lastShown[identity] = now
    self:WithFishName(item, function(name)
        if not self.db.settings.nearbyCatches or not self:CatchIsNearby(key, map, x, y) then return end
        local grade = specimen == "1" and (self.C.spec .. "Specimen|r") or self:GradeText(item, w)
        self:Print(("%s%s|r caught %s - %s%s"):format(self.C.hint, self:ShortName(sender), name,
            self:Weight(w), grade ~= "" and (" " .. grade) or ""))
        self.nearbyDiag.shown = self.nearbyDiag.shown + 1
    end)
end

MF:OnTick(function()
    local cutoff = GetTime() - 15
    for key, at in pairs(seen) do if at < cutoff then seen[key] = nil end end
    for key, at in pairs(lastShown) do if at < cutoff then lastShown[key] = nil end end
end)

MF:Command("nearby", "Other", "/tfl nearby [all|notable|off|status] - nearby anglers' catches", function(self, args)
    local mode = args[1]
    if mode == "status" then
        local d, spot = self.nearbyDiag, self:CurrentSpot()
        self:Print(("Nearby: %s; attempted %d, sent %d, received %d, displayed %d."):format(
            self.db.settings.nearbyCatches and (self.db.settings.nearbyNotableOnly and "notable only" or "all") or "off",
            d.attempted, d.sent, d.received, d.shown))
        self:Print(("Routes: channel %s, guild %s, group %s, quiet peers %d. Spot %s, map %s."):format(
            self:ChannelID() and "joined" or "not joined", IsInGuild() and "yes" or "no",
            IsInGroup() and "yes" or "no", #self:NearbyWhisperPeers(spot.mapID), spot.key, tostring(spot.mapID)))
        self:Print("Last filtered report: " .. (d.lastReject or "none"))
        return
    end
    if mode == "off" then self.db.settings.nearbyCatches = false
    elseif mode == "all" or mode == "notable" then
        self.db.settings.nearbyCatches = true
        self.db.settings.nearbyNotableOnly = mode == "notable"
    elseif not mode then self.db.settings.nearbyCatches = not self.db.settings.nearbyCatches
    else self:Print("Use /tfl nearby all, notable or off.") return end
    self:Print("Nearby catches: " .. (self.db.settings.nearbyCatches
        and (self.db.settings.nearbyNotableOnly and "notable only" or "all") or "off"))
end)

function MF:ResetNearbyCatches()
    serial,seen,lastShown=0,{},{}
    whisperPeers = {}
    self.nearbyDiag={attempted=0,sent=0,received=0,shown=0}
end
