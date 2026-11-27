-- Fishing goals: up to three at once, driven only by genuine local catches. No bonus XP or weight
-- modifiers: a goal is a reason to fish, not a scoring advantage.
--
-- A goal is one of:
--   missing   catch a fish you haven't had yet                     id = fish
--   specimen  land a specimen of a fish                            id = fish
--   grade     land one of a fish at a grade or better              id = fish, grade = "monster"...
--   best      beat your best of a fish at one water                id = fish, spot, best
--   zone      catch every fish listed for a zone                   id = zone name, fish = { ids }
--   skill     reach a fishing skill                                id = the skill
--   podium    make the top three of a bounty before it ends        kind = day/week/month, period
--   haul      (1.1.3) enter a three-fish haul; kept so saved ones still finish
-- Reaching one moves it to the finished list, with a pop-up; ended bounty goals wait to be cleared.
local _, MF = ...

local MAX_GOALS = 3
local DONE_KEPT = 12
MF.MAX_FISHING_GOALS = MAX_GOALS

local GRADE_ORDER = { tiddler = 1, small = 2, fair = 3, good = 4, cracker = 5, monster = 6 }
local GRADE_NAMES = { "tiddler", "small", "fair", "good", "cracker", "monster" }
MF.GOAL_GRADES = GRADE_NAMES
local KIND_LABEL = { day = "Daily", week = "Weekly", month = "Monthly" }

-- The goals you're working on. A 1.1.3 character's single goal comes across on first look.
function MF:FishingGoals()
    local cdb = self.cdb
    if type(cdb.fishingGoals) ~= "table" then
        cdb.fishingGoals = {}
        local old = cdb.fishingGoal
        if type(old) == "table" and old.mode then
            if old.completed then
                if type(cdb.goalsDone) ~= "table" then cdb.goalsDone = {} end
                table.insert(cdb.goalsDone, 1, old)
            else
                cdb.fishingGoals[1] = old
            end
        end
    end
    cdb.fishingGoal = nil
    return cdb.fishingGoals
end

function MF:FinishedGoals()
    if type(self.cdb.goalsDone) ~= "table" then self.cdb.goalsDone = {} end
    return self.cdb.goalsDone
end

function MF:HasFishingGoals() return #self:FishingGoals() > 0 end

-- The fish listed for a zone, by its English name
function MF:ZoneFishIDs(zone)
    local out = {}
    for id, f in pairs(self.FISH) do
        for _, z in ipairs(f.zones or {}) do
            if z == zone then out[#out + 1] = id break end
        end
    end
    table.sort(out)
    return out
end

local function Journal(self) return self.cdb.profile.journal or {} end

local function GradeIndex(self, id, weight)
    local short = weight and weight > 0 and self:WeightGradeShort(id, weight)
    return short and GRADE_ORDER[short]
end
MF.GoalGradeIndex = function(self, id, weight) return GradeIndex(self, id, weight) end

local function Same(a, b)
    return a.mode == b.mode and a.id == b.id and a.kind == b.kind and a.grade == b.grade
        and (a.mode ~= "best" or a.spot == b.spot)
end
MF.SameGoal = function(_, a, b) return Same(a, b) end

function MF:GoalTracked(goal)
    for _, g in ipairs(self:FishingGoals()) do if Same(g, goal) then return true end end
    return false
end

local function Refresh(self)
    if self.RefreshJournal then self:RefreshJournal() end
    if self.UpdateBoard then self:UpdateBoard() end
    if self.UpdateGoalTracker then self:UpdateGoalTracker() end
end

-- Make a goal from its parts; nil, and a reason, when it can't be one
function MF:MakeFishingGoal(mode, id, kind, extra)
    local goal = { mode = mode, started = GetServerTime() }
    local journal = Journal(self)
    if mode == "zone" then
        goal.id = id
        goal.fish = (extra and extra.fish) or (type(id) == "string" and self:ZoneFishIDs(id)) or {}
        if type(id) ~= "string" or #goal.fish == 0 then return nil, "There's no fish list for that zone." end
        if self:GoalZoneLeft(goal) == 0 then return nil, ("You've caught every fish listed for %s already."):format(id) end
    elseif mode == "skill" then
        goal.id = tonumber(id)
        local rank = self:FishingSkill()
        if not goal.id then return nil, "Pick a skill to reach." end
        if rank and rank >= goal.id then return nil, ("Your fishing skill is %d already."):format(rank) end
    elseif mode == "podium" or mode == "haul" then
        kind = kind or "day"
        local _, bid = self:Bounty(kind)
        if not bid then return nil, "There's no bounty to enter just now." end
        if mode == "haul" and self:BountyFormat(kind) ~= "top3" then return nil, "That bounty isn't a three-fish haul." end
        goal.kind, goal.period, goal.id = kind, self:BountyPeriod(kind), bid
        if mode == "podium" then
            local place = self:GoalPodium(kind)
            if place and place <= 3 then return nil, "You're on that bounty's podium already." end
        end
    else
        goal.id = tonumber(id)
        if not goal.id or (not self.FISH[goal.id] and not self.TROPHY[goal.id]) then return nil, "That isn't a fish The Fishing Log knows." end
        if mode == "missing" then
            if journal[goal.id] then return nil, "That card is already collected. Try a specimen or a grade goal." end
        elseif mode == "best" then
            goal.spot = (extra and extra.spot) or self:CurrentSpot().key
            local entry = (self.cdb.records[goal.spot] or {})[goal.id]
            goal.best = entry and entry.weight or 0
        elseif mode == "grade" then
            if not GRADE_ORDER[kind or ""] or not self:GradeLadder(goal.id) then return nil, "That fish has no grades to aim for." end
            goal.grade = kind
        elseif mode ~= "specimen" then
            return nil, "That isn't a kind of goal."
        end
    end
    return goal
end

-- Start working on a goal: false (and why, in chat) when it can't be added
function MF:TrackFishingGoal(mode, id, kind, extra)
    local goal, why = self:MakeFishingGoal(mode, id, kind, extra)
    if not goal then
        if why then self:Print(why) end
        return false
    end
    local goals = self:FishingGoals()
    if self:GoalTracked(goal) then
        self:Print("You're already working on that goal.")
        return false
    end
    if #goals >= MAX_GOALS then
        self:Print("You're working on three goals already. Clear one to make room.")
        return false
    end
    -- Where to fish it, as Find waters sees it now, for the goals tracker's line
    local page = self.Rework and self.Rework.GoalsPage
    if page and page.zones and type(goal.id) == "number" and goal.mode ~= "skill" and goal.mode ~= "best"
        and goal.mode ~= "podium" and goal.mode ~= "haul" then
        goal.where = page:Where(goal.id)
    end
    goals[#goals + 1] = goal
    self:Print("Fishing goal: " .. self:GoalTitle(goal))
    -- Some are already met the moment they're set (a haul you've entered, a skill you've passed)
    if not self:CheckFishingGoals() then Refresh(self) end
    return true
end

function MF:ClearFishingGoal(index)
    local goals = self:FishingGoals()
    if index then table.remove(goals, index)
    else
        for i = #goals, 1, -1 do goals[i] = nil end
        if self.ForgetFinishedFlashes then self:ForgetFinishedFlashes() end
    end
    Refresh(self)
end

-- ---------------------------------------------------------------------------
-- Words and progress
-- ---------------------------------------------------------------------------
function MF:GoalIcon(g)
    if g.mode == "zone" then return "Interface\\Icons\\INV_Misc_Map_01" end
    if g.mode == "skill" then return "Interface\\Icons\\Trade_Fishing" end
    if g.mode == "podium" or g.mode == "haul" then return self:BountyIcon(g.kind) end
    return self:FishIcon(g.id)
end

function MF:GoalTitle(g)
    local name = (g.mode ~= "zone" and g.mode ~= "skill" and g.mode ~= "podium" and g.mode ~= "haul")
        and (self:FishName(g.id) or "a fish") or nil
    if g.mode == "missing" then return "Collect " .. name end
    if g.mode == "specimen" then return "Land a specimen " .. name end
    if g.mode == "grade" then return ("Land a %s %s"):format(g.grade, name) end
    if g.mode == "best" then return "Beat your best " .. name end
    if g.mode == "zone" then return "Finish " .. tostring(g.id) end
    if g.mode == "skill" then return "Reach fishing skill " .. tostring(g.id) end
    if g.mode == "podium" then return ("Make the %s bounty podium"):format((KIND_LABEL[g.kind] or "bounty"):lower()) end
    if g.mode == "haul" then return (KIND_LABEL[g.kind] or "Bounty") .. " haul" end
    return "A fishing goal"
end

-- The text the boards show: your first goal, and how many more
function MF:FishingGoalText()
    local goals = self:FishingGoals()
    local g = goals[1]
    if not g then return "Choose a fishing goal" end
    local text = self:GoalTitle(g)
    if self:GoalEnded(g) then text = text .. " - ended, choose a new goal" end
    if #goals > 1 then text = text .. ("  |cffa0a0a0+%d|r"):format(#goals - 1) end
    return text
end

function MF:GoalEnded(g)
    return (g.mode == "podium" or g.mode == "haul") and g.period ~= self:BountyPeriod(g.kind)
end

-- just: a fish caught this moment, which the journal may not have taken in yet
function MF:GoalZoneLeft(g, just)
    local journal, left, names = Journal(self), 0, {}
    for _, id in ipairs(g.fish or {}) do
        if not journal[id] and id ~= just then
            left = left + 1
            names[#names + 1] = self:FishName(id)
        end
    end
    return left, names
end

-- Where you'd place in a bounty now, and the score to beat for third
function MF:GoalPodium(kind)
    local mine, others = 0, {}
    for _, e in ipairs(self:BountyStandings(kind) or {}) do
        if self:IsMe(e.name) then mine = math.max(mine, e.weight or 0)
        else others[#others + 1] = e.weight or 0 end
    end
    table.sort(others, function(a, b) return a > b end)
    local place
    if mine > 0 then
        place = 1
        for _, w in ipairs(others) do if w > mine then place = place + 1 end end
    end
    return place, mine, others[3] or 0
end

local function Score(self, kind, v) return self:BountyScoreText(kind, v, nil, false) end

-- How far along a goal is: { value, max, text, short }
function MF:GoalProgress(g)
    local W = function(v) return self:Weight(v) end
    local j = Journal(self)[g.id]
    local best = j and j.b or 0
    if g.mode == "missing" then
        return { value = 0, max = 1, text = "Not caught yet.", short = "to catch" }
    elseif g.mode == "specimen" then
        local f = self.FISH[g.id]
        if not f then return { value = 0, max = 1, text = best > 0 and ("Your best " .. W(best) .. ".") or "Not caught yet.", short = "" } end
        local lo, hi = self:SpecimenRange(f)
        local count = j and j.c or 0
        return { value = 0, max = 1,
            text = ("A chance on any catch where it's native, better in a frenzy. Specimens weigh %s to %s."):format(W(lo), W(hi)),
            short = count > 0 and (count == 1 and "1 caught" or (count .. " caught")) or "to catch" }
    elseif g.mode == "grade" then
        local ladder = self:GradeLadder(g.id) or {}
        local t = GRADE_ORDER[g.grade] or 1
        local from = ladder[t - 1] and ladder[t - 1].upTo or 0
        local now = GradeIndex(self, g.id, best)
        local p = { value = best, max = math.max(from, 0.01) }
        if best <= 0 then p.text, p.short = ("Not caught yet. A %s is over %s."):format(g.grade, W(from)), "to catch"
        else
            p.text = ("Your best %s, %s. A %s is over %s."):format(W(best), now and GRADE_NAMES[now] or "ungraded", g.grade, W(from))
            p.short = best < from and (W(from - best) .. " to go") or "keep fishing"
        end
        return p
    elseif g.mode == "best" then
        local here = ((self.cdb.records[g.spot] or {})[g.id] or {}).weight or 0
        return { value = 0, max = 1,
            text = ("Beat %s at %s."):format(W(g.best), self:SpotName(g.spot) or "that water"),
            short = "beat " .. W(g.best) }
    elseif g.mode == "zone" then
        local total = #(g.fish or {})
        local left, names = self:GoalZoneLeft(g)
        local shown = {}
        for i = 1, math.min(3, #names) do shown[i] = names[i] end
        return { value = total - left, max = math.max(total, 1),
            text = left == 0 and "Every fish caught." or ("Still to catch: %s%s."):format(table.concat(shown, ", "),
                #names > 3 and (" and " .. (#names - 3) .. " more") or ""),
            short = ("%d/%d"):format(total - left, total) }
    elseif g.mode == "skill" then
        local rank, cap = self:FishingSkill()
        rank = rank or 0
        local text = ("%d to go. Every fish you land can raise it."):format(math.max(0, g.id - rank))
        if cap and cap < g.id then text = (self:SkillNextStep() or ("Your skill stops at %d until you learn the next rank."):format(cap)) end
        return { value = rank, max = g.id, text = text, short = ("%d/%d"):format(rank, g.id) }
    elseif g.mode == "podium" or g.mode == "haul" then
        if self:GoalEnded(g) then return { value = 0, max = 1, text = "This bounty has ended.", short = "ended" } end
        local left = "  " .. self:FormatSpan(self:BountyTimeLeft(g.kind)) .. " left"
        if g.mode == "haul" then
            return { value = 0, max = 1, text = (self:BountyProgressText(g.kind) or "0/3 fish") .. left, short = self:BountyProgressText(g.kind) or "" }
        end
        local place, mine, third = self:GoalPodium(g.kind)
        local p = { value = mine, max = math.max(third, mine, 0.01) }
        if mine <= 0 then
            p.text = third > 0 and ("Not entered yet. Third place has %s."):format(Score(self, g.kind, third)) or "Not entered yet. Any entry makes the podium."
            p.short = "enter"
        else
            p.text = ("You're %s with %s; third has %s."):format(place and (place .. (place == 1 and "st" or place == 2 and "nd" or place == 3 and "rd" or "th")) or "-",
                Score(self, g.kind, mine), Score(self, g.kind, third))
            p.short = Score(self, g.kind, math.max(0, third - mine)) .. " behind"
        end
        p.text = p.text .. left
        return p
    end
    return { value = 0, max = 1, text = "", short = "" }
end

-- ---------------------------------------------------------------------------
-- Reaching a goal
-- ---------------------------------------------------------------------------
-- c is a catch; without one, only what can be read off where things stand
function MF:GoalReached(g, c)
    if g.mode == "missing" then return Journal(self)[g.id] ~= nil or (c ~= nil and c.itemID == g.id) end
    if g.mode == "zone" then return self:GoalZoneLeft(g, c and c.itemID) == 0 end
    if g.mode == "skill" then
        local rank = self:FishingSkill()
        return rank ~= nil and rank >= g.id
    end
    if g.mode == "podium" then
        if self:GoalEnded(g) then return false end
        local place = self:GoalPodium(g.kind)
        return place ~= nil and place <= 3
    end
    if g.mode == "haul" then return not self:GoalEnded(g) and (self:MyBountyBest(g.kind) or 0) > 0 end
    if not c or c.itemID ~= g.id then return false end
    if g.mode == "specimen" then return c.specimen and true or false end
    if g.mode == "best" then return c.spot ~= nil and c.spot.key == g.spot and (c.weight or 0) > g.best end
    if g.mode == "grade" then
        return c.specimen and true or (GradeIndex(self, g.id, c.weight) or 0) >= (GRADE_ORDER[g.grade] or 99)
    end
    return false
end

local COMPLETE_SOUND = SOUNDKIT and (SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.UI_EPICLOOT_TOAST)

-- Move anything reached to the finished list; returns what finished
function MF:CheckFishingGoals(c)
    local goals = self:FishingGoals()
    local done
    for i = #goals, 1, -1 do
        local g = goals[i]
        if self:GoalReached(g, c) then
            table.remove(goals, i)
            g.completed = GetServerTime()
            local finished = self:FinishedGoals()
            table.insert(finished, 1, g)
            while #finished > DONE_KEPT do table.remove(finished) end
            done = done or {}
            table.insert(done, 1, g)
        end
    end
    if not done then return nil end
    if self.GoalTrackerFinished then self:GoalTrackerFinished(done) end
    for _, g in ipairs(done) do
        local title = self:GoalTitle(g)
        self:Print("Fishing goal complete! " .. title)
        if self.Toast then
            self:Toast(self:GoalIcon(g), "GOAL COMPLETE", title,
                #goals < MAX_GOALS and "Pick another on the journal's Goals page." or nil, 1, 0.82, 0, COMPLETE_SOUND)
        end
    end
    Refresh(self)
    return done
end

MF:On("TFL_CATCH", function(self, c)
    if c.test or c.junk or #self:FishingGoals() == 0 then return end
    self:CheckFishingGoals(c)
    -- Bounty entries are settled by the catch's other listeners: look again once they have
    if C_Timer and #self:FishingGoals() > 0 then C_Timer.After(0, function() self:CheckFishingGoals() end) end
end)

MF:On("SKILL_LINES_CHANGED", function(self)
    local has
    for _, g in ipairs(self:FishingGoals()) do if g.mode == "skill" then has = true end end
    if has and C_Timer then C_Timer.After(0.5, function() self:CheckFishingGoals() end) end
end)

-- ---------------------------------------------------------------------------
-- Suggestions, from your own log
-- ---------------------------------------------------------------------------
-- zones is MF:FinderZones() when the caller already has it
function MF:SuggestedGoals(zones)
    local out = {}
    local journal = Journal(self)
    local function Add(g, reason)
        if g and not self:GoalTracked(g) then g.reason = reason out[#out + 1] = g end
    end
    if not zones and self.FinderZones then
        local ok, z = pcall(self.FinderZones, self)
        zones = ok and z or {}
    end
    zones = zones or {}

    -- A zone good for you with the fewest fish left
    local bestZone, seen = nil, {}
    for _, w in ipairs(zones) do
        if not seen[w.zone] and not w.enemy and (w.group == "ready" or w.here) then
            seen[w.zone] = true
            local g = self:MakeFishingGoal("zone", w.zone, nil, { fish = w.fish })
            if g then
                local left = self:GoalZoneLeft(g)
                if not bestZone or left < bestZone.left or (left == bestZone.left and w.here) then
                    bestZone = { goal = g, left = left }
                end
            end
        end
    end
    if bestZone then
        Add(bestZone.goal, ("%d fish left, in a zone good for your skill."):format(bestZone.left))
    end

    -- A specimen of the fish you catch most and have no specimen of: every catch is a chance
    local spec
    for id, j in pairs(journal) do
        if self.FISH[id] and (j.s or 0) <= 0 and (j.c or 0) > 0 then
            if not spec or j.c > spec.c or (j.c == spec.c and id < spec.id) then spec = { id = id, c = j.c } end
        end
    end
    if spec then
        Add(self:MakeFishingGoal("specimen", spec.id), ("You've caught %d with no specimen yet. Frenzies raise the chance."):format(spec.c))
    end

    -- The next grade up on a fish you've had
    local up
    for id, j in pairs(journal) do
        local idx = self.FISH[id] and GradeIndex(self, id, j.b)
        local ladder = idx and idx >= 3 and idx < 6 and self:GradeLadder(id)
        if ladder and ladder[idx] and ladder[idx].upTo and id ~= (spec and spec.id) then
            local r = j.b / ladder[idx].upTo
            if not up or r > up.r then up = { id = id, r = r, idx = idx, best = j.b, from = ladder[idx].upTo } end
        end
    end
    if up then
        Add(self:MakeFishingGoal("grade", up.id, GRADE_NAMES[up.idx + 1]),
            ("Your best is %s; a %s is over %s."):format(GRADE_NAMES[up.idx], GRADE_NAMES[up.idx + 1], self:Weight(up.from)))
    end

    -- A fish you haven't had, where you are or in the zone above
    local zone = self:ZoneEnglish()
    local here = {}
    for _, id in ipairs(self:ZoneFishIDs(zone or "")) do if not journal[id] then here[#here + 1] = id end end
    local where = zone
    if #here == 0 and bestZone then
        for _, id in ipairs(bestZone.goal.fish) do if not journal[id] then here[#here + 1] = id end end
        where = bestZone.goal.id
    end
    if #here > 0 then
        table.sort(here, function(a, b) return (self:FishName(a) or "") < (self:FishName(b) or "") end)
        Add(self:MakeFishingGoal("missing", here[1]), ("Still to catch, and it lives in %s."):format(where))
    end

    -- The bounty podium you're nearest
    local pod
    for _, kind in ipairs(self.BOUNTY_KINDS or {}) do
        local _, bid = self:Bounty(kind)
        if bid then
            local place, mine, third = self:GoalPodium(kind)
            if not place or place > 3 then
                local gap = third > 0 and math.max(0, third - mine) / third or 0
                if not pod or gap < pod.gap then pod = { kind = kind, gap = gap, mine = mine, third = third } end
            end
        end
    end
    if pod then
        Add(self:MakeFishingGoal("podium", nil, pod.kind), pod.mine > 0
            and ("%s behind third place."):format(Score(self, pod.kind, pod.third - pod.mine))
            or (pod.third > 0 and ("Not entered yet; third place has %s."):format(Score(self, pod.kind, pod.third))
                or "Fewer than three anglers have entered."))
    end

    -- Your next skill mark
    local rank, cap = self:FishingSkill()
    if rank and cap then
        if rank < cap then
            Add(self:MakeFishingGoal("skill", cap), ("%d to go, as high as your rank allows."):format(cap - rank))
        elseif cap < 300 then
            Add(self:MakeFishingGoal("skill", cap + 75), self:SkillNextStep() or "Learn the next rank first.")
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The line view (the 1.1.3 journal draws this; the Goals page has its own)
-- ---------------------------------------------------------------------------
function MF:FishingGoalLines()
    local out = { { text = "Your fishing goals", header = true } }
    local goals = self:FishingGoals()
    if #goals == 0 then out[#out + 1] = { text = "Choose a fishing goal", featured = true } end
    for i, g in ipairs(goals) do
        local index = i
        out[#out + 1] = { text = self:GoalTitle(g), icon = self:GoalIcon(g), right = self:GoalProgress(g).short,
            featured = true, onClick = function() self:ClearFishingGoal(index) end }
    end
    self:NoteRows(out, "Work on up to three goals at once. Progress comes from your catches, with no extra XP or weight bonuses.")
    local selected = self.goalFishSelected
    if selected then
        out[#out + 1] = { text = self:FishName(selected), icon = self:FishIcon(selected), header = true }
        for _, choice in ipairs({ { "missing", "Catch this fish" }, { "specimen", "Land a specimen" },
            { "grade", "Land a monster", "monster" }, { "best", "Beat my best at this water" } }) do
            out[#out + 1] = { text = choice[2], onClick = function() self:TrackFishingGoal(choice[1], selected, choice[3]) end }
        end
    end
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        local cadence = kind
        out[#out + 1] = { text = ("Make the %s bounty podium"):format((KIND_LABEL[kind] or kind):lower()),
            onClick = function() self:TrackFishingGoal("podium", nil, cadence) end }
    end
    out[#out + 1] = { text = "Choose a fish", header = true }
    local ids = {}
    for id in pairs(self.FISH) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return self:FishName(a) < self:FishName(b) end)
    for _, id in ipairs(ids) do
        local fish = id
        out[#out + 1] = { text = self:FishName(id), icon = self:FishIcon(id),
            onClick = function() self.goalFishSelected = fish self:OpenFishingGoal() end }
    end
    return out
end

MF:Command("goal", "Progress", "/tfl goal [clear] - choose up to three fishing goals", function(self, args)
    if args[1] == "clear" then self:ClearFishingGoal() else self:OpenFishingGoal() end
end)
