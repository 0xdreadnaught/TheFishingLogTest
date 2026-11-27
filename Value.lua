-- Value: what your catch is worth, for your own log only.
--
-- Prices come from a price addon if you have one (Auctionator or TSM), and
-- fall back to the vendor price, which every client knows. They're only ever
-- your own numbers: matches, records and bounties never use them, because
-- every player's price data is different.
local _, MF = ...

local CACHE_SECONDS = 60
local cache = {} -- itemID -> { copper, source, at }

local function FromAuctionator(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.GetAuctionPriceByItemID then return end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "TheFishingLog", itemID)
    if ok and type(price) == "number" and price > 0 then return price, "Auctionator" end
end

local function FromTSM(itemID)
    if not TSM_API or not TSM_API.GetCustomPriceValue then return end
    local ok, price = pcall(function()
        return TSM_API.GetCustomPriceValue("dbmarket", TSM_API.ToItemString("i:" .. itemID))
    end)
    if ok and type(price) == "number" and price > 0 then return price, "TSM" end
end

local function FromVendor(itemID)
    local sell = select(11, C_Item.GetItemInfo(itemID))
    if sell and sell > 0 then return sell, "vendor" end
end

-- Returns copper, source ("Auctionator", "TSM" or "vendor"), or nil.
function MF:FishValue(itemID)
    if not itemID then return end
    local hit = cache[itemID]
    if hit and GetTime() - hit.at < CACHE_SECONDS then
        return hit.copper, hit.source
    end
    local copper, source = FromAuctionator(itemID)
    if not copper then copper, source = FromTSM(itemID) end
    if not copper then copper, source = FromVendor(itemID) end
    cache[itemID] = { copper = copper, source = source, at = GetTime() }
    return copper, source
end

-- Short money text that fits on the board: "12g", "40s", "80c".
function MF:ShortMoney(copper)
    copper = math.floor(copper or 0)
    if copper >= 10000 then return ("%dg"):format(copper / 10000) end
    if copper >= 100 then return ("%ds"):format(copper / 100) end
    return ("%dc"):format(copper)
end

-- Full money text with the game's coin icons.
function MF:Money(copper)
    return GetCoinTextureString and GetCoinTextureString(math.floor(copper or 0))
        or self:ShortMoney(copper)
end

function MF:ValueEnabled()
    return self.db.settings.showValue
end
