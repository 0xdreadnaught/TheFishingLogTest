-- Census: who else on this realm and faction is running the addon right now.
-- Addons can't reach the internet, so this only ever sees players who are
-- online, on your realm, in your faction, and have the addon.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

local COLLECT_TIME = 8 -- seconds to wait for replies

MF.census = { at = 0, players = {} }

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (get and get(MF.ADDON, "Version")) or "?"
end
MF.Version = Version
-- Test build: the build number goes out as the last field of WHO and HERE, so a tester on an
-- older build can be told there is a newer one (TestBuild.lua, NoteBuild). Appended at the
-- end, which is the one safe change to these formats: a client that doesn't know the field
-- reads the ones before it and ignores the rest. "" when the toc has no X-Build.
local function Build()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local build = get and get(MF.ADDON, "X-Build")
    return type(build) == "string" and build:match("^%d+$") or ""
end
MF.BuildNumber = Build
-- Test build: after the build number, the finder channel the sender is in (Comm.lua,
-- "A locked channel"), so copies kept out of the usual one can find where the others went.
local function Finder() return MF.FinderChannelForWire and MF:FinderChannelForWire() or "" end
-- And after that, which of the addon's channel names refused the sender lately.
local function Refused() return MF.RefusedChannelsForWire and MF:RefusedChannelsForWire() or "" end
-- The version with the test build number from the toc (X-Build), for display.
function MF.VersionLabel()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local build = get and get(MF.ADDON, "X-Build")
    return build and build ~= "" and (Version() .. " build " .. build) or Version()
end

local RECENT_CONTACT = 600
local censusRequestedAt, censusPrintSerial = -math.huge, 0
function MF:RecentCensusPlayers()
    local now=GetTime()
    for key,p in pairs(self.census.players) do
        if not p.confirmedAt or now<p.confirmedAt or now-p.confirmedAt>RECENT_CONTACT then
            self.census.players[key]=nil
        end
    end
    return self.census.players
end
function MF:NoteCensusReply(sender,version,mapID)
    if type(sender)~="string" or sender=="" or self:IsMe(sender) then return end
    if self.MetPeer then self:MetPeer(sender) end -- test build: a copy with no channel asks where everyone is
    local key=self:AnglerKey(sender)
    if key=="" then return end
    local players=self:RecentCensusPlayers()
    if not players[key] and self.Count(players)>=500 then
        local oldest
        for k,p in pairs(players) do if not oldest or p.confirmedAt<players[oldest].confirmedAt then oldest=k end end
        if oldest then players[oldest]=nil end
    end
    local known=self.db.anglersSeen[key]
    local old=players[key]
    local validVersion=type(version)=="string" and #version<=32 and version:match("^%d+%.%d+%.%d+") and version or nil
    self:NoteSeen(sender,validVersion)
    mapID=tonumber(mapID)
    if not mapID or mapID<1 or mapID>3000 or mapID~=math.floor(mapID) then mapID=nil end
    players[key]={name=sender,version=validVersion or (old and old.version) or (known and known.version) or "?",
        mapID=mapID or 0,confirmedAt=GetTime()}
    self:RefreshJournal()
end
function MF:RequestCensus(quiet)
    self:RecentCensusPlayers()
    self.census.at=GetTime()
    local now=GetTime()
    if now-censusRequestedAt>=30 then
        censusRequestedAt=now
        self:SendWide("WHO", Version(), Build(), Finder(), Refused())
        if not self.CUSTOM_CHANNEL_SUPPORTED then
            if not quiet and self.db.settings.channel and GetChannelName(self.CHANNEL)<=0 then self:JoinChannel(true) end
            self:Fire("TFL_ROSTER_SYNC")
            local peers={}
            for _,p in pairs(self:RecentCensusPlayers()) do peers[#peers+1]=p end
            table.sort(peers,function(a,b) return a.confirmedAt>b.confirmedAt end)
            for i=1,math.min(2,#peers) do self:Whisper(peers[i].name,"WHO",Version(),Build(),Finder(),Refused()) end
        end
    end
    if not quiet then
        censusPrintSerial=censusPrintSerial+1
        local serial=censusPrintSerial
        self:Print("Checking available sync routes. Showing confirmed contacts from the last 10 minutes, not a complete online list.")
        local delay=self.CUSTOM_CHANNEL_SUPPORTED and COLLECT_TIME or 45
        C_Timer.After(delay,function() if serial==censusPrintSerial then self:PrintCensus() end end)
    end
end

MF:On("TFL_SYNC", function(self) self:RequestCensus(true) end)

-- Everyone answers, staggered so a busy realm doesn't flood the channel.
-- Whose guild is whose
--
-- A client can read its own guild and nobody else's: GetGuildRosterInfo is
-- your roster, so the addon can tell a guildmate from a stranger and has no
-- idea what guild the stranger is in. The only way anyone learns is if
-- everybody says - so this is said, once, in the message we already send to
-- announce ourselves.
--
-- Appended to the end of HERE, which is the one safe change to make to a
-- format with no version byte: clients that don't know about the field read
-- the ones before it and ignore what's left.
function MF:MyGuild()
    local name = GetGuildInfo and GetGuildInfo("player")
    if type(name) ~= "string" then return "" end
    return (name:gsub("[,;~|]", " "))
end

function MF:NoteGuild(name, guild)
    if not name or guild == nil or not self.db then return end
    local a = self.db.anglersSeen[self:AnglerKey(name)]
    -- Only from the horse's mouth, and "" is an answer: it means no guild,
    -- which is different from never having been told.
    if a then a.guild = guild end
end

function MF:GuildOf(name)
    local a = name and self.db.anglersSeen[self:AnglerKey(name)]
    return a and a.guild or nil
end

-- Since 1.0.8 the asker says its version too, so an angler who has just
-- updated is known to have updated before their first new record arrives.
function MF.handlers.WHO(self, sender, version, build, finder, refused)
    if self.NoteBuild then self:NoteBuild(sender, build) end
    if self.NotePeerRefusals then self:NotePeerRefusals(sender, refused, finder) end
    if self.NotePeerChannel then self:NotePeerChannel(sender, finder) end
    if self.ValidVersion(version) then self:NoteSeen(sender, version) end
    local whisper=self.lastRoad=="WHISPER"
    self:ReplyOnce("who:" .. self:AnglerKey(sender), 0, 6, function()
        if whisper then
            self:Whisper(sender,"HERE",Version(),self:MyRank(),self:MapID(),self:MyFaction(),
                self.cdb.profile.xp or 0,self:MyGuild(),self:TotalFishCaught(),self:CountingFloor(),Build(),Finder(),Refused())
        else
            self:SendWide("HERE", Version(), self:MyRank(), self:MapID(), self:MyFaction(),
                self.cdb.profile.xp or 0, self:MyGuild(), self:TotalFishCaught(), self:CountingFloor(), Build(), Finder(), Refused())
        end
    end)
end

function MF:TotalFishCaught()
    local total = 0
    for _, entry in pairs(self.cdb.profile.journal or {}) do total = total + (entry.c or 0) end
    return total
end

function MF:NoteProgression(sender, xp, fish)
    xp = tonumber(xp)
    if not xp or xp ~= xp or xp < 0 or xp > 1000000000 or xp ~= math.floor(xp) then return end
    self:NoteSeen(sender)
    local seen = self.db.anglersSeen[self:AnglerKey(sender)]
    if seen then
        seen.tflXP = xp
        seen.tflXPAt = GetServerTime()
        fish = tonumber(fish)
        if fish and fish == fish and fish >= 0 and fish <= 1000000000 and fish == math.floor(fish) then
            seen.tflFish = fish
            seen.tflFishAt = GetServerTime()
        end
    end
    self:NoteAngler(sender, { rank = self:RankFor(xp) })
    self:RefreshJournal()
end

function MF.handlers.HERE(self, sender, version, rank, mapID, faction, xp, guild, fish, floor, build, finder, refused)
    if self.NoteBuild then self:NoteBuild(sender, build) end
    if self.NotePeerRefusals then self:NotePeerRefusals(sender, refused, finder) end
    if self.NotePeerChannel then self:NotePeerChannel(sender, finder) end
    -- The oldest version they still count, appended in 1.0.8.
    self:NoteCountingFloor(sender, version, floor)
    self:NoteProgression(sender, xp, fish)
    rank = self:RankFromWire(rank, xp)
    self:NoteAngler(sender, { rank = rank })
    self:NoteSeen(sender, version)
    self:NoteFaction(sender, faction)
    self:NoteGuild(sender, guild)
    self:NoteCensusReply(sender,version,mapID)
    self:WarnIfOutdated()
end

------------------------------------------------------------------------
-- The register
--
-- A census only sees who's online this minute, and the standings only count
-- anglers who hold a record somewhere. Neither answers "how many people are
-- actually running this?". So every angler we hear anything at all from is
-- written down, with when we last heard from them and which version they
-- were on.
------------------------------------------------------------------------

local MAX_SEEN = 400 -- oldest are dropped past this; names are cheap, not free

local function Prune(seen)
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    while count > MAX_SEEN do
        local oldestKey, oldest
        for key, a in pairs(seen) do
            if not oldest or (a.at or 0) < oldest then oldestKey, oldest = key, a.at or 0 end
        end
        if not oldestKey then return end
        seen[oldestKey] = nil
        count = count - 1
    end
end

-- Called for every addon message that reaches us, whatever it was about.
function MF:NoteSeen(name, version)
    if not name or not self.db then return end
    local key = self:AnglerKey(name)
    if key == "" or self:IsMe(name) then return end
    local seen = self.db.anglersSeen
    local a = seen[key]
    if not a then
        a = {}
        seen[key] = a
        Prune(seen)
    end
    a.name = self:ShortName(name)
    a.at = time()
    if version and version ~= "?" then
        a.version = version
        a.versionAt = time() -- when we heard it, so a stale one isn't held against them
        self:VouchVersion(key, version)
    end
end

------------------------------------------------------------------------
-- "There's a newer version"
--
-- An addon can't ask CurseForge whether it's out of date. The only thing
-- on the realm that knows a release exists is somebody already running it,
-- and every message they send has carried their version number all along.
-- So this isn't new plumbing - it's reading what was already arriving.
--
-- Two anglers, not one. The version is the one field a sender writes
-- whatever they like into, and a single joker claiming 9.9.9 would put a
-- permanent "update available" on every client on the realm. Needing two
-- independent anglers makes that a conspiracy rather than a prank, and two
-- is also about what a real release reaches within a minute of a sync.
--
-- Said once a session, and late: a nag that repeats is one people learn to
-- read past, and this one should still be read in a fortnight.
------------------------------------------------------------------------

local VOUCHERS = 2       -- anglers who must be on it before we believe it
local NOTICE_DELAY = 30  -- seconds, so it lands after the news panel has gone

-- version -> set of angler keys heard running it. On MF rather than hidden
-- in a local so the census and the tests can both see what it's going on.
MF.versionsSeen = {}

local told, scheduled = false, false

function MF:VouchVersion(key, version)
    if not key or not version or not self:VersionNewer(version, Version()) then return end
    local who = self.versionsSeen[version]
    if not who then
        who = {}
        self.versionsSeen[version] = who
    end
    who[key] = true
    if told or scheduled or self.Count(who) < VOUCHERS then return end
    scheduled = true
    C_Timer.After(NOTICE_DELAY, function() self:AnnounceUpdate() end)
end

-- The newest version enough anglers are running, and how many that is.
-- Newest rather than first past the post: on the evening of a release both
-- the version you missed and the one after it can be out there.
function MF:NewerVersionSeen()
    local best, count
    for version, who in pairs(self.versionsSeen) do
        local n = self.Count(who)
        if n >= VOUCHERS and (not best or self:VersionNewer(version, best)) then
            best, count = version, n
        end
    end
    return best, count
end

function MF:AnnounceUpdate()
    if told then return end
    local version, n = self:NewerVersionSeen()
    if not version then return end
    told = true
    self:Print(("|cffffd100Version %s is available|r (you have %s). Update on CurseForge.")
        :format(version, Version()))
    -- Where it heard that, because there's no server to have heard it from
    -- and "how does it even know" is the first thing anyone sensible asks.
    print(("  |cff858585%d anglers on this realm are already running it.|r"):format(n))
end

-- Everyone we've ever heard from, most recent first.
function MF:AnglersSeen()
    local list = {}
    for key, a in pairs(self.db.anglersSeen) do
        list[#list + 1] = { key = key, name = a.name or key, at = a.at or 0, version = a.version }
    end
    table.sort(list, function(x, y) return x.at > y.at end)
    return list
end

function MF:AnglersSeenCount()
    return self.Count(self.db.anglersSeen)
end

MF:Command("anglers", "Other", "/tfl anglers - everyone the addon has ever heard from",
    function(self)
        local list = self:AnglersSeen()
        if #list == 0 then
            self:Print("You haven't heard from another angler yet.")
            return
        end
        local mine, old = self.Version(), 0
        for _, a in ipairs(list) do
            if a.version and a.version ~= mine then old = old + 1 end
        end
        self:Print(("Heard from %d angler%s:"):format(#list, #list == 1 and "" or "s"))
        local now = time()
        for i = 1, math.min(20, #list) do
            local a = list[i]
            local days = math.floor((now - a.at) / 86400)
            print(("  %s - %s%s"):format(a.name,
                days == 0 and "today" or (days == 1 and "yesterday" or days .. " days ago"),
                a.version and ("   v" .. a.version) or ""))
        end
        if #list > 20 then print(("  ...and %d more."):format(#list - 20)) end
        if old > 0 then
            print(("  |cffff8000%d on a different version to yours.|r"):format(old))
        end
    end)

-- Has this angler answered a census? Only ever a hint: they may have logged
-- in since, or simply not been listening when we last asked.
function MF:HasAddon(name)
    return name ~= nil and self:RecentCensusPlayers()[self:AnglerKey(name)] ~= nil
end

function MF:CensusCount()
    return self.Count(self:RecentCensusPlayers())
end

function MF:PrintCensus()
    local players = self:RecentCensusPlayers()
    local count, versions, zones = 0, {}, {}
    local myVersion = Version()
    local outdated = 0
    for _, p in pairs(players) do
        count = count + 1
        versions[p.version] = (versions[p.version] or 0) + 1
        if p.version ~= "?" and p.version ~= myVersion then outdated = outdated + 1 end
        local info = p.mapID > 0 and C_Map.GetMapInfo(p.mapID)
        local zone = info and info.name or "somewhere"
        zones[zone] = (zones[zone] or 0) + 1
    end

    if count == 0 then
        self:Print("No confirmed angler contacts in the last 10 minutes. This does not mean nobody is online.")
        if not self.CUSTOM_CHANNEL_SUPPORTED then
            self:Print(self:QuietSyncSummary())
        end
        return
    end

    self:Print(("%d other angler%s contacted your client in the last 10 minutes:"):format(count, count == 1 and "" or "s"))
    for version, n in pairs(versions) do
        if version=="?" then print(("  Version not reported: %d"):format(n))
        else print(("  v%s: %d%s"):format(version, n, version == myVersion and " (same as you)" or "")) end
    end
    local names={}
    for _,p in pairs(players) do names[#names+1]=p end
    table.sort(names,function(a,b) return a.confirmedAt>b.confirmedAt end)
    for i=1,math.min(20,#names) do
        local p=names[i]
        print(("  %s - %ds ago"):format(self:ShortName(p.name),math.floor(GetTime()-p.confirmedAt)))
    end
    local busiest, most = nil, 0
    for zone, n in pairs(zones) do
        if zone ~= "somewhere" and n > most then busiest, most = zone, n end
    end
    if busiest then
        print(("  Most confirmed locations in: %s (%d)"):format(busiest, most))
    end
    if outdated > 0 then
        print(("  |cffff8000%d on a different version - they may not see your matches or records.|r")
            :format(outdated))
    end
end

MF:Command({ "census", "who" }, "Other", "/tfl census - check recent confirmed angler contacts",
    function(self) self:RequestCensus() end)

function MF:ResetCensus()
    self.census,self.versionsSeen={at=0,players={}},{ }
    censusRequestedAt,censusPrintSerial=-math.huge,censusPrintSerial+1
    told,scheduled=false,false
end
