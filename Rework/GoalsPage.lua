-- Goals (1.1.4): up to three fishing goals, each with how far along it is and where to fish it.
-- Left: your goals with a bar each, goals suggested from your own log, more to pick from (bounty
-- podiums, your zone, your skill), and the goals you've finished. Right: every fish as an icon,
-- marked caught, missing or specimen, with a filter and a search; pick one for its goals.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.GoalsPage = P

local GOLD = "|cffffd100"
local GREEN = "|cff3ee63e"
local MUTED = "|cff8f8f8f"
local WHITE = "|cffffffff"
local RIGHT_W = 380
local MIN_RIGHT_W = 260 -- test build: the fish picker narrows to this so the goals beside it can be read
local LIST_GAP = 20     -- between the goals list and the picker; the list's scroll bar sits in it
local ICON_STEP = 34
local ICONS_MAX = 16
local GROUP_RANK = { ready = 1, higher = 2, unknown = 3, below = 4, enemy = 5 }

local function Prefs()
    local cdb = MF.cdb
    if type(cdb.goalsPage) ~= "table" then cdb.goalsPage = {} end
    return cdb.goalsPage
end

local function Fold(s)
    local R = ns.RealmPage
    if R and R.Fold then return R.Fold(s) end
    return (s or ""):lower()
end

local function Full() return #MF:FishingGoals() >= (MF.MAX_FISHING_GOALS or 3) end

-- The kind a goal is tracked with: a grade for a grade goal, a bounty's cadence for a podium
local function Track(g)
    local ok = MF:TrackFishingGoal(g.mode, g.id, g.mode == "grade" and g.grade or g.kind, { fish = g.fish, spot = g.spot })
    P:Refresh()
    return ok
end

-- Where to fish for a fish: the zone that suits you best among those it lives in
function P:Where(id)
    local best, rank
    for _, w in ipairs(self.zones or {}) do
        for _, f in ipairs(w.fish or {}) do
            if f == id then
                local r = w.here and 0 or (GROUP_RANK[w.group] or 6)
                if not rank or r < rank then best, rank = w.zone, r end
                break
            end
        end
    end
    if not best then
        local f = MF.FISH[id]
        best = f and f.zones and f.zones[1]
    end
    return best, rank
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function Tip(frame)
    frame:HookScript("OnEnter", function(self)
        if not self.tipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle, 1, 0.82, 0)
        for _, line in ipairs(self.tipLines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(self) W:HideTip(self) end)
end

-- Tooltip lines, leaving out the ones that don't apply
local function Lines(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and v ~= "" then out[#out + 1] = v end
    end
    return out
end

local function IsFish(id) return type(id) == "number" and (MF.FISH[id] or (MF.TROPHY and MF.TROPHY[id])) and true or false end

local function Highlight(r)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
end

local function GoalRow()
    local r = CreateFrame("Button")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.3)
    Highlight(r)
    r.icon = W:Icon(r, 26)
    r.icon:SetPoint("TOPLEFT", 8, -8)
    r.clear = W:Button(r, "Clear", 56, 20, function(b)
        local index = b.row and b.row.index
        if index then MF:ClearFishingGoal(index) P:Refresh() end
    end, "Clear this goal", "Stop working on it. Nothing you've caught is lost.")
    r.clear.row = r
    r.clear:SetPoint("TOPRIGHT", -8, -6)
    r.title = W:Label(r, "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0)
    -- Test build: the title runs up to the Clear button. The short progress ("2/5", "0.80 lb to
    -- go") used to sit between them and left the title about 80 wide; it is on the bottom line now.
    r.title:SetPoint("RIGHT", r.clear, "LEFT", -8, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.bar = W:Bar(r, 200, 10)
    r.bar:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -5)
    r.bar:SetPoint("RIGHT", -8, 0)
    r.right = W:Label(r, "GameFontNormalSmall")
    r.right:SetPoint("TOPRIGHT", r.bar, "BOTTOMRIGHT", 0, -4)
    r.right:SetJustifyH("RIGHT")
    r.sub = W:Label(r, "GameFontDisableSmall")
    r.sub:SetPoint("TOPLEFT", r.bar, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    Tip(r)
    r:SetScript("OnClick", function(self) if self.go then self.go() end end)
    return r
end

P.GoalRow = GoalRow -- for the tests

local function SuggestRow()
    local r = CreateFrame("Button")
    Highlight(r)
    r.icon = W:Icon(r, 22)
    r.icon:SetPoint("LEFT", 8, 0)
    r.track = W:Button(r, "Track", 64, 20, function(b)
        local g = b.row and b.row.goal
        if g then W:Sound("click") Track(g) end
    end)
    r.track.row = r
    r.track:SetPoint("RIGHT", -8, 0)
    r.title = W:Label(r, "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.title:SetPoint("RIGHT", r.track, "LEFT", -8, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.sub = W:Label(r, "GameFontDisableSmall")
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r.track, "LEFT", -8, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    Tip(r)
    r:SetScript("OnClick", function(self)
        local g = self.goal
        if g and g.mode ~= "skill" and IsFish(g.id) then MF:ShowCard(g.id) end
    end)
    return r
end

local function DoneRow()
    local r = CreateFrame("Frame")
    r.icon = W:Icon(r, 18)
    r.icon:SetPoint("LEFT", 10, 0)
    r.title = W:Label(r, "GameFontHighlightSmall")
    r.title:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.right = W:Label(r, "GameFontDisableSmall")
    r.right:SetPoint("RIGHT", -10, 0)
    return r
end

local function FishHeadRow()
    local r = CreateFrame("Button")
    r.icon = W:FramedIcon(r, 36)
    r.icon:SetPoint("TOPLEFT", 10, -8)
    r.name = W:Label(r, "GameFontNormalLarge")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 12, -1)
    r.name:SetPoint("RIGHT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.line1 = W:Label(r, "GameFontHighlightSmall")
    r.line1:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.line1:SetPoint("RIGHT", -8, 0)
    r.line1:SetJustifyH("LEFT")
    r.line2 = W:Label(r, "GameFontDisableSmall")
    r.line2:SetPoint("TOPLEFT", r.line1, "BOTTOMLEFT", 0, -3)
    r.line2:SetPoint("RIGHT", -8, 0)
    r.line2:SetJustifyH("LEFT")
    r.tipTitle = "Open its card"
    Tip(r)
    r:SetScript("OnClick", function(self) if self.fishID then MF:ShowCard(self.fishID) end end)
    return r
end

local function IconsRow()
    local r = CreateFrame("Frame")
    r.buttons = {}
    for i = 1, ICONS_MAX do
        local b = CreateFrame("Button", nil, r)
        b:SetSize(30, 30)
        b.icon = W:Icon(b, 28)
        b.icon:SetPoint("CENTER")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.ring = b:CreateTexture(nil, "OVERLAY")
        b.ring:SetPoint("TOPLEFT", -3, 3)
        b.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        b.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.ring:SetBlendMode("ADD")
        b.star = b:CreateTexture(nil, "OVERLAY")
        b.star:SetSize(12, 12)
        b.star:SetPoint("TOPRIGHT", 3, 3)
        b.star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        Tip(b)
        b:SetScript("OnClick", function(self)
            W:Sound("click")
            P.selected = self.fishID
            MF.goalFishSelected = self.fishID
            P:Refresh()
        end)
        r.buttons[i] = b
    end
    return r
end

local function Make(kind)
    if kind == "goal" then return GoalRow() end
    if kind == "suggest" then return SuggestRow() end
    if kind == "done" then return DoneRow() end
    if kind == "fishhead" then return FishHeadRow() end
    if kind == "icons" then return IconsRow() end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, kind == "note" and "GameFontDisableSmall" or "GameFontNormal")
    fr.right = W:Label(fr, "GameFontDisableSmall")
    fr.right:SetPoint("TOPRIGHT", -8, -11)
    fr.text:SetPoint("TOPLEFT", 8, kind == "note" and -4 or -10)
    if kind == "note" then
        fr.text:SetPoint("TOPRIGHT", -8, -4)
    else
        -- Test build: a heading stops at the note on its right instead of running under it.
        fr.text:SetPoint("RIGHT", fr.right, "LEFT", -6, 0)
        fr.text:SetWordWrap(false)
    end
    fr.text:SetJustifyH("LEFT")
    if kind == "section" then
        fr.rule = W:Divider(fr, 100)
        fr.rule:SetPoint("BOTTOMLEFT", 0, 1)
        fr.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    end
    return fr
end

local function FillGoal(fr, it)
    local g = it.g
    local p = MF:GoalProgress(g)
    local ended = MF:GoalEnded(g)
    fr.index = it.index
    fr.icon:SetTexture(MF:GoalIcon(g))
    fr.title:SetText(MF:GoalTitle(g))
    fr.right:SetText(ended and MUTED .. "ended|r" or (GOLD .. (p.short or "") .. "|r"))
    fr.bar:Set(p.value or 0, p.max or 1, "")
    if ended then fr.bar:SetColor(0.4, 0.4, 0.4) else fr.bar:SetColor(1, 0.75, 0.1) end
    fr.sub:SetText((p.text or "") .. (it.where and ("   " .. MUTED .. "Fish it in|r " .. WHITE .. it.where .. "|r") or ""))
    fr.go = it.go
    fr.tipTitle = MF:GoalTitle(g)
    fr.tipLines = Lines(p.text, it.where and ("Fish it in " .. it.where .. ".") or nil, it.goTip)
end

local function FillSuggest(fr, it)
    local g = it.g
    fr.goal = g
    fr.icon:SetTexture(MF:GoalIcon(g))
    fr.title:SetText(it.title or MF:GoalTitle(g))
    fr.sub:SetText(it.sub or g.reason or "")
    local tracked = MF:GoalTracked(g)
    fr.track:SetText(tracked and "Tracked" or "Track")
    if tracked or Full() then fr.track:Disable() else fr.track:Enable() end
    fr.tipTitle = MF:GoalTitle(g)
    fr.tipLines = Lines(it.sub or g.reason, Full() and not tracked and "You're working on three goals: clear one to make room." or nil,
        g.mode ~= "skill" and IsFish(g.id) and "Click for its card." or nil)
end

local function FillIcons(fr, it)
    local journal = MF.cdb.profile.journal or {}
    for i, b in ipairs(fr.buttons) do
        local id = it.ids[i]
        if id then
            local j = journal[id]
            b:ClearAllPoints()
            b:SetPoint("LEFT", fr, "LEFT", 8 + (i - 1) * ICON_STEP, 0)
            b.fishID = id
            b.icon:SetTexture(MF:FishIcon(id))
            b.icon:SetDesaturated(j == nil)
            b.icon:SetAlpha(j and 1 or 0.55)
            b.star:SetShown(j ~= nil and (j.s or 0) > 0)
            b.ring:SetShown(P.selected == id)
            b.tipTitle = MF:FishName(id)
            local state = not j and "Not caught yet." or (j.s or 0) > 0 and ("Specimen caught. Your best " .. MF:Weight(j.b) .. ".")
                or ("Caught. Your best " .. MF:Weight(j.b) .. (MF:GradeText(id, j.b) or "") .. ".")
            b.tipLines = { state, "Click to see its goals." }
            b:Show()
        else
            b:Hide()
        end
    end
end

local function Fill(fr, it)
    if it.kind == "goal" then FillGoal(fr, it)
    elseif it.kind == "suggest" then FillSuggest(fr, it)
    elseif it.kind == "done" then
        fr.icon:SetTexture(MF:GoalIcon(it.g))
        fr.title:SetText(GREEN .. "Done|r  " .. MF:GoalTitle(it.g))
        fr.right:SetText(it.g.completed and date("%d %b", it.g.completed) or "")
    elseif it.kind == "fishhead" then
        fr.fishID = it.id
        fr.icon.icon:SetTexture(MF:FishIcon(it.id))
        fr.name:SetText(MF:FishName(it.id) or "")
        fr.line1:SetText(it.line1 or "")
        fr.line2:SetText(it.line2 or "")
        fr.tipLines = { "Click for its card: weights, grades and where it lives." }
    elseif it.kind == "icons" then FillIcons(fr, it)
    else
        fr.text:SetText(it.text or "")
        fr.right:SetText(it.right or "")
    end
end

-- ---------------------------------------------------------------------------
-- The left side: your goals, suggestions, more goals, finished
-- ---------------------------------------------------------------------------
local KIND_LABEL = { day = "Daily", week = "Weekly", month = "Monthly" }

local function GoalAction(g, where)
    if g.mode == "zone" then
        return function()
            MF:OpenAnglingTools("finder")
            local F = ns.FinderPage
            if F and F.search then F.text = g.id F.search:SetText(g.id) if F.Refresh then F:Refresh() end end
        end, "Click to find it in Find waters."
    elseif g.mode == "podium" or g.mode == "haul" then
        return function() MF:OpenJournal("bounty") end, "Click for the Bounty tab."
    elseif g.mode == "skill" then
        return function() MF:OpenAnglingTools("finder") end, "Click for Find waters: where your skill lands fish."
    end
    return function() MF:ShowCard(g.id) end, "Click for its card."
end

function P:LeftItems()
    local items = {}
    local goals = MF:FishingGoals()
    items[#items + 1] = { kind = "section", h = 32, text = "Your goals", right = ("%d of %d"):format(#goals, MF.MAX_FISHING_GOALS or 3) }
    if #goals == 0 then
        local text = "Pick up to three: track a suggestion below, or choose a fish on the right. "
            .. "Goals come from your catches, with no extra XP or weight bonuses."
        items[#items + 1] = { kind = "note", h = self:NoteHeight(text, self.leftW), text = text }
    end
    for i, g in ipairs(goals) do
        local where
        if g.mode ~= "skill" and g.mode ~= "podium" and g.mode ~= "haul" and IsFish(g.id) then
            where = g.mode == "best" and MF:SpotName(g.spot) or self:Where(g.id)
        end
        local go, goTip = GoalAction(g)
        items[#items + 1] = { kind = "goal", h = 58, g = g, index = i, where = where, go = go, goTip = goTip }
    end

    local suggestions = MF:SuggestedGoals(self.zones)
    if #suggestions > 0 then
        items[#items + 1] = { kind = "section", h = 32, text = "Suggested for you", right = "from your log" }
        for _, g in ipairs(suggestions) do items[#items + 1] = { kind = "suggest", h = 40, g = g } end
    end

    -- Every kind of goal not offered above: the bounty podiums, finishing your zone, your skill
    local more = {}
    local function Offer(g, sub)
        if not g or MF:GoalTracked(g) then return end
        for _, s in ipairs(suggestions) do if MF:SameGoal(s, g) then return end end
        more[#more + 1] = { kind = "suggest", h = 40, g = g, sub = sub }
    end
    for _, kind in ipairs(MF.BOUNTY_KINDS or {}) do
        local _, bid = MF:Bounty(kind)
        if bid then
            local g = MF:MakeFishingGoal("podium", nil, kind)
            Offer(g, g and ((MF:BountyTitle(kind) or "") .. "  " .. MUTED .. MF:FormatSpan(MF:BountyTimeLeft(kind)) .. " left|r"))
        end
    end
    local zone = MF:ZoneEnglish()
    local zg = zone and MF:MakeFishingGoal("zone", zone)
    if zg then
        local left = MF:GoalZoneLeft(zg)
        Offer(zg, ("Where you are: %d of %d still to catch."):format(left, #zg.fish))
    end
    local rank, cap = MF:FishingSkill()
    if rank and cap then
        local target = rank < cap and cap or (cap < 300 and cap + 75) or nil
        local sg = target and MF:MakeFishingGoal("skill", target)
        if sg then Offer(sg, rank < cap and ("%d to go."):format(target - rank) or (MF:SkillNextStep() or "")) end
    end
    if #more > 0 then
        items[#items + 1] = { kind = "section", h = 32, text = "More goals" }
        for _, it in ipairs(more) do items[#items + 1] = it end
    end

    local finished = MF:FinishedGoals()
    if #finished > 0 then
        items[#items + 1] = { kind = "section", h = 32, text = "Finished", right = #finished > 5 and "the last five" or nil }
        for i = 1, math.min(5, #finished) do items[#items + 1] = { kind = "done", h = 24, g = finished[i] } end
    end
    return items
end

-- ---------------------------------------------------------------------------
-- The right side: a fish, its goals, and every fish
-- ---------------------------------------------------------------------------
function P:FishIDs()
    local journal = MF.cdb.profile.journal or {}
    local filter = Prefs().filter or "need"
    local words = {}
    for w in Fold(self.text or ""):gmatch("%S+") do words[#words + 1] = w end
    local ids = {}
    for id, f in pairs(MF.FISH) do
        local j = journal[id]
        local keep = filter == "all" or (filter == "need" and not j) or (filter == "spec" and (not j or (j.s or 0) <= 0))
        if keep and #words > 0 then
            local hay = Fold((MF:FishName(id) or "") .. " " .. table.concat(f.zones or {}, " "))
            for _, w in ipairs(words) do if not hay:find(w, 1, true) then keep = false break end end
        end
        if keep then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return (MF:FishName(a) or "") < (MF:FishName(b) or "") end)
    return ids
end

-- The goals one fish offers, each as a row with a Track button
function P:FishChoices(id)
    local out = {}
    local journal = MF.cdb.profile.journal or {}
    local j = journal[id]
    local function Add(mode, kind, extra)
        local g = MF:MakeFishingGoal(mode, id, kind, extra)
        if g then out[#out + 1] = { kind = "suggest", h = 40, g = g, sub = MF:GoalProgress(g).text } end
    end
    if not j then Add("missing") end
    if MF.FISH[id] and not (j and (j.s or 0) > 0) then Add("specimen") end
    local idx = j and MF:GoalGradeIndex(id, j.b) or 0
    local names = MF.GOAL_GRADES
    if idx < 6 then
        local next = names[math.max(idx + 1, 4)]
        Add("grade", next)
        if next ~= "monster" then Add("grade", "monster") end
    end
    local spot = MF:CurrentSpot()
    if spot and spot.key and ((MF.cdb.records[spot.key] or {})[id]) then Add("best") end
    return out
end

function P:RightItems()
    local items = {}
    local id = self.selected
    if id and not MF.FISH[id] and not (MF.TROPHY and MF.TROPHY[id]) then id, self.selected = nil, nil end
    if id then
        local j = (MF.cdb.profile.journal or {})[id]
        local f = MF.FISH[id]
        local zones = {}
        for i = 1, math.min(3, f and f.zones and #f.zones or 0) do zones[i] = f.zones[i] end
        local where = self:Where(id)
        items[#items + 1] = { kind = "fishhead", h = 60, id = id,
            line1 = j and (("Your best %s%s%s"):format(MF:Weight(j.b), MF:GradeText(id, j.b) or "",
                (j.s or 0) > 0 and ("   " .. GOLD .. "specimen " .. MF:Weight(j.s) .. "|r") or "")) or (MUTED .. "Not caught yet|r"),
            line2 = (#zones > 0 and ("Lives in " .. table.concat(zones, ", ") .. ((f and f.zones and #f.zones > 3) and "..." or "")) or "")
                .. (where and ("   Best for you: " .. where) or "") }
        local choices = self:FishChoices(id)
        for _, c in ipairs(choices) do items[#items + 1] = c end
        if #choices == 0 then items[#items + 1] = { kind = "note", h = 24, text = "Every goal for this fish is done or tracked." } end
    else
        local text = "Choose a fish below for its goals: collect it, land a specimen, a monster, or beat your best here."
        items[#items + 1] = { kind = "note", h = self:NoteHeight(text, (self.rightW or RIGHT_W) - 24), text = text }
    end
    local ids = self:FishIDs()
    local filterName = ({ need = "still to catch", spec = "without a specimen", all = "in all" })[Prefs().filter or "need"]
    items[#items + 1] = { kind = "section", h = 32, text = "Fish", right = #ids .. " " .. (filterName or "") }
    if #ids == 0 then
        items[#items + 1] = { kind = "note", h = 24, text = (self.text or "") ~= "" and "No fish match that search." or "Nothing left here: try another filter." }
    end
    -- The panel's width is set by Layout, so this doesn't wait on the list being laid out
    local per = math.max(4, math.min(ICONS_MAX, math.floor(((self.rightW or RIGHT_W) - 40) / ICON_STEP)))
    for i = 1, #ids, per do
        local row = {}
        for k = i, math.min(#ids, i + per - 1) do row[#row + 1] = ids[k] end
        items[#items + 1] = { kind = "icons", h = 36, ids = row }
    end
    self.fishCount = #ids
    return items
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
local function Segments(parent, choices)
    local buttons = {}
    local prev
    for _, c in ipairs(choices) do
        local b = W:Button(parent, c[2], c[3], 22, function()
            Prefs().filter = c[1] ~= "need" and c[1] or nil
            P:Refresh()
        end, c[2], c[4])
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
        b.value = c[1]
        buttons[#buttons + 1] = b
        prev = b
    end
    function buttons.Update()
        local on = Prefs().filter or "need"
        for _, b in ipairs(buttons) do
            if b.value == on then b:LockHighlight() else b:UnlockHighlight() end
            b:SetAlpha(b.value == on and 1 or 0.55)
            local fs = b.GetFontString and b:GetFontString()
            if fs then
                if b.value == on then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.85, 0.85, 0.85) end
            end
        end
    end
    return buttons
end

function P:Build(frame)
    self.frame = frame
    local right = W:Panel(frame, 0.85)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -2)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 0)
    right:SetWidth(RIGHT_W)
    self.right = right
    right.title = W:Label(right, "GameFontNormal", "Pick a fish")
    right.title:SetPoint("TOPLEFT", 12, -10)
    self.search = W:Search(right, 170, function(text)
        if P.text == text then return end
        P.text = text
        P:Refresh()
    end, "Fish or zone")
    self.search:SetPoint("TOPRIGHT", -10, -6)
    self.filter = Segments(right, {
        { "need", "Still to catch", 112, "Fish you haven't caught yet." },
        { "spec", "No specimen", 100, "Fish you haven't landed a specimen of, caught or not." },
        { "all", "All", 60, "Every fish." } })
    self.filter[1]:SetPoint("TOPLEFT", 10, -34)
    right.list = W:VList(right, Make, Fill)
    right.list:SetPoint("TOPLEFT", 4, -62)
    right.list:SetPoint("BOTTOMRIGHT", -20, 6)

    self.list = W:VList(frame, Make, Fill)
    self.list:SetPoint("TOPLEFT", 0, -2)
    self.list:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -LIST_GAP, 0)
    self.measure = W:Label(frame, "GameFontDisableSmall") -- never shown: measures how tall a note is
    self.measure:Hide()
    frame:HookScript("OnSizeChanged", function() P:Layout() end) -- the journal redraws the page when a resize ends
    self:Layout()
end

-- Test build: the page was drawn for the full width of the window, with the fish picker fixed
-- at 380. Beside the character that left the goals about 150 wide: titles cut to "Lan...", the
-- opening note running over the next heading. The picker now takes 46% of the page, between
-- MIN_RIGHT_W and the 380 it always had, and its search box and filters are sized to match.
-- Returns true when the widths changed.
function P:Layout()
    local frame, right = self.frame, self.right
    if not (frame and right) then return end
    local page = frame:GetWidth() or 0
    if page <= 0 then return end
    local w = math.max(MIN_RIGHT_W, math.min(RIGHT_W, math.floor(page * 0.46)))
    local leftW = page - 4 - w - LIST_GAP
    if w == self.rightW and leftW == self.leftW then return end
    self.rightW, self.leftW = w, leftW
    right:SetWidth(w)
    self.search:SetWidth(math.max(110, math.min(170, w - 110)))
    local widths = w >= 300 and { 112, 100, 60 } or { 100, 94, 40 }
    for i, b in ipairs(self.filter) do b:SetWidth(widths[i]) end
    self.leftSig, self.rightSig = nil, nil -- note heights and icons per row depend on the widths
    return true
end

-- How tall a note needs to be to show all of `text` in a list `width` wide.
function P:NoteHeight(text, width)
    local room = math.max(60, (width or 300) - 16)
    local measure, height = self.measure, nil
    if measure and measure.GetStringHeight then
        measure:SetWidth(room)
        measure:SetText(text)
        height = measure:GetStringHeight()
    end
    if not height or height <= 0 then height = math.ceil(#text * 5.6 / room) * 11 end -- no measuring: estimate
    return math.max(24, math.ceil(height) + 10)
end

local function Signature(items)
    local sig = {}
    for _, it in ipairs(items) do
        sig[#sig + 1] = it.kind .. tostring(it.g and MF:GoalTitle(it.g) or it.id or "") .. (it.text or "")
            .. (it.ids and table.concat(it.ids, ",") or "")
    end
    return table.concat(sig, "\1")
end

function P:Refresh()
    if not self.list then return end
    if self.refreshing then return end
    self.refreshing = true
    local ok, err = pcall(function()
        self:Layout()
        MF:CheckFishingGoals()
        if MF.goalFishSelected and MF.goalFishSelected ~= self.selected then self.selected = MF.goalFishSelected end
        local okZones, zones = pcall(MF.FinderZones, MF)
        self.zones = okZones and zones or {}
        local left = self:LeftItems()
        local sig = Signature(left)
        self.list:SetItems(left, sig == self.leftSig)
        self.leftSig = sig
        local right = self:RightItems()
        sig = Signature(right)
        self.right.list:SetItems(right, sig == self.rightSig)
        self.rightSig = sig
        self.filter.Update()
    end)
    self.refreshing = nil
    if not ok then geterrorhandler()(err) end
end

J:AddPage({
    key = "goals",
    match = function(state)
        return not state.recap and state.tab == "journal" and state.view == "goals"
    end,
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function() P:Refresh() end,
    subheading = function() return "Fishing goals" end,
    count = function()
        local n = #MF:FishingGoals()
        return ("%d of %d goals"):format(n, MF.MAX_FISHING_GOALS or 3)
    end,
})
