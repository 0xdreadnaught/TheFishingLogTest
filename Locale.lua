-- Locale: translation scaffolding.
--
-- MF.L[key] returns the translation for the player's client language, or the
-- key itself when there isn't one - so English text is the fallback and
-- nothing breaks if a translation is missing. UI labels go through it; chat
-- messages are still English and can be moved across over time.
--
-- To add a language, copy the deDE block, change the code (GetLocale values:
-- deDE, frFR, esES, esMX, ruRU, koKR, zhCN, zhTW, ptBR, itIT) and translate.
local _, MF = ...

local translations = {
    deDE = {
        -- ["Solo"] = "Solo",
        -- ["Stop"] = "Beenden",
    },
}

local active = translations[GetLocale()] or {}

MF.L = setmetatable({}, {
    __index = function(_, key)
        return active[key] or key
    end,
})
