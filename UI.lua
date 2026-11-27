-- UI: the movable board (solo log or live match) and centre-screen toasts.
--
-- Layout, top to bottom: title and clock, three summary cells, the catch or
-- standings list, two context bars (lure/match and frenzy), two footer lines
-- (bounty or event, and the spot's King), then a row of icon buttons.
local _, MF = ...

local ROWS = 8
local ROW_H = 16
local WIDTH = 280
local BOUNTY_IN = [[|TInterface\TargetingFrame\UI-RaidTargetingIcon_1:12:12|t]]
-- On MF so the width test measures against what the board actually uses.
MF.BOARD_WIDTH, MF.BOARD_TEXT_WIDTH = WIDTH, WIDTH - 24
local ICON_SIZE = 26
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t "
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"
local BOARD_HOME = { "CENTER", UIParent, "CENTER", 300, 100 }

local board, toast
local toastQueue = {}
local NextToast

------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------

local function CreateBar(parent, y, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(WIDTH - 24, 16)
    bar:SetPoint("TOPLEFT", 12, y)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetStatusBarColor(r, g, b)
    bar:SetMinMaxValues(0, 1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(1, 1, 1, 0.08)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", 4, 0)
    bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.right:SetPoint("RIGHT", -4, 0)
    return bar
end

-- Shows a value out of a maximum, or an empty bar with just a label.
local function SetBar(bar, fraction, label, right, r, g, b)
    bar:SetValue(math.max(0, math.min(1, fraction or 0)))
    if r then bar:SetStatusBarColor(r, g, b) end
    bar.label:SetText(label or "")
    bar.right:SetText(right or "")
end

-- A second segment past the end of the fill, for a bonus on top of a value.
-- A lure doesn't raise your fishing skill, it adds to it, and the bar should
-- say which - so the bonus sits beyond your own number in the blue the game
-- itself uses for a buffed stat. Drawn above the fill and below the labels.
local function SetBonus(bar, base, extra)
    if not bar.bonus then
        bar.bonus = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        bar.bonus:SetTexture(BAR_TEXTURE)
        -- Deep enough that the bar's own white text still reads over it:
        -- the numbers sit at the right edge, which is exactly where this
        -- segment lands.
        bar.bonus:SetVertexColor(0.13, 0.35, 0.78)
        -- A hairline where yours ends and the lure begins, so the join is
        -- legible at a glance rather than a change of shade.
        bar.edge = bar:CreateTexture(nil, "ARTWORK", nil, 2)
        bar.edge:SetColorTexture(1, 1, 1, 0.55)
        bar.edge:SetWidth(1)
    end
    if not extra or extra <= 0 then
        bar.bonus:Hide()
        bar.edge:Hide()
        return
    end
    local w, left = bar:GetWidth(), math.max(0, math.min(1, base or 0))
    bar.bonus:ClearAllPoints()
    bar.bonus:SetPoint("TOPLEFT", bar, "TOPLEFT", left * w, 0)
    bar.bonus:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left * w, 0)
    bar.bonus:SetWidth(math.max(1, math.min(1 - left, extra) * w))
    bar.bonus:Show()
    bar.edge:ClearAllPoints()
    bar.edge:SetPoint("TOP", bar, "TOPLEFT", left * w, 0)
    bar.edge:SetPoint("BOTTOM", bar, "BOTTOMLEFT", left * w, 0)
    bar.edge:Show()
end

local function Tooltip(button, title, line)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        if line then GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Turns a plain button into an icon button with a highlight and tooltip.
local function StyleIcon(button, icon, title, line)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:SetNormalTexture(icon)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    Tooltip(button, title, line)
    return button
end

local function IconButton(parent, icon, title, line, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetScript("OnClick", onClick)
    return StyleIcon(b, icon, title, line)
end

------------------------------------------------------------------------
-- The board
------------------------------------------------------------------------

-- A fixed particle pool: no per-frame textures, timers or random allocations.
local function CreateFrenzyEffect()
    local fx = CreateFrame("Frame", nil, board)
    fx:SetAllPoints(board)
    fx:EnableMouse(false)
    fx.bubbles = {}
    fx.age = 0
    -- Eight slices keep the halo soft at every panel size without stretching
    -- its corners or laying a bright texture over the text in the middle.
    local glow = CreateFrame("Frame", nil, fx)
    glow:SetAllPoints(board)
    glow:EnableMouse(false)
    local slices = {
        { "TOPLEFT", -14, 14, 0, 0.25, 0, 0.25 },
        { "TOPRIGHT", 14, 14, 0.75, 1, 0, 0.25 },
        { "BOTTOMLEFT", -14, -14, 0, 0.25, 0.75, 1 },
        { "BOTTOMRIGHT", 14, -14, 0.75, 1, 0.75, 1 },
    }
    local function GlowPiece(u1, u2, v1, v2)
        local art = glow:CreateTexture(nil, "BACKGROUND")
        art:SetTexture("Interface\\AddOns\\" .. MF.ADDON .. "\\Media\\FrenzyGlow.tga")
        art:SetTexCoord(u1, u2, v1, v2)
        art:SetBlendMode("ADD")
        return art
    end
    for _, slice in ipairs(slices) do
        local art = GlowPiece(slice[4], slice[5], slice[6], slice[7])
        art:SetSize(16, 16)
        art:SetPoint(slice[1], board, slice[1], slice[2], slice[3])
    end
    for _, top in ipairs({ true, false }) do
        local art = GlowPiece(0.25, 0.75, top and 0 or 0.75, top and 0.25 or 1)
        local edge = top and "TOP" or "BOTTOM"
        art:SetHeight(16)
        art:SetPoint(edge .. "LEFT", board, edge .. "LEFT", 2, top and 14 or -14)
        art:SetPoint(edge .. "RIGHT", board, edge .. "RIGHT", -2, top and 14 or -14)
    end
    for _, left in ipairs({ true, false }) do
        local art = GlowPiece(left and 0 or 0.75, left and 0.25 or 1, 0.25, 0.75)
        local edge = left and "LEFT" or "RIGHT"
        art:SetWidth(16)
        art:SetPoint("TOP" .. edge, board, "TOP" .. edge, left and -14 or 14, -2)
        art:SetPoint("BOTTOM" .. edge, board, "BOTTOM" .. edge, left and -14 or 14, 2)
    end
    glow:SetAlpha(0.62)
    fx.glow = glow
    local rim = fx:CreateTexture(nil, "OVERLAY")
    rim:SetColorTexture(1, 0.65, 0.18, 0.45)
    rim:SetPoint("TOPLEFT", board, "TOPLEFT", 8, -1)
    rim:SetPoint("TOPRIGHT", board, "TOPRIGHT", -26, -1)
    rim:SetHeight(2)
    fx.rim = rim
    for i = 1, 8 do
        local bubble = fx:CreateTexture(nil, "OVERLAY")
        bubble:SetTexture("Interface\\AddOns\\" .. MF.ADDON .. "\\Media\\FrenzyBubble.tga")
        local size = 5 + (i * 7 % 6)
        bubble:SetSize(size, size)
        bubble:Hide()
        fx.bubbles[i] = bubble
    end
    fx.tick = function(self, elapsed)
        self.age = self.age + elapsed
        self.glow:SetAlpha(0.62 + math.sin(self.age * math.pi / 2) * 0.12)
        for i, bubble in ipairs(self.bubbles) do
            local life = 2.6 + (i % 3) * 0.4
            -- Initially launch together; subsequent cycles are staggered.
            local age = self.age - (i - 1) * 0.13
            local phase = age >= 0 and (age % life) / life or -1
            if phase >= 0 then
                bubble:ClearAllPoints()
                bubble:SetPoint("BOTTOMLEFT", board, "TOPLEFT",
                    15 + ((i * 37) % (WIDTH - 48)) + math.sin(age * 1.7 + i) * 4,
                    -3 + phase * (24 + i % 3 * 5))
                bubble:SetAlpha(math.sin(phase * math.pi) * 0.48)
                bubble:Show()
            else bubble:Hide() end
        end
    end
    fx:SetScript("OnShow", function(self) self.age = 0 end)
    fx:Hide()
    board.frenzyEffect = fx
end

function MF:UpdateBoardFrenzy(active)
    local fx = board.frenzyEffect
    if active then
        board:SetBackdropBorderColor(1, 0.63, 0.16, 1)
        board:SetBackdropColor(0.19, 0.13, 0.06, 0.88)
        fx:Show()
        local animate = not self.db.settings.reducedMotion
        fx:SetScript("OnUpdate", animate and fx.tick or nil)
        if not animate then
            fx.glow:SetAlpha(0.62)
            for _, bubble in ipairs(fx.bubbles) do bubble:Hide() end
        end
    else
        board:SetBackdropBorderColor(1, 1, 1, 1)
        board:SetBackdropColor(unpack(self.FILL_OVERLAY))
        fx:SetScript("OnUpdate", nil)
        fx:Hide()
        fx.age = 0
        for _, bubble in ipairs(fx.bubbles) do bubble:Hide() end
    end
end

local function CreateBoard()
    board = MF:CreatePanel("TheFishingLogBoard", WIDTH, 96 + ROWS * ROW_H + 26 + 30 + 49,
        { backdrop = "tooltip", movable = true, fill = MF.FILL_OVERLAY })
    MF.boardFrame = board
    board:SetPoint(unpack(BOARD_HOME))
    CreateFrenzyEffect()
    board.goal = MF:CreateText(board, "GameFontHighlightSmall", "BOTTOMLEFT", 12, 43)
    board.goal:SetWidth(WIDTH - 24)
    board.goal:SetWordWrap(false)

    -- Title and clock share the top row; the summary cells sit below them,
    -- so nothing overlaps on the right.
    board.clock = MF:CreateText(board, "GameFontHighlight", "TOPRIGHT", -28, -10)

    board.title = MF:CreateText(board, "GameFontNormal", "TOPLEFT", 12, -10)
    board.title:SetPoint("TOPRIGHT", board.clock, "TOPLEFT", -8, 0)
    board.title:SetJustifyH("LEFT")
    board.title:SetWordWrap(false)

    -- Closing the board means you've finished fishing, so it stops the log
    -- rather than leaving a timer running out of sight.
    local close = CreateFrame("Button", nil, board, "UIPanelCloseButton")
    board.close = close -- so a test can press it rather than call past it
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScale(0.8)
    close:SetScript("OnClick", function()
        if MF:IsSessionRunning() then MF:StopSession() end
        MF:ShowBoard(false)
    end)
    Tooltip(close, "Close", "Stops your fishing log and hides the board.")

    -- Three summary cells: big number over a small label.
    board.cells = {}
    for i = 1, 3 do
        local cell = {}
        cell.value = MF:CreateText(board, "GameFontHighlight", "TOPLEFT", 12 + (i - 1) * 88, -30)
        cell.value:SetWidth(84)
        cell.value:SetJustifyH("LEFT")
        cell.label = MF:CreateText(board, "GameFontDisableSmall", "TOPLEFT", 12 + (i - 1) * 88, -46)
        board.cells[i] = cell
    end
    -- Casts and fish are different totals; keep the main panel compact and
    -- expose the accepted-cast ledger beside its existing catch count.
    local outcomes=CreateFrame("Frame",nil,board)
    outcomes:SetSize(84,30);outcomes:SetPoint("TOPLEFT",12,-28);outcomes:EnableMouse(true)
    outcomes:SetScript("OnEnter",function(frame)
        if MF:InMatch() then return end
        GameTooltip:SetOwner(frame,"ANCHOR_RIGHT")
        GameTooltip:AddLine("Cast outcomes",1,.82,0)
        GameTooltip:AddLine(MF:CastOutcomeSummary(MF.session),1,1,1,true)
        GameTooltip:AddLine("One landed cast can contain several fish. Unknown is not an escape.",.65,.65,.65,true)
        GameTooltip:Show()
    end)
    outcomes:SetScript("OnLeave",function() GameTooltip:Hide() end)
    board.cells[1].outcomes=outcomes

    board.rows = {}
    for i = 1, ROWS do
        local y = -64 - (i - 1) * ROW_H
        local row = CreateFrame("Frame", nil, board)
        row:SetSize(WIDTH - 20, ROW_H)
        row:SetPoint("TOPLEFT", 10, y)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 0.82, 0, 0.12) -- specimens
        row.highlight:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 20, 0)
        row.name:SetWidth(160)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.score:SetPoint("RIGHT", -4, 0)
        row.score:SetJustifyH("RIGHT")
        board.rows[i] = row
    end

    local barsY = -70 - ROWS * ROW_H
    board.barS = CreateBar(board, barsY, 0.35, 0.7, 0.9)            -- fishing skill
    board.barS:EnableMouse(true)
    board.barS:SetScript("OnEnter", function(bar)
        local rank, max, bonus, parts = MF:FishingSkill()
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Fishing skill")
        if rank and max then
            GameTooltip:AddLine(("%d of %d"):format(rank, max), 1, 1, 1)
            if bonus and bonus > 0 then
                -- Itemised, because they run out at different times: the
                -- lure goes first, the food outlasts it by a mile, and the
                -- gear doesn't go anywhere.
                for _, part in ipairs({ { parts.lure, "from your lure" },
                                        { parts.gear, "from your gear" },
                                        { parts.buffs, "from food and buffs" } }) do
                    if part[1] > 0 then
                        GameTooltip:AddLine(("+%d %s"):format(part[1], part[2]), 0.35, 0.62, 1)
                    end
                end
            end
        else
            GameTooltip:AddLine("Not learned yet", 0.8, 0.8, 0.8)
        end
        -- What skill is worth, as a figure rather than a paragraph. It is
        -- not a multiplier: nothing is scaled. The bottom of each fish's
        -- range moves up and the top stays exactly where it was, so the
        -- honest number is how far up that range the small ones stop.
        local lift, _, effective = MF:SkillFloorLift()
        GameTooltip:AddLine(" ")
        if MF:InMatch() then
            -- Worth saying plainly, in the moment somebody would otherwise
            -- wonder why their skill stopped counting.
            GameTooltip:AddDoubleLine("In a match", "weights are flat", 1, 1, 1, 1, 0.5, 0)
            GameTooltip:AddLine("Everyone fishes the same water in a match, whatever their "
                .. "skill. Your lure still helps you cast.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
            return
        end
        GameTooltip:AddDoubleLine("Fishing at", tostring(effective), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Weight floor", ("+%d%%"):format(lift * 100 + 0.5),
            1, 1, 1, 0.35, 0.62, 1)
        GameTooltip:AddLine(lift > 0
            and "The small ones have stopped biting. The heaviest is the same at any skill."
            or "Skill lifts the bottom of your catches, never the top.", 0.8, 0.8, 0.8, true)

        local need, nextLift, away = MF:NextSkillFloor()
        if need then
            GameTooltip:AddDoubleLine(("Next step at %d"):format(need),
                ("+%d%%"):format(nextLift * 100 + 0.5), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
            GameTooltip:AddLine(("%d to go."):format(away), 0.6, 0.6, 0.6)
        end

        local need, kind, rating, rate = MF:SkillHere(nil, effective)
        GameTooltip:AddLine(" ")
        if need then
            local verdict = rating == "reliable" and "you should land almost everything"
                or rating == "possible" and "you'll land some, but fish will get away"
                or "most fish will get away"
            GameTooltip:AddDoubleLine("This zone",
                ("%s from %d"):format(kind, need), 1, 1, 1, 1, 0.82, 0)
            GameTooltip:AddLine(("At %s, %s%s."):format(tostring(effective or "?"), verdict,
                rate and (" (about %d%% escape)"):format(math.floor(rate * 100 + 0.5)) or ""),
                0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("From the casts Fishing Log anglers have logged here.",
                0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddDoubleLine("This zone", "not known yet", 1, 1, 1, 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Not enough anglers have logged casts here to say what skill "
                .. "it needs. Every cast you make adds to it.", 0.6, 0.6, 0.6, true)
        end

        local next1 = MF:SkillNextStep()
        if next1 then GameTooltip:AddLine(next1, 0.6, 0.9, 1, true) end
        if not bonus or bonus == 0 then
            GameTooltip:AddLine("A lure adds to it while it lasts - and that counts.",
                0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    board.barS:SetScript("OnLeave", function() GameTooltip:Hide() end)
    board.barA = CreateBar(board, barsY - 15, 0.2, 0.8, 0.4)        -- lure, or match clock
    board.barB = CreateBar(board, barsY - 30, 0.9, 0.5, 0.1)        -- frenzy
    -- What a frenzy is, and the thing people actually want to know: that it
    -- belongs to this water rather than the realm, so the lake over the hill
    -- is on its own clock and worth walking to.
    board.barB:EnableMouse(true)
    board.barB:SetScript("OnEnter", function(bar)
        local spot = MF:CurrentSpot()
        local active, secs = MF:FrenzyPresentationState(spot and spot.key)
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Feeding frenzy")
        GameTooltip:AddLine(("Fish run %d%% heavier and specimens are %s as likely."):format(
            math.floor((MF.FRENZY_WEIGHT - 1) * 100 + 0.5),
            MF.FRENZY_SPECIMEN == 2 and "twice" or (MF.FRENZY_SPECIMEN .. " times")), 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Every spot gets %d minutes in every %d hours."):format(
            MF.FRENZY_LENGTH / 60, MF.FRENZY_CYCLE / 3600), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("It isn't random and it isn't realm-wide. Each water keeps its own "
            .. "schedule, worked out from where it is, so every angler sees the same clock "
            .. "for the same spot - and a lake that's quiet now may be in frenzy already.",
            0.8, 0.8, 0.8, true)
        if spot and spot.name then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(active
                and ("|cffff8000%s is in frenzy|r - %s left"):format(spot.name, MF:FormatClock(secs))
                or (secs and ("%s: next in %s"):format(spot.name, MF:FormatClock(secs))
                    or "No fishing location recorded here yet."), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    board.barB:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Three lines, not two. The bounty needs two of them: "Bounty: Oily
    -- Blackmouth in Hillsbrad Foothills" is twice what 280 pixels hold,
    -- and with wrapping off it simply stopped mid-word.
    board.footer = {}
    for i = 1, 3 do
        local line = MF:CreateText(board, "GameFontHighlightSmall", "TOPLEFT", 12, barsY - 49 - (i - 1) * 13)
        line:SetPoint("RIGHT", -12, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        board.footer[i] = line
    end
    board:EnableMouse(true)
    board:SetScript("OnEnter", function()
        if not board.kingDetail then return end
        GameTooltip:SetOwner(board, "ANCHOR_RIGHT")
        GameTooltip:AddLine(board.kingDetail, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    board:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Cast and Lure must be secure buttons: you click them, not the addon.
    local cast, lure = MF:CreateSecureButtons(board)
    MF:SetupCastBinding(board)
    StyleIcon(cast, FISHING_ICON, "Cast", "Start fishing.")
    StyleIcon(lure, FISHING_ICON, "Apply lure", "Left-click: puts your best lure on your pole. Right-click: choose a lure.")
    board.cast, board.lure = cast, lure

    board.pole = IconButton(board, FISHING_ICON, "Fishing gear", "Left-click: swap pole. Right-click: Fishing Outfit wardrobe.",
        function(_,button)
            if button == "RightButton" then MF:OpenFishingOutfit() else MF:TogglePole() end
        end)
    board.pole:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    board.stop = IconButton(board, "Interface\\Icons\\INV_Misc_PocketWatch_01", "Stop the log",
        "Ends this session and prints a summary.", function() MF:StopSession() end)
    board.share = IconButton(board, "Interface\\Icons\\INV_Letter_15", "Share",
        "Posts your log or match result to chat.", function() MF:Share() end)
    board.journal = IconButton(board, "Interface\\Icons\\INV_Misc_Book_09", "Angler's Journal",
        "Left-click: journal. Right-click: Fishing here.", function(_, button)
            if button == "RightButton" then MF:OpenFishingHere()
            elseif MF.current and MF:NoticeForMatch(MF.current.id) then MF:OpenMatchEvent(MF.current)
            else MF:ToggleJournal() end
        end)
    board.journal:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    board.volume = IconButton(board, "Interface\\Icons\\INV_Misc_Horn_01", "Volume",
        "Every game volume on a slider, to change while the line is out.",
        function(self) MF:ToggleVolumePanel(self) end)

    local buttons = { cast, lure, board.pole, board.stop, board.share }
    for i, button in ipairs(buttons) do
        button:SetPoint("BOTTOMLEFT", 12 + (i - 1) * (ICON_SIZE + 8) + (i > 3 and 8 or 0), 10)
    end
    -- The journal is the only button that's always there and always does the
    -- same thing, so it gets a corner rather than a place in the queue. Stop
    -- and Share come and go with a session, and a button that moves when
    -- they do is one you have to look for every time.
    board.journal:SetPoint("BOTTOMRIGHT", -12, 10)
    -- Volume sits beside it for the same reason: always there.
    board.volume:SetPoint("BOTTOMRIGHT", board.journal, "BOTTOMLEFT", -8, 0)
end

function MF:BoardVolumeButton() return self.boardVolume or (board and board.volume) end

local function CreateToast()
    toast = MF:CreatePanel("TheFishingLogToast", 360, 90, { backdrop = "tooltip", strata = "HIGH" })
    toast:SetPoint("TOP", UIParent, "TOP", 0, -160)

    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(56, 56)
    toast.icon:SetPoint("LEFT", 16, 0)

    toast.header = MF:CreateText(toast, "GameFontNormalHuge")
    toast.header:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, 0)
    toast.line1 = MF:CreateText(toast, "GameFontHighlightLarge")
    toast.line1:SetPoint("TOPLEFT", toast.header, "BOTTOMLEFT", 0, -4)
    toast.line2 = MF:CreateText(toast, "GameFontHighlight")
    toast.line2:SetPoint("TOPLEFT", toast.line1, "BOTTOMLEFT", 0, -2)
    for _, text in ipairs({ toast.header, toast.line1, toast.line2 }) do
        text:SetWidth(260)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
    end

    -- Hold for a few seconds, then fade out. Click to dismiss - and a
    -- pop-up about a fish opens that fish's card on the way out, since
    -- the card is the first thing you'd go looking for.
    local fade = toast:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetStartDelay(5)
    alpha:SetDuration(1.5)
    fade:SetScript("OnFinished", function() toast:Hide(); NextToast() end)
    toast.fade = fade
    toast:SetScript("OnMouseDown", function(_, button)
        local id = toast.card
        fade:Stop(); toast:Hide(); NextToast()
        if id and button ~= "RightButton" then MF:ShowCard(id) end
    end)
end

MF:On("TFL_INIT", function(self)
    CreateBoard()
    CreateToast()
    self:ApplyBoardScale()
end)

function MF:ApplyBoardScale()
    if board then board:SetScale(self.db.settings.boardScale or 1) end
end

function MF:ResetBoardPosition()
    board:ClearAllPoints()
    board:SetPoint(unpack(BOARD_HOME))
end

-- Big centre-screen pop-up (specimens, records, rank ups, frenzies, wins).
local POPUP_SETTINGS = {
    ["SPECIMEN!"] = "popupSpecimens", ["NEW SPECIMEN!"] = "popupSpecimens",
    ["KING OF THE SPOT"] = "popupRecords", ["RANK UP!"] = "popupRanks",
    ["FEEDING FRENZY"] = "popupFrenzies", ["BOUNTY REWARD"] = "popupBounties", ["FRENZY SOON"] = "popupFrenzies",
}

-- Which sound switch each pop-up's sound answers to.
local SOUND_SETTINGS = {
    ["SPECIMEN!"] = "soundSpecimens", ["NEW SPECIMEN!"] = "soundSpecimens",
    ["KING OF THE SPOT"] = "soundRecords", ["RANK UP!"] = "soundRanks",
    ["NEW CARD"] = "soundCards",
    ["FEEDING FRENZY"] = "soundFrenzies", ["EXTRAVAGANZA"] = "soundFrenzies", ["FRENZY SOON"] = "soundFrenzies",
    ["BOUNTY REWARD"] = "soundBounties",
    ["MATCH OVER"] = "soundMatches", ["TOURNAMENT CHAMPION"] = "soundMatches",
    ["MATCH STARTED"] = "soundMatches",
    ["EVENT STARTING"] = "soundMatches",
    ["SEASON OVER"] = "soundSeasons",
    ["GOAL COMPLETE"] = "soundGoals",
}
MF.POPUP_SOUND_SETTINGS = SOUND_SETTINGS

function MF:PopupAllowed(header)
    local settings = self.db.settings
    if not settings.toasts or settings[POPUP_SETTINGS[header] or "popupOther"] == false then return false end
    if header == "FEEDING FRENZY" and type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then return false end
    return true
end

NextToast = function()
    local presenter = MF.toastPresenter
    if not toast then return end
    if presenter then
        if presenter.Busy() then return end
    elseif toast:IsShown() then
        return
    end
    if not MF.db.settings.toasts then toastQueue = {} return end
    local notice = table.remove(toastQueue, 1)
    while notice do
        local expired = notice.expires and (GetTime() > notice.expires or notice.spot ~= MF:SpotKey())
        if not expired and MF:PopupAllowed(notice[2]) then break end
        -- Category controls affect visuals; retain the existing Sounds setting.
        if not expired then MF:Sound(notice[8], SOUND_SETTINGS[notice[2]]) end
        notice = table.remove(toastQueue, 1)
    end
    if not notice then return end
    local icon, header, line1, line2, r, g, b, sound = unpack(notice, 1, 8)
    MF:Sound(sound, SOUND_SETTINGS[header])
    if presenter then presenter.Show(notice) return end
    toast.icon:SetTexture(icon or 134400)
    toast.header:SetText(header)
    toast.header:SetTextColor(r or 1, g or 0.82, b or 0)
    toast:SetBackdropBorderColor(r or 1, g or 0.82, b or 0)
    toast.line1:SetText(line1 or "")
    toast.line2:SetText(line2 or "")
    toast.card = notice.card
    toast:SetHeight(math.max(96, 32 + toast.header:GetStringHeight()
        + toast.line1:GetStringHeight() + toast.line2:GetStringHeight() + 6))
    toast.fade:Stop()
    toast:SetAlpha(1)
    toast:Show()
    toast.fade:Play()
end

-- A toast presenter calls this when its toast has gone, for the next one.
function MF:ToastDone() NextToast() end

function MF:Toast(icon, header, line1, line2, r, g, b, sound, context)
    if not toast or not self:PopupAllowed(header) then self:Sound(sound, SOUND_SETTINGS[header]) return end
    if #toastQueue >= 20 then table.remove(toastQueue, 1) end
    local notice = { icon, header, line1, line2, r, g, b, sound }
    if context then notice.spot, notice.expires, notice.card = context.spot, context.expires, context.card end
    toastQueue[#toastQueue + 1] = notice
    NextToast()
end

-- Out of the way for the fight, back again afterwards
--
-- The cast, lure and binding buttons on the board are the game's secure
-- kind, which makes the whole board protected - and nothing an addon
-- does may show or hide a protected frame during combat. Pressing the X
-- mid-fight only ever produced "Interface action failed because of an
-- AddOn".
--
-- Hiding it as the fight starts is no better: PLAYER_REGEN_DISABLED
-- already arrives in lockdown, so the earliest moment an addon can see
-- combat beginning is a moment too late to act on it.
--
-- A state driver is the way through. The rule - hidden in combat, shown
-- otherwise - is handed to the game beforehand, and the game applies it
-- from inside, where it is allowed to. We never touch the frame during
-- a fight at all.
--
-- boardOpen is what the player asked for, which is not the same as what
-- is on screen: during a fight an open board is hidden and still open.
local boardOpen = false
local wanted = nil -- asked for mid-fight, applied when it ends

local function CanDrive()
    return RegisterStateDriver and UnregisterStateDriver and true or false
end

function MF:BoardOpen()
    return boardOpen
end

local function Apply(self, show)
    boardOpen = show
    if show then
        board:Show()
        if CanDrive() then
            RegisterStateDriver(board, "visibility", "[combat] hide; show")
        end
        self:UpdateBoard()
    else
        -- The driver has to let go before we hide it, or it would simply
        -- put the board back at the next thing that changes.
        if CanDrive() then UnregisterStateDriver(board, "visibility") end
        board:Hide()
    end
end

function MF:ShowBoard(show)
    if not board then return end
    show = show and true or false
    if show == boardOpen then
        wanted = nil
        if show then self:UpdateBoard() end
        return
    end
    -- Handing the rule over, or taking it back, is itself a protected
    -- act. During a fight an open board is already out of sight, so
    -- there is nothing to see here either way - only something to do
    -- afterwards.
    if InCombatLockdown() then
        if wanted ~= show then
            self:Print(show and "The board will open when you're out of combat."
                or "The board will close when you're out of combat.")
        end
        wanted = show
        return
    end
    wanted = nil
    Apply(self, show)
end

MF:On("PLAYER_REGEN_ENABLED", function(self)
    if wanted == nil then return end
    local show = wanted
    wanted = nil
    -- The driver has already put an open board back by now, so closing
    -- one that was closed mid-fight means undoing that.
    if show ~= boardOpen then Apply(self, show) end
end)

function MF:ToggleBoard()
    self:ShowBoard(not boardOpen)
end

MF:Command("show", "Other", "/tfl show | hide - the board", function(self) self:ShowBoard(true) end)
MF:Command("hide", "Other", nil, function(self) self:ShowBoard(false) end)

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------

local function SetCell(i, value, label)
    board.cells[i].value:SetText(value or "")
    board.cells[i].label:SetText(label or "")
end

local function SetRow(i, icon, left, right, highlight)
    local row = board.rows[i]
    row.icon:SetShown(icon ~= nil)
    if icon then row.icon:SetTexture(icon) end
    row.name:SetPoint("LEFT", icon and 20 or 4, 0)
    row.name:SetText(left or "")
    row.score:SetText(right or "")
    row.highlight:SetShown(highlight == true)
end

-- Idle, the board shrinks to its title, conditions and buttons; there's
-- nothing to list until you cast.
local FULL_HEIGHT = 96 + ROWS * ROW_H + 41 + 30 + 36 + 18
local COMPACT_HEIGHT = 96 + 41 + 30 + 18

local function SetCompact(compact)
    local extra = MF:HasFishingGoals() and 18 or 0
    if board.compact == compact and board.goalExtra == extra then return end
    board.compact = compact
    board.goalExtra = extra
    board:SetHeight((compact and COMPACT_HEIGHT or FULL_HEIGHT) + extra)
    for _, row in ipairs(board.rows) do row:SetShown(not compact) end
    for _, cell in ipairs(board.cells) do
        cell.value:SetShown(not compact)
        cell.label:SetShown(not compact)
    end
    local barsY = compact and -34 or (-70 - ROWS * ROW_H)
    board.barS:SetPoint("TOPLEFT", 12, barsY)
    board.barA:SetPoint("TOPLEFT", 12, barsY - 20)
    board.barB:SetPoint("TOPLEFT", 12, barsY - 40)
    for i, line in ipairs(board.footer) do
        line:SetPoint("TOPLEFT", 12, barsY - 63 - (i - 1) * 13)
    end
end

function MF:UpdateBoard()
    -- Open rather than shown: a fight hides the board without closing
    -- it, and a board that stopped keeping count while you fought would
    -- come back wrong.
    if not board or not boardOpen or InCombatLockdown() then return end
    if self.boardPresenter then
        self:DrawIcons()
        local ok, err = pcall(self.boardPresenter, self)
        if not ok then geterrorhandler()(err) end
        return
    end
    SetCompact((self.current and self:NoticeForMatch(self.current.id)) ~= nil or (not self.current and not self.session))
    if self.current then
        self:DrawMatch(self.current)
    elseif self.session then
        self:DrawSession(self.session)
    else
        board.title:SetText("The Fishing Log - cast to start a log")
        board.clock:SetText("")
        board.stop:Hide()
        board.share:Hide()
    end
    self:DrawIcons()
    self:DrawBars()
    self:DrawFooter()
end

MF:On("PLAYER_REGEN_ENABLED", function(self) self:UpdateBoard() end)

-- The lure and pole buttons show what they'd actually use.
function MF:DrawIcons()
    local lure = self:BestLure()
    board.lure:SetNormalTexture(lure and self:FishIcon(lure) or FISHING_ICON)
    local lureIcon = board.lure:GetNormalTexture()
    if lureIcon then lureIcon:SetDesaturated(lure == nil) end -- greyed when you have none
    board.pole:SetNormalTexture(GetInventoryItemTexture("player", 16) or FISHING_ICON)
end

-- The skill this water asks for, after the bar's label, in the colour of
-- how you measure up: green where your catches should be reliable, gold
-- where they're possible but fish will get away, red below that. Nothing
-- at all where nobody has logged enough casts to say.
function MF:SkillHereTag(effective)
    local need, _, rating = self:SkillHere(nil, effective)
    if not need then return "" end
    local colour = rating == "reliable" and self.C.good
        or rating == "possible" and self.C.gold or self.C.bad
    return ("  %s(here %s%d+|r%s)|r"):format(self.C.muted, colour, need, self.C.muted)
end

function MF:DrawBars()
    local skill, maxSkill, bonus = self:FishingSkill()
    if skill and maxSkill and maxSkill > 0 then
        -- A lure can carry you past the ceiling, so the scale grows to fit
        -- it. Otherwise a capped angler sees a full bar either way and the
        -- lure - the whole reason the next cast is better - shows nowhere.
        bonus = math.max(0, bonus or 0)
        local top = math.max(maxSkill, skill + bonus)
        -- Gold at the ceiling: your own skill is as high as it goes, and
        -- won't move again until you go and raise it.
        local capped = skill >= maxSkill
        SetBar(board.barS, skill / top,
            (capped and "|cffffd100Fishing skill|r" or "Fishing skill") .. self:SkillHereTag(skill + bonus),
            bonus > 0 and ("%d  |cff66ccffBonus +%d|r"):format(skill, bonus)
                or ("%d / %d"):format(skill, maxSkill),
            capped and 0.9 or 0.35, capped and 0.8 or 0.7, capped and 0.2 or 0.9)
        SetBonus(board.barS, skill / top, bonus / top)
    else
        SetBar(board.barS, 0, "Fishing skill", skill and tostring(skill) or "not learned",
            0.35, 0.35, 0.35)
        SetBonus(board.barS, 0, 0)
    end

    local m = self.current
    if m and not m.finished and not self:NoticeForMatch(m.id) then
        local now, span = GetServerTime(), m.endsAt - m.startsAt
        if now < m.startsAt then
            -- The wait can be a delayed start, not just the 30 second lobby,
            -- so the bar fills from whenever we heard about the match.
            local lobby = math.max(1, m.startsAt - (m.heard or (m.startsAt - 30)))
            SetBar(board.barA, (now - (m.startsAt - lobby)) / lobby, "Starting",
                self:FormatClock(m.startsAt - now), 0.9, 0.8, 0.2)
        else
            SetBar(board.barA, (m.endsAt - now) / span, "Time left",
                self:FormatClock(m.endsAt - now), 0.3, 0.6, 1)
        end
    else
        local lure = self:LureTimeLeft()
        SetBar(board.barA, lure and lure / 600 or 0, lure and "Lure" or "No lure",
            lure and self:FormatClock(lure) or "", 0.2, 0.8, 0.4)
    end

    local key = m and m.spot or self:SpotKey()
    local active, secs = self:FrenzyPresentationState(key)
    -- The ambient effect describes where the player is, even when the board
    -- is displaying a match taking place somewhere else.
    local here = self:SpotKey()
    local hereActive = self:FrenzyPresentationState(here)
    self:UpdateBoardFrenzy(hereActive)
    if active then
        SetBar(board.barB, secs / self.FRENZY_LENGTH, "|cffff8000FRENZY ACTIVE|r",
            self:FormatClock(secs), 0.9, 0.5, 0.1)
    elseif secs then
        SetBar(board.barB, 1 - secs / (2 * 60 * 60), "Next frenzy",
            self:FormatClock(secs), 0.35, 0.35, 0.35)
    else
        SetBar(board.barB,0,"No frenzy access area nearby","",0.35,0.35,0.35)
    end
end

function MF:DrawFooter()
    board.goal:SetText(self:HasFishingGoals() and self:FishingGoalText() or "")
    local key, name, mapID
    if self.current then
        key, name, mapID = self.current.spot, self.current.name, self.current.mapID
    else
        key, name, mapID = self:SpotInfo()
    end

    -- An event you've signed up for within the hour takes the bounty's line.
    local event = self:NextSignedEvent()
    local currentEvent = self.current and self:NoticeForMatch(self.current.id)
    local untilEvent = event and event.startsAt - GetServerTime()
    -- The what on one line and the where on the next, because a fish
    -- name and a zone name together never fit a 280 pixel board.
    local counts, floor = self:MyVersionCounts()
    if not counts then
        board.footer[1]:SetText(self.C.bad .. "Out of date - your catches don't count|r")
        board.footer[2]:SetText(("    for others. Update to %s or newer."):format(floor))
    elseif currentEvent then
        board.footer[1]:SetText("Match: " .. self.MODES[self.current.mode])
        board.footer[2]:SetText("Open journal for Events standings")
    elseif untilEvent and untilEvent <= 3600 then
        board.footer[1]:SetText(("Event: |cff66ccff%s|r"):format(event.title))
        board.footer[2]:SetText(("    starts in %s"):format(
            self:FormatClock(math.max(0, untilEvent))))
    else
        local _, bountyID, bountyZone = self:TodayBounty()
        local best = self:MyBountyBest()
        -- A star rather than the weight: the longest zone plus a weight
        -- is still wider than the board, and your own figure is already
        -- on the Bounty tab in full. Here it only has to say you are in.
        -- The fish takes the whole of the first line: "Bloated Bristle
        -- Whisker Catfish" and a label is already most of 280 pixels.
        -- The mark that says you have entered goes on the second line,
        -- which has room, and your own figure stays on the Bounty tab
        -- where there is space to say it properly.
        board.footer[1]:SetText(("Bounty: %s"):format(self:FishName(bountyID)))
        board.footer[2]:SetText(("    in %s%s"):format(bountyZone or "anywhere",
            best > 0 and ("  " .. BOUNTY_IN) or ""))
        if self:BountyFormat("day") == "top3" then
            board.footer[2]:SetText(("    %s - %s"):format(bountyZone or "anywhere", self:BountyProgressText("day")))
        end
    end

    local king = self:King(key)
    board.kingDetail = king and ("King: %s - %s, %s"):format(self:ShortName(king.h), self:FishName(king.id), MF:Weight(king.w)) or nil
    if not self:RecordsReady(mapID) then
        board.footer[3]:SetText("King: checking records...")
    elseif king then
        board.footer[3]:SetText(("King: |cffffd100%s|r - %s"):format(
            self:ShortName(king.h), MF:Weight(king.w)))
    else
        board.footer[3]:SetText("No King here yet - set a record!")
    end
end

function MF:DrawSession(s)
    local running = self:IsSessionRunning()
    local elapsed = self:SessionElapsed(s)
    board.title:SetText("Solo - " .. self:SessionWhere(s))
    board.clock:SetText((running and "|cff3ee63e" or "|cffa0a0a0") .. self:FormatClock(elapsed) .. "|r")

    local perHour = elapsed > 30 and (s.count / elapsed * 3600) or 0
    local finds = self:FindsText(s.finds)
    SetCell(1, s.count .. " fish", finds and ("Caught - " .. finds) or perHour > 0 and ("Caught - %.0f/hr"):format(perHour) or "Caught")
    -- Units stay with the value; the smaller line explains what it means.
    SetCell(2, self:Weight(s.total),
        (self:ValueEnabled() and s.value > 0)
            and ("Total - " .. self:ShortMoney(s.value))
            or "Total")
    SetCell(3, self:Weight(s.biggest), "Best")

    board.stop:SetShown(running)
    board.share:Show()

    for i = 1, ROWS do
        local c = s.catches[i]
        if not c then
            SetRow(i)
        elseif c.find then
            SetRow(i, self:FishIcon(c.itemID), "|cffe6c066" .. (c.name or "Find") .. "|r", "|cffe6c066find|r")
        elseif c.junk then
            SetRow(i, self:FishIcon(c.itemID), "|cff9d9d9d" .. (c.name or "Junk") .. "|r", "|cff9d9d9djunk|r")
        else
            SetRow(i, self:FishIcon(c.itemID),
                c.specimen and ("|cffffd100" .. (c.name or "?") .. "|r") or (c.name or "?"),
                MF:Weight(c.weight), c.specimen)
        end
    end
    if not running and #s.catches == 0 then
        SetRow(1, nil, "|cffa0a0a0Stopped. Cast again for a new log.|r")
    end
end

function MF:DrawMatch(m)
    board.title:SetText(m.name .. (m.fish and (" - " .. self:FishName(m.fish)) or ""))
    board.stop:Hide()
    board.share:Show()
    local now = GetServerTime()
    if m.finished then
        board.clock:SetText("|cffff8000Final|r")
    elseif now < m.startsAt then
        board.clock:SetText("|cffffd100-" .. self:FormatClock(m.startsAt - now) .. "|r")
    else
        board.clock:SetText(self:FormatClock(m.endsAt - now))
    end

    local mine = m.players[self:MatchPlayerName(m, self.me)]
    SetCell(1, mine and tostring(mine.count) or "0", "your fish")
    SetCell(2, mine and ("%.2f"):format(self:WeightNumber(mine.total)) or "0.00",
        self:WeightUnit() .. " total")
    SetCell(3, self.MODES[m.mode]:gsub("Heaviest ", ""):gsub("Biggest ", ""), m.hcp and "format (hcp)" or "format")

    -- Team totals first (in gold), then individual players.
    local lines = {}
    if m.team then
        for i, t in ipairs(self:TeamStandings(m)) do
            if i > 3 then break end
            lines[#lines + 1] = { nil, ("|cffffd100%d. %s|r"):format(t.place or i, self:TeamLabel(t.name)),
                "|cffffd100" .. self:FormatScore(t.p, m) .. "|r" }
        end
    end
    local king = self:King(m.spot)
    for i, s in ipairs(self:Standings(m)) do
        local color = self:IsMe(s.name) and "|cff3ee63e" or "|cffffffff"
        local crown = (king and self:SameAngler(king.h, s.name)) and CROWN or ""
        local fish = self:StandingFish(s.p, m)
        lines[#lines + 1] = { fish and self:FishIcon(fish), ("%s%s%d. %s|r"):format(crown, color, s.place or i, self:ShortName(s.name)),
            self:FormatScore(s.p, m) }
    end
    for i = 1, ROWS do
        local line = lines[i]
        SetRow(i, line and line[1], line and line[2], line and line[3])
    end
end

------------------------------------------------------------------------
-- What you missed
--
-- Records that fell while you were offline arrive in a heap a few seconds
-- after login, which is exactly when the chat window is least readable. So
-- they get a panel instead, and every line is a place you can click to be
-- pointed back at.
------------------------------------------------------------------------

local MAX_SHOWN = 8
local panel
local lastLosses

local function CreatePanel(self)
    panel = self:CreatePanel("TheFishingLogLosses", 460, 300,
        { strata = "DIALOG", movable = true, escCloses = true,
          title = true, close = true })
    panel:SetPoint("CENTER", 0, 120)

    panel.rows = {}
    for i = 1, MAX_SHOWN do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(420, 18)
        row:SetPoint("TOPLEFT", 20, -52 - (i - 1) * 20)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.highlight:Hide()
        row:SetScript("OnEnter", function(r) if r.spot then r.highlight:Show() end end)
        row:SetScript("OnLeave", function(r) r.highlight:Hide() end)
        row:SetScript("OnClick", function(r) if r.spot then self:PointToSpot(r.spot) end end)
        row.text = self:CreateText(row, "GameFontHighlightSmall", "LEFT", 0, 0)
        row.text:SetWidth(420)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        panel.rows[i] = row
    end

    panel.more = self:CreateText(panel, "GameFontDisableSmall", "TOPLEFT", 20, -52 - MAX_SHOWN * 20)
    panel.hint = self:CreateText(panel, "GameFontDisableSmall", "BOTTOMLEFT", 20, 46)
    panel.hint:SetText("Click a line to be pointed at the water it happened on.")

    local journal = self:CreateButton(panel, "Open the journal", 140, function()
        panel:Hide()
        self:OpenJournal("fame")
    end)
    journal:SetPoint("BOTTOMLEFT", 20, 16)
    local done = self:CreateButton(panel, "I'll win them back", 150, function() panel:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -20, 16)
end

function MF:ShowLosses(losses)
    if not losses or #losses == 0 then return end
    if not panel then CreatePanel(self) end
    lastLosses = losses

    local crowns,records = 0,0
    for _, l in ipairs(losses) do
        if l.king then crowns = crowns + 1 end
        if l.record then records = records + 1 end
    end
    local parts = {}
    if records > 0 then
        parts[#parts + 1] = ("%d record%s"):format(records, records == 1 and "" or "s")
    end
    if crowns > 0 then
        parts[#parts + 1] = ("%d crown%s"):format(crowns, crowns == 1 and "" or "s")
    end
    panel.title:SetText("While you were away you lost " .. table.concat(parts, " and "))

    for i, row in ipairs(panel.rows) do
        local l = losses[i]
        row:SetShown(l ~= nil)
        if l then
            row.spot = self:SpotPosition(l.key) and l.key or nil
            row.text:SetText((row.spot and "|cffffd100" or "|cffa0a0a0") .. self:LossLine(l) .. "|r")
        end
    end
    panel.more:SetText(#losses > MAX_SHOWN
        and ("...and %d more."):format(#losses - MAX_SHOWN) or "")

    self:Sound(SOUNDKIT.RAID_WARNING, "soundRecordLost")
    panel:Show()
end

-- The panel is dismissed in a hurry more often than it's read.
MF:Command("losses", "Other", nil, function(self)
    if not lastLosses or #lastLosses == 0 then
        self:Print("You haven't lost anything since you logged in.")
        return
    end
    self:ShowLosses(lastLosses)
end)

function MF:ResetFishingFeedback()
    toastQueue,lastLosses={},nil
    if toast then toast.fade:Stop() toast:Hide() end
    if self.toastPresenter then self.toastPresenter.Clear() end
    if panel then panel:Hide() end
    if self.journalWindow then self.journalWindow:Hide() end
    for _,name in ipairs({"TheFishingLogCard","TheFishingLogCardShare","TheFishingLogPostEvent","TheFishingLogExport","TheFishingLogCopyReport"}) do
        local frame=rawget(_G,name)
        if frame and type(frame.Hide)=="function" then frame:Hide() end
    end
end
