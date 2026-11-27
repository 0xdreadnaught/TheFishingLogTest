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
