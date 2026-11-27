-- Compat: staying out of other fishing addons' way, and letting them stay
-- out of ours.
--
-- FishFry and The Fishing Log do several of the same jobs: casting on a
-- double right-click, lifting the sound so you hear the bite, floating the
-- catch up the screen, and borrowing the soft-target settings to reach a
-- bobber. Run both and you get two of everything - two floaters, two volume
-- changes, and a right mouse button they are both trying to bind. Until now
-- the best we could do was notice and warn.
--
-- FishFry's author wrote a contract for this and sent it over. This is the
-- other half: we use theirs, and we publish the same shape so they, or
-- anyone else, can do the same to us.
--
-- Three rules, all of them theirs and all worth keeping:
--
-- Suppression is runtime only. It never writes anybody's saved settings,
-- and releasing never turns a feature on - it hands control back to
-- whatever the player had chosen.
--
-- Claims stack by owner. Two addons suppressing the same thing both have to
-- let go before it comes back.
--
-- And ours: we only ever suppress a feature we are actually performing. Turn
-- our floaters off and theirs return, on their own, immediately. That makes
-- the switches the player already has the arbiter, and means there is no
-- third set of options to learn about which addon wins.
local _, MF = ...

local OWNER = "TheFishingLog"

local Compat = {}
MF.Compat = Compat -- MF is _G.TheFishingLog, so this is TheFishingLog.Compat

Compat.API_VERSION = 1

-- Deliberately the same identifiers FishFry uses. Two addons describing the
-- same behaviour under two different names would make every integration
-- after this one a translation exercise.
Compat.Features = {
    DOUBLE_RIGHT_CLICK   = "casting.doubleRightClick",
    ONE_BUTTON_FISHING   = "fishing.oneButton",
    SOFT_INTERACT_ASSIST = "fishing.softInteractAssist",
    FISHING_SOUND_HELPER = "sound.fishingHelper",
    CATCH_FLOATERS       = "feedback.catchFloaters",
}

local FEATURES = {
    ["casting.doubleRightClick"] = {
        label = "Cast on a double right-click",
        suppressible = true,
        configured = function()
            return MF:CastBinding() == "BUTTON2" and MF:CastDouble() == true
        end,
    },
    -- Our cast key on anything but the double right-click: one key that
    -- casts, then reaches for the bobber.
    ["fishing.oneButton"] = {
        label = "Cast and reel on one key",
        suppressible = true,
        configured = function()
            local key = MF:CastBinding()
            return key ~= nil and key ~= "BUTTON2"
        end,
    },
    ["fishing.softInteractAssist"] = {
        label = "Soft interact assist, for reaching the bobber",
        suppressible = true,
        configured = function() return MF:CastBinding() ~= nil end,
    },
    ["sound.fishingHelper"] = {
        label = "Turn the sound up while the line is out",
        suppressible = true,
        configured = function() return MF.db.settings.loudSplash == true end,
    },
    ["feedback.catchFloaters"] = {
        label = "Each catch on screen as you land it",
        suppressible = true,
        configured = function() return MF.db.settings.floatCatches == true end,
    },
}

-- A fixed order, so the state signature below reads the same every tick.
local ORDER = {
    "casting.doubleRightClick",
    "feedback.catchFloaters",
    "fishing.oneButton",
    "fishing.softInteractAssist",
    "sound.fishingHelper",
}

local suppressors = {}

local function CleanOwner(owner)
    owner = tostring(owner or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return owner ~= "" and owner or nil
end

-- Something another addon has just taken over, or handed back. Our own
-- code reads the feature at the moment it would act, so there is only a
-- little to do here - but the cast binding is held by the game rather than
-- checked each time, so it has to be put up or taken down now.
local function Apply(feature)
    if feature == "casting.doubleRightClick" or feature == "fishing.oneButton"
        or feature == "fishing.softInteractAssist" then
        if MF.ApplyCastBinding then MF:ApplyCastBinding() end
    elseif feature == "sound.fishingHelper" then
        if MF.RestoreSplashVolume then MF:RestoreSplashVolume() end
    end
end

------------------------------------------------------------------------
-- What we publish
------------------------------------------------------------------------

function Compat:GetAPIVersion() return Compat.API_VERSION end

function Compat:IsFeatureSupported(feature)
    return FEATURES[tostring(feature or "")] ~= nil
end

function Compat:IsFeatureSuppressed(feature)
    local bucket = suppressors[tostring(feature or "")]
    return type(bucket) == "table" and next(bucket) ~= nil
end

function Compat:IsFeatureConfigured(feature)
    local def = FEATURES[tostring(feature or "")]
    if not def then return nil end
    local ok, on = pcall(def.configured)
    if not ok then return nil end
    return on == true
end

function Compat:IsFeatureEffective(feature)
    if not FEATURES[tostring(feature or "")] then return nil end
    if self:IsFeatureSuppressed(feature) then return false end
    return self:IsFeatureConfigured(feature) == true
end

function Compat:GetFeatureState(feature)
    feature = tostring(feature or "")
    local def = FEATURES[feature]
    if not def then
        return { feature = feature, supported = false, apiVersion = Compat.API_VERSION }
    end
    local count = 0
    for _ in pairs(suppressors[feature] or {}) do count = count + 1 end
    return {
        feature = feature,
        label = def.label,
        supported = true,
        suppressible = def.suppressible == true,
        configured = self:IsFeatureConfigured(feature) == true,
        effective = self:IsFeatureEffective(feature) == true,
        suppressed = count > 0,
        suppressorCount = count,
        apiVersion = Compat.API_VERSION,
    }
end

function Compat:GetSupportedFeatures()
    local out = {}
    for feature, def in pairs(FEATURES) do
        out[feature] = { label = def.label, suppressible = def.suppressible == true }
    end
    return out
end

function Compat:Suppress(owner, feature)
    owner, feature = CleanOwner(owner), tostring(feature or "")
    local def = FEATURES[feature]
    if not owner then return false, "owner is required" end
    if not def then return false, "unsupported feature" end
    if def.suppressible ~= true then return false, "feature is not suppressible" end

    local bucket = suppressors[feature]
    if type(bucket) ~= "table" then
        bucket = {}
        suppressors[feature] = bucket
    end
    if bucket[owner] then return true end
    bucket[owner] = true
    Apply(feature)
    return true
end

function Compat:Release(owner, feature)
    owner, feature = CleanOwner(owner), tostring(feature or "")
    if not owner then return false, "owner is required" end
    if not FEATURES[feature] then return false, "unsupported feature" end

    local bucket = suppressors[feature]
    if type(bucket) ~= "table" or not bucket[owner] then return true end
    bucket[owner] = nil
    if next(bucket) == nil then suppressors[feature] = nil end
    Apply(feature)
    return true
end

function Compat:SetSuppressed(owner, feature, suppressed)
    if suppressed then return self:Suppress(owner, feature) end
    return self:Release(owner, feature)
end

function Compat:ReleaseAll(owner)
    owner = CleanOwner(owner)
    if not owner then return false, "owner is required" end
    local changed = {}
    for feature, bucket in pairs(suppressors) do
        if type(bucket) == "table" and bucket[owner] then changed[#changed + 1] = feature end
    end
    for _, feature in ipairs(changed) do
        self:Release(owner, feature)
    end
    return true
end

-- Asked at the moment a feature would actually do something. Whatever the
-- player switched off is already off; this is only ever about somebody else
-- having asked us to stand down.
function MF:Yielded(feature)
    return Compat:IsFeatureSuppressed(feature)
end

------------------------------------------------------------------------
-- What we use
------------------------------------------------------------------------

function MF:FishFryCompat()
    local ff = _G.FishFry
    local api = ff and ff.Compat
    if type(api) ~= "table" or type(api.GetAPIVersion) ~= "function" then return end
    local ok, version = pcall(api.GetAPIVersion, api)
    if not ok or (tonumber(version) or 0) < 1 then return end
    return api
end

-- Hand over, or hand back, to match our own switches exactly: we suppress
-- their version of a thing precisely while we are doing it ourselves.
-- An addon on version 2 of the contract can hand us its messages to show.
-- We take one: its warning that the bobber landed out of reach, which we
-- have no way to see for ourselves. Shown with the catches, in our words,
-- and only while our catch text is on - otherwise it is left to show its
-- own, so the warning is never lost between the two of us.
local WARNING = "fishing.warning"
local UNREACHABLE = "BOBBER_NOT_REACHABLE"
local heardBy -- the API we registered with, so it happens once per arrival

local function OnFeedback(feedback)
    if type(feedback) ~= "table" or feedback.code ~= UNREACHABLE then return false end
    return MF:FloatWarning("Bobber out of reach - recast") == true
end
MF.CompatFeedback = OnFeedback

local function Listen(api)
    if heardBy == api or type(api.RegisterFeedbackHandler) ~= "function" then return end
    local supported = type(api.IsFeedbackCategorySupported) ~= "function"
        or select(2, pcall(api.IsFeedbackCategorySupported, api, WARNING)) == true
    if not supported then return end
    local ok, done = pcall(api.RegisterFeedbackHandler, api, OWNER, OnFeedback, { WARNING })
    if ok and done then heardBy = api end
end

function MF:SyncFishFry()
    local api = self:FishFryCompat()
    if not api then return end
    Listen(api)
    for _, feature in ipairs(ORDER) do
        local ok, supported = pcall(api.IsFeatureSupported, api, feature)
        if ok and supported then
            pcall(api.SetSuppressed, api, OWNER, feature,
                Compat:IsFeatureEffective(feature) == true)
        end
    end
end

-- Watched rather than wired into every switch that could change one of
-- these. A player can turn our floaters off from the options panel, a slash
-- command or another addon, and four call sites would eventually become
-- three. Comparing the answer costs nothing and cannot be forgotten.
-- Their arrival counts as a change too. Addon load order isn't ours to
-- decide, so a FishFry that finishes loading after we do would otherwise
-- never be told anything until the player happened to flick a switch.
local last
MF:OnTick(function(self)
    local now = self:FishFryCompat() and "y" or "n"
    for _, feature in ipairs(ORDER) do
        now = now .. (Compat:IsFeatureEffective(feature) and "1" or "0")
    end
    if now == last then return end
    last = now
    self:SyncFishFry()
end)

-- Ours were only ever runtime claims, but leaving them behind would be
-- rude to an addon that outlives us in the same session.
MF:On("PLAYER_LOGOUT", function(self)
    local api = self:FishFryCompat()
    if not api then return end
    pcall(api.ReleaseAll, api, OWNER)
    if type(api.UnregisterFeedbackHandler) == "function" then
        pcall(api.UnregisterFeedbackHandler, api, OWNER)
    end
end)

-- "casting, the catch text and the bite sound" - written out the way a
-- person would say it, because this goes in a line somebody reads once.
function MF.List(items)
    if #items <= 1 then return items[1] or "" end
    return table.concat(items, ", ", 1, #items - 1) .. " and " .. items[#items]
end

-- What we have taken on, in the words the player would use.
function MF:CompatHandling()
    local out = {}
    if Compat:IsFeatureEffective("casting.doubleRightClick")
        or Compat:IsFeatureEffective("fishing.oneButton") then out[#out + 1] = "casting" end
    if Compat:IsFeatureEffective("feedback.catchFloaters") then out[#out + 1] = "the catch text" end
    if Compat:IsFeatureEffective("sound.fishingHelper") then out[#out + 1] = "the bite sound" end
    return out
end
