-- Navigation: at most two rows of tabs anywhere in the journal.
--   bottom  the main pages (Journal, Records, Bounty, History, Events, Realm)
--   top     this page's own views on the left; on the right, its filters as boxed toggles
--           (This season | All time) and any one-off commands (Post event, Wardrobe)
-- The Fishing Log offers all of these as a row of action buttons and nested sub-tabs; here they are
-- sorted into views, toggles and commands, and every one still presses The Fishing Log's own button.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal
local N = {}
ns.Nav = N

local MF
local H = 26

-- Labels that switch between views (shown as tabs, never as commands)
local NAV_LABELS = {
    ["Fishing here"] = true, Journal = true, Back = true, ["Local waters"] = true, Tacklebox = true,
    ["Find waters"] = true, Here = true, ["By fish"] = true, ["By zone"] = true, Caught = true,
    ["All fish"] = true, Album = true, Sessions = true, ["By spot"] = true, Anglers = true,
    Records = true, ["XP leaderboard"] = true, ["Before the wipe"] = true,
    ["All events"] = true, Invites = true,
}

-- Two-way filters. The Fishing Log names its button after where it takes you, so the label it
-- offers is always the segment you're not on. Some only belong to one view (two pages use "All zones").
local function ToolsView(state, key)
    return state.tab == "journal" and state.view == "tools" and (MF.anglingToolsView or "waters") == key
end
local TOGGLES = {
    { "This season", "All time" },
    { "Everyone", "My guild" },
    { "Show empty", "Hide empty" },
    { "Planner", "Discoveries", when = function(st) return ToolsView(st, "frenzies") end },
    { "All zones", "Zone only", when = function(st) return ToolsView(st, "frenzies") end },
}

local function Has(state, label)
    for _, a in ipairs(state.actions or {}) do if a.label == label then return true end end
    return false
end

local function Press(label) return J:PressAction(label) end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
local function Tab(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(H - 2)
    b.text = W:Label(b, "GameFontNormal")
    b.text:SetPoint("CENTER", 0, 1)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT", 3, 0)
    b.line:SetPoint("BOTTOMRIGHT", -3, 0)
    b.line:SetHeight(2)
    b.line:SetColorTexture(1, 0.82, 0, 1)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetAllPoints()
    b.glow:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.85, 0.45)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.12)
    b:SetScript("OnClick", function(self)
        if self.on or not self.go then return end
        W:Sound("tab")
        self.go()
    end)
    return b
end

local function SetTab(b, label, on, go)
    b.text:SetText(label)
    b:SetWidth((b.text:GetStringWidth() or 50) + 20)
    b.on, b.go = on, go
    b.line:SetShown(on)
    b.glow:SetAlpha(on and 0.2 or 0)
    if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.75, 0.75, 0.75) end
    b:Show()
end

-- A boxed two-way switch: the chosen side lit
local function Toggle(parent)
    local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    t:SetHeight(20)
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    t:SetBackdropColor(0, 0, 0, 0.5)
    t:SetBackdropBorderColor(0.55, 0.47, 0.3, 1)
    t.segs = {}
    for i = 1, 2 do
        local s = CreateFrame("Button", nil, t)
        s:SetHeight(16)
        s.fill = s:CreateTexture(nil, "BACKGROUND")
        s.fill:SetAllPoints()
        s.fill:SetColorTexture(1, 0.82, 0, 0.22)
        s.text = W:Label(s, "GameFontHighlightSmall")
        s.text:SetPoint("CENTER")
        local hl = s:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        s:SetScript("OnClick", function(self)
            if self.on or not self.go then return end
            W:Sound("click")
            self.go()
        end)
        t.segs[i] = s
    end
    t.sep = t:CreateTexture(nil, "ARTWORK")
    t.sep:SetWidth(1)
    t.sep:SetColorTexture(0.55, 0.47, 0.3, 1)
    return t
end

local function SetToggle(t, a, b, current, go)
    local w = 0
    for i, label in ipairs({ a, b }) do
        local s = t.segs[i]
        s.text:SetText(label)
        local sw = (s.text:GetStringWidth() or 40) + 16
        s:SetWidth(sw)
        s:ClearAllPoints()
        s:SetPoint("LEFT", t, "LEFT", 2 + w, 0)
        w = w + sw
        s.on = label == current
        s.fill:SetShown(s.on)
        if s.on then s.text:SetTextColor(1, 0.82, 0) else s.text:SetTextColor(0.7, 0.7, 0.7) end
        s.go = function() go(label) end
    end
    t.sep:ClearAllPoints()
    t.sep:SetPoint("TOP", t.segs[2], "TOPLEFT", 0, 0)
    t.sep:SetPoint("BOTTOM", t.segs[2], "BOTTOMLEFT", 0, 0)
    t:SetWidth(w + 4)
    t:Show()
end

-- A command: a small plate with gold words (so it never reads as a tab)
local function Command(parent)
    local c = W:Card(parent, true)
    c:SetHeight(20)
    c:SetBackdropColor(0.12, 0.09, 0.04, 0.9)
    c:SetEdge(0.7, 0.58, 0.3, 1)
    c.text = W:Label(c, "GameFontNormalSmall")
    c.text:SetPoint("CENTER", 0, 0)
    c:SetScript("OnClick", function(self) if self.fn then W:Sound("click") self.fn() end end)
    return c
end

local function SetCommand(c, label, fn)
    c.text:SetText(label)
    c:SetWidth((c.text:GetStringWidth() or 50) + 20)
    c.fn = fn
    c:Show()
end

-- ---------------------------------------------------------------------------
-- What each page offers
-- ---------------------------------------------------------------------------
local function GoCollection()
    if Press("Journal") or Press("Back") then return end
    -- From Angling tools (or a Find waters detail): through Fishing here, which leads back
    MF:OpenFishingHere()
    Press("Journal")
end

local function JournalTabs(state)
    local view = state.view
    local tools = MF.anglingToolsView or "waters"
    local here = view == "here" and "here" or view == "tools" and tools or view == "goals" and "goals" or "collection"
    local function Tools(key) return function() MF:OpenAnglingTools(key) end end
    return {
        { "Collection", here == "collection", GoCollection },
        { "Fishing here", here == "here", function() MF:OpenFishingHere() end },
        { "Tacklebox", here == "tackle", Tools("tackle") },
        { "Find waters", here == "finder", Tools("finder") },
        { "Frenzies", here == "frenzies", Tools("frenzies") },
        { "Goals", here == "goals", function() if MF.OpenFishingGoal then MF:OpenFishingGoal() end end },
    }
end

local REALM_HOME = { "Back", "Anglers", "Records" }
local function RealmView(state)
    if Has(state, "By fish") and Has(state, "XP leaderboard") then return "anglers" end
    if Has(state, "Anglers") then return "species" end
    if Has(state, "Refresh") and Has(state, "Records") then return "xp" end
    if Has(state, "Back") and Has(state, "This season") or Has(state, "Back") and Has(state, "All time") then return "angler" end
    if Has(state, "Back") then return "founding" end
end
local function RealmGo(target)
    return function()
        -- Home to the standings first, then on to the view asked for
        for _ = 1, 3 do
            local st = J:State()
            if RealmView(st) == "anglers" then break end
            local moved = false
            for _, label in ipairs(REALM_HOME) do if Has(st, label) and Press(label) then moved = true break end end
            if not moved then break end
        end
        if target then Press(target) end
    end
end
local function RealmTabs(state)
    local v = RealmView(state)
    local tabs = {
        { "Anglers", v == "anglers", RealmGo(nil) },
        { "By fish", v == "species", RealmGo("By fish") },
        { "XP leaderboard", v == "xp", RealmGo("XP leaderboard") },
    }
    if v == "angler" then tabs[#tabs + 1] = { "Angler", true } end
    if v == "founding" or Has(state, "Before the wipe") then
        tabs[#tabs + 1] = { "Before the wipe", v == "founding", RealmGo("Before the wipe") }
    end
    return tabs
end

function N:Spec(state)
    local tabs = {}
    local tab = state.tab
    if state.recap then
        tabs = { { "Recap", true } }
    elseif tab == "history" or ToolsView(state, "reports") then
        -- The Logbook: your sessions, by spot, and the session reports (which The Fishing Log
        -- keeps in Angling tools; they're shown under the Logbook here, as in Godfall's 0.7.4)
        local reports = tab ~= "history"
        local spots = not reports and Has(state, "Sessions")
        local function Go(label)
            return function()
                if reports then MF:OpenJournal("history") end
                Press(label)
            end
        end
        tabs = { { "Sessions", not reports and not spots, Go("Sessions") },
            { "By spot", spots, Go("By spot") },
            { "Reports", reports, function() MF:OpenAnglingTools("reports") end } }
    elseif tab == "journal" then
        tabs = JournalTabs(state)
    elseif tab == "fame" then
        tabs = RealmTabs(state)
    elseif tab == "records" and ns.Waters then
        -- Drawn by the Waters page: this zone's map, with the way on to finding and frenzies
        local function Tools(key) return function() MF:OpenAnglingTools(key) end end
        tabs = { { "This zone", true }, { "Find waters", false, Tools("finder") },
            { "Frenzies", false, Tools("frenzies") } }
    elseif tab == "records" and ns.Records then
        -- Drawn by the Records page itself: The Fishing Log has one Records page
        local R = ns.Records
        local spots = R.view == "spots"
        tabs = { { "Here", not spots, function() R:SetView("here") end },
            { "Other spots", spots, function() R:SetView("spots") end } }
    elseif tab == "board" then
        local view = MF.EventView and MF:EventView() or (Has(state, "Back") and "detail" or "list")
        local count = MF.EventInviteCount and MF:EventInviteCount() or 0
        tabs = { { "All events", view == "list", function() MF:OpenEventList() end },
            { count > 0 and ("Invites (%d)"):format(count) or "Invites", view == "invites",
                function() MF:OpenEventInvites() end } }
        if view == "detail" then tabs[#tabs + 1] = { "Event", true } end
    end
    -- The Fishing Log's own sub-tabs (Bounty's Daily / Weekly / Monthly, and any page added later)
    if #tabs == 0 and state.subs then
        local host = J:Host()
        for i, s in ipairs(state.subs) do
            tabs[#tabs + 1] = { s.label, s.key == state.subs.current, function()
                local b = host and host.subs and host.subs[i]
                if b and b:IsEnabled() then b:Click() end
            end }
        end
    end

    -- Toggles and commands from its actions
    local toggles, commands, used = {}, {}, {}
    -- Find waters (1.1.4) has its own bar for skill, level, filter and search
    if ToolsView(state, "finder") and ns.FinderPage then return { tabs = tabs, toggles = toggles, commands = commands } end
    for _, pair in ipairs(TOGGLES) do
        local a, b = pair[1], pair[2]
        local hasA, hasB = Has(state, a), Has(state, b)
        if (hasA or hasB) and (not pair.when or pair.when(state)) and not (used[a] or used[b]) then
            used[a], used[b] = true, true
            -- The label offered is where it takes you: you're on the other one
            toggles[#toggles + 1] = { a, b, hasA and b or a, function(label) Press(label) end }
        end
    end
    -- Fishing finds live in The Fishing Log's album, which the Collection replaces: offer them here
    if tab == "journal" and not state.recap and (state.view == "zones" or state.view == "fish" or state.view == "cards" or state.view == nil) then
        if MF.albumFinds and state.view == "cards" then
            commands[#commands + 1] = { "Fish cards", function() MF.albumFinds = false GoCollection() end }
        else
            commands[#commands + 1] = { "Fishing finds", function()
                MF.albumFinds = true
                if not Press("Album") then MF:RedrawJournal() end
            end }
        end
    end
    for _, a in ipairs(state.actions or {}) do
        -- (the recap's Continue is the big button at the bottom of the page)
        -- ("Invites (2)" carries its count, so it's matched by its start)
        if not used[a.label] and not NAV_LABELS[a.label] and not a.label:find("^Invites")
            and not (state.recap and a.label == "Continue") then
            local label = a.label
            commands[#commands + 1] = { label, function() Press(label) end }
        end
    end
    return { tabs = tabs, toggles = toggles, commands = commands }
end

-- ---------------------------------------------------------------------------
-- Drawing it; returns the height it takes (0 when the page has nothing to offer)
-- ---------------------------------------------------------------------------
-- Everything on the right in one menu (the game's own dropdown menus)
function N:Menu(strip, spec)
    local m = strip.menu
    if not m then
        m = Command(strip)
        strip.menu = m
    end
    local n = #spec.toggles + #spec.commands
    SetCommand(m, ("Options (%d)"):format(n), function()
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(m, function(_, root)
                for i, tg in ipairs(spec.toggles) do
                    if i > 1 then root:CreateDivider() end
                    for _, label in ipairs({ tg[1], tg[2] }) do
                        root:CreateRadio(label, function() return tg[3] == label end, function()
                            if tg[3] ~= label then tg[4](label) end
                        end)
                    end
                end
                if #spec.toggles > 0 and #spec.commands > 0 then root:CreateDivider() end
                for _, cmd in ipairs(spec.commands) do root:CreateButton(cmd[1], cmd[2]) end
            end)
        else
            -- No menu system: run the first command (never happens on this client)
            if spec.commands[1] then spec.commands[1][2]() end
        end
    end)
    m:ClearAllPoints()
    m:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 3)
    m.spec = spec
    if not m.tipped then
        m.tipped = true
        W:Tip(m, "Options", function(self)
            local names = {}
            for _, tg in ipairs(self.spec.toggles) do names[#names + 1] = tg[3] end
            for _, cmd in ipairs(self.spec.commands) do names[#names + 1] = cmd[1] end
            return "Now: " .. table.concat(names, ", ")
        end)
    end
end

function N:Build(f)
    local strip = CreateFrame("Frame", nil, f.body)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(H)
    strip.rule = W:Divider(strip, 100)
    strip.rule:SetPoint("BOTTOMLEFT", 0, -2)
    strip.rule:SetPoint("BOTTOMRIGHT", 0, -2)
    strip.tabs, strip.toggles, strip.commands = {}, {}, {}
    strip:Hide()
    self.strip = strip
end

function N:Apply(state, tfl)
    MF = tfl
    local f = J:Frame()
    if not self.strip then self:Build(f) end
    local strip = self.strip
    local spec = self:Spec(state)
    for _, list in ipairs({ strip.tabs, strip.toggles, strip.commands }) do for _, w in ipairs(list) do w:Hide() end end
    if #spec.tabs == 0 and #spec.toggles == 0 and #spec.commands == 0 then
        strip:Hide()
        return 0
    end
    strip:Show()
    local x = 0
    for i, t in ipairs(spec.tabs) do
        local b = strip.tabs[i] or Tab(strip)
        strip.tabs[i] = b
        SetTab(b, t[1], t[2] and true or false, t[3])
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
        x = x + b:GetWidth() + 2
    end
    -- Filters and commands on the right, if they fit beside the tabs; otherwise one "Options" menu
    local avail = (f.body:GetWidth() or 800) - x - 16
    local need = 0
    for _, cmd in ipairs(spec.commands) do
        local probe = strip.probe or W:Label(strip, "GameFontNormalSmall")
        strip.probe = probe
        probe:SetText(cmd[1])
        need = need + (probe:GetStringWidth() or 50) + 26
    end
    for _, tg in ipairs(spec.toggles) do
        local probe = strip.probe or W:Label(strip, "GameFontHighlightSmall")
        strip.probe = probe
        probe:SetText(tg[1] .. tg[2])
        need = need + (probe:GetStringWidth() or 80) + 44
    end
    if strip.probe then strip.probe:SetText("") end
    if need > avail and (#spec.commands + #spec.toggles) > 0 then
        self:Menu(strip, spec)
        return H + 8
    end
    if strip.menu then strip.menu:Hide() end
    local right = 0
    for i = #spec.commands, 1, -1 do
        local cmd = spec.commands[i]
        local c = strip.commands[i] or Command(strip)
        strip.commands[i] = c
        SetCommand(c, cmd[1], cmd[2])
        c:ClearAllPoints()
        c:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -right, 3)
        right = right + c:GetWidth() + 6
    end
    for i = #spec.toggles, 1, -1 do
        local tg = spec.toggles[i]
        local t = strip.toggles[i] or Toggle(strip)
        strip.toggles[i] = t
        SetToggle(t, tg[1], tg[2], tg[3], tg[4])
        t:ClearAllPoints()
        t:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -right, 3)
        right = right + t:GetWidth() + 8
    end
    return H + 8
end
