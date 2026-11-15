-- UI/Ladder.lua: the listing ladder read on Blizzard's buy frames.
--
-- A click on a Buy tab row opens one of two frames: the commodity buy
-- frame, with a narrow list of unit price and units, or the item buy
-- frame, with a wide list of auctions. Both get an info block with the
-- reference, the deal depth, the next price step and the ladder's own
-- value. On the commodity list each units figure takes the verdict's
-- color; on the item list each auction's discount sits at the right
-- end of its row. A double-click buys the listing under the cursor: an
-- auction at its buyout, or a commodity's units up to that row through
-- Hound's own confirm under the cursor. Nothing of Blizzard's is
-- written or pressed (UI/House.lua has why).
local ADDON, H = ...

local UI = H.UI
local House = UI.House
local AH = C_AuctionHouse
local LU = { current = {}, block = {} }
UI.Ladder = LU

LU.BLOCK_HEIGHT = 62
LU.COLUMN_WIDTH = 56

------------------------------------------------------------------------
-- The info block: four lines.
------------------------------------------------------------------------
local function buildBlock(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(LU.BLOCK_HEIGHT)
  f.lines = {}
  local prev
  for i = 1, 4 do
    local fs = UI.Text(f, i == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall", "", "LEFT")
    if prev then
      fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
      fs:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -2)
    else
      fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
      fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    end
    f.lines[i] = fs
    prev = fs
  end
  function f:SetLines(lines)
    for i = 1, 4 do self.lines[i]:SetText(lines and lines[i] or "") end
  end
  return f
end

------------------------------------------------------------------------
-- Commodities: the ladder from the search results for the item the
-- frame shows, rebuilt on every results event for that item.
------------------------------------------------------------------------
local function commodityListings(itemID)
  local n = AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID) or 0
  local listings = {}
  for i = 1, n do
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice and r.quantity and r.quantity > 0 then
      table.insert(listings, { p = r.unitPrice, q = r.quantity, mine = r.containsOwnerItem })
    end
  end
  return listings
end

-- The units figure in the verdict's color; Blizzard's white where
-- there is none, since a cell is reused for another row as the list
-- scrolls and keeps whatever color it was given last.
local WHITE = { 1, 1, 1 }

local function colorUnits(cell, rowData)
  if type(cell.Text) ~= "table" then return end
  local verdict, low = H.Ladder.Verdict(LU.current.commodity, rowData and rowData.unitPrice)
  local color = H.Ladder.Color(verdict, low) or WHITE
  cell.Text:SetTextColor(color[1], color[2], color[3])
end

function LU.RebuildCommodity()
  local itemID = LU.commodityItemID
  local block = LU.block.commodity
  if not itemID then
    LU.current.commodity = nil
    if block then block:SetLines(nil) end
    return
  end
  local key = H.KeyForItemID(itemID) or tostring(itemID)
  LU.current.commodity = H.Ladder.Build(commodityListings(itemID), key, itemID)
  if block then block:SetLines(H.Ladder.Lines(LU.current.commodity)) end
  House.Each("commodity", colorUnits)
end

local function onCommodityResults(itemID)
  if itemID and itemID == LU.commodityItemID then LU.RebuildCommodity() end
end

H.RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", onCommodityResults)
H.RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED", onCommodityResults)
H.RegisterEvent("COMMODITY_SEARCH_RESULTS_RECEIVED", onCommodityResults)

local function onUnits(cell, rowData, index)
  local frame = LU.commodityFrame
  if not frame or not House.Under(cell, frame.ItemList) or type(rowData) ~= "table" then return end
  House.Track(cell, "commodity", rowData, index)
  colorUnits(cell, rowData)
end

local function installCommodity(ah)
  local frame = ah.CommoditiesBuyFrame
  if type(frame) ~= "table" or type(frame.ItemList) ~= "table" or type(frame.BuyDisplay) ~= "table" then return false end
  LU.commodityFrame = frame
  House.HookCells("AuctionHouseTableCellCommoditiesQuantityMixin", "Populate", "commodity list colors", onUnits)
  hooksecurefunc(frame, "SetItemIDAndPrice", function(_, itemID)
    LU.commodityItemID = itemID
    LU.current.commodity = nil
    if LU.block.commodity then LU.block.commodity:SetLines({ "reading the listings" }) end
  end)
  -- the buy display leaves room under its buy button
  local block = buildBlock(frame.BuyDisplay)
  block:SetPoint("BOTTOMLEFT", frame.BuyDisplay, "BOTTOMLEFT", 15, 14)
  block:SetPoint("BOTTOMRIGHT", frame.BuyDisplay, "BOTTOMRIGHT", -16, 14)
  LU.block.commodity = block
  return true
end

------------------------------------------------------------------------
-- Items: each auction's discount at the right end of its row, in the
-- wide units column, and the block above the headers.
------------------------------------------------------------------------
local function itemListings(itemKey)
  local n = AH.GetNumItemSearchResults and AH.GetNumItemSearchResults(itemKey) or 0
  local listings = {}
  for i = 1, n do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 then
      table.insert(listings, { p = r.buyoutAmount, q = r.quantity or 1, mine = r.containsOwnerItem })
    end
  end
  return listings
end

local function buildOff(cell)
  local o = CreateFrame("Frame", nil, cell)
  o:EnableMouse(false)
  o:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
  o:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
  o:SetWidth(LU.COLUMN_WIDTH)
  o:SetFrameLevel((cell.GetFrameLevel and cell:GetFrameLevel() or 0) + 2)
  o.Text = UI.Text(o, "Number14FontWhite", "", "RIGHT")
  o.Text:SetPoint("RIGHT", o, "RIGHT", 0, 0)
  return o
end

function LU.PaintOff(o, rowData)
  local L = LU.current.item
  local p = type(rowData) == "table" and rowData.buyoutAmount or nil
  if not p or p <= 0 then
    o.Text:SetText("")
    return
  end
  o.Text:SetText(H.Ladder.Off(L, p))
  local verdict, low = H.Ladder.Verdict(L, p)
  local color = H.Ladder.Color(verdict, low) or H.Browse.COLORS.over
  o.Text:SetTextColor(color[1], color[2], color[3])
end

function LU.OffFor(cell)
  return House.overlays[cell]
end

local function paintItemRow(cell, rowData)
  local o = House.overlays[cell]
  if o then LU.PaintOff(o, rowData) end
end

function LU.RebuildItem()
  local itemKey = LU.itemKey
  local block = LU.block.item
  if not itemKey then
    LU.current.item = nil
    if block then block:SetLines(nil) end
    return
  end
  LU.current.item = H.Ladder.Build(itemListings(itemKey), H.KeyFromItemKey(itemKey), itemKey.itemID)
  if block then block:SetLines(H.Ladder.Lines(LU.current.item)) end
  House.Each("item", paintItemRow)
end

local function onItemResults(itemKey)
  if not itemKey or not LU.itemKey then return end
  if H.KeyString(itemKey) == H.KeyString(LU.itemKey) then LU.RebuildItem() end
end

H.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", onItemResults)
H.RegisterEvent("ITEM_SEARCH_RESULTS_ADDED", onItemResults)

local function onItemUnits(cell, rowData, index)
  local frame = LU.itemFrame
  if not frame or not House.Under(cell, frame.ItemList) or type(rowData) ~= "table" then return end
  House.Track(cell, "item", rowData, index)
  LU.PaintOff(House.Overlay(cell, buildOff), rowData)
end

local function installItem(ah)
  local frame = ah.ItemBuyFrame
  if type(frame) ~= "table" or type(frame.ItemList) ~= "table" then return false end
  LU.itemFrame = frame
  local list = frame.ItemList
  House.HookCells("AuctionHouseTableCellItemQuantityMixin", "Populate", "item list discounts", onItemUnits)
  hooksecurefunc(frame, "SetItemKey", function(_, itemKey)
    LU.itemKey = itemKey
    LU.current.item = nil
    if LU.block.item then LU.block.item:SetLines({ "reading the auctions" }) end
  end)
  -- make room between the item header and the list
  local block = buildBlock(frame)
  if type(frame.ItemDisplay) == "table" then
    block:SetPoint("TOPLEFT", frame.ItemDisplay, "BOTTOMLEFT", 12, -8)
    block:SetPoint("TOPRIGHT", frame.ItemDisplay, "BOTTOMRIGHT", -12, -8)
    list:SetPoint("TOP", frame.ItemDisplay, "BOTTOM", 0, -(14 + LU.BLOCK_HEIGHT + 4))
  else
    block:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -8)
    block:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -8)
  end
  if list.Background and list.textureHeightClassic then
    list.Background:SetHeight(list.textureHeightClassic - LU.BLOCK_HEIGHT - 4)
  end
  LU.block.item = block
  return true
end

------------------------------------------------------------------------
-- A double-click on a listing buys it. An item goes straight to its
-- buyout: the double-click is the hardware event the house wants for
-- a bid. A commodity row asks the house for a price on every unit up
-- to it, the way Blizzard's own click selects them, and Hound's confirm
-- opens under the cursor with the total: the house wants a second
-- hardware event for the confirm, and that is the one click left.
-- Every purchase is noted by Buy.lua either way.
------------------------------------------------------------------------

-- Buys one auction of the item list outright. Returns true, or false
-- and why not.
function LU.BuyItem(rowData)
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
function LU.UnitsUpTo(itemID, rowData)
  if not itemID then return 0 end
  local n = AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID) or 0
  local units = 0
  for i = 1, n do
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r then
      units = units + math.max(0, (r.quantity or 0) - (r.numOwnerItems or 0))
      if type(rowData) == "table" and ((rowData.auctionID and r.auctionID == rowData.auctionID)
        or (not rowData.auctionID and r.unitPrice and rowData.unitPrice and r.unitPrice >= rowData.unitPrice)) then
        return units
      end
    end
  end
  return units
end

-- What the cheapest n units listed come to, less your own: the
-- confirm's estimate when its units box changes.
function LU.PriceOf(itemID, n)
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
-- opens Hound's confirm under the cursor (UI/Confirm.lua). Returns
-- true, or false and why.
function LU.BuyCommodity(rowData)
  local itemID = LU.commodityItemID
  if not itemID then return false, "no commodity on the buy frame" end
  local qty = LU.UnitsUpTo(itemID, rowData)
  if qty <= 0 then return false, "nothing there to buy: those are your own" end
  UI.Confirm.Commodity(itemID, qty, LU.UnitsUpTo(itemID), function(n) return LU.PriceOf(itemID, n) end)
  return true
end

House.OnDoubleClick("item", function(rowData)
  local ok, why = LU.BuyItem(rowData)
  if not ok and why then H.Print(why) end
end)

House.OnDoubleClick("commodity", function(rowData)
  local ok, why = LU.BuyCommodity(rowData)
  if not ok and why then H.Print(why) end
end)

------------------------------------------------------------------------
-- Install once the Blizzard frame exists.
------------------------------------------------------------------------
local function install()
  local ah = AuctionHouseFrame
  if LU.installed or type(ah) ~= "table" then return end
  if type(ah.CommoditiesBuyFrame) ~= "table" and type(ah.ItemBuyFrame) ~= "table" then return end
  LU.installed = true
  local ok, err = pcall(function()
    installCommodity(ah)
    installItem(ah)
  end)
  if not ok then
    H.Print("could not read the listing ladder on the buy frames (" .. tostring(err) .. ")")
  end
end

-- A scan or a setting that moves the reference re-reads the ladders
-- on show from the listings the house already gave.
local function rebuildCurrent()
  if LU.commodityItemID then LU.RebuildCommodity() end
  if LU.itemKey then LU.RebuildItem() end
end

H.Events:On("AH_UI_LOADED", install)
H.Events:On("AH_OPENED", install)
H.Events:On("SCAN_DONE", rebuildCurrent)
H.Events:On("SETTINGS_CHANGED", rebuildCurrent)
