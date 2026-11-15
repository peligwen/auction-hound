-- UI/Deals.lua: the Deals view, a buy list of Hound's own.
--
-- Blizzard's Buy tab keeps the house's order and its own columns (see
-- UI/House.lua for why Hound writes nothing there). The Deals view reads
-- the same results into a list that is Hound's frame through and
-- through, so it can be sorted by discount and filtered:
--
--   * Its rows are the house's results for the last search, whoever
--     made it: Hound's search box, or Blizzard's own search and
--     category tree on the Buy tab. Hound asks the house for the rest
--     of the pages while the view shows. Or, with the source set to
--     the last scan, every item the last full scan saw, at its floor
--     then, house open or not.
--   * Each row is read as the Buy tab reads it (Browse.lua): floor,
--     units, reference, discount, saving a unit, how long the floor
--     has been on offer, and with Depth on the units at or under the
--     deal limit.
--   * The filters: the minimum a deal clears (the same setting as
--     everywhere), deals only, history only, your own auctions left
--     out, a cap on the floor, the lowest quality and the item class.
--   * A double-click buys through Hound's own confirm (UI/Confirm.lua):
--     the units of a commodity at or under the deal limit, or the
--     cheapest auction of an item, read with one search first when
--     Depth has not read them already.
local ADDON, H = ...

local UI = H.UI
local AH = C_AuctionHouse
local D = { houseRows = {} }
UI.Deals = D

D.MAX_ROWS = 3000       -- results paged in before Hound stops asking for more
D.PAGE_TIMEOUT = 10     -- seconds to wait on a page before asking again

D.SOURCES = { "House", "Last scan" }
D.SOURCE_KEYS = { House = "house", ["Last scan"] = "scan" }

D.QUALITIES = {
  { 0, "Any quality" }, { 1, "Common+" }, { 2, "Uncommon+" }, { 3, "Rare+" }, { 4, "Epic+" },
}

-- The item classes the house sells, as Enum.ItemClass numbers them.
D.CLASSES = {
  { -1, "All items" }, { 2, "Weapons" }, { 4, "Armor" }, { 1, "Containers" }, { 0, "Consumables" },
  { 7, "Trade Goods" }, { 6, "Projectiles" }, { 11, "Quivers" }, { 9, "Recipes" }, { 5, "Reagents" },
  { 15, "Miscellaneous" },
}

local function labels(list)
  local out = {}
  for i, o in ipairs(list) do out[i] = o[2] end
  return out
end

local function valueOf(list, label)
  for _, o in ipairs(list) do if o[2] == label then return o[1] end end
  return list[1][1]
end

local function labelOf(list, value)
  for _, o in ipairs(list) do if o[1] == value then return o[2] end end
  return list[1][2]
end

function D.Source()
  return H.Settings().dealsSource == "scan" and "scan" or "house"
end

local function classOf(itemID)
  if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
  return select(6, C_Item.GetItemInfoInstant(itemID))
end

local function depthOf(row)
  return H.Settings().browseDepth and H.Depth.Get(row.raw) or nil
end

------------------------------------------------------------------------
-- Rows: a browse row (the house's, or one made from the last scan) and
-- Hound's reading of it.
------------------------------------------------------------------------
local function makeRow(raw)
  if type(raw) ~= "table" or type(raw.itemKey) ~= "table" or (raw.totalQuantity or 0) == 0 then return nil end
  local e = H.Browse.Evaluate(raw)
  if not e then return nil end
  return { key = H.KeyString(raw.itemKey), raw = raw, itemKey = raw.itemKey, itemID = e.itemID, e = e }
end

-- Every item the last full scan saw on offer, at its floor then.
function D.ScanRows()
  local out = {}
  local last = H.db and H.db.lastFull or 0
  if last <= 0 then return out end
  local now = H.Now()
  for _, key in ipairs(H.Store.Keys()) do
    local rec = H.Store.Get(key)
    local st = rec and H.Market.Stats(rec, now)
    if st and st.at and st.at >= last and (st.min or 0) > 0 and (st.qty or 0) > 0 then
      table.insert(out, { itemKey = H.ItemKeyFromString(key), minPrice = st.min, totalQuantity = st.qty, fromScan = true })
    end
  end
  return out
end

function D.Build()
  local raws = D.Source() == "scan" and D.ScanRows() or D.houseRows
  local rows = {}
  for _, raw in ipairs(raws) do
    local row = makeRow(raw)
    if row then table.insert(rows, row) end
  end
  D.rows = rows
  return rows
end

-- A setting, a scan or a ladder moved the readings: every row is read
-- again, or only the rows of one history key.
function D.Reread(key)
  for _, row in ipairs(D.rows or {}) do
    if not key or row.e.key == key then
      row.e = H.Browse.Evaluate(row.raw) or row.e
    end
  end
end

function D.Passes(row)
  local S = H.Settings()
  local e = row.e
  if S.dealsOnly and not e.deal then return false end
  if S.dealsHistory and not e.history then return false end
  if S.dealsHideMine and e.mine then return false end
  if (S.dealsMaxPrice or 0) > 0 and e.min > S.dealsMaxPrice then return false end
  if (S.dealsQuality or 0) > 0 then
    local q = H.ItemQuality(e.itemID)
    if q and q < S.dealsQuality then return false end
  end
  if (S.dealsClass or -1) >= 0 then
    local c = classOf(e.itemID)
    if c and c ~= S.dealsClass then return false end
  end
  if D.Source() == "scan" and (D.text or "") ~= "" then
    if not string.find(string.lower(H.ItemName(e.itemID)), string.lower(D.text), 1, true) then return false end
  end
  return true
end

function D.Counts()
  local n, deals = 0, 0
  for _, row in ipairs(D.rows or {}) do
    n = n + 1
    if row.e.deal then deals = deals + 1 end
  end
  return n, deals, D.view and #D.view.table.view or 0
end

------------------------------------------------------------------------
-- The house's results: the last search's, read as the house sends them,
-- and paged in while the view shows.
------------------------------------------------------------------------
local function shown()
  return D.view ~= nil and D.view:IsShown() and UI.IsShown()
end

local function full()
  return not (AH.HasFullBrowseResults and not AH.HasFullBrowseResults())
end

function D.Paging()
  return D.Source() == "house" and H.atAH and not full() and #D.houseRows < D.MAX_ROWS
end

-- Asks for the next page, one at a time, through the throttle.
function D.More()
  if D.asking or not shown() or not D.Paging() or H.Scan.state ~= "idle" then return false end
  D.asking = true
  local ask = {}
  D.ask = ask
  C_Timer.After(D.PAGE_TIMEOUT, function() if D.ask == ask then D.asking, D.ask = nil, nil end end)
  H.Throttle.Send(function() AH.RequestMoreBrowseResults() end)
  return true
end

-- The quality filters a query carries: the house reads them as the
-- qualities to include, and Blizzard's own search sends every one of
-- them unless one is unticked, so Hound sends those from the lowest
-- quality shown up.
function D.QualityFilters(min)
  local F = Enum and Enum.AuctionHouseFilter
  local out = {}
  if not F then return out end
  local byQuality = { [0] = F.PoorQuality, F.CommonQuality, F.UncommonQuality, F.RareQuality, F.EpicQuality, F.LegendaryQuality }
  for q = min or 0, 5 do
    if byQuality[q] then table.insert(out, byQuality[q]) end
  end
  return out
end

-- Hound's own search: the text, the class when one is picked, and the
-- qualities shown; no level range, as Blizzard's search has none by
-- default.
function D.Search(text)
  if not H.atAH then
    H.Print("open the auction house to search it")
    return false
  end
  D.text = text or ""
  local class = H.Settings().dealsClass or -1
  local query = {
    searchString = D.text,
    minLevel = 0,
    maxLevel = 0,
    sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
    filters = D.QualityFilters(H.Settings().dealsQuality or 0),
    itemClassFilters = class >= 0 and { { classID = class } } or {},
  }
  D.searched = { text = D.text, class = class }
  D.houseRows, D.asking, D.ask = {}, nil, nil
  -- the house's answers to Hound's own queries still to come: an answer
  -- with none outstanding is to a search of Blizzard's
  D.waiting = (D.waiting or 0) + 1
  H.Throttle.Send(function()
    local ok, err = pcall(AH.SendBrowseQuery, query)
    if not ok then
      D.waiting = math.max(0, (D.waiting or 1) - 1)
      H.Print("the house would not take the search: " .. tostring(err))
      D.Refresh()
    end
  end)
  D.Refresh()
  return true
end

-- A page: its rows are read and added, the rest left as they are.
function D.Append(raws)
  if not (D.view and D.view:IsShown()) then return end
  for _, raw in ipairs(raws) do
    local row = makeRow(raw)
    if row then table.insert(D.rows, row) end
  end
  D.view.table:SetData(D.rows)
  D.UpdateStatus()
end

local function landed(added)
  D.asking, D.ask = nil, nil
  local house = D.Source() == "house"
  if type(added) == "table" and #added > 0 then
    for _, r in ipairs(added) do table.insert(D.houseRows, r) end
    if house then D.Append(added) end
  else
    D.houseRows = AH.GetBrowseResults() or {}
    if house then D.Refresh() end
  end
  D.More()
end

H.RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  if (D.waiting or 0) > 0 then
    D.by, D.waiting = "hound", D.waiting - 1
  else
    D.by, D.searched = "buy tab", nil
  end
  landed(nil)
end)

H.RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
  landed(added)
end)

H.RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE", function()
  D.asking, D.ask, D.waiting = nil, nil, 0
  if D.view then D.Refresh() end
end)

------------------------------------------------------------------------
-- Buying: a double-click, through Hound's confirm.
------------------------------------------------------------------------

-- The units of a commodity's listings at or under a price, less your
-- own, and what the cheapest n of them come to.
local function unitsUnder(listings, limit)
  local n = 0
  for _, l in ipairs(listings) do
    if not limit or l.p <= limit then n = n + math.max(0, l.q - (l.own or 0)) end
  end
  return n
end

local function priceOf(listings, n)
  local sorted = {}
  for i, l in ipairs(listings) do sorted[i] = l end
  table.sort(sorted, function(a, b) return a.p < b.p end)
  local total, left = 0, n
  for _, l in ipairs(sorted) do
    if left <= 0 then break end
    local take = math.min(left, math.max(0, l.q - (l.own or 0)))
    total = total + take * l.p
    left = left - take
  end
  return left <= 0 and total or nil
end

-- Offers what the listings hold. hw: called from the double-click, so
-- a commodity's price can be asked for at once.
local function offer(row, listings, commodity, hw)
  local C = UI.Confirm
  local e = row.e
  if commodity == nil then commodity = H.CommodityStatus(e.itemID) end
  if commodity == nil then commodity = (H.MaxStack(e.itemID) or 1) > 1 end
  if commodity then
    local all = unitsUnder(listings, nil)
    if all <= 0 then return C.Fail("nothing there to buy: those are your own") end
    local L = H.Ladder.Build(listings, e.key, e.itemID)
    local qty = L and L.limit and unitsUnder(listings, L.limit) or 0
    local note
    if qty <= 0 then
      local floor = L and L.floor or listings[1].p
      qty = unitsUnder(listings, floor)
      if qty <= 0 then qty = 1 end
      note = "none of these are a deal now"
    end
    local cost = function(n) return priceOf(listings, n) end
    if hw then
      local p = C.Commodity(e.itemID, qty, all, cost)
      p.note = note
      C.Text()
    else
      C.Offer({ kind = "commodity", qty = qty, max = all, priceOf = cost, estimate = cost(qty), note = note })
    end
    return true
  end
  local best
  for _, l in ipairs(listings) do
    if not l.mine and l.auctionID and (l.p or 0) > 0 and (not best or l.p < best.p) then best = l end
  end
  if not best then return C.Fail("nothing there to buy: those are your own") end
  if hw then
    C.Item(row.itemKey, best.auctionID, best.p)
  else
    C.Offer({ kind = "item", auctionID = best.auctionID, total = best.p })
  end
  return true
end

-- Buys from a row: at once when its listings are read, else after one
-- search. Returns true, or false and why not.
function D.Buy(row)
  if not H.atAH then return false, "open the auction house to buy" end
  if type(row) ~= "table" or (row.e.qty or 0) == 0 then return false, "none listed" end
  local listings, commodity = H.Depth.Listings(row.raw)
  if listings then return offer(row, listings, commodity, true) end
  local p = UI.Confirm.Reading(row.itemKey, row.e.key)
  p.row = row
  H.Depth.Urgent(row.raw)
  return true
end

H.Events:On("DEPTH_UPDATED", function(key, L)
  local p = UI.Confirm.pending
  if p and p.stage == "reading" and p.row and key == p.key then
    local listings, commodity = H.Depth.Listings(p.row.raw)
    if listings then
      offer(p.row, listings, commodity, false)
    else
      UI.Confirm.Fail(string.format("the house has no listings for %s now", H.ItemName(p.itemID)))
    end
  end
end)

------------------------------------------------------------------------
-- The view.
------------------------------------------------------------------------
local COLORS = H.Browse.COLORS

local function verdictColor(e)
  if e.deal then return COLORS.deal end
  if (e.disc or 0) > 0 then return COLORS.under end
  if e.ref then return COLORS.over end
  return COLORS.none
end

local function rgb(c) return c[1], c[2], c[3] end

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

-- Money as a box shows it: 5s, 1g20s, 0c.
local function boxMoney(copper)
  return (string.gsub(H.MoneyExact(copper or 0), " ", ""))
end

local function rowTooltip(row, frame)
  if not GameTooltip then return end
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  local k = row.itemKey
  if GameTooltip.SetItemKey then
    GameTooltip:SetItemKey(k.itemID, k.itemLevel or 0, k.itemSuffix or 0)
  else
    GameTooltip:SetItemByID(k.itemID)
  end
  UI.Browse.ReadingLines(GameTooltip, row.raw, "on the Deals view", true)
  if row.raw.fromScan then
    GameTooltip:AddLine("as the last full scan saw it", 0.6, 0.6, 0.6)
  end
  GameTooltip:AddLine(H.atAH and "double-click to buy" or "open the auction house to buy", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function buildControls(v)
  local S = H.Settings()

  -- the first row: the search, the source and Depth, and the count
  local search = UI.EditBox(v, 170)
  search:SetPoint("TOPLEFT", v, "TOPLEFT", 6, -1)
  search:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    D.Find(self:GetText())
  end)
  v.search = search
  local go = UI.Button(v, "Search", 64, 22, function() D.Find(search:GetText()) end)
  go:SetPoint("LEFT", search, "RIGHT", 4, 0)
  v.go = go

  local source = UI.CycleButton(v, 84, D.SOURCES, function(label)
    H.Settings().dealsSource = D.SOURCE_KEYS[label]
    D.Rebuild()
    D.More()
  end)
  source:SetPoint("LEFT", go, "RIGHT", 10, 0)
  tip(source, "Source",
    "House: the house's results for the last search, Hound's or the Buy tab's, all of its pages.",
    "Last scan: every item the last full scan saw, at its floor then; works with the house closed.")
  v.source = source

  local depth = UI.CheckButton(v, "Depth", function(checked)
    H.Settings().browseDepth = checked and true or false
    D.Reread()
    D.Refresh()
    H.Events:Fire("DEPTH_UPDATED")
  end)
  depth:SetPoint("LEFT", source, "RIGHT", 10, 0)
  tip(depth, "Depth",
    "Each row on screen gets one search of its own, one at a time: the units at or under the deal limit, the next price step, and a reference capped by the listings' own value.")
  v.depth = depth

  v.status = UI.Text(v, "GameFontDisableSmall", "", "RIGHT")
  v.status:SetPoint("RIGHT", v, "TOPRIGHT", -4, -11)
  v.status:SetPoint("LEFT", depth.label or depth, "RIGHT", 10, 0)

  -- the second row: the filters
  local y = -27
  local minLabel = UI.Text(v, "GameFontHighlightSmall", "min", "LEFT")
  minLabel:SetPoint("TOPLEFT", v, "TOPLEFT", 4, y - 4)
  local min = UI.EditBox(v, 34, function(text)
    local n = tonumber(text)
    if not n then return end
    n = H.Clamp(n, 0, 99) / 100
    if math.abs(n - (H.Settings().minDiscount or 0)) < 1e-9 then return end
    H.Settings().minDiscount = n
    H.Events:Fire("SETTINGS_CHANGED", "minDiscount")
  end)
  min:SetPoint("LEFT", minLabel, "RIGHT", 8, 0)
  local pct = UI.Text(v, "GameFontHighlightSmall", "%", "LEFT")
  pct:SetPoint("LEFT", min, "RIGHT", 2, 0)
  tip(min, "Minimum discount", "A deal sits at least this far under the reference, in percent.")
  v.min = min

  local saving = UI.EditBox(v, 44, function(text)
    local n = H.ParseMoney(text)
    if not n or n < 0 then return end
    if n == (H.Settings().minSaving or 0) then return end
    H.Settings().minSaving = n
    H.Events:Fire("SETTINGS_CHANGED", "minSaving")
  end)
  saving:SetPoint("LEFT", pct, "RIGHT", 8, 0)
  tip(saving, "Minimum in copper",
    "A deal also sits at least this much a unit under the reference, so a cheap item at half price is not one.",
    "Money as you would type it: 5s, 1g20s. 0 for no such floor.")
  v.saving = saving

  local maxLabel = UI.Text(v, "GameFontHighlightSmall", "max", "LEFT")
  maxLabel:SetPoint("LEFT", saving, "RIGHT", 12, 0)
  local maxBox = UI.EditBox(v, 54, function(text)
    local n = (text == nil or text == "") and 0 or H.ParseMoney(text)
    if not n or n < 0 then return end
    if n == (H.Settings().dealsMaxPrice or 0) then return end
    H.Settings().dealsMaxPrice = n
    D.Filter()
  end)
  maxBox:SetPoint("LEFT", maxLabel, "RIGHT", 8, 0)
  tip(maxBox, "Dearest floor", "Rows whose floor costs more than this a unit are left out. Empty for no cap.")
  v.max = maxBox

  -- with the house as the source, a search of Hound's own asks the
  -- house again for a new quality or class
  local function again()
    if D.Source() == "house" and D.searched and H.atAH then D.Search(D.searched.text) else D.Filter() end
  end
  local quality = UI.CycleButton(v, 92, labels(D.QUALITIES), function(label)
    H.Settings().dealsQuality = valueOf(D.QUALITIES, label)
    again()
  end)
  quality:SetPoint("LEFT", maxBox, "RIGHT", 8, 0)
  tip(quality, "Quality", "The lowest quality shown. With the house as the source, Hound's own search is sent again for it. Right-click steps back.")
  v.quality = quality

  local class = UI.CycleButton(v, 100, labels(D.CLASSES), function(label)
    H.Settings().dealsClass = valueOf(D.CLASSES, label)
    again()
  end)
  class:SetPoint("LEFT", quality, "RIGHT", 4, 0)
  tip(class, "Item class", "Only items of this class. With the house as the source, Hound's own search is sent again for it. Right-click steps back.")
  v.class = class

  local function toggle(label, setting, after, title, line)
    local c = UI.CheckButton(v, label, function(checked)
      H.Settings()[setting] = checked and true or false
      D.Filter()
    end)
    c:SetPoint("LEFT", after.label or after, "RIGHT", 8, 0)
    tip(c, title, line)
    return c
  end
  v.only = toggle("Deals only", "dealsOnly", class, "Deals only",
    "Only rows that clear the minimum: green on the Buy tab.")
  v.history = toggle("History only", "dealsHistory", v.only, "History only",
    "Only rows judged against market history, not an estimate or the vendor price.")
  v.mine = toggle("Hide mine", "dealsHideMine", v.history, "Hide mine",
    "Leave out rows with an auction of yours among them.")
end

-- The controls read the settings back, after a slash command say.
function D.UpdateControls()
  local v = D.view
  if not v then return end
  local S = H.Settings()
  local function put(box, want)
    if box:GetText() ~= want and not box:HasFocus() then box:SetText(want) end
  end
  put(v.min, tostring(H.Round((S.minDiscount or 0) * 100)))
  put(v.saving, boxMoney(S.minSaving))
  put(v.max, (S.dealsMaxPrice or 0) > 0 and boxMoney(S.dealsMaxPrice) or "")
  v.source:SetValue(D.Source() == "scan" and "Last scan" or "House")
  v.quality:SetValue(labelOf(D.QUALITIES, S.dealsQuality or 0))
  v.class:SetValue(labelOf(D.CLASSES, S.dealsClass or -1))
  v.depth:SetChecked(S.browseDepth and true or false)
  v.only:SetChecked(S.dealsOnly and true or false)
  v.history:SetChecked(S.dealsHistory and true or false)
  v.mine:SetChecked(S.dealsHideMine and true or false)
end

function D.StatusText()
  local n, deals, kept = D.Counts()
  local parts = {}
  if D.Source() == "scan" then
    local last = H.db and H.db.lastFull or 0
    if last <= 0 then return "no full scan yet: run one from the Markets view" end
    table.insert(parts, string.format("last scan %s: %d item%s, %d deal%s, %d shown",
      H.Ago(H.Now() - last), n, n == 1 and "" or "s", deals, deals == 1 and "" or "s", kept))
  else
    if not H.atAH then return "open the auction house: the results of its searches show here" end
    if (D.waiting or 0) > 0 then return "searching" end
    if n == 0 and not D.by then return "search here or on the Buy tab" end
    table.insert(parts, string.format("%d row%s, %d deal%s, %d shown",
      n, n == 1 and "" or "s", deals, deals == 1 and "" or "s", kept))
    if D.Paging() then table.insert(parts, "loading more") end
  end
  if H.Depth.Reading() then table.insert(parts, "reading depth") end
  return table.concat(parts, ", ")
end

function D.UpdateStatus()
  if D.view then D.view.status:SetText(D.StatusText()) end
end

-- The filters changed: the rows stay, the list shown follows.
function D.Filter()
  if not D.view then return end
  D.view.table:Filter(D.Passes)
  D.UpdateStatus()
end

-- The rows are read again from the source.
function D.Rebuild()
  if not D.view then return end
  D.Build()
  D.view.table:SetData(D.rows)
  D.view.table:Filter(D.Passes)
  D.UpdateStatus()
end

-- The house's rows changed, or a reading moved: rebuilt when shown,
-- else when the view next opens.
function D.Refresh()
  if D.view and D.view:IsShown() then D.Rebuild() end
end

-- The search box: the house asked, or with the last scan the names
-- matched.
function D.Find(text)
  D.text = text or ""
  if D.Source() == "scan" then
    D.Filter()
    return true
  end
  return D.Search(text)
end

function UI.BuildDealsView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  D.view = v
  buildControls(v)

  local cols = {
    { key = "item", title = "Item", width = 236, kind = "item", value = function(r) return H.ItemName(r.itemID) end,
      text = function(r) return H.ColoredName(r.itemID) end },
    { key = "min", title = "Floor", width = 80, align = "RIGHT", kind = "money", value = function(r) return r.e.min end },
    { key = "qty", title = "Units", width = 46, align = "RIGHT", kind = "int", value = function(r) return r.e.qty end, desc = true },
    { key = "ref", title = "Reference", width = 84, align = "RIGHT", value = function(r) return r.e.ref end, desc = true,
      text = function(r, raw)
        if not raw then return "-" end
        local mark = r.e.refSrc == "vendor" and "v " or ((r.e.history or r.e.capped) and "" or "~")
        return mark .. H.MoneyShort(raw)
      end },
    { key = "disc", title = "Off", width = 50, align = "RIGHT", value = function(r) return r.e.disc end, desc = true,
      text = function(r, raw) return raw and H.Pct(-raw, true) or "-" end,
      color = function(r) return rgb(verdictColor(r.e)) end },
    { key = "saving", title = "Saves", width = 74, align = "RIGHT", kind = "money", value = function(r) return r.e.saving end, desc = true },
    { key = "deal", title = "Deal units", width = 62, align = "RIGHT", kind = "int", desc = true,
      value = function(r) local L = depthOf(r) return L and L.dealUnits or nil end },
    { key = "age", title = "On offer", width = 64, align = "RIGHT", value = function(r) return r.e.age end,
      text = function(r, raw)
        if not raw then return "-" end
        if raw == 0 then return "new" end
        return H.Span(raw)
      end,
      color = function(r) if r.e.sat then return rgb(COLORS.under) end return 0.8, 0.8, 0.8 end },
  }
  local tbl = UI.CreateTable(v, cols, {
    sortKey = "disc", sortDesc = true,
    tooltip = rowTooltip,
    onDouble = function(row)
      local ok, why = D.Buy(row)
      if not ok and why then H.Print(why) end
    end,
    -- with Depth on, the rows on screen are the ones searched
    onRefresh = function(_, rows)
      if not H.atAH or not H.Settings().browseDepth or not shown() then return end
      local raws = {}
      for i, row in ipairs(rows) do raws[i] = row.raw end
      H.Depth.SetWanted(raws)
    end,
  })
  tbl:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -54)
  tbl:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)
  v.table = tbl

  v:SetScript("OnShow", function()
    if D.Source() == "house" and H.atAH and #D.houseRows == 0 and AH.GetBrowseResults then
      D.houseRows = AH.GetBrowseResults() or {}
    end
    D.UpdateControls()
    D.Rebuild()
    D.More()
    H.Depth.Tick()
  end)
  D.UpdateControls()
  D.Rebuild()
  return v
end

-- Searches go out only while the list shows; a row about to be bought
-- goes out regardless (Depth.lua).
H.Depth.SetGate(function() return shown() end)

H.Events:On("DEPTH_UPDATED", function(key)
  if not D.view then return end
  D.Reread(key)
  if D.view:IsShown() then
    D.view.table:Filter(D.Passes)
    D.UpdateStatus()
  end
end)
H.Events:On("DEPTH_STATUS", D.UpdateStatus)
H.Events:On("SETTINGS_CHANGED", function()
  if not D.view then return end
  D.Reread()
  D.UpdateControls()
  D.Refresh()
end)
H.Events:On("SCAN_DONE", function() D.Refresh() end)
-- A visit starts and ends with nothing of the house's held.
local function forget()
  D.houseRows, D.by, D.searched, D.waiting, D.asking, D.ask = {}, nil, nil, 0, nil, nil
  D.Refresh()
end
H.Events:On("AH_OPENED", forget)
H.Events:On("AH_CLOSED", forget)
