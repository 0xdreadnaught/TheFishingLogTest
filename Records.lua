-- Records: shared per-spot records (all-time and this season) and the King of
-- each spot (holder of its heaviest ever catch).
--
-- There's no server: whoever sets a record announces it (REC2), everyone
-- merges it into their copy, and newcomers to a zone ask for a sync (RREQ2),
-- which one player answers with a packed list (RSYNC2). Spots are keyed by
-- area ID (see Spots.lua) so translated clients and border lakes agree.
--
-- Because the Forever beta doesn't reload saved data, a fresh login knows no
-- records at all. So a catch can't claim a record until the zone has synced
-- (an answer arrives, or nobody answers for a few seconds); catches made
-- before then are held and checked once it has. Your own records are kept
-- in your profile (Profile.lua) and re-announced when you log in.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

local ALERT_WINDOW = 600      -- only shout about records set in the last 10 min
local REQUEST_COOLDOWN = 600  -- per map, once a sync has finished
local SYNC_TIMEOUT = 8        -- seconds to wait for an answer before going ahead
local XP_RECORD, XP_SEASON = 40, 15
local ZONE_SETTLE_DELAY = 3   -- let the map ID update after a zone change

-- Where a spot is travels with its records, so you can find the water
-- someone else's record was set on without having been there. Positions go
-- as whole ten-thousandths: five characters, and finer than anyone can
-- stand. Clients that don't know about them read the fields before and
-- ignore these, so they're always added to the end.
local function PackPos(self,key,mapID)
    local where = self:SpotPosition(key)
    -- Fractions belong to exactly one map, even when records span borders.
    if not where or where.map ~= tonumber(mapID)
        or not self:ValidSpotPosition(key,where.map,where.x,where.y) then return "0", "0" end
    return ("%d"):format(where.x * 10000), ("%d"):format(where.y * 10000)
end

local function UnpackPos(self, key, mapID, x, y)
    x, y = tonumber(x), tonumber(y)
    if x and y and (x > 0 or y > 0) then
        self:MarkSpotPosition(key, mapID, x / 10000, y / 10000)
    end
end

-- s.maps lists every map the spot has been seen from, so a border lake is
-- synced to players on either side.
--
-- Every read and write of a spot comes through here, which is why this is
-- where a key is put right: a record arriving from a client that still
-- knows a named water only as a grid cell lands on the same spot as ours
-- instead of starting a second one.
function MF:Spot(key, create, mapID)
    key = self:CanonicalKey(key)
    local s = self.db.spots[key]
    if not s then
        if not create then return end
        s = { key = key, maps = {}, fish = {}, season = {}, seasonID = self:SeasonID() }
        self.db.spots[key] = s
        -- A new water can be the lowest nameless one on its map, which
        -- is the answer CanonicalKey caches.
        self:ForgetNamelessLow()
    end
    if mapID and mapID ~= 0 and self:SpotMapFits(key,mapID) ~= false then s.maps[mapID] = true end
    if s.seasonID ~= self:SeasonID() then
        -- The month that just ended is kept, not thrown away. Spots belong
        -- to the account and a season's send-off to each character, so the
        -- table has to outlive whichever of them touches the spot first. A
        -- quiet month leaves the last real one where it was.
        if s.season and next(s.season) then
            s.lastSeason, s.lastSeasonID = s.season, s.seasonID
        end
        s.season, s.seasonID = {}, self:SeasonID()
    end
    return s
end

function MF:SpotOnMap(s, mapID)
    return s.maps[mapID] == true and self:SpotMapFits(s.key,mapID) ~= false
end

------------------------------------------------------------------------
-- Struck records
------------------------------------------------------------------------

-- There is no server, so a record is whatever the realm's clients agree it
-- is, and a client that has been tampered with can put one in the book that
-- nobody ever caught. That can't be prevented: records have to be passed on
-- by anglers who didn't set them, or the book would empty every time its
-- holders logged off. What can be done is to take one back out.
--
-- A struck record is named by the catch - the fish, its weight in
-- hundredths and the second it claims - and never by the angler, because a
-- forged record can carry anyone's name and the name it carries is the one
-- person known not to have sent it. One entry removes that catch from every
-- water it was written into.
--
-- The list ships empty. It grows by release, the same way the junk list
-- does: MergeRecord refuses a struck catch from then on, and the sweep
-- below takes it out of books that already hold it. /tfl recordkeys shows
-- the keys for the water you're standing at.
MF.STRUCK_RECORDS = {
    -- ["6289:300:1796083200"] = true,
}
local STRUCK = 0 -- bump whenever the list above grows, to sweep again

function MF:RecordKey(itemID, w, t)
    return ("%d:%d:%d"):format(itemID, MF.Hundredths(w), t)
end

function MF:IsStruckRecord(itemID, w, t)
    return self.STRUCK_RECORDS[self:RecordKey(itemID, w, t)] == true
end

-- Returns how many entries went, across every table a spot keeps.
function MF:SweepStruckRecords()
    local gone = 0
    for _, s in pairs(self.db.spots) do
        for _, fish in ipairs({ s.fish or {}, s.season or {}, s.lastSeason or {} }) do
            for id, rec in pairs(fish) do
                if type(rec) == "table" and type(rec.w) == "number" and type(rec.t) == "number"
                    and self:IsStruckRecord(id, rec.w, rec.t) then
                    fish[id] = nil
                    gone = gone + 1
                end
            end
        end
    end
    return gone
end

MF:On("TFL_LOGIN", function(self)
    if self.db.struckSweep == STRUCK then return end
    self.db.struckSweep = STRUCK
    local gone = self:SweepStruckRecords()
    if gone == 0 then return end
    self:Print(("Removed %d record%s that this version strikes from the book."):format(
        gone, gone == 1 and "" or "s"))
    self:RefreshJournal()
end)

MF:Command("recordkeys", "Other", nil, function(self)
    local spot = self:CurrentSpot()
    local s = spot and self:Spot(spot.key)
    local lines = { "Record keys at " .. (spot and self:SpotName(spot.key) or "this water") }
    for id, rec in pairs(s and s.fish or {}) do
        lines[#lines + 1] = ("%s  %s  %s"):format(self:RecordKey(id, rec.w, rec.t),
            self:FishName(id) or ("Item " .. id), MF:Weight(rec.w))
    end
    self:ShowDiagnosticText(table.concat(lines, "\n"))
end)

local function Better(old, w, t)
    return not old or w > old.w or (w == old.w and t < old.t)
end

-- Returns changedAllTime, changedThisSeason, previous all-time record.
function MF:MergeRecord(key, mapID, itemID, w, holder, t, spec)
    itemID, w, t, mapID = tonumber(itemID), tonumber(w), tonumber(t), tonumber(mapID)
    if not self:IsSpotKey(key) or not itemID or not w or not t then return end
    if #key>80 or itemID~=itemID or itemID<1 or itemID>2147483647 or itemID~=math.floor(itemID)
        or w~=w or t~=t or t<0 or t==math.huge or t~=math.floor(t)
        or (mapID and (mapID~=mapID or mapID<0 or mapID>2147483647 or mapID~=math.floor(mapID))) then return end
    if type(holder)~="string" or holder=="" or #holder>100 or holder:find("[%c|~]") then return end
    if w <= 0 or w > self:MaxWeight(itemID) or t > GetServerTime() + 300 then return end
    -- Nothing caught before the wipe survives it. This is what makes the
    -- fresh start hold: a client that never updated will go on shouting its
    -- beta records into the new realm, and every client that did update will
    -- quietly drop them. No coordination, no catching up, and one angler who
    -- missed the patch can't re-seed a leaderboard full of ghosts.
    local fresh = self.FRESH_START
    if GetServerTime() >= fresh and t < fresh then return end
    -- Cloth, potions and cloaks are not fish and never were. Refusing them
    -- here is what makes clearing out the old ones stick: otherwise the next
    -- record book round the realm hands them all straight back.
    if self:IsKnownJunk(itemID) then return end
    if self:IsStruckRecord(itemID, w, t) then return end
    -- Caught after the holder's version stopped counting (Eligibility.lua).
    -- Records from before then stand.
    if not self:AnglerCounts(holder, t) then return end
    self:NoteSpotLabelEvidence(holder,t)

    local s = self:Spot(key, true, mapID)
    local rec = { h = holder, w = w, t = t, s = spec and true or nil }
    local prev = s.fish[itemID]
    local all, season = false, false
    if Better(prev, w, t) then
        s.fish[itemID] = rec
        all = true
    end
    if self:SeasonID(t) == s.seasonID and Better(s.season[itemID], w, t) then
        s.season[itemID] = rec
        season = true
    end
    return all, season, prev
end

-- Heaviest all-time catch at a spot: { h, w, t, s, id }.
function MF:King(key)
    local s = self:Spot(key)
    if not s then return end
    local best
    for id, rec in pairs(s.fish) do
        if not best or rec.w > best.w then
            best = { h = rec.h, w = rec.w, t = rec.t, s = rec.s, id = id }
        end
    end
    return best
end

-- All-time records we hold, heaviest first: { key, mapID, id, w, t, s }.
-- Used by Profile.lua to keep them in the save macros.
function MF:MyRecords(limit)
    local list = {}
    for key, s in pairs(self.db.spots) do
        for id, rec in pairs(s.fish) do
            if self:IsMe(rec.h) and not self:SpotLabelProblem(key) then
                local mapID = self:SpotRecordMap(key)
                list[#list + 1] = { key = key, mapID = mapID or 0, id = id, w = rec.w, t = rec.t, s = rec.s }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.w ~= b.w then return a.w > b.w end
        return a.key < b.key
    end)
    for i = #list, (limit or #list) + 1, -1 do list[i] = nil end
    return list
end

------------------------------------------------------------------------
-- Sync state per map
------------------------------------------------------------------------

local sync = {}     -- mapID -> { askedAt, done }
local pending = {}  -- mapID -> catches waiting for the sync to finish

function MF:RecordsReady(mapID)
    local st = sync[mapID or self:MapID()]
    return st ~= nil and st.done
end

-- Returns whether a sync is now in flight - whether, in other words, there
-- is anything for a caller to wait on. False means we cannot even ask:
-- without a map there is nobody to ask about, and a catch held back for an
-- answer that is never coming is a catch that is simply lost.
function MF:RequestRecords(mapID)
    mapID = mapID or self:MapID()
    if not mapID or mapID == 0 or not self.me then return false end
    local st = sync[mapID]
    local now = GetTime()
    if st and not st.done then return true end -- already waiting for an answer
    if st and now - st.askedAt < REQUEST_COOLDOWN then return st.done end
    sync[mapID] = { askedAt = now, done = st and st.done or false }
    self:SendWide("RREQ2", mapID)
    return true
end

local function FinishSync(self, mapID)
    local st = sync[mapID]
    if not st or st.done then return end
    st.done = true
    local waiting = pending[mapID]
    pending[mapID] = nil
    for _, c in ipairs(waiting or {}) do
        self:AddXP(self:CheckSpotRecord(c))
    end
    self:RefreshJournal()
end

-- Nobody answered: nobody online has records for this map, so go ahead.
MF:OnTick(function(self)
    local now = GetTime()
    for mapID, st in pairs(sync) do
        if not st.done and now - st.askedAt >= SYNC_TIMEOUT then
            FinishSync(self, mapID)
        end
    end
end)

MF:On("TFL_SYNC", function(self) self:RequestRecords() end)
MF:On("ZONE_CHANGED_NEW_AREA", function(self)
    C_Timer.After(ZONE_SETTLE_DELAY, function() self:RequestRecords() end)
end)

------------------------------------------------------------------------
-- Setting records
------------------------------------------------------------------------

-- Called for every real catch; returns bonus XP. Before the zone has synced
-- the catch is held back and checked (with its XP) once it has.
function MF:CheckSpotRecord(c)
    local key, name, mapID = c.spot.key, c.spot.name, c.spot.mapID
    if not self:RecordsReady(mapID) then
        -- Parked only if somebody is coming back for it.
        --
        -- A map the client cannot name gives MapID() 0, and nothing can be
        -- asked about map 0 - so no sync was ever started, the timeout that
        -- releases a parked catch had nothing to release, and the catch sat
        -- in here for the rest of the session. No record, no broadcast, no
        -- XP, and nothing said. That is how a specimen landed in the new
        -- Excavation Site and never reached the Realm tab.
        --
        -- Going ahead unsynced is the right failure: the worst it costs is
        -- announcing a record that an angler we could not reach already
        -- beat, and their copy refuses ours the moment they hear it.
        if self:RequestRecords(mapID) then
            pending[mapID] = pending[mapID] or {}
            table.insert(pending[mapID], c)
            return 0
        end
    end

    local weight = c.weight
    local oldKing = self:King(key)
    local all, season = self:MergeRecord(key, mapID, c.itemID, weight, self.me, c.at or GetServerTime(), c.specimen)
    c.recordAllTime, c.recordSeason = all and true or false, season and true or false
    self:CreditSessionRecord(c)
    if not all and not season then return 0 end

    local px, py = PackPos(self,key,mapID)
    self:SendWide("REC2", key, mapID, c.itemID, self:EncodeWeight(weight), self.me,
        c.at or GetServerTime(), c.specimen and 1 or 0, 0, name, px, py, self:MyFaction(), self.Version())
    -- The anglers in a match with us are at this water now: they shouldn't
    -- have to wait for a record swap to see it.
    if self:InMatch() and self.WhisperMatchPlayers then
        self:WhisperMatchPlayers(self.current, "REC2", key, mapID, c.itemID, self:EncodeWeight(weight), self.me,
            c.at or GetServerTime(), c.specimen and 1 or 0, 0, name, px, py, self:MyFaction(), self.Version())
    end

    local fish = self:FishName(c.itemID)
    local king = self:King(key)
    if king and self:IsMe(king.h) and (not oldKing or not self:IsMe(oldKing.h)) then
        self:Print(("|cffffd100You are the King of %s!|r"):format(name))
        self:Toast("Interface\\Icons\\INV_Crown_01", "KING OF THE SPOT", name,
            ("%s - %s"):format(fish, MF:Weight(weight)), 1, 0.82, 0, SOUNDKIT.UI_EPICLOOT_TOAST,
            { card = c.itemID })
    end
    if all then
        self:Print(("|cffffd100New all-time %s record at %s: %s!|r +%d XP")
            :format(fish, name, MF:Weight(weight), XP_RECORD))
        self:Sound(SOUNDKIT.READY_CHECK, "soundRecords") -- records get their own sound
        self:Tip("record", "That's yours until somebody beats it. Other anglers will see it on "
            .. "their |cffffd100Realm|r tab, and it'll point them at this water.")
        return XP_RECORD
    end
    self:Print(("New season %s record at %s: %s. +%d XP"):format(fish, name, MF:Weight(weight), XP_SEASON))
    return XP_SEASON
end

------------------------------------------------------------------------
-- Losing a record
--
-- Records you hold are yours wherever you are, so being beaten is always
-- worth hearing about - unlike the ambient "someone set a record nearby"
-- chatter, which stays local. Losses found during a sync (while you were
-- offline or away) are collected and reported as one summary.
------------------------------------------------------------------------

local losses = {}
local flushScheduled = false

-- One line for one loss: what went, who has it now, and by how much.
function MF:LossLine(l)
    if not l.record then
        return ("%s took the crown at %s"):format(self:ShortName(l.holder), self:SpotName(l.key))
    end
    local by = l.mine and (" |cff858585(yours was %.2f)|r"):format(l.mine) or ""
    return ("%s took %s at %s - %s%s"):format(self:ShortName(l.holder),
        self:FishName(l.itemID), self:SpotName(l.key), MF:Weight(l.weight), by)
end

local function ReportLosses(self)
    flushScheduled = false
    if #losses == 0 then return end
    -- Shown rather than printed: a list of waters to go back to is worth a
    -- window, and it would scroll past in the login chatter anyway.
    self:ShowLosses(losses)
    losses = {}
end

local function NoteLoss(self, key, itemID, holder, weight, king, record, mine)
    losses[#losses + 1] = { key = key, itemID = itemID, holder = holder, weight = weight,
        king = king, record = record, mine = mine }
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(3, function() ReportLosses(self) end)
    end
end

-- Told to us directly, as it happens.
local function AnnounceLoss(self, key, itemID, holder, weight, wasKing)
    self:WithFishName(itemID, function(fish)
        self:Print(("|cffff5a5a%s has taken your %s record at %s|r (%s)."):format(
            self:ShortName(holder), fish, self:SpotName(key), MF:Weight(weight)))
        if wasKing then
            self:Print(("|cffff5a5aYou're no longer King of %s.|r"):format(self:SpotName(key)))
        end
    end)
    self:Sound(SOUNDKIT.RAID_WARNING, "soundRecordLost")
end

function MF.handlers.REC2(self, sender, key, mapID, itemID, weight, holder, t, spec, isSync,
                          name, px, py, faction, version)
    if not self:IsSpotKey(key) then return end
    -- Their own record, stamped with what they're running since 1.0.8.
    if self.ValidVersion(version) and self:SameAngler(sender, holder) then self:NoteSeen(sender, version) end
    self:RememberSpotName(key, name)
    UnpackPos(self, key, mapID, px, py)
    self:NoteFaction(holder, faction)
    local oldKing = self:King(key)
    local all, season, prev = self:MergeRecord(key, mapID, itemID, self:DecodeWeight(weight),
        holder, t, spec == "1")
    if not (all or season) then return end
    self:RefreshJournal()

    -- Your own record being beaten follows you around; everything else is
    -- only announced where it happened.
    local king = self:King(key)
    local lostKing = oldKing and self:IsMe(oldKing.h) and king and not self:IsMe(king.h)
    local lostRecord = all and prev and self:IsMe(prev.h)
    if lostRecord or lostKing then
        local w = self:DecodeWeight(weight)
        if isSync == "1" then
            NoteLoss(self, key, tonumber(itemID), holder, w, lostKing, lostRecord,
                prev and prev.w or nil)
        elseif lostRecord then
            AnnounceLoss(self, key, tonumber(itemID), holder, w, lostKing)
        else
            self:WithFishName(king.id, function(fish)
                self:Print(("|cffff5a5a%s has taken the crown at %s from you|r (%s, %s)."):format(
                    self:ShortName(king.h), self:SpotName(key), fish, MF:Weight(king.w)))
            end)
            self:Sound(SOUNDKIT.RAID_WARNING, "soundRecordLost")
        end
        return
    end

    local fresh = GetServerTime() - (tonumber(t) or 0) < ALERT_WINDOW
    if isSync == "1" or not fresh or self:MapID() ~= tonumber(mapID) or not self.db.settings.recordAlerts then
        return
    end
    self:WithFishName(itemID, function(fish)
        self:Print(("|cffffd100%s set a new %s %s record at %s: %s.|r"):format(
            self:ShortName(holder), all and "all-time" or "season", fish,
            self:SpotName(key), MF:Weight(self:DecodeWeight(weight))))
    end)
end

------------------------------------------------------------------------
-- Packed sync (RSYNC2): answers to RREQ2, and our own records at login
------------------------------------------------------------------------

-- Entries: key,itemID,weight,holder,time,specimen,name joined by ";".
local function PackEntries(self, list, mapID)
    local entries = {}
    for _, e in ipairs(list) do
        local name = self:SpotNameForWire(e.key)
        local px, py = PackPos(self,e.key,mapID)
        entries[#entries + 1] = ("%s,%d,%s,%s,%d,%d,%s,%s,%s,%s"):format(
            e.key, e.id, self:EncodeWeight(e.rec.w), e.rec.h, e.rec.t, e.rec.s and 1 or 0,
            name, px, py, self:FactionOf(e.rec.h) or "")
    end
    return table.concat(entries, ";")
end

local function MapEntries(self, mapID)
    local list = {}
    for key, s in pairs(self.db.spots) do
        if self:SpotOnMap(s, mapID) then
            self:Spot(key) -- rolls the season over if needed
            for id, rec in pairs(s.fish) do list[#list + 1] = { key = key, id = id, rec = rec } end
            for id, rec in pairs(s.season) do
                if s.fish[id] ~= rec then list[#list + 1] = { key = key, id = id, rec = rec } end
            end
        end
    end
    return list
end

-- One player with records for the zone answers.
function MF.handlers.RREQ2(self, sender, mapID)
    mapID = tonumber(mapID)
    if not mapID then return end
    self:ReplyOnce("rsync:" .. mapID, 1, 5, function()
        local list = MapEntries(self, mapID)
        if #list > 0 then
            self:SendWide("RSYNC2", mapID, PackEntries(self, list,mapID))
        end
    end)
end

local function MergePacked(self, mapID, packed)
    for entry in (packed or ""):gmatch("[^;]+") do
        local key, id, w, holder, t, spec, name, px, py, faction = strsplit(",", entry)
        if self:IsSpotKey(key) then
            self:RememberSpotName(key, name)
            UnpackPos(self, key, mapID, px, py)
            self:NoteFaction(holder, faction)
            self:MergeRecord(key, mapID, id, self:DecodeWeight(w), holder, t, spec == "1")
        end
    end
    self:RefreshJournal()
end

-- A full answer to someone's RREQ2: the zone counts as synced.
function MF.handlers.RSYNC2(self, sender, mapID, packed)
    mapID = tonumber(mapID)
    if not mapID then return end
    self:MarkAnswered("rsync:" .. mapID)
    MergePacked(self, mapID, packed)
    FinishSync(self, mapID)
end

-- Just the sender's own records (sent at login): merge, but it isn't a full
-- sync, so it neither answers nor completes anyone's request.
function MF.handlers.RMINE(self, sender, mapID, packed)
    mapID = tonumber(mapID)
    if mapID then MergePacked(self, mapID, packed) end
end

-- After login (once macros have restored them), tell everyone about the
-- records we hold, so they come back whenever we're online.
function MF:AnnounceMyRecords()
    local byMap = {}
    for _, r in ipairs(self:MyRecords()) do
        local s = self:Spot(r.key)
        if s and r.mapID ~= 0 then
            byMap[r.mapID] = byMap[r.mapID] or {}
            table.insert(byMap[r.mapID], { key = r.key, id = r.id, rec = s.fish[r.id] })
        end
    end
    for mapID, list in pairs(byMap) do
        self:SendWide("RMINE", mapID, PackEntries(self, list,mapID))
    end
end

MF:On("TFL_SYNC", MF.AnnounceMyRecords)

------------------------------------------------------------------------
-- The record book
--
-- A zone sync only covers the zone you're standing in, so a record reaches
-- you only if you go there while someone who knows it happens to be online.
-- The book fixes that: once a session an angler hands over the heaviest
-- catch at every spot they know of, and anyone holding something the book
-- missed adds it. Records then travel between anglers who are never online
-- together - one relay at a time, through whoever was there for both.
------------------------------------------------------------------------

local BOOK_MAX = 80        -- entries one angler hands over at a time
local BOOK_TOPUP = 30      -- entries we add to someone else's book
local BOOK_COOLDOWN = 900  -- seconds before asking for another book
local MAX_TOPUPS = 2       -- per session, so a busy realm can't echo forever

local lastBook, topUps = -math.huge, 0

local function PackBook(self, list)
    local out = {}
    for _, e in ipairs(list) do
        local name = self:SpotNameForWire(e.key)
        local px, py = PackPos(self,e.key,e.mapID)
        out[#out + 1] = ("%s,%d,%s,%s,%d,%d,%d,%s,%s,%s,%s"):format(e.key, e.id,
            self:EncodeWeight(e.w), e.h, e.t, e.s and 1 or 0, e.mapID, name, px, py,
            self:FactionOf(e.h) or "")
    end
    return table.concat(out, ";")
end

-- Both written further down: the short form of the same book, and the one
-- door every book leaves by. Declared up here because everything that sends
-- one is between this line and theirs.
local PackBook2, SendBook

-- Own records and spot Kings retain priority, with space reserved for a
-- rotating slice of all known species records. Otherwise an ordinary record
-- can stop travelling as soon as its holder logs off.
--
-- With `theirs`, only the spots where we hold something better than they
-- just sent.
local function Freshest(a, b) return a.t > b.t end
local function Heaviest(a, b) return a.w > b.w end

-- A book has to be two things at once, and one sort order can only be one of
-- them. Freshest first keeps it current, but a record that stands for weeks
-- stops being recent while it is still the best thing on the realm, and
-- drops off the end - so the better a catch is, the sooner it stops
-- travelling. Heaviest first keeps the trophies moving but buries every
-- small fish, and those are what put their holders in the standings at all.
--
-- So the two orders are woven together: the heaviest, then the freshest,
-- then the next of each. The best catch we know of is in every book however
-- short it gets, recent water still travels, and what truncation drops is
-- the middle - mid-weight records that aren't news either.
local function Weave(list)
    if #list < 3 then return list end
    local heavy, fresh = {}, {}
    for i = 1, #list do heavy[i], fresh[i] = list[i], list[i] end
    table.sort(heavy, Heaviest)
    table.sort(fresh, Freshest)

    local out, taken, h, f = {}, {}, 1, 1
    while #out < #list do
        while h <= #heavy and taken[heavy[h]] do h = h + 1 end
        if h <= #heavy then
            taken[heavy[h]] = true
            out[#out + 1] = heavy[h]
        end
        while f <= #fresh and taken[fresh[f]] do f = f + 1 end
        if f <= #fresh then
            taken[fresh[f]] = true
            out[#out + 1] = fresh[f]
        end
        if h > #heavy and f > #fresh then break end
    end
    return out
end

-- Our own records lead the book, but they can't be all of it. An angler with
-- eighty records of their own would otherwise relay nothing of anybody
-- else's - and the anglers holding the most are the ones who meet the most
-- people, so that is exactly where the realm's best catches would stop.
local MINE_SHARE = 0.6
local bookCursors = {} -- per peer, bounded; rotation survives repeated syncs
local MAX_BOOK_CURSORS = 64

local function BookEntries(self, limit, theirs, peer)
    local mine, kings, seen, relay = {}, {}, {}, {}

    local function Add(into, key, id, rec, mapID)
        local tag = key .. "#" .. id
        if seen[tag] or not rec then return end
        seen[tag] = true
        into[#into + 1] = { key = key, id = id, w = rec.w, h = rec.h, t = rec.t,
            s = rec.s, mapID = mapID or 0 }
    end

    if not theirs then
        for _, r in ipairs(self:MyRecords()) do
            local s = self:Spot(r.key)
            Add(mine, r.key, r.id, s and s.fish[r.id], r.mapID)
        end
    end
    for key, s in pairs(self.db.spots) do
        local king = self:King(key)
        if king and not self:SpotLabelProblem(key) and (not theirs or Better(theirs[key], king.w, king.t)) then
            Add(kings, key, king.id, king, self:SpotRecordMap(key))
        end
        -- Standings count EVERY species record, not just each spot's King.
        -- Relay records held by absent anglers as well as our own catches.
        if not theirs and not self:SpotLabelProblem(key) then
            local mapID = self:SpotRecordMap(key) or 0
            for id, rec in pairs(s.fish) do
                relay[#relay + 1] = { key = key, id = id, w = rec.w, h = rec.h,
                    t = rec.t, s = rec.s, mapID = mapID, tag = key .. "#" .. id }
            end
        end
    end

    mine, kings = Weave(mine), Weave(kings)

    -- Keep three quarters of the book for the existing own-record/King
    -- priorities. The remaining space rotates through the full record set,
    -- without raising the packet rate or the 80-entry book limit.
    local priorityLimit = theirs and limit or math.max(1, limit - math.floor(limit / 4))
    local out, included = {}, {}
    local function Append(e)
        out[#out + 1] = e
        included[e.key .. "#" .. e.id] = true
    end
    local room = math.max(priorityLimit - #kings, math.floor(priorityLimit * MINE_SHARE))
    local used = 0
    for i = 1, math.min(#mine, room) do
        Append(mine[i])
        used = i
    end
    for _, e in ipairs(kings) do
        if #out >= priorityLimit then break end
        Append(e)
    end
    for i = used + 1, #mine do
        if #out >= priorityLimit then break end
        Append(mine[i])
    end
    if theirs or #relay == 0 then return out end

    local peerKey = peer and self:AnglerKey(peer) or "*"
    local cursor = bookCursors[peerKey]
    if not cursor then
        if self.Count(bookCursors) >= MAX_BOOK_CURSORS then
            local oldest, oldestAt
            for key, entry in pairs(bookCursors) do
                if not oldestAt or entry.at < oldestAt then oldest, oldestAt = key, entry.at end
            end
            bookCursors[oldest] = nil
        end
        cursor = { tag = "" }
        bookCursors[peerKey] = cursor
    end
    cursor.at = GetTime()
    -- Key order is stable when a weight changes. A last-key cursor also
    -- avoids restarting the same slice when records are added or removed.
    table.sort(relay, function(a, b) return a.tag < b.tag end)
    local start = 1
    for i, entry in ipairs(relay) do if entry.tag > cursor.tag then start = i break end end
    for offset = 0, #relay - 1 do
        if #out >= limit then break end
        local entry = relay[(start + offset - 1) % #relay + 1]
        cursor.tag = entry.tag
        if not included[entry.tag] then Append(entry) end
    end
    return out
end

function MF:RequestBook(force)
    if not force and GetTime() - lastBook < BOOK_COOLDOWN then return end
    self:SendWide("RALL")
end

function MF.handlers.RALL(self, sender)
    self:ReplyOnce("rbook", 2, 8, function()
        local list = BookEntries(self, BOOK_MAX)
        SendBook(self, nil, list)
    end)
end

-- One angler asking one angler, by whisper. The channel is the usual way
-- records travel, and when it isn't working - not joined, or the ten channel
-- limit reached - two people stood at the same lake can still swap.
local askedBack = {}
local bountySharedAt = {}
local bookSentAt = {}          -- angler key -> when we last whispered them a book
local BOOK_REPLY_COOLDOWN = 120
local manualBookRequests = {}
local rosterRequestedAt = -math.huge
-- The scan's reply is printed to chat by the game, and hidden by the filter
-- below. It used to be hidden only if it came within ten seconds, and a
-- reply held up by lag or a loading screen landed in the player's chat as
-- a wall of names. Now a reply is expected until one arrives, for up to a
-- minute, and the parts of a long list that follow it close behind are
-- taken with it. After that a list is the player's own /chatlist and shown.
local ROSTER_WAIT, ROSTER_TAIL = 60, 3
local rosterAnsweredAt = -math.huge
local rosterContacted = {}
local rosterBudget = 0
local rosterSeen, rosterAsked, rosterAnswered = {}, {}, {}
local REPLIES_SINCE = "1.0.8" -- the first version whose whispers arrive cross-realm
local confirmedPeers = {}
MF.syncDiagnostics = { records = 0, bounties = 0, pools = 0 }

local function NoteRecordPeer(self, sender)
    local key = self:AnglerKey(sender)
    if key == "" or not askedBack[key] then return end
    confirmedPeers[key] = GetTime()
    if rosterAsked[key] then rosterAnswered[key] = true end
end

-- Who the last scan whispered, as the whisper was addressed, and whether
-- they answered.
function MF:QuietSyncAsked()
    local out = {}
    for key, name in pairs(self.rosterAskedNames or {}) do
        out[#out + 1] = ("%s (%s)"):format(self:WhisperName(name) or name,
            rosterAnswered[key] and "answered" or "silent")
    end
    table.sort(out)
    return out
end

function MF:QuietSyncSummary()
    if not self.db.settings.channel then return "discovery disabled in Options" end
    if GetChannelName(self.CHANNEL) <= 0 then
        return self:DiscoveryJoinStatus()
    end
    if type(ListChannelByName) ~= "function" then return "roster lookup unavailable" end
    if rosterRequestedAt == -math.huge then return "discovery channel joined; scan not started" end
    return ("%d roster names, %d peers asked, %d answered (%ds ago)"):format(
        self.Count(rosterSeen), self.Count(rosterAsked), self.Count(rosterAnswered),
        math.floor(GetTime() - rosterRequestedAt))
end

local function RequestRoster(self)
    local now = GetTime()
    if self.CUSTOM_CHANNEL_SUPPORTED or not self.db.settings.channel
        or type(ListChannelByName) ~= "function" or GetChannelName(self.CHANNEL) <= 0
        or now - rosterRequestedAt < 60 then return false end
    rosterRequestedAt, rosterBudget, rosterAnsweredAt = now, 4, -math.huge
    rosterSeen, rosterAsked, rosterAnswered = {}, {}, {}
    MF.rosterAskedNames = {}
    MF.rosterReply = { requestedAt = now }
    ListChannelByName(self.CHANNEL)
    return true
end

MF:On("TFL_ROSTER_SYNC", RequestRoster)

-- Whether a channel list arriving now is the answer to our scan.
local function RosterReplyExpected()
    local now = GetTime()
    if now - rosterAnsweredAt <= ROSTER_TAIL then return true end
    return rosterAnsweredAt < rosterRequestedAt and now - rosterRequestedAt <= ROSTER_WAIT
end
MF.RosterReplyExpected = RosterReplyExpected

-- Whether a list is for our channel. Any of the three ways the game names
-- it will do, and a value this client has made secret can't be read, so
-- while a reply is expected that counts as ours rather than leaking.
local function OurChannel(self, channel, index, base)
    local id = GetChannelName(self.CHANNEL)
    if type(id) ~= "number" or id <= 0 then return false end
    local ok, ours = pcall(function()
        if issecretvalue and (issecretvalue(channel) or issecretvalue(base) or issecretvalue(index)) then
            return "secret"
        end
        return base == self.CHANNEL or channel == self.CHANNEL
            or channel == id .. ". " .. self.CHANNEL or index == id
    end)
    if not ok or ours == "secret" then return "secret" end
    return ours
end
MF.RosterListIsOurs = OurChannel

-- The chat filter itself: true hides the message.
function MF.RosterChatFilter(_, _, _, _, _, channel, _, _, _, index, base)
    if not RosterReplyExpected() then return false end
    return OurChannel(MF, channel, index, base) ~= false
end
local rosterFilterInstalled
MF:On("TFL_LOGIN", function(self)
    if self.CUSTOM_CHANNEL_SUPPORTED or rosterFilterInstalled then return end
    local addFilter = ChatFrame_AddMessageEventFilter
        or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if not addFilter then return end
    rosterFilterInstalled = true
    -- Hide our request's chat output without consuming the roster event.
    addFilter("CHAT_MSG_CHANNEL_LIST", MF.RosterChatFilter)
end)
MF:On("TFL_LOGIN", function(self)
    if not self.CUSTOM_CHANNEL_SUPPORTED then
        C_Timer.NewTicker(300, function() RequestRoster(self) end)
    end
end)

-- What the last channel list looked like when it arrived, for /tfl diag.
-- One angler's scan finds nobody while another's in the same channel finds
-- ninety, and the only way to see why is what the game actually handed us.
local function Shown(value)
    if issecretvalue and issecretvalue(value) then return "<secret>" end
    return tostring(value)
end

local function NoteRosterReply(self, text, channel, index, base)
    local r = MF.rosterReply
    if not r then return end
    r.events, r.at = (r.events or 0) + 1, GetTime()
    r.expected = RosterReplyExpected()
    r.ours = tostring(OurChannel(self, channel, index, base))
    r.id = Shown(GetChannelName(self.CHANNEL))
    r.channel, r.index, r.base = Shown(channel), Shown(index), Shown(base)
    if issecretvalue and issecretvalue(text) then
        r.text = "<secret>"
    elseif type(text) == "string" then
        -- Escapes shown as "!" so the copy box prints them rather than
        -- turning them into links and colours.
        r.text = ("%d chars: %s"):format(#text, (text:sub(1, 80):gsub("|", "!")))
    else
        r.text = type(text)
    end
end

MF:On("CHAT_MSG_CHANNEL_LIST", function(self, text, _, _, channel, _, _, _, index, base)
    local now = GetTime()
    NoteRosterReply(self, text, channel, index, base)
    if not RosterReplyExpected() then return end
    if OurChannel(self, channel, index, base) ~= true then return end
    -- Marked before anything can go wrong with the text, so the filter
    -- keeps taking the rest of this list either way.
    rosterAnsweredAt = now
    if issecretvalue and issecretvalue(text) then return end
    if type(text) ~= "string" or #text > 16384 then return end

    -- Who to ask, best first: anglers who answered us lately, then anglers
    -- last heard on a copy that can whisper back (1.0.8 fixed replies),
    -- then anglers we know nothing about, and last those last heard on an
    -- older copy - they may have updated since, but a whisper to a 1.0.7
    -- client is a request that can't be answered.
    local known, able, unknown, old = {}, {}, {}, {}
    for entry in text:gmatch("[^,]+") do
        local name = entry:match("|Hplayer:([^:|]+)")
            or entry:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
        local key = self:AnglerKey(name)
        if #name <= 80 and name:match("^[%a\128-\255][%a\128-\255' %-]+$")
            and key ~= "" and not self:IsMe(name) and not rosterSeen[key] then
            rosterSeen[key] = true
            if now - (rosterContacted[key] or -math.huge) >= BOOK_COOLDOWN then
                local list
                if now - (confirmedPeers[key] or -math.huge) <= 1800 then
                    list = known
                else
                    local version = self:AnglerVersion(name)
                    if not version then list = unknown
                    elseif self:VersionNewer(REPLIES_SINCE, version) then list = old
                    else list = able end
                end
                list[#list + 1] = { name = name, key = key }
            end
        end
    end
    local function Fresh()
        return #able > 0 and able or #unknown > 0 and unknown or #old > 0 and old or nil
    end
    while rosterBudget > 0 and (#known > 0 or Fresh()) do
        -- Reserve one request for discovery whenever a new name is available.
        local list = #known > 0 and (rosterBudget > 1 or not Fresh()) and known or Fresh()
        local peer = table.remove(list, math.random(#list))
        if not rosterContacted[peer.key] or now - rosterContacted[peer.key] >= BOOK_COOLDOWN then
            rosterBudget = rosterBudget - 1
            rosterContacted[peer.key] = now
            askedBack[peer.key] = now
            local scan = rosterAsked
            C_Timer.After((4 - rosterBudget) * 2, function()
                if scan ~= rosterAsked or self.db.settings.channel == false then return end
                scan[peer.key] = true
                MF.rosterAskedNames = MF.rosterAskedNames or {}
                MF.rosterAskedNames[peer.key] = peer.name
                self:Whisper(peer.name, "RASK", "ACK1", self:NearbyPeerMap(), self.cdb.profile.xp, self:TotalFishCaught(), self:Version())
                self:RequestPools(self:MapID(), peer.name)
                -- Frenzy discoveries otherwise travel only by guild and group,
                -- so an angler outside both would never hear any.
                self:RequestFrenzyObservations(peer.name)
            end)
        end
    end
end)

function MF.handlers.RACK1(self, sender, nearbyMap, xp, fish, version)
    self:NoteProgression(sender, xp, fish)
    self:NoteCensusReply(sender,version,nearbyMap)
    self:RequestQuietBounties(sender)
    NoteRecordPeer(self, sender)
    if askedBack[self:AnglerKey(sender)] then self:NoteNearbyPeer(sender, nearbyMap) end
end

function MF.handlers.RASK(self, sender, confirmation, nearbyMap, xp, fish, version)
    self:NoteProgression(sender, xp, fish)
    self:NoteCensusReply(sender,version,nearbyMap)
    self:RequestQuietBounties(sender)
    NoteRecordPeer(self, sender)
    -- Confirm even an empty book. Older clients ignore the optional field.
    if confirmation == "ACK1" then
        self:NoteNearbyPeer(sender, nearbyMap)
        self:Whisper(sender, "RACK1", self:NearbyPeerMap(), self.cdb.profile.xp, self:TotalFishCaught(), self:Version())
    end
    -- A book is twenty-odd messages; one whisper must not be able to ask
    -- for it over and over and fill our queue.
    local key, now = self:AnglerKey(sender), GetTime()
    if now - (bookSentAt[key] or -math.huge) >= BOOK_REPLY_COOLDOWN then
        bookSentAt[key] = now
        SendBook(self, sender, BookEntries(self, BOOK_MAX, nil, sender))
        self:SendTally(sender)
    end
    -- A swap, not a handout: ask for theirs too, but only once in a while,
    -- so two clients can't bat this back and forth.
    if not self.CUSTOM_CHANNEL_SUPPORTED and now - (bountySharedAt[key] or -math.huge) >= 60 then
        bountySharedAt[key] = now
        self:ShareCurrentBounties(sender)
        self:ShareNotices(sender)
    end
    if now - (askedBack[key] or -math.huge) > BOOK_COOLDOWN then
        askedBack[key] = GetTime()
        self:Whisper(sender, "RASK")
    end
end

-- What both book handlers do once the records are in. Kept in one place so
-- the long and short forms can't drift apart - the formats differ, what
-- they mean does not.
local function AfterBook(self, sender, theirs, learned)
    self:NoteCensusReply(sender)
    NoteRecordPeer(self, sender)
    self.syncDiagnostics.records = self.syncDiagnostics.records + learned
    if learned > 0 then self:RefreshJournal() end
    self:Debug(("record book from %s: %d new"):format(self:ShortName(sender), learned))
    -- A book we asked one angler for is worth saying out loud: it's the
    -- answer to "why can't we see each other's records?". Say how much of
    -- it is theirs, too - an angler who holds nothing is absent from the
    -- standings for want of anything to be in them with, which looks
    -- exactly like a sync that didn't work.
    local key = self:AnglerKey(sender)
    if manualBookRequests[key] then
        manualBookRequests[key] = nil
        local held = 0
        for _, s in pairs(self.db.spots) do
            for _, rec in pairs(s.fish) do
                if self:SameAngler(rec.h, sender) then held = held + 1 end
            end
        end
        self:Print(("%s's book: %d new to you. They hold %d record%s you know of."):format(
            self:ShortName(sender), learned, held, held == 1 and "" or "s"))
        if held == 0 then
            self:Print("|cff858585Nothing to put them in the standings with yet - "
                .. "they need the heaviest of a fish at a spot.|r")
        end
    end

    -- Whatever their book missed, we add, so it grows as it goes around.
    if topUps >= MAX_TOPUPS then return end
    local mine = BookEntries(self, BOOK_TOPUP, theirs)
    if #mine == 0 then return end
    topUps = topUps + 1
    -- A whisper swap may be the only working route. Capture the sender now:
    -- lastRoad can change while the delayed reply is waiting.
    local destination = self.lastRoad == "WHISPER" and sender or nil
    self:ReplySoon(5, 10, function() SendBook(self, destination, mine) end)
end

function MF.handlers.RBOOK(self, sender, packed)
    lastBook = GetTime()
    self:MarkAnswered("rbook")

    local theirs, learned = {}, 0
    for entry in (packed or ""):gmatch("[^;]+") do
        local key, id, w, holder, t, spec, mapID, name, px, py, faction = strsplit(",", entry)
        if self:IsSpotKey(key) then
            self:RememberSpotName(key, name)
            UnpackPos(self, key, mapID, px, py)
            self:NoteFaction(holder, faction)
            local all = self:MergeRecord(key, mapID, id, self:DecodeWeight(w), holder,
                tonumber(t), spec == "1")
            if all then learned = learned + 1 end
            local weight, when = self:DecodeWeight(w), tonumber(t) or 0
            if weight and Better(theirs[key], weight, when) then theirs[key] = { w = weight, t = when } end
        end
    end
    AfterBook(self, sender, theirs, learned)
end

------------------------------------------------------------------------
-- The short book
--
-- The same thing, written smaller. Three things were being paid for over
-- and over: the holder's name on every record they hold, the spot's name
-- and position on every fish caught there, and ten digits of timestamp.
--
--   long   n1429:860276218,6308,500,Shamalayah Ironrush,1791283731,0,1429,
--          Stormwind Harbor,2871,5434,A                         91 bytes
--   short  n1429:860276218,13t,2871,5434|4tk,500,p9x2,1h5z8k,0   59 bytes
--
-- So: the anglers are named once at the front and referred to by a hash
-- after that, each spot is written once with its fish hanging off it, and
-- numbers go in base 36 against a fixed epoch.
--
-- It is a new message type rather than a change to the old one, and that
-- is the whole reason it is safe. The wire has no version byte, so a
-- client that never updates would read "p9x2" out of the holder field,
-- store it as an angler, and gossip it round the realm as a person. Old
-- clients ignore a type they don't know; they simply carry on with the
-- long form.
------------------------------------------------------------------------

-- Before the addon existed, so every real timestamp is a positive offset.
local TIME_EPOCH = 1700000000

-- The version that can read it. Anyone older gets the long form.
local COMPACT_SINCE = "0.8.1"

PackBook2 = function(self, list)
    -- One block per spot, with every fish caught there hanging off it.
    local order, bySpot = {}, {}
    for _, e in ipairs(list) do
        if not bySpot[e.key] then
            bySpot[e.key] = {}
            order[#order + 1] = e
        end
        local block = bySpot[e.key]
        block[#block + 1] = e
    end

    local names, named, spots = {}, {}, {}
    for _, first in ipairs(order) do
        local key = first.key
        local spotName = self:SpotNameForWire(key)
        local px, py = PackPos(self,key,first.mapID)
        local parts = { ("%s,%s,%s,%s,%s"):format(key, self:Pack36(first.mapID or 0),
            spotName, px, py) }
        for _, e in ipairs(bySpot[key]) do
            local h = self:Hash(self:AnglerKey(e.h))
            if not named[h] then
                named[h] = true
                names[#names + 1] = ("%s,%s,%s"):format(self:Pack36(h),
                    tostring(e.h):gsub("[,;~|]", " "), self:FactionOf(e.h) or "")
            end
            parts[#parts + 1] = ("%s,%s,%s,%s,%s"):format(self:Pack36(e.id),
                self:EncodeWeight(e.w), self:Pack36(h),
                self:Pack36(math.max(0, (e.t or 0) - TIME_EPOCH)), e.s and 1 or 0)
        end
        spots[#spots + 1] = table.concat(parts, "|")
    end
    return table.concat(names, ";"), table.concat(spots, ";")
end

function MF.handlers.RBOOK2(self, sender, packedNames, packedSpots)
    lastBook = GetTime()
    self:MarkAnswered("rbook")

    -- Who the hashes belong to. Everything else in the message refers back
    -- to this, so it travels with it rather than being looked up.
    local who = {}
    for entry in (packedNames or ""):gmatch("[^;]+") do
        local h, name, faction = strsplit(",", entry)
        if h and name and name ~= "" then
            who[h] = name
            self:NoteFaction(name, faction)
        end
    end

    local theirs, learned = {}, 0
    for block in (packedSpots or ""):gmatch("[^;]+") do
        local fields = { strsplit("|", block) }
        local key, mapID, name, px, py = strsplit(",", table.remove(fields, 1) or "")
        if self:IsSpotKey(key) then
            mapID = self:Unpack36(mapID)
            self:RememberSpotName(key, name)
            UnpackPos(self, key, mapID, px, py)
            for _, fish in ipairs(fields) do
                local id, w, h, t, spec = strsplit(",", fish)
                -- A hash we have no name for is dropped rather than shown.
                -- A record is only worth having if it can say whose it is.
                local holder = who[h]
                if holder then
                    local weight = self:DecodeWeight(w)
                    local when = self:Unpack36(t) + TIME_EPOCH
                    if self:MergeRecord(key, mapID, self:Unpack36(id), weight, holder,
                        when, spec == "1") then
                        learned = learned + 1
                    end
                    if not theirs[key] or weight > theirs[key].w then
                        theirs[key] = { w = weight, t = when }
                    end
                end
            end
        end
    end
    AfterBook(self, sender, theirs, learned)
end

-- Who can read the short form
--
-- The census tells us what everyone is running, so this is answerable
-- rather than guessed. When we don't know, we assume they can't: a record
-- that doesn't arrive is a gap that closes at the next sync, and one that
-- arrives unreadable is a hash sitting on a leaderboard forever.
function MF:SpeaksCompact(name)
    local a = name and self.db.anglersSeen[self:AnglerKey(name)]
    local v = a and a.version
    return v ~= nil and not self:VersionNewer(COMPACT_SINCE, v)
end

-- A book shouted down the channel reaches everyone, so it can only be short
-- when nobody listening would choke on it. One angler still on an old
-- version holds the whole realm back, which is the correct trade: they stop
-- getting records otherwise.
function MF:RealmSpeaksCompact()
    local anyone = false
    for _, p in pairs(self:RecentCensusPlayers()) do
        anyone = true
        if self:VersionNewer(COMPACT_SINCE, p.version or "0") then return false end
    end
    return anyone
end

-- Every book leaves through here, so there is one place that decides which
-- form to use and one place to change when the long one can finally go.
SendBook = function(self, to, list)
    if #list == 0 then return end
    local short = to and self:SpeaksCompact(to) or (not to and self:RealmSpeaksCompact())
    if short then
        local names, spots = PackBook2(self, list)
        if to then self:Whisper(to, "RBOOK2", names, spots)
        else self:SendWide("RBOOK2", names, spots) end
        return
    end
    if to then self:Whisper(to, "RBOOK", PackBook(self, list))
    else self:SendWide("RBOOK", PackBook(self, list)) end
end

MF:On("TFL_SYNC", function(self) self:RequestBook() end)

------------------------------------------------------------------------
-- Filling the gaps
--
-- The original book carried only our records and the King of every spot.
-- Nobody relayed anybody else's ordinary records, so their holders could
-- remain invisible unless they happened to be online with you.
--
-- Over weeks that leaves every client with a different idea of who holds
-- what. The board stops being a leaderboard and becomes a rumour: two
-- anglers can read their own screens and each come away believing they
-- are first, which is exactly what happened.
--
-- Tallies supplement the rotating book: say how many records we hold for each angler and let
-- anyone holding more fill in the difference. A count is small, and it is
-- the one thing that makes a reply targeted - without it the only honest
-- move is to send everything to everybody, which is what the book was
-- capped at eighty entries to avoid.
--
-- Anglers go on the wire hashed, not named: "shamalayahironrush" is
-- eighteen bytes of a two-hundred-and-twenty byte message, and nothing
-- here ever needs the name back. Both sides hash their own.
------------------------------------------------------------------------

local TALLY_MAX = 40     -- anglers per tally: the ones a gap matters for
local GAP_MAX = 25       -- records handed over in one reply
local GAP_MIN = 3        -- a surplus smaller than this isn't worth a message
local MAX_GAPS = 2       -- replies per session, so a busy realm can't echo
-- A tally goes out over the channel, the guild and the group, so the same
-- one arrives up to three times. Without this, one angler asking once would
-- spend every gap reply we had on three copies of the same answer.
local TALLY_COOLDOWN = 300
local tallyAnswered = {} -- angler key -> when we last filled their gaps

-- On MF rather than hidden in a local, so a test can put the session back
-- to the start and the count is visible to anyone debugging a quiet realm.
MF.gapsSent = 0

-- How many records we hold for each angler, by the hash we put on the wire.
local function Tally(self)
    local counts = {}
    for _, s in pairs(self.db.spots) do
        for _, rec in pairs(s.fish) do
            local key = self:AnglerKey(rec.h)
            if key ~= "" then
                local h = self:Hash(key)
                counts[h] = (counts[h] or 0) + 1
            end
        end
    end
    return counts
end

function MF:SendTally(to)
    local list = {}
    for h, n in pairs(Tally(self)) do list[#list + 1] = { h = h, n = n } end
    -- Most records first: the gaps that decide the order at the top of the
    -- board are the ones worth the bytes. The hash breaks ties so two
    -- clients with the same counts cut the list in the same place.
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.h < b.h
    end)
    local out = {}
    for i = 1, math.min(#list, TALLY_MAX) do
        out[#out + 1] = ("%d:%d"):format(list[i].h, list[i].n)
    end
    if #out > 0 then
        if to then self:Whisper(to, "RTALLY", table.concat(out, ";"))
        else self:SendWide("RTALLY", table.concat(out, ";")) end
    end
end

-- Records we hold for anglers the asker is short on. Kings are left out on
-- purpose: those already travel in every book that goes round, so sending
-- them again spends the reply on the one thing that didn't need it.
local function GapEntries(self, short)
    local list = {}
    for key, s in pairs(self.db.spots) do
        local king = self:King(key)
        local mapID = self:SpotRecordMap(key)
        for id, rec in pairs(s.fish) do
            local isKing = king ~= nil and king.id == id
            if not isKing and not self:SpotLabelProblem(key) and short[self:Hash(self:AnglerKey(rec.h))] then
                list[#list + 1] = { key = key, id = id, w = rec.w, h = rec.h,
                    t = rec.t, s = rec.s, mapID = mapID or 0 }
            end
        end
    end
    if #list <= GAP_MAX then return list end

    -- A window at a random offset rather than the heaviest every time. The
    -- same reply twice teaches the asker nothing: they merged it the first
    -- time, their count went up, and they would ask again and be handed the
    -- identical twenty-five. Moving the window is what makes repeated
    -- exchanges eventually cover everything.
    list = Weave(list)
    local out, start = {}, math.random(#list)
    for i = 0, GAP_MAX - 1 do
        out[#out + 1] = list[(start + i - 1) % #list + 1]
    end
    return out
end

function MF.handlers.RTALLY(self, sender, packed)
    if self.gapsSent >= MAX_GAPS or self:IsMe(sender) then return end
    local mine, short, any = Tally(self), {}, false
    for pair in (packed or ""):gmatch("[^;]+") do
        local h, n = strsplit(":", pair)
        h, n = tonumber(h), tonumber(n)
        if h and n and (mine[h] or 0) - n >= GAP_MIN then
            short[h], any = true, true
        end
    end
    if not any then return end

    local who = self:AnglerKey(sender)
    if GetTime() - (tallyAnswered[who] or -math.huge) < TALLY_COOLDOWN then return end

    local list = GapEntries(self, short)
    if #list == 0 then return end
    tallyAnswered[who] = GetTime()
    self.gapsSent = self.gapsSent + 1
    -- Straight to the angler who asked, not the channel: the gap was worked
    -- out against their count and nobody else's.
    self:ReplySoon(3, 9, function()
        SendBook(self, sender, list)
    end)
end

MF:On("TFL_SYNC", MF.SendTally)

MF:Command("sync", "Other", "/tfl sync [name] - discover anglers and swap records, or sync with one angler",
    function(self, args, raw)
        local who = raw ~= "" and raw or nil
        if who == "target" then
            who=self:TargetPlayerName()
            if not who then self:Print("Target a player, or use /tfl sync Full Name.") return end
        elseif not who and UnitIsPlayer("target") then who=self:TargetPlayerName() end
        if who then
            self:Print(("Swapping records with %s..."):format(who))
            local key = self:AnglerKey(who)
            askedBack[key] = GetTime()
            manualBookRequests[key] = true
            self:Whisper(who, "RASK", "ACK1", self:NearbyPeerMap(), self.cdb.profile.xp, self:TotalFishCaught(), self:Version())
            self:RequestPools(self:MapID(), who)
            self:RequestFrenzyObservations(who)
            return
        end
        local discovering = RequestRoster(self)
        if discovering then
            self:Print("Looking for anglers on the realm...")
        elseif GetTime() - rosterRequestedAt < 60 then
            self:Print("A realm scan ran recently. Try again in a minute.")
        elseif not self.db.settings.channel then
            self:Print("Automatic discovery is disabled in Options > Data.")
        elseif GetChannelName(self.CHANNEL) <= 0 then
            self:JoinChannel(true)
            self:Print(self:DiscoveryJoinStatus())
        elseif type(ListChannelByName) ~= "function" then
            self:Print("This client cannot request the discovery channel roster.")
        else
            self:Print("Requesting fishing records from available sync routes...")
        end
        self:RequestBook(true)
        self:AnnounceMyRecords()
        self:RequestRecords()
        self:SendTally()
    end)

------------------------------------------------------------------------
-- The heaviest of each fish
--
-- Spot records reward breadth: fish forty waters and you hold forty of
-- them. This is the same records cut the other way, and it rewards landing
-- one enormous fish instead - a different kind of angler, and one crown per
-- species rather than per lake.
--
-- Nothing is sent for it. It is built from the records every client already
-- holds, which is also why a species nobody has caught yet shows as
-- unclaimed rather than being left out: an empty row is an invitation.
------------------------------------------------------------------------

-- Returns held records (heaviest first) and species nobody holds yet
-- (biggest kind first, since those are the ones worth chasing).
function MF:SpeciesRecords(seasonOnly)
    local best, thisSeason = {}, self:SeasonID()
    for key, s in pairs(self.db.spots) do
        local fish = s.fish
        if seasonOnly then
            fish = self:SeasonTable(s, thisSeason)
        end
        for id, rec in pairs(fish or {}) do
            local cur = best[id]
            if (not cur or rec.w > cur.w) and not self:IsKnownJunk(id) then
                best[id] = { id = id, w = rec.w, h = rec.h, t = rec.t, s = rec.s, spot = key }
            end
        end
    end

    local held, open = {}, {}
    for _, rec in pairs(best) do held[#held + 1] = rec end
    for id, f in pairs(self.FISH) do
        if not best[id] then open[#open + 1] = { id = id, max = f.max } end
    end
    table.sort(held, function(a, b)
        if a.w ~= b.w then return a.w > b.w end
        return a.id < b.id
    end)
    table.sort(open, function(a, b)
        if a.max ~= b.max then return a.max > b.max end
        return a.id < b.id
    end)
    return held, open
end

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------

-- Records at a spot, heaviest first: { id, all = rec, season = rec }.
function MF:SpotRecords(key)
    local s = self:Spot(key)
    local list = {}
    if not s then return list end
    local seen = {}
    for id in pairs(s.fish) do seen[id] = true end
    for id in pairs(s.season) do seen[id] = true end
    for id in pairs(seen) do
        local all, season = s.fish[id], s.season[id]
        local seasonDiffers = season and (not all or season.w ~= all.w or not self:SameAngler(season.h, all.h))
        list[#list + 1] = { id = id, all = all, season = season, seasonDiffers = seasonDiffers }
    end
    table.sort(list, function(a, b)
        return (a.all and a.all.w or 0) > (b.all and b.all.w or 0)
    end)
    return list
end

local function PrintSpot(self)
    local key, name, mapID = self:SpotInfo()
    self:RememberSpotName(key, name, true)
    -- Same rule as a catch: only wait where there is something to wait for,
    -- or an unnamed map answers "try again in a few seconds" forever.
    if not self:RecordsReady(mapID) and self:RequestRecords(mapID) then
        self:Print("Still checking records with other anglers - try again in a few seconds.")
        return
    end
    local king = self:King(key)
    if not king then
        self:Print(("No records at %s yet. Be the first!"):format(name))
        return
    end
    self:Print(("King of %s: |cffffd100%s|r (%s, %s)"):format(
        name, self:ShortName(king.h), self:FishName(king.id), MF:Weight(king.w)))
    for _, r in ipairs(self:SpotRecords(key)) do
        local line = "  " .. self:FishName(r.id) .. ": "
        if r.all then
            line = line .. ("%s by %s"):format(MF:Weight(r.all.w), self:ShortName(r.all.h))
        end
        if r.seasonDiffers then
            line = line .. (" (this season: %s by %s)"):format(MF:Weight(r.season.w), self:ShortName(r.season.h))
        end
        print(line)
    end
end

MF:Command({ "spot", "records" }, "Progress", "/tfl spot - records and King at this spot", PrintSpot)

function MF:ResetRecordSync()
    sync,pending,losses={},{},{}
    flushScheduled=false
    lastBook,topUps,askedBack=-math.huge,0,{}
    bountySharedAt, bookSentAt = {}, {}
    bookCursors, tallyAnswered = {}, {}
    rosterRequestedAt, rosterContacted, rosterBudget = -math.huge, {}, 0
    rosterSeen, rosterAsked, rosterAnswered, confirmedPeers = {}, {}, {}, {}
    self.syncDiagnostics = { records = 0, bounties = 0, pools = 0 }
    self.gapsSent=0
end
