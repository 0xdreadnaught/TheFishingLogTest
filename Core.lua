-- Core: the shared namespace and infrastructure every other file builds on.
--
--   * helpers (printing, names, weights, time formatting)
--   * saved data setup
--   * an event bus:       MF:On(event, fn) / MF:OnUnit(...) / MF:Fire(...)
--   * a once-a-second tick: MF:OnTick(fn)
--   * a command registry: MF:Command(names, section, help, fn)
--
-- Modules register their own events and commands, so adding a feature never
-- means editing this file. Addon-internal events are prefixed "TFL_":
--   TFL_INIT          saved data is ready; build frames
--   TFL_LOGIN         first PLAYER_ENTERING_WORLD of the session
--   TFL_SYNC          a few seconds after login; ask other players for data
--   TFL_FISHING_CAST  the player started channelling Fishing
--   TFL_FISHING_DONE  the channel ended (the line is back in)
--   TFL_CATCH         a catch was recorded (see Catch.lua for its fields)
--   TFL_MATCH_ANNOUNCED  a match was hosted, by us or someone else (m)
--   TFL_MATCH_FINISHED   a match we were in ended (m, standings)
--   TFL_NOTICE_NEW    an event we hadn't heard of was posted (notice)
local ADDON, MF = ...
MF.ADDON = ADDON

-- Two copies of The Fishing Log must never run together: they would share
-- one realm's addon traffic twice over and fight for the same frames. A
-- copy in any other folder stays dormant while the original is enabled -
-- no events, no messages, no slash command - and says so once at login.
-- Whether the game has loaded, or will load, another addon for this character.
local function WillLoad(addon)
    local api = C_AddOns or {}
    local loaded = api.IsAddOnLoaded or IsAddOnLoaded
    if loaded then
        local ok, yes = pcall(loaded, addon)
        if ok and yes then return true end
    end
    -- Not loaded yet: ask whether the game will load it for this character.
    -- (Its "enable state" is no good here - it counts an addon as on when
    -- it is ticked for any character on the account.)
    local info = api.GetAddOnInfo or GetAddOnInfo
    if info then
        local ok, name, _, _, loadable = pcall(info, addon)
        if ok and name and (loadable == true or loadable == 1) then return true end
    end
    return false
end

local function OriginalEnabled()
    if ADDON == "TheFishingLog" then return false end
    return WillLoad("TheFishingLog")
end
MF.inert = OriginalEnabled()

-- Godfall's UI Rework used to be a separate addon; it's built in from 1.1.0
-- (Rework\). With the old one still enabled, the built-in look stands down
-- rather than draw over it, and the player is asked to turn the old one off.
MF.oldRework = not MF.inert and WillLoad("TheFishingLog_UIRework")
if MF.inert then
    local note = CreateFrame("Frame")
    note:RegisterEvent("PLAYER_LOGIN")
    note:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(6, function()
            print("|cffffd100The Fishing Log (merged):|r switched off, because the original The Fishing Log "
                .. "is enabled too. Disable one of them in the AddOns list and reload.")
        end)
    end)
else
    _G.TheFishingLog = MF
end

local LOGIN_SYNC_DELAY = 10 -- seconds after login before asking other players

-- The day Forever wipes and goes live: 4 November 2026, 00:00 UTC.
--
-- One date, in one place, because several things turn on it and they must
-- all turn together - the new rank ladder begins, records older than it stop
-- being accepted, and what the realm knew is archived and cleared. Read from
-- the server's clock, never the machine's, so the whole realm turns over at
-- the same moment whatever anyone's computer says.
--
-- If the launch hour turns out to be something other than midnight, this is
-- the only number to change.
MF.FRESH_START = 1793750400

local DEFAULT_SETTINGS = {
    sounds = true,        -- play sounds
    toasts = true,        -- big centre-screen pop-ups
    recordAlerts = true,  -- chat alerts when records fall in your zone
    invites = true,       -- "join this match?" pop-ups
    invitesFromAnyone = true, -- take direct invites from outside guild/friends/party; opt out, not in
    channel = true,       -- use the realm-wide TheFishingLog channel
    autoBoard = true,     -- open the board when you start fishing
    minimap = true,       -- minimap button
    mapFrenzy = true,     -- frenzy marks on the world map
    poolWorldMap = true,  -- historical pool observations shared by anglers
    mapLayerButtons = true, -- the Frenzies/Pools on-off box on the world map
    poolMinimap = true,
    mapMarkerSize = 16,
    poolMinimapSize = 12,
    poolSharing = true,
    macroSave = true,     -- keep rank + journal in account macros (beta save bug)
    lureWarning = true,   -- warn when casting without a lure
    loudSplash = false,   -- turn the sound up while the line is out
    splashBackground = true,  -- ... and keep it playing with WoW in the background
    splashErrorSpeech = true, -- ... and quiet the "I can't do that" speech
    splashAmbience = false,   -- ... and switch ambience off
    muteMusicWithPole = true,
    reducedMotion = false,
    bobberHighlight = true,
    anglerNameplateHook = true,
    anglerChatHook = true,     -- the hook in front of fellow anglers' chat
    anglerChatHookSay = true,      -- and which kinds of chat it goes in
    anglerChatHookGuild = true,
    anglerChatHookGroup = true,
    anglerChatHookWhisper = true,
    anglerChatHookChannel = true,
    anglerTargetHook = true,   -- and beside their name on your target frame
    higherLower = true,        -- Higher or Lower at all; off puts the game away entirely
    flightGame = true,         -- offer Higher or Lower when a flight path takes off
    higherLowerSounds = true,  -- the game's own sounds; its mute button flips this
    -- One switch for each kind of sound, under Play sounds.
    soundSpecimens = true,
    soundRecords = true,
    soundRecordLost = true,
    soundRanks = true,
    soundCards = true,
    soundFrenzies = true,
    soundBounties = true,
    soundMatches = true,
    soundSeasons = true,
    soundGoals = true,
    -- A new setting key also enables this for profiles with the old off default.
    bobberAutoAssist = true,
    castFeedback = true,
    popupSpecimens = true,
    popupRecords = true,
    popupRanks = true,
    popupFrenzies = true,
    popupBounties = true,
    popupOther = true,
    matchSplash = true,   -- the match countdown and LINES IN! in the middle of the screen
    kilograms = false,    -- show weights in kg; pounds are still what's stored
    goalTracker = true,   -- your fishing goals under the quest tracker
    floatCatches = true,  -- each catch rises off the water, like combat text
    nearbyCatches = true, -- share and show same-faction catches at our spot
    nearbyNotableOnly = false,
    loginRecap = true,
    floatX = 0, floatY = 140,
    castClick = "BUTTON2", -- what casts: right-click by default, or any key
    castDouble = true,    -- press it twice, so a stray press doesn't cast
    autoSwapCombat = false, -- swap to combat weapon when attacked, pole back after
    tooltipItems = true,  -- Fishing Log details on fish item tooltips
    tooltipPlayers = true, -- angler rank and status on player tooltips
    noticeboard = true,   -- show the event noticeboard
    eventReminders = true, -- remind me before events I've signed up for
    showValue = true,     -- what your catch is worth (your own prices, solo only)
    journalHideMissing = false, -- hide fish you haven't caught in the journal
    realmSeason = true,   -- the Realm tab opens on the month, not all time
    minimapAngle = 220,
    boardScale = 1,
}
-- The settings window's "Reset this page" puts switches back to these.
MF.DEFAULT_SETTINGS = DEFAULT_SETTINGS

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- Only persistent, currently available chat windows belong in the selector.
function MF:ChatOutputWindows()
    local windows = { { id = 0, name = "Default chat window" } }
    if type(GetChatWindowInfo) ~= "function" then return windows end
    for id = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. id]
        local name = GetChatWindowInfo(id)
        if frame and type(name) == "string" and name ~= "" and not frame.isTemporary
            and (frame.isDocked or frame:IsShown() or select(7, GetChatWindowInfo(id))) then
            windows[#windows + 1] = { id = id, name = name, frame = frame }
        end
    end
    return windows
end

function MF:ChatOutputWindow()
    local selected = self.db and self.db.settings and self.db.settings.chatOutput
    if type(selected) == "table" then
        local match
        for _, window in ipairs(self:ChatOutputWindows()) do
            if window.id ~= 0 and window.name == selected.name then
                if window.id == selected.id then return window.frame end
                match = match or window.frame
            end
        end
        if match then return match end
    end
    return DEFAULT_CHAT_FRAME
end

local defaultPrint = print
function MF:PrintChat(...)
    local frame = self:ChatOutputWindow()
    if frame and frame ~= DEFAULT_CHAT_FRAME and type(frame.AddMessage) == "function" then
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        frame:AddMessage(table.concat(parts, " "))
    else
        defaultPrint(...)
    end
end

-- Local wrapper only: never change WoW's global print or another addon's output.
local function print(...) MF:PrintChat(...) end

function MF:Print(msg)
    print(self.C.brand .. "The Fishing Log|r: " .. tostring(msg))
end

function MF:Debug(msg)
    if self.db and self.db.debug then
        print("|cff858585TFL debug|r: " .. tostring(msg))
    end
end

-- Our realm. Forever's 1.60.1 hotfix makes every realm API answer "", so
-- the name is kept per character while the game still gives it, and the
-- kept one answers after. Everything saved before then carries the realm
-- ("Reed Angler-Realm"); without it our own names would stop matching.
-- "" when we have never been told.
local realmName
function MF:RealmName()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(r) == "string" and r ~= "" and not self:IsSecret(r) then
        realmName = r
        if self.cdb then self.cdb.realm = r end
        return r
    end
    return realmName or (self.cdb and type(self.cdb.realm) == "string" and self.cdb.realm) or ""
end

-- "Name-Realm", filling in our own realm when none is given. Just the name
-- when we don't know the realm, never "Name-".
function MF:FullName(name, realm)
    if not name then return end
    if name:find("-", 1, true) then return name end
    if not realm or realm == "" then realm = self:RealmName() end
    return realm ~= "" and (name .. "-" .. realm) or name
end

function MF:PlayerName()
    return self:FullName(UnitFullName("player"))
end

-- Forever's UnitName can omit the surname. Use the full player identity.
function MF:TargetPlayerName()
    if not UnitIsPlayer("target") then return end
    local name,realm=UnitFullName("target")
    if type(name)~="string" or name=="" then return end
    return self:FullName(name,realm)
end

-- Names reach us in three shapes. Our own client gives "First Last-Realm";
-- another angler's addon message gives "First-Last", the space having come
-- back as a hyphen and the realm dropped; from further off, "First-Last-Realm".
-- A character name holds one space and never a hyphen, which is enough to tell
-- the pieces apart: three pieces means the last is a realm, and so does two
-- when the first piece already has its space.
-- Returns the name as a person would write it, and the realm if there was one.
function MF:SplitName(name)
    local parts = { strsplit("-", name or "") }
    local ours = self:RealmName()
    local realm
    if #parts > 2 or (#parts == 2 and (parts[2] == ours or parts[1]:find(" ", 1, true))) then
        realm = table.remove(parts)
    end
    return table.concat(parts, " "), realm
end

function MF:ShortName(full)
    local plain = self:SplitName(full)
    return plain ~= "" and plain or "?"
end

-- One angler, one identity. Names reach us in more than one shape: a name
-- with a space comes back from other clients hyphenated and without its
-- realm ("Boom Flex-Realm" vs "Boom-Flex"), which would otherwise count the
-- same player twice. Compare on letters alone, realm removed: any realm
-- the name's shape gives away (see SplitName), and ours as well, so this
-- doesn't hang on the realm API, which Forever's hotfix empties. Forever
-- names are unique across its hidden realms (whispers find the plain name
-- wherever they are), so one name is one angler whatever realm it came with.
local keyCache, keyRealm = {}, nil
function MF:AnglerKey(name)
    if not name then return "" end
    local ours = self:RealmName()
    if ours ~= keyRealm then keyCache, keyRealm = {}, ours end
    local cached = keyCache[name]
    if cached then return cached end
    local key = self:SplitName(name):gsub("[%s%-]", ""):lower()
    local realm = ours:gsub("[%s%-]", ""):lower()
    if realm ~= "" and #key > #realm and key:sub(-#realm) == realm then
        key = key:sub(1, #key - #realm)
    end
    keyCache[name] = key
    return key
end

function MF:SameAngler(a, b)
    return a ~= nil and b ~= nil and self:AnglerKey(a) == self:AnglerKey(b)
end

-- Someone you'd expect to hear from unprompted: your guild, your friend list,
-- or whoever you're grouped with. Used to decide whose match invites are
-- welcome; a stranger across the realm shouldn't be able to pop a box on you.
function MF:IsKnownPlayer(name)
    if not name or self:AnglerKey(name) == "" then return false end

    -- UnitFullName, not UnitName: on Forever the surname comes back in the
    -- realm slot ("Grey", "Maebyrn"), and the first name alone never matched
    -- the "Grey-Maebyrn" their addon messages arrive under.
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, (GetNumGroupMembers() or 0) do
        local ok, n, r = pcall(UnitFullName, prefix .. i)
        if ok and type(n) == "string" and n ~= "" and not self:IsSecret(n) then
            if self:IsSecret(r) or type(r) ~= "string" then r = nil end
            if self:SameAngler(self:FullName(n, r), name) then return true end
        end
    end

    local friends = C_FriendList and C_FriendList.GetNumFriends
    for i = 1, (friends and C_FriendList.GetNumFriends() or 0) do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and self:SameAngler(info.name, name) then return true end
    end

    return self:IsGuildmate(name)
end

-- The guild, by angler key. Scanned at most every half minute: a roster can
-- run to hundreds of names and the standings ask about every row.
local guildKeys, guildAt = nil, -math.huge
local GUILD_CACHE = 30

function MF:GuildKeys()
    if guildKeys and GetTime() - guildAt < GUILD_CACHE then return guildKeys end
    guildKeys, guildAt = {}, GetTime()
    if IsInGuild() and GetGuildRosterInfo then
        local n = GetNumGuildMembers() or 0
        -- A roster the client hasn't asked for yet is empty, and nothing
        -- fills it on its own. Asking is free and the answer arrives in a
        -- moment, by which time the cache has expired and we look again.
        if n == 0 then
            local ask = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
            if ask then pcall(ask) end
        end
        for i = 1, n do
            local name = GetGuildRosterInfo(i)
            if name then guildKeys[self:AnglerKey(name)] = true end
        end
    end
    return guildKeys
end

function MF:IsGuildmate(name)
    if not name or not IsInGuild() then return false end
    return self:GuildKeys()[self:AnglerKey(name)] == true
end

-- Faction travels with a record, because nothing else can tell us: there's
-- no way to look up a name's faction, and the only players we can inspect
-- are the ones stood in front of us. Whether it ever arrives from the other
-- side is the open question - chat channels are faction-locked in Classic,
-- so this may only ever confirm what we already assume.
function MF:MyFaction()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

function MF:NoteFaction(name, letter)
    if not name or (letter ~= "A" and letter ~= "H") then return end
    local key = self:AnglerKey(name)
    if key ~= "" then self.db.factions[key] = letter end
end

function MF:FactionOf(name)
    if self:IsMe(name) then return self:MyFaction() end
    return name and self.db.factions[self:AnglerKey(name)] or nil
end

-- The shape of a name you can actually whisper. Addon messages hand us a
-- name with a space hyphenated and its realm attached; whispering that gets
-- "No player with the name Foxi-Gamma-Realm is playing" in everyone's chat
-- window. Names can't contain a hyphen of their own, so the realm comes off
-- and the rest go back to being spaces.
function MF:WhisperName(name)
    if not name then return nil end
    local plain, realm = self:SplitName(name)
    local ours = self:RealmName()
    if not plain:find(" ", 1, true) then
        if realm and realm ~= ours then return plain .. "-" .. realm end
        return plain
    end
    -- A two-word (Forever) name. Which form the server delivers has changed
    -- under us once already. It used to want "Grey Maebyrn-<realm>" and drop
    -- the plain name. In November 2026 the players of one guild turned out
    -- to sit on different realms behind the scenes (Realm3, Realm7), so
    -- adding our own realm addressed a name that doesn't exist there, and the
    -- server answered "No player named"; the plain name is found wherever
    -- they are. So plain is the default, and Comm.lua retries a refused
    -- whisper in the other form and keeps whichever one gets an answer
    -- (db.whisperRealm).
    if self.db and self.db.whisperRealm == true then
        local r = realm or ours
        if r ~= "" then return plain .. "-" .. r end
    end
    return plain
end

function MF:IsMe(name)
    return self:SameAngler(name, self.me)
end

-- Translated zone and subzone text, for display only (see Spots.lua for IDs).
function MF:Location()
    local zone = GetRealZoneText() or ""
    local sub = GetSubZoneText() or ""
    if sub == "" then sub = zone end
    return zone, sub
end

-- Deterministic string hash, so every client derives the same schedules.
-- Every client computes frenzy schedules and the daily bounty from this and
-- never sends a word about either, so it has to give the same answer
-- everywhere and spread its answers evenly.
--
-- One pass of djb2 did neither. Change the last character of a key and the
-- hash changes by exactly that much, because nothing mixes it back up the
-- number - so "a5150" and "a5151" came out one second apart in a two hour
-- cycle. Area IDs are handed out in runs, which meant every lake in a zone
-- frenzied together and the one over the hill was no use to you at all.
--
-- The second pass runs the bytes backwards, so the character that only
-- reached the bottom of the number now starts at the top. Multiplier kept
-- small on purpose: 2147483646 * 65599 is about 1.4e14, comfortably inside
-- the 2^53 a double holds exactly, so every client gets the same number
-- rather than the same rounding error.
function MF:Hash(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 2147483647
    end
    for i = #str, 1, -1 do
        h = (h * 65599 + str:byte(i)) % 2147483647
    end
    return h
end

function MF.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Weights are kept to 2 decimals and travel as integer hundredths of a pound.
function MF.Hundredths(w) return math.floor((w or 0) * 100 + 0.5) end
function MF.RoundWeight(w) return MF.Hundredths(w) / 100 end
function MF:EncodeWeight(w) return tostring(MF.Hundredths(w)) end
function MF:DecodeWeight(s) return (tonumber(s) or 0) / 100 end

-- Pounds, said in the reader's own words
--
-- Pounds are what the addon stores, sends, compares and grades against. A
-- record set by somebody reading kilograms has to be the same record on
-- everyone else's screen, and a weight that changed unit on its way into
-- the save file would be a different fish every time the switch was
-- flicked. So this is a change of language at the last possible moment:
-- nothing underneath the display ever sees a kilogram.
local KG_PER_LB = 0.45359237

function MF:Metric()
    return self.db ~= nil and self.db.settings.kilograms == true
end

function MF:WeightUnit()
    return self:Metric() and "kg" or "lb"
end

function MF:WeightNumber(w)
    w = tonumber(w) or 0
    return self:Metric() and w * KG_PER_LB or w
end

-- "2.45 lb", or "1.11 kg". `places` for the few lines that want it rounder.
function MF:Weight(w, places)
    return ("%." .. (places or 2) .. "f %s"):format(self:WeightNumber(w), self:WeightUnit())
end

-- "2-10 lb": one unit for the pair, because it is one range.
function MF:WeightRange(lo, hi, places)
    places = places or 0
    return ("%." .. places .. "f-%." .. places .. "f %s"):format(
        self:WeightNumber(lo), self:WeightNumber(hi), self:WeightUnit())
end

-- Numbers on the wire, short
--
-- Messages are 255 bytes and a record book is hundreds of them, so a number
-- written as decimal digits is most of what we spend. Base 36 is digits and
-- letters, which is everything the separators (, ; | ~) don't claim - a
-- timestamp goes from ten characters to six, an item id from four to three.
--
-- Hex was suggested first and would work; 36 is the same idea carried as
-- far as it goes without needing to escape anything.
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

function MF:Pack36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = ""
    while n > 0 do
        local d = n % 36
        out = B36:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end

function MF:Unpack36(s)
    return tonumber(tostring(s or ""), 36) or 0
end

-- A countdown somebody can read at a glance
--
-- FormatClock counts hours, which is right for a frenzy and useless for
-- a month: "resets in 291:29:49" is a number you have to do arithmetic
-- on before it means anything.
function MF:FormatSpan(secs)
    secs = math.max(0, math.floor(tonumber(secs) or 0))
    local days = math.floor(secs / 86400)
    if days >= 1 then
        return ("%dd %dh"):format(days, math.floor((secs % 86400) / 3600))
    end
    return self:FormatClock(secs)
end

function MF:FormatClock(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

-- kind is the setting that switches this sound off on its own (see the
-- sound switches in Options); Play sounds still decides first.
function MF:Sound(kit, kind)
    local settings = self.db.settings
    if not kit or not settings.sounds then return end
    if kind and settings[kind] == false then return end
    PlaySound(kit)
end

function MF:IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

------------------------------------------------------------------------
-- Event bus
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local listeners = {}

-- Listen for a game event or an internal TFL_ event. fn(MF, ...).
function MF:On(event, fn)
    if not listeners[event] then
        listeners[event] = {}
        if not event:find("^TFL_") and not MF.inert then frame:RegisterEvent(event) end
    end
    table.insert(listeners[event], fn)
end

-- Same as On, for events that should only fire for one unit (e.g. "player").
function MF:OnUnit(event, unit, fn)
    if not listeners[event] then
        listeners[event] = {}
        if not MF.inert then frame:RegisterUnitEvent(event, unit) end
    end
    table.insert(listeners[event], fn)
end

-- One listener's error must not cost the rest of them their turn: a catch
-- has a dozen listeners and logout restores the player's own settings.
-- The error still reaches the game's handler, so it is reported, not hidden.
local function Report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end
MF.ReportError = Report

function MF:Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, self, ...)
        if not ok then Report(err) end
    end
end

frame:SetScript("OnEvent", function(_, event, ...) MF:Fire(event, ...) end)

-- Once-a-second work. Runs only after saved data is ready.
MF.tickers = {}
function MF:OnTick(fn)
    table.insert(self.tickers, fn)
end

------------------------------------------------------------------------
-- Fish names
--
-- Item names come from the client's own cache, so a fish we have never seen
-- ourselves - another angler's record in waters we don't fish - has no name
-- until we ask the server for one.
------------------------------------------------------------------------

local NAME_WAIT = 3 -- seconds before we give up and show the item ID
local waiting = {}  -- itemID -> callbacks

local requested = {}

-- Every name the game gives us is also kept in saved data, so a fish named
-- once stays named in later sessions even before the game loads it again.
local function KnownName(self, itemID)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    local saved = TheFishingLogDB and TheFishingLogDB.fishNames
    if name then
        if saved then saved[itemID] = name end
        return name
    end
    local info = self.FISH[itemID]
    return (info and info.name) or self.FISH_NAMES[itemID] or (saved and saved[itemID])
end

-- Ask the server for an item we've never seen, once per session.
local function Request(itemID)
    if requested[itemID] then return end
    requested[itemID] = true
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    -- Asking for an item's details is itself the request: it answers nil for
    -- something the client has never seen, fetches it, and tells us with
    -- GET_ITEM_INFO_RECEIVED. Belt and braces, since the call above isn't on
    -- every client.
    if C_Item.GetItemInfo then C_Item.GetItemInfo(itemID) end
end

function MF:FishName(itemID)
    itemID = tonumber(itemID)
    if not itemID then return UNKNOWN end
    local name = KnownName(self, itemID)
    if name then return name end
    Request(itemID)
    return "Item " .. itemID
end

function MF:FishIcon(itemID)
    return (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400
end

local function Deliver(self, itemID)
    local fns = waiting[itemID]
    if not fns then return end
    waiting[itemID] = nil
    local name = self:FishName(itemID)
    for _, fn in ipairs(fns) do fn(name) end
end

-- Run fn(name) once the fish has a real name. A line of chat is written once
-- and can't be rewritten later, so it waits; windows simply redraw.
function MF:WithFishName(itemID, fn)
    itemID = tonumber(itemID)
    if not itemID or KnownName(self, itemID) then return fn(self:FishName(itemID)) end
    Request(itemID)
    if not waiting[itemID] then
        waiting[itemID] = {}
        C_Timer.After(NAME_WAIT, function() Deliver(self, itemID) end)
    end
    table.insert(waiting[itemID], fn)
end

MF:On("GET_ITEM_INFO_RECEIVED", function(self, itemID) Deliver(self, tonumber(itemID)) end)

------------------------------------------------------------------------
-- Saved data and startup
------------------------------------------------------------------------

-- Early Forever betas wrote saved variables but never read them back, which
-- is why progress also lives in account macros. We leave a marker every
-- session: finding it next login proves saving works on this client.
--
-- The live realm saves properly, and the launch wipe removes the marker, so
-- after launch the marker proves nothing: a first session would otherwise
-- write account macros and broadcast backups, then ask to have them deleted.
local function DetectSaving(db)
    db.lastSeen = time()
end

local function InitDB()
    TheFishingLogDB = TheFishingLogDB or {}
    local db = TheFishingLogDB
    db.spots = db.spots or {}
    db.spotNames = db.spotNames or {}
    db.fishNames = db.fishNames or {} -- itemID -> name, as the game last gave it
    db.spotWhere = db.spotWhere or {} -- key -> { map, x, y, mine }: where to go
    db.anglersSeen = db.anglersSeen or {} -- angler key -> { name, at, version }
    db.factions = db.factions or {} -- angler key -> "A" or "H", when they tell us
    db.peers = nil -- other anglers' profile backups, from before saving worked
    db.notices = db.notices or {}
    db.hiddenHosts = db.hiddenHosts or {}
    db.champions = db.champions or {}
    db.newZones = db.newZones or {} -- catches in zones the fish data doesn't cover
    -- mapID -> { lo, hi, n }: where fishing skill has been seen to go up.
    -- Observations reset with the rest of beta data at launch.
    db.skillUps = db.skillUps or {}
    db.poolAtlas = db.poolAtlas or {} -- shared geography, preserved across seasonal resets
    -- db.lastVersion: what was running last time, so an update can say
    -- what changed in the ones you missed.
    -- No beta archive is retained by the launch reset.
    -- db.freshStart: the wipe we have already done, so it happens once.
    -- db.castClashTold: the other fishing addon we've mentioned sharing the
    -- cast button with, so it's said once rather than every login.
    -- Spot keys changed in 0.3.0 (translated text -> map:area) and again in
    -- 0.3.3 (map:area -> area only); old keys can't be converted.
    if db.spotFormat ~= 3 then
        db.spots, db.spotFormat = {}, 3
    end
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    -- Invites from anyone became the default in 1.1.2: fishing is social,
    -- so players opt out rather than in. The old default was saved into
    -- every profile, so it is switched on once here; turned off again
    -- afterwards, it stays off.
    if db.invitesOpenDefault ~= 1 then
        db.settings.invitesFromAnyone = true
        db.invitesOpenDefault = 1
    end
    DetectSaving(db)
    MF.db = db

    -- Your log is yours, not your account's: rank, journal, personal bests,
    -- sessions and gear follow the character who earned them. What the realm
    -- told us - its records, its spots, its anglers - is the same whoever
    -- you're playing, and stays above.
    -- Everything lived here, account-wide, before 0.6.4. Set it aside so the
    -- character who earned it can claim it - once, and by being asked.
    if db.profile or db.records or db.history then
        db.legacy = db.legacy or { profile = db.profile, records = db.records,
            history = db.history, caughtIn = db.caughtIn, gear = db.gear }
        db.profile, db.records, db.history, db.caughtIn, db.gear = nil, nil, nil, nil, nil
    end

    TheFishingLogChar = TheFishingLogChar or {}
    local cdb = TheFishingLogChar
    cdb.profile = cdb.profile or { xp = 0, updated = 0, journal = {} }
    cdb.records = cdb.records or {}   -- spot key -> itemID -> your best there
    cdb.history = cdb.history or {}
    cdb.caughtIn = cdb.caughtIn or {} -- itemID -> zone -> { c, b, s, spot }
    cdb.gear = cdb.gear or {}
    MF.cdb = cdb
end

-- Launch is a complete reset, including unknown future saved fields.
-- Retain only unfinished client-CVar restoration until it can complete.
function MF:InitializeLaunchData(clearRealm)
    local music,soft,sfx=self.db.musicVolumeRestore,self.db.softTargetRestore,self.db.sfxVolumeRestore
    if clearRealm then for key in pairs(self.db) do self.db[key]=nil end end
    for key in pairs(self.cdb) do self.cdb[key]=nil end
    InitDB()
    if clearRealm then
        self.db.musicVolumeRestore,self.db.softTargetRestore,self.db.sfxVolumeRestore=music,soft,sfx
    end
end

-- Discard beta tables before migrations, UI builders or recovery listeners
-- can inspect them. Completion markers are written by FreshStart at login.
function MF:DiscardExpiredBetaData()
    if GetServerTime()<self.FRESH_START then return false end
    local old=TheFishingLogDB
    local realm=type(old)~="table" or old.freshStart~=self.FRESH_START or old.launchReset~=self.FRESH_START
    local char=TheFishingLogChar
    if realm then
        TheFishingLogDB={}
        if type(old)=="table" then
            TheFishingLogDB.musicVolumeRestore=old.musicVolumeRestore
            TheFishingLogDB.softTargetRestore=old.softTargetRestore
            TheFishingLogDB.sfxVolumeRestore=old.sfxVolumeRestore
            -- Only a log that held something is worth telling the player
            -- about; a first install has nothing to have been cleared.
            MF.hadBetaData=next(old.spots or {})~=nil or old.lastVersion~=nil
        end
        TheFishingLogDiscord=nil
    end
    if realm or type(char)~="table" or char.freshStart~=self.FRESH_START or char.launchReset~=self.FRESH_START then
        TheFishingLogChar={}
    end
    return realm
end

MF:On("ADDON_LOADED", function(self, name)
    if name ~= ADDON then return end
    self:DiscardExpiredBetaData()
    InitDB()
    self:Fire("TFL_INIT")
    C_Timer.NewTicker(1, function()
        if self.loggedIn then
            local ok, err = pcall(self.FreshStart, self)
            if not ok then Report(err) end
        end
        for _, fn in ipairs(self.tickers) do
            local ok, err = pcall(fn, self)
            if not ok then Report(err) end
        end
        local ok, err = pcall(self.UpdateBoard, self)
        if not ok then Report(err) end
    end)
end)

MF:On("PLAYER_ENTERING_WORLD", function(self)
    -- The realm name isn't reliable until now, so our identity is set here.
    self.me = self:PlayerName()
    self:FreshStart()
    if self.loggedIn then return end
    self.loggedIn = true
    self:Fire("TFL_LOGIN")
    C_Timer.After(LOGIN_SYNC_DELAY, function() self:Fire("TFL_SYNC") end)
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

local SECTIONS = { "Solo", "Matches", "Progress", "Gear", "Other" }
local commands = {}      -- name -> handler
local helpBySection = {} -- section -> { help lines in registration order }

-- Register a command. names: string or list of aliases. help: nil to hide it
-- from /tfl. fn(MF, args) where args are the lowercased words after the name.
function MF:Command(names, section, help, fn)
    if type(names) == "string" then names = { names } end
    for _, name in ipairs(names) do commands[name] = fn end
    if help then
        helpBySection[section] = helpBySection[section] or {}
        table.insert(helpBySection[section], help)
    end
end

function MF:PrintHelp()
    print("|cffffd100Solo|r - a log starts automatically when you cast Fishing.")
    for _, section in ipairs(SECTIONS) do
        local lines = helpBySection[section]
        if lines then
            if section ~= "Solo" then print("|cffffd100" .. section .. "|r") end
            for _, line in ipairs(lines) do print("  " .. line) end
        end
    end
end

-- Handlers get the words lowercased, which is what nearly all of them want,
-- and the rest of the line untouched for the ones that take a player name.
if not MF.inert then
    SLASH_THEFISHINGLOG1 = "/tfl"
    SLASH_THEFISHINGLOG2 = "/fishinglog"
    SLASH_THEFISHINGLOG3 = "/mf" -- old name, kept for muscle memory
    SlashCmdList.THEFISHINGLOG = function(input)
        local raw = strtrim(input or "")
        local args = { strsplit(" ", raw:lower()) }
        local name = table.remove(args, 1)
        local handler = commands[name]
        if handler then
            handler(MF, args, strtrim(raw:sub(#name + 1)))
        else
            MF:PrintHelp()
        end
    end
end

MF:Command({ "units", "kg", "lb" }, "Other", "/tfl units - weights in pounds or kilograms",
    function(self)
        self.db.settings.kilograms = not self:Metric()
        self:Print(("Weights in |cffffd100%s|r.%s"):format(
            self:Metric() and "kilograms" or "pounds",
            self:Metric() and " Records are still kept and compared in pounds." or ""))
        self:RefreshJournal()
        self:UpdateBoard()
    end)

MF:Command("debug", "Other", "/tfl debug - debug output, enables /tfl test [itemID] and /tfl spec [itemID]",
    function(self)
        self.db.debug = not self.db.debug
        self:Print("Debug " .. (self.db.debug and "on" or "off"))
    end)
