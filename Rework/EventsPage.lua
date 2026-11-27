-- Events: the noticeboard as posters.
--   list    each event a card: the day and time, the title, the water, the format, who's hosting,
--           how full it is (a bar), and running / in 3h / finished; a tick on the ones you're in
--   detail  the event in full: when and where, format, host, the live or final standings with medals,
--           and everyone signed up; Sign up / Withdraw / Cancel are The Fishing Log's own buttons
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
-- The event The Fishing Log has open in its detail view. Its detail page asks MF:MatchIDFor(n) about
-- exactly that one notice (its list never does), so we listen to that while its Events page builds.
local shownId

local function Countdown(seconds)
    local floor = math.floor
    if seconds >= 86400 then return ("%dd %dh"):format(floor(seconds / 86400), floor(seconds % 86400 / 3600)) end
    if seconds >= 3600 then return ("%dh %dm"):format(floor(seconds / 3600), floor(seconds % 3600 / 60)) end
    return ("%dm"):format(math.max(1, math.ceil(seconds / 60)))
end

local STATUS = {
    started = "|cff3ee63eRunning now|r", finished = "|cffa0a0a0Finished|r",
    nostart = "|cffff5a5aDidn't start|r", cancelled = "|cffff5a5aCancelled|r",
}
local function StateText(n)
    if n.status ~= "open" then return STATUS[n.status] or tostring(n.status) end
    local left = n.startsAt - GetServerTime()
    return left > 0 and ("|cffffd100in " .. Countdown(left) .. "|r") or "|cffffd100Starting|r"
end

local function FormatText(n)
    local parts = { MF.MODES[n.mode] or "?", ("%d min"):format(math.floor((n.duration or 0) / 60)) }
    if n.fish then parts[#parts + 1] = MF:FishName(n.fish) .. " only" end
    local flags = n.flags or ""
    if flags:find("t") then parts[#parts + 1] = "teams" end
    if flags:find("h") then parts[#parts + 1] = "handicap" end
    return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------
-- List
-- ---------------------------------------------------------------------------
local function EventCard()
    local c = W:Card(nil, true)
    c.day = W:Label(c, "GameFontNormalSmall")
    c.day:SetPoint("TOPLEFT", 14, -12)
    c.day:SetWidth(54)
    c.time = W:Label(c, "GameFontHighlightLarge")
    c.time:SetPoint("TOPLEFT", c.day, "BOTTOMLEFT", 0, -3)
    c.sep = c:CreateTexture(nil, "ARTWORK")
    c.sep:SetColorTexture(1, 0.82, 0, 0.25)
    c.sep:SetWidth(1)
    c.sep:SetPoint("TOPLEFT", 76, -8)
    c.sep:SetPoint("BOTTOMLEFT", 76, 8)
    c.title = W:Label(c, "GameFontNormal")
    c.title:SetPoint("TOPLEFT", 90, -10)
    c.title:SetJustifyH("LEFT")
    c.title:SetWordWrap(false)
    c.sub = W:Label(c, "GameFontHighlightSmall")
    c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
    c.sub:SetJustifyH("LEFT")
    c.sub:SetWordWrap(false)
    c.host = W:Label(c, "GameFontDisableSmall")
    c.host:SetPoint("TOPLEFT", c.sub, "BOTTOMLEFT", 0, -4)
    c.state = W:Label(c, "GameFontHighlight")
    c.state:SetPoint("TOPRIGHT", -14, -10)
    c.bar = W:Bar(c, 120, 12, 0.3, 0.6, 0.9)
    c.bar:SetPoint("TOPRIGHT", c.state, "BOTTOMRIGHT", 0, -8)
    c.bar.text:SetFontObject("GameFontHighlightSmall")
    c.tick = W:Label(c, "GameFontNormal")
    c.tick:SetPoint("BOTTOMRIGHT", -14, 8)
    c:SetScript("OnClick", function(self)
        local n = self.item and self.item.n
        if n then W:Sound("row") MF:OpenEvent(n.id) end
    end)
    c:SetScript("OnEnter", function(self)
        local n = self.item and self.item.n
        if not n then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(n.title or "Event", 1, 0.82, 0)
        GameTooltip:AddLine(FormatText(n), 1, 1, 1, true)
        GameTooltip:AddLine("Click for the details and to sign up.", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return c
end

local function FillEvent(c, it)
    local n = it.n
    c.day:SetText(date("%a %d", n.startsAt):upper())
    c.time:SetText(date("%H:%M", n.startsAt))
    c.title:SetText((n.title or "Event") .. (n.guild and "  |cff3ee63e<guild>|r" or ""))
    c.sub:SetText(("%s  |cffa0a0a0%s|r"):format(n.spotName or "?", FormatText(n)))
    c.host:SetText("hosted by " .. MF:ShortName(n.host))
    c.state:SetText(StateText(n))
    local count, max = MF:SignupCount(n), n.maxPlayers or 0
    c.bar:Set(count, math.max(1, max), ("%d / %d anglers"):format(count, max))
    if count >= max and max > 0 then c.bar:SetColor(0.8, 0.5, 0.1) else c.bar:SetColor(0.3, 0.6, 0.9) end
    c.tick:SetText(MF:IsSignedUp(n) and (TICK .. " |cff3ee63esigned up|r") or "")
    local live = n.status == "started"
    c:SetEdge(live and 0.25 or 0.5, live and 0.9 or 0.42, live and 0.25 or 0.25, 0.95)
    local faded = n.status ~= "open" and n.status ~= "started"
    c:SetAlpha(faded and 0.65 or 1)
    local w = (c:GetWidth() or 500) - 90 - 150
    c.title:SetWidth(math.max(80, w))
    c.sub:SetWidth(math.max(80, w))
end

-- ---------------------------------------------------------------------------
-- Detail
-- ---------------------------------------------------------------------------
local NAME_WIDTH = 170

local function StandRow()
    local r = CreateFrame("Frame")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.place = W:Label(r, "GameFontNormal")
    r.place:SetPoint("LEFT", 10, 0)
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", 50, 0)
    r.name:SetWidth(NAME_WIDTH)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.score = W:Label(r, "GameFontHighlight")
    r.score:SetPoint("RIGHT", -10, 0)
    -- What the score is made of: the fish's icon and name, or a short tally.
    r.detail = W:Label(r, "GameFontHighlightSmall")
    r.detail:SetPoint("RIGHT", r.score, "LEFT", -14, 0)
    r.detail:SetJustifyH("RIGHT")
    r.detail:SetWordWrap(false)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:SetPoint("RIGHT", r.detail, "LEFT", -6, 0)
    return r
end

local function Make(kind)
    if kind == "event" then return EventCard() end
    if kind == "stand" then return StandRow() end
    if kind == "note" then
        local fr = CreateFrame("Frame")
        fr.text = W:Label(fr, "GameFontDisableSmall")
        fr.text:SetPoint("LEFT", 6, 0)
        fr.text:SetPoint("RIGHT", -6, 0)
        fr.text:SetJustifyH("LEFT")
        return fr
    end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, "GameFontNormal")
    fr.text:SetPoint("BOTTOMLEFT", 4, 6)
    fr.rule = W:Divider(fr, 100)
    fr.rule:SetPoint("BOTTOMLEFT", 0, 2)
    fr.rule:SetPoint("BOTTOMRIGHT", 0, 2)
    return fr
end

local function Fill(fr, it)
    if it.kind == "event" then FillEvent(fr, it) return end
    if it.kind == "note" then fr.text:SetText(it.text) return end
    if it.kind == "stand" then
        W:Place(fr.place, it.place)
        fr.name:SetText(it.name)
        if it.mine then fr.name:SetTextColor(1, 0.62, 0) else fr.name:SetTextColor(1, 1, 1) end
        fr.score:SetText(it.score)
        -- The name keeps its room; a long fish name gives way, not the angler.
        -- Measured unconstrained first, so a short one sits right by the score.
        fr.detail:SetWidth(0)
        fr.detail:SetText(it.detail or "")
        local room = (fr:GetWidth() or 0) - 50 - 10 - (fr.score:GetStringWidth() or 0) - 14
            - NAME_WIDTH - 12 - (it.icon and 24 or 0)
        local wide = fr.detail.GetUnboundedStringWidth and fr.detail:GetUnboundedStringWidth()
            or fr.detail:GetStringWidth() or 0
        fr.detail:SetWidth(math.max(40, math.min(wide + 2, room)))
        fr.icon:SetShown(it.icon ~= nil)
        if it.icon then fr.icon:SetTexture(it.icon) end
        fr.bg:SetColorTexture(1, 0.62, 0, it.mine and 0.14 or (it.index % 2 == 0 and 0.03 or 0))
        return
    end
    fr.text:SetText(it.text)
end

function P:Build(frame)
    self.list = W:VList(frame, Make, Fill)
    self.list:SetPoint("TOPLEFT")
    self.list:SetPoint("BOTTOMRIGHT", -16, 0)

    -- An empty board: a big invitation, its button is The Fishing Log's "Post event"
    local empty = CreateFrame("Frame", nil, frame)
    empty:SetSize(420, 220)
    empty:SetPoint("CENTER", 0, 20)
    empty.icon = W:FramedIcon(empty, 60, "Interface\\Icons\\INV_Misc_Note_02")
    empty.icon:SetPoint("TOP")
    empty.title = W:Label(empty, "GameFontNormalLarge", "No events planned")
    empty.title:SetPoint("TOP", empty.icon, "BOTTOM", 0, -20)
    empty.note = W:Label(empty, "GameFontHighlight", "Pick a water, set a time, and invite your rivals. Everyone with the addon sees it here.")
    empty.note:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
    empty.note:SetWidth(400)
    empty.note:SetTextColor(0.8, 0.8, 0.8)
    empty.post = W:Button(empty, "Post an event", 160, 26, function() J:PressAction("Post event") end)
    empty.post:SetPoint("TOP", empty.note, "BOTTOM", 0, -18)
    empty:Hide()
    self.empty = empty

    -- The detail view
    local d = CreateFrame("Frame", nil, frame)
    d:SetAllPoints()
    d:Hide()
    self.detail = d
    local head = W:Panel(d, 0.88)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(108)
    head.icon = W:FramedIcon(head, 52, "Interface\\Icons\\INV_Misc_Note_02")
    head.icon:SetPoint("TOPLEFT", 18, -18)
    head.title = W:Label(head, "GameFontNormalLarge")
    head.title:SetPoint("TOPLEFT", 86, -16)
    head.state = W:Label(head, "GameFontHighlightLarge")
    head.state:SetPoint("TOPRIGHT", -16, -16)
    head.facts = {}
    for i = 1, 4 do
        local l = W:Label(head, "GameFontDisableSmall")
        local v = W:Label(head, "GameFontHighlightSmall")
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        l:SetPoint("TOPLEFT", 86 + col * 300, -44 - row * 30)
        v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -2)
        v:SetWidth(290)
        v:SetJustifyH("LEFT")
        v:SetWordWrap(false)
        head.facts[i] = { l, v }
    end
    self.head = head

    local signed = W:Panel(d, 0.7)
    signed:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -8)
    signed:SetPoint("BOTTOMRIGHT")
    signed:SetWidth(240)
    signed.title = W:Header(signed, "Signed up", 210)
    signed.title:SetPoint("TOPLEFT", 12, -10)
    signed.names = W:Label(signed, "GameFontHighlightSmall")
    signed.names:SetPoint("TOPLEFT", 14, -36)
    signed.names:SetWidth(212)
    signed.names:SetJustifyH("LEFT")
    signed.names:SetSpacing(4)
    self.signed = signed

    self.stand = W:VList(d, Make, Fill)
    self.stand:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    self.stand:SetPoint("BOTTOMRIGHT", signed, "BOTTOMLEFT", -24, 0)
    self.standNote = W:Label(d, "GameFontDisable")
    self.standNote:SetPoint("CENTER", self.stand, "CENTER")
    self.standNote:SetWidth(340)
end

function P:RefreshList()
    self.detail:Hide()
    local list = MF:BoardNotices()
    local items = {}
    local group
    for _, n in ipairs(list) do
        local g = (n.status == "open" or n.status == "started") and "Coming up" or "Past events"
        if g ~= group then
            group = g
            items[#items + 1] = { kind = "head", h = 30, text = g }
        end
        items[#items + 1] = { kind = "event", h = 66, gap = 6, n = n }
    end
    self.items = items
    self.list:SetItems(items, true)
    self.list:SetShown(#list > 0)
    self.empty:SetShown(#list == 0)
end

-- Your invitations: the same cards, each with who asked you.
function P:RefreshInvites()
    self.detail:Hide()
    self.empty:Hide()
    local items = {}
    for _, inv in ipairs(MF:EventInvites()) do
        items[#items + 1] = { kind = "head", h = 30, text = "Invited by |cffffffff" .. MF:ShortName(inv.from) .. "|r" }
        items[#items + 1] = { kind = "event", h = 66, gap = 6, n = inv.n }
    end
    if #items == 0 then
        items[1] = { kind = "note", h = 40,
            text = "No invitations right now. When an angler invites you to an event, it shows up here." }
    end
    self.items = items
    self.list:SetItems(items, true)
    self.list:Show()
end

function P:RefreshDetail(n)
    self.shownTitle = n.title
    self.list:Hide()
    self.list.bar:Hide()
    self.empty:Hide()
    self.detail:Show()
    local head = self.head
    head.title:SetText((n.title or "Event") .. (n.guild and "  |cff3ee63e<guild>|r" or ""))
    head.state:SetText(StateText(n))
    local hostInfo = MF:AnglerInfo(n.host)
    local facts = {
        { "WHEN", date("%A %d %B, %H:%M", n.startsAt) },
        { "WHERE", n.spotName or "?" },
        { "FORMAT", FormatText(n) },
        { "HOST", MF:ShortName(n.host) .. (hostInfo and hostInfo.rank and ("  |cffa0a0a0" .. MF:RankName(hostInfo.rank) .. "|r") or "") },
    }
    for i, fact in ipairs(facts) do
        head.facts[i][1]:SetText(fact[1])
        head.facts[i][2]:SetText(fact[2])
    end

    local items = {}
    local m = MF.matches and MF.matches[MF:MatchIDFor(n)]
    local notes = {}
    if m and not m.cancelled then
        local now = GetServerTime()
        local clock = m.finished and "" or ("  |cffa0a0a0" .. (now < m.startsAt and "starts in " or "") ..
            MF:FormatClock(math.max(0, (now < m.startsAt and m.startsAt or m.endsAt) - now)) .. "|r")
        items[#items + 1] = { kind = "head", h = 30, text = (m.finished and "Final standings" or "Live standings") .. clock }
        if m.team then
            for i, team in ipairs(MF:TeamStandings(m)) do
                local fish = MF:StandingFish(team.p, m)
                items[#items + 1] = { kind = "stand", h = 28, place = team.place or i, index = i,
                    name = MF:TeamLabel(team.name), score = MF:FormatScore(team.p, m),
                    detail = MF:StandingDetail(team.p, m), icon = fish and MF:FishIcon(fish) }
            end
            items[#items + 1] = { kind = "head", h = 30, text = "Anglers" }
        end
        for i, a in ipairs(MF:Standings(m)) do
            local fish = MF:StandingFish(a.p, m)
            items[#items + 1] = { kind = "stand", h = 28, place = a.place or i, index = i, mine = MF:IsMe(a.name),
                name = MF:ShortName(a.name), score = MF:FormatScore(a.p, m),
                detail = MF:StandingDetail(a.p, m), icon = fish and MF:FishIcon(fish) }
        end
        -- Everyone signed up has a line, so the late are seen as late rather than missing.
        -- Shown only: they join the standings (and the results) when they join the match.
        if not m.finished then
            local absent = MF:AbsentSignups(m)
            for i, name in ipairs(absent) do
                items[#items + 1] = { kind = "stand", h = 28, index = #items + i, mine = MF:IsMe(name), absent = true,
                    name = "|cff858585" .. MF:ShortName(name) .. "|r", score = "|cff858585not here yet|r" }
            end
        end
    end
    if m and not m.cancelled then
        notes[#notes + 1] = "Equal scores share places and finish as a draw; draws award participation XP only."
        if m.team then notes[#notes + 1] = "Teams compete for team win XP; individual Tournament Champion titles aren't awarded in team events." end
    end
    if n.champion then
        items[#items + 1] = { kind = "head", h = 30, text = "Champion: |cffffffff" .. MF:ShortName(n.champion) .. "|r" }
    end
    if n.results then notes[#notes + 1] = "|cffffffffResults:|r " .. n.results end
    for _, text in ipairs(notes) do items[#items + 1] = { kind = "note", h = 30, text = text } end
    self.stand:SetItems(items, true)
    local hasStandings = m and not m.cancelled
    self.standNote:SetShown(not hasStandings)
    self.standNote:SetText(n.status == "open" and "Standings appear here once the match starts." or
        (n.status == "started" and "The match is running. Standings arrive from the anglers taking part.") or
        "No standings were recorded.")

    local names = {}
    for name in pairs(n.signups or {}) do names[#names + 1] = name end
    table.sort(names)
    local text = {}
    for _, name in ipairs(names) do
        local mine = MF:IsMe(name)
        text[#text + 1] = (mine and "|cffff9d00" or "|cffffffff") .. MF:ShortName(name) .. "|r" ..
            (name == n.host and "  |cffa0a0a0host|r" or "")
    end
    self.signed.title:SetText(("Signed up  |cffa0a0a0%d / %d|r"):format(MF:SignupCount(n), n.maxPlayers or 0))
    local inviter = MF.EventInviteFrom and MF:EventInviteFrom(n)
    self.signed.names:SetText((inviter and ("|cffa0a0a0Invited by|r |cffffffff" .. MF:ShortName(inviter) .. "|r\n\n") or "")
        .. (#text > 0 and table.concat(text, "\n") or "|cff858585Nobody yet.|r"))
end

local function InDetail(state)
    for _, a in ipairs(state.actions or {}) do if a.label == "Back" then return true end end
    return false
end

function P:Refresh(state)
    if InDetail(state) then
        local n = shownId and MF.db.notices and MF.db.notices[shownId]
        if n then self:RefreshDetail(n) return end
    end
    if MF.EventView and MF:EventView() == "invites" then self:RefreshInvites() return end
    self:RefreshList()
end

ns.EventsPage = P
J:AddPage({
    key = "events",
    match = function(state)
        if state.recap or state.tab ~= "board" then return false end
        local db = state.MF.db
        -- Turned off in its options: its own page says so
        if not db.settings.noticeboard and not InDetail(state) then return false end
        -- A detail view we didn't open ourselves (we don't know which event): The Fishing Log's own
        if InDetail(state) and not (shownId and db.notices and db.notices[shownId]) then return false end
        return true
    end,
    live = true, -- its clocks count down
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function(_, state) P:Refresh(state) end,
    subheading = function(state)
        if InDetail(state) then return "Event" end
        return (MF and MF.EventView and MF:EventView() == "invites") and "Your invitations" or "The noticeboard"
    end,
    count = function()
        if P.detail and P.detail:IsShown() then return "" end
        if MF and MF.EventView and MF:EventView() == "invites" then
            local n = #MF:EventInvites()
            return n == 1 and "1 invite" or (n .. " invites")
        end
        local n = 0
        for _, it in ipairs(P.items or {}) do if it.kind == "event" then n = n + 1 end end
        return n == 1 and "1 event" or (n .. " events")
    end,
})

-- The Fishing Log opens events from elsewhere too (the board's journal button in a match, links):
-- note which one, so our detail view can show it
ns:OnSetup("journal", function(tfl)
    if not tfl.MatchIDFor then return end
    local building, seen = false, nil
    local matchFor = tfl.MatchIDFor
    tfl.MatchIDFor = function(self, n, ...)
        if building and n and n.id then seen = n.id end
        return matchFor(self, n, ...)
    end
    for _, tab in ipairs(tfl.JOURNAL_TABS or {}) do
        if tab.key == "board" then
            local build = tab.build
            tab.build = function(...)
                building, seen = true, nil
                local ok, a, b, c = pcall(build, ...)
                building = false
                shownId = seen
                if not ok then error(a, 0) end
                return a, b, c
            end
        end
    end
end)
