-- UI/Auctions.lua: a Total column on Blizzard's Auctions tab, what
-- each of your auctions brings in. The list shows an open auction's
-- buyout as the unit price, so the product with its units is the
-- total; a sold auction waiting in the mail shows its buyout as the
-- whole sum already, and that is shown as it is.
-- Hovering a total shows the house's cut, the deposit paid and what
-- is left after both. The Bid column goes: it repeats the buyout for
-- anything posted without a separate bid, and the room is better
-- spent on item names.
local ADDON, H = ...

local UI = H.UI
local A = {}
UI.Auctions = A

A.COLUMN_WIDTH = 150

------------------------------------------------------------------------
-- The cell. UI/Cells.xml mixes this into AuctionHoundTotalCellTemplate.
-- It takes the mouse for its tooltip, so hovering is passed on to the
-- row underneath the way Blizzard's own tooltip cells do; clicks fall
-- through to the row by themselves.
------------------------------------------------------------------------
AuctionHoundTotalCellMixin = UI.CellMixin()

function AuctionHoundTotalCellMixin:Init(owner)
  self.owner = owner
end

local SOLD = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold

-- total, cut, what is left and whether the auction has sold, or nil for
-- an auction without a buyout
function A.Figures(rowData)
  local buyout = type(rowData) == "table" and rowData.buyoutAmount or nil
  if not buyout or buyout <= 0 then return nil end
  local sold = SOLD ~= nil and rowData.status == SOLD or false
  local total = sold and buyout or buyout * (rowData.quantity or 1)
  local cut = H.Round(total * (H.Settings().cut or 0))
  return total, cut, total - cut, sold
end

function AuctionHoundTotalCellMixin:Populate(rowData)
  self.rowData = rowData
  local total = A.Figures(rowData)
  self.Text:SetText(total and H.Money(total) or "")
end

function AuctionHoundTotalCellMixin:OnEnter()
  UI.RowScript(self, "OnEnter")
  local r = self.rowData
  local total, cut, net, sold = A.Figures(r)
  if not total or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("|cffe6b800Hound|r total", 1, 1, 1)
  GameTooltip:AddDoubleLine(sold and "sold, the whole auction" or "buyout x units", H.Money(total), 0.8, 0.8, 0.8, 1, 1, 1)
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
  UI.RowScript(self, "OnLeave")
  if GameTooltip then GameTooltip:Hide() end
end

------------------------------------------------------------------------
-- The columns: Bid out, Total in before Time Left.
------------------------------------------------------------------------

-- Blizzard has already built the Bid column and its header by the time
-- the layout reaches us. Taking the column out of the table before it
-- is arranged means no cells are ever made for it; the header goes
-- back to its pool.
function A.DropBid(tb)
  local cols = type(tb) == "table" and tb.GetColumns and tb:GetColumns()
  local bid = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Bid
  if type(cols) ~= "table" or not bid then return nil end
  for i, col in ipairs(cols) do
    local header = col.GetHeaderFrame and col:GetHeaderFrame()
    if type(header) == "table" and header.sortOrder == bid then
      table.remove(cols, i)
      local pools = tb.GetHeaderPoolCollection and tb:GetHeaderPoolCollection()
      if type(pools) == "table" and type(pools.Release) == "function" then
        pcall(pools.Release, pools, header)
      end
      if header.Hide then header:Hide() end
      return col
    end
  end
  return nil
end

local function addColumn(tb, owner)
  A.DropBid(tb)
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
