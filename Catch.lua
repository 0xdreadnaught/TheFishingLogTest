-- Catch: spots fishing loot, weighs it, and announces it to the rest of the
-- addon as one TFL_CATCH event per individual fish carrying a catch table:
--
--   itemID, name, link, quality   what was caught
--   weight, specimen, junk        the roll (weight is 0 for junk)
--   frenzy                        rolled during a feeding frenzy
--   spot                          MF:CurrentSpot() at the time of the catch
--   zone                          English zone name (fish data, bounties)
--   test                          simulated with /tfl test or /tfl spec
--   at                            server time of the catch
--
-- Listeners, in load order: Profile (journal, XP, records, bounty),
-- Session (solo log), Match (live match).
local _, MF = ...
local function print(...) MF:PrintChat(...) end

local FISHING_SPELL = 7620
local LOOT_WINDOW = 5      -- seconds after the Fishing channel ends that loot counts
local DEDUPE_SECONDS = 3   -- the same catch can be seen by more than one path
local MAX_CHANNEL = 35     -- seconds; longer than any Fishing channel

local LOOT_GRACE = 1       -- seconds for the rest of one bobber's loot to arrive

local fishingName          -- localized "Fishing"
local selfLootPrefix       -- localized "You receive loot: "
local createdPrefix        -- localized "You create: "
local pushedPrefix         -- localized "You receive item: " (purchases, rewards)
local interactions = {}
local castStartedWithMail = false
local castStartedWithQuest = false
local castStartedWithVendor = false -- only a vendor open: anglers sell as they fish
local castOpenKey                   -- the window open when this cast began, if any
local sourceBlockedCast = false
local pendingLootSource = false -- READY can precede a reliable fishing-source flag
local nonFishingWindow = false -- container loot must not invalidate a live bobber
local sourceQuietUntil = -math.huge
local lootTaken = false    -- this cast's loot has been counted already
local closing = false
local channeling = false
local channelStartedAt = -math.huge
local channelEndedAt = -math.huge
local recorded = {}        -- itemID -> { at, quantity } already weighed this cast
local castSerial = 0
local castAt = 0 -- server epoch; a beta bobber is not a live-realm cast
local lootContext
local multipleLootPattern
-- Kept in saved data, so the question "why didn't that count?" can still be
-- answered after the /reload most people do before asking it.
-- Looked up each time rather than held: the launch reset replaces saved data.
local loose = {}
local function Trace()
    local db = MF.db
    if not db then return loose end
    if type(db.catchTrace) ~= "table" then db.catchTrace = {} end
    return db.catchTrace
end
function MF:TraceCatch(message)
    local trace = Trace()
    trace[#trace + 1] = ("%s %s"):format(date("%H:%M:%S"), message)
    while #trace > 60 do table.remove(trace, 1) end
    self:Debug(message)
end

-- A fish arrived in the bags and was not counted as a catch. Said out loud:
-- a trophy that silently doesn't count is the worst thing this file can do,
-- and saying so with the reason is what turns it into a report we can fix.
local missedAt = {}
function MF:CatchMissed(itemID, link, reason)
    if not (self.FISH[itemID] or self.TROPHY[itemID]) then return end
    self:TraceCatch(("MISSED item=%d: %s"):format(itemID, reason))
    if GetTime() - (missedAt[itemID] or -math.huge) < 30 then return end
    missedAt[itemID] = GetTime()
    self:Print(("|cffff8000%s wasn't counted as a catch|r (%s). If it came off your bobber, "
        .. "type |cffffd100/tfl catchtrace|r and send what it shows to the Discord."):format(
        link or self:FishName(itemID), reason))
end
MF:Command("catchtrace", "Other", "/tfl catchtrace - copy recent catch diagnostics", function(self)
    local spot = self:CurrentSpot()
    local heading = ("TFL %s | %s | map %s | %s | "):format(self.Version(), spot.name,
        tostring(spot.mapID), spot.key)
    self:ShowDiagnosticText(heading .. table.concat(Trace(), " | "))
end)

MF:On("TFL_INIT", function()
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(FISHING_SPELL)
    fishingName = info and info.name or "Fishing"
    selfLootPrefix = (LOOT_ITEM_SELF or "You receive loot: %s."):match("^(.-)%%s") or ""
    createdPrefix = (LOOT_ITEM_CREATED_SELF or "You create: %s."):match("^(.-)%%s") or ""
    pushedPrefix = (LOOT_ITEM_PUSHED_SELF or "You receive item: %s."):match("^(.-)%%s") or ""
    multipleLootPattern = "^" .. (LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.")
        :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        :gsub("%%%%s", ".-"):gsub("%%%%d", "(%%d+)") .. "$"
end)

local function InvalidateSource()
    sourceBlockedCast = true
    lootTaken, channelEndedAt = true, -math.huge
    MF:Fire("TFL_FISHING_INVALIDATED",castSerial)
end

-- These receipts can use ordinary loot wording and our own GUID. Closing
-- the interaction does not make the interrupted bobber valid again.
for _, events in ipairs({
    { "TRADE_SHOW", "TRADE_CLOSED", "trade" },
    { "MERCHANT_SHOW", "MERCHANT_CLOSED", "vendor" },
    { "MAIL_SHOW", "MAIL_CLOSED", "mail" },
    { "QUEST_DETAIL", "QUEST_FINISHED", "quest" },
    { "QUEST_PROGRESS", "QUEST_FINISHED", "quest" },
    { "QUEST_COMPLETE", "QUEST_FINISHED", "quest" },
    { "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "bank" },
    { "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "guildbank" },
    { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "auction" },
}) do
    local key = events[3]
    MF:On(events[1], function(self)
        interactions[key] = true
        self:TraceCatch("interaction opened: " .. key)
        InvalidateSource()
    end)
    MF:On(events[2], function(self)
        if interactions[key] then
            interactions[key] = nil
            sourceQuietUntil = GetTime() + LOOT_WINDOW
            self:TraceCatch("interaction closed: " .. key)
        end
    end)
end

------------------------------------------------------------------------
-- Detection
--
-- A catch can reach us three ways, because other fishing addons often use
-- "fast loot", which empties and closes the loot window before LOOT_OPENED:
--   1. LOOT_READY  - the loot window's contents, as early as we can read them
--   2. LOOT_OPENED - the same, for clients or setups where READY was empty
--   3. CHAT_MSG_LOOT - the "You receive loot" line, which fast loot can't
--      skip, counted only just after a Fishing cast ends
-- Each item's quantity is reconciled across paths; each fish is weighed once.
------------------------------------------------------------------------

local function IsFishingSpell(spellID)
    -- The known cast remains fishing even while spell data is unavailable.
    -- Name lookup alone turned a cache miss into a non-fishing source block.
    if spellID == FISHING_SPELL then return true end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    return ok and info and info.name == fishingName
end

-- Cast/channel starts identify a deliberate non-fishing action. Do not
-- reject every SUCCEEDED event: passive fishing perks can also trigger spells.
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START" }) do
    MF:OnUnit(event, "player", function(self, unit, _, spellID)
        if unit == "player" and not IsFishingSpell(spellID) then
            self:TraceCatch("catch source blocked by " .. event .. " spell=" .. tostring(spellID))
            InvalidateSource()
            sourceQuietUntil = GetTime() + LOOT_WINDOW
        end
    end)
end
MF:On("QUEST_LOOT_RECEIVED", function()
    InvalidateSource()
    sourceQuietUntil = GetTime() + LOOT_WINDOW
end)

-- True while the line is actually out.
function MF:IsCasting()
    return channeling and GetTime() - channelStartedAt < MAX_CHANNEL
end

-- A cast puts one bobber on the water and the bobber holds what it holds.
-- Once that has been counted the window shuts, so a crate you open or a
-- bar you smelt in the seconds afterwards is your own doing and not the
-- river's. Without this, anything looted within five seconds of reeling
-- in was being weighed and paid XP for - which is as good a way to cheese
-- a leaderboard as standing at a forge.
local function RecentlyFishing()
    if lootTaken then return false end
    local now = GetTime()
    -- The channel caps out around 30s; don't trust a start whose stop we missed.
    if channeling and now - channelStartedAt < MAX_CHANNEL then return true end
    return now - channelEndedAt < LOOT_WINDOW
end

local function ItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Each path reports a total quantity, not an increment. If fast loot reports
-- one fish before the window reveals two, weigh only the missing second fish.
local function RecordOnce(self, itemID, name, quality, link, quantity)
    local now = GetTime()
    quantity = tonumber(quantity) or 1
    if quantity ~= math.floor(quantity) or quantity < 1 or quantity > 200 then return end
    local prior = recorded[itemID]
    local counted = prior and (castSerial > 0 or now - prior.at < DEDUPE_SECONDS) and prior.quantity or 0
    if quantity <= counted then return end
    recorded[itemID] = { at = now, quantity = quantity }
    self:TraceCatch(("accepted item=%d quantity=%d cast=%d"):format(itemID, quantity, castSerial))
    lootContext = lootContext or self:CatchContext()
    lootContext.castSerial=castSerial
    self:Fire("TFL_FISHING_LOOT",castSerial,castAt)
    -- A bobber can hold more than one thing, and the parts of it arrive
    -- separately, so the window shuts a moment after the first rather than
    -- on it.
    if not closing then
        closing = true
        local serial = castSerial
        C_Timer.After(LOOT_GRACE, function()
            if castSerial == serial then lootTaken, closing = true, false end
        end)
    end
    for i = counted + 1, quantity do
        self:RecordCatch(itemID, name, quality, link, { context = lootContext })
    end
end

MF:OnUnit("UNIT_SPELLCAST_CHANNEL_START", "player", function(self, unit, guid, spellID)
    if unit ~= "player" or not IsFishingSpell(spellID) then return end
    channeling, channelStartedAt = true, GetTime()
    castSerial = castSerial + 1
    castAt=GetServerTime()
    recorded, lootContext, closing = {}, nil, false
    pendingLootSource = false
    nonFishingWindow = false
    sourceBlockedCast = next(interactions) ~= nil
    castStartedWithMail = interactions.mail and true or false
    castStartedWithQuest = interactions.quest and true or false
    castStartedWithVendor = interactions.vendor and true or false
    castOpenKey = next(interactions)
    if castStartedWithVendor then
        for key in pairs(interactions) do if key~="vendor" then castStartedWithVendor=false break end end
    end
    if castStartedWithMail then
        for key in pairs(interactions) do if key~="mail" then castStartedWithMail=false break end end
    end
    if castStartedWithQuest then
        for key in pairs(interactions) do if key~="quest" then castStartedWithQuest=false break end end
    end
    lootTaken = false -- a fresh cast, a fresh bobber
    self:TraceCatch("fishing cast accepted serial=" .. castSerial)
    self:Fire("TFL_FISHING_CAST",castSerial,castAt,guid)
end)

MF:OnUnit("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(self, unit, _, spellID)
    if unit ~= "player" or not IsFishingSpell(spellID) then return end
    channeling = false
    channelEndedAt = GetTime()
    self:Fire("TFL_FISHING_DONE",castSerial,castAt)
end)

local function ReadLootWindow(self, opened)
    if GetServerTime()>=self.FRESH_START and castAt<self.FRESH_START then
        self:TraceCatch("loot scan rejected: launch-era fishing cast required") return
    end
    local verified = IsFishingLoot and IsFishingLoot()
    -- A missed interaction close can suppress every subsequent cast. Recover
    -- only an uninterrupted NEW bobber, with a hidden native window and an
    -- explicitly fishing loot window. Mail chat alone never clears a block.
    local staleKey=interactions.mail and castStartedWithMail and "mail"
        or interactions.quest and castStartedWithQuest and "quest"
    if staleKey and RecentlyFishing() and verified then
        local frame=_G[staleKey=="mail" and "MailFrame" or "QuestFrame"]
        local ok,shown=false,nil
        if frame and type(frame.IsShown)=="function" then ok,shown=pcall(frame.IsShown,frame) end
        local onlySource=true
        for key in pairs(interactions) do if key~=staleKey then onlySource=false break end end
        if ok and shown==false and onlySource then
            interactions[staleKey]=nil
            sourceBlockedCast=false
            castStartedWithMail=false
            castStartedWithQuest=false
            sourceQuietUntil=GetTime()+LOOT_WINDOW
            self:TraceCatch("stale " .. staleKey .. " state cleared: hidden window and verified fresh fishing loot")
        end
    end
    -- A vendor left open while you fish, selling as you go. A purchase never
    -- opens a loot window, so a verified fishing window from a bobber that
    -- nothing else has touched since it was cast is the bobber's. (RecentlyFishing
    -- is already false if a spell, reward or new window cut in during the cast.)
    local vendorOnly = verified and RecentlyFishing() and (castStartedWithVendor or not castOpenKey)
    if vendorOnly then
        for key in pairs(interactions) do if key ~= "vendor" then vendorOnly = false break end end
    end
    if vendorOnly and (next(interactions) or sourceBlockedCast) then
        self:TraceCatch("vendor open: verified fishing window accepted")
    elseif next(interactions) or sourceBlockedCast then
        self:TraceCatch("loot scan rejected: " .. (next(interactions) or "cast source blocked"))
        return
    end
    if IsFishingLoot and not verified then
        -- READY can expose items before the client identifies their source.
        -- Hold chat fallback until OPENED resolves it; do not poison this cast
        -- merely because the early scan's flag is false.
        if RecentlyFishing() and not opened and GetNumLootItems() > 0 then
            pendingLootSource = true
            self:TraceCatch("loot source pending: READY reports non-fishing loot")
        elseif RecentlyFishing() and opened then
            self:TraceCatch("loot scan rejected: OPENED reports non-fishing loot slots=" .. tostring(GetNumLootItems()))
            nonFishingWindow = true
            sourceQuietUntil = GetTime() + LOOT_WINDOW
        end
        return
    end
    if verified then
        if nonFishingWindow then
            -- A clam can be opened while a bobber is already in the water.
            -- Only a verified fishing window tied to that still-eligible cast
            -- can recover it; chat and unrelated source blocks cannot.
            if not RecentlyFishing() then
                self:TraceCatch("loot scan rejected: no eligible cast after container")
                return
            end
            self:TraceCatch("verified fishing window recovered cast after container")
            nonFishingWindow = false
        end
        if pendingLootSource then self:TraceCatch("loot source resolved: verified fishing window") end
        pendingLootSource = false
    end
    if GetTime() < sourceQuietUntil and not verified then return end
    local fishing = verified or (not IsFishingLoot and RecentlyFishing())
    if not fishing then return end
    local items = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = ItemIDFromLink(link)
        if itemID then
            local _, name, quantity, _, quality = GetLootSlotInfo(slot)
            local item = items[itemID] or { name = name, quality = quality, link = link, quantity = 0 }
            item.quantity = item.quantity + (tonumber(quantity) or 1)
            items[itemID] = item
        end
    end
    for itemID, item in pairs(items) do
        RecordOnce(self, itemID, item.name, item.quality, item.link, item.quantity)
    end
    -- READY may expose only part of the bobber. Always reconcile OPENED too;
    -- RecordOnce suppresses quantities already seen, including shrinking slots
    -- as fast loot removes items between the two events.
end

MF:On("LOOT_READY", function(self) ReadLootWindow(self, false) end)
MF:On("LOOT_OPENED", function(self) ReadLootWindow(self, true) end)

-- Item quality from the client, or from the link's colour if it isn't cached.
local function QualityFromLink(itemID, link)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    if q then return q end
    q = tonumber(link:match("|cnIQ(%d):"))  -- modern link colour format
    if q then return q end
    return link:find("|cff9d9d9d", 1, true) and 0 or 1
end

-- Why a fishing-time loot receipt is being turned away, in the player's
-- words, or nil when nothing stands in its way.
local function Blocked()
    local open = next(interactions)
    if open then return ("a %s window was open"):format(open), "interaction " .. open end
    if sourceBlockedCast and castOpenKey and RecentlyFishing() then
        return ("the cast began with a %s window open"):format(castOpenKey), "cast began in " .. castOpenKey
    end
    if sourceBlockedCast then return "another spell or action interrupted that cast", "cast source blocked" end
    if nonFishingWindow then return "another loot window opened during that cast", "non-fishing loot window" end
    if GetTime() < sourceQuietUntil then return "it came straight after something other than fishing", "recent non-fishing interaction" end
end

MF:On("CHAT_MSG_LOOT", function(self, text, ...)
    if type(text) ~= "string" or MF:IsSecret(text) then return end
    -- Receiving our own item is not proof it came from the bobber. Vendor
    -- purchases and rewards can carry our GUID too, even during a cast.
    if pushedPrefix ~= "" and text:sub(1, #pushedPrefix) == pushedPrefix then return end
    -- "You create:" is a crafting line, not a catch, and it arrives on this
    -- same event carrying your own GUID - so it has to be ruled out before
    -- the GUID is consulted rather than after.
    if createdPrefix ~= "" and text:sub(1, #createdPrefix) == createdPrefix then return end
    -- Only our own loot: by GUID where the client gives one, else by wording.
    local guid = select(11, ...)
    if type(guid) == "string" and guid ~= "" then
        if guid ~= UnitGUID("player") then return end
    end
    -- GUID alone must not admit alternate receipt wording (mail, crafting,
    -- quest rewards). Genuine catches also need the self-loot wording.
    if selfLootPrefix == "" or text:sub(1, #selfLootPrefix) ~= selfLootPrefix then
        return
    end

    local link = text:match("(|c[^|]+|Hitem:.-|h.-|h|r)") or text:match("(|Hitem:.-|h.-|h)")
    local itemID = ItemIDFromLink(link)
    if not itemID then return end
    -- Already counted from the loot window this cast: this line is the
    -- same fish arriving by a second road, not a fish being turned away.
    local counted = recorded[itemID] ~= nil
    if not RecentlyFishing() then
        self:TraceCatch("loot receipt ignored: no eligible fishing cast item=" .. itemID)
        if not counted then self:CatchMissed(itemID, link, "no fishing cast just before it") end
        return
    end
    local why, traced = Blocked()
    if why then
        self:TraceCatch("loot receipt ignored: " .. traced .. " item=" .. itemID)
        if not counted then self:CatchMissed(itemID, link, why) end
        return
    end
    local quantity = tonumber(text:match(multipleLootPattern)) or 1
    local serial = castSerial
    -- Let source/interaction events in this frame rule out a container or
    -- reward before chat can publish an irreversible catch/record.
    C_Timer.After(0, function()
        if serial ~= castSerial or not RecentlyFishing() then return end
        local late = Blocked()
        if late then
            if recorded[itemID] == nil then self:CatchMissed(itemID, link, late) end
            return
        end
        if pendingLootSource then
            self:TraceCatch("loot receipt held: unresolved loot source")
            return
        end
        RecordOnce(self, itemID, link:match("|h%[(.-)%]|h"), QualityFromLink(itemID, link), link, quantity)
    end)
end)

------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------

local function Announce(self, c)
    local label = c.link or c.name
    if c.junk and self.IsFishingFind and self:IsFishingFind(c.itemID) then
        self:Print(("Reeled in %s - a fishing find!"):format(label))
        return
    end
    if c.junk then
        self:Print(("Reeled in %s. That's junk, %s."):format(label, self:Weight(0)))
        return
    end
    self:Print(("Caught %s: |cffffd100%s|r%s%s%s"):format(label, MF:Weight(c.weight),
        c.specimen and " |cffff8000SPECIMEN!|r" or self:GradeText(c.itemID, c.weight),
        c.frenzy and " |cffff8000(frenzy)|r" or "",
        c.best and " |cffffd100- your best yet!|r" or ""))
    if c.specimen then
        local unlocked = not c.wasSpecimen and not c.test
        self:Toast(self:FishIcon(c.itemID), unlocked and "NEW SPECIMEN!" or "SPECIMEN!", c.name,
            MF:Weight(c.weight) .. (unlocked and " - Foil card unlocked" or ""),
            -- Store UI uses kit 39516. The numeric fallback also works on
            -- Classic clients that omit the named Mainline SOUNDKIT entry.
            1, 0.82, 0, SOUNDKIT.UI_IG_STORE_CONFIRM_PURCHASE_BUTTON or 39516, { card = c.itemID })
    end
end

-- The single entry point for a catch, real or simulated.
function MF:CatchContext()
    local spot = self:CurrentSpot()
    -- In a match, the water is the match's. Where a water has no name of
    -- its own, two anglers side by side can file it under two different
    -- keys (a gridline between them, or each snapping to a spot only they
    -- had fished), and then compete on one list and set records on two.
    -- Anything the match counts as its water is filed under the match's key,
    -- which every client in it shares.
    local m = self.current
    if self.InMatch and self:InMatch() and m and m.spot and spot.key ~= m.spot
        and self:AtMatchSpot(m, spot.key) then
        spot = { key = m.spot, name = m.name or spot.name, mapID = m.mapID ~= 0 and m.mapID or spot.mapID,
            x = spot.x, y = spot.y }
    end
    local frenzy,water=self:FrenzyCatchState()
    return { spot = spot, zone = self:ZoneEnglish(), frenzy = frenzy, frenzyLocation=water,
        at = GetServerTime(), night = self:IsNight(), lift = self:SkillFloorLift() }
end

-- opts: shared context for a stack; test/forceSpecimen are testing only.
function MF:RecordCatch(itemID, name, quality, link, opts)
    opts = opts or {}
    local context = opts.context or self:CatchContext()
    if GetServerTime()>=self.FRESH_START and (context.at or 0)<self.FRESH_START then return end
    local spot = context.spot
    if not opts.test then
        self:RememberSpotName(spot.key, spot.name, true)
        self:MarkSpotPosition(spot.key, spot.mapID, spot.x, spot.y, true, context.at or GetServerTime())
    end

    local c = {
        itemID = itemID, name = name or self:FishName(itemID), link = link, quality = quality,
        spot = spot, zone = context.zone, frenzy = context.frenzy,
        test = opts.test and true or false, at = context.at, frenzyLocation=context.frenzyLocation,
        castSerial=context.castSerial,
    }
    c.weight, c.specimen, c.junk = self:RollWeight(itemID, c.name, quality, c.zone, c.frenzy,
        opts.forceSpecimen, context)

    -- Worked out here because the journal is updated by a TFL_CATCH listener
    -- and this runs first, so the entry still holds the best from before.
    -- Only when there was one to beat: the first of a species is already
    -- announced as a new journal entry, and saying both is saying it twice.
    local known = self.cdb.profile.journal[itemID]
    c.best = (not c.junk and known and c.weight > (known.b or 0)) or nil
    -- What the card looked like before this fish, for the same reason:
    -- an edition only goes up when a better one crosses a grade, and
    -- nothing downstream can work that out once the journal has moved.
    c.wasBest = known and known.b or nil
    c.wasSpecimen = known and (known.s or 0) > 0 or nil

    Announce(self, c)
    self:Debug(("itemID=%d quality=%s zone=%s spot=%s test=%s"):format(
        itemID, tostring(quality), c.zone, spot.key, tostring(c.test)))
    self:Fire("TFL_CATCH", c)
end

------------------------------------------------------------------------
-- Personal bests per spot
------------------------------------------------------------------------

function MF:CheckPersonalBest(c)
    local records = self.cdb.records
    local spot = records[c.spot.key] or {}
    records[c.spot.key] = spot
    local prev = spot[c.itemID]
    if not prev or c.weight > prev.weight then
        spot[c.itemID] = { weight = c.weight, name = c.name, when = c.at or GetServerTime(), specimen = c.specimen or false }
        if prev then
            self:Print(("New personal best %s at %s! (was %s)"):format(c.name, c.spot.name, MF:Weight(prev.weight)))
        end
    end
end

MF:Command("pb", "Progress", "/tfl pb - personal bests here", function(self)
    local spot = self:CurrentSpot()
    local bests = self.cdb.records[spot.key]
    if not bests or not next(bests) then
        self:Print("No personal bests at " .. spot.name .. " yet.")
        return
    end
    self:Print("Personal bests at " .. spot.name .. ":")
    for _, rec in pairs(bests) do
        print(("  %s - %s"):format(rec.name or "?", MF:Weight(rec.weight)))
    end
end)

------------------------------------------------------------------------
-- Test commands (debug only)
------------------------------------------------------------------------

local function Simulate(self, args, forceSpecimen)
    if not self.db.debug then
        self:Print("Turn on /tfl debug first.")
        return
    end
    local itemID = tonumber(args[1]) or 6358
    local name, link, quality = C_Item.GetItemInfo(itemID)
    self:RecordCatch(itemID, name or self:FishName(itemID), quality or 1, link,
        { test = true, forceSpecimen = forceSpecimen })
end

MF:Command("test", "Other", nil, function(self, args) Simulate(self, args, false) end)
MF:Command("spec", "Other", nil, function(self, args) Simulate(self, args, true) end)

function MF:ResetCatchState()
    castSerial=castSerial+1
    castAt=0
    recorded,lootContext={},nil
    local trace = Trace() for i = #trace, 1, -1 do trace[i] = nil end
    channeling,closing,lootTaken=false,false,true
    channelStartedAt,channelEndedAt=-math.huge,-math.huge
    pendingLootSource,nonFishingWindow=false,false
end
