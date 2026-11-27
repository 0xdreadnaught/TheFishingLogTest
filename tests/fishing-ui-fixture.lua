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
    "SetNormalFontObject","LockHighlight","UnlockHighlight","SetSheathed","SetPosition","SetAllPoints"}) do methods[key]=function() end end
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
return { MF=MF, load=load, methods=methods, frames=frames, setTime=function(t) now=t end }