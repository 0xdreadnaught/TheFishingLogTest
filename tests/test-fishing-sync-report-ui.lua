-- Construct the actual report using the existing theme widgets; no computer use.
local F=assert(loadfile("tests/fishing-ui-fixture.lua"))()
local MF=F.MF
function F.methods:SetEnabled(v) self.enabled=v end
wipe=function(t) for k in pairs(t) do t[k]=nil end end
date=os.date
GetServerTime=function() return 1800000000+math.floor(GetTime()) end
SOUNDKIT={TELL_MESSAGE=3081}
function MF:OnTick() end
function MF:Command() end
function MF:Toast(...) self.lastToast={...} end
function MF:IsMe(n) return n==self.me end
function MF:AnglerKey(n) return n:lower() end
function MF:SyncTransfersPending() return false end
function MF:ShowCopyText(title,text) self.copied={title,text} end
function MF:OpenJournal(page) self.journalPage=page end
function MF:Weight(w) return tostring(w).." lb" end
function MF:SpotName(k) return k end
function MF:FishName(id) return tostring(id) end
function MF.Count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
F.load("SyncLog.lua");F.load("Rework/SyncReport.lua")
local function click(b) assert(b.enabled~=false,"disabled control");b.scripts.OnClick(b) end
MF:OpenSyncReport()
local w=MF.Rework.SyncReport
assert(w:IsShown() and w.heading:GetText()=="No activity")
assert(w.copy.enabled==false and w.older.enabled==false and w.newer.enabled==false)
assert(w.list.items[1].title=="No sync activity yet")
for _,b in ipairs({w.copy,w.older,w.newer,w.realm}) do assert(b:GetText()~="","empty report button") end
w:Hide()
local ctx=MF:SyncMessageBegin("Peer","WHISPER","RBOOK",{""})
MF:SyncMessageEnd(ctx,true)
MF.lastToast[9].onClick()
assert(w:IsShown() and w.heading:GetText()=="In progress" and w.page:GetText()=="1 / 1")
assert(w.list.items[1].title=="Peer")
-- Updates preserve scroll; the report follows its object from active to history.
w.list:SetHeight(100)
w.list.scroll,w.list.target=10,10
MF:SyncMessageBegin("Second","WHISPER","RACK1",{})
MF:SyncReportTick()
assert(w.list.items[4].title=="Second" and w.list.scroll==10)
F.setTime(21);MF:SyncReportTick()
assert(w.heading:GetText()=="Finished" and w.page:GetText()=="1 / 1")
click(w.copy)
assert(MF.copied[2]:find("Peer",1,true) and MF.copied[2]:find("Second",1,true))
click(w.realm);assert(MF.journalPage=="realm")
-- Disable auto-open and watch navigation while a second report is in progress.
MF.db.settings.syncReportPopup=false
MF:SyncMessageBegin("New Peer","WHISPER","RACK1",{})
MF:SyncReportTick()
assert(w.page:GetText()=="2 / 2" and w.newer.enabled==true,"history navigation missed a new active report")
click(w.newer)
assert(w.heading:GetText()=="In progress" and w.page:GetText()=="1 / 2")
click(w.older)
assert(w.heading:GetText()=="Finished" and w.page:GetText()=="2 / 2")
w:Hide();MF:SyncReportTick();assert(not w:IsShown(),"progress reopened a dismissed window")
F.setTime(42);MF:SyncReportTick();assert(not w:IsShown(),"disabled auto-open was ignored")
MF:OpenSyncReport();assert(w.list.items[1].title=="New Peer")
print("PASS: report construction, labeled controls, live updates, preserved scroll, copy, Realm, history, dismissal, and auto-open setting")
