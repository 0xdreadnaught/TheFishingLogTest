-- No game or network use: exercise the real record and transport handlers.
local source=arg[1] or ""
local now=100
unpack=table.unpack
GetTime=function() return now end
GetServerTime=function() return 1800000000+math.floor(now) end
strjoin=function(sep,...) local out={...};for i=1,#out do out[i]=tostring(out[i]) end;return table.concat(out,sep) end
strsplit=function(sep,text,limit)
    local out,start={},1
    while not limit or #out<limit-1 do
        local at=text:find(sep,start,true);if not at then break end
        out[#out+1]=text:sub(start,at-1);start=at+#sep
    end
    out[#out+1]=text:sub(start);return table.unpack(out)
end
IsInGuild=function() return false end
IsInRaid=function() return false end
IsInGroup=function() return false end
GetChannelName=function() return 0 end
Enum={SendAddonMessageResult={AddonMessageThrottle=3}}
local delayed,pumps={},{}
C_Timer={After=function(_,fn) delayed[#delayed+1]=fn end,NewTicker=function(_,fn) pumps[#pumps+1]=fn end}
local function flush() local jobs=delayed;delayed={};for _,fn in ipairs(jobs) do fn() end end
local function Client(name,records,recordSource)
    local c={me=name,handlers={},listeners={},ticks={},out={},FRESH_START=1,dataGeneration=1,CUSTOM_CHANNEL_SUPPORTED=false,
        db={spots={},settings={channel=false},anglersSeen={}},cdb={profile={xp=1}},syncDiagnostics={records=0,bounties=0,pools=0}}
    function c:On(e,fn) self.listeners[e]=self.listeners[e] or {};table.insert(self.listeners[e],fn) end
    function c:OnTick(fn) self.ticks[#self.ticks+1]=fn end
    function c:Fire(e,...) for _,fn in ipairs(self.listeners[e] or {}) do fn(self,...) end end
    function c:Command() end
    function c:Debug() end
    function c:Print() end
    function c:PrintChat() end
    function c:AnglerKey(n) return (n or ""):lower():gsub("[%s%-]","") end
    function c:IsMe(n) return self:AnglerKey(n)==self:AnglerKey(self.me) end
    function c:SameAngler(a,b) return self:AnglerKey(a)==self:AnglerKey(b) end
    function c:ShortName(n) return n end
    function c:FullName(n) return n end
    function c:WhisperName(n) return n end
    function c:SplitName(n) return n end
    function c:RealmName() return "Test" end
    function c:Whisper(to,...) self.out[#self.out+1]={to=to,args={...}} end
    function c:SendWide(...) self.out[#self.out+1]={args={...},unrouted=true} end
    function c:NoteSeen() end
    function c:NoteCensusReply() end
    function c:NoteProgression() end
    function c:RequestQuietBounties() end
    function c:NoteNearbyPeer() end
    function c:NearbyPeerMap() return 1 end
    function c:TotalFishCaught() return 1 end
    function c:Version() return "1.1.4" end
    function c:ShareCurrentBounties() end
    function c:ShareNotices() end
    function c:MarkAnswered() end
    function c:RefreshJournal() end
    function c:NoteFaction() end
    function c:FactionOf() return "H" end
    function c:NoteSpotLabelEvidence() end
    function c:CanonicalKey(k) return k end
    function c:IsSpotKey(k) return type(k)=="string" and k:match("^a%d+$") end
    function c:SpotMapFits() return true end
    function c:ForgetNamelessLow() end
    function c:SeasonID() return 1 end
    function c:MaxWeight() return 100000 end
    function c:IsKnownJunk() return false end
    function c:AnglerCounts() return true end
    function c:SpotLabelProblem() return false end
    function c:SpotRecordMap() return 1 end
    function c:SpotPosition() end
    function c:SpotNameForWire(k) return k end
    function c:RememberSpotName() end
    function c:EncodeWeight(w) return tostring(w) end
    function c:DecodeWeight(w) return tonumber(w) end
    function c:Pack36(n)
        n=math.floor(n);local s="";local alphabet="0123456789abcdefghijklmnopqrstuvwxyz"
        repeat local d=n%36;s=alphabet:sub(d+1,d+1)..s;n=math.floor(n/36) until n==0
        return s
    end
    function c:Unpack36(s) return tonumber(s,36) or 0 end
    function c:Hash(s) local h=0;for i=1,#s do h=(h*31+s:byte(i))%1000000007 end;return h end
    function c:VersionNewer(a,b) return a>b end
    function c:RecentCensusPlayers() return {} end
    function c:ReplySoon(_,_,fn) delayed[#delayed+1]=fn end
    function c.Count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
    function c.Hundredths(n) return math.floor(n*100+0.5) end
    if records then assert(loadfile((recordSource or source).."Records.lua"))("TheFishingLogTest",c) end
    return c
end
return { Client=Client, setTime=function(t) now=t end, advance=function(t) now=now+t end,
    flush=flush, clear=function() delayed={} end, pump=function() return pumps[#pumps] end }