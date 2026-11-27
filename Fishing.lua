-- Fishing: lure timer and warnings, one-click lure and pole, gear sets and
-- an optional swap back to your combat weapons when something attacks you.
--
-- Applying a lure and casting have to go through secure buttons the player
-- clicks themselves; addons can't do either on your behalf.
local _, MF = ...
local function print(...) MF:PrintChat(...) end

local FISHING_POLE_SUBCLASS = 20 -- weapon subclass
local FISHING_SPELL = 7620

-- Several item functions moved into C_Item on modern clients; Forever has
-- some in one place and some in the other, so try both.
local function Equip(link, slot)
    if InCombatLockdown() then return false end
    local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if not fn then
        MF:Print("This client has no way for addons to equip items.")
        return false
    end
    fn(link, slot)
    return true
end

-- Putting on a particular weapon, rather than one like it
--
-- EquipItemByName matches the item and not which copy of it. A dual
-- wielder carrying a Bronze Shortsword in each hand has two links that
-- differ only in which instance they are, so asking for the off-hand
-- finds the one already in the main hand and does nothing at all - main
-- hand back, off-hand slot empty, no error. That is the whole of "swap
-- only gave me my main hand", and no amount of getting the sequence
-- right was ever going to fix it.
--
-- A bag slot is one copy and nothing else, so taking it out by position
-- cannot make that mistake. Falls back to asking by name when the item
-- is not in the bags, which is also the case where the game has
-- something worth saying.
local function EquipFromBags(link, slot)
    if InCombatLockdown() then return false end
    local want = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(link)
    local byHand = C_Container and C_Container.PickupContainerItem and EquipCursorItem
    -- Never while something is already held: it would be put down
    -- somewhere nobody asked for.
    if GetCursorInfo and GetCursorInfo() then byHand = nil end
    if want and byHand then
        for bag = 0, 4 do
            for i = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, i)
                local found = info and (info.hyperlink or info.link)
                if found and C_Item.GetItemInfoInstant(found) == want then
                    C_Container.PickupContainerItem(bag, i)
                    EquipCursorItem(slot)
                    -- If the slot refused it, put it back rather than
                    -- leaving somebody's weapon stuck to their cursor.
                    if GetCursorInfo and GetCursorInfo() and ClearCursor then ClearCursor() end
                    return true
                end
            end
        end
    end
    return Equip(link, slot)
end

local function InventoryLink(slot)
    local fn = GetInventoryItemLink or (C_Item and C_Item.GetInventoryItemLink)
    return fn and fn("player", slot)
end

local function ItemCount(itemID)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return (fn and fn(itemID)) or 0
end

local WARN_EVERY = 60
local FISHING_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17 }

-- Best first; the addon uses the best one you're carrying.
MF.LURES = {
    { id = 6533, bonus = 100, skill = 100, seconds = 300 }, -- Aquadynamic Fish Attractor
    { id = 6532, bonus = 75, skill = 100, seconds = 600 }, -- Bright Baubles
    { id = 7307, bonus = 75, skill = 100, seconds = 600 }, -- Flesh Eating Worm
    { id = 291005, bonus = 60, skill = 50, seconds = 300 }, -- Camper's Lure (Forever; conjured, unique)
    { id = 6530, bonus = 50, skill = 50, seconds = 600 }, -- Nightcrawlers
    { id = 6811, bonus = 50, skill = 50, seconds = 600 }, -- Aquadynamic Fish Lens
    { id = 6529, bonus = 25, skill = 0, seconds = 600 }, -- Shiny Bauble
    { id = 268880, bonus = 25, skill = 0, seconds = 600 }, -- "Secret" Bait
}

-- Tooltip evidence: Forever build 70450, enUS, 20 October 2026.
-- These descriptions do not establish availability, sources or stacking.
MF.FISHING_HAT = {id=259846,bonus=25,skill=1,seconds=600}
MF.FISHING_SUPPLIES = {
    {id=5476,bonus=5,level=5,seconds=900,kind="food"},
    {id=4593,bonus=8,level=15,seconds=900,kind="food"},
    {id=8957,bonus=18,level=45,seconds=900,kind="food"},
    {id=13930,bonus=18,level=35,seconds=900,kind="food"},
    {id=286732,bonus=30,seconds=1800,kind="coin"},
}

function MF:LureEligibility(lure)
    local rank=self:FishingSkill()
    if (lure.skill or 0)>0 and not rank then return false,"Fishing skill unavailable" end
    if (rank or 0)<(lure.skill or 0) then return false,"Requires Fishing " .. lure.skill end
    return true,"Ready"
end

function MF:FishingHatStatus()
    local hat=self.FISHING_HAT
    local id=tonumber((InventoryLink(1) or ""):match("item:(%d+)"))
    if id~=hat.id then return false,"Equip to use" end
    local eligible,reason=self:LureEligibility(hat)
    if not eligible then return false,reason end
    if type(GetInventoryItemCooldown)~="function" then return false,"Cooldown unavailable" end
    local ok,start,duration,enabled=pcall(GetInventoryItemCooldown,"player",1)
    if not ok or type(start)~="number" or type(duration)~="number" then return false,"Cooldown unavailable" end
    if enabled~=1 then return false,enabled==0 and "Unavailable" or "Cooldown unavailable" end
    local left=math.max(0,start+duration-GetTime())
    if left>0 then return false,"Ready in " .. self:FormatClock(left),left end
    return true,"Ready"
end

------------------------------------------------------------------------
-- Lures
------------------------------------------------------------------------

-- Returns seconds left on your pole's lure, or nil if there isn't one.
function MF:LureTimeLeft()
    local hasEnchant, expiration = GetWeaponEnchantInfo()
    if not hasEnchant or not expiration then return end
    return expiration / 1000
end

function MF:BestLure()
    local best
    for _, lure in ipairs(self.LURES) do
        if ItemCount(lure.id) > 0 and self:LureEligibility(lure) then best=lure break end
    end
    -- An equipped, ready hat saves a consumable when its bonus is as good.
    if (not best or best.bonus<=self.FISHING_HAT.bonus) and self:FishingHatStatus() then return self.FISHING_HAT.id end
    return best and best.id
end

function MF:HasFishingPole()
    local link = InventoryLink(16)
    if not link then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    return classID == 2 and subclassID == FISHING_POLE_SUBCLASS
end

-- Music is borrowed for the equipped pole, not just one cast. Persist the
-- original so reload/login never mistakes our temporary zero for the user.
-- Music the player turns back up with the pole still out stays up, until
-- the pole comes off: they heard it go quiet and decided otherwise.
local musicKept = false
function MF:UpdateFishingMusic(restoreOnly)
    if not self.db or InCombatLockdown() then return end
    local pole = self:HasFishingPole()
    if not pole then musicKept = false end
    local mute = not restoreOnly and not musicKept and self.db.settings.muteMusicWithPole and pole
    local original = self.db.musicVolumeRestore
    if mute and original ~= nil then
        local volume = GetCVar("Sound_MusicVolume")
        if not self:IsSecret(volume) and (tonumber(volume) or 0) > 0 then
            musicKept, mute = true, false
            self.db.musicVolumeRestore = nil
            return
        end
    end
    if mute then
        if original == nil then
            local volume = GetCVar("Sound_MusicVolume")
            if self:IsSecret(volume) or not tonumber(volume) then return end
            original = volume
            self.db.musicVolumeRestore = original
        end
        if tonumber(GetCVar("Sound_MusicVolume")) ~= 0 then pcall(SetCVar, "Sound_MusicVolume", 0) end
    elseif original ~= nil then
        local ok, result = pcall(SetCVar, "Sound_MusicVolume", original)
        if ok and result ~= false and tonumber(GetCVar("Sound_MusicVolume")) == tonumber(original) then
            self.db.musicVolumeRestore = nil
        end
    end
end
MF:On("TFL_LOGIN", function(self) self:UpdateFishingMusic() end)
MF:On("PLAYER_EQUIPMENT_CHANGED", function(self, slot)
    if slot == 16 then self:UpdateFishingMusic() end
end)
MF:OnUnit("UNIT_INVENTORY_CHANGED", "player", function(self) self:UpdateFishingMusic() end)
MF:On("PLAYER_REGEN_ENABLED", function(self) self:UpdateFishingMusic() end)
MF:On("PLAYER_LOGOUT", function(self) self:UpdateFishingMusic(true) end)

local lastWarn = -math.huge
function MF:CheckLure()
    if not self.db.settings.lureWarning then return end
    if self:LureTimeLeft() or GetTime() - lastWarn < WARN_EVERY then return end
    lastWarn = GetTime()
    local lure = self:BestLure()
    if lure then
        self:Print(("No lure on your pole - click |cffffd100Lure|r on the board to apply %s.")
            :format(self:FishName(lure)))
    else
        self:Print("No lure on your pole, and none in your bags. Lures raise your fishing skill.")
    end
end

------------------------------------------------------------------------
-- Poles and gear sets
------------------------------------------------------------------------

local function FindPoleInBags()
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and (info.hyperlink or info.link)
            if link then
                local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
                if classID == 2 and subclassID == FISHING_POLE_SUBCLASS then
                    return link
                end
            end
        end
    end
end

-- Swapping a pole in and out, when you dual wield
--
-- A fishing pole is two-handed, so putting one on takes the off-hand weapon
-- off too, and putting your weapons back is two steps rather than one. Both
-- steps went wrong.
--
-- The off-hand was equipped in the same breath as the main hand, but at that
-- moment the pole is still in your hands and the off-hand slot is blocked by
-- it, so the game simply refused. It has to wait until the main hand has
-- actually landed, which is what clears the two-hander out of the way.
--
-- And equipping the main hand fires an equipment change, which is what we
-- hang "remember what they're holding" on - so the moment the one-hander
-- landed, with the off-hand slot still empty, we wrote down that they had no
-- off-hand. The memory destroyed itself one step before it was needed. So
-- nothing is remembered while a swap of our own is in flight.
local SWAP_TIMEOUT = 5 -- seconds before we assume a swap isn't coming
local swapping              -- { to = "pole"|"combat", offhand, at, sent }

function MF:RememberCombatWeapons()
    if swapping or self.outfitChanging then return end
    local main = InventoryLink(16)
    if not main or self:HasFishingPole() then return end
    self.cdb.gear.combatWeapon = main
    self.cdb.gear.combatOffhand = InventoryLink(17)
end

MF:On("TFL_LOGIN", MF.RememberCombatWeapons)
MF:On("PLAYER_EQUIPMENT_CHANGED", function(self, slot)
    if slot ~= 16 and slot ~= 17 then return end
    if not swapping then
        self:RememberCombatWeapons()
        return
    end
    if swapping.to == "pole" then
        -- Putting a pole on empties the off-hand slot, and that arrives as an
        -- equipment change of its own. Ending the guard on it would end it
        -- one event before the thing it is guarding against.
        if slot == 16 then swapping = nil end
    elseif not swapping.offhand then
        swapping = nil -- nothing to put back
    elseif InventoryLink(17) then
        swapping = nil -- it is on; that is the whole job done
    elseif not self:HasFishingPole() then
        -- What is actually being held, rather than how many events have
        -- arrived. Counting events assumed one change meant "the weapon
        -- has landed", and a client is free to announce the pole leaving
        -- before the one-hander arrives - in which case the off-hand was
        -- sent while the two-hander still blocked the slot, refused
        -- exactly as it was before any of this, and never tried again.
        -- Asking the hands cannot be wrong about it, and nothing here is
        -- spent if it has to ask twice.
        EquipFromBags(swapping.offhand, 17)
    end
end)

-- A swap that never finishes - bags full, or the off-hand gone from them -
-- must not leave us never remembering anything again.
--
-- Nor may it quietly cost you the off-hand for good. Letting go of the
-- guard and then remembering writes down what you are holding, which after
-- a failed restore is a main hand and an empty slot - so one bad swap
-- erased the off-hand, and every swap after it handed back the main hand
-- alone. It looks exactly like the fix having been undone, which is how it
-- was reported, and it is sticky in a way the original bug never was.
MF:OnTick(function(self)
    if swapping and GetTime() - swapping.at > SWAP_TIMEOUT then
        local stranded = swapping.to == "combat" and swapping.offhand
            and not InventoryLink(17) and swapping.offhand or nil
        swapping = nil
        self:RememberCombatWeapons()
        if stranded then
            self.cdb.gear.combatOffhand = stranded
            self:Print("Couldn't put your off-hand back on - is it still in your bags?")
        end
    end
end)

function MF:EquipPole()
    if self.outfitChanging then self:Print("Finish the outfit change first.") return end
    self.outfitSuppressPoleReturn = nil
    if InCombatLockdown() then self:Print("Leave combat before equipping your fishing pole.") return end
    if self:HasFishingPole() then
        self:Print("You're already holding a fishing pole.")
        return
    end
    local link = FindPoleInBags()
    if not link then
        self:Print("No fishing pole in your bags.")
        return
    end
    self:RememberCombatWeapons()
    -- Taking the pole up clears the off-hand slot, and that is an equipment
    -- change like any other. Without this it would be written down as "they
    -- had no off-hand" before we ever put the pole on.
    swapping = { to = "pole", at = GetTime() }
    if Equip(link, 16) then
        self:Print("Equipped " .. link)
    end
end

function MF:EquipCombatWeapon()
    if self.outfitChanging then self:Print("Finish the outfit change first.") return end
    if InCombatLockdown() then
        self:Print("Click Equip weapons or use your pole/weapon keybind to swap in combat.")
        return
    end
    local weapon = self.cdb.gear.combatWeapon
    if not weapon then
        self:Print("No combat weapon known yet - equip your weapon once and it'll be remembered.")
        return
    end
    -- Held here rather than read back later: the main hand landing is what
    -- triggers the off-hand, and the same event is what used to overwrite it.
    swapping = { to = "combat", offhand = self.cdb.gear.combatOffhand, at = GetTime() }
    -- By name is enough here: the hands are holding a pole, so there is
    -- no copy of this weapon already on to be found instead. It is the
    -- off-hand, going on beside an identical main hand, that needs more.
    Equip(weapon, 16)
end

function MF:TogglePole()
    if self:HasFishingPole() then
        self:EquipCombatWeapon()
    else
        self:EquipPole()
    end
end

function MF:SaveGear(which)
    local set = {}
    for _, slot in ipairs(FISHING_SLOTS) do
        set[slot] = InventoryLink(slot)
    end
    self.cdb.gear[which] = set
    self:Print(("Saved your current gear as the '%s' set."):format(which))
end

function MF:WearGear(which)
    if self.outfitChanging then self:Print("Finish the outfit change first.") return end
    if InCombatLockdown() then self:Print("Leave combat before changing a gear set.") return end
    local set = self.cdb.gear[which]
    if not set then
        self:Print(("No '%s' set saved. Wear the gear you want, then /tfl gear save %s.")
            :format(which, which))
        return
    end
    -- Equipment Manager does this better when it's available.
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID then
        local id = C_EquipmentSet.GetEquipmentSetID(which)
        if id then
            C_EquipmentSet.UseEquipmentSet(id)
            return
        end
    end
    for slot, link in pairs(set) do
        if link ~= InventoryLink(slot) then
            Equip(link, slot)
        end
    end
    self:Print(("Wearing your '%s' set."):format(which))
end

-- Something attacked you while you were holding a pole.
local swappedForCombat = false
function MF:OnCombatStart()
    if not self.db.settings.autoSwapCombat or not self:HasFishingPole() then return end
    if not self.cdb.gear.combatWeapon then return end
    swappedForCombat = true
    self:Print("Combat: click Equip weapons or press your pole/weapon keybind.")
end

function MF:OnCombatEnd()
    if not swappedForCombat then return end
    C_Timer.After(1, function()
        if InCombatLockdown() then return end
        if self.outfitChanging or self.outfitSuppressPoleReturn then swappedForCombat = false return end
        if self.db.settings.autoSwapCombat and not self:HasFishingPole() then self:EquipPole() end
        swappedForCombat = false
    end)
end

function MF:IsGearSwapBusy()
    return swapping ~= nil or self.outfitChanging == true
end

-- Prebuilt secure action: combat equipment changes require the player's
-- own click/key press. Never configure attributes or bindings in lockdown.
local weaponBindingOwner = CreateFrame("Frame")
function MF:CombatSwapMacro()
    local gear = self.cdb.gear
    local main = gear.combatWeapon and gear.combatWeapon:match("item:(%d+)")
    if not main then return "" end
    local lines = { "/equipslot [combat] 16 item:" .. main }
    local off = gear.combatOffhand and gear.combatOffhand:match("item:(%d+)")
    if off then
        local target = "item:" .. off
        -- Identical dual-wield weapons need a distinct bag copy, just as
        -- the out-of-combat restoration does. Equipping the main hand
        -- leaves this second copy in place for another press if necessary.
        if off == main and C_Container then
            local skipped = false
            for bag = 0, 4 do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    local link = info and (info.hyperlink or info.link)
                    if link and link:match("item:(%d+)") == off then
                        if skipped then target = bag .. " " .. slot break end
                        skipped = true
                    end
                end
                if target ~= "item:" .. off then break end
            end
        end
        lines[#lines + 1] = "/equipslot [combat] 17 " .. target
    end
    return table.concat(lines, "\n")
end

function MF:UpdateWeaponSwapButton()
    if InCombatLockdown() then return end
    local button = self.weaponSwapButton
    if not button then
        button = CreateFrame("Button", "TheFishingLogWeaponSwapButton", UIParent,
            "SecureActionButtonTemplate,BackdropTemplate")
        button:SetSize(230, 40)
        button:SetFrameStrata("DIALOG")
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "macro")
        button:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        button:SetBackdropColor(unpack(self.FILL_READING))
        self:CreateText(button, "GameFontNormal", "CENTER", 0, 0):SetText("Equip weapons - click")
        button:SetScript("PreClick", function()
            if InCombatLockdown() and MF.cdb.gear.combatWeapon
                and (MF:HasFishingPole() or (MF.cdb.gear.combatOffhand and not InventoryLink(17))) then
                swapping = { to = "combat", offhand = MF.cdb.gear.combatOffhand, at = GetTime() }
            end
        end)
        button:SetScript("PostClick", function(_, _, down)
            if not down and not InCombatLockdown() then MF:TogglePole() end
        end)
        self.weaponSwapButton = button
    end
    local macro = self:CombatSwapMacro()
    button:SetAttribute("macrotext", macro)
    local armed = macro ~= "" and self:HasFishingPole() and self.db.settings.autoSwapCombat
    if RegisterStateDriver then RegisterStateDriver(button, "visibility", armed and "[combat] show; hide" or "hide")
    else button:Hide() end
    ClearOverrideBindings(weaponBindingOwner)
    local first, second = GetBindingKey("THEFISHINGLOG_POLE")
    for _, key in ipairs({ first, second }) do
        SetOverrideBindingClick(weaponBindingOwner, true, key, button:GetName(), "LeftButton")
    end
end
MF:On("TFL_LOGIN", MF.UpdateWeaponSwapButton)
MF:On("PLAYER_EQUIPMENT_CHANGED", MF.UpdateWeaponSwapButton)
MF:On("BAG_UPDATE_DELAYED", MF.UpdateWeaponSwapButton)
MF:On("UPDATE_BINDINGS", MF.UpdateWeaponSwapButton)

------------------------------------------------------------------------
-- Secure buttons (the player clicks these; we only set them up)
------------------------------------------------------------------------

-- Bare secure buttons; the UI gives them their icons and tooltips.
local function SecureButton(name, parent, actionType)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", actionType)
    return b
end

function MF:CreateSecureButtons(parent)
    local cast = SecureButton("TheFishingLogCastButton", parent, "spell")
    cast:SetAttribute("spell", (C_Spell.GetSpellInfo(FISHING_SPELL) or {}).name or "Fishing")
    cast:SetScript("PreClick", function(button)
        if InCombatLockdown() then return end
        if self:CastPending() then button:SetAttribute("type", nil)
        else button:SetAttribute("type", "spell") end
    end)
    local lure = SecureButton("TheFishingLogLureButton", parent, nil)
    lure:Disable() -- no secure action until a bag scan finds a lure
    self.castButton, self.lureButton = cast, lure
    return cast, lure
end

-- Keep the lure button pointing at the best lure you're carrying. Secure
-- attributes can't change in combat, so leaving combat re-checks too.
function MF:UpdateLureButton()
    local button = self.lureButton
    if not button or InCombatLockdown() then return end
    local lure = self:BestLure()
    if button.lureInitialised and lure == self.lureButtonItem then return end
    button.lureInitialised = true
    self.lureButtonItem = lure
    if lure then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(lure))
        button:Enable()
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
        button:Disable()
    end
end

MF:On("TFL_LOGIN", MF.UpdateLureButton)
MF:On("BAG_UPDATE_DELAYED", MF.UpdateLureButton)
MF:On("BAG_UPDATE_COOLDOWN", MF.UpdateLureButton)
MF:On("SPELL_UPDATE_COOLDOWN", MF.UpdateLureButton)
MF:On("PLAYER_EQUIPMENT_CHANGED", MF.UpdateLureButton)
MF:On("SKILL_LINES_CHANGED",function(self) self:InvalidateSkill() self:UpdateLureButton() end)

------------------------------------------------------------------------
-- Fishing skill (cached; it changes rarely and the board reads it a lot)
------------------------------------------------------------------------

-- Read often rather than cached hard: a lure changes the number the moment
-- it goes on the pole, and a bar that takes ten seconds to notice looks
-- broken rather than cautious.
local SKILL_CACHE_SECONDS = 2
local skillCache, maxCache, bonusCache, skillReadAt = nil, nil, 0, -math.huge
local partsCache = { lure = 0, gear = 0, buffs = 0 }

-- Returns your skill, the most it can currently reach (75 as an apprentice,
-- 150 as a journeyman and so on, which is what the professions tab shows),
-- and the skill line's own modifier - the "+50" the Skills window shows,
-- which on this build is the lure and nothing else.
--
-- Which of the two modifier fields carries it varies by client, so take
-- whichever has something in it rather than adding both and counting the
-- same lure twice.
-- Modern Forever exposes a skill record directly. This modifier is a total,
-- so equipment/buff tooltip scans below must not be added to it again.
function MF:ReadModernFishingSkill()
    local api=C_SkillInfo
    if type(api)~="table" then return end
    local function Read(row)
        if type(row)~="table" or self:IsSecret(row.isHeader) or row.isHeader or self:IsSecret(row.rank) or self:IsSecret(row.maxRank)
            or type(row.rank)~="number" or type(row.maxRank)~="number"
            or row.rank~=row.rank or row.maxRank~=row.maxRank or row.rank<0
            or row.maxRank<1 or row.maxRank>1000 or row.rank>row.maxRank then return end
        local bonus=0
        for _,key in ipairs({"tempPoints","modifier"}) do
            local n=row[key]
            if self:IsSecret(n) or n~=nil and (type(n)~="number" or n~=n or math.abs(n)>1000) then return end
            bonus=bonus+(n or 0)
        end
        return row.rank,row.maxRank,math.max(0,bonus),true
    end
    if type(api.GetSkillLineInfoByID)=="function" then
        local ok,row=pcall(api.GetSkillLineInfoByID,356)
        if ok then local rank,cap,bonus,complete=Read(row);if rank then return rank,cap,bonus,complete end end
    end
    if type(api.GetNumSkillLines)~="function" or type(api.GetSkillLineInfo)~="function" then return end
    local ok,n=pcall(api.GetNumSkillLines)
    if not ok or self:IsSecret(n) or type(n)~="number" or n~=n or n<0 or n>1000 then return end
    for i=1,math.floor(n) do
        local got,row=pcall(api.GetSkillLineInfo,i)
        if got and type(row)=="table" and not self:IsSecret(row.skillID) and row.skillID==356 then
            local rank,cap,bonus,complete=Read(row);if rank then return rank,cap,bonus,complete end
        end
    end
end
local function ReadFishingSkill()
    local rank,cap,bonus,complete=MF:ReadModernFishingSkill()
    if rank then return rank,cap,bonus,complete end
    if GetProfessions then
        local fishing = select(4, GetProfessions())
        if fishing then
            local _, _, rank, maxRank, _, _, _, modifier = GetProfessionInfo(fishing)
            return rank, maxRank, tonumber(modifier) or 0
        end
    end
    if GetNumSkillLines then
        local want = C_Spell.GetSpellInfo(FISHING_SPELL)
        for i = 1, GetNumSkillLines() do
            local name, _, _, rank, temp, modifier, maxRank = GetSkillLineInfo(i)
            if want and name == want.name then
                local bonus = tonumber(modifier) or 0
                if bonus == 0 then bonus = tonumber(temp) or 0 end
                return rank, maxRank, bonus
            end
        end
    end
end

-- The three ways something can raise your fishing skill
--
-- They are genuinely three different mechanisms, and this client reports
-- them in three different places:
--
--   a lure      enchant on the pole   the skill line's own modifier
--   food        aura on you           the buff's text, nowhere else
--   +3 pole     equip bonus on item   the item's tooltip, nowhere else
--
-- So the skill line is read for the first and tooltips are read for the
-- other two. Numbers are matched off the client's own name for the skill
-- rather than the English word, so this holds up translated, and capped so
-- a line that merely mentions fishing beside a big number can't run away
-- with the bar.
local MAX_AURAS = 40
local SLOTS = 19
local SANE = 500
local scanner

-- Reading a tooltip, three ways, because none of them works everywhere.
--
-- Modern clients hand the lines over as data and never draw anything
-- (C_TooltipInfo). Older ones only draw, so you keep a tooltip of your own
-- off-screen, point it at the thing and read its font strings. A spell has
-- a third door: its description, which is the same sentence the buff shows.
--
-- This client answers to the first and the third and ignores the second,
-- which is worth knowing, because a rewrite that kept only the second is
-- how a working +8 quietly became +0.
function MF:TooltipTextLines(fetch, ...)
    if not fetch then return end
    local ok, data = pcall(fetch, ...)
    if not ok or self:IsSecret(data) or type(data) ~= "table" then return end
    local rows = data.lines
    if self:IsSecret(rows) or type(rows) ~= "table" then return end
    local surface = TooltipUtil and TooltipUtil.SurfaceArgs
    -- Surfacing mutates Blizzard-owned colour/argument tables. On secret-
    -- capable clients consume public text directly, without touching colours.
    if type(issecretvalue) == "function" then surface = nil end
    if surface then pcall(surface, data) rows = data.lines end
    local out = {}
    for _, line in ipairs(rows) do
        if not self:IsSecret(line) and type(line) == "table" then
            if surface then pcall(surface, line) end
            local text = line.leftText
            if not self:IsSecret(text) and type(text) == "string" and text ~= "" then out[#out + 1] = text end
        end
    end
    return out[1] and out or nil
end

local function DrawnLines(setter)
    if InCombatLockdown() or type(issecretvalue) == "function" then return end
    if not scanner then
        scanner = CreateFrame("GameTooltip", "TheFishingLogScan", nil, "GameTooltipTemplate")
        scanner:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanner:ClearLines()
    if not pcall(setter, scanner) then return end
    local out = {}
    for i = 1, scanner:NumLines() do
        local fs = _G["TheFishingLogScanTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then out[#out + 1] = text end
    end
    return out[1] and out or nil
end

-- A buff's description, whole. Safe to treat as one line where a tooltip
-- isn't: it's a sentence about the buff, not a name followed by a damage
-- range waiting to be mistaken for a skill bonus.
local function SpellLines(spellID)
    if MF:IsSecret(spellID) then return end
    local get = C_Spell and C_Spell.GetSpellDescription
    if not get or not spellID then return end
    local ok, desc = pcall(get, spellID)
    if not ok or MF:IsSecret(desc) or type(desc) ~= "string" or desc == "" then return end
    return { desc }
end

-- One line at a time, never the whole tooltip joined up: "Blump Family
-- Fishing Pole" followed later by "13 - 21 Damage" would otherwise read as
-- a fishing bonus of 13. `must` narrows it further where a tooltip holds
-- several fishing numbers that aren't all ours to count.
local function FirstMatch(lines, word, must)
    for _, line in ipairs(lines or {}) do
        if not must or line:find(must, 1, true) then
            local n = tonumber(line:match(word .. "[^%d]-(%d+)"))
            if n and n > 0 and n <= SANE then return n end
        end
    end
    return 0
end

local function SkillWord()
    local info = C_Spell.GetSpellInfo(FISHING_SPELL)
    return ((info and info.name) or "Fishing"):gsub("(%W)", "%%%1")
end

-- Watched, not polled. The board asks for your skill every second and
-- the cache behind it is two seconds deep, so this was reading forty
-- buff tooltips every couple of seconds for a number that changes when
-- a buff does and at no other time. Same treatment as gear.
local auraCache, auraDirty = 0, true

local function AuraBonus(word)
    if InCombatLockdown() then return auraCache end
    if not auraDirty then return auraCache end
    local total = 0
    for i = 1, MAX_AURAS do
        local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if MF:IsSecret(aura) then return auraCache end
        if not aura then break end
        local lines = MF:TooltipTextLines(C_TooltipInfo and C_TooltipInfo.GetUnitBuff, "player", i)
            or DrawnLines(function(t) t:SetUnitBuff("player", i) end)
            or SpellLines(aura.spellId)
        total = total + FirstMatch(lines, word)
    end
    auraCache, auraDirty = total, false
    return total
end

MF:OnUnit("UNIT_AURA", "player", function() auraDirty = true end)

-- Scanned only when you change what you're wearing; nineteen tooltips is
-- too much to do twice a second for a number that moves when you equip
-- something and at no other time.
local gearCache, gearDirty = 0, true

local function EquipBonus(word)
    if InCombatLockdown() then return gearCache end
    if not gearDirty then return gearCache end
    -- The game's own "Equip:" is what separates a permanent bonus from the
    -- lure sitting above it on the same tooltip and the "Requires Fishing
    -- (1)" sitting below - both of which carry a number we mustn't count.
    local must = (ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"):gsub("%%s", ""):gsub("%s+$", "")
    local total = 0
    for slot = 1, SLOTS do
        local lines = MF:TooltipTextLines(C_TooltipInfo and C_TooltipInfo.GetInventoryItem, "player", slot)
            or DrawnLines(function(t) t:SetInventoryItem("player", slot) end)
        total = total + FirstMatch(lines, word, must)
    end
    gearCache, gearDirty = total, false
    return total
end

MF:On("PLAYER_EQUIPMENT_CHANGED", function() gearDirty = true end)
MF:On("TFL_LOGIN", function() auraDirty = true end)
MF:On("TFL_LOGIN", function() gearDirty = true end)

-- Whether this build counts equipment in the skill line is answerable at
-- exactly one moment: with no lure on the pole, anything the line reports
-- has to be coming from gear. We remember that answer rather than assume
-- one, so a build that starts folding gear in doesn't get it counted twice.
local lineCountsGear = false

-- Returns skill, its ceiling, the whole bonus, and where it came from:
-- { lure, gear, buffs }, which always add up to the whole.
-- Forget the cached read. A skill-up is announced the instant it happens
-- and a two second old number would miss the very thing we're watching.
function MF:InvalidateSkill()
    skillReadAt = -math.huge
end

function MF:FishingSkill()
    if InCombatLockdown() then return skillCache, maxCache, bonusCache, partsCache end
    if GetTime() - skillReadAt >= SKILL_CACHE_SECONDS then
        local ok, skill, max, line, complete = pcall(ReadFishingSkill)
        skillCache, maxCache = ok and skill or nil, ok and max or nil
        line = math.max(0, (ok and line) or 0)

        local word = SkillWord()
        local okGear, gear = pcall(EquipBonus, word)
        gear = math.max(0, (okGear and gear) or 0)
        local okAura, buffs = pcall(AuraBonus, word)
        buffs = math.max(0, (okAura and buffs) or 0)

        if not self:LureTimeLeft() then lineCountsGear = line > 0 and gear > 0 end
        -- When the line already holds the gear, the lure's share is what's
        -- left of it; otherwise the line is the lure and gear stands alone.
        local lure = lineCountsGear and math.max(0, line - gear) or line
        partsCache = { lure = lure, gear = gear, buffs = buffs }
        if complete then
            gear=math.min(gear,line)
            buffs=math.min(buffs,math.max(0,line-gear))
            lure=math.max(0,line-gear-buffs)
            partsCache={lure=lure,gear=gear,buffs=buffs}
            bonusCache=line
        else bonusCache = lure + gear + buffs end
        skillReadAt = GetTime()
    end
    return skillCache, maxCache, bonusCache, partsCache
end

-- Undocumented: every line the addon can see that mentions your skill, and
-- which of the three readers produced it. Three different clients report
-- these three bonuses in three different ways, so when a number goes
-- missing the useful question isn't "what did it total" but "what text did
-- it have to work with" - and that can only be answered from in the game.
MF:Command("skilldump", "Other", nil, function(self)
    local word = SkillWord()
    self:Print("What the addon can see about your fishing skill:")
    local rank, max, bonus, parts = self:FishingSkill()
    print(("  skill %s / %s, bonus +%d (lure %d, gear %d, buffs %d)"):format(
        tostring(rank), tostring(max), bonus, parts.lure, parts.gear, parts.buffs))

    local function Show(what, lines, how)
        if not lines then
            print(("  %s: nothing readable"):format(what))
            return
        end
        print(("  %s: %d lines via %s"):format(what, #lines, how))
        for _, line in ipairs(lines) do
            if line:find(word) then
                print(("      |cffffd100%s|r  -> %s"):format(line,
                    tostring(tonumber(line:match(word .. "[^%d]-(%d+)")))))
            end
        end
    end

    for i = 1, MAX_AURAS do
        local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        if self:IsSecret(aura) then break end
        local lines, how = self:TooltipTextLines(C_TooltipInfo and C_TooltipInfo.GetUnitBuff, "player", i), "data"
        if not lines then
            lines, how = DrawnLines(function(t) t:SetUnitBuff("player", i) end), "drawn"
        end
        if not lines then lines, how = SpellLines(aura.spellId), "description" end
        Show("buff " .. (aura.name or i), lines, how)
    end

    local must = (ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"):gsub("%%s", ""):gsub("%s+$", "")
    print(("  the \"equip\" marker being matched: %q"):format(must))
    for slot = 1, SLOTS do
        if GetInventoryItemID and GetInventoryItemID("player", slot) then
            local lines, how = self:TooltipTextLines(C_TooltipInfo and C_TooltipInfo.GetInventoryItem,
                "player", slot), "data"
            if not lines then
                lines, how = DrawnLines(function(t) t:SetInventoryItem("player", slot) end), "drawn"
            end
            Show("slot " .. slot, lines, how)
        end
    end
end)

------------------------------------------------------------------------
-- Events and commands
------------------------------------------------------------------------

MF:On("TFL_FISHING_CAST", MF.CheckLure)

-- Full bags
--
-- With nowhere to put it, a fish stays in the loot window and is gone when
-- the window closes - a trophy included. Said as the line goes out, while
-- there is still time to make room, and on screen as well as in chat
-- because the bobber is where the player is looking.
local BAG_WARN_EVERY = 60

-- Free slots that can hold a fish: ordinary bags only (bag type 0), not
-- quivers, soul bags or profession bags. Nil when the client can't say.
function MF:FreeBagSlots()
    local api = C_Container
    local count = api and api.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if type(count) ~= "function" then return nil end
    local free, known = 0, false
    for bag = 0, 4 do
        local ok, n, family = pcall(count, bag)
        if ok and type(n) == "number" and not self:IsSecret(n) then
            known = true
            if (family or 0) == 0 then free = free + n end
        end
    end
    return known and free or nil
end

local lastBagWarn = -math.huge
function MF:CheckBagSpace()
    if GetTime() - lastBagWarn < BAG_WARN_EVERY then return end
    if self:FreeBagSlots() ~= 0 then return end
    lastBagWarn = GetTime()
    self:Print("|cffff5a5aYour bags are full.|r Make room before you loot, or what you catch "
        .. "may stay in the loot window and be lost when it closes.")
    if self.FloatWarning then self:FloatWarning("Bags full - make room") end
end
MF:On("TFL_FISHING_CAST", MF.CheckBagSpace)
MF:On("PLAYER_REGEN_DISABLED", MF.OnCombatStart)
MF:On("PLAYER_REGEN_ENABLED", function(self)
    self:OnCombatEnd()
    self:UpdateLureButton()
    self:UpdateWeaponSwapButton()
end)

MF:Command("pole", "Gear", "/tfl pole - swap between your fishing pole and combat weapon", MF.TogglePole)

MF:Command("gear", "Gear", "/tfl gear fishing|combat - wear a saved set", function(self, args)
    local saving = args[1] == "save"
    local which = saving and args[2] or args[1]
    if which ~= "fishing" and which ~= "combat" then
        self:Print("Use /tfl gear fishing, /tfl gear combat, or /tfl gear save fishing|combat.")
    elseif saving then
        self:SaveGear(which)
    else
        self:WearGear(which)
    end
end)
-- Help-only entry so the save form is listed too.
MF:Command({}, "Gear", "/tfl gear save fishing|combat - save what you're wearing as a set")

------------------------------------------------------------------------
-- Casting from a button or a key
--
-- Only a real press of a real button can cast a spell, so the binding is
-- pointed straight at a secure button of our own rather than at any code of
-- ours. It's live only while a fishing pole is in your hands, which keeps it
-- out of the way the rest of the time.
--
-- Bindings can't be changed during a fight, so one that's already up stays
-- up until the fight ends. Binding it to plain right-click costs you camera
-- turning while a pole is out, which is why that isn't the default.
------------------------------------------------------------------------

local DOUBLE_WINDOW = 0.4  -- seconds between the two presses of a double
local DOUBLE_MIN = 0.04    -- faster than this is one press the game saw twice
local MOUSE = "BUTTON2"    -- right-click, handled a click at a time
local binder = CreateFrame("Frame") -- owns the bindings, so they lift cleanly
local armedAt = -math.huge
local mousePress

local function CastOnKeyDown()
    return GetCVar("ActionButtonUseKeyDown") ~= "0"
end

function MF:CastBinding()
    local key = self.db.settings.castClick
    return key ~= "" and key or nil
end

-- What people actually call the buttons
--
-- The game calls right mouse BUTTON2 and so does this command, but nobody
-- has ever called it that out loud. Asked for "mouse2" the addon bound a
-- key the game has never heard of, said "Press MOUSE2 twice to cast", and
-- left nothing casting at all - and since BUTTON2 is the default, that is
-- what happened to anyone who changed the binding and tried to put it back
-- in their own words.
local ALIASES = {
    MOUSE1 = "BUTTON1", M1 = "BUTTON1", LMB = "BUTTON1", LEFT = "BUTTON1",
    LEFTCLICK = "BUTTON1", LEFTMOUSE = "BUTTON1", MOUSELEFT = "BUTTON1",
    MOUSE2 = "BUTTON2", M2 = "BUTTON2", RMB = "BUTTON2", RIGHT = "BUTTON2",
    RIGHTCLICK = "BUTTON2", RIGHTMOUSE = "BUTTON2", MOUSERIGHT = "BUTTON2",
    MOUSE3 = "BUTTON3", M3 = "BUTTON3", MMB = "BUTTON3", MIDDLE = "BUTTON3",
    MIDDLECLICK = "BUTTON3", MIDDLEMOUSE = "BUTTON3",
    MOUSE4 = "BUTTON4", M4 = "BUTTON4", MOUSE5 = "BUTTON5", M5 = "BUTTON5",
}

-- And said back the same way. BUTTON3 is a button nobody owns.
local function Said(key)
    return (tostring(key):gsub("BUTTON(%d)", "mouse%1"))
end

-- Modifiers are kept as they are, so shift-mouse2 is still shift-something.
function MF:CastKeyFromWords(key)
    key = (key or ""):upper():gsub("%s+", ""):gsub("_", "-")
    if key == "" then return "" end
    local prefix, base = key:match("^(.-%-)([^%-]+)$")
    if not base then prefix, base = "", key end
    return prefix .. (ALIASES[base] or base)
end

-- Did a binding actually take? An unknown key name doesn't raise anything,
-- it simply doesn't bind - so without asking, the addon's own report of
-- what it just did is the one thing that can't be trusted.
local function Bound(key)
    if not GetBindingAction then return true end
    local ok, action = pcall(GetBindingAction, key, true)
    return ok and action ~= nil and action ~= ""
end

-- Sharing the button with somebody else
--
-- FishFry offers double-right-click casting too, and two addons binding
-- the same button will fight over it. What that looks like from the
-- player's side is casting that works every other time - which gets
-- reported as our bug, and costs somebody an evening before anyone thinks
-- to ask what else is loaded.
--
-- We can't see what they've set, only that they're there, so the warning
-- says what we know and leaves the choice alone. Said once ever, not once
-- a session: plenty of people will run both on purpose.
local RIVALS = { FishFry = "Another fishing addon" }

function MF:CastRival()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not loaded then return end
    for folder, name in pairs(RIVALS) do
        local ok, yes = pcall(loaded, folder)
        if ok and yes then return name end
    end
end

local CLASH_DELAY = 14 -- seconds: after the news panel, before the update notice

MF:On("TFL_LOGIN", function(self)
    -- Only when we're on right-click ourselves. Their casting is a double
    -- right-click, so a player who moved ours to a key has nothing to hear.
    if self:CastBinding() ~= MOUSE then return end
    local rival = self:CastRival()
    if not rival or self.db.castClashTold == rival then return end
    self.db.castClashTold = rival
    C_Timer.After(CLASH_DELAY, function()
        -- A version of theirs that can be talked to needs no warning: the
        -- two addons have already sorted it out between them by now.
        local handling = self:FishFryCompat() and self:CompatHandling()
        if handling and #handling > 0 then
            self:Print(("|cffffd100%s is running alongside us|r - sorted out between us. "
                .. "The Fishing Log is doing %s; %s's versions are paused."):format(
                rival, self.List(handling), rival))
            print(("  |cff858585Turn any of ours off and %s's comes straight back.|r"):format(rival))
            return
        end
        self:Print(("|cffff8000%s is running alongside us.|r It casts on right-click too, "
            .. "and only one addon can have the button."):format(rival))
        print(("  |cff858585If casting misbehaves, turn it off in one of us. |cffffd100/tfl cast off|r "
            .. "hands right-click to %s, or |cffffd100/tfl cast f|r moves ours to a key.|r"):format(rival))
    end)
end)

-- Will the game bind this at all? Asked on its own because the binding
-- only goes on while a pole is in hand, and somebody setting their key at
-- the bank would otherwise be told it worked and find out it hadn't an
-- hour later, at the water, with no idea which of the two was to blame.
function MF:CastKeyWorks(key)
    if key == MOUSE or key == "" then return true end
    if not self.castBindButton or InCombatLockdown() then return true end
    local ok = pcall(SetOverrideBindingClick, binder, true, key, self.castBindButton:GetName())
    local good = ok and Bound(key)
    ClearOverrideBindings(binder)
    return good
end

-- Why right-click insists on the double press
--
-- Binding a button is binding the whole press, not the click: the game
-- hands it to whatever is bound and stops doing its own job with it. For a
-- key you don't otherwise use that is exactly what you want. For right
-- mouse it is not, because the game's own job for right mouse is turning
-- the camera - so a single-press binding means holding it to look around
-- casts at your feet instead.
--
-- The double press is what makes it liveable: nothing is bound until the
-- second click of a double has been seen, and it is unbound again on the
-- way up, so right-click goes on turning the camera every other moment.
-- That isn't a preference, it's the only way the two can share a button,
-- so for the mouse buttons the game already needs it is not optional.
local CAMERA_BUTTONS = { BUTTON1 = true, BUTTON2 = true }

function MF:CastNeedsDouble()
    return CAMERA_BUTTONS[self:CastBinding() or ""] == true
end

function MF:CastDouble()
    return self.db.settings.castDouble or self:CastNeedsDouble()
end

-- Said rather than silently ignored: a setting that does nothing where you
-- put it is worse than one that explains itself.
function MF:CastDoubleNote()
    if self.db.settings.castDouble or not self:CastNeedsDouble() then return end
    return ("|cff858585A single press can't work on %s - the game needs it for turning the "
        .. "camera, and binding the whole press takes that away. On any other key a single "
        .. "press is fine: try |cffffd100/tfl cast f|r|cff858585.|r"):format(
        (self:CastBinding() or ""):lower())
end

-- While the line is out, the same button reaches for the bobber instead.
-- Nothing lets an addon loot a bobber itself - it's a click on something in
-- the world - but the game's own "interact with target" will do it, provided
-- the game counts the bobber as what you're reaching for. These three
-- settings are what make it so, and they're put back the moment the line is
-- in, because they're the player's settings and not ours.
-- Reeling uses the native Interact action. A missed reach keeps reeling;
-- Shift plus the fishing key (or Shift double-right-click) explicitly recasts.
local INTERACT = "INTERACTTARGET"
local pendingUntil, pendingGUID, pendingSerial = -math.huge, nil, 0
local guardButton

local function Public(value)
    return not issecretvalue or not issecretvalue(value)
end

function MF:CastPending()
    return GetTime() < pendingUntil
end

local function FishingSpell(spellID)
    if not Public(spellID) then return false end
    if spellID == FISHING_SPELL then return true end
    if type(spellID) ~= "number" then return false end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    local own = C_Spell.GetSpellInfo(FISHING_SPELL)
    return ok and info and own and Public(info.name) and Public(own.name)
        and info.name == own.name
end

function MF:ReelNPCRisk()
    for _, unit in ipairs({ "target", "softinteract" }) do
        local ok, guid = pcall(UnitGUID, unit)
        if not ok or not Public(guid) then return true end
        if type(guid) == "string"
            and (guid:match("^Creature%-") or guid:match("^Vehicle%-")) then
            local readable, interactable = false, nil
            if type(UnitIsInteractable) == "function" then
                readable, interactable = pcall(UnitIsInteractable, unit)
            end
            if not readable or not Public(interactable) or interactable ~= false then
                return true
            end
        end
    end
    return false
end

local function ClearPending(self)
    pendingUntil, pendingGUID = -math.huge, nil
    pendingSerial = pendingSerial + 1
    self:ApplyCastBinding()
end

MF:OnUnit("UNIT_SPELLCAST_SENT", "player", function(self, unit, _, guid, spellID)
    if unit ~= "player" or not FishingSpell(spellID) then return end
    pendingSerial = pendingSerial + 1
    local serial = pendingSerial
    pendingUntil = GetTime() + 2
    pendingGUID = Public(guid) and guid or nil
    -- The spell's initiating input must finish before changing its binding.
    C_Timer.After(0, function()
        if pendingSerial == serial then self:ApplyCastBinding() end
    end)
    C_Timer.After(2, function()
        if pendingSerial == serial then ClearPending(self) end
    end)
end)

for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    MF:OnUnit(event, "player", function(self, unit, guid, spellID)
        if unit ~= "player" or not FishingSpell(spellID) or not self:CastPending() then return end
        if pendingGUID and (not Public(guid) or guid ~= pendingGUID) then return end
        ClearPending(self)
    end)
end

local SOFT_TARGET = {
    SoftTargetInteract = 3,      -- reach for game objects, not just NPCs
    SoftTargetInteractArc = 2,   -- however you're facing
    SoftTargetInteractRange = 60,
}
local saved -- the player's own values, while ours are in place

local function SoftTarget(on)
    -- These CVars are protected in combat on the Forever beta. pcall does
    -- not prevent ADDON_BLOCKED reports: do not attempt the write at all.
    if InCombatLockdown() then return false end
    saved = saved or (MF.db and MF.db.softTargetRestore)
    if on then
        if saved then return end
        saved = {}
        MF.db.softTargetRestore = saved
        for cvar, value in pairs(SOFT_TARGET) do
            local current = GetCVar(cvar)
            if cvar == "SoftTargetInteract" then
                current = MF:TakeBobberInteractRestore(current) or current
            end
            saved[cvar] = current
            pcall(SetCVar, cvar, value)
        end
        return
    end
    if not saved then return end
    for cvar in pairs(SOFT_TARGET) do
        local value = saved[cvar]
        if value ~= nil then
            local ok, result = pcall(SetCVar, cvar, value)
            if ok and result ~= false then saved[cvar] = nil end
        end
    end
    if not next(saved) then saved, MF.db.softTargetRestore = nil, nil end
end

------------------------------------------------------------------------
-- Hearing the bite
--
-- The splash is quiet, and losing a fish because you didn't hear it over
-- a boat, a battle or your own music is the most irritating thing in
-- fishing. There is no bite event - nothing tells an addon the bobber has
-- gone under - so playing our own cue isn't on offer. The only thing
-- available is making the game's own splash easier to hear.
--
-- So it borrows the game's sound settings while the line is out and puts
-- them straight back, the same borrow-and-return as the soft-target
-- settings above:
--   - sound, and sound effects, are switched on if they were off;
--   - the sound effects and master volumes go up to full;
--   - sound keeps playing while WoW is in the background;
--   - your character's "I can't do that" speech is quiet, and ambience
--     too if asked for, so there is less to hear the splash over.
-- The volumes only ever go up: somebody already at full hears no change.
--
-- Off by default. Changing what the game sounds like is the sort of thing
-- that should be asked for rather than arrive with an update.
------------------------------------------------------------------------

local SPLASH_VOLUME = "1" -- sound effects and master, at least, while casting

-- Restored in this order. The parent switches come first, going on and
-- coming back, because some clients carry a parent's change down to the
-- categories under it.
local SPLASH_CVARS = {
    "Sound_EnableAllSound", "Sound_EnableSFX", "Sound_SFXVolume", "Sound_MasterVolume",
    "Sound_EnableSoundWhenGameIsInBG", "Sound_EnableAmbience", "Sound_EnableErrorSpeech",
}

-- What a cast borrows: { cvar, value, only raise it }.
local function SplashRules()
    local s = MF.db.settings
    local rules = {
        { "Sound_EnableAllSound", "1" },
        { "Sound_EnableSFX", "1" },
        { "Sound_SFXVolume", SPLASH_VOLUME, true },
        { "Sound_MasterVolume", SPLASH_VOLUME, true },
    }
    if s.splashBackground ~= false then rules[#rules + 1] = { "Sound_EnableSoundWhenGameIsInBG", "1" } end
    if s.splashAmbience == true then rules[#rules + 1] = { "Sound_EnableAmbience", "0" } end
    if s.splashErrorSpeech ~= false then rules[#rules + 1] = { "Sound_EnableErrorSpeech", "0" } end
    return rules
end

local function ReadSound(cvar)
    local value = GetCVar(cvar)
    if value == nil or MF:IsSecret(value) then return nil end
    return tostring(value)
end

local function SameSound(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return math.abs(na - nb) < 0.005 end
    return a == b
end

-- What we hold, as { [cvar] = { old = theirs, applied = ours } }. Kept in
-- saved data, like the music and soft-target restores, so a crash or a
-- failed logout mid-cast can't leave the player's settings ours. 1.0.8 and
-- older kept only the sound effects volume, under its own name.
local function Held()
    local db = MF.db
    if not db then return nil end
    if db.sfxVolumeRestore ~= nil then
        db.soundRestore = db.soundRestore or {}
        db.soundRestore.Sound_SFXVolume = db.soundRestore.Sound_SFXVolume
            or { old = tostring(db.sfxVolumeRestore), applied = "0.7" }
        db.sfxVolumeRestore = nil
    end
    return db.soundRestore
end

local function Louder(on, force)
    if not MF.db then return end
    local held = Held()
    if on then
        if held or not MF.db.settings.loudSplash then return end
        if MF:Yielded("sound.fishingHelper") then return end
        held = {}
        for _, rule in ipairs(SplashRules()) do
            local cvar, want, raise = rule[1], rule[2], rule[3]
            local now = ReadSound(cvar)
            local already = now == nil
                or (raise and (tonumber(now) or 0) >= tonumber(want))
                or (not raise and SameSound(now, want))
            if not already then
                local ok, result = pcall(SetCVar, cvar, want)
                if ok and result ~= false then held[cvar] = { old = now, applied = want } end
            end
        end
        if next(held) then MF.db.soundRestore = held end
        return
    end
    if not held then return end
    for _, cvar in ipairs(SPLASH_CVARS) do
        local entry = held[cvar]
        if type(entry) ~= "table" or entry.old == nil then
            held[cvar] = nil
        else
            -- A setting that isn't the one we set was changed by the player
            -- while the line was out, and is theirs to keep: putting the
            -- old one back would undo what they had just done.
            local now = ReadSound(cvar)
            if not force and now ~= nil and not SameSound(now, entry.applied) then
                held[cvar] = nil
            else
                local ok, result = pcall(SetCVar, cvar, entry.old)
                if ok and result ~= false then held[cvar] = nil end
            end
        end
    end
    if not next(held) then MF.db.soundRestore = nil end
end

-- A restore left over from a session that never reached logout.
MF:On("TFL_LOGIN", function(self)
    if Held() ~= nil and not self:IsCasting() then Louder(false) end
end)

-- For the compatibility layer: give the settings back now, because
-- somebody else has taken the job on mid-cast.
function MF:RestoreSplashVolume() Louder(false) end

-- Sound or sound effects switched off. Louder splash switches them on for
-- the cast, but with the setting off nothing would, so it's worth saying.
function MF:SplashMuted()
    if GetCVar("Sound_EnableAllSound") == "0" then return "all sound is off" end
    if GetCVar("Sound_EnableSFX") == "0" then return "sound effects are off" end
    return nil
end

MF:On("TFL_FISHING_CAST", function() Louder(true) end)

-- Every sound setting we have borrowed goes back now, whatever state the
-- cast is in. For the moment something has gone wrong - a crash, a stuck
-- cast - and the game is louder or quieter than the player left it.
function MF:RestoreSound()
    local held = Held() ~= nil or self.db.musicVolumeRestore ~= nil
    Louder(false, true)
    if self.db.musicVolumeRestore ~= nil then
        musicKept = true
        self:UpdateFishingMusic(true)
    end
    return held
end

MF:Command({ "restoresound", "fixsound" }, "Solo",
    "/tfl restoresound - put your sound and music volume back the way you had them",
    function(self)
        if InCombatLockdown() then
            self:Print("That has to wait until combat ends.")
            return
        end
        if self:RestoreSound() then
            self:Print("Your sound and music volume are back the way you had them.")
        else
            self:Print("Nothing to put back: your sound settings are already your own.")
        end
    end)
MF:On("TFL_FISHING_DONE", function() Louder(false) end)

MF:Command("splash", "Solo", "/tfl splash - turn the sound up while the line is out, so you hear the bite",
    function(self)
        local on = not self.db.settings.loudSplash
        self.db.settings.loudSplash = on
        if not on then Louder(false) end
        self:Print(("Louder splash: |cffffd100%s|r."):format(on and "on" or "off"))
        local muted = on and self:SplashMuted()
        if muted then
            print(("  |cffffd100At the moment %s; it switches them on while your line is out.|r"):format(muted))
        end
    end)

-- Whatever happens, the player's settings go back when they log out.
MF:On("PLAYER_LOGOUT", function()
    SoftTarget(false)
    Louder(false)
end)

function MF:ApplyCastBinding(fishing)
    if fishing==nil then fishing=self:IsCasting() end
    local key = self:CastBinding()
    -- Another fishing addon has taken casting on, so we let go of the
    -- button entirely rather than the two of us trading it mid-cast.
    if key == MOUSE and self:Yielded("casting.doubleRightClick") then key = nil end
    if key and key ~= MOUSE and self:Yielded("fishing.oneButton") then key = nil end
    local ours = key ~= nil and self:HasFishingPole()

    -- SoftTarget handles its own combat guard and retains pending restores.
    -- PLAYER_REGEN_ENABLED retries once protected CVar writes are permitted.
    SoftTarget(ours and fishing and not self:Yielded("fishing.softInteractAssist") or false)

    local button = self.castBindButton
    if not button or InCombatLockdown() then return end
    -- Target and equipment updates can arrive before the second click is released.
    if mousePress and ours and key == MOUSE
        and (not mousePress.reeling or (fishing and not self:ReelNPCRisk())) then
        return true
    end
    mousePress = nil
    ClearOverrideBindings(binder)
    if not ours then return end
    -- Right-click is taken over for the instant it's being double-clicked,
    -- never held, so it goes on turning the camera the rest of the time.
    if key == MOUSE then return true end
    -- A key the game doesn't recognise is the player's typo, not an error -
    -- but it has to come back as a failure, because the binding silently
    -- not happening is exactly what it looks like from the player's side.
    if self:CastPending() or (fishing and self:ReelNPCRisk()) then
        return guardButton and pcall(SetOverrideBindingClick, binder, true, key,
            guardButton:GetName()) and Bound(key)
    end
    if fishing then
        local ok = pcall(SetOverrideBinding, binder, true, key, INTERACT) and Bound(key)
        if not key:find("%-") then
            local recastKey = "SHIFT-" .. key
            local assigned = GetBindingAction(recastKey)
            if not assigned or assigned == "" then
                pcall(SetOverrideBindingClick, binder, true, recastKey, button:GetName())
            end
        end
        return ok
    end
    return pcall(SetOverrideBindingClick, binder, true, key, button:GetName()) and Bound(key)
end

function MF:SetupCastBinding(parent)
    guardButton = CreateFrame("Button", "TheFishingLogCastGuard", parent, "SecureActionButtonTemplate")
    guardButton:RegisterForClicks("AnyDown", "AnyUp")
    local b = CreateFrame("Button", "TheFishingLogCastBind", parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("spell", (C_Spell.GetSpellInfo(FISHING_SPELL) or {}).name or "Fishing")
    b:SetAttribute("type", "spell")
    -- The first press of a double arms it and does nothing; the second casts.
    b:SetScript("PreClick", function(self, _, down)
        if InCombatLockdown() then return end
        -- Both edges reach PreClick. Count only the edge WoW uses for the action.
        if down ~= CastOnKeyDown() then
            self:SetAttribute("type", nil)
            return
        end
        if MF:CastPending() then
            self:SetAttribute("type", nil)
            return
        end
        if mousePress or not MF:CastDouble() then
            self:SetAttribute("type", "spell")
            return
        end
        local now = GetTime()
        if now - armedAt <= DOUBLE_WINDOW then
            armedAt = -math.huge
            self:SetAttribute("type", "spell")
        else
            armedAt = now
            self:SetAttribute("type", nil)
        end
    end)
    MF.castBindButton = b
end

-- Nothing is bound to right-click until we've seen the second click of a
-- double, and it's unbound again after that click. Anywhere else
-- - over the UI, in combat, with loot open, without a pole - we keep out of
-- the way entirely.
local lastRightClick = -math.huge

local function OverTheWorld()
    local foci = GetMouseFoci and GetMouseFoci()
    if foci and foci[1] then
        for _, focus in ipairs(foci) do
            if not Public(focus) then return false end
            if focus == WorldFrame then return true end

            -- Motion-only overlays can appear above the world without taking clicks.
            local ok, clicks = pcall(function() return focus:IsMouseClickEnabled() end)
            if not ok or not Public(clicks) or clicks ~= false then return false end
        end
        return true
    end

    local focus = GetMouseFocus and GetMouseFocus()
    return Public(focus) and (focus == nil or focus == WorldFrame)
end

-- Bound the override even if mouse-up never arrives. Key-up players get
-- more time to release the button before it reverts to camera control.
local HOLD_DOWN, HOLD_UP = 0.3, 1

local function ReleaseMouse(press)
    if not press or mousePress ~= press then return end
    mousePress = nil
    if InCombatLockdown() then return end
    ClearOverrideBindings(binder)
end

MF:On("GLOBAL_MOUSE_DOWN", function(self, button)
    if button ~= "RightButton" or self:CastBinding() ~= MOUSE then return end
    ReleaseMouse(mousePress)
    if self:Yielded("casting.doubleRightClick") then return end
    if InCombatLockdown() or IsMouseButtonDown("LeftButton") then return end
    if not self:HasFishingPole() or GetNumLootItems() ~= 0 or not OverTheWorld() then return end
    if self:CastPending() then
        lastRightClick = -math.huge
        return
    end

    local now, gap = GetTime(), GetTime() - lastRightClick
    lastRightClick = now
    if self:CastDouble() and (gap < DOUBLE_MIN or gap > DOUBLE_WINDOW) then return end
    lastRightClick = -math.huge

    local recast = IsShiftKeyDown and IsShiftKeyDown()
    local reeling = self:IsCasting() and not recast
    if reeling and self:ReelNPCRisk() then return end
    if reeling then
        SoftTarget(true)
    end
    local press = { keyDown = CastOnKeyDown(), reeling = reeling }
    mousePress = press
    if reeling then
        pcall(SetOverrideBinding, binder, true, MOUSE, INTERACT)
    else
        local key = recast and "SHIFT-BUTTON2" or MOUSE
        pcall(SetOverrideBindingClick, binder, true, key, self.castBindButton:GetName())
    end
    C_Timer.After(press.keyDown and HOLD_DOWN or HOLD_UP, function() ReleaseMouse(press) end)
end)


MF:On("GLOBAL_MOUSE_UP", function(_, button)
    local press = mousePress
    if button ~= "RightButton" or not press then return end
    if press.keyDown then
        ReleaseMouse(press)
    else
        -- Let WoW dispatch the release to the secure binding before clearing it.
        C_Timer.After(0, function() ReleaseMouse(press) end)
    end
end)


MF:On("TFL_LOGIN", function(self) self:ApplyCastBinding() end)

-- Keeping a key's binding up
--
-- Right-click is bound at the moment of the double-click, so nothing can
-- take it away beforehand. A key is bound once, when the pole comes out or
-- you log in - and the game loads its key bindings while a /reload is still
-- settling, which can drop ours with nothing to say so: the key simply
-- stops casting until the pole comes off and goes back on. So whenever the
-- game's bindings are loaded or changed, and once things have settled after
-- login, look at the key, and put ours back only if it isn't there. Only
-- then: putting a binding up is itself a change of bindings, and answering
-- every one would answer our own.
local recheckAt -- when a look was queued; a stale one never blocks the next
function MF:RecheckCastBinding()
    if not C_Timer or (recheckAt and math.abs(GetTime() - recheckAt) < 2) then return end
    recheckAt = GetTime()
    C_Timer.After(0.5, function()
        recheckAt = nil
        if InCombatLockdown() or not self.castBindButton then return end
        local key = self:CastBinding()
        if not key or key == MOUSE or not self:HasFishingPole() then return end
        local ok, action = pcall(GetBindingAction, key, true)
        action = ok and type(action) == "string" and action or ""
        if action == INTERACT or action:find("TheFishingLogCast", 1, true) then return end
        self:ApplyCastBinding()
    end)
end
MF:On("UPDATE_BINDINGS", function(self) self:RecheckCastBinding() end)
MF:On("PLAYER_ENTERING_WORLD", function(self) self:RecheckCastBinding() end)
MF:On("TFL_LOGIN", function(self)
    if C_Timer then C_Timer.After(3, function() self:RecheckCastBinding() end) end
end)

MF:On("PLAYER_REGEN_ENABLED", function(self)
    ReleaseMouse(mousePress)
    self:ApplyCastBinding()
end)
MF:OnUnit("UNIT_INVENTORY_CHANGED", "player", function(self) self:ApplyCastBinding() end)
MF:On("TFL_FISHING_CAST", function(self)
    pendingUntil, pendingGUID = -math.huge, nil
    pendingSerial = pendingSerial + 1
    local serial = pendingSerial
    C_Timer.After(0, function()
        if serial == pendingSerial then self:ApplyCastBinding() end
    end)
end)
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
    if not C_EventUtils or type(C_EventUtils.IsEventValid) ~= "function"
        or C_EventUtils.IsEventValid(event) then
        MF:On(event, function(self)
            if self:IsCasting() then self:ApplyCastBinding() end
        end)
    end
end
MF:On("TFL_FISHING_DONE", function(self)
    -- A beat after the line lands, so the press that looted the bobber
    -- doesn't arm a cast on its way back up.
    C_Timer.After(0.5, function() self:ApplyCastBinding() end)
end)

local function Describe(self, key)
    local twice = self:CastDouble()
    if key == MOUSE then
        local click = twice and "Double right-click" or "Right-click"
        return ("%s to cast, then again to land the fish. Hold Shift and double-right-click "
            .. "to discard the current cast and cast again - with a pole equipped."):format(click)
    end
    local press = twice and ("Press %s twice"):format(Said(key)) or ("Press %s"):format(Said(key))
    return ("%s to cast, then once more to land the fish. To cast again, use the panel cast "
        .. "button. Shift plus an unmodified fishing key also recasts when that Shift combination is unassigned."):format(press)
end

MF:Command("cast", "Solo",
    "/tfl cast [mouse2|mouse3|f|off] - what casts and lands the fish",
    function(self, args, raw)
        local key = self:CastKeyFromWords(strtrim(raw or ""))
        if key == "" then
            local now = self:CastBinding()
            self:Print(now and Describe(self, now)
                or "Nothing casts for you. Try /tfl cast mouse2 for right-click.")
            local note = self:CastDoubleNote()
            if note then print("  " .. note) end
            return
        end
        if key == "OFF" or key == "NONE" then key = "" end
        self:SetCastKey(key)
    end)

-- What casts, set from /tfl cast or the Key bindings page. "" is nothing at all.
-- Says what happened in chat, and returns false when the key wouldn't take.
function MF:SetCastKey(key)
    key = key or ""
    if key == "" then
        self.db.settings.castClick = ""
        self:ApplyCastBinding()
        self:Print("Nothing casts for you now.")
        return true
    end
    local was = self.db.settings.castClick
    self.db.settings.castClick = key
    local ok = self:CastKeyWorks(key) and self:ApplyCastBinding() ~= false
    if not ok then
        -- Put back what they had. Losing a working binding to a typo is
        -- the difference between "that didn't work" and "nothing casts
        -- any more and I don't know why" - and the second one is what
        -- gets reported, days later, as the addon breaking itself.
        self.db.settings.castClick = was
        self:ApplyCastBinding()
        self:Print(("The game doesn't know a button called %s. Try |cffffd100mouse2|r for "
            .. "right-click, mouse3, shift-mouse2, or a key like f."):format(key))
        if was ~= "" then
            print(("  |cff858585%s still casts for you.|r"):format(Said(was)))
        end
        return false
    end
    self:Print(Describe(self, key))
    local note = self:CastDoubleNote()
    if note then print("  " .. note) end
    return true
end

------------------------------------------------------------------------
-- When the bar fills
--
-- Fishing doesn't raise its own ceiling: each rank is bought, taught or
-- earned somewhere specific, and a full bar tells you nothing about where.
-- Forever follows vanilla here.
------------------------------------------------------------------------

local NEXT_RANK = {
    [75] = "Journeyman (150) is taught by any fishing trainer.",
    [150] = "Expert (225) comes from a book, \"Expert Fishing - The Bass and You\", "
        .. "sold by Old Man Heming in Booty Bay.",
    [225] = "Artisan (300) comes from Nat Pagle's quest in Dustwallow Marsh.",
}

-- Returns the next step when your skill is sitting at its ceiling.
function MF:SkillNextStep()
    local rank, max = self:FishingSkill()
    if not rank or not max or rank < max then return nil end
    return NEXT_RANK[max], max
end

function MF:ResetFishingState()
    pendingUntil, pendingGUID = -math.huge, nil
    pendingSerial = pendingSerial + 1
    swapping,swappedForCombat=nil,false
    mousePress,armedAt,lastRightClick=nil,-math.huge,-math.huge
    self.outfitSuppressPoleReturn,self.outfitChanging=nil,nil
    gearDirty,auraDirty,skillReadAt=true,true,-math.huge
    SoftTarget(false)
    Louder(false)
    if not InCombatLockdown() then ClearOverrideBindings(binder) end
end

-- Said once per ceiling, when you reach it. The bar shows the numbers; this
-- is the part you'd otherwise have to go and look up.
MF:OnTick(function(self)
    local step, max = self:SkillNextStep()
    if not step or self.cdb.capTold == max then return end
    self.cdb.capTold = max
    self:Print(("Your fishing skill is capped at %d. %s"):format(max, step))
end)
