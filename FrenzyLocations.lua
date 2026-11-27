-- Static casting-access patches, independent of catch record identities.
-- Source audit: reports/geography/static-frenzy-research-2026-10-23.
-- These deliberately cover small access areas, not entire named subzones.
local _, MF = ...
-- Stable IDs retain their original schedules as the catalogue grows.
MF.FRENZY_CATALOGUE_VERSION = 4
local function Water(id,name,map,x,y,source,anchors)
    return {id="fw1:"..id,name=name,map=map,x=x/100,y=y/100,radius=25,
        source=source,anchors=anchors}
end
MF.FRENZY_LOCATIONS = {
    Water("approved-1433-2298-5844","Redridge Mountains water (22.98, 58.44)",1433,22.98,58.44,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1431-9326-1103","Duskwood water (93.26, 11.03)",1431,93.26,11.03,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1429-7633-7011","Elwynn Forest water (76.33, 70.11)",1429,76.33,70.11,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1417-2375-5239","Arathi Highlands water (23.75, 52.39)",1417,23.75,52.39,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1417-2565-4928","Arathi Highlands water (25.65, 49.28)",1417,25.65,49.28,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1424-5692-4740","Hillsbrad water (56.92, 47.40)",1424,56.92,47.40,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1424-6097-3337","Hillsbrad water (60.97, 33.37)",1424,60.97,33.37,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1429-7393-7322","Elwynn Forest water (73.93, 73.22)",1429,73.93,73.22,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1429-7486-7111","Elwynn Forest water (74.86, 71.11)",1429,74.86,71.11,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1436-6783-6188","Westfall water (67.83, 61.88)",1436,67.83,61.88,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1424-4303-5448","Hillsbrad water (43.03, 54.48)",1424,43.03,54.48,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1424-5598-5054","Hillsbrad water (55.98, 50.54)",1424,55.98,50.54,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("approved-1431-863-6228","Duskwood water (8.63, 62.28)",1431,8.63,62.28,"Manually reviewed and approved by maintainer, 8 November 2026"),
    Water("hillsbrad-community-6284-4142","Hillsbrad water (62.84, 41.42)",1424,62.8406,41.4161,"Approved 8 November 2026; three reported character anglers with five fishing casts each: South African, Thurite Cielebene, Welsh Gwydion"),
    Water("sw-canals","The Canals",1453,56.05,70.13,"TFL locally observed catch; supplementary access reports",
        {{.5605,.7013},{.5509,.6978},{.7002,.5226}}),
    Water("sw-harbor","Stormwind Harbor",1453,26.14,47.26,"Reported fishing-access point"),
    Water("sw-heroes","Valley of Heroes water",1453,76.12,83.95,"Reported fishing-access point"),
    Water("auberdine","Auberdine coast",1439,36.13,44.61,"Reported fishing-access point"),
    Water("darkshore-inland","Southern inland water",1439,40.60,74.00,"Reported fishing-access point"),
    Water("astranaar","Astranaar water",1440,35.98,53.25,"Reported fishing-access point"),
    Water("mystral","Mystral Lake",1440,48.91,68.23,"Reported fishing-access point"),
    Water("crystal","Crystal Lake",1429,47.68,62.53,"Fishing-access reference point"),
    Water("forlorn","Forlorn Cavern pool",1455,46.74,13.96,"Fishing-access reference point"),
    Water("mirkfallon","Mirkfallon Lake",1442,46.75,41.98,"Fishing-access reference point"),
    Water("cragpool","Cragpool Lake",1442,64.38,43.68,"Fishing-access reference point"),
    Water("lushwater","Lushwater Oasis",1413,46.10,36.84,"Fishing-access reference point"),
    Water("stagnant","The Stagnant Oasis",1413,55.62,41.89,"Fishing-access reference point"),
    Water("loch","The Loch",1432,41.43,38.79,"Fishing-access reference point"),
    Water("iceflow","Iceflow Lake",1426,35.59,40.42,"TFL Iceflow client diagnostics and accepted fishing trace"),
    Water("stone-cairn","Stone Cairn Lake",1429,70.75,58.34,"Requested; TFL a86 fish records and current map-consistent saved access"),
    Water("everstill","Lake Everstill",1433,22.900003194809,52.964794635773,"Requested; TFL a68 personal fish records and locally saved casting access"),
    Water("stendels","Stendel's Pond",1436,45.983493328094,57.774865627289,"Requested; TFL a919 personal fish records and locally saved casting access"),
    Water("eluneara","Lake Elune'ara",1450,63.38,61.07,"Requested; TFL a656 fish records and current map-consistent saved access"),
    Water("steamwheedle","Steamwheedle Port",1446,67.805814743042,26.974546909332,"Requested; TFL a977 personal fish records and locally saved shoreline casting access"),
    Water("helms-bed","Helm's Bed Lake",1426,75.915265083313,53.258144855499,"TFL a212 personal fish records and exact locally observed catch position"),
    Water("darrowmere","Darrowmere Lake",1422,60.144126415253,84.200358390808,"TFL a2297 personal fish records and locally saved casting access"),
    Water("wellspring","Wellspring Lake",1438,42.857915163040,41.371059417725,"TFL a266 personal fish records and exact locally observed catch position"),
    Water("nazferiti","Lake Nazferiti",1434,40.873956680298,14.623349905014,"TFL a37 personal fish records and locally saved casting access"),
    Water("iris","Iris Lake",1440,45.334464311600,46.621149778366,"TFL a424 personal fish records and locally saved casting access"),
    Water("falathim","Lake Falathim",1440,20.963597297668,42.553508281708,"TFL a441 personal fish records and locally saved casting access"),
    Water("mirror","Mirror Lake",1429,31.075894832611,61.385715007782,"TFL a92 personal fish records and exact locally observed catch position"),
    Water("brightwater","Brightwater Lake",1420,68.59,53.07,"TFL a162 shared fish records and current map-consistent saved access; old quarantined point not used"),
    Water("stonebull","Stonebull Lake",1412,43.94,63.82,"TFL a223 shared fish records and current map-consistent saved access"),
    Water("alameth","Lake Al'Ameth",1438,57.89,69.53,"TFL a259 shared fish records and current map-consistent saved access"),
    Water("fallen-sky","Fallen Sky Lake",1440,65.96,79.79,"TFL a422 shared fish records and current map-consistent saved access"),
    Water("stillwater","Stillwater Pond",1420,50.24,52.70,"TFL a810 shared fish records and current map-consistent saved access"),
    Water("wildwind","Wildwind Lake",1444,77.53,43.85,"TFL a1102 shared fish records and current map-consistent saved access"),
    Water("lordamere-silverpine","Lordamere Lake — Silverpine shore",1421,59.86,34.26,"TFL a1338 fish records and map-specific access; distinct from ambiguous cross-map a170"),
    Water("lordamere-alterac","Lordamere Lake — Alterac shore",1416,21.83,45.63,"TFL a1339 fish records and map-specific access; distinct from ambiguous cross-map a170"),
    -- Community discoveries approved by the maintainer on 13 November 2026,
    -- including single-angler points so new areas such as Riverglades have frenzies.
    Water("community-1416-2328-8299","Alterac Mountains water (23.28, 82.99)",1416,23.2781,82.9860,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1416-8831-4741","Alterac Mountains water (88.31, 47.41)",1416,88.3103,47.4098,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1416-9040-4571","Alterac Mountains water (90.40, 45.71)",1416,90.4018,45.7084,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1417-2471-5393","Arathi Highlands water (24.71, 53.93)",1417,24.7136,53.9277,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1417-2937-5364","Arathi Highlands water (29.37, 53.64)",1417,29.3715,53.6443,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1417-4371-7215","Arathi Highlands water (43.71, 72.15)",1417,43.7069,72.1544,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1417-4380-8459","Arathi Highlands water (43.80, 84.59)",1417,43.7965,84.5931,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1421-6900-4361","Silverpine water (69.00, 43.61)",1421,69.0010,43.6091,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1424-5524-5659","Hillsbrad water (55.23, 56.59)",1424,55.2350,56.5922,"Approved by maintainer 13 November 2026 from community discovery; 5 qualifying anglers"),
    Water("community-1424-6237-4320","Hillsbrad water (62.37, 43.20)",1424,62.3651,43.1995,"Approved by maintainer 13 November 2026 from community discovery; 2 qualifying anglers"),
    Water("community-1424-6548-3859","Hillsbrad water (65.48, 38.59)",1424,65.4823,38.5944,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1424-6748-2998","Hillsbrad water (67.48, 29.98)",1424,67.4842,29.9795,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1424-6794-3564","Hillsbrad water (67.94, 35.64)",1424,67.9439,35.6367,"Approved by maintainer 13 November 2026 from community discovery; 2 qualifying anglers"),
    Water("community-1424-6802-2639","Hillsbrad water (68.02, 26.39)",1424,68.0159,26.3937,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1424-6863-1808","Hillsbrad water (68.63, 18.08)",1424,68.6338,18.0769,"Approved by maintainer 13 November 2026 from community discovery; 2 qualifying anglers"),
    Water("community-1424-6905-1330","Hillsbrad water (69.05, 13.30)",1424,69.0453,13.2999,"Approved by maintainer 13 November 2026 from community discovery; 2 qualifying anglers"),
    Water("community-1431-9495-1113","Duskwood water (94.95, 11.13)",1431,94.9509,11.1286,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1433-5955-6584","Redridge Mountains water (59.55, 65.84)",1433,59.5472,65.8386,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1433-6274-7239","Redridge Mountains water (62.74, 72.39)",1433,62.7397,72.3897,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1434-3055-635","Stranglethorn water (30.55, 6.35)",1434,30.5508,6.3498,"Approved by maintainer 13 November 2026 from community discovery; 2 qualifying anglers"),
    Water("community-1437-1155-5145","Wetlands water (11.55, 51.45)",1437,11.5484,51.4519,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1437-1544-4600","Wetlands water (15.44, 46.00)",1437,15.4414,45.9982,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1437-3018-4158","Wetlands water (30.18, 41.58)",1437,30.1794,41.5777,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1437-3410-3799","Wetlands water (34.10, 37.99)",1437,34.0975,37.9873,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1437-5437-4583","Wetlands water (54.37, 45.83)",1437,54.3711,45.8335,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1437-6050-7036","Wetlands water (60.50, 70.36)",1437,60.4975,70.3564,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1437-6148-6780","Wetlands water (61.48, 67.80)",1437,61.4807,67.8044,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1440-3665-6109","Ashenvale water (36.65, 61.09)",1440,36.6504,61.0860,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1443-5907-8233","Desolace water (59.07, 82.33)",1443,59.0693,82.3281,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1445-3922-4415","Dustwallow Marsh water (39.22, 44.15)",1445,39.2247,44.1545,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1445-4010-3651","Dustwallow Marsh water (40.10, 36.51)",1445,40.0975,36.5140,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1445-4575-2586","Dustwallow Marsh water (45.75, 25.86)",1445,45.7514,25.8568,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-4894-5405","Riverglades water (48.94, 54.05)",2548,48.9420,54.0523,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-4924-7802","Riverglades water (49.24, 78.02)",2548,49.2400,78.0154,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-4994-9322","Riverglades water (49.94, 93.22)",2548,49.9404,93.2229,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-5447-9128","Riverglades water (54.47, 91.28)",2548,54.4684,91.2844,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-5562-8087","Riverglades water (55.62, 80.87)",2548,55.6210,80.8704,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-5654-8541","Riverglades water (56.54, 85.41)",2548,56.5407,85.4108,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-6103-7878","Riverglades water (61.03, 78.78)",2548,61.0303,78.7817,"Approved by maintainer 13 November 2026 from community discovery; 1 qualifying angler"),
    -- Approved 14 November 2026: the first waters reported by Horde anglers through the realm list.
    Water("community-1416-1714-5269","Alterac Mountains water (17.14, 52.69)",1416,17.1438,52.6923,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1421-6012-3693","Silverpine water (60.12, 36.93)",1421,60.1242,36.9349,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1421-6879-4527","Silverpine water (68.79, 45.27)",1421,68.7892,45.2679,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1424-6208-3173","Hillsbrad water (62.08, 31.73)",1424,62.0765,31.7253,"Approved by maintainer 14 November 2026 from community discovery; 2 qualifying anglers"),
    -- Approved 14 November 2026, second pass: further realm-list reports, including Thunder Bluff.
    Water("community-1456-4166-5787","Thunder Bluff water (41.66, 57.87)",1456,41.6639,57.8718,"Approved by maintainer 14 November 2026 from community discovery; 4 qualifying anglers"),
    Water("community-1424-6074-2979","Hillsbrad water (60.74, 29.79)",1424,60.7377,29.7906,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1421-4765-2658","Silverpine water (47.65, 26.58)",1421,47.6517,26.5780,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-2548-5666-4293","Riverglades water (56.66, 42.93)",2548,56.6610,42.9253,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1444-7443-3553","Feralas water (74.43, 35.53)",1444,74.4301,35.5277,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("community-1444-7403-3702","Feralas water (74.03, 37.02)",1444,74.0281,37.0158,"Approved by maintainer 14 November 2026 from community discovery; 1 qualifying angler"),
    Water("approved-1446-6730-1850","Tanaris water (67.30, 18.50)",1446,67.30,18.50,"Manually reviewed and approved by maintainer, 14 November 2026"),
}
local function Number(v,lo,hi)
    return type(v)=="number" and v==v and v>=lo and v<=hi
end
function MF:FrenzyZoneLabel(map)
    return self:ZoneNameFor(map) or self.ZONE_IDS[map] or ("Map "..tostring(map))
end
-- A zone's size never changes, and the pool scan asks thousands of times.
local mapSizes={}
function MF:FrenzyMapSize(map)
    local known=mapSizes[map]
    if known then return known[1],known[2] end
    if type(LibStub)~="table" or type(LibStub.GetLibrary)~="function" then return end
    local ok,lib=pcall(LibStub.GetLibrary,LibStub,"HereBeDragons-2.0",true)
    if not ok or not lib or type(lib.GetZoneSize)~="function" then return end
    local w,h=lib:GetZoneSize(map)
    if Number(w,1,100000) and Number(h,1,100000) then
        mapSizes[map]={w,h}
        return w,h
    end
end
function MF:FrenzyDistance(map,x,y,xx,yy)
    if not Number(x,0,1) or not Number(y,0,1) or not Number(xx,0,1) or not Number(yy,0,1) then return end
    local w,h=self:FrenzyMapSize(map)
    if not w then return end -- Never replace unavailable yard scales with map percentages.
    return math.sqrt(((x-xx)*w)^2+((y-yy)*h)^2)
end
function MF:StaticFrenzyByID(id)
    for _,w in ipairs(self.FRENZY_LOCATIONS) do if w.id==id then return w end end
end
function MF:StaticFrenzyAt(map,x,y)
    local best,distance
    for _,w in ipairs(self.FRENZY_LOCATIONS) do
        if w.map==map then
            for _,a in ipairs(w.anchors or {{w.x,w.y}}) do
                local d=self:FrenzyDistance(map,x,y,a[1],a[2])
                if d and d<=w.radius and (not distance or d<distance or (d==distance and w.id<best.id)) then best,distance=w,d end
            end
        end
    end
    return best
end
function MF:ResolveFrenzyLocation(key)
    local static=self:StaticFrenzyByID(key)
    if static then return static end -- An explicit catalogue lookup for a map pin.
    local current=self:CurrentSpot()
    if not key or key==current.key then
        if type(UnitOnTaxi)=="function" and UnitOnTaxi("player")==true then return end
        if type(IsInInstance)=="function" and IsInInstance()==true then return end
        return self:StaticFrenzyAt(current.mapID,current.x,current.y)
    end
    local p=self:SpotPosition(key)
    if p then return self:StaticFrenzyAt(p.map,p.x,p.y) end
end

-- Community observations never become active geography automatically.
-- Each sender can attest only their own capped cumulative progress.
local MAX_WATERS,MAX_ANGLERS,AGE=500,20,30*86400
local castEvidence,lastCatch
local requests={}
function MF:FrenzyDiscoveryStore()
    if type(self.db.frenzyDiscoveries)~="table" then self.db.frenzyDiscoveries={} end
    local store,now=self.db.frenzyDiscoveries,GetServerTime()
    for i=#store,1,-1 do
        local n=store[i]
        if type(n)~="table" or type(n.id)~="string" or not self.ZONE_IDS[n.map]
            or not Number(n.x,0,1) or not Number(n.y,0,1) or type(n.anglers)~="table" then table.remove(store,i)
        else
            for k,a in pairs(n.anglers) do
                if type(k)~="string" or type(a)~="table" or type(a.name)~="string"
                    or not Number(a.x,0,1) or not Number(a.y,0,1)
                    or not Number(a.at,now-AGE,now+60) or not Number(a.count,1,5) or a.count~=math.floor(a.count) then n.anglers[k]=nil end
            end
            if not next(n.anglers) then table.remove(store,i) end
        end
    end
    return self.db.frenzyDiscoveries
end
function MF:IsUnnamedFishingSpot(s)
    if not s or not s.key then return false end
    return s.key:match("^%d+@%d+,%d+$")~=nil or s.key:match("^%d+$")~=nil
        or s.name==self:ZoneNameFor(s.mapID) or s.name==self.ZONE_IDS[s.mapID]
end
function MF:MergeFrenzyObservation(sender,map,x,y,count,at,mine)
    local now=GetServerTime()
    if type(sender)~="string" or #sender<2 or #sender>100 or sender:find("[%c~|]") then return end
    if not Number(map,1,3000) or map~=math.floor(map) or not self.ZONE_IDS[map] or map==1414 or map==1415
        or not Number(count,1,5) or count~=math.floor(count)
        or not Number(at,math.max(1,now-AGE),now+60) or at~=math.floor(at)
        or (now>=self.FRESH_START and at<self.FRESH_START)
        or not self:FrenzyDistance(map,x,y,x,y) or self:StaticFrenzyAt(map,x,y) then return end
    local who=self:AnglerKey(sender)
    if who=="" then return end
    local store=self:FrenzyDiscoveryStore()
    local found,nearest
    for _,n in ipairs(store) do
        local d=n.map==map and self:FrenzyDistance(map,x,y,n.x,n.y)
        -- Anchor never moves: a chain of catches cannot bridge two lakes.
        if d and d<=40 and (not nearest or d<nearest or (d==nearest and n.id<found.id)) then found,nearest=n,d end
    end
    if not found then
        if #store>=MAX_WATERS then return end
        found={id=("%d:%d:%d"):format(map,math.floor(x*1000000+.5),math.floor(y*1000000+.5)),
            map=map,x=x,y=y,anglers={}}
        store[#store+1]=found
    end
    local old=found.anglers[who]
    if not old and self.Count(found.anglers)>=MAX_ANGLERS then return end
    if old and old.at>=now-AGE and (count<old.count or at<old.at or (at==old.at and count==old.count)) then return found end
    found.anglers[who]={name=sender,count=count,at=at,x=x,y=y,mine=mine or (old and old.mine) or false}
    self:RefreshJournal()
    return found
end
-- Review decisions are shipped geography, never accepted from peer messages.
MF.FRENZY_REJECTIONS = { { map=1431, x=.8630, y=.2068, radius=25,
    reason="Maintainer reviewed and rejected this point on 8 November 2026." } }
function MF:FrenzyDiscoveryStatus(n)
    if self:StaticFrenzyAt(n.map,n.x,n.y) then return "Approved" end
    for _, decision in ipairs(self.FRENZY_REJECTIONS) do
        local distance = decision.map==n.map and self:FrenzyDistance(n.map,n.x,n.y,decision.x,decision.y)
        if distance and distance<=decision.radius then return "Rejected" end
    end
    local ready = self:FrenzyDiscoveryProgress(n)
    return ready and "Awaiting review" or "Collecting"
end
function MF:InspectFrenzyPoint(map,x,y)
    local marked = self:PointToCoordinates({ map=map,x=x,y=y })
    if OpenWorldMap then pcall(OpenWorldMap,map)
    elseif WorldMapFrame then
        pcall(ShowUIPanel,WorldMapFrame)
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID,WorldMapFrame,map) end
    end
    self:Print(("%s: %.2f, %.2f%s"):format(self:FrenzyZoneLabel(map),x*100,y*100,
        marked and "" or " (no waypoint available on this client)"))
end

function MF:FrenzyDiscoveryProgress(n)
    local qualified,total=0,0
    for _,a in pairs(n.anglers or {}) do
        if a.at>=GetServerTime()-AGE then total=total+1 if a.count>=5 then qualified=qualified+1 end end
    end
    return qualified>=3,qualified,total
end
function MF:UpdateFrenzyDiscoveryReview(n)
    local ready=self:FrenzyDiscoveryProgress(n)
    if ready and self:FrenzyDiscoveryStatus(n)=="Awaiting review" and not n.reviewNotified then
        n.reviewNotified=true
        self:Print(("Unnamed water in %s has three anglers with five catches each. Added to the Frenzy List for review; no frenzy has been enabled."):format(self:FrenzyZoneLabel(n.map)))
    end
    self:RefreshJournal()
end
function MF:ResetFrenzyDiscoveryRuntime() castEvidence,lastCatch,requests=nil,nil,{} end
MF:On("TFL_FISHING_CAST",function(self)
    self:ForgetCurrentSpot()
    local s=self:CurrentSpot()
    castEvidence={key=s.key,name=s.name,mapID=s.mapID,x=s.x,y=s.y,at=GetServerTime(),used=false}
    if (type(IsInInstance)=="function" and IsInInstance()==true)
        or (type(UnitOnTaxi)=="function" and UnitOnTaxi("player")==true) then castEvidence=nil return end
    local w=self:StaticFrenzyAt(s.mapID,s.x,s.y)
    castEvidence.water=w and w.id
    castEvidence.frenzy=w and (self:FrenzyState(w.id)) or false
end)
function MF:FrenzyCatchState()
    local s=castEvidence
    if not s or GetServerTime()<s.at or GetServerTime()-s.at>45 then return false end
    return s.frenzy,s.water
end
function MF:ObserveFrenzyCatch(c)
    local s=castEvidence
    if c.test or c.junk or not self.FISH[c.itemID] or not s or s.used
        or not self:IsUnnamedFishingSpot(s)
        or GetServerTime()-s.at>45 or GetServerTime()<s.at then return end
    -- The accepted fishing cast supplies the location, not where loot was opened.
    s.used=true
    local now=GetServerTime()
    if lastCatch==s.at then return end
    lastCatch=s.at
    local n=self:MergeFrenzyObservation(self.me,s.mapID,s.x,s.y,1,now,true)
    if not n then return end
    local who=self:AnglerKey(self.me)
    -- Find this character's private progress; never increment a peer claim.
    if type(self.cdb.frenzyProgress)~="table" then self.cdb.frenzyProgress={} end
    for key,p in pairs(self.cdb.frenzyProgress) do
        if type(p)~="table" or not Number(p.at,now-AGE,now+60) or not Number(p.count,1,5)
            or p.count~=math.floor(p.count) then self.cdb.frenzyProgress[key]=nil end
    end
    if not self.cdb.frenzyProgress[n.id] and self.Count(self.cdb.frenzyProgress)>=MAX_WATERS then return end
    local old=self.cdb.frenzyProgress[n.id]
    local count=old and old.at>=now-AGE and math.min(5,old.count+1) or 1
    local published=old and Number(old.published,0,now) and old.published or 0
    self.cdb.frenzyProgress[n.id]={count=count,at=now,x=s.x,y=s.y,map=s.mapID,published=published}
    n.anglers[who]={name=self.me,count=count,at=now,x=s.x,y=s.y,mine=true}
    self:UpdateFrenzyDiscoveryReview(n)
    if not old or old.count<5 or old.at<now-AGE or now-published>=300 then
        self:SendWide("FWOBS1",s.mapID,math.floor(s.x*1000000+.5),math.floor(s.y*1000000+.5),count,now)
        self.cdb.frenzyProgress[n.id].published=now
    end
end
MF:On("TFL_CATCH",MF.ObserveFrenzyCatch)
function MF.handlers.FWOBS1(self,sender,map,x,y,count,at)
    if self:SameAngler(sender,self.me) then return end
    map,x,y,count,at=tonumber(map),tonumber(x),tonumber(y),tonumber(count),tonumber(at)
    if not x or not y then return end
    local n=self:MergeFrenzyObservation(sender,map,x/1000000,y/1000000,count,at,false)
    if n then self:UpdateFrenzyDiscoveryReview(n) end
end
function MF:ShareOwnFrenzyObservations(target)
    local rows=self.cdb.frenzyProgress or {}
    local sorted={}
    if type(rows)~="table" then return end
    for _,p in pairs(rows) do
        if type(p)=="table" and self.ZONE_IDS[p.map] and Number(p.x,0,1) and Number(p.y,0,1)
            and Number(p.count,1,5) and p.count==math.floor(p.count)
            and Number(p.at,GetServerTime()-AGE,GetServerTime()+60) then sorted[#sorted+1]=p end
    end
    table.sort(sorted,function(a,b)return a.at>b.at end)
    for i=1,math.min(50,#sorted) do
        local p=sorted[i]
        if target then self:Whisper(target,"FWOBS1",p.map,math.floor(p.x*1000000+.5),math.floor(p.y*1000000+.5),p.count,p.at)
        else self:SendWide("FWOBS1",p.map,math.floor(p.x*1000000+.5),math.floor(p.y*1000000+.5),p.count,p.at) end
    end
end
function MF.handlers.FWREQ1(self,sender)
    local who=self:AnglerKey(sender)
    for key,at in pairs(requests) do if GetTime()-at>=300 then requests[key]=nil end end
    if self.Count(requests)>=100 then return end
    if self:SameAngler(sender,self.me) or (requests[who] and GetTime()-requests[who]<300) then return end
    requests[who]=GetTime()
    self:ReplySoon(2,8,function() self:ShareOwnFrenzyObservations(sender) end)
end
-- One angler, by whisper: how the realm list and /tfl sync <name> reach
-- anglers outside our guild and group. They answer with their own
-- observations only, at most every five minutes per asker (FWREQ1 above).
function MF:RequestFrenzyObservations(peer)
    if type(peer)=="string" and peer~="" and not self:SameAngler(peer,self.me) then self:Whisper(peer,"FWREQ1") end
end
MF:On("TFL_LOGIN",function(self)
    -- Comm deliberately joins after 30 seconds to protect General/Trade order.
    self:ReplySoon(40,10,function()
        self:ShareOwnFrenzyObservations()
        self:SendWide("FWREQ1")
    end)
end)
-- Keep catalogue order stable for identities; presentation has its own ordering.
function MF:FrenzyPlannerRows()
    local current=self:CurrentSpot()
    local here=self:ResolveFrenzyLocation()
    local rows={}
    for _,w in ipairs(self.FRENZY_LOCATIONS) do
        if not self.frenzyLocalOnly or w.map==current.mapID then
            local active,left=self:FrenzyState(w.id)
            rows[#rows+1]={water=w,active=active,left=left,localZone=w.map==current.mapID,
                here=here and here.id==w.id or false}
        end
    end
    table.sort(rows,function(a,b)
        if a.active~=b.active then return a.active end
        if a.localZone~=b.localZone then return a.localZone end
        if a.left~=b.left then return a.left<b.left end
        if a.water.name~=b.water.name then return a.water.name<b.water.name end
        return a.water.id<b.water.id
    end)
    return rows
end
function MF:FrenzyListLines()
    local discovery=self.frenzyListView=="discoveries"
    local out={{text=self.C.gold..(discovery and "Community discoveries" or "Frenzy planner").."|r",header=true}}
    if not discovery then
        self:NoteRows(out,"Your zone first within each section, then shortest time. Hover a water for its access point.")
        local rows=self:FrenzyPlannerRows()
        for _,active in ipairs({true,false}) do
            local count=0
            for _,r in ipairs(rows) do if r.active==active then count=count+1 end end
            out[#out+1]={text=(active and "|cffff9d00Active now" or self.C.gold.."Upcoming").." ("..count..")|r",header=true}
            for _,r in ipairs(rows) do
                if r.active==active then
                    local w=r.water
                    local tip={self:FrenzyZoneLabel(w.map),
                        ("Access: %.2f, %.2f; within %d yards"):format(w.x*100,w.y*100,w.radius),w.source,
                        "Only the small marked access area is supported, not the whole named subzone."}
                    out[#out+1]={text=(r.here and self.C.good or self.C.text)..w.name.."|r",
                        right=(active and "|cffff9d00Ends in " or self.C.hint.."Starts in ")..self:FormatClock(r.left).."|r",
                        group=true,tooltip=tip,onClick=function() self:InspectFrenzyPoint(w.map,w.x,w.y) end}
                    out[#out+1]={text=self.C.muted.."    "..self:FrenzyZoneLabel(w.map).."|r",
                        right=r.here and self.C.good.."You are here|r" or r.localZone and self.C.hint.."Your zone|r" or nil,
                        tooltip=tip}
                end
            end
            if count==0 then self:NoteRows(out,active and "No active waters in this view." or "No upcoming waters in this view.") end
        end
        return out
    end
    self:NoteRows(out,"Three anglers, five successful casts each. Qualified waters await review and remain inactive.")
    out[#out+1]={text=self.C.gold.."Community discoveries|r",header=true}
    local rows={}
    for _,n in ipairs(self:FrenzyDiscoveryStore()) do
        if not self.frenzyLocalOnly or n.map==self:CurrentSpot().mapID then rows[#rows+1]=n end
    end
    table.sort(rows,function(a,b)
        local ar,aq=self:FrenzyDiscoveryProgress(a)
        local br,bq=self:FrenzyDiscoveryProgress(b)
        if ar~=br then return ar end
        if aq~=bq then return aq>bq end
        return a.id<b.id
    end)
    for _,n in ipairs(rows) do
        local ready,qualified,total=self:FrenzyDiscoveryProgress(n)
        local status=self:FrenzyDiscoveryStatus(n)
        local inspect=function() self:InspectFrenzyPoint(n.map,n.x,n.y) end
        local names={}
        for _,a in pairs(n.anglers) do if a.at>=GetServerTime()-AGE then names[#names+1]=self:ShortName(a.name)..": "..a.count.."/5 catches" end end
        table.sort(names)
        local tip={"Sender-reported observations from the last 30 days; character identities, not verified accounts."}
        for _,line in ipairs(names) do tip[#tip+1]=line end
        out[#out+1]={text=(ready and self.C.gold or self.C.muted).."Unnamed water — "..self:FrenzyZoneLabel(n.map).."|r",
            right=status=="Collecting" and (qualified.."/3 anglers") or status,tooltip=tip,onClick=inspect}
        out[#out+1]={text=("%.2f, %.2f — %d participating anglers"):format(n.x*100,n.y*100,total),
            right=status=="Approved" and "In catalogue" or status=="Rejected" and "Inactive - rejected" or "Inactive",onClick=inspect}
    end
    if #rows==0 then self:NoteRows(out,"No unnamed waters reported yet. Genuine fishing casts build evidence; test catches and duplicate loot do not count.") end
    self:PoolCandidateLines(out)
    return out
end
------------------------------------------------------------------------
-- Pool sightings as places worth checking
--
-- A pool proves fish, not a frenzy water, and atlas entries carry no proof
-- of who saw them. So a busy cluster of sightings never joins the catalogue
-- by itself: it is only pointed at, so anglers go and fish there and the
-- ordinary three-anglers-five-catches evidence can build up.
------------------------------------------------------------------------

local CLUSTER_YARDS = 60  -- pools this close are one stretch of water
local CLEAR_YARDS = 40    -- beyond a catalogue water's own radius
local MIN_SIGHTINGS = 3   -- distinct pool spots in one cluster, or
local MIN_WITNESSES = 2   -- this many anglers who saw them first-hand
local MAX_CANDIDATES = 25

local function Covered(self, map, x, y, store)
    for _, w in ipairs(self.FRENZY_LOCATIONS) do
        if w.map == map then
            for _, a in ipairs(w.anchors or {{w.x, w.y}}) do
                local d = self:FrenzyDistance(map, x, y, a[1], a[2])
                if d and d <= w.radius + CLEAR_YARDS then return true end
            end
        end
    end
    for _, r in ipairs(self.FRENZY_REJECTIONS) do
        local d = r.map == map and self:FrenzyDistance(map, x, y, r.x, r.y)
        if d and d <= r.radius + CLEAR_YARDS then return true end
    end
    for _, n in ipairs(store) do
        local d = n.map == map and self:FrenzyDistance(map, x, y, n.x, n.y)
        if d and d <= CLEAR_YARDS then return true end
    end
end

-- Clusters of pool sightings away from every known or reported water:
-- { map, x, y, sightings, horde, alliance, unknown, newest, names }.
-- The list redraws often and the atlas holds thousands of entries, so the
-- answer is kept for a little while.
local candidateCache, candidateAt = nil, -math.huge
function MF:PoolFrenzyCandidates()
    if candidateCache and GetTime() - candidateAt < 30 then return candidateCache end
    local clusters, store = {}, self:FrenzyDiscoveryStore()
    for _, p in ipairs(self.db.poolAtlas or {}) do
        if type(p) == "table" and self.ZONE_IDS[p.map] and p.map ~= 1414 and p.map ~= 1415
            and self:FrenzyMapSize(p.map) and not Covered(self, p.map, p.x, p.y, store) then
            local home
            for _, c in ipairs(clusters) do
                local d = c.map == p.map and self:FrenzyDistance(p.map, p.x, p.y, c.ax, c.ay)
                if d and d <= CLUSTER_YARDS then home = c break end
            end
            if not home then
                -- The first pool anchors the cluster, so a chain can't creep along a coast.
                home = { map = p.map, ax = p.x, ay = p.y, sx = 0, sy = 0, sightings = 0,
                    by = {}, newest = 0, names = {} }
                clusters[#clusters + 1] = home
            end
            home.sightings = home.sightings + 1
            home.sx, home.sy = home.sx + p.x, home.sy + p.y
            home.newest = math.max(home.newest, tonumber(p.at) or 0)
            home.names[p.name] = (home.names[p.name] or 0) + 1
            for key, letter in pairs(type(p.by) == "table" and p.by or {}) do
                if letter == "?" then letter = self.db.factions[key] or "?" end
                if home.by[key] == nil or home.by[key] == "?" then home.by[key] = letter end
            end
        end
    end
    local out = {}
    for _, c in ipairs(clusters) do
        local h, a, u = 0, 0, 0
        for _, letter in pairs(c.by) do
            if letter == "H" then h = h + 1 elseif letter == "A" then a = a + 1 else u = u + 1 end
        end
        if c.sightings >= MIN_SIGHTINGS or h + a + u >= MIN_WITNESSES then
            out[#out + 1] = { map = c.map, x = c.sx / c.sightings, y = c.sy / c.sightings,
                sightings = c.sightings, horde = h, alliance = a, unknown = u,
                witnesses = h + a + u, newest = c.newest, names = c.names }
        end
    end
    -- Your own side's reports first: they are the waters you can go and check.
    local mine = self:MyFaction() == "H" and "horde" or "alliance"
    table.sort(out, function(p, q)
        if (p[mine] > 0) ~= (q[mine] > 0) then return p[mine] > 0 end
        if p.witnesses ~= q.witnesses then return p.witnesses > q.witnesses end
        if p.sightings ~= q.sightings then return p.sightings > q.sightings end
        return p.newest > q.newest
    end)
    for i = #out, MAX_CANDIDATES + 1, -1 do out[i] = nil end
    candidateCache, candidateAt = out, GetTime()
    return out
end

function MF:PoolCandidateWitnessText(c)
    if c.witnesses == 0 then return "no first-hand reports yet" end
    local parts = {}
    if c.horde > 0 then parts[#parts + 1] = c.horde .. " Horde" end
    if c.alliance > 0 then parts[#parts + 1] = c.alliance .. " Alliance" end
    if c.unknown > 0 then parts[#parts + 1] = c.unknown .. " unknown" end
    return table.concat(parts, ", ") .. (c.witnesses == 1 and " angler" or " anglers")
end

function MF:PoolCandidateLines(out)
    out[#out + 1] = { text = self.C.gold .. "Suggested by pool sightings|r", header = true }
    self:NoteRows(out, "Busy pool waters with no frenzy water nearby. Not reviewed: fish here so evidence can build.")
    local here = self:CurrentSpot().mapID
    local shown = 0
    for _, c in ipairs(self:PoolFrenzyCandidates()) do
        if not self.frenzyLocalOnly or c.map == here then
            shown = shown + 1
            local names = {}
            for name, n in pairs(c.names) do names[#names + 1] = name .. (n > 1 and (" x" .. n) or "") end
            table.sort(names)
            local tip = { ("%s %.2f, %.2f"):format(self:FrenzyZoneLabel(c.map), c.x * 100, c.y * 100),
                "Pools seen: " .. table.concat(names, ", "),
                "First-hand: " .. self:PoolCandidateWitnessText(c),
                "Last seen " .. date("%d %b", c.newest),
                "Catches count toward a discovery only where TFL shows the water as unnamed.",
                "Pool sightings alone never add a water to the catalogue." }
            local inspect = function() self:InspectFrenzyPoint(c.map, c.x, c.y) end
            out[#out + 1] = { text = self.C.text .. "Pool water — " .. self:FrenzyZoneLabel(c.map) .. "|r",
                right = c.sightings .. (c.sightings == 1 and " sighting" or " sightings"), tooltip = tip, onClick = inspect }
            out[#out + 1] = { text = self.C.muted .. ("    %.2f, %.2f — %s"):format(c.x * 100, c.y * 100,
                self:PoolCandidateWitnessText(c)) .. "|r", right = self.C.hint .. "Unchecked|r", tooltip = tip, onClick = inspect }
        end
    end
    if shown == 0 then self:NoteRows(out, "No busy pool waters away from known frenzy waters yet.") end
end

function MF:FrenzyReviewText()
    local out={"TFL frenzy discovery review | catalogue "..self.FRENZY_CATALOGUE_VERSION,
        "Three distinct character anglers with five genuine fishing casts each. Sender-reported, not account verification. No automatic activation."}
    for _,n in ipairs(self:FrenzyDiscoveryStore()) do
        local ready,qualified,total=self:FrenzyDiscoveryProgress(n)
        out[#out+1]=("%s | map %d | %.5f, %.5f | %d/3 qualified, %d participants | %s"):format(
            self:FrenzyZoneLabel(n.map),n.map,n.x*100,n.y*100,qualified,total,self:FrenzyDiscoveryStatus(n):upper())
        local lines={}
        for _,a in pairs(n.anglers) do
            if a.at>=GetServerTime()-AGE then lines[#lines+1]=("  %s | %d/5 | %.5f, %.5f | %s"):format(a.name,a.count,a.x*100,a.y*100,date("%Y-%m-%d %H:%M",a.at)) end
        end
        table.sort(lines)
        for _,line in ipairs(lines) do out[#out+1]=line end
    end
    out[#out+1]="Suggested by pool sightings (not evidence on their own):"
    for _,c in ipairs(self:PoolFrenzyCandidates()) do
        local names={}
        for name,n in pairs(c.names) do names[#names+1]=name.." x"..n end
        table.sort(names)
        out[#out+1]=("%s | map %d | %.5f, %.5f | %d sightings | first-hand: %s | last %s | %s"):format(
            self:FrenzyZoneLabel(c.map),c.map,c.x*100,c.y*100,c.sightings,self:PoolCandidateWitnessText(c),
            date("%Y-%m-%d",c.newest),table.concat(names,", "))
    end
    return table.concat(out,"\n")
end
MF:Command("frenzies","Solo","/tfl frenzies - fixed waters and community discovery review",function(self) self:OpenAnglingTools("frenzies") end)
