-- Versioned, display-only snapshots. Plain chat transport avoids sending an
-- unsupported custom hyperlink through the server. Updated clients render
-- the token as an addon link; no addon whispers, scoring or imports occur.
local _,MF=...
local PREFIX="TFLcard1"
local sharePanel
local function Text(s,limit)
    s=tostring(s or ""):gsub("|H.-|h(.-)|h","%1"):gsub("|c%x%x%x%x%x%x%x%x","")
        :gsub("|r",""):gsub("|T.-|t",""):gsub("[|%c%[%]:]","")
    local out=""
    for char in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #out+#char>limit then break end
        out=out .. char
    end
    return out
end
local function Hex(s) return (s:gsub(".",function(c) return ("%02x"):format(c:byte()) end)) end
local function Unhex(s,limit)
    if #s>limit*2 or #s%2~=0 or s:find("[^%da-f]") then return nil end
    local value=s:gsub("..",function(c) return string.char(tonumber(c,16)) end)
    if Text(value,limit)~=value then return nil end
    return value
end
local function Integer(n,max)
    return type(n)=="number" and n==n and n>=0 and n<=max and n==math.floor(n)
end

function MF:CardSnapshot(id)
    local c=self:CardFor(id)
    if not c or not (self.FISH[id] or self.TROPHY[id]) then return nil end
    return {id=id,owner=self:FullName(self.me),count=c.count,best=c.best,specimen=c.specimen,
        waters=c.waters,water=Text(self:CardBestWater(id),32),at=GetServerTime(),caughtAt=self:CardBestCaughtAt(id)}
end

function MF:CardShareToken(snapshot)
    local s=snapshot
    if not s or not s.owner or #s.owner>64 then return nil end
    local function Pack(n) return self:Pack36(n) end
    local fields={Hex(s.owner),Pack(s.id),Pack(s.count),Pack(math.floor(s.best*100+.5)),
        Pack(math.floor(s.specimen*100+.5)),Pack(s.waters),Pack(s.at),Hex(s.water or "")}
    local version=PREFIX
    if s.caughtAt then fields[9]=Pack(s.caughtAt) version="TFLcard2" end
    local token="[" .. version .. ":" .. table.concat(fields,":") .. "]"
    if #token>250 then return nil end
    return token
end

function MF:ParseCardShare(token)
    if type(token)~="string" or #token>250 then return nil end
    local version,payload=token:match("^%[TFLcard([12]):(.-)%]$")
    if not payload then return nil end
    local fields={strsplit(":",payload)}
    if #fields~=(version=="2" and 9 or 8) then return nil end
    local owner,water=Unhex(fields[1],64),Unhex(fields[8],32)
    if not owner or owner=="" or not water then return nil end
    local nums={}
    for i=2,7 do
        if fields[i]=="" or fields[i]:find("[^%da-z]") then return nil end
        nums[i]=tonumber(fields[i],36)
        if not Integer(nums[i],2147483647) then return nil end
    end
    local id,count,best,specimen,waters,at=nums[2],nums[3],nums[4]/100,nums[5]/100,nums[6],nums[7]
    if not (self.FISH[id] or self.TROPHY[id]) or count<1 or count>100000000
        or best<=0 or best>10000 or specimen>best or waters>10000 or at<1 or at>GetServerTime()+300 then return nil end
    local edition,colour=self:Edition(id,best,specimen>0)
    local caughtAt
    if version=="2" then
        if fields[9]:find("[^%da-z]") then return nil end
        caughtAt=tonumber(fields[9],36)
        if not Integer(caughtAt,2147483647) or caughtAt<1 or caughtAt>at then return nil end
    end
    return {id=id,owner=owner,count=count,best=best,specimen=specimen,waters=waters,
        at=at,caughtAt=caughtAt,water=water~="" and water or nil,edition=edition,colour=colour}
end

function MF:CardShareLink(token)
    local s=self:ParseCardShare(token)
    if not s then return nil end
    local payload=token:sub(2,-2)
    return s.colour .. "|Haddon:TheFishingLog:" .. payload .. "|h[" .. Text(self:ShortName(s.owner),48)
        .. "'s " .. Text(self:FishName(s.id),70) .. " - " .. self:Weight(s.best) .. "]|h|r"
end

function MF:OpenSharedCardLink(link)
    if type(link)~="string" or #link>300 then return false end
    local payload=link:match("^addon:TheFishingLog:(TFLcard[12]:.*)$")
    local snapshot=payload and self:ParseCardShare("[" .. payload .. "]")
    if not snapshot then return false end
    self:ShowCard(snapshot.id,snapshot)
    return true
end

function MF:FilterCardShare(event,message,sender)
    -- Chat in protected content can arrive secret: leave it exactly as it is.
    if self:IsSecret(message) or self:IsSecret(sender) then return message end
    if type(message)~="string" or #message>1000 then return message end
    return (message:gsub("%[TFLcard[12]:[^%]]+%]",function(token)
        local s=self:ParseCardShare(token)
        if not s then return token end
        local author=event=="CHAT_MSG_WHISPER_INFORM" and self.me or sender
        if not author or self:AnglerKey(self:FullName(author))~=self:AnglerKey(self:FullName(s.owner)) then return token end
        return self:CardShareLink(token) or token
    end))
end

function MF:PrepareCardShare(id,road,target)
    if road~="GUILD" and road~="WHISPER" and road~="PARTY" and road~="CHANNEL" then return false end
    if road=="GUILD" and not IsInGuild() then self:Print("Join a guild to share a card in guild chat.") return false end
    if road=="PARTY" and not IsInGroup() then self:Print("Join a party to share a card in party chat.") return false end
    if road=="CHANNEL" then
        local number=tostring(target or ""):match("^/?(%d+)$")
        target=tonumber(number)
        local id,name
        if target and target>=1 and target<=99 and type(GetChannelName)=="function" then id,name=GetChannelName(target) end
        if id~=target or type(name)~="string" or name=="" or name:lower()=="thefishinglog" then
            self:Print("Enter the number of a joined chat channel, such as 1 for General or 2 for Trade.") return false
        end
    end
    if road=="WHISPER" then
        target=strtrim(tostring(target or ""))
        -- Spaces are valid in Forever player names; no command/control text.
        if target=="" or #target>64 or target:find("[/|%c%[%]:]") then
            self:Print("Enter the player's full name, including realm if needed.") return false
        end
    end
    local token=self:CardShareToken(self:CardSnapshot(id))
    if not token then self:Print("That earned card cannot be shared yet.") return false end
    local util=ChatFrameUtil
    local open=type(ChatFrame_OpenChat)=="function" and ChatFrame_OpenChat or (util and util.OpenChat)
    if type(open)~="function" then self:Print("Chat is unavailable. Try again outside a loading screen.") return false end
    -- Route via edit-box attributes: /w parsing would split Forever names
    -- containing spaces. Never call SendChatMessage from the share UI.
    -- OpenChat schedules its argument for the edit box's next OnUpdate.
    -- Passing "" here would wipe any immediately inserted token next frame.
    local edit=open(token)
    if not edit and type(ChatEdit_GetActiveWindow)=="function" then edit=ChatEdit_GetActiveWindow() end
    if not edit and util and type(util.GetActiveWindow)=="function" then edit=util.GetActiveWindow() end
    if not edit or type(edit.SetAttribute)~="function" or type(edit.SetText)~="function" then
        self:Print("Could not open the chat composer.") return false
    end
    edit:SetAttribute("chatType",road)
    edit:SetAttribute("tellTarget",road=="WHISPER" and target or nil)
    edit:SetAttribute("channelTarget",road=="CHANNEL" and target or nil)
    if type(ChatEdit_UpdateHeader)=="function" then ChatEdit_UpdateHeader(edit) end
    if type(ChatEdit_UpdateHeader)~="function" and type(edit.UpdateHeader)=="function" then edit:UpdateHeader() end
    edit:SetFocus()
    -- Header/focus setup can clear a newly routed composer. Populate only
    -- after activation, routing and header updates have all finished.
    edit:SetText(token)
    edit:SetCursorPosition(#token)
    if type(edit.GetText)=="function" then
        local shown=edit:GetText()
        if not self:IsSecret(shown) and shown~=token then
            self:Print("The chat composer did not accept the card text. Your card has not been sent.") return false
        end
    end
    return true
end

function MF:OpenCardShare(id)
    local s=self:CardSnapshot(id)
    if not s then return end
    if not sharePanel then
        local p=self:CreatePanel("TheFishingLogCardShare",360,370,
            {title="Share a fishing card",close=true,movable=true,escCloses=true,strata="DIALOG"})
        sharePanel=p p:SetPoint("CENTER")
        p.icon=p:CreateTexture(nil,"ARTWORK") p.icon:SetSize(44,44) p.icon:SetPoint("TOPLEFT",22,-48)
        p.name=self:CreateText(p,"GameFontNormal","TOPLEFT",78,-48)
        p.name:SetWidth(254) p.name:SetWordWrap(true)
        p.summary=self:CreateText(p,"GameFontHighlightSmall","TOPLEFT",78,-77) p.summary:SetWidth(254)
        local help=self:CreateText(p,"GameFontHighlightSmall","TOPLEFT",22,-110)
        help:SetWidth(316) help:SetWordWrap(true)
        help:SetText("Share a snapshot of your collection. TFL turns the chat token into a clickable card. Press Enter in chat to send.")
        local label=self:CreateText(p,"GameFontNormalSmall","TOPLEFT",22,-158) label:SetText("Whisper to (player name)")
        p.target=CreateFrame("EditBox",nil,p,"InputBoxTemplate") p.target:SetSize(300,24)
        p.target:SetPoint("TOPLEFT",28,-178) p.target:SetAutoFocus(false) p.target:SetMaxLetters(64)
        p.target:SetScript("OnEscapePressed",function(edit) edit:ClearFocus() p:Hide() end)
        p.guild=self:CreateButton(p,"Guild (/g)",148,function()
            p.target:ClearFocus() p.number:ClearFocus() p:Hide()
            if not MF:PrepareCardShare(p.id,"GUILD") then p:Show() end
        end) p.guild:SetPoint("TOPLEFT",22,-214)
        p.whisper=self:CreateButton(p,"Whisper (/w)",148,function()
            local target=p.target:GetText()
            p.target:ClearFocus() p.number:ClearFocus() p:Hide()
            if not MF:PrepareCardShare(p.id,"WHISPER",target) then p:Show() end
        end) p.whisper:SetPoint("TOPRIGHT",-22,-214)
        p.party=self:CreateButton(p,"Party (/p)",148,function()
            p.target:ClearFocus() p.number:ClearFocus() p:Hide()
            if not MF:PrepareCardShare(p.id,"PARTY") then p:Show() end
        end) p.party:SetPoint("TOPLEFT",22,-248)
        p.channel=self:CreateButton(p,"Channel (/1)",148,function()
            local number=p.number:GetText()
            p.target:ClearFocus() p.number:ClearFocus() p:Hide()
            if not MF:PrepareCardShare(p.id,"CHANNEL",number) then p:Show() end
        end) p.channel:SetPoint("TOPRIGHT",-22,-248)
        local channelLabel=self:CreateText(p,"GameFontNormalSmall","TOPLEFT",22,-288)
        channelLabel:SetText("Chat channel number")
        p.number=CreateFrame("EditBox",nil,p,"InputBoxTemplate") p.number:SetSize(86,24)
        p.number:SetPoint("TOPRIGHT",-28,-280) p.number:SetAutoFocus(false)
        p.number:SetMaxLetters(2) p.number:SetNumeric(true)
        p.number:SetScript("OnTextChanged",function(edit)
            p.channel:SetText("Channel (/" .. (edit:GetText() or "") .. ")")
        end)
        p.number:SetScript("OnEscapePressed",function(edit) edit:ClearFocus() p:Hide() end)
        p.number:SetText("1")
        local footer=self:CreateText(p,"GameFontDisableSmall","BOTTOMLEFT",22,20)
        footer:SetWidth(316) footer:SetText("Recipients need a TFL version with shared cards.")
    end
    sharePanel.id=id
    sharePanel.icon:SetTexture(self:FishIcon(id))
    sharePanel.name:SetText(self:FishName(id))
    sharePanel.summary:SetText(self:ShortName(s.owner) .. " / " .. self:Weight(s.best))
    local target=type(UnitIsPlayer)=="function" and UnitIsPlayer("target") and type(GetUnitName)=="function" and GetUnitName("target",true) or ""
    sharePanel.target:SetText(target or "")
    sharePanel.guild:SetEnabled(IsInGuild())
    sharePanel.party:SetEnabled(IsInGroup())
    local height,width=UIParent:GetHeight(),UIParent:GetWidth()
    if height and width and height>100 and width>100 then sharePanel:SetScale(math.min(1,(height-40)/370,(width-40)/360)) end
    sharePanel:Show()
end

local registered=false
MF:On("TFL_LOGIN",function(self)
    if registered then return end
    registered=true
    if type(ChatFrame_AddMessageEventFilter)=="function" then
        for _,event in ipairs({"CHAT_MSG_GUILD","CHAT_MSG_WHISPER","CHAT_MSG_WHISPER_INFORM",
            "CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER","CHAT_MSG_CHANNEL"}) do
            ChatFrame_AddMessageEventFilter(event,function(_,kind,message,sender,...)
                return false,self:FilterCardShare(kind,message,sender),sender,...
            end)
        end
    end
    if EventRegistry and type(EventRegistry.RegisterCallback)=="function" then
        EventRegistry:RegisterCallback("SetItemRef",function(_,link) self:OpenSharedCardLink(link) end,self)
    elseif type(hooksecurefunc)=="function" and type(SetItemRef)=="function" then
        hooksecurefunc("SetItemRef",function(link) self:OpenSharedCardLink(link) end)
    end
end)
