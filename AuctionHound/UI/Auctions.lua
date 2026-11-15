-- UI/Auctions.lua: what each of your auctions brings in, on Blizzard's
-- Auctions tab. The list shows an open auction's buyout as the unit
-- price, so the product with its units is the total; a sold auction
-- waiting in the mail shows its buyout as the whole sum already, and
-- that is shown as it is. The total sits at the right end of the
-- auction's name, as Hound's own frame (UI/House.lua has why), and
-- hovering the row adds the house's cut, the deposit paid and what is
-- left after both to the row's own tooltip.
local ADDON, H = ...

local UI = H.UI
local House = UI.House
local A = {}
UI.Auctions = A

A.COLUMN_WIDTH = 130
A.ROOM = A.COLUMN_WIDTH + 6

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

------------------------------------------------------------------------
-- The total on a row.
------------------------------------------------------------------------
local function build(cell)
  local o = CreateFrame("Frame", nil, cell)
  o:EnableMouse(false)
  o:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
  o:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
  o:SetWidth(A.COLUMN_WIDTH)
  o:SetFrameLevel((cell.GetFrameLevel and cell:GetFrameLevel() or 0) + 2)
  o.Text = UI.Text(o, "Number14FontWhite", "", "RIGHT")
  o.Text:SetPoint("RIGHT", o, "RIGHT", 0, 0)
  return o
end

function A.Paint(o, rowData)
  local total = A.Figures(rowData)
  o.Text:SetText(total and H.Money(total) or "")
end

function A.OverlayFor(cell)
  return House.overlays[cell]
end

local function onAuctions(cell)
  return A.list ~= nil and House.Under(cell, A.list)
end

local function onPopulate(cell, rowData, index)
  if not onAuctions(cell) or type(rowData) ~= "table" then return end
  House.MakeRoom(cell, A.ROOM)
  House.Track(cell, "auction", rowData, index)
  A.Paint(House.Overlay(cell, build), rowData)
end

local function onDisplay(cell)
  if onAuctions(cell) then House.MakeRoom(cell, A.ROOM) end
end

function A.Repaint()
  House.Each("auction", function(cell, rowData)
    local o = House.overlays[cell]
    if o then A.Paint(o, rowData) end
  end)
end

------------------------------------------------------------------------
-- The row's tooltip: the cut and the deposit.
------------------------------------------------------------------------
function A.TooltipLines(tooltip, r)
  local total, cut, net, sold = A.Figures(r)
  if not total then return end
  tooltip:AddLine(" ")
  tooltip:AddLine("|cffe6b800Hound|r total", 1, 1, 1)
  tooltip:AddDoubleLine(sold and "sold, the whole auction" or "buyout x units", H.Money(total), 0.8, 0.8, 0.8, 1, 1, 1)
  tooltip:AddDoubleLine(string.format("cut %d%%", H.Round((H.Settings().cut or 0) * 100)), "-" .. H.Money(cut), 0.8, 0.8, 0.8, 1, 1, 1)
  local post = H.Fan.PostForAuction and H.Fan.PostForAuction(r.auctionID)
  if post and post.deposit then
    tooltip:AddDoubleLine("deposit paid", H.Money(post.deposit), 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddDoubleLine("left after cut and deposit", H.Money(net - post.deposit), 0.8, 0.8, 0.8, 0.4, 0.9, 0.4)
  else
    tooltip:AddDoubleLine("left after the cut", H.Money(net), 0.8, 0.8, 0.8, 0.4, 0.9, 0.4)
    tooltip:AddLine("deposit not recorded: posted before the addon saw it", 0.6, 0.6, 0.6, true)
  end
end

House.OnTooltip("auction", A.TooltipLines)

------------------------------------------------------------------------
-- Install once the Blizzard frame exists, before the list makes cells.
------------------------------------------------------------------------
local function install()
  local ah = AuctionHouseFrame
  local af = type(ah) == "table" and ah.AuctionsFrame
  local list = type(af) == "table" and af.AllAuctionsList
  if A.installed or type(list) ~= "table" then return end
  A.installed = true
  A.list = list
  local ok = House.HookCells("AuctionHouseTableCellAuctionsItemDisplayMixin", "Populate", "Auctions tab total", onPopulate)
  House.HookCells("AuctionHouseTableCellAuctionsItemDisplayMixin", "UpdateDisplay", "Auctions tab total", onDisplay)
  if not ok then
    H.Print("could not add the total to the Auctions tab (its name cells were not found)")
  end
end

H.Events:On("AH_UI_LOADED", install)
H.Events:On("AH_OPENED", install)
H.Events:On("SETTINGS_CHANGED", function() if A.list then A.Repaint() end end)
