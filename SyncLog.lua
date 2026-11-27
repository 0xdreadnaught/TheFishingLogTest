-- Local activity reports. No new messages or delivery claims are added to the wire.
local _, MF = ...
local QUIET, REPLY_WAIT, MAX_AGE = 20, 120, 1800
local KEEP, MAX_PEERS, MAX_CHANGES, MAX_PLACES = 10, 32, 160, 32
local active, pendingPopup, serial
serial = 0
local DATA = { RBOOK="records", RBOOK2="records", RSYNC2="records", RMINE="records",
    POBOOK1="pools", FWOBS1="frenzies", BNTY2="bounties", BNTY3="bounties", BNTY4="bounties",
    QBROW1="bounties", NPOST="events", NPOSTG1="events", RTALLY="tallies" }
local REQUEST = { RASK="records", RREQ2="records", RALL="records", POREQ1="pools",
    FWREQ1="frenzies", BREQ2="bounties", BREQ4="bounties", QBASK1="bounties", NREQ="events" }
local CONTROL = { RACK1=true, RTALLY=true, QBEND1=true }
local BULK = { RBOOK=true, RBOOK2=true, RSYNC2=true, RMINE=true, POBOOK1=true }
local ORDER = { "records", "pools", "bounties", "frenzies", "events", "tallies" }

local function Clean(text)
    return tostring(text or ""):gsub("|", ""):gsub("[%c]", " "):sub(1, 160)
end
function MF:IsSyncKind(kind) return DATA[kind] ~= nil or REQUEST[kind] ~= nil or CONTROL[kind] end
function MF:SyncHistory() self.db.syncReports = self.db.syncReports or {}; return self.db.syncReports end
function MF:ActiveSyncReport() return active end

local function Track(self, name, road, direction, kind)
    if not self.db or not self:IsSyncKind(kind) or not name or self:IsMe(name) then return end
    local group = direction == "out" and road ~= "WHISPER"
    -- A broadcast request alone has not contacted another person. Live bounty
    -- and frenzy broadcasts also must not open reports for every catch.
    if not active and (group or (road ~= "WHISPER" and not BULK[kind] and not REQUEST[kind])) then return end
    if not active then
        serial = serial + 1
        active = { id=tostring(GetServerTime())..":"..serial, at=GetServerTime(), started=GetTime(), last=GetTime(),
            state="In progress", peers={}, order={}, changes={}, omitted=0, revision=0 }
        local report = active
        self:Toast("Interface\\Icons\\Trade_Fishing", "SYNC STARTED", Clean(self:ShortName(name)),
            "Click for activity", 1, 0.82, 0, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081,
            { onClick=function() self:OpenSyncReport(report) end })
    end
    local key = group and ("@"..road) or self:AnglerKey(name)
    local peer = active.peers[key]
    if not peer then
        if #active.order >= MAX_PEERS then active.truncated=true; return end
        peer = { name=Clean(name), group=group, routes={}, received={}, sent={}, places={incoming={},outgoing={}},
            awaiting={}, requests={incoming={},outgoing={}}, acknowledgements=0,
            new=0, updated=0, seasonal=0, poolChanges=0, bountyChanges=0, errors=0, heard=false }
        active.peers[key] = peer; active.order[#active.order+1] = key
    end
    peer.routes[road or "?"] = true
    active.last, active.revision = GetTime(), active.revision + 1
    if direction == "in" then peer.heard = true end
    return active, peer
end

local function Place(self, peer, direction, category, key, map, count)
    local name
    if key and self.SpotName then name = self:SpotName(key) end
    if (not name or name == "") and tonumber(map) and self.ZoneNameFor then name = self:ZoneNameFor(tonumber(map)) end
    name = Clean(name or key or (map and ("Map "..map)) or "")
    if name == "" then return end
    local places = peer.places[direction]
    local tag = category..": "..name
    if not places[tag] and self.Count(places) >= MAX_PLACES then tag = category..": other locations" end
    places[tag] = (places[tag] or 0) + (count or 1)
end

local function Details(self, peer, direction, kind, fields)
    if REQUEST[kind] then
        local requests=peer.requests[direction]
        requests[REQUEST[kind]]=(requests[REQUEST[kind]] or 0)+1
    end
    if kind == "RACK1" and direction == "incoming" then peer.acknowledgements=peer.acknowledgements+1 end
    local category, count = DATA[kind], 0
    if not category then return end
    if kind == "RBOOK" then
        for entry in (fields[1] or ""):gmatch("[^;]+") do
            local f={strsplit(",",entry)}; count=count+1; Place(self,peer,direction,category,f[1],f[7])
        end
    elseif kind == "RBOOK2" then
        for block in (fields[2] or ""):gmatch("[^;]+") do
            local f={strsplit("|",block)}; local key,map=strsplit(",",f[1] or "")
            local n=math.max(0,#f-1); count=count+n
            Place(self,peer,direction,category,key,self:Unpack36(map or "0"),n)
        end
    elseif kind == "RSYNC2" or kind == "RMINE" then
        for entry in (fields[2] or ""):gmatch("[^;]+") do
            local key=strsplit(",",entry); count=count+1; Place(self,peer,direction,category,key,fields[1])
        end
    elseif kind == "POBOOK1" then
        for entry in (fields[1] or ""):gmatch("[^;]+") do
            local _,map=strsplit(",",entry); count=count+1; Place(self,peer,direction,category,nil,map)
        end
    elseif kind == "RTALLY" then
        for _ in (fields[1] or ""):gmatch("[^;]+") do count=count+1 end
    elseif kind == "FWOBS1" then count=1; Place(self,peer,direction,category,nil,fields[1])
    elseif category == "events" then
        count=1; Place(self,peer,direction,category,fields[4],fields[6])
    else count=1 end
    local totals = direction == "incoming" and peer.received or peer.sent
    totals[category] = (totals[category] or 0) + count
end

function MF:SyncPacketStarted(name, road, direction, kind)
    return Track(self, name, road, direction, kind)
end

function MF:SyncSendFinished(meta)
    if not self:IsSyncKind(meta.kind) then return end
    local name = meta.dist == "WHISPER" and meta.target or meta.dist
    local report,peer=Track(self,name,meta.dist,"out",meta.kind)
    if not peer then return end
    if meta.failed then peer.errors=peer.errors+1; return end
    if REQUEST[meta.kind] and not peer.group then peer.awaiting[REQUEST[meta.kind]]=GetTime() end
    Details(self,peer,"outgoing",meta.kind,meta.fields)
end

function MF:SyncMessageBegin(sender, road, kind, fields)
    local report,peer=Track(self,sender,road,"in",kind)
    if not peer then return end
    local diagnostics=self.syncDiagnostics or {}
    return { report=report,peer=peer,sender=sender,kind=kind,fields=fields,
        pools=diagnostics.pools or 0,bounties=diagnostics.bounties or 0 }
end
function MF:SyncMessageEnd(context, ok)
    if not context or context.report ~= active then return end
    local peer, category=context.peer,DATA[context.kind]
    if category then peer.awaiting[category]=nil end
    if not ok then peer.errors=peer.errors+1; return end
    Details(self,peer,"incoming",context.kind,context.fields)
    local diagnostics=self.syncDiagnostics or {}
    peer.poolChanges=peer.poolChanges+math.max(0,(diagnostics.pools or 0)-context.pools)
    peer.bountyChanges=peer.bountyChanges+math.max(0,(diagnostics.bounties or 0)-context.bounties)
end

-- Called only after a validated record merge, inside a tracked receive handler.
function MF:SyncRecordMerged(key,map,id,record,previous,all,season,previousSeason)
    local context=self.syncReceiveContext
    if not context or context.report ~= active or DATA[context.kind] ~= "records" or not (all or season) then return end
    local peer=context.peer
    local change=all and (previous and "Updated" or "New") or "Season"
    if not all then previous=previousSeason end
    if change=="New" then peer.new=peer.new+1 elseif change=="Updated" then peer.updated=peer.updated+1 else peer.seasonal=peer.seasonal+1 end
    if #active.changes >= MAX_CHANGES then active.omitted=active.omitted+1; return end
    active.changes[#active.changes+1]={from=Clean(context.sender),kind=change,spot=Clean(self:SpotName(key)),
        map=tonumber(map),fish=Clean(self:FishName(id)),holder=Clean(record.h),weight=record.w,
        previous=previous and previous.w or nil,previousHolder=previous and Clean(previous.h) or nil}
end

function MF:SyncTransferFailed(sender, road, kind)
    local _,peer=Track(self,sender,road,"in",kind)
    if peer then peer.errors=peer.errors+1 end
end

function MF:SyncUnknownTransferFailed(sender)
    -- A peer already in this batch lost its first fragment. We cannot name
    -- that transfer's category, but must not silently call it complete.
    local peer=active and active.peers[self:AnglerKey(sender)]
    if peer then
        peer.errors=peer.errors+1
        active.last,active.revision=GetTime(),active.revision+1
    end
end

local function Totals(t)
    local parts={}
    for _,category in ipairs(ORDER) do if (t[category] or 0)>0 then parts[#parts+1]=t[category].." "..category end end
    return #parts>0 and table.concat(parts,", ") or "none"
end
local function Routes(peer)
    local out={};for route in pairs(peer.routes) do out[#out+1]=route:lower() end;table.sort(out);return table.concat(out,", ")
end
local function Places(places)
    local out={};for name,n in pairs(places) do out[#out+1]=name.." ("..n..")" end;table.sort(out);return table.concat(out,"; ")
end
function MF:SyncReportRows(report)
    local rows={}
    if not report then return {{kind="row",h=44,title="No sync activity yet",note=""}} end
    for _,key in ipairs(report.order) do
        local peer=report.peers[key]
        rows[#rows+1]={kind="header",h=32,title=peer.name, note=peer.state or "In progress",tip=Routes(peer)}
        if next(peer.requests.incoming) or next(peer.requests.outgoing) then
            rows[#rows+1]={kind="row",h=44,title="Requested: "..Totals(peer.requests.outgoing),
                note="Asked us for: "..Totals(peer.requests.incoming)..(peer.acknowledgements>0 and " · Reply received" or "")}
        end
        rows[#rows+1]={kind="row",h=44,title="Received: "..Totals(peer.received),
            note=("%d new records · %d updated · %d season changes"):format(peer.new,peer.updated,peer.seasonal),tip=Places(peer.places.incoming)}
        rows[#rows+1]={kind="row",h=44,title="Sent: "..Totals(peer.sent),note="Receipt unconfirmed",tip=Places(peer.places.outgoing)}
        for _,direction in ipairs({"incoming","outgoing"}) do
            local placeList={};for name,n in pairs(peer.places[direction]) do placeList[#placeList+1]={name=name,n=n} end
            table.sort(placeList,function(a,b) return a.name<b.name end)
            for _,place in ipairs(placeList) do
                rows[#rows+1]={kind="row",h=30,title=(direction=="incoming" and "In  " or "Out  ")..place.name.." · "..place.n,note=""}
            end
        end
        if peer.poolChanges+peer.bountyChanges>0 then
            rows[#rows+1]={kind="row",h=30,title=("Changed: %d pools · %d bounty scores"):format(peer.poolChanges,peer.bountyChanges),note=""}
        end
        if peer.errors>0 then rows[#rows+1]={kind="row",h=30,title=peer.errors.." failed or expired transfers",note=""} end
    end
    if #report.changes>0 then rows[#rows+1]={kind="header",h=32,title="Record changes",note=""} end
    for _,change in ipairs(report.changes) do
        local title=change.kind..": "..change.fish.." · "..self:Weight(change.weight)
        local tip=change.previous and (self:Weight(change.previous).." · "..change.previousHolder.." → "..self:Weight(change.weight).." · "..change.holder) or change.holder
        rows[#rows+1]={kind="row",h=44,title=title,note=change.spot.." · from "..change.from,tip=tip}
    end
    if report.omitted>0 then rows[#rows+1]={kind="row",h=30,title=report.omitted.." further changes (totals included)",note=""} end
    if report.truncated then rows[#rows+1]={kind="row",h=30,title="Additional peers omitted (32-peer limit)",note=""} end
    return rows
end
function MF:SyncReportText(report)
    if not report then return "No sync activity yet." end
    local out={"Sync report — "..report.state,date("%d %b %H:%M:%S",report.at),
        "Ends after 20s quiet with no pending transfers or replies. Received includes unchanged data; sends are unconfirmed.",""}
    for _,row in ipairs(self:SyncReportRows(report)) do
        out[#out+1]=row.title
        if row.note~="" then out[#out+1]="  "..row.note end
        if row.tip and row.tip~="" then out[#out+1]="  "..row.tip end
    end
    return table.concat(out,"\n")
end

local function Finish(self, timedOut)
    local report=active
    report.duration=math.floor(GetTime()-report.started)
    report.ended=GetServerTime(); report.state=timedOut and "Timed out" or "Finished"
    for _,key in ipairs(report.order) do
        local peer=report.peers[key]
        if timedOut or peer.errors>0 then peer.state="Incomplete";report.state="Partial"
        elseif not peer.group and not peer.heard then peer.state="No reply";report.state="Partial"
        elseif next(peer.awaiting) then
            local missing={};for category in pairs(peer.awaiting) do missing[#missing+1]=category end;table.sort(missing)
            peer.state="No "..table.concat(missing,"/").." received"; report.state="Partial"
        else peer.state=peer.group and "Sent; unconfirmed" or "Finished" end
        peer.awaiting={}
    end
    local history=self:SyncHistory();table.insert(history,1,report)
    while #history>KEEP do table.remove(history) end
    active=nil
    if self.db.settings.syncReportPopup~=false then pendingPopup=report end
    self:Fire("TFL_SYNC_REPORT_UPDATED",report)
end
function MF:SyncReportTick()
    if active then
        local now=GetTime()
        local waiting=false
        for _,peer in pairs(active.peers) do for _,at in pairs(peer.awaiting) do if now-at<REPLY_WAIT then waiting=true end end end
        if now-active.started>=MAX_AGE then Finish(self,true)
        elseif now-active.last>=QUIET and not waiting and not self:SyncTransfersPending() then Finish(self,false)
        else self:Fire("TFL_SYNC_REPORT_UPDATED",active) end
    end
    if pendingPopup and not (InCombatLockdown and InCombatLockdown()) then
        local report=pendingPopup;pendingPopup=nil
        if self.db.settings.syncReportPopup~=false then self:OpenSyncReport(report) end
    end
end
function MF:ResetSyncActivity()
    active,pendingPopup=nil,nil
    self.syncReceiveContext=nil
end
MF:OnTick(function(self) self:SyncReportTick() end)
MF:Command("synclog","Other","/tfl synclog - recent sync activity",function(self)
    self:OpenSyncReport(active or self:SyncHistory()[1])
end)
