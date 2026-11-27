-- A small keepsake checklist, separate from weighed fish and trophy cards.
local _,MF=...
MF.FISHING_FINDS={6307,6351,6352,6353,6354,6355,6356,6357,13874,13875,13918,20708,21113,21150,21228}
local known={};for _,id in ipairs(MF.FISHING_FINDS) do known[id]=true end
-- A trunk or a bottle, rather than a boot: sessions count these apart from junk.
function MF:IsFishingFind(itemID) return known[itemID]==true end
MF:On("TFL_CATCH",function(self,c)
    if c.test or not known[c.itemID] or type(c.castSerial)~="number" or c.castSerial<1 then return end
    local p=self.cdb.profile
    if type(p.finds)~="table" then p.finds={} end
    local found=p.finds[c.itemID]
    if type(found)~="table" or type(found.count)~="number" or found.count~=found.count
        or found.count<0 or found.count>10000000 then found=nil end
    if not found then
        found={count=0,at=c.at,name=c.name,water=c.spot.name};p.finds[c.itemID]=found
    end
    found.count=found.count+1
    self:MarkProfileChanged();self:RefreshJournal()
end)
function MF:FishingFindLines(out)
    out=out or {}
    local store=type(self.cdb.profile.finds)=="table" and self.cdb.profile.finds or {}
    local count=0;for _,id in ipairs(self.FISHING_FINDS) do if type(store[id])=="table" then count=count+1 end end
    out[#out+1]={text=self.C.gold.."Fishing finds|r",header=true,right=count.." / "..#self.FISHING_FINDS}
    self:NoteRows(out,"Bottles, chests and trunks landed while fishing. These keepsakes have no generated fish weight and do not unlock by opening containers.")
    for _,id in ipairs(self.FISHING_FINDS) do
        local entry=type(store[id])=="table" and store[id] or nil
        out[#out+1]={text=(entry and self.C.text or self.C.muted)..(entry and type(entry.name)=="string" and entry.name or self:FishName(id)).."|r",
            right=entry and ("Caught "..tostring(entry.count or "?")) or "Still to find",icon=self:FishIcon(id),group=true}
        if entry then
            out[#out+1]={text=self.C.label..(type(entry.water)=="string" and entry.water or "Water not recorded").."|r",
                right=type(entry.at)=="number" and entry.at>0 and entry.at<=GetServerTime()
                    and date("%d %b %Y",entry.at) or "Date not recorded"}
        end
    end
    return out
end
local album=MF.AlbumLines
function MF:AlbumLines(out)
    local toggle={text=self.C.hint..(self.albumFinds and "View fish cards" or "View fishing finds").."|r",
        onClick=function() self.albumFinds=not self.albumFinds;self:RedrawJournal() end}
    if self.albumFinds then out[#out+1]=toggle;return self:FishingFindLines(out) end
    album(self,out)
    -- Keep the latest specimen at the top; the category switch belongs at
    -- the album heading, not ahead of that personal milestone.
    for i,row in ipairs(out) do
        if row.header and row.text:find("Album  -",1,true) then table.insert(out,i+1,toggle);return out end
    end
    out[#out+1]=toggle;return out
end
