-- The lure menu: right-click the board's lure button for every lure you're
-- carrying, and click one to put it on your pole.
--
-- The lure button itself always reaches for your best lure, which is right
-- nearly every time - but not when you'd rather save the good ones, or the
-- best one asks for more skill than a cheaper one gets you anyway. So a
-- right-click opens this list instead of applying anything.
--
-- Putting a lure on a pole is a protected action, so each row is a secure
-- button holding the same two-line macro the lure button uses. Secure
-- buttons can only be built, changed, shown or hidden out of combat, so the
-- menu is filled as it opens, and while it's open the game's own state
-- driver hides it when a fight starts - the way the board does - because
-- by the time an addon hears about the fight it is no longer allowed to.
local _, MF = ...

local ROW_H, WIDTH, PAD = 30, 230, 10
local menu
local rows = {}

local function LureList(self)
    local list = {}
    for _, lure in ipairs(self:TackleboxLures()) do list[#list + 1] = lure end
    -- The fishing hat is a lure you wear: listed when it's on your head.
    local hat = self.FISHING_HAT
    if tonumber((GetInventoryItemLink("player", 1) or ""):match("item:(%d+)")) == hat.id then
        local ready, reason = self:FishingHatStatus()
        list[#list + 1] = { id = hat.id, bonus = hat.bonus, ready = ready, reason = reason, hat = true }
    end
    return list
end

local function Row(i)
    if rows[i] then return rows[i] end
    local b = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetSize(WIDTH - PAD * 2, ROW_H - 2)
    b:SetPoint("TOPLEFT", PAD, -28 - (i - 1) * ROW_H)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0, 0.12)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(24, 24)
    b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.name = MF:CreateText(b, "GameFontHighlightSmall")
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.name:SetPoint("RIGHT", -34, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.note = MF:CreateText(b, "GameFontDisableSmall")
    b.note:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 1)
    b.note:SetPoint("RIGHT", -34, 0)
    b.note:SetJustifyH("LEFT")
    b.note:SetWordWrap(false)
    b.count = MF:CreateText(b, "NumberFontNormal")
    b.count:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnEnter", function(self)
        if not self.lure then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.lure.id)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The macro has run by now (on the press or the release, whichever the
    -- game acts on); close on the release so the menu doesn't flicker.
    b:SetScript("PostClick", function(_, _, down)
        if not down then MF:CloseLureMenu() end
    end)
    rows[i] = b
    return b
end

local function Fill(self)
    local list = LureList(self)
    for i, lure in ipairs(list) do
        local b = Row(i)
        b.lure = lure
        b.icon:SetTexture(self:FishIcon(lure.id))
        b.icon:SetDesaturated(not lure.ready)
        b.name:SetText(self:FishName(lure.id))
        b.name:SetTextColor(lure.ready and 1 or 0.5, lure.ready and 1 or 0.5, lure.ready and 1 or 0.5)
        b.note:SetText(lure.ready and ("+%d Fishing"):format(lure.bonus) or (lure.reason or ""))
        b.count:SetText(lure.hat and "" or tostring(lure.count or ""))
        if lure.ready then
            b:SetAttribute("type", "macro")
            b:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(lure.id))
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("macrotext", nil)
        end
        b:Show()
    end
    for i = #list + 1, #rows do
        rows[i].lure = nil
        rows[i]:SetAttribute("type", nil)
        rows[i]:Hide()
    end
    menu.empty:SetShown(#list == 0)
    local left = self:LureTimeLeft()
    menu.status:SetText(left and left > 0 and ("%son your pole: %s|r"):format(self.C.muted, self:FormatClock(left))
        or (self.C.muted .. "nothing on your pole|r"))
    menu:SetHeight(28 + math.max(1, #list) * ROW_H + PAD)
end

local function Build(self)
    menu = self:CreatePanel("TheFishingLogLureMenu", WIDTH, 80,
        { backdrop = "tooltip", strata = "DIALOG", escCloses = true, title = "Lures" })
    menu:SetClampedToScreen(true)
    menu.title:SetFontObject("GameFontNormal")
    menu.title:ClearAllPoints()
    menu.title:SetPoint("TOPLEFT", PAD + 2, -9)
    menu.status = self:CreateText(menu, "GameFontHighlightSmall")
    menu.status:SetPoint("TOPRIGHT", -PAD - 2, -11)
    menu.empty = self:CreateText(menu, "GameFontHighlightSmall")
    menu.empty:SetPoint("TOPLEFT", PAD + 2, -34)
    menu.empty:SetText("You aren't carrying any lures.")
    -- Closed by Escape, or by us: the driver goes too, or it would bring the
    -- menu back when the next fight ends. A fight's own hide keeps it.
    menu:HookScript("OnHide", function(self)
        if self.driven and not InCombatLockdown() and UnregisterStateDriver then
            UnregisterStateDriver(self, "visibility")
            self.driven = nil
        end
    end)
end

function MF:CloseLureMenu()
    if not menu or InCombatLockdown() then return end
    if menu.driven and UnregisterStateDriver then UnregisterStateDriver(menu, "visibility") end
    menu.driven = nil
    menu:Hide()
end

function MF:ToggleLureMenu(anchor)
    if InCombatLockdown() then
        self:Print("The lure menu can't open during a fight.")
        return
    end
    if not menu then Build(self) end
    if menu:IsShown() then self:CloseLureMenu() return end
    Fill(self)
    menu:ClearAllPoints()
    anchor = anchor or self.lureButton
    if anchor then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -8, 10)
    else
        menu:SetPoint("CENTER")
    end
    if RegisterStateDriver then
        menu.driven = true
        RegisterStateDriver(menu, "visibility", "[combat] hide; show")
    else
        menu:Show()
    end
end

function MF:LureMenuShown() return menu ~= nil and menu:IsShown() end

-- The driver hid it for the fight and would put it back afterwards; a menu
-- you opened before the fight is stale by then, so it stays shut.
MF:On("PLAYER_REGEN_ENABLED", function(self) if menu and menu.driven then self:CloseLureMenu() end end)
MF:On("BAG_UPDATE_DELAYED", function(self) if menu and menu:IsShown() and not InCombatLockdown() then Fill(self) end end)

-- Right-click on the lure button opens the menu instead of applying a lure.
-- PreClick runs before the button's secure action, so for the right button
-- it takes the action away for this one click and PostClick gives it back.
MF:On("TFL_INIT", function(self)
    local button = self.lureButton
    if not button then return end
    button:SetScript("PreClick", function(b, which)
        if which ~= "RightButton" or InCombatLockdown() then return end
        b.lureMenuType = b:GetAttribute("type")
        b:SetAttribute("type", nil)
    end)
    button:SetScript("PostClick", function(b, which, down)
        if which ~= "RightButton" or InCombatLockdown() then return end
        b:SetAttribute("type", b.lureMenuType)
        b.lureMenuType = nil
        if not down then self:ToggleLureMenu(b) end
    end)
end)

MF:Command({ "lures", "lure" }, "Solo", "/tfl lures - choose which lure to put on your pole",
    function(self) self:ToggleLureMenu() end)
