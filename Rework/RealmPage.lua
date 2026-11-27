-- Realm: the hall of fame.
--   anglers   the heaviest catch known, a podium for the top three, then everyone else; click an
--             angler for their records (The Fishing Log's own page for one angler)
--   by fish   the heaviest of each fish and who holds it; the ones nobody has landed yet
--   XP        the angler XP leaderboard, with their rank titles
-- The Fishing Log keeps which view is up to itself; its footer buttons (season / all time, by fish,
-- my guild, XP leaderboard...) switch them, and we tell them apart by the buttons it offers.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local J = ns.Journal

local MF
local P = {}
ns.RealmPage = P
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t"

local function HasAction(state, label)
    for _, a in ipairs(state.actions or {}) do if a.label == label then return true end end
    return false
end

local function View(state)
    if HasAction(state, "By fish") and HasAction(state, "XP leaderboard") then return "anglers" end
    if HasAction(state, "Anglers") then return "species" end
    if HasAction(state, "Refresh") and HasAction(state, "Records") then return "xp" end
end

-- You in orange, guildmates in green (as The Fishing Log marks them)
local function NameColour(name)
    if MF:IsMe(name) then return 1, 0.62, 0 end
    if MF.InMyGuild and MF:InMyGuild(name) then return 0.25, 0.9, 0.25 end
    return 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Search: one box for all three views, so a name you looked up stays looked up as you switch.
-- Forgiving: no capitals, no accents ("kalanyos" finds Kalányos), a hyphen is a space, and every
-- word typed has to be in there somewhere.
-- ---------------------------------------------------------------------------
local ACCENTS = {
    ["à"] = "a", ["á"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a", ["æ"] = "ae",
    ["ç"] = "c", ["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e", ["ì"] = "i", ["í"] = "i",
    ["î"] = "i", ["ï"] = "i", ["ñ"] = "n", ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o",
    ["ö"] = "o", ["ø"] = "o", ["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u", ["ý"] = "y",
    ["ÿ"] = "y", ["ß"] = "ss",
    ["À"] = "a", ["Á"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a", ["Å"] = "a", ["Æ"] = "ae",
    ["Ç"] = "c", ["È"] = "e", ["É"] = "e", ["Ê"] = "e", ["Ë"] = "e", ["Ì"] = "i", ["Í"] = "i",
    ["Î"] = "i", ["Ï"] = "i", ["Ñ"] = "n", ["Ò"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o",
    ["Ö"] = "o", ["Ø"] = "o", ["Ù"] = "u", ["Ú"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ý"] = "y",
}
function P.Fold(s)
    s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("[\195][\128-\191]", ACCENTS)
    -- (the curly apostrophe is three bytes, so it can't sit in a [set] without eating other letters)
    return (s:lower():gsub("’", " "):gsub("[%-_']", " "))
end

-- Does this text hold every word of the search?
function P:Matches(...)
    local q = self.query or ""
    if q == "" then return true end
    local hay = {}
    for i = 1, select("#", ...) do hay[#hay + 1] = P.Fold(select(i, ...)) end
    local text = table.concat(hay, " ")
    -- "boomflex" finds Boom Flex too
    local squashed = text:gsub("%s+", "")
    for word in P.Fold(q):gmatch("%S+") do
        if not text:find(word, 1, true) and not squashed:find(word, 1, true) then return false end
    end
    return true
end

function P:Searching() return (self.query or "") ~= "" end

-- While searching: say so when nothing matched, and count "3 of 511 anglers"
function P:SearchFooter(items, found, total, one, many, why)
    if found == 0 and total > 0 then
        items[#items + 1] = { kind = "note", h = 44, text = why:format("|cffffffff" .. self.query .. "|r") }
    end
    self.count = ("%d of %d %s"):format(found, total, total == 1 and one or many)
end

local function Faction(name)
    local f = MF.FactionOf and MF:FactionOf(name)
    if f == "A" then return " |cff5080ff(A)|r" elseif f == "H" then return " |cffff4040(H)|r" end
    return ""
end

-- ---------------------------------------------------------------------------
-- Faces for the podium. The game only draws a real portrait of someone it can see as a unit
-- (you, your group, your target or mouseover, a nameplate near you). For everyone else we show
-- the race we last saw them as: learned from those same units, from the sender of any chat
-- line (the chat's player GUID gives race and sex), and from guildmates (below).
-- From Godfall's UI Rework 0.7.4 (MIT), without its whispers to strangers.
-- ---------------------------------------------------------------------------
local FACES_MAX = 3000
local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Faces()
    if not ns.db then return nil end
    ns.db.faces = ns.db.faces or {}
    return ns.db.faces
end

local function Remember(name, race, sex, class)
    local faces = Faces()
    name, race, sex, class = Plain(name), Plain(race), Plain(sex), Plain(class)
    if not (faces and MF and type(name) == "string" and name ~= "" and type(race) == "string") then return end
    local key = MF:AnglerKey(name)
    if key == "" then return end
    local f = faces[key]
    if not f then
        f = {}
        faces[key] = f
        faces.n = (faces.n or 0) + 1
    end
    local now = time()
    -- Nothing new: leave the saved data alone (chat repeats the same people all day)
    if f.race == race and (sex == nil or f.sex == sex) and (class == nil or f.class == class)
        and now - (f.at or 0) < 86400 then return end
    f.race, f.sex, f.class, f.at = race, sex or f.sex, class or f.class, now
    -- Chat brings a lot of names; keep the most recently seen
    if faces.n > FACES_MAX then
        local list = {}
        for k, v in pairs(faces) do if type(v) == "table" then list[#list + 1] = { k, v.at or 0 } end end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        local keep = math.floor(FACES_MAX * 0.8)
        for i = keep + 1, #list do faces[list[i][1]] = nil end
        faces.n = math.min(#list, keep)
    end
end

local function LearnUnit(unit)
    if not (MF and unit and UnitExists(unit) and UnitIsPlayer(unit)) then return end
    pcall(function()
        local _, race = UnitRace(unit)
        local _, class = UnitClass(unit)
        Remember(MF:FullName(UnitFullName(unit)), race, UnitSex(unit), class)
    end)
end

local function GroupUnits()
    local units = { "player", "target", "focus", "mouseover" }
    local prefix, n = IsInRaid() and "raid" or "party", GetNumGroupMembers() or 0
    for i = 1, n do units[#units + 1] = prefix .. i end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            if plate.namePlateUnitToken then units[#units + 1] = plate.namePlateUnitToken end
        end
    end
    return units
end

-- A unit the game can draw them from right now (Forever's UnitName can leave the surname off;
-- UnitFullName doesn't)
local function UnitKey(unit)
    local n, r = UnitFullName(unit)
    n, r = Plain(n), Plain(r)
    if type(n) ~= "string" or n == "" then return nil end
    return MF:AnglerKey(MF:FullName(n, r))
end

local function UnitOf(name)
    local want = MF:AnglerKey(name)
    if want == "" then return nil end
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitIsPlayer(unit) then
            local ok, key = pcall(UnitKey, unit)
            if ok and key == want then return unit end
        end
    end
end

local seenGUID = {}
local learn = CreateFrame("Frame")
-- (registered once the look starts, below: a dormant or stood-down copy listens to nothing)
local LEARN_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE",
    "NAME_PLATE_UNIT_ADDED", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }
learn:SetScript("OnEvent", function(_, event, ...)
    if not MF or ns.standDown then return end
    if event == "PLAYER_ENTERING_WORLD" then LearnUnit("player")
    elseif event == "PLAYER_TARGET_CHANGED" then LearnUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then LearnUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then LearnUnit((...))
    elseif event == "GROUP_ROSTER_UPDATE" then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, (GetNumGroupMembers() or 0) do LearnUnit(prefix .. i) end
    else
        -- Each chatter once a session: trade chat repeats the same people all evening
        local guid = Plain((select(12, ...)))
        if type(guid) ~= "string" or seenGUID[guid] or not GetPlayerInfoByGUID then return end
        seenGUID[guid] = true
        if not guid:find("^Player%-") then return end
        local sender = select(2, ...)
        local ok, _, class, _, race, sex = pcall(GetPlayerInfoByGUID, guid)
        if ok then Remember(sender, race, sex, class) end
    end
end)

local SEX = { [2] = "male", [3] = "female" }
local RACE_ALIAS = { scourge = "undead" }
local function RaceAtlas(race, sex)
    local g = SEX[sex]
    if not (race and g) then return end
    local r = race:lower()
    for _, name in ipairs({ r, RACE_ALIAS[r] or r }) do
        for _, fmt in ipairs({ "raceicon128-%s-%s", "raceicon-%s-%s" }) do
            local atlas = fmt:format(name, g)
            if W:HasAtlas(atlas) then return atlas end
        end
    end
end

local shownFaces -- (below: guildmates telling us theirs)

-- Fill a round podium face: live portrait, else their race, else their class, else an angler
local function SetFace(face, name)
    if shownFaces then shownFaces[face] = name end
    local tex = face.icon
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(1, 1, 1)
    local unit = UnitOf(name)
    if unit and SetPortraitTexture then
        SetPortraitTexture(tex, unit)
        return "live"
    end
    local f = (Faces() or {})[MF:AnglerKey(name)]
    local atlas = f and RaceAtlas(f.race, f.sex)
    if atlas then tex:SetAtlas(atlas) return "race" end
    local coords = f and f.race and SEX[f.sex] and RACE_ICON_TCOORDS and RACE_ICON_TCOORDS[(f.race .. "_" .. SEX[f.sex]):upper()]
    if coords then
        tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races")
        tex:SetTexCoord(unpack(coords))
        return "race"
    end
    coords = f and f.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[f.class]
    if coords then
        tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        tex:SetTexCoord(unpack(coords))
        return "class"
    end
    tex:SetTexture("Interface\\Icons\\Trade_Fishing")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetVertexColor(0.55, 0.55, 0.55)
    return "none"
end
ns.RealmFaces = { SetFace = SetFace, Remember = Remember, UnitOf = UnitOf }

-- ---------------------------------------------------------------------------
-- Guildmates tell each other their race, sex and class (a few bytes) once per login, so the
-- podium can show their race when they're not around. Godfall's UI Rework also asked anglers
-- on the podium by whisper; we don't message strangers, but we still answer anyone who asks us,
-- so the two stay compatible (same prefix). Off with ns.db.shareFace = false.
-- ---------------------------------------------------------------------------
local PREFIX = "TFLUIFace1"
shownFaces = setmetatable({}, { __mode = "k" }) -- face frame -> angler name on it
local answered = {}
local lastSend = 0

local function Sharing() return ns.db and ns.db.shareFace ~= false end

local function Locked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function SendFace(kind, dist, target)
    if not (Sharing() and C_ChatInfo and C_ChatInfo.SendAddonMessage) or Locked() then return false end
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    if type(race) ~= "string" then return false end
    local msg = strjoin("~", kind, race, tostring(UnitSex("player") or 0), class or "")
    lastSend = GetTime()
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, dist, target)
    -- (the client reports a throttle or lockdown as a result code, not an error)
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    return ok and (res == nil or res == true or res == success)
end

local comm = CreateFrame("Frame")
comm:SetScript("OnEvent", function(_, event, prefix, text, dist, sender)
    if ns.standDown then return end
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(text) or issecretvalue(sender)) then return end
    if prefix ~= PREFIX or not MF or not MF.me then return end
    if type(text) ~= "string" or #text > 80 or type(sender) ~= "string" or sender == "" then return end
    sender = MF:FullName(sender)
    if MF:IsMe(sender) then return end
    local kind, race, sex, class = strsplit("~", text)
    sex = tonumber(sex)
    if (kind ~= "F" and kind ~= "Q") or not race or not race:match("^%a+$") or #race > 24 then return end
    if class and not class:match("^%u*$") then class = nil end
    Remember(sender, race, (sex == 2 or sex == 3) and sex or nil, class ~= "" and class or nil)
    -- Answer a question with ours, once a minute per angler at most
    if kind == "Q" and dist == "WHISPER" then
        local key = MF:AnglerKey(sender)
        if GetTime() - (answered[key] or -math.huge) > 60 then
            answered[key] = GetTime()
            C_Timer.After(0.5 + math.random() * 1.5, function() SendFace("F", "WHISPER", MF:WhisperName(sender)) end)
        end
    end
    -- Put it straight on the podium if they're up there
    for face, name in pairs(shownFaces) do
        if face:IsVisible() and MF:SameAngler(name, sender) then SetFace(face, name) end
    end
end)
ns.RealmFaces.comm = comm
-- Learning and answering work from login, not only once the Realm page has been opened.
-- Setups only run when this look is the one in use (not dormant, not standing down for the old add-on).
ns:OnSetup(nil, function(tfl)
    MF = tfl
    for _, e in ipairs(LEARN_EVENTS) do pcall(learn.RegisterEvent, learn, e) end
    LearnUnit("player")
    comm:RegisterEvent("CHAT_MSG_ADDON")
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    -- Once the guild roster and surname have settled
    C_Timer.After(45, function() if IsInGuild() then SendFace("F", "GUILD") end end)
end)

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function PodiumCard()
    local c = W:Card(nil, true)
    c.place = W:Label(c, "GameFontNormalHuge")
    c.place:SetPoint("TOPLEFT", 10, -8)
    c.face = W:RoundIcon(c, 64)
    c.face:SetPoint("TOP", 0, -10)
    c.name = W:Label(c, "GameFontNormal")
    c.name:SetPoint("TOP", c.face, "BOTTOM", 0, -4)
    c.line1 = W:Label(c, "GameFontHighlight")
    c.line1:SetPoint("TOP", c.name, "BOTTOM", 0, -6)
    c.line2 = W:Label(c, "GameFontDisableSmall")
    c.line2:SetPoint("TOP", c.line1, "BOTTOM", 0, -4)
    c:SetScript("OnClick", function(self) if self.open then W:Sound("row") self.open() end end)
    return c
end

local function Podium()
    local fr = CreateFrame("Frame")
    fr.cards = {}
    for i = 1, 3 do fr.cards[i] = PodiumCard() fr.cards[i]:SetParent(fr) end
    return fr
end

local function FillPodium(fr, it)
    local w = (fr:GetWidth() or 600)
    local cw = math.min(220, (w - 24) / 3)
    -- 2nd, 1st, 3rd, the winner a step up
    local order = { 2, 1, 3 }
    for slot, place in ipairs(order) do
        local c = fr.cards[place]
        local e = it.top[place]
        c:SetShown(e ~= nil)
        if e then
            c:ClearAllPoints()
            local x = (w - (cw * 3 + 24)) / 2 + (slot - 1) * (cw + 12)
            local h = place == 1 and it.h - 4 or it.h - 24
            c:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", x, 2)
            c:SetSize(cw, h)
            W:Place(c.place, place)
            local size = place == 1 and 72 or 60
            c.face:SetSize(size, size)
            c.face.icon:SetSize(size * 0.76, size * 0.76)
            c.face.ring:SetSize(size, size)
            SetFace(c.face, e.name)
            c.name:SetText(MF:ShortName(e.name) .. Faction(e.name))
            c.name:SetTextColor(NameColour(e.name))
            c.line1:SetText(e.line1)
            c.line2:SetText(e.line2 or "")
            local m = W.MEDAL[place]
            c:SetEdge(m[1], m[2], m[3], 1)
            c.open = e.open
        end
    end
end

local function RankRow()
    local r = CreateFrame("Button")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)
    r.place = W:Label(r, "GameFontNormal")
    r.place:SetPoint("LEFT", 10, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 48, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = W:Label(r, "GameFontHighlight")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.cols = {}
    for i = 1, 3 do
        local c = W:Label(r, "GameFontHighlight")
        c:SetJustifyH("RIGHT")
        c:SetWordWrap(false)
        c:SetWidth(90)
        r.cols[i] = c
    end
    r.cols[3]:SetPoint("RIGHT", -10, 0)
    r.cols[2]:SetPoint("RIGHT", r.cols[3], "LEFT", 0, 0)
    r.cols[1]:SetPoint("RIGHT", r.cols[2], "LEFT", 0, 0)
    r:SetScript("OnClick", function(self) if self.item and self.item.open then W:Sound("row") self.item.open() end end)
    r:SetScript("OnEnter", function(self)
        local tip = self.item and self.item.tip
        if not tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i, line in ipairs(tip) do
            if i == 1 then GameTooltip:SetText(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) W:HideTip(self) end)
    return r
end

-- Column widths, right to left in the row but listed left to right. A page
-- can give its own (a holder's name wants more room than a count does).
local WIDTHS = { 90, 90, 90 }
local function SetWidths(cols, widths)
    local total = 0
    for i = 1, 3 do
        cols[i]:SetWidth(widths[i])
        cols[i]:SetShown(widths[i] > 0)
        total = total + widths[i]
    end
    return total
end

local function FillRank(r, it)
    if it.place then W:Place(r.place, it.place) else r.place:SetText("") end
    -- No place column: the icon moves up to the edge rather than leave a gap.
    local left = it.place and 48 or 10
    r.icon:ClearAllPoints()
    r.icon:SetPoint("LEFT", left, 0)
    r.icon:SetShown(it.icon ~= nil)
    if it.icon then r.icon:SetTexture(it.icon) end
    local nameX = it.icon and left + 28 or left
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", nameX, 0)
    r.name:SetText(it.name)
    r.name:SetTextColor(it.r or 1, it.g or 1, it.b or 1)
    for i = 1, 3 do r.cols[i]:SetText(it.cols and it.cols[i] or "") end
    local cols = SetWidths(r.cols, it.widths or WIDTHS)
    r.name:SetWidth(math.max(80, (r:GetWidth() or 500) - nameX - cols - 20))
    local mine = it.mine
    r.bg:SetColorTexture(1, 0.62, 0, mine and 0.14 or (it.index % 2 == 0 and 0.035 or 0))
    r:EnableMouse(it.open ~= nil or it.tip ~= nil)
end

local function Make(kind)
    if kind == "podium" then return Podium() end
    if kind == "rank" then return RankRow() end
    if kind == "head" then
        local fr = CreateFrame("Frame")
        fr.text = W:Label(fr, "GameFontNormal")
        fr.text:SetPoint("BOTTOMLEFT", 4, 6)
        fr.cols = {}
        for i = 1, 3 do
            local c = W:Label(fr, "GameFontDisableSmall")
            c:SetJustifyH("RIGHT")
            c:SetWidth(90)
            fr.cols[i] = c
        end
        fr.cols[3]:SetPoint("BOTTOMRIGHT", -10, 7)
        fr.cols[2]:SetPoint("RIGHT", fr.cols[3], "LEFT", 0, 0)
        fr.cols[1]:SetPoint("RIGHT", fr.cols[2], "LEFT", 0, 0)
        fr.rule = W:Divider(fr, 100)
        fr.rule:SetPoint("BOTTOMLEFT", 0, 2)
        fr.rule:SetPoint("BOTTOMRIGHT", 0, 2)
        return fr
    end
    local fr = CreateFrame("Frame")
    fr.text = W:Label(fr, "GameFontDisableSmall")
    fr.text:SetPoint("LEFT", 6, 0)
    fr.text:SetPoint("RIGHT", -6, 0)
    fr.text:SetJustifyH("LEFT")
    return fr
end

local function Fill(fr, it)
    if it.kind == "podium" then FillPodium(fr, it)
    elseif it.kind == "rank" then FillRank(fr, it)
    elseif it.kind == "head" then
        fr.text:SetText(it.text)
        for i = 1, 3 do fr.cols[i]:SetText(it.cols and it.cols[i] or "") end
        SetWidths(fr.cols, it.widths or WIDTHS)
    else
        fr.text:SetText(it.text)
    end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
local BAR_H = 30

-- Your target's name, if it's a player
local function TargetName()
    if not (UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")) then return end
    local name = Plain(UnitName("target"))
    return type(name) == "string" and name ~= "" and name or nil
end

function P:SetQuery(text)
    text = strtrim and strtrim(text or "") or (text or "")
    if text == (self.query or "") then return end
    self.query = text
    -- Our own redraw: The Fishing Log's RedrawJournal only redraws its classic window, which
    -- isn't up under this look, so typing changed nothing
    if not (MF and self.list and J.page and J.page.key == "realm") then return end
    self:Refresh(J:State())
    if J.count then J.count:SetText(self.count or "") end
end

function P:Build(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_H - 6)
    self.search = W:Search(bar, 230, function(text) P:SetQuery(text) end, "Find an angler")
    self.search:SetPoint("LEFT", 6, 0)
    self.target = W:Button(bar, "Target", 80, 22, function()
        local name = TargetName()
        if name then self.search:SetText(name) self.search:ClearFocus() end
    end)
    self.target:SetPoint("LEFT", self.search, "RIGHT", 10, 0)
    self.target:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Find your target", 1, 0.82, 0)
        GameTooltip:AddLine("Target a player you see in the world, then click to look them up.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.target:SetScript("OnLeave", function(b) W:HideTip(b) end)
    local function Targetable() self.target:SetEnabled(TargetName() ~= nil) end
    bar:RegisterEvent("PLAYER_TARGET_CHANGED")
    bar:SetScript("OnEvent", Targetable)
    bar:SetScript("OnShow", Targetable)
    self.bar = bar

    local hero = W:Card(frame, true)
    hero:SetPoint("TOPLEFT", 0, -BAR_H)
    hero:SetPoint("TOPRIGHT", 0, -BAR_H)
    hero:SetHeight(70)
    hero:SetBackdropColor(0.06, 0.08, 0.15, 0.9)
    hero:SetEdge(0.9, 0.72, 0.3, 1)
    hero.icon = W:FramedIcon(hero, 42)
    hero.icon:SetPoint("LEFT", 16, 0)
    hero.kicker = W:Label(hero, "GameFontNormalSmall")
    hero.kicker:SetPoint("TOPLEFT", 74, -12)
    hero.kicker:SetTextColor(0.8, 0.8, 0.8)
    hero.title = W:Label(hero, "GameFontNormalLarge")
    hero.title:SetPoint("TOPLEFT", hero.kicker, "BOTTOMLEFT", 0, -4)
    hero.where = W:Label(hero, "GameFontDisableSmall")
    hero.where:SetPoint("TOPLEFT", hero.title, "BOTTOMLEFT", 0, -3)
    hero.weight = W:Label(hero, "GameFontNormalHuge")
    hero.weight:SetPoint("RIGHT", -18, 4)
    hero.holder = W:Label(hero, "GameFontHighlight")
    hero.holder:SetPoint("TOPRIGHT", hero.weight, "BOTTOMRIGHT", 0, -2)
    hero:SetScript("OnClick", function(self) if self.open then W:Sound("row") self.open() end end)
    self.hero = hero

    self.season = W:Label(frame, "GameFontDisableSmall")
    self.season:SetJustifyH("LEFT")
    self.season:SetWordWrap(true)
    self.season:SetSpacing(2)
    self.list = W:VList(frame, Make, Fill)
    self.list:SetPoint("BOTTOMRIGHT", -16, 0)
end

-- The Fishing Log's rows for each angler, in order, so a click opens its page for them
local function AnglerOpeners(state)
    local out = {}
    for _, line in ipairs(state.lines or {}) do
        if line.onClick and line.columns and not line.header then out[#out + 1] = line.onClick end
    end
    return out
end

function P:Anglers(state, items)
    local season = MF.db.settings.realmSeason
    local list, best = MF:RealmStandings(season)
    local guildOnly = HasAction(state, "Everyone")
    if guildOnly then
        local mine = {}
        best = nil
        for _, a in ipairs(list) do
            if MF:InMyGuild(a.name) then
                mine[#mine + 1] = a
                if a.best and (not best or a.best.w > best.w) then best = { w = a.best.w, id = a.best.id, spot = a.best.spot, h = a.name } end
            end
        end
        list = mine
    end
    self:Hero(best, guildOnly and (season and "YOUR GUILD'S HEAVIEST THIS SEASON" or "HEAVIEST IN YOUR GUILD")
        or (season and "HEAVIEST THIS SEASON" or "HEAVIEST CATCH KNOWN"))

    local openers = AnglerOpeners(state)
    local searching = self:Searching()
    local top = {}
    for i = 1, math.min(3, searching and 0 or #list) do
        local a = list[i]
        top[i] = { name = a.name, open = openers[i],
            line1 = ("%d %s  %s%d"):format(a.records, a.records == 1 and "record" or "records", CROWN, a.kings),
            line2 = a.specimens > 0 and (STAR .. " " .. a.specimens .. " specimen " .. (a.specimens == 1 and "record" or "records")) or nil }
    end
    if #top > 0 then items[#items + 1] = { kind = "podium", h = 178, gap = 10, top = top } end
    -- Searching: no podium, the top three are rows like everyone else, at their real places
    local found = 0
    if #list > 3 or searching then
        local rows = {}
        for i = searching and 1 or 4, #list do
            if self:Matches(MF:ShortName(list[i].name)) then rows[#rows + 1] = i end
        end
        found = #rows
        if #rows > 0 then
            items[#items + 1] = { kind = "head", h = 30, text = searching and "Found" or (guildOnly and "Your guild" or "Everyone else"),
                cols = { "Records", "Kings", "Specimens" } }
        end
        for _, i in ipairs(rows) do
            local a = list[i]
            local r, g, b = NameColour(a.name)
            items[#items + 1] = { kind = "rank", h = 26, index = i, place = i, name = MF:ShortName(a.name) .. Faction(a.name),
                r = r, g = g, b = b, mine = MF:IsMe(a.name), open = openers[i],
                cols = { tostring(a.records), tostring(a.kings), a.specimens > 0 and (STAR .. " " .. a.specimens) or "-" },
                tip = { MF:ShortName(a.name), "Click to see their records." } }
        end
    end
    if #list == 0 then
        local text
        if guildOnly then
            text = IsInGuild() and "Nobody in your guild holds a record yet. Somebody has to be first."
                or "You're not in a guild, so there's nobody to compare yourself with here."
        else
            text = season and "Nothing set this season yet. The board is wide open." or "No records known yet. Fish a few spots and they'll fill in."
        end
        items[#items + 1] = { kind = "note", h = 40, text = text }
    end
    if searching then
        self:SearchFooter(items, found, #list, "angler", "anglers",
            "No angler called %s holds a record you've heard of. They may not have The Fishing Log, may not have caught anything yet, or their records haven't reached you.")
        return
    end

    -- Your past seasons
    local seasons = {}
    for i = #(MF.cdb.history or {}), 1, -1 do
        local hist = MF.cdb.history[i]
        if hist.season then seasons[#seasons + 1] = hist end
    end
    if #seasons > 0 then
        items[#items + 1] = { kind = "head", h = 34, text = "Your past seasons", cols = { "XP", "Records", "Kings" } }
        for i, hist in ipairs(seasons) do
            items[#items + 1] = { kind = "rank", h = 26, index = i, name = MF:SeasonName(hist.season),
                cols = { tostring(hist.xp or 0), tostring(hist.records or 0), tostring(hist.kings or 0) } }
        end
    end

    -- The small print: whose board this is, who else is about
    local spots = MF.Count and MF.Count(MF.db.spots) or 0
    if guildOnly and IsInGuild() then
        local everyone = #(MF:RealmStandings(season))
        items[#items + 1] = { kind = "note", h = 24, text = ("%d of the %d anglers holding records are in your guild."):format(#list, everyone) }
    elseif not guildOnly then
        items[#items + 1] = { kind = "note", h = 24, text = ("Your board, not the realm's: %d %s holding records at %d %s your client has heard of. |cffff9d00You|r and |cff3ee63eyour guild|r are picked out."):format(
            #list, #list == 1 and "angler" or "anglers", spots, spots == 1 and "spot" or "spots") }
        local met = MF.AnglersSeenCount and MF:AnglersSeenCount() or 0
        if met > #list then
            items[#items + 1] = { kind = "note", h = 20, text = ("You've heard from %d anglers in all; the rest hold no records yet. |cffffd100/tfl anglers|r lists them."):format(met) }
        end
        local online = MF.CensusCount and MF:CensusCount() or 0
        if online > 0 then
            items[#items + 1] = { kind = "note", h = 20, text = ("%d other %s online with the addon right now. |cffffd100/tfl sync|r swaps records with them."):format(
                online, online == 1 and "angler is" or "anglers are") }
        end
    end
    self.count = #list == 1 and "1 angler" or (#list .. " anglers")
end

function P:Species(state, items)
    local season = MF.db.settings.realmSeason
    local held, open = MF:SpeciesRecords(season) -- already heaviest first, ties settled
    local mine = 0
    for _, r in ipairs(held) do if MF:IsMe(r.h) then mine = mine + 1 end end
    self.hero:Show()
    local h = self.hero
    h.icon.icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_09")
    h.kicker:SetText(season and "THIS SEASON'S SPECIES RECORDS" or "SPECIES RECORDS")
    h.title:SetText(("%d claimed, %d still open"):format(#held, #open))
    h.where:SetText(mine > 0 and ("|cffff9d00You hold " .. mine .. "|r") or "You hold none yet")
    h.weight:SetText(tostring(mine))
    h.holder:SetText("yours")
    h.open = nil
    -- The holder gets the room: two-word names wrapped in a 90 wide column.
    local widths = { 76, 86, 170 }
    -- A search finds a fish by its name, or every fish one angler holds by theirs
    local found, openFound = {}, {}
    for _, r in ipairs(held) do
        if self:Matches(MF:FishName(r.id), MF:ShortName(r.h)) then found[#found + 1] = r end
    end
    for _, fish in ipairs(open) do
        if self:Matches(MF:FishName(fish.id)) then openFound[#openFound + 1] = fish end
    end
    local total = #held + #open
    held, open = found, openFound
    if #held > 0 then
        items[#items + 1] = { kind = "head", h = 30, text = "Heaviest of each fish", cols = { "Specimen", "Weight", "Holder" },
            widths = widths }
    end
    for i, r in ipairs(held) do
        local cr, cg, cb = NameColour(r.h)
        local holder = MF:ShortName(r.h)
        local hex = ("|cff%02x%02x%02x"):format(cr * 255, cg * 255, cb * 255)
        local spot = r.spot
        items[#items + 1] = { kind = "rank", h = 26, index = i, icon = MF:FishIcon(r.id), name = MF:FishName(r.id),
            mine = MF:IsMe(r.h), widths = widths, cols = { r.s and STAR or "", "|cffffd100" .. MF:Weight(r.w) .. "|r", hex .. holder .. "|r" },
            open = MF:SpotPosition(spot) and function() MF:ShowSpotOnMap(spot) end or nil,
            tip = { MF:FishName(r.id), ("%s by %s"):format(MF:Weight(r.w), holder), "at " .. MF:SpotWhere(spot),
                MF:SpotPosition(spot) and "Click to show the water on your map." or nil } }
    end
    if #open > 0 then
        items[#items + 1] = { kind = "head", h = 34, text = ("Nobody has landed these yet  |cffa0a0a0(%d)|r"):format(#open) }
        for i, fish in ipairs(open) do
            items[#items + 1] = { kind = "rank", h = 24, index = i, icon = MF:FishIcon(fish.id), name = "|cffa0a0a0" .. MF:FishName(fish.id) .. "|r",
                cols = { "", "", "|cff858585unclaimed|r" }, widths = widths }
        end
    end
    if self:Searching() then
        self:SearchFooter(items, #held + #open, total, "species", "species",
            "No fish or record holder matches %s.")
        return
    end
    self.count = total .. " species"
end

local function Age(at)
    if not at then return "update time not recorded" end
    return ("last received %d minutes ago"):format(math.floor(math.max(0, GetServerTime() - at) / 60))
end

function P:XP(state, items)
    local guildOnly = HasAction(state, "Everyone")
    local list = MF:XPStandings(guildOnly)
    self.hero:Show()
    local h = self.hero
    local myXP = MF.cdb.profile.xp or 0
    local myPlace
    for i, a in ipairs(list) do if MF:IsMe(a.name) then myPlace = i end end
    local _, title = MF:RankFor(myXP)
    h.icon.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    h.kicker:SetText(guildOnly and "GUILD XP LEADERBOARD" or "ANGLER XP LEADERBOARD")
    h.title:SetText(title or "")
    h.where:SetText("Lifetime XP from every angler who shares their progress")
    h.weight:SetText(myPlace and ("#" .. myPlace) or "-")
    h.holder:SetText(("%d XP"):format(myXP))
    h.open = nil
    local searching = self:Searching()
    local top = {}
    for i = 1, math.min(3, searching and 0 or #list) do
        local a = list[i]
        top[i] = { name = a.name, line1 = ("%s XP"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(a.xp) or a.xp),
            line2 = (a.title or "") .. (a.fish and ("  |cffa0a0a0%d fish|r"):format(a.fish) or "") }
    end
    if #top > 0 then items[#items + 1] = { kind = "podium", h = 178, gap = 10, top = top } end
    local rows = {}
    for i = searching and 1 or 4, #list do
        if self:Matches(MF:ShortName(list[i].name)) then rows[#rows + 1] = i end
    end
    if #rows > 0 then
        items[#items + 1] = { kind = "head", h = 30, text = searching and "Found" or "Everyone else", cols = { "Title", "XP", "Fish" } }
        for _, i in ipairs(rows) do
            local a = list[i]
            local r, g, b = NameColour(a.name)
            items[#items + 1] = { kind = "rank", h = 26, index = i, place = i, name = MF:ShortName(a.name), r = r, g = g, b = b,
                mine = MF:IsMe(a.name), cols = { "|cffa0a0a0" .. (a.title or "") .. "|r", BreakUpLargeNumbers and BreakUpLargeNumbers(a.xp) or tostring(a.xp),
                    a.fish and tostring(a.fish) or "-" },
                tip = { MF:ShortName(a.name), "XP: " .. Age(a.xpAt), "Fish: " .. (a.fish ~= nil and Age(a.fishAt) or "Not shared by this angler yet"),
                    "Fish counts weighed Journal fish, not casts, clams or junk." } }
        end
    end
    if #list == 0 then items[#items + 1] = { kind = "note", h = 40, text = "No anglers with shared XP match this filter yet." } end
    if searching then
        self:SearchFooter(items, #rows, #list, "angler", "anglers",
            "No angler called %s has shared their XP with you. They may not have The Fishing Log, or haven't been heard from yet.")
        return
    end
    self.count = #list == 1 and "1 angler" or (#list .. " anglers")
end

function P:Hero(best, kicker)
    local h = self.hero
    h:SetShown(best ~= nil)
    if not best then return end
    h.icon.icon:SetTexture(MF:FishIcon(best.id))
    h.kicker:SetText(kicker)
    h.title:SetText(MF:FishName(best.id))
    h.where:SetText("at " .. MF:SpotWhere(best.spot))
    h.weight:SetText(MF:Weight(best.w))
    h.holder:SetText(MF:ShortName(best.h))
    h.holder:SetTextColor(NameColour(best.h))
    local spot = best.spot
    h.open = MF:SpotPosition(spot) and function() MF:PointToSpot(spot) end or nil
end

function P:Refresh(state)
    local items = {}
    self.hero.holder:SetTextColor(1, 1, 1)
    local view = View(state)
    if type(self.search.Instructions) == "table" then
        self.search.Instructions:SetText(view == "species" and "Find a fish or holder" or "Find an angler")
    end
    if view == "anglers" then self:Anglers(state, items)
    elseif view == "species" then self:Species(state, items)
    else self:XP(state, items) end
    local season = MF.db.settings.realmSeason and view ~= "xp"
    self.season:SetShown(season and true or false)
    local top = -BAR_H + (self.hero:IsShown() and -78 or 0)
    if season then
        self.season:ClearAllPoints()
        self.season:SetPoint("TOPLEFT", 4, top - 2)
        self.season:SetPoint("TOPRIGHT", -4, top - 2)
        self.season:SetText(("%s, %s left.  %s"):format(MF:SeasonName(), MF:SeasonLeft(), MF:SeasonNote() or ""))
        top = top - (self.season:GetStringHeight() or 12) - 8
    end
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 0, top)
    self.list:SetPoint("BOTTOMRIGHT", -16, 0)
    self.list:SetItems(items, true)
end

J:AddPage({
    key = "realm",
    match = function(state) return not state.recap and state.tab == "fame" and View(state) ~= nil end,
    build = function(frame, tfl) MF = tfl P:Build(frame) end,
    refresh = function(_, state) P:Refresh(state) end,
    subheading = function(state)
        local v = View(state)
        return v == "species" and "Records by fish" or v == "xp" and "Angler XP" or "Hall of fame"
    end,
    count = function() return P.count or "" end,
})
