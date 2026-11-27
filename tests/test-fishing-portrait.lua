-- Run real portrait/widget/journal code against a small client API mock.
-- Rendering still needs an in-game check; this checks behavior and integration.
local methods, frames, now = {}, {}, 0
local function frame(kind, parent)
    local f = setmetatable({kind=kind,parent=parent,scripts={},points={},regions={},shown=true,children={},calls={}}, {__index=methods})
    if parent then parent.children[#parent.children+1]=f end
    frames[#frames+1]=f
    return f
end
for _, key in ipairs({"SetFrameStrata","SetToplevel","SetClampedToScreen","SetMovable","EnableMouse","EnableMouseWheel",
    "RegisterForDrag","SetShadowOffset","SetJustifyH","SetTextColor","SetFontObject","SetBackdrop","SetBackdropColor",
    "SetBackdropBorderColor","SetColorTexture","SetTexture","SetTexCoord","SetBlendMode","SetVertexColor",
    "SetStatusBarTexture","SetStatusBarColor","SetAutoFocus","SetClipsChildren","SetOrientation","SetValueStep",
    "SetNormalTexture","SetHighlightTexture","SetPushedTexture","SetResizable","SetResizeBounds","SetWordWrap",
    "SetSpacing","SetChecked","SetNormalFontObject","LockHighlight","UnlockHighlight","SetSheathed","SetPosition","SetAllPoints"}) do methods[key]=function() end end
function methods:SetScript(k,fn) self.scripts[k]=fn end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k,fn)
    local old=self.scripts[k]; self.scripts[k]=function(...) if old then old(...) end;fn(...) end
end
function methods:SetPoint(...) self.points[#self.points+1]={...} end
function methods:GetPoint(i) return table.unpack(self.points[i or 1] or {}) end
function methods:ClearAllPoints() self.points={} end
function methods:SetSize(w,h)
    local changed=self.w~=w or self.h~=h;self.w,self.h=w,h
    if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self,w,h) end
end
function methods:SetWidth(w) self.w=w end
function methods:SetHeight(h) self.h=h end
function methods:GetWidth() return self.w or 700 end
function methods:GetHeight() return self.h or 450 end
function methods:GetSize() return self:GetWidth(),self:GetHeight() end
function methods:SetText(t) self.textValue=t end
function methods:GetText() return self.textValue or "" end
function methods:GetStringWidth() return #self:GetText()*6 end
function methods:CreateTexture() local t=frame("Texture",self);self.regions[#self.regions+1]=t;return t end
function methods:CreateFontString() local t=frame("FontString",self);self.regions[#self.regions+1]=t;return t end
function methods:GetRegions() return table.unpack(self.regions) end
function methods:GetNumPoints() return #self.points end
function methods:GetObjectType() return self.kind end
function methods:GetDrawLayer() return "BACKGROUND" end
function methods:SetFrameLevel(v) self.level=v end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetScale(v) self.scale=v end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:SetAlpha(v) self.alpha=v end
function methods:SetMinMaxValues(a,b) self.range={a,b} end
function methods:SetValue(v) self.value=v end
function methods:SetThumbTexture() self.thumb=frame("Texture",self) end
function methods:GetThumbTexture() return self.thumb end
function methods:GetFontString() return self.label end
function methods:SetID(id) self.id=id end
function methods:SetParent(p) self.parent=p end
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:SetRotation(v) self.angle=v end
function methods:SetPortraitZoom(v) self.zoom=v end
function methods:SetCamDistanceScale(v) self.distance=v end
function methods:SetUnit(unit)
    assert(unit=="player");self.calls[#self.calls+1]={"unit",unit}
    self.equipment={[1]="combat hat",[5]="current chest",[16]="current sword",[17]="current shield"}
    return self.unitResult
end
function methods:IsGeoReady() return self.ready~=false end
function methods:TryOn(link,hand)
    self.calls[#self.calls+1]={"try",link,hand}
    if self.failItem then return 1 end
    local slots={hat=1,pole=16,sword=16,shield=17}
    self.equipment[slots[link] or 5]=link
    return 0
end
function methods:UndressSlot(slot) self.calls[#self.calls+1]={"clear",slot};self.equipment[slot]=nil end
CreateFrame=function(kind,name,parent,template)
    local f=frame(kind,parent)
    if template=="UIPanelButtonTemplate" then f.label=f:CreateFontString() end
    return f
end
UIParent=frame("Frame");UISpecialFrames={};tinsert=table.insert;unpack=table.unpack
GetTime=function() return now end
local cursor=0
GetCursorPosition=function() return cursor,0 end
IsMouseButtonDown=function() return true end
issecretvalue=function() return false end
C_Item={GetItemInfoInstant=function(link)
    return 1,"Weapon","Fishing Pole",link=="pole" and "INVTYPE_2HWEAPON" or "INVTYPE_WEAPON",42,2,link=="pole" and 20 or 7
end}
hooksecurefunc=function(object,key,fn)
    local old=object[key];object[key]=function(self,...) old(self,...);fn(self,...) end
end
-- Any accidental real-equipment manipulation is a hard failure.
for _,key in ipairs({"EquipItemByName","PickupInventoryItem","UseInventoryItem","EquipCursorItem","PickupContainerItem"}) do
    _G[key]=function() error("Preview attempted to change real equipment: "..key) end
end
local MF={listeners={},me="Test Angler",cdb={profile={xp=15512},gear={outfit={selected={[1]=true,[5]=false,[16]=true,[17]=true,[8]=true},items={[1]={link="hat"},[5]={link="ignored chest"},[16]={link="pole"},[17]={link="shield"},[8]=false}}}},db={settings={}}}
function MF:On(event,fn) self.listeners[event]=self.listeners[event] or {};table.insert(self.listeners[event],fn) end
function MF:Fire(event,...) for _,fn in ipairs(self.listeners[event] or {}) do fn(self,...) end end
function MF:ShortName(name) return name end
function MF:RealmRank() if not self.unranked then return 1,334 end end
function MF:RankFor() return 2,"Old Hand",19000 end
function MF:Ladder() return {{xp=0},{xp=10000}} end
function MF:OpenFishingOutfit() self.outfitOpened=true end
local function load(name) assert(loadfile(""..name))("TheFishingLogTest",MF) end
load("Rework/Core.lua");MF.Rework.db={sounds=false,animations=false,journalW=900,journalH=500}
load("Rework/Widgets.lua");load("Rework/AnglerPortrait.lua")
local P=MF.Rework.AnglerPortrait
local panel=P:Create(UIParent)
local function update(seconds) now=now+seconds;panel.scripts.OnUpdate(panel,seconds) end
panel:Show();update(0.2)
assert(panel.model.equipment[1]=="hat" and panel.model.equipment[5]=="current chest")
assert(panel.model.equipment[16]=="pole" and panel.model.equipment[17]==nil,"pole must replace both hands in the preview")
assert(panel.caption:GetText()=="Fishing outfit")
-- no world known: the heading falls back to "Realm"; the place sits on the line below
assert(panel.realm:GetText()=="Realm" and panel.realmNote:GetText()=="#1 of 334 anglers · All time",panel.realm:GetText().." / "..panel.realmNote:GetText())
-- world known: the heading is the detected region and rule set
MF.worldKey="US-PvP";function MF:WorldLabel() return "Americas & Oceania, PvP" end
panel:RefreshRank()
assert(panel.realm:GetText()=="Americas & Oceania, PvP" and panel.realmNote:GetText()=="#1 of 334 anglers · All time")
MF.unranked=true;panel:RefreshRank()
assert(panel.realm:GetText()=="Americas & Oceania, PvP" and panel.realmNote:GetText()=="No records here yet")
MF.worldKey="?";panel:RefreshRank();assert(panel.realm:GetText()=="Realm")
MF.unranked=nil;MF.worldKey="US-PvP";panel:RefreshRank()
assert(panel.xp.bar.value==5512 and panel.xp.bar.range[2]==9000)
assert(panel.xp.text:GetText()=="15512 / 19000 XP")
local tries, units=0,0
for _,c in ipairs(panel.model.calls) do
    if c[1]=="try" then tries=tries+1;if c[2]=="pole" then assert(c[3]=="MAINHANDSLOT") end end
    if c[1]=="unit" then units=units+1 end
end
assert(tries==2 and units==1,"only selected saved visual slots should be applied, once")
update(3);assert(#panel.model.calls==5,"unchanged previews should not be rebuilt each tick")
-- Outfit edits update the preview; one-handed sets retain an off hand.
MF.cdb.gear.outfit.items[16]={link="sword"}
update(1);update(0.2)
assert(panel.model.equipment[16]=="sword" and panel.model.equipment[17]=="shield")
local foundOffhand=false
for _,c in ipairs(panel.model.calls) do if c[1]=="try" and c[2]=="shield" then foundOffhand=c[3]=="SECONDARYHANDSLOT" end end
assert(foundOffhand)
-- Equipment events coalesce, and unrelated unit changes do not rebuild self.
panel.dirty=nil;MF:Fire("UNIT_MODEL_CHANGED","target");assert(not panel.dirty)
MF:Fire("PLAYER_EQUIPMENT_CHANGED",5);MF:Fire("PLAYER_EQUIPMENT_CHANGED",16)
update(1);assert(panel.loading);update(0.2);assert(not panel.loading)
-- Selection/empty/absent outfits keep current gear and do not create saved state.
MF.cdb.gear.outfit=nil
update(1);update(0.2)
assert(panel.caption:GetText()=="Current gear" and panel.model.equipment[17]=="current shield")
assert(MF.cdb.gear.outfit==nil)
MF.unranked=true;MF.cdb.profile.xp=15600;update(1)
assert(panel.realm:GetText()=="Americas & Oceania, PvP" and panel.realmNote:GetText()=="No records here yet")
assert(panel.xp.bar.value==5600,"progress refreshes independently of page content")
-- Deferred geometry waits, then times out rather than repeatedly dressing/loading.
panel.model.ready=false;panel:RefreshModel();local count=#panel.model.calls
update(0.2);assert(panel.loading and #panel.model.calls==count)
update(7);assert(not panel.loading and panel.caption:GetText()=="Preview unavailable")
panel.model.ready=true;panel:RefreshModel();update(0.2)
-- Item failures are visible and retried only after a data-ready event.
MF.cdb.gear.outfit={selected={[1]=true},items={[1]={link="hat"}}}
panel.model.failItem=true;panel:RefreshModel();update(0.2)
assert(panel.needsItemData and panel.caption:GetText()=="Some outfit pieces unavailable")
panel.model.failItem=false;MF:Fire("GET_ITEM_INFO_RECEIVED",1,true);update(1);update(0.2)
assert(not panel.needsItemData and panel.model.equipment[1]=="hat")
-- Camera controls are local to the preview; hiding stops dragging/loading.
panel.model.scripts.OnMouseDown(panel.model,"LeftButton");cursor=100;update(0.1)
assert(panel.model.angle>0.12)
panel.model.scripts.OnMouseWheel(panel.model,100);assert(panel.camera.zoom==0.75)
panel.model.scripts.OnMouseWheel(panel.model,-100);assert(panel.camera.zoom==-0.7 and panel.model.distance>1)
panel:Hide();assert(not panel.dragX and not panel.loading)
for _,f in ipairs(frames) do if f.kind=="Button" and f:GetText()=="Outfit" then f.scripts.OnClick(f);break end end
assert(MF.outfitOpened)

-- Build the actual journal with its existing widgets and six bottom tabs.
load("Rework/Journal.lua")
MF.journalWindow=CreateFrame("Frame");MF.journalWindow:Hide()
MF.journalWindow.searchBar={filters={},edit=CreateFrame("EditBox")}
MF.journalWindow.subs={};MF.journalWindow.actions={};MF.journalWindow.scrollHint={}
MF.JOURNAL_TABS={}
for _,key in ipairs({"journal","records","bounty","history","events","realm"}) do
    table.insert(MF.JOURNAL_TABS,{key=key,label=key})
end
for _,setup in ipairs(MF.Rework.setups) do if setup.key=="journal" then setup.fn(MF) end end
local J=MF.Rework.Journal
local win=J:Frame()
assert(win and #win.tabs==6 and win.angler and win.body)
assert(win:GetWidth()==1140 and win:GetHeight()==560,"old saved sizes must leave enough room for the new workspace")
assert(win.body.points[1][2]==win.angler and win.body.points[1][3]=="TOPRIGHT")
assert(win.tabs[1].points[1][2]==win and win.tabs[1].points[1][3]=="BOTTOMLEFT")
for _,width in ipairs({1140,1250,1400}) do
    win:SetSize(width,620)
    local remaining=width-48-win.angler:GetWidth()
    assert(math.abs(remaining-2*win.angler:GetWidth())<=2,"workspace must keep its two-thirds share")
end
-- The page heading and its note are centred as one line under the window title.
local function headingLeft() local p=win.heading.points[1];return p[1],p[2],p[3],p[4],p[5] end
win.heading:SetText("Waters");win.subheading:SetText("")
local point,under,rel,x,y=headingLeft()
assert(#win.heading.points==1 and point=="TOPLEFT" and under==win.drag and rel=="TOP" and y==-32)
assert(x==-18,"a 36-wide heading starts 18 left of centre, got "..tostring(x))
win.subheading:SetText("This zone") -- 54 wide, 10 gap: the pair is 100 wide
assert(select(4,headingLeft())==-50,"heading and note are centred together, got "..tostring(select(4,headingLeft())))
win:SetSize(1250,620);assert(select(4,headingLeft())==-50,"resizing keeps it centred")

-- Bounty page: nothing may be wider than the column it sits in, at any window width.
local pageDef
local realAdd=J.AddPage
J.AddPage=function(self,def) if def.key=="bounty" then pageDef=def end;return realAdd(self,def) end
load("Rework/BountyPage.lua");J.AddPage=realAdd
assert(pageDef,"bounty page did not register")
local page=CreateFrame("Frame");page:SetSize(568,400)
pageDef.build(page,MF)
local B
for _,r in ipairs(frames) do if r.kind=="Frame" and r.title and r.slots then B=r end end
assert(B,"poster not found")
local function posterWidth(w) page:SetSize(w,400);return B:GetWidth() end
assert(posterWidth(568)==300,"narrow page: poster at its minimum, got "..B:GetWidth())
assert(B.title:GetWidth()==260 and 568-300-12>=250,"standings keep at least 250")
assert(B.slots[1].points[1][4]==-90 and B.slots[3].points[1][4]==90,"haul slots stay inside the poster")
assert(posterWidth(718)==359 and posterWidth(1100)==360,"wide page: poster back to its normal width")
assert(B.slots[1].points[1][4]==-104)
print("PASS: page heading centred under the title; bounty poster narrows with the page")

-- Standings rows: no XP on the podium rows, bare counts, a place column that fits the longest
-- place, and a cut after the first 100 with your own row kept.
local P=MF.Rework.BountyPage
local mode="species"
function MF:BountyFormat() return mode end
function MF:BountyScoreText(_,score,_,specimen) return score.." lb"..(specimen and " *" or "") end
function MF:IsMe(name) return name=="Me" end
local function board(n,me)
    local list={}
    for i=1,n do list[i]={name=(i==me and "Me" or "Angler"..i),weight=n-i+1} end
    return list
end
local items,entered,placeW=P:StandingItems("day",board(16))
assert(#items==16 and entered==16 and placeW==36,"a short board keeps the narrow place column")
assert(items[1].scoreText=="16" and items[1].xp==nil,"a count is shown bare and podium rows carry no XP: "..items[1].scoreText)
mode="count";assert(P:StandingItems("day",board(3))[1].scoreText=="3","no x prefix either")
mode="heaviest";assert(P:StandingItems("day",{{name="A",weight=7,specimen=true}})[1].scoreText=="7 lb *","weights keep their unit")
mode="species"
-- ties share a place
items=P:StandingItems("day",{{name="A",weight=9},{name="B",weight=7},{name="C",weight=7},{name="D",weight=6}})
assert(items[2].place==2 and items[3].place==2 and items[4].place==4)
-- 5,000 entered, you are 4,321st: 100 rows, a gap, then you; the column fits "#4321"
items,entered,placeW=P:StandingItems("day",board(5000,4321))
assert(#items==102 and entered==5000,"expected 100 rows, a gap and your row, got "..#items)
assert(items[100].place==100 and items[101].kind=="note" and items[102].e.name=="Me" and items[102].place==4321)
assert(placeW==36,"#4321 still fits the narrow column, got "..placeW)
items,entered,placeW=P:StandingItems("day",board(20000,15000))
assert(items[102].place==15000 and placeW==#"#15000"*6+2,"place column grows to fit the longest place shown, got "..placeW)
-- inside the top 100 you are just one of the rows
items=P:StandingItems("day",board(5000,12));assert(#items==100 and items[12].e.name=="Me")
-- a place in the millions still gets its room, and the name gives way
items,entered,placeW=P:StandingItems("day",{{name="Me",weight=1}});items[1].place=2345678
P.placeW=#"#2345678"*6+2
local row=P.StandingRow();row:SetSize(240,28);row.item=items[1]
P.FillRow(row,items[1])
assert(row.xp==nil and row.place:GetText()=="#2345678" and row.place:GetWidth()==P.placeW)
assert(row.name.points[1][2]==10+P.placeW+4,"the name starts after the place column")
assert(row.name:GetWidth()==240-(10+P.placeW+4)-6-22,"the name takes what is left, got "..row.name:GetWidth())
print("PASS: standings rows - bare counts, no podium XP, place column fits, top 100 plus your row")

-- Frenzies page: the strip's three texts, and a filter row that fits its page.
function MF:FormatClock(s) return ("%d:%02d"):format(math.floor(s/60),s%60) end
local frenzyDef
J.AddPage=function(self,def) if def.key=="frenzies" then frenzyDef=def end;return realAdd(self,def) end
load("Rework/FrenzyPage.lua");J.AddPage=realAdd
assert(frenzyDef,"frenzies page did not register")
local FP=MF.Rework.FrenzyPage
local fpage=CreateFrame("Frame");fpage:SetSize(563,400)
MF.cdb.frenzyPage=nil
frenzyDef.build(fpage,MF)
local function plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end
local unnamed={water={name="Desolace water (59.07, 82.33)"},zone="Desolace",left=131}
local named={water={name="Lake Elune'ara"},zone="Moonglade",left=3725}
local on={water={name="Tirisfal Glades water (61.20, 52.10)"},zone="Tirisfal Glades",active=true,left=95}
-- nothing where you are: the next one anywhere, zone first, no "Water at", no dashes
local count,place,timer,shown=FP.StripText({on,on,unnamed,named})
assert(plain(count)=="2 active" and plain(place)=="Next  Desolace 59.07, 82.33" and plain(timer)=="starts in 2:11",plain(place).." | "..plain(timer))
assert(shown==unnamed and not plain(place):find("[Ww]ater") and not plain(place):find(" %- "))
count,place=FP.StripText({named});assert(plain(place)=="Next  Lake Elune'ara, Moonglade",plain(place))
-- one coming in your zone: the zone is not repeated
unnamed.localZone=true
count,place,timer=FP.StripText({on,unnamed});assert(plain(place)=="Next here  59.07, 82.33",plain(place))
-- standing at one
on.here=true
count,place,timer,shown=FP.StripText({on,unnamed})
assert(plain(place)=="You're at a frenzy water" and plain(timer)=="ends in 1:35" and shown==on,plain(place).." | "..plain(timer))
named.here=true;count,place=FP.StripText({named});assert(plain(place)=="You're at Lake Elune'ara")
count,place,timer,shown=FP.StripText({});assert(plain(count)=="0 active" and timer=="" and shown==nil)
-- the built strip: the place is tied between the count and a fixed-width countdown
local strip=FP.strip
assert(strip.timer:GetWidth()==104 and strip.timer.points[1][2]==strip.remind)
assert(#strip.right.points==2 and strip.right.points[1][2]==strip.left and strip.right.points[2][2]==strip.timer)
-- the filter row never needs more than the page has, down to the narrowest page seen in game
for _,width in ipairs({563,600,728,880,1080}) do
    FP.bar:SetSize(width,26)
    local used=FP:LayoutBar()
    assert(used<=width,("filter row needs %d of %d"):format(used,width))
    assert(FP.search:GetWidth()>=90 and FP.search:GetWidth()<=230)
end
FP.bar:SetSize(1080,26);FP:LayoutBar();assert(FP.when[1]:GetWidth()==90 and FP.search:GetWidth()==230,"full width keeps the original sizes")
print("PASS: frenzy strip wording and slots; filter row fits its page")
print("PASS: fishing outfit preservation, weapon slots, delayed models, refresh events, rank/XP, camera, and journal integration")
