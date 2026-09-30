-- Browse.lua: Hound's reading of the Buy tab.
--
-- Blizzard's browse gives one row per item key: the floor price and the
-- units listed. This module turns a row into a reference, a discount and
-- a verdict, and decides which rows the Buy tab shows and in what
-- order. The frame work lives in UI/Browse.lua.
local ADDON, H = ...

local Browse = {}
H.Browse = Browse

-- References are cached per key; a scan, a fresh visit or a setting
-- that moves the reference (estimates) changes them.
local refs = {}

function Browse.Invalidate()
  refs = {}
end

H.Events:On("SCAN_DONE", Browse.Invalidate)
H.Events:On("AH_OPENED", Browse.Invalidate)
H.Events:On("SETTINGS_CHANGED", Browse.Invalidate)

local function reference(key, itemID)
  local r = refs[key]
  if not r then
    local ref, src, conf, st = H.Reference(key, itemID)
    r = { ref = ref, src = src, conf = conf or 0, st = st, vendor = H.Priors.VendorSell(itemID), rec = H.Store.Get(key) }
    refs[key] = r
  end
  return r
end

------------------------------------------------------------------------
-- One browse row, read. Returns nil for a row without an item key.
--
--   key, itemID, min, qty, mine
--   ref, refSrc   market | prior:<kind> | vendor | nil
--   history       the reference is real market history
--   capped        with Depth on and the row's ladder read, its value
--                 sat under the reference and is the reference now
--   disc          fraction under the reference; negative above it
--   saving        copper a unit under the reference; negative above it
--   vendorFlip    the floor sits under the vendor sell price
--   age, scans    how long the scans have seen this floor, and over
--                 how many of them; 0 and 0 for a floor new since the
--                 last scan, nil without history
--   new           new since a scan within the last hour
--   sat           on offer for the sat setting's hours or more: passed
--                 over by every buyer since, so no longer a deal
--   deal          under the reference by the minimum and not sat, or a
--                 vendor flip, with units there to buy. The minimum is
--                 a percentage and a number of copper a unit, and both
--                 must hold: a three-copper item at half price is fifty
--                 percent off and still not worth the click.
--   small         far enough under by the percentage, or under vendor,
--                 but not by the copper: the reason it is not a deal
------------------------------------------------------------------------
Browse.NEW_WITHIN = 3600

function Browse.Evaluate(row)
  if type(row) ~= "table" or type(row.itemKey) ~= "table" or not row.itemKey.itemID then return nil end
  local S = H.Settings()
  local itemID = row.itemKey.itemID
  local key = H.KeyFromItemKey(row.itemKey)
  local r = reference(key, itemID)
  local e = {
    key = key, itemID = itemID,
    min = row.minPrice or 0, qty = row.totalQuantity or 0,
    mine = row.containsOwnerItem and true or false,
    ref = r.ref, refSrc = r.src, conf = r.conf, st = r.st, vendor = r.vendor,
    history = r.src == "market",
  }
  if e.min > 0 and r.vendor and e.min < r.vendor then
    e.vendorFlip = true
    if not e.ref then e.ref, e.refSrc = r.vendor, "vendor" end
  end
  if S.browseDepth and H.Depth then
    local L = H.Depth.Get(row)
    if L and L.capped and e.ref and L.ref < e.ref then
      e.ref, e.capped = L.ref, true
    end
  end
  if e.ref and e.ref > 0 and e.min > 0 then
    e.disc = 1 - e.min / e.ref
    e.saving = e.ref - e.min
  end
  e.age, e.scans = H.Market.FloorAge(r.rec, e.min)
  if e.age then
    local since = r.st and r.st.age
    e.new = e.age == 0 and since ~= nil and since <= Browse.NEW_WITHIN
    e.sat = (S.satHours or 0) > 0 and e.age >= S.satHours * 3600
  end
  local far = e.vendorFlip or (not e.sat and e.disc ~= nil and e.disc >= (S.minDiscount or 0)) or false
  local enough = (e.saving or 0) >= (S.minSaving or 0)
  e.deal = e.qty > 0 and far and enough
  e.small = e.qty > 0 and far and not enough
  return e
end

-- The floor as the tooltip reads it: the price, the units, and how
-- long the scans have seen it on offer.
function Browse.FloorLine(e)
  local line = string.format("floor %s, %d units listed", H.Money(e.min), e.qty)
  if e.sat then
    line = line .. string.format(", on offer %s over %d scan%s: not a deal", H.Span(e.age), e.scans, e.scans == 1 and "" or "s")
  elseif e.age and e.age > 0 then
    line = line .. string.format(", on offer %s over %d scan%s", H.Span(e.age), e.scans, e.scans == 1 and "" or "s")
  elseif e.new then
    line = line .. ", new since the scan " .. H.Ago(e.st.age)
  end
  return line
end

------------------------------------------------------------------------
-- What the Hound column shows for a row: a note on the left, a figure
-- on the right, and the figure's color. With the row's ladder known,
-- the note ends in the units at the floor.
------------------------------------------------------------------------
Browse.COLORS = {
  deal = { 0.30, 0.85, 0.30 },
  under = { 0.85, 0.80, 0.45 },
  over = { 0.70, 0.70, 0.70 },
  none = { 0.45, 0.45, 0.45 },
}

function Browse.CellText(e, L)
  if not e or e.qty == 0 then return "", "", Browse.COLORS.none end
  if not e.ref then return "no reference", "", Browse.COLORS.none end
  local note = H.MoneyShort(e.ref)
  if e.refSrc == "vendor" then
    note = "vendor " .. note
  elseif not e.history then
    note = "~" .. note
  end
  if type(L) == "table" and L.floorUnits then
    note = note .. " x" .. L.floorUnits
  end
  local color
  if e.deal then
    color = Browse.COLORS.deal
  elseif (e.disc or 0) > 0 then
    color = Browse.COLORS.under
  else
    color = Browse.COLORS.over
  end
  return note, H.Pct(-(e.disc or 0), true), color
end

------------------------------------------------------------------------
-- Which rows to show, in what order. getRow(i) returns Blizzard's row i
-- of n. opts: sort, deals, history, notMine. Returns an array of row
-- indices; with nothing on, it is the identity.
--
-- Sorted: deals first, then by discount, with rows that have no
-- reference or no units at the end. Ties keep Blizzard's order.
------------------------------------------------------------------------
local function rank(e)
  if not e or e.qty == 0 then return -3, -math.huge end
  if e.deal then return 1, e.disc or 0 end
  if e.disc then return 0, e.disc end
  return -1, -math.huge
end

function Browse.BuildIndex(n, getRow, opts)
  opts = opts or {}
  local idx, evals = {}, {}
  for i = 1, n do
    local e = Browse.Evaluate(getRow(i))
    local keep = true
    if opts.deals and not (e and e.deal) then keep = false end
    if opts.history and not (e and e.history) then keep = false end
    if opts.notMine and e and e.mine then keep = false end
    if keep then
      idx[#idx + 1] = i
      evals[i] = e
    end
  end
  if opts.sort then
    table.sort(idx, function(a, b)
      local ta, da = rank(evals[a])
      local tb, db = rank(evals[b])
      if ta ~= tb then return ta > tb end
      if da ~= db then return da > db end
      return a < b
    end)
  end
  return idx
end

------------------------------------------------------------------------
-- What the Buy tab makes of the first n rows the house gave, for
-- checking in game that a row meets the history the scan stored.
------------------------------------------------------------------------
function Browse.Debug(n)
  local AH = C_AuctionHouse
  local rows = AH and AH.GetBrowseResults and AH.GetBrowseResults() or {}
  H.Printf("buy tab rows from the house: %d", #rows)
  for i = 1, math.min(n, #rows) do
    local row = rows[i]
    local k = type(row) == "table" and row.itemKey
    if type(k) == "table" and k.itemID then
      local e = Browse.Evaluate(row)
      H.Printf("[%d] %s id=%s level=%s suffix=%s key=%s stored=%s ref=%s (%s)",
        i, H.ItemName(k.itemID), tostring(k.itemID), tostring(k.itemLevel), tostring(k.itemSuffix),
        e.key, tostring(H.Store.Has(e.key)), e.ref and H.Money(e.ref) or "none", tostring(e.refSrc))
    end
  end
end

function Browse.Active(S)
  S = S or H.Settings()
  return (S.browseSort or S.browseDeals or S.browseHistory or S.browseNotMine) and true or false
end
