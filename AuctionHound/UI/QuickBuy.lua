-- UI/QuickBuy.lua: a double-click on Blizzard's buy frames buys.
--
-- A click on a Buy tab row opens one of two frames: the commodity buy
-- frame, with a narrow list of unit price and units, or the item buy
-- frame, with a wide list of auctions. A double-click on a listing
-- there buys it: an auction at its buyout, or a commodity's units up to
-- that row through Hound's own confirm under the cursor. Nothing of
-- Blizzard's is written or pressed (UI/House.lua has why): the rows are
-- only noted, by Hound, as Blizzard's cells fill them.
local ADDON, H = ...

local UI = H.UI
local House = UI.House
local AH = C_AuctionHouse
local QB = {}
UI.QuickBuy = QB

------------------------------------------------------------------------
-- The rows, noted as Blizzard's cells fill them, and the item each
-- frame shows.
------------------------------------------------------------------------
local function onUnits(cell, rowData, index)
  local frame = QB.commodityFrame
  if not frame or not House.Under(cell, frame.ItemList) or type(rowData) ~= "table" then return end
  House.Track(cell, "commodity", rowData, index)
end

local function onItemUnits(cell, rowData, index)
  local frame = QB.itemFrame
  if not frame or not House.Under(cell, frame.ItemList) or type(rowData) ~= "table" then return end
  House.Track(cell, "item", rowData, index)
end

local function installCommodity(ah)
  local frame = ah.CommoditiesBuyFrame
  if type(frame) ~= "table" or type(frame.ItemList) ~= "table" then return false end
  QB.commodityFrame = frame
  House.HookCells("AuctionHouseTableCellCommoditiesQuantityMixin", "Populate", "commodity list double-click", onUnits)
  hooksecurefunc(frame, "SetItemIDAndPrice", function(_, itemID) QB.commodityItemID = itemID end)
  return true
end

local function installItem(ah)
  local frame = ah.ItemBuyFrame
  if type(frame) ~= "table" or type(frame.ItemList) ~= "table" then return false end
  QB.itemFrame = frame
  House.HookCells("AuctionHouseTableCellItemQuantityMixin", "Populate", "item list double-click", onItemUnits)
  return true
end

------------------------------------------------------------------------
-- Buying. An item goes straight to its buyout: the double-click is the
-- hardware event the house wants for a bid. A commodity row asks the
-- house for a price on every unit up to it, the way Blizzard's own
-- click selects them, and Hound's confirm opens under the cursor with
-- the total: the house wants a second hardware event for the confirm,
-- and that is the one click left. Every purchase is noted by Buy.lua.
------------------------------------------------------------------------

-- Buys one auction of the item list outright. Returns true, or false
-- and why not.
function QB.BuyItem(rowData)
  if type(rowData) ~= "table" or not rowData.auctionID then return false, "no auction under the cursor" end
  local buyout = rowData.buyoutAmount
  if not buyout or buyout <= 0 then return false, "that auction has no buyout" end
  if type(GetMoney) == "function" and (GetMoney() or 0) < buyout then
    return false, "not enough gold for " .. H.Money(buyout)
  end
  local itemID = type(rowData.itemKey) == "table" and rowData.itemKey.itemID
  H.Printf("buying %s for %s", itemID and H.ItemName(itemID) or "the auction", H.Money(buyout))
  AH.PlaceBid(rowData.auctionID, buyout)
  return true
end

-- The units a click on a commodity row selects: everything listed up
-- to and including that row, less your own, which the house will not
-- sell you. With no row, every unit listed.
--
-- The row is found by its auction, and failing that by its price: the
-- results run cheapest first, so it ends where the price passes the
-- row's. A row's auction can be gone from the results while the row
-- still shows it, after a purchase say, when the house reads the
-- listings again; counting on to the end then offered every unit
-- listed. A row with neither selects nothing.
function QB.UnitsUpTo(itemID, rowData)
  if not itemID then return 0 end
  local row = type(rowData) == "table" and rowData or nil
  if row and not row.auctionID and not row.unitPrice then return 0 end
  local n = AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID) or 0
  local units = 0
  for i = 1, n do
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r then
      if row and row.unitPrice and r.unitPrice and r.unitPrice > row.unitPrice then return units end
      units = units + math.max(0, (r.quantity or 0) - (r.numOwnerItems or 0))
      if row and row.auctionID and r.auctionID == row.auctionID then return units end
    end
  end
  if row and not row.unitPrice then return 0 end
  return units
end

-- What the cheapest n units listed come to, less your own: the
-- confirm's estimate when its units box changes.
function QB.PriceOf(itemID, n)
  local count = AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID) or 0
  local total, left = 0, n
  for i = 1, count do
    if left <= 0 then break end
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice then
      local take = math.min(left, math.max(0, (r.quantity or 0) - (r.numOwnerItems or 0)))
      total = total + take * r.unitPrice
      left = left - take
    end
  end
  return left <= 0 and total or nil
end

-- Asks the house for a price on the units up to a commodity row and
-- opens Hound's confirm under the cursor (UI/Confirm.lua). The item is
-- the row's own where it names one, else the one the frame was last
-- set to. Returns true, or false and why.
function QB.BuyCommodity(rowData)
  local itemID = type(rowData) == "table" and rowData.itemID or QB.commodityItemID
  if not itemID then return false, "no commodity on the buy frame" end
  local qty = QB.UnitsUpTo(itemID, rowData)
  if qty <= 0 then return false, "nothing there to buy: those are your own" end
  UI.Confirm.Commodity(itemID, qty, QB.UnitsUpTo(itemID), function(n) return QB.PriceOf(itemID, n) end)
  return true
end

House.OnDoubleClick("item", function(rowData)
  local ok, why = QB.BuyItem(rowData)
  if not ok and why then H.Print(why) end
end)

House.OnDoubleClick("commodity", function(rowData)
  local ok, why = QB.BuyCommodity(rowData)
  if not ok and why then H.Print(why) end
end)

------------------------------------------------------------------------
-- Install once the Blizzard frame exists.
------------------------------------------------------------------------
local function install()
  local ah = AuctionHouseFrame
  if QB.installed or type(ah) ~= "table" then return end
  if type(ah.CommoditiesBuyFrame) ~= "table" and type(ah.ItemBuyFrame) ~= "table" then return end
  QB.installed = true
  local ok, err = pcall(function()
    installCommodity(ah)
    installItem(ah)
  end)
  if not ok then
    H.Print("could not set up the double-click on the buy frames (" .. tostring(err) .. ")")
  end
end

H.Events:On("AH_UI_LOADED", install)
H.Events:On("AH_OPENED", install)
