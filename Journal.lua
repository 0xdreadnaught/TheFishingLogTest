-- Journal: the Angler's Journal window with Journal, Records, Bounty and
-- History tabs. Each tab builds a list of lines; one scrolling list shows them.
local _, MF = ...

local ROWS = 22
local ROW_H = 17
local ROW_POOL = 96
-- A row of sub-tabs costs the list two of its rows, which is cheaper
-- than making the window taller for the one tab that wants them.
local SUB_H = 28
local SUB_COST = 2
-- How many rows the list is showing right now; the sub-tab row takes
-- some. Render and the scrollbar both count in these, not in ROWS.
local shown = ROWS
local STAR = [[|TInterface\TargetingFrame\UI-RaidTargetingIcon_1:13:13|t]]
local win
local offset = 0
local offsetTab
local lines = {}

------------------------------------------------------------------------
-- Tab contents. A tab's build(MF) returns lines and, optionally, actions:
--   line:   { text, right, icon, header, onClick }
--   action: { label, onClick } - shown as buttons along the bottom
------------------------------------------------------------------------

local function Header(text) return { text = "|cffffd100" .. text .. "|r", header = true } end
local function Blank() return { text = "" } end

-- The Journal: what you've caught, and where you actually caught it.
--
-- A fish lives in several zones, so a species-per-zone list says the same
-- thing many times over. The zone view is for "what's left here", the fish
-- view for "what have I got" - and either way the numbers beside a fish
-- belong to the water you're reading about, once we've watched you catch
-- one there. Catches from before that only prove you've been.
local journalView = "zones" -- or "fish", or "cards" for the album
local expanded       -- itemID whose zones are showing
local unknownShown   -- did anything on screen have to say "x?"
local searchText, searchFilter = "", "all"

local function SwitchTab(self, tab)
    local settings = self.db.settings
    settings.journalOffsets = settings.journalOffsets or {}
    settings.journalOffsets[offsetTab or win.tab] = offset
    if tab ~= win.tab or offsetTab ~= tab then
        win.tab = tab
        offsetTab = tab
        local saved = tonumber(settings.journalOffsets[tab]) or 0
        offset = saved == saved and saved < math.huge and math.max(0, math.floor(saved)) or 0
    end
end

function MF:SetJournalSearch(text, filter)
    searchText = strtrim(tostring(text or "")):lower()
    if filter == "all" or filter == "missing" or filter == "specimens" then searchFilter = filter end
    offset, expanded = 0, nil
    self:RefreshJournal()
end

-- One species per result. Zone matches include observed catches as well as
-- the native-zone list, so new Forever waters can be searched too.
function MF:JournalSearchResults(text, filter)
    local query = strtrim(tostring(text or "")):lower()
    local ids, out = {}, {}
    for id in pairs(self.FISH) do ids[id] = true end
    for id in pairs(self.cdb.profile.journal) do ids[id] = true end
    for id in pairs(ids) do
        local j = self.cdb.profile.journal[id]
        local f = self.FISH[id]
        local matches = query == "" or self:FishName(id):lower():find(query, 1, true) ~= nil
        local zones = {}
        for _, zone in ipairs(f and f.zones or {}) do zones[zone] = true end
        for zone in pairs(self.cdb.caughtIn[id] or {}) do zones[zone] = true end
        for zone in pairs(zones) do
            if zone:lower():find(query, 1, true) then matches = true end
        end
        local allowed = filter ~= "missing" or not j
        if filter == "specimens" then allowed = j and (j.s or 0) > 0 end
        if matches and allowed then out[#out + 1] = { id = id, name = self:FishName(id), journal = j } end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

local function SearchLines(self, out)
    local results = self:JournalSearchResults(searchText, searchFilter)
    out[#out + 1] = Header(("Search results - %d species"):format(#results))
    out[#out + 1] = { text = "Fish", columns = { "Best", "Caught", "", "Specimen" }, header = true }
    for _, result in ipairs(results) do
        local id, j = result.id, result.journal
        out[#out + 1] = {
            text = result.name, icon = self:FishIcon(id),
            columns = j and { self:Weight(j.b), "x" .. j.c, "", (j.s or 0) > 0 and self:Weight(j.s) or "-" }
                or { "-", "-", "", "not caught" },
            onClick = function() self:ShowCard(id) end,
        }
    end
    if #results == 0 then self:NoteRows(out, "No fish match. Try a different name, zone or filter.") end
end

-- Goals use existing evidence only. Personal records are per spot; the
-- collection and native list describe the zone or species, never a promise
-- about the exact shoreline.
function MF:FishingHereLines()
    local out = {}
    local spot, zone = self:CurrentSpot(), self:ZoneEnglish()
    local journal, mine = self.cdb.profile.journal, self.cdb.records
    local bests = mine[spot.key] or {}
    local active, secs = self:FrenzyPresentationState(spot.key)
    out[#out + 1] = Header("Fishing here - " .. spot.name)
    if self.session and self.session.outcomes then self:NoteRows(out,self:CastOutcomeSummary(self.session)) end
    out[#out + 1] = { text = zone, right = secs and ((active and "Frenzy: " or "Frenzy in ") .. self:FormatClock(secs)) or "Fishing location unconfirmed" }
    local native, missing = {}, {}
    for id in pairs(self:ZoneFish(zone)) do
        native[#native + 1] = id
        if not journal[id] then missing[#missing + 1] = id end
    end
    local function ByName(a, b) return self:FishName(a) < self:FishName(b) end
    table.sort(native, ByName)
    table.sort(missing, ByName)
    local function CardRow(id, right)
        return { text = self:FishName(id), icon = self:FishIcon(id), right = right,
            onClick = function() self:ShowCard(id) end }
    end
    out[#out + 1] = Blank()
    out[#out + 1] = Header("Still to catch in " .. zone)
    if #native == 0 then self:NoteRows(out, "No native fish list is available for this zone yet.")
    elseif #missing == 0 then self:NoteRows(out, "You have collected every species listed for this zone.")
    else
        for i = 1, math.min(2, #missing) do out[#out + 1] = CardRow(missing[i], "not caught") end
        if #missing > 2 then self:NoteRows(out, ("%d more in your journal."):format(#missing - 2)) end
    end
    self:NoteRows(out, "Native to the zone does not guarantee a catch at this exact water.")

    local candidate, gap
    local recordsReady = self:RecordsReady(spot.mapID) or spot.mapID == 0
    if not recordsReady then self:RequestRecords(spot.mapID) end
    if recordsReady then
        for _, r in ipairs(self:SpotRecords(spot.key)) do
            local personal = bests[r.id]
            if personal and r.all and not self:IsMe(r.all.h) and r.all.w > personal.weight then
                local difference = r.all.w - personal.weight
                if not gap or difference < gap or (difference == gap and r.id < candidate.id) then
                    candidate, gap = r, difference
                end
            end
        end
    end
    out[#out + 1] = Blank()
    out[#out + 1] = Header("A spot record to chase")
    if candidate then
        out[#out + 1] = CardRow(candidate.id, self:Weight(gap) .. " to match")
        out[#out + 1] = { text = "Your best here", right = self:Weight(bests[candidate.id].weight) }
        out[#out + 1] = { text = "Known spot record", right = self:Weight(candidate.all.w) }
    else
        self:NoteRows(out, recordsReady and "No higher known spot record to compare with your catches here yet."
            or "Checking spot records with other anglers. This page will update when they arrive.")
    end

    local improve, percentile
    for _, id in ipairs(native) do
        local personal = bests[id]
        local p = personal and self:WeightPercentile(id, personal.weight)
        if p and p < 0.98 and (not percentile or p < percentile) then improve, percentile = id, p end
    end
    if improve then
        out[#out + 1] = Blank()
        out[#out + 1] = Header("Improve a personal best")
        out[#out + 1] = CardRow(improve, self:Weight(bests[improve].weight))
        local grade = self:WeightGradeShort(improve, bests[improve].weight)
        self:NoteRows(out, "Your best here is graded " .. grade .. ". A better catch would improve this spot's personal best.")
    end

    out[#out + 1] = Blank()
    out[#out + 1] = Header("Bounties you can enter in this zone")
    local relevant = 0
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        local _, id, targetZone = self:Bounty(kind)
        if id and (not targetZone or targetZone == zone) then
            local mode = self:BountyFormat(kind)
            local collection = mode == "species" or mode == "zone" or mode == "specimenSpecies"
            local possible = collection or targetZone == zone
            for _, fid in ipairs(native) do if fid == id then possible = true end end
            if (self.cdb.caughtIn[id] or {})[zone] then possible = true end
            if bests[id] then possible = true end
            if possible then
                relevant = relevant + 1
                local label = kind == "day" and "Daily" or (kind == "week" and "Weekly" or "Monthly")
                out[#out + 1] = CardRow(id, label .. " - " .. self:FormatSpan(self:BountyTimeLeft(kind)))
                if mode ~= "heaviest" and mode ~= "count" then out[#out].text = self:BountyTitle(kind) end
                out[#out].icon = self:BountyIcon(kind)
                if collection then
                    out[#out].onClick = function() self:OpenJournal("bounty") end
                end
                local entry = self:MyBountyBest(kind)
                local standings = self:BountyStandings(kind)
                local leader = standings[1] and standings[1].weight or 0
                local function Score(value,specimen) return self:BountyScoreText(kind, value,nil,specimen) end
                out[#out + 1] = { text = "Your entry", right = entry > 0 and Score(entry,self:BountySpecimenStatus(kind,self.me,nil,entry)) or "not entered" }
                if leader > 0 then
                    out[#out + 1] = { text = "Best known entry", right = Score(leader,standings[1].specimen) }
                    if entry > 0 and leader > entry then
                        out[#out + 1] = { text = "Gap to the lead", right = Score(leader - entry,false) }
                    end
                end
            end
        end
    end
    if relevant == 0 then self:NoteRows(out, "No current bounty matches the fish known in this zone.") end

    out[#out + 1] = Blank()
    out[#out + 1] = Header("Your catches at this spot")
    local ids = {}
    for id in pairs(bests) do ids[#ids + 1] = id end
    table.sort(ids, ByName)
    if #ids == 0 then self:NoteRows(out, "No personal catches logged at this water yet.") end
    for _, id in ipairs(ids) do
        local grade, colour = self:WeightGradeShort(id, bests[id].weight)
        if bests[id].specimen then grade, colour = "specimen", self.C.spec end
        local right = self:Weight(bests[id].weight) .. (grade and ("  " .. colour .. grade .. "|r") or "")
        out[#out + 1] = CardRow(id, right)
    end
    self:NoteRows(out, "Open a fish card for collection-wide counts and specimen progress.")
    return out
end

function MF:OpenFishingHere()
    journalView = "here"
    self:OpenJournal("journal")
end

function MF:OpenAnglingTools(view)
    self.anglingToolsView = view or "waters"
    journalView = "tools"
    offset, expanded = 0, nil
    self:OpenJournal("journal")
    self:RedrawJournal()
end

function MF:OpenFishingGoal(id)
    if id then self.goalFishSelected = id end
    journalView = "goals"
    offset, expanded = 0, nil
    self:OpenJournal("journal")
    self:RedrawJournal()
end

local function Caught(self, id, zone)
    local byZone = self.cdb.caughtIn[id]
    return byZone and byZone[zone]
end

-- Every zone you've landed this fish in, newest data first.
local function ZonesFor(self, id, j)
    local list = {}
    for zone, here in pairs(self.cdb.caughtIn[id] or {}) do
        list[#list + 1] = { zone = zone, c = here.c, b = here.b, s = here.s, spot = here.spot }
    end
    -- Zones we know about only from the old bitmask have no weights to show.
    local f = self.FISH[id]
    for i, zone in ipairs(f and f.zones or {}) do
        if self:CaughtInZone(j, i) and not (self.cdb.caughtIn[id] or {})[zone] then
            list[#list + 1] = { zone = zone }
        end
    end
    table.sort(list, function(a, b) return (a.b or 0) > (b.b or 0) end)
    return list
end

-- How good your best is, for its kind. The grade is said once in chat when
-- you land the fish and then it is gone; this is the place you come to ask
-- the question afterwards, so it belongs here too.
local function Graded(self, id, weight, specimen)
    if (specimen or 0) > 0 then return "  " .. self.C.spec .. "Specimen|r" end
    local name, colour = self:WeightGradeShort(id, weight)
    if not name then return "" end
    return ("  %s%s|r"):format(colour, name)
end

local function FishRight(self, j, here, id)
    if here and here.c then
        return ("best %s%s  x%d   %s"):format(MF:Weight(here.b), Graded(self, id, here.b, here.s), here.c,
            (here.s or 0) > 0 and (STAR .. (" |cffffd100%.2f|r"):format(here.s))
                or "|cff6a6a6ano specimen|r"),
            { MF:Weight(here.b), Graded(self, id, here.b, here.s), "x" .. here.c,
              (here.s or 0) > 0 and (STAR .. " " .. MF:Weight(here.s)) or "|cff6a6a6a-|r" }
    end
    -- All we know is that you've caught one here at some point: this fish
    -- was landed before the addon kept a tally per water. The "x?" mirrors
    -- the "x10" on rows that do know, so it reads as missing, not as none.
    unknownShown = true
    return ("|cffa0a0a0caught here  x?|r   |cff858585best anywhere %s|r"):format(MF:Weight(j.b))
end

local function ExpandLines(self, out, id, j)
    for _, z in ipairs(ZonesFor(self, id, j)) do
        local right = z.c and ("best %s%s  x%d"):format(MF:Weight(z.b), Graded(self, id, z.b, z.s), z.c)
            or "|cff858585caught here  x?|r"
        out[#out + 1] = {
            text = "|cffa0a0a0    " .. z.zone .. "|r",
            right = right,
            onClick = z.spot and function() self:PointToSpot(z.spot) end or nil,
        }
    end
    if #ZonesFor(self, id, j) == 0 then
        out[#out + 1] = { text = "|cff858585    caught somewhere the addon didn't know|r" }
    end
end

local function FishRow(self, out, id, j, right, columns)
    out[#out + 1] = {
        text = self:FishName(id), icon = self:FishIcon(id), right = right, columns = columns,
        onClick = function()
            expanded = expanded ~= id and id or nil
            self:RedrawJournal()
        end,
    }
    if expanded == id then ExpandLines(self, out, id, j) end
end

-- How far you've got, in one line each.
local function ProgressLines(self, out)
    local journal = self.cdb.profile.journal
    local caught, specimens = 0, 0
    for id in pairs(self.FISH) do
        local j = journal[id]
        if j then
            caught = caught + 1
            if j.s > 0 then specimens = specimens + 1 end
        end
    end
    local total = self.Count(self.FISH)
    local waters = 0
    for _ in pairs(self.cdb.caughtIn) do waters = waters + 1 end

    out[#out + 1] = Header("Your journal")
    -- Where somebody wondering why their journal is empty will actually be
    -- looking. A chat line at login is not where that question gets asked.
    local waiting = self:LegacyWaiting()
    if waiting and (waiting.xp or 0) > (self.cdb.profile.xp or 0) then
        out[#out + 1] = {
            text = ("|cffff8000An older log is waiting - %d XP, %d entries.|r"):format(
                waiting.xp or 0, self.Count(waiting.journal or {})),
            right = "|cffffd100claim it|r",
            onClick = function() self:OfferClaim() end,
        }
    end
    out.summary = {
        { label = "Species caught", value = ("%d / %d"):format(caught, total) },
        { label = "Species with a specimen", value = STAR .. " " .. specimens },
    }
    local value = self.cdb.profile.value or 0
    if self:ValueEnabled() and value > 0 then
        out.summary[3] = { label = "Landed so far", value = self:Money(value) }
    end
    out[#out + 1] = Blank()
end

-- Every species once, heaviest first among the ones you've landed.
local function FishViewLines(self, out)
    local journal = self.cdb.profile.journal
    local mine, missing = {}, {}
    for id, f in pairs(self.FISH) do
        if journal[id] then mine[#mine + 1] = id else missing[#missing + 1] = id end
    end
    for id, j in pairs(journal) do
        if not self.FISH[id] then mine[#mine + 1] = id end
    end
    table.sort(mine, function(a, b) return (journal[a].b or 0) > (journal[b].b or 0) end)
    table.sort(missing, function(a, b) return self.FISH[a].max < self.FISH[b].max end)

    out[#out + 1] = Header(("Caught  -  %d species"):format(#mine))
    out[#out + 1] = { text = "Fish", columns = { "Best", "Grade", "Caught", "Waters" }, header = true }
    for _, id in ipairs(mine) do
        local j = journal[id]
        local zones = #ZonesFor(self, id, j)
        FishRow(self, out, id, j, ("best %s%s  x%d   %s"):format(MF:Weight(j.b),
            Graded(self, id, j.b, j.s), j.c,
            zones > 0 and ("|cffa0a0a0%d %s|r"):format(zones, zones == 1 and "water" or "waters")
                or "|cff858585-|r"),
            { MF:Weight(j.b), Graded(self, id, j.b, j.s), "x" .. j.c,
              zones > 0 and tostring(zones) or "|cff6a6a6a-|r" })
    end
    if self.db.settings.journalHideMissing or #missing == 0 then return end
    out[#out + 1] = Blank()
    out[#out + 1] = Header(("Still to catch  -  %d"):format(#missing))
    for _, id in ipairs(missing) do
        local f = self.FISH[id]
        out[#out + 1] = { text = "|cff858585???|r", icon = 134400,
            right = ("|cff6a6a6a%s|r"):format(f.zones and f.zones[1] or "somewhere") }
    end
end

-- Zone by zone: what lives here, and what you've taken out of it.
local function ZoneViewLines(self, out)
    local journal = self.cdb.profile.journal
    local zones, byZone, extra = {}, {}, {}
    local function Zone(z)
        if not byZone[z] then
            byZone[z] = {}
            extra[z] = {}
            zones[#zones + 1] = z
        end
        return byZone[z]
    end
    for id, f in pairs(self.FISH) do
        for _, z in ipairs(f.zones or {}) do
            table.insert(Zone(z), id)
        end
    end

    -- Fish don't read the data. Anything you've actually landed in a zone
    -- belongs on that zone's list, whether or not we expected it there -
    -- and a zone we know nothing about still earns a heading once you've
    -- caught something in it.
    for id, byZ in pairs(self.cdb.caughtIn) do
        for z in pairs(byZ) do
            local native = false
            for _, n in ipairs(byZone[z] or Zone(z)) do
                if n == id then
                    native = true
                    break
                end
            end
            if not native then table.insert(extra[z], id) end
        end
    end

    -- Water you've actually fished comes first, then your own zone, then the
    -- rest in name order - so the places you know aren't below Ashenvale.
    local fished = {}
    for _, byZ in pairs(self.cdb.caughtIn) do
        for zone in pairs(byZ) do fished[zone] = true end
    end
    local myZone = self:Location()
    table.sort(zones, function(a, b)
        if (a == myZone) ~= (b == myZone) then return a == myZone end
        if (fished[a] or false) ~= (fished[b] or false) then return fished[a] end
        return a < b
    end)

    local hideMissing = self.db.settings.journalHideMissing
    for _, z in ipairs(zones) do
        local ids = byZone[z]
        table.sort(ids, function(a, b) return self.FISH[a].max < self.FISH[b].max end)
        local here, caught, specs = {}, 0, 0
        for _, id in ipairs(ids) do
            local j = journal[id]
            local index = self:ZoneIndexFor(id, z)
            here[id] = (index and self:CaughtInZone(j, index)) or Caught(self, id, z) ~= nil
            if here[id] then
                caught = caught + 1
                local mine = Caught(self, id, z)
                if (mine and (mine.s or 0) > 0) or (not mine and j.s > 0) then specs = specs + 1 end
            end
        end
        local surprises = extra[z] or {}
        if not (hideMissing and caught == 0 and #surprises == 0) then
            out[#out + 1] = Header(#ids > 0
                and ("%s  -  %d/%d fish, %d/%d specimens"):format(z, caught, #ids, specs, #ids)
                or ("%s  -  %d caught"):format(z, #surprises))
            out[#out + 1] = { text = "Fish", columns = { "Best", "Grade", "Caught", "Specimen" }, header = true }
            for _, id in ipairs(ids) do
                if here[id] then
                    FishRow(self, out, id, journal[id], FishRight(self, journal[id], Caught(self, id, z), id))
                elseif not hideMissing then
                    out[#out + 1] = { text = "|cff858585???|r", icon = 134400,
                        right = "|cff6a6a6anot caught|r" }
                end
            end
            for _, id in ipairs(surprises) do
                FishRow(self, out, id, journal[id], FishRight(self, journal[id], Caught(self, id, z), id))
            end
            out[#out + 1] = Blank()
        end
    end

    -- Fish we caught that aren't in the data table (e.g. new Forever fish).
    local other = {}
    for id, j in pairs(journal) do
        if not self.FISH[id] then other[#other + 1] = { id = id, j = j } end
    end
    if #other > 0 then
        out[#out + 1] = Header("Other catches")
        for _, o in ipairs(other) do
            FishRow(self, out, o.id, o.j, ("best %s%s  x%d"):format(MF:Weight(o.j.b),
                Graded(self, o.id, o.j.b, o.j.s), o.j.c))
        end
    end
end

local function JournalLines(self)
    local out = {}
    unknownShown = false
    if journalView == "tools" then return self:AnglingToolsLines() end
    if journalView == "goals" then
        return self:FishingGoalLines(), { { label = "Journal", onClick = function()
            journalView = "zones" self:RedrawJournal()
        end } }
    end
    if journalView == "here" then
        return self:FishingHereLines(), { { label = "Journal", onClick = function()
            journalView = "zones"
            self:RedrawJournal()
        end }, { label = "Local waters", onClick = function() self:OpenAnglingTools("waters") end },
            { label = "Tacklebox", onClick = function() self:OpenAnglingTools("tackle") end },
            { label = "Find waters", onClick = function() self:OpenAnglingTools("finder") end } }
    end
    if searchText ~= "" or searchFilter ~= "all" then
        ProgressLines(self, out)
        SearchLines(self, out)
        return out, { { label = "Here", onClick = function() self:OpenFishingHere() end } }
    end
    -- The album counts itself in its own header, so the progress block
    -- would be the same two numbers again directly above it.
    if journalView ~= "cards" then ProgressLines(self, out) end
    if journalView == "cards" then
        self:AlbumLines(out)
    elseif journalView == "fish" then
        FishViewLines(self, out)
    else
        ZoneViewLines(self, out)
    end

    if unknownShown then
        out[#out + 1] = Blank()
        self:NoteRows(out, "x? means you caught it there before the addon counted catches "
            .. "water by water. New ones will show properly.")
    end

    local hideMissing = self.db.settings.journalHideMissing
    local function Go(view)
        return function()
            journalView = view
            expanded = nil
            self:RedrawJournal()
        end
    end

    -- The album gets a button of its own rather than a third stop on the
    -- view cycle. Cycling meant the word "Album" only appeared once you
    -- had already pressed the button, so there was nothing on screen to
    -- say an album existed - which is exactly how it went unfound.
    if journalView == "cards" then
        return out, { { label = "Back", onClick = Go("zones") },
            { label = "Here", onClick = function() self:OpenFishingHere() end } }
    end
    return out, {
        { label = journalView == "fish" and "By zone" or "By fish",
          onClick = Go(journalView == "fish" and "zones" or "fish") },
        { label = hideMissing and "All fish" or "Caught",
          onClick = function()
              self.db.settings.journalHideMissing = not hideMissing
              self:RedrawJournal()
          end },
        { label = "Album", onClick = Go("cards") },
        { label = "Here", onClick = function() self:OpenFishingHere() end },
        { label = "Find waters", onClick = function() self:OpenAnglingTools("finder") end },
    }
end

-- A spot's name as a list shows it: its own name, or where it is when it
-- has none of its own (or only the zone's).
function MF:SpotListLabel(spotKey)
    local name = self:SpotName(spotKey)
    local where = self.db.spotWhere[spotKey]
    local zone = self:ZoneNameFor(where and where.map or self:MapOfKey(spotKey))
    if not self:KnownSpotName(spotKey) or name == zone then
        if where and self:ValidSpotPosition(spotKey, where.map, where.x, where.y) then
            return ("%s (%.0f, %.0f)"):format(name, where.x * 100, where.y * 100)
        end
        return name .. " (location unknown)"
    end
    return name
end

-- Every other spot on this map, by name: { key = , label = }.
function MF:OtherSpots(key, mapID)
    local list = {}
    for _, s in pairs(self.db.spots) do
        if self:SpotOnMap(s, mapID) and s.key ~= key then
            list[#list + 1] = { key = s.key, label = self:SpotListLabel(s.key) }
        end
    end
    table.sort(list, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.key < b.key
    end)
    return list
end

function MF:MapName(mapID)
    local info = mapID and mapID > 0 and C_Map.GetMapInfo(mapID)
    return (info and info.name) or "this zone"
end

local function RecordsLines(self)
    local out = {}
    local key, sub, mapID = self:SpotInfo()
    local king = self:King(key)
    out[#out + 1] = { text = ("|cffa0a0a0%s - %s left|r"):format(self:SeasonName(), self:SeasonLeft()) }
    out[#out + 1] = Header(sub)
    if not self:RecordsReady(mapID) then
        self:RequestRecords(mapID)
        out[#out + 1] = { text = "|cff858585Waiting for records from other anglers...|r" }
        return out
    end
    if king then
        -- The header above names the spot; a longer label collides with the
        -- holder and fish on the right.
        out[#out + 1] = { text = "King", icon = "Interface\\Icons\\INV_Crown_01",
            right = ("|cffffd100%s|r - %s %s"):format(self:ShortName(king.h), self:FishName(king.id), MF:Weight(king.w)) }
    else
        out[#out + 1] = { text = "|cff858585No records here yet. Be the first!|r" }
    end
    local myBests = self.cdb.records[key] or {}
    for _, r in ipairs(self:SpotRecords(key)) do
        local right = r.all and ("%s  %s"):format(MF:Weight(r.all.w), self:ShortName(r.all.h)) or ""
        if r.all and r.all.s then right = STAR .. " " .. right end
        out[#out + 1] = { text = self:FishName(r.id), icon = self:FishIcon(r.id), right = right, group = true }
        -- How close you are, when the record isn't yours.
        local mine = myBests[r.id]
        if mine and r.all and not self:IsMe(r.all.h) then
            out[#out + 1] = { text = "    |cff3ee63eyour best|r",
                right = ("|cff3ee63e%s|r  |cffa0a0a0(%s behind)|r"):format(
                    MF:Weight(mine.weight), MF:Weight(r.all.w - mine.weight)) }
        end
        if r.seasonDiffers then
            out[#out + 1] = { text = "    |cffa0a0a0this season|r",
                right = ("|cffa0a0a0%s  %s|r"):format(MF:Weight(r.season.w), self:ShortName(r.season.h)) }
        end
    end

    -- Other spots in this zone.
    local others = self:OtherSpots(key, mapID)
    if #others > 0 then
        out[#out + 1] = Blank()
        out[#out + 1] = Header("Other spots in " .. self:MapName(mapID))
        for _, o in ipairs(others) do
            local spotKey = o.key
            local k = self:King(spotKey)
            out[#out + 1] = { text = o.label, right = k
                and ("King %s (%s)"):format(self:ShortName(k.h), MF:Weight(k.w)) or "",
                onClick = function() self:PointToSpot(spotKey) end }
        end
    end
    return out
end

local BOUNTY_LABEL = { day = "Today", week = "This week", month = "This month" }
local BOUNTY_TAB = { day = "Daily", week = "Weekly", month = "Monthly" }
local bountyView = "day"

local function BountyLines(self)
    local out = {}
    local kind = bountyView
    local _, id, zone = self:Bounty(kind)

    local subs = { current = kind, onPick = function(k) bountyView = k end }
    for _, k in ipairs(self.BOUNTY_KINDS) do
        subs[#subs + 1] = { key = k, label = BOUNTY_TAB[k] }
    end

    if not id then
        out[#out + 1] = { text = "|cff858585Nothing on offer this time.|r" }
        return out, nil, subs
    end

    out[#out + 1] = Header(BOUNTY_LABEL[kind])
    -- The fish name plus a place is too long for a row that also has
    -- text on the right, so where it is gets a line of its own.
    out[#out + 1] = { text = self:BountyTitle(kind),
        icon = self:BountyIcon(kind),
        right = "resets in " .. self:FormatSpan(self:BountyTimeLeft(kind)), group = true }
    out[#out + 1] = { text = zone
        and ("    in |cffffd100" .. zone .. "|r")
        or "    |cff858585anywhere on the realm|r" }

    local best = self:MyBountyBest(kind)
    out[#out + 1] = { text = self:BountyFormat(kind) == "top3" and "Your haul" or "Your best",
        right = best > 0
            and self:BountyScoreText(kind, best, nil, self:BountySpecimenStatus(kind,self.me,nil,best))
            or "-", tooltip = self:BountyFormat(kind)=="top3" and { "The specimen icon on a haul total means it contains at least one specimen." } or nil }
    local progress = self:BountyProgressText(kind)
    if progress then out[#out + 1] = { text = "Haul progress", right = progress } end
    if self:BountyFormat(kind) == "top3" then
        local haul = self:BountyHaul(kind)
        for slot = 1, 3 do
            local fish = haul[slot]
            local specimen=fish and fish.specimen
            if fish and specimen==nil then specimen=self:GuaranteedSpecimenWeight(id,fish.weight) end
            out[#out + 1] = { text = slot .. ". " .. self:FishName(id), icon = self:FishIcon(id),
                right = fish and (self:Weight(fish.weight) .. (fish.legacy and not specimen and "  (grade not saved)"
                    or (specimen and ("  " .. STAR .. " " .. self.C.spec .. "Specimen|r") or Graded(self, id, fish.weight, 0)))) or "Not caught yet",
                tooltip = fish and fish.legacy and not specimen and { "This older haul saved its weight only. Specimen status cannot be recovered safely." } or nil,
                group = true }
        end
    end
    out[#out + 1] = Blank()
    out[#out + 1] = Header("Standings")
    local standings = self:BountyStandings(kind)
    if #standings == 0 then
        out[#out + 1] = { text = "|cff858585No entries yet.|r" }
    end
    -- One cadence to a page now, so the whole board fits.
    local place, last = 0, nil
    for i, e in ipairs(standings) do
        if e.weight ~= last then place, last = i, e.weight end
        local colour = self:IsMe(e.name) and "|cff3ee63e" or ""
        out[#out + 1] = {
            text = ("%s%d. %s"):format(colour, place, self:ShortName(e.name)),
            right = self:BountyScoreText(kind, e.weight, nil, e.specimen),
            tooltip = self:BountyFormat(kind)=="top3" and { "Combined weight of three fish. The specimen icon means at least one fish was a specimen." } or nil,
        }
    end

    out[#out + 1] = Blank()
    local rewards = self.BOUNTY_REWARDS[kind]
    out[#out + 1] = { text = "Podium XP (1st / 2nd / 3rd)",
        right = ("%d XP / %d XP / %d XP"):format(rewards[1], rewards[2], rewards[3]) }
    local reward = self:BountyRewardResult(kind)
    if reward then
        out[#out + 1] = Blank()
        out[#out + 1] = Header("Your previous result")
        local ordinal = ({ "1st", "2nd", "3rd" })[reward.place] or ("#" .. reward.place)
        out[#out + 1] = { text = ordinal .. " place", right = "+" .. reward.xp .. " XP",
            featured = true, group = true }
        self:NoteRows(out, self:BountyTitle(kind, reward.period))
    elseif self:IsBountyRewardPeriod(kind, self:BountyPeriod(kind) - 1)
        and self:MyBountyBest(kind, self:BountyPeriod(kind) - 1) > 0
        and ((self.cdb.profile.bountyRewardThrough or {})[kind] or -1) < self:BountyPeriod(kind) - 1 then
        out[#out + 1] = { text = "Previous result", right = "Syncing standings...", featured = true }
    end

    -- Who took the last one. The objective is worked out from the period
    -- rather than remembered, so this costs nothing to show for a bounty
    -- nobody on this client entered.
    local won = self:BountyWinner(kind)
    if won then
        out[#out + 1] = Blank()
        out[#out + 1] = Header("Previous winner")
        local mine = self:IsMe(won.name)
        out[#out + 1] = {
            text = ("%s%s|r"):format(mine and "|cff3ee63e" or "|cffffd100",
                self:ShortName(won.name)),
            icon = self:BountyIcon(kind, won.period),
            right = self:BountyScoreText(kind, won.score, won.period, won.specimen),
            tooltip = self:BountyFormat(kind,won.period)=="top3" and { "Combined weight of the winning three-fish haul. The icon means it contains a specimen; older unknown hauls stay unmarked unless the total exceeds the maximum for three ordinary fish." } or nil,
        }
        self:NoteRows(out, self:BountyTitle(kind, won.period))
        if won.zone then
            out[#out + 1] = { text = ("    |cff858585in %s|r"):format(won.zone) }
        end
    end

    out[#out + 1] = Blank()
    out[#out + 1] = { text = "Rules and rewards", right = "Hover for details",
        tooltip = { self:BountyRule(kind), "Ties share a place and reward (1st, 1st, 3rd).",
            "Rewards use known shared standings after a two-minute sync window and 30 seconds without changes.",
            kind == "day" and "Daily objectives are drawn for your faction." or "The objective's location restrictions apply to every catch." } }
    return out, nil, subs
end

-- A log is worth keeping only if it tells you something. The history adds up
-- what you've done, and can turn itself inside out to rank the waters you
-- fish by how they actually treat you.
local historyView = "sessions" -- or "spots"


local function Hours(seconds)
    seconds = math.floor(seconds or 0)
    local h, m = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

local function PerHour(amount, seconds)
    if (seconds or 0) < 60 then return nil end
    return amount / (seconds / 3600)
end

-- Everything we've logged, added up, plus the days worth remembering.
local function Totals(self)
    local t = { sessions = 0, fish = 0, weight = 0, seconds = 0, specimens = 0, value = 0,
        matches = 0, wins = 0 }
    for _, h in ipairs(self.cdb.history) do
        if h.solo then
            t.sessions = t.sessions + 1
            t.fish = t.fish + (h.count or 0)
            t.weight = t.weight + (h.total or 0)
            t.seconds = t.seconds + (h.duration or 0)
            t.specimens = t.specimens + (h.specimens or 0)
            t.value = t.value + (h.value or 0)
            if not t.mostFish or (h.count or 0) > (t.mostFish.count or 0) then t.mostFish = h end
            if not t.biggest or (h.biggest or 0) > (t.biggest.biggest or 0) then t.biggest = h end
        elseif not h.season then
            t.matches = t.matches + 1
            if h.place == 1 then t.wins = t.wins + 1 end
        end
    end
    return t
end

local function SummaryLines(self, out)
    local t = Totals(self)
    if t.sessions == 0 then return end

    out[#out + 1] = Header("Your log so far")
    out[#out + 1] = { text = "Time fished",
        right = ("%s over %d %s"):format(Hours(t.seconds), t.sessions,
            t.sessions == 1 and "session" or "sessions") }
    out[#out + 1] = { text = "Caught", right = ("%d fish, %s"):format(t.fish, MF:Weight(t.weight)) }

    local rate = PerHour(t.fish, t.seconds)
    if rate then
        local money = self:ValueEnabled() and PerHour(t.value, t.seconds)
        out[#out + 1] = { text = "Catch rate",
            right = ("%.1f fish an hour%s"):format(rate,
                money and (", " .. self:ShortMoney(money) .. " an hour") or "") }
    end
    if t.specimens > 0 then
        out[#out + 1] = { text = "Specimens landed", right = STAR .. " " .. t.specimens }
    end
    if self:ValueEnabled() and t.value > 0 then
        out[#out + 1] = { text = "Your haul was worth", right = self:ShortMoney(t.value) }
    end
    if t.matches > 0 then
        out[#out + 1] = { text = "Matches fished", right = ("%d, won %d"):format(t.matches, t.wins) }
    end

    if t.biggest and (t.biggest.biggest or 0) > 0 then
        out[#out + 1] = Blank()
        out[#out + 1] = Header("Days to remember")
        out[#out + 1] = { text = "Biggest catch",
            right = ("%s %s"):format(MF:Weight(t.biggest.biggest), t.biggest.biggestName or "fish") }
        out[#out + 1] = { text = ("|cffa0a0a0    at %s, %s|r"):format(t.biggest.sub or "?",
            date("%d %b", t.biggest.when)) }
    end
    if t.mostFish and (t.mostFish.count or 0) > 0 then
        out[#out + 1] = { text = "Best haul",
            right = ("%d fish, %s"):format(t.mostFish.count, MF:Weight(t.mostFish.total or 0)) }
        out[#out + 1] = { text = ("|cffa0a0a0    at %s, %s|r"):format(t.mostFish.sub or "?",
            date("%d %b", t.mostFish.when)) }
    end
    out[#out + 1] = Blank()
end

-- The same sessions, gathered by the water they were fished in.
-- Ranked by what each water actually gave you, which means reading the
-- per-spot tally a log now keeps rather than the one water it started at.
-- Logs written before that existed only know where they began, so they
-- count as one spot - the best that can honestly be said of them.
local function WaterLines(self, out)
    local spots, list = {}, {}

    local function Spot(name)
        local spot = spots[name]
        if not spot then
            spot = { name = name, sessions = 0, fish = 0, weight = 0, seconds = 0,
                specimens = 0, value = 0, best = 0 }
            spots[name] = spot
            list[#list + 1] = spot
        end
        return spot
    end

    for _, h in ipairs(self.cdb.history) do
        -- Test build: only waters a fish was landed in (Session.lua, FishedWaters).
        local waters = h.solo and h.spots and h.spots[1] and (self.FishedWaters and self:FishedWaters(h.spots) or h.spots)
        if waters then
            for _, e in ipairs(waters) do
                local spot = Spot(e.name)
                spot.sessions = spot.sessions + 1
                spot.fish = spot.fish + (e.count or 0)
                spot.weight = spot.weight + (e.total or 0)
                spot.seconds = spot.seconds + math.floor(e.seconds or 0)
                spot.specimens = spot.specimens + (e.specimens or 0)
                spot.value = spot.value + (e.value or 0)
                if (e.biggest or 0) > spot.best then
                    spot.best, spot.bestName = e.biggest, e.biggestName
                end
            end
        elseif h.solo and h.sub and (h.count or 0) > 0 then -- test build: same rule for a log with no per-water tally
            local spot = Spot(h.sub)
            spot.sessions = spot.sessions + 1
            spot.fish = spot.fish + (h.count or 0)
            spot.weight = spot.weight + (h.total or 0)
            spot.seconds = spot.seconds + (h.duration or 0)
            spot.specimens = spot.specimens + (h.specimens or 0)
            spot.value = spot.value + (h.value or 0)
            if (h.biggest or 0) > spot.best then
                spot.best, spot.bestName = h.biggest, h.biggestName
            end
        end
    end
    if #list == 0 then
        out[#out + 1] = { text = "|cff858585No solo logs yet.|r" }
        return
    end

    -- Best first, but a spot you fished for two minutes hasn't earned a place
    -- above one you've spent hours at.
    table.sort(list, function(a, b)
        local x, y = PerHour(a.fish, a.seconds), PerHour(b.fish, b.seconds)
        if x and y then return x > y end
        if x or y then return x ~= nil end
        return a.fish > b.fish
    end)

    out[#out + 1] = Header("Your waters, best first")
    for _, spot in ipairs(list) do
        local rate = PerHour(spot.fish, spot.seconds)
        out[#out + 1] = {
            text = spot.name,
            right = ("%d fish in %s%s"):format(spot.fish, Hours(spot.seconds),
                rate and ("  -  %.1f/hr"):format(rate) or ""),
        }
        local money = self:ValueEnabled() and PerHour(spot.value, spot.seconds)
        local detail = {}
        if spot.best > 0 then
            detail[#detail + 1] = ("best %s %s"):format(MF:Weight(spot.best), spot.bestName or "fish")
        end
        if spot.specimens > 0 then detail[#detail + 1] = STAR .. " " .. spot.specimens end
        if money then detail[#detail + 1] = self:ShortMoney(money) .. " an hour" end
        if #detail > 0 then
            out[#out + 1] = { text = "|cffa0a0a0    " .. table.concat(detail, "   ") .. "|r" }
        end
    end
end

local function SessionLines(self, out)
    for i = #self.cdb.history, 1, -1 do
        local first = #out + 1
        local h = self.cdb.history[i]
        local when = date("%d %b %H:%M", h.when)
        if h.season then
            out[#out + 1] = { text = ("|cffffd100%s ended|r"):format(self:SeasonName(h.season)),
                right = ("%d XP, %d records, %d Kings"):format(h.xp or 0, h.records or 0, h.kings or 0) }
        elseif h.solo and not (self.db.settings.historyHideEmpty and (h.count or 0) == 0 and (h.finds or 0) == 0) then
            out[#out + 1] = { text = when, right = h.sub or "?",
                tooltip = { "Click to preview and copy this fishing report." },
                onClick = function() self:OpenSessionReport(h) end }
            out[#out + 1] = { text = "Catch", columns = { tostring(h.count or 0), MF:Weight(h.total or 0),
                self:ValueEnabled() and self:ShortMoney(h.value or 0) or "-", self:FormatClock(h.duration or 0) },
                tooltip = { "Recorded fishing time: " .. self:FormatClock(h.duration or 0),
                    h.elapsed and ("Elapsed session time: " .. self:FormatClock(h.elapsed))
                        or "Elapsed time was not saved for this older session." } }
            if h.outcomes then self:NoteRows(out,self:CastOutcomeSummary(h)) end
            if (h.finds or 0) > 0 then
                self:NoteRows(out, "Finds: " .. (self:FindItemsText(h.findItems) or self:FindsText(h.finds)))
            end
            -- The bit you'd actually tell someone about.
            if (h.biggest or 0) > 0 then
                self:NoteRows(out, ("Best: %s %s%s"):format(MF:Weight(h.biggest),
                    h.biggestName or "fish",
                    (h.specimens or 0) > 0 and ("   " .. STAR .. " " .. h.specimens) or ""))
            end
        elseif not h.solo then
            out[#out + 1] = { text = ("%s  Match @ %s"):format(when, h.sub),
                right = h.place and ("%s of %d"):format(h.place == 1 and "|cffffd1001st|r" or ("#" .. h.place),
                    h.players or 0) or "" }
        end
        if out[first] then out[first].group = true end
    end
end

local function HistoryLines(self)
    local out = {}
    if #self.cdb.history == 0 then
        return { { text = "|cff858585No logs or matches yet. Cast a line and this fills in.|r" } }
    end

    local actions = { { label = historyView == "spots" and "Sessions" or "By spot",
        onClick = function()
            historyView = historyView == "spots" and "sessions" or "spots"
            self:RedrawJournal()
        end } }

    SummaryLines(self, out)
    if historyView == "spots" then
        WaterLines(self, out)
    else
        actions[#actions + 1] = { label = self.db.settings.historyHideEmpty and "Show empty" or "Hide empty",
            onClick = function()
                self.db.settings.historyHideEmpty = not self.db.settings.historyHideEmpty
                self:RedrawJournal()
            end }
        out[#out + 1] = Header("Every session")
        out[#out + 1] = { text = "Session / catch", columns = { "Fish", "Weight", "Value", "Fished" }, header = true }
        SessionLines(self, out)
    end
    actions[#actions+1] = { label = "Reports", onClick = function() self:OpenAnglingTools("reports") end }
    return out, actions
end

local TABS = {
    { key = "journal", label = "Journal", build = JournalLines },
    { key = "records", label = "Records", build = RecordsLines },
    { key = "bounty",  label = "Bounty",  build = BountyLines },
    { key = "history", label = "History", build = HistoryLines },
}

-- Other files add tabs while loading (before the window is built).
function MF:AddJournalTab(key, label, build)
    table.insert(TABS, { key = key, label = label, build = build })
end

-- On MF so a test can build every tab and check nothing runs off the edge.
MF.JOURNAL_TABS = TABS

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local MAX_ACTIONS = 5
local MAX_SUBS, SUB_W = 4, 96
local WIN_W = 600          -- room for names and aligned statistic columns
local DEFAULT_W, DEFAULT_H = 600, 120 + ROWS * 17
local MIN_W, MIN_H = 360, 360
local narrow = false
local LIST_TOP = 68
local TAB_W, TAB_STEP = 88, 94
local ROW_W = WIN_W - 56   -- leaves room for the scrollbar on the right

-- Notes that are longer than a row
--
-- The list scrolls by whole rows, so every row is one line of fixed height
-- and nothing wraps: a sentence longer than the panel is simply cut off
-- mid-word, with no sign that it was. Anything explanatory therefore has to
-- be broken up before it gets here.
--
-- Measured rather than counted, because "about ninety characters" is wrong
-- the moment somebody writes a line full of capitals or a long guild name.
local measure

local function Fits(text)
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        measure:Hide()
    end
    -- Colour codes are bytes that take no room, so they don't count.
    measure:SetText((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    local width = measure:GetStringWidth()
    return type(width) ~= "number" or width <= ROW_W - 10
end

-- Whichever highlight is still open at the end of a line, if any. A row
-- that breaks in the middle of one has to close it and the next row has to
-- open it again, or the colour either bleeds or vanishes at the seam.
local function OpenColour(s)
    local open
    for pos, tok in s:gmatch("()(|[cr])") do
        open = tok == "|c" and s:sub(pos, pos + 9) or nil
    end
    return open
end

-- Appends `text` to `out` as however many rows it takes, split on words.
function MF:NoteRows(out, text, colour)
    colour = colour or "|cff858585"
    local line, carry
    local function Flush()
        out[#out + 1] = { text = colour .. (carry or "") .. line .. "|r" }
        carry = OpenColour((carry or "") .. line)
    end
    for word in tostring(text or ""):gmatch("%S+") do
        if not line then
            line = word
        elseif Fits((carry or "") .. line .. " " .. word) then
            line = line .. " " .. word
        else
            Flush()
            line = word
        end
    end
    if line then Flush() end
    return out
end
local TEXT_W = 280         -- label width when a row also has text on the right

-- The two widths a row's text has to live inside, so the test that checks
-- nothing overruns is measuring against the same numbers the drawing does.
MF.ROW_WIDTH, MF.LABEL_WIDTH = ROW_W, TEXT_W

local function Render()
    local context = MF.recapActive and "recap" or win.tab
    local offsets = MF.db.settings.journalOffsets or {}
    if offsetTab ~= context then
        if offsetTab then offsets[offsetTab] = offset end
        offset = tonumber(offsets[context]) or 0
        offsetTab = context
    end
    local stacked = narrow and not (win.tab == "journal" and journalView == "here")
    local max = math.max(0, #lines - shown)
    offset = math.max(0, math.min(offset, max))
    MF.db.settings.journalOffsets = MF.db.settings.journalOffsets or {}
    MF.db.settings.journalOffsets[context] = offset
    local groups, group = {}, 0
    for n, entry in ipairs(lines) do
        if entry.header then group = 0 end
        if entry.group then group = group + 1 end
        groups[n] = group
    end
    local function Reading(text)
        return ((text or ""):gsub("|cff858585", MF.C.label))
    end
    local columnLabels = {}
    for n = 1, offset do
        local entry = lines[n]
        if entry.header then columnLabels = entry.columns or {} end
    end
    for i, row in ipairs(win.rows) do
        local line = lines[offset + i]
        if line and line.header then columnLabels = line.columns or {} end
        row.tooltipValues = {}
        if line and line.columns and not line.header then
            for n, value in ipairs(line.columns) do
                if value ~= "" then
                    row.tooltipValues[#row.tooltipValues + 1] = (columnLabels[n] and columnLabels[n] ~= ""
                        and (columnLabels[n] .. ": ") or "") .. value
                end
            end
        end
        if line then
            row.text:SetText(Reading(line.text))
            row.right:SetText(Reading(line.right))
            row.icon:SetShown(line.icon ~= nil)
            if line.icon then row.icon:SetTexture(line.icon) end
            row.text:ClearAllPoints()
            row.text:SetPoint(stacked and "TOPLEFT" or "LEFT", line.icon and 20 or 0, stacked and -1 or 0)
            row.text:SetWidth(stacked and (ROW_W - (line.icon and 20 or 0)) or (line.columns and (ROW_W - 274 - 24)
                or ((line.right and line.right ~= "") and (narrow and ROW_W * 0.55 - 20 or TEXT_W) or ROW_W)))
        else
            row.text:SetText("")
            row.right:SetText("")
            row.icon:Hide()
        end
        row.onClick = line and line.onClick
        row.help = line and line.tooltip
        row:EnableMouse(line ~= nil)
        if not row.onClick then row.highlight:Hide() end
        -- Shade a whole record/session group, including continuation rows.
        local group = groups[offset + i] or 0
        row.shade:SetShown(line ~= nil and not line.header and line.text ~= ""
            and (line.mine or line.featured or group % 2 == 1) or false)
        row.shade:SetColorTexture(1, 0.82, 0, line and (line.mine or line.featured) and 0.10 or 0.035)
        row.rule:SetShown(line and line.header or false)
        row.text:SetTextColor(1, 1, 1)
        row.text:SetFontObject(line and line.featured and "GameFontNormal" or "GameFontHighlightSmall")
        local columns = line and line.columns
        -- Existing text stays available to the simulator; columns take its
        -- place visually without changing the data or click handlers.
        row.right:ClearAllPoints()
        row.right:SetPoint(stacked and "BOTTOMRIGHT" or "RIGHT", 0, stacked and 2 or 0)
        row.right:SetWidth(stacked and ROW_W or (narrow and ROW_W * 0.45 - 8 or (line and line.columns and 274 or ROW_W - TEXT_W - 8)))
        row.right:SetWordWrap(false)
        row.right:SetShown(narrow or not columns)
        if narrow and columns then row.right:SetText(Reading(table.concat(columns, "  "))) end
        local widths = line and line.columnWidths or { 70, 70, 46, 88 }
        local edge = 0
        for n = 4, 1, -1 do
            local cell = row.columns[n]
            cell:ClearAllPoints()
            cell:SetPoint("RIGHT", -edge, 0)
            cell:SetWidth(math.max(1, widths[n] - 8))
            edge = edge + widths[n]
            cell:SetShown(columns ~= nil and not narrow and widths[n] > 0)
            cell:SetText(Reading(columns and columns[n]))
            cell:SetTextColor(line and line.header and 0.63 or 1,
                line and line.header and 0.63 or 1, line and line.header and 0.63 or 1)
        end
    end
    win.scrollHint:SetText(#lines > shown and ("%d-%d of %d"):format(
        offset + 1, math.min(#lines, offset + shown), #lines) or "")
    MF:Fire("TFL_JOURNAL_DRAWN")

    if win.scroll then
        local max = math.max(0, #lines - shown)
        win.scroll:SetMinMaxValues(0, max)
        win.scroll:SetShown(max > 0)
        if math.floor(win.scroll:GetValue() + 0.5) ~= offset then
            win.scroll:SetValue(offset)
        end
    end
end

-- Where the list starts, and how much of it there is. Called on every
-- redraw because a tab with sub-tabs and one without want different
-- answers, and the journal switches between them.
local function LayoutRows(withSubs)
    ROW_H = narrow and not (win.tab == "journal" and journalView == "here") and 34 or (MF.recapActive and 22 or 17)
    local summary = lines.summary ~= nil
    local search = win.tab == "journal" and journalView ~= "here" and journalView ~= "tools" and journalView ~= "goals" and not MF.recapActive
    local searchHeight = search and 56 or 0
    local heroHeight = lines.hero and 112 or 0
    local top = -(LIST_TOP + heroHeight + searchHeight + (withSubs and SUB_H or 0) + (summary and 68 or 0))
    shown = math.max(1, math.min(ROW_POOL, math.floor((win:GetHeight() + top - 52) / ROW_H)))
    win.summary:SetPoint("TOPLEFT", 20, -(LIST_TOP + heroHeight + searchHeight))
    win.recapHero:SetShown(lines.hero ~= nil)
    if lines.hero then
        win.recapHero:SetPoint("TOPLEFT", 20, -LIST_TOP)
        win.recapHero:SetWidth(WIN_W - 40)
        win.recapHero.title:SetText(narrow and lines.hero.shortTitle or lines.hero.title)
        win.recapHero.title:SetWidth(WIN_W - 128)
        win.recapHero.note:SetText(narrow and lines.hero.shortSubtitle or lines.hero.subtitle)
        win.recapHero.note:SetWidth(WIN_W - 128)
        win.recapHero.status:SetText(lines.hero.status)
    end
    win.searchBar:SetShown(search)
    win.searchBar:SetPoint("TOPLEFT", 20, -LIST_TOP)
    win.searchBar:SetWidth(WIN_W - 40)
    win.searchBar.edit:SetWidth(WIN_W - 144)
    for _, button in ipairs(win.searchBar.filters) do
        button:SetEnabled(button.filter ~= searchFilter)
    end
    win.summary:SetShown(summary)
    win.empty:ClearAllPoints()
    win.empty:SetPoint("TOP", 0, -(LIST_TOP + 12))
    win.empty:SetHeight(math.min(180, win:GetHeight() - LIST_TOP - 72))
    for i, cell in ipairs(win.summary.cells) do
        local stat = lines.summary and lines.summary[i]
        cell.value:SetText(stat and stat.value or "")
        cell.label:SetText(stat and (narrow and (stat.shortLabel or ({ "Species", "Specimens", "Haul" })[i]) or stat.label) or "")
    end
    win.scroll:SetPoint("TOPRIGHT", -12, top - 4)
    for i, row in ipairs(win.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 20, top - (i - 1) * ROW_H)
        row:SetSize(ROW_W, ROW_H)
        row.icon:ClearAllPoints()
        row.icon:SetPoint(narrow and "TOPLEFT" or "LEFT", 0, narrow and -1 or 0)
        row:SetShown(i <= shown)
    end
end

-- subs: { current = key, { key, label }, ... }, centred under the tabs.
local function ShowSubs(self, subs)
    local count = subs and #subs or 0
    local span = count * SUB_W + math.max(0, count - 1) * 6
    for i, b in ipairs(win.subs) do
        local sub = subs and subs[i]
        b:SetShown(sub ~= nil)
        if sub then
            b:SetText(sub.label)
            b:SetHeight(19)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", (WIN_W - span) / 2 + (i - 1) * (SUB_W + 6), -(LIST_TOP - 4))
            -- Same trick the tab row uses: the one you are reading is
            -- the one you cannot click, and it is painted as current.
            b:SetEnabled(sub.key ~= subs.current)
            b:SetScript("OnClick", function()
                subs.current = sub.key
                if subs.onPick then subs.onPick(sub.key) end
                offset = 0
                self:RedrawJournal()
            end)
        end
    end
    LayoutRows(count > 0)
end

local function ShowActions(actions)
    local count = actions and #actions or 0
    local width = count > 0 and math.min(90, (WIN_W - 56 - (count - 1) * 6) / count) or 90
    for i, button in ipairs(win.actions) do
        local a = actions and actions[i]
        button:SetShown(a ~= nil)
        if a then
            button:SetWidth(width)
            button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", 16 + (i - 1) * (width + 6), 12)
            button:SetText(a.label)
            button:SetScript("OnClick", a.onClick)
        end
    end
end

local function RefreshNow(self)
    if not win or not win:IsShown() then return end
    WIN_W = win:GetWidth()
    narrow = WIN_W < 520
    ROW_H = narrow and 34 or 17
    ROW_W = WIN_W - 56
    TEXT_W = math.max(100, math.min(280, ROW_W * 0.52))
    MF.ROW_WIDTH, MF.LABEL_WIDTH = ROW_W, TEXT_W
    LIST_TOP = narrow and 124 or 68
    win.rank:ClearAllPoints()
    win.rank:SetPoint("TOPRIGHT", -36, narrow and -38 or -18)
    win.rank:SetWidth(WIN_W - (narrow and 52 or 240))
    win.rank:SetJustifyH("RIGHT")
    win.rank:SetWordWrap(false)
    local across = narrow and 3 or #TABS
    local tabWidth = (WIN_W - 32 - (across - 1) * 6) / across
    for i, tab in ipairs(TABS) do
        tab.button:SetWidth(tabWidth)
        tab.button:ClearAllPoints()
        tab.button:SetPoint("TOPLEFT", 16 + ((i - 1) % across) * (tabWidth + 6),
            -(narrow and 62 or 38) - math.floor((i - 1) / across) * 28)
    end
    win.summary:SetWidth(WIN_W - 40)
    for i, cell in ipairs(win.summary.cells) do
        local x = 12 + (i - 1) * ((WIN_W - 64) / 3)
        cell.value:ClearAllPoints()
        cell.value:SetPoint("TOPLEFT", x, -8)
        cell.value:SetWidth((WIN_W - 64) / 3 - 8)
        cell.label:ClearAllPoints()
        cell.label:SetPoint("TOPLEFT", x, -32)
        cell.label:SetWidth((WIN_W - 64) / 3 - 8)
    end
    win.empty:SetWidth(WIN_W - 40)
    win.empty.note:SetWidth(WIN_W - 60)
    local xp = self.cdb.profile.xp
    local _, name, nextXP = self:RankFor(xp)
    win.rank:SetText(("|cffffd100%s|r  -  %d XP%s"):format(name, xp,
        nextXP and ("  (%d to next rank)"):format(nextXP - xp) or ""))
    local actions, subs
    for _, tab in ipairs(TABS) do
        tab.button:SetEnabled(tab.key ~= win.tab)
        if tab.key == win.tab then lines, actions, subs = tab.build(self) end
    end
    if self.recapActive then lines, actions, subs = self:RecapLines() end
    self.journalPage = { lines = lines, actions = actions, subs = subs }
    self.db.settings.journalTab = win.tab -- reopen where you left off
    self.db.settings.journalView = journalView
    ShowSubs(self, subs)
    ShowActions(actions)
    Render()
    local empty = lines.empty
    win.empty:SetShown(empty ~= nil)
    if empty then
        win.empty.title:SetText(empty.title)
        win.empty.note:SetText(empty.note)
        win.empty.action:SetText(actions[1].label)
        win.empty.action:SetScript("OnClick", actions[1].onClick)
        for _, row in ipairs(win.rows) do row:Hide() end
        win.actions[1]:Hide()
    end
end

-- Redraw straight away (after a click), rather than on the next refresh.
function MF:RedrawJournal()
    RefreshNow(self)
end

-- Data changes can arrive in bursts (item info, record syncs), so refreshes
-- are coalesced into one rebuild shortly after the first request.
local REFRESH_DELAY = 0.2
local refreshPending = false

function MF:RefreshJournal()
    if not win or not win:IsShown() or refreshPending then return end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        RefreshNow(self)
    end)
end

function MF:ToggleJournal(tab)
    if not win:IsShown() and (not tab or tab == "journal") and self.ShouldOpenRecap and self:ShouldOpenRecap() then
        self:ShowRecap()
        return
    end
    if win:IsShown() and (not tab or tab == win.tab) then
        win:Hide()
        return
    end
    if tab then
        SwitchTab(self, tab)
    end
    win:Show()
    RefreshNow(self)
end

-- Show a tab, opening the window if needed (never closes it).
function MF:OpenJournal(tab)
    if tab ~= "journal" then self.recapActive = false end
    SwitchTab(self, tab)
    win:Show()
    RefreshNow(self)
end

MF:Command("here", "Progress", "/tfl here - fishing goals at this water", MF.OpenFishingHere)

local hereRefresh = 0
MF:OnTick(function(self)
    if (journalView ~= "here" and journalView ~= "tools") or not win or not win:IsShown() or win.tab ~= "journal" then return end
    hereRefresh = hereRefresh + 1
    if hereRefresh >= 5 then hereRefresh = 0 self:RefreshJournal() end
end)
MF:On("ZONE_CHANGED", MF.RefreshJournal)
MF:On("ZONE_CHANGED_NEW_AREA", MF.RefreshJournal)
MF:On("TFL_CATCH", MF.RefreshJournal)

MF:On("GET_ITEM_INFO_RECEIVED", MF.RefreshJournal)

MF:Command({ "journal", "j" }, "Progress",
    "/tfl journal - Angler's Journal (also: records, bounty, history tabs)",
    function(self) self:ToggleJournal("journal") end)
MF:Command("history", "Progress", nil, function(self) self:ToggleJournal("history") end)

MF:On("TFL_INIT", function(self)
    win = self:CreatePanel("TheFishingLogJournal", DEFAULT_W, DEFAULT_H,
        { strata = "DIALOG", movable = true, escCloses = true,
          title = ("Angler's Journal  |cffa0a0a0v%s|r"):format(self.VersionLabel()),
          close = true, fill = self.FILL_READING })
    win:SetPoint("CENTER")
    -- The stock background texture has transparent pixels even when its
    -- tint is opaque. A solid inset surface keeps the world out of the text.
    win.readingSurface = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    win.readingSurface:SetPoint("TOPLEFT", 7, -7)
    win.readingSurface:SetPoint("BOTTOMRIGHT", -7, 7)
    win.readingSurface:SetColorTexture(unpack(self.FILL_READING))
    -- Cards.lua anchors itself beside this, and asking the addon beats
    -- reading the frame's global name back out of _G.
    self.journalWindow = win
    win.tab = self.db.settings.journalTab or "journal"
    local savedView = self.db.settings.journalView
    if savedView == "zones" or savedView == "fish" or savedView == "cards" or savedView == "here" then journalView = savedView end
    offset = math.max(0, tonumber((self.db.settings.journalOffsets or {})[win.tab]) or 0)

    win.rank = self:CreateText(win, "GameFontHighlightSmall", "TOPRIGHT", -36, -18)

    win.summary = CreateFrame("Frame", nil, win)
    win.summary:SetSize(WIN_W - 40, 56)
    win.summary:SetPoint("TOPLEFT", 20, -68)
    local summaryFill = win.summary:CreateTexture(nil, "BACKGROUND")
    summaryFill:SetAllPoints()
    summaryFill:SetColorTexture(1, 1, 1, 0.045)
    win.summary.cells = {}
    for i = 1, 3 do
        local cell = {}
        local x = 12 + (i - 1) * ((WIN_W - 64) / 3)
        cell.value = self:CreateText(win.summary, "GameFontHighlightLarge", "TOPLEFT", x, -8)
        cell.label = self:CreateText(win.summary, "GameFontHighlightSmall", "TOPLEFT", x, -32)
        cell.label:SetTextColor(0.63, 0.63, 0.63)
        win.summary.cells[i] = cell
    end
    win.summary:Hide()

    win.recapHero = CreateFrame("Frame", nil, win)
    win.recapHero:SetSize(WIN_W - 40, 100)
    local heroFill = win.recapHero:CreateTexture(nil, "BACKGROUND")
    heroFill:SetAllPoints()
    heroFill:SetColorTexture(1, 0.82, 0, 0.055)
    local heroIcon = win.recapHero:CreateTexture(nil, "ARTWORK")
    heroIcon:SetSize(48, 48)
    heroIcon:SetPoint("TOPLEFT", 14, -12)
    heroIcon:SetTexture("Interface\\Icons\\Trade_Fishing")
    heroIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    win.recapHero.title = self:CreateText(win.recapHero, "GameFontNormalLarge", "TOPLEFT", 76, -12)
    win.recapHero.title:SetJustifyH("LEFT")
    win.recapHero.note = self:CreateText(win.recapHero, "GameFontHighlightSmall", "TOPLEFT", 76, -36)
    win.recapHero.note:SetJustifyH("LEFT")
    win.recapHero.note:SetSpacing(2)
    win.recapHero.status = self:CreateText(win.recapHero, "GameFontDisableSmall", "BOTTOMLEFT", 14, 10)
    win.recapHero:EnableMouse(true)
    win.recapHero:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Your fishing recap")
        GameTooltip:AddLine("Compared with your last saved visit. Peer information may be incomplete or arrive later; missing data is never treated as a loss.", 0.63, 0.63, 0.63, true)
        GameTooltip:Show()
    end)
    win.recapHero:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.recapHero:Hide()

    win.searchBar = CreateFrame("Frame", nil, win)
    win.searchBar:SetSize(WIN_W - 40, 52)
    local find = self:CreateText(win.searchBar, "GameFontHighlightSmall", "TOPLEFT", 0, -5)
    find:SetText("Find")
    win.searchBar.edit = CreateFrame("EditBox", nil, win.searchBar, "InputBoxTemplate")
    win.searchBar.edit:SetSize(WIN_W - 144, 22)
    win.searchBar.edit:SetPoint("TOPLEFT", 40, 0)
    win.searchBar.edit:SetAutoFocus(false)
    win.searchBar.edit:SetMaxLetters(120)
    win.searchBar.edit:SetScript("OnTextChanged", function(edit)
        self:SetJournalSearch(edit:GetText(), searchFilter)
    end)
    win.searchBar.edit:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    win.searchBar.edit:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() self:RedrawJournal() end)
    win.searchBar.edit:SetScript("OnEnter", function(edit)
        GameTooltip:SetOwner(edit, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Search fish names or zones")
        GameTooltip:Show()
    end)
    win.searchBar.edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.searchBar.clear = self:CreateButton(win.searchBar, "Clear", 48, function()
        searchFilter = "all"
        win.searchBar.edit:SetText("")
        self:SetJournalSearch("", "all")
        self:RedrawJournal()
    end)
    win.searchBar.clear:SetPoint("TOPRIGHT", 0, 0)
    win.searchBar.filters = {}
    for i, option in ipairs({ { "all", "All" }, { "missing", "Missing" }, { "specimens", "Specimens" } }) do
        local key = option[1]
        local button = self:CreateButton(win.searchBar, option[2], 86, function()
            self:SetJournalSearch(win.searchBar.edit:GetText(), key)
            self:RedrawJournal()
        end)
        button.filter = key
        button:SetPoint("TOPLEFT", (i - 1) * 92, -26)
        win.searchBar.filters[i] = button
    end
    win.searchBar:Hide()

    win.empty = CreateFrame("Frame", nil, win)
    win.empty:SetSize(360, 180)
    win.empty:SetPoint("CENTER", 0, 20)
    local emptyIcon = win.empty:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetSize(48, 48)
    emptyIcon:SetPoint("TOP")
    emptyIcon:SetTexture("Interface\\Icons\\Trade_Fishing")
    emptyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    win.empty.title = self:CreateText(win.empty, "GameFontNormalLarge", "TOP", 0, -64)
    win.empty.note = self:CreateText(win.empty, "GameFontHighlight", "TOP", 0, -94)
    win.empty.note:SetWidth(340)
    win.empty.note:SetJustifyH("CENTER")
    win.empty.note:SetTextColor(0.63, 0.63, 0.63)
    win.empty.action = self:CreateButton(win.empty, "Post event", 140)
    win.empty.action:SetPoint("BOTTOM", 0, 0)
    win.empty:Hide()

    for i, tab in ipairs(TABS) do
        tab.button = self:CreateButton(win, tab.label, TAB_W, function()
            self.recapActive = false
            SwitchTab(self, tab.key)
            RefreshNow(self)
        end)
        tab.button:SetPoint("TOPLEFT", 16 + (i - 1) * TAB_STEP, -38)
    end

    -- A row of sub-tabs, for a tab with parallel views rather than
    -- toggles. The bounty tab has three of them and all three on one
    -- page was twenty-odd rows before anybody had entered anything.
    win.subs = {}
    for i = 1, MAX_SUBS do
        local b = self:CreateButton(win, "", SUB_W)
        b:Hide()
        win.subs[i] = b
    end

    win.actions = {}
    for i = 1, MAX_ACTIONS do
        local button = self:CreateButton(win, "", 90)
        button:SetPoint("BOTTOMLEFT", 16 + (i - 1) * 96, 12)
        button:Hide()
        win.actions[i] = button
    end

    win.rows = {}
    for i = 1, ROW_POOL do
        local row = CreateFrame("Frame", nil, win)
        row:SetSize(ROW_W, ROW_H)
        row:SetPoint("TOPLEFT", 20, -68 - (i - 1) * ROW_H)
        -- Clickable rows (the noticeboard) light up on hover.
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.highlight:Hide()
        row.shade = row:CreateTexture(nil, "BACKGROUND")
        row.shade:SetAllPoints()
        row.shade:Hide()
        row.rule = row:CreateTexture(nil, "BACKGROUND")
        row.rule:SetHeight(1)
        row.rule:SetPoint("BOTTOMLEFT", 0, -1)
        row.rule:SetPoint("BOTTOMRIGHT", 0, -1)
        row.rule:SetColorTexture(0.44, 0.37, 0.22, 0.35)
        row.rule:Hide()
        row:SetScript("OnEnter", function(r)
            if r.onClick then r.highlight:Show() end
            if r.text:GetText() and r.text:GetText() ~= "" then
                GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
                GameTooltip:AddLine(r.text:GetText() or "", 1, 1, 1, true)
                if #(r.tooltipValues or {}) == 0 then GameTooltip:AddLine(r.right:GetText() or "", 1, 1, 1, true) end
                for _, value in ipairs(r.tooltipValues or {}) do
                    GameTooltip:AddLine(value, 1, 1, 1, true)
                end
                for _, value in ipairs(r.help or {}) do GameTooltip:AddLine(value, 1, 1, 1, true) end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(r) r.highlight:Hide() GameTooltip:Hide() end)
        row:SetScript("OnMouseUp", function(r) if r.onClick then r.onClick() end end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(15, 15)
        row.icon:SetPoint("LEFT")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT")
        row.text:SetJustifyH("LEFT")
        row.text:SetWidth(TEXT_W)
        row.text:SetWordWrap(false)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT")
        row.right:SetJustifyH("RIGHT")
        row.columns = {}
        local widths = { 70, 70, 46, 88 }
        local edge = 0
        for n = 4, 1, -1 do
            local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetPoint("RIGHT", -edge, 0)
            cell:SetWidth(widths[n] - 8)
            cell:SetJustifyH("RIGHT")
            cell:SetWordWrap(false)
            row.columns[n] = cell
            edge = edge + widths[n]
        end
        win.rows[i] = row
    end

    win.scrollHint = self:CreateText(win, "GameFontDisableSmall", "BOTTOMRIGHT", -20, 40)

    -- A plain slider, not UIPanelScrollBarTemplate: that template expects to
    -- live inside a scroll frame and errors when it doesn't.
    local scroll = CreateFrame("Slider", nil, win)
    scroll:SetOrientation("VERTICAL")
    scroll:SetWidth(12)
    scroll:SetPoint("TOPRIGHT", -12, -88)
    scroll:SetPoint("BOTTOMRIGHT", -12, 60)
    -- Draw the thumb ourselves; the stock knob textures aren't on every client.
    scroll:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = scroll:GetThumbTexture()
    thumb:SetSize(10, 26)
    thumb:SetColorTexture(0.75, 0.75, 0.75, 0.9)
    scroll:SetMinMaxValues(0, 1)
    scroll:SetValueStep(1)
    scroll:SetObeyStepOnDrag(true)
    local track = scroll:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", 3, 0)
    track:SetPoint("BOTTOMRIGHT", -3, 0)
    track:SetColorTexture(1, 1, 1, 0.07)
    -- A vertical slider starts at the top, so the value is the row offset.
    scroll:SetScript("OnValueChanged", function(self, value)
        local wanted = math.floor(value + 0.5)
        if wanted ~= offset then
            offset = wanted
            Render()
        end
    end)
    win.scroll = scroll

    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Render()
    end)

    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(MIN_W, MIN_H, 1400, 1600)
    else win:SetMinResize(MIN_W, MIN_H) win:SetMaxResize(1400, 1600) end
    win.resize = CreateFrame("Button", nil, win)
    win.resize:SetSize(20, 20)
    win.resize:SetPoint("BOTTOMRIGHT", -5, 5)
    local grip = win.resize:CreateTexture(nil, "ARTWORK")
    grip:SetAllPoints()
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    win.resize:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then win:StartSizing("BOTTOMRIGHT") end
    end)
    local function FinishResize()
        win:StopMovingOrSizing()
        self.db.settings.journalWidth = win:GetWidth()
        self.db.settings.journalHeight = win:GetHeight()
        RefreshNow(self)
    end
    win.resize:SetScript("OnMouseUp", FinishResize)
    win:HookScript("OnHide", FinishResize)
    win:SetScript("OnSizeChanged", function() RefreshNow(self) end)
    win:SetSize(math.max(MIN_W, math.min(1400, tonumber(self.db.settings.journalWidth) or DEFAULT_W)),
        math.max(MIN_H, math.min(1600, tonumber(self.db.settings.journalHeight) or DEFAULT_H)))
end)

MF:Command("journalsize", "Other", "/tfl journalsize - reset the journal size", function(self)
    self.db.settings.journalWidth, self.db.settings.journalHeight = nil, nil
    win:SetSize(DEFAULT_W, DEFAULT_H)
    RefreshNow(self)
end)

function MF:ResetJournalState()
    self.finderFish,self.finderMissing,self.finderSelected=nil,nil,nil
    self.finderSkill,self.finderLevel,self.finderCurrentZone,self.finderReadyOnly=nil,nil,nil,nil
    self.albumFinds=nil
    journalView,expanded,searchText,searchFilter="zones",nil,"","all"
    historyView,bountyView="sessions","day"
    offset,offsetTab=0,nil
    if win then
        win.tab="journal"
        win.searchBar.edit:SetText("")
        win:SetSize(DEFAULT_W,DEFAULT_H)
    end
end
