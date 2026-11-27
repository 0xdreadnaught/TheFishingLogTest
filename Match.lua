-- Match: hosting, joining, formats, validation, scoring, results and sharing.
local _, MF = ...
-- A dormant copy (Core.lua) leaves the running copy's dialogs alone.
local POPUPS = MF.inert and {} or StaticPopupDialogs
local function print(...) MF:PrintChat(...) end

local LOBBY_SECONDS = 30      -- time between hosting and the first cast counting
local ANNOUNCE_EVERY = 10     -- host re-announces so late arrivals see the match
local MIN_CATCH_GAP = 3       -- seconds; faster than this isn't a real cast
local BOBBER_MAX = 3          -- catches one bobber can deliver at once
local SPRINT_MINUTES = 5
local XP_PLAYED, XP_WON, XP_TEAM_WON = 20, 100, 50
local MAX_DISTANCE = 0.12     -- map units from the host's anchor that still count
local PRUNE_EVERY = 60        -- seconds between clean-ups of old matches
local FORGET_AFTER = 600      -- seconds after a match ends before we forget it

MF.MODES = {
    weight   = "Heaviest total bag",
    biggest  = "Biggest single fish",
    count    = "Most fish caught",
    specimen = "First specimen wins",
}

MF.matches = {}   -- every match we've heard of, by id
MF.current = nil  -- the match we're in

local function Now() return GetServerTime() end

local function NewMatch(id, host, spot, name, mapID, x, y, duration, startsAt, mode, fish, flags)
    flags = flags or ""
    return {
        id = id, host = host, spot = spot, name = name,
        mapID = tonumber(mapID) or 0, x = tonumber(x), y = tonumber(y),
        duration = duration, startsAt = startsAt, endsAt = startsAt + duration,
        mode = MF.MODES[mode] and mode or "weight",
        fish = (tonumber(fish) or 0) > 0 and tonumber(fish) or nil,
        team = flags:find("t") ~= nil, hcp = flags:find("h") ~= nil,
        players = {}, seen = {}, seq = 0, heard = Now(),
    }
end

-- One angler can reach us under more than one spelling of their name (see
-- Core's SplitName). Whatever spelling arrives first is the one kept.
local function PlayerName(m, name)
    m.keys = m.keys or {}
    local key = MF:AnglerKey(name)
    local known = m.keys[key]
    if known and m.players[known] then return known end
    m.keys[key] = name
    return name
end
MF.MatchPlayerName = function(_, m, name) return PlayerName(m, name) end

local function Stats(m, name)
    name = PlayerName(m, name)
    local p = m.players[name]
    if not p then
        p = { count = 0, total = 0, biggest = 0, specimens = 0, seq = 0, lastT = 0,
            rank = 1, rejected = 0 }
        m.players[name] = p
    end
    return p
end

local function IsBusy(m)
    return m ~= nil and not m.finished and not m.cancelled
end

function MF:InMatch()
    return IsBusy(self.current)
end

------------------------------------------------------------------------
-- Teams and handicap
------------------------------------------------------------------------

-- Your team is your party leader; in a raid it's your raid group.
function MF:MyTeam()
    if IsInRaid() then
        local idx = UnitInRaid("player")
        local subgroup = idx and select(3, GetRaidRosterInfo(idx))
        return "Group " .. (subgroup or 1)
    end
    if IsInGroup() then
        if UnitIsGroupLeader("player") then return self.me end
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then return self:FullName(UnitFullName(unit)) end
        end
    end
    return self.me
end

function MF:TeamLabel(team)
    if team and team:find("-", 1, true) then
        return self:ShortName(team) .. "'s team"
    end
    return team or "?"
end

-- Low-skill anglers get up to +50% weight in handicap matches.
function MF:HandicapFactor()
    local skill = self:FishingSkill()
    if not skill then return 1 end
    return 1 + math.max(0, 300 - skill) / 600
end

------------------------------------------------------------------------
-- Scoring
------------------------------------------------------------------------

function MF:Score(p, mode)
    if mode == "count" then return p.count end
    if mode == "biggest" then return p.biggest end
    if mode == "specimen" then
        -- Earliest specimen wins; without one, biggest fish breaks ties.
        return p.firstSpec and (3e9 - p.firstSpec) or p.biggest / 1000
    end
    return p.total
end

function MF:FormatScore(p, m)
    if m.mode == "count" then return tostring(p.count) end
    if m.mode == "biggest" then return MF:Weight(p.biggest) end
    if m.mode == "specimen" then
        if p.firstSpec then
            return "|cffffd100specimen|r " .. self:FormatClock(p.firstSpec - m.startsAt)
        end
        return "best " .. self:Weight(p.biggest)
    end
    return MF:Weight(p.total)
end

-- What the score is made of
--
-- A weight on its own says who won; the fish says how. Every catch arrives
-- with its item, so each angler keeps the item behind their biggest fish,
-- their first specimen and a tally of what they've landed. A SCORE snapshot
-- carries the first two from 1.1.3 on; from anyone older, or after a
-- snapshot we can't account for, the row simply shows the weight.

local SPECIMEN_MARK = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"

-- "Raw Bristle Whisker Catfish" reads as "Bristle Whisker Catfish" on a row.
function MF:ShortFishName(itemID)
    return (self:FishName(itemID):gsub("^Raw ", ""))
end

-- The fish behind a standing: itemID, specimen. Nil when we don't know it.
function MF:StandingFish(p, m)
    if not p then return end
    if m.mode == "specimen" and p.firstSpec then return p.firstSpecID, true end
    if (p.biggest or 0) > 0 and p.biggestID then return p.biggestID, p.biggestSpec end
end

-- The kind landed most, only while every catch is accounted for: a snapshot
-- replaces the count without saying what was in it.
function MF:StandingMostly(p)
    if not p or not p.kinds then return end
    local n, best, bestN = 0, nil, 0
    for id, c in pairs(p.kinds) do
        n = n + c
        if c > bestN or (c == bestN and id < best) then best, bestN = id, c end
    end
    if n == p.count then return best end
end

-- A few words beside the score on a standings row. plain drops the colours
-- and the specimen mark, for chat and the Results line.
function MF:StandingDetail(p, m, plain)
    if not p or (p.count or 0) == 0 then return "" end
    local id, spec = self:StandingFish(p, m)
    local fish = ""
    if id then
        fish = self:ShortFishName(id)
        if not plain then
            if spec then
                fish = "|cffffd100" .. fish .. "|r " .. SPECIMEN_MARK
            else
                -- A handicapped weight isn't the fish's own, so it isn't graded.
                local colour
                if not m.hcp then colour = select(2, self:WeightGrade(id, p.biggest)) end
                fish = (colour or "|cffbbbbbb") .. fish .. "|r"
            end
        elseif spec and m.mode ~= "specimen" then
            -- (the specimen format's score already says so)
            fish = "specimen " .. fish
        end
    end
    if m.mode == "weight" then
        local text = ("%d fish"):format(p.count)
        if id then text = text .. ", best " .. fish .. " " .. self:Weight(p.biggest) end
        return plain and text or ("|cffa0a0a0" .. text .. "|r")
    elseif m.mode == "count" then
        local mostly = self:StandingMostly(p)
        local text = self:Weight(p.total) .. (mostly and (", mostly " .. self:ShortFishName(mostly)) or "")
        return plain and text or ("|cffa0a0a0" .. text .. "|r")
    end
    return fish
end

local function Sorted(list, mode)
    for _, s in ipairs(list) do s.score = MF:Score(s.p, mode) end
    table.sort(list, function(x, y)
        if x.score ~= y.score then return x.score > y.score end
        return x.name < y.name
    end)
    local place, last = 0, nil
    for i, entry in ipairs(list) do
        if entry.score ~= last then place, last = i, entry.score end
        entry.place = place
    end
    return list
end

function MF:Standings(m)
    local list = {}
    for name, p in pairs(m.players) do
        list[#list + 1] = { name = name, p = p }
    end
    return Sorted(list, m.mode)
end

function MF:TeamStandings(m)
    local teams = {}
    for name, p in pairs(m.players) do
        local key = p.team or name
        local t = teams[key]
        if not t then
            t = { count = 0, total = 0, biggest = 0, specimens = 0, members = 0 }
            teams[key] = t
        end
        t.members = t.members + 1
        t.count = t.count + p.count
        t.total = t.total + p.total
        if p.biggest > t.biggest then
            t.biggest, t.biggestID, t.biggestSpec = p.biggest, p.biggestID, p.biggestSpec
        end
        t.specimens = t.specimens + p.specimens
        if p.firstSpec and (not t.firstSpec or p.firstSpec < t.firstSpec) then
            t.firstSpec, t.firstSpecID = p.firstSpec, p.firstSpecID
        end
    end
    local list = {}
    for key, t in pairs(teams) do
        list[#list + 1] = { name = key, p = t }
    end
    return Sorted(list, m.mode)
end

------------------------------------------------------------------------
-- Hosting / joining
------------------------------------------------------------------------

function MF:DescribeMatch(m)
    local parts = { ("%d-minute %s match at %s"):format(
        math.floor(m.duration / 60), self.MODES[m.mode]:lower(), m.name) }
    if m.fish then parts[#parts + 1] = self:FishName(m.fish) .. " only" end
    if m.team then parts[#parts + 1] = "teams" end
    if m.hcp then parts[#parts + 1] = "skill handicap" end
    return table.concat(parts, ", ")
end

-- The match, as it travels: the same fields whether it's announced to the
-- channel or whispered to one person.
local function MatchFields(self, m)
    local host = Stats(m, self.me)
    return m.id, m.spot, m.mapID, m.x or 0, m.y or 0, m.duration, m.startsAt, m.mode,
        m.fish or 0, (m.team and "t" or "") .. (m.hcp and "h" or ""),
        host.team or "", host.rank, m.name, self.cdb.profile.xp or 0
end

-- Whispered to this many of the others in a match, at most. A match bigger
-- than that wants a raid, where the group carries it.
local WHISPER_PLAYERS = 8

function MF:SendMatch(m, kind, ...)
    if m.guild then
        if IsInGuild() and GetGuildInfo("player") == m.guild then
            self:SendGuild("GMATCH1", m.guild, kind, ...)
        end
        return
    end
    self:Send(kind, ...)
    -- On Forever the channel carries no addon messages, so outside a party
    -- "the channel and the group" reached nobody: two anglers in a match
    -- each saw only their own catches. Everyone we know is in this match is
    -- whispered as well. Anyone also in our group gets it twice, and the
    -- handlers already ignore a catch, score or join they have counted.
    -- The host's announcement repeats every few seconds for anyone nearby
    -- and isn't whispered: everyone in the match has it already.
    if kind == "HOST2" then return end
    self:WhisperMatchPlayers(m, kind, ...)
end

-- Everyone else in a match, by whisper (up to WHISPER_PLAYERS). Also how a
-- record set mid-match reaches the anglers standing beside you, who would
-- otherwise only hear of it through a later record swap.
function MF:WhisperMatchPlayers(m, kind, ...)
    if not m or m.guild then return end
    local sent = 0
    for name in pairs(m.players or {}) do
        if sent >= WHISPER_PLAYERS then break end
        if not self:IsMe(name) then
            sent = sent + 1
            self:Whisper(name, kind, ...)
        end
    end
end

function MF:Announce(m)
    self:SendMatch(m, "HOST2", MatchFields(self, m))
    m.lastAnnounce = Now()
end

-- An event's sign-ups who aren't in its match yet, by name, sorted. Kept apart from m.players:
-- a seat there means a whisper slot, a place in the standings and a share of the results.
function MF:AbsentSignups(m)
    local n = m and self.NoticeForMatch and self:NoticeForMatch(m.id)
    local out = {}
    if not n or not n.signups then return out end
    for name in pairs(n.signups) do
        local seated = false
        for player in pairs(m.players) do
            if self:SameAngler(player, name) then seated = true break end
        end
        if not seated then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

-- The announcement only travels the channel and your group, and on Forever the channel carries
-- nothing, so a sign-up fishing elsewhere never heard their event start. The host whispers it
-- to each sign-up still missing, once a minute, until they're in or it's over.
local CALL_SIGNUPS_EVERY = 60

-- One angler, told of a match we host
function MF:SendMatchTo(m, name)
    if not IsBusy(m) or m.guild or not self:IsMe(m.host) or self:IsMe(name) then return end
    self:Whisper(name, "HOST2", MatchFields(self, m))
end
function MF:CallAbsentSignups(m)
    if not IsBusy(m) or m.guild or not self:IsMe(m.host) then return end
    if Now() - (m.lastCall or 0) < CALL_SIGNUPS_EVERY then return end
    m.lastCall = Now()
    local absent = self:AbsentSignups(m)
    if #absent == 0 then return end
    -- A long list takes turns, WHISPER_PLAYERS at a time
    local from = (m.callFrom or 0) % #absent
    for i = 1, math.min(WHISPER_PLAYERS, #absent) do
        local name = absent[(from + i - 1) % #absent + 1]
        self:SendMatchTo(m, name)
    end
    m.callFrom = from + WHISPER_PLAYERS
end

------------------------------------------------------------------------
-- Inviting by name
--
-- An announced match only reaches the people fishing the same zone. An
-- invite is aimed at one angler and finds them wherever they are, so it's
-- held to what you'd accept from a stranger: only a host can send one, only
-- one an hour from the same host, and by default only from people you know.
------------------------------------------------------------------------

local INVITE_COOLDOWN = 60 -- seconds before we'll take another from one host
local lastInvite = {}      -- angler key -> GetTime() they last invited us

-- The guild roster is empty until something asks the server for it, and we
-- need it to tell a guildmate's invite from a stranger's.
MF:On("TFL_LOGIN", function()
    local roster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
    if IsInGuild() and roster then pcall(roster) end
end)

function MF:InviteToMatch(who)
    local m = self.current
    if not IsBusy(m) or not self:IsMe(m.host) then
        self:Print("You're not hosting a match. Start one with /tfl host.")
        return
    end
    who = strtrim(who or "")
    if who == "" then who = self:TargetPlayerName() or "" end
    if who == "" then
        self:Print("Who? Use /tfl invite <name>, or target them first.")
        return
    end
    if self:IsMe(who) then return end
    if m.guild then
        self:Print("Guild events announce inside the guild; use the event's sign-up or Join action.")
        return
    end

    self:Whisper(who, "INV", MatchFields(self, m))
    self:Print(("Invited %s to your match."):format(who))
    if not self:HasAddon(who) then
        self:Print("|cff9d9d9dNo recent direct contact from this angler yet; that does not tell us whether they have the addon.|r")
    end
end

-- A fish by item ID or part of its name ("oily" -> Oily Blackmouth).
function MF:FindFish(words)
    local id = tonumber(words)
    if id then return id end
    for fid, f in pairs(self.FISH) do
        if f.name:lower():find(words:lower(), 1, true) then return fid end
    end
end

-- Create a match we host and announce it. Used by /tfl host and by
-- noticeboard events. o: id, spot, name, mapID, x, y, duration (seconds),
-- startsAt, mode, fish, flags.
function MF:StartHostedMatch(o)
    self:StopSession(true)
    self:RememberSpotName(o.spot, o.name, true)
    local m = NewMatch(o.id, self.me, o.spot, o.name, o.mapID, o.x, o.y, o.duration,
        o.startsAt, o.mode, o.fish, o.flags)
    self.matches[m.id] = m
    m.guild = o.guild
    self.current = m
    local p = Stats(m, self.me)
    p.team, p.rank = self:MyTeam(), self:MyRank()
    self:Announce(m)
    self:Fire("TFL_MATCH_ANNOUNCED", m)
    self:Print(("Hosting a %s. Starts in %s."):format(self:DescribeMatch(m),
        self:FormatClock(m.startsAt - Now())))
    self:ShowBoard(true)
    if self.OpenMatchEvent then self:OpenMatchEvent(m) end
    return m
end

-- /tfl host [minutes|sprint] [mode] [team] [hcp] [fish name words...]
function MF:HostMatch(args)
    if IsBusy(self.current) then
        self:Print("You're already in a match. /tfl leave first.")
        return
    end
    local minutes, mode, team, hcp, words = 15, "weight", false, false, {}
    args = args or {}
    -- "in 5" holds the start back, so anyone you invite has time to travel.
    local delay = 0
    for i, arg in ipairs(args) do
        if arg == "in" and tonumber(args[i + 1]) then
            delay = math.max(0, math.min(60, math.floor(tonumber(args[i + 1])))) * 60
            args[i], args[i + 1] = "", ""
            break
        end
    end
    for _, arg in ipairs(args) do
        if tonumber(arg) and #words == 0 and tonumber(arg) < 1000 then
            minutes = tonumber(arg)
        elseif arg == "sprint" then
            minutes = SPRINT_MINUTES
        elseif self.MODES[arg] then
            mode = arg
        elseif arg == "team" or arg == "teams" then
            team = true
        elseif arg == "hcp" or arg == "handicap" then
            hcp = true
        elseif arg ~= "" then
            words[#words + 1] = arg
        end
    end
    local fish
    if #words > 0 then
        fish = self:FindFish(table.concat(words, " "))
        if not fish then
            self:Print("Unknown fish: " .. table.concat(words, " "))
            return
        end
    end
    minutes = math.max(1, math.min(120, math.floor(minutes)))

    local spot = self:CurrentSpot()
    self:StartHostedMatch({
        id = self.me .. ":" .. Now(), spot = spot.key, name = spot.name, mapID = spot.mapID,
        x = spot.x, y = spot.y, duration = minutes * 60,
        startsAt = Now() + math.max(LOBBY_SECONDS, delay),
        mode = mode, fish = fish, flags = (team and "t" or "") .. (hcp and "h" or ""),
    })
end

function MF:JoinMatch(hostArg, id)
    local m
    if id then
        m = self.matches[id]
    elseif hostArg then
        for _, cand in pairs(self.matches) do
            if self:ShortName(cand.host):lower() == hostArg and Now() < cand.endsAt
                and not cand.cancelled then
                m = cand
            end
        end
    else
        m = self.matches[self.lastAnnounced]
    end

    if not m or m.cancelled or Now() >= m.endsAt then
        self:Print("No open match found. Try /tfl list.")
        return
    end
    if m.guild and (not IsInGuild() or GetGuildInfo("player") ~= m.guild) then return end
    if self.current == m then
        self:Print("You're already in that match.")
        return
    end
    if IsBusy(self.current) then
        self:Print("You're already in a match. /tfl leave first.")
        return
    end
    if self:RefuseOutdated("matches") then return end

    self:StopSession(true)
    self.current = m
    local p = Stats(m, self.me)
    p.team, p.rank = self:MyTeam(), self:MyRank()
    -- Whispered to the host too (SendMatch), so joining works outside a
    -- party, whether we were invited or saw the match announced.
    self:SendMatch(m, "JOIN", m.id, p.team, p.rank, self.cdb.profile.xp or 0)
    self:Print(("Joined %s's %s. Only catches at %s count!"):format(
        self:ShortName(m.host), self:DescribeMatch(m), m.name))
    self:ShowBoard(true)
    if self.OpenMatchEvent then self:OpenMatchEvent(m) end
end

function MF:LeaveMatch()
    local m = self.current
    if not m then
        self:Print("You're not in a match.")
        return
    end
    if self:IsMe(m.host) and IsBusy(m) then
        self:CancelMatch()
        return
    end
    if IsBusy(m) then self:SendMatch(m, "LEAVE", m.id) end
    self.current = nil
    self:Print("Left the match.")
end

function MF:CancelMatch()
    local m = self.current
    if not m or not self:IsMe(m.host) or not IsBusy(m) then
        self:Print("You aren't hosting a running match.")
        return
    end
    m.cancelled = true
    self:SendMatch(m, "CANCEL", m.id)
    self.current = nil
    self:Print("Match cancelled.")
end

function MF:ListMatches()
    local any = false
    for _, m in pairs(self.matches) do
        if not m.cancelled and Now() < m.endsAt then
            any = true
            local n = 0
            for _ in pairs(m.players) do n = n + 1 end
            print(("  %s: %s - ends in %dm - %d players"):format(
                self:ShortName(m.host), self:DescribeMatch(m),
                math.ceil((m.endsAt - Now()) / 60), n))
        end
    end
    if not any then self:Print("No match announcements received through your available sync routes.") end
end

------------------------------------------------------------------------
-- Catches
------------------------------------------------------------------------

local function ApplyCatch(p, seq, w, spec, t, itemID)
    p.seq = seq
    p.count = p.count + 1
    p.total = p.total + w
    -- The first of two equal fish keeps the place, as it does in the standings.
    if w > p.biggest then
        p.biggest, p.biggestID, p.biggestSpec = w, itemID, spec or nil
    end
    if itemID then
        p.kinds = p.kinds or {}
        p.kinds[itemID] = (p.kinds[itemID] or 0) + 1
    end
    -- Catches landing together are one bobber's worth; count how many.
    if p.lastT > 0 and t - p.lastT < MIN_CATCH_GAP then
        p.burst = (p.burst or 1) + 1
    else
        p.burst = 1
    end
    p.lastT = t
    if spec then
        p.specimens = p.specimens + 1
        if not p.firstSpec then p.firstSpec, p.firstSpecID = t, itemID end
    end
end

-- Same spot key, or close enough to the host's anchor to count as one water.
function MF:AtMatchSpot(m, key)
    if key == m.spot then return true end
    local distance = self:DistanceFrom(m.mapID, m.x, m.y)
    return distance ~= nil and distance <= MAX_DISTANCE
end

function MF:OnCatch(c)
    local m = self.current
    if not IsBusy(m) or c.junk then return end
    local now = Now()
    if now < m.startsAt then
        -- Said once: with a delayed start there could be a lot of these.
        if not m.lobbyWarned then
            m.lobbyWarned = true
            self:Print(("The match starts in %s - catches before then don't count."):format(
                self:FormatClock(m.startsAt - now)))
        end
        return
    end
    if now >= m.endsAt then return end
    if not self:AtMatchSpot(m, c.spot.key) then
        self:Print(("You're not at %s, so that one doesn't count."):format(m.name))
        return
    end
    if m.fish and c.itemID ~= m.fish then
        self:Print(("Only %s counts in this match."):format(self:FishName(m.fish)))
        return
    end

    local weight = m.hcp and self.RoundWeight(c.weight * self:HandicapFactor()) or c.weight
    m.seq = m.seq + 1
    ApplyCatch(Stats(m, self.me), m.seq, weight, c.specimen, now, c.itemID)
    self:SendMatch(m, "CATCH", m.id, m.seq, c.itemID, self:EncodeWeight(weight), now,
        c.specimen and 1 or 0, c.test and 1 or 0)
    if m.mode == "specimen" and c.specimen then
        self:FinishMatch(m)
    end
end

MF:On("TFL_CATCH", MF.OnCatch)

------------------------------------------------------------------------
-- Incoming messages
------------------------------------------------------------------------

local H = MF.handlers

POPUPS["THEFISHINGLOG_INVITE"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, id) MF:JoinMatch(nil, id) end,
    -- No means no more asking (the event's Join match button still works); a timeout doesn't
    OnCancel = function(_, id, reason)
        local m = reason == "clicked" and MF.matches[id]
        if m then m.declined = true end
    end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
}

-- Someone asked you by name, so they're told either way rather than left
-- wondering whether to hold the start.
POPUPS["THEFISHINGLOG_INVITED"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) MF:JoinMatch(nil, data.id) end,
    OnCancel = function(_, data)
        if data then MF:Whisper(data.host, "INVNO", data.id) end
    end,
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
}

-- Take note of a match we've been told about. Returns the match, and whether
-- this is the first we've heard of it.
local function RememberMatch(self, sender, id, spot, mapID, x, y, duration, startsAt, mode, fish,
                             flags, team, rank, name, xp)
    if not id then return nil end
    duration, startsAt = tonumber(duration), tonumber(startsAt)
    if type(id)~="string" or #id>150 or not self:IsSpotKey(spot) then return nil end
    if not duration or duration~=duration or duration<60 or duration>7200 or duration~=math.floor(duration)
        or not startsAt or startsAt~=startsAt or startsAt<1 or startsAt>Now()+7*86400
        or startsAt~=math.floor(startsAt) or Now()>=startsAt+duration then return nil end
    if self.matches[id] then return self.matches[id], false end

    self:RememberSpotName(spot, name)
    local m = NewMatch(id, sender, spot, self:SpotName(spot), mapID, x, y, duration, startsAt,
        mode, fish, flags)
    self.matches[id] = m
    m.guild = self.receivingMatchGuild
    local p = Stats(m, sender)
    p.team = (team and team ~= "") and team or sender
    p.rank = self:RankFromWire(rank, xp)
    self:NoteAngler(sender, { rank = p.rank })
    self.lastAnnounced = id
    self:Fire("TFL_MATCH_ANNOUNCED", m)
    return m, true
end

-- One angler asking you in particular, so it reaches you wherever you are.
function H.INV(self, sender, ...)
    if not self.db.settings.invites then return end
    if not self.db.settings.invitesFromAnyone and not self:IsKnownPlayer(sender) then return end
    if C_FriendList and C_FriendList.IsIgnored and C_FriendList.IsIgnored(self:WhisperName(sender)) then
        return
    end
    local key = self:AnglerKey(sender)
    if GetTime() - (lastInvite[key] or -math.huge) < INVITE_COOLDOWN then return end
    lastInvite[key] = GetTime()

    local m = RememberMatch(self, sender, ...)
    if not m or not IsBusy(m) or Now() >= m.endsAt or self.current == m then return end
    m.direct = true
    if IsBusy(self.current) then
        self:Print(("%s invited you to a match at %s, but you're already in one."):format(
            self:ShortName(sender), m.name))
        return
    end
    local wait = m.startsAt - Now()
    -- DescribeMatch already says where ("... match at Gallows' Corner").
    local text = ("%s invites you to a %s.%s\n\nJoin?"):format(
        self:ShortName(sender), self:DescribeMatch(m),
        wait > 5 and (" It starts in " .. self:FormatClock(wait) .. ".") or "")
    self:Sound(SOUNDKIT.TELL_MESSAGE, "soundMatches")
    StaticPopup_Show("THEFISHINGLOG_INVITED", text, nil, { id = m.id, host = sender })
end

-- Turned down, so the host knows not to hold the start for them.
function H.INVNO(self, sender, id)
    local m = self.matches[id]
    if m and self:IsMe(m.host) then
        self:Print(("%s can't make it."):format(self:ShortName(sender)))
    end
end

local OFFER_AGAIN = 120 -- a missed or closed pop-up comes back this often, unless you said No

function H.HOST2(self, sender, ...)
    local m, isNew = RememberMatch(self, sender, ...)
    if not m then return end
    local id = m.id
    local notice = self:NoticeForMatch(id)
    local signed = notice and self:IsSignedUp(notice)
    -- Our event, already under way: arriving late still gets you in. Asked again every couple
    -- of minutes while you're not in it, as a pop-up is easily missed mid-flight or in combat.
    if not isNew then
        if not signed or self.current == m or IsBusy(self.current) or m.declined
            or not IsBusy(m) or Now() >= m.endsAt
            or GetTime() - (m.offeredAt or -math.huge) < OFFER_AGAIN then return end
        m.offeredAt = GetTime()
        local text = ("Your event |cffffd100%s|r is under way at %s, %s left.\n\nJoin now?"):format(
            notice.title, m.name, self:FormatClock(math.max(0, m.endsAt - Now())))
        StaticPopup_Show("THEFISHINGLOG_INVITE", text, nil, id)
        return
    end
    local p = Stats(m, sender)
    if IsBusy(self.current) then return end

    -- A noticeboard event we signed up for: invite us wherever we are.
    if signed then
        m.offeredAt = GetTime()
        local text = (Now() < m.startsAt and "Your event |cffffd100%s|r is starting at %s.\n\nJoin?"
            or "Your event |cffffd100%s|r is under way at %s.\n\nJoin now?"):format(notice.title, m.name)
        StaticPopup_Show("THEFISHINGLOG_INVITE", text, nil, id)
        return
    end

    -- The channel is realm-wide; only bother people in the same zone.
    if self:MapID() == m.mapID and self.db.settings.invites then
        local text = ("%s (%s) is hosting a %s.\n\nJoin?"):format(
            self:ShortName(sender), self:RankName(p.rank), self:DescribeMatch(m))
        StaticPopup_Show("THEFISHINGLOG_INVITE", text, nil, id)
    end
end

function MF:SendScore(m)
    local p = Stats(m, self.me)
    self:SendMatch(m, "SCORE", m.id, p.seq, p.count, self:EncodeWeight(p.total),
        self:EncodeWeight(p.biggest), p.specimens, p.firstSpec or 0, p.team or "", p.rank,
        self.cdb.profile.xp or 0, p.biggestID or 0, p.biggestSpec and 1 or 0, p.firstSpecID or 0)
end

function H.JOIN(self, sender, id, team, rank, xp)
    local m = self.matches[id]
    if not m then return end
    if not self:AnglerCounts(sender) then
        if self.current == m then self:NoteOutdatedAngler(sender, "this match") end
        return
    end
    local isNew = not m.players[PlayerName(m, sender)]
    local p = Stats(m, sender)
    p.team = (team and team ~= "") and team or sender
    p.rank = self:RankFromWire(rank, xp)
    self:NoteAngler(sender, { rank = p.rank })
    if isNew and self.current == m then
        self:Print(("%s (%s) joined the match."):format(self:ShortName(sender), self:RankName(p.rank)))
        -- Tell the newcomer where we stand; everyone in the match replies.
        self:ReplySoon(0, 3, function() self:SendScore(m) end)
    end
end

function H.LEAVE(self, sender, id)
    local m = self.matches[id]
    if m then
        m.players[PlayerName(m, sender)] = nil
        if m.keys then m.keys[self:AnglerKey(sender)] = nil end
    end
end

function H.CANCEL(self, sender, id)
    local m = self.matches[id]
    if not m or not self:SameAngler(m.host, sender) then return end
    m.cancelled = true
    if self.current == m then
        self.current = nil
        self:Print(self:ShortName(sender) .. " cancelled the match.")
    end
end

-- Returns a reason string if the catch can't be real.
local function Invalid(m, p, itemID, w, t)
    if w > MF:MaxWeight(itemID) * (m.hcp and 1.5 or 1) then return "too heavy" end
    if t < m.startsAt - 5 or t > m.endsAt + 30 then return "outside match time" end
    -- One bobber can hold more than one thing - a fish and a Bloated one,
    -- say - and they arrive in the same second. Up to a bobber's worth is
    -- let through together; only a run of catches faster than casting is not.
    if p.lastT > 0 and t - p.lastT < MIN_CATCH_GAP and (p.burst or 1) >= BOBBER_MAX then
        return "too fast"
    end
    if m.fish and itemID ~= m.fish then return "wrong fish" end
end

function H.CATCH(self, sender, id, seq, itemID, weight, t, spec, test)
    local m = self.matches[id]
    seq, itemID, t = tonumber(seq), tonumber(itemID), tonumber(t)
    if not m or not seq or not itemID or not t then return end
    if not self:AnglerCounts(sender) then return end
    if seq~=seq or seq<1 or seq~=math.floor(seq) or seq>math.ceil(m.duration/MIN_CATCH_GAP)+20
        or itemID~=itemID or itemID<1 or itemID>2147483647 or itemID~=math.floor(itemID)
        or t~=t or t<1 or t==math.huge or t~=math.floor(t) then return end
    local w = self:DecodeWeight(weight)
    if w~=w or w<=0 or w==math.huge then return end
    local key = self:AnglerKey(sender) .. "#" .. seq
    if m.seen[key] then return end -- same message via channel and group
    m.seen[key] = true
    if test == "1" and not self.db.debug then return end

    local p = Stats(m, sender)
    if seq <= p.seq then return end -- already counted in a SCORE snapshot
    local reason = Invalid(m, p, itemID, w, t)
    if reason then
        p.seq = seq
        p.rejected = p.rejected + 1
        self:Debug(("rejected %s's catch: %s"):format(self:ShortName(sender), reason))
        if p.rejected == 3 and self.current == m then
            self:Print(("|cffff5a5aIgnoring suspicious catches from %s.|r"):format(self:ShortName(sender)))
        end
        return
    end
    ApplyCatch(p, seq, w, spec == "1", t, itemID)

    if self.current == m then
        self:WithFishName(itemID, function(name)
            if spec == "1" then
                self:Print(("|cffffd100%s landed a SPECIMEN %s (%s)!|r"):format(
                    self:ShortName(sender), name, MF:Weight(w)))
                self:Sound(SOUNDKIT.RAID_WARNING, "soundMatches")
            else
                self:Print(("%s caught %s (%s)"):format(self:ShortName(sender), name, MF:Weight(w)))
            end
        end)
        if m.mode == "specimen" and spec == "1" and not m.finished then
            self:FinishMatch(m)
        end
    end
end

function H.SCORE(self, sender, id, seq, count, total, biggest, specs, firstSpec, team, rank, xp,
        bigID, bigSpec, specID)
    local m = self.matches[id]
    if not self:AnglerCounts(sender) then return end
    local function Integer(value)
        local n = tonumber(value)
        return n and n == n and n < math.huge and n >= 0 and n == math.floor(n) and n or nil
    end
    seq, count, specs, firstSpec = Integer(seq), Integer(count), Integer(specs), Integer(firstSpec)
    total, biggest = Integer(total), Integer(biggest)
    if not m or not seq or not count or not specs or not firstSpec or not total or not biggest then return end
    local elapsed = math.max(0, math.min(Now() + 30, m.endsAt + 30) - m.startsAt + 5)
    local limit = math.floor(elapsed / MIN_CATCH_GAP) + 1
    local ceiling = self:MaxWeight(m.fish or 999999)
    if not m.fish then
        for item in pairs(self.FISH) do ceiling = math.max(ceiling, self:MaxWeight(item)) end
        for item in pairs(self.TROPHY) do ceiling = math.max(ceiling, self:MaxWeight(item)) end
    end
    ceiling = ceiling * (m.hcp and 1.5 or 1)
    local weight, best = total / 100, biggest / 100
    if seq < count or count > limit or seq > limit or specs > count
        or best > ceiling or best > weight or weight > count * best + 0.01
        or (count == 0 and (weight ~= 0 or best ~= 0 or specs ~= 0))
        or (specs == 0 and firstSpec ~= 0)
        or (specs > 0 and (firstSpec < m.startsAt - 5
            or firstSpec > math.min(Now() + 30, m.endsAt + 30))) then return end
    local p = Stats(m, sender)
    p.team = (team and team ~= "") and team or p.team or sender
    p.rank = self:RankFromWire(rank, xp) or p.rank
    self:NoteAngler(sender, { rank = p.rank })
    if seq <= p.seq then return end
    p.seq = seq
    local hadBest, hadSpec = p.biggest, p.firstSpec
    p.count, p.total, p.biggest, p.specimens = count, weight, best, specs
    p.firstSpec = firstSpec > 0 and firstSpec or nil
    -- The fish behind those numbers, from 1.1.3 on. Without it, keep what the
    -- catches told us only while the numbers still agree with it.
    local function Item(value)
        local n = Integer(value)
        return n and n > 0 and n <= 2147483647 and n or nil
    end
    bigID, specID = Item(bigID), Item(specID)
    if bigID then
        p.biggestID, p.biggestSpec = bigID, tostring(bigSpec) == "1" or nil
    elseif best ~= hadBest then
        p.biggestID, p.biggestSpec = nil, nil
    end
    if specID and p.firstSpec then
        p.firstSpecID = specID
    elseif p.firstSpec ~= hadSpec then
        p.firstSpecID = nil
    end
    if self.current == m and m.mode == "specimen" and p.firstSpec and not m.finished then
        self:FinishMatch(m)
    end
end

------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------

-- Guild-scoped matches use a separate envelope that older clients ignore.
-- Public packets cannot mutate a private match even if its ID is known.
for _, kind in ipairs({ "HOST2", "INV", "JOIN", "LEAVE", "CANCEL", "CATCH", "SCORE" }) do
    local original = H[kind]
    H[kind] = function(self, sender, id, ...)
        local m = self.matches[id]
        if m and m.guild ~= self.receivingMatchGuild then return end
        return original(self, sender, id, ...)
    end
end
function H.GMATCH1(self, sender, guild, kind, id, ...)
    if type(guild) ~= "string" or guild == "" or self.lastRoad ~= "GUILD" or not IsInGuild() or guild ~= GetGuildInfo("player")
        or not ({ HOST2 = true, JOIN = true, LEAVE = true, CANCEL = true, CATCH = true, SCORE = true })[kind]
        or type(id) ~= "string" then return end
    self.receivingMatchGuild = guild
    local ok, err = pcall(H[kind], self, sender, id, ...)
    self.receivingMatchGuild = nil
    if not ok then self:Debug("guild match packet rejected: " .. tostring(err)) end
end

-- How many players (or teams) caught something. A match needs at least two
-- before anyone can win it, so nobody can win XP or titles by fishing alone.
local MIN_CONTENDERS = 2

local function Contenders(list)
    local n = 0
    for _, s in ipairs(list) do
        if s.p.count > 0 then n = n + 1 end
    end
    return n
end

function MF:HasWinner(m)
    local list = m.team and self:TeamStandings(m) or self:Standings(m)
    return Contenders(list) >= MIN_CONTENDERS and list[1].score > list[2].score
end

function MF:FinishMatch(m)
    if m.finished then return end
    m.finished = true
    -- A snapshot carries the winning specimen if a peer missed its catch
    -- packet. Every participant keeps the same stop-on-specimen rule.
    if self.current == m then self:SendScore(m) end
    local standings = self:Standings(m)
    self:Print(("Match at %s is over! (%s)"):format(m.name, self.MODES[m.mode]))
    local contested = Contenders(standings) >= MIN_CONTENDERS
    if not contested then
        self:Print("Fewer than two anglers caught anything, so there's no winner this time.")
        -- Silence from the others usually means their catches never reached
        -- us, not that they caught nothing: say how to fix it.
        local quiet = {}
        for _, s in ipairs(standings) do
            if s.p.count == 0 and not self:IsMe(s.name) then quiet[#quiet + 1] = self:ShortName(s.name) end
        end
        if #quiet > 0 and Stats(m, self.me).count > 0 then
            print(("  |cff858585No catches arrived from %s. If they were fishing, put everyone in a party, "
                .. "or make sure everyone is on the latest version.|r"):format(self.List(quiet)))
        end
    end

    local teamWinner
    if m.team then
        local teams = self:TeamStandings(m)
        teamWinner = Contenders(teams) >= MIN_CONTENDERS and teams[1].score > teams[2].score and teams[1].name or nil
        for i = 1, math.min(3, #teams) do
            print(("  Team %d. %s - %s"):format(teams[i].place, self:TeamLabel(teams[i].name),
                self:FormatScore(teams[i].p, m)))
        end
    end
    local place
    for i, s in ipairs(standings) do
        if self:IsMe(s.name) then place = s.place end
        if i <= 5 then
            local detail = self:StandingDetail(s.p, m, true)
            print(("  %d. %s - %s%s"):format(s.place, self:ShortName(s.name), self:FormatScore(s.p, m),
                detail ~= "" and ("  |cffa0a0a0(" .. detail .. ")|r") or ""))
        end
    end

    local mine = Stats(m, self.me)
    table.insert(self.cdb.history, {
        when = time(), spot = m.spot, sub = m.name, mode = m.mode, host = m.host,
        place = place, players = #standings, total = mine.total, count = mine.count,
    })

    if mine.count > 0 then
        local xp = XP_PLAYED
        if not m.team and self:HasWinner(m) and place == 1 and standings[1].score > 0 then
            xp = xp + XP_WON
        end
        if teamWinner and teamWinner == mine.team then
            xp = xp + XP_TEAM_WON
        end
        self:AddXP(xp)
    end
    local winner = not m.team and self:HasWinner(m) and standings[1].score > 0 and standings[1] or nil
    -- Biggest fish and first specimen are won by one fish: name it.
    local winningFish = winner and (m.mode == "biggest" or m.mode == "specimen")
        and self:StandingDetail(winner.p, m, true) or ""
    local result = winner and (self:ShortName(winner.name) .. " - " .. self:FormatScore(winner.p, m)
        .. (winningFish ~= "" and (" (" .. winningFish .. ")") or ""))
        or (contested and "Draw - equal scores" or "No winner")
    if m.team then
        local teams = self:TeamStandings(m)
        result = teamWinner and (self:TeamLabel(teamWinner) .. " - " .. self:FormatScore(teams[1].p, m))
            or (Contenders(teams) >= MIN_CONTENDERS and "Draw - equal team scores" or "No winner")
    end
    self:Toast("Interface\\Icons\\Trade_Fishing", "MATCH OVER", result, m.name,
        1, 0.82, 0, SOUNDKIT.RAID_WARNING)
    self:Fire("TFL_MATCH_FINISHED", m, standings)
    self:RefreshJournal()
    self:UpdateBoard()
end

MF:OnTick(function(self)
    local m = self.current
    if not IsBusy(m) then return end
    local now = Now()
    if now >= m.endsAt then
        self:FinishMatch(m)
    elseif self:IsMe(m.host) and now - (m.lastAnnounce or 0) >= ANNOUNCE_EVERY then
        self:Announce(m)
        self:CallAbsentSignups(m)
    end
end)

-- The channel is realm-wide, so we hear about every match on the realm.
-- Forget ones that ended a while ago (except the one on our board).
local sincePrune = 0
MF:OnTick(function(self)
    sincePrune = sincePrune + 1
    if sincePrune < PRUNE_EVERY then return end
    sincePrune = 0
    local cutoff = Now() - FORGET_AFTER
    for id, m in pairs(self.matches) do
        if m ~= self.current and m.endsAt < cutoff then
            self.matches[id] = nil
        end
    end
end)

------------------------------------------------------------------------
-- Sharing to chat
------------------------------------------------------------------------

local SHARE_TARGETS = { party = "PARTY", raid = "RAID", guild = "GUILD", say = "SAY", yell = "YELL" }

function MF:Share(where)
    local dist = SHARE_TARGETS[where or ""]
        or (self.current and self.current.guild and "GUILD")
        or (IsInRaid() and "RAID") or (IsInGroup() and "PARTY") or "SAY"
    local msg
    local m = self.current
    if m then
        local parts = {}
        for i, s in ipairs(self:Standings(m)) do
            if i > 5 then break end
            parts[#parts + 1] = ("%d. %s %s"):format(s.place or i, self:ShortName(s.name),
                self:FormatScore(s.p, m):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        end
        msg = ("[The Fishing Log] %s @ %s%s: %s"):format(self.MODES[m.mode], m.name,
            m.finished and "" or " (live)", table.concat(parts, ", "))
    elseif self.session then
        msg = "[The Fishing Log] " .. self:SessionSummary(self.session)
    else
        self:Print("Nothing to share yet.")
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(msg:sub(1, 255), dist)
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

MF:Command("share", "Solo", "/tfl share [party|raid|guild|say] - post your log or match result",
    function(self, args) self:Share(args[1]) end)
MF:Command("host", "Matches",
    "/tfl host [minutes|sprint] [weight|biggest|count|specimen] [team] [hcp] [in N] [fish name]",
    MF.HostMatch)
MF:Command({}, "Matches", "   e.g. /tfl host 10 biggest team   or   /tfl host sprint in 5")
MF:Command("invite", "Matches", "/tfl invite <name> - ask an angler to your match (or your target)",
    function(self, args, raw) self:InviteToMatch(raw) end)
MF:Command("join", "Matches", "/tfl join [host] - join an announced match",
    function(self, args, raw) self:JoinMatch(raw and raw~="" and raw:lower() or nil) end)
MF:Command("leave", "Matches", "/tfl leave - leave your match", MF.LeaveMatch)
MF:Command("cancel", "Matches", "/tfl cancel - cancel the match you're hosting", MF.CancelMatch)
MF:Command("list", "Matches", "/tfl list - matches announced nearby", MF.ListMatches)
