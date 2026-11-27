-- Alerts: The Fishing Log's pop-ups ("NEW SPECIMEN!", "RANK UP!", "FEEDING FRENZY"...) as a framed
-- banner in the achievement alert's manner: the icon in a gold ring, a flash as it lands, a gentle
-- drop into place, and it waits while your mouse is over it. Same queue rules as The Fishing Log's own:
-- its popup settings decide what shows, and an alert about a spot you've since left is dropped.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local T = {}
ns.Toast = T

local MF
local f
local HOLD, FADE, IN = 5.5, 1.0, 0.35
local DROP = 18

local function Build()
    if f then return f end
    f = CreateFrame("Button", "AnglersLodgeToast", UIParent, "BackdropTemplate")
    f:SetSize(360, 86)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 20, insets = { left = 5, right = 5, top = 5, bottom = 5 } })
    f:SetBackdropColor(0.05, 0.06, 0.11, 0.94)
    local sheen = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetPoint("TOPLEFT", 5, -5)
    sheen:SetPoint("TOPRIGHT", -5, -5)
    sheen:SetHeight(38)
    sheen:SetColorTexture(1, 1, 1, 1)
    if CreateColor and sheen.SetGradient then
        sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 0.9, 0.6, 0.12))
    else
        sheen:SetAlpha(0.06)
    end
    f.sheen = sheen

    f.icon = W:FramedIcon(f, 46, ns.ICON)
    f.icon:SetPoint("LEFT", 18, 1)

    f.header = W:Label(f, "GameFontNormal")
    f.header:SetPoint("TOPLEFT", 82, -14)
    f.header:SetPoint("TOPRIGHT", -16, -14)
    f.header:SetJustifyH("LEFT")
    f.line1 = W:Label(f, "GameFontHighlightLarge")
    f.line1:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -4)
    f.line1:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -4)
    f.line1:SetJustifyH("LEFT")
    f.line2 = W:Label(f, "GameFontHighlight")
    f.line2:SetPoint("TOPLEFT", f.line1, "BOTTOMLEFT", 0, -3)
    f.line2:SetPoint("TOPRIGHT", f.line1, "BOTTOMRIGHT", 0, -3)
    f.line2:SetJustifyH("LEFT")
    f.line2:SetTextColor(0.8, 0.8, 0.8)
    for _, fs in ipairs({ f.header, f.line1, f.line2 }) do fs:SetWordWrap(true) end

    -- The flash as it lands, and a glow that breathes once on the icon ring
    f.flash = f:CreateTexture(nil, "OVERLAY")
    f.flash:SetPoint("TOPLEFT", 4, -4)
    f.flash:SetPoint("BOTTOMRIGHT", -4, 4)
    f.flash:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    f.flash:SetBlendMode("ADD")
    f.flash:SetAlpha(0)
    f.ring = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.ring:SetPoint("CENTER", f.icon, "CENTER")
    f.ring:SetSize(84, 84)
    f.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.ring:SetBlendMode("ADD")
    f.ring:SetAlpha(0)

    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", function(_, button)
        local card, action = f.card, f.action
        T:Dismiss()
        if button ~= "RightButton" then
            if action then action() elseif card then MF:ShowCard(card) end
        end
    end)
    f:SetScript("OnEnter", function() f.hover = true end)
    f:SetScript("OnLeave", function() f.hover = nil end)
    f:SetScript("OnUpdate", function(self, elapsed)
        if self.hover and self.state == "hold" then
            self.age = 0
            self:SetAlpha(1)
            return
        end
        self.age = (self.age or 0) + elapsed
        if self.state == "in" then
            local t = math.min(1, self.age / IN)
            local e = 1 - (1 - t) * (1 - t) * (1 - t)
            self:SetAlpha(t)
            self:SetPoint("TOP", UIParent, "TOP", 0, -150 + DROP * (1 - e))
            self.flash:SetAlpha(0.55 * (1 - t))
            self.ring:SetAlpha(0.9 * math.sin(t * math.pi))
            if t >= 1 then self.state, self.age = "hold", 0 end
        elseif self.state == "hold" then
            if self.age >= (ns.db.toastHold or HOLD) then self.state, self.age = "out", 0 end
        elseif self.state == "out" then
            local t = math.min(1, self.age / FADE)
            self:SetAlpha(1 - t)
            if t >= 1 then T:Dismiss() end
        end
    end)
    f:Hide()
    return f
end

-- The Fishing Log has already chosen this one and played its sound.
function T:Show(n)
    if not f then return end
    local icon, header, line1, line2, r, g, b = unpack(n, 1, 7)
    f.card = n.card
    f.action = n.action
    f.icon.icon:SetTexture(icon or 134400)
    f.header:SetText(header or "")
    f.header:SetTextColor(r or 1, g or 0.82, b or 0)
    f.flash:SetVertexColor(r or 1, g or 0.82, b or 0)
    f.ring:SetVertexColor(r or 1, g or 0.82, b or 0)
    f.line1:SetText(line1 or "")
    f.line2:SetText(line2 or "")
    f.line2:SetShown(line2 ~= nil and line2 ~= "")
    local h = 28 + (f.header:GetStringHeight() or 12) + (f.line1:GetStringHeight() or 16)
        + ((line2 and line2 ~= "") and ((f.line2:GetStringHeight() or 12) + 3) or 0)
    f:SetHeight(math.max(86, h + 4))
    f.state, f.age, f.hover = "in", 0, nil
    if ns.db.animations == false then f.state = "hold" f:SetAlpha(1) end
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    f:Show()
end

-- From the options panel: how an alert looks, without waiting for a catch
function T:Test()
    if not (f and MF) then
        -- New alerts switched off: show The Fishing Log's own
        local tfl = ns:MF()
        if tfl and tfl.Toast then tfl:Toast(tfl:FishIcon(6358), "NEW SPECIMEN!", "Oily Blackmouth, 6.26 lb", "This is how alerts look.", 1, 0.5, 0) end
        return
    end
    MF:Toast(MF:FishIcon(6358), "NEW SPECIMEN!", "Oily Blackmouth, 6.26 lb", "This is how alerts look.", 1, 0.5, 0)
end

function T:Dismiss()
    if not f then return end
    f:Hide()
    f.state = nil
    MF:ToastDone()
end

ns:OnSetup("toasts", function(tfl)
    MF = tfl
    if not (MF.ToastDone and MF.ShowCard) then return end
    Build()
    local old = _G.TheFishingLogToast
    if old then old:Hide() end
    MF.toastPresenter = {
        Busy = function() return f:IsShown() end,
        Show = function(n) T:Show(n) end,
        Clear = function() f:Hide() f.state = nil end,
    }
end)
