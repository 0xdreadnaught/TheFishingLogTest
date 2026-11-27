-- Bobber highlight: a visual aid, never a bite detector or an input action.
local _, MF = ...
local rows, recordingUntil, lastState = {}, 0, nil
local markedGUID, lastSnapshot, sparkle, probe, driver
local stars, watched, unavailable, borrowed = {}, {}, {}, {}
local bubbles = {}
local castSawBobber, castSawPlate, plateMisses, plateHinted = false, false, 0, false
local MAX_ROWS, INTERVAL = 240, .15
local function Public(value)
    return not (type(issecretvalue)=="function" and issecretvalue(value))
end
local function Read(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    if not ok or not Public(value) then return nil end
    return value
end
local function Text(value)
    if not Public(value) then return "unknown" end
    if type(value)=="string" then return value:gsub("[%c|]"," "):sub(1,160) end
    if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
    return "unknown"
end
local function Recording() return GetTime()<recordingUntil end
local function Trace(text)
    if not Recording() then return end
    rows[#rows+1]=("%.2f %s"):format(GetTime(),text)
    if #rows>MAX_ROWS then table.remove(rows,1) end
end
local function GetVar(name)
    return Read(C_CVar and C_CVar.GetCVar or GetCVar,name)
end
local function SetVar(name,value)
    local fn=C_CVar and C_CVar.SetCVar or SetCVar
    if type(fn)=="function" then pcall(fn,name,value) end
end
-- Not SoftTargetIconGameObject: that only draws the game's interact cog over
-- the bobber, which the highlight doesn't need and players asked about.
local ASSIST={SoftTargetInteract="3",SoftTargetNameplateInteract="1"}
local INTERACT = "SoftTargetInteract"

-- Fishing may take over this setting mid-cast when reeling is enabled.
function MF:TakeBobberInteractRestore(current)
    local entry = borrowed[INTERACT]
    if not entry then return nil end
    borrowed[INTERACT] = nil
    if not next(borrowed) then self.db.bobberCVarRestore = nil end
    if current == entry.written then return entry.previous end
end

-- Restore only values still equal to our last write: respect another owner's change.
local function Assist(wanted)
    if Read(InCombatLockdown)==true then return end
    if wanted then
        for name,value in pairs(ASSIST) do
            local canBorrow = name ~= INTERACT or (not MF.db.softTargetRestore
                and not MF:Yielded("fishing.softInteractAssist"))
            if canBorrow and not borrowed[name] then
                local previous=GetVar(name)
                if type(previous)=="string" and previous~=value then
                    borrowed[name]={previous=previous,written=value}
                    MF.db.bobberCVarRestore=borrowed
                    SetVar(name,value)
                    -- Read it back: a client or another addon that refuses the change shows up here
                    Trace(("assist %s %s -> %s, reads %s"):format(name,Text(previous),value,Text(GetVar(name))))
                end
            end
        end
    else
        for name,saved in pairs(borrowed) do
            if GetVar(name)==saved.written then SetVar(name,saved.previous) end
            Trace(("restore %s, reads %s"):format(name,Text(GetVar(name))))
            borrowed[name]=nil
        end
        if MF.db then MF.db.bobberCVarRestore=nil end
    end
end
local function Plate(unit)
    return Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,unit)
end
local function Snapshot(self)
    local unit="softinteract"
    local guid=Read(UnitGUID,unit)
    local name=Read(UnitName,unit)
    local object=Read(UnitIsGameObject,unit)
    if type(guid)=="string" and guid:match("^GameObject%-") then object=true end
    local tooltip
    if object==true and C_TooltipInfo and type(C_TooltipInfo.GetUnit)=="function" then
        local lines=self:TooltipTextLines(C_TooltipInfo.GetUnit,unit)
        tooltip=lines and lines[1]
    end
    local function BobberName(value)
        return type(value)=="string" and (value=="Fishing Bobber" or value=="Fishing Float")
    end
    local identified=object==true and (BobberName(name) or BobberName(tooltip)
        or (type(guid)=="string" and guid==markedGUID)) or false
    local plate=Plate(unit)
    if not plate then
        for token in pairs(watched) do
            if Read(UnitIsUnit,token,unit)==true then plate=Plate(token) if plate then break end end
        end
    end
    local cursor,atlas
    if object==true and probe and type(SetUnitCursorTexture)=="function" then
        local ok=pcall(SetUnitCursorTexture,probe,unit,nil,true)
        if ok then cursor=Read(probe.GetTexture,probe) atlas=Read(probe.GetAtlas,probe) end
    end
    return {guid=guid,name=name,tooltip=tooltip,object=object,identified=identified,plate=plate,
        interactable=Read(UnitIsInteractable,unit),inRange=Read(UnitIsInInteractRange,unit),
        cursor=cursor,atlas=atlas,casting=self:IsCasting() and true or false}
end
function MF:BobberSample()
    local s=Snapshot(self)
    lastSnapshot=s
    local state=("cast=%s object=%s name=%s tooltip=%s guid=%s bobber=%s plate=%s interact=%s range=%s cursor=%s atlas=%s plateVar=%s")
        :format(Text(s.casting),Text(s.object),Text(s.name),Text(s.tooltip),Text(s.guid),Text(s.identified),
            tostring(s.plate~=nil),Text(s.interactable),Text(s.inRange),Text(s.cursor),Text(s.atlas),
            Text(GetVar("SoftTargetNameplateInteract")))
    if state~=lastState then lastState=state Trace("state "..state) end
    return s
end
local function Hide() if sparkle then sparkle:Hide() end end
local function Draw(self,s)
    if not sparkle or not self.db.settings.bobberHighlight or not s.casting or not s.identified
        or not s.plate or Read(InCombatLockdown)==true then Hide() return end
    if sparkle.plate~=s.plate then
        sparkle:ClearAllPoints()
        sparkle:SetPoint("CENTER",s.plate,"CENTER",0,-36)
        sparkle.plate=s.plate
    end
    local t, moving = GetTime(), not self.db.settings.reducedMotion
    -- Different phases and sizes avoid the old four-corner sparkle box.
    for i,star in ipairs(stars) do
        local phase=moving and ((t*.29+i*.371)%1) or .5
        local angle=(moving and t*.25 or 0)+i*2.39996
        star:ClearAllPoints()
        star:SetPoint("CENTER",sparkle,"CENTER",math.cos(angle)*(17+i*3),math.sin(angle)*(7+i*2))
        star:SetSize(5+9*math.sin(math.pi*phase),5+9*math.sin(math.pi*phase))
        star:SetAlpha(moving and (.82*math.sin(math.pi*phase)^3) or .75)
        star:Show()
    end
    for i,bubble in ipairs(bubbles) do
        local phase=(t*(.23+i*.017)+i*.271)%1
        bubble:ClearAllPoints()
        bubble:SetPoint("CENTER",sparkle,"CENTER",(i-2.5)*10+math.sin(t*.7+i)*3,-7+phase*30)
        bubble:SetSize(3+phase*3,3+phase*3)
        bubble:SetAlpha(.48*math.sin(math.pi*phase))
        bubble:SetShown(moving)
    end
    sparkle:Show()
end
function MF:UpdateBobberHighlight()
    if not self.db then return end
    local casting=self:IsCasting() and true or false
    local highlighting = self.db.settings.bobberHighlight and casting
    if driver then driver:SetShown(Recording() or highlighting or false) end
    local sample
    if Recording() or highlighting then sample = self:BobberSample() end
    -- Once borrowed, keep the settings until the cast ends. Turning them off
    -- as soon as the nameplate appears would make the highlight flicker.
    local needsAssist = highlighting and self.db.settings.bobberAutoAssist
        and (next(borrowed) ~= nil or not (sample.identified and sample.plate))
    Assist(needsAssist)
    if sample then Draw(self,sample) else Hide() end
    if sample and casting then
        if sample.identified then castSawBobber=true end
        if sample.identified and sample.plate then castSawPlate=true end
    end
end
-- The bobber found but never given a nameplate, cast after cast: the highlight has nothing to sit
-- on. Say so once a session, rather than leave the setting looking broken.
local NO_PLATE_CASTS = 3
function MF:NoteBobberCastEnd()
    if castSawPlate then plateMisses=0
    elseif castSawBobber then plateMisses=plateMisses+1 end
    castSawBobber,castSawPlate=false,false
    if plateMisses>=NO_PLATE_CASTS and not plateHinted and self.db.settings.bobberHighlight then
        plateHinted=true
        Trace("hint: no nameplate on the bobber for "..plateMisses.." casts")
        self:Print("Your bobber never gets a nameplate, so the bobber highlight has nothing to show on. "
            .."Something is hiding interact nameplates: check nameplate addons, or try /console SoftTargetNameplateInteract 1. "
            .."/tfl bobber off turns the highlight off.")
    end
end
function MF:BobberHighlightVisible() return sparkle and sparkle:IsShown() or false end
function MF:BobberDiagnosticText()
    self:BobberSample()
    local out={"TFL bobber diagnostics "..self:Version(),
        "Highlight="..tostring(self.db.settings.bobberHighlight==true).." assist="..tostring(self.db.settings.bobberAutoAssist==true)
        .." recording="..tostring(Recording()).." glints="..tostring(self:BobberHighlightVisible()),
        "Soft-target bobber candidate only; ownership and bite timing are not proven. No custom bite sound is enabled.",
        "Polling 0.15s; state changes only; last 240 entries; recording expires after 10 minutes.",
        "Current: "..(lastState or "no sample")}
    for name in pairs(ASSIST) do out[#out+1]=name.."="..Text(GetVar(name)) end
    for _,name in ipairs({"SoftTargetInteractRange","SoftTargetInteractArc","SoftTargetInteractOnlyInRange"}) do out[#out+1]=name.."="..Text(GetVar(name)) end
    out[#out+1]="APIs: object="..type(UnitIsGameObject).." nameplate="..type(C_NamePlate and C_NamePlate.GetNamePlateForUnit).." cursor="..type(SetUnitCursorTexture)
    if #unavailable>0 then out[#out+1]="Unavailable events: "..table.concat(unavailable,", ") end
    out[#out+1]="--- Trace ---"
    for _,line in ipairs(rows) do out[#out+1]=line end
    return table.concat(out,"\n")
end
MF:On("TFL_INIT",function(self)
    -- Recover a borrowed setting after an interrupted session. Never overwrite
    -- a value the player or another addon has since changed.
    if type(self.db.bobberCVarRestore)=="table" then
        for name,saved in pairs(self.db.bobberCVarRestore) do
            if ASSIST[name] and type(saved)=="table" and type(saved.previous)=="string"
                and saved.written==ASSIST[name] then borrowed[name]=saved end
        end
        Assist(false)
    end
    sparkle=CreateFrame("Frame",nil,UIParent)
    sparkle:SetSize(80,64) sparkle:SetFrameStrata("HIGH") sparkle:EnableMouse(false) sparkle:Hide()
    for i=1,3 do
        local star=sparkle:CreateTexture(nil,"OVERLAY") star:SetSize(16,16)
        star:SetTexture("Interface\\Cooldown\\star4") star:SetBlendMode("ADD")
        star:SetVertexColor(1,.87,.38) stars[i]=star
    end
    for i=1,4 do
        local bubble=sparkle:CreateTexture(nil,"OVERLAY")
        bubble:SetTexture("Interface\\AddOns\\" .. MF.ADDON .. "\\Media\\FrenzyBubble.tga")
        bubble:SetBlendMode("ADD") bubble:SetVertexColor(.6,.86,1) bubbles[i]=bubble
    end
    probe=sparkle:CreateTexture(nil,"BACKGROUND") probe:Hide()
    driver=CreateFrame("Frame") driver:Hide()
    local elapsed=0
    driver:SetScript("OnUpdate",function(_,delta)
        elapsed=elapsed+delta
        if elapsed>=INTERVAL then elapsed=0 self:UpdateBobberHighlight()
        elseif lastSnapshot and sparkle:IsShown() then Draw(self,lastSnapshot) end
    end)
end)
MF:On("TFL_FISHING_CAST",function(self) markedGUID=nil lastState=nil castSawBobber,castSawPlate=false,false Trace("TFL_FISHING_CAST") self:UpdateBobberHighlight() end)
MF:On("TFL_FISHING_DONE",function(self) Trace("TFL_FISHING_DONE") markedGUID=nil Hide() self:NoteBobberCastEnd() self:UpdateBobberHighlight() end)
MF:On("PLAYER_REGEN_DISABLED",Hide)
MF:On("PLAYER_REGEN_ENABLED",function(self) self:UpdateBobberHighlight() end)
MF:On("PLAYER_LOGOUT",function() Assist(false) Hide() end)
-- Register optional events defensively: absent client events must not stop loading.
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_SOFT_INTERACT_CHANGED","UPDATE_MOUSEOVER_UNIT","NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_FAILED","LOOT_READY","LOOT_OPENED","LOOT_CLOSED","GLOBAL_MOUSE_DOWN","GLOBAL_MOUSE_UP"}) do
    local valid=not (C_EventUtils and type(C_EventUtils.IsEventValid)=="function")
        or Read(C_EventUtils.IsEventValid,event)==true
    -- A dormant copy (Core.lua) listens for nothing.
    if not MF.inert and (not valid or not pcall(events.RegisterEvent,events,event)) then unavailable[#unavailable+1]=event end
end
events:SetScript("OnEvent",function(_,event,unit)
    if event=="NAME_PLATE_UNIT_ADDED" and type(unit)=="string" then watched[unit]=true end
    if event=="NAME_PLATE_UNIT_REMOVED" and type(unit)=="string" then watched[unit]=nil end
    if event:match("^UNIT_SPELLCAST") and unit~="player" then return end
    Trace("event "..event..(event:match("^GLOBAL_MOUSE") and (" "..Text(unit)) or ""))
    if event=="NAME_PLATE_UNIT_REMOVED" then Hide() end
    MF:UpdateBobberHighlight()
end)
MF:Command("bobber","Solo","/tfl bobber on|off|assist|record|stop|bite|mark|trace - bobber highlight and diagnostics",function(self,args)
    local action=args[1]
    if action=="on" or action=="off" then
        self.db.settings.bobberHighlight=action=="on"
        self:UpdateBobberHighlight()
        self:Print("Bobber highlight "..action..".")
    elseif action=="assist" then
        self.db.settings.bobberAutoAssist=not self.db.settings.bobberAutoAssist
        self:UpdateBobberHighlight()
        self:Print("Automatic bobber highlight assistance: "..(self.db.settings.bobberAutoAssist and "on" or "off"))
    elseif action=="record" then
        rows={} recordingUntil=GetTime()+600 lastState=nil Trace("recording started") self:UpdateBobberHighlight()
        self:Print("Bobber trace recording for 10 minutes. /tfl bobber bite marks an observed bite; /tfl bobber trace copies the trace.")
    elseif action=="stop" then
        Trace("recording stopped") recordingUntil=0 self:UpdateBobberHighlight() self:Print("Bobber recording stopped; trace retained until reload.")
    elseif action=="bite" then
        if not Recording() then self:Print("Start /tfl bobber record first.") return end
        Trace("MANUAL observed bite (player marker, not detected)") self:UpdateBobberHighlight()
    elseif action=="mark" then
        local s=self:BobberSample()
        if not s.casting or s.object~=true or type(s.guid)~="string" then
            self:Print("While fishing, soft-target your bobber, then try /tfl bobber mark. No readable world object is selected.") return
        end
        markedGUID=s.guid Trace("MANUAL bobber identity marked for this cast") self:UpdateBobberHighlight()
        self:Print("Current soft-target object marked as your bobber for this cast only.")
    elseif action=="trace" then self:ShowDiagnosticText(self:BobberDiagnosticText())
    else self:Print("/tfl bobber on or off; assist toggles temporary settings; record, bite, stop and trace test bite signals. mark identifies a soft-target bobber for this cast.") end
end)
