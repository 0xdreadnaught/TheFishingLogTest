-- Test build notice. This file exists only in the test build. Once per login it tells
-- the player that this is not the main addon, and why the realm looks empty.
local _, MF = ...

local function Notice(self)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local build = get and get(MF.ADDON, "X-Build")
    self:Print(("|cffff8040TEST BUILD%s - not the main addon.|r It only sees anglers who run the test "
        .. "build and keeps its own saved data. The main addon is The Fishing Log on CurseForge.")
        :format(build and build ~= "" and (" " .. build) or ""))
    if self.WorldLabel and self.worldKey and self.worldKey ~= "?" then
        self:Print("You are on " .. self:WorldLabel() .. ". Records, standings and events shown are this world's only.")
    else
        -- Without a world this copy can only hear other copies that also couldn't tell.
        self:Print("|cffff8040Couldn't tell which region and rule set this character is on,|r so nothing will sync. "
            .. "If you just updated, restart the game (a /reload isn't enough). If it still says this, type "
            .. "|cffffd100/tfl clientdiag|r and send the World lines to whoever gave you the test build.")
    end
end
MF.TestBuildNotice = Notice

-- Which build is everyone else on? Every WHO and HERE ends with the sender's build number
-- (Census.lua). Builds can differ in ways that stop them hearing each other properly, and the
-- addon's own "update available" notice never fires here because every test build calls itself
-- 1.1.4. So the first time someone on a newer build is heard, say so once.
local REPO = "github.com/0xdreadnaught/TheFishingLogTest"
local builds, told = {}, false
local function Mine() return tonumber(MF.BuildNumber and MF.BuildNumber() or "") end

function MF:NoteBuild(sender, build)
    local n = type(build) == "string" and build:match("^%d%d?%d?%d?%d?$") and tonumber(build)
    if not n or n < 1 or not sender or (self.IsMe and self:IsMe(sender)) then return end
    builds[self:AnglerKey(sender)] = n
    local mine = Mine()
    if told or not mine or n <= mine then return end
    told = true
    local function Say()
        local newest = 0
        for _, b in pairs(builds) do if b > newest then newest = b end end
        self:Print(("|cffff8040Test build %d is out; you have %d.|r Different builds may not sync with each other. "
            .. "Update with git pull in the addon folder, or get the ZIP from %s, then restart the game.")
            :format(newest, mine, REPO))
    end
    if C_Timer and C_Timer.After then C_Timer.After(30, Say) else Say() end
end

-- "15 x3, 14 x1": the builds heard this session, newest first, for /tfl clientdiag.
function MF:BuildsHeardText()
    local count, order = {}, {}
    for _, b in pairs(builds) do
        if not count[b] then count[b] = 0 order[#order + 1] = b end
        count[b] = count[b] + 1
    end
    table.sort(order, function(a, b) return a > b end)
    for i, b in ipairs(order) do order[i] = b .. " x" .. count[b] end
    return #order > 0 and table.concat(order, ", ") or "none yet"
end

MF:On("TFL_LOGIN", function(self)
    if C_Timer and C_Timer.After then C_Timer.After(8, function() Notice(self) end) else Notice(self) end
end)

-- Can an addon message travel over a custom chat channel on Forever? The addon assumes not
-- (Comm.lua, CUSTOM_CHANNEL_SUPPORTED = false) and never tries. /tfl channeltest tries once:
-- one short message to our own finder channel, then reports what the client answered and
-- whether the message came back to us, as a sender's own channel messages normally do.
-- Nothing is sent unless the command is typed. Other test builds ignore the message.
local channelTest = { at = -math.huge }
function MF:ChannelSendTest()
    local say = function(text) self:Print("Channel test: " .. text) end
    local now = GetTime()
    if now - channelTest.at < 30 then return say("wait a few seconds between tries.") end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if type(send) ~= "function" or type(GetChannelName) ~= "function" then return say("this client has no way to try.") end
    local id = GetChannelName(self.CHANNEL)
    if type(id) ~= "number" or id <= 0 then
        return say("not in the " .. tostring(self.CHANNEL) .. " channel yet. Type /tfl sync, wait a minute and try again.")
    end
    channelTest.at = now
    local nonce = tostring(math.random(100000, 999999))
    local payload = "CHTEST~" .. nonce
    local heard
    if not channelTest.frame and CreateFrame then
        channelTest.frame = CreateFrame("Frame")
        channelTest.frame:RegisterEvent("CHAT_MSG_ADDON")
        channelTest.frame:SetScript("OnEvent", function(_, _, prefix, text, dist, _, _, _, number, name)
            if channelTest.listen and prefix == MF.PREFIX then channelTest.listen(text, dist, number, name) end
        end)
    end
    channelTest.listen = function(text, dist, number, name)
        if text == payload then heard = tostring(dist) .. ", marked as channel " .. tostring(number) .. " \"" .. tostring(name) .. "\"" end
    end
    local ok, result = pcall(send, self.PREFIX, payload, "CHANNEL", id)
    local name
    for key, value in pairs(type(Enum) == "table" and type(Enum.SendAddonMessageResult) == "table" and Enum.SendAddonMessageResult or {}) do
        if value == result then name = key end
    end
    local accepted = ok and (result == nil or result == true or result == 0)
    say(("sent one message to channel %d. The client answered: %s%s."):format(id,
        ok and tostring(result) or ("ERROR " .. tostring(result)), name and (" (" .. name .. ")") or ""))
    local function Verdict()
        channelTest.listen = nil
        if heard then
            say("|cff3ee63eit came back on " .. heard .. ".|r Addon messages DO travel over a custom channel here.")
        elseif not accepted then
            say("|cffff8040the client refused it and nothing came back.|r Custom channels are closed to addon messages here.")
        else
            say("|cffffd100the client accepted it but nothing came back in 5 seconds.|r Either the server drops it quietly, "
                .. "or senders don't hear their own. A second test-build player in the channel settles it: have them run this "
                .. "and watch /tfl clientdiag for 'channel test heard'.")
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(5, Verdict) else Verdict() end
end

-- How many chat channels can one player be in at once? Joins numbered throwaway channels
-- until the client stops taking them, reports the count and the numbers they were given,
-- then leaves them all again. Takes up to a minute. /tfl channeltest slots
local PROBE = "TFLTestProbe"
local slotTest
local function JoinedNumber(name)
    local id = type(GetChannelName) == "function" and GetChannelName(name)
    return type(id) == "number" and id > 0 and id or nil
end
local function ChannelsJoined()
    if type(GetChannelList) ~= "function" then return nil end
    return math.floor(select("#", GetChannelList()) / 3)
end
function MF:ChannelSlotTest()
    local say = function(text) self:Print("Channel slots: " .. text) end
    if slotTest then return say("already running.") end
    if type(JoinTemporaryChannel) ~= "function" or type(LeaveChannelByName) ~= "function" or not (C_Timer and C_Timer.After) then
        return say("this client has no way to try.")
    end
    local cap = tonumber(MAX_WOW_CHAT_CHANNELS)
    local before, ours = ChannelsJoined(), JoinedNumber(self.CHANNEL)
    slotTest = { tried = 0, numbers = {} }
    say(("the client's stated limit is %s. You are in %s now; ours is number %s. Joining test channels, one every 2 seconds..."):format(
        cap and tostring(cap) or "not stated", before and tostring(before) or "?", ours and tostring(ours) or "not joined"))
    local limit = math.min(30, (cap or 20) + 2)
    local function Finish(refused)
        local t = slotTest
        for i = 1, t.tried do pcall(LeaveChannelByName, PROBE .. i) end
        C_Timer.After(3, function()
            local left, after = 0, JoinedNumber(self.CHANNEL)
            for i = 1, t.tried do if not JoinedNumber(PROBE .. i) then left = left + 1 end end
            say(("joined %d more%s, so %s at once. They were given the numbers %s."):format(#t.numbers,
                refused and " before the client stopped taking them" or " and stopped there (the test's own limit)",
                before and tostring(before + #t.numbers) or "?", #t.numbers > 0 and table.concat(t.numbers, " ") or "none"))
            say(("left %d of %d test channels. Ours was number %s and is now %s."):format(left, t.tried,
                ours and tostring(ours) or "not joined", after and tostring(after) or "not joined"))
            slotTest = nil
        end)
    end
    local function Step(retried)
        local t = slotTest
        if t.tried > 0 then
            local id = JoinedNumber(PROBE .. t.tried)
            if id then t.numbers[#t.numbers + 1] = id
            elseif not retried then return C_Timer.After(2, function() Step(true) end) -- a slow answer is not a refusal
            else return Finish(true) end
        end
        if t.tried >= limit then return Finish(false) end
        t.tried = t.tried + 1
        pcall(JoinTemporaryChannel, PROBE .. t.tried)
        C_Timer.After(2, function() Step(false) end)
    end
    Step(false)
end

-- How fast can one player send on the channel? 45 numbered messages in three steps (2, 5 and
-- 10 a second, about 12 seconds), sent straight to the client, not through the addon's own
-- one-a-second queue. Reports for each step how many the client accepted, how many it
-- throttled, and how many came back. Other test builds count how many they heard.
-- /tfl channeltest rate
local RATE_STEPS = { { 2, 10 }, { 5, 15 }, { 10, 20 } }
local rateTest = { at = -math.huge }
function MF:ChannelRateTest()
    local say = function(text) self:Print("Channel rate: " .. text) end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if type(send) ~= "function" or not (C_Timer and C_Timer.After) then return say("this client has no way to try.") end
    local now = GetTime()
    if now - rateTest.at < 60 then return say("wait a minute between runs.") end
    if not JoinedNumber(self.CHANNEL) then return say("not in the " .. tostring(self.CHANNEL) .. " channel yet. Type /tfl sync, wait a minute and try again.") end
    rateTest.at = now
    local nonce, total = tostring(math.random(100000, 999999)), 0
    for _, step in ipairs(RATE_STEPS) do total = total + step[2] end
    local results = {}
    rateTest.nonce = nonce
    rateTest.listen = function(text)
        local n, step = text:match("^CHRATE~(%d+)~(%d)~")
        if n == nonce and results[tonumber(step)] then results[tonumber(step)].back = results[tonumber(step)].back + 1 end
    end
    local throttle = type(Enum) == "table" and type(Enum.SendAddonMessageResult) == "table" and Enum.SendAddonMessageResult.AddonMessageThrottle
    local at = 0
    for index, step in ipairs(RATE_STEPS) do
        local r = { rate = step[1], sent = 0, ok = 0, throttled = 0, refused = 0, back = 0 }
        results[index] = r
        for seq = 1, step[2] do
            C_Timer.After(at, function()
                local id = JoinedNumber(self.CHANNEL) -- by name every time: the number can change
                if not id then r.refused = r.refused + 1 return end
                local ok, result = pcall(send, self.PREFIX, ("CHRATE~%s~%d~%d~%d"):format(nonce, index, seq, total), "CHANNEL", id)
                r.sent = r.sent + 1
                if ok and (result == nil or result == true or result == 0) then r.ok = r.ok + 1
                elseif ok and throttle ~= nil and result == throttle then r.throttled = r.throttled + 1
                else r.refused = r.refused + 1 end
            end)
            at = at + 1 / step[1]
        end
        at = at + 1 -- a breath between steps
    end
    say(("sending %d messages over about %d seconds..."):format(total, math.ceil(at)))
    C_Timer.After(at + 5, function()
        rateTest.listen = nil
        for _, r in ipairs(results) do
            say(("%d a second: %d sent, %d accepted, %d throttled, %d refused, %d came back."):format(
                r.rate, r.sent, r.ok, r.throttled, r.refused, r.back))
        end
    end)
end


-- What does the game tell an addon when a channel it wants is locked with a password, or it
-- has been banned? Everything the client says about our channels (names starting "TFL", and
-- the finder channel) is kept for /tfl clientdiag. /tfl channeltest join NAME makes the addon
-- itself ask to join, the way it would at login, so the answer can be seen; it leaves again
-- after 10 seconds if it got in.
local lockSignals, lockEvent = {}, false
local function OurChannel(name)
    if type(name) ~= "string" then return false end
    name = name:gsub("^%d+%.%s*", "")
    return name:find("^TFL") ~= nil or name:lower() == tostring(MF.CHANNEL):lower()
end
local function NoteLockSignal(text)
    lockSignals[#lockSignals + 1] = text
    if #lockSignals > 8 then table.remove(lockSignals, 1) end
end
do
    local f = CreateFrame and CreateFrame("Frame")
    if f and f.RegisterEvent then
        lockEvent = pcall(f.RegisterEvent, f, "CHANNEL_PASSWORD_REQUEST") -- an unknown event name raises an error
        pcall(f.RegisterEvent, f, "CHAT_MSG_CHANNEL_NOTICE")
        f:SetScript("OnEvent", function(_, event, first, _, _, prefixed, _, _, _, _, base)
            if event == "CHANNEL_PASSWORD_REQUEST" then
                if OurChannel(first) then NoteLockSignal("PASSWORD_REQUEST event " .. first) end
            elseif first ~= "YOU_JOINED" and first ~= "YOU_LEFT" and first ~= "YOU_CHANGED" then
                local name = type(base) == "string" and base ~= "" and base or prefixed
                if OurChannel(name) then NoteLockSignal(tostring(first) .. " notice " .. tostring(name):gsub("^%d+%.%s*", "")) end
            end
        end)
    end
end
function MF:ChannelJoinTest(name)
    local say = function(text) self:Print("Channel join: " .. text) end
    if type(name) ~= "string" or not name:find("^TFL[%w]+$") or #name > 30 then
        return say("give a channel name starting with TFL, letters and digits only. Example: /tfl channeltest join TFLLockTest")
    end
    if type(JoinTemporaryChannel) ~= "function" or not (C_Timer and C_Timer.After) then return say("this client has no way to try.") end
    local ok = pcall(JoinTemporaryChannel, name)
    say("asked to join " .. name .. (ok and "." or ", and the client raised an error.") .. " Watch for a password box.")
    C_Timer.After(4, function()
        local id = JoinedNumber(name)
        local box = type(StaticPopup_Visible) == "function" and StaticPopup_Visible("CHAT_CHANNEL_PASSWORD") and true or false
        say((id and ("got in, as channel " .. id .. ". Leaving it again shortly.") or "did not get in.")
            .. " Password box on screen: " .. (box and "yes" or "no") .. ". Now paste the 'lock signals' line from /tfl clientdiag.")
        if id and type(LeaveChannelByName) == "function" then C_Timer.After(6, function() pcall(LeaveChannelByName, name) end) end
    end)
end


-- Try the locked-channel handling (Comm.lua, "A locked channel") without touching the real
-- finder channel: for this session only, the addon looks for other anglers in NAME instead.
-- Have someone lock NAME first (/join NAME secret). A /reload puts everything back.
-- /tfl channeltest base NAME
function MF:ChannelBaseTest(name)
    local say = function(text) self:Print("Channel fallback: " .. text) end
    if type(name) ~= "string" or not name:find("^TFL[%a]+$") or #name > 24 then
        return say("give a name starting with TFL, letters only. Example: /tfl channeltest base TFLLockTest")
    end
    if not (self.JoinChannel and self.CHANNEL_BASE and C_Timer and C_Timer.After) then return say("this copy has no fallback to try.") end
    if JoinedNumber(self.CHANNEL) and type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, self.CHANNEL) end
    self.CHANNEL_BASE, self.CHANNEL = name, name
    self.channelBaseOverridden = true -- nothing from this session is remembered as the real channel
    self.discoveryJoin = { attempts = 0, last = -math.huge, nextAt = 0, readyAt = 0 }
    local locksBefore, boxesBefore = self.channelLocks or 0, self.passwordBoxesClosed or 0
    say("for this session the finder channel is " .. name .. ". Asking to join it now; watch for a password box. /reload undoes this.")
    self:JoinChannel(true)
    C_Timer.After(12, function()
        local id = JoinedNumber(self.CHANNEL)
        local box = type(StaticPopup_Visible) == "function" and StaticPopup_Visible("CHAT_CHANNEL_PASSWORD") and true or false
        say(("ended up in %s (%s). Locked names met: %d. Password boxes closed: %d (by %s). Box on screen now: %s."):format(
            tostring(self.CHANNEL), id and ("channel " .. id) or "not joined yet", (self.channelLocks or 0) - locksBefore,
            (self.passwordBoxesClosed or 0) - boxesBefore, tostring(self.passwordBoxClosedBy), box and "YES" or "no"))
    end)
end

if MF.Command then
    MF:Command("channeltest", "Other",
        "/tfl channeltest - test build: can addon messages use the finder channel? (also: slots, rate, join NAME, base NAME)",
        function(self, args, rest)
            local what = args and args[1]
            local word = type(rest) == "string" and rest:match("^%S+%s+(%S+)") or nil
            if what == "slots" then self:ChannelSlotTest()
            elseif what == "rate" then self:ChannelRateTest()
            elseif what == "join" then self:ChannelJoinTest(word)
            elseif what == "base" then self:ChannelBaseTest(word)
            else self:ChannelSendTest() end
        end)
end
-- The test channels come and go quietly.
if ChatFrame_AddMessageEventFilter then
    local function Quiet(_, _, ...)
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and v:find(PROBE, 1, true) then return true end
        end
    end
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", Quiet)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", Quiet)
end
-- Someone else's test arriving on the channel proves the route for everyone who hears it.
do
    local f = CreateFrame and CreateFrame("Frame")
    if f then
        f:RegisterEvent("CHAT_MSG_ADDON")
        f:SetScript("OnEvent", function(_, _, prefix, text, dist, sender)
            if prefix ~= MF.PREFIX or type(text) ~= "string" or dist ~= "CHANNEL" then return end
            local mine = MF.IsMe and type(sender) == "string" and MF:IsMe(sender)
            if text:find("^CHRATE~") then
                -- Ours is told apart by its number, not by the sender's name.
                local nonce, total = text:match("^CHRATE~(%d+)~%d~%d+~(%d+)$")
                if nonce and nonce == rateTest.nonce then
                    if rateTest.listen then rateTest.listen(text) end
                elseif nonce then
                    -- someone else's rate test: how many of theirs reached us
                    local heard = MF.rateTestHeard
                    if not heard or heard.nonce ~= nonce then heard = { nonce = nonce, n = 0, total = tonumber(total) } MF.rateTestHeard = heard end
                    heard.n = heard.n + 1
                end
            elseif text:find("^CHTEST~%d+$") and not mine then
                MF.channelTestsHeard = (MF.channelTestsHeard or 0) + 1
            end
        end)
    end
end

-- Which world is this character in? Forever splits players by region and by rule set, and
-- its realm-name calls answer "". This lists everything the client will say about it, so the
-- right call can be picked from evidence. Read-only; shown by /tfl clientdiag.
function MF:WorldProbeLines()
    local out = {}
    local function Show(v)
        if self.IsSecret and self:IsSecret(v) then return "restricted" end
        if type(v) == "string" then return '"' .. v .. '"' end
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(x)
                if #parts >= 12 then parts[#parts + 1] = "..." break end
            end
            table.sort(parts)
            return "{" .. table.concat(parts, " ") .. "}"
        end
        return tostring(v)
    end
    local function List(...)
        local n, parts = select("#", ...), {}
        for i = 1, n do parts[i] = Show((select(i, ...))) end
        return n > 0 and table.concat(parts, ", ") or "nothing"
    end
    local function Answer(ok, ...)
        if not ok then return "ERROR" end
        return List(...)
    end
    local function Call(fn, ...)
        if type(fn) == "string" then fn = _G[fn] end
        if type(fn) ~= "function" then return "absent" end
        return Answer(pcall(fn, ...))
    end
    local function Line(label, text) out[#out + 1] = "World " .. label .. ": " .. text end

    Line("key", Show(self.worldKey) .. " | sent as " .. Show(self.worldCode) .. " | " .. (self.WorldLabel and self:WorldLabel() or "?") .. " | saved data holds " .. Show(self.db and self.db.world)
        .. " | parked " .. Show(self.db and self.db.worlds and (function() local n = {} for k in pairs(self.db.worlds) do n[#n + 1] = k end table.sort(n) return table.concat(n, " ") end)() or "")
        .. " | other-world messages dropped " .. tostring(self.otherWorldsHeard or 0))
    Line("channel test heard", tostring(self.channelTestsHeard or 0) .. " from other players this session"
        .. " | last rate test heard: " .. (self.rateTestHeard and (self.rateTestHeard.n .. " of " .. tostring(self.rateTestHeard.total)) or "none"))
    Line("lock signals", "password-request event " .. (lockEvent and "exists" or "absent") .. " | seen: "
        .. (#lockSignals > 0 and table.concat(lockSignals, "; ") or "none"))
    Line("channel slots", "stated limit " .. tostring(MAX_WOW_CHAT_CHANNELS) .. " | joined now " .. tostring(ChannelsJoined())
        .. " | ours is " .. tostring(self.CHANNEL) .. ", number " .. tostring(JoinedNumber(self.CHANNEL or ""))
        .. " | locked names met " .. tostring(self.channelLocks or 0) .. " | password boxes closed " .. tostring(self.passwordBoxesClosed or 0))
    Line("finder channel", tostring(self.CHANNEL) .. " | told to others as " .. Show(self.FinderChannelForWire and self:FinderChannelForWire() or nil)
        .. " | remembered " .. Show(self.db and self.db.finderChannel) .. " | channels heard from others " .. tostring(self.peerChannels or 0)
        .. " | last " .. tostring(self.lastPeerChannel))
    Line("password box", "closed by " .. tostring(self.passwordBoxClosedBy) .. " | show hook " .. tostring(self.passwordBoxHook)
        .. " | StaticPopup_Visible gave " .. tostring(self.passwordBoxSeenAs)
        .. " | walker " .. type(StaticPopup_ForEachShownDialog) .. " | StaticPopup1 " .. type(StaticPopup1)
        .. " | StaticPopup_Hide " .. type(StaticPopup_Hide))
    Line("builds", "mine " .. tostring(Mine()) .. " | heard this session: " .. self:BuildsHeardText())
    Line("region", Call("GetCurrentRegion") .. " | name " .. Call("GetCurrentRegionName"))
    Line("realm name", Call("GetRealmName") .. " | normalized " .. Call("GetNormalizedRealmName")
        .. " | id " .. Call("GetRealmID") .. " | kept " .. Show(self.cdb and self.cdb.realm))
    Line("native realm id", Call("GetNativeRealmID") .. " | selected realm " .. Call("SelectedRealmName")
        .. " | unique names " .. Call("RegionalUniqueNamesEnabled") .. " | tournament " .. Call("IsOnTournamentRealm"))
    Line("guid realm", Call(function() return (tostring(UnitGUID("player")):match("^%a+%-(%d+)%-")) end))
    Line("connected realms", Call("GetAutoCompleteRealms"))
    Line("cvars", "portal " .. Call("GetCVar", "portal") .. " | realmName " .. Call("GetCVar", "realmName")
        .. " | agentUID " .. Call("GetCVar", "agentUID") .. " | locale " .. Call("GetLocale"))
    Line("zone pvp", Call("GetZonePVPInfo") .. " | flagged " .. Call("UnitIsPVP", "player")
        .. " | desired " .. Call("GetPVPDesired"))

    local function Members(name)
        local t = _G[name]
        if type(t) ~= "table" then return "absent" end
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        return #keys > 0 and table.concat(keys, " ") or "empty"
    end
    Line("C_GameRules", Members("C_GameRules"))
    local rules = type(Enum) == "table" and Enum.GameRule
    if type(rules) == "table" and type(C_GameRules) == "table" and type(C_GameRules.IsGameRuleActive) == "function" then
        local active, count = {}, 0
        for name, id in pairs(rules) do
            count = count + 1
            local ok, on = pcall(C_GameRules.IsGameRuleActive, id)
            if ok and on then active[#active + 1] = tostring(name) end
        end
        table.sort(active)
        Line("active game rules", ("%d of %d: %s"):format(#active, count, #active > 0 and table.concat(active, " ") or "none"))
    else
        Line("active game rules", "no Enum.GameRule or no IsGameRuleActive")
    end
    local GR = type(C_GameRules) == "table" and C_GameRules or {}
    for _, name in ipairs({ "IsHardcoreActive", "IsStandard", "IsSelfFoundAllowed", "GetActiveGameMode",
        "GetCurrentGameModeRecordID", "GetCurrentGameModeDisplayInfo", "GetForeverExperiencePreset",
        "GetCurrentEventRealmQueues", "IsCharacterlessLoginActive" }) do
        if GR[name] then Line("C_GameRules." .. name, Call(GR[name])) end
    end
    if GR.GetNumDisplayedGameModes and GR.GetDisplayedGameModeRecordIDAtIndex then
        local ok, n = pcall(GR.GetNumDisplayedGameModes)
        n = ok and tonumber(n) or 0
        Line("displayed game modes", tostring(n))
        for i = 1, math.min(n, 10) do
            local okID, id = pcall(GR.GetDisplayedGameModeRecordIDAtIndex, i)
            Line("game mode " .. i, "record " .. Show(okID and id or "ERROR")
                .. " | info " .. Call(GR.GetGameModeDisplayInfoByRecordID, okID and id or nil)
                .. " | glue name " .. Call(GR.GetGameModeGlueScreenName, okID and id or nil)
                .. " | enabled " .. Call(GR.IsGameModeEnabled, okID and id or nil))
        end
    end
    if type(Enum) == "table" then
        Line("Enum.GameMode", Show(Enum.GameMode))
        Line("Enum.EventRealmQueues", Show(Enum.EventRealmQueues))
        Line("Enum.ChatChannelRuleset", Show(Enum.ChatChannelRuleset))
    end
    if type(rules) == "table" then
        local names, values = {}, {}
        for name, id in pairs(rules) do
            names[#names + 1] = tostring(name)
            if GR.IsGameRuleActive and GR.GetGameRuleAsFloat then
                local okA, on = pcall(GR.IsGameRuleActive, id)
                local okV, v = pcall(GR.GetGameRuleAsFloat, id)
                if okA and on and okV then values[#values + 1] = tostring(name) .. "=" .. tostring(v) end
            end
        end
        table.sort(names) table.sort(values)
        Line("active rule values", table.concat(values, " "))
        Line("all game rules", table.concat(names, " "))
    end

    -- Is the finder channel one per world, or shared across the region?
    local CI = type(C_ChatInfo) == "table" and C_ChatInfo or {}
    local function Channel(label, name)
        local ok, id = pcall(GetChannelName, name)
        id = ok and tonumber(id) or 0
        Line("channel " .. label, "id " .. tostring(id)
            .. " | ruleset " .. Call(CI.GetChannelRulesetForChannelID, id)
            .. " | regional " .. Call(CI.IsChannelRegionalForChannelID, id))
    end
    if type(GetChannelName) == "function" then
        Channel("finder", self.CHANNEL or "TheFishingLogTest")
        Channel("1", 1)
    end
    Line("regional chat service", Call(CI.IsRegionalServiceAvailable))
    Line("C_Seasons", Members("C_Seasons"))
    if type(C_Seasons) == "table" then
        Line("season", "has " .. Call(C_Seasons.HasActiveSeason) .. " | active " .. Call(C_Seasons.GetActiveSeason))
    end

    -- Anything else the client names after these ideas: globals, C_ namespaces, enums.
    local words = { "realm", "region", "gamerule", "ruleset", "gamemode", "hardcore", "roleplay", "district", "preset" }
    local function Matches(key)
        if type(key) ~= "string" then return false end
        local lower = key:lower()
        for _, w in ipairs(words) do if lower:find(w, 1, true) then return true end end
        return false
    end
    local function Scan(label, t, limit)
        if type(t) ~= "table" then Line(label, "absent") return end
        local found = {}
        for k, v in pairs(t) do
            if Matches(k) and (type(v) == "function" or type(v) == "table") then
                found[#found + 1] = k .. (type(v) == "table" and "{}" or "")
            end
        end
        table.sort(found)
        local total = #found
        for i = #found, limit + 1, -1 do found[i] = nil end
        Line(label, ("%d: %s%s"):format(total, table.concat(found, " "), total > limit and " ..." or ""))
    end
    Scan("globals", _G, 90)
    Scan("enums", type(Enum) == "table" and Enum or nil, 40)
    for name, t in pairs(_G) do
        if type(name) == "string" and name:find("^C_") and type(t) == "table" and not Matches(name) then
            local found = {}
            for k in pairs(t) do if Matches(k) then found[#found + 1] = tostring(k) end end
            if #found > 0 then table.sort(found) Line(name, table.concat(found, " ")) end
        end
    end
    return out
end
