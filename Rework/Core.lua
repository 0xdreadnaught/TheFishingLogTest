-- The Fishing Log's new look (originally "The Fishing Log | Expansion: UI Rework" by Godfall, MIT
-- licence - see LICENSE-UIRework.txt; internally "the Lodge"), now part of The Fishing Log itself.
--
-- The Fishing Log keeps doing all the work (catches, records, bounties, matches, sync). This part only
-- changes how it looks and feels:
--   Journal.lua  a new journal window that draws The Fishing Log's own pages, and clicks its own buttons
--   Toast.lua    achievement-style alerts in place of the flat pop-ups
--   Board.lua    the fishing board, reskinned in place (it holds secure buttons, so it is never rebuilt)
--   Panels.lua   every panel and button The Fishing Log makes later (fish card, welcome, news...) restyled
-- It is The Fishing Log's look, not an option: every part always loads, and it has no commands of
-- its own. Its look-and-feel settings are in the settings window (Settings.lua) with the rest.
--
-- It meets The Fishing Log at four seams rather than by replacing its functions:
--   MF.boardPresenter      UpdateBoard draws through it          (UI.lua)
--   MF.toastPresenter      the toast queue shows through it      (UI.lua)
--   MF.panelSkin / buttonSkin   CreatePanel / CreateButton call them   (Widgets.lua)
--   MF.journalPage + TFL_JOURNAL_DRAWN   each page as built, and word it was drawn   (Journal.lua)
local _, TFL = ...
local ns = {}
TFL.Rework = ns

ns.TITLE = "Appearance"
ns.SHORT = "The Fishing Log"
ns.ICON = "Interface\\Icons\\Trade_Fishing"

-- The parts (journal, toasts, board, panels) used to be switches; they're
-- always on now, and any old "off" saved for them is cleared at load.
local PARTS = { "journal", "toasts", "board", "panels" }

ns.defaults = {
    sounds = true,
    animations = true,
    scale = 1.0,
    boardAlpha = 0.9,   -- the fishing board's background (0 = see-through, 1 = solid)
    feedRows = 6,       -- catches the board lists (3-8)
    toastHold = 5.5,    -- seconds an alert stays up
    journalW = 1140, journalH = 620,
    -- journalPos = { point, relPoint, x, y }
}

local function Print(...)
    print("|cffffd100" .. ns.SHORT .. ":|r", ...)
end
ns.Print = Print

function ns:MF() return TFL end

-- Each feature registers a setup function; they run once The Fishing Log has built its frames.
ns.setups = {}
function ns:OnSetup(key, fn) self.setups[#self.setups + 1] = { key = key, fn = fn } end

-- These files load last, so this runs after every TFL_INIT listener of The Fishing Log's own:
-- its board, toast and journal all exist by now.
TFL:On("TFL_INIT", function(MF)
    AnglersLodgeDB = AnglersLodgeDB or {}
    ns.db = AnglersLodgeDB
    for k, v in pairs(ns.defaults) do
        if ns.db[k] == nil then ns.db[k] = v end
    end
    for _, k in ipairs(PARTS) do ns.db[k] = nil end
    if MF.oldRework then
        ns.standDown = true
        TFL:On("TFL_LOGIN", function()
            C_Timer.After(8, function()
                print("|cffffd100The Fishing Log:|r the UI Rework is built in now. Turn off "
                    .. "\"The Fishing Log | Expansion: UI Rework\" in your AddOns list and reload "
                    .. "to get the new look; until then you're on the old add-on's version of it.")
            end)
        end)
        return
    end
    for _, s in ipairs(ns.setups) do
        local fn = s.fn
        xpcall(function() fn(MF) end, geterrorhandler())
    end
end)
