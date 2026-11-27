-- Small companions to the journal: our own catches, tackle and known waters.
-- These views never equip, use items, send chat or invent geography.
local _, MF = ...
local function Header(text) return {text=MF.C.gold .. text .. "|r",header=true} end
local function Blank(out) out[#out+1]={text=""} end
local function Plain(text)
    return tostring(text or "?"):gsub("|H.-|h(.-)|h","%1"):gsub("|c%x%x%x%x%x%x%x%x","")
        :gsub("|r",""):gsub("|T.-|t",""):gsub("[%c]"," "):gsub("[`*_~]","")
end

function MF:LocationConfidence(key)
    local w=self:SpotPosition(key)
    if not w then return "Location unknown",self.C.muted end
    if self:SpotLocallyObserved(key) then return "Locally observed",self.C.good end
    if self:SpotMapFits(key,w.map)==true then return "Zone-consistent report",self.C.hint end
    return "Unverified report",self.C.muted
end

function MF:LocalWaters(mapID)
    mapID=mapID or self:MapID()
    local current=self:CurrentSpot()
    local rows={}
    -- Positions must belong to this exact map; a record association alone
    -- cannot put a pin on the map or prove a shoreline.
    for key in pairs(self.db.spotWhere) do
        local w=self:SpotPosition(key)
        if w and w.map==mapID then
            local active,left=self:FrenzyPresentationState(key)
            rows[#rows+1]={key=key,name=self:SpotName(key),where=w,
                current=key==current.key,active=active,left=left}
        end
    end
    table.sort(rows,function(a,b)
        if a.current~=b.current then return a.current end
        if a.active~=b.active then return a.active end
        if a.name~=b.name then return a.name<b.name end
        return a.key<b.key
    end)
    return rows
end

function MF:LocalWaterLines()
    local map=self:MapID()
    local rows=self:LocalWaters(map)
    local out={Header("Local waters"),{text=self:ZoneNameFor(map) or "Current zone",right=#rows .. " known locations"}}
    self:NoteRows(out,"Select a water to see your catches and its known records.")
    local chosen
    for _,r in ipairs(rows) do if r.key==self.localWaterSelected then chosen=r end end
    chosen=chosen or rows[1]
    if chosen then
        local key=chosen.key
        Blank(out)
        local heading=Header(chosen.name)
        heading.right=chosen.current and "You are here" or "Viewing this water"
        out[#out+1]=heading
        local confidence,colour=self:LocationConfidence(key)
        out[#out+1]={text=colour .. confidence .. "|r",right=("%.1f, %.1f"):format(chosen.where.x*100,chosen.where.y*100),
            tooltip={"Locally observed: a genuine catch at this saved position.",
                "Zone-consistent: the zone matches; exact water coordinates are not certified.",
                "Unverified: this reported position has not been confirmed locally.",
                "Saved locations do not guarantee a pool is currently available."}}
        if chosen.active then out[#out+1]={text=self.C.spec .. "Frenzy active|r",right=self:FormatClock(chosen.left) .. " left"} end
        local king=self:King(key)
        if king then
            out[#out+1]={text="Known record holder",right=self:ShortName(king.h)}
            out[#out+1]={text=self:FishName(king.id),icon=self:FishIcon(king.id),right=self:Weight(king.w)}
        else self:NoteRows(out,"No spot record received yet.") end
        local catches={}
        for id,c in pairs(self.cdb.records[key] or {}) do catches[#catches+1]={id=id,catch=c} end
        table.sort(catches,function(a,b)
            if a.catch.weight~=b.catch.weight then return a.catch.weight>b.catch.weight end
            return a.id<b.id
        end)
        out[#out+1]=Header("Your best catches at this water")
        if #catches==0 then self:NoteRows(out,"No personal catches saved at this water yet.") end
        for _,entry in ipairs(catches) do
            local id,c=entry.id,entry.catch
            local grade,colour=self:WeightGradeShort(id,c.weight)
            if c.specimen then grade,colour="specimen",self.C.spec end
            out[#out+1]={text=self:FishName(id),icon=self:FishIcon(id),right=self:Weight(c.weight),
                tooltip={grade and (colour .. grade .. "|r") or "Grade unavailable","Click to choose a fishing goal for this fish."},
                onClick=function() self:OpenFishingGoal(id) end}
        end
        out[#out+1]={text=self.C.hint .. "Show this location on the map|r",onClick=function() self:PointToSpot(key) end}
    end
    Blank(out)
    out[#out+1]=Header("Explore this zone")
    if #rows==0 then self:NoteRows(out,"No usable positions saved here. A genuine catch can record your current location.") end
    for _,r in ipairs(rows) do
        local confidence,colour=self:LocationConfidence(r.key)
        local badges={}
        if r.current then badges[#badges+1]="You are here" end
        if r.key==(chosen and chosen.key) then badges[#badges+1]="Selected" end
        if r.active then badges[#badges+1]=self.C.spec .. "Frenzy|r" end
        out[#out+1]={text=(r.current and self.C.gold or self.C.text) .. r.name .. "|r",
            right=#badges>0 and table.concat(badges," / ") or "View",
            featured=r.key==(chosen and chosen.key),
            tooltip={colour .. confidence .. "|r",("%.1f, %.1f"):format(r.where.x*100,r.where.y*100)},
            onClick=function() self.localWaterSelected=r.key self:RedrawJournal() end}
    end
    return out
end

function MF:CarriedFishingItems()
    local counts={}
    if C_Container and type(C_Container.GetContainerNumSlots)=="function"
        and type(C_Container.GetContainerItemInfo)=="function" then
        for bag=0,4 do
            for slot=1,C_Container.GetContainerNumSlots(bag) do
                local info=C_Container.GetContainerItemInfo(bag,slot)
                if info then
                    local id=tonumber(info.itemID)
                    if not id or id<=0 then id=tonumber((info.hyperlink or info.link or ""):match("item:(%d+)")) end
                    if id then counts[id]=(counts[id] or 0)+(info.stackCount or 1) end
                end
            end
        end
    end
    return counts
end

function MF:TackleboxLures()
    local counts=self:CarriedFishingItems()
    local out={}
    for _,lure in ipairs(self.LURES) do
        if (counts[lure.id] or 0)>0 then
            local ready,reason=self:LureEligibility(lure)
            out[#out+1]={id=lure.id,bonus=lure.bonus,count=counts[lure.id],seconds=lure.seconds,
                skill=lure.skill,ready=ready,reason=reason}
        end
    end
    table.sort(out,function(a,b) if a.bonus~=b.bonus then return a.bonus>b.bonus end return a.id<b.id end)
    return out
end

function MF:FishingReadinessLines()
    local rank,cap,bonus,parts=self:FishingSkill()
    local out={Header("Ready for the water")}
    out[#out+1]={text="Effective fishing skill",right=rank and tostring(rank+(bonus or 0)) or "Not available yet"}
    if rank then out[#out+1]={text="Base skill / bonuses",right=("%d / %d  +%d"):format(rank,cap or rank,bonus or 0)} end
    if parts then out[#out+1]={text="Active fishing buff bonus",right="+" .. tostring(parts.buffs or 0),
        tooltip={"Fishing bonuses read from your active buff tooltips.","Carried food and consumables are not added to your skill until an active effect is observed."}} end
    out[#out+1]={text="Fishing pole",right=self:HasFishingPole() and (self.C.good .. "Equipped|r") or (self.C.muted .. "Not equipped|r")}
    local lure=self:HasFishingPole() and self:LureTimeLeft()
    out[#out+1]={text="Lure remaining",right=lure and self:FormatClock(lure) or "No active lure"}
    out[#out+1]={text="Fishing goal",right=self:FishingGoalText(),onClick=function() self:OpenFishingGoal() end}
    return out
end

function MF:TackleboxLines()
    local out=self:FishingReadinessLines()
    Blank(out)
    out[#out+1]=Header("Lures in your bags")
    local lures=self:TackleboxLures()
    for _,lure in ipairs(lures) do
        out[#out+1]={text=self:FishName(lure.id),icon=self:FishIcon(lure.id),
            right=("x%d  /  +%d fishing"):format(lure.count,lure.bonus),
            tooltip={("+%d Fishing for %s. Requires Fishing %d."):format(lure.bonus,self:FormatClock(lure.seconds),lure.skill or 0),
                lure.reason,"Apply a lure using the fishing panel's lure button. Hat lures are used when equipped, ready and at least as strong as your best usable carried lure."}}
        out[#out+1]={text=(lure.ready and self.C.good or self.C.muted) .. lure.reason .. "|r",
            right=self:FormatClock(lure.seconds) .. " duration"}
    end
    if #lures==0 then self:NoteRows(out,"No recognised fishing lures found in your bags.") end
    local counts=self:CarriedFishingItems()
    local hat=self.FISHING_HAT
    local worn=tonumber((GetInventoryItemLink("player",1) or ""):match("item:(%d+)"))==hat.id
    if worn or (counts[hat.id] or 0)>0 then
        Blank(out)
        out[#out+1]=Header("Reusable lure")
        local ready,status=self:FishingHatStatus()
        out[#out+1]={text=self:FishName(hat.id),icon=self:FishIcon(hat.id),right=("+%d / %s"):format(hat.bonus,self:FormatClock(hat.seconds)),
            tooltip={"Tooltip describes a +25 Fishing lure for 10 minutes, with a 10-minute cooldown.",
                "Requires Fishing 1. Equip the hat to use it through the fishing panel's lure button.",
                "This is an activated lure, not a passive equipment bonus."}}
        out[#out+1]={text=worn and "Equipped" or "In your bags",right=(ready and self.C.good or self.C.muted) .. status .. "|r"}
    end
    local supplyCount=0
    for _,supply in ipairs(self.FISHING_SUPPLIES) do
        if (counts[supply.id] or 0)>0 then
            if supplyCount==0 then Blank(out) out[#out+1]=Header("Fishing food and consumables") end
            supplyCount=supplyCount+1
            local level=type(UnitLevel)=="function" and UnitLevel("player") or nil
            local requirement=supply.level and ("Requires level " .. supply.level) or "No requirement shown in scan"
            out[#out+1]={text=self:FishName(supply.id),icon=self:FishIcon(supply.id),
                right=("x%d / +%d fishing"):format(counts[supply.id],supply.bonus),
                tooltip={("Tooltip describes +%d Fishing for %s."):format(supply.bonus,self:FormatClock(supply.seconds)),
                    requirement,supply.kind=="food" and "Eat for at least 10 seconds to become well fed." or "Use manually from your bags.",
                    "Observed in Forever beta build 70450. Stacking and gameplay effects have not been independently tested."}}
            out[#out+1]={text=supply.level and type(level)=="number" and level<supply.level and (self.C.muted .. requirement .. "|r") or "Use from your bags",
                right=self:FormatClock(supply.seconds) .. " duration"}
        end
    end
    if supplyCount>0 then self:NoteRows(out,"Listed bonuses describe item tooltips. Your effective skill uses observed active effects; carrying these items does not add a bonus.") end
    Blank(out)
    out[#out+1]=Header("Your saved outfit")
    local state=self:FishingOutfitState()
    local saved=0
    for _,entry in ipairs(self:FishingOutfitSlots()) do
        local slot=entry[1]
        local item=state.items[slot]
        if state.selected[slot] and item then
            saved=saved+1
            local status,colour=self:OutfitItemStatus(slot)
            out[#out+1]={text=entry[2],right=colour .. status .. "|r"}
            out[#out+1]={text="    " .. Plain(item.link),onClick=function() self:OpenFishingOutfit() end}
        end
    end
    if saved==0 then self:NoteRows(out,"Save your fishing outfit in the Wardrobe to see which pieces are ready or missing.") end
    out[#out+1]={text=self.C.hint .. "Open Angler's Wardrobe|r",onClick=function() self:OpenFishingOutfit() end}
    if state.previous then self:NoteRows(out,"Your previous gear is remembered. Restore it from the Wardrobe when you are ready.") end
    return out
end

function MF:SessionReportText(h,short)
    if not h or not h.solo then return nil end
    local out={"**The Fishing Log - Fishing Report**",Plain(h.sub or h.zone)}
    if h.when then out[#out+1]=date("%d %b %Y, %H:%M",h.when) end
    out[#out+1]=("%d fish / %s / %s fishing time"):format(h.count or 0,self:Weight(h.total or 0),self:FormatClock(h.duration or 0))
    if (h.biggest or 0)>0 then out[#out+1]="Biggest: " .. Plain(h.biggestName or "fish") .. " - " .. self:Weight(h.biggest) end
    out[#out+1]=("Specimens: %d"):format(h.specimens or 0)
    if (h.finds or 0)>0 then
        local items=self:FindItemsText(h.findItems)
        out[#out+1]=("Fishing finds: %d%s"):format(h.finds,items and (" (" .. Plain(items) .. ")") or "")
    end
    if h.outcomes then out[#out+1]=self:CastOutcomeSummary(h) end
    if h.recordStats then
        out[#out+1]=("Known spot records improved: %d all-time / %d seasonal"):format(h.recordStats.all or 0,h.recordStats.season or 0)
    elseif not short then out[#out+1]="Record improvements were not tracked for this older session." end
    if not short then
        if self:ValueEnabled() then out[#out+1]="Estimated catch value: " .. Plain(self:ShortMoney(h.value or 0)) end
        if h.elapsed then out[#out+1]="Elapsed session time: " .. self:FormatClock(h.elapsed) end
        out[#out+1]=""
        out[#out+1]="**Waters fished**"
        if h.spots and #h.spots>0 then
            for _,s in ipairs(h.spots) do
                out[#out+1]=("- %s: %d fish / %s"):format(Plain(s.name),s.count or 0,self:Weight(s.total or 0))
            end
        else out[#out+1]="- " .. Plain(h.sub or "Location unavailable") end
    end
    return table.concat(out,"\n")
end

function MF:OpenSessionReport(h,short)
    local text=self:SessionReportText(h,short)
    if text then self:ShowCopyText("Fishing report",text) end
end

function MF:SessionReportLines()
    local out={Header("Share a fishing session")}
    self:NoteRows(out,"Choose a full report or a short post. Preview and copy it, then paste it wherever you like. Nothing is sent automatically.")
    local count=0
    for i=#self.cdb.history,1,-1 do
        local h=self.cdb.history[i]
        if h.solo then
            count=count+1
            Blank(out)
            out[#out+1]=Header(date("%d %b %H:%M",h.when) .. " - " .. (h.sub or "Fishing session"))
            out[#out+1]={text=("%d fish / %s"):format(h.count or 0,self:Weight(h.total or 0)),right=self:FormatClock(h.duration or 0)}
            out[#out+1]={text=self.C.hint .. "Copy full report|r",
                onClick=function() self:OpenSessionReport(h,false) end,
                tooltip={"Click for the full report. The next row opens a shorter version."}}
            out[#out+1]={text=self.C.hint .. "Copy short post|r",onClick=function() self:OpenSessionReport(h,true) end}
        end
    end
    if count==0 then self:NoteRows(out,"No completed solo sessions yet. Stop your current log to save it in History.") end
    return out
end

function MF:AnglingToolsLines()
    local view=self.anglingToolsView or "waters"
    local out=view=="frenzies" and self:FrenzyListLines() or view=="tackle" and self:TackleboxLines() or view=="reports" and self:SessionReportLines() or self:LocalWaterLines()
    local subs={current=view,onPick=function(key) self.anglingToolsView=key end}
    for _,entry in ipairs({{"waters","Local waters"},{"tackle","Tacklebox"},{"reports","Reports"},{"frenzies","Frenzy List"}}) do
        local key,label=entry[1],entry[2]
        subs[#subs+1]={key=key,label=label}
    end
    local actions={{label="Fishing here",onClick=function() self:OpenFishingHere() end},
        {label="Wardrobe",onClick=function() self:OpenFishingOutfit() end}}
    if view=="frenzies" then
        actions[#actions+1]={label=self.frenzyListView=="discoveries" and "Planner" or "Discoveries",onClick=function()
            self.frenzyListView=self.frenzyListView=="discoveries" and "planner" or "discoveries"
            self:OpenAnglingTools("frenzies")
        end}
        actions[#actions+1]={label=self.frenzyLocalOnly and "All zones" or "Zone only",onClick=function()
            self.frenzyLocalOnly=not self.frenzyLocalOnly
            self:OpenAnglingTools("frenzies")
        end}
        if self.frenzyListView=="discoveries" then
            actions[#actions+1]={label="Copy review",onClick=function() self:ShowCopyText("Frenzy discovery review",self:FrenzyReviewText()) end}
        end
    end
    return out,actions,subs
end

for _,event in ipairs({"BAG_UPDATE_DELAYED","PLAYER_EQUIPMENT_CHANGED","ZONE_CHANGED","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED_INDOORS"}) do
    MF:On(event,function(self) self:RefreshJournal() end)
end
-- The Waters tab is where local waters live in the journal's new look; the classic look keeps its own view.
MF:Command("waters","Solo","/tfl waters - explore known local fishing waters",function(self)
    if self.Rework and self.Rework.Journal and not self.oldRework then self:OpenJournal("records")
    else self:OpenAnglingTools("waters") end
end)
MF:Command("tackle","Gear","/tfl tackle - your fishing supplies and saved outfit",function(self) self:OpenAnglingTools("tackle") end)
MF:Command("sessionreport","Solo","/tfl sessionreport - copy a completed fishing session",function(self) self:OpenAnglingTools("reports") end)
