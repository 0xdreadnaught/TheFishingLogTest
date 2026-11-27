-- Settings: one window for everything The Fishing Log lets you change, in the journal's look.
-- Categories down the left, one short page each on the right, and a search box over all of it.
--
-- It replaces two pages in the game's AddOns options that had grown into one long column of
-- checkboxes, with sounds, pop-ups, maps and tooltips run together, and the board's size on one
-- page and its background on the other. Every setting keeps its saved name, so nothing anyone
-- has chosen changes.
--
-- The pages are data (MF.SETTINGS), so a test can read every setting without drawing a pixel.
--   switch   key = a The Fishing Log setting, or get/set for one of the look's own (ns.db)
--            parent = a switch it hangs under: it folds away while the parent is off
--   slider   lo, hi, step, get, set, fmt, default
--   choice   get, set, choices() -> { {value, label}, ... }, default
--   button   label, run
--   note     text (a function, read when drawn)
--   bind     action = a binding from Bindings.xml, or get/set for the cast key; click it, then
--            press a key or mouse button. Right-click clears it.
-- label is the line itself, desc a short line under it, tip the full story on mouse-over.
local _, TFL = ...
local ns = TFL.Rework
local W = ns.W
local S = {}
ns.Settings = S

local MF = TFL
local function DB() return MF.db.settings end
local function Look() return ns.db or ns.defaults end

local function Pct(v) return ("%d%%"):format(v * 100 + 0.5) end
local function Px(v) return ("%d px"):format(v + 0.5) end

local function RedrawBoard()
    if MF.UpdateBoard and not InCombatLockdown() then MF:UpdateBoard() end
end

-- The board holds secure buttons, so the game won't let it be resized or moved in combat:
-- a change made then waits for the fight to end
local afterCombat = {}
local waiter = CreateFrame("Frame")
waiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for key, fn in pairs(afterCombat) do afterCombat[key] = nil pcall(fn) end
end)
local function OutOfCombat(key, fn)
    if not InCombatLockdown() then fn() return end
    if not next(afterCombat) then MF:Print("The board changes once you're out of combat.") end
    afterCombat[key] = fn
    waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- ---------------------------------------------------------------------------
-- The pages
-- ---------------------------------------------------------------------------
local PAGES = {
{ key = "fishing", title = "Fishing", icon = "Interface\\Icons\\Trade_Fishing",
  intro = "Casting, the bobber and your catches.", items = {
    { kind = "head", text = "Casting" },
    { key = "lureWarning", label = "Warn when casting without a lure" },
    { key = "autoSwapCombat", label = "Offer a weapon swap in combat",
      desc = "And back to your pole once the fight is over.",
      tip = "The swap needs your click or the pole/weapon key binding. Dual wielding may need a "
        .. "second press once the weapon cooldown is up.",
      onChange = function() MF:UpdateWeaponSwapButton() end },
    { kind = "head", text = "The bobber" },
    { key = "bobberHighlight", label = "Highlight the bobber",
      desc = "Rising bubbles and gold glints, so it's easier to spot.",
      tip = "Stays on for the whole cast; it doesn't signal a bite. Reduce motion (Board & windows) "
        .. "keeps the glints steady.",
      onChange = function() MF:UpdateBobberHighlight() end },
    { key = "bobberAutoAssist", parent = "bobberHighlight", label = "Help the highlight appear",
      desc = "Turns on interaction and object nameplates while your line is out.",
      tip = "Only if the highlight needs them. Your own nameplate settings are put back when the cast ends.",
      onChange = function() MF:UpdateBobberHighlight() end },
    { key = "loudSplash", label = "Louder splash",
      desc = "Turns the sound up while your line is out, and back after.",
      tip = "The splash of a bite is quiet and easy to miss. While you cast this switches sound "
        .. "effects on and turns them and the master volume up to full; volumes only ever go up. "
        .. "If another fishing addon does the same, this one takes over while it's on. "
        .. "/tfl restoresound puts your settings back if they ever stick.",
      onChange = function(on)
          local muted = on and MF:SplashMuted()
          if muted then
              MF:Print(("Louder splash is on. At the moment %s; it switches them on while your line is out."):format(muted))
          end
      end },
    { key = "splashBackground", parent = "loudSplash", label = "Keep sound on with WoW in the background" },
    { key = "splashErrorSpeech", parent = "loudSplash", label = "Quiet your character's \"I can't do that\"" },
    { key = "splashAmbience", parent = "loudSplash", label = "Switch ambience off (wind, water, crowds)" },
    { key = "muteMusicWithPole", label = "Mute music while you hold a fishing pole",
      tip = "Your music volume comes back when the pole is put away. Changes in combat wait until it ends.",
      onChange = function() MF:UpdateFishingMusic() end },
    { kind = "head", text = "Your goals" },
    { key = "goalTracker", label = "Show your goals under the quest tracker",
      desc = "While you have goals. Shift-drag it to move it.",
      tip = "Your fishing goals in the quest tracker's style, each with how far along it is. Click one "
        .. "for the Goals page, right-click for options. It hides in combat.",
      onChange = function() MF:UpdateGoalTracker() end },
    { kind = "button", label = "Put the goals tracker back", run = function()
          MF.db.settings.goalTrackerPos = nil
          MF:UpdateGoalTracker()
      end },
    { kind = "head", text = "Your catches" },
    { key = "floatCatches", label = "Show each catch rising off the water",
      tip = "/tfl float move puts it wherever you like." },
    { key = "castFeedback", label = "Show brief cast results under the board" },
    { key = "showValue", label = "Show what a catch is worth",
      desc = "From your own prices, when you're fishing on your own." },
    { key = "tooltipItems", label = "Fish tooltips: your bests and specimen info" },
} },

{ key = "board", title = "Board & windows", icon = "Interface\\Icons\\INV_Misc_Note_02",
  intro = "How the fishing board and the journal look.", items = {
    { kind = "head", text = "Fishing board" },
    { key = "autoBoard", label = "Open the board when you start fishing" },
    { kind = "slider", label = "Board size", lo = 0.6, hi = 1.6, step = 0.05, fmt = Pct, default = 1,
      get = function() return DB().boardScale or 1 end,
      set = function(v) DB().boardScale = v OutOfCombat("scale", function() MF:ApplyBoardScale() end) end },
    { kind = "slider", label = "Board background", lo = 0, hi = 1, step = 0.05, fmt = Pct, default = 0.9,
      tip = "How solid the board's background is. The gear on the board does the same.",
      get = function() return Look().boardAlpha or 0.9 end,
      set = function(v)
          if ns.Board and ns.Board.SetBackgroundAlpha then ns.Board:SetBackgroundAlpha(v) else ns.db.boardAlpha = v end
      end },
    { kind = "slider", label = "Catches listed on the board", lo = 3, hi = 8, step = 1, default = 6,
      fmt = function(v) return tostring(math.floor(v + 0.5)) end,
      get = function() return Look().feedRows or 6 end,
      set = function(v) ns.db.feedRows = v RedrawBoard() end },
    { kind = "button", label = "Reset board position", run = function()
          OutOfCombat("position", function() MF:ResetBoardPosition() end)
      end },
    { kind = "head", text = "Journal" },
    { kind = "slider", label = "Journal size", lo = 0.6, hi = 1.6, step = 0.05, fmt = Pct, default = 1,
      get = function() return Look().scale or 1 end,
      set = function(v)
          ns.db.scale = v
          local jf = ns.Journal and ns.Journal:Frame()
          if jf then jf:SetScale(v) ns.Journal:SyncHost() end
      end },
    { kind = "button", label = "Reset journal size and position", run = function()
          ns.db.journalPos, ns.db.journalW, ns.db.journalH = nil, ns.defaults.journalW, ns.defaults.journalH
          ns.db.scale = 1
          local jf = ns.Journal and ns.Journal:Frame()
          if jf then jf:SetScale(1) ns.Journal:ApplySize(true) end
      end },
    { key = "loginRecap", label = "Offer a recap after you log in",
      desc = "On your first visit to the journal. /tfl recap opens it any time." },
    { kind = "head", text = "Look and feel" },
    { label = "Animations", desc = "Fades, sliding catches, counting numbers and smooth scrolling.",
      get = function() return Look().animations ~= false end, set = function(v) ns.db.animations = v end,
      default = true },
    { key = "reducedMotion", label = "Reduce motion",
      desc = "A steady frenzy glow, with no bubbles or pulsing map markers.",
      onChange = function() RedrawBoard() MF:RefreshMapPins() end },
    { key = "kilograms", label = "Weights in kilograms",
      tip = "Only what you see. Every record is still kept, sent and compared in pounds, so you and "
        .. "an angler reading pounds are always looking at the same fish.",
      onChange = function() MF:RefreshJournal() RedrawBoard() end },
    { key = "minimap", label = "Minimap button",
      desc = "Click: board. Right-click: journal. Shift-click: settings.",
      onChange = function() MF:UpdateMinimapButton() end },
} },

{ key = "alerts", title = "Alerts & chat", icon = "Interface\\Icons\\INV_Letter_15",
  intro = "Pop-ups in the middle of the screen, and what The Fishing Log says in chat.", items = {
    { kind = "head", text = "Pop-ups" },
    { key = "toasts", label = "Show pop-ups",
      desc = "Off hides them all. Sounds and chat lines aren't affected." },
    { key = "popupSpecimens", parent = "toasts", label = "Specimen catches" },
    { key = "popupRecords", parent = "toasts", label = "Spot records and Kings" },
    { key = "popupRanks", parent = "toasts", label = "Rank ups" },
    { key = "popupFrenzies", parent = "toasts", label = "Feeding frenzies",
      tip = "Not while you're on a flight path. Landing at a water in a frenzy can still announce it." },
    { key = "popupBounties", parent = "toasts", label = "Bounty rewards" },
    { key = "popupOther", parent = "toasts", label = "New cards, goals, matches, events and seasons" },
    { kind = "slider", label = "Time on screen", lo = 3, hi = 12, step = 0.5, default = 5.5,
      fmt = function(v) return ("%.1f s"):format(v) end,
      tip = "How long a pop-up stays before it fades. Hovering one keeps it up.",
      get = function() return Look().toastHold or 5.5 end, set = function(v) ns.db.toastHold = v end },
    { kind = "button", label = "Show a test pop-up", run = function()
          if ns.Toast and ns.Toast.Test then ns.Toast:Test()
          elseif MF.Toast then MF:Toast(MF:FishIcon(6358), "NEW SPECIMEN!", "Oily Blackmouth, 6.26 lb", "This is how alerts look.", 1, 0.5, 0) end
      end },
    { kind = "head", text = "Chat" },
    { kind = "choice", label = "Send messages to",
      tip = "Pick a chat tab for The Fishing Log's messages. Make the tab in WoW first; a tab that's "
        .. "gone or renamed falls back to the default window.",
      choices = function()
          local out = {}
          for _, w in ipairs(MF:ChatOutputWindows()) do out[#out + 1] = { w.id ~= 0 and w.name or "", w.name } end
          return out
      end,
      get = function()
          local c = DB().chatOutput
          return type(c) == "table" and c.name or ""
      end,
      set = function(name)
          if name == "" then DB().chatOutput = nil return end
          for _, w in ipairs(MF:ChatOutputWindows()) do
              if w.id ~= 0 and w.name == name then DB().chatOutput = { id = w.id, name = w.name } return end
          end
      end,
      default = "" },
    { key = "recordAlerts", label = "Records set in your zone",
      desc = "A line in chat when someone sets a record where you are." },
} },

{ key = "sounds", title = "Sounds", icon = "Interface\\Icons\\INV_Misc_Horn_01",
  intro = "Every sound The Fishing Log makes. The louder splash is under Fishing.", items = {
    { key = "sounds", label = "Play sounds", desc = "Off silences everything below." },
    { key = "soundSpecimens", parent = "sounds", label = "Specimen catches" },
    { key = "soundRecords", parent = "sounds", label = "Records and crowns you set" },
    { key = "soundRecordLost", parent = "sounds", label = "Records and crowns you lose" },
    { key = "soundRanks", parent = "sounds", label = "Rank ups" },
    { key = "soundCards", parent = "sounds", label = "New cards" },
    { key = "soundFrenzies", parent = "sounds", label = "Feeding frenzies and the Extravaganza" },
    { key = "soundBounties", parent = "sounds", label = "Bounty rewards" },
    { key = "soundMatches", parent = "sounds", label = "Matches, invites and events",
      desc = "The match countdown's ticks and horn too." },
    { key = "soundSeasons", parent = "sounds", label = "Season send-offs" },
    { key = "soundGoals", parent = "sounds", label = "Fishing goals you finish" },
    { key = "higherLowerSounds", parent = "sounds", label = "Higher or Lower" },
    { parent = "sounds", label = "Window sounds", desc = "Page turns and clicks in the journal and here.",
      get = function() return Look().sounds ~= false end, set = function(v) ns.db.sounds = v end, default = true },
} },

{ key = "matches", title = "Matches & events", icon = "Interface\\Icons\\INV_Crown_01",
  intro = "Invites, the event noticeboard and the match countdown.", items = {
    { kind = "head", text = "Invites" },
    { key = "invites", label = "Match invites in your zone",
      desc = "A pop-up when someone hosts a match in your zone." },
    { key = "invitesFromAnyone", label = "Take invites from anyone",
      desc = "Not only your guild, friends and party.",
      tip = "Players on your ignore list can't invite you either way." },
    { kind = "head", text = "Events" },
    { key = "noticeboard", label = "Event noticeboard" },
    { key = "eventReminders", label = "Remind me before events I've signed up for" },
    { kind = "head", text = "Matches" },
    { key = "matchSplash", label = "Countdown in the middle of the screen",
      desc = "3, 2, 1 and LINES IN! at the start, and the last seconds at the end.",
      tip = "Chat and the pop-up say it either way. The ticks and horn follow the Matches sound." },
} },

{ key = "maps", title = "Maps & pools", icon = "Interface\\Icons\\INV_Misc_Map_01",
  intro = "Feeding frenzies and fishing pools on your maps.", items = {
    { kind = "head", text = "World map" },
    { key = "mapFrenzy", label = "Feeding frenzies",
      onChange = function() MF:RefreshMapPins() MF:RefreshMapLayerControls() end },
    { key = "poolWorldMap", label = "Known fishing pools",
      tip = "Recorded when an angler hovers a named pool and catches from it, then shared between "
        .. "Fishing Log anglers. A marker isn't a pool that's there now. No gathering addon needed.",
      onChange = function() MF:RefreshPoolPins() end },
    { key = "mapLayerButtons", label = "Frenzies and Pools buttons on the map",
      desc = "Off hides the box. The marks still follow the two switches above.",
      onChange = function() MF:RefreshMapLayerControls() end },
    { kind = "slider", label = "Pool marker size", lo = 12, hi = 24, step = 2, fmt = Px, default = 16,
      get = function() return MF:MapMarkerSize("world") end,
      set = function(v) MF:SetMapMarkerSize("world", v) end },
    { kind = "head", text = "Minimap" },
    { key = "poolMinimap", label = "Known fishing pools",
      onChange = function() MF:RefreshPoolPins() end },
    { kind = "slider", label = "Pool marker size", lo = 8, hi = 18, step = 2, fmt = Px, default = 12,
      get = function() return MF:MapMarkerSize("minimap") end,
      set = function(v) MF:SetMapMarkerSize("minimap", v) end },
    { kind = "head", text = "Sharing" },
    { key = "poolSharing", label = "Share and receive pool locations" },
    { kind = "note", text = function() return MF.MapMarkerLegend and MF:MapMarkerLegend() or "" end },
} },

{ key = "anglers", title = "Other anglers", icon = "Interface\\Icons\\INV_Misc_Fish_09",
  intro = "Spotting fellow anglers, and hearing about their catches.", items = {
    { kind = "head", text = "The gold hook" },
    { key = "anglerNameplateHook", label = "On nameplates",
      tip = "Marks players whose Fishing Log you've heard from in the last three days. It uses the "
        .. "nameplates WoW already shows, so friendly nameplates need to be on.",
      onChange = function() MF:RefreshAnglerNameplates() end },
    { key = "anglerTargetHook", label = "On your target frame",
      tip = "Works with Blizzard's target frame and most unit-frame addons.",
      onChange = function() MF:RefreshTargetHook() end },
    { key = "anglerChatHook", label = "In chat", desc = "Works with nameplates off. Pick which chat below." },
    { key = "anglerChatHookSay", parent = "anglerChatHook", label = "Say, yell and emotes" },
    { key = "anglerChatHookGuild", parent = "anglerChatHook", label = "Guild and officer" },
    { key = "anglerChatHookGroup", parent = "anglerChatHook", label = "Party, raid and instance" },
    { key = "anglerChatHookWhisper", parent = "anglerChatHook", label = "Whispers" },
    { key = "anglerChatHookChannel", parent = "anglerChatHook", label = "Channels (General, Trade and the like)" },
    { kind = "head", text = "Their catches" },
    { key = "nearbyCatches", label = "Nearby anglers' catches in chat",
      desc = "Same faction, same fishing spot.",
      tip = "Both of you need an up-to-date Fishing Log. Distance is checked where the game allows. "
        .. "/tfl nearby off turns it off too." },
    { key = "nearbyNotableOnly", parent = "nearbyCatches", label = "Only specimens, crackers and monsters" },
    { key = "tooltipPlayers", label = "Angler rank on player tooltips" },
    { kind = "head", text = "The realm" },
    { key = "channel", label = "Discover anglers across the realm",
      desc = "Joins TheFishingLog channel, kept out of your chat.",
      onChange = function(on) if on then MF:JoinChannel() else MF:LeaveChannel() end end },
} },

{ key = "keys", title = "Key bindings", icon = "Interface\\Icons\\INV_Misc_Key_03",
  intro = "Click a key, then press the key or mouse button you want. Right-click one to clear it.", items = {
    { kind = "head", text = "Casting" },
    { kind = "bind", label = "Cast and land the fish",
      desc = "Casts while you hold a pole, then reels in the bobber.",
      tip = "Only takes the key while a fishing pole is in your hands, so it's free the rest of the "
        .. "time. Right and left mouse need a double press, so they still turn the camera. "
        .. "/tfl cast does the same from chat.",
      get = function() return DB().castClick or "" end,
      set = function(key) return MF:SetCastKey(key) end,
      default = "BUTTON2" },
    { key = "castDouble", label = "Double-press to cast",
      desc = "So a stray press of your cast key doesn't throw a line.",
      tip = "Right and left mouse always need the double press, whatever this says: binding the "
        .. "whole press is what takes camera turning away. Any other key takes a single press "
        .. "when this is off.",
      -- On and greyed while the cast key is a mouse button the camera needs
      forced = function() return MF:CastNeedsDouble() end,
      forcedDesc = "Always on with a mouse button, so it can still turn the camera." },
    { kind = "bind", label = "Put your best lure on", action = "CLICK TheFishingLogLureButton:LeftButton",
      tip = "The same as the board's lure button: the best lure in your bags, on your pole." },
    { kind = "bind", label = "Open the lure menu", action = "THEFISHINGLOG_LUREMENU",
      tip = "Pick which lure to use. It can't open during a fight." },
    { kind = "bind", label = "Swap fishing pole and weapon", action = "THEFISHINGLOG_POLE",
      tip = "Works in combat too: the key presses the swap button." },
    { kind = "head", text = "Windows" },
    { kind = "bind", label = "The Angler's Journal", action = "THEFISHINGLOG_JOURNAL" },
    { kind = "bind", label = "The fishing board", action = "THEFISHINGLOG_BOARD" },
    { kind = "bind", label = "Settings", action = "THEFISHINGLOG_SETTINGS" },
    { kind = "bind", label = "Fishing here", action = "THEFISHINGLOG_HERE",
      desc = "The water you're at, in the journal." },
    { kind = "bind", label = "Find waters", action = "THEFISHINGLOG_FINDER",
      desc = "Where to fish next, in the journal." },
    { kind = "head", text = "Your session" },
    { kind = "bind", label = "Stop the fishing log", action = "THEFISHINGLOG_STOP" },
    { kind = "note", tall = true, text = "These are the game's own key bindings, so they're kept with the rest of "
        .. "yours and show under The Fishing Log in Esc > Options > Keybindings too. Taking a key "
        .. "another action uses moves it here, and chat says what it did before." },
} },

{ key = "extras", title = "Extras", icon = "Interface\\Icons\\INV_Misc_Ticket_Tarot_Stack_01",
  intro = "The card game, and a spare copy of your progress.", items = {
    { key = "higherLower", label = "Higher or Lower",
      desc = "The card game played with your own album.",
      tip = "Off puts it away entirely: no flight offer, and /tfl higherlower won't open it. Your best streaks are kept.",
      onChange = function(on) if not on then MF:PutAwayHigherLower() end end },
    { key = "flightGame", parent = "higherLower", label = "Offer a game on flight paths",
      desc = "Needs five cards with a weight on them.",
      onChange = function(on) if not on then MF:HideHigherLowerOffer() end end },
    { key = "macroSave", label = "Back up your progress in account macros",
      desc = "A spare copy of your rank and journal, in case a save is lost.",
      onChange = function(on) if on then MF.macroDirty = true else MF:DeleteSaveMacros() end end },
} },
}
MF.SETTINGS = PAGES

-- ---------------------------------------------------------------------------
-- Reading and writing a setting
-- ---------------------------------------------------------------------------
local function Kind(it) return it.kind or "switch" end

function S:Get(it)
    if it.get then return it.get() end
    if it.action then return (GetBindingKey and GetBindingKey(it.action)) or "" end
    return DB()[it.key]
end

-- What a binding is called, for "F did ... before"
local function ActionName(action)
    return _G["BINDING_NAME_" .. action] or action
end

-- A game key binding: one key to the action, saved with the player's other bindings
function S:Bind(it, key)
    if InCombatLockdown() then
        MF:Print("Key bindings can't change during a fight.")
        return false
    end
    local old = { GetBindingKey(it.action) }
    for _, k in ipairs(old) do SetBinding(k) end
    if key ~= "" then
        local before = GetBindingAction(key)
        if before and before ~= "" and before ~= it.action then
            MF:Print(("%s did \"%s\" before; now it's %s."):format(S.KeyText(key), ActionName(before), it.label))
        end
        if not SetBinding(key, it.action) then
            for _, k in ipairs(old) do SetBinding(k, it.action) end
            MF:Print(("The game won't bind %s."):format(S.KeyText(key)))
            return false
        end
    end
    SaveBindings(GetCurrentBindingSet())
    return true
end

function S:Set(it, v)
    if Kind(it) == "bind" and not it.set then
        if not self:Bind(it, v) then return end
    elseif it.set then it.set(v) else DB()[it.key] = v end
    if it.onChange then
        local ok, err = pcall(it.onChange, v)
        if not ok then geterrorhandler()(err) end
    end
end

-- A switch under another counts as off while its parent is
function S:ParentOn(it)
    if not it.parent then return true end
    return DB()[it.parent] and true or false
end

function S:Default(it)
    if it.default ~= nil then return it.default end
    if it.action then return "" end
    if it.key and MF.DEFAULT_SETTINGS then return MF.DEFAULT_SETTINGS[it.key] end
end

function S:HasChildren(it)
    if not it.key then return false end
    for _, page in ipairs(PAGES) do
        for _, other in ipairs(page.items) do if other.parent == it.key then return true end end
    end
    return false
end

-- Everything on a page back as it came
function S:ResetPage(page)
    for _, it in ipairs(page.items) do
        local k = Kind(it)
        if k == "switch" or k == "slider" or k == "choice" or k == "bind" then
            local d = self:Default(it)
            if d ~= nil and self:Get(it) ~= d then self:Set(it, d) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Search: the same forgiving match as the Realm tabs (capitals, accents and hyphens don't count)
-- ---------------------------------------------------------------------------
local function Fold(s)
    local R = ns.RealmPage
    if R and R.Fold then return R.Fold(s) end
    return (s or ""):lower()
end

local function Text(v) if type(v) == "function" then return v() or "" end return v or "" end

function S:Matches(page, it, query)
    local words = {}
    for w in Fold(query):gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return true end
    local hay = Fold(table.concat({ it.label or "", it.desc or "", it.tip or "", Text(it.text) }, " "))
    local around = Fold(page.title .. " " .. (it.under or ""))
    for _, w in ipairs(words) do
        if not (hay:find(w, 1, true) or around:find(w, 1, true)) then return false end
    end
    return true
end

-- The rows to draw for a page, or for a search across every page
function S:Rows(pageKey, query)
    local rows = {}
    local searching = query and query:match("%S")
    for _, page in ipairs(PAGES) do
        if searching or page.key == pageKey then
            local under, found = nil, {}
            for _, it in ipairs(page.items) do
                local k = Kind(it)
                if k == "head" then
                    under = it.text
                    if not searching then found[#found + 1] = { kind = "head", text = it.text } end
                else
                    it.under = under
                    if searching then
                        if k ~= "note" and self:Matches(page, it, query) then
                            -- The section it's in, so two "Known fishing pools" say which map
                            if under and under ~= found.under then
                                found[#found + 1] = { kind = "head", text = under }
                                found.under = under
                            end
                            found[#found + 1] = { kind = k, it = it }
                        end
                    elseif self:ParentOn(it) then
                        found[#found + 1] = { kind = k, it = it }
                    end
                end
            end
            if searching and #found > 0 then
                rows[#rows + 1] = { kind = "page", page = page }
                for _, r in ipairs(found) do rows[#rows + 1] = r end
            elseif not searching then
                for _, r in ipairs(found) do rows[#rows + 1] = r end
            end
        end
    end
    return rows
end

-- How many settings a search found
local function Count(rows)
    local n = 0
    for _, r in ipairs(rows) do if r.it then n = n + 1 end end
    return n
end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
local GOLD = { 1, 0.82, 0 }

-- A round-ended on/off switch: a gold track with the knob to the right when on
local function Round(parent, layer, size)
    local t = parent:CreateTexture(nil, layer)
    t:SetSize(size, size)
    t:SetColorTexture(1, 1, 1, 1)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(t)
    t:AddMaskTexture(mask)
    return t
end

local SW, SH = 34, 18
local function Switch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(SW, SH)
    s.track = {
        Round(s, "BACKGROUND", SH),
        Round(s, "BACKGROUND", SH),
        s:CreateTexture(nil, "BACKGROUND"),
    }
    s.track[1]:SetPoint("LEFT")
    s.track[2]:SetPoint("RIGHT")
    s.track[3]:SetPoint("TOPLEFT", SH / 2, 0)
    s.track[3]:SetPoint("BOTTOMRIGHT", -SH / 2, 0)
    s.track[3]:SetColorTexture(1, 1, 1, 1)
    s.knob = Round(s, "ARTWORK", SH - 4)
    s.pos = 0
    function s:Paint(e)
        local on = self.on
        local r, g, b = 0.22, 0.22, 0.24
        if on then r, g, b = 0.85 * e + 0.22 * (1 - e), 0.62 * e + 0.22 * (1 - e), 0.08 * e + 0.24 * (1 - e)
        else r, g, b = 0.85 * (1 - e) + 0.22 * e, 0.62 * (1 - e) + 0.22 * e, 0.08 * (1 - e) + 0.24 * e end
        local a = self.enabled == false and 0.4 or 1
        for _, t in ipairs(self.track) do t:SetVertexColor(r, g, b, a) end
        local from = on and 0 or 1
        local x = (from + ((on and 1 or 0) - from) * e) * (SW - SH)
        self.knob:ClearAllPoints()
        self.knob:SetPoint("LEFT", 2 + x, 0)
        local k = on and 1 or 0.78
        self.knob:SetVertexColor(k, k, k * (on and 0.92 or 1), a)
    end
    function s:SetOn(on, animate)
        local was = self.on
        self.on = on and true or false
        -- Nothing to change: leave a running slide alone
        if not animate and was == self.on and self.painted == self.enabled then return end
        self.painted = self.enabled
        if animate and was ~= nil and was ~= self.on then
            W:Tween(self, 0.14, function(e) self:Paint(e) end)
        else
            W:StopTween(self)
            self:Paint(1)
        end
    end
    return s
end

local function Slider(parent)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(17)
    if s.SetBackdrop then
        s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    -- No mouse wheel: it scrolls the page, rather than resizing the board under the cursor
    return s
end

local MakeRow, FillRow

-- A key as the game writes it ("SHIFT-F", "BUTTON3"), said the way people say it
function S.KeyText(key)
    if not key or key == "" then return "" end
    local text = GetBindingText and GetBindingText(key)
    if type(text) ~= "string" or text == "" then text = key end
    return text
end

-- The key a press makes: modifiers first, in the game's order
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE_KEYS = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
    Button4 = "BUTTON4", Button5 = "BUTTON5" }
function S.PressKey(key)
    if MODIFIER_KEYS[key] then return nil end
    key = MOUSE_KEYS[key] or key
    local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
    return mods .. key
end

-- Plain left or right mouse would stop the game's own clicking and camera, so only the cast key
-- (which knows how to share them) may have them
local function Allowed(it, key)
    if it.action and (key == "BUTTON1" or key == "BUTTON2") then
        MF:Print("Plain left or right mouse would stop clicking and turning the camera. Hold Shift, Ctrl or Alt with it, or pick another key.")
        return false
    end
    -- Shift, Ctrl and Alt with a left click are the game's own: linking, trying on, and more
    if key:find("%-BUTTON1$") then
        MF:Print("Shift, Ctrl or Alt with a left click are the game's own (linking an item, trying it on). Pick another key.")
        return false
    end
    -- One key, one job: the cast key takes its key over while a pole is out, so sharing it
    -- would work only half the time
    if it.action and key == MF:CastBinding() then
        MF:Print(("%s casts for you. Pick another key, or move the cast key first."):format(S.KeyText(key)))
        return false
    end
    if not it.action then
        local ok, other = pcall(GetBindingAction, key)
        other = ok and type(other) == "string" and other or ""
        if other:find("^THEFISHINGLOG_") or other:find("TheFishingLog", 1, true) then
            MF:Print(("%s does \"%s\" already. Pick another key for casting, or clear that one first."):format(
                S.KeyText(key), _G["BINDING_NAME_" .. other] or other))
            return false
        end
    end
    return true
end

function S:StopListening()
    local b = self.listening
    if not b then return end
    self.listening, self.listenItem = nil, nil
    b:EnableKeyboard(false)
    b:EnableMouseWheel(false)
    if b.SetPropagateKeyboardInput and not InCombatLockdown() then pcall(b.SetPropagateKeyboardInput, b, true) end
    if b.row and b.row.item and b.row.label then FillRow(b.row, b.row.item) end
end

function S:Listen(b)
    if InCombatLockdown() then MF:Print("Key bindings can't change during a fight.") return end
    self:StopListening()
    self.listening = b
    self.listenItem = b.row and b.row.item and b.row.item.it
    b:SetText("|cffffd100Press a key...|r")
    b:EnableKeyboard(true)
    b:EnableMouseWheel(true)
    if b.SetPropagateKeyboardInput then pcall(b.SetPropagateKeyboardInput, b, false) end
end

-- A press while listening: Escape gives up, anything else is the new key
function S:Pressed(b, key)
    if self.listening ~= b then return end
    local it = self.listenItem
    -- A second plain click on the key gives up too, rather than binding the left mouse button
    if key == "ESCAPE" or (key == "LeftButton" and not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown())) then
        self:StopListening()
        return
    end
    key = S.PressKey(key)
    if not key or not it then return end
    self:StopListening()
    if not Allowed(it, key) then return end
    if key ~= self:Get(it) then self:Set(it, key) end
    self:Refresh(true)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local PAD = 10
local INDENT = 24

local function Hover(row)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.06)
    hl:Hide()
    row.hl = hl
    row:HookScript("OnEnter", function(self) self.hl:Show() end)
    row:HookScript("OnLeave", function(self) self.hl:Hide() end)
end

local function Tooltip(row)
    row:HookScript("OnEnter", function(self)
        local it = self.item and self.item.it
        if not (it and it.tip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(it.label or "", 1, 0.82, 0)
        GameTooltip:AddLine(it.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function(self) W:HideTip(self) end)
end

-- The child line: a thin gold rule down the left of a switch that hangs under another
local function ChildRule(row)
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetWidth(2)
    row.rule:SetPoint("TOPLEFT", PAD + 8, 0)
    row.rule:SetPoint("BOTTOMLEFT", PAD + 8, 0)
    row.rule:SetColorTexture(1, 0.82, 0, 0.35)
end

function MakeRow(kind)
    local row
    if kind == "head" then
        row = CreateFrame("Frame")
        row.text = W:Label(row, "GameFontNormal")
        row.text:SetPoint("BOTTOMLEFT", PAD, 8)
        row.line = W:Divider(row, 100)
        row.line:SetPoint("BOTTOMLEFT", PAD - 4, 3)
        row.line:SetPoint("BOTTOMRIGHT", -PAD, 3)
    elseif kind == "page" then
        row = CreateFrame("Button")
        row.icon = W:Icon(row, 22)
        row.icon:SetPoint("LEFT", PAD, -2)
        row.text = W:Label(row, "GameFontNormalLarge")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.go = W:Label(row, "GameFontHighlightSmall", "Open page")
        row.go:SetPoint("RIGHT", -PAD, -2)
        row.go:SetTextColor(0.6, 0.6, 0.6)
        row.line = W:Divider(row, 100)
        row.line:SetPoint("BOTTOMLEFT", PAD - 4, 2)
        row.line:SetPoint("BOTTOMRIGHT", -PAD, 2)
        Hover(row)
        row:SetScript("OnClick", function(self) W:Sound("tab") S:Show(self.item.page.key) end)
    elseif kind == "switch" then
        row = CreateFrame("Button")
        Hover(row)
        ChildRule(row)
        row.label = W:Label(row, "GameFontHighlight")
        row.label:SetJustifyH("LEFT")
        row.desc = W:Label(row, "GameFontHighlightSmall")
        row.desc:SetJustifyH("LEFT")
        row.desc:SetTextColor(0.62, 0.62, 0.62)
        row.switch = Switch(row)
        row.switch:SetPoint("RIGHT", -PAD, 0)
        local function Flip()
            local it = row.item and row.item.it
            if not it or not S:ParentOn(it) or (it.forced and it.forced()) then return end
            W:Sound("click")
            local on = not S:Get(it)
            S:Set(it, on)
            row.switch:SetOn(on, true)
            -- A switch with others under it opens or folds them
            if S:HasChildren(it) then S:Refresh(true) end
        end
        row:SetScript("OnClick", Flip)
        row.switch:SetScript("OnClick", Flip)
        row.switch:HookScript("OnEnter", function() row.hl:Show() end)
        row.switch:HookScript("OnLeave", function() row.hl:Hide() end)
        Tooltip(row)
    elseif kind == "slider" then
        row = CreateFrame("Frame")
        row:EnableMouse(true)
        Hover(row)
        row.label = W:Label(row, "GameFontHighlight")
        row.label:SetPoint("TOPLEFT", PAD, -6)
        row.value = W:Label(row, "GameFontNormal")
        row.value:SetPoint("TOPRIGHT", -PAD, -6)
        row.slider = Slider(row)
        row.slider:SetPoint("TOPLEFT", PAD, -26)
        row.slider:SetPoint("TOPRIGHT", -PAD, -26)
        row.slider:SetScript("OnValueChanged", function(self, v)
            local it = row.item and row.item.it
            if not it then return end
            v = math.floor(v / it.step + 0.5) * it.step
            row.value:SetText((it.fmt or tostring)(v))
            if not row.loading then S:Set(it, v) end
        end)
        Tooltip(row)
    elseif kind == "choice" then
        row = CreateFrame("Frame")
        row:EnableMouse(true)
        Hover(row)
        row.label = W:Label(row, "GameFontHighlight")
        row.label:SetPoint("LEFT", PAD, 0)
        local function It() return row.item and row.item.it end
        row.choice = W:Choice(row, 200,
            function() local it = It() return it and S:Get(it) end,
            function(v) local it = It() if it then S:Set(it, v) end end,
            function() local it = It() return it and it.choices() or {} end)
        row.choice:SetPoint("RIGHT", -PAD, 0)
        Tooltip(row)
    elseif kind == "button" then
        row = CreateFrame("Frame")
        row.button = W:Button(row, "", 220, 22, function()
            local it = row.item and row.item.it
            if it and it.run then it.run() end
            S:Refresh(true)
        end)
        row.button:SetPoint("LEFT", PAD, 0)
    elseif kind == "bind" then
        row = CreateFrame("Frame")
        row:EnableMouse(true)
        Hover(row)
        row.label = W:Label(row, "GameFontHighlight")
        row.label:SetJustifyH("LEFT")
        row.desc = W:Label(row, "GameFontHighlightSmall")
        row.desc:SetJustifyH("LEFT")
        row.desc:SetTextColor(0.62, 0.62, 0.62)
        local b = W:Button(row, "", 170, 22)
        b.row = row
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", function(self, button)
            if S.listening == self then S:Pressed(self, button) return end
            local it = row.item and row.item.it
            if not it then return end
            W:Sound("click")
            if button == "RightButton" then
                if S:Get(it) ~= "" then S:Set(it, "") S:Refresh(true) end
            elseif button == "LeftButton" then
                S:Listen(self)
            end
        end)
        b:SetScript("OnKeyDown", function(self, key) S:Pressed(self, key) end)
        b:SetScript("OnMouseWheel", function(self, delta) S:Pressed(self, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
        b:SetScript("OnHide", function(self) if S.listening == self then S:StopListening() end end)
        b:HookScript("OnEnter", function(self)
            row.hl:Show()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.item and row.item.it.label or "", 1, 0.82, 0)
            GameTooltip:AddLine("Click, then press a key or mouse button. Escape or another click gives up.", 1, 1, 1, true)
            GameTooltip:AddLine("Right-click clears it.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function(self) row.hl:Hide() W:HideTip(self) end)
        b:SetPoint("RIGHT", -PAD, 0)
        row.key = b
        Tooltip(row)
    else -- note
        row = CreateFrame("Frame")
        row.text = W:Label(row, "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", PAD, -4)
        row.text:SetPoint("TOPRIGHT", -PAD, -4)
        row.text:SetJustifyH("LEFT")
        row.text:SetTextColor(0.75, 0.75, 0.75)
    end
    return row
end

function FillRow(row, item)
    local it = item.it
    if item.kind == "head" then
        row.text:SetText(item.text)
    elseif item.kind == "page" then
        row.icon:SetTexture(item.page.icon)
        row.text:SetText(item.page.title)
    elseif item.kind == "switch" then
        local child = it.parent and true or false
        local left = PAD + (child and INDENT or 0)
        row.rule:SetShown(child)
        row.label:SetText(it.label)
        row.label:ClearAllPoints()
        row.desc:ClearAllPoints()
        if it.desc then
            row.label:SetPoint("TOPLEFT", left, -6)
            row.label:SetPoint("TOPRIGHT", -(PAD + SW + 12), -6)
            row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
            row.desc:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -3)
            row.desc:SetText(it.forcedDesc and it.forced and it.forced() and it.forcedDesc or it.desc)
            row.desc:Show()
        else
            row.label:SetPoint("LEFT", left, 0)
            row.label:SetPoint("RIGHT", row.switch, "LEFT", -12, 0)
            row.desc:Hide()
        end
        local forced = it.forced and it.forced()
        local enabled = S:ParentOn(it) and not forced
        row.switch.enabled = enabled
        row.label:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
        row.switch:SetOn((forced or S:Get(it)) and true or false)
    elseif item.kind == "slider" then
        row.loading = true
        row.label:SetText(it.label)
        row.slider:SetMinMaxValues(it.lo, it.hi)
        row.slider:SetValueStep(it.step)
        local v = S:Get(it) or it.lo
        row.slider:SetValue(v)
        row.value:SetText((it.fmt or tostring)(v))
        row.loading = false
    elseif item.kind == "choice" then
        row.label:SetText(it.label)
        if row.choice.GenerateMenu then row.choice:GenerateMenu() end
    elseif item.kind == "bind" then
        row.label:SetText(it.label)
        row.label:ClearAllPoints()
        if it.desc then
            row.label:SetPoint("TOPLEFT", PAD, -6)
            row.label:SetPoint("RIGHT", row.key, "LEFT", -12, 0)
            row.desc:ClearAllPoints()
            row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
            row.desc:SetPoint("RIGHT", row.key, "LEFT", -12, 0)
            row.desc:SetText(it.desc)
            row.desc:Show()
        else
            row.label:SetPoint("LEFT", PAD, 0)
            row.label:SetPoint("RIGHT", row.key, "LEFT", -12, 0)
            row.desc:Hide()
        end
        if S.listening == row.key and S.listenItem ~= it then S:StopListening() end
        if S.listening ~= row.key then
            local key = S:Get(it)
            row.key:SetText(key ~= "" and S.KeyText(key) or "|cff808080Not bound|r")
        end
    elseif item.kind == "button" then
        row.button:SetText(it.label)
        row.button:SetWidth(math.max(160, (row.button:GetFontString() and row.button:GetFontString():GetStringWidth() or 120) + 32))
    else
        row.text:SetText(Text(it.text))
    end
end

local HEIGHTS = { head = 34, page = 40, slider = 50, choice = 36, button = 34, note = 30 }
local function Height(r)
    if r.kind == "switch" or r.kind == "bind" then return r.it.desc and 42 or 32 end
    if r.kind == "note" and r.it and r.it.tall then return 46 end
    return HEIGHTS[r.kind] or 30
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local LEFT_W = 196

local function CategoryButton(parent, page)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(34)
    W:Row(b)
    b.icon = W:Icon(b, 22, page.icon)
    b.icon:SetPoint("LEFT", 8, 0)
    b.text = W:Label(b, "GameFontNormal", page.title)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.page = page
    b:SetScript("OnClick", function(self)
        W:Sound("tab")
        S:Show(self.page.key)
    end)
    return b
end

function S:Build()
    if self.frame then return self.frame end
    local f = W:Window("TheFishingLogSettings", "The Fishing Log", 780, 580, ns.ICON)
    self.frame = f
    f:SetPoint("CENTER")
    f.heading:SetText("Settings")
    f:HookScript("OnShow", function() W:Sound("open") end)
    f:HookScript("OnHide", function() W:Sound("close") S.armed = nil S:StopListening() end)
    f:RegisterEvent("UPDATE_BINDINGS")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then S:StopListening()
        elseif event == "UPDATE_BINDINGS" and f:IsShown() and not S.listening then S:Refresh(true) end
    end)

    local ground = W:Ground(f)
    ground:SetPoint("TOPLEFT", 4, -60)
    ground:SetPoint("BOTTOMRIGHT", -4, 4)
    W:HideTopCorners(ground)

    -- Left: search, then the pages
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", ground, "TOPLEFT", 10, -10)
    left:SetPoint("BOTTOMLEFT", ground, "BOTTOMLEFT", 10, 10)
    left:SetWidth(LEFT_W)
    self.search = W:Search(left, LEFT_W - 6, function(text) S:SetQuery(text) end, "Search settings")
    self.search:SetPoint("TOPLEFT", 6, -2)
    self.cats = {}
    for i, page in ipairs(PAGES) do
        local b = CategoryButton(left, page)
        b:SetPoint("TOPLEFT", 0, -30 - (i - 1) * 36)
        b:SetPoint("RIGHT")
        self.cats[i] = b
    end
    local hint = W:Label(left, "GameFontHighlightSmall", "Type |cffffd100/tfl|r in chat for every command.")
    hint:SetPoint("BOTTOMLEFT", 4, 4)
    hint:SetPoint("BOTTOMRIGHT", -4, 4)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.6, 0.6, 0.6)

    -- Right: the page
    local right = W:Panel(f, 0.55)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", ground, "BOTTOMRIGHT", -10, 10)
    self.right = right
    f.pageIcon = W:Icon(right, 30)
    f.pageIcon:SetPoint("TOPLEFT", 14, -12)
    f.pageTitle = W:Label(right, "GameFontNormalLarge")
    f.pageTitle:SetPoint("TOPLEFT", 54, -12)
    f.pageIntro = W:Label(right, "GameFontHighlightSmall")
    f.pageIntro:SetPoint("TOPLEFT", 54, -32)
    f.pageIntro:SetPoint("TOPRIGHT", -14, -32)
    f.pageIntro:SetJustifyH("LEFT")
    f.pageIntro:SetTextColor(0.75, 0.75, 0.75)

    local footer = CreateFrame("Frame", nil, right)
    footer:SetPoint("BOTTOMLEFT", 8, 8)
    footer:SetPoint("BOTTOMRIGHT", -8, 8)
    footer:SetHeight(24)
    self.reset = W:Button(footer, "Reset this page", 140, 22, function() S:PressReset() end,
        "Reset this page", "Puts every setting on this page back as it came. Press twice.")
    self.reset:SetPoint("RIGHT")
    f.pageCount = W:Label(footer, "GameFontHighlightSmall")
    f.pageCount:SetPoint("LEFT", 4, 0)
    f.pageCount:SetTextColor(0.7, 0.7, 0.7)

    local list = W:VList(right, MakeRow, FillRow)
    list:SetPoint("TOPLEFT", 4, -54)
    list:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -14, 6)
    self.list = list

    self.pageKey = self.pageKey or PAGES[1].key
    return f
end

function S:Page(key)
    for _, p in ipairs(PAGES) do if p.key == key then return p end end
end

function S:Searching() return (self.query or ""):match("%S") ~= nil end

-- Draw the page (or the search) again; keep says where you were scrolled stays put
function S:Refresh(keep)
    local f = self.frame
    if not f then return end
    local page = self:Page(self.pageKey) or PAGES[1]
    local searching = self:Searching()
    for _, b in ipairs(self.cats) do
        local on = not searching and b.page == page
        b.sel:SetShown(on)
        if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.85, 0.85, 0.85) end
    end
    local rows = self:Rows(page.key, self.query)
    for _, r in ipairs(rows) do r.h = Height(r) end
    if searching then
        f.pageIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        f.pageTitle:SetText("Search")
        local n = Count(rows)
        f.pageIntro:SetText(n == 0 and ("Nothing matches \"%s\". Try a shorter word, like \"sound\" or \"map\"."):format(self.query)
            or ("Settings matching \"%s\", from every page."):format(self.query))
        f.pageCount:SetText(n == 1 and "1 setting" or (n .. " settings"))
        self.reset:Hide()
    else
        f.pageIcon:SetTexture(page.icon)
        f.pageTitle:SetText(page.title)
        f.pageIntro:SetText(page.intro)
        f.pageCount:SetText("")
        self.reset:Show()
    end
    self.list:SetItems(rows, keep)
    self.rows = rows
end

function S:Show(key)
    self:Build()
    if key and self:Page(key) then self.pageKey = key end
    if self:Searching() then
        self.query = ""
        if self.search then self.search:SetText("") end
    end
    self.armed = nil
    if self.reset then self.reset:SetText("Reset this page") end
    self.frame:SetScale(ns.db and ns.db.scale or 1) -- the same size as the journal
    if not self.frame:IsShown() then self.frame:Show() end
    self:Refresh()
end

function S:SetQuery(text)
    text = strtrim and strtrim(text or "") or (text or "")
    if text == (self.query or "") then return end
    self.query = text
    if self.frame then self:Refresh() end
end

-- Reset asks twice: the first press arms it for a few seconds
function S:PressReset()
    local page = self:Page(self.pageKey)
    if not page then return end
    if not self.armed then
        self.armed = GetTime()
        self.reset:SetText("Press again to reset")
        C_Timer.After(4, function()
            if self.armed and GetTime() - self.armed >= 3.9 then
                self.armed = nil
                self.reset:SetText("Reset this page")
            end
        end)
        return
    end
    self.armed = nil
    self.reset:SetText("Reset this page")
    self:ResetPage(page)
    MF:Print(("%s settings are back as they came."):format(page.title))
    self:Refresh(true)
end

function S:Toggle(key)
    if self.frame and self.frame:IsShown() and not key then self.frame:Hide() return end
    self:Show(key)
end
