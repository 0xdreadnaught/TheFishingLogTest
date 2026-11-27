-- The goals tracker (1.1.4): your fishing goals on the right of the screen, in the quest
-- tracker's style, so they're in view while you fish.
--
-- The game's own tracker only lists real quests, so this is a frame of our own. It sits under
-- the quest tracker (Questie's, when Questie has taken it over) and follows it as it grows; or
-- wherever you Shift-drag it. A finished goal shows Done for a few seconds, then drops off.
-- Hidden in combat, when the setting is off, and when you have no goals.
local _, MF = ...

local WIDTH = 230
local DONE_SHOWN = 5        -- seconds a finished goal stays, marked Done
local FOLLOW_AFTER = 5      -- seconds after login to look for the quest tracker again
local MAX_LINES = 6         -- three goals, and up to three just finished

local frame
local finishedAt = {}       -- goal -> when it finished, while it's still shown as Done

-- The quest trackers we can sit under, the first one showing wins
local TRACKERS = { "Questie_BaseFrame", "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" }

local function Tracker()
    for _, name in ipairs(TRACKERS) do
        local f = rawget(_G, name)
        if type(f) == "table" and type(f.IsShown) == "function" then
            local ok, shown, bottom = pcall(function() return f:IsShown(), f:GetBottom() end)
            if ok and shown == true and type(bottom) == "number" then return f end
        end
    end
end

-- Where the line for a goal says to fish
function MF:GoalWhere(g)
    if g.mode == "best" then return self:SpotName(g.spot) end
    if g.where then return g.where end
    local f = type(g.id) == "number" and g.mode ~= "skill" and self.FISH[g.id]
    return f and f.zones and f.zones[1] or nil
end

-- The one line under a goal's name, as short as the tracker needs it
function MF:GoalTrackerLine(g)
    local p = self:GoalProgress(g)
    local where = self:GoalWhere(g)
    local inWhere = where and g.mode ~= "best" and (" in " .. where) or ""
    if g.mode == "missing" then return "Not caught yet" .. inWhere end
    if g.mode == "specimen" then return "A chance on every catch" .. inWhere end
    if g.mode == "grade" then
        if (p.value or 0) <= 0 then return "Not caught yet" .. inWhere end
        return ("%s / %s"):format(self:Weight(p.value), self:Weight(p.max))
    end
    if g.mode == "best" then return ("Beat %s at %s"):format(self:Weight(g.best or 0), where or "that water") end
    if g.mode == "zone" then return ("%d/%d fish caught"):format(p.value or 0, p.max or 0) end
    if g.mode == "skill" then return ("Skill %d/%d"):format(p.value or 0, p.max or 0) end
    if (g.mode == "podium" or g.mode == "haul") and self:GoalEnded(g) then return "Ended: clear it on the Goals page" end
    if g.mode == "podium" then
        local short = p.short == "enter" and "Not entered yet" or (p.short or "")
        return ("%s (%s left)"):format(short, self:FormatSpan(self:BountyTimeLeft(g.kind)))
    end
    return p.short or ""
end

-- ---------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------
local function Moved(self)
    local pos = self.db.settings.goalTrackerPos
    return type(pos) == "table" and pos.x and pos.y
end

local function Place(self)
    if not frame then return end
    frame:ClearAllPoints()
    local pos = Moved(self) and self.db.settings.goalTrackerPos
    if pos then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        frame.following = nil
        return
    end
    local t = Tracker()
    if t then
        frame:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
    elseif MinimapCluster then
        frame:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -10, -20)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -240)
    end
    frame.following = t
end

local function StartDrag()
    if not IsShiftKeyDown() or InCombatLockdown() then return end
    frame:StartMoving()
    frame.dragging = true
end

local function StopDrag()
    if not frame.dragging then return end
    frame.dragging = nil
    frame:StopMovingOrSizing()
    local x, y = frame:GetLeft(), frame:GetTop()
    if x and y then MF.db.settings.goalTrackerPos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) } end
    Place(MF)
end

local function Menu(owner, g, index)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then MF:OpenFishingGoal() return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(MF:GoalTitle(g))
        root:CreateButton("Open the Goals page", function() MF:OpenFishingGoal() end)
        if index then root:CreateButton("Clear this goal", function() MF:ClearFishingGoal(index) end) end
        root:CreateDivider()
        root:CreateButton("Hide the goals tracker", function()
            MF.db.settings.goalTracker = false
            MF:UpdateGoalTracker()
            MF:Print("The goals tracker is hidden. Settings > Fishing turns it back on.")
        end)
        if Moved(MF) then
            root:CreateButton("Put it back under the quest tracker", function()
                MF.db.settings.goalTrackerPos = nil
                MF:UpdateGoalTracker()
            end)
        end
    end)
end

local function Line()
    local b = CreateFrame("Button", nil, frame)
    b:SetWidth(WIDTH)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.title = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.title:SetPoint("TOPLEFT", 0, 0)
    b.title:SetWidth(WIDTH)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.line = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.line:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 10, -2)
    b.line:SetWidth(WIDTH - 10)
    b.line:SetJustifyH("LEFT")
    b.line:SetWordWrap(false)
    b:SetHeight(30)
    b:SetScript("OnEnter", function(self)
        if not self.goal then return end
        self.title:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(MF:GoalTitle(self.goal), 1, 0.82, 0)
        GameTooltip:AddLine(MF:GoalProgress(self.goal).text or "", 1, 1, 1, true)
        GameTooltip:AddLine("Click: the Goals page. Right-click: options. Shift-drag: move.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if self.done then self.title:SetTextColor(0.25, 0.9, 0.3) else self.title:SetTextColor(1, 0.82, 0) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", StartDrag)
    b:SetScript("OnMouseUp", StopDrag)
    b:SetScript("OnClick", function(self, button)
        if frame.dragging or not self.goal then return end
        if button == "RightButton" then Menu(self, self.goal, self.index) else MF:OpenFishingGoal() end
    end)
    return b
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "TheFishingLogGoalTracker", UIParent)
    MF.goalTrackerFrame = frame
    frame:SetSize(WIDTH, 20)
    frame:SetFrameStrata("LOW")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.header = CreateFrame("Button", nil, frame)
    frame.header:SetSize(WIDTH, 18)
    frame.header:SetPoint("TOPLEFT")
    frame.header.icon = frame.header:CreateTexture(nil, "ARTWORK")
    frame.header.icon:SetSize(14, 14)
    frame.header.icon:SetPoint("LEFT")
    frame.header.icon:SetTexture("Interface\\Icons\\Trade_Fishing")
    frame.header.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.header.text = frame.header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.header.text:SetPoint("LEFT", frame.header.icon, "RIGHT", 5, 0)
    frame.header.text:SetText("Fishing goals")
    frame.header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.header:SetScript("OnMouseDown", StartDrag)
    frame.header:SetScript("OnMouseUp", StopDrag)
    frame.header:SetScript("OnClick", function(self, button)
        if frame.dragging then return end
        if button == "RightButton" then Menu(self, { mode = "", id = 0 }) else MF:OpenFishingGoal() end
    end)
    frame.lines = {}
    for i = 1, MAX_LINES do frame.lines[i] = Line() end
    return frame
end

-- What the tracker lists: your goals, then any that finished a moment ago
local function Entries(self)
    local out = {}
    for i, g in ipairs(self:FishingGoals()) do out[#out + 1] = { g = g, index = i } end
    local now = GetTime()
    for g, at in pairs(finishedAt) do
        if now - at <= DONE_SHOWN then out[#out + 1] = { g = g, done = true, at = at } else finishedAt[g] = nil end
    end
    table.sort(out, function(a, b)
        if (a.done or false) ~= (b.done or false) then return not a.done end
        if a.done then return a.at < b.at end
        return a.index < b.index
    end)
    return out
end

function MF:UpdateGoalTracker()
    local entries = (self.db.settings.goalTracker ~= false) and Entries(self) or {}
    if #entries == 0 or InCombatLockdown() then
        if frame then frame:Hide() end
        return
    end
    Build()
    Place(self)
    local y = -22
    for i, b in ipairs(frame.lines) do
        local e = entries[i]
        if e then
            b.goal, b.index, b.done = e.g, e.index, e.done
            b.title:SetText(self:GoalTitle(e.g))
            if e.done then
                b.title:SetTextColor(0.25, 0.9, 0.3)
                b.line:SetText("|cff3ee63eDone!|r")
            else
                b.title:SetTextColor(1, 0.82, 0)
                b.line:SetText("- " .. self:GoalTrackerLine(e.g))
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
            b:Show()
            y = y - 34
        else
            b.goal = nil
            b:Hide()
        end
    end
    frame:SetHeight(-y)
    frame:Show()
end

-- Clearing every goal clears the Done lines too
function MF:ForgetFinishedFlashes()
    for g in pairs(finishedAt) do finishedAt[g] = nil end
end

-- Goals.lua tells us what finished, so it can say Done before it goes
function MF:GoalTrackerFinished(goals)
    local now = GetTime()
    for _, g in ipairs(goals or {}) do finishedAt[g] = now end
    self:UpdateGoalTracker()
    if C_Timer then C_Timer.After(DONE_SHOWN + 0.1, function() self:UpdateGoalTracker() end) end
end

MF:On("TFL_LOGIN", function(self)
    self:UpdateGoalTracker()
    -- Questie builds its own tracker a little after login: look again once it has
    if C_Timer then C_Timer.After(FOLLOW_AFTER, function() self:UpdateGoalTracker() end) end
end)
-- It sits on the quest tracker's bottom edge, so it follows the tracker growing and shrinking by
-- itself; these are when a tracker can appear, go, or be swapped for another, and when a podium's
-- time left is worth saying again. No timer of its own.
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    if not C_EventUtils or type(C_EventUtils.IsEventValid) ~= "function" or C_EventUtils.IsEventValid(event) then
        MF:On(event, function(self)
            if frame and frame:IsShown() or #self:FishingGoals() > 0 then self:UpdateGoalTracker() end
        end)
    end
end
MF:On("PLAYER_REGEN_DISABLED", function() if frame then frame:Hide() end end)
MF:On("PLAYER_REGEN_ENABLED", function(self) self:UpdateGoalTracker() end)
MF:On("SKILL_LINES_CHANGED", function(self) if frame and frame:IsShown() then self:UpdateGoalTracker() end end)
