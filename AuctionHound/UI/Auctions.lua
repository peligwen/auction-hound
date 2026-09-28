-- UI/Auctions.lua: a Total column on Blizzard's Auctions tab, buyout
-- times units for each of your auctions, with the house's cut beside
-- it in grey. The list shows the buyout as a unit price, so the
-- product is what the whole auction brings in. The deposit lives in
-- the cell's tooltip and in the History view, since Blizzard's list
-- has no room for another column without crushing the item names.
local ADDON, H = ...

local UI = H.UI
local A = {}
UI.Auctions = A

A.COLUMN_WIDTH = 150

------------------------------------------------------------------------
-- The cell. UI/Cells.xml mixes this into AuctionHoundTotalCellTemplate.
------------------------------------------------------------------------
AuctionHoundTotalCellMixin = {}

function AuctionHoundTotalCellMixin:Init(owner)
  self.owner = owner
end

-- total, cut and what is left, or nil for an auction without a buyout
function A.Figures(rowData)
  local buyout = type(rowData) == "table" and rowData.buyoutAmount or nil
  if not buyout or buyout <= 0 then return nil end
  local total = buyout * (rowData.quantity or 1)
  local cut = H.Round(total * (H.Settings().cut or 0))
  return total, cut, total - cut
end

function AuctionHoundTotalCellMixin:Populate(rowData)
  self.rowData = rowData
  local total, cut = A.Figures(rowData)
  if not total then
    self.Text:SetText("")
    self.Sub:SetText("")
    return
  end
  self.Text:SetText(H.Money(total))
  self.Sub:SetText(cut > 0 and ("(-" .. H.Money(cut) .. ")") or "")
end

function AuctionHoundTotalCellMixin:OnEnter()
  local r = self.rowData
  local total, cut, net = A.Figures(r)
  if not total or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("|cffe6b800Hound|r total", 1, 1, 1)
  GameTooltip:AddDoubleLine("buyout x units", H.Money(total), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine(string.format("cut %d%%", H.Round((H.Settings().cut or 0) * 100)), "-" .. H.Money(cut), 0.8, 0.8, 0.8, 1, 1, 1)
  local post = H.Fan.PostForAuction and H.Fan.PostForAuction(r.auctionID)
  if post and post.deposit then
    GameTooltip:AddDoubleLine("deposit paid", H.Money(post.deposit), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("left after cut and deposit", H.Money(net - post.deposit), 0.8, 0.8, 0.8, 0.4, 0.9, 0.4)
  else
    GameTooltip:AddDoubleLine("left after the cut", H.Money(net), 0.8, 0.8, 0.8, 0.4, 0.9, 0.4)
    GameTooltip:AddLine("deposit not recorded: posted before the addon saw it", 0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

function AuctionHoundTotalCellMixin:OnLeave()
  if GameTooltip then GameTooltip:Hide() end
end

-- the cell takes the mouse for its tooltip, so pass a click on to the
-- row underneath
function AuctionHoundTotalCellMixin:OnMouseUp(button)
  local row = self:GetParent()
  if row and row.Click then row:Click(button or "LeftButton") end
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
