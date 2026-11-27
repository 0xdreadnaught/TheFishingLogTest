-- Launch reset: no beta data, archive or undo survives 4 November 2026 UTC.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

-- Manual character resets remain undoable within the current realm only.
function MF:KeepUndo(why)
    local cdb = self.cdb
    cdb.undo = {
        when = GetServerTime(), why = why, profile = cdb.profile, records = cdb.records,
        history = cdb.history, caughtIn = cdb.caughtIn, gear = cdb.gear,
        bounties = cdb.bounties,
    }
end

function MF:RestoreUndo()
    local cdb, u = self.cdb, self.cdb.undo
    if not u or not u.profile then return false end
    if GetServerTime()>=self.FRESH_START and (u.when or 0)<self.FRESH_START then cdb.undo=nil return false end
    cdb.profile, cdb.records = u.profile, u.records or {}
    cdb.history, cdb.caughtIn = u.history or {}, u.caughtIn or {}
    cdb.gear = u.gear or cdb.gear
    cdb.bounties = u.bounties or {}
    cdb.undo = nil
    self:MarkProfileChanged()
    self:RefreshJournal()
    self:UpdateBoard()
    return true, u
end

-- Reused character names must not inherit their beta log.
function MF:FreshStart(force)
    local at = self.FRESH_START
    if not force and GetServerTime() < at then return false end
    local realmNeeded = force or self.db.freshStart ~= at or self.db.launchReset~=at
    local characterNeeded = realmNeeded or self.cdb.freshStart ~= at or self.cdb.launchReset~=at
    if not realmNeeded and not characterNeeded then return false end
    -- Read before the reset: a brand-new install has nothing to clear and
    -- should not be told its beta progress was taken away.
    local p = self.cdb.profile
    -- A new alt on an already-reset realm only has its own log to lose.
    local charData = p and ((p.xp or 0) > 0 or next(p.journal or {}) ~= nil) or false
    local hadData = force or charData or (realmNeeded and (self.hadBetaData
        or self.db.lastVersion ~= nil or next(self.db.spots or {}) ~= nil))
    self.hadBetaData = nil

    self.dataGeneration=(self.dataGeneration or 0)+1
    self:ResetFishingState()
    self:UpdateFishingMusic(true)
    self:InitializeLaunchData(realmNeeded)
    self.db.freshStart, self.cdb.freshStart = at, at
    self.db.launchReset,self.cdb.launchReset=at,at
    if realmNeeded then self.db.clearLaunchMacros=true end
    self:ClearLaunchMacros()
    if realmNeeded then TheFishingLogDiscord=nil end
    self.session,self.current,self.matches=nil,nil,{}
    self.recapPrevious,self.recapProfile,self.recapActive=nil,self.cdb.profile,false
    self.bountyRewardWait,self.localWaterSelected,self.goalFishSelected=nil,nil,nil
    self.profileDirty,self.macroDirty,self.profileRestored=false,false,nil
    self.recapOffered,self.recapReadyAt=false,GetTime()+30
    self:ResetCommunicationState()
    self:ResetCatchState()
    self:ResetCastOutcomes()
    self:ResetCatchSkill()
    self:ResetRecordSync()
    self:ResetAnglerState()
    self:ResetRealmRankCache()
    self:ResetCensus()
    self:ResetNearbyCatches()
    self:ResetPoolObservation()
    self:ResetFrenzyDiscoveryRuntime()
    self:ForgetNamelessLow()
    self:ForgetCurrentSpot()
    self:ResetFishingFeedback()
    self:ResetJournalState()
    self:ResetCatchFloat()
    self:ResetFishingOutfit()
    if hadData then
        self:Print("|cffffd100A new realm, a completely fresh fishing log.|r Beta progress, records, locations, outfits, backups and settings have been cleared. No beta archive is kept.")
    end
    self:UpdateMinimapButton()
    self:ApplyBoardScale()
    self:UpdateWeaponSwapButton()
    self:RefreshPoolPins()
    self:RefreshMapPins()
    self:RefreshJournal()
    self:UpdateBoard()
    return true
end

-- Core runs this before login listeners and at the deadline while online.

------------------------------------------------------------------------
-- Compatibility with the Realm tab: there is no retained beta board.
------------------------------------------------------------------------

function MF:FoundingLines() return nil end

-- Undocumented: run the wipe now, for seeing what it does before it happens.
MF:Command("restore", "Other", "/tfl restore - put back a log that was emptied",
    function(self)
        local ok, u = self:RestoreUndo()
        if not ok then
            self:Print("Nothing to put back - this character's log hasn't been emptied.")
            return
        end
        self:Print(("Put back what %s cleared on %s: %d XP, %d journal entries, %d sessions."):format(
            u.why or "something", date("%d %B", u.when or 0), u.profile.xp or 0,
            self.Count(u.profile.journal or {}), #(u.history or {})))
    end)

MF:Command("freshstart", "Other", nil, function(self)
    if self:FreshStart() then return end
    self:Print("The clean launch reset is automatic on 4 November 2026 at 00:00 UTC and runs once.")
end)

------------------------------------------------------------------------
-- Clearing out what was never a fish
--
-- Before the junk list existed, anything that came up on the hook was
-- weighed - so cloth, potions, cloaks and sealed trunks took spot records
-- and have been sitting on leaderboards ever since, travelling from angler
-- to angler like anything else.
--
-- Fixing the weighing stopped new ones. It did nothing about the ones
-- already out there, which is why this walks what we hold and takes them
-- out. It uses IsKnownJunk, never the guess: a record is somebody's, and
-- deleting one on a hunch is much worse than leaving it.
--
-- MergeRecord refuses the same items now, which is the half that makes it
-- hold - otherwise the next book round the realm would hand them all back.
------------------------------------------------------------------------

local PURGE = 2 -- bump when the junk list grows, to sweep again

local function Sweep(self, fish)
    local gone = 0
    for id in pairs(fish or {}) do
        if self:IsKnownJunk(id) then
            fish[id] = nil
            gone = gone + 1
        end
    end
    return gone
end

-- Returns how many records, personal bests and journal entries went.
function MF:PurgeJunkRecords()
    local records, mine = 0, 0
    for _, s in pairs(self.db.spots) do
        records = records + Sweep(self, s.fish)
        Sweep(self, s.season)
        Sweep(self, s.lastSeason)
    end
    for _, fish in pairs(self.cdb.records or {}) do
        mine = mine + Sweep(self, fish)
    end
    local journal = Sweep(self, self.cdb.profile.journal)
    Sweep(self, self.cdb.caughtIn)
    return records, mine, journal
end

MF:On("TFL_LOGIN", function(self)
    if self.db.junkPurge == PURGE then return end
    self.db.junkPurge = PURGE
    local records, mine, journal = self:PurgeJunkRecords()
    if records + mine + journal == 0 then return end
    self:Print(("Cleared %d record%s that were never fish - cloth, potions and the like, "
        .. "weighed by an older version before the addon knew better."):format(
        records, records == 1 and "" or "s"))
    if journal > 0 then
        print(("  |cff858585%d journal %s went with them.|r"):format(
            journal, journal == 1 and "entry" or "entries"))
    end
    self:RefreshJournal()
    self:UpdateBoard()
end)

-- The sweep only takes what's on the list. Anything else that doesn't look
-- like a fish is pointed at rather than removed, because the list is the only
-- thing allowed to delete a record and it grows by being told. That list is
-- shown by /tfl report only: printed at login, it greeted brand-new players
-- with records they had only received from others and a request to paste
-- them somewhere, which read like the addon was broken.

MF:Command("purge", "Other", nil, function(self)
    local records, mine, journal = self:PurgeJunkRecords()
    self:Print(("Cleared %d spot record%s, %d of your own bests and %d journal %s."):format(
        records, records == 1 and "" or "s", mine, journal,
        journal == 1 and "entry" or "entries"))
    self:RefreshJournal()
    self:UpdateBoard()
end)
