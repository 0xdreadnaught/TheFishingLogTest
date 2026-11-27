-- Independent pool observations. A hover plus a genuine fishing catch is
-- evidence of use; fish item types alone never establish a pool.
local _, MF = ...
local hover, pending
local MAX_NODES, MERGE_RADIUS = 3000, 0.003
-- Named pool objects from FishFry's shared reference. Trap interactables
-- and generic water contexts are deliberately excluded.
local SPECIAL_POOLS = {
    ["floating debris"] = true, ["floating wreckage"] = true,
    ["waterlogged wreckage"] = true, ["bloodsail wreckage"] = true,
    ["inland oil spill"] = true, ["oil spill"] = true, ["muddy churning waters"] = true,
}

function MF:PoolName(name)
    if type(name) ~= "string" or #name < 3 or #name > 80 or name:find("[%c~;,|]") then return end
    name = strtrim(name)
    local lower = name:lower()
    if lower:find("school", 1, true) or lower:find("swarm", 1, true)
        or lower:find("pool", 1, true) or SPECIAL_POOLS[lower] then return strtrim(name) end
end

-- Shared sightings age out, and one sender can only add so many new places
-- a session, so nobody can fill the atlas with fakes for good. Your own
-- observations never expire.
local SHARED_AGE = 60 * 86400
local NEW_PER_SENDER = 150
local addedBy = {} -- angler key -> new nodes accepted from them this session

function MF:PrunePools()
    local atlas, cutoff = self.db.poolAtlas or {}, GetServerTime() - SHARED_AGE
    for i = #atlas, 1, -1 do
        local node = atlas[i]
        if type(node) ~= "table" or (not node.mine and (tonumber(node.at) or 0) < cutoff) then
            table.remove(atlas, i)
        end
    end
end
MF:On("TFL_LOGIN", function(self) self:PrunePools() end)

-- Who saw a pool with their own eyes, with the faction they fished it as.
-- Only first-hand sightings count: your own catches, a live POOL1 from the
-- angler who just fished it, or an atlas entry its sender marks as their own.
-- A relayed entry adds no witness, so passing an atlas around can't make one
-- pool look like many anglers' find. A handful is plenty to tell one report
-- from several, and the cap keeps a node small however often it's seen.
local MAX_WITNESSES = 6

local function AddWitness(self, node, key, letter)
    if type(key) ~= "string" or key == "" then return end
    node.by = type(node.by) == "table" and node.by or {}
    if node.by[key] then
        if node.by[key] == "?" and letter then node.by[key] = letter end
        return
    end
    if self.Count(node.by) >= MAX_WITNESSES then return end
    node.by[key] = letter or "?"
end

-- How far apart two points on one map are, as a fraction of the merge
-- distance: 1 is exactly MERGE_YARDS. Measured in yards where the zone's
-- size is known, so a duplicate is the same distance in every zone; the
-- old map-fraction radius was an oval 21 x 14 yards in Tanaris and a
-- different size everywhere else. The fraction is the fallback.
local MERGE_YARDS = 25
function MF:PoolGap(map, x1, y1, x2, y2, yards)
    yards = yards or MERGE_YARDS
    -- Called directly: "a and f()" would keep only the first return value.
    local w, h
    if self.FrenzyMapSize then w, h = self:FrenzyMapSize(map) end
    if w and h and w > 0 and h > 0 then
        return math.sqrt(((x1 - x2) * w)^2 + ((y1 - y2) * h)^2) / yards
    end
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2) / (MERGE_RADIUS * yards / MERGE_YARDS)
end

-- One pass over what's already saved, so atlases filled under the old
-- radius match what the new one keeps: same-type duplicates within the
-- merge distance become one node. The newest sighting keeps its place,
-- the others give up their time, ownership and witnesses to it. Maps with
-- no known size are left alone rather than merged on a guess.
local TIDY = 1
local function Tidy(self)
    if self.db.poolTidy == TIDY then return end
    local atlas = self.db.poolAtlas
    if type(atlas) ~= "table" or #atlas == 0 then self.db.poolTidy = TIDY return end
    if not (self.FrenzyMapSize and select(1, self:FrenzyMapSize(1446))) then return end -- library not up yet
    local order = {}
    for i, node in ipairs(atlas) do order[i] = node end
    table.sort(order, function(a, b) return (a.at or 0) > (b.at or 0) end)
    local kept, gone = {}, {}
    for _, node in ipairs(order) do
        local into
        if self:FrenzyMapSize(node.map) then
            local lower = node.name:lower()
            for _, k in ipairs(kept) do
                if k.map == node.map and k.name:lower() == lower
                    and self:PoolGap(node.map, k.x, k.y, node.x, node.y) <= 1 then into = k break end
            end
        end
        if into then
            into.at = math.max(into.at or 0, node.at or 0)
            into.mine = into.mine or node.mine or false
            for key, letter in pairs(type(node.by) == "table" and node.by or {}) do
                AddWitness(self, into, key, letter)
            end
            gone[node] = true
        else
            kept[#kept + 1] = node
        end
    end
    local before = #atlas
    for i = #atlas, 1, -1 do
        if gone[atlas[i]] then table.remove(atlas, i) end
    end
    self.db.poolTidy = TIDY
    self.poolTidied = before - #atlas
    if self.RefreshPoolPins then self:RefreshPoolPins() end
end
MF:On("TFL_LOGIN", function(self) Tidy(self) end)
MF:OnTick(function(self) if self.db.poolTidy ~= TIDY then Tidy(self) end end)

-- Horde, Alliance and unknown witness counts for one atlas node.
function MF:PoolWitnesses(node)
    local h, a, u = 0, 0, 0
    for key, letter in pairs(type(node.by) == "table" and node.by or {}) do
        if letter == "?" then letter = self.db.factions[key] or "?" end
        if letter == "H" then h = h + 1 elseif letter == "A" then a = a + 1 else u = u + 1 end
    end
    return h, a, u
end

function MF:MergePool(name, map, x, y, at, mine, sender, witnessed)
    name, map, x, y, at = self:PoolName(name), tonumber(map), tonumber(x), tonumber(y), tonumber(at)
    if not name or not map or map < 1 or map > 3000 or map ~= math.floor(map)
        or not x or not y or x < 0 or x > 1 or y < 0 or y > 1
        or x ~= x or y ~= y or not at or at < 1 or at > GetServerTime() + 60
        or at ~= math.floor(at) then return end
    if GetServerTime()>=self.FRESH_START and at<self.FRESH_START then return end
    if not mine and at < GetServerTime() - SHARED_AGE then return end
    self.db.poolAtlas = self.db.poolAtlas or {}
    local atlas, match, distance = self.db.poolAtlas, nil, math.huge
    local lower = name:lower()
    for _, node in ipairs(atlas) do
        if node.map == map and node.name:lower() == lower then
            local d = self:PoolGap(map, node.x, node.y, x, y)
            if d <= 1 and d < distance then match, distance = node, d end
        end
    end
    local witness, letter
    if mine then
        witness, letter = self:AnglerKey(self.me), self:MyFaction()
    elseif witnessed and sender then
        witness, letter = self:AnglerKey(sender), self:FactionOf(sender)
    end
    if match then
        local changed = at > match.at
        match.at = math.max(match.at, at)
        match.mine = match.mine or mine or false
        if witness then AddWitness(self, match, witness, letter) end
        return match, changed
    end
    if #atlas >= MAX_NODES then
        self:PrunePools()
        if #atlas >= MAX_NODES then return nil, false, false, "full" end
    end
    local who = sender and self:AnglerKey(sender)
    if who and who ~= "" then
        if (addedBy[who] or 0) >= NEW_PER_SENDER then return nil, false, false, "sender" end
        addedBy[who] = (addedBy[who] or 0) + 1
    end
    local node = { name = name, map = map, x = x, y = y, at = at, mine = mine or false }
    if witness then AddWitness(self, node, witness, letter) end
    atlas[#atlas + 1] = node
    return node, true, true
end

function MF:ObservePool(name, map, x, y)
    local node, changed, created, reason = self:MergePool(name, map, x, y, GetServerTime(), true)
    if reason == "full" and GetTime() >= (self.poolFullNoticeAt or 0) then
        self.poolFullNoticeAt = GetTime() + 300
        self:Print("Pool atlas is full (3,000 locations). This new location was not saved. Existing locations still update; /tfl pools status shows atlas usage.")
    end
    if created then self:Print("Pool location saved: " .. node.name .. ". Availability is unknown.") end
    if node and changed and self.db.settings.poolSharing ~= false then
        self:SendWide("POOL1", node.name, node.map, math.floor(node.x * 10000 + 0.5),
            math.floor(node.y * 10000 + 0.5), node.at)
    end
    if node then self.poolRefreshAt = nil end
    return node, reason
end

local function TooltipName()
    local tooltip = _G.GameTooltip
    if tooltip and type(tooltip.GetOwner) == "function" then
        local owner = tooltip:GetOwner()
        if owner and owner ~= UIParent and owner ~= _G.WorldFrame then return end
    end
    if tooltip and type(tooltip.GetUnit) == "function" then
        local _, unit = tooltip:GetUnit()
        if unit then return end
    end
    local line = _G.GameTooltipTextLeft1
    if not line or type(line.GetText) ~= "function" then return end
    local name = line:GetText()
    if issecretvalue and issecretvalue(name) then return end
    return MF:PoolName(name)
end

function MF:CheckPoolHover()
    local self = MF
    if self:IsCasting() then return end
    local name = TooltipName()
    if not name then return end
    local x, y = self:PlayerPos()
    if x and y then hover = { name = name, map = self:MapID(), x = x, y = y, seen = GetTime() } end
end
MF:On("TFL_INIT", function()
    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        local elapsed = 0
        GameTooltip:HookScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= 0.15 then elapsed = 0 MF:CheckPoolHover() end
        end)
    end
end)
MF:OnTick(function(self) self:CheckPoolHover() end)

MF:On("TFL_FISHING_CAST", function(self)
    local name = TooltipName()
    local x, y = self:PlayerPos()
    if name and x and y then hover = { name = name, map = self:MapID(), x = x, y = y, seen = GetTime() } end
    pending = nil
    if hover and GetTime() - hover.seen <= 10 and hover.map == self:MapID() and x and y
        and (hover.x - x)^2 + (hover.y - y)^2 <= 0.01^2 then
        pending = { name = hover.name, map = hover.map, x = x, y = y, cast = GetTime() }
    end
end)

-- Was this cast aimed at a pool we had just hovered? For catch statistics,
-- which keep pool and open-water casts apart.
function MF:PoolCastPending()
    return pending ~= nil and GetTime() - pending.cast <= 40
end

function MF:LogPoolCatch(catch)
    if catch.test or not pending then return end
    local observation = pending
    pending = nil
    if GetTime() - observation.cast > 40 or self:MapID() ~= observation.map then return end
    self:ObservePool(observation.name, observation.map, observation.x, observation.y)
end
MF:On("TFL_CATCH", MF.LogPoolCatch)

local function Receive(self, sender, name, map, x, y, at, witnessed)
    if self.db.settings.poolSharing == false then return end
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end
    local node, changed = self:MergePool(name, map, x / 10000, y / 10000, at, false, sender, witnessed)
    if changed then self.syncDiagnostics.pools = self.syncDiagnostics.pools + 1 end
    if node then self.poolRefreshAt = nil end
end

-- Sent the moment the sender lands a catch from the pool: first-hand.
function MF.handlers.POOL1(self, sender, name, map, x, y, at)
    Receive(self, sender, name, map, x, y, at, true)
end

-- A trailing "w" marks a pool this character saw itself. Older clients read
-- five fields and ignore the sixth; entries without it are relayed.
local function Packed(self, node)
    local me = self:AnglerKey(self.me)
    local own = type(node.by) == "table" and me ~= "" and node.by[me] ~= nil
    return table.concat({ node.name, node.map, math.floor(node.x * 10000 + 0.5),
        math.floor(node.y * 10000 + 0.5), node.at, own and "w" or nil }, ",")
end

-- The second field marks a broadcast answer, so everyone else holding the
-- same atlas can stand down. Older clients ignore it.
function MF.handlers.POBOOK1(self, sender, packed, answering)
    if tonumber(answering) then self:MarkAnswered("pools:" .. tonumber(answering)) end
    if self.db.settings.poolSharing == false or type(packed) ~= "string" or #packed > 4000 then return end
    local n = 0
    for entry in packed:gmatch("[^;]+") do
        n = n + 1 if n > 10 then break end
        local name, map, x, y, at, seen = strsplit(",", entry)
        Receive(self, sender, name, map, x, y, at, seen == "w")
    end
end

local replies = {}
local BROADCAST_NODES = 100
function MF.handlers.POREQ1(self, sender, map, cursor)
    map, cursor = tonumber(map), tonumber(cursor) or 0
    if self.db.settings.poolSharing == false or not map or map < 0 or map > 3000 or map ~= math.floor(map)
        or cursor < 0 or cursor >= MAX_NODES or cursor % 300 ~= 0 then return end
    local key = self:AnglerKey(sender) .. ":" .. map .. ":" .. cursor
    if GetTime() - (replies[key] or -math.huge) < 60 then return end
    replies[key] = GetTime()
    local function Nodes()
        local nodes = {}
        for _, node in ipairs(self.db.poolAtlas) do if map == 0 or node.map == map then nodes[#nodes + 1] = node end end
        table.sort(nodes, function(a, b) return a.at > b.at end)
        return nodes
    end
    -- Asked of everyone at once (login, a zone change): one angler answers,
    -- out loud, with the newest page, and the rest hear it and stay quiet.
    -- Every peer whispering its own 300 was a flood landing on one player.
    if self.lastRoad ~= "WHISPER" then
        if cursor > 0 then return end
        self:ReplyOnce("pools:" .. map, 1, 8, function()
            local nodes, batch = Nodes(), {}
            for i = 1, math.min(BROADCAST_NODES, #nodes) do
                batch[#batch + 1] = Packed(self, nodes[i])
                if #batch == 10 or i == math.min(BROADCAST_NODES, #nodes) then
                    self:SendWide("POBOOK1", table.concat(batch, ";"), map)
                    batch = {}
                end
            end
        end)
        return
    end
    self:ReplySoon(1, 8, function()
        local nodes = Nodes()
        -- Bounded pages keep bulk traffic below the live-match queue.
        local batch = {}
        local last = math.min(cursor + 300, #nodes)
        for i = cursor + 1, last do
            batch[#batch + 1] = Packed(self, nodes[i])
            if #batch == 10 or i == last then
                self:Whisper(sender, "POBOOK1", table.concat(batch, ";"))
                batch = {}
            end
        end
        if last < #nodes then self:Whisper(sender, "POEND1", map, last) end
    end)
end

function MF.handlers.POEND1(self, sender, map, cursor)
    map, cursor = tonumber(map), tonumber(cursor)
    if self.db.settings.poolSharing == false or not map or map < 0 or map > 3000 or map ~= math.floor(map)
        or not cursor or cursor <= 0 or cursor >= MAX_NODES or cursor % 300 ~= 0 then return end
    self:Whisper(sender, "POREQ1", map, cursor)
end

function MF:RequestPools(map, peer)
    if self.db.settings.poolSharing == false then return end
    if peer then
        -- Quiet discovery asks only for the current zone, so a roster scan
        -- cannot start multiple realm-wide atlas transfers.
        if map and map > 0 then self:Whisper(peer, "POREQ1", map) end
    else
        self:SendWide("POREQ1", map or 0)
    end
end
MF:On("TFL_SYNC", function(self) self:RequestPools(0) end)
MF:On("ZONE_CHANGED_NEW_AREA", function(self) self:RequestPools(self:MapID()) end)

function MF:ResetPoolObservation() hover,pending,replies,addedBy=nil,nil,{},{} end
