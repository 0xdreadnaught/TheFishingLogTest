-- NoticeboardUI: the Events tab in the Angler's Journal (list and details)
-- and the "Post event" form.
local _, MF = ...
-- A dormant copy (Core.lua) leaves the running copy's dialogs alone.
local POPUPS = MF.inert and {} or StaticPopupDialogs

local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
local GUILD_TAG = " |cff3ee63e<guild>|r"
local MODE_ORDER = { "weight", "biggest", "count", "specimen" }
local STATUS_TEXT = {
    started = "|cff3ee63erunning now|r",
    finished = "|cffa0a0a0finished|r",
    nostart = "|cffff5a5adidn't start|r",
    cancelled = "|cffff5a5acancelled|r",
}

local selected -- id of the notice shown in detail, or nil for the list
local invitesView = false -- the list is your invitations rather than every event

local function Header(text) return { text = "|cffffd100" .. text .. "|r", header = true } end
local function Blank() return { text = "" } end

local floor = math.floor

local function Countdown(seconds)
    if seconds >= 86400 then
        return ("%dd %dh"):format(floor(seconds / 86400), floor(seconds % 86400 / 3600))
    elseif seconds >= 3600 then
        return ("%dh %dm"):format(floor(seconds / 3600), floor(seconds % 3600 / 60))
    end
    return ("%dm"):format(math.max(1, math.ceil(seconds / 60)))
end

-- "in 2h 14m", "starting", or the status for events that aren't upcoming.
local function StateText(n)
    if n.status ~= "open" then return STATUS_TEXT[n.status] or n.status end
    local left = n.startsAt - GetServerTime()
    return left > 0 and ("in " .. Countdown(left)) or "starting"
end

local function FormatText(self, n)
    local parts = { self.MODES[n.mode], ("%d min"):format(floor(n.duration / 60)) }
    if n.fish then parts[#parts + 1] = self:FishName(n.fish) .. " only" end
    if n.flags:find("t") then parts[#parts + 1] = "teams" end
    if n.flags:find("h") then parts[#parts + 1] = "handicap" end
    return table.concat(parts, ", ")
end

local function Select(self, id)
    selected = id
    self:RedrawJournal()
end

function MF:OpenMatchEvent(m)
    local n = m and self:NoticeForMatch(m.id)
    if not n then return end
    selected = n.id
    self:OpenJournal("board")
end

function MF:OpenEvent(id)
    selected = id
    self:OpenJournal("board")
end

-- Which view the Events tab is on: "detail", "invites" or "list".
function MF:EventView()
    if selected then return "detail" end
    return invitesView and "invites" or "list"
end

function MF:OpenEventList()
    selected, invitesView = nil, false
    self:OpenJournal("board")
    self:RedrawJournal()
end

function MF:OpenEventInvites()
    selected, invitesView = nil, true
    self:OpenJournal("board")
    self:RedrawJournal()
end

local function InvitesLabel(self)
    local count = self:EventInviteCount()
    return count > 0 and ("Invites (%d)"):format(count) or "Invites"
end

------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------

local function ListLines(self)
    local out = { Header("Events") }
    local list = self:BoardNotices()
    if #list == 0 then
        out[#out + 1] = { text = "|cff858585No events posted yet - post one and invite your rivals.|r" }
        out.empty = { title = "No events planned", note = "Pick a water, set a time, and invite your rivals." }
    end
    for _, n in ipairs(list) do
        local open = function() Select(self, n.id) end
        out[#out + 1] = {
            text = (self:IsSignedUp(n) and TICK or "") .. date("%a %H:%M", n.startsAt) .. "  "
                .. n.title .. (n.guild and GUILD_TAG or ""),
            right = ("%d/%d - %s"):format(self:SignupCount(n), n.maxPlayers, StateText(n)),
            onClick = open,
        }
        out[#out + 1] = {
            text = ("    |cffa0a0a0%s - %s - by %s|r"):format(n.spotName, self.MODES[n.mode], self:ShortName(n.host)),
            onClick = open,
        }
    end
    return out, { { label = "Post event", onClick = function() self:ShowPostForm() end },
        { label = InvitesLabel(self), onClick = function() self:OpenEventInvites() end } }
end

-- Events you've been invited to, and by whom.
local function InviteLines(self)
    local out = { Header("Invites") }
    local list = self:EventInvites()
    if #list == 0 then
        out[#out + 1] = { text = "|cff858585No invitations right now. When an angler invites you to an event, it shows up here.|r" }
        out.empty = { title = "No invitations", note = "When an angler invites you to an event, it shows up here." }
    end
    for _, inv in ipairs(list) do
        local n = inv.n
        local open = function() Select(self, n.id) end
        out[#out + 1] = {
            text = (self:IsSignedUp(n) and TICK or "") .. date("%a %H:%M", n.startsAt) .. "  " .. n.title,
            right = ("%d/%d - %s"):format(self:SignupCount(n), n.maxPlayers, StateText(n)),
            onClick = open,
        }
        out[#out + 1] = {
            text = ("    |cffa0a0a0%s - invited by %s|r"):format(n.spotName, self:ShortName(inv.from)),
            onClick = open,
        }
    end
    return out, { { label = "All events", onClick = function() self:OpenEventList() end } }
end

------------------------------------------------------------------------
-- One event
------------------------------------------------------------------------

local function DetailLines(self, n)
    local out = { Header(n.title .. (n.guild and GUILD_TAG or "")) }
    local hostInfo = self:AnglerInfo(n.host)
    out[#out + 1] = { text = "Host", right = self:ShortName(n.host)
        .. (hostInfo and hostInfo.rank and (" (" .. self:RankName(hostInfo.rank) .. ")") or "") }
    out[#out + 1] = { text = "Where", right = n.spotName }
    out[#out + 1] = { text = "When", right = date("%A %d %b, %H:%M", n.startsAt) .. " - " .. StateText(n) }
    out[#out + 1] = { text = "Format", right = FormatText(self, n) }
    local inviter = self:EventInviteFrom(n)
    if inviter then out[#out + 1] = { text = "Invited by", right = self:ShortName(inviter) } end
    local m = self.matches[self:MatchIDFor(n)]
    if m and not m.cancelled then
        local now = GetServerTime()
        out[#out + 1] = Blank()
        out[#out + 1] = Header(m.finished and "Final standings" or "Live match")
        self:NoteRows(out, "Equal scores share places and finish as a draw; draws award participation XP only.")
        if m.team then self:NoteRows(out, "Teams compete for team win XP; individual Tournament Champion titles are not awarded in team events.") end
        out[#out + 1] = { text = m.finished and "Finished" or (now < m.startsAt and "Starts in" or "Time remaining"),
            right = not m.finished and self:FormatClock(math.max(0, (now < m.startsAt and m.startsAt or m.endsAt) - now)) or "" }
        if m.team then
            for i, team in ipairs(self:TeamStandings(m)) do
                out[#out + 1] = { text = ("%d. %s"):format(team.place or i, self:TeamLabel(team.name)), right = self:FormatScore(team.p, m) }
            end
            out[#out + 1] = Blank()
        end
        for i, angler in ipairs(self:Standings(m)) do
            local mine = self:IsMe(angler.name)
            local detail = self:StandingDetail(angler.p, m)
            out[#out + 1] = { text = (mine and self.C.good or self.C.text)
                .. ("%d. %s"):format(angler.place or i, self:ShortName(angler.name)) .. "|r",
                right = (detail ~= "" and (detail .. "   ") or "") .. self:FormatScore(angler.p, m),
                mine = mine, group = true }
        end
        if not m.finished then
            for _, name in ipairs(self:AbsentSignups(m)) do
                out[#out + 1] = { text = "|cff858585    " .. self:ShortName(name) .. "|r", right = "|cff858585not here yet|r" }
            end
        end
    end
    if n.champion then
        out[#out + 1] = { text = "Champion", right = "|cffffd100" .. self:ShortName(n.champion) .. "|r" }
    end
    if n.results then
        out[#out + 1] = { text = "Results" }
        out[#out + 1] = { text = "    " .. n.results }
    end

    out[#out + 1] = Blank()
    out[#out + 1] = Header(("Signed up (%d/%d)"):format(self:SignupCount(n), n.maxPlayers))
    local names = {}
    for name in pairs(n.signups) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        out[#out + 1] = { text = "    " .. self:ShortName(name) .. (name == n.host and " |cffa0a0a0(host)|r" or "") }
    end

    local actions = { { label = "Back", onClick = function() Select(self, nil) end } }
    if m and self.current == m and not m.finished and not m.cancelled then
        actions[#actions + 1] = { label = self:IsMe(m.host) and "Cancel match" or "Leave match",
            onClick = function() if self:IsMe(m.host) then self:CancelMatch() else self:LeaveMatch() end self:RefreshJournal() end }
    elseif m and not m.finished and not m.cancelled and GetServerTime() < m.endsAt and not self:InMatch() then
        -- Arrived late, missed the pop-up or said No to it: still in time to fish
        actions[#actions + 1] = { label = "Join match", onClick = function() self:JoinMatch(nil, m.id) self:RefreshJournal() end }
    end
    if self:CanInviteToEvent(n) then
        actions[#actions + 1] = { label = "Invite", onClick = function() self:PromptEventInvite(n) end }
    end
    if n.status == "open" then
        if self:IsMe(n.host) then
            actions[#actions + 1] = { label = "Cancel event", onClick = function() self:CancelNotice(n) end }
        elseif self:IsSignedUp(n) then
            actions[#actions + 1] = { label = "Withdraw", onClick = function() self:SignUp(n, false) end }
        else
            actions[#actions + 1] = { label = "Sign up", onClick = function() self:SignUp(n, true) end }
            if inviter then
                actions[#actions + 1] = { label = "Decline", onClick = function()
                    self:DeclineEventInvite(n)
                    Select(self, nil)
                end }
            end
        end
    end
    -- Under way, and we never heard the match (or Join match would be here): signing up now
    -- asks the host to send it
    local running = m and not m.finished and not m.cancelled and GetServerTime() < m.endsAt
    if not running and n.status ~= "open" and self:CanSignUpLate(n) and not self:IsSignedUp(n) and not self:IsMe(n.host) then
        actions[#actions + 1] = { label = "Sign up late", onClick = function() self:SignUp(n, true) end }
    end
    if not self:IsMe(n.host) then
        actions[#actions + 1] = { label = "Hide host", onClick = function()
            self:HideHost(n.host)
            Select(self, nil)
        end }
    end
    return out, actions
end

MF:AddJournalTab("board", "Events", function(self)
    if not self.db.settings.noticeboard and not selected then
        return { { text = "|cff858585The noticeboard is turned off in the options.|r" } }
    end
    local n = selected and self.db.notices[selected]
    if n and not self.db.hiddenHosts[n.host] then return DetailLines(self, n) end
    selected = nil
    if invitesView then return InviteLines(self) end
    return ListLines(self)
end)

------------------------------------------------------------------------
-- Invites: asking who, and being asked
------------------------------------------------------------------------

-- The dialog's edit box has gone by more than one name across clients.
local function EditBoxOf(dialog)
    return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

POPUPS["THEFISHINGLOG_EVENT_INVITE_WHO"] = {
    text = "Invite an angler to %s\n\nTheir name (or leave it for your target):",
    button1 = "Invite",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 64,
    OnShow = function(dialog)
        local box = EditBoxOf(dialog)
        if box then
            box:SetText(MF:TargetPlayerName() and MF:ShortName(MF:TargetPlayerName()) or "")
            box:SetFocus()
        end
    end,
    OnAccept = function(dialog, n)
        local box = EditBoxOf(dialog)
        MF:InviteToEvent(n, box and box:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        MF:InviteToEvent(dialog.data, box:GetText() or "")
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function MF:PromptEventInvite(n)
    if not self:CanInviteToEvent(n) then return end
    StaticPopup_Show("THEFISHINGLOG_EVENT_INVITE_WHO", n.title, nil, n)
end

POPUPS["THEFISHINGLOG_EVENT_INVITED"] = {
    text = "%s",
    button1 = "Sign up",
    button2 = "Not now",
    OnAccept = function(_, n) if n then MF:SignUp(n, true) end end,
    -- Left in Invites either way; Decline there takes it off the list.
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
}

function MF:ShowEventInvite(n, from)
    local text = ("%s invited you to |cffffd100%s|r\n%s at %s, %s.\n\nSign up?"):format(
        self:ShortName(from), n.title, date("%A %H:%M", n.startsAt), n.spotName, FormatText(self, n):lower())
    StaticPopup_Show("THEFISHINGLOG_EVENT_INVITED", text, nil, n)
end

MF:OnTick(function(self)
    if selected then self:RefreshJournal() end
end)

------------------------------------------------------------------------
-- Post event form
------------------------------------------------------------------------

local form
local state -- values being edited

local function DefaultState()
    -- An hour from now, rounded up to the next quarter hour.
    local now=time()
    local t = date("*t", now + 3600)
    local minutes = math.ceil((t.hour * 60 + t.min) / 15) * 15
    local day = date("%Y%j",now)~=date("%Y%j",now+3600) and 1 or 0
    if minutes >= 1440 then day, minutes = day+1, minutes - 1440 end
    return { day = day, minutes = minutes, length = 30, mode = 1, players = 10,
        team = false, hcp = false, guild = false }
end

local function StartTime()
    local t = date("*t")
    t.day = t.day + state.day
    t.hour, t.min, t.sec = math.floor(state.minutes / 60), state.minutes % 60, 0
    return time(t)
end

-- The form reads top to bottom as the questions a host is answering: what
-- and where, when, how it's won, and who can come. Every choice is a row
-- of buttons showing all the options at once, rather than a value nudged
-- with - and + until the right one comes round, and each format and switch
-- says what it does in a line beside it. The bottom line reads the whole
-- event back as a sentence, so the host sees what they are posting.

local W = 470
local LEFT, FIELD = 20, 112 -- labels, and where the fields start

-- What each format means, in the words a player would use to explain it.
local FORMAT_INFO = {
    weight   = { label = "Heaviest bag",
        text = "Every fish you land goes in your bag. The heaviest bag at the end wins." },
    biggest  = { label = "Biggest fish",
        text = "Only your single heaviest fish counts. The biggest one landed wins." },
    count    = { label = "Most fish",
        text = "Every fish counts as one, whatever it weighs. Whoever lands the most wins." },
    specimen = { label = "First specimen",
        text = "The first angler to land a specimen wins. If nobody does, the biggest fish takes it." },
}
MF.EVENT_FORMAT_INFO = FORMAT_INFO

local LENGTHS = { 15, 30, 45, 60, 90, 120 }
local PLAYERS = { 5, 10, 20, 40 }

-- "20:30", "2030", "8:30pm", "9pm", "21". Minutes past midnight, or nil.
local function ParseTime(text)
    text = tostring(text or ""):lower():gsub("%s+", "")
    local h, m, half = text:match("^(%d%d?):?(%d%d)([ap]?)m?$")
    if not h then
        h, half = text:match("^(%d%d?)([ap]?)m?$")
        m = "0"
    end
    h, m = tonumber(h), tonumber(m)
    if not h or m > 59 then return nil end
    if half ~= "" then
        if h < 1 or h > 12 then return nil end
        h = h % 12 + (half == "p" and 12 or 0)
    end
    if h > 23 then return nil end
    return h * 60 + m
end
MF.ParseEventTime = ParseTime

local function Label(parent, text, y)
    local fs = MF:CreateText(parent, "GameFontHighlight", "TOPLEFT", LEFT, y)
    fs:SetText(text)
    return fs
end

local function Section(parent, text, y)
    local fs = MF:CreateText(parent, "GameFontNormal", "TOPLEFT", LEFT - 4, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    return fs
end

local function Tip(button, title, text)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A row of buttons, one per choice; the chosen one is drawn pressed in.
-- Returns the buttons and a refresh.
local function Choices(parent, x, y, width, gap, values, label, key, onPick)
    local buttons = {}
    for i, value in ipairs(values) do
        local b = MF:CreateButton(parent, label(value, i), width, function()
            state[key] = value
            if onPick then onPick(value) end
            form.refresh()
        end)
        b:SetDisabledFontObject("GameFontHighlightSmall")
        b:SetPoint("TOPLEFT", x + (i - 1) * (width + gap), y)
        b.value = value
        buttons[i] = b
    end
    local function refresh()
        for _, b in ipairs(buttons) do b:SetEnabled(state[key] ~= b.value) end
    end
    return buttons, refresh
end

-- A switch, with what it does said beside it.
local function Switch(parent, label, note, y, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", LEFT - 4, y)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    local aside = MF:CreateText(parent, "GameFontDisableSmall")
    aside:SetPoint("LEFT", cb, "LEFT", 134, 0)
    aside:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    aside:SetJustifyH("LEFT")
    aside:SetText(note)
    cb:SetScript("OnClick", function(self)
        state[key] = self:GetChecked() and true or false
        form.refresh()
    end)
    return function() cb:SetChecked(state[key]) end
end

local function DayLabel(day)
    if day == 0 then return "Today" end
    local t = date("*t")
    t.day, t.hour = t.day + day, 12
    return date("%a %d", time(t))
end

-- How long until it starts, or what is wrong with the time.
local function StartsIn()
    if not state.timeOK then
        return MF.C.bad .. "Type a time like 20:30 or 8:30pm.|r"
    end
    local left = StartTime() - time()
    if left <= 0 then return MF.C.bad .. "That time has already passed.|r" end
    if left < MF.NOTICE_LIMITS.minAhead then
        return MF.C.bad .. ("Give people at least %d minutes' notice.|r"):format(
            MF.NOTICE_LIMITS.minAhead / 60)
    end
    return MF.C.muted .. "starts in " .. Countdown(left) .. "|r"
end

-- The whole event as a sentence.
local function Summary()
    if not state.timeOK then return "" end
    local starts = StartTime()
    local parts = {
        ("%s, %s to %s."):format(date("%a %d %b", starts), date("%H:%M", starts),
            date("%H:%M", starts + state.length * 60)),
        FORMAT_INFO[state.mode].label .. ((state.fishName and (", " .. state.fishName .. " only")) or "")
            .. (", up to %d anglers"):format(state.players),
    }
    local extras = {}
    if state.team then extras[#extras + 1] = "in teams" end
    if state.hcp then extras[#extras + 1] = "with a skill handicap" end
    if state.guild then extras[#extras + 1] = "for your guild only" end
    if #extras > 0 then parts[2] = parts[2] .. ", " .. MF.List(extras) end
    return parts[1] .. " " .. parts[2] .. "."
end

local function EditBox(parent, width, x, y, max)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetPoint("TOPLEFT", x + 6, y + 5)
    box:SetAutoFocus(false)
    if max then box:SetMaxLetters(max) end
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end

local function CreateForm()
    local L = MF.NOTICE_LIMITS
    form = MF:CreatePanel("TheFishingLogPostEvent", W, 580,
        { strata = "DIALOG", movable = true, escCloses = true,
          title = "Post an event", close = true })
    form:SetPoint("CENTER", 0, 30)
    local refreshers = {}
    local function Add(fn) refreshers[#refreshers + 1] = fn end

    -- What and where ---------------------------------------------------
    Section(form, "What and where", -46)
    Label(form, "Title", -70)
    form.title = EditBox(form, W - FIELD - 26, FIELD, -70, L.title)
    -- On the box itself: the box is drawn above the form, so a hint on the
    -- form would sit underneath it.
    form.titleHint = MF:CreateText(form.title, "GameFontDisableSmall", "LEFT", 2, 0)
    form.titleHint:SetText("Name it - e.g. Friday night bass-off")
    form.title:SetScript("OnTextChanged", function(box)
        form.titleHint:SetShown(box:GetText() == "")
    end)
    Label(form, "Spot", -96)
    form.spot = MF:CreateText(form, "GameFontNormal", "TOPLEFT", FIELD, -96)
    form.spotNote = MF:CreateText(form, "GameFontDisableSmall", "TOPLEFT", FIELD, -112)
    form.spotNote:SetText("Where you're standing. To hold it somewhere else, go there first.")

    -- When ---------------------------------------------------------------
    Section(form, "When", -138)
    Label(form, "Day", -162)
    local days = {}
    for d = 0, 6 do days[#days + 1] = d end
    form.days, form.daysRefresh = Choices(form, FIELD, -158, 44, 3, days, DayLabel, "day")
    Add(form.daysRefresh)

    Label(form, "Starts at", -192)
    form.time = EditBox(form, 64, FIELD, -192, 7)
    form.starts = MF:CreateText(form, "GameFontHighlightSmall", "TOPLEFT", FIELD + 80, -194)
    form.time:SetScript("OnTextChanged", function(box)
        local minutes = ParseTime(box:GetText())
        state.timeOK = minutes ~= nil
        if minutes then state.minutes = minutes end
        form.refresh()
    end)

    Label(form, "Lasts", -222)
    local _, lengthRefresh = Choices(form, FIELD, -218, 50, 3, LENGTHS,
        function(v) return v .. " min" end, "length")
    Add(lengthRefresh)

    -- How it's won ---------------------------------------------------------
    Section(form, "How it's won", -252)
    local formats, formatRefresh = Choices(form, LEFT, -274, 102, 4, MODE_ORDER,
        function(mode) return FORMAT_INFO[mode].label end, "mode")
    Add(formatRefresh)
    form.formatText = MF:CreateText(form, "GameFontHighlightSmall", "TOPLEFT", LEFT, -304)
    form.formatText:SetWidth(W - 40)
    form.formatText:SetJustifyH("LEFT")
    -- Hovering a format previews its rules; leaving shows the chosen one's.
    for _, b in ipairs(formats) do
        b:HookScript("OnEnter", function(self)
            form.formatText:SetText(FORMAT_INFO[self.value].text)
        end)
        -- Only the text: disabling the button under the mouse fires OnLeave,
        -- so a full refresh here called itself until the stack ran out.
        b:HookScript("OnLeave", function() form.formatText:SetText(FORMAT_INFO[state.mode].text) end)
    end

    Label(form, "One fish", -336)
    form.fish = EditBox(form, 180, FIELD, -336)
    form.fishNote = MF:CreateText(form, "GameFontDisableSmall", "TOPLEFT", FIELD + 196, -338)
    form.fishNote:SetText("Leave blank for any fish.")
    form.fish:SetScript("OnTextChanged", function(box)
        local text = box:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        local fish = text ~= "" and MF:FindFish(text) or nil
        state.fishText, state.fish = text, fish
        state.fishName = fish and MF:FishName(fish) or nil
        if text == "" then
            form.fishNote:SetText("Leave blank for any fish.")
        elseif fish then
            form.fishNote:SetText(MF.C.good .. state.fishName .. "|r")
        else
            form.fishNote:SetText(MF.C.bad .. "No fish by that name.|r")
        end
        form.refresh()
    end)

    -- Who can join ---------------------------------------------------------
    Section(form, "Who can join", -366)
    Label(form, "Up to", -390)
    local _, playersRefresh = Choices(form, FIELD, -386, 44, 3, PLAYERS, tostring, "players")
    Add(playersRefresh)
    MF:CreateText(form, "GameFontHighlight", "TOPLEFT", FIELD + 4 * 47 + 6, -390):SetText("anglers")

    Add(Switch(form, "Guild only", "Only your guild sees it and can sign up.", -414, "guild"))
    Add(Switch(form, "Teams", "Scores add up by party, or by raid group in a raid.", -440, "team"))
    Add(Switch(form, "Skill handicap", "Lower-skilled anglers' fish count for up to 50% more.",
        -466, "hcp"))

    -- The event read back, or what's stopping it being posted, set off
    -- from the switches above and the buttons below.
    local rule = form:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", LEFT - 4, -498)
    rule:SetPoint("TOPRIGHT", -20, -498)
    form.summary = MF:CreateText(form, "GameFontNormalSmall", "TOPLEFT", LEFT, -508)
    form.summary:SetWidth(W - 40)
    form.summary:SetJustifyH("LEFT")
    form.error = MF:CreateText(form, "GameFontRedSmall", "TOPLEFT", LEFT, -508)
    form.error:SetWidth(W - 40)
    form.error:SetJustifyH("LEFT")

    local post = MF:CreateButton(form, "Post event", 120, function() MF:SubmitPostForm() end)
    post:SetPoint("BOTTOMRIGHT", form, "BOTTOM", -4, 16)
    local cancel = MF:CreateButton(form, CANCEL or "Cancel", 120, function() form:Hide() end)
    cancel:SetPoint("BOTTOMLEFT", form, "BOTTOM", 4, 16)

    local refreshing = false
    form.refresh = function()
        if refreshing then return end
        refreshing = true
        for _, r in ipairs(refreshers) do r() end
        refreshing = false
        form.starts:SetText(StartsIn())
        form.formatText:SetText(FORMAT_INFO[state.mode].text)
        form.error:SetText("")
        form.summary:SetText(Summary())
    end
end

function MF:ShowPostForm()
    if not form then CreateForm() end
    state = DefaultState()
    state.mode = MODE_ORDER[state.mode] or "weight"
    state.timeOK = true
    for i, b in ipairs(form.days) do b:SetText(DayLabel(i - 1)) end
    local spot = self:CurrentSpot()
    form.spot:SetText(spot.name)
    form.title:SetText("")
    form.fish:SetText("")
    form.time:SetText(("%02d:%02d"):format(floor(state.minutes / 60), state.minutes % 60))
    form.refresh()
    form:Show()
    form.title:SetFocus()
end

function MF:SubmitPostForm()
    if not state.timeOK then
        form.error:SetText("Type a start time like 20:30 or 8:30pm.")
        return
    end
    if state.fishText and state.fishText ~= "" and not state.fish then
        form.error:SetText("No fish called \"" .. state.fishText .. "\". Leave it blank for any fish.")
        return
    end
    local n, reason = self:PostNotice({
        title = form.title:GetText(), startsAt = StartTime(), minutes = state.length,
        mode = state.mode, fish = state.fish, team = state.team, hcp = state.hcp,
        guild = state.guild, maxPlayers = state.players,
    })
    if not n then
        form.summary:SetText("")
        form.error:SetText(reason)
        return
    end
    form:Hide()
    selected = n.id
    self:OpenJournal("board")
end
