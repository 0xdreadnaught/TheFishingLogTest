-- The look's own settings (window sounds, animations, the board's background and catches listed,
-- the journal's size, how long alerts stay) used to be an Appearance page in the game's AddOns
-- options. They're in the settings window now, with everything else (Rework/Settings.lua).
local _, TFL = ...
local ns = TFL.Rework
local O = {}
ns.Options = O

function O:Open() TFL:OpenOptions("board") end

-- The addon compartment (the AddOns button by the minimap)
if TFL.inert then
    -- The menu entry is still there while this copy is dormant; say why it does nothing.
    function TheFishingLog_OnAddonCompartmentClick()
        print("|cffffd100The Fishing Log (merged):|r switched off while the original The Fishing Log is enabled.")
    end
else
    function TheFishingLog_OnAddonCompartmentClick()
        local MF = ns:MF()
        if MF and MF.ToggleJournal then MF:ToggleJournal() end
    end
end
