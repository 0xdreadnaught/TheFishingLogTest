-- A personal baseline compared with the latest peer data, not a complete
-- offline event log. Missing data never establishes a loss or a winner.
local _, MF = ...
local LABELS = { day = "Daily", week = "Weekly", month = "Monthly" }
local function Header(text) return { text = MF.C.gold .. text .. "|r", header = true } end

function MF:CaptureRecap()
    local snapshot = { version = 1, owner = self.me, at = GetServerTime(), records = {}, kings = {}, bounties = {} }
    local records = {}
    for key, spot in pairs(self.db.spots) do
        for id, record in pairs(spot.fish or {}) do
            if self:IsMe(record.h) then records[#records + 1] = { key = key, id = id, weight = record.w } end
        end
        local king = self:King(key)
        if king and self:IsMe(king.h) then snapshot.kings[key] = true end
    end
    table.sort(records, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.id < b.id end)
    for i = 1, math.min(512, #records) do snapshot.records[i] = records[i] end
    snapshot.recordsTruncated = #records > 512
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        snapshot.bounties[kind] = { period = self:BountyPeriod(kind), score = self:MyBountyBest(kind) }
    end
    return snapshot
end

function MF:RecapChanges()
    if self.recapProfile and self.recapProfile ~= self.cdb.profile then self.recapPrevious = nil end
    local previous, changes = self.recapPrevious, { records = {}, kings = {}, ended = {}, unknown = 0 }
    if not previous then return changes end
    for _, old in ipairs(previous.records or {}) do
        if type(old.key) == "string" and type(old.id) == "number" and type(old.weight) == "number" then
            local key = self:CanonicalKey(old.key)
            local spot = self.db.spots[key]
            local latest = spot and spot.fish and spot.fish[old.id]
            if latest and latest.w >= old.weight and not self:IsMe(latest.h) then
                changes.records[#changes.records + 1] = { key = key, id = old.id, weight = old.weight, latest = latest }
            elseif not latest then changes.unknown = changes.unknown + 1 end
        end
    end
    for key in pairs(previous.kings or {}) do
        local canonical = self:CanonicalKey(key)
        local king = self:King(canonical)
        if king and not self:IsMe(king.h) then changes.kings[#changes.kings + 1] = { key = canonical, king = king } end
    end
    table.sort(changes.records, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.id < b.id end)
    table.sort(changes.kings, function(a, b) return a.key < b.key end)
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        local old = (previous.bounties or {})[kind]
        if old and type(old.period) == "number" and self:BountyPeriod(kind) > old.period then
            changes.ended[#changes.ended + 1] = { kind = kind, period = old.period, score = tonumber(old.score) or 0 }
        end
    end
    return changes
end

function MF:ShouldOpenRecap()
    if self.recapOffered or self.db.settings.loginRecap == false then return false end
    self.recapOffered = true
    if not self.recapPrevious then return false end
    local changes = self:RecapChanges()
    if GetTime() < (self.recapReadyAt or 0) then return true end
    if #changes.records + #changes.kings + #changes.ended > 0 then return true end
    for _, notice in ipairs(self:BoardNotices()) do
        if self:IsSignedUp(notice) and notice.status == "open" then return true end
    end
    return false
end

function MF:ShowRecap()
    if not self.recapActive then self.recapReturnTab = self.db.settings.journalTab or "journal" end
    self.recapActive, self.recapOffered = true, true
    self.db.settings.journalOffsets = self.db.settings.journalOffsets or {}
    self.db.settings.journalOffsets.recap = 0
    self:OpenJournal("journal")
end

function MF:RecapLines()
    local changes = self:RecapChanges()
    local out, previous = {}, self.recapPrevious
    out.hero = {
        title = previous and ("Welcome back, " .. self:ShortName(self.me)) or "Your next visit starts here",
        shortTitle = previous and "Welcome back" or "Your next visit",
        subtitle = previous and ("Since " .. date("%d %b, %H:%M", previous.at))
            or "We'll remember your records and bounties, then show what changed when you return.",
        shortSubtitle = previous and ("Since " .. date("%d %b, %H:%M", previous.at))
            or "We'll save your progress for your next visit.",
        status = GetTime() < (self.recapReadyAt or 0) and "Checking for updates..." or "Based on latest known angler data",
    }
    if previous then out.summary = {
        { value = tostring(#changes.records), label = "Records challenged", shortLabel = "Records" },
        { value = tostring(#changes.ended), label = "Bounties ended", shortLabel = "Bounties" },
        { value = "0", label = "Signed-up events", shortLabel = "Events" },
    } end
    if #changes.records + #changes.kings > 0 then out[#out + 1] = Header("Records to reclaim") end
    for i = 1, math.min(12, #changes.records) do
        local loss = changes.records[i]
        out[#out + 1] = { text = self:FishName(loss.id), icon = self:FishIcon(loss.id),
            right = self:Weight(loss.latest.w), group = true, featured = true,
            onClick = function() self:PointToSpot(loss.key) end }
        self:NoteRows(out, self:SpotName(loss.key) .. " - now held by " .. self:ShortName(loss.latest.h)
            .. "; " .. self:Weight(loss.latest.w - loss.weight) .. " above your saved record. Click the fish to find the water.")
    end
    if #changes.records > 12 then self:NoteRows(out, (#changes.records - 12) .. " additional record changes are available in Records.") end
    if changes.unknown > 0 then self:NoteRows(out, changes.unknown .. " saved records cannot yet be compared; missing data is not a loss.") end
    if previous and previous.recordsTruncated then self:NoteRows(out, "The saved baseline contains the first 512 held records.") end
    for _, change in ipairs(changes.kings) do
        out[#out + 1] = { text = "King changed: " .. self:SpotName(change.key),
            right = self:ShortName(change.king.h), onClick = function() self:PointToSpot(change.key) end }
    end

    if #changes.ended > 0 then
        out[#out + 1] = { text = "" }
        out[#out + 1] = Header("Bounty results")
    end
    for _, ended in ipairs(changes.ended) do
        local settled = self:BountyRewardResult(ended.kind, ended.period)
        local standings = self:BountyStandings(ended.kind, ended.period)
        local place = self:BountyPlace(self.me, ended.kind, ended.period)
        out[#out + 1] = { text = LABELS[ended.kind] .. " bounty ended",
            right = settled and ("#" .. settled.place .. " / +" .. settled.xp .. " XP")
                or (ended.score > 0 and "Result not settled" or "No saved entry") }
        if settled then
            self:NoteRows(out, "Saved settlement: " .. self:BountyScoreText(ended.kind, settled.score, ended.period, settled.specimen)
                .. ". Later peer updates may show different standings; this is the result used for your reward.")
        end
        if ended.score > 0 then
            self:NoteRows(out, "Your saved entry: " .. self:BountyScoreText(ended.kind, ended.score, ended.period, self:BountySpecimenStatus(ended.kind,self.me,ended.period,ended.score))
                .. (place and ("; position " .. place .. " in known standings.") or "; final position unavailable."))
        end
        if standings[1] then self:NoteRows(out, "Latest known leader: " .. self:ShortName(standings[1].name) .. ".")
        else self:NoteRows(out, "Results unavailable. No winner is inferred from missing standings.") end
    end
    local _, id, zone = self:TodayBounty()
    out[#out + 1] = { text = "" }
    out[#out + 1] = Header("Something to chase today")
    out[#out + 1] = { text = self:BountyTitle("day"), icon = self:FishIcon(id), featured = true, group = true,
        right = self:FormatSpan(self:BountyTimeLeft("day")),
        onClick = function() self.recapActive = false self:OpenJournal("bounty") end }
    out[#out + 1] = { text = zone or "Any eligible water", right = "Daily bounty", featured = true }
    self:NoteRows(out, "Click the fish to open the bounty.")

    local events = 0
    for _, notice in ipairs(self:BoardNotices()) do
        if self:IsSignedUp(notice) then
            events = events + 1
            if events == 1 then
                out[#out + 1] = { text = "" }
                out[#out + 1] = Header("Coming up for you")
            end
            if events <= 8 then
                local left = notice.startsAt - GetServerTime()
                local state = notice.status == "open" and (left > 0 and ("in " .. self:FormatSpan(left)) or "due to start")
                    or notice.status
                out[#out + 1] = { text = notice.title, right = state, group = true, featured = true,
                    onClick = function() self.recapActive = false self:OpenEvent(notice.id) end }
                self:NoteRows(out, notice.spotName .. " - " .. date("%d %b %H:%M", notice.startsAt))
            end
        end
    end
    if out.summary then out.summary[3].value = tostring(events) end
    if events > 8 then self:NoteRows(out, (events - 8) .. " more signed-up events in Events.") end
    if not previous then
        out[#out + 1] = { text = "" }
        self:NoteRows(out, "No previous visit snapshot yet. Your recap starts with this visit.")
    elseif #changes.records + #changes.kings + #changes.ended + events == 0 then
        out[#out + 1] = { text = "" }
        self:NoteRows(out, "You're caught up. No confirmed changes in the data available so far.")
    end
    return out, {
        { label = "Continue", onClick = function() self.recapActive = false self:OpenJournal(self.recapReturnTab or "journal") end },
        { label = "Check again", onClick = function()
            self:Fire("TFL_ROSTER_SYNC")
            self:RequestBook(true)
            self:RequestBounty()
            self:RequestRecords()
            self.recapReadyAt = GetTime() + 15
            self:RefreshJournal()
        end },
    }
end

MF:On("TFL_LOGIN", function(self)
    self.recapProfile = self.cdb.profile
    local previous = self.cdb.profile.recapSnapshot
    self.recapPrevious = type(previous) == "table" and previous.version == 1
        and type(previous.at) == "number" and self:IsMe(previous.owner) and previous or nil
    -- Quiet discovery starts after the delayed channel join, then staggers
    -- the requests so several peers do not all answer at once.
    local wait = not self.CUSTOM_CHANNEL_SUPPORTED and self.db.settings.channel and 45 or 30
    self.recapReadyAt, self.recapOffered, self.recapActive = GetTime() + wait, false, false
end)
MF:On("PLAYER_LOGOUT", function(self) self.cdb.profile.recapSnapshot = self:CaptureRecap() end)
local savedAt = 0
MF:OnTick(function(self)
    if self.recapActive then self:RefreshJournal() end
    if GetTime() - savedAt >= 300 then
        savedAt = GetTime()
        self.cdb.profile.recapSnapshot = self:CaptureRecap()
    end
end)
MF:Command("recap", "Progress", "/tfl recap - changes since your last saved visit", MF.ShowRecap)
