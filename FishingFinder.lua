-- Forever fishing planner. Observed skill gains are not minimum catch requirements.
local _, MF = ...
local levels={
 [1429]=1,[1426]=1,[1420]=1,[1411]=1,[1412]=1,[1438]=1,
 [1439]=10,[1436]=10,[1421]=10,[1413]=10,[1432]=10,[1433]=15,
 [1431]=18,[1440]=18,[1424]=20,[1442]=15,[1437]=20,[1441]=25,
 [1417]=30,[1416]=30,[1443]=30,[1434]=30,[1445]=35,[1435]=35,
 [1444]=40,[1425]=40,[1446]=40,[1447]=45,[1448]=48,[1449]=48,
 [1422]=50,[1423]=53,[1452]=55,[1451]=55,[1450]=10,

}
local cities={[1453]="Alliance",[1455]="Alliance",[1457]="Alliance",
 [1454]="Horde",[1456]="Horde",[1458]="Horde"}
local names={}
local function Heading(self,text) return {text=self.C.gold..text.."|r",header=true} end
function MF:FinderTravelLevel(map)
 if C_Map and type(C_Map.GetMapLevels)=="function" then
  local ok,low=pcall(C_Map.GetMapLevels,map)
  if ok and not self:IsSecret(low) and type(low)=="number" and low==low and low>=1 and low<=100 then
   return math.floor(low),"Client map levels"
  end
 end
 return levels[map] or (cities[map] and 1),"Estimated travel level"
end
function MF:OpenFishFinder(id)
 self.finderFish=id;self.finderSelected=nil
 self:OpenAnglingTools("finder")
end
function MF:FinderInputs()
 local rank,_,bonus=self:FishingSkill()
 local level=UnitLevel("player")
 return self.finderSkill or (rank and rank+(bonus or 0)),self.finderLevel or (type(level)=="number" and level or 1)
end
function MF:FinderWaters()
 local rows={}
 for map,zone in pairs(self.ZONE_IDS) do
  if map~=1414 and map~=1415 then
   local fish={}
   for id,f in pairs(self.FISH) do
     for _,home in ipairs(f.zones or {}) do if home==zone then fish[#fish+1]=id break end end
   end
   local present={};for _,id in ipairs(fish) do present[id]=true end
   local mine={}
   for id,byZone in pairs(self.cdb.caughtIn or {}) do
    local catch=byZone[zone]
    if (self.FISH[id] or self.cdb.profile.journal[id]) and type(catch)=="table" and (catch.c or 0)>0 then
     mine[id]=true;if not present[id] then fish[#fish+1]=id;present[id]=true end
    end
   end
   local level,levelSource=self:FinderTravelLevel(map)
   if #fish>0 then rows[#rows+1]={map=map,name="Zone waters",level=level,levelSource=levelSource,fish=fish,mine=mine,
    observed=self:SkillUpRange(map),
    faction=cities[map],source="Existing zone-wide guidance; exact waters and skill thresholds unverified."} end
  end
 end
 return rows
end
-- How a zone rates at the skill being asked about. Unknown is not a "no":
-- a zone nobody has reported yet stays in the suitable list.
local RATING_GRADE={reliable=1,possible=2,yours=3,unknown=4,below=6}
function MF:FinderResults()
 local skill,level=self:FinderInputs()
 local faction=UnitFactionGroup("player")
 local rows={}
 for _,w in ipairs(self:FinderWaters()) do
  local enemy=w.faction and w.faction~=faction
  w.rating,w.escape=self:CatchSkillRating(w.map,skill)
  local fits=not not (w.level and level>=w.level and not enemy and w.rating~="below")
  local fish,missing={},false
  for _,id in ipairs(w.fish) do
   if (not self.finderFish or self.finderFish==id) and (not self.finderMissing or not self.cdb.profile.journal[id]) then
    fish[#fish+1]=id;missing=true
   end
  end
  w.fish=fish
  if missing and (not self.finderReadyOnly or fits) and (not self.finderCurrentZone or w.map==self:MapID()) then
   w.ready=fits;w.enemy=enemy
   w.grade=(RATING_GRADE[w.rating] or 4)+((w.rating=="unknown" and not w.observed) and 1 or 0)
   rows[#rows+1]=w
  end
 end
 table.sort(rows,function(a,b)
  if a.ready~=b.ready then return a.ready==true end
  if a.grade~=b.grade then return a.grade<b.grade end
  if (a.level or 999)~=(b.level or 999) then return (a.level or 999)<(b.level or 999) end
  local az,bz=self:ZoneNameFor(a.map) or "",self:ZoneNameFor(b.map) or ""
  if az~=bz then return az<bz end
  return a.name<b.name
 end)
 return rows
end
-- Every fishing zone for the Find waters page (1.1.4), whatever the old filters say: where it
-- stands for you (here, ready, higher level, fish get away, opposing city), its fish and how
-- many you still need. The page groups, searches and filters these itself.
function MF:FinderZones()
 local skill,level=self:FinderInputs()
 local faction=UnitFactionGroup("player")
 local here=self:MapID()
 local journal=self.cdb.profile.journal or {}
 local out={}
 for _,w in ipairs(self:FinderWaters()) do
  w.zone=self:ZoneNameFor(w.map) or self.ZONE_IDS[w.map] or "Unknown zone"
  w.enemy=w.faction~=nil and w.faction~=faction
  local summary
  w.rating,w.escape,summary=self:CatchSkillRating(w.map,skill)
  -- The lowest skill anglers have landed fish at here, when that's above yours
  w.from=summary and summary.possible and summary.possible*(self.CATCH_SKILL_BAND or 25) or nil
  w.need=0
  for _,id in ipairs(w.fish) do if not journal[id] then w.need=w.need+1 end end
  w.here=w.map==here
  if w.enemy then w.group="enemy"
  elseif w.rating=="below" then w.group="below"
  elseif not w.level then w.group="unknown"
  elseif level<w.level then w.group="higher"
  else w.group="ready" end
  out[#out+1]=w
 end
 table.sort(out,function(a,b)
  if (a.level or 999)~=(b.level or 999) then return (a.level or 999)<(b.level or 999) end
  return a.zone<b.zone
 end)
 return out,skill,level
end
function MF:FishingFinderLines()
 local skill,level=self:FinderInputs()
 local out={Heading(self,"Where can I fish?"),{text="Effective skill: "..(skill or "unknown"),right="Character level: "..level}}
 if self.finderFish then
  out[#out+1]={text=self.C.hint.."Looking for: "..self:FishName(self.finderFish).."|r",right="Click to clear",
   onClick=function() self.finderFish=nil;self.finderSelected=nil;self:OpenAnglingTools("finder") end}
 end
 self:NoteRows(out,self.finderSkill and "Preview values. Choose Use my stats to return to your character." or "Uses your current fishing skill plus observed gear and active bonuses.")
 local function ChangeSkill(delta)
  self.finderSkill=math.max(0,math.min(1000,(skill or 0)+delta));self:OpenAnglingTools("finder")
 end
 out[#out+1]={text=self.C.hint.."Skill -25|r",right="Preview skill",onClick=function() ChangeSkill(-25) end}
 out[#out+1]={text=self.C.hint.."Skill +25|r",right="/tfl finder 350 60 for exact values",onClick=function() ChangeSkill(25) end}
 local selected=self.finderSelected
 if selected then
  out[#out+1]=Heading(self,(self:ZoneNameFor(selected.map) or "Unknown zone").." — "..selected.name)
  self:NoteRows(out,selected.source)
  if selected.levelSource then self:NoteRows(out,selected.levelSource.."; adventure levels are not fishing requirements.") end
  self:CatchSkillLines(selected.map,out,skill)
  self:NoteRows(out,selected.level and ("Travel guidance: level "..selected.level.."+. This is not a fishing requirement or a safe-route guarantee.") or "Travel level is unverified for this zone.")
  if selected.observed then self:NoteRows(out,("Skill gains reported at base skill %d–%d. These are observations, not minimum fishing requirements."):format(selected.observed.lo,selected.observed.hi)) end
  out[#out+1]=Heading(self,"Known frenzy access points")
  local points=0
  for _,water in ipairs(self.FRENZY_LOCATIONS) do
   if water.map==selected.map then
    points=points+1
    out[#out+1]={text=water.name,right=("%.1f, %.1f"):format(water.x*100,water.y*100),tooltip={"Supported access point; not a complete shoreline boundary."}}
   end
  end
  if points==0 then self:NoteRows(out,"No static frenzy access points listed in this zone.") end
  if selected.enemy then self:NoteRows(out,"Opposing-faction city: access is dangerous.") end
  if selected.access then self:NoteRows(out,selected.access) end
  out[#out+1]=Heading(self,"Your recorded waters")
  local personal={}
  for key,records in pairs(self.cdb.records) do
   local p=self:SpotPosition(key)
   if p and p.map==selected.map then
    local found=false
    for _,id in ipairs(selected.fish) do if records[id] then found=true break end end
    if found then
     personal[#personal+1]={key=key,name=self:SpotName(key)}
    end
   end
  end
  table.sort(personal,function(a,b) if a.name~=b.name then return a.name<b.name end return a.key<b.key end)
  for _,record in ipairs(personal) do
   local spot=record.key
   out[#out+1]={text=self.C.hint..record.name.."|r",right="Show on map",
    onClick=function() self:PointToSpot(spot) end,tooltip={"Your recorded catch at a validated saved position; not a complete water boundary."}}
  end
  if #personal==0 then self:NoteRows(out,"No matching personal water records with a usable saved position.") end
  out[#out+1]=Heading(self,"Fish to look for")
  local ids={} for _,id in ipairs(selected.fish) do ids[#ids+1]=id end
  table.sort(ids,function(a,b) return (names[a] or self:FishName(a))<(names[b] or self:FishName(b)) end)
  for _,id in ipairs(ids) do
   local item=id
   local card=self.FISH[id] or self.TROPHY[id]
   out[#out+1]={text=names[id] or self:FishName(id),icon=card and self:FishIcon(id) or nil,
    right=selected.mine and selected.mine[id] and "Caught by you in this zone" or "Reference guidance",
    onClick=card and function() self:ShowCard(item) end or nil}
  end
  if self.finderFish then
   out[#out+1]={text=self.C.hint.."Track this fish as a goal|r",onClick=function() self:OpenFishingGoal(self.finderFish) end}
  end
  self:NoteRows(out,"A zone list is not an exact-water guarantee. Special fish may require pools, season or time of day.")
 else
  self:NoteRows(out,"Select a zone for fish and access points. Suitable checks travel level and how often fish get away at your skill, from your casts and other anglers'.")
  local rows=self:FinderResults()
  out[#out+1]=Heading(self,#rows.." waters • "..(self.finderReadyOnly and "Suitable for you" or "All zones"))
  for _,w in ipairs(rows) do
   local water=w
   local escape=w.escape and (" - %d%% escape"):format(math.floor(w.escape*100+0.5)) or ""
   local status,colour
   if w.rating=="reliable" then status,colour="Reliable at your skill",self.C.good
   elseif w.rating=="possible" then status,colour="Possible"..escape,self.C.hint
   elseif w.rating=="yours" then status,colour="Your casts"..escape,self.C.hint
   elseif w.rating=="below" then status,colour="Below observed skill",self.C.bad
   else status,colour=w.observed and "Skill gains reported" or "Skill not yet observed",self.C.muted end
   out[#out+1]={text=self.C.hint..(self:ZoneNameFor(w.map) or "Unknown zone").."|r",right=colour..status.."|r",group=true,
    onClick=function() self.finderSelected=water;self:OpenAnglingTools("finder") end}
   out[#out+1]={text="    "..w.name,right=(w.level and "Travel "..w.level.."+" or "Travel level unknown")..(w.enemy and " • Opposing city" or ""),
    onClick=function() self.finderSelected=water;self:OpenAnglingTools("finder") end}
  end
  if #rows==0 then self:NoteRows(out,"No waters meet these filters. Try All zones or preview a higher character level.") end
 end
 return out
end
local tools=MF.AnglingToolsLines
function MF:AnglingToolsLines()
 local lines,actions,subs=tools(self)
 -- Keep the four-slot tool navigation; Reports remains available by command.
 for _,sub in ipairs(subs) do if sub.key=="reports" then sub.key,sub.label="finder","Find waters" end end
 if self.anglingToolsView~="finder" then return lines,actions,subs end
 lines=self:FishingFinderLines()
 actions={
  {label=self.finderSelected and "Back to waters" or "Fishing here",onClick=function()
   if self.finderSelected then self.finderSelected=nil;self:OpenAnglingTools("finder") else self:OpenFishingHere() end end},
  {label="Use my stats",onClick=function() self.finderSkill,self.finderLevel=nil,nil;self:OpenAnglingTools("finder") end},
  {label=self.finderReadyOnly and "All zones" or "Suitable for me",onClick=function() self.finderReadyOnly=not self.finderReadyOnly;self.finderSelected=nil;self:OpenAnglingTools("finder") end},
  {label=self.finderCurrentZone and "All regions" or "Current zone",onClick=function() self.finderCurrentZone=not self.finderCurrentZone;self.finderSelected=nil;self:OpenAnglingTools("finder") end},
  {label=self.finderMissing and "All fish" or "Still to catch",onClick=function() self.finderMissing=not self.finderMissing;self.finderSelected=nil;self:OpenAnglingTools("finder") end},
 }
 return lines,actions,subs
end
MF:Command("finder","Solo","/tfl finder [effective skill] [character level] - find fishing waters",function(self,args,raw)
 local text=(raw or table.concat(args or {}," ")):match("^%s*(.-)%s*$")
 if text~="" then
  local s,l=text:match("^(%d+)%s*(%d*)$")
  s,l=tonumber(s),tonumber(l)
  if not s or s>1000 or l and (l<1 or l>60) then self:Print("Use /tfl finder 350 60 (skill 0-1000, level 1-60).") return end
  self.finderSkill,self.finderLevel=s,l
 end
 self.finderSelected=nil;self:OpenAnglingTools("finder")
end)
MF:Command("findfish","Solo","/tfl findfish <fish name or item ID> - find waters for a fish",function(self,args,raw)
 local query=(raw or table.concat(args or {}," ")):lower():match("^%s*(.-)%s*$")
 local id=tonumber(query)
 if id and self.FISH[id] then return self:OpenFishFinder(id) end
 if query=="" then self:Print("Choose Find waters on a fish card, or use /tfl findfish <fish name>.") return end
 local matches={}
 for item,fish in pairs(self.FISH) do
  local name=self:FishName(item):lower()
  if name==query or fish.name:lower()==query then return self:OpenFishFinder(item) end
  if name:find(query,1,true) or fish.name:lower():find(query,1,true) then matches[#matches+1]=item end
 end
 table.sort(matches)
 if #matches==1 then return self:OpenFishFinder(matches[1]) end
 self:Print(#matches==0 and "No matching fish in the fishing guide." or "Several fish match; enter a fuller name or an item ID.")
end)
