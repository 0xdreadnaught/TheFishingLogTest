-- News: what changed, shown once, the first time you log in on a new version.
--
-- An addon can't read its own changelog file - there's no file access - so
-- the notes live here as data. Keeping them short is the point: this is the
-- thing people see before they've asked for it, and nobody reads a wall of
-- text that appeared on its own. The full version stays on CurseForge.
--
-- Everything you've missed is shown, not just the newest version, because
-- someone who updates once a fortnight skips releases and would otherwise
-- never learn what changed in them.
local _, MF = ...

local SHOW_DELAY = 8   -- seconds after login; behind the claim prompt and welcome
local WIDTH = 480
-- Keep the window inside the screen; its reading area scrolls independently
-- of the title and footer so every included release remains accessible.
local MAX_HEIGHT = 620
local SIDE = 22

-- `released` is the day it went out, UTC. Eligibility.lua counts a week
-- from it before a version two releases older stops counting, so every
-- release from 1.0.6 on needs one.
--
-- Newest first. Two or three lines a release: what changed, why anyone
-- should care, and who found it. Anything longer belongs in the changelog
-- proper.
--
-- The third field is the player who reported it, and it is worth the room.
-- A name in the changelog is read by nobody; a name here is read by the
-- person who sent the report and by everyone wondering whether sending one
-- is worth the trouble.
MF.NEWS = {
    { v = "1.1.4", released = "2026-11-27", items = {
        { "Goals, rebuilt: up to three at once.",
          "Each goal has a progress bar and where to fish it, with new kinds (a grade, a whole zone, a skill, a bounty podium), suggestions from your own log, and a tracker under your quest log." },
        { "Settings in a window of their own, with key bindings.",
          "Every setting on short pages with a search box, and a Key bindings page for casting, the lure, the journal and more." },
        { "Find waters and Fishing here, redrawn.",
          "Find waters lists zones by how well they suit you, with catch rates and where to stand. Fishing here is a dashboard for the water you're at." },
        { "Bounties show the fish, and bloated fish count.",
          "Hover a standing for the fish behind it. From 10 December bloated fish count in the collection bounties." },
        { "And a few fixes.",
          "Catches count with a vendor open, a keyboard cast key survives a reload, frenzy waters ripple on the Waters map, and zones list the fish with no home zone." },
    } },
    { v = "1.1.3", released = "2026-11-26", items = {
        { "Late for an event? You're still in it.",
          "Everyone signed up shows in the live standings until they arrive, and the host sends the match to anyone missing. Sign-ups stay open until the event ends: press Sign up late or Join match on its page. The host needs 1.1.3.", "Nightblood Wrynn" },
        { "Search the Realm tabs, and a rebuilt Frenzies tab.",
          "Find any angler or fish on Realm, or press Target to look up a player you see. Frenzies has search, a timeline, favourites and Remind me." },
        { "Matches show the fish, with a countdown you can't miss.",
          "Standings show each angler's fish, and the start and end count down 3, 2, 1 in the middle of the screen." },
        { "And a few fixes.",
          "Waters reported in other languages merge into the English ones, Waters map pins work again, and the channel notice at login is gone." },
    } },
    { v = "1.1.2", released = "2026-11-24", items = {
        { "Matches work outside a party.",
          "Unless you were grouped, nobody in a match saw anyone else's catches, so a 1v1 could end with no winner. Catches, scores and records now reach everyone in the match, and catches off one bobber all count. Everyone in the match needs 1.1.2." },
        { "Invite anglers to events.",
          "Press Invite on an event you're hosting or signed up for. They get a pop-up to sign up, and a new Invites tab in Events lists everything you've been invited to." },
        { "Trunks and bottles are finds.",
          "They're counted apart from junk on the board and in your Logbook. Casting with full bags now warns you, so a catch isn't lost in the loot window." },
        { "And a handful of fixes.",
          "Cancelled events stay cancelled, match invites from your party get through, invites from any angler are on by default (Options turns them off), and the wardrobe opens in front of the journal." },
    } },
    { v = "1.1.1", released = "2026-11-23", items = {
        { "Waters: your zone on a map.",
          "The Records tab is now Waters. Your zone is shown fully explored, with every known water pinned and the frenzy and King of each at a glance. Scroll to zoom, drag to move, and Show on map opens the world map there. History is now the Logbook, with Sessions, By spot and Reports, and the Realm podium shows the anglers' faces. Thanks again to Godfall, whose latest version these come from." },
        { "An error and odd records fixed.",
          "The Appearance options error at login is gone. Vials, a club and lures fished up no longer count as fish records, and any that did are cleared. The cog over your bobber is hidden, and Camper's Lure now works in the lure slot." },
        { "Smaller touches.",
          "Collection tiles and fish cards wear their grade's colour. The login recap is a banner above the journal instead of a page to click past. A new option hides the Frenzies and Pools buttons on the world map." },
    } },
    { v = "1.1.0", released = "2026-11-22", items = {
        { "A new look, thanks to Godfall.",
          "The journal, board, pop-ups and windows are redrawn in the game's own art, built in from Godfall's UI Rework - a big thank you to Godfall for making it and sharing it. Click a fish in your collection to open its card, Records has Here and Other spots tabs, and the Appearance page under The Fishing Log's options sets sounds, animations, sizes and alert time. If you had the separate UI Rework add-on, turn it off: it's built in now." },
        { "Events reach everyone.",
          "Public events, sign-ups and cancellations now travel by guild, group and whisper as well as the channel, which on Forever carries no addon messages. Anglers still on 1.0.8 can see your events but their sign-ups can't reach you; until they update, they can join your party or raid before it starts." },
        { "Ready for the realm change.",
          "Forever's next hotfix hides realm names from addons. TFL now remembers each character's realm, so your records and bounty scores stay yours. Log in each of your characters once on 1.1.0 before the hotfix." },
        { "Lures, volume and more.",
          "Right-click the lure button for a menu of every lure you carry. A volume button sits on the board (/tfl volume), Louder splash works harder, Higher or Lower can be switched off entirely, and the discovery channel joins again for anyone it said was full." },
    } },
    { v = "1.0.8", released = "2026-11-19", items = {
        { "Bounty boards fill again.",
          "Anglers in one guild can sit on different realms behind the scenes, and TFL's whispers were addressed to your realm rather than theirs, so they went nowhere. Record swaps and bounty sharing had quietly stopped. Whispers now arrive, your bounty score also goes to your guild, and each swap passes on the whole board rather than the top three. Anglers still on 1.0.7 can't whisper anyone, so ask your guild to update." },
        { "Higher or Lower.",
          "A game for flight paths, played with your own cards. One card shows your best weight; is the next fish's heavier or lighter? It can also be played on how many you've caught or how many waters. It's offered when a flight takes off, or type /tfl hl. Nothing is sent and it earns no XP; it keeps your best streak." },
        { "Posting an event, explained.",
          "The post-an-event form is rebuilt: pick the day, time and length from buttons, each format says how it's won, and a line at the foot reads the whole event back as a sentence before you post it." },
        { "Pop-ups open their card.",
          "Click a specimen, new card or King of the Spot pop-up to open that fish's card. Right-click still just dismisses it." },
        { "The skill your zone needs.",
          "The board's skill bar now shows the skill anglers have found the zone asks for, such as (here 225+), green when yours is enough. Hover it for how many fish you can expect to get away. Zones nobody has logged yet show nothing." },
        { "A switch for every sound.",
          "Specimens, records, ranks, cards, frenzies, bounties, matches and seasons each have their own sound switch under Play sounds. A volume you change while TFL has the splash turned up is now kept, and /tfl restoresound puts your sound and music back if they ever stick." },
        { "Alongside another fishing addon.",
          "If another fishing addon also offers a cast key or catch messages, the two now agree on which one does it, and its warning that the bobber landed out of reach is shown with your catches." },
        { "Old versions stop counting.",
          "A version two releases behind stops counting for shared scores a week after the second of those came out. Its catches still go in that angler's own log; they just don't reach anyone else's records, bounties or matches. If yours is too old, the board says so." },
        { "Windows come to the front.",
          "A window opened over the journal could draw through it. Whichever you opened or clicked last now sits on top." },
    } },
    { v = "1.0.7", released = "2026-11-15", items = {
        { "The season send-off counts your records.",
          "When a season ends you're told what you finished with. Logging in after the month had turned would have said 0 season records whatever you held, because the old month's tables were emptied before they were counted. Each water now keeps the month that just ended through the month after it, so every character on the account gets a true count." },
        { "Last season's board.",
          "When the month turns, the Realm tab's season board used to go blank. Once a month has ended, the season button steps through this season, last season and all time, so you can see how it finished. It is your client's copy of the board as it stood, and nothing is awarded for it." },
        { "Diagnostics you can copy.",
          "/tfl diag now opens in a box you can copy from, ready to paste into a bug report. /tfl diag chat prints it to chat as before." },
    } },
    { v = "1.0.6", released = "2026-11-15", items = {
        { "Cards, redrawn.",
          "Every card now wears its edition: the border, a wash behind the art and a glow around it all take its colour. Pips under the name show how far up the grades you are and what weight the next one needs, the realm record is a bar you can see yourself closing in on, and the details are grouped into your best, history and native waters. Fish you haven't caught show as a silhouette, and a card's lore sits in its own box at the foot." },
        { "The angler hook actually shows.",
          "The gold hook on fellow anglers' nameplates never appeared: two-word names didn't match how the game reports them, and the question that confirms a nearby angler never reached them. It now shows beside the name of anyone whose TFL messages you've had in the last three days, with Blizzard's nameplates or an addon's such as EllesmereUI." },
        { "Spot anglers with nameplates off.",
          "The gold hook now also leads fellow anglers' chat, and sits beside their name on your target frame - Blizzard's or a unit-frame addon's. Each has its own switch in Options > AddOns > The Fishing Log, and the chat hook can be turned off for one kind of chat and kept for the rest - there, or with /tfl chathook guild off." },
        { "Tidier pool maps.",
          "A pool spawn point picks a different school each time it comes back, so one stretch of shore used to be a pile of pins. Each spot is now one pin showing its newest school, with a count when more than one has been seen there and the full list on hover. Duplicate sightings of the same school are merged by distance in yards, and your saved atlas is tidied once to match." },
        { "Whispers reach two-word names.",
          "Messages TFL sent straight to one angler - asking who's an angler nearby, nearby catches, direct pool and census requests - were addressed without the realm, which the server accepts and then never delivers for a name with a space in it. They now arrive." },
        { "Trophy fish keep their names.",
          "A record held with a fish your game hadn't seen yet - another angler's 25 Pound Salmon, say - showed as \"Item 13904\". Every trophy and bloated fish now has its name built in, and any name the game gives is remembered between sessions, in the log, on cards and in the Discord export." },
        { "A new frenzy water in Tanaris.",
          "North of Steamwheedle Port, at 67.3, 18.5." },
    } },
    { v = "1.0.5", items = {
        { "Find waters that suit your skill.",
          "TFL now learns how often fish get away at each skill in each zone, from your own casts and other anglers'. Where can I fish? uses it: Suitable for me, the skill preview and /tfl escapes all show what that skill can reliably land." },
        { "49 more frenzy waters.",
          "Community discoveries across Hillsbrad, the Wetlands, Arathi, Dustwallow, Alterac, Silverpine, Feralas, Redridge and more are now in the frenzy catalogue - including the first eight in Riverglades, the first in Thunder Bluff and the first reported by Horde anglers. Frenzy discoveries are now swapped with anglers found through the realm-wide angler list too, not only your guild and group." },
        { "Pools point the way to new frenzy waters.",
          "Busy pool waters with no frenzy water nearby now appear in the Frenzy List's discoveries under Suggested by pool sightings. They're places to go and fish, not approved waters. Shared pools now remember which anglers saw them first-hand and on which side; /tfl pools horde or /tfl pools alliance shows what each side has found." },
        { "Help map Forever's new waters.",
          "/tfl report now builds a copyable survey of everything you catch in zones TFL has no fish data for yet. Paste it on the Discord so those fish can be added." },
        { "Spot fellow anglers.",
          "A small gold hook marks player nameplates after recent confirmed TFL contact. Turn it off in Options > AddOns > The Fishing Log." },
        { "One error no longer stops the rest.",
          "If any part of the addon hits a problem, your catch is still logged, matches still score and your sound settings are still put back. The error is reported instead of silently breaking everything after it." },
        { "Your sound always comes back.",
          "The louder splash now remembers your own volume in saved data, so a crash or disconnect mid-cast can no longer leave it raised." },
        { "Two-word names count once.",
          "Anglers whose names contain a space are recognised however their name arrives, so they appear once in match standings and event sign-ups, and their cancels and results are accepted." },
        { "A quieter first login.",
          "New installs no longer create TFL Save macros or report beta progress being cleared when there was none." },
        { "Shared data is harder to spam.",
          "Only an event's host can change or close it. Shared pool locations expire after 60 days, one angler can add only so many, and a skill-curve range appears once two anglers agree. Skill notes you share are now only your own, and anglers on older versions - who all pass on the same merged copy - count as one voice between them. Pool requests get one answer instead of one from everybody, and record books are swapped at most every two minutes." },
    } },
    { v = "1.0.4", items = {
        { "Double-right-click to cast and reel.",
          "Works with key-down or key-up casting and respects clickable UI when OPie is enabled.", "Toggsy" },
        { "Bobber sparkles get help automatically.",
          "When needed, TFL temporarily enables the interaction settings used by the highlight and restores them after the cast." },
    } },
    { v = "1.0.3", items = {
        { "Spot specimen catches in bounty standings.",
          "Specimen icons now appear consistently on bounty weights, haul entries and previous winners. On a haul total, the icon means it contains a specimen. Older weights qualify only when they exceed the applicable ordinary-catch ceiling; unknown overlapping scores stay unmarked." },
        { "Census follows quiet sync.",
          "Census and diagnostics show recent confirmed contacts, not a claimed complete online count. Route tests and pool refresh can contact recent peers directly. Targeted sync and match invites use full player names." },
        { "Discovery reconnects after a failed join.",
          "Channel joining retries with a backoff and recovers lost membership. /tfl sync retries too. Status explains missing membership or a full channel list instead of indefinitely asking you to wait after login." },
        { "See your fishing bobber more clearly.",
          "Rising bubbles and bright gold glints highlight the fishing bobber while casting, enabled by default. Turn it off in Fishing options or /tfl bobber off. Optional interaction assistance can help when it is missing. Reduced motion uses steady gold glints." },
        { "More reliable bounty settlement.",
          "Solo quiet sync can request previous-period scores and waits for a completed peer reply before starting its reward window. Results remain based on your known shared board." },
        { "Clearer reviews and shared progression.",
          "Frenzy discoveries show approval or rejection and open their map when clicked. XP rows refresh on received progression, show formatted totals and explain sample age on hover. Restored translated water names." },
        { "More approved frenzy waters.",
          "Added the community-qualified Hillsbrad point and thirteen manually reviewed access points across Arathi, Hillsbrad, Elwynn, Westfall, Duskwood and Redridge. Each uses the usual 25-yard radius and timed schedule." },
        { "See the angler XP leaderboard.",
          "Choose XP leaderboard on the Realm tab for player names, titles and lifetime XP, highest first. Filter to your guild. Quiet sync shares progression; unknown XP is excluded." },
        { "Choose your fishing chat tab.",
          "Open /tfl config and choose Chat output to send TFL messages and reports to an existing chat tab. Changes apply immediately; unavailable tabs fall back to the default window.", "Nuibbles" },
    } },
    { v = "1.0.2", items = {
        { "More complete quiet sync.",
          "Peer exchanges now include current bounty scores and pool sightings for your zone. Nearby Catches can reach a limited set of confirmed peers on the same map when both anglers have this version and nearby sharing enabled." },
        { "More reliable fishing controls.",
          "Repeat presses wait for a cast to start. Reeling avoids selected or soft-targeted NPCs, and early reel attempts keep your bobber. Shift double-right-click deliberately casts again." },
        { "A clearer Journal and map.",
          "The Journal header shows your version. Duplicate season rows are hidden when the holder and weight match. Right-drag either map layer button to move both; their position is saved." },
        { "Record and recap fixes.",
          "Confirmed translated water names share a leaderboard, and shared names keep complete UTF-8 characters. Recap refresh uses quiet discovery. /tfl diag shows scan replies, imported data and send refusals." },
    } },
    { v = "1.0.1", items = {
        { "Live sync hotfix.",
          "Automatic sync uses the channel roster to find anglers and exchanges records through addon whispers. Existing catches and records are kept." },
    } },
    { v = "1.0.0", items = {
        { "Remember your first catch.",
          "New fish cards keep the date and water of your first catch separately from your personal best. Older catches without a recorded date remain unknown." },
        { "Know what happened to each cast.",
          "Hover the panel's fish count or open Fishing here for landed, escaped, interrupted and unknown cast totals. Early clicks keep waiting. Brief result messages can be disabled in Options." },
        { "A few keepsakes for your Album.",
          "Fishing finds tracks bottles, chests and trunks caught while fishing. Open Album, then View fishing finds. They stay separate from weighed fish and trophy cards." },
        { "Find your next fishing water.",
          "Open Find waters in the Journal, Fishing here or on a fish card. Filter fish you still need, follow personal water records, and distinguish your catches from reference guidance. Unknown fishing requirements stay marked unknown." },
        { "Ready for the fresh realm.",
          "Tightened backup recovery and shared-data checks. Fixed casting-key refreshes, month-boundary XP, midnight event defaults and joining hosts by their full name." },
        { "A completely clean launch on 4 November.",
          "At 00:00 UTC, beta progress, records, locations, outfits, settings, archives and save macros are cleared. No beta undo is kept. Old beta saves and shared messages cannot restore that data on the live realm. Each character resets on first login after launch." },
        { "City bounties ask for city fish.",
          "Corrected the daily city fish lists, including Darnassus asking for coastal mackerel. Daily periods starting 24 October UTC use the corrected lists; earlier results keep their original targets. Update together for matching standings." },
        { "Frenzies have fixed fishing-access areas.",
          "The catalogue now contains 35 locations with small 25-yard access areas, including additional record-backed lakes. Map pins work on a fresh log. Bonuses, alerts and panel effects use the same location rules; whole-zone and grid fallbacks no longer activate frenzies." },
        { "Help discover unnamed waters.",
          "Open /tfl frenzies. Three character anglers making five successful fishing casts each earns an unnamed water a review listing. It stays inactive until approved for a catalogue update. Use Copy review to share the evidence." },
        { "Keep fishing after finishing a quest.",
          "Fixed a stuck quest-interaction flag rejecting genuine catches after the quest window closes. Quest rewards remain excluded from fishing progress." },
        { "Remember when you landed your best.",
          "Fish cards now show the date and local time of the personal-best catch where a matching saved timestamp exists. Shared cards carry the catch time separately from the snapshot time. Older catches without a reliable timestamp say Date not recorded. Dated shared cards need 1.0.0 to open; older card links still work." },
    } },
    { v = "0.11.1", items = {
        { "All your card-sharing options, in one update.",
          "This build includes Guild, Whisper, Party and numbered-channel sharing, plus the fix for an empty chat box. Open a card, choose Share and press Enter in chat to send. Other players need the updated build to open party and channel card links." },
    } },
    { v = "0.11.0", items = {
        { "Your fishing outfit, ready to wear.",
          "Save an outfit in the Angler's Wardrobe, equip it and restore your previous gear. Open /tfl outfit or right-click the fishing panel's pole button." },
        { "Check your tackle before you cast.",
          "Use /tfl tackle to check skill, lures, fishing food and saved gear. Lures show requirements and durations; selection checks your base skill and supports the equipped fishing hat's reusable lure." },
        { "Get to know the local waters.",
          "Use /tfl waters to browse known locations, personal catches, spot records and active frenzies. Location confidence is shown clearly; your records are preserved when bad map positions are set aside." },
        { "Share your favourite cards.",
          "Share cards through Guild, Whisper, Party or a joined numbered channel such as General or Trade. Choose the destination, then press Enter to send. Fixed the empty chat box when preparing a card message. Both players need this update." },
        { "Keep a report of the afternoon.",
          "Copy a full session report or a short Discord post from History or /tfl sessionreport. Includes catches, weight, biggest fish and specimens. Nothing is sent automatically." },
        { "Clearer maps and fewer interruptions.",
          "Smaller pool markers, prominent frenzy markers and separate map size controls. Choose which pop-ups you want; frenzy arrival alerts wait until you leave a flight path. Reading windows share a solid dark finish." },
        { "More reliable catch logging.",
          "Improved early loot scans and recovery after opening clams or a missed mailbox-close event. Non-fishing receipts remain excluded. Corrected shared fishing locations appearing on unrelated maps." },
    } },
    { v = "0.10.8", items = {
        { "Choose a personal fishing goal.",
          "Track a missing card, specimen, best at this water or three-fish bounty haul. Use Goal in the Journal, Track goal on a card, or /tfl goal. Progress uses real catches, with no extra scoring bonuses." },
        { "Keep the afternoon in your History.",
          "Unfinished solo sessions now save a History summary when you log out or reload, without counting catches or XP twice." },
        { "Guild events stay in the guild.",
          "Private events use guild-only match traffic. Update participants together: older clients cannot run or join the new private matches. Equal match scores share places and finish as a draw." },
        { "Fair targets and complete nearby catches.",
          "New heaviest/count periods opening from 20 October use ordinary-fish targets; active bounties keep their rules. Nearby double catches no longer lose the second specimen." },
        { "Know what was saved and settled.",
          "Pool discoveries confirm when saved and report a full atlas. Recap shows saved bounty rewards. /tfl catchtrace copies recent catch-detection decisions." },
        { "More room to read.",
          "Options reflow to their panel width, pop-ups wrap long text, and these notes now scroll to show every change." },
        { "See when your water is in frenzy.",
          "The fishing panel gains an amber glow, warm tint and rising bubbles. Reduced motion keeps a steady glow without bubbles. Arrival pop-ups now work before starting a session." },
        { "Keep addon traffic on the right channel.",
          "Queued messages resolve and verify TheFishingLog at send time, even after channel reordering. Login joins wait for normal channels to load; zoning no longer schedules another join." },
        { "Catch every item from the bobber.",
          "Later loot scans pick up extra items, including trophy fish, without duplicates. Fishing casts remain recognised when the client has not supplied their spell name yet." },
        { "Oil spills belong on the atlas too.",
          "Both Oil Spill and Inland Oil Spill are recognised. Hover before casting; genuine loot, including junk, records and shares the location." },
        { "Quieter music while fishing.",
          "Equipping a pole mutes music and unequipping restores your volume. Enabled by default with a Fishing option; combat changes wait until combat ends." },
        { "Safer beta tooltips and targeting settings.",
          "Hardened tooltip handling for secret values and deferred protected targeting changes until combat ends. Hold Shift before hovering for expanded item details.", "Mayah Hawk" },
    } },
    { v = "0.10.7", items = {
        { "Bounty podiums now award XP.",
          "Daily: 150/100/50 XP; weekly: 750/500/250; monthly: 2000/1250/750. Ties share rewards. Results settle after shared standings sync, with protection against repeat payouts." },
        { "Fishing progress comes from fishing.",
          "Trades, mail, rewards, crafting and non-fishing loot are excluded from catch progress. Delayed receipts are guarded; fast loot and Luremaster double catches remain supported." },
        { "Quieter background syncing.",
          "Fixed offline-player errors escaping the addon whisper filter when background messages had waited in a busy queue." },
        { "Hear your specimens.",
          "Specimen catch pop-ups now use the store purchase-confirmation sound, including specimens caught as the second fish in a double catch." },
        { "Tell unnamed fishing spots apart.",
          "The Records list adds coordinates to generic zone labels. Click a spot to locate it; records remain separate." },
        { "Map controls stay on the map.",
          "Frenzies and Pools buttons now sit inside the map area, clear of the quest log in compact view." },
        { "Room for both fish.",
          "Floating catch notifications now play one after another when Luremaster gives two fish, keeping both weights and grades readable. Scoring and chat remain immediate." },
        { "Combat swaps need your click.",
          "Click Equip weapons or use your pole/weapon keybind when attacked. The pole returns after combat if enabled." },
    } },
    { v = "0.10.6", items = {
        { "Luremaster's extra fish gets its own weight.",
          "Every fish in stacked fishing loot now rolls independently, including its specimen chance. Both count towards your progress and competitions; duplicate loot reports are reconciled." },
        { "More ways to win a bounty.",
          "New rotations include three-fish hauls, combined weight, most specimens, species collections and zone challenges. Existing bounties keep their rules until reset; new formats can start from 17 October UTC. Update together for shared standings." },
        { "Fixed duplicate bounty standings.",
          "Names with different beta realm suffixes now share one standing, keeping the highest score without adding duplicate monthly totals." },
        { "One record book for The Loch.",
          "Confirmed west/central lake fallback locations merge into The Loch, preserving realm and personal bests. School of Whimsyfin markers now use its fish icon." },
    } },
    { v = "0.10.5", items = {
        { "What changed since your last visit?",
          "/tfl recap compares saved records and bounty periods with the latest known peer data, plus your signed-up events. It can appear on the first Journal visit after login; missing information stays unknown." },
        { "More fishing guidance.",
          "Expanded city and selected zone fish lists, plus recognition of more wreckage and special pool types." },
        { "Your first specimen unlocks a foil card.",
          "A NEW SPECIMEN banner celebrates each species' first specimen. The Album keeps your Latest specimen at the top with its weight, water and catch time." },
        { "Prototype: fishing pools on both maps.",
          "Hover a named pool before casting; a catch records its approximate location. Anglers share their discoveries and save them in a pool atlas. Both maps work without GatherMate2. /tfl pools status checks the atlas." },
    } },
    { v = "0.10.4", items = {
        { "Less hunting, clearer details.",
          "Journal tabs remember your place, table tooltips label their statistics, and notifications wait their turn. Click a pop-up to advance to the next." },
        { "Know when the match is over.",
          "A match-over notification shows the winner and score, or No winner, for every participant." },
        { "Event standings belong in Events.",
          "Hosted and joined events open their live standings in the Journal. The small board keeps your lure, skill and frenzy information; its journal button returns to the event." },
        { "Match invites no longer wait behind record sync.",
          "Invites and match controls take priority over background traffic. Live match catches and scores also move ahead of bulk sync, within the same server throttle limits." },
        { "A tidier fishing board and Here page.",
          "Fishing here stays compact in narrow windows. The board has clearer King details, skill bonuses and footer text. New spot bests remember specimen status." },
        { "More reliable nearby catch sharing.",
          "Nearby anglers can share catches even when their fishing spot names differ. Live catches take priority over record sync and also use guild and party routes. /tfl nearby status helps diagnose missing reports." },
    } },
    { v = "0.10.3", items = {
        { "Search your journal, or find something to chase here.",
          "Search fish names or zones and filter missing species or specimens. The Here button, /tfl here, or a right-click on the board's journal icon brings together local bests, record gaps, relevant bounties and frenzy timing." },
        { "A clearer journal, sized to suit you.",
          "A solid background, collection summary and aligned statistics make it easier to read. Drag the bottom-right corner to resize; /tfl journalsize resets it. Board is now called Events." },
        { "Fixed: duplicated bounty names and purchased catches.",
          "Different spellings of one angler now share one standing. Buying items while fishing no longer feeds the chat catch fallback or awards catch XP.", "Erik Lightfuryl" },
        { "Full backups and stronger progress checks.",
          "/tfl export now includes your complete character log, with confirmation and undo when restoring. Macro saves retry on failure, impossible match snapshots are refused, and the wipe checks every character separately." },
    } },
    { v = "0.10.2", items = {
        { "Fixed: anglers who logged off vanished from the standings.",
          "Everyone else's score was held in memory only, and asking the realm for it again only reaches people who are online to answer - so a bounty you led in the evening had nobody on it by bedtime. Standings are kept now, and whoever answers sends the whole board rather than just their own line." },
        { "The board steps out of the way for a fight.",
          "It used to sit there through the whole thing, and the X only produced \"Interface action failed because of an AddOn\" - the secure buttons on it make the board protected, and nothing may hide one of those in combat. It goes when the fight starts and comes back when it ends, counting the whole time.",
          "Mayah Hawk" },
        { "Fixed: swapping back from your pole gave only your main hand.",
          "If you dual wield two of the same weapon, the addon asked for your off-hand by what it is - and the game found the one already in your main hand and did nothing. It takes the right one out of your bag now. A failed swap also used to forget the off-hand for good, so every swap after it gave back the main hand alone.",
          "Foom Blex" },
        { "Fixed: a catch in one of the new dungeons vanished.",
          "It waits a few seconds while the realm is asked what records stand there - and a dungeon the client has no map for can't be asked about, so nothing ended the wait. No record, no Realm tab, no XP, and nothing said. Your journal and personal bests were never affected." },
        { "Dungeons keep records of their own.",
          "Every place the client can't map was filed as one spot, so two dungeons would have shared a record book. Each is its own now, named for the dungeon rather than the room. Anglers still on 0.10.1 won't see these until they update." },
    } },
    { v = "0.10.1", items = {
        { "Bounties remember who won the last one.",
          "Name, what it was for and what they took it with, on each of the three tabs - and clients swap the result, so logging in after a rollover still tells you." },
        { "Time fished no longer counts time away.",
          "A log ran on the wall clock, so one cast and an hour away was an hour on the board - and the board reads fish an hour. It counts while you're fishing and stops shortly after you stop." },
    } },
    { v = "0.10.0", items = {
        { "Bounties are daily, weekly and monthly.",
          "Daily is heaviest of a fish in one zone, drawn for your side of the realm; weekly is heaviest anywhere; monthly counts catches instead of weighing them. And they land where people actually fish now - more than half used to pick a zone nobody levels through, which is why the standings were always empty." },
        { "Fixed: frenzy marks you couldn't see.",
          "On about half the maps they were there, in the right place, and invisible - the map decides what sits above what, and a mark hung on it by hand ends up underneath. Drawn the map's own way now." },
        { "Fixed: duplicate spots came back while you played.",
          "A reload cleared them and an hour's fishing put them back, because the folding only ran at login. Copies are folded as they arrive now, so a cleared board stays cleared." },
    } },
    { v = "0.9.0", items = {
        { "New: feeding frenzies show on the world map.",
          "Any water in frenzy right now is marked on the zone you're looking at, with how long it has left. Zones you've fished yourself only. |cffffd100/tfl mappins|r turns them off.",
          "Mayah Hawk" },
        { "Fixed: the last of the duplicate spots.",
          "They were being folded by distance, and each copy arrived with wherever its sender was standing - so one water could read as thirteen scattered ones. A water nobody can name is now folded on its zone instead. They go on this login." },
        { "New: a card for every fish - |cffffd100Album|r on the Journal tab.",
          "47 cards, one a species. Specimens catch the light. A card turns over the first time you land that fish and its edition is your best one so far, up to Specimen. Each one carries the realm's heaviest and who holds it. Clears with your character on 4 November, so everyone starts the album together." },
        { "Fixed: a fight could cost you the camera.",
          "Right-click stayed bound to casting if something attacked you mid-press, until the fight ended - which is when you most need to turn round.",
          "Mayah Hawk" },
    } },
    { v = "0.8.2", items = {
        { "Weights in kilograms, if you'd rather.",
          "A switch in the Interface options, or |cffffd100/tfl units|r. Only what you see changes - records are still kept and compared in pounds, so the board reads the same for everyone." },
        { "Fixed: records were breeding copies of themselves.",
          "Spots called things like |cffffd100n1431:1138521219|r, all holding the same fish. My fault, in 0.8.0 - they fold back into one on this login." },
        { "Running another fishing addon? Shared features coordinate.",
          "Casting, catch text and the bite sound were being done twice. Whichever of ours is on, theirs stands down - and comes straight back when you switch ours off." },
    } },
    { v = "0.8.1", items = {
        { "|cffffd100My guild|r on the Realm tab.",
          "The same standings with everyone outside your guild taken out - where you stand among the people you actually fish with, rather than among eighty strangers." },
        { "Records find their way to you now.",
          "Nobody ever relayed anyone else's ordinary records, so an angler who played while you slept was invisible - and two people could each believe they were first. Clients now fill in each other's gaps, and the Realm tab says whose board it is." },
        { "November is The Pre-Season.",
          "The realm opens on the 4th with everyone at nothing, so the first season is short and spent levelling. December is the first proper month." },
    } },
    { v = "0.8.0", items = {
        { "The Booty Bay contest no longer starts without you.",
          "Fifteen minutes' warning before the Extravaganza opens, and |cffffd100/tfl contest|r whenever you want to know how long you have." },
        { "Your fishing skill changes what you catch, and lures count.",
          "Skill lifts the bottom of every catch and never the top: at 225 the small ones have stopped biting, and the record is still anybody's. Your lure, gear and food all count towards it." },
        { "|cffffd100/tfl cast mouse2|r now means what you meant.",
          "It only answered to \"button2\", so asking for mouse2 bound nothing and said it had worked. A key it can't use no longer costs you the one you had.",
          "Mayah Hawk" },
    } },
    { v = "0.7.5", items = {
        { "Trophy fish are graded on their fraction.",
          "A 12.98 is the pick of the twelve pounders and a 12.01 a poor one. Until now nothing said so." },
        { "The Journal says how good your best is, not just how heavy.",
          "The grade used to be said once in chat and then gone. Now it sits beside every best you hold." },
        { "Single-press casting no longer costs you the camera.",
          "Right mouse keeps the double press whatever the setting says - it is the only way casting and turning can share a button. Any other key takes a single press.",
          "Mayah Hawk" },
        { "Right-click casting can pull the line in and cast again.",
          "A reach that catches nothing hands the button back to casting, instead of reaching at nothing until the channel runs out.",
          "Mayah Hawk" },
    } },
    { v = "0.7.4", items = {
        { "An older log could sit unclaimed without you knowing.",
          "If you were set back to Minnow when logs moved to characters, the Journal now offers it back.",
          "South African" },
        { "Your catch rises off the water, not just into the chat box.",
          "Icon, weight and grade, floating up the screen. |cffffd100/tfl float move|r puts it where you want it." },
        { "Every catch is graded against its own kind.",
          "A 4.59 lb grouper is a good one; a mud snapper that size would be a monster. Now it says which." },
        { "A leaderboard for the heaviest of each fish.",
          "One crown per species rather than per lake. |cffffd100By fish|r on the Realm tab, with the unclaimed ones listed." },
        { "A log follows you from one water to the next.",
          "It used to keep naming the lake you started at, and History credited every fish to it.",
          "Claudi Amburil" },
        { "The Pole button gives a dual wielder their off-hand back.",
          "A fishing pole is two-handed, so swapping back was always two steps - and the second one never happened." },
    } },
    { v = "0.7.3", items = {
        { "Things that were never fish have stopped holding records.",
          "Cloth, potions and sealed trunks were weighed by an early version. They're cleared out, and refused from now on." },
        { "|cffffd100/tfl report|r names anything odd still holding one.",
          "Nothing is deleted on a hunch. Send what it lists and it can be ruled out properly." },
    } },
    { v = "0.7.2", items = {
        { "Twenty ranks instead of six, from 4 November.",
          "Legend of the Deep was about thirty hours of fishing. The new ladder runs Fry to Legend over twenty titles." },
        { "The fishing skill bar counts your lure, your gear and your food.",
          "Hover it for a breakdown of where every point comes from." },
        { "Opening a crate no longer counts as catching a fish.",
          "Anything looted just after reeling in was being weighed and paid XP, crafting included.",
          "Mayah Hawk" },
        { "The biggest catch on the realm had stopped travelling.",
          "Record books were ordered newest-first, so the best fish anyone had seen aged off the end. Fixed." },
        { "Ready for the wipe on 4 November.",
          "The old realm is archived and cleared, and beta records are refused afterwards - so nobody starts with ghosts on their board." },
    } },
}

------------------------------------------------------------------------
-- Which versions are new to you
------------------------------------------------------------------------

local function Parts(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

-- Is a newer than b?
function MF:VersionNewer(a, b)
    local a1, a2, a3 = Parts(a)
    local b1, b2, b3 = Parts(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

-- Every release newer than `since`, newest first. With no `since`, just the
-- one we're running: a player whose addon has never recorded a version is
-- not owed the whole history.
function MF:NewsSince(since)
    local out = {}
    for _, release in ipairs(self.NEWS) do
        if since then
            if self:VersionNewer(release.v, since) then out[#out + 1] = release end
        elseif release.v == self.Version() then
            out[#out + 1] = release
        end
    end
    return out
end

------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------

local panel

local function CreatePanel()
    panel = MF:CreatePanel("TheFishingLogNews", WIDTH, MAX_HEIGHT,
        { strata = "DIALOG", movable = true, escCloses = true, fill = MF.FILL_READING,
          title = true, close = true })
    panel:SetPoint("CENTER", 0, 60)

    panel.rows = {}
    panel.done = MF:CreateButton(panel, "Thanks", 110, function() panel:Hide() end)
    panel.done:SetPoint("BOTTOMRIGHT", -SIDE, 16)
    panel.journal = MF:CreateButton(panel, "Open the journal", 150, function()
        panel:Hide()
        MF:OpenJournal("journal")
    end)
    panel.journal:SetPoint("BOTTOMLEFT", SIDE, 16)
end

-- Rows are made as needed and kept, so reopening doesn't build them again.
local function Row(i, font)
    local row = panel.rows[i]
    if not row then
        row = MF:CreateText(panel.content, font, "TOPLEFT", 0, 0)
        row:SetWidth(WIDTH - SIDE * 2)
        row:SetJustifyH("LEFT")
        row:SetSpacing(2)
        panel.rows[i] = row
    end
    row:SetFontObject(font)
    return row
end

function MF:ShowNews(releases)
    if not releases or #releases == 0 then return false end
    if not panel then CreatePanel() end
    if not panel.scroll then
        panel.scroll = CreateFrame("ScrollFrame", nil, panel)
        panel.scroll:SetPoint("TOPLEFT", SIDE, -52)
        panel.scroll:SetPoint("BOTTOMRIGHT", -SIDE - 18, 54)
        panel.content = CreateFrame("Frame", nil, panel.scroll)
        panel.content:SetWidth(WIDTH - SIDE * 2 - 18)
        panel.scroll:SetScrollChild(panel.content)
        panel.bar = CreateFrame("Slider", nil, panel)
        panel.bar:SetOrientation("VERTICAL")
        panel.bar:SetWidth(12)
        panel.bar:SetPoint("TOPRIGHT", -SIDE, -52)
        panel.bar:SetPoint("BOTTOMRIGHT", -SIDE, 54)
        panel.bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        panel.bar:GetThumbTexture():SetSize(10, 32)
        panel.bar:GetThumbTexture():SetColorTexture(0.75, 0.65, 0.4, 0.85)
        panel.bar:SetScript("OnValueChanged", function(_, value) panel.scroll:SetVerticalScroll(value) end)
        panel.scroll:EnableMouseWheel(true)
        panel.scroll:SetScript("OnMouseWheel", function(_, delta)
            local _, maximum = panel.bar:GetMinMaxValues()
            panel.bar:SetValue(math.max(0, math.min(maximum or 0, panel.bar:GetValue() - delta * 40)))
        end)
    end
    panel.title:SetText(#releases == 1 and ("What's new in " .. releases[1].v) or "What's new since you last played")
    local y, n = 0, 0
    local function Add(font, text, gap)
        n = n + 1
        local row = Row(n, font)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        row:SetWidth(WIDTH - SIDE * 2 - 18)
        row:SetText(text)
        row:Show()
        y = y - row:GetStringHeight() - gap
    end
    for _, release in ipairs(releases) do
        if #releases > 1 then Add("GameFontNormal", release.v, 8) end
        for _, item in ipairs(release.items) do
            Add("GameFontHighlight", item[1], 2)
            Add("GameFontHighlightSmall", item[2], item[3] and 2 or 12)
            if item[3] then Add("GameFontDisableSmall", "Spotted by " .. item[3], 12) end
        end
    end
    for i = n + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.content:SetHeight(-y + 4)
    panel:SetHeight(math.min(MAX_HEIGHT, math.max(200, -y + 110)))
    local maximum = math.max(0, -y + 4 - (panel:GetHeight() - 106))
    panel.bar:SetMinMaxValues(0, maximum)
    panel.bar:SetValue(0)
    panel.bar:SetShown(maximum > 0)
    panel:Show()
    return true
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- When it appears
------------------------------------------------------------------------

MF:On("TFL_LOGIN", function(self)
    local now = self.Version()
    local seen = self.db.lastVersion
    self.db.lastVersion = now
    if seen == now then return end

    -- Somebody's first ever login gets the welcome, not a list of things
    -- that changed before they arrived.
    if not seen and self:IsNewAngler() then return end

    C_Timer.After(SHOW_DELAY, function()
        if not self:ShowNews(self:NewsSince(seen)) then return end
        self:Print(("Updated to |cffffd100%s|r. |cffffd100/tfl news|r shows what changed.")
            :format(now))
    end)
end)

MF:Command({ "news", "changelog" }, "Other", "/tfl news - what changed in this version",
    function(self)
        if self:ShowNews(self:NewsSince()) then return end
        self:Print(("No notes for %s."):format(self.Version()))
    end)
