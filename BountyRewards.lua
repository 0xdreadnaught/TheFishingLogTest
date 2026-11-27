-- Bounty podiums are settled locally from the shared board, not certified
-- by a server. Wait for sync and a quiet board, then save one result/claim.
local _, MF = ...
local SPAN = { day = 86400, week = 604800, month = 2419200 }
local LABEL = { day = "Daily", week = "Weekly", month = "Monthly" }
MF.BOUNTY_REWARD_START = 1792108800 -- 16 October 2026 UTC; includes periods in progress
MF.BOUNTY_REWARDS = { day = { 150, 100, 50 }, week = { 750, 500, 250 }, month = { 2000, 1250, 750 } }
local function Identity(self, name)
    return (self:SplitName(name)):gsub("[%s%-]", ""):lower()
end

function MF:BountyRewardXP(kind, place)
    return (self.BOUNTY_REWARDS[kind] or {})[place] or 0
end

function MF:IsBountyRewardPeriod(kind, period)
    return SPAN[kind] and period == self:BountyPeriod(kind) - 1
        and period >= math.floor(self.BOUNTY_REWARD_START / SPAN[kind])
end

function MF:BountyRewardResult(kind, period)
    local result = (self.cdb.profile.bountyRewardResults or {})[kind]
    if result and result.period == (period or self:BountyPeriod(kind) - 1) then return result end
end

function MF:CheckBountyRewards()
    if not self.cdb or not self.me then return end
    local p, now = self.cdb.profile, GetTime()
    self.bountyRewardWait = self.bountyRewardWait or {}
    local request = false
    local needsQuiet = false
    for _, kind in ipairs(self.BOUNTY_KINDS) do
        local period = self:BountyPeriod(kind) - 1
        local through = (p.bountyRewardThrough or {})[kind] or -1
        local score = self:MyBountyBest(kind, period)
        if self:IsBountyRewardPeriod(kind, period) and period > through and score > 0 then
            -- A request with nowhere to send cannot settle an offline board.
            if self:ChannelID() or IsInGroup() or self:QuietBountyReady(kind,period) then
                local entries = self:BountyStandings(kind, period)
                local parts, place, seen = {}, 1, {}
                for _, entry in ipairs(entries) do
                    local key = Identity(self, entry.name)
                    if not seen[key] then
                        seen[key] = true
                        parts[#parts + 1] = key .. "=" .. self:EncodeWeight(entry.weight)
                        if key ~= Identity(self, self.me) and entry.weight > score then place = place + 1 end
                    end
                end
                table.sort(parts)
                local fingerprint = table.concat(parts, ";")
                local wait = self.bountyRewardWait[kind]
                if not wait or wait.period ~= period or wait.profile ~= p or now < wait.started then
                    wait = { period = period, profile = p, started = now, changed = now,
                        fingerprint = fingerprint }
                    self.bountyRewardWait[kind] = wait
                    request = true
                elseif wait.fingerprint ~= fingerprint then
                    wait.fingerprint, wait.changed = fingerprint, now
                end
                if self:BountySyncPending() then wait.started = now end
                if now - wait.started >= 120 and now - wait.changed >= 30 then
                    local xp = self:BountyRewardXP(kind, place)
                    p.bountyRewardThrough = p.bountyRewardThrough or {}
                    p.bountyRewardResults = p.bountyRewardResults or {}
                    -- Save the claim before notifications/XP so callbacks cannot
                    -- re-enter and pay the same period twice. Save non-podiums too.
                    p.bountyRewardThrough[kind] = period
                    p.bountyRewardResults[kind] = { period = period, place = place, xp = xp, score = score,
                        at = GetServerTime(), standings = entries, specimen = self:BountySpecimenStatus(kind,self.me,period,score) }
                    p.updated = GetServerTime()
                    if xp > 0 then
                        self:AddXP(xp)
                        self:Print(("%s bounty reward: #%d - +%d XP (%s).")
                            :format(LABEL[kind], place, xp, self:BountyTitle(kind, period)))
                        self:Toast(self:BountyIcon(kind, period), "BOUNTY REWARD",
                            LABEL[kind] .. " - Place " .. place, "+" .. xp .. " XP", 1, 0.82, 0,
                            SOUNDKIT.UI_EPICLOOT_TOAST)
                    else self:MarkProfileChanged() end
                    self:RefreshJournal()
                    self.bountyRewardWait[kind] = nil
                end
            else
                -- Disconnecting must not count as time spent syncing.
                self.bountyRewardWait[kind] = nil
                needsQuiet = true
            end
        else self.bountyRewardWait[kind] = nil end
    end
    if needsQuiet and now-(self.bountyQuietRequestedAt or -math.huge)>=60 then
        self.bountyQuietRequestedAt=now
        request=true
    end
    if request then self:RequestBounty() end
end

MF:OnTick(function(self) self:CheckBountyRewards() end)
