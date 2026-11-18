-- UI/Browse.lua: Hound's reading of each row on the Buy tab.
--
-- Each row of Blizzard's browse list gets Hound's figures at the right
-- end of its name: the reference on the left, the discount off it on
-- the right, green for a deal, amber under the reference, grey above.
-- The figures are Hound's own frame on the name cell (UI/House.lua has
-- why nothing of Blizzard's is written), and the name gives them room.
-- Hovering a row adds Hound's lines to the row's own tooltip. The list
-- keeps Blizzard's order and layout: the minimum, the filters and the
-- order by discount are the Deals view's (UI/Deals.lua), which reads
-- the same results.
local ADDON, H = ...

local UI = H.UI
local House = UI.House
local B = {}
UI.Browse = B

B.COLUMN_WIDTH = 104
B.ROOM = B.COLUMN_WIDTH + 6     -- how far a name is pulled in from its cell's edge

------------------------------------------------------------------------
-- The figures on a row.
------------------------------------------------------------------------
local function build(cell)
  local o = CreateFrame("Frame", nil, cell)
  o:EnableMouse(false)
  o:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
  o:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
  o:SetWidth(B.COLUMN_WIDTH)
  o:SetFrameLevel((cell.GetFrameLevel and cell:GetFrameLevel() or 0) + 2)
  o.Text = UI.Text(o, "Number14FontWhite", "", "RIGHT")
  o.Text:SetPoint("RIGHT", o, "RIGHT", 0, 0)
  o.Sub = UI.Text(o, "GameFontDisableSmall", "", "LEFT")
  o.Sub:SetPoint("LEFT", o, "LEFT", 0, 0)
  o.Sub:SetPoint("RIGHT", o.Text, "LEFT", -4, 0)
  return o
end

function B.Paint(o, rowData)
  local note, figure, color = H.Browse.CellText(H.Browse.Evaluate(rowData))
  o.Sub:SetText(note)
  o.Text:SetText(figure)
  o.Text:SetTextColor(color[1], color[2], color[3])
end

-- Hound's figures for a row, for a test or a look in game.
function B.OverlayFor(cell)
  return House.overlays[cell]
end

local function onBrowse(cell)
  return B.list ~= nil and House.Under(cell, B.list)
end

-- After Blizzard fills a name cell: room for the figures, the figures
-- for the row, and the row noted for its tooltip.
local function onPopulate(cell, rowData, index)
  if not onBrowse(cell) or type(rowData) ~= "table" then return end
  House.MakeRoom(cell, B.ROOM)
  House.Track(cell, "browse", rowData, index)
  B.Paint(House.Overlay(cell, build), rowData)
end

-- The name is drawn again when the item's details arrive late, and
-- anchored to the cell's edge again with it.
local function onDisplay(cell)
  if onBrowse(cell) then House.MakeRoom(cell, B.ROOM) end
end

function B.Repaint()
  House.Each("browse", function(cell, rowData)
    local o = House.overlays[cell]
    if o then B.Paint(o, rowData) end
  end)
end

------------------------------------------------------------------------
-- The row's tooltip: what the figures stand on. The Deals view's rows
-- carry the same lines under their own title.
------------------------------------------------------------------------
function B.ReadingLines(tooltip, rowData, title)
  local e = H.Browse.Evaluate(rowData)
  if not e or e.qty == 0 then return end
  tooltip:AddLine(" ")
  tooltip:AddLine("|cffe6b800Hound|r " .. title, 1, 1, 1)
  local reward = H.Browse.RewardLines(e)
  if reward then
    for i, line in ipairs(reward) do
      local v = i == 1 and 1 or 0.8
      tooltip:AddLine(line, v, v, v, true)
    end
  end
  local cleared = H.Market.ClearedLine(e.st)
  if e.ref then
    tooltip:AddLine(string.format("reference %s  (%s)", H.Money(e.ref), H.ReferenceSource(e.refSrc, e.st)), 0.8, 0.8, 0.8, true)
  else
    tooltip:AddLine(H.NoReferenceLine(), 0.8, 0.8, 0.8, true)
  end
  tooltip:AddLine(H.Browse.FloorLine(e), 0.8, 0.8, 0.8, true)
  if e.small then
    tooltip:AddLine(string.format("%s under, but only %s a unit; the minimum is %s",
      H.Pct(e.disc), H.MoneyExact(e.saving), H.MoneyExact(H.Settings().minSaving or 0)), 0.85, 0.80, 0.45, true)
  end
  if cleared then tooltip:AddLine(cleared, 0.8, 0.8, 0.8, true) end
end

function B.TooltipLines(tooltip, rowData)
  B.ReadingLines(tooltip, rowData, "on the Buy tab")
end

House.OnTooltip("browse", B.TooltipLines)

------------------------------------------------------------------------
-- Install once the Blizzard frame exists: the hooks on the name cells,
-- before the list makes any.
------------------------------------------------------------------------
local function install()
  local ah = AuctionHouseFrame
  local br = type(ah) == "table" and ah.BrowseResultsFrame
  local list = type(br) == "table" and br.ItemList
  if B.installed or type(list) ~= "table" then return end
  B.installed = true
  B.br, B.list = br, list
  local ok, err = pcall(function()
    if not House.HookCells("AuctionHouseTableCellItemDisplayMixin", "Populate", "Buy tab figures", onPopulate) then
      error("the browse list's name cells were not found")
    end
    House.HookCells("AuctionHouseTableCellItemDisplayMixin", "UpdateDisplay", "Buy tab figures", onDisplay)
  end)
  if not ok then
    H.Print("could not add Hound's figures to the Buy tab (" .. tostring(err) .. ")")
  end
end

H.Events:On("AH_UI_LOADED", install)
H.Events:On("AH_OPENED", install)
-- A scan or a setting moves the references: the figures follow.
H.Events:On("SETTINGS_CHANGED", function() if B.list then B.Repaint() end end)
H.Events:On("SCAN_DONE", function() if B.list then B.Repaint() end end)
