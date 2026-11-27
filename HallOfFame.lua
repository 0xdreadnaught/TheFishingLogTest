-- Hall of Fame: the realm seen as a whole, rather than one spot at a time.
--
-- Nothing new is sent for this. Every client already holds the spot records
-- it has heard about, so the standings are just those records added up. That
-- means it shows what your client knows: fish more places, hear more records.
--
-- Click an angler to see exactly what they hold.
local _, MF = ...

local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:13:13|t"
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:13:13|t"

-- You in orange, your guild in the game's own guild green, everyone else
-- plain. On a leaderboard, the people you know are what you look for first.
-- Guildmates are the green names, which is the same green as "yes".
local ME, GUILD = MF.C.me, MF.C.good

local selected -- angler key we're showing in detail, or nil for the standings
local founding -- showing the board from before the wipe
local species  -- showing the heaviest of each fish
local xpView
local guildOnly -- standings with everyone outside your guild taken out
local past      -- the season board, showing the month that just ended

-- The month is the board worth looking at: it's the one anybody can still
-- win. All time is a click away, and whichever you leave it on is where it
-- opens next.
local function SeasonView(self)
    return self.db.settings.realmSeason
end

-- Last month's board is read from what each spot kept when it rolled over.
-- Nothing is sent for it and nothing is awarded by it: it is this client's
-- copy of how the month stood, shown so the board doesn't simply go blank.
local function PastSeason(self)
    return past and SeasonView(self) and (self:SeasonID() - 1) or nil
end

local function Header(text) return { text = "|cffffd100" .. text .. "|r", header = true } end
local function Blank() return { text = "" } end

-- Alliance blue, Horde red, nothing at all for an angler who has never
-- told us. Which of those we actually see is the point of the exercise.
local FACTION = { A = MF.C.alliance .. "(A)|r", H = MF.C.horde .. "(H)|r" }

local function Side(self, name)
    local letter = FACTION[self:FactionOf(name) or ""]
    return letter and (" " .. letter) or ""
end

local function Colour(self, name)
    if self:IsMe(name) then return ME end
    if self:IsGuildmate(name) then return GUILD end
    return ""
end

-- Everyone who holds a record, keyed by angler identity so the same player
-- isn't counted twice when their name reaches us in different shapes.
-- { key, name, records, kings, specimens, best = { w, id, spot }, holdings }
-- The heaviest catch in a set of records, which is who wears the crown
-- there - all-time, or for the month, depending which set you hand it.
local function Heaviest(fish)
    local best, bestID
    for id, rec in pairs(fish) do
        if not best or rec.w > best.w then best, bestID = rec, id end
    end
    if best then return { h = best.h, w = best.w, t = best.t, s = best.s, id = bestID } end
end

-- With seasonOnly, the month's board: the same standings built from this
-- season's records instead of the all-time ones. Spots still carrying last
-- month's tag are skipped - their season table is last month's until a catch
-- there clears it.
function MF:RealmStandings(seasonOnly, seasonID)
    local anglers, best = {}, nil
    local which = seasonID or self:SeasonID()
    for spotKey, s in pairs(self.db.spots) do
        local fish = s.fish
        if seasonOnly then
            fish = self:SeasonTable(s, which)
        end
        local king = fish and (seasonOnly and Heaviest(fish) or self:King(spotKey))
        for id, rec in pairs(fish or {}) do
            local key = self:AnglerKey(rec.h)
            local a = anglers[key]
            if not a then
                a = { key = key, name = rec.h, records = 0, kings = 0, specimens = 0, holdings = {} }
                anglers[key] = a
            end
            -- Prefer the fullest spelling of the name we've seen.
            if #rec.h > #a.name then a.name = rec.h end
            a.records = a.records + 1
            if rec.s then a.specimens = a.specimens + 1 end
            a.holdings[#a.holdings + 1] = { spot = spotKey, id = id, w = rec.w, spec = rec.s,
                king = king ~= nil and self:SameAngler(king.h, rec.h) and king.id == id }
            if not a.best or rec.w > a.best.w then
                a.best = { w = rec.w, id = id, spot = spotKey }
            end
            if not best or rec.w > best.w then
                best = { w = rec.w, id = id, spot = spotKey, h = rec.h }
            end
        end
        if king then
            local a = anglers[self:AnglerKey(king.h)]
            if a then a.kings = a.kings + 1 end
        end
    end

    local list = {}
    for _, a in pairs(anglers) do list[#list + 1] = a end
    table.sort(list, function(x, y)
        if x.records ~= y.records then return x.records > y.records end
        if x.kings ~= y.kings then return x.kings > y.kings end
        return x.name < y.name
    end)
    return list, best, anglers
end

-- Where an angler stands on the realm, for the tooltip. Worked out from the
-- same standings the tab shows, and cached, because a tooltip asks on every
-- hover and the standings walk every record we hold.
local RANK_CACHE = 20
local rankOf, rankTotal, rankedAt = nil, 0, -math.huge

function MF:RealmRank(name)
    if not rankOf or GetTime() - rankedAt > RANK_CACHE then
        rankOf, rankedAt = {}, GetTime()
        local list = self:RealmStandings()
        rankTotal = #list
        for i, a in ipairs(list) do rankOf[a.key] = i end
    end
    local place = name and rankOf[self:AnglerKey(name)]
    if not place then return nil end
    return place, rankTotal
end

------------------------------------------------------------------------
-- Views
------------------------------------------------------------------------

-- One angler's line. Shared by the realm standings and a guild's roster so
-- the same angler reads the same way wherever you came across them.
local function AnglerRow(self, i, a)
    return {
        text = ("%s%d. %s|r%s"):format(Colour(self, a.name), i, self:ShortName(a.name),
            Side(self, a.name)),
        columns = { tostring(a.records), tostring(a.kings), "", tostring(a.specimens) },
        group = true, mine = self:IsMe(a.name),
        right = ("%d %s - %d %s%s"):format(a.records,
            a.records == 1 and "record" or "records", a.kings,
            a.kings == 1 and "King" or "Kings",
            a.specimens > 0 and ("  " .. STAR .. " " .. a.specimens) or ""),
        onClick = function()
            selected = a.key
            MF:RedrawJournal()
        end,
    }
end

function MF:XPStandings(onlyGuild)
    local list, added = {}, {}
    local function Add(name, xp, fish, xpAt, fishAt)
        local key = self:AnglerKey(name)
        if added[key] or (onlyGuild and not self:InMyGuild(name)) then return end
        if type(xp) ~= "number" or xp < 0 or xp ~= xp or xp == math.huge then return end
        added[key] = true
        local _, title = self:RankFor(xp)
        list[#list + 1] = { name = name, xp = xp, title = title, fish = fish, xpAt = xpAt, fishAt = fishAt }
    end
    Add(self.me, self.cdb.profile.xp or 0, self:TotalFishCaught(), GetServerTime(), GetServerTime())
    for key, seen in pairs(self.db.anglersSeen) do
        if not self:IsMe(key) then Add(seen.name or key, seen.tflXP, seen.tflFish, seen.tflXPAt, seen.tflFishAt) end
    end
    table.sort(list, function(a, b)
        if a.xp ~= b.xp then return a.xp > b.xp end
        return self:AnglerKey(a.name) < self:AnglerKey(b.name)
    end)
    return list
end

local function ReadableCount(value)
    local text = ("%.0f"):format(value)
    repeat local changed; text, changed = text:gsub("^(%d+)(%d%d%d)", "%1,%2") until changed == 0
    return text
end
local function SampleAge(at)
    if not at then return "Update time not recorded" end
    return "Last received " .. math.floor(math.max(0, GetServerTime() - at) / 60) .. " minutes ago"
end

local function XPLines(self)
    local out = { Header(guildOnly and "Guild XP leaderboard" or "Angler XP leaderboard") }
    self:NoteRows(out, "Lifetime XP, highest first. Hover an angler for update times and catch-count details.")
    out[#out + 1] = { text = "Player name", columns = { "Title", "XP", "", "Fish" }, columnWidths = { 142, 66, 0, 66 }, header = true }
    local list = self:XPStandings(guildOnly)
    for i, a in ipairs(list) do
        out[#out + 1] = { text = ("%s%d. %s|r"):format(Colour(self, a.name), i, self:ShortName(a.name)),
            columns = { a.title, ReadableCount(a.xp), "", a.fish ~= nil and ReadableCount(a.fish) or "—" },
            columnWidths = { 142, 66, 0, 66 }, mine = self:IsMe(a.name), group = true,
            tooltip = { self:ShortName(a.name), "XP: " .. SampleAge(a.xpAt),
                "Fish: " .. (a.fish ~= nil and SampleAge(a.fishAt) or "Not shared by this angler yet"),
                "Fish counts weighed Journal fish, not casts, clams or junk.",
                "Other anglers must share progression; this is your known board, not a complete realm census." } }
    end
    if #list == 0 then self:NoteRows(out, "No anglers with shared XP match this filter yet.") end
    return out
end

local function StandingsLines(self)
    local out = {}
    local seasonView = SeasonView(self)
    local pastID = PastSeason(self)
    local list, best = self:RealmStandings(seasonView, pastID)

    -- The same board with everyone else taken out. A realm board answers
    -- "where do I stand"; this one answers "where do I stand among the
    -- people I actually fish with", which on a realm of eighty anglers is
    -- the question more often worth asking.
    if guildOnly then
        local mine = {}
        best = nil
        for _, a in ipairs(list) do
            if self:InMyGuild(a.name) then
                mine[#mine + 1] = a
                if a.best and (not best or a.best.w > best.w) then
                    best = { w = a.best.w, id = a.best.id, spot = a.best.spot, h = a.name }
                end
            end
        end
        list = mine
    end

    if pastID then
        out[#out + 1] = { text = ("|cffa0a0a0%s - how it finished|r"):format(self:SeasonName(pastID)) }
        self:NoteRows(out, self:IsPreSeason(pastID)
            and "The warm-up month. It was kept for the record and nothing was awarded for it."
            or "As this client had it when the month turned. Nothing is awarded for it.")
    elseif seasonView then
        out[#out + 1] = { text = ("|cffa0a0a0%s - %s left|r"):format(
            self:SeasonName(), self:SeasonLeft()) }
        local note = self:SeasonNote()
        if note then self:NoteRows(out, note) end
    end
    if best then
        out[#out + 1] = Header(pastID and "Heaviest last season"
            or (seasonView and "Heaviest this season" or "Heaviest catch known"))
        out[#out + 1] = { text = self:FishName(best.id), icon = self:FishIcon(best.id),
            right = ("|cffffd100%s|r  %s%s|r"):format(MF:Weight(best.w), Colour(self, best.h),
                self:ShortName(best.h)) }
        out[#out + 1] = { text = "    at " .. self:SpotWhere(best.spot),
            onClick = self:SpotPosition(best.spot) and function() self:PointToSpot(best.spot) end or nil }
        out[#out + 1] = Blank()
    end

    out[#out + 1] = Header(guildOnly and "Your guild - click one to see their records"
        or (pastID and "Last season - click one to see their records")
        or (seasonView and "This season - click one to see their records"
            or "Every angler - click one to see their records"))
    -- Said at the top of the table rather than buried under it. There is no
    -- server, so this is one client's tally and another angler's won't match
    -- it - and a board that looks like a league table while quietly being a
    -- rumour is how two people end up both believing they're first.
    if #list > 1 then
        -- One row, deliberately: it sits above the standings, and the
        -- footer below already points at /tfl sync when anyone's online.
        self:NoteRows(out, "Your board, not the realm's: another angler's order "
            .. "won't match yours.")
    end
    if #list == 0 and guildOnly then
        self:NoteRows(out, IsInGuild()
            and "Nobody in your guild holds a record yet. Somebody has to be first."
            or "You're not in a guild, so there's nobody to compare yourself with here.")
    elseif #list == 0 then
        out[#out + 1] = { text = pastID
            and "|cff858585Nothing was kept from last season on this client.|r"
            or seasonView
            and "|cff858585Nothing set this season yet. The board is wide open.|r"
            or "|cff858585No records known yet. Fish a few spots and they'll fill in.|r" }
    end
    if #list > 0 then
        out[#out + 1] = { text = "Angler", columns = { "Records", "Kings", "", "Specimens" }, header = true }
    end
    for i = 1, #list do
        out[#out + 1] = AnglerRow(self, i, list[i])
    end

    -- Your own seasons, kept from the history.
    local seasons = {}
    for i = #self.cdb.history, 1, -1 do
        local h = self.cdb.history[i]
        if h.season then seasons[#seasons + 1] = h end
    end
    if #seasons > 0 then
        out[#out + 1] = Blank()
        out[#out + 1] = Header("Your past seasons")
        for _, h in ipairs(seasons) do
            out[#out + 1] = { text = self:SeasonName(h.season),
                right = ("%d XP, %d records, %d Kings"):format(h.xp or 0, h.records or 0, h.kings or 0) }
        end
    end

    out[#out + 1] = Blank()
    -- Filtered, the realm-wide counts below would be answering a question
    -- nobody asked. Say how much of the realm this is instead.
    if guildOnly then
        if IsInGuild() then
            local everyone = #select(1, self:RealmStandings(seasonView, pastID))
            self:NoteRows(out, ("%d of the %d anglers holding records are in your guild."):format(
                #list, everyone))
        end
        return out
    end

    -- Say where the numbers come from: this is what your client has heard,
    -- not a realm census, and the difference matters on a quiet realm.
    out[#out + 1] = { text = ("%sYou|r and %syour guild|r are picked out.")
        :format(ME, GUILD) }
    local spots = self.Count(self.db.spots)
    self:NoteRows(out, ("%s your client has heard about: %d %s holding them, at %d %s."):format(
        pastID and "Last season's records" or (seasonView and "This season's records" or "Records"),
        #list, #list == 1 and "angler" or "anglers",
        spots, spots == 1 and "spot" or "spots"))
    local met = self:AnglersSeenCount()
    if met > #list then
        self:NoteRows(out, ("You've heard from %d anglers in all - the rest hold no records "
            .. "yet. |cffffd100/tfl anglers|r lists them."):format(met))
    end
    local online = self:CensusCount()
    if online > 0 then
        self:NoteRows(out, ("%d other %s online with the addon right now. "
            .. "|cffffd100/tfl sync|r swaps records with them."):format(
            online, online == 1 and "angler is" or "anglers are"))
    end
    return out
end

local function AnglerLines(self, a)
    local out = { Header(self:ShortName(a.name) .. Side(self, a.name)
        .. (SeasonView(self) and ("  |cffa0a0a0" .. self:SeasonName(PastSeason(self)) .. "|r") or "")) }
    out[#out + 1] = { text = "Records held", right = tostring(a.records) }
    out[#out + 1] = { text = "King of", right = ("%d %s"):format(a.kings, a.kings == 1 and "spot" or "spots") }
    out[#out + 1] = { text = "Specimen records", right = tostring(a.specimens) }
    if a.best then
        out[#out + 1] = { text = "Heaviest", icon = self:FishIcon(a.best.id),
            right = ("%s  %s"):format(MF:Weight(a.best.w), self:FishName(a.best.id)) }
        out[#out + 1] = { text = "    at " .. self:SpotWhere(a.best.spot) }
    end

    out[#out + 1] = Blank()
    out[#out + 1] = Header("Their records - click one to find the water")
    table.sort(a.holdings, function(x, y) return x.w > y.w end)
    for _, h in ipairs(a.holdings) do
        local zone = self:SpotPosition(h.spot)
        out[#out + 1] = {
            text = ("%s%s%s"):format(h.king and (CROWN .. " ") or "", h.spec and (STAR .. " ") or "",
                self:SpotName(h.spot)),
            icon = self:FishIcon(h.id),
            right = ("%s  %s"):format(MF:Weight(h.w), self:FishName(h.id)),
            onClick = zone and function() self:PointToSpot(h.spot) end or nil,
        }
    end

    return out, { { label = "Back", onClick = function()
        selected = nil
        self:RedrawJournal()
    end } }
end

local CENSUS_STALE = 120 -- seconds before opening the tab asks again

-- One crown per fish rather than per lake. The unclaimed list is the point
-- as much as the held one: it says what is still there to be taken.
local function SpeciesLines(self)
    local seasonView = SeasonView(self)
    local held, open = self:SpeciesRecords(seasonView)
    local out = {}

    if seasonView then
        out[#out + 1] = { text = ("|cffa0a0a0%s - %s left|r"):format(
            self:SeasonName(), self:SeasonLeft()) }
        local note = self:SeasonNote()
        if note then self:NoteRows(out, note) end
    end

    local mine = 0
    for _, r in ipairs(held) do
        if self:IsMe(r.h) then mine = mine + 1 end
    end
    -- Two counts rather than "x of y": held includes trophy fish, which have
    -- item IDs of their own, so the total grew every time somebody landed a
    -- new kind - and "34 of 61" becoming "35 of 63" reads like losing ground
    -- when you have just gained some.
    out.summary = {
        { label = "Claimed records", shortLabel = "Claimed", value = tostring(#held) },
        { label = "Unclaimed species", shortLabel = "Unclaimed", value = tostring(#open) },
        { label = "Records you hold", shortLabel = "Yours", value = tostring(mine) },
    }
    out[#out + 1] = Header("Heaviest of each fish")
    if #held == 0 then
        out[#out + 1] = { text = "|cff858585Not one of them is spoken for. Go and take one.|r" }
    end

    local widths = { 80, 148, 46, 0 }
    if #held > 0 then
        out[#out + 1] = { text = "Fish", columns = { "Weight", "Holder", "Spec.", "" },
            columnWidths = widths, header = true }
    end

    for _, r in ipairs(held) do
        out[#out + 1] = {
            text = self:FishName(r.id),
            icon = self:FishIcon(r.id),
            right = ("|cffffd100%s|r  %s%s|r"):format(MF:Weight(r.w), Colour(self, r.h),
                self:ShortName(r.h)),
            columns = { MF:Weight(r.w), Colour(self, r.h) .. self:ShortName(r.h) .. "|r",
                r.s and STAR or "|cff6a6a6a-|r", "" },
            columnWidths = widths, group = true, mine = self:IsMe(r.h),
            onClick = self:SpotPosition(r.spot) and function() self:ShowSpotOnMap(r.spot) end or nil,
        }
    end

    if #open > 0 then
        out[#out + 1] = Blank()
        out[#out + 1] = Header(("Nobody has landed these yet (%d)"):format(#open))
        for _, f in ipairs(open) do
            out[#out + 1] = { text = self:FishName(f.id), icon = self:FishIcon(f.id),
                right = "|cff858585unclaimed|r", group = true }
        end
    end
    return out
end

------------------------------------------------------------------------
-- By guild
--
-- A client can read its own guild roster and nobody else's, so the only
-- way anyone knows what guild a stranger is in is if that stranger said
-- so - which they now do, in the census. That makes this board honest but
-- incomplete by nature: an angler who has never been online with you is
-- counted nowhere, and saying so is part of the view rather than a
-- footnote to it.
------------------------------------------------------------------------

-- Is this one of ours?
--
-- Two routes, because either can be missing. The guild roster is the
-- authority but isn't always loaded - a client that has just logged in
-- answers nothing for a few seconds, and asking for it is how it arrives.
-- Meanwhile anyone running this version says which guild they're in as
-- part of the census, which covers the gap and keeps working for an angler
-- the roster hasn't caught up with.
function MF:InMyGuild(name)
    if not name or self:IsGuildmate(name) then return name ~= nil end
    local mine = self:MyGuild()
    return mine ~= "" and self:GuildOf(name) == mine
end

local function FoundingView(self)
    local lines = self:FoundingLines()
    return lines, { { label = "Back", onClick = function()
        founding = false
        self:RedrawJournal()
    end } }
end

MF:AddJournalTab("fame", "Realm", function(self)
    -- Opening the tab is as good a moment as any to see who's about, and to
    -- hand our records to anyone who has just arrived.
    if GetTime() - (self.census.at or 0) > CENSUS_STALE then
        self:RequestCensus(true)
        self:RequestBook()
    end
    if xpView then
        return XPLines(self), {
            { label = "Refresh", onClick = function()
                self:Fire("TFL_ROSTER_SYNC")
                self:RequestCensus(true)
                self:Print("Refreshing known progression. Solo replies require the progression-sharing update; discovery cooldowns still apply.")
                self:RedrawJournal()
            end },
            { label = "Records", onClick = function() xpView = nil self:RedrawJournal() end },
            { label = guildOnly and "Everyone" or "My guild", onClick = function()
                guildOnly = not guildOnly self:RedrawJournal()
            end },
        }
    end
    -- One button walks the boards: this season, last season (once this
    -- client has one kept), all time. Its label is where the next click goes.
    local hasPast = self:HasSeasonRecords(self:SeasonID() - 1)
    if not hasPast or not SeasonView(self) then past = nil end
    local toggle = { label = not SeasonView(self) and "This season"
        or (not past and hasPast and not species) and "Last season" or "All time", onClick = function()
        if not SeasonView(self) then
            self.db.settings.realmSeason = true
        elseif not past and hasPast and not species then
            past = true
        else
            past = nil
            self.db.settings.realmSeason = false
        end
        selected = nil -- the boards don't hold the same anglers
        self:RedrawJournal()
    end }

    -- The beta's board, kept rather than deleted. Only offered once there
    -- is one, so it never appears before the realm has a past.
    if founding and self:FoundingLines() then
        return FoundingView(self)
    end
    if species then
        return SpeciesLines(self), { toggle, { label = "Anglers", onClick = function()
            species = false
            self:RedrawJournal()
        end } }
    end
    local look
    if self:FoundingLines() then
        look = { label = "Before the wipe", onClick = function()
            founding = true
            selected = nil
            self:RedrawJournal()
        end }
    end

    if selected then
        local _, _, anglers = self:RealmStandings(SeasonView(self), PastSeason(self))
        local a = anglers[selected]
        if a then
            local lines, actions = AnglerLines(self, a)
            table.insert(actions, toggle)
            return lines, actions
        end
        selected = nil
    end
    local actions = { toggle, { label = "By fish", onClick = function()
        species = true
        past = nil -- by fish is this season or all time
        selected = nil
        self:RedrawJournal()
    end }, { label = guildOnly and "Everyone" or "My guild", onClick = function()
        guildOnly = not guildOnly
        selected = nil
        self:RedrawJournal()
    end } }
    actions[#actions + 1] = { label = "XP leaderboard", onClick = function()
        xpView, selected, species = true, nil, nil
        self:RedrawJournal()
    end }
    if look then actions[#actions + 1] = look end
    return StandingsLines(self), actions
end)

MF:Command("realm", "Progress", "/tfl realm - the realm's hall of fame", function(self)
    self:ToggleJournal("fame")
end)

function MF:ResetRealmRankCache()
    rankOf,rankTotal,rankedAt=nil,0,-math.huge
    xpView = nil
    selected,founding,species,guildOnly,past=nil,nil,nil,nil,nil
end
