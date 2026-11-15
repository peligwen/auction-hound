-- UI/Browse.lua: Hound's reading of each row on the Buy tab, and the
-- strip above the list.
--
-- Each row of Blizzard's browse list gets Hound's figures at the right
-- end of its name: the reference, and the units at the floor once
-- Depth has read them, on the left; the discount off the reference on
-- the right, green for a deal, amber under the reference, grey above.
-- The figures are Hound's own frame on the name cell (UI/House.lua has
-- why nothing of Blizzard's is written), and the name gives them room.
-- Hovering a row adds Hound's lines to the row's own tooltip. The strip
-- above the headers sets the minimum a deal clears, turns Depth on and
-- counts the rows and the deals among them. The list keeps Blizzard's
-- order: putting it in another one takes its data provider.
local ADDON, H = ...

local UI = H.UI
local House = UI.House
local B = {}
UI.Browse = B

B.STRIP_HEIGHT = 24
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
  local e = H.Browse.Evaluate(rowData)
  local L = nil
  if e and H.Settings().browseDepth then L = H.Depth.Want(rowData) end
  local note, figure, color = H.Browse.CellText(e, L)
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
  B.UpdateStrip()
end

------------------------------------------------------------------------
-- The row's tooltip: what the figures stand on.
------------------------------------------------------------------------
function B.TooltipLines(tooltip, rowData)
  local e = H.Browse.Evaluate(rowData)
  if not e or e.qty == 0 then return end
  tooltip:AddLine(" ")
  tooltip:AddLine("|cffe6b800Hound|r on the Buy tab", 1, 1, 1)
  local reward = H.Browse.RewardLines(e)
  if reward then
    for i, line in ipairs(reward) do
      local v = i == 1 and 1 or 0.8
      tooltip:AddLine(line, v, v, v, true)
    end
  end
  local depthOn = H.Settings().browseDepth
  local L = depthOn and H.Depth.Get(rowData) or nil
  local cleared = H.Market.ClearedLine(e.st)
  if L then
    for _, line in ipairs(H.Ladder.Lines(L)) do
      tooltip:AddLine(line, 0.8, 0.8, 0.8, true)
    end
    if cleared then tooltip:AddLine(cleared, 0.8, 0.8, 0.8, true) end
    return
  end
  if e.ref then
    tooltip:AddLine(string.format("reference %s  (%s)", H.Money(e.ref), H.ReferenceSource(e.refSrc, e.st)), 0.8, 0.8, 0.8, true)
    if string.sub(e.refSrc or "", 1, 6) == "prior:" then
      tooltip:AddLine("untick estimates on the Hound tab to judge by history alone", 0.6, 0.6, 0.6, true)
    end
  else
    tooltip:AddLine(H.NoReferenceLine(), 0.8, 0.8, 0.8, true)
  end
  tooltip:AddLine(H.Browse.FloorLine(e), 0.8, 0.8, 0.8, true)
  if e.small then
    tooltip:AddLine(string.format("%s under, but only %s a unit; the minimum is %s",
      H.Pct(e.disc), H.MoneyExact(e.saving), H.MoneyExact(H.Settings().minSaving or 0)), 0.85, 0.80, 0.45, true)
  end
  if cleared then tooltip:AddLine(cleared, 0.8, 0.8, 0.8, true) end
  if depthOn and H.Depth.Failed(rowData) then
    tooltip:AddLine("the house answered with no listings; asked again in a minute", 0.6, 0.6, 0.6, true)
  elseif depthOn then
    tooltip:AddLine("reading the listings", 0.6, 0.6, 0.6)
  else
    tooltip:AddLine("tick Depth for the units at the floor and the next step", 0.6, 0.6, 0.6, true)
  end
end

House.OnTooltip("browse", B.TooltipLines)

------------------------------------------------------------------------
-- Depth: searches go out only while the list shows. A ladder landing
-- repaints the figures.
------------------------------------------------------------------------
H.Depth.SetGate(function()
  return B.list ~= nil and B.br ~= nil and B.br:IsShown()
end)

H.Events:On("DEPTH_UPDATED", function() B.Repaint() end)
H.Events:On("DEPTH_STATUS", function() B.UpdateStrip() end)

------------------------------------------------------------------------
-- The strip: the minimum (a percentage and copper a unit), Depth, and
-- a count of the rows and the deals among them.
------------------------------------------------------------------------
-- Money as the copper box shows it: 5s, 1g20s, 0c.
local function boxMoney(copper)
  return (string.gsub(H.MoneyExact(copper or 0), " ", ""))
end

local function tip(frame, ...)
  local lines = { ... }
  frame:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    for i, line in ipairs(lines) do
      if i == 1 then GameTooltip:AddLine(line, 1, 1, 1) else GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function buildStrip(br)
  local strip = CreateFrame("Frame", nil, br)
  strip:SetHeight(B.STRIP_HEIGHT)
  strip:SetPoint("TOPLEFT", br, "TOPLEFT", 6, 0)
  strip:SetPoint("TOPRIGHT", br, "TOPRIGHT", -10, 0)

  local minLabel = UI.Text(strip, "GameFontHighlightSmall", "min", "LEFT")
  minLabel:SetPoint("LEFT", strip, "LEFT", 0, 0)
  local box = UI.EditBox(strip, 34, function(text)
    local v = tonumber(text)
    if not v then return end
    v = H.Clamp(v, 0, 99) / 100
    if math.abs(v - (H.Settings().minDiscount or 0)) < 1e-9 then return end
    H.Settings().minDiscount = v
    H.Events:Fire("SETTINGS_CHANGED", "minDiscount")
  end)
  box:SetPoint("LEFT", minLabel, "RIGHT", 6, 0)
  local pct = UI.Text(strip, "GameFontHighlightSmall", "%", "LEFT")
  pct:SetPoint("LEFT", box, "RIGHT", 2, 0)
  strip.min = box
  tip(box, "Minimum discount",
    "A deal sits at least this far under the reference, in percent.")

  -- the copper minimum: a deal must also sit this many copper a unit
  -- under the reference, so a three-copper item at half price is not one
  local saving = UI.EditBox(strip, 44, function(text)
    local v = H.ParseMoney(text)
    if not v or v < 0 then return end
    if v == (H.Settings().minSaving or 0) then return end
    H.Settings().minSaving = v
    H.Events:Fire("SETTINGS_CHANGED", "minSaving")
  end)
  saving:SetPoint("LEFT", pct, "RIGHT", 6, 0)
  strip.saving = saving
  tip(saving, "Minimum in copper",
    "A deal also sits at least this much a unit under the reference, so a cheap item at half price is not one.",
    "Money as you would type it: 5s, 1g20s. 0 for no such floor.")

  strip.depth = UI.CheckButton(strip, "Depth", function(checked)
    H.Settings().browseDepth = checked and true or false
    B.Repaint()
    H.Depth.Tick()
  end)
  strip.depth:SetPoint("LEFT", saving, "RIGHT", 14, 0)
  tip(strip.depth, "Depth",
    "Each row on screen gets one search of its own, one at a time: its figures then end in the units at the floor, and its tooltip shows the next price step.")

  -- the count fills what is left; anchored on both sides it truncates
  -- on a narrow frame instead of running under the boxes
  strip.status = UI.Text(strip, "GameFontDisableSmall", "", "RIGHT")
  strip.status:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
  strip.status:SetPoint("LEFT", strip.depth.label or strip.depth, "RIGHT", 8, 0)
  return strip
end

-- The rows the house gave and the deals among them: Blizzard's own
-- list of them is read, never written.
function B.Counts()
  local results = B.br and B.br.browseResults
  if type(results) ~= "table" then return 0, 0 end
  local deals = 0
  for _, row in ipairs(results) do
    local e = H.Browse.Evaluate(row)
    if e and e.deal and e.qty > 0 then deals = deals + 1 end
  end
  return #results, deals
end

function B.UpdateStrip()
  local strip = B.strip
  if not strip then return end
  local S = H.Settings()
  strip.depth:SetChecked(S.browseDepth and true or false)
  local want = tostring(H.Round((S.minDiscount or 0) * 100))
  if strip.min:GetText() ~= want and not strip.min:HasFocus() then strip.min:SetText(want) end
  want = boxMoney(S.minSaving)
  if strip.saving:GetText() ~= want and not strip.saving:HasFocus() then strip.saving:SetText(want) end

  local n, deals = B.Counts()
  local text = string.format("%d row%s", n, n == 1 and "" or "s")
  if n > 0 then text = text .. string.format(", %d deal%s", deals, deals == 1 and "" or "s") end
  if H.Depth.Reading() then text = text .. ", reading depth" end
  strip.status:SetText(text)
end

------------------------------------------------------------------------
-- Install once the Blizzard frame exists: the hooks on the name cells,
-- before the list makes any, and the strip.
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
    hooksecurefunc(br, "UpdateBrowseResults", function()
      H.Depth.Tick()
      B.UpdateStrip()
    end)
    br:HookScript("OnShow", function()
      H.Depth.Tick()
      B.UpdateStrip()
    end)

    -- Make room above the headers. The classic background is a fixed
    -- size texture hung from the top, so it is shortened to match.
    list:SetPoint("TOPLEFT", br, "TOPLEFT", 0, -(B.STRIP_HEIGHT + 1))
    if list.Background and list.textureHeightClassic then
      list.Background:SetHeight(list.textureHeightClassic - B.STRIP_HEIGHT - 1)
    end
    B.strip = buildStrip(br)
    B.UpdateStrip()
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
