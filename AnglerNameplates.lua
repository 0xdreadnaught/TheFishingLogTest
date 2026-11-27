local _, MF = ...
local units = {}
local hooks = setmetatable({}, { __mode = "k" })
local texture = "Interface\\AddOns\\" .. MF.ADDON .. "\\Media\\AnglerHook.tga"
local SEEN_WITHIN = 3 * 86400 -- a TFL message from them this recently counts

local function Public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end

local function Plate(unit)
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(get) ~= "function" then return end
    local ok, plate = pcall(get, unit)
    if ok and Public(plate) and plate and not (plate.IsForbidden and plate:IsForbidden()) then
        return plate
    end
end

local function Clear(unit)
    local hook = units[unit]
    if hook then hook:Hide() end
    units[unit] = false
end

-- Only ask players a whisper can reach: one to the other faction comes
-- back as a "no player named" error in chat. Nameplate units can hand the
-- faction back as a secret on this client, which silently stopped every
-- lookup - so a friendly check stands in when the faction can't be read,
-- and an unreadable answer to both means don't ask.
local function SameSide(unit)
    local ok, faction, ours = pcall(function() return UnitFactionGroup(unit), UnitFactionGroup("player") end)
    if ok and Public(faction) and Public(ours) and faction and ours then return faction == ours end
    local okFriend, friend = pcall(UnitIsFriend, "player", unit)
    if okFriend and Public(friend) then return friend and true or false end
    return false
end

-- Matched on AnglerKey alone, the same identity everything else uses.
-- Forever's names have two words, and the client hands them over split at
-- the space ("Grey", realm "Maebyrn") while addon messages arrive as
-- "Grey-Maebyrn" - so comparing the plain name and the realm separately
-- failed for every angler on the realm and no hook was ever drawn. The key
-- drops the hyphen, the space and our own realm, so all three shapes meet;
-- a player from another realm keeps theirs in the key and can't collide.
--
-- One answer for every place a hook is drawn - nameplate, chat, target
-- frame - so a player is never marked in one and not the other.
function MF:IsRecentAngler(name, peers)
    if type(name) ~= "string" or name == "" or not Public(name) or not self.db or self:IsMe(name) then
        return false
    end
    local key = self:AnglerKey(name)
    if key == "" then return false end
    peers = peers or self:RecentCensusPlayers()
    if peers[key] then return true end
    -- Or anyone whose TFL messages we've received lately. Every message
    -- stamps anglersSeen, and it survives a reload, so this doesn't hang
    -- on a live reply - which older versions can't send to a two-word
    -- name, so nobody on the realm got a hook until everyone updated.
    local seen = self.db.anglersSeen and self.db.anglersSeen[key]
    return seen ~= nil and type(seen.at) == "number" and time() - seen.at < SEEN_WITHIN
end

local function Confirmed(self, unit, peers)
    local name = self:AnglerUnitIdentity(unit)
    if not name or self:IsMe(name) then return false end
    if self:IsRecentAngler(name, peers) then return true end
    if self.me and SameSide(unit) then self:RequestAnglerInfo(name, true) end
    return false
end

-- What to hang the hook beside
--
-- The name on the plate, wherever it is drawn. Blizzard's plate frame is
-- wider than its name, and a nameplate addon's container is wider still
-- and mostly empty, so hanging the hook off either left it floating.
--
-- Under EllesmereUI (and anything else that sets the name from the unit
-- on this client) the name text is a secret value: we can see the string
-- is there but not read it, so it can't be recognised by what it says. It
-- can still be anchored to, though, and we already know what it says -
-- the unit's own name - so the hook measures that name in the same font
-- and stands just off its left edge.
local function Shown(region)
    if not (region and region.IsVisible) then return false end
    local ok, visible = pcall(region.IsVisible, region)
    if not ok or not Public(visible) or not visible then return false end
    -- Nameplate alpha can come back secret. Shown and unreadable is still
    -- shown; only an alpha we can read and that is near zero rules it out.
    local okAlpha, alpha = pcall(region.GetEffectiveAlpha, region)
    if okAlpha and Public(alpha) and type(alpha) == "number" then return alpha > 0.05 end
    return true
end

local function IsText(region)
    return region and region.GetObjectType and region:GetObjectType() == "FontString"
end

-- The first line of a plate's text, colour codes out. EllesmereUI writes
-- onto Blizzard's own name text and can put a level in front ("60 | Grey
-- Maebyrn"), a title round it, or the guild on a second line - so the name
-- is looked for inside the first line rather than as the whole of it.
local function FirstLine(region)
    local ok, text = pcall(region.GetText, region)
    if not ok then return nil, false end
    if not Public(text) then return nil, true end
    if type(text) ~= "string" or text == "" then return nil, false end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return text:match("^[^\n]*"), false
end

-- "match" when the text reads as this player's name, "secret" when it
-- can't be read at all, nil otherwise.
local function Reads(region, key)
    local line, secret = FirstLine(region)
    if secret then return "secret" end
    if not line or not key or key == "" then return nil end
    return MF:AnglerKey(line):find(key, 1, true) and "match" or nil
end

-- Depth-first, in the order the addon built the plate. The first secret
-- text is the name on every plate seen so far: an addon creates the name
-- before the health text that might also be secret.
local function Find(frame, key, depth, found)
    for _, region in ipairs({ frame:GetRegions() }) do
        if IsText(region) and Shown(region) then
            local how = Reads(region, key)
            if how == "match" then found.match = region return found end
            if how == "secret" and not found.secret then found.secret = region end
        end
    end
    if depth > 0 then
        for _, child in ipairs({ frame:GetChildren() }) do
            if Shown(child) then
                Find(child, key, depth - 1, found)
                if found.match then return found end
            end
        end
    end
    return found
end

local function Anchor(plate, key, current)
    -- Still up and still the name: keep it rather than search every tick.
    if current and IsText(current) and Shown(current) and Reads(current, key) then return current end
    local found = Find(plate, key, 5, {})
    if found.match or found.secret then return found.match or found.secret end
    local uf = plate.UnitFrame
    if Shown(uf) then return uf.healthBar or uf end
    return plate
end

-- How wide this name is in that font, in the hook's own units. The text
-- is drawn at the plate's scale and the hook at UIParent's, so the width
-- is carried across both.
local ruler
local function NameWidth(to, plain, hook)
    -- What the line really says when we can read it, the bare name when not.
    plain = FirstLine(to) or plain
    if not plain or plain == "" then return end
    local ok, font, size, flags = pcall(to.GetFont, to)
    if not ok or not Public(font) or not Public(size) or not font or not size then return end
    if not ruler then
        ruler = UIParent:CreateFontString(nil, "BACKGROUND")
        ruler:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -200)
        ruler:SetAlpha(0)
    end
    if not pcall(ruler.SetFont, ruler, font, size, Public(flags) and flags or "") then return end
    ruler:SetText(plain)
    local w = ruler:GetStringWidth()
    local okScale, theirs, ours = pcall(function()
        return to:GetEffectiveScale(), hook:GetEffectiveScale() end)
    if not okScale or not Public(theirs) or not Public(ours) or not ours or ours == 0 then return w end
    return w * theirs / ours
end

local function Place(hook, to, plain)
    hook:ClearAllPoints()
    if not IsText(to) then
        hook:SetPoint("RIGHT", to, "LEFT", -3, 0)
        return
    end
    -- Text sized to its own contents - Blizzard's name, and EllesmereUI's,
    -- which clears any width on it - already starts where its left edge
    -- is. That edge is exact; measuring the name ourselves is the fallback
    -- for a fixed-width box, and it overshot on a plate drawn at its own scale.
    local okW, width, sw = pcall(function() return to:GetWidth(), to:GetStringWidth() end)
    if okW and Public(width) and Public(sw) and type(width) == "number" and type(sw) == "number"
        and width > 1 and width <= sw + 4 then
        hook:SetPoint("RIGHT", to, "LEFT", -3, 0)
        return
    end
    local ok, justify = pcall(to.GetJustifyH, to)
    justify = ok and Public(justify) and justify or "CENTER"
    if justify == "LEFT" then
        hook:SetPoint("RIGHT", to, "LEFT", -3, 0)
        return
    end
    local w = NameWidth(to, plain, hook)
    if not w then
        hook:SetPoint("RIGHT", to, "LEFT", -3, 0)
    elseif justify == "RIGHT" then
        hook:SetPoint("RIGHT", to, "RIGHT", -w - 3, 0)
    else
        hook:SetPoint("RIGHT", to, "CENTER", -w / 2 - 3, 0)
    end
end

-- The hook is our own frame rather than a texture on the plate, so an
-- addon that hides or fades Blizzard's plate doesn't take the hook with
-- it. Parented to UIParent, so it still goes when the interface is hidden.
local function NewHook()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(15, 15)
    f:SetFrameStrata("LOW")
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f.tex:SetTexture(texture)
    f:Hide()
    return f
end

local function Update(self, unit, peers)
    local plate = peers and Plate(unit)
    if not plate or not Confirmed(self, unit, peers) then Clear(unit) return end
    local hook = hooks[plate]
    if not hook then
        hook = NewHook()
        hooks[plate] = hook
    end
    -- The name as the plate shows it: "Grey Maebyrn", not the "Grey" the
    -- client hands back with "Maebyrn" in the realm slot.
    local name = self:AnglerUnitIdentity(unit)
    local plain = name and self:ShortName(name)
    local to = Anchor(plate, self:AnglerKey(name), hook.to)
    if hook.to ~= to or hook.plain ~= plain then
        hook.to, hook.plain = to, plain
        Place(hook, to, plain)
    end
    if units[unit] ~= hook then Clear(unit) end
    units[unit] = hook
    hook:Show()
end

function MF:RefreshAnglerNameplates()
    if not self.db or not next(units) then return end
    local peers = self.db.settings.anglerNameplateHook and self:RecentCensusPlayers()
    for unit in pairs(units) do Update(self, unit, peers) end
end

local events = CreateFrame("Frame")
if not MF.inert and pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_ADDED") then
    pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_REMOVED")
end
events:SetScript("OnEvent", function(_, event, unit)
    if not Public(unit) or type(unit) ~= "string" then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        Clear(unit)
        if MF.db and MF.db.settings.anglerNameplateHook then
            Update(MF, unit, MF:RecentCensusPlayers())
        end
    else
        Clear(unit)
        units[unit] = nil
    end
end)
-- What each visible nameplate resolved to, for when a hook doesn't show.
MF:Command("hooks", "Other", nil, function(self)
    local lines = {}
    local function Out(text) lines[#lines + 1] = Public(text) and text or "<line held a secret value>" end
    local peers = self:RecentCensusPlayers()
    Out(("Nameplate hooks: %s; %d confirmed anglers in the last 10 minutes."):format(
        self.db.settings.anglerNameplateHook and "on" or "off", self.Count(peers)))
    for key, p in pairs(peers) do
        Out(("  confirmed: key=%s name=%q %ds ago"):format(key, tostring(p.name),
            math.floor(GetTime() - (p.confirmedAt or 0))))
    end
    Out(("  send refusals=%d last=%s"):format(self.sendRefusals or 0, tostring(self.lastSendRefusal)))
    local any
    for unit, hook in pairs(units) do
        any = true
        local name = self:AnglerUnitIdentity(unit)
        local to = hook and hook.to
        local where = to and (to.GetObjectType and to:GetObjectType()) or "-"
        Out(("  %s: %s key=%s plate=%s confirmed=%s hook=%s beside=%s"):format(unit,
            tostring(name), name and self:AnglerKey(name) or "-", tostring(Plate(unit) ~= nil),
            tostring(name and peers[self:AnglerKey(name)] ~= nil),
            tostring(hook and hook:IsShown() or false), tostring(where)))
        local okF, faction = pcall(UnitFactionGroup, unit)
        local okR, friend = pcall(UnitIsFriend, "player", unit)
        local info = name and self:AnglerInfo(name)
        Out(("    faction=%s friend=%s sameSide=%s info=%s"):format(
            not okF and "<error>" or Public(faction) and tostring(faction) or "<secret>",
            not okR and "<error>" or Public(friend) and tostring(friend) or "<secret>",
            tostring(SameSide(unit)),
            info and ("%ds old%s"):format(math.floor(GetTime() - (info.at or 0)), info.full and "" or ", partial") or "none"))
        local seen = name and self.db.anglersSeen and self.db.anglersSeen[self:AnglerKey(name)]
        Out(("    last TFL message from them: %s"):format(seen and type(seen.at) == "number"
            and ("%.1f hours ago"):format((time() - seen.at) / 3600) or "never"))
        local ask = name and self.infoAsks and self.infoAsks[self:AnglerKey(name)]
        local sent = ask and self.whisperResults and self.whisperResults[ask.to]
        Out(("    asked=%s to=%q send=%s"):format(
            ask and ("%ds ago"):format(math.floor(GetTime() - ask.at)) or "never",
            ask and ask.to or "-",
            sent and ("%s, %ds ago"):format(sent.result, math.floor(GetTime() - sent.at)) or "not sent"))
        -- Every piece of text on the plate, so we can see where an addon
        -- keeps the name and why it didn't match.
        local plate = Plate(unit)
        local function Walk(frame, path, depth)
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "FontString" then
                    local ok, text = pcall(region.GetText, region)
                    local okA, alpha = pcall(region.GetEffectiveAlpha, region)
                    local shown = tostring(pcall(region.IsVisible, region) and region:IsVisible())
                        .. " alpha=" .. (not okA and "<error>" or Public(alpha) and ("%.2f"):format(alpha or 0) or "<secret>")
                        .. " usable=" .. tostring(Shown(region))
                    text = not ok and "<error>" or not Public(text) and "<secret>" or tostring(text)
                    Out(("    %s text=%q shown=%s"):format(path, (text:gsub("|", "||")), tostring(shown)))
                end
            end
            if depth <= 0 then return end
            for i, child in ipairs({ frame:GetChildren() }) do
                local ok, named = pcall(child.GetName, child)
                local label = ok and Public(named) and named or ("#" .. i)
                Walk(child, path .. ">" .. label, depth - 1)
            end
        end
        if plate then Walk(plate, "plate", 5) end
    end
    if not any then Out("  No nameplates seen. Friendly nameplates need to be turned on.") end
    self:ShowDiagnosticText(table.concat(lines, "\n"))
end)

MF:OnTick(function(self)
    if self.db.settings.anglerNameplateHook then self:RefreshAnglerNameplates() end
end)

------------------------------------------------------------------------
-- In chat
--
-- With nameplates off, the name over a player's head is drawn by the
-- game itself and no addon can touch it. Chat is where most players
-- meet each other anyway, so the hook goes in front of what a fellow
-- angler says - say, yell, guild, group, whispers and channels.
--
-- A filter only rewrites the message, not the name the chat frame draws
-- before it, so the hook leads the message: "[Grey Maebyrn]: (hook) hi".
-- Nothing is sent and nothing is stored; it's display only.
------------------------------------------------------------------------

local CHAT_HOOK = "|T" .. texture .. ":0|t "
-- Each kind of chat has its own switch under the main one, so the hook can
-- be left out of a busy guild chat and kept everywhere else.
MF.CHAT_HOOK_KINDS = {
    { key = "anglerChatHookSay", word = "say", label = "Say, yell and emotes",
      events = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" } },
    { key = "anglerChatHookGuild", word = "guild", label = "Guild and officer",
      events = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" } },
    { key = "anglerChatHookGroup", word = "group", label = "Party, raid and instance",
      events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
          "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
    { key = "anglerChatHookWhisper", word = "whisper", label = "Whispers",
      events = { "CHAT_MSG_WHISPER" } },
    { key = "anglerChatHookChannel", word = "channel", label = "Channels (General, Trade and the like)",
      events = { "CHAT_MSG_CHANNEL" } },
}
local CHAT_EVENTS, KIND_OF = {}, {}
for _, kind in ipairs(MF.CHAT_HOOK_KINDS) do
    for _, event in ipairs(kind.events) do
        CHAT_EVENTS[#CHAT_EVENTS + 1] = event
        KIND_OF[event] = kind.key
    end
end

local function ChatFilter(_, event, message, sender, ...)
    -- Chat in protected content can arrive secret; leave it exactly as is.
    local settings = MF.db and MF.db.settings
    if not settings or not settings.anglerChatHook then return false end
    if KIND_OF[event] and settings[KIND_OF[event]] == false then return false end
    if not Public(message) or not Public(sender) or type(message) ~= "string" then return false end
    if not MF:IsRecentAngler(sender) then return false end
    return false, CHAT_HOOK .. message, sender, ...
end

local chatInstalled
MF:On("TFL_LOGIN", function()
    if chatInstalled then return end
    local add = ChatFrame_AddMessageEventFilter
        or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if type(add) ~= "function" then return end
    chatInstalled = true
    for _, event in ipairs(CHAT_EVENTS) do pcall(add, event, ChatFilter) end
end)

-- /tfl chathook guild off - the same switches without opening Options.
MF:Command("chathook", "Other", "/tfl chathook [say|guild|group|whisper|channel|all] [on|off] - hook in chat",
    function(self, args)
        local s = self.db.settings
        local which, state = args[1], args[2]
        if which == "on" or which == "off" then which, state = "all", which end
        if which and (state == "on" or state == "off") then
            local on = state == "on"
            if which == "all" then
                s.anglerChatHook = on
            else
                local found
                for _, kind in ipairs(self.CHAT_HOOK_KINDS) do
                    if kind.word == which then s[kind.key], found = on, true end
                end
                if not found then
                    self:Print("Chat types: say, guild, group, whisper, channel - or all.")
                    return
                end
                if on then s.anglerChatHook = true end
            end
        end
        local parts = {}
        for _, kind in ipairs(self.CHAT_HOOK_KINDS) do
            parts[#parts + 1] = kind.word .. " " .. (s[kind.key] ~= false and "|cff00ff00on|r" or "|cffff4040off|r")
        end
        self:Print(("Chat hook %s: %s"):format(s.anglerChatHook and "|cff00ff00on|r" or "|cffff4040off|r",
            table.concat(parts, ", ")))
    end)

------------------------------------------------------------------------
-- On the target frame
--
-- The closest thing to "on the player" without a nameplate: target a
-- fellow angler and the hook sits beside their name on your target
-- frame. Blizzard's frame or a unit-frame addon's - the name is found
-- the same way it is on a plate, by what it says, and the frame's top
-- left corner stands in when the name can't be read or is shortened.
------------------------------------------------------------------------

local TARGET_FRAMES = {
    "EllesmereUIUnitFrames_Target", "ElvUF_Target", "SUFUnittarget",
    "PitBull4_Frames_Target", "Perl_Target_Frame", "TargetFrame",
}

local targetHook

local function TargetFrameShown()
    for _, name in ipairs(TARGET_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and f.IsVisible and Shown(f) then return f end
    end
end

local function HideTargetHook()
    if targetHook then targetHook:Hide(); targetHook.to = nil end
end

function MF:RefreshTargetHook()
    if not self.db or not self.db.settings.anglerTargetHook then HideTargetHook() return end
    local okTarget, isPlayer = pcall(UnitIsPlayer, "target")
    if not okTarget or not Public(isPlayer) or not isPlayer then HideTargetHook() return end
    local name = self:AnglerUnitIdentity("target")
    if not name or not self:IsRecentAngler(name) then HideTargetHook() return end
    local frame = TargetFrameShown()
    if not frame then HideTargetHook() return end

    if not targetHook then targetHook = NewHook() end
    local key, plain = self:AnglerKey(name), self:ShortName(name)
    local current = targetHook.to
    local to
    if current and IsText(current) and Shown(current) and Reads(current, key) == "match" then
        to = current
    else
        to = Find(frame, key, 6, {}).match
    end
    if to ~= targetHook.to or targetHook.frame ~= frame or targetHook.plain ~= plain then
        targetHook.to, targetHook.frame, targetHook.plain = to, frame, plain
        targetHook:ClearAllPoints()
        if to then
            Place(targetHook, to, plain)
        else
            targetHook:SetPoint("CENTER", frame, "TOPLEFT", 4, -4)
        end
    end
    -- Above the frame it marks, whatever strata that addon chose.
    local okS, strata, level = pcall(function() return frame:GetFrameStrata(), frame:GetFrameLevel() end)
    if okS and Public(strata) and Public(level) then
        targetHook:SetFrameStrata(strata)
        targetHook:SetFrameLevel((level or 0) + 20)
    end
    targetHook:Show()
end

MF:On("PLAYER_TARGET_CHANGED", function(self)
    HideTargetHook()
    self:RefreshTargetHook()
    -- Unit-frame addons fill the name in a moment after the event.
    C_Timer.After(0.2, function() self:RefreshTargetHook() end)
end)
MF:OnTick(function(self)
    if targetHook and targetHook:IsShown() or UnitExists("target") then self:RefreshTargetHook() end
end)
