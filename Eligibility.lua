-- Eligibility: which versions of the addon still count towards shared scores.
--
-- An old copy carries old bugs - a weight read wrongly, a frenzy missed, a
-- bounty scored on last month's rules - and those leak onto everybody's
-- boards. So a version stops counting for shared scores once it is two
-- releases behind, and the second of those releases has been out for a
-- week. The week is for hotfixes: two releases a day apart must not cut
-- anyone off overnight.
--
-- "Counting" is decided by the one receiving a score, never by the one
-- sending it: nothing can make an old copy stop talking. Every client that
-- has updated simply stops writing that angler's new scores into its own
-- records, bounty boards and matches. What stops counting is the shared
-- part only. Their own journal, cards, bests and XP are theirs whatever
-- version they are on, and records they set while their version still
-- counted stand.
--
-- Release dates come from News.lua, so a client only ever judges by the
-- releases it knows of. An out-of-date client therefore can't work out
-- that it is out of date on its own - it learns that from anglers who are
-- newer, who say the oldest version they still count (see HERE).
local _, MF = ...

local BEHIND = 2               -- releases behind before a version stops counting
local GRACE = 7 * 86400        -- and how long the second of those has been out
local VOUCHERS = 2             -- anglers who must agree before we believe we're out
-- How long a version we heard is believed for. Long enough to cover a
-- fishing session between census replies, short enough that someone who
-- updated and whose news didn't reach us is only misjudged for an evening.
local TRUST = 6 * 3600

-- "2026-11-15" as a UTC timestamp, without asking the local clock: time()
-- with a table reads it as local time, and the cut-off has to be the same
-- moment on every client.
local function UTC(stamp)
    local y, m, d = tostring(stamp or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or m < 1 or m > 12 or d < 1 or d > 31 then return end
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400
end
MF.UTCDate = UTC

local function Valid(v)
    return type(v) == "string" and #v <= 32 and v:match("^%d+%.%d+%.%d+$") ~= nil
end
MF.ValidVersion = Valid

function MF:ReleaseDate(v)
    for _, release in ipairs(self.NEWS or {}) do
        if release.v == v then return UTC(release.released) end
    end
end

-- When a version stopped (or will stop) counting, or nil while there is no
-- such moment yet: fewer than two newer releases known, or the second has
-- no date to count the week from.
function MF:StopsCountingAt(v)
    if not Valid(v) then return end
    local newer = {}
    for _, release in ipairs(self.NEWS or {}) do
        if self:VersionNewer(release.v, v) then newer[#newer + 1] = release end
    end
    if #newer < BEHIND then return end
    table.sort(newer, function(a, b) return self:VersionNewer(b.v, a.v) end)
    -- Releases before dates were kept have none; the first dated release
    -- after them came out later still, so counting from it only ever errs
    -- towards counting a little longer.
    for i = BEHIND, #newer do
        local out = UTC(newer[i].released)
        if out then return out + GRACE end
    end
end

-- Whether a score made on version v at time `at` (default now) counts.
function MF:VersionCounts(v, at)
    local cut = self:StopsCountingAt(v)
    return not cut or (at or GetServerTime()) < cut
end

function MF:AnglerVersion(name)
    local a = name and self.db and self.db.anglersSeen[self:AnglerKey(name)]
    return a and a.version or nil
end

-- Whether another angler's score, made at `at` (default now), counts.
--
-- The version we hold for them is only believed near the moment it was
-- heard: from then until a few hours later. Saved versions outlive the
-- session, and someone last heard on an old copy may well have updated
-- since without it reaching us - records are relayed by third parties,
-- and the census only reaches guild, group and whispers on this client.
-- Not knowing, and knowing only stale, both get the benefit of the doubt.
function MF:AnglerCounts(name, at)
    if not name or self:IsMe(name) then return true end
    local a = self.db and self.db.anglersSeen[self:AnglerKey(name)]
    if not a or not a.version or not a.versionAt then return true end
    at = at or GetServerTime()
    if at > a.versionAt + TRUST then return true end
    return self:VersionCounts(a.version, at)
end

-- The oldest release this client still counts, said in HERE so an older
-- client can learn where it stands.
function MF:CountingFloor()
    local floor
    for _, release in ipairs(self.NEWS or {}) do
        if self:VersionCounts(release.v) and (not floor or self:VersionNewer(floor, release.v)) then
            floor = release.v
        end
    end
    return floor or self.Version()
end

------------------------------------------------------------------------
-- Are we out of date ourselves?
------------------------------------------------------------------------

-- floor -> set of angler keys who said it. Only believed from anglers on a
-- version at least as new as the floor they name, and only once two agree,
-- for the same reason the update notice needs two.
MF.floorsSeen = {}

function MF:NoteCountingFloor(sender, version, floor)
    if not Valid(floor) or not Valid(version) or self:VersionNewer(floor, version) then return end
    local who = self.floorsSeen[floor]
    if not who then who = {} self.floorsSeen[floor] = who end
    who[self:AnglerKey(sender)] = true
end

-- false and the oldest version that still counts, when enough newer
-- anglers say ours doesn't; true otherwise.
function MF:MyVersionCounts()
    local mine, best = self.Version(), nil
    for floor, who in pairs(self.floorsSeen) do
        if self.Count(who) >= VOUCHERS and self:VersionNewer(floor, mine)
            and (not best or self:VersionNewer(floor, best)) then
            best = floor
        end
    end
    if best then return false, best end
    return true
end

local warned = false
function MF:WarnIfOutdated()
    local counts, floor = self:MyVersionCounts()
    if counts or warned then return counts end
    warned = true
    self:Print(("%sYour version (%s) is too old to count.|r Your catches still go in your own "
        .. "log, but other anglers won't see your records, bounty entries or match scores "
        .. "until you update to %s or newer on CurseForge."):format(self.C.bad, self.Version(), floor))
    if self.UpdateBoard then pcall(self.UpdateBoard, self) end
    return counts
end

-- Said to the player trying to join something they can't count in.
function MF:RefuseOutdated(what)
    if self:MyVersionCounts() then return false end
    self:Print(("%sUpdate to take part.|r Your version is too old to count in %s."):format(self.C.bad, what))
    return true
end

-- Said once per angler per session to whoever is running something.
local noted = {}
function MF:NoteOutdatedAngler(name, what)
    local key = self:AnglerKey(name)
    if noted[key] then return end
    noted[key] = true
    self:Print(("%s is on an old version (%s) and can't count in %s until they update.")
        :format(self:ShortName(name), self:AnglerVersion(name) or "?", what))
end
