-- Storage: keeps your rank, journal and spot records in account macros, plus /tfl export
-- and /tfl import. The text format lives in Profile.lua (EncodeProfile).
--
-- Why macros: early Forever betas wrote saved variables but never loaded
-- them, so progress vanished on relog. Macros live on Blizzard's servers and
-- came back fine. Each macro body is "/tfl data <chunk>"; clicking one is
-- harmless. Blizzard has since fixed saving, so on a fixed client the macros
-- are read once and then left alone (see StandDown below).
local _, MF = ...
-- A dormant copy (Core.lua) leaves the running copy's dialogs alone.
local POPUPS = MF.inert and {} or StaticPopupDialogs

local MACRO_NAME = "TFL Save "
local MAX_MACROS = 4
local CHUNK = 230              -- data characters per macro (bodies max out at 255)
local MACRO_ICON = 134400      -- question mark
local SAVE_DELAY = 20          -- seconds after a change before rewriting macros
local LOAD_DELAY = 3           -- seconds after login; macros load a little late
local ACCOUNT_MACRO_LIMIT = MAX_ACCOUNT_MACROS or 120

-- A data-only codec: never load or execute imported text. Length-prefixed
-- strings retain names, item links and whitespace exactly; hex keeps the
-- result copyable through the same single-line interface as legacy saves.
local function EncodeData(value, depth)
    depth = depth or 0
    assert(depth <= 32, "backup nesting is too deep")
    local kind = type(value)
    if kind == "number" then
        assert(value == value and math.abs(value) < math.huge, "invalid backup number")
        return "n" .. ("%.17g"):format(value) .. ";"
    elseif kind == "string" then return "s" .. #value .. ":" .. value
    elseif kind == "boolean" then return value and "b1" or "b0"
    elseif kind == "table" then
        local keys, out = {}, {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
        out[1] = "t" .. #keys .. ":"
        for _, key in ipairs(keys) do
            out[#out + 1] = EncodeData(key, depth + 1)
            out[#out + 1] = EncodeData(value[key], depth + 1)
        end
        return table.concat(out)
    end
    error("unsupported backup value")
end

local function DecodeFull(str)
    if type(str) ~= "string" or #str > 8 * 1024 * 1024 then return end
    local checksum, hex = str:match("^[Tt][Ff][Ll]2:([%w]+):([%x]+)$")
    if not hex or #hex % 2 ~= 0 then return end
    local raw = hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end)
    if MF:Unpack36(checksum) ~= MF:Hash(raw) then return end
    local pos, nodes = 1, 0
    local function Read(depth)
        nodes = nodes + 1
        assert(depth <= 32 and nodes <= 200000, "backup is too complex")
        local tag = raw:sub(pos, pos)
        pos = pos + 1
        if tag == "b" then
            local bit = raw:sub(pos, pos)
            assert(bit == "0" or bit == "1", "bad boolean")
            pos = pos + 1
            return bit == "1"
        end
        local delimiter = tag == "n" and ";" or ":"
        local stop = assert(raw:find(delimiter, pos, true), "truncated backup")
        local token = raw:sub(pos, stop - 1)
        local n = assert(tonumber(token), "bad number")
        assert(n == n and math.abs(n) < math.huge, "bad number")
        pos = stop + 1
        if tag == "n" then return n end
        assert(token:match("^%d+$") and n <= #raw, "bad length")
        if tag == "s" then
            assert(pos + n - 1 <= #raw, "truncated string")
            local value = raw:sub(pos, pos + n - 1)
            pos = pos + n
            return value
        end
        assert(tag == "t", "unknown backup tag")
        local value = {}
        for _ = 1, n do
            local key = Read(depth + 1)
            assert(type(key) == "string" or type(key) == "number", "bad key")
            assert(value[key] == nil, "duplicate key")
            value[key] = Read(depth + 1)
        end
        return value
    end
    local ok, result = pcall(Read, 0)
    if not ok or pos ~= #raw + 1 or type(result) ~= "table" then return end
    local c = result.character
    if type(c) ~= "table" or type(c.profile) ~= "table"
        or type(c.profile.xp) ~= "number" or c.profile.xp < 0
        or type(c.profile.updated) ~= "number" or type(c.profile.journal) ~= "table"
        or type(result.records) ~= "table" or type(result.owner) ~= "string" then return end
    for _, key in ipairs({ "records", "history", "caughtIn", "gear" }) do
        if type(c[key]) ~= "table" then return end
    end
    if c.bounties ~= nil and type(c.bounties) ~= "table" then return end
    for id, entry in pairs(c.profile.journal) do
        if type(id) ~= "number" or type(entry) ~= "table" then return end
        for _, key in ipairs({ "c", "b", "s" }) do
            if type(entry[key]) ~= "number" or entry[key] < 0 then return end
        end
    end
    for _, record in ipairs(result.records) do
        if type(record) ~= "table" or type(record.key) ~= "string"
            or type(record.id) ~= "number" or type(record.w) ~= "number"
            or type(record.t) ~= "number" then return end
    end
    return result
end

function MF:ExportString(compact)
    if compact then return self:EncodeProfile(self.cdb.profile) end
    local raw = EncodeData({ owner = self.me, character = self.cdb, records = self:MyRecords() })
    return "TFL2:" .. self:Pack36(self:Hash(raw)) .. ":"
        .. raw:gsub(".", function(char) return ("%02x"):format(char:byte()) end)
end

function MF:RestoreFullBackup(str)
    local backup = DecodeFull(str)
    if not backup then return false end
    if GetServerTime()>=self.FRESH_START and backup.character.launchReset~=self.FRESH_START then
        self:Print("Pre-launch backups cannot be imported into the fresh realm.") return false
    end
    self:KeepUndo("full backup import")
    local undo = self.cdb.undo
    for key in pairs(self.cdb) do self.cdb[key] = nil end
    for key, value in pairs(backup.character) do self.cdb[key] = value end
    self.cdb.undo = undo
    for _, record in ipairs(backup.records) do
        self:MergeRecord(record.key, record.mapID, record.id, record.w, self.me, record.t, record.s)
    end
    self:MarkProfileChanged()
    self:RefreshJournal()
    self:UpdateBoard()
    self:Print("Restored the complete character backup. /tfl restore undoes this import.")
    return true
end

POPUPS["THEFISHINGLOG_FULL_IMPORT"] = {
    text = "Replace this character's fishing log with the full backup from %s?\n\n"
        .. "This restores journal, personal bests, sessions, gear and bounty progress. "
        .. "Your current log is kept for /tfl restore.",
    button1 = "Restore backup", button2 = CANCEL, timeout = 0,
    whileDead = true, hideOnEscape = true,
    OnAccept = function(_, str) MF:RestoreFullBackup(str) end,
}

function MF:ImportString(str, source)
    if type(str) == "string" and str:sub(1, 5):lower() == "tfl2:" then
        local backup = DecodeFull(str)
        if not backup then self:Print("That full backup is invalid or incomplete.") return false end
        if GetServerTime()>=self.FRESH_START and backup.character.launchReset~=self.FRESH_START then
            self:Print("Pre-launch backups cannot be imported into the fresh realm.") return false
        end
        StaticPopup_Show("THEFISHINGLOG_FULL_IMPORT", self:ShortName(backup.owner), nil, str)
        return true
    end
    local xp, journal, updated, records, champUntil, value, season, seasonXP, rewardThrough = self:DecodeProfile(str)
    if not xp then
        self:Print("That doesn't look like a Fishing Log save string.")
        return false
    end
    if GetServerTime()>=self.FRESH_START and ((updated or 0)<self.FRESH_START or not self:IsLiveProfileSave(str)) then
        self:Print("Pre-launch saves cannot be imported into the fresh realm.") return false
    end
    self:MergeProfile(xp, journal, updated, records, champUntil, value, season, seasonXP, rewardThrough)
    self:Print(("Restored progress from %s: %d XP, %d journal entries (merged with what you had)."):format(
        source or "import", xp, self.Count(journal)))
    return true
end

------------------------------------------------------------------------
-- Macro storage
------------------------------------------------------------------------

local function MacroIndex(i)
    return GetMacroIndexByName(MACRO_NAME .. i) or 0
end

local function ReadMacroData()
    local parts = {}
    for i = 1, MAX_MACROS do
        local idx = MacroIndex(i)
        if idx == 0 then break end
        parts[#parts + 1] = (GetMacroBody(idx) or ""):match("/tfl data%s+(%S+)") or ""
    end
    return table.concat(parts)
end

function MF:LoadFromMacros()
    local data = ReadMacroData()
    if data ~= "" then
        local _,_,updated=self:DecodeProfile(data)
        if GetServerTime()>=self.FRESH_START and ((updated or 0)<self.FRESH_START or not self:IsLiveProfileSave(data)) then
            self:Print("Pre-launch save macros cannot restore progress on the fresh realm.")
        else self:ImportString(data, "your saved macros") end
    end
    self.macrosLoaded = true
    self.macroDirty = false
end

-- Creates, updates or deletes macros so they hold exactly these chunks.
-- Returns false if we ran out of macro slots.
local function WriteMacros(self, chunks)
    local created = false
    local needed = 0
    for i = 1, MAX_MACROS do
        if chunks[i] and MacroIndex(i) == 0 then needed = needed + 1 end
    end
    if needed > ACCOUNT_MACRO_LIMIT - GetNumMacros() then
        self:Print("Your account macros are full, so progress can't be saved. "
            .. "Free a slot or use /tfl export.")
        return false, false
    end
    for i = 1, MAX_MACROS do
        local idx = MacroIndex(i)
        if chunks[i] then
            local body = "/tfl data " .. chunks[i]
            if idx > 0 then
                if GetMacroBody(idx) ~= body then
                    EditMacro(idx, MACRO_NAME .. i, MACRO_ICON, body)
                end
            elseif GetNumMacros() >= ACCOUNT_MACRO_LIMIT then
                self:Print("Your account macros are full, so progress can't be saved. "
                    .. "Free a slot or use /tfl export.")
                return false, created
            else
                CreateMacro(MACRO_NAME .. i, MACRO_ICON, body, false)
                created = true
            end
        elseif idx > 0 then
            DeleteMacro(idx)
        end
    end
    return true, created
end

function MF:SaveToMacros()
    if not self.db.settings.macroSave or not self.macrosLoaded then return end
    if InCombatLockdown() then return end -- try again next tick
    if GetTime() < (self.macroRetryAt or 0) then return end

    -- The macros are a copy of the character's saved data, written on
    -- request (/tfl macros on). They are never read back on their own.
    self.macroDirty = true

    -- Rank and journal come first; if space is tight, save fewer records.
    local data
    local limit = self.MAX_SAVED_RECORDS
    repeat
        data = self:EncodeProfile(self.cdb.profile, limit)
        limit = limit - 5
    until #data <= MAX_MACROS * CHUNK or limit < 0
    if #data > MAX_MACROS * CHUNK then
        self.macroRetryAt = GetTime() + 60
        self:Print("Your journal is too big to fit in the save macros. Use /tfl export as a backup.")
        return
    end
    local chunks = {}
    for i = 1, math.ceil(#data / CHUNK) do
        chunks[i] = data:sub((i - 1) * CHUNK + 1, i * CHUNK)
    end

    local ok, success, created = pcall(WriteMacros, self, chunks)
    success = ok and success and ReadMacroData() == data
    self.macroDirty = not success
    if success then self.macroRetryAt = nil else self.macroRetryAt = GetTime() + 60 end
    if created and not self.db.macroNoticeShown then
        self.db.macroNoticeShown = true
        self:Print("Your progress is now saved in account macros named |cffffd100TFL Save|r. "
            .. "Please don't delete them - they're how your rank and journal survive a relog.")
    end
end

function MF:DeleteSaveMacros()
    if InCombatLockdown() then return end
    for i = MAX_MACROS, 1, -1 do
        local idx = MacroIndex(i)
        if idx > 0 then DeleteMacro(idx) end
    end
end

function MF:ClearLaunchMacros()
    if not self.db.clearLaunchMacros or InCombatLockdown() then return end
    self:DeleteSaveMacros()
    for i=1,MAX_MACROS do if MacroIndex(i)>0 then return end end
    self.db.clearLaunchMacros=nil
end
MF:On("PLAYER_REGEN_ENABLED",function(self) self:ClearLaunchMacros() end)

-- Blizzard fixed addon saving, so the macros aren't needed any more: we stop
-- writing them and say they can be cleared out.
local function StandDown(self)
    self.macrosLoaded=true
    if not self.db.settings.macroSave then return end
    self.db.settings.macroSave = false
    if MacroIndex(1) > 0 then
        self:Print("Your progress saves normally now, so the |cffffd100TFL Save|r macros aren't "
            .. "needed. |cffffd100/tfl macros clear|r deletes them, and |cffffd100/tfl macros load|r "
            .. "puts an old backup on this character if you ever want it.")
    end
end

MF:On("TFL_LOGIN", function(self)
    C_Timer.After(LOAD_DELAY, function()
        -- The macros belong to the account, and a log now belongs to one
        -- character. Reading them on every login handed an old account-wide
        -- snapshot to every alt who logged in, so they are never read on
        -- their own: /tfl macros load is there for anyone who wants an old
        -- backup on purpose.
        StandDown(self)
    end)
end)

MF:Command("macros", "Other", nil, function(self, args)
    local what = args[1]
    if what == "clear" then
        self:DeleteSaveMacros()
        self:Print("Save macros deleted.")
    elseif what == "load" then
        -- Asked for, never assumed: the macros are account-wide and this
        -- merges them into whichever character you're playing.
        self:LoadFromMacros(true)
    elseif what == "on" then
        self.db.settings.macroSave = true
        self.macroDirty = true
        self:Print("Saving progress to macros again.")
    elseif what == "off" then
        self.db.settings.macroSave = false
        self:Print("Stopped saving progress to macros.")
    else
        self:Print(("Save macros are %s. Use /tfl macros on, off or clear."):format(
            self.db.settings.macroSave and "on" or "off"))
    end
end)

MF:On("PLAYER_LOGOUT", function(self)
    pcall(self.SaveToMacros, self)
end)

MF:OnTick(function(self)
    if self.macroDirty and GetTime() - (self.lastMacroSave or 0) >= SAVE_DELAY then
        self.lastMacroSave = GetTime()
        self:SaveToMacros()
    end
end)

------------------------------------------------------------------------
-- Export / import window (a plain edit box you can copy from / paste into)
------------------------------------------------------------------------

local box

local function CreateBox()
    box = MF:CreatePanel("TheFishingLogExport", 460, 130, { strata = "DIALOG", escCloses = true })
    box:SetPoint("CENTER", 0, 120)

    box.title = MF:CreateText(box, "GameFontNormal", "TOP", 0, -16)

    box.edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    box.edit:SetSize(400, 24)
    box.edit:SetPoint("TOP", 0, -44)
    box.edit:SetAutoFocus(true)
    box.edit:SetMaxLetters(0)
    box.edit:SetScript("OnEscapePressed", function() box:Hide() end)

    box.ok = MF:CreateButton(box, "", 100)
    box.ok:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -4, 16)
    box.close = MF:CreateButton(box, CLOSE or "Close", 100, function() box:Hide() end)
    box.close:SetPoint("BOTTOMLEFT", box, "BOTTOM", 4, 16)
end

local function OpenBox(title, text, onOK, okLabel)
    if not box then CreateBox() end
    box.title:SetText(title)
    box.edit:SetText(text)
    box.ok:SetShown(onOK ~= nil)
    if onOK then
        box.ok:SetText(okLabel)
        box.ok:SetScript("OnClick", onOK)
    end
    box:Show()
    box.edit:SetFocus()
    box.edit:HighlightText()
end

function MF:ShowExport(compact)
    OpenBox(compact and "Compact progress backup - press Ctrl+C to copy"
        or "Full character backup - press Ctrl+C to copy", self:ExportString(compact))
end

function MF:ShowDiagnosticText(text)
    OpenBox("Fishing diagnostics - press Ctrl+C to copy", text)
end

local copyPanel
function MF:ShowCopyText(title,text)
    if not copyPanel then
        copyPanel=self:CreatePanel("TheFishingLogCopyReport",560,470,
            {title="Fishing report",close=true,movable=true,escCloses=true,strata="DIALOG"})
        copyPanel:SetPoint("CENTER")
        copyPanel.help=self:CreateText(copyPanel,"GameFontHighlightSmall","TOPLEFT",24,-45)
        copyPanel.help:SetWidth(508) copyPanel.help:SetJustifyH("LEFT")
        local scroll=CreateFrame("ScrollFrame",nil,copyPanel,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",24,-82) scroll:SetPoint("BOTTOMRIGHT",-44,66)
        local edit=CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true) edit:SetAutoFocus(false) edit:SetMaxLetters(0)
        edit:SetFontObject("ChatFontNormal") edit:SetWidth(482) edit:SetHeight(300)
        edit:SetScript("OnEscapePressed",function() edit:ClearFocus() copyPanel:Hide() end)
        scroll:SetScrollChild(edit)
        copyPanel.edit,copyPanel.scroll=edit,scroll
        local select=self:CreateButton(copyPanel,"Select text",140,function() edit:SetFocus() edit:HighlightText() end)
        select:SetPoint("BOTTOMLEFT",24,24)
        local close=self:CreateButton(copyPanel,"Close",100,function() edit:ClearFocus() copyPanel:Hide() end)
        close:SetPoint("BOTTOMRIGHT",-24,24)
        copyPanel:SetScript("OnHide",function() edit:ClearFocus() end)
    end
    copyPanel.title:SetText(title)
    copyPanel.help:SetText("Preview your report. Select text, then press Ctrl+C to copy.\nPaste it into Discord or wherever you like; nothing is sent automatically.")
    local lines=0
    for line in (text .. "\n"):gmatch("(.-)\n") do lines=lines+math.max(1,math.ceil(#line/65)) end
    copyPanel.edit:SetHeight(math.max(300,lines*18))
    copyPanel.edit:SetText(text)
    local height,width=UIParent:GetHeight(),UIParent:GetWidth()
    if height and width and height>100 and width>100 then copyPanel:SetScale(math.min(1,(height-40)/470,(width-40)/560)) end
    copyPanel:Show() copyPanel.scroll:SetVerticalScroll(0)
    copyPanel.edit:SetFocus() copyPanel.edit:HighlightText()
end

function MF:ShowImport(str)
    if str and str ~= "" then
        self:ImportString(str)
        return
    end
    OpenBox("Paste a Fishing Log save string (Ctrl+V)", "", function()
        if MF:ImportString(box.edit:GetText()) then box:Hide() end
    end, "Import")
end

MF:Command("export", "Progress", "/tfl export [compact] - copy a full character backup",
    function(self, args) self:ShowExport(args[1] == "compact") end)
MF:Command("import", "Progress", "/tfl import [string] - restore one",
    function(self, args) self:ShowImport(args[1]) end)
MF:Command("data", "Other", nil, function(self)
    self:Print("This macro stores your Fishing Log progress. Please don't delete it.")
end)

------------------------------------------------------------------------
-- Starting a character over
--
-- For a character carrying a log that was never theirs - an old account-wide
-- backup, or a claim made by the wrong alt. It empties this character's log
-- and nothing else: the realm's records and your settings are untouched.
------------------------------------------------------------------------

POPUPS["THEFISHINGLOG_RESET"] = {
    text = "Empty %s's fishing log?\n\nRank, journal, personal bests and sessions "
        .. "go for good. The realm's records and your settings stay.",
    button1 = "Empty it",
    button2 = CANCEL,
    OnAccept = function() MF:ResetCharacterLog() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

function MF:ResetCharacterLog()
    local cdb = self.cdb
    self:KeepUndo("/tfl reset")
    cdb.profile = { xp = 0, updated = time(), journal = {} }
    cdb.records, cdb.history, cdb.caughtIn = {}, {}, {}
    cdb.fishingGoal, cdb.fishingGoals, cdb.goalsDone = nil, nil, nil
    cdb.declinedLegacy = true -- don't re-offer the old account log
    self:Print("This character's log is empty. Tight lines. "
        .. "|cff858585(|cffffd100/tfl restore|r|cff858585 undoes this.)|r")
    self:RefreshJournal()
    self:UpdateBoard()
end

MF:Command("reset", "Other", "/tfl reset - empty this character's log and start over",
    function(self)
        StaticPopup_Show("THEFISHINGLOG_RESET", self:ShortName(self.me))
    end)
