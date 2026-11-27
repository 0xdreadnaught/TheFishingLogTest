-- World: which of Forever's worlds this character is in, and keeping each world's shared data apart.
--
-- Forever splits players by region (Americas & Oceania, Europe, Korea, Taiwan) and by rule set
-- (Normal, PvP, Roleplay, Roleplay PvP, Hardcore). Its realm-name calls answer "", but the client
-- does say both: GetCurrentRegion() for the region, and the game rules PvPRuleset, RPRuleset and
-- HardcoreRuleset for the rule set.
--
-- What other anglers told us (records, standings, events, pools, who is about) belongs to the
-- world it was heard in. TheFishingLogDB is one table per game account, so it holds one world at
-- a time: the world of the character that is logged in. Other worlds' data waits under
-- db.worlds[key] and is swapped back in when one of their characters logs in. The rest of the
-- addon never sees more than the current world, and needs no changes.
local _, MF = ...

-- Keys of TheFishingLogDB that belong to one world, migration markers included so a marker always
-- travels with the data it describes.
MF.WORLD_KEYS = {
    "spots", "spotFormat", "spotNames", "spotWhere", "struckSweep", "junkPurge",
    "quarantinedSpotMaps", "quarantinedSpotNames", "quarantinedSpotPositions", "mapDump",
    "anglersSeen", "factions",
    "notices", "cancelledNotices", "hiddenHosts", "champions",
    "bounties", "bountyBoard", "bountySeen",
    "poolAtlas", "poolTidy", "frenzyDiscoveries",
    "skillUps", "skillUpsBaseline", "skillUpsHeard", "skillUpsSplit", "catchSkill", "catchSkillHeard",
    "newZones", "zoneSurvey", "syncReports",
}
-- Everything else is the player's own and the same in every world. Listed so a test can tell
-- when a new key appears that nobody has sorted yet.
MF.ACCOUNT_KEYS = {
    "settings", "world", "worlds", "freshStart", "launchReset", "clearLaunchMacros", "lastSeen", "lastVersion",
    "debug", "welcomed", "invitesOpenDefault", "macroNoticeShown", "castClashTold", "whisperRealm",
    "legacy", "legacyClaimedBy", "fishNames", "catchTrace", "peers",
    "profile", "records", "history", "caughtIn", "gear", -- pre-0.6.4 account-wide log, moved to legacy on load
    "musicVolumeRestore", "softTargetRestore", "sfxVolumeRestore", "soundRestore", "bobberCVarRestore",
}

local REGION_CODE = { "US", "KR", "EU", "TW", "CN" }
local REGION_LABEL = { US = "Americas & Oceania", KR = "Korea", EU = "Europe", TW = "Taiwan", CN = "China" }

local function Try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or (MF.IsSecret and MF:IsSecret(value)) then return nil end
    return value
end

-- What the client says right now, or nil while it can't say.
local function Detect()
    local region = Try(GetCurrentRegion)
    if type(region) ~= "number" or region < 1 then return nil end
    local rules = type(Enum) == "table" and Enum.GameRule
    local GR = C_GameRules
    if type(rules) ~= "table" or type(GR) ~= "table" or type(GR.IsGameRuleActive) ~= "function" then return nil end
    local function Rule(name)
        return rules[name] ~= nil and Try(GR.IsGameRuleActive, rules[name]) == true
    end
    return {
        region = region, code = REGION_CODE[region] or ("R" .. region),
        pvp = Rule("PvPRuleset"), rp = Rule("RPRuleset"),
        hardcore = Rule("HardcoreRuleset") or Try(GR.IsHardcoreActive) == true,
        mode = tonumber(Try(GR.GetCurrentGameModeRecordID)) or 0, -- kept for diagnostics, not part of the key
    }
end

-- "US-PvP", "EU-Normal", "US-RP-PvP", "US-HC". The name saved data is filed under. Not sent.
local function Key(w)
    local rule = (w.rp and w.pvp and "RP-PvP") or (w.rp and "RP") or (w.pvp and "PvP") or "Normal"
    if w.hardcore then rule = rule == "Normal" and "HC" or ("HC-" .. rule) end
    return w.code .. "-" .. rule
end

-- What goes on every message instead of the key: one number, (region - 1) * 8 + rule-set bits
-- (1 PvP, 2 Roleplay, 4 Hardcore), written in base 36. One character for the four regions
-- Forever has: "0" is US-Normal, "1" US-PvP, "g" EU-Normal. "?" when the world isn't known.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local REGION_NUMBER = {}
for number, code in ipairs(REGION_CODE) do REGION_NUMBER[code] = number end
function MF:WorldCode(key)
    local code, rule = tostring(key):match("^([%u%d]+)%-(.+)$")
    local region = code and (REGION_NUMBER[code] or tonumber(code:match("^R(%d+)$")))
    if not region or region < 1 then return "?" end
    local bits, rest = 0, "-" .. rule .. "-"
    for name, bit in pairs({ PvP = 1, RP = 2, HC = 4 }) do
        local found
        rest, found = rest:gsub("%-" .. name .. "%-", "-", 1)
        if found > 0 then bits = bits + bit end
    end
    if rest:gsub("%-Normal%-", "-", 1):find("[^%-]") then return "?" end -- a rule set this build doesn't know
    local n, out = (region - 1) * 8 + bits, ""
    repeat out = DIGITS:sub(n % 36 + 1, n % 36 + 1) .. out n = math.floor(n / 36) until n == 0
    return out
end

local function ValidKey(key)
    return type(key) == "string" and #key <= 24 and key:find("^[%u%d]+%-[%w%-]+$") ~= nil
end

local RULE_LABEL = { Normal = "Normal", PvP = "PvP", RP = "Roleplay", ["RP-PvP"] = "Roleplay PvP", HC = "Hardcore",
    ["HC-PvP"] = "Hardcore PvP", ["HC-RP"] = "Hardcore Roleplay", ["HC-RP-PvP"] = "Hardcore Roleplay PvP" }

-- "Americas & Oceania, PvP" for a key, ours by default.
function MF:WorldLabel(key)
    key = key or self.worldKey
    if not ValidKey(key) then return "an unknown world" end
    local code, rule = key:match("^([%u%d]+)%-(.+)$")
    return (REGION_LABEL[code] or code) .. ", " .. (RULE_LABEL[rule] or rule)
end

-- Makes the top level of TheFishingLogDB hold world `key`, parking whatever world was there.
local function SwapTo(db, key)
    if db.world == key then return false end
    if db.world == nil then db.world = key return false end -- first run: what is here was this account's only world
    db.worlds = type(db.worlds) == "table" and db.worlds or {}
    local parked = {}
    for _, k in ipairs(MF.WORLD_KEYS) do parked[k] = db[k] db[k] = nil end
    db.worlds[db.world] = parked
    local mine = db.worlds[key]
    if type(mine) == "table" then
        for _, k in ipairs(MF.WORLD_KEYS) do db[k] = mine[k] end
    end
    db.worlds[key] = nil
    db.world = key
    return true
end

-- Called from Core as the addon loads, before anything reads saved data.
function MF:EnterWorld()
    local found = Detect()
    local char = TheFishingLogChar
    -- A character never changes world, so what it was last time stands in if the client can't say yet.
    local key = found and Key(found) or (type(char) == "table" and ValidKey(char.world) and char.world) or nil
    self.world, self.worldKey = found, key or "?"
    self.worldCode = key and self:WorldCode(key) or "?"
    if not key then return end
    if type(char) ~= "table" then char = {} TheFishingLogChar = char end
    char.world = key
    if type(TheFishingLogDB) == "table" then self.worldSwapped = SwapTo(TheFishingLogDB, key) end
end

-- The client couldn't say while loading. Ask once more now the character is in the world.
MF:On("PLAYER_ENTERING_WORLD", function(self)
    if self.worldKey ~= "?" then return end
    local found = Detect()
    if not found then return end
    local key = Key(found)
    self.cdb.world = key
    if self.db.world == nil or self.db.world == key then
        self.db.world, self.world, self.worldKey, self.worldCode = key, found, key, self:WorldCode(key)
    elseif not self.worldReloadAsked then
        -- The log on screen is another world's. It can only be changed while loading.
        self.worldReloadAsked = true
        self:Print(("|cffff8040This character is on %s, but the log loaded is for %s.|r Type |cffffd100/reload|r once to switch."):format(
            self:WorldLabel(key), self:WorldLabel(self.db.world)))
    end
end)
