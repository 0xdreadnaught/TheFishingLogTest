-- Cards: one card per species, earned by fishing rather than by rolling.
--
-- Russian Fishing 4 drops cards at random and lets you trade for the ones
-- you never saw. There is no trading here and no server, so a random drop
-- has no second route: a flat chance on top of the 1% specimen roll leaves
-- 46 of the 47 cards blank for months, which is the same objection that
-- killed the specimen pin map.
--
-- So the card is not a drop. It unlocks the first time you land the fish
-- and its edition is your best one so far, which means the album is a map
-- of your fishing rather than a record of your luck. The weights behind it
-- are the ones that already travel and already get checked against the
-- receiver's own tables, so there is nothing here anybody can mint.
--
-- Nothing on a card is stored. Every line is read from the journal, the
-- per-water tallies and the realm's records at the moment you open it,
-- which is also why the wipe needs no code here: clearing the character
-- clears the album with it.
local _, MF = ...

local CARD_W = 300
local WRAP = CARD_W - 40
local STAR = [[|TInterface\TargetingFrame\UI-RaidTargetingIcon_1:13:13|t]]
local card

-- Shared entry point also used by the Anniversary finder override.
function MF:OpenFishFinder(id)
    self.finderFish=id;self.finderSelected=nil
    self:OpenAnglingTools("finder")
end

------------------------------------------------------------------------
-- What the game knows about a fish
--
-- Only where there is something true to say. Most Classic fish have no
-- lore at all - a Longjaw Mud Snapper is a fish called a Longjaw Mud
-- Snapper - and inventing a line for the other forty would be the one
-- thing this addon cannot afford, which is to sound authoritative about
-- something it made up. A card with no note simply doesn't show one.
------------------------------------------------------------------------

local NOTES = {
    [6522]  = "Mutated in the Wailing Caverns. Cooked into Savory Deviate "
           .. "Delight, which turns the eater into a pirate or a ninja - "
           .. "nobody has ever been able to choose which.",
    [6358]  = "Rendered for Elixir of Water Walking and Shadow Oil. The oil "
           .. "is the point; the fish is the inconvenience.",
    [6359]  = "Pressed for Elixir of Fire Power. Stranglethorn's coast is "
           .. "lined with alchemists who have never held a rod.",
    [13422] = "Boiled down to Stonescale Oil, which is why it is fished at "
           .. "night by people who would rather be asleep. Forty eels to a "
           .. "raid's worth of potions.",
    [21071] = "Baked into Sagefish Delight. For a while the best mana food "
           .. "a low-level mage could get was something a fisherman pulled "
           .. "out of Hillsbrad.",
    [21153] = "The grown version, and the reason the Sagefish schools in "
           .. "Wetlands and Ashenvale are never empty for long.",
    [8365]  = "Mithril Head Trout. Named for the colour of its skull, not "
           .. "its contents, though the Dark Iron claim otherwise.",
    [13888] = "Grilled into one of the few Agility foods in the game, which "
           .. "is how a lobster ended up in rogues' bags for a decade.",
    [13755] = "Only surfaces after dark. Cooked into Grilled Squid - the "
           .. "other half of that same rogue's bag.",
    [13756] = "Only feeds in daylight, which makes it the exact opposite of "
           .. "the squid it shares a coastline with.",
    [13759] = "Night only, and worth the lost sleep: Nightfin Soup restores "
           .. "mana while you stand up.",
    [13760] = "Day only. Sunscale Salmon is the fish that taught a "
           .. "generation of anglers to read a clock.",
    [13757] = "Lightning Eel. Caught from the same waters as everything "
           .. "else and sold for more than all of it.",
    [13893] = "The biggest thing on a line in Azeroth. Forty pounds is an "
           .. "ordinary one.",
    [19975] = "Zul'Gurub's own fish, and the only reason anyone fishes "
           .. "inside a raid.",
    [19807] = "Speckled Tastyfish. Worth nothing at all except during the "
           .. "Stranglethorn Fishing Extravaganza, when it is worth the "
           .. "whole tournament.",
    [19803] = "One of the four rare fish that end the Extravaganza. Found "
           .. "in Stranglethorn and nowhere else, by people who are not "
           .. "looking for it.",
    [19805] = "An Extravaganza prize fish. Turned in to Riggle Bassbait, "
           .. "who has never once seemed impressed.",
    [19806] = "An Extravaganza prize fish, and the one most often caught by "
           .. "somebody who had given up.",
    [19808] = "An Extravaganza prize fish. Rockhide, because it is easier "
           .. "to say than what it looks like.",
    -- Nat Pagle's four. "Nat Pagle, Angler Extreme" wants one of each,
    -- from four coasts, and pays in Nat's Lucky Fishing Pole. It asks for
    -- 225 fishing, which is exactly where the beta caps - so it is a
    -- quest the Pre-Season can actually finish.
    [16967] = "One of Nat Pagle's four. He wants one from the Verdantis "
           .. "River, and will not seem impressed when you bring it.",
    [16970] = "One of Nat Pagle's four, from the Misty Reed Strand in the "
           .. "Swamp of Sorrows. The worst of the four to fish for, "
           .. "according to everyone who has.",
    [16968] = "One of Nat Pagle's four, from Sar'theris Strand on the "
           .. "Desolace coast. Named after the beach, like most things "
           .. "nobody could think of a name for.",
    [16969] = "One of Nat Pagle's four, from the Savage Coast. Bring all "
           .. "four to Theramore and he hands over his lucky pole.",
    [12238] = "Gubber Blump in Auberdine wants six, and gives out the "
           .. "Blump Family Fishing Pole for them. He says they make good "
           .. "eating, and that he catches them for fun anyway.",
    [6458]  = "Oil Covered Fish. Pulled out of the Oil Fields in Dustwallow "
           .. "and good for absolutely nothing.",
    [6299]  = "Sickly Looking Fish. It is not sick. It looks sick. It has "
           .. "always looked like that.",
    [1467]  = "Spotted Sunfish. One of the oldest fish in the game's files "
           .. "and one of the least remarkable in its water.",
    [6317]  = "Loch Frenzy. Loch Modan's water is fresh, cold, and full of "
           .. "something that bites back.",
    [13890] = "Plated Armorfish. Named by somebody who had to get the hook "
           .. "out of it.",
    [6360]  = "Steelscale Crushfish. The name is a warning and the weight "
           .. "is not.",
}

-- The bloated fish are ordinary fish with something inside them, and the
-- same sentence is true of all six. The list lives in Fish.lua, which is
-- also where the bounty picker reads it to leave them out.
for _, id in ipairs(MF.BLOATED) do
    NOTES[id] = "Swallowed something it shouldn't have. Cut open for "
        .. "whatever the last thing it ate was carrying."
end

------------------------------------------------------------------------
-- Reading the card off the data
------------------------------------------------------------------------

-- Your entry, the realm's best, and the numbers that go on the face.
-- Nil when you have never landed one: that card is still face down.
function MF:CardFor(id)
    local j = self.cdb.profile.journal[id]
    if not j then return nil end

    local waters = 0
    for _ in pairs(self.cdb.caughtIn[id] or {}) do waters = waters + 1 end

    local edition, colour = self:Edition(id, j.b, (j.s or 0) > 0)
    return { id = id, count = j.c or 0, best = j.b or 0, specimen = j.s or 0,
        waters = waters, edition = edition, colour = colour }
end

-- What a card of this weight is called, and in what colour. Split out
-- because the upgrade notice has to ask the same question about the
-- fish you had before, and two copies of this rule would drift.
function MF:Edition(id, best, specimen)
    if specimen then return "specimen", self.C.spec end
    local name, colour = self:WeightGradeShort(id, best)
    return name or "caught", colour or "|cffbbbbbb"
end

-- The heaviest of this species anybody on the realm has told us about,
-- and who holds it. The card is a scoreboard, not a trophy shelf.
function MF:CardRealmBest(id)
    local held = self:SpeciesRecords()
    for _, rec in ipairs(held) do
        if rec.id == id then return rec end
    end
    return nil
end

-- How much of the album is turned over.
function MF:CardsHeld()
    local held, total = 0, 0
    for id in pairs(self.FISH) do
        total = total + 1
        if self.cdb.profile.journal[id] then held = held + 1 end
    end
    return held, total
end

-- The water your heaviest of this species came out of. Its proper name
-- where the spot has one, and the zone when it doesn't - the same
-- fallback the journal uses, so a card never shows a raw spot key.
function MF:CardBestWater(id)
    local heaviest, zone, key
    for z, here in pairs(self.cdb.caughtIn[id] or {}) do
        if not heaviest or (here.b or 0) > heaviest then
            heaviest, zone, key = here.b or 0, z, here.spot
        end
    end
    if not zone then return nil end
    local named = key and self:KnownSpotName(self:CanonicalKey(key))
    if named and named ~= zone then
        return ("%s, %s"):format(named, zone), key
    end
    return zone, key
end

-- Use the saved personal-best catch, never a record-sync or sharing time.
function MF:CardBestCaughtAt(id)
    local j=self.cdb.profile.journal[id]
    if not j then return nil end
    local function Caught(key)
        local r=(self.cdb.records[key] or {})[id]
        local at=r and r.when
        if r and type(r.weight)=="number" and type(j.b)=="number"
            and self.Hundredths(r.weight)==self.Hundredths(j.b) and type(at)=="number"
            and at>0 and at==math.floor(at) and at<=GetServerTime()+300 then return at end
    end
    local _,key=self:CardBestWater(id)
    if key then return Caught(key) or Caught(self:CanonicalKey(key)) end
    local earliest
    for spot in pairs(self.cdb.records) do
        local at=Caught(spot)
        if at and (not earliest or at<earliest) then earliest=at end
    end
    return earliest
end

-- Trophies
--
-- A "22 Pound Catfish" is the most trophy-shaped thing the game has and
-- it had no card, because the album walked MF.FISH and trophies live in
-- a table of their own. They are a category inside the album rather than
-- a second album: the 47 is a count of species, and a trophy is not one.
--
-- Two things make them their own kind. A trophy can never be a specimen
-- - RollWeight returns its fixed weight before the specimen roll - so a
-- trophy card never reaches the top edition and never catches the light.
-- And there is no zone data behind one, only the weight on the tin,
-- which turns out to be the better line anyway.
function MF:IsTrophyCard(id, name)
    return self:TrophyWeight(id, name) ~= nil
end

-- Held, heaviest first, and how many there are to find.
function MF:TrophyCards()
    local held = {}
    for id in pairs(self.TROPHY) do
        if self.cdb.profile.journal[id] then held[#held + 1] = id end
    end
    table.sort(held, function(a, b)
        if self.TROPHY[a] ~= self.TROPHY[b] then return self.TROPHY[a] > self.TROPHY[b] end
        return a < b
    end)
    return held, self.Count(self.TROPHY)
end

function MF:CardNote(id) return NOTES[id] end

------------------------------------------------------------------------
-- The card itself
--
-- A collectible has to read as one before a word of it is read: the art
-- first, the name under it, and the rarity carried by colour rather than
-- by a caption. v1 was a tooltip - a small icon in a corner, the title
-- wrapping beside it and a left-aligned list underneath - and it sat in a
-- fixed 404 of grey whatever it had to say, so most cards were half empty.
--
-- So the frame is sized to its contents now, the edition owns the border
-- and the name, and the art is the middle of the top rather than a corner
-- of it.
--
-- v2 was a tooltip that filled itself in: art, name, then seven "label /
-- value" pairs at one weight, so the pond your best came out of read the
-- same as how many waters you had fished. v3 makes the frame say the
-- edition before a word is read - border, a wash behind the art and a glow
-- around it, all in the edition's colour - and groups the face into a few
-- short sections with the realm record drawn as a bar you can close in on.
------------------------------------------------------------------------

local PAD = 18
local ART = 84             -- the icon inside is 64: the source's own size, so it stays sharp
local ICON = ART - 20
local GAP = 10
local SECTION_GAP = 12
local BUTTON_ROW = 22
local FOOT = 14 + BUTTON_ROW + GAP
local MIN_HEIGHT = 400     -- cards come out near one shape rather than any shape
local BAR_H = 6
local WASH_H = PAD + ART + 46
local GREY = "|cff858585"

-- "|cffRRGGBB" to the three numbers a border wants.
local function RGB(code)
    local hex = type(code) == "string" and code:match("^|c%x%x(%x%x%x%x%x%x)$")
    if not hex then return 1, 1, 1 end
    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end

-- The art is the item's icon, and that is all there is
--
-- A fish's own 3D model would have been a better card face, and this
-- client will not give us one: SetItem is accepted without complaint and
-- nothing ever arrives, checked after a wait and with OnModelLoaded
-- hooked, so there is nothing to wait longer for.
--
-- So the icon has to carry it, and the frame around it does the rest.
-- A card you haven't earned shows the shape and nothing else: the name
-- was already "???", and a greyed-out icon gave the answer away anyway.
local function Art(self, f, id, known)
    f.icon:SetTexture(self:FishIcon(id))
    f.icon:SetDesaturated(not known)
    if known then f.icon:SetVertexColor(1, 1, 1) else f.icon:SetVertexColor(0, 0, 0) end
    f.mystery:SetShown(not known)
end

-- A gradient, either way round. Modern signature first, the old one
-- after: a wash is not worth an error if the client changes under us.
-- from is the left or bottom end, to the right or top.
local function Gradient(tex, orient, r, g, b, from, to)
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, orient,
            CreateColor(r, g, b, from), CreateColor(r, g, b, to))
        if ok then return true end
    end
    if tex.SetGradientAlpha then
        local ok = pcall(tex.SetGradientAlpha, tex, orient, r, g, b, from, r, g, b, to)
        if ok then return true end
    end
    -- No gradient to be had, so a flat tint at half strength.
    tex:SetColorTexture(r, g, b, math.max(from, to) / 2)
    return false
end

-- Shared with the Higher or Lower table, which draws small card faces in the
-- same colours. Read-only helpers: nothing about this card changes.
MF.CardRGB, MF.CardGradient = RGB, Gradient

------------------------------------------------------------------------
-- The holographic specimen
--
-- A rare card you can tell apart from across the table is most of what a
-- collection is for. A specimen is the one worth a moving part: a band of
-- light that crosses the art every few seconds, the way a holo card
-- catches a lamp when you tilt it. Only specimens get it - a sheen on
-- every card is wallpaper.
--
-- Two halves back to back rather than one band, because a gradient only
-- ramps one way and a sheen needs to fade in and out again. Each half is
-- drawn ADD, so it lightens what is underneath instead of covering it,
-- and the art frame clips so nothing escapes over the name.
------------------------------------------------------------------------

local SWEEP = 0.85       -- seconds the band takes to cross
local REST = 2.9         -- seconds of stillness between sweeps
local BAND = 15          -- half-width of the band, in pixels
local BRIGHT = 0.42      -- how much light the middle of it adds

local function BuildSheen(f)
    f.art:SetClipsChildren(true)
    f.sheen = {}
    for i = 1, 2 do
        local t = f.art:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, BRIGHT)
        t:SetBlendMode("ADD")
        t:SetSize(BAND, ART * 2)
        -- Leaning over, so it crosses the fish rather than wiping it.
        pcall(t.SetRotation, t, 0.42)
        t:Hide()
        f.sheen[i] = t
    end
    Gradient(f.sheen[1], "HORIZONTAL", 1, 1, 1, 0, BRIGHT)
    Gradient(f.sheen[2], "HORIZONTAL", 1, 1, 1, BRIGHT, 0)
end

local function Sheen(f, on)
    f.holo = on or nil
    f.sheenAt = 0
    for _, t in ipairs(f.sheen or {}) do t:SetShown(false) end
    if on then f:SetScript("OnUpdate", f.sheenTick) else f:SetScript("OnUpdate", nil) end
end

local function SheenTick(f, dt)
    if not f.holo or not f.sheen then return end
    f.sheenAt = (f.sheenAt or 0) + dt
    local cycle = SWEEP + REST
    local t = f.sheenAt % cycle
    if t > SWEEP then
        for _, tex in ipairs(f.sheen) do tex:Hide() end
        return
    end
    -- Starts off the left edge and finishes off the right, so the band
    -- is never parked half-way across when the sweep ends.
    local span = ART + BAND * 4
    local x = -BAND * 2 + span * (t / SWEEP)
    for i, tex in ipairs(f.sheen) do
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", f.art, "LEFT", x + (i - 1) * BAND, 0)
        tex:Show()
    end
end

------------------------------------------------------------------------
-- Building the frame
------------------------------------------------------------------------

local PIPS = 7             -- six grades and the specimen above them
local PIP_W, PIP_H, PIP_GAP = 18, 4, 3

-- A heading and its text, made the first time a card needs that many.
local function Section(self, f, i)
    local s = f.sections[i]
    if s then return s end
    s = {}
    s.head = self:CreateText(f, "GameFontNormalSmall")
    s.head:SetJustifyH("LEFT")
    s.body = self:CreateText(f, "GameFontHighlightSmall")
    s.body:SetWidth(WRAP)
    s.body:SetJustifyH("LEFT")
    s.body:SetSpacing(2)
    s.body:SetWordWrap(true)
    f.sections[i] = s
    return s
end

local function Build(self)
    local f = self:CreatePanel("TheFishingLogCard", CARD_W, MIN_HEIGHT,
        { backdrop = "tooltip", strata = "DIALOG", movable = true, escCloses = true,
          fill = self.FILL_READING, close = true })
    f.readingSurface = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.readingSurface:SetPoint("TOPLEFT", 4, -4)
    f.readingSurface:SetPoint("BOTTOMRIGHT", -4, 4)
    f.readingSurface:SetColorTexture(unpack(self.FILL_READING))

    -- With the UI Rework: the card is a page that folds out of the journal,
    -- so it stands on the journal's own stone. The stone is a frame of its
    -- own, kept one level under the card so everything drawn on the card
    -- stays on top; the card's own fill goes, and its edition-coloured edge
    -- stays.
    local Wd = self.Rework and self.Rework.W
    if Wd then
        f.ground = Wd:Ground(f)
        f.ground:SetPoint("TOPLEFT", 4, -4)
        f.ground:SetPoint("BOTTOMRIGHT", -4, 4)
        Wd:HideTopCorners(f.ground) -- they'd sit under the close button and the fish
        local function Under() f.ground:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1)) end
        Under()
        -- Opening brings the card to the front, which moves its level
        f:HookScript("OnShow", function() Under() C_Timer.After(0, Under) end)
        f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f.readingSurface:Hide()
    end

    -- The edition's colour, fading down from the top edge, so the card
    -- says what it is before you have found the name.
    f.wash = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.wash:SetPoint("TOPLEFT", 4, -4)
    f.wash:SetPoint("TOPRIGHT", -4, -4)
    f.wash:SetHeight(WASH_H)
    f.wash:SetColorTexture(1, 1, 1, 1)

    -- A soft ring of the same colour around the art. The action-button
    -- glow is in every client and is already a soft square of light.
    f.glow = f:CreateTexture(nil, "BORDER")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetSize(ART * 1.9, ART * 1.9)

    -- The art sits in a frame of its own so the edition can colour its
    -- border without touching the card's.
    f.art = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.art:SetSize(ART, ART)
    f.art:SetPoint("TOP", 0, -PAD)
    f.art:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f.art:SetBackdropColor(0, 0, 0, 0.6)
    f.glow:SetPoint("CENTER", f.art, "CENTER")

    f.icon = f.art:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(ICON, ICON)
    f.icon:SetPoint("CENTER")
    -- Every item icon has a grey bevel baked into the texture. Cropping
    -- the outer 7% gets the art without a frame inside the frame.
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- With the UI Rework, the fish wears the gold ring its other windows use
    -- (the edition still colours the card's edge, the wash and the glow)
    if Wd then
        local ring = CreateFrame("Frame", nil, f)
        ring:SetAllPoints(f.art)
        ring:SetFrameLevel(f.art:GetFrameLevel() + 3)
        ring.tex = ring:CreateTexture(nil, "OVERLAY")
        ring.tex:SetPoint("CENTER", -1, 2)
        ring.tex:SetSize(ART * 1.38, ART * 1.38)
        if not Wd:Atlas(ring.tex, "ui-achievement-iconframe") then
            ring.tex:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
            ring.tex:SetTexCoord(0, 0.5625, 0, 0.5625)
        end
        f.ring = ring
        f.art:SetBackdropColor(0, 0, 0, 1)
    end

    f.mystery = f.art:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.mystery:SetPoint("CENTER", 0, -1)
    f.mystery:SetText("?")
    f.mystery:SetTextColor(0.55, 0.55, 0.55)

    f.name = self:CreateText(f, "GameFontNormalLarge")
    f.name:SetPoint("TOP", f.art, "BOTTOM", 0, -GAP)
    f.name:SetWidth(CARD_W - PAD * 2)
    f.name:SetJustifyH("CENTER")
    f.name:SetWordWrap(true)

    f.edition = self:CreateText(f, "GameFontNormalSmall")
    f.edition:SetPoint("TOP", f.name, "BOTTOM", 0, -5)
    f.edition:SetWidth(CARD_W - PAD * 2)
    f.edition:SetJustifyH("CENTER")

    -- The grade ladder: one pip per edition, lit up to the one you hold.
    f.pips = {}
    for i = 1, PIPS do
        local p = f:CreateTexture(nil, "ARTWORK")
        p:SetSize(PIP_W, PIP_H)
        p:SetColorTexture(1, 1, 1, 1)
        f.pips[i] = p
    end
    f.nextGrade = self:CreateText(f, "GameFontDisableSmall")
    f.nextGrade:SetWidth(WRAP)
    f.nextGrade:SetJustifyH("CENTER")

    f.owner = self:CreateText(f, "GameFontDisableSmall")
    f.owner:SetWidth(WRAP)
    f.owner:SetJustifyH("CENTER")
    f.owner:SetWordWrap(true)

    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetHeight(1)
    f.rule:SetColorTexture(1, 1, 1, 0.12)

    -- The two numbers somebody opens a card to see get the size.
    f.tally = self:CreateText(f, "GameFontHighlightLarge")
    f.tally:SetJustifyH("LEFT")
    f.tallyLabel = self:CreateText(f, "GameFontDisableSmall")
    f.tallyLabel:SetJustifyH("LEFT")
    f.best = self:CreateText(f, "GameFontHighlightLarge")
    f.best:SetJustifyH("RIGHT")
    f.bestLabel = self:CreateText(f, "GameFontDisableSmall")
    f.bestLabel:SetJustifyH("RIGHT")

    f.rule2 = f:CreateTexture(nil, "ARTWORK")
    f.rule2:SetHeight(1)
    f.rule2:SetColorTexture(1, 1, 1, 0.12)

    f.sections = {}

    -- How close you are to the realm's heaviest, as a bar to fill.
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetSize(WRAP, BAR_H)
    f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bar.bg:SetAllPoints()
    f.bar.bg:SetColorTexture(1, 1, 1, 0.08)
    f.bar.fill = f.bar:CreateTexture(nil, "ARTWORK")
    f.bar.fill:SetPoint("TOPLEFT")
    f.bar.fill:SetPoint("BOTTOMLEFT")
    f.bar.fill:SetColorTexture(1, 1, 1, 1)
    f.barPct = self:CreateText(f, "GameFontHighlightSmall")
    f.barPct:SetJustifyH("RIGHT")

    -- Only the native-waters line opens the full list. It used to cover
    -- the whole body, so hovering the date of your best did it too.
    f.nativeHover = CreateFrame("Frame", nil, f)
    f.nativeHover:EnableMouse(true)
    f.nativeHover:SetScript("OnEnter", function(frame)
        if not f.nativeZones then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Native waters")
        GameTooltip:AddLine(f.nativeZones, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.nativeHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Flavour text in a box of its own at the foot of the card, where a
    -- trading card keeps it: read last, and plainly not a statistic.
    f.flavour = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.flavour:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f.flavour:SetBackdropColor(0, 0, 0, 0.28)
    f.flavour:SetBackdropBorderColor(1, 1, 1, 0.08)
    f.note = self:CreateText(f.flavour, "GameFontDisableSmall")
    f.note:SetPoint("TOPLEFT", 10, -8)
    f.note:SetWidth(WRAP - 20)
    f.note:SetJustifyH("LEFT")
    f.note:SetSpacing(2)
    f.note:SetWordWrap(true)
    f.note:SetTextColor(0.72, 0.68, 0.58)

    -- One row of buttons; Close is the X in the corner.
    f.find = self:CreateButton(f, "Find waters", 80, function()
        MF:OpenFishFinder(f.fishID); f:Hide()
    end)
    f.track = self:CreateButton(f, "Track goal", 80, function()
        if f.shared then MF:ShowCard(f.fishID)
        elseif f.fishID then MF:OpenFishingGoal(f.fishID) f:Hide() end
    end)
    f.share = self:CreateButton(f, "Share", 80, function()
        if f.fishID then MF:OpenCardShare(f.fishID) end
    end)

    f.sheenTick = SheenTick
    BuildSheen(f)

    return f
end

------------------------------------------------------------------------
-- Laying it out
--
-- Everything below the art hangs off whatever the thing above it turned
-- out to be. Measured rather than assumed: a two-line fish name is common
-- and a ten-zone list is normal.
------------------------------------------------------------------------

local function Rule(f, tex, y)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    tex:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
    return y + 1
end

local function At(f, region, y, point, x)
    region:ClearAllPoints()
    region:SetPoint(point or "TOPLEFT", f, point or "TOPLEFT", x or PAD, -y)
end

local function Buttons(f)
    local shown = {}
    for _, b in ipairs({ f.find, f.track, f.share }) do
        if b:IsShown() then shown[#shown + 1] = b end
    end
    local gap = 6
    local w = (CARD_W - 28 - gap * (#shown - 1)) / #shown
    for i, b in ipairs(shown) do
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14 + (i - 1) * (w + gap), 14)
    end
end

-- view: { stats, pips, sections = { { head, text, bar, hover } }, note }
local function Layout(f, view)
    local y = PAD + ART + GAP + f.name:GetStringHeight() + 5 + f.edition:GetStringHeight()

    for i, p in ipairs(f.pips) do
        p:SetShown(view.pips ~= nil and i <= #view.pips)
    end
    if view.pips then
        y = y + 6
        local n = #view.pips
        local row = n * PIP_W + (n - 1) * PIP_GAP
        for i, pip in ipairs(view.pips) do
            local p = f.pips[i]
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", f, "TOP", -row / 2 + (i - 1) * (PIP_W + PIP_GAP), -y)
            p:SetVertexColor(pip.r, pip.g, pip.b, pip.a)
        end
        y = y + PIP_H
    end

    if f.nextGrade:GetText() and f.nextGrade:GetText() ~= "" then
        f.nextGrade:Show()
        At(f, f.nextGrade, y + 5, "TOP", 0)
        y = y + 5 + f.nextGrade:GetStringHeight()
    else
        f.nextGrade:Hide()
    end

    At(f, f.owner, y + 6, "TOP", 0)
    y = y + 6 + f.owner:GetStringHeight()
    y = Rule(f, f.rule, y + GAP) + GAP

    for _, fs in ipairs({ f.tally, f.tallyLabel, f.best, f.bestLabel }) do
        fs:SetShown(view.stats)
    end
    f.rule2:SetShown(view.stats)
    if view.stats then
        At(f, f.tally, y)
        At(f, f.best, y, "TOPRIGHT", -PAD)
        local row = math.max(f.tally:GetStringHeight(), f.best:GetStringHeight())
        At(f, f.tallyLabel, y + row + 1)
        At(f, f.bestLabel, y + row + 1, "TOPRIGHT", -PAD)
        y = y + row + 1 + f.tallyLabel:GetStringHeight()
        y = Rule(f, f.rule2, y + GAP) + GAP
    end

    f.bar:Hide(); f.barPct:Hide(); f.nativeHover:Hide()
    for i, s in ipairs(f.sections) do
        local want = view.sections[i]
        s.head:SetShown(want ~= nil)
        s.body:SetShown(want ~= nil)
    end
    for i, want in ipairs(view.sections) do
        local s = f.sections[i]
        if i > 1 then y = y + SECTION_GAP end
        At(f, s.head, y)
        local headY = y
        y = y + s.head:GetStringHeight() + 4
        if want.bar then
            At(f, f.bar, y + 1)
            At(f, f.barPct, headY, "TOPRIGHT", -PAD)
            f.bar:Show(); f.barPct:Show()
            y = y + BAR_H + 6
        end
        At(f, s.body, y)
        if want.hover then
            f.nativeHover:ClearAllPoints()
            f.nativeHover:SetAllPoints(s.body)
            f.nativeHover:Show()
        end
        y = y + s.body:GetStringHeight()
    end

    if view.note then
        f.flavour:Show()
        f.flavour:ClearAllPoints()
        f.flavour:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + GAP + 4))
        local h = f.note:GetStringHeight() + 16
        f.flavour:SetSize(WRAP, h)
        y = y + GAP + 4 + h
    else
        f.flavour:Hide()
    end

    Buttons(f)
    f:SetHeight(math.max(MIN_HEIGHT, y + GAP + FOOT))
end

-- CreatePanel deliberately leaves positioning to the caller. Beside the
-- journal you opened it from, since that is where you are looking, and the
-- middle of the screen when the journal isn't up. It stays draggable after.
local function Place(self, f)
    f:ClearAllPoints()
    local journal = self.journalWindow
    if journal and journal:IsShown() then
        f:SetPoint("TOPLEFT", journal, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER")
    end
end

-- A fish lives in ten zones, and the list was most of the card. It stays
-- whole on a card you have not earned, where it is the reason to go
-- anywhere; on one you have, three and a count, with the rest on hover.
local function Zones(f, limit)
    local z = f and f.zones
    if not z or #z == 0 then return nil end
    if not limit or #z <= limit then return table.concat(z, ", ") end
    return ("%s %s+%d more|r"):format(table.concat(z, ", ", 1, limit), GREY, #z - limit)
end

-- The edition colours the frame: border, the wash from the top, and the
-- glow behind the art. Grey editions get less of it, so a monster and a
-- tiddler don't glow alike.
local function Tint(f, r, g, b, strength)
    f:SetBackdropBorderColor(r, g, b)
    -- A ringed fish (UI Rework) has the ring for its frame, not a coloured edge
    f.art:SetBackdropBorderColor(r, g, b, f.ring and 0 or 1)
    -- and the ring wears the edition, as its tile in the Collection does: the gold
    -- art greyed first so the colour comes out true rather than muddied by the gold
    if f.ring then
        f.ring.tex:SetDesaturated(true)
        f.ring.tex:SetVertexColor(r, g, b)
    end
    -- On the stone a pale edition's wash all but vanished, so it gets a floor.
    -- (An uncaught card, at 0.15, stays the faint grey it means to be.)
    local wash = strength
    if f.ground and strength >= 0.3 then wash = math.max(strength, 0.6) end
    Gradient(f.wash, "VERTICAL", r, g, b, 0, 0.30 * wash)
    f.glow:SetVertexColor(r, g, b)
    f.glow:SetAlpha(0.85 * strength)
    f.glow:SetShown(strength > 0)
end

-- The ladder as pips, and a line saying what the next one asks for.
-- Returns the pips (nil when there is nothing to grade against) and that line.
local function Ladder(self, id, c)
    local ladder = self:GradeLadder(id)
    if not ladder then return nil, nil end
    local trophy = self:TrophyWeight(id) ~= nil
    local p = self:WeightPercentile(id, c.best) or 0
    local held = #ladder
    for i, g in ipairs(ladder) do
        if p <= g.p then held = i break end
    end
    local specimen = (c.specimen or 0) > 0
    local pips = {}
    for i, g in ipairs(ladder) do
        local r, gg, b = RGB(g.colour)
        local lit = specimen or i <= held
        pips[i] = { r = r, g = gg, b = b, a = lit and 1 or 0.18 }
    end
    if not trophy then
        local r, g, b = RGB(self.C.spec)
        pips[#pips + 1] = { r = r, g = g, b = b, a = specimen and 1 or 0.18 }
    end

    local line
    if specimen then
        line = "The top edition there is."
    elseif held < #ladder and ladder[held].upTo then
        local nxt = ladder[held + 1]
        line = ("Next: %s%s|r above %s"):format(nxt.colour, nxt.short, self:Weight(ladder[held].upTo))
    elseif trophy then
        line = "The best a trophy can be."
    else
        line = ("Only a %sspecimen|r ranks higher."):format(self.C.spec)
    end
    return pips, line
end

-- The fish your own card is showing, or nil (a shared card isn't yours).
function MF:CardFish()
    return card and card:IsShown() and not card.shared and card.fishID or nil
end

function MF:HideCard()
    if card then card:Hide() end
end

function MF:ShowCard(id, shared)
    -- Whatever row was hovered to open this card leaves its tooltip
    -- behind otherwise, sitting over the card.
    GameTooltip:Hide()
    card = card or Build(self)
    card.fishID = id
    card.shared = shared
    card.track:SetText(shared and "View mine" or "Track goal")
    Place(self, card)
    local c = shared or self:CardFor(id)
    card.share:SetShown(not shared and c ~= nil)
    Art(self, card, id, c ~= nil)

    local owner = (shared and self:ShortName(shared.owner) or self.me or "Your") .. "'s collection"
    if shared then
        owner = owner .. "\nShared snapshot, " .. date("%d %b %Y %H:%M", shared.at)
    end
    card.owner:SetText(owner)

    local fish = self.FISH[id]
    local trophy = self:TrophyWeight(id)
    card.nativeZones = Zones(fish)
    local view = { sections = {} }
    local function Add(head, text, extra)
        if not text or text == "" then return end
        local s = Section(self, card, #view.sections + 1)
        s.head:SetText(head:upper())
        s.body:SetText(text)
        local entry = extra or {}
        view.sections[#view.sections + 1] = entry
    end

    if not c then
        -- A card you haven't earned says what it is and where to look,
        -- and nothing else. The blank is the invitation.
        card.name:SetText(GREY .. "???|r")
        card.edition:SetText("|cff6a6a6aNOT CAUGHT|r")
        card.nextGrade:SetText("Land one to turn this card over.")
        Tint(card, 0.35, 0.35, 0.35, 0.15)
        card.tally:SetText(""); card.tallyLabel:SetText("")
        card.best:SetText(""); card.bestLabel:SetText("")
        if trophy then
            Add("Always", ("%s, give or take the fraction"):format(self:Weight(trophy, 0)))
        else
            Add("Lives in", Zones(fish) or "Somewhere")
            if fish then Add("Usual size", ("%s to %s"):format(self:Weight(fish.min, 1), self:Weight(fish.max, 1))) end
        end
        local realm = self:CardRealmBest(id)
        if realm and (realm.w or 0) > 0 then
            Add("Realm record", ("%s, held by %s"):format(self:Weight(realm.w), self:ShortName(realm.h or "?")))
        end
        card.note:SetText("")
        Sheen(card, false)
        Layout(card, view)
        card:Show()
        return
    end

    -- The edition is the whole point of a collection, so it carries the
    -- name and the frame rather than sitting underneath as a caption.
    card.name:SetText(("%s%s|r"):format(c.colour, self:FishName(id)))
    card.edition:SetText(("%s%s|r"):format(c.colour, c.edition:upper()))
    local grey = c.colour == "|cff808080" or c.colour == "|cff9d9d9d" or c.colour == "|cffbbbbbb"
    local r, g, b = RGB(c.colour)
    Tint(card, r, g, b, grey and 0.3 or 1)
    local pips, nextLine = Ladder(self, id, c)
    view.pips = pips
    card.nextGrade:SetText(nextLine or "")

    view.stats = true
    card.tally:SetText(tostring(c.count))
    card.tallyLabel:SetText("Caught")
    -- Your best already counts your specimens, so printing both was the
    -- same number twice on almost every card that had one.
    local starred = c.specimen >= c.best
    card.best:SetText(("|cffffffff%s|r%s"):format(self:Weight(c.best), starred and ("  " .. STAR) or ""))
    card.bestLabel:SetText(starred and "Best specimen" or "Personal best")

    -- Where it came from, which is the thing only this addon knows. A zone
    -- list can be looked up; the pond you pulled your best out of cannot.
    local water, caughtAt
    if shared then water, caughtAt = shared.water, shared.caughtAt
    else water, caughtAt = self:CardBestWater(id), self:CardBestCaughtAt(id) end
    local when = caughtAt and (GREY .. date("%d %b %Y, %H:%M", caughtAt) .. "|r")
    Add(shared and "Their best" or "Your best",
        water and when and (water .. "\n" .. when) or water or when)

    local history = {}
    if not shared then
        local entry = self.cdb.profile.journal[id]
        local first = entry and entry.firstCatch
        if type(first) == "table" and type(first.at) == "number" and first.at > 0
            and first.at <= GetServerTime() and type(first.name) == "string" then
            history[#history + 1] = "First caught in " .. first.name
            history[#history + 1] = GREY .. date("%d %b %Y, %H:%M", first.at) .. "|r"
        end
    end
    if c.waters > 0 then
        history[#history + 1] = ("Landed in %d %s"):format(c.waters, c.waters == 1 and "water" or "waters")
    end
    Add("History", table.concat(history, "\n"))

    local realm = self:CardRealmBest(id)
    if realm and (realm.w or 0) > 0 then
        -- Who holds it, not whether the weight looks like yours. Comparing
        -- weights read your ordinary best and missed your own specimen.
        local mine = self:AnglerKey(realm.h) == self:AnglerKey(self.me)
        local theirs = shared and self:AnglerKey(realm.h) == self:AnglerKey(shared.owner)
        local holds = mine and not shared
        local ratio = math.min(1, c.best / realm.w)
        if theirs then ratio = 1 end
        local holder = (mine and "you") or (theirs and "them")
            or self:ShortName(realm.h or "?")
        Add(shared and "Realm record (your client)" or "Realm record",
            ("%s, held by %s"):format(self:Weight(realm.w), holder), { bar = true })
        local top = holds or theirs or ratio >= 1
        card.barPct:SetText(top and "|cffffd100Record|r" or ("%d%%"):format(math.floor(ratio * 100)))
        card.bar.fill:SetWidth(math.max(1, WRAP * ratio))
        if top then card.bar.fill:SetVertexColor(1, 0.82, 0)
        else card.bar.fill:SetVertexColor(RGB(c.colour)) end
    end

    if trophy then
        -- The whole identity of a trophy, and the only thing it is sure
        -- of: the fraction is what tells two of them apart.
        Add("Always", ("%s, give or take the fraction"):format(self:Weight(trophy, 0)))
    else
        local z = Zones(fish, 3)
        Add("Native waters", z, { hover = fish and fish.zones and #fish.zones > 3 })
    end

    view.note = NOTES[id]
    card.note:SetText(view.note or "")
    Sheen(card, c.specimen > 0)
    Layout(card, view)
    card:Show()
end

------------------------------------------------------------------------
-- The album, as a view inside the Journal tab
------------------------------------------------------------------------

local function Header(text) return { text = "|cffffd100" .. text .. "|r", header = true } end

-- Earned cards first, best edition at the top, then the face-down ones
-- smallest first - the next card you are likely to turn over.
function MF:AlbumLines(out)
    local journal = self.cdb.profile.journal
    local latest = self.cdb.profile.latestSpecimen
    if latest and journal[latest.id] and (journal[latest.id].s or 0) > 0 then
        out[#out + 1] = Header("Latest specimen")
        out[#out + 1] = { text = self:FishName(latest.id), icon = self:FishIcon(latest.id),
            right = self.C.spec .. "Foil  " .. self:Weight(latest.weight) .. "|r",
            onClick = function() self:ShowCard(latest.id) end }
        self:NoteRows(out, (latest.spot or "Unknown water") .. " - " .. date("%d %b %H:%M", latest.at))
        out[#out + 1] = { text = "" }
    end
    local held, blank = {}, {}
    for id in pairs(self.FISH) do
        if journal[id] then held[#held + 1] = id else blank[#blank + 1] = id end
    end
    table.sort(held, function(a, b)
        local pa = self:WeightPercentile(a, journal[a].b) or 0
        local pb = self:WeightPercentile(b, journal[b].b) or 0
        local sa, sb = (journal[a].s or 0) > 0, (journal[b].s or 0) > 0
        if sa ~= sb then return sa end
        if pa ~= pb then return pa > pb end
        return a < b
    end)
    table.sort(blank, function(a, b) return self.FISH[a].max < self.FISH[b].max end)

    local count, total = self:CardsHeld()
    out[#out + 1] = Header(("Album  -  %d of %d"):format(count, total))
    self:NoteRows(out, "Sorted by: specimens first, then best relative grade.")

    for _, id in ipairs(held) do
        local c = self:CardFor(id)
        out[#out + 1] = {
            text = self:FishName(id), icon = self:FishIcon(id),
            right = ("%s%s%s|r   |cffa0a0a0x%d|r"):format(
                c.specimen > 0 and (STAR .. " ") or "", c.colour, c.edition, c.count),
            onClick = function() self:ShowCard(id) end,
        }
    end

    -- A category inside the album rather than a second album. The
    -- headline stays a count of species, because a trophy is not one -
    -- and the ones you have not landed are a line rather than 32 more
    -- rows of "???", which would be most of the list.
    local trophies, allTrophies = self:TrophyCards()
    if #trophies > 0 or allTrophies > 0 then
        out[#out + 1] = { text = "" }
        out[#out + 1] = Header(("Trophies  -  %d of %d"):format(#trophies, allTrophies))
        for _, id in ipairs(trophies) do
            local c = self:CardFor(id)
            out[#out + 1] = {
                text = self:FishName(id), icon = self:FishIcon(id),
                right = ("%s%s|r   |cffa0a0a0x%d|r"):format(c.colour, c.edition, c.count),
                onClick = function() self:ShowCard(id) end,
            }
        end
        if #trophies == 0 then
            self:NoteRows(out, "Named fish that always weigh what they say. "
                .. "You have not landed one yet.")
        end
    end

    if #blank > 0 then
        out[#out + 1] = { text = "" }
        out[#out + 1] = Header(("Face down  -  %d"):format(#blank))
        for _, id in ipairs(blank) do
            out[#out + 1] = {
                text = "|cff858585???|r", icon = 134400,
                right = ("|cff6a6a6a%s|r"):format(
                    self.FISH[id].zones and self.FISH[id].zones[1] or "somewhere"),
                onClick = function() self:ShowCard(id) end,
            }
        end
    end

    -- Said here rather than discovered on the day. An album that resets
    -- without warning reads as a collection lost, and the whole point of
    -- the timing is that everybody starts the next one together.
    if GetServerTime() < self.FRESH_START then
        out[#out + 1] = { text = "" }
        self:NoteRows(out, ("The album is your character's, so it clears with "
            .. "everything else on %s - the realm starts its first full season "
            .. "with every card face down."):format(date("%d %B", self.FRESH_START)))
    end

    return out
end

------------------------------------------------------------------------
-- Turning one over
--
-- A collection wants a moment of acquisition. Landing a species for the
-- first time printed one line of chat about a journal entry and nothing
-- else, which is a poor way to be handed the thing the album is for.
--
-- Only the first one. An edition going up is already covered - a
-- specimen has its own toast and a personal best has its own line - and
-- a card that announces itself every time it improves would be noise
-- within an hour of a new character.
------------------------------------------------------------------------

-- A specimen toast runs for five seconds and fades over another one and
-- a half. Landing a specimen of a species you have never caught fires
-- both, so the card waits its turn rather than talking over the rarer
-- of the two.
local AFTER_SPECIMEN = 7

MF:On("TFL_CATCH", function(self, c)
    if c.junk or not (self.FISH[c.itemID] or self:IsTrophyCard(c.itemID, c.name)) then return end
    -- No guard against /tfl test here, and it was tried: Profile refuses
    -- a simulated catch before it ever reaches the journal, so there is
    -- never an entry standing at one for us to read. The test that
    -- proves a simulated catch hands out no card passes with the extra
    -- check taken out, which is the whole argument for not having it.
    local j = self.cdb.profile.journal[c.itemID]
    -- Profile keeps the journal and listens before we do, so by now a
    -- species landed for the first time stands at exactly one.
    if not j or (j.c or 0) ~= 1 then return end

    local card = self:CardFor(c.itemID)
    local held, total = self:CardsHeld()
    local r, g, b = RGB(card and card.colour)
    local function Show()
        if GetServerTime()>=self.FRESH_START and (c.at or 0)<self.FRESH_START then return end
        self:Toast(self:FishIcon(c.itemID), "NEW CARD", c.name,
            ("Album  -  %d of %d"):format(held, total), r, g, b,
            SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST, { card = c.itemID })
    end
    if c.specimen then C_Timer.After(AFTER_SPECIMEN, Show) else Show() end
end)

-- Ranking one up
--
-- A card goes up when a better fish crosses a grade, which is at most
-- five times in a species' life and usually two or three - so this is a
-- line of chat rather than a toast, and there is no danger of it being
-- constant. An earlier version of me argued it would be noise; that was
-- wrong, because the grades are percentile thresholds and not every
-- personal best moves one.
--
-- Nothing guards against /tfl test here. Profile refuses a simulated
-- catch, so the journal never moves, so the before and after editions
-- are the same and there is nothing to announce.
MF:On("TFL_CATCH", function(self, c)
    if c.junk or not (self.FISH[c.itemID] or self:IsTrophyCard(c.itemID, c.name)) then return end
    -- No previous entry is a brand new card, which has already said so.
    if not c.wasBest then return end

    local j = self.cdb.profile.journal[c.itemID]
    if not j then return end

    local was = self:Edition(c.itemID, c.wasBest, c.wasSpecimen)
    local now, colour = self:Edition(c.itemID, j.b, (j.s or 0) > 0)
    if was == now then return end

    self:Print(("Card upgraded: |cffffd100%s|r is now %s%s|r.%s"):format(
        c.name, colour, now,
        now == "specimen" and " It catches the light." or ""))
end)
