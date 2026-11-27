-- Report: two commands that make it easy to send useful information back.
--
--   /tfl report  catches the fish data doesn't cover yet - new zones, new fish
--                - ready to paste into Discord
--   /tfl diag    the state of the addon, for bug reports
local _, MF = ...
local function print(...) MF:PrintChat(...) end

-- Read-only live-client evidence, independent of any particular map build.
function MF:ClientDiagnosticText()
    local out={"TFL client diagnostics " .. self.VersionLabel()}
    local function Probe(label,fn)
        local ok,value=pcall(fn)
        if ok and self:IsSecret(value) then value="restricted" end
        out[#out+1]=label .. ": " .. (ok and tostring(value) or ("ERROR " .. tostring(value):sub(1,180)))
    end
    Probe("Client",function()
        local version,build,stamp,interface=GetBuildInfo()
        return ("%s build=%s interface=%s date=%s"):format(tostring(version),tostring(build),tostring(interface),tostring(stamp))
    end)
    Probe("Clock",function() return ("server=%s uptime=%.2f"):format(tostring(GetServerTime()),GetTime()) end)
    if self.WorldProbeLines then
        local ok,lines=pcall(self.WorldProbeLines,self)
        if ok then for _,line in ipairs(lines) do out[#out+1]=line end
        else out[#out+1]="World probe: ERROR " .. tostring(lines):sub(1,180) end
    end
    Probe("Raw player map",function() return C_Map.GetBestMapForUnit("player") end)
    Probe("Raw zone",function() return GetRealZoneText() end)
    Probe("Raw subzone",function() return GetSubZoneText() end)
    Probe("Displayed map",function() return WorldMapFrame:GetMapID() end)
    Probe("Frenzy renderer",function() return self:MapPinDiagnostics() end)
    Probe("Frenzy catalogue",function()
        local s=self:CurrentSpot()
        local w,h=self:FrenzyMapSize(s.mapID)
        local water=self:ResolveFrenzyLocation()
        return ("v%d; locations=%d; map-yards=%s,%s; current=%s; discovery-only=%d"):format(
            self.FRENZY_CATALOGUE_VERSION,#self.FRENZY_LOCATIONS,tostring(w),tostring(h),water and water.id or "none",#self:FrenzyDiscoveryStore())
    end)
    Probe("Pool renderer",function() return self:PoolPinDiagnostics() end)
    Probe("Settings",function()
        local s=self.db.settings
        return ("frenzy=%s pools-world=%s pools-mini=%s motion-reduced=%s"):format(
            tostring(s.mapFrenzy),tostring(s.poolWorldMap),tostring(s.poolMinimap),tostring(s.reducedMotion))
    end)
    Probe("Current spot",function()
        local s=self:CurrentSpot()
        local active,seconds,window=self:FrenzyPresentationState(s.key)
        return ("%s | %s | map=%s | x=%s y=%s | active=%s seconds=%s window=%s hash=%s"):format(
            tostring(s.key),tostring(s.name),tostring(s.mapID),tostring(s.x),tostring(s.y),
            tostring(active),tostring(seconds),tostring(window),tostring(self:Hash(s.key)))
    end)
    Probe("Frenzy display",function()
        local key=self:CurrentSpot().key
        local active,seconds=self:FrenzyPresentationState(key)
        return ("known-water=%s location-usable=%s locally-observed=%s displayed-active=%s seconds=%s"):format(
            tostring(self:KnownFishingWater(key)),tostring(self:FrenzyLocationUsable(key)),
            tostring(self:SpotLocallyObserved(key)),tostring(active),tostring(seconds))
    end)
    Probe("Current-map saved data",function()
        local map=self:MapID()
        local all,valid,active,shown=0,0,0,#self:FrenziesOnMap(map)
        for key,w in pairs(self.db.spotWhere) do
            if type(w)=="table" and w.map==map then
                all=all+1
                if self:ValidSpotPosition(key,w.map,w.x,w.y) then valid=valid+1 end
                if self:IsFrenzy(key) then active=active+1 end
            end
        end
        return ("map=%s positions=%d valid=%d active-timers=%d eligible-markers=%d pools=%d"):format(
            tostring(map),all,valid,active,shown,#self:PoolNodes(map))
    end)
    for _,name in ipairs({"AddDataProvider","AcquirePin","GetMapID"}) do
        Probe("WorldMapFrame." .. name,function() return type(WorldMapFrame and WorldMapFrame[name]) end)
    end
    Probe("WorldMapFrame.pinPools",function() return type(WorldMapFrame and WorldMapFrame.pinPools) end)
    for _,name in ipairs({"CreateFromMixins","CreateFramePool","MapCanvasPinMixin","MapCanvasDataProviderMixin"}) do
        Probe(name,function() return type(_G[name]) end)
    end
    out[#out+1]="Read-only snapshot. Capture again at the same location if the frenzy timer or spot name changes unexpectedly."
    return table.concat(out,"\n")
end

MF:Command("clientdiag","Other","/tfl clientdiag - copy map, spot and frenzy client diagnostics",function(self)
    self:ShowDiagnosticText(self:ClientDiagnosticText())
end)

------------------------------------------------------------------------
-- The survey: what bites in waters the fish data doesn't cover yet
--
-- Weights are rolled by the addon, so nobody's scales can say how heavy a
-- Riverglades fish should be - that part is a design choice. What anglers
-- can say is which fish turn up where and how often, and that is what this
-- writes down: every catch in a zone the data says nothing about, and any
-- fish it has never heard of wherever it bites. The share of a zone's
-- catches, whether it came from a pool and the skill it was caught at are
-- what turn "seen once" into a native list someone can trust.
------------------------------------------------------------------------

local SURVEY_ZONES = 40
local SURVEY_WATERS = 20

local function Survey(self)
    self.db.zoneSurvey = self.db.zoneSurvey or {}
    return self.db.zoneSurvey
end

MF:On("TFL_CATCH", function(self, c)
    if c.test or type(c.zone) ~= "string" or c.zone == "" then return end
    local uncovered = not self:ZoneCovered(c.zone)
    local unknown = not c.junk and not self.FISH[c.itemID] and not self.TROPHY[c.itemID]
    if not uncovered and not unknown then return end
    local survey = Survey(self)
    local z = survey[c.zone]
    if not z then
        if self.Count(survey) >= SURVEY_ZONES then return end
        z = { map = c.spot and c.spot.mapID or 0, total = 0, fish = {}, waters = {} }
        survey[c.zone] = z
    end
    -- A zone the data does cover only records the fish it doesn't know, so
    -- its total is not a share of anything and is not reported as one.
    z.covered = not uncovered or nil
    z.total = z.total + 1
    local f = z.fish[c.itemID] or { c = 0, pool = 0 }
    z.fish[c.itemID] = f
    f.c, f.junk = f.c + 1, c.junk or nil
    f.name = f.name or c.name
    if self:PoolCastPending() then f.pool = f.pool + 1 end
    local rank, _, bonus = self:FishingSkill()
    if rank then
        local skill = rank + (bonus or 0)
        f.lo, f.hi = math.min(f.lo or skill, skill), math.max(f.hi or skill, skill)
    end
    local water = c.spot and c.spot.name
    if type(water) == "string" and water ~= "" and (z.waters[water] or self.Count(z.waters) < SURVEY_WATERS) then
        z.waters[water] = (z.waters[water] or 0) + 1
    end
end)

-- The survey as one block of text for pasting, a line per zone and per fish.
function MF:SurveyText()
    local survey = Survey(self)
    local zones = {}
    for zone in pairs(survey) do zones[#zones + 1] = zone end
    for zone in pairs(self.db.newZones) do if not survey[zone] then zones[#zones + 1] = zone end end
    table.sort(zones)
    if #zones == 0 then return nil end
    local out = { ("TFL %s fish survey | %s | %s"):format(self.Version(), (GetRealmName() ~= "" and GetRealmName() or self:RealmName()),
        date("!%Y-%m-%d", GetServerTime())) }
    for _, zone in ipairs(zones) do
        local z = survey[zone]
        if z then
            out[#out + 1] = ("%s (map %d, %s): %d catches"):format(zone, z.map or 0,
                z.covered and "unknown fish only" or "no fish data", z.total)
            local list = {}
            for id, f in pairs(z.fish) do list[#list + 1] = { id = id, f = f } end
            table.sort(list, function(a, b)
                if a.f.c ~= b.f.c then return a.f.c > b.f.c end
                return a.id < b.id
            end)
            for _, e in ipairs(list) do
                local f = e.f
                out[#out + 1] = ("  %s (%d): %d%s%s%s%s"):format(f.name or self:FishName(e.id), e.id, f.c,
                    z.covered and "" or (" (%d%%)"):format(math.floor(f.c / math.max(1, z.total) * 100 + 0.5)),
                    f.pool > 0 and (", %d at pools"):format(f.pool) or "",
                    f.lo and (", skill %d-%d"):format(f.lo, f.hi) or "",
                    f.junk and ", junk" or "")
            end
            local waters = {}
            for name, n in pairs(z.waters) do waters[#waters + 1] = { name = name, n = n } end
            table.sort(waters, function(a, b) return a.n > b.n end)
            local parts = {}
            for i = 1, math.min(8, #waters) do parts[i] = ("%s %d"):format(waters[i].name, waters[i].n) end
            if #parts > 0 then out[#out + 1] = "  Waters: " .. table.concat(parts, ", ") end
        else
            -- Counted before the survey existed: fish and counts, nothing more.
            local parts = {}
            for id, n in pairs(self.db.newZones[zone]) do parts[#parts + 1] = ("%s (%d) x%d"):format(self:FishName(id), id, n) end
            table.sort(parts)
            out[#out + 1] = ("%s (earlier counts): %s"):format(zone, table.concat(parts, ", "))
        end
    end
    return table.concat(out, "\n")
end

-- Records held by things the addon has no list entry for and doesn't believe
-- are fish. Named rather than deleted: the list is what gets acted on, and
-- the only way it grows is somebody sending these in.
local function Suspicious(self)
    local found = {}
    for key, s in pairs(self.db.spots) do
        for id, rec in pairs(s.fish) do
            if self:LooksWrong(id) then
                local e = found[id]
                if not e then
                    e = { id = id, n = 0, w = 0 }
                    found[id] = e
                end
                e.n = e.n + 1
                if rec.w > e.w then e.w, e.where = rec.w, self:SpotName(key) end
            end
        end
    end
    local list = {}
    for _, e in pairs(found) do list[#list + 1] = e end
    table.sort(list, function(a, b) return a.w > b.w end)
    return list
end

function MF:PrintSuspicious()
    local list = Suspicious(self)
    if #list == 0 then return 0 end
    self:Print(("%d thing%s holding records that may not be fish (paste this on the Discord):")
        :format(#list, #list == 1 and " is" or "s are"))
    for _, e in ipairs(list) do
        print(("  %s (%d) - %s at %s, %d record%s"):format(self:FishName(e.id), e.id,
            MF:Weight(e.w), e.where or "?", e.n, e.n == 1 and "" or "s"))
    end
    print("  |cff858585Nothing has been removed. Items are only ruled out once they're on the "
        .. "list, and the list grows from reports like this one.|r")
    return #list
end

-- A report is written to be pasted somewhere else, so every line has to
-- stand on its own. The client only knows an item's name once something has
-- made it look the item up, and these are things nobody has in their bags -
-- so the report came out as eleven lines of "Item 4234 (4234)", which told
-- the person reading it nothing and left them looking up every one by hand.
--
-- Asking costs nothing and the answers arrive within a moment, so the
-- report waits for them rather than going out unreadable.
local function Unnamed(self, id)
    return self:FishName(id):match("^Item %d+$") ~= nil
end

local function AskForNames(self)
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return false end
    local waiting = false
    local function Ask(id)
        if Unnamed(self, id) then
            pcall(C_Item.RequestLoadItemDataByID, id)
            waiting = true
        end
    end
    for _, e in ipairs(Suspicious(self)) do Ask(e.id) end
    for _, caught in pairs(self.db.newZones) do
        for id in pairs(caught) do Ask(id) end
    end
    for _, z in pairs(Survey(self)) do
        for id in pairs(z.fish) do Ask(id) end
    end
    return waiting
end

local function Report(self)
    self:PrintSuspicious()
    local text = self:SurveyText()
    if not text then
        self:Print("Nothing to report - the addon knows every fish and zone you have fished.")
        return
    end
    self:Print("Fish survey ready: copy it from the window and paste it on the Discord.")
    self:ShowCopyText("Fish survey", text)
end

MF:Command("report", "Other", "/tfl report - a copyable survey of fish in zones the addon has no data for",
    function(self)
        if AskForNames(self) then
            self:Print("Asking the client what these are...")
            C_Timer.After(1.5, function() Report(self) end)
            return
        end
        Report(self)
    end)

-- Undocumented: what the client says about one item, for working out why
-- something was weighed - or not weighed - the way it was.
MF:Command("item", "Other", nil, function(self, args)
    local id = tonumber(args[1])
    if not id then
        self:Print("Usage: /tfl item <itemID>")
        return
    end
    local _, itemType, subType, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    self:Print(("item %d - %s"):format(id, self:FishName(id)))
    print(("  type %s / %s   equip \"%s\"   class %s.%s"):format(tostring(itemType),
        tostring(subType), tostring(equipLoc), tostring(classID), tostring(subclassID)))
    print(("  in fish data: %s   trophy: %s   listed as not a fish: %s"):format(
        tostring(self.FISH[id] ~= nil), tostring(self.TROPHY[id] or false),
        tostring(self.NOT_FISH[id] == true)))
end)

-- Runs fn with everything it prints collected instead of sent to chat, and
-- returns the lines as plain text: colours, icons and links taken out, so
-- what is pasted into a bug report reads the way it did on screen.
function MF:CapturePrints(fn, ...)
    local lines, real = {}, self.PrintChat
    self.PrintChat = function(_, ...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        local text = table.concat(parts, " ")
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        text = text:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
        lines[#lines + 1] = text
    end
    local ok, err = pcall(fn, self, ...)
    self.PrintChat = real
    if not ok then lines[#lines + 1] = "error while collecting: " .. tostring(err) end
    return lines
end

local function PrintDiag(self)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = (get and get(self.ADDON, "Version")) or "?"
    local channel = self:ChannelID()
    local spot, name, mapID = self:SpotInfo()

    local newer, vouchers = self:NewerVersionSeen()
    self:Print(("diagnostics - v%s, interface %s%s"):format(version, select(4, GetBuildInfo()),
        newer and (" |cffffd100(v%s is out, %d anglers on it)|r"):format(newer, vouchers) or ""))
    print(("  save macros: %s"):format(self.db.settings.macroSave and "on" or "off"))
    print(("  channel broadcast: %s   guild: %s   group: %s"):format(
        channel and ("joined (" .. channel .. ")") or (self.CUSTOM_CHANNEL_SUPPORTED and "not joined" or "unsupported by client"),
        IsInGuild() and "yes" or "no",
        IsInRaid() and "raid" or (IsInGroup() and "party" or "none")))
    print(("  realm: %s   you are: %s"):format((self:RealmName() ~= "" and self:RealmName() or "?"), self.me or "?"))
    print(("  anglers: %d confirmed contacts in last 10m, %d heard from ever"):format(
        self:CensusCount(), self:AnglersSeenCount()))

    -- The faction tally answers whether anything reaches us across the line.
    local sides = { A = 0, H = 0 }
    for _, letter in pairs(self.db.factions) do
        sides[letter] = (sides[letter] or 0) + 1
    end
    print(("  factions known: %d alliance, %d horde (you are %s)"):format(
        sides.A, sides.H, self:MyFaction() == "H" and "horde" or "alliance"))

    local roads, total = {}, 0
    for dist, n in pairs(self.heard) do
        roads[#roads + 1] = ("%s %d"):format(dist:lower(), n)
        total = total + n
    end
    table.sort(roads)
    print(("  messages heard this session: %s"):format(
        total > 0 and table.concat(roads, ", ") or "none at all"))
    if not self.CUSTOM_CHANNEL_SUPPORTED then
        local sync = self.syncDiagnostics
        print("  quiet sync, last scan: " .. self:QuietSyncSummary())
        local asked = self:QuietSyncAsked()
        if #asked > 0 then print("    asked: " .. table.concat(asked, ", ")) end
        local r = self.rosterReply
        if r and not r.at then
            print(("    channel list: no reply to the last scan (our channel is number %s)")
                :format(tostring(GetChannelName(self.CHANNEL))))
        elseif r then
            print(("    channel list: %d repl%s, last %ds ago; expected=%s ours=%s; channel=%s index=%s base=%s id=%s")
                :format(r.events, r.events == 1 and "y" or "ies", math.floor(GetTime() - r.at),
                    tostring(r.expected), r.ours, r.channel, r.index, r.base, r.id))
            print("      text: " .. tostring(r.text))
        end
        print(("  whispers sent this session: %d, player not found: %d%s"):format(
            self.whispersSent or 0, self.whispersNotFound or 0,
            self.lastNotFound and (" (last: " .. self.lastNotFound .. ")") or ""))
        print(("  accepted this session: %d record book entries, %d bounty scores, %d pool sightings")
            :format(sync.records, sync.bounties, sync.pools))
    end
    if self.handlerErrors then
        print(("  messages from other clients dropped as unreadable: %d (last: %s)"):format(
            self.handlerErrors, tostring(self.lastHandlerError)))
    end
    print("  transport: " .. self:CommunicationStatus())
    if self.sendRefusals then
        print(("  addon send refusals this session: %d (last: %s)"):format(
            self.sendRefusals, self.lastSendRefusal))
    end
    if channel and total > 0 and not self.heard.CHANNEL then
        print("  |cffff8000Nothing has come over the channel this session.|r")
    end
    print(("  spot: %s (%s) map %s   records synced: %s"):format(
        name, spot, tostring(mapID), tostring(self:RecordsReady(mapID))))
    -- Another fishing addon on the same button is the likeliest cause of
    -- "casting doesn't work", and the one thing a bug report never mentions.
    local rival = self:CastRival()
    local talking = rival and self:FishFryCompat()
    print(("  casts on: %s%s"):format(self:CastBinding() or "nothing",
        rival and ("   " .. (talking and "|cff3ee63e" or "|cffff8000") .. rival
            .. (talking and " is loaded, and we're talking|r" or " is also loaded|r")) or ""))
    -- A key beginning "a" means the client named the area; anything else
    -- means it wouldn't, and the count says whether that is this one water
    -- or the whole lookup. It is the difference between a quirk and every
    -- water on the realm being filed under a grid square.
    print(("  area names the client knows: %d"):format(self.areaNames or 0))
    print(("  skill curve: %d zones known"):format(#self:SkillCurve()))
    print(("  known: %d spots, %d notices, %d anglers, %d journal entries"):format(
        self.Count(self.db.spots), self.Count(self.db.notices), self.Count(self.anglers),
        self.Count(self.cdb.profile.journal)))
    -- Two saved files, and the rank lives in the per-character one. "Saving
    -- works" is read from the account file, so it can say yes while this
    -- character has nothing - which is exactly how somebody ends up back at
    -- the first rank with their realm records intact and no explanation.
    local legacy = self.db.legacy and self.db.legacy.profile
    print(("  this character: %d XP, %d journal entries, %d sessions"):format(
        self.cdb.profile.xp or 0, self.Count(self.cdb.profile.journal), #self.cdb.history))
    if legacy then
        print(("  |cffff8000an account-wide log is parked: %d XP, %d entries%s|r"):format(
            legacy.xp or 0, self.Count(legacy.journal or {}),
            self.db.legacyClaimedBy and (", taken by " .. self:ShortName(self.db.legacyClaimedBy))
                or " - |cffffd100/tfl claim|r takes it"))
    end
    if self.cdb.declinedLegacy then
        print("  |cff858585this character turned down the old account log|r")
    end

    local ladder = self:Ladder()
    print(("  rank %s, %d XP, season %s"):format(self:RankName(self:MyRank()),
        self.cdb.profile.xp or 0, self:SeasonName()))
    print(("  ladder: %d ranks, top is %s at %d XP%s"):format(#ladder,
        ladder[#ladder].name, ladder[#ladder].xp,
        GetServerTime() < self.FRESH_START
            and ("   |cff858585new ladder in %d days|r"):format(
                math.ceil((self.FRESH_START - GetServerTime()) / 86400)) or ""))
    -- The bonus is the client's own number, not ours. Printing it is how we
    -- tell "no lure on" apart from "this build doesn't report lures".
    local rank, max, bonus, parts = self:FishingSkill()
    print(("  fishing skill: %s / %s, bonus +%d (lure %d, gear %d, buffs %d)   lure on pole: %s"):format(
        tostring(rank), tostring(max), bonus or 0, parts.lure, parts.gear, parts.buffs,
        self:LureTimeLeft() and ("%d min left"):format((self:LureTimeLeft() or 0) / 60) or "no"))
end

-- Chat can't be copied from, and a diagnostic nobody can paste is one that
-- gets retyped wrong. So it opens in the copy box; "chat" keeps the old way.
MF:Command("diag", "Other", "/tfl diag [chat] - addon state in a box you can copy, handy for bug reports",
    function(self, args)
        if args[1] == "chat" then return PrintDiag(self) end
        self:ShowDiagnosticText(table.concat(self:CapturePrints(PrintDiag), "\n"))
    end)

------------------------------------------------------------------------
-- The road test
--
-- Two anglers stood at the same lake, both in the channel, neither hearing
-- the other: is the channel carrying addon messages at all on this server?
-- Rather than guess, send the same ping down every road and have whoever
-- hears it whisper back which ones arrived. Whispers are the one road we
-- know works, which is what makes them the right way to answer.
------------------------------------------------------------------------

local ROADS = { "CHANNEL", "GUILD", "PARTY", "RAID", "SAY", "YELL" }
local ANSWER_AFTER = 4 -- seconds to collect roads before answering
local sent = {}        -- nonce -> roads we managed to send down
local heard = {}       -- nonce -> { from, roads }

MF:Command("roads", "Other", "/tfl roads [full name] - test available message routes",
    function(self, args, raw)
        local nonce = tostring(math.random(1000, 9999))
        local tried, skipped = {}, {}
        for _, road in ipairs(ROADS) do
            if self:SendVia(road, "PING", nonce) then
                tried[#tried + 1] = road:lower()
            else
                skipped[#skipped + 1] = road:lower()
            end
        end
        if raw and raw~="" then
            self:Whisper(raw,"PING",nonce) tried[#tried+1]="whisper"
        elseif not self.CUSTOM_CHANNEL_SUPPORTED then
            local peers={}
            for _,p in pairs(self:RecentCensusPlayers()) do peers[#peers+1]=p end
            table.sort(peers,function(a,b) return a.confirmedAt>b.confirmedAt end)
            for i=1,math.min(2,#peers) do self:Whisper(peers[i].name,"PING",nonce) end
            if #peers>0 then tried[#tried+1]="whisper" end
        end
        if #tried==0 then
            self:Print("No usable broadcast route or recent peer to test. Use /tfl roads Full Name, or /tfl census to discover peers.")
            self:Fire("TFL_ROSTER_SYNC")
            return
        end
        sent[nonce] = tried
        self:Print(("Queued tests over %s. Only peers reached by these routes can answer.")
            :format(table.concat(tried, ", ")))
        if #skipped > 0 then
            print(("  |cff858585Not available to you right now: %s.|r"):format(
                table.concat(skipped, ", ")))
        end
        C_Timer.After(ANSWER_AFTER + 6, function()
            if sent[nonce] then
                sent[nonce] = nil
                self:Print("No route-test replies received. This does not prove that nobody is online or that a nearby angler lacks the addon.")
            end
        end)
    end)

function MF.handlers.PING(self, sender, nonce)
    if not nonce then return end
    local p = heard[nonce]
    if not p then
        p = { from = sender, roads = {} }
        heard[nonce] = p
        C_Timer.After(ANSWER_AFTER, function()
            heard[nonce] = nil
            local list = {}
            for road in pairs(p.roads) do list[#list + 1] = road:lower() end
            table.sort(list)
            self:Whisper(p.from, "PONG", nonce, table.concat(list, "+"))
        end)
    end
    p.roads[self.lastRoad or "?"] = true
end

function MF.handlers.PONG(self, sender, nonce, roads)
    local tried = sent[nonce]
    if not tried then return end
    sent[nonce] = nil
    local got = {}
    for road in (roads or ""):gmatch("[^+]+") do got[road] = true end

    self:Print(("%s heard you on: %s"):format(self:ShortName(sender),
        (roads or ""):gsub("%+", ", ")))
    local lost = {}
    for _, road in ipairs(tried) do
        if not got[road] then lost[#lost + 1] = road end
    end
    if #lost > 0 then
        print(("  |cffff8000Nothing arrived by: %s.|r"):format(table.concat(lost, ", ")))
    end
end
