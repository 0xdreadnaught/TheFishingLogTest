-- Float: the catch, on screen, where the catch happened.
--
-- A fish landing is a moment, and chat is where moments go to be scrolled
-- past - by the time you've read the line, three guild messages have pushed
-- it up. So the same thing rises off the water the way combat text does:
-- the icon, the weight, and how good it was for its kind.
--
-- Chat still says everything. This says the part worth seeing without
-- looking away from the bobber.
local _, MF = ...

local LINES = 6        -- alive at once; catches are seconds apart, so plenty
local RISE = 80        -- pixels it climbs on its way out
local HOLD = 1.4       -- seconds at full strength
local FADE = 1.1
local ICON = 20

local anchor, pool, nextLine = nil, {}, 1
local nextFloatAt = 0

------------------------------------------------------------------------
-- What it says
------------------------------------------------------------------------

-- Kept apart from the drawing so it can be checked without a screen. Junk
-- is shown too, dimmed: knowing the addon saw your boot is worth a moment,
-- and it stops the silence after a cast looking like a fault.
--
-- Returns the words, how loudly to say them, and the icon - the icon kept
-- separate rather than written into the string as a |T. An inline texture
-- does not follow a translation animation: the words climb and the fish is
-- left floating on the water where it started.
function MF:CatchFloatText(c)
    if not c or c.test then return end
    local icon = self:FishIcon(c.itemID)

    if c.junk and self.IsFishingFind and self:IsFishingFind(c.itemID) then
        return ("|cffe6c066%s|r  find"):format(c.name or "Find"), "normal", icon
    end
    if c.junk then
        return ("|cff9d9d9d%s|r"):format(c.name or "junk"), "small", icon
    end

    local line = ("%s  |cffffd100%s|r"):format(c.name or "?", MF:Weight(c.weight or 0))
    if c.specimen then
        return ("%s  |cffff8000SPECIMEN|r"):format(line), "big", icon
    end
    local grade, colour = self:WeightGrade(c.itemID, c.weight)
    if grade then
        line = ("%s  %s(%s)|r"):format(line, colour, grade)
    end
    if c.best then
        return ("%s  |cffffd100best yet|r"):format(line), "big", icon
    end
    return line, "normal", icon
end

------------------------------------------------------------------------
-- Where it goes
------------------------------------------------------------------------

local FONTS = { small = "GameFontDisableSmall", normal = "GameFontNormal", big = "GameFontNormalLarge" }

local function CreateAnchor(self)
    anchor = CreateFrame("Frame", "TheFishingLogFloat", UIParent, "BackdropTemplate")
    anchor:SetSize(260, 28)
    anchor:SetPoint("CENTER", UIParent, "CENTER",
        self.db.settings.floatX or 0, self.db.settings.floatY or 140)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetClampedToScreen(true)
    anchor:SetScript("OnDragStart", anchor.StartMoving)
    anchor:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        -- Remember where it was put, relative to the middle of the screen,
        -- so it lands in the same place at any resolution.
        local x, y = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and ux then
            MF.db.settings.floatX = math.floor(x - ux)
            MF.db.settings.floatY = math.floor(y - uy)
        end
    end)

    anchor.label = MF:CreateText(anchor, "GameFontNormal")
    anchor.label:SetPoint("CENTER")
    anchor.label:SetText("Catches appear here - drag me")
    anchor:EnableMouse(false)
    anchor.label:Hide()
end

local function CreateLine()
    local f = CreateFrame("Frame", nil, anchor)
    f:SetSize(400, 24)
    f:SetPoint("CENTER")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(ICON, ICON)
    f.text = MF:CreateText(f, "GameFontNormal")

    local group = f:CreateAnimationGroup()
    local rise = group:CreateAnimation("Translation")
    rise:SetOffset(0, RISE)
    rise:SetDuration(HOLD + FADE)
    rise:SetSmoothing("OUT")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(HOLD)
    fade:SetDuration(FADE)
    group:SetScript("OnFinished", function() f:Hide() end)

    f.anim = group
    f:Hide()
    return f
end

local function ShowCatch(self, text, size, icon)
    if not self.db.settings.floatCatches or self:Yielded("feedback.catchFloaters") then return end
    if not anchor then CreateAnchor(self) end

    local f = pool[nextLine]
    if not f then
        f = CreateLine()
        pool[nextLine] = f
    end
    nextLine = nextLine % LINES + 1

    f.anim:Stop()
    f.text:SetFontObject(FONTS[size] or FONTS.normal)
    f.text:SetText(text)

    -- Centre the pair as a pair, so a long name doesn't push the fish off
    -- to one side and a short one doesn't leave it stranded.
    f.icon:ClearAllPoints()
    f.text:ClearAllPoints()
    if icon then
        f.icon:SetTexture(icon)
        f.icon:Show()
        local span = ICON + 4 + (f.text:GetStringWidth() or 0)
        f.icon:SetPoint("LEFT", f, "CENTER", -span / 2, 0)
        f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    else
        f.icon:Hide()
        f.text:SetPoint("CENTER")
    end
    f:SetAlpha(1)
    f:Show()
    f.anim:Play()
end

function MF:FloatCatch(c)
    if not self.db.settings.floatCatches or self:Yielded("feedback.catchFloaters") then return end
    local text, size, icon = self:CatchFloatText(c)
    if not text then return end
    -- Extra fish arrive in the same frame. Give each the full readable
    -- animation before the next starts, rather than drawing over it.
    -- Only the visual waits: scoring and catch chat still happen immediately.
    local now = GetTime()
    local wait = math.max(0, nextFloatAt - now)
    nextFloatAt = now + wait + HOLD + FADE + 0.1
    if wait == 0 then ShowCatch(self, text, size, icon)
    else
        local generation=self.dataGeneration
        C_Timer.After(wait,function() if generation==self.dataGeneration then ShowCatch(self,text,size,icon) end end)
    end
end

MF:On("TFL_CATCH", MF.FloatCatch)

-- A warning about the cast, shown where the catches are. Says whether it
-- was shown, so whoever asked can show it themselves if it wasn't.
function MF:FloatWarning(text)
    if not text or not self.db.settings.floatCatches or self:Yielded("feedback.catchFloaters") then
        return false
    end
    ShowCatch(self, MF.C.bad .. text .. "|r", "big")
    return true
end

function MF:ResetCatchFloat()
    nextFloatAt,nextLine=0,1
    for _,f in ipairs(pool) do f.anim:Stop() f:Hide() end
end

------------------------------------------------------------------------
-- Moving it
------------------------------------------------------------------------

local unlocked = false

function MF:UnlockFloat(show)
    if not anchor then CreateAnchor(self) end
    unlocked = show
    anchor:EnableMouse(show)
    anchor:SetBackdrop(show and {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    } or nil)
    anchor.label:SetShown(show)
    anchor:SetShown(true)
    self:Print(show and "Drag the box where you want catches to appear, then |cffffd100/tfl float lock|r."
        or "Catches will appear there from now on.")
end

MF:Command("float", "Solo", "/tfl float - show each catch on screen, or move where it appears",
    function(self, args)
        local what = (args[1] or ""):lower()
        if what == "move" or what == "unlock" then
            self:UnlockFloat(true)
        elseif what == "lock" then
            self:UnlockFloat(false)
        elseif what == "on" or what == "off" then
            self.db.settings.floatCatches = what == "on"
            self:Print(("Catches on screen: |cffffd100%s|r."):format(what))
        else
            self.db.settings.floatCatches = not self.db.settings.floatCatches
            self:Print(("Catches on screen: |cffffd100%s|r. |cffffd100/tfl float move|r puts them elsewhere.")
                :format(self.db.settings.floatCatches and "on" or "off"))
        end
    end)
