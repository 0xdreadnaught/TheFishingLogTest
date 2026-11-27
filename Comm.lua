-- Comm: hidden addon messages over the TheFishingLog channel and your group.
--
-- Messages are fields joined by "~", the first field being the type. Anything
-- over the 255-byte limit is split into "P" parts and reassembled on arrival.
-- Everything goes through a queue so we stay under the server's rate limit.
--
--   Matches:  HOST2 JOIN LEAVE CANCEL CATCH SCORE       (Match.lua)
--   Records:  REC2 RREQ2 RSYNC2 RMINE RALL RBOOK RASK   (Records.lua)
--   Bounty:   BNTY2 BREQ2                               (Conditions.lua)
--
-- BOUNTY and BREQ were retired rather than kept: a 0.9.x client picks
-- its bounty from a different pool, so its weight is for a different
-- fish and scoring it here would be entering it in a contest it never
-- took part in. Those clients are simply absent from the standings
-- until they update, which is honest where accepting them would not be.
--   Census:   WHO HERE                                  (Census.lua)
--   Tooltips: INFOQ INFO (whispers)                     (Tooltip.lua)
--   Invites:  INV INVNO (whispers)                      (Match.lua)
--   Events:   NPOST NSIGN NCANCEL NREQ NRESULT          (Noticeboard.lua)
--   Roads:    PING PONG (the road test)                 (Report.lua)
--   Curve:    SKREQ SKUP (where skill comes up)         (Guide.lua)
local _, MF = ...

-- Test build: its own message prefix and finder channel, so it only ever talks to
-- other copies of this build. Upstream values: "FishingLog" and "TheFishingLog".
MF.PREFIX = "FishingLogTest"
MF.CHANNEL = "TheFishingLogTest"
MF.CHANNEL_BASE = MF.CHANNEL -- MF.CHANNEL moves to CHANNEL_BASE .. 2, 3, ... while a name is locked (see "A locked channel")
-- Forever rejects addon sends over custom channels.
MF.CUSTOM_CHANNEL_SUPPORTED = false
local SEP = "~"
local MAX_LEN = 250
local CHUNK_LEN = 220
local CHANNEL_JOIN_DELAY = 30 -- let the client's saved/default channels restore first
local CACHE_LIFETIME = 120   -- idle timeout; active transfers can take longer
local MAX_TRANSFER_AGE = 1800 -- absolute cap even if new parts keep arriving
local MAX_PARTS = 1024      -- allow large map syncs, reject unbounded chunk counts
local MAX_PARTIAL = 64      -- bound incomplete messages during a busy sync
local PRUNE_EVERY = 60

local handlers = {}
MF.handlers = handlers

------------------------------------------------------------------------
-- Outgoing queue (token bucket: short bursts, then ~1 message a second)
------------------------------------------------------------------------

local queue = {}
local tokens, MAX_TOKENS, REFILL_PER_SEC = 6, 6, 1.2
local lastRefill = GetTime()
local chunkID = 0
local whispered = {} -- name -> actual send time, not queue time
-- The last whisper to each two-word name on our realm, kept for a few
-- seconds so a "No player named" can be answered by trying the other form.
local lastWhisper = {}
local function WhisperKey(name)
    return (MF:SplitName(name)):gsub("[%s%-]", ""):lower()
end

local function Pump()
    local now = GetTime()
    tokens = math.min(MAX_TOKENS, tokens + (now - lastRefill) * REFILL_PER_SEC)
    lastRefill = now
    while tokens >= 1 and #queue > 0 do
        local item = table.remove(queue, 1)
        -- Channel numbers are mutable, including while bulk sync is queued.
        -- Never trust the numeric destination captured by Enqueue.
        local target = item.target
        if item.dist == "CHANNEL" then target = MF:ChannelID() end
        if item.dist ~= "CHANNEL" or target then
            if item.dist == "WHISPER" then
                whispered[WhisperKey(target)] = now
                MF.whispersSent = (MF.whispersSent or 0) + 1
            end
            local result = C_ChatInfo.SendAddonMessage(MF.PREFIX, item.msg, item.dist, target)
            -- Kept per whisper target for /tfl hooks: whether a two-word
            -- name is one the server will deliver to is only visible here.
            if item.dist == "WHISPER" then
                MF.whisperResults = MF.whisperResults or {}
                MF.whisperResults[target] = { result = tostring(result), at = now }
            end
            if result == false or (type(result) == "number" and result ~= 0) then
                MF.sendRefusals = (MF.sendRefusals or 0) + 1
                MF.lastSendRefusal = item.dist .. " " .. tostring(result)
            end
            local throttled = Enum.SendAddonMessageResult
                and result == Enum.SendAddonMessageResult.AddonMessageThrottle
            if throttled then
                table.insert(queue, 1, item)
                tokens = 0
                return
            end
            local transfer = item.transfer
            if transfer then
                local name = item.dist == "WHISPER" and target or item.dist
                MF:SyncPacketStarted(name, item.dist, "out", transfer.kind)
                if result == false or (type(result) == "number" and result ~= 0) then transfer.failed = true end
                transfer.remaining = transfer.remaining - 1
                if transfer.remaining == 0 then MF:SyncSendFinished(transfer) end
            end
            tokens = tokens - 1
        end
    end
end

local MATCH_CONTROL = { INV = true, INVNO = true, HOST2 = true, JOIN = true, LEAVE = true, CANCEL = true }

local function Enqueue(dist, target, msg, priority)
    local kind = msg:match("^([^~]+)")
    local transfer
    if MF.IsSyncKind and MF:IsSyncKind(kind) then
        local fields = { strsplit(SEP, msg) }; table.remove(fields, 1)
        transfer = { kind=kind,fields=fields,dist=dist,target=target,remaining=1 }
    end
    if kind == "GMATCH1" then
        local _, _, inner = strsplit(SEP, msg, 4)
        kind = inner -- private match controls keep the same queue priority
    end
    priority = MATCH_CONTROL[kind] and 2 or ((priority or kind == "CATCH" or kind == "SCORE" or kind == "RACK1") and 1 or 0)
    -- Keep arrival order within each class. Match controls precede live
    -- catches, which precede bulk sync, without bypassing the token bucket.
    local function Insert(item)
        item.priority = priority
        item.transfer = transfer
        local at = #queue + 1
        for i, queued in ipairs(queue) do
            if (queued.priority or 0) < priority then at = i break end
        end
        table.insert(queue, at, item)
    end
    if GetServerTime()>=MF.FRESH_START then msg=strjoin(SEP,"LIVE2",MF.FRESH_START,MF.worldCode or "?",msg) end
    if #msg <= MAX_LEN then
        local item = { dist = dist, target = target, msg = msg }
        Insert(item)
        return
    end
    chunkID = chunkID % 9999 + 1
    local n = math.ceil(#msg / CHUNK_LEN)
    if transfer then transfer.remaining = n end
    for i = 1, n do
        local part = msg:sub((i - 1) * CHUNK_LEN + 1, i * CHUNK_LEN)
        Insert({ dist = dist, target = target,
            msg = strjoin(SEP, "P", chunkID, i, n, part) })
    end
end

-- A reward sync window must not elapse while its requests are still
-- waiting behind bulk traffic in this queue.
function MF:BountySyncPending()
    for _, item in ipairs(queue) do
        local kind = item.msg:match("^([^~]+)")
        if kind=="LIVE2" then local _,_,_,body=strsplit(SEP,item.msg,4) kind=body and body:match("^([^~]+)") end
        if kind == "BREQ2" or kind == "BREQ4" or kind == "QBASK1" then return true end
    end
    return false
end

MF:On("TFL_INIT", function(self)
    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    C_Timer.NewTicker(0.25, Pump)
end)

------------------------------------------------------------------------
-- Channel
------------------------------------------------------------------------

function MF:ChannelID()
    if not self.CUSTOM_CHANNEL_SUPPORTED or not self.db.settings.channel then return nil end
    local id, name = GetChannelName(self.CHANNEL)
    if type(id) ~= "number" or id <= 0 or type(name) ~= "string"
        or name:lower() ~= self.CHANNEL:lower() then return end
    local actualID, actualName = GetChannelName(id)
    if actualID == id and type(actualName) == "string"
        and actualName:lower() == self.CHANNEL:lower() then return id end
end

local function DiscoveryState(self)
    if not self.discoveryJoin then self.discoveryJoin={attempts=0,last=-math.huge,nextAt=0,readyAt=0} end
    return self.discoveryJoin
end
local function JoinedID(self)
    local id=GetChannelName(self.CHANNEL)
    return type(id)=="number" and id>0 and id or nil
end
local function DiscoveryConnected(self,state)
    local remove=ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
    if remove and DEFAULT_CHAT_FRAME then pcall(remove,DEFAULT_CHAT_FRAME,self.CHANNEL) end
    if state.joined then return end
    state.joined=true state.error=nil state.attempts=0 state.nextAt=0
    if not self.CUSTOM_CHANNEL_SUPPORTED then self:Fire("TFL_ROSTER_SYNC")
    else self:Fire("TFL_SYNC") end
end
-- The channels you're in, as "1. General" and so on, and how many. Only
-- used to explain a join that didn't happen: the game is asked to join
-- whatever we count, because a miscount here once stopped the join from
-- ever being tried.
local function ChannelSlots()
    if type(GetChannelList)~="function" then return end
    local values={GetChannelList()}
    local names={}
    for i=1,#values,3 do
        local id,name=values[i],values[i+1]
        if type(id)=="number" and id>0 then names[#names+1]=("%d. %s"):format(id,tostring(name or "?")) end
    end
    return #names,names
end
MF.ChannelSlots=function() return ChannelSlots() end
function MF:DiscoveryJoinStatus()
    if not self.db.settings.channel then return "Automatic discovery is disabled in Options > Data." end
    if JoinedID(self) then
        return self.CHANNEL == self.CHANNEL_BASE and "Discovery channel joined."
            or ("Discovery channel joined: " .. self.CHANNEL .. " (the usual one is locked).")
    end
    local state=DiscoveryState(self)
    local now=GetTime()
    if now<state.readyAt then return ("Discovery channel join starts in %d seconds."):format(math.ceil(state.readyAt-now)) end
    local delay=math.max(0,math.ceil((state.nextAt or now)-now))
    return ("Discovery channel not joined: %s. %d attempt(s); automatic retry in %ds. /tfl sync retries too.")
        :format(state.error or "join has not completed",state.attempts,delay)
end
function MF:JoinChannel(manual)
    if not self.db or not self.db.settings.channel then return false end
    local state,now=DiscoveryState(self),GetTime()
    if JoinedID(self) then DiscoveryConnected(self,state) return true end
    state.joined=false
    -- Explicit retries can bypass backoff, but never issue joins faster than 15s.
    if now-state.last<15 or (not manual and (now<state.readyAt or now<state.nextAt)) then return false end
    state.last=now state.attempts=state.attempts+1
    state.nextAt=now+(state.attempts==1 and 15 or state.attempts==2 and 60 or 300)
    if type(JoinTemporaryChannel)~="function" then state.error="channel join API unavailable"
    else
        if self.ExpectChannelAnswer then self:ExpectChannelAnswer() end
        local ok=pcall(JoinTemporaryChannel,self.CHANNEL)
        state.error=ok and "the client has not confirmed membership" or "the client rejected the join request"
    end
    C_Timer.After(2,function()
        if self.discoveryJoin~=state or not self.db.settings.channel then return end
        if not JoinedID(self) then
            local count,names=ChannelSlots()
            if count and count>=10 then
                state.error=("all ten channel slots look taken (%s); leave one you don't use with /leave <number>")
                    :format(table.concat(names,", "))
            end
        end
        if JoinedID(self) then DiscoveryConnected(self,state)
        elseif state.attempts>=3 and GetTime()-(state.warningAt or -math.huge)>=1800 then
            state.warningAt=GetTime()
            self:Print(self:DiscoveryJoinStatus())
        end
    end)
    return false
end
function MF:EnsureDiscoveryChannel()
    if not self.db or not self.db.settings.channel or not self.discoveryJoin then return end
    local state=DiscoveryState(self)
    if GetTime()<state.readyAt then return end
    if JoinedID(self) then
        -- No need to remove chat output on every health check.
        if not state.joined then DiscoveryConnected(self,state) end
    else
        if state.joined then
            state.joined=false state.last=-math.huge state.nextAt=GetTime()
            state.error="membership was lost"
        end
        self:JoinChannel()
    end
end
function MF:LeaveChannel()
    self.discoveryJoin=nil
    if JoinedID(self) then LeaveChannelByName(self.CHANNEL) end
end
MF:On("TFL_LOGIN",function(self)
    self.discoveryJoin={attempts=0,last=-math.huge,nextAt=GetTime()+CHANNEL_JOIN_DELAY,readyAt=GetTime()+CHANNEL_JOIN_DELAY}
    local state=self.discoveryJoin
    C_Timer.After(CHANNEL_JOIN_DELAY,function()
        if self.discoveryJoin==state then self:JoinChannel(true) end
    end)
end)
local discoveryCheckAt=0
MF:OnTick(function(self)
    if GetTime()<discoveryCheckAt then return end
    discoveryCheckAt=GetTime()+5
    self:EnsureDiscoveryChannel()
end)

------------------------------------------------------------------------
-- Test build: a locked channel
--
-- Whoever has been in a custom channel longest owns it, and an owner can put a password on
-- it or ban people. A join is then refused, and the game puts a password box on the
-- player's screen each time the addon retries. Seen in game on 1.60.1: the client fires
-- CHANNEL_PASSWORD_REQUEST with the channel's name, then a WRONG_PASSWORD channel notice.
--
-- So: close the box, stop asking for that name, and use the next one: TheFishingLogTest2,
-- then 3, up to FALLBACKS. Every copy walks the same list from the start at each login, so
-- everyone ends up in the lowest name that is open. While in a later name, the earlier ones
-- are asked for again every RECHECK seconds, one at a time, and we move back down when one
-- opens. Nothing is saved: a lock is somebody's doing, not a fact about the name.
-- Record sync by whisper, guild and group does not depend on any of this.
------------------------------------------------------------------------
local FALLBACKS = 20
local RECHECK = 1800
local lockedAt = {} -- name, lower case -> GetTime() it last refused us (or we last asked)
local lockTold = false

local function ChannelName(index) return index == 1 and MF.CHANNEL_BASE or (MF.CHANNEL_BASE .. index) end
local function ChannelIndex(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%d+%.%s*", ""):lower()
    local base = MF.CHANNEL_BASE:lower()
    if name == base then return 1 end
    if name:sub(1, #base) ~= base then return nil end
    local n = tonumber(name:sub(#base + 1):match("^(%d%d?)$"))
    return n and n >= 2 and n <= FALLBACKS and n or nil
end
function MF:IsOurChannelName(name) return ChannelIndex(name) ~= nil end

-- The game's "enter the password for <channel>" box. Seen in game: it does appear when the
-- addon's own join is refused, and it stays until the player answers it. Three ways to find
-- it, because the popup code differs between clients: the numbered popup frames, the
-- "each shown dialog" walker, and StaticPopup_Visible. A box asking about a channel that is
-- not one of ours is the player's own and is left alone.
local POPUP = "CHAT_CHANNEL_PASSWORD"
local function Ours(dialog)
    local data = type(dialog) == "table" and dialog.data or nil
    return type(data) ~= "string" or ChannelIndex(data) ~= nil
end
local function CloseDialog(dialog, how)
    if type(dialog) ~= "table" or dialog.which ~= POPUP or not Ours(dialog) then return false end
    if type(dialog.IsShown) == "function" and not dialog:IsShown() then return false end
    if not pcall(dialog.Hide, dialog) then return false end
    MF.passwordBoxesClosed = (MF.passwordBoxesClosed or 0) + 1
    MF.passwordBoxClosedBy = how
    return true
end
local function HidePasswordBox()
    local closed = false
    for i = 1, 8 do
        if CloseDialog(_G["StaticPopup" .. i], "numbered frame") then closed = true end
    end
    if type(StaticPopup_ForEachShownDialog) == "function" then
        pcall(StaticPopup_ForEachShownDialog, function(dialog)
            if CloseDialog(dialog, "dialog walker") then closed = true end
        end)
    end
    if type(StaticPopup_Visible) == "function" then
        local ok, a, b = pcall(StaticPopup_Visible, POPUP)
        MF.passwordBoxSeenAs = ok and (type(a) .. "," .. type(b)) or "error"
        local dialog = ok and (type(b) == "table" and b or type(a) == "table" and a or (type(a) == "string" and _G[a])) or nil
        if type(dialog) == "table" and Ours(dialog) then
            if CloseDialog(dialog, "StaticPopup_Visible") then closed = true
            elseif type(StaticPopup_Hide) == "function" and (type(dialog.IsShown) ~= "function" or dialog:IsShown()) then
                pcall(StaticPopup_Hide, POPUP)
                MF.passwordBoxesClosed = (MF.passwordBoxesClosed or 0) + 1
                MF.passwordBoxClosedBy = "StaticPopup_Hide"
                closed = true
            end
        end
    end
    return closed
end
-- Close it the moment the game opens it, before a frame is drawn, when it is asking about one
-- of our names. hooksecurefunc runs after the game's own function and does not alter it.
local expectingBox = -math.huge
if type(hooksecurefunc) == "function" and type(StaticPopup_Show) == "function" and not MF.inert then
    MF.passwordBoxHook = pcall(hooksecurefunc, "StaticPopup_Show", function(which, channel)
        if which ~= POPUP then return end
        if ChannelIndex(channel) or GetTime() - expectingBox < 2 then HidePasswordBox() end
    end)
end

-- Closing the box after it opens still lets it make its opening sound (heard in game on
-- build 21). The box is opened by the game's chat windows when they hear the password
-- request. So for a few seconds after each join the addon asks for, the chat windows are
-- taken off that one event and we answer it instead: ours is dealt with silently, and a
-- request about a channel of the player's own is handed to the chat window as usual.
-- The hook above stays as the net if this client opens the box from somewhere else.
local LOCK_EVENT = "CHANNEL_PASSWORD_REQUEST"
local QUIET_FOR = 5
local quieted, quietUntil = {}, 0
local function EndQuiet()
    for i = #quieted, 1, -1 do
        pcall(quieted[i].RegisterEvent, quieted[i], LOCK_EVENT)
        quieted[i] = nil
    end
end
function MF:ExpectChannelAnswer()
    if self.inert then return end
    for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
        local f = _G["ChatFrame" .. i]
        if type(f) == "table" and type(f.IsEventRegistered) == "function" and type(f.UnregisterEvent) == "function" then
            local ok, on = pcall(f.IsEventRegistered, f, LOCK_EVENT)
            if ok and on and pcall(f.UnregisterEvent, f, LOCK_EVENT) then quieted[#quieted + 1] = f end
        end
    end
    self.passwordEventQuieted = #quieted
    quietUntil = GetTime() + QUIET_FOR
    if C_Timer and C_Timer.After then
        C_Timer.After(QUIET_FOR + 0.1, function() if GetTime() >= quietUntil then EndQuiet() end end)
    end
end
MF:OnTick(function() if #quieted > 0 and GetTime() >= quietUntil then EndQuiet() end end) -- the timer's backstop
-- The chat window's own answer to a request we intercepted that was not about us.
local function HandBack(name)
    local f = quieted[1]
    local handler = f and type(f.GetScript) == "function" and f:GetScript("OnEvent")
    if handler then pcall(handler, f, LOCK_EVENT, name) end
end

function MF:ChannelLocked(name, why)
    local index = ChannelIndex(name)
    if not index then return end
    name = ChannelName(index)
    -- The game's own handler for the same event may run after ours, or a little later.
    expectingBox = GetTime()
    HidePasswordBox()
    if C_Timer and C_Timer.After then
        for _, delay in ipairs({ 0, 0.2, 1 }) do C_Timer.After(delay, HidePasswordBox) end
    end
    local key, now = name:lower(), GetTime()
    local fresh = not lockedAt[key] or now - lockedAt[key] > 5 -- the event and the notice arrive as a pair
    lockedAt[key] = now
    if not fresh then return end
    self.channelLocks = (self.channelLocks or 0) + 1
    self.lastChannelLock = name .. " " .. tostring(why)
    if key ~= tostring(self.CHANNEL):lower() then return end -- an earlier name asked for again: still locked
    local nextIndex = index + 1
    while nextIndex <= FALLBACKS do
        local at = lockedAt[ChannelName(nextIndex):lower()]
        if not at or now - at >= RECHECK then break end
        nextIndex = nextIndex + 1
    end
    local state = self.discoveryJoin
    if nextIndex > FALLBACKS then
        if state then state.error = "every channel name is locked" state.nextAt = now + RECHECK end
        return
    end
    self.CHANNEL = ChannelName(nextIndex)
    if not lockTold then
        lockTold = true
        self:Print("Someone has locked the channel this addon uses to find other anglers. Using another one. "
            .. "Syncing with people you already know is not affected.")
    end
    if state then
        state.joined, state.attempts, state.last, state.nextAt = false, 0, -math.huge, 0
        state.error = "moved to " .. self.CHANNEL .. " (the one before is locked)"
        C_Timer.After(2, function()
            if self.discoveryJoin == state then self:JoinChannel(true) end
        end)
    end
end
-- pcall: asking a client for an event it does not have raises an error.
pcall(MF.On, MF, LOCK_EVENT, function(self, name)
    if ChannelIndex(name) then self:ChannelLocked(name, "PASSWORD_REQUEST") else HandBack(name) end
end)
pcall(MF.On, MF, "CHAT_MSG_CHANNEL_NOTICE", function(self, notice, _, _, prefixed, _, _, _, _, base)
    if notice == "WRONG_PASSWORD" or notice == "BANNED" then
        self:ChannelLocked(type(base) == "string" and base ~= "" and base or prefixed, notice)
    end
end)

-- In a later name: get back to an earlier one as soon as it opens.
local lowerCheckAt = 0
MF:OnTick(function(self)
    local now = GetTime()
    if now < lowerCheckAt then return end
    lowerCheckAt = now + 30
    local index = ChannelIndex(self.CHANNEL) or 1
    if index <= 1 or not self.db or not self.db.settings.channel or not self.discoveryJoin then return end
    for i = 1, index - 1 do
        local name = ChannelName(i)
        local id = GetChannelName(name)
        if type(id) == "number" and id > 0 then -- an earlier ask went through
            local old = self.CHANNEL
            self.CHANNEL, lockedAt[name:lower()] = name, nil
            if type(LeaveChannelByName) == "function" then
                local oldID = GetChannelName(old)
                if type(oldID) == "number" and oldID > 0 then pcall(LeaveChannelByName, old) end
            end
            self.discoveryJoin.joined = false -- so the next health check announces the channel and scans it
            return
        end
    end
    for i = 1, index - 1 do
        local name = ChannelName(i)
        local at = lockedAt[name:lower()]
        if not at or now - at >= RECHECK then
            lockedAt[name:lower()] = now -- asked: whatever the answer, not again for RECHECK
            self:ExpectChannelAnswer()
            if type(JoinTemporaryChannel) == "function" then pcall(JoinTemporaryChannel, name) end
            return
        end
    end
end)

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------

local function GroupDist()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Live catch reports must not expire behind a large record-book sync.
-- They still consume the same token bucket and server throttle budget.
function MF:SendNearby(...)
    local msg = strjoin(SEP, ...)
    local id, group, roads = self:ChannelID(), GroupDist(), 0
    if id then Enqueue("CHANNEL", id, msg, true) roads = roads + 1 end
    if IsInGuild() then Enqueue("GUILD", nil, msg, true) roads = roads + 1 end
    if group then Enqueue(group, nil, msg, true) roads = roads + 1 end
    if not id and not self.CUSTOM_CHANNEL_SUPPORTED then
        local map = select(8, ...)
        for _, peer in ipairs(self:NearbyWhisperPeers(map)) do
            Enqueue("WHISPER", peer, msg, true)
            roads = roads + 1
        end
    end
    return roads
end

-- Whispering someone who has just logged out, or whose name we got in a
-- shape the server won't take, puts an error in the chat window that the
-- player never asked for. We swallow that line if it names someone we
-- whispered a moment ago - it's our doing, not theirs.
local NOT_FOUND_WINDOW = 10
local lastError, lastErrorAt = nil, -math.huge

-- A two-word name refused in one form is tried once in the other. Which form
-- we keep using is only decided by an answer (ConfirmWhisperForm): the
-- server has dropped whispers without a word before, so silence after a
-- send proves nothing.
function MF:RetryWhisperForm(key)
    local w = lastWhisper[key]
    if not w then return end
    if w.retried then w.failed = true return end
    local plain, realm = self:SplitName(w.to)
    local alt = plain
    if not realm then
        -- Their own realm if we were told it, else ours.
        local _, theirs = self:SplitName(w.full or "")
        local r = theirs or self:RealmName()
        if r == "" then return end
        alt = plain .. "-" .. r
    end
    lastWhisper[key] = { msg = w.msg, to = alt, full = w.full, at = GetTime(), retried = true }
    Enqueue("WHISPER", alt, w.msg)
end

-- A whisper back from someone we just whispered: the form we used reached
-- them, so it's the one to use from now on.
function MF:ConfirmWhisperForm(sender)
    local key = WhisperKey(sender)
    local w = lastWhisper[key]
    if not w or GetTime() - w.at > 60 or w.failed or not self.db then return end
    self.db.whisperRealm = select(2, self:SplitName(w.to)) ~= nil
    lastWhisper[key] = nil
end

function MF:IsAddonWhisperError(text)
    if type(text) ~= "string" then return false end
    local template = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
    local pattern = "^" .. template:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        :gsub("%%%%s", "(.-)") .. "$"
    local missing = text:match(pattern)
    if not missing then return false end
    local key = WhisperKey(missing)
    local now = GetTime()
    for name, at in pairs(whispered) do
        if now - at > NOT_FOUND_WINDOW then
            whispered[name] = nil
        end
    end
    if whispered[key] == nil then return false end
    -- The game asks this once for every chat window showing the error, so
    -- one error must only be counted and acted on once.
    if lastError == text and now - lastErrorAt < 1 then return true end
    lastError, lastErrorAt = text, now
    -- Hidden from chat, but counted: a whisper the server couldn't deliver
    -- is the first thing to rule out when nobody answers.
    MF.whispersNotFound = (MF.whispersNotFound or 0) + 1
    MF.lastNotFound = missing
    MF:RetryWhisperForm(key)
    return true
end

-- The channel's own notices. The channel is taken out of the chat window once the join is
-- confirmed, but on Forever the server often turns the first join down at login
-- (NOT_ALLOWED_IN_CHANNEL, INVALID_NAME) and those answers arrive while the window still
-- lists it: "[10. TheFishingLog] That operation is not permitted in this channel." A later
-- try goes through, so the answer is kept for /tfl diag instead of shown. YOU_LEFT is let
-- through: the chat window needs it to forget the channel, and leaving is yours to see.
function MF:IsDiscoveryChannelNotice(notice, prefixed, base)
    if notice == "YOU_LEFT" then return false end
    local name = type(base) == "string" and base ~= "" and base
        or (type(prefixed) == "string" and prefixed:gsub("^%d+%.%s*", "")) or ""
    if not self:IsOurChannelName(name) then return false end
    if notice == "WRONG_PASSWORD" or notice == "BANNED" then self:ChannelLocked(name, notice) end
    if name:lower() ~= tostring(self.CHANNEL):lower() then return true end -- one of our other names: hidden, nothing to record
    if notice ~= "YOU_JOINED" and notice ~= "YOU_CHANGED" then
        local state = self.discoveryJoin
        if state and not JoinedID(self) then state.error = "the server answered " .. tostring(notice) end
        MF.lastChannelNotice = tostring(notice)
    end
    return true
end

MF:On("TFL_INIT", function()
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, text)
            return MF:IsAddonWhisperError(text)
        end)
        local function Notice(_, _, notice, _, _, prefixed, _, _, _, _, base)
            return MF:IsDiscoveryChannelNotice(notice, prefixed, base)
        end
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", Notice)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", Notice)
    end
end)

-- Match traffic: the channel AND your group. Receivers drop duplicates.
function MF:Send(...)
    local msg = strjoin(SEP, ...)
    local id, group = self:ChannelID(), GroupDist()
    if id then Enqueue("CHANNEL", id, msg) end
    if group then Enqueue(group, nil, msg) end
    self:Debug("send " .. msg:sub(1, 120) .. ((id or group) and "" or " (nowhere to send!)"))
end

-- Guild chat only (guild-only noticeboard events).
function MF:SendGuild(...)
    local msg = strjoin(SEP, ...)
    Enqueue("GUILD", nil, msg)
    self:Debug("send(guild) " .. msg:sub(1, 120))
end

-- One player only (tooltip lookups). Works without the channel.
function MF:Whisper(target, ...)
    local msg = strjoin(SEP, ...)
    local to = self:WhisperName(target)
    if not to or to == "" then return end
    if to:find(" ", 1, true) then
        lastWhisper[WhisperKey(to)] = { msg = msg, to = to, full = target, at = GetTime() }
    end
    Enqueue("WHISPER", to, msg)
    self:Debug("whisper " .. self:ShortName(target) .. ": " .. msg:sub(1, 120))
end

-- Realm-wide traffic (records, bounty, backups): the channel, else your group.
function MF:SendChannel(...)
    local msg = strjoin(SEP, ...)
    local id, group = self:ChannelID(), GroupDist()
    if id then
        Enqueue("CHANNEL", id, msg)
    elseif group then
        Enqueue(group, nil, msg)
    end
    self:Debug("send(ch) " .. msg:sub(1, 120))
end

-- Records and the census go to your guild as well as the channel. Forever's
-- Updated and Classic experiences don't appear to share one, so guildmates
-- on the other side of that line would never see each other's records.
-- Handlers ignore what they already have, so the second copy costs nothing.
function MF:SendWide(...)
    self:SendChannel(...) -- the channel, or the group when there's no channel
    local msg = strjoin(SEP, ...)
    if IsInGuild() then Enqueue("GUILD", nil, msg) end
    -- And the group as well, not only as a fallback: a channel that's joined
    -- but silent would otherwise leave two anglers in the same party unable
    -- to hear each other.
    local group = GroupDist()
    if group and self:ChannelID() then Enqueue(group, nil, msg) end
end

-- Send down one named road, for the road test. Returns false if that road
-- isn't available to us at all (no channel, not in a group, no guild).
function MF:SendVia(road, ...)
    local msg = strjoin(SEP, ...)
    if road == "CHANNEL" then
        local id = self:ChannelID()
        if not id then return false end
        Enqueue("CHANNEL", id, msg)
    elseif road == "GUILD" then
        if not IsInGuild() then return false end
        Enqueue("GUILD", nil, msg)
    elseif road == "PARTY" or road == "RAID" then
        if GroupDist() ~= road then return false end
        Enqueue(road, nil, msg)
    else
        Enqueue(road, nil, msg)
    end
    return true
end

------------------------------------------------------------------------
-- Replying to requests
--
-- A request on the channel reaches everyone, so replies are staggered by a
-- random delay to avoid a burst. ReplyOnce is for requests only one player
-- needs to answer: whoever's timer fires first answers, and everyone who
-- sees that answer (MarkAnswered) stays quiet.
------------------------------------------------------------------------

local answered = {} -- topic -> GetTime() it was last answered

function MF:ReplySoon(minDelay, spread, send)
    local generation=self.dataGeneration
    C_Timer.After(minDelay + math.random() * spread,function()
        if generation==self.dataGeneration then send() end
    end)
end

function MF:MarkAnswered(topic)
    answered[topic] = GetTime()
end

function MF:ReplyOnce(topic, minDelay, spread, send)
    local asked = GetTime()
    self:ReplySoon(minDelay, spread, function()
        if (answered[topic] or 0) >= asked then return end -- someone beat us to it
        answered[topic] = GetTime()
        send()
    end)
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------

local partial = {}   -- sender#id -> { n, got, parts, at, lastAt }
local finished = {}  -- sender#id -> GetTime(), so channel+group copies run once

function MF:CommunicationStatus()
    return ("%d packets queued; %d transfers receiving; %d completed; %d expired; %d dropped from other worlds"):format(
        #queue, self.Count(partial), self.transfersCompleted or 0, self.transfersExpired or 0, self.otherWorldsHeard or 0)
end

function MF:SyncTransfersPending()
    for _, item in ipairs(queue) do if item.transfer then return true end end
    -- An out-of-order first chunk can arrive later; do not close an active
    -- report while an unidentified FishingLog transfer is still arriving.
    for _, buf in pairs(partial) do if buf.syncKind or not buf.kindKnown then return true end end
    return false
end

local function Dispatch(self, sender, text)
    local envelope,epoch,world,body=strsplit(SEP,text,4)
    if GetServerTime()>=self.FRESH_START then
        if envelope~="LIVE2" or tonumber(epoch)~=self.FRESH_START or not body then return end
        -- Another region or rule set (World.lua): not ours to hear. Counted for /tfl diag.
        if world~=(self.worldCode or "?") then self.otherWorldsHeard=(self.otherWorldsHeard or 0)+1 return end
        text=body
    elseif envelope=="LIVE1" or envelope=="LIVE2" then return end
    self:NoteSeen(sender)
    local fields = { strsplit(SEP, text) }
    local kind = table.remove(fields, 1)
    -- Handlers take fields, not plumbing; the road a message came down is
    -- only of interest to the road test, which reads it here.
    local handler = handlers[kind]
    self:Debug("recv " .. self:ShortName(sender) .. ": " .. text:sub(1, 120))
    if handler then
        -- What arrives was written by another client, which may be older,
        -- newer or simply broken. A message it got wrong is dropped and
        -- counted for /tfl diag, rather than raising a Lua error on ours.
        local context = self.SyncMessageBegin and self:SyncMessageBegin(sender, self.lastRoad, kind, fields)
        local previous = self.syncReceiveContext
        self.syncReceiveContext = context
        local ok, err = pcall(handler, self, sender, unpack(fields))
        self.syncReceiveContext = previous
        if context then self:SyncMessageEnd(context, ok) end
        if not ok then
            self.handlerErrors = (self.handlerErrors or 0) + 1
            self.lastHandlerError = tostring(kind) .. ": " .. tostring(err):sub(1, 160)
            if self.db and self.db.debug and self.ReportError then self.ReportError(err) end
        end
    end
end

local function Reassemble(self, sender, rest)
    local id, i, n, part = strsplit(SEP, rest or "", 4)
    local key = sender .. "#" .. tostring(id)
    i, n = tonumber(i), tonumber(n)
    if not id or not id:match("^%d+$") or #id>4 or not i or not n
        or i~=math.floor(i) or n~=math.floor(n) or n<1 or n>MAX_PARTS
        or i<1 or i>n or type(part)~="string" or #part>CHUNK_LEN or finished[key] then return end
    local buf = partial[key]
    if buf and buf.n~=n then return end
    if not buf then
        if self.Count(partial)>=MAX_PARTIAL then return end
        buf = { n = n, got = 0, parts = {}, at = GetTime(), lastAt = GetTime(), sender=sender, road=self.lastRoad }
        partial[key] = buf
    end
    if not buf.parts[i] then
        buf.parts[i] = part or ""
        buf.got = buf.got + 1
        -- Refresh only on progress. Duplicate fragments must not keep an
        -- abandoned transfer alive. A throttled map sync can exceed 120s.
        buf.lastAt = GetTime()
        if i == 1 and self.IsSyncKind then
            local first, epoch, world, body = strsplit(SEP, part, 4)
            buf.kindKnown = true
            if GetServerTime() >= self.FRESH_START then
                first = first == "LIVE2" and tonumber(epoch) == self.FRESH_START and world == (self.worldCode or "?")
                    and body and body:match("^([^~]+)")
            elseif first == "LIVE1" or first == "LIVE2" then first = nil end
            if first and self:IsSyncKind(first) then buf.syncKind, buf.sender, buf.road = first, sender, self.lastRoad end
        end
        if buf.syncKind then self:SyncPacketStarted(sender, self.lastRoad, "in", buf.syncKind) end
    end
    if buf.got == buf.n then
        partial[key] = nil
        finished[key] = GetTime()
        self.transfersCompleted = (self.transfersCompleted or 0) + 1
        Dispatch(self, sender, table.concat(buf.parts))
    end
end

-- What arrives, and by which road. When two anglers can't see each other's
-- records this is the question that settles it: a channel that's joined but
-- silent looks exactly like one that works.
MF.heard = {}

MF:On("CHAT_MSG_ADDON", function(self, prefix, text, dist, sender)
    if prefix ~= self.PREFIX or not self.me then return end
    if type(text)~="string" or #text>MAX_LEN or type(sender)~="string" or sender=="" then return end
    self.heard[dist or "?"] = (self.heard[dist or "?"] or 0) + 1
    self.lastRoad = dist
    -- Some chat types deliver the name without the realm.
    sender = self:FullName(sender)
    if self:IsMe(sender) then return end
    if dist == "WHISPER" then self:ConfirmWhisperForm(sender) end
    -- Whatever they were telling us, we now know they're out there.

    local kind, rest = strsplit(SEP, text, 2)
    if kind == "P" then
        Reassemble(self, sender, rest)
    else
        Dispatch(self, sender, text)
    end
end)

function MF:ResetCommunicationState()
    queue,whispered,answered,partial,finished={},{},{},{},{}
    self.heard={}
    self.transfersCompleted, self.transfersExpired = 0, 0
    if self.ResetSyncActivity then self:ResetSyncActivity() end
end

-- Forget reassembly state that's old enough not to matter: finished
-- messages can't arrive again, and half-received ones lost a part.
local sincePrune = 0
MF:OnTick(function()
    sincePrune = sincePrune + 1
    if sincePrune < PRUNE_EVERY then return end
    sincePrune = 0
    local cutoff = GetTime() - CACHE_LIFETIME
    for key, at in pairs(finished) do
        if at < cutoff then finished[key] = nil end
    end
    for key, buf in pairs(partial) do
        if buf.lastAt < cutoff or GetTime() - buf.at > MAX_TRANSFER_AGE then
            partial[key] = nil
            MF.transfersExpired = (MF.transfersExpired or 0) + 1
            if buf.syncKind then MF:SyncTransferFailed(buf.sender, buf.road, buf.syncKind)
            elseif not buf.kindKnown and MF.SyncUnknownTransferFailed then MF:SyncUnknownTransferFailed(buf.sender) end
        end
    end
    for topic, at in pairs(answered) do
        if at < cutoff then answered[topic] = nil end
    end
end)
