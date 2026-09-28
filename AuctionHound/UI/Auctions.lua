-- UI/Auctions.lua: a Total column on Blizzard's Auctions tab, buyout
-- times units for each of your auctions. The list shows the buyout as
-- a unit price, so the product is what the whole auction brings in.
local ADDON, H = ...

local UI = H.UI
local A = {}
UI.Auctions = A

A.COLUMN_WIDTH = 110

------------------------------------------------------------------------
-- The cell. UI/Cells.xml mixes this into AuctionHoundTotalCellTemplate.
------------------------------------------------------------------------
AuctionHoundTotalCellMixin = {}

function AuctionHoundTotalCellMixin:Init(owner)
  self.owner = owner
end

function AuctionHoundTotalCellMixin:Populate(rowData)
  local buyout = type(rowData) == "table" and rowData.buyoutAmount or nil
  if not buyout or buyout <= 0 then
    self.Text:SetText("")
    return
  end
  self.Text:SetText(H.Money(buyout * (rowData.quantity or 1)))
end

local function addColumn(tb, owner)
  return tb:AddUnsortableFixedWidthColumn(owner, 0, A.COLUMN_WIDTH, 10, 0, "Total", "AuctionHoundTotalCellTemplate")
end

------------------------------------------------------------------------
-- Install once the Blizzard frame exists. The list's layout is set
-- when the frame loads and never rebuilt, so one wrap is enough.
------------------------------------------------------------------------
local function install()
  local ah = AuctionHouseFrame
  local af = type(ah) == "table" and ah.AuctionsFrame
  local list = type(af) == "table" and af.AllAuctionsList
  if A.installed or type(list) ~= "table" then return end
  A.installed = true
  A.list = list
  local ok, err = pcall(UI.HookListLayout, list, af, addColumn)
  if not ok then
    H.Print("could not add the Total column to the Auctions tab (" .. tostring(err) .. ")")
  end
end

H.Events:On("AH_UI_LOADED", install)
H.Events:On("AH_OPENED", install)
