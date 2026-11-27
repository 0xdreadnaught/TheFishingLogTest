-- One character's fishing wardrobe. Manual actions only; verified changes,
-- exact bag copies where possible, and a persistent, non-overwriting restore point.
local _, MF = ...
local SLOTS = {{16,"Fishing pole"},{1,"Head"},{8,"Feet"},{10,"Hands"},{15,"Back"},
    {17,"Off hand"},{2,"Neck"},{3,"Shoulders"},{5,"Chest"},{9,"Wrists"},
    {6,"Waist"},{7,"Legs"},{11,"Finger 1"},{12,"Finger 2"},{13,"Trinket 1"},
    {14,"Trinket 2"},{18,"Ranged"}}
local op, panel
local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY = {[1]="Head",[2]="Neck",[3]="Shoulder",[5]="Chest",[6]="Waist",[7]="Legs",
    [8]="Feet",[9]="Wrists",[10]="Hands",[11]="Finger",[12]="Finger",[13]="Trinket",
    [14]="Trinket",[15]="Chest",[16]="MainHand",[17]="SecondaryHand",[18]="Ranged"}

local function Link(slot)
    return GetInventoryItemLink("player",slot)
end
local function Payload(link)
    return type(link) == "string" and (link:match("|H(item:[^|]+)|h") or link:match("^(item:.*)$")) or link
end
local function GUID(bag,slot)
    if not ItemLocation or type(ItemLocation.CreateFromEquipmentSlot) ~= "function"
        or not C_Item or type(C_Item.GetItemGUID) ~= "function" then return end
    local ok, result = pcall(function()
        local location = bag == nil and ItemLocation:CreateFromEquipmentSlot(slot)
            or ItemLocation:CreateFromBagAndSlot(bag,slot)
        return C_Item.GetItemGUID(location)
    end)
    return ok and type(result) == "string" and result or nil
end
local function Item(slot)
    local link = Link(slot)
    return link and {link=link,guid=GUID(nil,slot)} or false
end
local function Same(want,slot)
    if not want then return not Link(slot) end
    if want.guid then
        local guid = GUID(nil,slot)
        if guid then return guid == want.guid end
    end
    return Payload(want.link) == Payload(Link(slot))
end
local function State(self)
    self.cdb.gear = self.cdb.gear or {}
    local state = self.cdb.gear.outfit
    if not state then
        state = {selected={[16]=true,[1]=true,[8]=true,[10]=true,[15]=true},items={}}
        self.cdb.gear.outfit = state
    end
    return state
end
local function BagItems(fn)
    if not C_Container or type(C_Container.GetContainerNumSlots) ~= "function"
        or type(C_Container.GetContainerItemInfo) ~= "function" then return end
    for bag=0,4 do
        for slot=1,C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag,slot)
            if fn(bag,slot,info) then return bag,slot,info end
        end
    end
end
local function Find(want)
    return BagItems(function(bag,slot,info)
        if not info then return false end
        local link = info.hyperlink or info.link
        if want.guid then
            local guid = GUID(bag,slot)
            if guid then return guid == want.guid end
        end
        return Payload(link) == Payload(want.link)
    end)
end
local function IsPole(want)
    if not want or not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then return false end
    local _,_,_,_,_,class,subclass = C_Item.GetItemInfoInstant(want.link)
    return class == 2 and subclass == 20
end
local function CursorBusy()
    return type(GetCursorInfo) == "function" and GetCursorInfo() ~= nil
end

function MF:FishingOutfitState() return State(self) end
function MF:FishingOutfitSlots() return SLOTS end

function MF:OutfitItemStatus(slot)
    local want = State(self).items[slot]
    if not want then return "Not saved", self.C.muted end
    if Same(want,slot) then return "Equipped", self.C.good end
    local bag,_,info = Find(want)
    if bag then return info and info.isLocked and "Locked" or "In bags", self.C.hint end
    return "Not in bags", self.C.bad
end

function MF:SaveFishingOutfit()
    local state = State(self)
    if InCombatLockdown() or self:IsGearSwapBusy() then
        self:Print("Save your outfit out of combat, after any gear change finishes.") return false
    end
    if state.previous then
        self:Print("Restore your previous gear before replacing the saved fishing outfit.") return false
    end
    local items,n = {},0
    for _,entry in ipairs(SLOTS) do
        local slot = entry[1]
        if state.selected[slot] then
            items[slot] = Item(slot)
            if items[slot] then n=n+1 end
        end
    end
    if n == 0 then self:Print("Select at least one slot containing an item to save.") return false end
    state.items, state.savedAt = items, GetServerTime()
    state.message = ("Saved %d pieces. Your fishing outfit is ready."):format(n)
    self:Print(state.message)
    self:RefreshFishingOutfit()
    return true
end

local function Finish(self,message)
    local restoring = op and op.restoring
    op, self.outfitChanging = nil,nil
    local state = State(self)
    if restoring and state.previous then
        local complete = true
        for slot,want in pairs(state.previous) do if not Same(want,slot) then complete=false break end end
        if complete then
            state.previous = nil
            message = "Previous gear restored. Ready for your next adventure."
            self:RememberCombatWeapons()
        else
            message = "Some previous gear is missing or blocked. Restore point kept; check your bags and click Restore again."
        end
    end
    state.message = message
    self:Print(message)
    self:RefreshFishingOutfit()
end

local function Step(self,transaction)
    if op ~= transaction then return end
    if State(self) ~= transaction.state then
        Finish(self,"Outfit data changed. Check your equipment before starting another change.") return
    end
    if InCombatLockdown() then
        Finish(self,"Outfit change stopped for combat. Click Equip or Restore again when safe.") return
    end
    if CursorBusy() then Finish(self,"Outfit change stopped: clear the item on your cursor, then try again.") return end
    local change = transaction.changes[transaction.index]
    if not change then
        local failures = transaction.failed
        Finish(self, failures > 0 and ("%d slots need attention. Check your bags and click again; your restore point is kept."):format(failures)
            or transaction.restoring and "Restoration checked." or "Fishing outfit equipped. Your previous gear is safely remembered.")
        return
    end
    local slot,want = change.slot,change.want
    if Same(want,slot) then
        transaction.index = transaction.index + 1
        transaction.sentAt = nil
    elseif transaction.sentAt then
        if GetTime() - transaction.sentAt >= 3 then
            transaction.failed = transaction.failed + 1
            transaction.index = transaction.index + 1
            transaction.sentAt = nil
        end
    else
        local bag,position,info
        if want then bag,position,info = Find(want)
        else bag,position = BagItems(function(_,_,item) return not item end) end
        if bag == nil or (info and info.isLocked) then
            transaction.failed = transaction.failed + 1
            transaction.index = transaction.index + 1
        else
            transaction.sentAt = GetTime()
            local ok = pcall(function()
                if want then
                    C_Container.PickupContainerItem(bag,position)
                    if not CursorBusy() then return end
                    EquipCursorItem(slot)
                else
                    PickupInventoryItem(slot)
                    if not CursorBusy() then return end
                    C_Container.PickupContainerItem(bag,position)
                end
                if CursorBusy() and type(ClearCursor) == "function" then ClearCursor() end
            end)
            if not ok then
                if CursorBusy() then pcall(ClearCursor) end
                Finish(self,"The client refused an equipment change. Your restore point is kept; check your bags and try again.") return
            end
        end
    end
    self:RefreshFishingOutfit()
    C_Timer.After(0.15,function() Step(self,transaction) end)
end

function MF:ApplyFishingOutfit(restoring)
    if InCombatLockdown() then self:Print("Leave combat, then click Equip or Restore again. No outfit change is queued.") return false end
    if self:IsGearSwapBusy() then self:Print("Finish the current equipment change first.") return false end
    if CursorBusy() then self:Print("Clear the item on your cursor before changing outfits.") return false end
    if not C_Container or type(C_Container.PickupContainerItem) ~= "function"
        or type(EquipCursorItem) ~= "function" or type(PickupInventoryItem) ~= "function"
        or type(GetCursorInfo) ~= "function" or type(ClearCursor) ~= "function" then
        self:Print("This client cannot safely change outfit items.") return false
    end
    local state = State(self)
    local target
    if restoring then target = state.previous else target = state.items end
    if not target or not next(target) then self:Print(restoring and "No previous outfit to restore." or "Save a fishing outfit first.") return false end
    local changes = {}
    for _,entry in ipairs(SLOTS) do
        local slot = entry[1]
        local want = target[slot]
        if (restoring and want ~= nil or not restoring and want and state.selected[slot]) and not Same(want,slot) then
            changes[#changes+1] = {slot=slot,want=want}
        end
    end
    -- A main-hand change must settle before an off-hand can be restored.
    table.sort(changes,function(a,b)
        local function order(slot) return slot == 16 and -2 or slot == 17 and -1 or slot end
        return order(a.slot) < order(b.slot)
    end)
    if #changes == 0 then
        if restoring then op={restoring=true} Finish(self,"Previous gear already equipped.")
        else self:Print("Your selected fishing outfit is already equipped.") end
        return true
    end
    if not restoring and IsPole(target[16]) and target[17] and state.selected[17] then
        self:Print("A fishing pole needs both hands. Leave off hand unchecked.") return false
    end
    self:RememberCombatWeapons()
    if not restoring then
        -- Never replace the original restore point on repeat or partial Equip.
        state.previous = state.previous or {}
        for _,change in ipairs(changes) do
            if state.previous[change.slot] == nil then state.previous[change.slot] = Item(change.slot) end
            if change.slot == 16 and state.previous[17] == nil then state.previous[17] = Item(17) end
        end
    end
    self.outfitSuppressPoleReturn = restoring and true or nil
    self.outfitChanging = true
    op = {restoring=restoring,changes=changes,index=1,failed=0,state=state}
    state.message = restoring and "Restoring your previous gear..." or "Getting you ready for the water..."
    Step(self,op)
    return true
end

local function Text(parent,font,x,y,width)
    local label = MF:CreateText(parent,font,"TOPLEFT",x,y)
    label:SetWidth(width) label:SetJustifyH("LEFT") label:SetWordWrap(true)
    return label
end

function MF:RefreshFishingOutfit()
    if not panel or not panel:IsShown() then return end
    local state = State(self)
    local n,ready = 0,0
    for _,row in ipairs(panel.rows) do
        local slot = row.slot
        local want = state.items[slot]
        local preview = want or Item(slot)
        row.check:SetChecked(state.selected[slot] == true)
        row.check:SetEnabled(not self.outfitChanging and not state.previous)
        local status,color = self:OutfitItemStatus(slot)
        row.name:SetText(preview and (preview.link:match("|h%[(.-)%]|h") or preview.link) or "Nothing equipped")
        if not want and preview then status,color = "Wearing — not saved",self.C.muted end
        row.status:SetText((state.selected[slot] and color or self.C.muted) .. (state.selected[slot] and status or "Slot excluded") .. "|r")
        local texture = preview and C_Item.GetItemIconByID and C_Item.GetItemIconByID(preview.link)
        if not want then texture = GetInventoryItemTexture("player",slot) or texture end
        row.icon:SetTexture(texture or ("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (EMPTY[slot] or "Bag")))
        row.icon:SetDesaturated(not state.selected[slot])
        row.link = preview and preview.link
        if state.selected[slot] then row:SetBackdropBorderColor(0.48,0.39,0.16,0.85)
        else row:SetBackdropBorderColor(0.23,0.25,0.29,0.6) end
        if want and state.selected[slot] then
            n=n+1
            if status == "Equipped" or status == "In bags" then ready=ready+1 end
        end
    end
    panel.summary:SetText(n == 0 and "A little preparation. A better day by the water." or ("%d pieces saved  /  %d ready to wear"):format(n,ready))
    panel.status:SetText(state.message or "Wear your fishing pieces, tick the slots to remember, then save. Only those slots will change.")
    local busy = self.outfitChanging or InCombatLockdown()
    panel.save:SetEnabled(not busy and not state.previous)
    panel.equip:SetEnabled(not busy and n > 0)
    panel.restore:SetEnabled(not busy and state.previous ~= nil)
    panel.returnNote:SetText(state.previous and "Previous gear remembered — Restore returns it, including your off hand." or "Your current gear is remembered before you equip. Lures stay separate.")
    self:LayoutFishingOutfit()
end

function MF:LayoutFishingOutfit()
    if not panel then return end
    local selected,other = {},{}
    local state = State(self)
    for _,tile in ipairs(panel.rows) do
        local group = state.selected[tile.slot] and selected or other
        group[#group+1] = tile
    end
    local function Place(group,top,shown)
        for i,tile in ipairs(group) do
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT",24+((i-1)%2)*322,top-math.floor((i-1)/2)*58)
            tile:SetShown(shown)
        end
        return top-math.ceil(#group/2)*58
    end
    local top = Place(selected,-150,true)
    panel.extra:ClearAllPoints() panel.extra:SetPoint("TOPLEFT",24,top-8)
    panel.extra:SetText((panel.expanded and "Hide other slots" or "Choose other slots") .. " (" .. #other .. ") " .. (panel.expanded and "-" or "+"))
    top=top-46
    if panel.expanded then top=Place(other,top,true)
    else Place(other,top,false) end
    local height=math.max(380,-top+110)
    panel:SetHeight(height)
    local screenH,screenW=UIParent:GetHeight(),UIParent:GetWidth()
    if screenH and screenW and screenH>100 and screenW>100 then
        panel:SetScale(math.min(1,(screenH-40)/height,(screenW-40)/680))
    end
end

function MF:OpenFishingOutfit()
    if not panel then
        panel = self:CreatePanel("TheFishingLogOutfit",680,680,{title="Angler's Wardrobe",close=true,movable=true,escCloses=true,fill=self.FILL_READING,
            -- Above the journal (HIGH), which is where it is usually opened from
            strata="DIALOG"})
        -- The dialog artwork contains translucent regions even with alpha 1.
        -- Use a flat reading fill so scenery cannot show through this window.
        -- Not over the new look's panel skin, though: that lays the stone
        -- under the window, and an opaque fill here would cover it.
        if not panel.lodgeStyle then
            panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize=24,insets={left=6,right=6,top=6,bottom=6}})
            panel:SetBackdropColor(unpack(self.FILL_READING))
        end
        panel:SetPoint("CENTER")
        local crest = panel:CreateTexture(nil,"ARTWORK")
        crest:SetSize(44,44) crest:SetPoint("TOPLEFT",22,-48)
        crest:SetTexture("Interface\\Icons\\Trade_Fishing")
        local crestBorder = panel:CreateTexture(nil,"OVERLAY")
        crestBorder:SetSize(64,64) crestBorder:SetPoint("CENTER",crest,"CENTER",0,0)
        crestBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        Text(panel,"GameFontNormalLarge",80,-49,560):SetText("Your Fishing Outfit")
        local tackle=self:CreateButton(panel,"Tacklebox",100,function() panel:Hide() MF:OpenAnglingTools("tackle") end)
        tackle:SetPoint("TOPRIGHT",-26,-48)
        panel.summary = Text(panel,"GameFontHighlightSmall",80,-75,560)
        Text(panel,"GameFontHighlightSmall",24,-103,630):SetText("Wear the pieces you want, select their slots, then save. Everything else stays yours to change.")
        Text(panel,"GameFontNormal",24,-128,630):SetText("In your fishing outfit")
        panel.rows = {}
        for i,entry in ipairs(SLOTS) do
            local col,row = (i-1)%2,math.floor((i-1)/2)
            local tile = CreateFrame("Frame",nil,panel,"BackdropTemplate")
            tile:SetSize(310,52) tile:SetPoint("TOPLEFT",24+col*322,-150-row*58)
            tile:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
            tile:SetBackdropColor(unpack(self.FILL)) tile:SetBackdropBorderColor(0.34,0.29,0.13,0.7)
            tile.slot = entry[1]
            tile.check = CreateFrame("CheckButton",nil,tile,"UICheckButtonTemplate")
            tile.check:SetSize(24,24) tile.check:SetPoint("LEFT",2,0)
            tile.check:SetScript("OnClick",function(check)
                local state=State(MF)
                if state.previous or MF.outfitChanging then return end
                state.selected[tile.slot] = check:GetChecked() and true or false
                MF:RefreshFishingOutfit()
            end)
            tile.icon = tile:CreateTexture(nil,"ARTWORK")
            tile.icon:SetSize(32,32) tile.icon:SetPoint("LEFT",30,0)
            local iconBorder=tile:CreateTexture(nil,"OVERLAY")
            iconBorder:SetSize(42,42) iconBorder:SetPoint("CENTER",tile.icon,"CENTER",0,0)
            iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            Text(tile,"GameFontNormalSmall",70,-4,225):SetText(entry[2])
            tile.name = Text(tile,"GameFontHighlightSmall",70,-18,225)
            tile.name:SetWordWrap(false)
            tile.status = Text(tile,"GameFontDisableSmall",70,-35,225)
            tile:EnableMouse(true)
            tile:SetScript("OnEnter",function(rowFrame)
                if not rowFrame.link then return end
                GameTooltip:SetOwner(rowFrame,"ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(rowFrame.link) GameTooltip:Show()
            end)
            tile:SetScript("OnLeave",function() GameTooltip:Hide() end)
            panel.rows[#panel.rows+1] = tile
        end
        panel.extra = self:CreateButton(panel,"Choose other slots",632,function()
            panel.expanded = not panel.expanded
            MF:LayoutFishingOutfit()
        end)
        panel.extra:SetHeight(26)
        panel.status = self:CreateText(panel,"GameFontHighlightSmall")
        panel.status:SetPoint("BOTTOMLEFT",24,76)
        panel.status:SetWidth(630) panel.status:SetJustifyH("LEFT") panel.status:SetWordWrap(true)
        panel.status:SetHeight(30)
        panel.save = self:CreateButton(panel,"Save current gear",180,function() MF:SaveFishingOutfit() end)
        panel.save:SetPoint("BOTTOMLEFT",24,40)
        panel.equip = self:CreateButton(panel,"Equip fishing outfit",206,function() MF:ApplyFishingOutfit(false) end)
        panel.equip:SetPoint("BOTTOMLEFT",216,40)
        panel.equip:SetHeight(28)
        panel.restore = self:CreateButton(panel,"Restore previous gear",222,function() MF:ApplyFishingOutfit(true) end)
        panel.restore:SetPoint("BOTTOMRIGHT",-24,40)
        panel.returnNote = self:CreateText(panel,"GameFontDisableSmall")
        panel.returnNote:SetPoint("BOTTOMLEFT",24,16) panel.returnNote:SetWidth(630)
        panel.returnNote:SetJustifyH("LEFT") panel.returnNote:SetWordWrap(true)
        -- On the new look's stone the bottom corners carry ornaments, so the
        -- bottom row moves in from the edges and the note sits between them.
        if panel.lodgeGround then
            panel.save:SetWidth(176) panel.equip:SetWidth(180) panel.restore:SetWidth(176)
            panel.save:ClearAllPoints() panel.save:SetPoint("BOTTOMLEFT",56,40)
            panel.equip:ClearAllPoints() panel.equip:SetPoint("BOTTOM",0,40)
            panel.restore:ClearAllPoints() panel.restore:SetPoint("BOTTOMRIGHT",-56,40)
            panel.returnNote:ClearAllPoints() panel.returnNote:SetPoint("BOTTOM",0,18)
            panel.returnNote:SetWidth(520) panel.returnNote:SetJustifyH("CENTER")
            panel.status:ClearAllPoints() panel.status:SetPoint("BOTTOMLEFT",56,76)
            panel.status:SetWidth(568)
        end
        panel:SetScript("OnShow",function() MF:RefreshFishingOutfit() end)
        self.outfitPanel = panel
    end
    local height,width = UIParent:GetHeight(),UIParent:GetWidth()
    if height and width and height > 100 and width > 100 then
        panel:SetScale(math.min(1,(height-40)/680,(width-40)/680))
    end
    panel:Show() self:RefreshFishingOutfit()
end

for _,event in ipairs({"BAG_UPDATE_DELAYED","PLAYER_EQUIPMENT_CHANGED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED","GET_ITEM_INFO_RECEIVED"}) do
    local name = event
    MF:On(event,function(self)
        if name == "PLAYER_REGEN_DISABLED" and op then
            Finish(self,"Outfit change stopped for combat. Click Equip or Restore again when safe.")
        end
        self:RefreshFishingOutfit()
    end)
end
MF:On("TFL_LOGIN",function(self)
    local state = self.cdb.gear and self.cdb.gear.outfit
    if state and state.previous then state.message = "Your previous gear is remembered. Click Restore whenever you are ready." end
end)
MF:Command("outfit","Gear","/tfl outfit - open your fishing wardrobe",MF.OpenFishingOutfit)

function MF:ResetFishingOutfit() op=nil if panel then panel:Hide() end end
