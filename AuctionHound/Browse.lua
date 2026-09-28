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
    r = { ref = ref, src = src, conf = conf or 0, st = st, vendor = H.Priors.VendorSell(itemID) }
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
--   disc          fraction under the reference; negative above it
--   vendorFlip    the floor sits under the vendor sell price
--   deal          under the reference by the minimum discount, or a
--                 vendor flip, with units there to buy
------------------------------------------------------------------------
function Browse.Evaluate(row)
  if type(row) ~= "table" or type(row.itemKey) ~= "table" or not row.itemKey.itemID then return nil end
  local S = H.Settings()
  local itemID = row.itemKey.itemID
  local key = H.KeyString(row.itemKey)
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
  if e.ref and e.ref > 0 and e.min > 0 then
    e.disc = 1 - e.min / e.ref
  end
  e.deal = e.qty > 0 and (e.vendorFlip or (e.disc ~= nil and e.disc >= (S.minDiscount or 0))) or false
  return e
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

function Browse.Active(S)
  S = S or H.Settings()
  return (S.browseSort or S.browseDeals or S.browseHistory or S.browseNotMine) and true or false
end
