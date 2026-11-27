-- Fish data and weight rolls.
local _, MF = ...

-- Zone groups, used for "native waters". Specimens can only be caught in a
-- fish's native zones. Best-guess vanilla data - tune freely.
local STARTER = { "Elwynn Forest", "Dun Morogh", "Tirisfal Glades", "Durotar", "Mulgore", "Teldrassil" }
local LOW_COAST = { "Durotar", "Teldrassil", "Darkshore", "Westfall", "The Barrens", "Silverpine Forest" }
local LOW_INLAND = { "Loch Modan", "Silverpine Forest", "Westfall", "Redridge Mountains", "The Barrens",
    "Darkshore", "Duskwood", "Hillsbrad Foothills", "Ashenvale", "Wetlands" }
local MID_INLAND = { "Duskwood", "Hillsbrad Foothills", "Wetlands", "Ashenvale", "Stonetalon Mountains",
    "Thousand Needles", "Redridge Mountains", "Alterac Mountains", "Arathi Highlands" }
local MID_COAST = { "Wetlands", "Arathi Highlands", "Hillsbrad Foothills", "Desolace",
    "Stranglethorn Vale", "Dustwallow Marsh" }
local HIGH_MID = { "Stranglethorn Vale", "Swamp of Sorrows", "Arathi Highlands", "Dustwallow Marsh",
    "Desolace", "Feralas" }
local HIGH_COAST = { "Stranglethorn Vale", "Feralas", "Tanaris", "Azshara", "The Hinterlands" }
local HIGH_INLAND = { "Feralas", "The Hinterlands", "Un'Goro Crater", "Felwood", "Western Plaguelands",
    "Eastern Plaguelands", "Winterspring", "Moonglade", "Azshara" }
local COLD = { "Winterspring", "Eastern Plaguelands", "Western Plaguelands", "Burning Steppes",
    "Silithus", "Moonglade" }
local STV = { "Stranglethorn Vale" }

-- min/max: normal weight range (lb). specMin/specMax: the rare specimen range
-- (defaults to 1.3x-2x max). night/day: heavier at that time of day.
MF.FISH = {
    [6291]  = { name = "Raw Brilliant Smallfish", min = 0.2, max = 1.5, zones = STARTER },
    [6303]  = { name = "Raw Slitherskin Mackerel", min = 0.3, max = 1.8, zones = LOW_COAST },
    [6289]  = { name = "Raw Longjaw Mud Snapper", min = 0.5, max = 3.0, zones = LOW_INLAND },
    [6317]  = { name = "Raw Loch Frenzy", min = 0.8, max = 3.5, zones = { "Loch Modan" } },
    [6522]  = { name = "Deviate Fish", min = 0.5, max = 2.5, specMin = 4, specMax = 7, zones = { "The Barrens" } },
    [6358]  = { name = "Oily Blackmouth", min = 1.0, max = 6.0,
        zones = { "Westfall", "The Barrens", "Darkshore", "Wetlands", "Silverpine Forest", "Hillsbrad Foothills" } },
    [6361]  = { name = "Raw Rainbow Fin Albacore", min = 1.0, max = 5.0,
        zones = { "Westfall", "Darkshore", "The Barrens", "Wetlands" } },
    [6308]  = { name = "Raw Bristle Whisker Catfish", min = 1.5, max = 7.0, specMin = 12, specMax = 20, zones = MID_INLAND },
    [6359]  = { name = "Firefin Snapper", min = 1.5, max = 6.5, zones = MID_COAST },
    [6362]  = { name = "Raw Rockscale Cod", min = 2.0, max = 8.0,
        zones = { "Stranglethorn Vale", "Desolace", "Dustwallow Marsh", "Arathi Highlands", "Tanaris" } },
    [21071] = { name = "Raw Sagefish", min = 1.0, max = 5.0,
        zones = { "Hillsbrad Foothills", "Ashenvale", "Stonetalon Mountains", "Wetlands" } },
    [21153] = { name = "Raw Greater Sagefish", min = 2.0, max = 9.0, zones = HIGH_MID },
    [8365]  = { name = "Raw Mithril Head Trout", min = 2.0, max = 9.0, zones = HIGH_MID },
    [4603]  = { name = "Raw Spotted Yellowtail", min = 3.0, max = 12.0, zones = HIGH_COAST },
    [13422] = { name = "Stonescale Eel", min = 2.0, max = 10.0, specMin = 16, specMax = 25, zones = HIGH_COAST },
    [13754] = { name = "Raw Glossy Mightfish", min = 3.0, max = 14.0, zones = HIGH_COAST },
    [13755] = { name = "Raw Winter Squid", min = 2.0, max = 10.0, specMin = 18, specMax = 30, zones = HIGH_COAST, night = true },
    [13756] = { name = "Raw Summer Bass", min = 3.0, max = 12.0, zones = HIGH_COAST, day = true },
    [13758] = { name = "Raw Redgill", min = 3.0, max = 13.0, zones = HIGH_INLAND },
    [13759] = { name = "Raw Nightfin Snapper", min = 3.0, max = 13.0, zones = HIGH_INLAND, night = true },
    [13760] = { name = "Raw Sunscale Salmon", min = 3.0, max = 13.0, zones = HIGH_INLAND, day = true },
    [13889] = { name = "Raw Whitescale Salmon", min = 4.0, max = 15.0, zones = COLD },
    [13888] = { name = "Darkclaw Lobster", min = 1.0, max = 6.0, specMin = 9, specMax = 14, zones = HIGH_COAST },
    [13893] = { name = "Large Raw Mightfish", min = 8.0, max = 40.0, specMin = 55, specMax = 90, zones = HIGH_COAST },

    -- Quest fish, each tied to the water it's named after.
    [12238] = { name = "Darkshore Grouper", min = 1.0, max = 6.0, zones = { "Darkshore" } },
    [16967] = { name = "Feralas Ahi", min = 3.0, max = 12.0, zones = { "Feralas" } },
    [16968] = { name = "Sar'theris Striker", min = 3.0, max = 12.0, zones = { "Desolace" } },
    [16969] = { name = "Savage Coast Blue Sailfin", min = 4.0, max = 15.0, zones = STV },
    [16970] = { name = "Misty Reed Mahi Mahi", min = 3.0, max = 12.0, zones = { "Swamp of Sorrows" } },
    [19975] = { name = "Zulian Mudskunk", min = 3.0, max = 12.0, zones = STV },

    -- The Stranglethorn Fishing Extravaganza's own fish.
    [19807] = { name = "Speckled Tastyfish", min = 1.0, max = 4.0, zones = STV },
    [19803] = { name = "Brownell's Blue Striped Racer", min = 5.0, max = 25.0, zones = STV },
    [19805] = { name = "Keefer's Angelfish", min = 5.0, max = 25.0, zones = STV },
    [19806] = { name = "Dezian Queenfish", min = 5.0, max = 25.0, zones = STV },
    [19808] = { name = "Rockhide Strongfish", min = 5.0, max = 25.0, zones = STV },

    -- Bloated fish have swallowed something, and it shows on the scales.
    [6643]  = { name = "Bloated Brilliant Smallfish", min = 1.0, max = 2.5, zones = STARTER },
    [6645]  = { name = "Bloated Mud Snapper", min = 2.0, max = 4.5, zones = LOW_INLAND },
    [6647]  = { name = "Bloated Bristle Whisker Catfish", min = 4.0, max = 9.0, zones = MID_INLAND },
    [8366]  = { name = "Bloated Mithril Head Trout", min = 5.0, max = 11.0, zones = HIGH_MID },
    [13881] = { name = "Bloated Redgill", min = 6.0, max = 15.0, zones = HIGH_INLAND },
    [13891] = { name = "Bloated Whitescale Salmon", min = 7.0, max = 17.0, zones = COLD },

    -- The rest of what bites. No zone list means it's at home anywhere.
    [13757] = { name = "Lightning Eel", min = 2.0, max = 10.0, zones = HIGH_COAST, night = true },
    [13890] = { name = "Raw Plated Armorfish", min = 3.0, max = 14.0, zones = HIGH_COAST },
    [6360]  = { name = "Steelscale Crushfish", min = 2.0, max = 8.0 },
    [1467]  = { name = "Spotted Sunfish", min = 0.5, max = 3.0 },
    [6458]  = { name = "Oil Covered Fish", min = 0.5, max = 3.0 },
    [6299]  = { name = "Sickly Looking Fish", min = 0.1, max = 0.8 },
}


-- Not everything that comes up on the hook is a fish. Chests and crates hold
-- armour, recipes and cloth, and the water itself gives up potions, gems,
-- pearls and the odd bottle of rum. Every one of them is listed here, taken
-- from Forever's own fishing loot table, because asking the client whether an
-- item is wearable turned out to call a catfish a boot. Anything that isn't
-- in the table at all is given the benefit of the doubt and weighed.
local NOT_FISH = {
    118, 727, 766, 768, 770, 774, 789, 804, 805, 818, 828, 856,
    857, 858, 865, 866, 929, 954, 955, 1180, 1206, 1210, 1438, 1478,
    1529, 1608, 1639, 1640, 1705, 1710, 1712, 1725, 1994, 2073, 2075, 2078,
    2079, 2140, 2318, 2319, 2406, 2407, 2409, 2447, 2455, 2553, 2555, 2598,
    2601, 2632, 2657, 2819, 2881, 2882, 2883, 2934, 2958, 2959, 2960, 2961,
    2962, 2963, 2964, 2965, 2966, 2968, 2970, 2971, 2972, 2973, 2974, 2975,
    2976, 2977, 2979, 2982, 2983, 2985, 2987, 2988, 2992, 2996, 2997, 3012,
    3013, 3036, 3037, 3039, 3040, 3042, 3055, 3057, 3065, 3067, 3184, 3187,
    3190, 3192, 3193, 3195, 3200, 3201, 3205, 3206, 3207, 3208, 3210, 3213,
    3214, 3385, 3395, 3396, 3430, 3531, 3609, 3610, 3612, 3641, 3643, 3647,
    3740, 3820, 3827, 3832, 3857, 3864, 3866, 3867, 3869, 3914, 3928, 4037,
    4041, 4049, 4059, 4062, 4064, 4071, 4072, 4076, 4089, 4234, 4294, 4299,
    4304, 4305, 4339, 4345, 4346, 4349, 4350, 4352, 4359, 4363, 4364, 4371,
    4377, 4382, 4387, 4408, 4409, 4410, 4496, 4500, 4560, 4561, 4562, 4563,
    4564, 4565, 4566, 4567, 4568, 4569, 4570, 4571, 4575, 4658, 4659, 4662,
    4663, 4665, 4666, 4677, 4678, 4684, 4690, 4695, 4697, 4698, 4699, 4700,
    4706, 4709, 4711, 4712, 4713, 4714, 4734, 4735, 5002, 5003, 5207, 5212,
    5213, 5498, 5500, 5572, 5573, 5574, 5575, 5576, 6149, 6211, 6266, 6268,
    6269, 6271, 6297, 6301, 6304, 6306, 6307, 6336, 6348, 6351, 6352, 6353,
    6354, 6355, 6356, 6357, 6378, 6379, 6380, 6381, 6387, 6388, 6389, 6391,
    6394, 6396, 6398, 6399, 6405, 6409, 6411, 6412, 6418, 6419, 6421, 6429,
    6455, 6456, 6457, 6470, 6506, 6507, 6508, 6509, 6510, 6512, 6513, 6514,
    6515, 6517, 6518, 6520, 6521, 6538, 6539, 6540, 6541, 6543, 6545, 6546,
    6548, 6549, 6551, 6552, 6553, 6554, 6555, 6556, 6557, 6558, 6559, 6560,
    6561, 6562, 6563, 6564, 6566, 6567, 6568, 6569, 6571, 6572, 6574, 6576,
    6578, 6580, 6583, 6584, 6585, 6587, 6592, 6595, 6596, 6597, 6600, 6601,
    6603, 6604, 6605, 6611, 6612, 6614, 6615, 6717, 6718, 7070, 7079, 7080,
    7085, 7092, 7108, 7109, 7112, 7288, 7350, 7351, 7354, 7356, 7370, 7410,
    7412, 7415, 7416, 7424, 7440, 7443, 7448, 7455, 7477, 7479, 7485, 7486,
    7496, 7517, 7521, 7523, 7525, 7526, 7528, 7530, 7536, 7545, 7558, 7909,
    7910, 7971, 7973, 7974, 7975, 7990, 7992, 8108, 8118, 8120, 8125, 8126,
    8138, 8159, 8160, 8170, 8177, 8178, 8179, 8180, 8181, 8182, 8183, 8184,
    8186, 8196, 8199, 8256, 8259, 8267, 8273, 8305, 8306, 8314, 8317, 8350,
    8385, 9291, 9295, 9744, 9745, 9746, 9749, 9750, 9751, 9752, 9753, 9754,
    9755, 9756, 9757, 9760, 9761, 9762, 9763, 9765, 9775, 9776, 9777, 9779,
    9781, 9783, 9784, 9785, 9786, 9787, 9788, 9789, 9795, 9797, 9798, 9799,
    9800, 9807, 9811, 9814, 9815, 9816, 9817, 9818, 9826, 9837, 9840, 9845,
    9851, 9857, 9858, 9861, 9862, 9863, 9866, 9870, 9876, 9878, 9879, 9880,
    9885, 9886, 9890, 9894, 9898, 9906, 9909, 9910, 9912, 9916, 9919, 9923,
    9931, 9934, 9939, 9942, 9946, 9949, 9950, 9951, 9953, 9961, 9963, 9973,
    9974, 10059, 10063, 10074, 10077, 10082, 10089, 10091, 10092, 10096, 10100, 10108,
    10124, 10130, 10148, 10164, 10168, 10172, 10186, 10197, 10199, 10224, 10234, 10242,
    10244, 10280, 10282, 10300, 10312, 10320, 10374, 10404, 10406, 10409, 10424, 10505,
    10561, 10601, 11081, 11098, 11165, 11167, 11202, 11204, 11225, 11967, 11970, 11972,
    11976, 11982, 11996, 12007, 12008, 12010, 12026, 12029, 12047, 13443, 13446, 13874,
    13875, 13918, 13926, 14048, 14166, 14167, 14168, 14170, 14172, 14175, 14466, 14474,
    14478, 14492, 14508, 15210, 15212, 15213, 15215, 15223, 15224, 15225, 15226, 15227,
    15228, 15230, 15232, 15233, 15234, 15238, 15241, 15242, 15245, 15248, 15249, 15250,
    15253, 15259, 15262, 15264, 15268, 15274, 15281, 15284, 15285, 15294, 15322, 15323,
    15324, 15743, 15745, 15746, 15895, 15926, 15928, 15932, 15933, 15938, 15939, 16218,
    17057, 17058, 20708, 20709, 21113, 21114, 21150, 21151, 21228, 209027,
    -- Not in the loot table but fished up all the same, and weighed into
    -- records: vials, a club, lures and a bottle.
    3372, 6530, 6532, 6651, 8925, 15222,
}

MF.NOT_FISH = {}
for _, id in ipairs(NOT_FISH) do MF.NOT_FISH[id] = true end

-- Two questions, deliberately different, because the cost of being wrong
-- is not the same in both directions.
--
-- IsKnownJunk is the certain one: this item is on the list. It is what gets
-- used to refuse a record and to clear old ones out, because deleting
-- somebody's record on a guess is a great deal worse than failing to.
--
-- IsJunkItem adds a guess, and is only used when weighing a fresh catch,
-- where being wrong costs one fish its weight and nothing else.
function MF:IsKnownJunk(itemID)
    if self.FISH[itemID] or self.TROPHY[itemID] then return false end
    return self.NOT_FISH[itemID] == true
end

-- What kind of item a fish is, according to the client - learned from the
-- fish we already know rather than assumed.
--
-- Hardcoding "fish are Consumables" is how a catfish got called a boot last
-- time. This asks the client what class our own forty-odd fish are and will
-- not rule out anything sharing a class with one of them, so it cannot
-- misjudge a fish of a kind we already have. Forever's loot table is missing
-- entries - Bolt of Linen Cloth fishes up and isn't in it - and this is what
-- catches those without waiting for a list to be updated.
-- Settled only once every fish has answered. Freezing the set as soon as a
-- handful had would be the whole trap in miniature: if the first few to
-- resolve were all one kind, every fish of any other kind becomes junk, and
-- the guess built to avoid calling a catfish a boot would do exactly that.
local KINDS_NEEDED = 8 -- before the guess is trusted at all
local RECHECK = 30     -- seconds between attempts while fish are still missing
local kinds, kindsFrom, kindsAt = nil, 0, -math.huge

local function FishKinds(self)
    local total = self.Count(self.FISH)
    if kinds and (kindsFrom >= total or GetTime() - kindsAt < RECHECK) then return kinds end
    local found, n = {}, 0
    for id in pairs(self.FISH) do
        local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, id)
        if ok and classID then
            found[classID .. "." .. tostring(subclassID)] = true
            n = n + 1
        end
    end
    kinds, kindsFrom, kindsAt = found, n, GetTime()
    return kinds
end

-- Not on the list, but it doesn't look like a fish either. Separate from
-- IsJunkItem so a report can say "these look wrong" without anything
-- being thrown away on the strength of it.
function MF:LooksWrong(itemID)
    if self.FISH[itemID] or self.TROPHY[itemID] or self.NOT_FISH[itemID] then return false end
    local known = FishKinds(self)
    if kindsFrom < KINDS_NEEDED then return false end
    local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or not classID then return false end
    return not known[classID .. "." .. tostring(subclassID)]
end

function MF:IsJunkItem(itemID)
    if self.FISH[itemID] or self.TROPHY[itemID] then return false end
    if self.NOT_FISH[itemID] == true then return true end
    return self:LooksWrong(itemID)
end

-- Trophy fish that carry their weight in their name. Listed by ID so they
-- work on any client's language; the name is only a fallback for trophies
-- that aren't in here.
-- Fish a bounty must not ask for
--
-- A bounty is a thing somebody can go and do today. These are not.
--
-- The bloated six are an ordinary fish with something inside it, and
-- they turn up rarely enough that "heaviest Bloated Mud Snapper" is a
-- week of fishing rather than an evening.
MF.BLOATED = { 6643, 6645, 6647, 8366, 13881, 13891 }

-- And these are worse than rare, they are shut: the five Extravaganza
-- prizes only exist during the Stranglethorn contest, an hour a week,
-- and the Mudskunk only inside Zul'Gurub. All of them live in
-- Stranglethorn Vale, which is a zone bounties draw from, so without
-- this a daily could ask for a fish that cannot be caught at all on the
-- day it asks.
local SHUT = { 19803, 19805, 19806, 19807, 19808, 19975 }

MF.NOT_BOUNTY = {}
for _, id in ipairs(MF.BLOATED) do MF.NOT_BOUNTY[id] = true end
for _, id in ipairs(SHUT) do MF.NOT_BOUNTY[id] = true end

MF.TROPHY = {
    [6292] = 10, [6294] = 12, [6295] = 15, [6309] = 17, [6310] = 19, [6311] = 22,
    [6363] = 26, [6364] = 32, [13876] = 40, [13877] = 47, [13878] = 53, [13879] = 59,
    [13880] = 68, [13882] = 42, [13883] = 45, [13884] = 49, [13885] = 34, [13886] = 37,
    [13887] = 52, [13901] = 15, [13902] = 18, [13903] = 22, [13904] = 25, [13905] = 29,
    [13907] = 7, [13908] = 9, [13909] = 12, [13910] = 15, [13911] = 19, [13912] = 21,
    [13913] = 22, [13914] = 70, [13915] = 85, [13916] = 92,
}

-- Names for the trophy and bloated fish, which FISH above doesn't carry.
-- The game only knows an item's name once it has seen one, so another
-- angler's 25 Pound Salmon would otherwise show as "Item 13904".
MF.FISH_NAMES = {
    [6292] = "10 Pound Mud Snapper", [6294] = "12 Pound Mud Snapper", [6295] = "15 Pound Mud Snapper",
    [6309] = "17 Pound Catfish", [6310] = "19 Pound Catfish", [6311] = "22 Pound Catfish",
    [6363] = "26 Pound Catfish", [6364] = "32 Pound Catfish",
    [13876] = "40 Pound Yellowtail", [13877] = "47 Pound Yellowtail", [13878] = "53 Pound Yellowtail",
    [13879] = "59 Pound Yellowtail", [13880] = "68 Pound Yellowtail",
    [13885] = "34 Pound Redgill", [13886] = "37 Pound Redgill", [13882] = "42 Pound Redgill",
    [13883] = "45 Pound Redgill", [13884] = "49 Pound Redgill", [13887] = "52 Pound Redgill",
    [13901] = "15 Pound Salmon", [13902] = "18 Pound Salmon", [13903] = "22 Pound Salmon",
    [13904] = "25 Pound Salmon", [13905] = "29 Pound Salmon", [13906] = "32 Pound Salmon",
    [13907] = "7 Pound Lobster", [13908] = "9 Pound Lobster", [13909] = "12 Pound Lobster",
    [13910] = "15 Pound Lobster", [13911] = "19 Pound Lobster", [13912] = "21 Pound Lobster",
    [13913] = "22 Pound Lobster",
    [13914] = "70 Pound Mightfish", [13915] = "85 Pound Mightfish", [13916] = "92 Pound Mightfish",
    [6643] = "Bloated Brilliant Smallfish", [6645] = "Bloated Mud Snapper",
    [6647] = "Bloated Bristle Whisker Catfish", [8366] = "Bloated Mithril Head Trout",
    [13881] = "Bloated Redgill", [13891] = "Bloated Whitescale Salmon",
}

-- Anything not listed above that isn't junk (e.g. new Forever fish).
MF.DEFAULT_FISH = { min = 0.5, max = 4.0 }
MF.UNKNOWN_MAX = 100           -- sanity cap for fish we have no data on
MF.SPECIMEN_CHANCE = 0.01
MF.FRENZY_WEIGHT = 1.2         -- feeding frenzy weight bonus
MF.FRENZY_SPECIMEN = 2         -- feeding frenzy specimen chance multiplier
MF.TIME_BONUS = 1.15           -- night fish at night / day fish by day
MF.WEIGHT_SKEW = 2.2           -- rolls lean low, so big fish stay rare
MF.TROPHY_SPREAD = 0.99        -- a "12 Pound" fish lands in 12.00-12.99

-- Zones our fish data says something about. Forever adds zones the vanilla
-- data never covered (Mount Hyjal, Riverglades and friends); we don't know
-- what lives there, so rather than ruling specimens out entirely we treat
-- those zones as home waters for everything until the data catches up.
-- Preserve the pre-reference specimen policy. Adding city guidance must
-- not turn previously permissive waters into newly restrictive ones.
local originalNativeZones = {}
for _, fish in pairs(MF.FISH) do
    for _, zone in ipairs(fish.zones or {}) do originalNativeZones[zone] = true end
end

-- Additive guidance from GuildedVellum's FishFry Forever 1.4.4 reference.
-- Never remove or reorder existing zones: their indices are saved in the
-- journal's caught-in bitmask. Leave disputed and imported instance lists
-- for verification, and never use access coordinates as pool spawns.
local referenceAdditions = {
    ["Darkshore"] = { 6291, 6308 },
    ["Alterac Mountains"] = { 8365, 21153 },
    ["Ashenvale"] = { 6359, 6358, 8365, 6361 },
    ["Stormwind City"] = { 6358, 6291, 6308, 6289, 6361, 6303 },
    ["Orgrimmar"] = { 6291, 6308, 6289 },
    ["Ironforge"] = { 6291, 6308, 6289 },
    ["Darnassus"] = { 6291, 6308, 6289 },
    ["Thunder Bluff"] = { 6291, 6308, 6289 },
    ["Undercity"] = { 6291, 6308, 6289 },
}
local referenceZoneOrder = { "Darkshore", "Alterac Mountains", "Ashenvale", "Stormwind City",
    "Orgrimmar", "Ironforge", "Darnassus", "Thunder Bluff", "Undercity" }
for _, zone in ipairs(referenceZoneOrder) do
    local ids = referenceAdditions[zone]
    for _, id in ipairs(ids) do
        local fish, copy, found = MF.FISH[id], {}, false
        for _, existing in ipairs(fish.zones or {}) do
            copy[#copy + 1] = existing
            if existing == zone then found = true end
        end
        if not found then copy[#copy + 1] = zone end
        fish.zones = copy
    end
end
local knownZones

-- True if our fish data says anything about this zone at all.
function MF:ZoneCovered(zone)
    if not knownZones then
        knownZones = {}
        for _, f in pairs(self.FISH) do
            for _, z in ipairs(f.zones or {}) do knownZones[z] = true end
        end
    end
    return knownZones[zone] == true
end

-- Where two of the fish with no zone list are listed, for the pages that list a zone's fish.
-- Display only: a fish's own zone list also decides where a specimen can roll and is counted in
-- the caught-in record, so these don't go in it. From the reference lists compared in October
-- (Sickly Looking Fish in four zones, Oil Covered Fish in one); Spotted Sunfish and Steelscale
-- Crushfish weren't listed anywhere, so they stay anywhere.
MF.FISH_LISTED_IN = {
    [6299] = { "Tirisfal Glades", "Undercity", "Silverpine Forest", "Blackfathom Deeps" }, -- Sickly Looking Fish
    [6458] = { "Stonetalon Mountains" },                                                   -- Oil Covered Fish
}

-- A fish with no zone list and nowhere it's listed bites almost anywhere
function MF:BitesAnywhere(itemID)
    local f = self.FISH[itemID]
    return f ~= nil and f.zones == nil and not self.TROPHY[itemID] and not self.FISH_LISTED_IN[itemID]
end

-- The fish of a zone, for the pages that list them: its own fish (FISH_LISTED_IN included), the
-- two that bite almost anywhere, and anything you've caught there that's on neither list. Each id maps to why it's
-- there: "native", "anywhere" or "caught". A zone goal still means its own fish only
-- (MF:ZoneFishIDs), so finishing a zone never waits on a fish that isn't really of it.
function MF:ZoneFish(zone)
    local out = {}
    if not zone then return out end
    for id, f in pairs(self.FISH) do
        if f.zones then
            for _, z in ipairs(f.zones) do
                if z == zone then out[id] = "native" break end
            end
        elseif self.FISH_LISTED_IN[id] then
            for _, z in ipairs(self.FISH_LISTED_IN[id]) do
                if z == zone then out[id] = "native" break end
            end
        elseif not self.TROPHY[id] then
            out[id] = "anywhere"
        end
    end
    local caughtIn = self.cdb and self.cdb.caughtIn or {}
    for id, zones in pairs(caughtIn) do
        if not out[id] and zones[zone] and (self.FISH[id] or self.TROPHY[id]) then out[id] = "caught" end
    end
    return out
end

function MF:IsNative(itemID, zone)
    local f = self.FISH[itemID]
    if not f or not f.zones then return true end
    for _, z in ipairs(f.zones) do
        if z == zone then return true end
    end
    return not originalNativeZones[zone]
end

function MF:SpecimenRange(f)
    return f.specMin or f.max * 1.3, f.specMax or f.max * 2
end

-- The pounds a trophy fish carries in its name, from the table or from the
-- name itself. One place to ask, because the weight, the ceiling and now the
-- grade all need the same answer.
function MF:TrophyWeight(itemID, name)
    local fixed = self.TROPHY[itemID]
    if fixed then return fixed end
    name = name or self:FishName(itemID)
    if type(name) ~= "string" then return end
    return tonumber(name:match("^(%d+) Pound"))
end

-- Heaviest weight a fish can legitimately roll; used to reject bogus data.
function MF:MaxWeight(itemID)
    local fixed = self:TrophyWeight(itemID)
    if fixed then return fixed + 1 end
    local f = self.FISH[itemID]
    if not f then return self.UNKNOWN_MAX end
    local _, hi = self:SpecimenRange(f)
    return hi * self.FRENZY_WEIGHT * self.TIME_BONUS + 0.01
end

-- How good a fish is, for its own kind
--
-- A weight on its own means nothing unless you already know what a big one
-- looks like, which is the thing every fishing game solves and this didn't:
-- 4.59 lb tells a new angler nothing, and only a one-in-a-hundred specimen
-- ever got called out.
--
-- Grading on where the weight falls between min and max would be wrong,
-- because the roll leans low on purpose - two thirds of the range holds a
-- handful of fish and almost everything would come out "small". So the skew
-- is undone first, and the grade is how many of its own kind it beats.
-- Two wordings of the same grade. A line of chat has room to read like
-- somebody talking; a column in the journal, beside a weight and a count
-- and a fish with a long name, does not.
local GRADES = {
    { p = 0.15, name = "a tiddler",   short = "tiddler", colour = "|cff808080" },
    { p = 0.40, name = "small",       short = "small",   colour = "|cff9d9d9d" },
    { p = 0.70, name = "average",     short = "fair",    colour = "|cffbbbbbb" },
    { p = 0.90, name = "a good one",  short = "good",    colour = "|cff1eff00" },
    { p = 0.98, name = "a cracker",   short = "cracker", colour = "|cff0070dd" },
    { p = 2.00, name = "a monster",   short = "monster", colour = "|cffa335ee" },
}

-- What share of this fish's kind it beats, 0 to 1. Nil when there's nothing
-- to compare it against - an item we have no range for could be anything.
function MF:WeightPercentile(itemID, weight)
    if not weight or weight <= 0 then return end

    -- A trophy weighs what its name says, but the scales are allowed the
    -- fraction - which is the only thing that tells two of them apart. A
    -- 12.98 is the pick of the twelve pounders and a 12.01 is a poor one,
    -- and that fraction is rolled flat, so it is already the percentile.
    local fixed = self:TrophyWeight(itemID)
    if fixed then
        local over = weight - fixed
        if over < 0 then return end
        return math.min(1, over / self.TROPHY_SPREAD)
    end

    local f = self.FISH[itemID]
    if not f then return end
    local span = f.max - f.min
    if span <= 0 then return end
    local frac = (weight - f.min) / span
    if frac <= 0 then return 0 end
    if frac >= 1 then return 1 end
    return frac ^ (1 / self.WEIGHT_SKEW)
end

-- Returns the grade, its colour, and the percentile behind it.
function MF:WeightGrade(itemID, weight)
    local p = self:WeightPercentile(itemID, weight)
    if not p then return end
    for _, g in ipairs(GRADES) do
        if p <= g.p then return g.name, g.colour, p end
    end
end

-- The same grade in one word, for a column rather than a sentence.
function MF:WeightGradeShort(itemID, weight)
    local p = self:WeightPercentile(itemID, weight)
    if not p then return end
    for _, g in ipairs(GRADES) do
        if p <= g.p then return g.short, g.colour, p end
    end
end

-- Every grade this fish can reach, lowest first, with the weight that has
-- to be beaten to get past it: { short, colour, p, upTo }. upTo is nil on
-- the top grade, which nothing but a specimen outranks. The percentile is
-- undone the same way WeightPercentile does it, so the card's "next grade
-- at" can never disagree with the grade a catch is actually given.
function MF:GradeLadder(itemID)
    local fixed = self:TrophyWeight(itemID)
    local f = self.FISH[itemID]
    if not fixed and (not f or f.max <= f.min) then return nil end
    local function At(p)
        if fixed then return fixed + p * self.TROPHY_SPREAD end
        return f.min + (f.max - f.min) * p ^ self.WEIGHT_SKEW
    end
    local out = {}
    for _, g in ipairs(GRADES) do
        out[#out + 1] = { short = g.short, colour = g.colour, p = g.p,
            upTo = g.p < 1 and At(g.p) or nil }
    end
    return out
end

-- "a good one", coloured, ready to drop into a line of chat.
function MF:GradeText(itemID, weight)
    local name, colour = self:WeightGrade(itemID, weight)
    if not name then return "" end
    return (" %s(%s)|r"):format(colour, name)
end

-- What skill is worth
--
-- A better angler does not land a bigger fish. They stop landing rubbish
-- ones - so skill lifts the floor of every catch and leaves the ceiling
-- exactly where it was.
--
-- That distinction is the whole reason this is safe. If skill raised the
-- ceiling, every record on the realm would belong to whoever had the most
-- of it, a beginner could never compete, and the weight would have to be
-- checked against the catcher's skill - a number they send us, about
-- themselves, which is no check at all. Raising the floor changes nothing
-- about what is possible, so MaxWeight is untouched, nothing new goes over
-- the wire, and a lucky beginner can still tie the realm record.
--
-- Steps rather than a slope, because these thresholds already mean
-- something: 150 is the Journeyman ceiling, 225 the book from Booty Bay,
-- 300 Nat Pagle. Reaching one is a moment and it should feel like one. The
-- last is half a step, for being capped with a lure on rather than for any
-- rank, which is the most an angler can do.
MF.SKILL_FLOOR = {
    { at = 350, lift = 0.445 },
    { at = 300, lift = 0.390 },
    { at = 225, lift = 0.280 },
    { at = 150, lift = 0.170 },
}

-- Returns the lift, the step you're on, and your effective skill - which
-- counts your lure, your gear and your food, because those are skill as far
-- as the water is concerned and this is the first thing a lure has ever
-- actually done.
--
-- None of it applies in a match. A record is set against the whole realm
-- over weeks, where skill is something everyone can go and earn; a match is
-- two anglers at one lake for ten minutes, where it is simply a head start.
-- So the water is flat for everybody once a match is running, and the only
-- thing between them is where they stand and how often they cast.
function MF:SkillFloorLift()
    if self:InMatch() then return 0, 0, 0 end
    local rank, _, bonus = self:FishingSkill()
    if not rank then return 0, 0, 0 end
    local effective = rank + (bonus or 0)
    for _, step in ipairs(self.SKILL_FLOOR) do
        if effective >= step.at then return step.lift, step.at, effective end
    end
    return 0, 0, effective
end

-- The next step up, for saying what the next rank is worth: returns the
-- skill needed and the lift it brings, or nil at the top.
function MF:NextSkillFloor()
    local _, _, effective = self:SkillFloorLift()
    local best
    for _, step in ipairs(self.SKILL_FLOOR) do
        if effective < step.at and (not best or step.at < best.at) then best = step end
    end
    if best then return best.at, best.lift, best.at - effective end
end

-- Returns weight (lb, 2 decimals), isSpecimen, isJunk.
-- forceSpecimen is for /tfl spec testing only.
function MF:RollWeight(itemID, itemName, quality, zone, frenzy, forceSpecimen, context)
    -- Grey items (boots, driftwood) and everything else that isn't a fish.
    if quality == 0 or self:IsJunkItem(itemID) then
        return 0, false, true
    end
    -- A "12 Pound Mud Snapper" weighs what it says on the tin - but the scales
    -- are allowed the fraction. It lands between 12.00 and 12.99 lb, so it's
    -- still a twelve pounder and two of them can still be told apart.
    local fixed = self:TrophyWeight(itemID, itemName)
    if fixed then
        return MF.RoundWeight(fixed + math.random() * self.TROPHY_SPREAD), false, false
    end

    local f = self.FISH[itemID] or self.DEFAULT_FISH
    local mult = frenzy and self.FRENZY_WEIGHT or 1
    local night = self:IsNight()
    if context then night = context.night end
    if (f.night and night) or (f.day and not night) then
        mult = mult * self.TIME_BONUS
    end

    local chance = self.SPECIMEN_CHANCE * (frenzy and self.FRENZY_SPECIMEN or 1)
    if forceSpecimen or (self:IsNative(itemID, zone) and math.random() < chance) then
        local lo, hi = self:SpecimenRange(f)
        return MF.RoundWeight((lo + (hi - lo) * math.random()) * mult), true, false
    end
    -- Skew toward the low end so big fish feel rare - within a range whose
    -- bottom your skill has lifted. Specimens and trophy fish are left out
    -- of this: both are already the top of their own scale.
    local lift = context and context.lift or self:SkillFloorLift()
    local lo = f.min + (f.max - f.min) * lift
    return MF.RoundWeight((lo + (f.max - lo) * (math.random() ^ self.WEIGHT_SKEW)) * mult),
        false, false
end
