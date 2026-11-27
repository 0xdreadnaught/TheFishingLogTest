-- Find waters (1.1.4): where to fish next, at your skill and level.
--   bar     skill and level steppers (your character's, or a preview), Still to catch / Every fish,
--           and a search across zone and fish names
--   list    one row per zone, grouped: where you are, good for you now, higher level, fish get away
--           at your skill, opposing cities. Each shows its travel level coloured against yours and
--           how many of its fish you still need
--   detail  the chosen zone beside the list: its fish (click for the card), catch rate by skill with
--           yours marked, and where to stand: frenzy access points and your own recorded waters
-- The figures come from FishingFinder.lua and CatchSkill.lua; The Fishing Log's own line view of
-- this page (FishingFinderLines) still sits underneath for /tfl finder's preview values.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.FinderPage = P

local GOLD = "|cffffd100"
local GREEN = "|cff3ee63e"
local ORANGE = "|cffff9d00"
local RED = "|cffff5a5a"
local MUTED = "|cff8f8f8f"
local HINT = "|cff9ec9ff"

local GROUPS = {
    { key = "here", title = "Where you are" },
    { key = "ready", title = "Good for you now" },
    { key = "higher", title = "Higher level" },
    { key = "below", title = "Only landed at a higher skill so far" },
    { key = "unknown", title = "Travel level not known" },
    { key = "enemy", title = "Opposing faction cities" },
}

local function Prefs()
    local cdb = MF.cdb
    if type(cdb.finderPage) ~= "table" then cdb.finderPage = {} end
    return cdb.finderPage
end

local function Fold(s)
    if ns.RealmPage and ns.RealmPage.Fold then return ns.RealmPage.Fold(s) end
    return tostring(s or ""):lower()
end

local function Pct(rate) return math.floor((rate or 0) * 100 + 0.5) .. "%" end

-- A travel level coloured the way quests are: red well above you, orange above, green at or below
local function LevelText(w, level)
    if not w.level then return MUTED .. "level ?|r" end
    local diff = w.level - (level or 1)
    local colour = diff >= 5 and RED or diff > 0 and ORANGE or GREEN
    return colour .. w.level .. "+|r"
end

-- How a zone rates at the skill asked about, in a few words
local function RatingText(w)
    if w.rating == "reliable" then
        return GREEN .. "Reliable at your skill|r" .. (w.escape and (MUTED .. "  " .. Pct(w.escape) .. " escape|r") or "")
    elseif w.rating == "possible" then
        return GOLD .. "Some get away: " .. Pct(w.escape) .. "|r"
    elseif w.rating == "yours" then
        return HINT .. "From your casts: " .. Pct(w.escape) .. " escape|r"
    elseif w.rating == "below" then
        return ORANGE .. "Landed from " .. (w.from or "?") .. " skill so far|r"
    end
    return MUTED .. "No catch data here yet|r"
end

local function FishCard(id) return MF.FISH[id] or (MF.TROPHY and MF.TROPHY[id]) end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function ZoneRow()
    local r = CreateFrame("Button")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", 10, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.right = W:Label(r, "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r.right:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
        local it = self.item
        if not (it and it.w) or P.map == it.w.map then return end
        P.map = it.w.map
        W:Sound("click")
        P:Refresh(true)
    end)
    return r
end

local function FishRow()
    local r = CreateFrame("Button")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r.icon = W:Icon(r, 18)
    r.icon:SetPoint("LEFT", 6, 0)
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.right = W:Label(r, "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r:SetScript("OnClick", function(self)
        local it = self.item
        if it and FishCard(it.id) then MF:ShowCard(it.id) end
    end)
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(MF:FishName(it.id), 1, 0.82, 0)
        GameTooltip:AddLine(it.mine and "You've caught it in this zone." or it.caught and "You've caught it, but not here."
            or "Not in your journal yet.", 1, 1, 1)
        if not it.listed then
            GameTooltip:AddLine("Not on this zone's reference list: it's here from your own catches.", 0.7, 0.7, 0.7, true)
        end
        if FishCard(it.id) then GameTooltip:AddLine("Click for its card.", 0.6, 0.8, 1) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return r
end

-- Catch rate by skill: a bar for each band anglers have logged here, yours marked
local CHART_H = 46
local function ChartRow()
    local r = CreateFrame("Button")
    r.bars = {}
    r.base = r:CreateTexture(nil, "BORDER")
    r.base:SetColorTexture(1, 1, 1, 0.25)
    r.base:SetHeight(1)
    r.base:SetPoint("BOTTOMLEFT", 10, 18)
    r.base:SetPoint("BOTTOMRIGHT", -10, 18)
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetColorTexture(1, 1, 1, 0.9)
    r.mark:SetHeight(2)
    r.lo = W:Label(r, "GameFontDisableSmall")
    r.hi = W:Label(r, "GameFontDisableSmall")
    r.you = W:Label(r, "GameFontHighlightSmall")
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Catch success by skill", 1, 0.82, 0)
        local lines = {}
        MF:CatchSkillLines(it.map, lines, it.skill)
        for i = 2, #lines do
            local line = lines[i]
            if line.right then
                GameTooltip:AddDoubleLine(line.text, line.right, 1, 1, 1, 1, 1, 1)
            else
                GameTooltip:AddLine(line.text, 0.8, 0.8, 0.8, true)
            end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return r
end

local function SpotRow()
    local r = CreateFrame("Frame")
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", 10, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.go = W:Button(r, "Show on map", 110, 20, function(self)
        local it = self:GetParent().item
        if it and it.go then it.go() end
    end)
    r.go:SetPoint("RIGHT", -6, 0)
    r.where = W:Label(r, "GameFontDisableSmall")
    r.where:SetPoint("RIGHT", r.go, "LEFT", -10, 0)
    return r
end

local function Make(kind)
    if kind == "zone" then return ZoneRow() end
    if kind == "fish" then return FishRow() end
    if kind == "chart" then return ChartRow() end
    if kind == "spot" then return SpotRow() end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, kind == "note" and "GameFontDisableSmall" or "GameFontNormal")
    fr.text:SetPoint("TOPLEFT", 8, kind == "note" and -4 or -8)
    fr.text:SetPoint("TOPRIGHT", -8, kind == "note" and -4 or -8)
    fr.text:SetJustifyH("LEFT")
    fr.right = W:Label(fr, "GameFontDisableSmall")
    fr.right:SetPoint("TOPRIGHT", -8, -9)
    if kind == "group" or kind == "head" then
        fr.rule = W:Divider(fr, 100)
        fr.rule:SetPoint("BOTTOMLEFT", 0, 1)
        fr.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    end
    return fr
end

local function FillZone(fr, it)
    local w = it.w
    local chosen = w.map == P.map
    fr.bg:SetColorTexture(1, 0.82, 0, chosen and 0.18 or (it.index % 2 == 0 and 0.035 or 0))
    fr.name:SetText((chosen and GOLD or "|cffffffff") .. w.zone .. "|r  " .. LevelText(w, P.level))
    local right
    if w.group == "below" then
        right = ORANGE .. (w.escape and (Pct(w.escape) .. " escape") or w.from and ("landed from " .. w.from) or "higher skill") .. "|r"
    elseif w.need > 0 then
        right = "|cffffffff" .. w.need .. "|r" .. MUTED .. " to catch|r"
    else
        right = MUTED .. "all caught|r"
    end
    if w.group == "enemy" then right = RED .. "opposing city|r" end
    fr.right:SetText(right)
    fr.name:SetWidth(math.max(80, (fr:GetWidth() or 300) - 110))
end

local function FillChart(fr, it)
    local width = math.max(60, (fr:GetWidth() or 300) - 20)
    local n = #it.bands
    local slot = math.min(26, width / math.max(1, n))
    for i, b in ipairs(it.bands) do
        local bar = fr.bars[i]
        if not bar then
            bar = fr:CreateTexture(nil, "ARTWORK")
            fr.bars[i] = bar
        end
        local catch = 1 - b.escape
        if catch >= 0.9 then bar:SetColorTexture(0.25, 0.85, 0.3, b.mine and 1 or 0.75)
        elseif catch >= 0.7 then bar:SetColorTexture(1, 0.8, 0.1, b.mine and 1 or 0.75)
        else bar:SetColorTexture(0.9, 0.3, 0.25, b.mine and 1 or 0.75) end
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", 10 + (i - 1) * slot, 19)
        bar:SetSize(math.max(2, slot - 3), math.max(2, CHART_H * catch))
        bar:Show()
        if b.mine then
            fr.mark:ClearAllPoints()
            fr.mark:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
            fr.mark:SetWidth(math.max(2, slot - 3))
        end
    end
    for i = n + 1, #fr.bars do fr.bars[i]:Hide() end
    local first, last = it.bands[1], it.bands[n]
    fr.lo:ClearAllPoints()
    fr.lo:SetPoint("BOTTOMLEFT", 10, 2)
    fr.lo:SetText(first.band * MF.CATCH_SKILL_BAND)
    fr.hi:ClearAllPoints()
    fr.hi:SetPoint("BOTTOMLEFT", 10 + (n - 1) * slot, 2)
    fr.hi:SetText(n > 1 and (last.band * MF.CATCH_SKILL_BAND) or "")
    local mine
    for i, b in ipairs(it.bands) do if b.mine then mine = i end end
    fr.mark:SetShown(mine ~= nil)
    fr.you:SetText(mine and "you" or "")
    if mine then
        fr.you:ClearAllPoints()
        fr.you:SetPoint("BOTTOMLEFT", 10 + (mine - 1) * slot, 2)
        -- Your mark says "you"; the band edges step aside rather than print over it
        if mine == 1 then fr.lo:SetText("") end
        if mine == n then fr.hi:SetText("") end
    end
end

local function Fill(fr, it)
    if it.kind == "zone" then FillZone(fr, it)
    elseif it.kind == "fish" then
        fr.icon:SetTexture(MF:FishIcon(it.id))
        fr.icon:SetDesaturated(it.caught and true or false)
        fr.icon:SetAlpha(it.caught and 0.6 or 1)
        local name = MF:FishName(it.id) or ("Item " .. it.id)
        fr.name:SetText((it.match and GOLD or it.caught and "|cffa8a8a8" or "|cffffffff") .. name .. "|r")
        fr.right:SetText(it.mine and (GREEN .. "caught here|r") or it.caught and (MUTED .. "caught elsewhere|r")
            or (GOLD .. "still to catch|r"))
        fr.name:SetWidth(math.max(80, (fr:GetWidth() or 300) - 150))
    elseif it.kind == "chart" then FillChart(fr, it)
    elseif it.kind == "spot" then
        fr.name:SetText(it.text)
        fr.where:SetText(it.where or "")
        fr.name:SetWidth(math.max(80, (fr:GetWidth() or 300) - 200))
    else
        fr.text:SetText(it.text or "")
        fr.right:SetText(it.right or "")
    end
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------
local function Stepper(parent, label, tip, get, step)
    local s = {}
    s.label = W:Label(parent, "GameFontNormalSmall", label)
    s.minus = W:Button(parent, "-", 22, 20, function() step(-1) end)
    s.minus:SetPoint("LEFT", s.label, "RIGHT", 6, 0)
    s.value = W:Label(parent, "GameFontHighlight")
    s.value:SetWidth(34)
    s.value:SetPoint("LEFT", s.minus, "RIGHT", 2, 0)
    s.plus = W:Button(parent, "+", 22, 20, function() step(1) end)
    s.plus:SetPoint("LEFT", s.value, "RIGHT", 2, 0)
    W:Tip(s.minus, label, tip)
    W:Tip(s.plus, label, tip)
    function s.Update() s.value:SetText(get()) end
    return s
end

local function Shift() return IsShiftKeyDown and IsShiftKeyDown() and true or false end

local function Segments(parent, choices, get, set)
    local buttons = {}
    local prev
    for _, c in ipairs(choices) do
        local b = W:Button(parent, c[2], c[3] or 100, 22, function()
            set(c[1])
            P:Refresh()
        end, c[2], c[4])
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
        b.value = c[1]
        buttons[#buttons + 1] = b
        prev = b
    end
    function buttons.Update()
        local on = get()
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
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(26)
    self.bar = bar

    self.skillStep = Stepper(bar, "Skill",
        "Effective fishing skill: your skill plus lure, gear and food. Steps of 25, or 5 with Shift held.",
        function() return P.skill and tostring(P.skill) or "?" end,
        function(d)
            local skill = MF:FinderInputs()
            MF.finderSkill = math.max(0, math.min(1000, (skill or 0) + d * (Shift() and 5 or 25)))
            P:Refresh(true)
        end)
    self.skillStep.label:SetPoint("LEFT", 8, 0)
    self.levelStep = Stepper(bar, "Level",
        "Character level, checked against each zone's travel level. Steps of 1, or 5 with Shift held.",
        function() return tostring(P.level or "?") end,
        function(d)
            local _, level = MF:FinderInputs()
            MF.finderLevel = math.max(1, math.min(60, (level or 1) + d * (Shift() and 5 or 1)))
            P:Refresh(true)
        end)
    self.levelStep.label:SetPoint("LEFT", self.skillStep.plus, "RIGHT", 18, 0)

    self.mine = W:Label(bar, "GameFontDisableSmall", "your character")
    self.mine:SetPoint("LEFT", self.levelStep.plus, "RIGHT", 12, 0)
    self.back = W:Button(bar, "Back to my stats", 130, 22, function()
        MF.finderSkill, MF.finderLevel = nil, nil
        P:Refresh(true)
    end, "Back to my stats", "Your own effective skill and level again, instead of the preview.")
    self.back:SetPoint("LEFT", self.levelStep.plus, "RIGHT", 12, 0)

    self.search = W:Search(bar, 190, function(text)
        if P.text == text then return end
        P.text = text
        P:Refresh()
    end, "Zone or fish")
    self.search:SetPoint("RIGHT", -6, 0)
    self.filter = Segments(bar, {
        { "need", "Still to catch", 110, "Only zones with a fish you haven't caught yet." },
        { "all", "Every fish", 90, "Every zone, including those you've finished." } },
        function() return Prefs().every and "all" or "need" end,
        function(v) Prefs().every = v == "all" or nil end)
    self.filter[1]:SetPoint("RIGHT", self.search, "LEFT", -(90 + 2 + 14), 0)

    self.list = W:VList(frame, Make, Fill)
    self.list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    self.list:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    self.list:SetWidth(420)

    local d = W:Panel(frame, 0.85)
    d:SetPoint("TOPLEFT", self.list, "TOPRIGHT", 22, 0)
    d:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 0)
    d.name = W:Label(d, "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", 14, -12)
    d.name:SetPoint("TOPRIGHT", -14, -12)
    d.name:SetJustifyH("LEFT")
    d.line1 = W:Label(d, "GameFontHighlightSmall")
    d.line1:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)
    d.line1:SetPoint("TOPRIGHT", d.name, "BOTTOMRIGHT", 0, -6)
    d.line1:SetJustifyH("LEFT")
    d.line2 = W:Label(d, "GameFontDisableSmall")
    d.line2:SetPoint("TOPLEFT", d.line1, "BOTTOMLEFT", 0, -4)
    d.line2:SetPoint("TOPRIGHT", d.line1, "BOTTOMRIGHT", 0, -4)
    d.line2:SetJustifyH("LEFT")
    d.list = W:VList(d, Make, Fill)
    d.list:SetPoint("TOPLEFT", 8, -70)
    d.list:SetPoint("BOTTOMRIGHT", -22, 8)
    self.detail = d
end

-- The zones on the list, grouped, after the search and the filter
function P:Rows()
    local zones, skill, level = MF:FinderZones()
    self.all = zones
    local words = {}
    for word in Fold(self.text or ""):gmatch("%S+") do words[#words + 1] = word end
    local every = Prefs().every
    local shown = {}
    for _, w in ipairs(zones) do
        w.matches = nil
        local keep = true
        if #words > 0 then
            local zone = Fold(w.zone)
            local names = {}
            for _, id in ipairs(w.fish) do names[id] = Fold(MF:FishName(id) or "") end
            for _, word in ipairs(words) do
                local hit = zone:find(word, 1, true)
                if not hit then
                    for _, name in pairs(names) do if name:find(word, 1, true) then hit = true break end end
                end
                if not hit then keep = false break end
            end
            -- The fish the search names, to bring to the top of the zone's list
            if keep then
                for id, name in pairs(names) do
                    local all = true
                    for _, word in ipairs(words) do if not name:find(word, 1, true) then all = false break end end
                    if all then w.matches = w.matches or {} w.matches[id] = true end
                end
            end
        elseif not every and w.need == 0 then
            keep = false
        end
        if keep then shown[#shown + 1] = w end
    end
    return shown, skill, level
end

function P:Items(shown)
    local items = {}
    if #shown == 0 then
        local text = (self.text or "") ~= "" and ("No zone or fish matches \"" .. self.text .. "\".")
            or "You've caught every fish these waters are known for. Every fish shows them all."
        items[1] = { kind = "note", h = 40, text = text }
        return items
    end
    for _, g in ipairs(GROUPS) do
        local rows = {}
        for _, w in ipairs(shown) do
            local group = w.here and "here" or w.group
            if group == g.key then rows[#rows + 1] = w end
        end
        if #rows > 0 then
            items[#items + 1] = { kind = "group", h = 28, text = g.title, right = tostring(#rows) }
            for i, w in ipairs(rows) do items[#items + 1] = { kind = "zone", h = 24, w = w, index = i } end
        end
    end
    return items
end

local function Bands(map, skill)
    local summary = MF:CatchSkillSummary(map, "o")
    local band = MF:SkillBand(skill)
    local out = {}
    for band = 0, 24 do
        local b = summary.bands[band]
        if b then
            local total = b.l + b.e
            local escape
            if b.sources >= 2 and total > 0 then escape = b.e / total
            elseif b.ownL and b.ownL + b.ownE > 0 then escape = b.ownE / (b.ownL + b.ownE) end
            if escape then out[#out + 1] = { band = band, escape = escape } end
        end
    end
    -- You're marked on your band, or the nearest one below it anglers have logged
    local mine
    for _, b in ipairs(out) do if band and b.band <= band then mine = b end end
    if mine then mine.mine = true end
    return out, summary
end

function P:DetailItems(w)
    local items = {}
    local journal = MF.cdb.profile.journal or {}
    -- Fish you still need first, then the rest; a fish the search named before both
    local fish = {}
    for _, id in ipairs(w.fish) do
        local home = false
        for _, z in ipairs((MF.FISH[id] or {}).zones or {}) do if z == MF.ZONE_IDS[w.map] then home = true break end end
        fish[#fish + 1] = { kind = "fish", h = 24, id = id, caught = journal[id] and true or false,
            mine = w.mine and w.mine[id] or false, listed = home, match = w.matches and w.matches[id] or false,
            name = MF:FishName(id) or "" }
    end
    table.sort(fish, function(a, b)
        if a.match ~= b.match then return a.match end
        if a.caught ~= b.caught then return not a.caught end
        return a.name < b.name
    end)
    items[#items + 1] = { kind = "head", h = 28, text = "Fish here",
        right = w.need > 0 and (w.need .. " still to catch") or "all caught" }
    for _, f in ipairs(fish) do items[#items + 1] = f end

    items[#items + 1] = { kind = "head", h = 32, text = "Catch rate by skill" }
    local bands, summary = Bands(w.map, self.skill)
    if #bands > 0 then
        items[#items + 1] = { kind = "chart", h = CHART_H + 30, map = w.map, skill = self.skill, bands = bands }
        local parts = {}
        if summary.possible then parts[#parts + 1] = "catches from " .. summary.possible * MF.CATCH_SKILL_BAND end
        if summary.reliable then parts[#parts + 1] = "reliable from " .. summary.reliable * MF.CATCH_SKILL_BAND end
        items[#items + 1] = { kind = "note", h = 22, text = (#parts > 0 and ("Anglers report " .. table.concat(parts, ", ") .. ". ") or "")
            .. "Hover the bars for every figure." }
    else
        items[#items + 1] = { kind = "note", h = 34,
            text = "Nobody has logged casts here yet. Every cast you fish here adds to it, and other anglers' once two agree." }
    end

    items[#items + 1] = { kind = "head", h = 32, text = "Where to stand" }
    local spots = 0
    for _, water in ipairs(MF.FRENZY_LOCATIONS or {}) do
        if water.map == w.map then
            spots = spots + 1
            local map, x, y = water.map, water.x, water.y
            items[#items + 1] = { kind = "spot", h = 26, text = "|cffffffff" .. water.name .. "|r",
                where = ("frenzy water  %.1f, %.1f"):format(x * 100, y * 100),
                go = function() MF:InspectFrenzyPoint(map, x, y) end }
        end
    end
    local personal = {}
    for key, records in pairs(MF.cdb.records or {}) do
        local p = MF:SpotPosition(key)
        if p and p.map == w.map then
            for _, id in ipairs(w.fish) do
                if records[id] then personal[#personal + 1] = { key = key, name = MF:SpotName(key) or key } break end
            end
        end
    end
    table.sort(personal, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.key < b.key end)
    for _, rec in ipairs(personal) do
        local key = rec.key
        spots = spots + 1
        items[#items + 1] = { kind = "spot", h = 26, text = GOLD .. rec.name .. "|r", where = "your record",
            go = function() MF:PointToSpot(key) end }
    end
    if spots == 0 then
        items[#items + 1] = { kind = "note", h = 26, text = "No frenzy waters listed here, and you have no records here yet." }
    end
    if w.enemy then items[#items + 1] = { kind = "note", h = 22, text = RED .. "An opposing faction's city: fishing here is dangerous.|r" } end
    items[#items + 1] = { kind = "note", h = 46,
        text = "Zone lists are guidance, not exact waters: some fish need pools, a season or a time of day. Travel levels are a guide to getting there safely, not a fishing requirement." }
    return items
end

function P:FillDetail(w)
    local d = self.detail
    if not w then
        d.name:SetText("")
        d.line1:SetText("")
        d.line2:SetText("")
        d.list:SetItems({})
        self.detailMap = nil
        return
    end
    d.name:SetText(w.zone)
    d.line1:SetText("Travel level " .. LevelText(w, self.level) .. "    " .. RatingText(w))
    local src = w.levelSource == "Client map levels" and "Travel level from the game's map." or "Travel level estimated."
    d.line2:SetText(src .. (w.here and ("  " .. GREEN .. "You're here.|r") or ""))
    -- The same zone redrawn keeps its scroll; another zone starts at the top
    d.list:SetItems(self:DetailItems(w), self.detailMap == w.map)
    self.detailMap = w.map
end

function P:Refresh(keepList)
    if not self.list then return end
    -- From a fish card's Find waters: search for that fish
    if MF.finderFish then
        local name = MF:FishName(MF.finderFish) or ""
        MF.finderFish = nil
        self.text = name
        self.search:SetText(name)
    end
    local width = self.frame:GetWidth() or 0
    if width > 0 then self.list:SetWidth(math.max(300, math.min(480, math.floor(width * 0.44)))) end

    local shown, skill, level = self:Rows()
    self.skill, self.level, self.shown = skill, level, #shown
    self.skillStep.Update()
    self.levelStep.Update()

    local preview = MF.finderSkill ~= nil or MF.finderLevel ~= nil
    self.back:SetShown(preview)
    self.mine:SetShown(not preview)
    self.filter.Update()

    -- The chosen zone: kept while it's on the list, else where you are, else the first
    local chosen
    for _, w in ipairs(shown) do if w.map == self.map then chosen = w end end
    if not chosen then
        for _, w in ipairs(shown) do if w.here then chosen = w end end
        local items = self:Items(shown)
        if not chosen then for _, it in ipairs(items) do if it.w then chosen = it.w break end end end
        self.map = chosen and chosen.map or nil
        self.list:SetItems(items, keepList)
    else
        self.list:SetItems(self:Items(shown), keepList)
    end
    self:FillDetail(chosen)
    if J.count and J.page and J.page.key == "finder" then J.count:SetText(self:Count()) end
end

function P:Count()
    local total = self.all and #self.all or 0
    if (self.shown or 0) == total then return total .. " zones" end
    return ("%d of %d zones"):format(self.shown or 0, total)
end

J:AddPage({
    key = "finder",
    match = function(state)
        return not state.recap and state.tab == "journal" and state.view == "tools"
            and (state.MF.anglingToolsView or "waters") == "finder"
    end,
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function() P:Refresh(true) end,
    subheading = function() return "Where can I fish?" end,
    count = function() return P:Count() end,
})
