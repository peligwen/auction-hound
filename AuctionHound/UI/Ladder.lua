-- UI/Ladder.lua: the listing ladder read on Blizzard's buy frames.
--
-- A click on a Buy tab row opens one of two frames: the commodity buy
-- frame, with a narrow list of unit price and units, or the item buy
-- frame, with a wide list of auctions. Both get an info block with the
-- reference, the deal depth, the next price step and the ladder's own
-- value. The commodity list is too narrow for a column, so its units
-- figure takes the verdict's color instead; the item list gets a
-- discount column. On both lists a shift-double-click buys the listing
-- under the cursor.
local ADDON, H = ...

local UI = H.UI
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
  local list = LU.commodityFrame and LU.commodityFrame.ItemList
  if list and list.DirtyScrollFrame then list:DirtyScrollFrame() end
end

local function onCommodityResults(itemID)
  if itemID and itemID == LU.commodityItemID then LU.RebuildCommodity() end
end

H.RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", onCommodityResults)
H.RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED", onCommodityResults)
H.RegisterEvent("COMMODITY_SEARCH_RESULTS_RECEIVED", onCommodityResults)

-- The units cell of Blizzard's commodity lists. Cells are made from
-- the mixin after this hook is in place, so every cell carries it; the
-- owner check keeps the sell list's cells untouched.
local function hookQuantityCells()
  local mixin = AuctionHouseTableCellCommoditiesQuantityMixin
  if LU.quantityHooked or type(mixin) ~= "table" or type(mixin.Populate) ~= "function" then return end
  LU.quantityHooked = true
  hooksecurefunc(mixin, "Populate", function(cell, rowData)
    local frame = LU.commodityFrame
    if not frame or cell.owner ~= frame.ItemList or not cell.Text then return end
    LU.WatchRow(cell, "commodity", rowData)
    local verdict, low = H.Ladder.Verdict(LU.current.commodity, rowData and rowData.unitPrice)
    local color = H.Ladder.Color(verdict, low)
    if color then cell.Text:SetTextColor(color[1], color[2], color[3]) end
  end)
end

local function installCommodity(ah)
  local frame = ah.CommoditiesBuyFrame
  if type(frame) ~= "table" or type(frame.ItemList) ~= "table" or type(frame.BuyDisplay) ~= "table" then return false end
  LU.commodityFrame = frame
  hookQuantityCells()
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
-- Items: a discount column on the auction list and the block above
-- its headers.
------------------------------------------------------------------------
AuctionHoundLadderCellMixin = UI.CellMixin()

function AuctionHoundLadderCellMixin:Init(owner)
  self.owner = owner
end

function AuctionHoundLadderCellMixin:Populate(rowData)
  LU.WatchRow(self, "item", rowData)
  local L = LU.current.item
  local p = type(rowData) == "table" and rowData.buyoutAmount or nil
  if not p or p <= 0 then
    self.Text:SetText("")
    return
  end
  self.Text:SetText(H.Ladder.Off(L, p))
  local verdict, low = H.Ladder.Verdict(L, p)
  local color = H.Ladder.Color(verdict, low) or H.Browse.COLORS.over
  self.Text:SetTextColor(color[1], color[2], color[3])
end

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
  local list = LU.itemFrame and LU.itemFrame.ItemList
  if list and list.DirtyScrollFrame then list:DirtyScrollFrame() end
end

local function onItemResults(itemKey)
  if not itemKey or not LU.itemKey then return end
  if H.KeyString(itemKey) == H.KeyString(LU.itemKey) then LU.RebuildItem() end
end

H.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", onItemResults)
H.RegisterEvent("ITEM_SEARCH_RESULTS_ADDED", onItemResults)

local function addItemColumn(tb, owner)
  return tb:AddUnsortableFixedWidthColumn(owner, 0, LU.COLUMN_WIDTH, 10, 0, "Hound", "AuctionHoundLadderCellTemplate")
end

local function installItem(ah)
  local frame = ah.ItemBuyFrame
  if type(frame) ~= "table" or type(frame.ItemList) ~= "table" then return false end
  LU.itemFrame = frame
  local list = frame.ItemList
  UI.HookListLayout(list, frame, addItemColumn)
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
-- Shift-double-click on a listing buys it. An item goes straight to
-- its buyout: the double-click is the hardware event the house wants
-- for a bid. A commodity row is already selected by the first click,
-- with every unit up to it in the buy display, so the house's own Buy
-- button is pressed for it and its dialog quotes the total: the house
-- wants a second hardware event for the confirm, and that is the one
-- click left. Every purchase is noted by Buy.lua either way.
------------------------------------------------------------------------
local watched = setmetatable({}, { __mode = "k" })

local function shiftHeld()
  return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

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

-- Presses the house's Buy button for the units selected in the
-- commodity buy display. Returns true, or false and why not.
function LU.BuyCommodity()
  local frame = LU.commodityFrame
  local display = type(frame) == "table" and frame.BuyDisplay
  local button = type(display) == "table" and display.BuyButton
  if type(button) ~= "table" or type(button.Click) ~= "function" then
    return false, "the house's Buy button was not found; use it by hand"
  end
  local qty = type(display.GetQuantity) == "function" and display:GetQuantity() or nil
  if qty == 0 or (button.IsEnabled and not button:IsEnabled()) then
    return false, "select the units first"
  end
  H.Printf("%s: the house's dialog quotes the total, confirm it there", qty and (qty .. " units") or "buying")
  button:Click()
  return true
end

local function onDoubleClick(row)
  if not shiftHeld() then return end
  local ok, why
  if row.houndKind == "item" then
    ok, why = LU.BuyItem(row.houndRow)
  else
    ok, why = LU.BuyCommodity()
  end
  if not ok and why then H.Print(why) end
end

-- Called as a cell is populated: the row behind it learns its listing
-- and, once, answers a double-click. Rows are reused as the list
-- scrolls, so the listing is refreshed every time.
function LU.WatchRow(cell, kind, rowData)
  local row = type(cell) == "table" and cell.GetParent and cell:GetParent()
  if type(row) ~= "table" then return end
  row.houndKind, row.houndRow = kind, rowData
  if watched[row] then return end
  watched[row] = true
  if row.GetScript and row:GetScript("OnDoubleClick") then
    row:HookScript("OnDoubleClick", onDoubleClick)
  elseif row.SetScript then
    row:SetScript("OnDoubleClick", onDoubleClick)
  end
end

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
