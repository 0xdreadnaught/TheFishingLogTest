-- Test build notice. This file exists only in the test build. Once per login it tells
-- the player that this is not the main addon, and why the realm looks empty.
local _, MF = ...

local function Notice(self)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local build = get and get(MF.ADDON, "X-Build")
    self:Print(("|cffff8040TEST BUILD%s - not the main addon.|r It only sees anglers who run the test "
        .. "build and keeps its own saved data. The main addon is The Fishing Log on CurseForge.")
        :format(build and build ~= "" and (" " .. build) or ""))
end
MF.TestBuildNotice = Notice

MF:On("TFL_LOGIN", function(self)
    if C_Timer and C_Timer.After then C_Timer.After(8, function() Notice(self) end) else Notice(self) end
end)

-- Which world is this character in? Forever splits players by region and by rule set, and
-- its realm-name calls answer "". This lists everything the client will say about it, so the
-- right call can be picked from evidence. Read-only; shown by /tfl clientdiag.
function MF:WorldProbeLines()
    local out = {}
    local function Show(v)
        if self.IsSecret and self:IsSecret(v) then return "restricted" end
        if type(v) == "string" then return '"' .. v .. '"' end
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(x)
                if #parts >= 12 then parts[#parts + 1] = "..." break end
            end
            table.sort(parts)
            return "{" .. table.concat(parts, " ") .. "}"
        end
        return tostring(v)
    end
    local function List(...)
        local n, parts = select("#", ...), {}
        for i = 1, n do parts[i] = Show((select(i, ...))) end
        return n > 0 and table.concat(parts, ", ") or "nothing"
    end
    local function Answer(ok, ...)
        if not ok then return "ERROR" end
        return List(...)
    end
    local function Call(fn, ...)
        if type(fn) == "string" then fn = _G[fn] end
        if type(fn) ~= "function" then return "absent" end
        return Answer(pcall(fn, ...))
    end
    local function Line(label, text) out[#out + 1] = "World " .. label .. ": " .. text end

    Line("region", Call("GetCurrentRegion") .. " | name " .. Call("GetCurrentRegionName"))
    Line("realm name", Call("GetRealmName") .. " | normalized " .. Call("GetNormalizedRealmName")
        .. " | id " .. Call("GetRealmID") .. " | kept " .. Show(self.cdb and self.cdb.realm))
    Line("player realm slot", Call(function() return (select(2, UnitFullName("player"))) end))
    Line("guid realm", Call(function() return (tostring(UnitGUID("player")):match("^%a+%-(%d+)%-")) end))
    Line("connected realms", Call("GetAutoCompleteRealms"))
    Line("cvars", "portal " .. Call("GetCVar", "portal") .. " | realmName " .. Call("GetCVar", "realmName")
        .. " | agentUID " .. Call("GetCVar", "agentUID") .. " | locale " .. Call("GetLocale"))
    Line("zone pvp", Call("GetZonePVPInfo") .. " | flagged " .. Call("UnitIsPVP", "player")
        .. " | desired " .. Call("GetPVPDesired"))

    local function Members(name)
        local t = _G[name]
        if type(t) ~= "table" then return "absent" end
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        return #keys > 0 and table.concat(keys, " ") or "empty"
    end
    Line("C_GameRules", Members("C_GameRules"))
    local rules = type(Enum) == "table" and Enum.GameRule
    if type(rules) == "table" and type(C_GameRules) == "table" and type(C_GameRules.IsGameRuleActive) == "function" then
        local active, count = {}, 0
        for name, id in pairs(rules) do
            count = count + 1
            local ok, on = pcall(C_GameRules.IsGameRuleActive, id)
            if ok and on then active[#active + 1] = tostring(name) end
        end
        table.sort(active)
        Line("active game rules", ("%d of %d: %s"):format(#active, count, #active > 0 and table.concat(active, " ") or "none"))
    else
        Line("active game rules", "no Enum.GameRule or no IsGameRuleActive")
    end
    for _, name in ipairs({ "IsHardcoreActive", "GetActiveGameMode", "GetCurrentGameMode", "IsStandard" }) do
        if type(C_GameRules) == "table" and C_GameRules[name] then Line("C_GameRules." .. name, Call(C_GameRules[name])) end
    end
    Line("C_Seasons", Members("C_Seasons"))
    if type(C_Seasons) == "table" then
        Line("season", "has " .. Call(C_Seasons.HasActiveSeason) .. " | active " .. Call(C_Seasons.GetActiveSeason))
    end

    -- Anything else the client names after these ideas: globals, C_ namespaces, enums.
    local words = { "realm", "region", "gamerule", "ruleset", "gamemode", "hardcore", "roleplay", "season" }
    local function Matches(key)
        if type(key) ~= "string" then return false end
        local lower = key:lower()
        for _, w in ipairs(words) do if lower:find(w, 1, true) then return true end end
        return false
    end
    local function Scan(label, t, limit)
        if type(t) ~= "table" then Line(label, "absent") return end
        local found = {}
        for k, v in pairs(t) do
            if Matches(k) and (type(v) == "function" or type(v) == "table") then
                found[#found + 1] = k .. (type(v) == "table" and "{}" or "")
            end
        end
        table.sort(found)
        local total = #found
        for i = #found, limit + 1, -1 do found[i] = nil end
        Line(label, ("%d: %s%s"):format(total, table.concat(found, " "), total > limit and " ..." or ""))
    end
    Scan("globals", _G, 90)
    Scan("enums", type(Enum) == "table" and Enum or nil, 40)
    for name, t in pairs(_G) do
        if type(name) == "string" and name:find("^C_") and type(t) == "table" and not Matches(name) then
            local found = {}
            for k in pairs(t) do if Matches(k) then found[#found + 1] = tostring(k) end end
            if #found > 0 then table.sort(found) Line(name, table.concat(found, " ")) end
        end
    end
    return out
end
