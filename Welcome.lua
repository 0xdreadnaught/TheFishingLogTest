-- Welcome: what a brand new angler sees, and a few one-time tips.
--
-- Shown once, to someone with nothing to their name yet. The "have we said
-- hello" flag is saved, and the XP and journal checks stand behind it for
-- anyone whose saved data never arrived.
local _, MF = ...
-- A dormant copy (Core.lua) leaves the running copy's dialogs alone.
local POPUPS = MF.inert and {} or StaticPopupDialogs

local WELCOME_DELAY = 6      -- seconds after login, once things have settled
local NEW_ANGLER_XP = 50     -- below this you're still finding your feet
local TIP_XP_LIMIT = 500     -- tips stop once you clearly know the addon

local panel
local tipped = {}

function MF:IsNewAngler()
    if self.db.welcomed then return false end
    local p = self.cdb.profile
    return (p.xp or 0) < NEW_ANGLER_XP and self.Count(p.journal) == 0
end

-- A one-off nudge for newcomers. Each tip is shown once per session, and
-- only while you're new enough for it to be useful.
function MF:Tip(key, text)
    if tipped[key] or (self.cdb.profile.xp or 0) > TIP_XP_LIMIT then return end
    tipped[key] = true
    self:Print("|cff66ccffTip:|r " .. text)
end

------------------------------------------------------------------------
-- The welcome panel
------------------------------------------------------------------------

local LINES = {
    "|cffffd100Just fish.|r Your log starts itself on the first cast. Every fish is weighed, and your best are kept.",
    "|cffffd100Double right-click the water|r to cast, and again to land the fish. |cffffd100/tfl cast|r changes the button, or turns it off.",
    "|cffffd100Chase the big ones.|r Rare |cffffd100specimens|r and the heaviest fish at a spot make you King of it.",
    "|cffffd100Race other anglers.|r |cffffd100/tfl host|r starts a match where you stand; the |cffffd100Events|r tab is for events arranged for later.",
    "|cffffd100You're on the realm's leaderboard.|r Records travel from angler to angler, so the |cffffd100Realm|r tab fills in as you fish.",
}

local function CreatePanel()
    panel = MF:CreatePanel("TheFishingLogWelcome", 460, 360,
        { strata = "DIALOG", movable = true, escCloses = true,
          title = "Welcome to The Fishing Log", close = true })
    panel:SetPoint("CENTER", 0, 80)

    local y = -56
    panel.lines = {}
    for i, text in ipairs(LINES) do
        local line = MF:CreateText(panel, "GameFontHighlight", "TOPLEFT", 24, y)
        line:SetWidth(410)
        line:SetJustifyH("LEFT")
        line:SetSpacing(2)
        line:SetText(text)
        panel.lines[i] = line
        y = y - 48
    end

    local hint = MF:CreateText(panel, "GameFontDisableSmall", "TOPLEFT", 24, y - 4)
    hint:SetText("Type /tfl at any time for the full list of commands.")

    local journal = MF:CreateButton(panel, "Open the journal", 140, function()
        panel:Hide()
        MF:OpenJournal("journal")
    end)
    journal:SetPoint("BOTTOMLEFT", 20, 16)
    local options = MF:CreateButton(panel, "Options", 100, function() MF:OpenOptions() end)
    options:SetPoint("LEFT", journal, "RIGHT", 8, 0)
    local done = MF:CreateButton(panel, "Start fishing", 120, function() panel:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -20, 16)
end

-- On the morning of a wipe this is the truest thing the addon can say, and
-- it is only true for a few days. Every record in the game is unclaimed at
-- the same moment and nobody has a head start - which will not happen again.
local FRESH_REALM =
    "|cffffd100The board is empty.|r Every record on this realm is unclaimed, and whoever "
    .. "casts first holds it. The |cffffd100Realm|r tab is where that gets settled."

function MF:ShowWelcome()
    if not panel then CreatePanel() end
    self.db.welcomed = true
    if panel.lines and panel.lines[#LINES] then
        panel.lines[#LINES]:SetText(self.Count(self.db.spots) == 0 and FRESH_REALM
            or LINES[#LINES])
    end
    panel:Show()
end

MF:Command("welcome", "Other", nil, MF.ShowWelcome)

MF:On("TFL_LOGIN", function(self)
    C_Timer.After(WELCOME_DELAY, function()
        if self:IsNewAngler() then
            self:ShowWelcome()
        end
    end)
end)

------------------------------------------------------------------------
-- Tips, in the order a new angler meets them
------------------------------------------------------------------------

MF:On("TFL_CATCH", function(self, c)
    if c.test then return end
    if c.junk then
        self:Tip("junk", "Junk weighs nothing, but it still sells - your log tracks what your haul is worth.")
        return
    end
    self:Tip("first", ("Weights are the addon's own: this %s could have been anywhere from tiny to a record."):format(c.name))
    if c.specimen then
        self:Tip("specimen", "Specimens are the rarest catch of all - about 1 in 100, and only in that fish's home waters.")
    end
    if self.Count(self.cdb.profile.journal) >= 3 then
        self:Tip("journal", "Your journal is filling up - open it with |cffffd100/tfl journal|r to see what's left to catch here.")
    end
end)

MF:On("TFL_NOTICE_NEW", function(self, n)
    if self:IsMe(n.host) then return end
    self:Tip("board", ("%s posted an event. Open the |cffffd100Events|r tab to sign up."):format(self:ShortName(n.host)))
end)

------------------------------------------------------------------------
-- The log that came from the account
--
-- Until 0.6.4 one log covered every character, so an alt who had never
-- fished showed their main's personal bests. The log now belongs to the
-- character who earned it - but the addon can't know which character that
-- was, so it asks, once, and only of a character with nothing of their own
-- to lose.
------------------------------------------------------------------------

local CLAIM_DELAY = 4

POPUPS["THEFISHINGLOG_CLAIM"] = {
    text = "The Fishing Log used to keep one log for your whole account. "
        .. "From now on it follows the character who earned it.\n\nIs that log %s's?",
    button1 = "Yes, it's mine",
    button2 = "Not mine",
    OnAccept = function() MF:ClaimLegacyLog() end,
    OnCancel = function() MF.cdb.declinedLegacy = true end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

-- An older log, parked and still unclaimed. Returns its profile, or nil.
function MF:LegacyWaiting()
    local legacy = self.db.legacy
    if not legacy or not legacy.profile then return end
    if self.db.legacyClaimedBy then return end
    return legacy.profile
end

function MF:OfferClaim()
    StaticPopup_Show("THEFISHINGLOG_CLAIM", self:ShortName(self.me), self:ClaimHint())
end

-- Claiming merges, taking the better of each part, so it cannot cost this
-- character anything - which means there was never a reason to offer it only
-- to a character with nothing at all. That test meant one cast was enough to
-- never be asked again, and an angler sat at the first rank for weeks with
-- their own log parked beside them, told only by a line of chat they had
-- learned to scroll past.
local function WorthClaiming(self)
    local theirs = self:LegacyWaiting()
    if not theirs or self.cdb.declinedLegacy then return false end
    local mine = self.cdb.profile
    return (theirs.xp or 0) > (mine.xp or 0)
        or self.Count(theirs.journal or {}) > self.Count(mine.journal)
end

-- Two logs, one character: take the better of each part rather than the
-- whole of either, because a character may already be carrying an old macro
-- backup and nothing here is worth losing.
local function Bigger(a, b) return (a or 0) >= (b or 0) and a or b end

local function MergeJournal(into, from)
    for id, theirs in pairs(from or {}) do
        local mine = into[id]
        if not mine then
            into[id] = theirs
        else
            mine.c = Bigger(mine.c, theirs.c)
            mine.b = Bigger(mine.b, theirs.b)
            mine.s = Bigger(mine.s, theirs.s)
            -- Zone bitmasks: 0 means "caught before zones were tracked", which
            -- counts as everywhere, so it wins.
            if (mine.z or 0) ~= 0 and (theirs.z or 0) ~= 0 then
                mine.z = MF:MergeZoneMasks(mine.z, theirs.z)
            else
                mine.z = 0
            end
        end
    end
end

-- Which character earned it? The realm remembers who holds what, so say so
-- rather than leaving the player to guess on a screen they see once.
function MF:ClaimHint()
    local n = 0
    for _, s in pairs(self.db.spots) do
        for _, rec in pairs(s.fish) do
            if self:IsMe(rec.h) then n = n + 1 end
        end
    end
    if n == 0 then
        return "This character holds no records on the realm, which may mean it isn't the one."
    end
    return ("This character holds %d record%s on the realm."):format(n, n == 1 and "" or "s")
end

function MF:ClaimLegacyLog()
    local legacy = self.db.legacy
    if not legacy then return end
    local mine, theirs = self.cdb.profile, legacy.profile or {}

    mine.xp = Bigger(mine.xp, theirs.xp)
    mine.value = Bigger(mine.value, theirs.value)
    mine.seasonXP = Bigger(mine.seasonXP, theirs.seasonXP)
    mine.champUntil = Bigger(mine.champUntil, theirs.champUntil)
    mine.season = mine.season or theirs.season
    mine.updated = time()
    MergeJournal(mine.journal, theirs.journal)

    for key, fish in pairs(legacy.records or {}) do
        local here = self.cdb.records[key] or {}
        self.cdb.records[key] = here
        for id, rec in pairs(fish) do
            if not here[id] or (rec.weight or 0) > (here[id].weight or 0) then here[id] = rec end
        end
    end

    local seen = {}
    for _, h in ipairs(self.cdb.history) do seen[h.when or 0] = true end
    for _, h in ipairs(legacy.history or {}) do
        if not seen[h.when or 0] then table.insert(self.cdb.history, h) end
    end
    table.sort(self.cdb.history, function(a, b) return (a.when or 0) < (b.when or 0) end)

    for id, byZone in pairs(legacy.caughtIn or {}) do
        self.cdb.caughtIn[id] = self.cdb.caughtIn[id] or byZone
    end
    for slot, set in pairs(legacy.gear or {}) do
        self.cdb.gear[slot] = self.cdb.gear[slot] or set
    end

    -- Kept, not consumed: if the wrong character claimed it, the right one
    -- can still take it with /tfl claim. Nobody is offered it unasked twice.
    self.db.legacyClaimedBy = self.me
    self.cdb.declinedLegacy = nil
    self:Print(("That log is yours: %d XP, %d journal entries, %d sessions. It stays with "
        .. "this character from now on."):format(mine.xp or 0, self.Count(mine.journal),
        #self.cdb.history))
    self:RefreshJournal()
    self:UpdateBoard()
end

MF:Command("claim", "Other", "/tfl claim - take the old account-wide log onto this character",
    function(self)
        if not self.db.legacy then
            self:Print("There's no account-wide log to claim.")
            return
        end
        if self.db.legacyClaimedBy and not self:IsMe(self.db.legacyClaimedBy) then
            self:Print(("|cffff8000%s has already taken that log.|r Claiming it here as well "
                .. "gives two characters the same journal - carry on only if that first claim "
                .. "was a mistake."):format(self:ShortName(self.db.legacyClaimedBy)))
        end
        StaticPopup_Show("THEFISHINGLOG_CLAIM", self:ShortName(self.me), self:ClaimHint())
    end)

MF:On("TFL_LOGIN", function(self)
    -- Said straight away. A player who opens the journal in the meantime
    -- finds it empty, and should know why before they think it's lost.
    if self.db.legacy and self.db.legacy.profile and not self.db.legacyClaimedBy then
        self:Print("Your log now belongs to the character who earned it, rather than the "
            .. "whole account. Nothing is lost - say yes to the question coming up to keep "
            .. "it here, or use |cffffd100/tfl claim|r on whichever character it belongs to.")
    end
    C_Timer.After(CLAIM_DELAY, function()
        if WorthClaiming(self) then
            StaticPopup_Show("THEFISHINGLOG_CLAIM", self:ShortName(self.me), MF:ClaimHint())
        end
    end)
end)
