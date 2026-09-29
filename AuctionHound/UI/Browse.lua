-- UI/Browse.lua: the Hound column and filter strip on the Buy tab.
--
-- Blizzard's browse list is a table builder over a scroll box. The
-- column joins its layout the way the Level column does for armor. The
-- strip sits above the headers and swaps the list's data provider for a
-- filtered, sorted order over the same rows. With Depth on, each row on
-- screen is searched for its ladder (Depth.lua) and the cell's tooltip
-- shows it. Buying still goes through Blizzard's own frames.
local ADDON, H = ...

local UI = H.UI
local B = { pages = 0 }
UI.Browse = B

------------------------------------------------------------------------
-- Blizzard's item lists take a layout function that adds their columns
-- to a table builder. Wrapping it runs theirs, then addColumn(tb,
-- owner) for ours, which is then moved in front of the last column so
-- the edge column keeps its place. Returns false when the list has no
-- layout yet.
------------------------------------------------------------------------
local wrapped = setmetatable({}, { __mode = "k" })

function UI.HookListLayout(list, owner, addColumn)
  local orig = list.tableBuilderLayoutFunction
  if type(orig) ~= "function" or wrapped[orig] then return false end
  local function layout(tb)
    orig(tb)
    local col = addColumn(tb, owner)
    local cols = col and tb.GetColumns and tb:GetColumns()
    if type(cols) == "table" and #cols >= 2 and cols[#cols] == col then
      table.remove(cols)
      table.insert(cols, #cols, col)
    end
  end
  wrapped[layout] = true
  list:SetTableBuilderLayout(layout)
  return true
end

B.STRIP_HEIGHT = 24
B.COLUMN_WIDTH = 104

------------------------------------------------------------------------
-- The cell. UI/Cells.xml mixes this into AuctionHoundBrowseCellTemplate.
------------------------------------------------------------------------
AuctionHoundBrowseCellMixin = UI.CellMixin()

function AuctionHoundBrowseCellMixin:Init(owner)
  self.owner = owner
end

function AuctionHoundBrowseCellMixin:Populate(rowData)
  self.rowData = rowData
  local e = H.Browse.Evaluate(rowData)
  local L = nil
  if e and H.Settings().browseDepth then L = H.Depth.Want(rowData) end
  local note, figure, color = H.Browse.CellText(e, L)
  self.Sub:SetText(note)
  self.Text:SetText(figure)
  self.Text:SetTextColor(color[1], color[2], color[3])
end

function AuctionHoundBrowseCellMixin:OnEnter()
  UI.RowScript(self, "OnEnter")
  local e = H.Browse.Evaluate(self.rowData)
  if not e or e.qty == 0 or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("|cffe6b800Hound|r", 1, 1, 1)
  local depthOn = H.Settings().browseDepth
  local L = depthOn and H.Depth.Get(self.rowData) or nil
  if L then
    for _, line in ipairs(H.Ladder.Lines(L)) do
      GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
    end
  else
    if e.ref then
      GameTooltip:AddLine(string.format("reference %s  (%s)", H.Money(e.ref), H.ReferenceSource(e.refSrc, e.st)), 0.8, 0.8, 0.8, true)
      if string.sub(e.refSrc or "", 1, 6) == "prior:" then
        GameTooltip:AddLine("untick estimates on the Hound tab to judge by history alone", 0.6, 0.6, 0.6, true)
      end
    else
      GameTooltip:AddLine(H.NoReferenceLine(), 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(string.format("floor %s, %d units listed", H.Money(e.min), e.qty), 0.8, 0.8, 0.8, true)
    if depthOn and H.Depth.Failed(self.rowData) then
      GameTooltip:AddLine("the house answered with no listings; asked again in a minute", 0.6, 0.6, 0.6, true)
    elseif depthOn then
      GameTooltip:AddLine("reading the listings", 0.6, 0.6, 0.6)
    else
      GameTooltip:AddLine("tick Depth for the units at the floor and the next step", 0.6, 0.6, 0.6, true)
    end
  end
  GameTooltip:Show()
end

function AuctionHoundBrowseCellMixin:OnLeave()
  UI.RowScript(self, "OnLeave")
  if GameTooltip then GameTooltip:Hide() end
end

------------------------------------------------------------------------
-- The column, in front of the favorite star.
------------------------------------------------------------------------
local function addColumn(tb, owner)
  return tb:AddUnsortableFixedWidthColumn(owner, 0, B.COLUMN_WIDTH, 10, 0, "Hound", "AuctionHoundBrowseCellTemplate")
end

local function wrapLayout(list, owner)
  UI.HookListLayout(list, owner, addColumn)
end

------------------------------------------------------------------------
-- The data provider. Blizzard's list reads rows through three
-- functions; ours map through an index over the same rows. An index
-- built for a different row count is stale and passes straight through
-- until the next rebuild.
------------------------------------------------------------------------
local function currentIndex()
  local idx = B.index
  if idx and idx.n == B.getNum() then return idx end
  return nil
end

local function wrapProvider(list)
  local getEntry, getNum = list.getEntry, list.getNumEntries
  if type(getEntry) ~= "function" or type(getNum) ~= "function" then return false end
  B.getEntry, B.getNum = getEntry, getNum
  list:SetDataProvider(
    list.searchStartedFunc,
    function(i)
      local idx = currentIndex()
      if idx then return getEntry(idx[i]) end
      return getEntry(i)
    end,
    function()
      local idx = currentIndex()
      if idx then return #idx end
      return getNum()
    end,
    list.hasFullResultsFunc)
  return true
end

------------------------------------------------------------------------
-- Fetching the rest. With a filter or sort on, the order only means
-- something over the whole result set, so the remaining pages are
-- requested without waiting for a scroll, one at a time through the
-- throttle queue, up to the page setting.
------------------------------------------------------------------------
local function requestMore()
  if B.loading then C_AuctionHouse.RequestMoreBrowseResults() end
end

function B.LoadMore()
  local AH = C_AuctionHouse
  B.loading = false
  if not B.br or not H.Browse.Active() then return end
  if not H.atAH or not B.br:IsShown() then return end
  if AH.HasFullBrowseResults and AH.HasFullBrowseResults() then return end
  if H.Scan.state ~= "idle" then return end
  if B.pages >= (H.Settings().snipePages or 40) then
    B.capped = true
    return
  end
  B.loading = true
  H.Throttle.Send(requestMore)
end

-- A dropped message while a page is wanted: ask again once the system
-- is ready. Blizzard's own scroll can request pages too, so a drop is
-- not always ours, and a spare request is harmless.
H.RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
  if B.loading and not H.Throttle.Pending() then H.Throttle.Send(requestMore) end
end)

------------------------------------------------------------------------
-- Depth: searches go out only while the list shows and no page is on
-- its way. A ladder landing refreshes the rows so the cells show it.
------------------------------------------------------------------------
H.Depth.SetGate(function()
  return B.list ~= nil and B.br ~= nil and B.br:IsShown() and not B.loading
end)

H.Events:On("DEPTH_UPDATED", function()
  if B.list then B.list:DirtyScrollFrame() end
  B.UpdateStrip()
end)

H.Events:On("DEPTH_STATUS", function() B.UpdateStrip() end)

------------------------------------------------------------------------
-- Rebuild after Blizzard's rows change or a toggle moves.
------------------------------------------------------------------------
function B.Rebuild()
  if not B.list then return end
  local S = H.Settings()
  if H.Browse.Active(S) then
    local n = B.getNum()
    local idx = H.Browse.BuildIndex(n, B.getEntry, {
      sort = S.browseSort, deals = S.browseDeals, history = S.browseHistory, notMine = S.browseNotMine,
    })
    idx.n = n
    B.index = idx
  else
    B.index = nil
  end
  B.list:DirtyScrollFrame()
  B.LoadMore()
  H.Depth.Tick()
  B.UpdateStrip()
end

------------------------------------------------------------------------
-- The strip: four toggles, the minimum discount, and a count.
------------------------------------------------------------------------
local function buildStrip(br)
  local strip = CreateFrame("Frame", nil, br)
  strip:SetHeight(B.STRIP_HEIGHT)
  strip:SetPoint("TOPLEFT", br, "TOPLEFT", 6, 0)
  strip:SetPoint("TOPRIGHT", br, "TOPRIGHT", -10, 0)

  local S = H.Settings()
  local prev
  local function toggle(label, key)
    local c = UI.CheckButton(strip, label, function(checked)
      H.Settings()[key] = checked and true or false
      B.Rebuild()
    end)
    c:SetChecked(S[key] and true or false)
    if prev then
      c:SetPoint("LEFT", prev.label, "RIGHT", 10, 0)
    else
      c:SetPoint("LEFT", strip, "LEFT", 0, 0)
    end
    prev = c
    return c
  end
  strip.sort = toggle("Sort by off", "browseSort")
  strip.deals = toggle("Deals only", "browseDeals")
  strip.history = toggle("History only", "browseHistory")
  strip.notMine = toggle("Not mine", "browseNotMine")
  strip.depth = toggle("Depth", "browseDepth")

  local minLabel = UI.Text(strip, "GameFontHighlightSmall", "min", "LEFT")
  minLabel:SetPoint("LEFT", prev.label, "RIGHT", 14, 0)
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

  strip.status = UI.Text(strip, "GameFontDisableSmall", "", "RIGHT")
  strip.status:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
  return strip
end

function B.UpdateStrip()
  local strip = B.strip
  if not strip then return end
  local S = H.Settings()
  strip.sort:SetChecked(S.browseSort and true or false)
  strip.deals:SetChecked(S.browseDeals and true or false)
  strip.history:SetChecked(S.browseHistory and true or false)
  strip.notMine:SetChecked(S.browseNotMine and true or false)
  strip.depth:SetChecked(S.browseDepth and true or false)
  local want = tostring(H.Round((S.minDiscount or 0) * 100))
  if strip.min:GetText() ~= want and not strip.min:HasFocus() then strip.min:SetText(want) end

  local n = B.getNum and B.getNum() or 0
  local idx = B.getNum and currentIndex()
  local text
  if idx then
    text = string.format("%d of %d", #idx, n)
  else
    text = string.format("%d rows", n)
  end
  if B.loading then
    text = text .. ", loading more"
  elseif B.capped then
    text = text .. string.format(", stopped at %d pages", B.pages)
  elseif H.Depth.Reading() then
    text = text .. ", reading depth"
  end
  strip.status:SetText(text)
end

------------------------------------------------------------------------
-- Install once the Blizzard frame exists.
------------------------------------------------------------------------
local function install()
  local ah = AuctionHouseFrame
  local br = type(ah) == "table" and ah.BrowseResultsFrame
  local list = type(br) == "table" and br.ItemList
  if B.installed or type(list) ~= "table" then return end
  B.installed = true
  B.br, B.list = br, list
  local ok, err = pcall(function()
    if not wrapProvider(list) then error("the browse list has no data provider") end
    wrapLayout(list, br)
    hooksecurefunc(br, "SetupTableBuilder", function() wrapLayout(list, br) end)
    hooksecurefunc(br, "UpdateBrowseResults", function(_, added)
      if added then
        B.pages = B.pages + 1
      else
        B.pages = 0
        B.capped = false
      end
      B.Rebuild()
    end)
    br:HookScript("OnShow", function()
      B.LoadMore()
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
    H.Print("could not add the Hound column to the Buy tab (" .. tostring(err) .. ")")
  end
end

H.Events:On("AH_UI_LOADED", install)
H.Events:On("AH_OPENED", install)
H.Events:On("AH_CLOSED", function()
  B.loading = false
end)
H.Events:On("SETTINGS_CHANGED", function()
  if B.list then B.Rebuild() end
end)
-- A scan changes the references, and pages paused for it can resume.
H.Events:On("SCAN_DONE", function()
  if B.list then B.Rebuild() end
end)
