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
local failures=0
local function test(label,fn)
    delayed={};local ok,err=pcall(fn)
    if ok then print("PASS: "..label) else failures=failures+1;print("FAIL: "..label..": "..tostring(err)) end
end
local function countRecords(c)
    local n=0;for _,s in pairs(c.db.spots) do n=n+c.Count(s.fish) end;return n
end
local function seed(c,n,owner)
    for i=1,n do
        c:MergeRecord("a"..math.ceil(i/40),1,1000+i,i+1,owner,1800000000,false)
    end
end
local function deliverBooks(sender,recipient)
    local packets,records=0,0
    for _,m in ipairs(sender.out) do
        local kind=m.args[1]
        if m.to==recipient.me and (kind=="RBOOK" or kind=="RBOOK2") then
            packets=packets+1
            if kind=="RBOOK" then for _ in m.args[2]:gmatch("[^;]+") do records=records+1 end
            else for block in m.args[3]:gmatch("[^;]+") do for _ in block:gmatch("|") do records=records+1 end end end
            recipient.lastRoad="WHISPER"
            recipient.handlers[kind](recipient,sender.me,table.unpack(m.args,2))
        end
    end
    sender.out={}
    return packets,records
end

test("whisper-only peers receive corrective follow-ups",function()
    local c=Client("Local",true);seed(c,1,"Local")
    c.lastRoad="WHISPER"
    c.handlers.RBOOK(c,"Peer","a2,1002,2,Peer,1800000000,0,1,a2,0,0,H")
    flush()
    assert(#c.out==1 and c.out[1].to=="Peer" and not c.out[1].unrouted,"top-up went to unavailable broadcast routes")
end)

for _,compact in ipairs({false,true}) do
test("bounded books eventually relay every third-party record ("..(compact and "compact" or "legacy")..")",function()
    local a,b=Client("Sender",true),Client("Receiver",true)
    seed(a,240,"Offline Angler")
    if compact then a.db.anglersSeen[a:AnglerKey(b.me)]={version="1.1.4"} end
    for i=1,6 do
        now=now+901
        a.handlers.RASK(a,b.me,"ACK1",1,1,1,"1.1.4")
        local n,size=deliverBooks(a,b)
        assert(n==1 and size<=80,"book must preserve the 80-record traffic limit")
        delayed={}
    end
    assert(countRecords(b)==240,"only "..countRecords(b).." of 240 records relayed")
end)
end

test("whisper handshake includes existing tally protocol",function()
    local c=Client("Sender",true);seed(c,4,"Other")
    c.handlers.RASK(c,"Peer","ACK1",1,1,1,"1.1.4")
    for _,m in ipairs(c.out) do if m.to=="Peer" and m.args[1]=="RTALLY" then return end end
    error("no directed tally was sent")
end)

test("per-peer rotation reaches legacy receivers while preserving own-record priority and cooldowns",function()
    local a=Client("Sender",true)
    local legacy="tests/legacy-1.1.4/"
    local b,c=Client("Receiver",true,legacy),Client("Another",true,legacy)
    seed(a,240,"Offline Angler")
    for i=1,160 do a:MergeRecord("a100",1,2000+i,i+1,a.me,1800000000,false) end
    a.db.anglersSeen[a:AnglerKey(c.me)]={version="1.1.4"}
    for round=1,24 do
        now=now+121
        for _,peer in ipairs({b,c}) do
            a.handlers.RASK(a,peer.me,"ACK1",1,1,1,"1.1.4")
            local packets,size=deliverBooks(a,peer)
            assert(packets==1 and size<=80)
            if round==1 then
                assert(peer.db.spots.a100 and peer.Count(peer.db.spots.a100.fish)>=36,"own records lost priority")
            end
            -- Repeated requests must not produce another book in the cooldown.
            a.handlers.RASK(a,peer.me,"ACK1",1,1,1,"1.1.4")
            assert(deliverBooks(a,peer)==0)
            delayed={}
        end
    end
    assert(countRecords(b)==400 and countRecords(c)==400,"each peer needs independent progress")
end)

test("multipart transfers stay alive while new parts arrive beyond two minutes",function()
    local c=Client("Receiver",false)
    assert(loadfile(source.."Comm.lua"))("TheFishingLogTest",c)
    local got
    c.handlers.TEST=function(_,_,body) got=body end
    local body=("abcd"):rep(10000)
    local payload="LIVE2~1~?~TEST~"..body
    local n=math.ceil(#payload/220)
    for i=1,n do
        now=now+1
        c:Fire("CHAT_MSG_ADDON","FishingLogTest",strjoin("~","P",1,i,n,payload:sub((i-1)*220+1,i*220)),"WHISPER","Sender")
        for _,fn in ipairs(c.ticks) do fn(c) end
    end
    assert(got==body,"active multipart message was discarded before its final part")
end)

test("duplicate fragments do not keep abandoned transfers alive",function()
    local c=Client("Receiver",false)
    assert(loadfile(source.."Comm.lua"))("TheFishingLogTest",c)
    local got=false;c.handlers.TEST=function() got=true end
    local prefix="LIVE2~1~?~TEST~"
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~2~1~2~"..prefix,"WHISPER","Sender")
    for i=1,240 do
        now=now+1
        c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~2~1~2~"..prefix,"WHISPER","Sender")
        for _,fn in ipairs(c.ticks) do fn(c) end
    end
    -- After an idle-expiry a repeated first fragment could start a new buffer.
    -- Stop sending it and let that second buffer expire too.
    for i=1,240 do now=now+1;for _,fn in ipairs(c.ticks) do fn(c) end end
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~2~2~2~tail","WHISPER","Sender")
    assert(not got)
end)

test("out-of-order and duplicate chunks dispatch exactly once",function()
    local c=Client("Receiver",false)
    assert(loadfile(source.."Comm.lua"))("TheFishingLogTest",c)
    local got,count=nil,0;c.handlers.TEST=function(_,_,body) got=body;count=count+1 end
    local body=("payload"):rep(100)
    local payload="LIVE2~1~?~TEST~"..body
    local n=math.ceil(#payload/220)
    assert(n==4)
    for _,i in ipairs({4,2,2,1,3,1,2,3,4}) do
        c:Fire("CHAT_MSG_ADDON","FishingLogTest",strjoin("~","P",3,i,n,payload:sub((i-1)*220+1,i*220)),"WHISPER","Sender")
    end
    assert(count==1 and got==body)
end)

test("continuous slow transfers still have a hard lifetime bound",function()
    local c=Client("Receiver",false)
    assert(loadfile(source.."Comm.lua"))("TheFishingLogTest",c)
    local got=false;c.handlers.TEST=function() got=true end
    for i=1,70 do
        for second=1,30 do now=now+1;for _,fn in ipairs(c.ticks) do fn(c) end end
        c:Fire("CHAT_MSG_ADDON","FishingLogTest",strjoin("~","P",4,i,70,i==1 and "LIVE2~1~?~TEST~" or "x"),"WHISPER","Sender")
    end
    assert(not got and c.transfersExpired>0)
end)

if failures>0 then error(failures.." sync regression(s)") end
print("All fishing sync regressions passed")
