-- Higher or Lower: a game for the flight, played with your own album.
--
-- A flight path is a minute or three of watching the ground go by, and an
-- angler on one has nothing to do with the cards they spent the week
-- earning. This turns them into a deck. One card is face up with your best
-- weight on it; the next shows only the fish. Is your best one of those
-- heavier or lighter? Right and the streak goes on, wrong and it ends.
--
-- The skill is knowing your own fishing: how big a catfish runs and
-- whether the one you landed was a good one, which fish you have hauled
-- out by the hundred, and which you have chased round half the map. A
-- game can be about your best weights, how many you have caught, how many
-- waters you have caught them in, or a different one of those each round.
-- The next card shows its edition, the colour it wears in the album, and
-- keeps its number face down. Trophy fish stay out of the deck, because "22 Pound Catfish"
-- is the answer written on the front.
--
-- Nothing here is sent, and nothing earns XP: a long flight would be an XP
-- farm, and fishing has stayed the only way to progress. What it keeps is
-- your best streak, on this character, beside the album it was played with.
--
-- The rules are plain functions and the window only draws them, so every
-- outcome can be checked outside the game.
local _, MF = ...

local MIN_DECK = 5        -- fewer cards than this is not a game
local CLOSE_BIAS = 0.6    -- how often the next card is drawn from the near weights
local NEAR_SHARE = 3      -- ...meaning the closest third of what is left
local OFFER_SECONDS = 25  -- how long the flight offer waits before it fades

-- What a round can ask about. Each reads one number off a card, and says
-- it the way the card would: a weight, a tally, a count of places.
local STATS = {
    weight = { label = "Best weight", up = "Heavier", down = "Lighter",
        question = "Is your best of the next fish heavier or lighter?",
        caption = "your best" },
    caught = { label = "Caught", up = "More", down = "Fewer",
        question = "Have you caught the next fish more or fewer times?",
        caption = "times caught" },
    waters = { label = "Waters", up = "More", down = "Fewer",
        question = "Have you landed the next fish in more or fewer waters?",
        caption = "waters fished" },
}
local MODES = { "mixed", "weight", "caught", "waters" }
local MODE_LABEL = { mixed = "Mixed", weight = "Best weight", caught = "Caught", waters = "Waters" }
local MIXED = { "weight", "caught", "waters" }
MF.HIGHER_LOWER_MODES = MODES

------------------------------------------------------------------------
-- The deck
------------------------------------------------------------------------

local bloated = {}
for _, id in ipairs(MF.BLOATED or {}) do bloated[id] = true end

-- Every species card you hold with a weight on it, as { id, w, n, waters }.
-- w is hundredths of a pound, so two weights the scales call equal are
-- equal here; n is how many you have caught; waters is how many places.
function MF:HigherLowerDeck()
    local deck = {}
    local journal = self.cdb and self.cdb.profile and self.cdb.profile.journal or {}
    local caughtIn = self.cdb and self.cdb.caughtIn or {}
    for id, entry in pairs(journal) do
        if self.FISH[id] and not bloated[id] and not self:TrophyWeight(id)
            and type(entry.b) == "number" and entry.b > 0 then
            local waters = 0
            for _ in pairs(caughtIn[id] or {}) do waters = waters + 1 end
            deck[#deck + 1] = { id = id, w = MF.Hundredths(entry.b),
                n = math.max(1, tonumber(entry.c) or 1), waters = math.max(1, waters) }
        end
    end
    table.sort(deck, function(a, b) return a.id < b.id end)
    return deck
end

function MF:HigherLowerReady()
    return #self:HigherLowerDeck() >= MIN_DECK, MIN_DECK
end

function MF:HigherLowerStats()
    local p = self.cdb.profile
    p.higherLower = p.higherLower or { best = 0, runs = 0, cleared = 0 }
    local stats = p.higherLower
    -- One best per kind of game: a run on weights and a run on tallies are
    -- not the same test. best stays as the highest of them.
    stats.bests = stats.bests or { weight = stats.best or 0 }
    stats.mode = stats.mode or "mixed"
    return stats
end

function MF:HigherLowerBest(mode)
    return self:HigherLowerStats().bests[mode or "mixed"] or 0
end

-- The number a round compares. Weight is in hundredths of a pound.
function MF:HigherLowerValue(card, stat)
    if stat == "caught" then return card.n end
    if stat == "waters" then return card.waters end
    return card.w
end

-- How a number reads on the table.
function MF:HigherLowerShow(card, stat)
    if stat == "caught" then return ("%d"):format(card.n) end
    if stat == "waters" then return ("%d"):format(card.waters) end
    return self:Weight(card.w / 100)
end

function MF:HigherLowerStat(stat) return STATS[stat] end
function MF:HigherLowerModeLabel(mode) return MODE_LABEL[mode] end

------------------------------------------------------------------------
-- A run
------------------------------------------------------------------------

local run -- the game in progress, or the one that just finished

function MF:HigherLowerRun() return run end

-- The next card. Drawn at random most of the time from the values nearest
-- the one showing, because a smallfish against a catfish is not a question;
-- the rest of the time from anywhere, so a run is never all close calls.
-- Near means near, not equal: waters fished is mostly ones and twos, and a
-- draw that hunted for the closest would deal nothing but free passes.
local function Draw(self, pile, against, stat)
    if #pile == 0 then return nil end
    local pick = math.random(#pile)
    if against and math.random() < CLOSE_BIAS and #pile > 2 then
        local mine = self:HigherLowerValue(against, stat)
        local order = {}
        for i, card in ipairs(pile) do
            local theirs = self:HigherLowerValue(card, stat)
            if theirs ~= mine then
                order[#order + 1] = { i = i, gap = math.abs(math.log(theirs / mine)) }
            end
        end
        if #order > 0 then
            table.sort(order, function(a, b) return a.gap < b.gap end)
            local near = math.min(#order, math.max(2, math.ceil(#order / NEAR_SHARE)))
            pick = order[math.random(near)].i
        end
    end
    return table.remove(pile, pick)
end

local function PickStat(mode)
    if STATS[mode] then return mode end
    return MIXED[math.random(#MIXED)]
end

-- source is "flight" when the flight offer started it, so landing ends it,
-- and anything else when it was opened on purpose. mode is a stat, or
-- "mixed" for a different one each round; it defaults to the last played.
function MF:StartHigherLower(source, mode)
    local stats = self:HigherLowerStats()
    mode = (mode == "mixed" or STATS[mode]) and mode or stats.mode
    stats.mode = mode
    local pile = self:HigherLowerDeck()
    if #pile < MIN_DECK then return nil, #pile end
    local current = table.remove(pile, math.random(#pile))
    run = { pile = pile, current = current, streak = 0, source = source or "manual",
        mode = mode, dealt = 1, size = #pile + 1 }
    run.stat = PickStat(mode)
    run.next = Draw(self, pile, current, run.stat)
    run.dealt = 2
    stats.runs = stats.runs + 1
    return run
end

-- Keeps the best the moment it is beaten, so a reload mid-run can't lose it.
local function Bank(self)
    local stats = self:HigherLowerStats()
    if run.streak > (stats.bests[run.mode] or 0) then
        stats.bests[run.mode] = run.streak
        run.newBest = true
    end
    if run.streak > stats.best then stats.best = run.streak end
end

-- Ends the run for any reason: "wrong", "cleared", "landed" or "closed".
function MF:EndHigherLower(reason)
    if not run or run.over then return run end
    run.over = reason
    Bank(self)
    if reason == "cleared" then
        local stats = self:HigherLowerStats()
        stats.cleared = stats.cleared + 1
    end
    return run
end

-- guess is "higher" or "lower". Returns "right", "push" or "wrong", with
-- the card that was turned over. The run moves on, or ends, before this
-- returns; the window only animates what has already been decided.
function MF:GuessHigherLower(guess)
    if not run or run.over or not run.next then return nil end
    local shown, turned, stat = run.current, run.next, run.stat
    local was, now = self:HigherLowerValue(shown, stat), self:HigherLowerValue(turned, stat)
    local outcome
    if now == was then
        outcome = "push"
    elseif (now > was) == (guess == "higher") then
        outcome = "right"
        run.streak = run.streak + 1
        Bank(self)
    else
        outcome = "wrong"
    end
    run.last = { outcome = outcome, guess = guess, shown = shown, turned = turned, stat = stat,
        heavier = now > was }
    if outcome == "wrong" then
        self:EndHigherLower("wrong")
        return outcome, turned
    end
    run.current = turned
    run.stat = PickStat(run.mode)
    run.next = Draw(self, run.pile, turned, run.stat)
    if run.next then
        run.dealt = run.dealt + 1
    else
        self:EndHigherLower("cleared")
    end
    return outcome, turned
end

------------------------------------------------------------------------
-- The table
------------------------------------------------------------------------

-- Drawn in the UI Rework's manner (Rework\Widgets.lua): cards as its navy
-- panels with the fish in the gold achievement ring, the modes as its boxed
-- switch, and the score as the board's number cells.
local W, H = 530, 434
local TOP = 84 -- where the cards start, under the title, the stat row and the question
local FACE_W, FACE_H = 186, 222
local ART = 64
local REVEAL, HOLD, SLIDE, ARRIVE = 0.65, 0.55, 0.28, 0.22 -- seconds

local panel

local function Calm() return MF.db.settings.reducedMotion end

-- The table's own sounds, which its mute button silences without touching
-- the addon's Play sounds setting: someone flying past a guildmate wants
-- the game quiet, not every record and frenzy alert with it.
function MF:HigherLowerSound(kit)
    self:Sound(kit, "higherLowerSounds")
end

local function MuteLabel(self)
    return self.db.settings.higherLowerSounds == false and "Sound off" or "Sound on"
end

local function Face(self, parent)
    local Wd = self.Rework.W
    local face = Wd:Card(parent)
    face:SetSize(FACE_W, FACE_H)
    -- The journal's navy, warmed toward charcoal-brown so the card sits on
    -- the stone without going cold against it; still dark enough for the
    -- edition wash and the big number.
    face:SetBackdropColor(0.07, 0.06, 0.07, 0.93)

    face.wash = face:CreateTexture(nil, "BACKGROUND", nil, 1)
    face.wash:SetPoint("TOPLEFT", 3, -3)
    face.wash:SetPoint("TOPRIGHT", -3, -3)
    face.wash:SetHeight(ART + 40)
    face.wash:SetColorTexture(1, 1, 1, 1)

    face.glow = face:CreateTexture(nil, "BORDER")
    face.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    face.glow:SetBlendMode("ADD")
    face.glow:SetSize(ART * 1.9, ART * 1.9)

    -- The fish in the gold ring the journal and the toasts wear
    face.art = Wd:FramedIcon(face, ART)
    face.art:SetPoint("TOP", 0, -20)
    face.glow:SetPoint("CENTER", face.art, "CENTER")
    face.icon = face.art.icon

    face.name = self:CreateText(face, "GameFontNormal")
    face.name:SetPoint("TOP", face.art, "BOTTOM", 0, -12)
    face.name:SetWidth(FACE_W - 20)
    face.name:SetJustifyH("CENTER")
    face.name:SetWordWrap(true)
    face.name:SetMaxLines(2)

    face.edition = self:CreateText(face, "GameFontNormalSmall")
    face.edition:SetPoint("TOP", face.name, "BOTTOM", 0, -4)

    face.rule = Wd:Divider(face, FACE_W - 36)
    face.rule:SetPoint("BOTTOM", 0, 74)
    face.weight = self:CreateText(face, "GameFontNormalHuge")
    face.weight:SetPoint("BOTTOM", 0, 34)
    face.caption = self:CreateText(face, "GameFontDisableSmall")
    face.caption:SetPoint("TOP", face.weight, "BOTTOM", 0, -3)

    -- Clicking the face-up card opens the full one, the album's own.
    face:EnableMouse(true)
    face:SetScript("OnMouseUp", function(f)
        if f.clickable and f.card then MF:ShowCard(f.card.id) end
    end)
    face:SetScript("OnEnter", function(f)
        if not f.clickable then return end
        GameTooltip:SetOwner(f, "ANCHOR_TOP")
        GameTooltip:AddLine("Click to open the card")
        GameTooltip:Show()
    end)
    face:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return face
end

-- Draws one card for a round on stat. hidden keeps the number face down.
local function Paint(self, face, card, hidden, stat)
    local about = STATS[stat] or STATS.weight
    face.card = card
    local c = self:CardFor(card.id)
    local r, g, b = MF.CardRGB(c and c.colour)
    face.icon:SetTexture(self:FishIcon(card.id))
    face.name:SetText(self:FishName(card.id) or ("Item " .. card.id))
    face.edition:SetText(c and (c.colour .. c.edition:upper() .. "|r") or "")
    face:SetEdge(r, g, b, 1)
    MF.CardGradient(face.wash, "VERTICAL", r, g, b, 0, 0.22)
    face.glow:SetVertexColor(r, g, b)
    face.glow:SetAlpha(0.7)
    if hidden then
        face.weight:SetText(self.C.faint .. "?|r")
        face.caption:SetText(about.caption .. " - higher or lower?")
    else
        face.weight:SetText(self.C.text .. self:HigherLowerShow(card, stat) .. "|r")
        face.caption:SetText(about.caption)
    end
    face.clickable = not hidden
end

local function Slots(f)
    f.left:ClearAllPoints()
    f.left:SetPoint("TOPLEFT", 26, -TOP)
    f.right:ClearAllPoints()
    f.right:SetPoint("TOPRIGHT", -26, -TOP)
    f.left:SetAlpha(1)
    f.right:SetAlpha(1)
end

-- The score as the board shows its numbers: a big figure over a small label.
local function Footer(self, f)
    local left = run and not run.over and (#run.pile + (run.next and 1 or 0)) or 0
    f.streak:SetText(("%s%d|r"):format(self.C.gold, run and run.streak or 0))
    f.best:SetText(("%s%d|r"):format(self.C.text, self:HigherLowerBest(run and run.mode)))
    f.bestLabel:SetText((run and MODE_LABEL[run.mode] or "Mixed"):lower() .. " best")
    f.remaining:SetText(("%s%d|r"):format(self.C.text, left))
    f.remainingLabel:SetText(left == 1 and "card left" or "cards left")
end

local function Controls(f, live)
    f.higher:SetEnabled(live)
    f.lower:SetEnabled(live)
end

-- The round's question, and the stat between the cards, so a mixed game
-- never leaves you guessing which number is face down.
local function Ask(self, f)
    local about = STATS[run.stat] or STATS.weight
    f.question:SetText(about.question)
    f.vs:SetText(self.C.muted .. "vs|r")
    f.statName:SetText(self.C.gold .. about.label:upper() .. "|r")
    for _, tab in ipairs(f.modes) do tab:SetEnabled(tab.mode ~= run.mode) end
end

local Redraw

-- The end of a run, over the table: what happened, and the way back in.
local function Verdict(self, f)
    local over, last = run.over, run.last
    local head, line
    if over == "wrong" then
        local shown, turned = last.shown, last.turned
        head = self.C.bad .. "Wrong way|r"
        local about = STATS[last.stat] or STATS.weight
        line = ("%s: %s %s against %s %s."):format(about.label, self:FishName(turned.id),
            self:HigherLowerShow(turned, last.stat), self:FishName(shown.id), self:HigherLowerShow(shown, last.stat))
    elseif over == "cleared" then
        head = self.C.good .. "The whole album|r"
        line = "Every card in the deck, turned over without a wrong call."
    elseif over == "landed" then
        head = self.C.gold .. "Touched down|r"
        line = "The flight's over, and the streak goes in the book."
    else
        head = self.C.gold .. "Run ended|r"
        line = ""
    end
    f.veil:Show()
    f.verdict:SetText(head)
    f.verdictLine:SetText(line)
    f.verdictScore:SetText(("Streak %s%d|r%s"):format(self.C.gold, run.streak,
        run.newBest and ("   " .. self.C.good .. "New best!|r")
            or ("   " .. self.C.muted .. MODE_LABEL[run.mode]:lower() .. " best " .. self:HigherLowerBest(run.mode) .. "|r")))
    f.again:Show()
    Controls(f, false)
end

-- The animation is one clock on the panel: reveal counts the hidden weight
-- up, hold lets the result sit, slide carries the card across, arrive
-- fades the next one in. Reduced motion skips straight to each end.
local function Tick(f, dt)
    local a = f.anim
    if not a then f:SetScript("OnUpdate", nil) return end
    a.t = a.t + dt
    local self = MF
    if a.stage == "reveal" then
        local k = math.min(1, a.t / REVEAL)
        local eased = 1 - (1 - k) ^ 3
        local shown
        if a.stat == "weight" then
            shown = self:Weight(a.turned.w / 100 * eased)
        else
            shown = ("%d"):format(math.floor(self:HigherLowerValue(a.turned, a.stat) * eased + 0.5))
        end
        f.right.weight:SetText(self.C.text .. shown .. "|r")
        if k >= 1 then
            Paint(self, f.right, a.turned, false, a.stat)
            f.result:SetText(a.verdict)
            if a.outcome == "wrong" or run.over then
                f.anim = nil
                Verdict(self, f)
                Footer(self, f)
                return
            end
            a.stage, a.t = "hold", 0
        end
    elseif a.stage == "hold" then
        if a.t >= HOLD then a.stage, a.t = "slide", 0 end
    elseif a.stage == "slide" then
        local k = math.min(1, a.t / SLIDE)
        local eased = k * k * (3 - 2 * k)
        f.left:SetAlpha(1 - k)
        local travel = (W - 52 - FACE_W) * eased
        f.right:ClearAllPoints()
        f.right:SetPoint("TOPRIGHT", -26 - travel, -TOP)
        if k >= 1 then
            Slots(f)
            Paint(self, f.left, run.current, false, run.stat)
            Paint(self, f.right, run.next, true, run.stat)
            Ask(self, f)
            f.right:SetAlpha(0)
            a.stage, a.t = "arrive", 0
        end
    elseif a.stage == "arrive" then
        local k = math.min(1, a.t / ARRIVE)
        f.right:SetAlpha(k)
        if k >= 1 then
            f.anim = nil
            f.result:SetText("")
            Footer(self, f)
            Controls(f, true)
        end
    end
end

local SAYS = {
    right = { "Right.", "Spot on.", "Called it.", "Good read.", "Keep going." },
}

local function Guess(self, guess)
    local f = panel
    if not run or run.over or f.anim then return end
    local outcome, turned = self:GuessHigherLower(guess)
    if not outcome then return end
    local verdict
    if outcome == "right" then
        verdict = self.C.good .. SAYS.right[math.random(#SAYS.right)] .. "|r"
        self:HigherLowerSound(run.newBest and SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.READY_CHECK)
    elseif outcome == "push" then
        verdict = self.C.hint .. "Dead level - a free pass.|r"
    else
        local about = STATS[run.last.stat] or STATS.weight
        verdict = self.C.bad .. ("%s, not %s.|r"):format(
            run.last.heavier and about.up or about.down, (guess == "higher" and about.up or about.down):lower())
        self:HigherLowerSound(SOUNDKIT.RAID_WARNING)
    end
    Controls(f, false)
    f.anim = { stage = "reveal", t = 0, turned = turned, outcome = outcome, verdict = verdict,
        stat = run.last.stat }
    if Calm() then
        -- Every stage at once, in order, with nothing drawn between them.
        f.anim.t = REVEAL Tick(f, 0)
        if f.anim then f.anim.stage, f.anim.t = "slide", SLIDE Tick(f, 0) end
        if f.anim then f.anim.t = ARRIVE Tick(f, 0) end
        f.result:SetText(verdict)
        return
    end
    f:SetScript("OnUpdate", Tick)
end

local function Build(self)
    local f = self:CreatePanel("TheFishingLogHigherLower", W, H,
        { backdrop = "dialog", strata = "DIALOG", movable = true, escCloses = true,
          title = "Higher or Lower", close = true })
    f:SetPoint("CENTER", 0, 80)

    -- Beside the close button, where a mute is looked for.
    f.mute = self:CreateButton(f, MuteLabel(self), 72, function(button)
        MF.db.settings.higherLowerSounds = MF.db.settings.higherLowerSounds == false
        button:SetText(MuteLabel(MF))
    end)
    f.mute:SetPoint("TOPRIGHT", -38, -11)

    local Wd = self.Rework.W
    -- The journal's own ground: the game's collections stone, under the
    -- title bar. Text goes on a layer above it, since the stone is a frame
    -- of its own and would otherwise cover anything drawn straight on the
    -- window; the cards and buttons are frames already above it.
    f.ground = f.lodgeGround
    if not f.ground then
        f.ground = Wd:Ground(f)
        f.ground:SetPoint("TOPLEFT", 8, -34)
        f.ground:SetPoint("BOTTOMRIGHT", -8, 8)
        Wd:HideTopCorners(f.ground)
    end
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(math.max(f:GetFrameLevel(), f.ground:GetFrameLevel()) + 2)

    -- Which number the game is about, as the Collection's boxed switch: the
    -- one you are playing is lit (and can't be pressed); picking another
    -- deals a fresh run on it.
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetHeight(22)
    box:SetPoint("TOP", f, "TOP", 0, -40)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    box:SetBackdropColor(0, 0, 0, 0.5)
    box:SetBackdropBorderColor(0.55, 0.47, 0.3, 1)
    f.modes = {}
    local x = 2
    for i, mode in ipairs(MODES) do
        local tab = CreateFrame("Button", nil, box)
        tab:SetHeight(18)
        tab.text = Wd:Label(tab, "GameFontHighlightSmall", MODE_LABEL[mode])
        tab.text:SetPoint("CENTER")
        tab:SetWidth(math.max(60, (tab.text:GetStringWidth() or 60) + 24))
        tab.line = tab:CreateTexture(nil, "BACKGROUND")
        tab.line:SetAllPoints()
        tab.line:SetColorTexture(1, 0.82, 0, 0.22)
        tab.line:Hide()
        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        if i > 1 then
            local sep = box:CreateTexture(nil, "ARTWORK")
            sep:SetWidth(1)
            sep:SetColorTexture(0.55, 0.47, 0.3, 1)
            sep:SetPoint("TOP", tab, "TOPLEFT", 0, 0)
            sep:SetPoint("BOTTOM", tab, "BOTTOMLEFT", 0, 0)
        end
        tab:SetPoint("LEFT", box, "LEFT", x, 0)
        x = x + tab:GetWidth()
        tab.mode = mode
        tab:SetScript("OnClick", function()
            MF:OpenHigherLower(MF:OnFlight() and "flight" or "manual", mode)
        end)
        tab:SetScript("OnDisable", function(b) b.line:Show() b.text:SetTextColor(1, 0.82, 0) end)
        tab:SetScript("OnEnable", function(b) b.line:Hide() b.text:SetTextColor(1, 1, 1) end)
        f.modes[i] = tab
    end
    box:SetWidth(x + 2)
    f.question = self:CreateText(top, "GameFontHighlightSmall")
    f.question:SetPoint("TOP", f, "TOP", 0, -68)

    f.left = Face(self, f)
    f.right = Face(self, f)
    Slots(f)

    f.vs = self:CreateText(top, "GameFontNormalLarge")
    f.vs:SetPoint("CENTER", f, "TOP", 0, -TOP - FACE_H / 2 + 8)
    -- The gap between the cards is all the room the stat gets, so it
    -- wraps inside it rather than running under a card.
    f.statName = self:CreateText(top, "GameFontNormalSmall")
    f.statName:SetPoint("TOP", f.vs, "BOTTOM", 0, -6)
    f.statName:SetWidth(W - 52 - FACE_W * 2 - 8)
    f.statName:SetJustifyH("CENTER")
    f.statName:SetWordWrap(true)

    f.result = self:CreateText(top, "GameFontNormal")
    f.result:SetPoint("TOP", f, "TOP", 0, -TOP - FACE_H - 10)

    local UP = "|TInterface\\Buttons\\Arrow-Up-Up:14:14:0:-2|t "
    local DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:14:14:0:2|t "
    f.higher = self:CreateButton(f, UP .. "Higher", 150, function() Guess(MF, "higher") end)
    f.lower = self:CreateButton(f, DOWN .. "Lower", 150, function() Guess(MF, "lower") end)
    f.higher:SetHeight(28)
    f.lower:SetHeight(28)
    f.lower:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 62)
    f.higher:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 62)

    -- Streak, best and what's left, as the board's number cells
    -- Kept clear of the stone's bottom corner ornaments, which stay
    f.footRule = Wd:Divider(top, W - 220)
    f.footRule:SetPoint("BOTTOM", 0, 52)
    local function Cell(x)
        local value = self:CreateText(top, "GameFontHighlightLarge")
        value:SetPoint("BOTTOM", f, "BOTTOM", x, 26)
        local label = self:CreateText(top, "GameFontDisableSmall")
        label:SetPoint("TOP", value, "BOTTOM", 0, -2)
        return value, label
    end
    local third = 120
    local streakLabel
    f.streak, streakLabel = Cell(-third)
    streakLabel:SetText("streak")
    f.best, f.bestLabel = Cell(0)
    f.remaining, f.remainingLabel = Cell(third)

    -- The verdict sits on a veil over the cards, so the losing pair is
    -- still there to see underneath it, in a panel of its own.
    f.veil = CreateFrame("Frame", nil, f)
    f.veil:SetPoint("TOPLEFT", 8, -64)
    f.veil:SetPoint("BOTTOMRIGHT", -8, 56)
    f.veil:SetFrameLevel(f:GetFrameLevel() + 20)
    f.veil:EnableMouse(true)
    f.veil.bg = f.veil:CreateTexture(nil, "BACKGROUND")
    f.veil.bg:SetAllPoints()
    f.veil.bg:SetColorTexture(0.02, 0.02, 0.03, 0.72)
    f.veil.box = Wd:Panel(f.veil, 0.96)
    f.veil.box:SetSize(W - 110, 200)
    f.veil.box:SetPoint("CENTER", 0, 4)
    f.verdict = self:CreateText(f.veil.box, "GameFontNormalHuge")
    f.verdict:SetPoint("TOP", 0, -24)
    f.verdictLine = self:CreateText(f.veil.box, "GameFontHighlight")
    f.verdictLine:SetPoint("TOP", f.verdict, "BOTTOM", 0, -10)
    f.verdictLine:SetWidth(W - 150)
    f.verdictLine:SetJustifyH("CENTER")
    f.verdictScore = self:CreateText(f.veil.box, "GameFontNormalLarge")
    f.verdictScore:SetPoint("TOP", f.verdictLine, "BOTTOM", 0, -14)
    f.again = self:CreateButton(f.veil.box, "Deal again", 150, function()
        MF:OpenHigherLower(MF:OnFlight() and "flight" or "manual", run and run.mode)
    end)
    f.again:SetHeight(28)
    f.again:SetPoint("TOP", f.verdictScore, "BOTTOM", 0, -18)
    f.veil:Hide()

    -- Closing mid-run ends it, and the streak still counts.
    f:SetScript("OnHide", function(frame)
        frame.anim = nil
        frame:SetScript("OnUpdate", nil)
        if run and not run.over then MF:EndHigherLower("closed") end
        GameTooltip:Hide()
    end)
    return f
end

Redraw = function(self)
    local f = panel
    f.anim = nil
    f:SetScript("OnUpdate", nil)
    Slots(f)
    f.veil:Hide()
    f.result:SetText("")
    Paint(self, f.left, run.current, false, run.stat)
    Paint(self, f.right, run.next, true, run.stat)
    Ask(self, f)
    Controls(f, true)
    Footer(self, f)
end

-- Opens the table and deals. Says why instead when the album is too thin.
function MF:HigherLowerEnabled() return self.db.settings.higherLower ~= false end

-- Switching the game off: the offer goes, and an open table closes (which
-- ends a run in progress, as closing it always does).
function MF:PutAwayHigherLower()
    if self.HideHigherLowerOffer then self:HideHigherLowerOffer() end
    if panel and panel:IsShown() then panel:Hide() end
end

function MF:OpenHigherLower(source, mode)
    if not self:HigherLowerEnabled() then
        self:Print("Higher or Lower is switched off. Turn it back on in |cffffd100/tfl options|r.")
        return false
    end
    -- Switching game mid-run ends the run that was going, and it counts.
    if run and not run.over then self:EndHigherLower("closed") end
    local started, have = self:StartHigherLower(source, mode)
    if not started then
        self:Print(("Higher or Lower needs %d cards with a weight on them, and you have %d. "
            .. "Land %d more kinds of fish to play."):format(MIN_DECK, have, MIN_DECK - have))
        return false
    end
    panel = panel or Build(self)
    if self.HideHigherLowerOffer then self:HideHigherLowerOffer() end
    Redraw(self)
    panel:Show()
    return true
end

function MF:HigherLowerShown() return panel ~= nil and panel:IsShown() end

MF:Command({ "higherlower", "hl" }, "Solo",
    "/tfl higherlower [weight|caught|waters|mixed] - play Higher or Lower with your cards",
    function(self, args)
        local mode = args[1]
        if mode and mode ~= "" and mode ~= "mixed" and not STATS[mode] then
            self:Print("Play on weight, caught, waters or mixed - for example |cffffd100/tfl hl caught|r.")
            return
        end
        self:OpenHigherLower("manual", mode ~= "" and mode or nil)
    end)

------------------------------------------------------------------------
-- The flight offer
--
-- Asked once a flight, and only if the deck is big enough to play. It is
-- a small note at the top of the screen rather than the table itself,
-- because opening a window on someone who took a flight to get somewhere
-- is how a feature gets switched off.
------------------------------------------------------------------------

local offer
local onTaxi = false

function MF:OnFlight() return onTaxi end

local function BuildOffer(self)
    local o = self:CreatePanel("TheFishingLogHigherLowerOffer", 330, 64,
        { backdrop = "tooltip", strata = "HIGH" })
    o:SetPoint("TOP", 0, -120)
    o.icon = o:CreateTexture(nil, "ARTWORK")
    o.icon:SetSize(38, 38)
    o.icon:SetPoint("LEFT", 12, 0)
    o.icon:SetTexture("Interface\\Icons\\INV_Misc_Ticket_Tarot_Stack_01")
    o.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    o.head = self:CreateText(o, "GameFontNormal")
    o.head:SetPoint("TOPLEFT", o.icon, "TOPRIGHT", 10, -1)
    o.line = self:CreateText(o, "GameFontHighlightSmall")
    o.line:SetPoint("TOPLEFT", o.head, "BOTTOMLEFT", 0, -4)
    o.play = self:CreateButton(o, "Play", 64, function() MF:OpenHigherLower("flight") end)
    o.play:SetPoint("TOPRIGHT", -10, -10)
    o.dismiss = self:CreateButton(o, "Not now", 64, function() MF:HideHigherLowerOffer() end)
    o.dismiss:SetPoint("TOP", o.play, "BOTTOM", 0, -4)
    o.head:SetText("Higher or Lower?")
    o:SetScript("OnUpdate", function(frame)
        if frame.until_ and GetTime() >= frame.until_ then MF:HideHigherLowerOffer() end
    end)
    return o
end

function MF:HideHigherLowerOffer()
    if offer then offer:Hide() end
end

function MF:OfferHigherLower()
    if not (self:HigherLowerEnabled() and self.db.settings.flightGame) or self:HigherLowerShown() then
        return false
    end
    local ready = self:HigherLowerReady()
    if not ready then return false end
    offer = offer or BuildOffer(self)
    local best = self:HigherLowerStats().best
    offer.line:SetText(best > 0 and ("A game for the flight. Best streak: %d."):format(best)
        or ("A game for the flight, with your %d cards."):format(#self:HigherLowerDeck()))
    offer.until_ = GetTime() + OFFER_SECONDS
    offer:Show()
    return true
end

-- Watching for take-off and landing on the tick, because the game has no
-- event that is both reliable and the same on every client for "you got
-- on a gryphon".
function MF:CheckFlightGame()
    local now = type(UnitOnTaxi) == "function" and UnitOnTaxi("player") == true
    if now == onTaxi then return end
    onTaxi = now
    if now then
        self:OfferHigherLower()
    else
        self:HideHigherLowerOffer()
        -- Landing ends a game the flight started. One opened on purpose
        -- is yours to finish.
        if run and not run.over and run.source == "flight" then
            self:EndHigherLower("landed")
            if panel and panel:IsShown() then
                panel.anim = nil
                panel:SetScript("OnUpdate", nil)
                Verdict(self, panel)
                Footer(self, panel)
            end
        end
    end
end

MF:OnTick(function(self) self:CheckFlightGame() end)
