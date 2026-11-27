-- MatchCues: a match you can't miss starting.
--
-- A match used to begin in silence - the board's clock quietly changed
-- from "in 0:16" to the time left, and anyone not watching it cast late.
-- So the start is counted down out loud, the way a race is: a minute's
-- notice, a tick at ten, three big numbers, then LINES IN! with a horn.
-- The end gets the same in reverse, short of the MATCH OVER that follows.
--
-- Nothing here goes over the wire. Every angler counts from the match's own
-- start and end, which are server time, so the cues land together for
-- everyone - and an angler still on 1.1.2 loses nothing but the fanfare.
--
-- Sounds follow "Matches, invites and events"; the big text in the middle
-- of the screen has its own switch (matchSplash); chat and the pop-up stay
-- on either way.
local _, MF = ...

local WARN_AT = 60       -- the minute's notice, before the start and the end
local TICK_AT = 10       -- the soft tick that says "nearly"
local COUNT_FROM = 3     -- the big numbers
local LATE = 30          -- joined later than this after the start: no fanfare

------------------------------------------------------------------------
-- Sounds
------------------------------------------------------------------------

-- Not every sound in the modern list is on every client. PlaySound says
-- whether it will play; if the first choice won't, the next one does.
local function Kit(name) return SOUNDKIT and SOUNDKIT[name] end
local TICK = { "UI_BATTLEGROUND_COUNTDOWN_TIMER", "IG_MAINMENU_OPTION_CHECKBOX_ON" }
local HORN = { "UI_BATTLEGROUND_COUNTDOWN_FINISHED", "READY_CHECK", "RAID_WARNING" }

local function Play(self, list)
    local settings = self.db.settings
    if not settings.sounds or settings.soundMatches == false then return end
    for _, name in ipairs(list) do
        local kit = Kit(name)
        if kit then
            local ok, willPlay = pcall(PlaySound, kit)
            if ok and willPlay ~= false then return name end
        end
    end
end
MF.MatchCueSound = Play

------------------------------------------------------------------------
-- The big text
------------------------------------------------------------------------

local splash

local function Build()
    splash = CreateFrame("Frame", "TheFishingLogMatchSplash", UIParent)
    splash:SetSize(600, 120)
    splash:SetPoint("CENTER", 0, 180)
    splash:SetFrameStrata("HIGH")
    splash:EnableMouse(false)
    splash.text = splash:CreateFontString(nil, "OVERLAY")
    splash.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 64, "THICKOUTLINE")
    splash.text:SetPoint("CENTER")
    splash.sub = splash:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    splash.sub:SetPoint("TOP", splash.text, "BOTTOM", 0, -6)

    local group = splash:CreateAnimationGroup()
    local grow = group:CreateAnimation("Scale")
    if grow.SetScaleFrom then grow:SetScaleFrom(1.6, 1.6) grow:SetScaleTo(1, 1)
    elseif grow.SetFromScale then grow:SetFromScale(1.6, 1.6) grow:SetToScale(1, 1) end
    grow:SetDuration(0.18)
    grow:SetSmoothing("OUT")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(0.9)
    fade:SetDuration(0.5)
    group:SetScript("OnFinished", function() splash:Hide() end)
    splash.anim = group
    splash:Hide()
end

-- Shows text in the middle of the screen; says whether it did.
function MF:MatchSplash(text, sub, r, g, b, hold)
    if self.db.settings.matchSplash == false then return false end
    if not splash then Build() end
    splash.anim:Stop()
    splash.text:SetText(text)
    splash.text:SetTextColor(r or 1, g or 0.82, b or 0)
    splash.sub:SetText(sub or "")
    splash:SetAlpha(1)
    splash:Show()
    splash.anim:Play()
    splash.shownText = text
    return true
end

function MF:MatchSplashText()
    return splash and splash:IsShown() and splash.shownText or nil
end

------------------------------------------------------------------------
-- When
------------------------------------------------------------------------

-- Each cue once per match. The ticker is one second, but it doesn't keep
-- step with the server's seconds, so a second can be skipped: a count
-- shows the number it lands on rather than waiting for one it missed.
local function Once(m, key)
    m.cues = m.cues or {}
    if m.cues[key] then return false end
    m.cues[key] = true
    return true
end

local function NotHere(self, m)
    local spot = self.SpotKey and self:SpotKey()
    return not self:AtMatchSpot(m, spot)
end

local function Count(self, m, which, left)
    if left < 1 or left > COUNT_FROM then return end
    -- 3, 2, 1: only ever downwards, one number per second.
    local last = m.cues and m.cues[which .. "n"]
    if last and left >= last then return end
    m.cues = m.cues or {}
    m.cues[which .. "n"] = left
    Play(self, TICK)
    if which == "start" then
        self:MatchSplash(tostring(left), nil, 1, 0.82, 0)
    else
        self:MatchSplash(tostring(left), "left", 1, 0.5, 0.25)
    end
end

local function Start(self, m)
    local length = self:FormatClock(m.endsAt - m.startsAt)
    self:MatchSplash("LINES IN!", ("%s  -  %s"):format(self.MODES[m.mode] or "Match", length), 0.4, 0.8, 1)
    Play(self, HORN)
    self:Print(("|cff66ccffThe match at %s has started!|r %s, %s."):format(
        m.name, self.MODES[m.mode] or "", length))
    self:Toast("Interface\\Icons\\Trade_Fishing", "MATCH STARTED",
        ("%s  -  %s"):format(self.MODES[m.mode] or "Match", length), m.name, 0.4, 0.8, 1)
    if NotHere(self, m) then
        self:Print(("|cffff5a5aYou're not at %s - catches won't count until you are.|r"):format(m.name))
        self:FloatWarning(("Go to %s"):format(m.name))
    end
    self:Fire("TFL_MATCH_STARTED", m)
end

function MF:MatchCueTick(now)
    local m = self.current
    if not m or m.finished or m.cancelled then return end
    now = now or GetServerTime()
    local toStart, toEnd = m.startsAt - now, m.endsAt - now

    if toStart > 0 then
        -- The minute's notice, if the wait was long enough to need one. An
        -- event has its own ("EVENT STARTING"), so it isn't said twice.
        if toStart <= WARN_AT and toStart > TICK_AT and (m.startsAt - (m.heard or now)) > WARN_AT
            and not (self.NoticeForMatch and self:NoticeForMatch(m.id))
            and Once(m, "start60") then
            self:Print(("The match at %s starts in %s."):format(m.name, self:FormatClock(toStart)))
            if NotHere(self, m) then
                self:Print(("|cffff5a5aYou're not at %s - catches won't count there.|r"):format(m.name))
                self:FloatWarning(("Match starts in %s - go to %s"):format(self:FormatClock(toStart), m.name))
            end
        end
        if toStart <= TICK_AT and toStart > COUNT_FROM and Once(m, "start10") then
            Play(self, TICK)
            self:MatchSplash(("Starting in %d"):format(toStart), nil, 1, 0.82, 0)
        end
        Count(self, m, "start", toStart)
        return
    end

    if now - m.startsAt <= LATE and Once(m, "start") then Start(self, m) end
    if toEnd <= 0 then return end
    if m.duration > WARN_AT * 2 and toEnd <= WARN_AT and toEnd > TICK_AT and Once(m, "end60") then
        self:Print(("|cffffd1001:00 left|r in the match at %s."):format(m.name))
        self:MatchSplash("1:00 left", nil, 1, 0.82, 0)
        Play(self, TICK)
    end
    if toEnd <= TICK_AT and toEnd > COUNT_FROM and Once(m, "end10") then
        Play(self, TICK)
        self:MatchSplash(("%d seconds left"):format(toEnd), nil, 1, 0.5, 0.25)
    end
    Count(self, m, "end", toEnd)
end

MF:OnTick(function(self) self:MatchCueTick() end)
