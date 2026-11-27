-- Cast outcomes are separate from weighed fish: one cast can land a stack.
-- Only Catch.lua's accepted serial and accepted loot can establish success.
local _,MF=...
local current,feedback,renderFailed
local function Counts(s)
    s.outcomes=s.outcomes or {casts=0,landed=0,escaped=0,cancelled=0,unknown=0,early=0}
    return s.outcomes
end
function MF:CastOutcomeSummary(s)
    local c=s and s.outcomes
    if type(c)~="table" then return "Cast outcomes were not recorded." end
    for _,key in ipairs({"casts","landed","escaped","cancelled","unknown"}) do
        local n=c[key]
        if type(n)~="number" or n~=n or n<0 or n>10000000 then return "Cast outcomes were not recorded." end
    end
    local pending=math.max(0,c.casts-c.landed-c.escaped-c.cancelled-c.unknown)
    return ("%d casts / %d landed / %d escaped / %d cancelled / %d unknown%s"):format(
        c.casts,c.landed,c.escaped,c.cancelled,c.unknown,pending>0 and (" / "..pending.." pending") or "")
end
function MF:ShowCastFeedback(text,success)
    if renderFailed or not self.db.settings.castFeedback or self:InMatch() then return end
    local ok,err=pcall(function()
        if not feedback then
            feedback=CreateFrame("Frame","TheFishingLogCastFeedback",UIParent)
            feedback:SetSize(290,24);feedback:SetFrameStrata("MEDIUM");feedback:EnableMouse(false)
            feedback.text=self:CreateText(feedback,"GameFontHighlightSmall","CENTER",0,0)
            feedback:Hide()
        end
        local board=_G.TheFishingLogBoard
        if not board or not board:IsShown() then return end
        feedback:SetScale(board:GetEffectiveScale()/UIParent:GetEffectiveScale())
        feedback:ClearAllPoints();feedback:SetPoint("TOP",board,"BOTTOM",0,-5)
        feedback.text:SetText((success and self.C.good or self.C.label)..text.."|r")
        feedback.untilAt=GetTime()+3
        feedback:SetAlpha(1);feedback:Show()
    end)
    if not ok then
        renderFailed=true
        if feedback then feedback:Hide() end
        self:Print("Cast feedback disabled after a display error: "..tostring(err))
    end
end
local function Set(self,status)
    if not current or current.status==status then return end
    -- Accepted loot is stronger evidence than a late interrupt/error message.
    if current.status=="landed" or current.status~="pending" and status~="landed" then return end
    local c=Counts(current.session)
    if current.status~="pending" then c[current.status]=math.max(0,c[current.status]-1) end
    local was=current.status
    current.status=status;c[status]=c[status]+1
    self:NoteCastSkill(current,was,status)
    if status=="landed" then self:ShowCastFeedback("Catch landed",true)
    elseif status=="escaped" then self:ShowCastFeedback("Fish got away",false)
    elseif status=="cancelled" then self:ShowCastFeedback("Cast interrupted",false) end
end
MF:On("TFL_FISHING_CAST",function(self,serial,at,guid)
    if current then Set(self,"unknown") end
    current=nil
    if type(serial)~="number" or serial<1 or not self:IsSessionRunning() or self:InMatch() then return end
    if GetServerTime()>=self.FRESH_START and (at or 0)<self.FRESH_START then return end
    local c=Counts(self.session);c.casts=c.casts+1
    if self:IsSecret(guid) then guid=nil end
    current={serial=serial,at=at,guid=guid,started=GetTime(),status="pending",session=self.session}
    self:CatchSkillCastContext(current)
end)
MF:On("TFL_FISHING_DONE",function(_,serial)
    if current and serial==current.serial then current.stopped=GetTime() end
end)
MF:On("TFL_FISHING_LOOT",function(self,serial,at)
    if current and serial==current.serial and at==current.at and GetTime()-current.started<=40 then Set(self,"landed") end
end)
MF:On("TFL_FISHING_INVALIDATED",function(self,serial)
    if current and current.serial==serial then Set(self,"unknown") end
end)
local function Eligible(self)
    return current and current.status=="pending" and current.session==self.session
        and not self:InMatch() and GetTime()-current.started<=35
        and (not current.stopped or GetTime()-current.stopped<=2)
end
function MF:NoteFishingError(message)
    if self:IsSecret(message) or type(message)~="string" or not Eligible(self) then return end
    if type(ERR_FISH_ESCAPED)=="string" and message==ERR_FISH_ESCAPED then Set(self,"escaped")
    elseif type(ERR_FISH_NOT_HOOKED)=="string" and message==ERR_FISH_NOT_HOOKED then
        if GetTime()-(current.earlyAt or -math.huge)<0.6 then return end
        current.earlyAt=GetTime()
        local c=Counts(current.session);c.early=c.early+1
        self:ShowCastFeedback("Too early — keep waiting",false)
    end
end
for _,event in ipairs({"UI_ERROR_MESSAGE","UI_INFO_MESSAGE"}) do
    MF:On(event,function(self,a,b) self:NoteFishingError(type(b)=="string" and b or a) end)
end
for _,event in ipairs({"UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_FAILED"}) do
    MF:OnUnit(event,"player",function(self,unit,guid,spell)
        if self:IsSecret(guid) or self:IsSecret(spell) then return end
        if unit=="player" and spell==7620 and Eligible(self)
            and (not current.guid or not guid or current.guid==guid) then Set(self,"cancelled") end
    end)
end
MF:OnTick(function(self)
    if current and (GetTime()-current.started>40 or current.stopped and GetTime()-current.stopped>5) then Set(self,"unknown") end
    if feedback and feedback:IsShown() then
        local board=_G.TheFishingLogBoard
        if GetTime()>feedback.untilAt or not self.db.settings.castFeedback or not board or not board:IsShown() or self:InMatch() then feedback:Hide() end
    end
end)
function MF:ResetCastOutcomes()
    current=nil
    if feedback then feedback:Hide() end
end
MF:Command("casts","Solo","/tfl casts - outcomes of this session's accepted casts",function(self)
    self:Print(self:CastOutcomeSummary(self.session))
end)
