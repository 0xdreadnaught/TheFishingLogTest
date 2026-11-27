-- Actual Comm/Records/SyncLog modules, with no game or network access.
local F = assert(loadfile("tests/fishing-sync-fixture.lua"))()
local source = ""
local failures = 0
local combat, sendResult = false, 0
local wire = {}
SOUNDKIT = {TELL_MESSAGE=3081}
InCombatLockdown = function() return combat end
date = os.date
C_ChatInfo = {
    RegisterAddonMessagePrefix=function() end,
    SendAddonMessage=function(_,msg,road,to) wire[#wire+1]={msg=msg,road=road,to=to};return sendResult end
}
local function Client()
    F.setTime(100); F.clear(); combat=false; sendResult=0;wire={}
    local c=F.Client("Local",false)
    c.toasts,c.opened={},{}
    function c:Toast(...) self.toasts[#self.toasts+1]={...} end
    function c:OpenSyncReport(report) self.opened[#self.opened+1]=report end
    function c:SpotName(key) return "Water "..tostring(key) end
    function c:ZoneNameFor(map) return "Zone "..tostring(map) end
    function c:FishName(id) return "Fish "..tostring(id) end
    function c:Weight(w) return tostring(w).." lb" end
    assert(loadfile(source.."Comm.lua"))("TheFishingLogTest",c)
    c.pruneTransfers=c.ticks[#c.ticks]
    c.listeners.TFL_INIT[1](c)
    local pump=F.pump()
    assert(loadfile(source.."SyncLog.lua"))("TheFishingLogTest",c)
    assert(loadfile(source.."Records.lua"))("TheFishingLogTest",c)
    c.gapsSent=0
    return c,pump
end
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then print("PASS: "..name) else failures=failures+1;print("FAIL: "..name..": "..tostring(err)) end
end
local function receive(c,peer,payload)
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","LIVE2~1~?~"..payload,"WHISPER",peer)
end
local function entry(key,id,weight,holder)
    return table.concat({key,id,weight,holder,1800000000,0,1,key,0,0,"H"},",")
end
local function book(c,peer,text) receive(c,peer,"RBOOK~"..text) end
local function finish(c,seconds) F.advance(seconds or 21);c:SyncReportTick() end
local function drain(c,pump)
    local limit=0
    while c:SyncTransfersPending() and limit<2000 do F.advance(1);pump();limit=limit+1 end
    assert(limit<2000,"send queue did not drain")
end

test("one clickable start toast and ding; acknowledgement is not a completed book",function()
    local c,pump=Client()
    c:Whisper("Peer","RASK","ACK1",1,1,1,"1.1.4")
    assert(not c:ActiveSyncReport() and #c.toasts==0,"a queued request is not sent")
    pump()
    assert(#c.toasts==1 and c.toasts[1][2]=="SYNC STARTED" and c.toasts[1][8]==3081)
    local report=c:ActiveSyncReport()
    c.toasts[1][9].onClick();assert(c.opened[1]==report)
    receive(c,"Peer","RACK1~1~2~3~1.1.4")
    finish(c)
    assert(c:ActiveSyncReport()==report,"acknowledgement prematurely completed the sync")
    book(c,"Peer",entry("a1",1001,12,"Holder"))
    assert(#c.toasts==1,"book created another start alert")
    finish(c)
    assert(not c:ActiveSyncReport() and c:SyncHistory()[1]==report and c.opened[2]==report)
    assert(report.state=="Finished" and report.peers.peer.new==1 and report.peers.peer.received.records==1)
    assert(report.peers.peer.requests.outgoing.records==1 and report.peers.peer.acknowledgements==1)
end)

test("report distinguishes new, upgraded and unchanged records and names the source and water",function()
    local c=Client()
    c:MergeRecord("a1",1,1001,5,"Older Holder",1800000000,false)
    book(c,"Relay",entry("a1",1001,12,"Better Holder")..";"..entry("a1",1002,8,"New Holder"))
    book(c,"Relay",entry("a1",1001,12,"Better Holder"))
    local r=c:ActiveSyncReport(); local p=r.peers.relay
    assert(p.new==1 and p.updated==1 and p.received.records==3)
    assert(#r.changes==2 and r.changes[1].from=="Relay" and r.changes[1].holder=="Better Holder")
    assert(r.changes[1].previous==5 and r.changes[1].spot=="Water a1")
    assert(p.places.incoming["records: Water a1"]==3)
    local text=c:SyncReportText(r)
    assert(text:find("Older Holder",1,true) and text:find("Better Holder",1,true) and text:find("Relay",1,true))
    assert(c.syncReceiveContext==nil,"receive context leaked out of dispatch")
    c:MergeRecord("a1",1,1003,10,"Local",1800000000,false)
    assert(#r.changes==2,"local catches must not be attributed to a sync peer")
end)

test("overlapping peers share a batch, with separate incoming and outgoing destinations",function()
    local c,pump=Client()
    book(c,"Alice",entry("a1",1001,4,"Holder"))
    book(c,"Bob",entry("a2",1002,5,"Other"))
    c:Whisper("Bob","RBOOK",entry("a1",1001,4,"Holder"));pump()
    local r=c:ActiveSyncReport()
    assert(#c.toasts==1 and #r.order==2)
    assert(r.peers.alice.sent.records==nil and r.peers.bob.sent.records==1)
    assert(r.peers.bob.places.outgoing["records: Water a1"]==1)
    assert(c:SyncReportText(r):find("Receipt unconfirmed",1,true))
end)

test("season-only changes compare the previous season record rather than the all-time winner",function()
    local c=Client()
    c:MergeRecord("a1",1,1001,30,"All-time",1800000000,false)
    c.db.spots.a1.season[1001]={w=5,h="Season holder",t=1800000000}
    book(c,"Peer",entry("a1",1001,12,"New season holder"))
    local r=c:ActiveSyncReport();local change=r.changes[1]
    assert(r.peers.peer.seasonal==1 and r.peers.peer.updated==0)
    assert(change.kind=="Season" and change.previous==5 and change.previousHolder=="Season holder")
end)

test("compact books report the decoded water and actual changes in both directions",function()
    local c,pump=Client()
    local hash=c:Pack36(c:Hash(c:AnglerKey("Holder")))
    local names=hash..",Holder,H"
    local spots="a1,1,a1,0,0|"..c:Pack36(1001)..",9,"..hash..","..c:Pack36(100000000)..",0"
    receive(c,"Peer","RBOOK2~"..names.."~"..spots)
    c:Whisper("Peer","RBOOK2",names,spots);pump()
    local p=c:ActiveSyncReport().peers.peer
    assert(p.new==1 and p.received.records==1 and p.sent.records==1)
    assert(p.places.incoming["records: Water a1"]==1 and p.places.outgoing["records: Water a1"]==1)
end)

test("multipart outgoing counts once after its last packet, never as confirmed delivery",function()
    local c,pump=Client()
    local entries={};for i=1,50 do entries[#entries+1]=entry("a1",1000+i,i,"Holder") end
    c:Whisper("Receiver","RBOOK",table.concat(entries,";"));pump()
    local r=c:ActiveSyncReport()
    assert(r and not r.peers.receiver.sent.records and c:SyncTransfersPending())
    finish(c,30);assert(c:ActiveSyncReport()==r,"completed while send queue was blocked")
    drain(c,pump)
    assert(r.peers.receiver.sent.records==50)
    finish(c)
    assert(r.peers.receiver.state=="No reply" and r.state=="Partial")
end)

test("out-of-order incoming parts delay completion and duplicates do not duplicate records",function()
    local c=Client();receive(c,"Peer","RACK1~1~1~1~1.1.4")
    local payload="LIVE2~1~?~RBOOK~"..entry("a1",1001,9,"Holder")
    local parts={payload:sub(1,25),payload:sub(26)}
    local function part(i) c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~1~"..i.."~2~"..parts[i],"WHISPER","Peer") end
    part(2);finish(c)
    assert(c:ActiveSyncReport(),"unidentified first fragment was ignored")
    part(2);part(1);part(1)
    assert(c:ActiveSyncReport().peers.peer.received.records==1)
    finish(c);assert(c:SyncHistory()[1].peers.peer.new==1)
end)

test("expired incoming transfers finish as incomplete",function()
    local c=Client()
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~8~1~2~LIVE2~1~?~RBOOK~a1,1001,9","WHISPER","Peer")
    finish(c,121);assert(c:ActiveSyncReport(),"partial transfer was reported complete")
    for _=1,60 do c.pruneTransfers(c) end
    finish(c)
    local r=c:SyncHistory()[1]
    assert(r and r.state=="Partial" and r.peers.peer.errors==1)
end)

test("server refusal is not counted as sent; throttle retry is not a failure",function()
    local c,pump=Client();sendResult=3
    c:Whisper("Peer","RBOOK",entry("a1",1001,4,"Holder"));pump()
    assert(not c:ActiveSyncReport() and c:SyncTransfersPending())
    sendResult=0;F.advance(1);pump()
    assert(c:ActiveSyncReport().peers.peer.errors==0 and c:ActiveSyncReport().peers.peer.sent.records==1)
    sendResult=2;c:Whisper("Peer","RBOOK",entry("a1",1002,5,"Holder"));F.advance(1);pump()
    assert(c:ActiveSyncReport().peers.peer.errors==1 and c:ActiveSyncReport().peers.peer.sent.records==1)
end)

test("a missing first fragment from a known peer is also reported incomplete",function()
    local c=Client();receive(c,"Peer","RACK1~1~1~1~1.1.4")
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~8~2~2~unknown tail","WHISPER","Peer")
    F.advance(121)
    for _=1,60 do c.pruneTransfers(c) end
    finish(c)
    assert(c:SyncHistory()[1].peers.peer.errors==1 and c:SyncHistory()[1].state=="Partial")
end)

test("no reply and acknowledged-but-empty requests wait 120 seconds and say what is missing",function()
    local c,pump=Client()
    c:Whisper("Silent","RASK");c:Whisper("Empty","RASK");pump()
    receive(c,"Empty","RACK1~1~1~1~1.1.4")
    finish(c,119);assert(c:ActiveSyncReport())
    finish(c,1)
    local r=c:SyncHistory()[1]
    assert(r.peers.silent.state=="No reply" and r.peers.empty.state=="No records received")
end)

test("auto report waits out combat; disabling auto report still saves history",function()
    local c=Client();combat=true
    book(c,"Peer",entry("a1",1001,4,"Holder"));finish(c)
    assert(#c.opened==0 and #c:SyncHistory()==1)
    combat=false;c:SyncReportTick();assert(#c.opened==1)
    c.db.settings.syncReportPopup=false
    book(c,"Peer",entry("a1",1002,4,"Holder"));finish(c)
    assert(#c.opened==1 and #c:SyncHistory()==2)
end)

test("handler errors are marked and restore attribution context",function()
    local c=Client();c.handlers.POBOOK1=function() error("bad packet") end
    receive(c,"Peer","POBOOK1~Pool,1,0.2,0.3,1800000000,w")
    assert(c.handlerErrors==1 and c.syncReceiveContext==nil)
    assert(c:ActiveSyncReport().peers.peer.errors==1)
    finish(c);assert(c:SyncHistory()[1].state=="Partial")
end)

test("history and detail counts are bounded; continued traffic has a maximum lifetime",function()
    local c=Client()
    for i=1,12 do book(c,"Peer",entry("a1",1000+i,4,"Holder"));finish(c) end
    assert(#c:SyncHistory()==10)
    for i=1,190 do book(c,"Peer",entry("a2",2000+i,4,"Holder")) end
    local r=c:ActiveSyncReport()
    assert(#r.changes==160 and r.omitted==30 and r.peers.peer.new==190)
    F.advance(1800);book(c,"Peer",entry("a3",3000,4,"Holder"));c:SyncReportTick()
    assert(not c:ActiveSyncReport() and c:SyncHistory()[1].state=="Partial")
end)

test("ordinary live broadcasts and wrong-generation fragments do not open sync alerts",function()
    local c=Client();c.handlers.FWOBS1=function() end
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","LIVE2~1~?~FWOBS1~1","GUILD","Peer")
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~1~1~2~LIVE2~2~?~RBOOK~a1","WHISPER","Peer")
    c:Fire("CHAT_MSG_ADDON","FishingLogTest","P~2~1~2~RBOOK~a1","WHISPER","Peer")
    assert(#c.toasts==0 and not c:ActiveSyncReport())
end)

if failures>0 then error(failures.." sync report regression(s) failed") end
print("All sync report regressions passed")
