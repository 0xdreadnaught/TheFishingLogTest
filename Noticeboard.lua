-- Noticeboard: scheduled fishing events. Players post an event (where,
-- when, format), others sign up, and when the time comes it runs as an
-- ordinary match (Match.lua). The winner is Tournament Champion for a week.
--
-- There's no server, so the board lives in everyone's addon:
--   NPOST    the full notice. Sent when posted, and again every few minutes
--            by the host while it's open. relay=1 marks an answer to NREQ.
--   NSIGN    sign up (1) or withdraw (0)
--   NCANCEL  the host cancels
--   NREQ     "send me the board" (after login); one player answers
--   NRESULT  the top 3 and the champion, from whoever ran the match
-- Guild-only notices travel over guild chat, so only the guild ever sees
-- them. Public ones go to the guild and group as well as the channel - on
-- Forever the channel carries no addon messages at all, so "the channel"
-- alone meant your party and nobody else - and ride along on the whisper
-- swap with each angler the roster scan finds, which is the only road to
-- anglers in another guild.
--
-- If the host isn't online when the event should start, the first
-- signed-up player to notice takes over and runs it.
local _, MF = ...

local TITLE_MAX = 40
local MIN_AHEAD, MAX_AHEAD = 10 * 60, 7 * 86400
local MIN_LENGTH, MAX_LENGTH = 5, 120          -- minutes
local MIN_PLAYERS, MAX_PLAYERS = 2, 40
local MAX_OPEN_PER_HOST = 3
local MAX_NOTICES = 50
local REANNOUNCE_EVERY = 300    -- host re-sends open notices this often
local SIGNUP_ECHO_DELAY = 30    -- host re-sends soon after sign-ups change
local HOST_LEAD = 60            -- the match lobby opens this long before start
local TAKEOVER_AFTER = 120      -- seconds past start before someone takes over
local TAKEOVER_SPREAD = 20      -- random delay so only one player takes over
local GIVE_UP_AFTER = 600       -- seconds past start before "didn't start"
local KEEP_FINISHED = 3600      -- finished notices stay this long
local KEEP_CANCELLED = 600
local CHAMPION_FOR = 7 * 86400
local REMINDERS = { 600, 60 }   -- seconds before start

MF.NOTICE_LIMITS = {
    title = TITLE_MAX, minAhead = MIN_AHEAD, maxAhead = MAX_AHEAD,
    minLength = MIN_LENGTH, maxLength = MAX_LENGTH, minPlayers = MIN_PLAYERS, maxPlayers = MAX_PLAYERS,
}

local function Now() return GetServerTime() end

-- Free text travels to every player: no field separators, no escape codes.
local function Clean(text, max)
    text = tostring(text or ""):gsub("[~|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, max)
end

local function Board(self) return self.db.notices end

function MF:MatchIDFor(n) return "ev:" .. n.id end

function MF:NoticeForMatch(matchID)
    local id = type(matchID) == "string" and matchID:match("^ev:(.+)$")
    return id and Board(self)[id]
end

function MF:NoticeEndsAt(n)
    return (n.runStartsAt or n.startsAt) + n.duration
end

-- The sign-up list is keyed by whatever spelling of a name arrived, and
-- one angler can arrive under more than one (see Core's SplitName).
local function SignupKey(self, n, name)
    if not name then return end
    if n.signups[name] ~= nil then return name end
    for key in pairs(n.signups) do
        if self:SameAngler(key, name) then return key end
    end
end

function MF:IsSignedUp(n, name)
    return SignupKey(self, n, name or self.me) ~= nil
end

function MF:SignupCount(n)
    return self.Count(n.signups)
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------

local function SendScope(self, n, ...)
    if n.guild then
        if IsInGuild() and (not n.guildName or n.guildName == GetGuildInfo("player")) then self:SendGuild(...) end
    else
        self:SendWide(...)
    end
end

local function SignupList(n)
    local names = {}
    for name in pairs(n.signups) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ",")
end

local function SendNotice(self, n, relay)
    SendScope(self, n, n.guild and "NPOSTG1" or "NPOST", n.id, n.host, n.title, n.spot, Clean(n.spotName, 60), n.mapID,
        n.x or 0, n.y or 0, n.startsAt, n.duration, n.mode, n.fish or 0, n.flags or "",
        n.maxPlayers, n.guild and 1 or 0, n.updated, n.status, SignupList(n),
        Clean(n.results, 200), n.champion or "", relay and 1 or 0)
    if self:IsMe(n.host) then n.lastSent = GetTime() end
end

------------------------------------------------------------------------
-- Board maintenance
------------------------------------------------------------------------

local function OpenCountFor(self, host)
    local count = 0
    for _, n in pairs(Board(self)) do
        if self:SameAngler(n.host, host) and n.status == "open" then count = count + 1 end
    end
    return count
end

-- Keep the board bounded: drop the event furthest in the future.
local function EnforceCap(self)
    local board = Board(self)
    while self.Count(board) > MAX_NOTICES do
        local furthest
        for _, n in pairs(board) do
            if not furthest or n.startsAt > furthest.startsAt then furthest = n end
        end
        board[furthest.id] = nil
    end
end

local function Valid(n)
    local now = Now()
    return n.id and n.host and n.title ~= ""
        and n.startsAt and n.startsAt <= now + MAX_AHEAD + 600
        and n.duration and n.duration >= MIN_LENGTH * 60 and n.duration <= MAX_LENGTH * 60
        and n.maxPlayers and n.maxPlayers >= MIN_PLAYERS and n.maxPlayers <= MAX_PLAYERS
        and MF.MODES[n.mode] ~= nil and MF:IsSpotKey(n.spot)
end

-- Cancelled events, remembered after they leave the board
--
-- A cancelled event stays on the board for ten minutes and is then dropped,
-- but anglers who missed the cancel go on passing the event on as open. With
-- nothing left to say it had been cancelled, the next copy to arrive looked
-- brand new, and the host's own client took it back and announced it again.
-- So a cancel is remembered until the event would have ended: copies of it
-- are refused, and the host answers whoever passed one on with the cancel.
local recancelled = {} -- angler key -> GetTime() we last sent them the cancel

local function Struck(self)
    self.db.cancelledNotices = self.db.cancelledNotices or {}
    local struck, now = self.db.cancelledNotices, Now()
    for id, untilAt in pairs(struck) do
        if type(untilAt) ~= "number" or now > untilAt then struck[id] = nil end
    end
    return struck
end

local function Strike(self, n)
    if n and n.id and n.startsAt and n.duration then
        Struck(self)[n.id] = self:NoticeEndsAt(n) + KEEP_FINISHED
    end
end

function MF:IsCancelledNotice(id) return Struck(self)[id] ~= nil end

function MF.handlers.NPOST(self, sender, id, host, title, spot, spotName, mapID, x, y, startsAt,
                           duration, mode, fish, flags, maxPlayers, guild, updated, status,
                           signups, results, champion, relay)
    if relay == "1" then self:MarkAnswered("nlist:" .. (guild == "1" and "g" or "p")) end
    if id and Struck(self)[id] then
        -- Ours, cancelled, and they still think it's on: tell them.
        if guild ~= "1" and status == "open" and self:IsMe(host) and not self:IsMe(sender) then
            local key = self:AnglerKey(sender)
            if key ~= "" and GetTime() - (recancelled[key] or -math.huge) >= 60 then
                recancelled[key] = GetTime()
                self:Whisper(sender, "NCANCEL", id)
            end
        end
        return
    end
    local n = {
        id = id, host = host, title = Clean(title, TITLE_MAX), spot = spot,
        spotName = Clean(spotName, 60), mapID = tonumber(mapID) or 0, x = tonumber(x), y = tonumber(y),
        startsAt = tonumber(startsAt), duration = tonumber(duration), mode = mode,
        fish = (tonumber(fish) or 0) > 0 and tonumber(fish) or nil, flags = flags or "",
        maxPlayers = tonumber(maxPlayers), guild = guild == "1", updated = tonumber(updated) or 0,
        status = status or "open", signups = {}, results = results ~= "" and results or nil,
        champion = champion ~= "" and champion or nil,
        legacyGuild = guild == "1" and not self.receivingGuildNotice or nil,
        guildName = guild == "1" and self.receivingGuildNotice and GetGuildInfo("player") or nil,
    }
    if not Valid(n) then return end
    for name in (signups or ""):gmatch("[^,]+") do n.signups[name] = n.updated end

    local board = Board(self)
    local old = board[id]
    if old then
        if old.guild and (not n.guild or self.lastRoad ~= "GUILD"
            or (old.guildName and old.guildName ~= n.guildName)) then return end
        if n.updated < old.updated then return end
        -- Only the host decides what an event is. A relay (or anyone else)
        -- may bring a newer sign-up list, but can't rewrite the event, hand
        -- it to a new host, or close it - the host's NCANCEL and NRESULT,
        -- and our own clock, are the only ways an event ends.
        if not self:SameAngler(sender, old.host) then
            for _, field in ipairs({ "host", "title", "spot", "spotName", "mapID", "x", "y", "startsAt",
                "duration", "mode", "fish", "flags", "maxPlayers", "guild", "guildName", "legacyGuild",
                "status", "results", "champion" }) do
                n[field] = old[field]
            end
        end
        -- Keep things only we know: our own sign-up if the host hasn't
        -- heard it yet, and how far our own copy has progressed.
        local mine = SignupKey(self, old, self.me)
        if mine and not SignupKey(self, n, self.me) and old.signups[mine] > n.updated then
            n.signups[mine] = old.signups[mine]
        end
        if old.status ~= "open" and n.status == "open" then n.status = old.status end
        n.reminded, n.takeover, n.runStartsAt = old.reminded, old.takeover, old.runStartsAt
    elseif n.status == "open" and OpenCountFor(self, host) >= MAX_OPEN_PER_HOST then
        return -- anti-spam: a host can only have a few open events
    end
    self:RememberSpotName(n.spot, n.spotName)
    board[id] = n
    EnforceCap(self)
    if not old and n.status == "open" then self:Fire("TFL_NOTICE_NEW", n) end
    self:RefreshJournal()
end

function MF.handlers.NPOSTG1(self, sender, ...)
    if self.lastRoad ~= "GUILD" or not IsInGuild() then return end
    self.receivingGuildNotice = true
    local ok, err = pcall(self.handlers.NPOST, self, sender, ...)
    self.receivingGuildNotice = nil
    if not ok then self:Debug("guild notice rejected: " .. tostring(err)) end
end

function MF.handlers.NSIGN(self, sender, id, on)
    local n = Board(self)[id]
    if not n then return end
    local late = n.status ~= "open"
    if late and not (on == "1" and n.status == "started" and Now() < self:NoticeEndsAt(n)) then return end
    if n.guild and (self.lastRoad ~= "GUILD" or (n.guildName and n.guildName ~= GetGuildInfo("player"))) then return end
    local key = SignupKey(self, n, sender)
    if on == "1" then
        if self:SignupCount(n) >= n.maxPlayers and not key then return end
        if not key and not self:AnglerCounts(sender) then
            if self:IsMe(n.host) then self:NoteOutdatedAngler(sender, "events") end
            return
        end
        n.signups[key or sender] = Now()
    elseif key then
        n.signups[key] = nil
    end
    -- The host echoes the updated list so everyone's copy agrees.
    if self:IsMe(n.host) then
        n.updated = Now()
        n.echoAt = n.echoAt or (GetTime() + SIGNUP_ECHO_DELAY)
    end
    -- Signed up after the start: the match goes straight back to them, for their Join pop-up
    if late and self.SendMatchTo then
        local m = self.matches[self:MatchIDFor(n)]
        if m and self.current == m then self:SendMatchTo(m, sender) end
    end
    self:RefreshJournal()
end

function MF.handlers.NCANCEL(self, sender, id)
    local n = Board(self)[id]
    if not n or not self:SameAngler(n.host, sender) then return end
    if n.guild and (self.lastRoad ~= "GUILD" or (n.guildName and n.guildName ~= GetGuildInfo("player"))) then return end
    n.status, n.updated = "cancelled", Now()
    Strike(self, n)
    self:RefreshJournal()
end

function MF.handlers.NREQ(self, sender, scope)
    local wantGuild = scope == "g"
    self:ReplyOnce("nlist:" .. (wantGuild and "g" or "p"), 1, 5, function()
        for _, n in pairs(Board(self)) do
            if n.guild == wantGuild and n.status ~= "cancelled" then SendNotice(self, n, true) end
        end
    end)
end

function MF.handlers.NRESULT(self, sender, id, results, champion)
    local n = Board(self)[id]
    if not n then return end
    if n.guild and (self.lastRoad ~= "GUILD" or (n.guildName and n.guildName ~= GetGuildInfo("player"))) then return end
    if not self:SameAngler(sender, n.host) and not SignupKey(self, n, sender) then return end
    n.status, n.results = "finished", Clean(results, 200)
    n.champion = champion ~= "" and champion or nil
    n.updated = Now()
    if n.champion then self.db.champions[self:AnglerKey(n.champion)] = Now() + CHAMPION_FOR end
    self:RefreshJournal()
end

function MF:RequestBoard()
    self:SendWide("NREQ", "p")
    if IsInGuild() then self:SendGuild("NREQ", "g") end
end

-- One public event, whispered whole to one angler.
local function WhisperNotice(self, recipient, n)
    self:Whisper(recipient, "NPOST", n.id, n.host, n.title, n.spot, Clean(n.spotName, 60), n.mapID,
        n.x or 0, n.y or 0, n.startsAt, n.duration, n.mode, n.fish or 0, n.flags or "",
        n.maxPlayers, 0, n.updated, n.status, SignupList(n),
        Clean(n.results, 200), n.champion or "", 0)
end

-- Open public events, whispered to one angler the roster swap has found.
-- Nobody else would ever tell an angler outside our guild and group.
local SHARE_MAX = 10
function MF:ShareNotices(recipient)
    if not recipient then return 0 end
    local list = {}
    for _, n in pairs(Board(self)) do
        if not n.guild and (n.status == "open" or n.status == "started") then list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return a.startsAt < b.startsAt end)
    for i = 1, math.min(SHARE_MAX, #list) do WhisperNotice(self, recipient, list[i]) end
    return math.min(SHARE_MAX, #list)
end

------------------------------------------------------------------------
-- Inviting an angler to an event
--
-- The event goes with the invite (the same NPOST the roster swap
-- whispers), so it lands on their board even if it never reached them
-- another way; NINV1 then says it was meant for them. A client older than
-- 1.1.2 ignores NINV1 and simply has the event on its board.
--
-- Held to what a match invite is held to: the receiver's invite settings,
-- their ignore list, and one invite a minute from the same angler.
------------------------------------------------------------------------

local INVITE_COOLDOWN = 60
local invitedBy = {} -- angler key -> GetTime() of their last invite we took

-- Who may invite to an event: its host, and anyone signed up to it, while
-- it is open. Guild events stay in the guild, which already sees them.
function MF:CanInviteToEvent(n)
    return n ~= nil and n.status == "open" and not n.guild
        and (self:IsMe(n.host) or self:IsSignedUp(n))
end

function MF:InviteToEvent(n, who)
    if not self:CanInviteToEvent(n) then
        self:Print("You can invite anglers to an open public event you're hosting or signed up for.")
        return false
    end
    who = strtrim(who or "")
    if who == "" then who = self:TargetPlayerName() or "" end
    if who == "" then
        self:Print("Who? Type their name, or target them first.")
        return false
    end
    if #who > 64 or who:find("[/|%c%[%]:~]") then
        self:Print("That doesn't look like a player's name.")
        return false
    end
    if self:IsMe(who) then return false end
    if SignupKey(self, n, who) then
        self:Print(("%s is already signed up."):format(self:ShortName(who)))
        return false
    end
    WhisperNotice(self, who, n)
    self:Whisper(who, "NINV1", n.id)
    self:Print(("Invited %s to %s."):format(who, n.title))
    return true
end

-- Invites waiting on this character, by event id: { from, at }. Ones for
-- events that have gone - ended, cancelled, or dropped off the board - are
-- cleared on the way in.
function MF:EventInviteStore()
    self.cdb.eventInvites = self.cdb.eventInvites or {}
    local store, now = self.cdb.eventInvites, GetServerTime()
    for id, inv in pairs(store) do
        local n = Board(self)[id]
        if type(inv) ~= "table" or not n or n.status == "cancelled" or n.status == "nostart"
            or now > self:NoticeEndsAt(n) then
            store[id] = nil
        end
    end
    return store
end

-- { n, from, at }, soonest first.
function MF:EventInvites()
    local out = {}
    for id, inv in pairs(self:EventInviteStore()) do
        out[#out + 1] = { n = Board(self)[id], from = inv.from, at = inv.at }
    end
    table.sort(out, function(a, b) return a.n.startsAt < b.n.startsAt end)
    return out
end

-- Invites still waiting for an answer: open, and not yet signed up to.
function MF:EventInviteCount()
    local count = 0
    for _, inv in ipairs(self:EventInvites()) do
        if inv.n.status == "open" and not self:IsSignedUp(inv.n) then count = count + 1 end
    end
    return count
end

function MF:EventInviteFrom(n)
    local inv = n and self:EventInviteStore()[n.id]
    return inv and inv.from or nil
end

function MF:DeclineEventInvite(n)
    if not n then return end
    self:EventInviteStore()[n.id] = nil
    self:RefreshJournal()
end

function MF.handlers.NINV1(self, sender, id)
    local n = Board(self)[id]
    if not n or n.status ~= "open" or n.guild or self:IsMe(sender) then return end
    local s = self.db.settings
    if not s.invites then return end
    if not s.invitesFromAnyone and not self:IsKnownPlayer(sender) then return end
    if C_FriendList and C_FriendList.IsIgnored and C_FriendList.IsIgnored(self:WhisperName(sender)) then return end
    local key = self:AnglerKey(sender)
    if key == "" or GetTime() - (invitedBy[key] or -math.huge) < INVITE_COOLDOWN then return end
    invitedBy[key] = GetTime()
    local store = self:EventInviteStore()
    local fresh = store[id] == nil
    store[id] = { from = sender, at = GetServerTime() }
    self:RefreshJournal()
    if not fresh or self:IsSignedUp(n) then return end
    self:Sound(SOUNDKIT.TELL_MESSAGE, "soundMatches")
    if self.ShowEventInvite then self:ShowEventInvite(n, sender) end
end

MF:On("TFL_SYNC", MF.RequestBoard)

------------------------------------------------------------------------
-- Player actions
------------------------------------------------------------------------

-- o: title, startsAt, minutes, mode, fish, team, hcp, guild, maxPlayers.
-- Returns the notice, or nil and a reason.
function MF:PostNotice(o)
    local now = Now()
    local title = Clean(o.title, TITLE_MAX)
    if title == "" then return nil, "Give your event a title." end
    local spot = self:CurrentSpot()
    if not self:IsSpotKey(spot.key) then return nil, "Can't work out where you are - try moving a little." end
    if o.startsAt < now + MIN_AHEAD then return nil, "Events must start at least 10 minutes from now." end
    if o.startsAt > now + MAX_AHEAD then return nil, "Events can be at most 7 days ahead." end
    if o.guild and not IsInGuild() then return nil, "You're not in a guild." end
    if OpenCountFor(self, self.me) >= MAX_OPEN_PER_HOST then
        return nil, ("You can have at most %d open events."):format(MAX_OPEN_PER_HOST)
    end

    local n = {
        id = self.me .. ":" .. now, host = self.me, title = title,
        spot = spot.key, spotName = spot.name, mapID = spot.mapID, x = spot.x, y = spot.y,
        startsAt = o.startsAt, duration = math.floor(o.minutes) * 60, mode = o.mode, fish = o.fish,
        flags = (o.team and "t" or "") .. (o.hcp and "h" or ""), maxPlayers = o.maxPlayers,
        guild = o.guild and true or false, updated = now, status = "open",
        guildName = o.guild and GetGuildInfo("player") or nil,
        signups = { [self.me] = now },
    }
    if not Valid(n) then return nil, "Something about that event isn't valid." end
    Board(self)[n.id] = n
    SendNotice(self, n)
    self:Print(("Posted |cffffd100%s|r for %s."):format(n.title, date("%a %H:%M", n.startsAt)))
    self:RefreshJournal()
    return n
end

-- Signing up stays open until the event ends: arriving after the start still gets you in.
-- (Our copy may read "didn't start" when we never heard the match; the host knows better.)
-- Withdrawing is only before the start.
function MF:CanSignUpLate(n)
    return (n.status == "started" or n.status == "nostart") and Now() < self:NoticeEndsAt(n)
end

function MF:SignUp(n, on)
    if n.status ~= "open" and not (on and self:CanSignUpLate(n)) then return end
    local mine = SignupKey(self, n, self.me)
    if on and not mine and self:RefuseOutdated("events") then return end
    if on and not mine and self:SignupCount(n) >= n.maxPlayers then
        self:Print("That event is full.")
        return
    end
    n.signups[mine or self.me] = on and Now() or nil
    SendScope(self, n, "NSIGN", n.id, on and 1 or 0)
    if not n.guild and not self:IsMe(n.host) then self:Whisper(n.host, "NSIGN", n.id, on and 1 or 0) end
    if self:IsMe(n.host) then n.updated = Now() end
    if on and n.status ~= "open" then
        self:Print(("Signed up for %s, which has started. The host will send you the match to join."):format(n.title))
        self:RefreshJournal()
        return
    end
    self:Print(on and ("Signed up for %s."):format(n.title) or ("Withdrew from %s."):format(n.title))
    self:RefreshJournal()
end

function MF:CancelNotice(n)
    if not self:IsMe(n.host) or n.status ~= "open" then return end
    n.status, n.updated = "cancelled", Now()
    Strike(self, n)
    SendScope(self, n, "NCANCEL", n.id)
    if not n.guild then
        for name in pairs(n.signups) do
            if not self:IsMe(name) then self:Whisper(name, "NCANCEL", n.id) end
        end
    end
    self:Print(("Cancelled %s."):format(n.title))
    self:RefreshJournal()
end

function MF:HideHost(host)
    self.db.hiddenHosts[host] = true
    self:Print(("Hiding events from %s."):format(self:ShortName(host)))
    self:RefreshJournal()
end

------------------------------------------------------------------------
-- Queries for the UI
------------------------------------------------------------------------

-- Visible notices: open and running first by start time, then the rest.
function MF:BoardNotices()
    local list = {}
    for _, n in pairs(Board(self)) do
        if not self.db.hiddenHosts[n.host] then list[#list + 1] = n end
    end
    local order = { started = 1, open = 2, finished = 3, nostart = 4, cancelled = 5 }
    table.sort(list, function(a, b)
        local oa, ob = order[a.status] or 9, order[b.status] or 9
        if oa ~= ob then return oa < ob end
        return a.startsAt < b.startsAt
    end)
    return list
end

-- The soonest open event you're signed up to (or nil).
function MF:NextSignedEvent()
    local best
    for _, n in pairs(Board(self)) do
        if n.status == "open" and self:IsSignedUp(n) and (not best or n.startsAt < best.startsAt) then
            best = n
        end
    end
    return best
end

------------------------------------------------------------------------
-- Running events
------------------------------------------------------------------------

local function RunEvent(self, n, late)
    if self:InMatch() then return false end
    if n.legacyGuild then return false end -- old guild notices remain viewable, never public takeovers
    local guild = n.guild and GetGuildInfo("player") or nil
    if n.guild and (not IsInGuild() or type(guild) ~= "string" or guild == "") then return false end
    if n.guildName and n.guildName ~= guild then return false end
    local startsAt = late and (Now() + 30) or n.startsAt
    n.runStartsAt = startsAt
    self:StartHostedMatch({
        id = self:MatchIDFor(n), spot = n.spot, name = n.spotName, mapID = n.mapID, x = n.x, y = n.y,
        duration = n.duration, startsAt = startsAt, mode = n.mode, fish = n.fish, flags = n.flags,
        guild = guild,
    })
    n.status = "started"
    if late then self:Print(("The host of %s isn't here, so you're running it."):format(n.title)) end
    return true
end

-- A match for one of our events was announced (by us or anyone).
MF:On("TFL_MATCH_ANNOUNCED", function(self, m)
    local n = self:NoticeForMatch(m.id)
    if not n then return end
    self:MarkAnswered("nstart:" .. n.id)
    if n.status == "open" then n.status = "started" end
    n.runStartsAt = m.startsAt
    self:RefreshJournal()
end)

local function Standout(self, m, standings)
    local parts = {}
    for i = 1, math.min(3, #standings) do
        local s = standings[i]
        local score = self:FormatScore(s.p, m):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        -- One fish wins these formats, so the line names it (it's kept after a
        -- reload, when the standings themselves are gone).
        local fish = (m.mode == "biggest" or m.mode == "specimen") and self.StandingDetail
            and self:StandingDetail(s.p, m, true) or ""
        parts[#parts + 1] = ("%d. %s %s%s"):format(s.place or i, self:ShortName(s.name), score,
            fish ~= "" and (" (" .. fish .. ")") or "")
    end
    -- Whole entries only: a cut-off fish name reads worse than a shorter list.
    local text = table.concat(parts, ", ")
    while #text > 200 and #parts > 1 do
        parts[#parts] = nil
        text = table.concat(parts, ", ")
    end
    return text
end

MF:On("TFL_MATCH_FINISHED", function(self, m, standings)
    local n = self:NoticeForMatch(m.id)
    if not n then return end
    local winner = standings[1]
    -- No champion unless at least two anglers actually competed.
    local champion = not m.team and self:HasWinner(m) and winner and winner.score > 0 and winner.name or nil
    n.status, n.results, n.champion, n.updated = "finished", Standout(self, m, standings), champion, Now()
    if champion then self.db.champions[self:AnglerKey(champion)] = Now() + CHAMPION_FOR end

    if self:IsMe(m.host) then
        SendScope(self, n, "NRESULT", n.id, Clean(n.results, 200), champion or "")
    end
    if self:IsMe(champion) then
        local p = self.cdb.profile
        p.champUntil = math.max(p.champUntil or 0, Now() + CHAMPION_FOR)
        p.updated = Now()
        self:MarkProfileChanged()
        self:Print(("|cffffd100You won %s! You're Tournament Champion for a week.|r"):format(n.title))
        self:Toast("Interface\\Icons\\Trade_Fishing", "TOURNAMENT CHAMPION", n.title,
            "Title for 7 days", 1, 0.82, 0, SOUNDKIT.UI_EPICLOOT_TOAST)
    end
    self:RefreshJournal()
end)

function MF:IsChampion(name, champUntil)
    local now = Now()
    if (champUntil or 0) > now then return true end
    if self:IsMe(name) and (self.cdb.profile.champUntil or 0) > now then return true end
    return (self.db.champions[self:AnglerKey(name)] or 0) > now
end

------------------------------------------------------------------------
-- The clock: re-announce, reminders, start, takeover, expiry
------------------------------------------------------------------------

local function Remind(self, n, now)
    if not self.db.settings.eventReminders or not self:IsSignedUp(n) then return end
    n.reminded = n.reminded or {}
    for _, before in ipairs(REMINDERS) do
        local due = n.startsAt - before
        if now >= due and now < n.startsAt and not n.reminded[before] then
            n.reminded[before] = true
            local text = ("%s starts in %s at %s."):format(n.title, self:FormatClock(n.startsAt - now), n.spotName)
            if before <= 60 then
                self:Toast("Interface\\Icons\\Trade_Fishing", "EVENT STARTING", n.title,
                    ("%s - %s"):format(n.spotName, self:FormatClock(n.startsAt - now)), 0.4, 0.8, 1,
                    SOUNDKIT.RAID_WARNING)
            end
            self:Print("|cff66ccff" .. text .. "|r")
        end
    end
end

local function Expired(self, n, now)
    if n.status == "cancelled" then return now > n.updated + KEEP_CANCELLED end
    return now > self:NoticeEndsAt(n) + KEEP_FINISHED
end

MF:OnTick(function(self)
    if not self.me then return end
    local now, clock = Now(), GetTime()
    for id, n in pairs(Board(self)) do
        if Expired(self, n, now) then
            Board(self)[id] = nil
        elseif n.status == "open" then
            Remind(self, n, now)
            if self:IsMe(n.host) then
                -- Our event: keep it announced, and open the match on time.
                if n.echoAt and clock >= n.echoAt then n.echoAt = nil; SendNotice(self, n) end
                if clock - (n.lastSent or -math.huge) >= REANNOUNCE_EVERY then SendNotice(self, n) end
                if now >= n.startsAt - HOST_LEAD then
                    RunEvent(self, n, now > n.startsAt + HOST_LEAD) -- late host: fresh start
                end
            elseif now >= n.startsAt + GIVE_UP_AFTER then
                n.status = "nostart"
            elseif now >= n.startsAt + TAKEOVER_AFTER and self:IsSignedUp(n) and not n.takeover
                and not self.matches[self:MatchIDFor(n)] then
                -- The host hasn't started it; whoever gets here first does.
                n.takeover = true
                self:ReplyOnce("nstart:" .. n.id, 0, TAKEOVER_SPREAD, function()
                    if n.status == "open" and not self.matches[self:MatchIDFor(n)] then
                        RunEvent(self, n, true)
                    end
                end)
            end
        end
    end
end)

MF:Command("board", "Matches", "/tfl board - the event noticeboard", function(self)
    self:ToggleJournal("board")
end)
