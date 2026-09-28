-- UI/Browse.lua: the Hound column and filter strip on the Buy tab.
--
-- Blizzard's browse list is a table builder over a scroll box. The
-- column joins its layout the way the Level column does for armor. The
-- strip sits above the headers and swaps the list's data provider for a
-- filtered, sorted order over the same rows. Buying still goes through
-- Blizzard's own frames.
local ADDON, H = ...

local UI = H.UI
local B = { pages = 0, wrapped = setmetatable({}, { __mode = "k" }) }
UI.Browse = B

B.STRIP_HEIGHT = 24
B.COLUMN_WIDTH = 104

------------------------------------------------------------------------
-- The cell. UI/Browse.xml mixes this into AuctionHoundBrowseCellTemplate.
------------------------------------------------------------------------
AuctionHoundBrowseCellMixin = {}

function AuctionHoundBrowseCellMixin:Init(owner)
  self.owner = owner
end

function AuctionHoundBrowseCellMixin:Populate(rowData)
  local note, figure, color = H.Browse.CellText(H.Browse.Evaluate(rowData))
  self.Sub:SetText(note)
  self.Text:SetText(figure)
  self.Text:SetTextColor(color[1], color[2], color[3])
end

------------------------------------------------------------------------
-- The column, appended to Blizzard's layout and moved in front of the
-- favorite star so the star keeps the edge.
------------------------------------------------------------------------
local function addColumn(tb, owner)
  local col = tb:AddUnsortableFixedWidthColumn(owner, 0, B.COLUMN_WIDTH, 10, 0, "Hound", "AuctionHoundBrowseCellTemplate")
  local cols = tb.GetColumns and tb:GetColumns()
  if type(cols) == "table" and #cols >= 2 and cols[#cols] == col then
    table.remove(cols)
    table.insert(cols, #cols, col)
  end
  return col
end

local function wrapLayout(list, owner)
  local orig = list.tableBuilderLayoutFunction
  if type(orig) ~= "function" or B.wrapped[orig] then return end
  local function layout(tb)
    orig(tb)
    addColumn(tb, owner)
  end
  B.wrapped[layout] = true
  list:SetTableBuilderLayout(layout)
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
-- throttle, up to the snipe page setting.
------------------------------------------------------------------------
local pendingSend

local function sendWhenReady(fn)
  local AH = C_AuctionHouse
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    pendingSend = fn
    return
  end
  pendingSend = nil
  fn()
end

H.RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  local fn = pendingSend
  pendingSend = nil
  if fn then fn() end
end)

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
  sendWhenReady(requestMore)
end

-- A dropped message while a page is wanted: ask again once the system
-- is ready. Blizzard's own scroll can request pages too, so a drop is
-- not always ours, and a spare request is harmless.
H.RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
  if B.loading and not pendingSend then sendWhenReady(requestMore) end
end)

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

  local minLabel = UI.Text(strip, "GameFontHighlightSmall", "min", "LEFT")
  minLabel:SetPoint("LEFT", prev.label, "RIGHT", 14, 0)
  local box = UI.EditBox(strip, 34, function(text)
    local v = tonumber(text)
    if not v then return end
    v = H.Clamp(v, 0, 99) / 100
    if math.abs(v - (H.Settings().minDiscount or 0)) < 1e-9 then return end
    H.Settings().minDiscount = v
    B.Rebuild()
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
  pendingSend = nil
end)
H.Events:On("SETTINGS_CHANGED", function()
  if B.list then B.Rebuild() end
end)
