-- Character preview only. The wardrobe remains the sole owner of real gear changes.
-- Keep Godfall's existing panel, text, button and XP-bar styling.
local _, MF = ...
local ns, W = MF.Rework, MF.Rework.W
local Portrait = {}
ns.AnglerPortrait = Portrait
local VISIBLE = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18 }
local HAND = { [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT" }

local function Safe(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
local function Call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    local ok, value = pcall(object[method], object, ...)
    if ok then return true, Safe(value) end
    return false
end
local function Outfit()
    return MF.cdb and MF.cdb.gear and MF.cdb.gear.outfit
end

-- Only slots the wardrobe would actually swap. Unchecked, unsaved and saved
-- empty slots retain current gear, matching ApplyFishingOutfit's semantics.
function Portrait:Items()
    local state, items, signature = Outfit(), {}, {}
    for _, slot in ipairs(VISIBLE) do
        local saved = state and state.items and state.items[slot]
        if state and state.selected and state.selected[slot] and type(saved) == "table" and type(saved.link) == "string" then
            items[#items + 1] = { slot = slot, link = saved.link }
            signature[#signature + 1] = slot .. ":" .. saved.link
        end
    end
    return items, table.concat(signature, "|")
end

local function TwoHanded(link)
    local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(info) ~= "function" then return false end
    local ok, _, _, _, inventoryType, _, classID, subclassID = pcall(info, link)
    if not ok then return false end
    inventoryType, classID, subclassID = Safe(inventoryType), Safe(classID), Safe(subclassID)
    return inventoryType == "INVTYPE_2HWEAPON" or classID == 2 and subclassID == 20
end

function Portrait:ApplyItems(model, items)
    local main, failures = nil, 0
    for _, item in ipairs(items) do if item.slot == 16 then main = item end end
    local twoHanded = main and TwoHanded(main.link)
    -- Discard the current off hand before dressing a pole, even if it was not
    -- selected in the saved outfit (a pole occupies both hands in the wardrobe).
    if twoHanded and not Call(model, "UndressSlot", 17) then failures = failures + 1 end
    for _, item in ipairs(items) do
        if not (item.slot == 17 and twoHanded) then
            local ok, result = Call(model, "TryOn", item.link, HAND[item.slot])
            if not ok or result == false or type(result) == "number" and result ~= 0 then failures = failures + 1 end
        end
    end
    if twoHanded then Call(model, "UndressSlot", 17) end
    Call(model, "SetSheathed", false, false)
    return failures
end

function Portrait:Create(parent)
    local panel = W:Panel(parent, 0.48)
    panel.camera = { angle = 0.12, zoom = 0 }
    panel.poll = 0
    local overlay = CreateFrame("Frame", nil, panel)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(panel:GetFrameLevel() + 5)

    panel.realm = W:Label(overlay, "GameFontNormalLarge", "Realm —")
    panel.realm:SetPoint("TOPLEFT", 12, -15)
    panel.realm:SetPoint("TOPRIGHT", -12, -15)
    panel.realm:SetJustifyH("CENTER")
    panel.realmNote = W:Label(overlay, "GameFontDisableSmall", "All time")
    panel.realmNote:SetPoint("TOPLEFT", 12, -39)
    panel.realmNote:SetPoint("TOPRIGHT", -12, -39)
    panel.realmNote:SetJustifyH("CENTER")
    local rankTip = CreateFrame("Frame", nil, overlay)
    rankTip:SetPoint("TOPLEFT", 8, -8)
    rankTip:SetPoint("TOPRIGHT", -8, -8)
    rankTip:SetHeight(45)
    rankTip:EnableMouse(true)
    W:Tip(rankTip, "Realm ranking", "All-time record standings known to your addon, matching the Realm tab. Shared records can change your place.")

    panel.character = W:Label(overlay, "GameFontNormal", "")
    panel.character:SetPoint("BOTTOMLEFT", 10, 112)
    panel.character:SetPoint("BOTTOMRIGHT", -10, 112)
    panel.character:SetJustifyH("CENTER")
    panel.rank = W:Label(overlay, "GameFontHighlight", "")
    panel.rank:SetPoint("BOTTOMLEFT", 10, 91)
    panel.rank:SetPoint("BOTTOMRIGHT", -10, 91)
    panel.rank:SetJustifyH("CENTER")
    panel.xp = W:Bar(overlay, 200, 14, 0.58, 0.0, 0.55)
    panel.xp:SetPoint("BOTTOMLEFT", 18, 69)
    panel.xp:SetPoint("BOTTOMRIGHT", -18, 69)
    panel.xp.text:SetFontObject("GameFontHighlightSmall")
    panel.xp:EnableMouse(true)
    W:Tip(panel.xp, "Angler rank", function()
        local xp = MF.cdb and MF.cdb.profile and MF.cdb.profile.xp or 0
        local _, name, nextXP = MF:RankFor(xp)
        return ("%s, %d XP%s"):format(name or "", xp, nextXP and ("\n%d XP to the next rank."):format(nextXP - xp) or "\nThe top of the ladder.")
    end)
    panel.caption = W:Label(overlay, "GameFontDisableSmall", "")
    panel.caption:SetPoint("BOTTOMLEFT", 10, 47)
    panel.caption:SetPoint("BOTTOMRIGHT", -10, 47)
    panel.caption:SetJustifyH("CENTER")
    local outfit = W:Button(overlay, "Outfit", 102, 24, function() MF:OpenFishingOutfit() end,
        "Fishing outfit", "Choose the saved pieces used in this preview. Opening this panel does not equip them.")
    outfit:SetPoint("BOTTOMLEFT", 16, 14)
    local reset = W:Button(overlay, "Reset view", 102, 24, function()
        panel.camera.angle, panel.camera.zoom = 0.12, 0
        panel:RefreshModel()
    end)
    reset:SetPoint("BOTTOMRIGHT", -16, 14)

    local ok, model = pcall(CreateFrame, "DressUpModel", nil, panel)
    if ok then
        panel.model = model
        model:SetPoint("TOPLEFT", 6, -57)
        model:SetPoint("BOTTOMRIGHT", -6, 138)
        model:SetFrameLevel(panel:GetFrameLevel() + 1)
        model:EnableMouse(true)
        model:EnableMouseWheel(true)
        model:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then panel.dragX = Safe(GetCursorPosition()) end
        end)
        model:SetScript("OnMouseUp", function() panel.dragX = nil end)
        model:SetScript("OnMouseWheel", function(_, delta)
            panel.camera.zoom = math.max(-0.7, math.min(0.75, panel.camera.zoom + delta * 0.1))
            panel:Camera()
        end)
        model:SetScript("OnModelLoaded", function() if panel.loading then panel.loaded = true end end)
        W:Tip(model, "Fishing outfit preview", "Drag to turn; scroll to zoom. Saved fishing pieces replace the selected slots; the rest is your current gear.")
    else
        panel.caption:SetText("Preview unavailable")
    end

    function panel:Camera()
        local camera = self.camera
        Call(self.model, "SetRotation", camera.angle, false)
        Call(self.model, "SetPortraitZoom", math.max(0, camera.zoom))
        Call(self.model, "SetCamDistanceScale", 1 + math.max(0, -camera.zoom) * 2)
        Call(self.model, "SetPosition", 0, 0, 0)
    end
    function panel:RefreshModel()
        if not self.model or not self:IsShown() then return end
        self.items, self.outfitSignature = Portrait:Items()
        self.needsItemData = false
        self.loading, self.loaded, self.loadAt = true, false, GetTime()
        self.caption:SetText("Loading preview…")
        -- Always initialize from the live player: display/model IDs alone do
        -- not preserve this client's skin, face and customization.
        local loaded, result = Call(self.model, "SetUnit", "player")
        if not loaded or result == false then
            self.loading = false
            self.caption:SetText("Preview unavailable")
        end
        self:Camera()
    end
    function panel:RefreshRank()
        self.character:SetText(MF.me and MF:ShortName(MF.me) or "")
        local place, total
        if MF.RealmRank and MF.me then place, total = MF:RealmRank(MF.me) end
        self.realm:SetText(place and ("Realm #%d"):format(place) or "Realm —")
        self.realmNote:SetText(place and ("of %d anglers · All time"):format(total or place) or "No realm records yet")
        local xp = MF.cdb and MF.cdb.profile and MF.cdb.profile.xp or 0
        local idx, name, nextXP = MF:RankFor(xp)
        self.rank:SetText(name or "")
        local ladder = MF.Ladder and MF:Ladder()
        local floor = ladder and ladder[idx] and ladder[idx].xp or 0
        if nextXP then
            self.xp:Set(xp - floor, nextXP - floor, ("%d / %d XP"):format(xp, nextXP))
        else
            self.xp:Set(1, 1, ("%d XP"):format(xp))
        end
    end
    panel:SetScript("OnShow", function(self) self:RefreshRank(); self:RefreshModel() end)
    panel:SetScript("OnHide", function(self) self.dragX = nil; self.loading = false end)
    panel:SetScript("OnUpdate", function(self, elapsed)
        if self.dragX then
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.dragX = nil
            else
                local x = Safe(GetCursorPosition())
                if type(x) == "number" then
                    self.camera.angle = self.camera.angle + (x - self.dragX) / math.max(1, self:GetEffectiveScale()) * 0.012
                    self.dragX = x; self:Camera()
                end
            end
        end
        if self.loading then
            local hasGeo, ready = Call(self.model, "IsGeoReady")
            local age = GetTime() - self.loadAt
            if age >= 0.1 and (ready or not hasGeo and (self.loaded or age > 0.2)) then
                self.loading = false
                self.needsItemData = Portrait:ApplyItems(self.model, self.items) > 0
                self.caption:SetText(self.needsItemData and "Some outfit pieces unavailable" or #self.items > 0 and "Fishing outfit" or "Current gear")
                self:Camera()
            elseif GetTime() - self.loadAt > 6 then
                self.loading = false; self.caption:SetText("Preview unavailable")
            end
        end
        self.poll = self.poll + elapsed
        if self.poll >= 1 then
            self.poll = 0; self:RefreshRank()
            local _, signature = Portrait:Items()
            if self.dirty or signature ~= self.outfitSignature then self.dirty = nil; self:RefreshModel() end
        end
    end)
    MF:On("PLAYER_EQUIPMENT_CHANGED", function() panel.dirty = true end)
    MF:On("UNIT_MODEL_CHANGED", function(_, unit) if unit == "player" then panel.dirty = true end end)
    MF:On("PLAYER_ENTERING_WORLD", function() panel.dirty = true end)
    MF:On("GET_ITEM_INFO_RECEIVED", function() if panel.needsItemData then panel.dirty = true end end)
    return panel
end
