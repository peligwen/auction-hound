-- Buy.lua: what you bought at the house.
--
-- Scans show what sellers ask and your own sales show what buyers pay;
-- what you paid is the third column of the ledger. Every purchase that
-- goes through the house's API is noted, from Blizzard's buy frames or
-- the shift-double-click on their lists (UI/Ladder.lua): a commodity
-- from its quote and confirm, an item from the bid placed at its
-- buyout. The History view lists them beside your own auctions.
local ADDON, H = ...

local AH = C_AuctionHouse
local Buy = {}
H.Buy = Buy

Buy.PENDING_TTL = 120     -- seconds a started purchase waits for the house's answer
Buy.SEEN_TTL = 3600       -- seconds an auction from a search stays known by its id

local seq = 0

local function record(b, now)
  now = now or H.Now()
  seq = seq + 1
  b.id = string.format("%d.%d", now, seq)
  b.t = now
  b.status = "bought"
  b.name = b.name or H.ItemName(b.itemID)
  H.Store.AddBuy(b)
  H.Store.Ledger({ t = now, key = b.key, itemID = b.itemID, qty = b.qty, unit = b.unit, kind = "buy" })
  if b.qty > 1 then
    H.Printf("bought %d x %s for %s (%s each)", b.qty, b.name, H.Money(b.total), H.Money(b.unit))
  else
    H.Printf("bought %s for %s", b.name, H.Money(b.total))
  end
  H.Events:Fire("BUY_RECORDED", b)
  return b
end

------------------------------------------------------------------------
-- Commodities: the house quotes a total for the units asked, and the
-- confirm buys them at it. Both calls are hooked after the fact.
------------------------------------------------------------------------
Buy.commodity = nil

local function startCommodity(itemID, qty)
  Buy.commodity = { itemID = itemID, qty = qty, t = H.Now() }
end

local function confirmCommodity(itemID, qty)
  local c = Buy.commodity
  if not c or c.itemID ~= itemID then
    c = { itemID = itemID, t = H.Now() }
    Buy.commodity = c
  end
  c.qty = qty
  c.confirmed = true
end

H.RegisterEvent("COMMODITY_PRICE_UPDATED", function(unit, total)
  local c = Buy.commodity
  if c then c.unit, c.total = unit, total end
end)

H.RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", function() Buy.commodity = nil end)
H.RegisterEvent("COMMODITY_PURCHASE_FAILED", function() Buy.commodity = nil end)

H.RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
  local c = Buy.commodity
  Buy.commodity = nil
  if not c or not c.confirmed or not c.qty or c.qty <= 0 then return end
  if H.Now() - c.t > Buy.PENDING_TTL then return end
  local total = c.total or (c.unit and c.unit * c.qty)
  if not total then
    H.Printf("bought %d x %s; the house gave no price to note", c.qty, H.ItemName(c.itemID))
    return
  end
  record({
    key = H.KeyForItemID(c.itemID) or tostring(c.itemID), itemID = c.itemID,
    qty = c.qty, unit = H.Round(total / c.qty), total = total, commodity = true,
  })
end)

------------------------------------------------------------------------
-- Items: a bid at the buyout is a purchase. The auction behind an id
-- is known from the search that listed it; a plain bid is settled
-- later, by mail, and is not followed.
------------------------------------------------------------------------
local seen = {}
Buy.bids = {}

local function noteResults(itemKey)
  if not (AH.GetNumItemSearchResults and AH.GetItemSearchResultInfo) then return end
  local now = H.Now()
  for id, a in pairs(seen) do
    if now - a.t > Buy.SEEN_TTL then seen[id] = nil end
  end
  local n = AH.GetNumItemSearchResults(itemKey) or 0
  for i = 1, n do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.auctionID then
      local k = r.itemKey or itemKey
      seen[r.auctionID] = { key = H.KeyFromItemKey(k), itemID = k.itemID, buyout = r.buyoutAmount, qty = r.quantity or 1, t = now }
    end
  end
end

function Buy.Seen(auctionID)
  return seen[auctionID]
end

function Buy.NoteBid(auctionID, amount)
  local a = seen[auctionID]
  if not a or not a.buyout or a.buyout <= 0 or not amount or amount < a.buyout then return false end
  Buy.bids[auctionID] = { key = a.key, itemID = a.itemID, qty = a.qty, total = amount, t = H.Now() }
  return true
end

H.RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
  local b = auctionID and Buy.bids[auctionID]
  if not b then return end
  Buy.bids[auctionID] = nil
  if H.Now() - b.t > Buy.PENDING_TTL then return end
  record({ key = b.key, itemID = b.itemID, qty = b.qty, unit = H.Round(b.total / b.qty), total = b.total, auctionID = auctionID })
end)

H.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey) if itemKey then noteResults(itemKey) end end)
H.RegisterEvent("ITEM_SEARCH_RESULTS_ADDED", function(itemKey) if itemKey then noteResults(itemKey) end end)

if AH and hooksecurefunc then
  if AH.StartCommoditiesPurchase then hooksecurefunc(AH, "StartCommoditiesPurchase", startCommodity) end
  if AH.ConfirmCommoditiesPurchase then hooksecurefunc(AH, "ConfirmCommoditiesPurchase", confirmCommodity) end
  if AH.CancelCommoditiesPurchase then hooksecurefunc(AH, "CancelCommoditiesPurchase", function() Buy.commodity = nil end) end
  if AH.PlaceBid then hooksecurefunc(AH, "PlaceBid", Buy.NoteBid) end
end

------------------------------------------------------------------------
-- Totals over recent purchases for the History view.
------------------------------------------------------------------------
function Buy.Summary(buys, now, days)
  now = now or H.Now()
  days = days or H.Market.CLEARING_DAYS
  local cutoff = now - days * 86400
  local s = { units = 0, spent = 0, n = 0, days = days }
  for _, b in ipairs(buys or {}) do
    if (b.t or 0) >= cutoff then
      s.n = s.n + 1
      s.units = s.units + (b.qty or 0)
      s.spent = s.spent + (b.total or 0)
    end
  end
  return s
end
