-- Bounty: today's, this week's and this month's bounty as a poster and a podium.
--   top    Daily / Weekly / Monthly
--   left   the poster: the fish (or "any species"), where, when it resets, the rule; your entry, and
--          for a three-fish haul the three slots filling up
--   right  the standings with medals and the XP each podium place pays, you picked out;
--          underneath, your last result and the last winner
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.BountyPage = P
local LEFT_W = 360
local MIN_LEFT_W = 300 -- test build: the poster narrows to this before the standings are squeezed
local TOP_ROWS = 100   -- test build: the standings list the first this many, then your own row
local PLACE_W = 36     -- the place column is at least this wide ("1st"), and grows with the longest place shown
local KIND_LABEL = { day = "TODAY'S BOUNTY", week = "THIS WEEK'S BOUNTY", month = "THIS MONTH'S BOUNTY" }

-- The fish behind a standing, on mouse-over: a haul's three weights, or a collection's species
local function Graded(id, weight)
    if not (MF.GradeText and id and weight) then return "" end
    return MF:GradeText(id, weight) or ""
end

local function Detailed(mode)
    return mode == "top3" or mode == "species" or mode == "zone" or mode == "specimenSpecies"
end

local function ShowEntry(row)
    MF = MF or TFL
    local it = row.item
    if not (it and it.kind == "row" and P.kind) then return end
    local kind = P.kind
    local mode = MF:BountyFormat(kind)
    if not Detailed(mode) then return end
    local detail = MF:BountyDetail(kind, it.e.name)
    local _, id = MF:Bounty(kind)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(MF:ShortName(it.e.name), 1, 0.82, 0)
    if detail and detail.fish then
        GameTooltip:AddLine(("Three-fish haul, %s"):format(MF:Weight(it.e.weight)), 0.8, 0.8, 0.8)
        local icon = MF:FishIcon(id)
        for _, fish in ipairs(detail.fish) do
            local grade = fish.specimen and "|cffff8000Specimen|r" or Graded(id, fish.weight):gsub("^%s+", "")
            GameTooltip:AddDoubleLine(("|T%s:16:16|t  %s"):format(icon or "", MF:Weight(fish.weight)), grade, 1, 1, 1, 1, 1, 1)
        end
    elseif detail and detail.species then
        local names = {}
        for _, fishID in ipairs(detail.species) do
            names[#names + 1] = { name = MF:FishName(fishID) or "?", icon = MF:FishIcon(fishID) }
        end
        table.sort(names, function(a, b) return a.name < b.name end)
        GameTooltip:AddLine(#names == 1 and "1 species" or (#names .. " species"), 0.8, 0.8, 0.8)
        for _, f in ipairs(names) do
            GameTooltip:AddLine(("|T%s:16:16|t  %s"):format(f.icon or "", f.name), 1, 1, 1)
        end
    else
        GameTooltip:AddLine("Their fish show here once they're on The Fishing Log 1.1.4.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function StandingRow()
    local r = CreateFrame("Button")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r:SetScript("OnEnter", ShowEntry)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    r.place = W:Label(r, "GameFontNormal")
    r.place:SetPoint("LEFT", 10, 0)
    r.place:SetWidth(36)
    r.place:SetJustifyH("LEFT")
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", 50, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.score = W:Label(r, "GameFontHighlight")
    r.score:SetPoint("RIGHT", -10, 0)
    -- (Test build: no XP figure on the podium rows. "Podium pays" above the list says it once.)
    return r
end

P.StandingRow = StandingRow -- for the tests

local function Make(kind)
    if kind == "row" then return StandingRow() end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, "GameFontDisable")
    fr.text:SetPoint("LEFT", 8, 0) -- tied to the row so a long note wraps instead of being cut at both ends
    fr.text:SetPoint("RIGHT", -8, 0)
    fr.text:SetJustifyH("CENTER")
    return fr
end

local function Fill(fr, it)
    if it.kind ~= "row" then fr.text:SetText(it.text) return end
    W:Place(fr.place, it.place)
    local me = MF:IsMe(it.e.name)
    fr.name:SetText(MF:ShortName(it.e.name))
    if me then fr.name:SetTextColor(1, 0.62, 0) else fr.name:SetTextColor(1, 1, 1) end
    fr.score:SetText(it.scoreText)
    if me then
        fr.bg:SetColorTexture(1, 0.62, 0, 0.14)
    elseif it.place <= 3 then
        local m = W.MEDAL[it.place]
        fr.bg:SetColorTexture(m[1], m[2], m[3], 0.07)
    else
        fr.bg:SetColorTexture(1, 1, 1, it.index % 2 == 0 and 0.03 or 0)
    end
    -- The place column is as wide as the longest place on the board; the name gets whatever the
    -- place and the score leave.
    local placeW = P.placeW or PLACE_W
    fr.place:SetWidth(placeW)
    fr.name:ClearAllPoints()
    fr.name:SetPoint("LEFT", 10 + placeW + 4, 0)
    fr.name:SetWidth(math.max(60, (fr:GetWidth() or 300) - (10 + placeW + 4) - (fr.score:GetStringWidth() or 60) - 10 - 12))
end
P.FillRow = Fill -- for the tests

-- What a standings row shows as the score. A count is shown bare ("17", not "17 species" or
-- "x17"): the bounty on the left already says what is being counted. Weights keep their unit.
local function RowScore(kind, e)
    local mode = MF:BountyFormat(kind)
    if mode == "top3" or mode == "total" or mode == "heaviest" then
        return MF:BountyScoreText(kind, e.weight, nil, e.specimen)
    end
    return tostring(math.floor(tonumber(e.weight) or 0))
end

-- The rows of the standings list from the sorted standings: the first TOP_ROWS, then your own
-- row if you are further down. Returns the rows, how many anglers entered, and the width the
-- place column needs for the longest place shown.
function P:StandingItems(kind, standings)
    local items, mine = {}, nil
    local place, last = 0, nil
    for i, e in ipairs(standings) do
        if e.weight ~= last then place, last = i, e.weight end
        if i <= TOP_ROWS then
            items[#items + 1] = { kind = "row", h = 28, e = e, place = place, index = i, scoreText = RowScore(kind, e) }
        elseif not mine and MF:IsMe(e.name) then
            mine = { kind = "row", h = 28, e = e, place = place, index = i, scoreText = RowScore(kind, e) }
        end
    end
    if mine then
        items[#items + 1] = { kind = "note", h = 18, text = "..." }
        items[#items + 1] = mine
    end
    local widest = PLACE_W
    local measure = self.measure
    for _, it in ipairs(items) do
        if it.kind == "row" and it.place > 3 then
            local text = "#" .. it.place
            local w = PLACE_W
            if measure then measure:SetText(text) w = math.ceil(measure:GetStringWidth() or 0) + 2 end
            if w > widest then widest = w end
        end
    end
    return items, #standings, widest
end

-- A haul slot's frame in its fish's grade colour (orange for a specimen); gold when empty or ungraded
local function TintRim(rim, colour)
    local r, g, bl = (colour or ""):match("|cff(%x%x)(%x%x)(%x%x)")
    if r then
        rim:SetDesaturated(true)
        rim:SetVertexColor(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(bl, 16) / 255)
    else
        rim:SetDesaturated(false)
        rim:SetVertexColor(1, 1, 1)
    end
    rim.grade = r and colour or nil
end
P.TintRim = TintRim

local function Slot(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(96, 84)
    s.icon = W:FramedIcon(s, 40)
    s.icon:SetPoint("TOP", 0, -6)
    s.weight = W:Label(s, "GameFontNormal")
    s.weight:SetPoint("TOP", s.icon, "BOTTOM", 0, -8)
    s.note = W:Label(s, "GameFontDisableSmall")
    s.note:SetPoint("TOP", s.weight, "BOTTOM", 0, -2)
    return s
end

function P:Build(frame)
    self.frame = frame
    -- Daily / Weekly / Monthly
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(26)
    local rule = W:Divider(strip, 100)
    rule:SetPoint("BOTTOMLEFT", 0, -2)
    rule:SetPoint("BOTTOMRIGHT", 0, -2)
    self.tabs = {}
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, strip)
        b:SetHeight(24)
        b.text = W:Label(b, "GameFontNormal")
        b.text:SetPoint("CENTER", 0, 1)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT", 3, 0)
        b.line:SetPoint("BOTTOMRIGHT", -3, 0)
        b.line:SetHeight(2)
        b.line:SetColorTexture(1, 0.82, 0, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.12)
        b:SetScript("OnClick", function(self)
            local host = J:Host()
            local sb = host and host.subs and host.subs[i]
            if sb and sb:IsEnabled() then W:Sound("tab") sb:Click() end
        end)
        if i == 1 then b:SetPoint("BOTTOMLEFT", 0, 0) else b:SetPoint("LEFT", self.tabs[i - 1], "RIGHT", 6, 0) end
        self.tabs[i] = b
    end

    strip:Hide() -- (the navigation strip above the page has Daily / Weekly / Monthly)

    -- The poster
    local poster = W:Panel(frame, 0.88)
    poster:SetPoint("TOPLEFT", 0, 0)
    poster:SetPoint("BOTTOMLEFT")
    poster:SetWidth(LEFT_W)
    poster.kicker = W:Label(poster, "GameFontNormalSmall")
    poster.kicker:SetPoint("TOP", 0, -16)
    poster.kicker:SetTextColor(0.8, 0.8, 0.8)
    poster.icon = W:FramedIcon(poster, 60)
    poster.icon:SetPoint("TOP", poster.kicker, "BOTTOM", 0, -16)
    poster.title = W:Label(poster, "GameFontNormalLarge")
    poster.title:SetPoint("TOP", poster.icon, "BOTTOM", 0, -16)
    poster.title:SetWidth(LEFT_W - 40)
    poster.where = W:Label(poster, "GameFontHighlight")
    poster.where:SetPoint("TOP", poster.title, "BOTTOM", 0, -6)
    poster.resets = W:Label(poster, "GameFontDisableSmall")
    poster.resets:SetPoint("TOP", poster.where, "BOTTOM", 0, -6)
    poster.rule = W:Label(poster, "GameFontHighlightSmall")
    poster.rule:SetPoint("TOP", poster.resets, "BOTTOM", 0, -12)
    poster.rule:SetWidth(LEFT_W - 50)
    poster.rule:SetTextColor(0.75, 0.75, 0.75)
    poster.rule:SetSpacing(2)
    -- The small print, on hover (as The Fishing Log's "Rules and rewards" row had it)
    poster:EnableMouse(true)
    poster:SetScript("OnEnter", function(self)
        local kind = P.kind
        if not kind then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rules and rewards", 1, 0.82, 0)
        GameTooltip:AddLine(MF:BountyRule(kind) or "", 1, 1, 1, true)
        GameTooltip:AddLine("Ties share a place and reward (1st, 1st, 3rd).", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Rewards use known shared standings after a two-minute sync window and 30 seconds without changes.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(kind == "day" and "Daily objectives are drawn for your faction."
            or "The objective's location restrictions apply to every catch.", 0.8, 0.8, 0.8, true)
        if MF:BountyFormat(kind) == "top3" then
            GameTooltip:AddLine("A haul is the combined weight of three fish; the star means at least one was a specimen.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    poster:SetScript("OnLeave", function(self) W:HideTip(self) end)
    poster.divider = W:Divider(poster, LEFT_W - 40)
    poster.divider:SetPoint("TOP", poster.rule, "BOTTOM", 0, -14)
    poster.entryLabel = W:Label(poster, "GameFontNormalSmall")
    poster.entryLabel:SetPoint("TOP", poster.divider, "BOTTOM", 0, -12)
    poster.entry = W:Label(poster, "GameFontHighlightHuge")
    poster.entry:SetPoint("TOP", poster.entryLabel, "BOTTOM", 0, -6)
    poster.progress = W:Label(poster, "GameFontDisableSmall")
    poster.progress:SetPoint("TOP", poster.entry, "BOTTOM", 0, -4)
    poster.slots = {}
    for i = 1, 3 do
        local s = Slot(poster)
        s:SetPoint("TOP", poster.progress, "BOTTOM", (i - 2) * 104, -10)
        poster.slots[i] = s
    end
    poster.empty = W:Label(poster, "GameFontDisable", "Nothing on offer this time.")
    poster.empty:SetPoint("CENTER")
    self.poster = poster

    -- Standings and results
    local right = CreateFrame("Frame", nil, frame)
    right:SetPoint("TOPLEFT", poster, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT")
    self.right = right
    local h = W:Header(right, "Standings", 300)
    h:SetPoint("TOPLEFT", 4, -4)
    h.rule:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, -22)
    self.standHeader = h
    -- Test build: what the podium pays has a line of its own, tied to both edges of the column,
    -- so it wraps inside a narrow column. It used to follow "Standings" and ran out of the window.
    self.payout = W:Label(right, "GameFontDisableSmall")
    self.payout:SetPoint("TOPLEFT", 4, -30)
    self.payout:SetPoint("TOPRIGHT", -4, -30)
    self.payout:SetJustifyH("LEFT")
    self.measure = W:Label(right, "GameFontNormal") -- never shown: measures the longest place for the column
    self.measure:Hide()

    -- Your last result and the last winner sit at the foot of the poster, so
    -- the standings run the whole height of the page however long they get.
    local results = CreateFrame("Frame", nil, poster)
    results:SetPoint("BOTTOMLEFT", 12, 12)
    results:SetPoint("BOTTOMRIGHT", -12, 12)
    results:SetHeight(104)
    self.results = results
    results.rule = W:Divider(results, LEFT_W - 40)
    results.rule:SetPoint("BOTTOM", results, "TOP", 0, 8)
    results.last = W:Card(results)
    results.last:SetPoint("TOPLEFT", 0, 0)
    results.last:SetPoint("TOPRIGHT", results, "TOP", -4, 0)
    results.last:SetHeight(104)
    results.won = W:Card(results)
    results.won:SetPoint("TOPLEFT", results, "TOP", 4, 0)
    results.won:SetPoint("TOPRIGHT", 0, 0)
    results.won:SetHeight(104)
    for _, card in ipairs({ results.last, results.won }) do
        card.kicker = W:Label(card, "GameFontNormalSmall")
        card.kicker:SetPoint("TOPLEFT", 12, -10)
        card.icon = W:FramedIcon(card, 32)
        card.icon:SetPoint("TOPLEFT", 14, -32)
        card.big = W:Label(card, "GameFontNormalLarge")
        card.big:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -2)
        card.big:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        card.big:SetJustifyH("LEFT")
        card.big:SetWordWrap(false)
        card.small = W:Label(card, "GameFontHighlightSmall")
        card.small:SetPoint("TOPLEFT", card.big, "BOTTOMLEFT", 0, -4)
        card.small:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        card.small:SetJustifyH("LEFT")
        card.small:SetWordWrap(false)
        card.note = W:Label(card, "GameFontDisableSmall")
        card.note:SetPoint("BOTTOMLEFT", 12, 10)
        card.note:SetPoint("BOTTOMRIGHT", -12, 10)
        card.note:SetJustifyH("LEFT")
        card.note:SetWordWrap(false)
    end

    self.list = W:VList(right, Make, Fill)
    self.list:SetPoint("TOPLEFT", 0, -48)
    self.list:SetPoint("BOTTOMRIGHT", -14, 0)

    -- On a short journal the poster's own content (a haul's three slots
    -- especially) can reach down to the results; then they step aside.
    poster:HookScript("OnSizeChanged", function() P:FitResults() end)
    frame:HookScript("OnSizeChanged", function() P:Layout() end)
    self:Layout()
end

-- Test build: the page was drawn for the whole width of the window. Beside the character it
-- has about two thirds of that, so the poster takes half the page, between MIN_LEFT_W and the
-- width it always had, and everything sized from the poster follows.
function P:Layout()
    local frame, poster = self.frame, self.poster
    if not (frame and poster) then return end
    local page = frame:GetWidth() or 0
    if page <= 0 then return end
    local w = math.max(MIN_LEFT_W, math.min(LEFT_W, math.floor(page * 0.5)))
    if w == self.posterW then return end
    self.posterW = w
    poster:SetWidth(w)
    poster.title:SetWidth(w - 40)
    poster.rule:SetWidth(w - 50)
    poster.divider:SetWidth(w - 40)
    if self.results and self.results.rule then self.results.rule:SetWidth(w - 40) end
    local step = math.min(104, math.floor((w - 24 - 96) / 2)) -- a haul's three slots stay inside the poster
    for i, s in ipairs(poster.slots) do
        s:ClearAllPoints()
        s:SetPoint("TOP", poster.progress, "BOTTOM", (i - 2) * step, -10)
    end
end

function P:FitResults()
    local poster, results = self.poster, self.results
    if not (poster and results) then return end
    local lowest = poster.progress
    if poster.slots[1] and poster.slots[1]:IsShown() then lowest = poster.slots[1] end
    local bottom, top = lowest:GetBottom(), results:GetTop()
    results:SetShown(not (bottom and top) or bottom > top + 16)
end

-- A long name steps down a font size to fit its card, and only then is cut short.
local function Fit(fs)
    fs:SetFontObject("GameFontNormalLarge")
    local width = fs:GetWidth() or 0
    local need = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0
    if width > 0 and need > width then fs:SetFontObject("GameFontNormal") end
end

function P:Refresh(state)
    local subs = state.subs
    local kind = subs and subs.current or "day"
    self.kind = kind
    for i, b in ipairs(self.tabs) do
        local s = subs and subs[i]
        b:SetShown(s ~= nil)
        if s then
            b.text:SetText(s.label)
            b:SetWidth((b.text:GetStringWidth() or 50) + 24)
            local on = s.key == kind
            b.line:SetShown(on)
            if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.75, 0.75, 0.75) end
        end
    end

    local poster = self.poster
    local _, id, zone = MF:Bounty(kind)
    local has = id ~= nil
    for _, r in ipairs({ poster.kicker, poster.icon, poster.title, poster.where, poster.resets, poster.rule, poster.divider,
        poster.entryLabel, poster.entry, poster.progress }) do r:SetShown(has) end
    poster.empty:SetShown(not has)
    local top3 = has and MF:BountyFormat(kind) == "top3"
    if has then
        poster.kicker:SetText(KIND_LABEL[kind] or "BOUNTY")
        poster.icon.icon:SetTexture(MF:BountyIcon(kind))
        poster.title:SetText(MF:BountyTitle(kind))
        poster.where:SetText(zone and ("in |cffffd100" .. zone .. "|r") or "|cffa0a0a0anywhere on the realm|r")
        poster.resets:SetText("resets in " .. MF:FormatSpan(MF:BountyTimeLeft(kind)))
        poster.rule:SetText(MF:BountyRule(kind) or "")
        local best = MF:MyBountyBest(kind) or 0
        poster.entryLabel:SetText(top3 and "YOUR HAUL" or "YOUR ENTRY")
        poster.entry:SetText(best > 0 and MF:BountyScoreText(kind, best, nil, MF:BountySpecimenStatus(kind, MF.me, nil, best)) or "|cff858585-|r")
        poster.progress:SetText(MF:BountyProgressText(kind) or (best > 0 and "" or "Not entered yet"))
    end
    local haul = top3 and MF:BountyHaul(kind) or {}
    for i, s in ipairs(poster.slots) do
        s:SetShown(top3 and true or false)
        if top3 then
            local fish = haul[i]
            s.icon.icon:SetTexture(MF:FishIcon(id))
            s.icon.icon:SetDesaturated(fish == nil)
            s.icon.icon:SetVertexColor(fish and 1 or 0.25, fish and 1 or 0.25, fish and 1 or 0.25)
            if fish then
                local specimen = fish.specimen
                if specimen == nil then specimen = MF:GuaranteedSpecimenWeight(id, fish.weight) end
                s.weight:SetText(MF:Weight(fish.weight))
                s.note:SetText(specimen and "|cffff8000Specimen|r" or (fish.legacy and "|cff858585grade not saved|r" or Graded(id, fish.weight)))
                local colour = specimen and "|cffff8000" or (not fish.legacy and select(2, MF:WeightGradeShort(id, fish.weight))) or nil
                TintRim(s.icon.rim, colour)
            else
                TintRim(s.icon.rim, nil)
                s.weight:SetText("|cff858585-|r")
                s.note:SetText("not caught yet")
            end
        end
    end

    -- Standings
    local rewards = MF.BOUNTY_REWARDS and MF.BOUNTY_REWARDS[kind] or {}
    local items, entered, placeW = self:StandingItems(kind, has and MF:BountyStandings(kind) or {})
    self.entered, self.placeW = entered, placeW
    if #items == 0 then items[1] = { kind = "note", h = 60, text = has and "No entries yet. The podium is empty." or "" } end
    self.items = items
    self.list:SetItems(items, true)
    self.payout:SetText(rewards[1] and ("Podium pays %d / %d / %d XP"):format(rewards[1], rewards[2] or 0, rewards[3] or 0) or "")

    -- Your last result, and the last winner
    local res = self.results
    local reward = MF:BountyRewardResult(kind)
    res.last.kicker:SetText("YOUR LAST RESULT")
    if reward then
        W:Place(res.last.big, reward.place)
        res.last.small:SetText(("|cff3ee63e+%d XP|r"):format(reward.xp or 0))
        res.last.note:SetText(MF:BountyTitle(kind, reward.period))
        res.last.icon.icon:SetTexture(MF:BountyIcon(kind, reward.period))
        res.last.icon:Show()
    elseif MF.IsBountyRewardPeriod and MF:IsBountyRewardPeriod(kind, MF:BountyPeriod(kind) - 1)
        and (MF:MyBountyBest(kind, MF:BountyPeriod(kind) - 1) or 0) > 0
        and (((MF.cdb.profile.bountyRewardThrough or {})[kind]) or -1) < MF:BountyPeriod(kind) - 1 then
        -- You entered last time and the standings are still being agreed
        res.last.big:SetText("|cffffd100...|r")
        res.last.small:SetText("|cffa0a0a0Syncing standings...|r")
        res.last.note:SetText("Rewards settle once the realm's standings agree.")
        res.last.icon:Hide()
    else
        res.last.big:SetText("|cff858585-|r")
        res.last.small:SetText("|cff858585No podium last time.|r")
        res.last.note:SetText("")
        res.last.icon:Hide()
    end
    local won = MF:BountyWinner(kind)
    res.won.kicker:SetText("LAST WINNER")
    if won then
        local mine = MF:IsMe(won.name)
        res.won.big:SetText((mine and "|cffff9d00" or "|cffffd100") .. MF:ShortName(won.name) .. "|r")
        Fit(res.won.big)
        res.won.small:SetText(MF:BountyScoreText(kind, won.score, won.period, won.specimen))
        res.won.note:SetText(MF:BountyTitle(kind, won.period) .. (won.zone and ("  |cff858585in " .. won.zone .. "|r") or ""))
        res.won.icon.icon:SetTexture(MF:BountyIcon(kind, won.period))
        res.won.icon:Show()
    else
        res.won.big:SetText("|cff858585-|r")
        Fit(res.won.big)
        res.won.small:SetText("|cff858585Not heard yet.|r")
        res.won.note:SetText("")
        res.won.icon:Hide()
    end
end

J:AddPage({
    key = "bounty",
    match = function(state) return not state.recap and state.tab == "bounty" and state.subs ~= nil end,
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function(_, state) P:Layout() P:Refresh(state) P:FitResults() end,
    subheading = function(state)
        local s = state.subs
        for _, sub in ipairs(s or {}) do if sub.key == s.current then return sub.label end end
        return ""
    end,
    count = function()
        local n = P.entered or 0
        local text = n == 1 and "1 angler entered" or (n .. " anglers entered")
        if n > 0 and P.kind and Detailed(MF:BountyFormat(P.kind)) then text = text .. "  |cff858585- hover a name for their fish|r" end
        return text
    end,
})
