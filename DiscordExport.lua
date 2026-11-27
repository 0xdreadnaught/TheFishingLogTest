-- Read-only record snapshot for the optional desktop Discord relay.
-- No network calls or webhook secrets belong in the addon.
local _,MF=...
local function Hex(value)
    return (tostring(value or ""):gsub(".",function(c) return ("%02x"):format(c:byte()) end))
end
function MF:BuildDiscordExport()
    local rows={"1|" .. Hex(GetRealmName() ~= "" and GetRealmName() or self:RealmName()) .. "|" .. tostring(self.FRESH_START)}
    for _,r in ipairs(self:SpeciesRecords(false)) do
        rows[#rows+1]=table.concat({r.id,math.floor(r.w*100+.5),r.t,
            Hex(r.h),Hex(self:FishName(r.id)),Hex(self:SpotName(r.spot))},"|")
    end
    return Hex(table.concat(rows,"\n"))
end
-- Ask for every record holder's fish name early in the session, so the game
-- has them loaded by logout and the export carries names, not item numbers.
MF:On("TFL_LOGIN",function(self)
    for _,r in ipairs(self:SpeciesRecords(false)) do self:FishName(r.id) end
end)
MF:On("PLAYER_LOGOUT",function(self)
    TheFishingLogDiscord=self:BuildDiscordExport()
end)
