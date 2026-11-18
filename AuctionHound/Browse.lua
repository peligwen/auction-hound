-- Browse.lua: Hound's reading of the Buy tab.
--
-- Blizzard's browse gives one row per item key: the floor price and the
-- units listed. This module turns a row into a reference, a discount and
-- a verdict, and the figures and lines Hound shows for it. The frame
-- work lives in UI/Browse.lua.
local ADDON, H = ...

local Browse = {}
H.Browse = Browse

-- References are cached per key, and what a crate or a writ costs to
-- fill per item; a scan, a fresh visit or a setting changes them.
local refs, fills = {}, {}

function Browse.Invalidate()
  refs, fills = {}, {}
end

H.Events:On("SCAN_DONE", Browse.Invalidate)
H.Events:On("AH_OPENED", Browse.Invalidate)
H.Events:On("SETTINGS_CHANGED", Browse.Invalidate)

local function reference(key, itemID)
  local r = refs[key]
  if not r then
    local ref, src, st = H.Reference(key)
    r = { ref = ref, src = src, st = st, vendor = H.VendorSell(itemID) }
    refs[key] = r
  end
  return r
end

------------------------------------------------------------------------
-- What a Waylaid Crate or a Craftsman's Writ pays and what filling it
-- takes: for a crate the bundle to buy (Crate.lua), for a writ the
-- item it asks for (Writ.lua). Nil for any other item.
--
--   kind        "crate" or "writ"
--   amount      the Merchant's Favor or the reputation it pays; nil
--               for a crate whose favor is not known yet
--   what        "Merchant's Favor" or "reputation"
--   fill        copper for the fill, nil when nothing is priced
--   fillItem, fillQty, fillName   what the fill is
--   listed      the units the last scan saw, when fewer than the fill
--               takes: no fill the house could sell whole is priced
------------------------------------------------------------------------
function Browse.Reward(itemID)
  local f = fills[itemID]
  if f ~= nil then return f or nil end
  f = false
  if H.Crates and H.Crates[itemID] then
    local r = H.Crate.Read(itemID)
    f = { kind = "crate", amount = r.favor, what = "Merchant's Favor" }
    local b = r.fill and r.bundles[r.fill]
    if b then
      f.fill, f.fillItem, f.fillQty, f.fillName = b.total, b.itemID, b.qty, b.name
      f.listed = b.listed
    end
  elseif H.Writs and H.Writs[itemID] then
    local r = H.Writ.Read(itemID)
    f = {
      kind = "writ", amount = r.rep, what = "reputation",
      fill = r.total, fillItem = r.item, fillQty = r.qty, fillName = r.name,
      listed = r.listed,
    }
  end
  fills[itemID] = f
  return f or nil
end

------------------------------------------------------------------------
-- One browse row, read. Returns nil for a row without an item key.
--
--   key, itemID, min, qty, mine
--   ref, refSrc   market | vendor | nil
--   history       the reference is market history
--   disc          fraction under the reference; negative above it
--   saving        copper a unit under the reference; negative above it
--   vendorFlip    the floor sits under the vendor sell price
--   deal          under the reference by the minimum, or a vendor flip,
--                 with units there to buy. The minimum is a percentage
--                 and a number of copper a unit, and both must hold: a
--                 three-copper item at half price is fifty percent off
--                 and still not worth the click.
--   small         far enough under by the percentage, or under vendor,
--                 but not by the copper: the reason it is not a deal
--   reward        a crate's or a writ's, as Browse.Reward reads it
--   cost          the row's floor and the fill: one turned in
--   perGold       what it pays for each gold of that cost
------------------------------------------------------------------------
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
    ref = r.ref, refSrc = r.src, st = r.st, vendor = r.vendor,
    history = r.src == "market",
  }
  if e.min > 0 and r.vendor and e.min < r.vendor then
    e.vendorFlip = true
    if not e.ref then e.ref, e.refSrc = r.vendor, "vendor" end
  end
  if e.ref and e.ref > 0 and e.min > 0 then
    e.disc = 1 - e.min / e.ref
    e.saving = e.ref - e.min
  end
  local far = e.vendorFlip or (e.disc ~= nil and e.disc >= (S.minDiscount or 0)) or false
  local enough = (e.saving or 0) >= (S.minSaving or 0)
  e.deal = e.qty > 0 and far and enough
  e.small = e.qty > 0 and far and not enough
  local f = Browse.Reward(itemID)
  if f then
    e.reward = f
    if f.amount and f.fill and e.qty > 0 and e.min > 0 then
      e.cost = e.min + f.fill
      e.perGold = f.amount * 10000 / e.cost
    end
  end
  return e
end

-- A rate as the cell and the tooltip give it: two decimals under one,
-- one under ten, whole numbers from there.
function Browse.Rate(x)
  if x >= 9.95 then return tostring(H.Round(x)) end
  if x >= 0.995 then return string.format("%.1f", x) end
  return string.format("%.2f", x)
end

-- What a crate or a writ comes to, for the cell's tooltip: what it
-- pays and for how much a gold, then the sum. A fill the house cannot
-- sell whole carries the "~". Nil for any other row.
function Browse.RewardLines(e)
  local f = e and e.reward
  if not f then return nil end
  if not f.amount then
    return { "the Merchant's Favor this crate pays is not known yet" }
  end
  if not f.fill then
    return { string.format("%d %s; no price for %s", f.amount, f.what,
      f.kind == "crate" and "any bundle that fills it" or "the item it asks for") }
  end
  if not e.perGold then
    return { string.format("%d %s", f.amount, f.what) }
  end
  local mark = f.listed and "~" or ""
  local name = H.Crate.GoodName(f.fillItem, f.fillName)
  if f.fillQty > 1 then name = f.fillQty .. " " .. name end
  local short = ""
  if f.listed then short = f.listed > 0 and string.format(", only %d listed", f.listed) or ", none listed" end
  return {
    string.format("%d %s, %s%s a gold", f.amount, f.what, mark, Browse.Rate(e.perGold)),
    string.format("%s %s + %s %s%s = %s%s", f.kind, H.Money(e.min), name,
      H.Money(f.fill), short, mark, H.Money(e.cost)),
  }
end

-- The floor as the tooltip reads it: the price and the units.
function Browse.FloorLine(e)
  return string.format("floor %s, %d units listed", H.Money(e.min), e.qty)
end

-- The dearest price a deal sits at, for a row read by Evaluate: the
-- minimum discount off the reference, and the minimum copper a unit
-- under it, whichever bites first; under the vendor price is a deal
-- too, copper minimum kept. Nil without a reference.
function Browse.Limit(e)
  local ref = e and e.ref
  if not ref or ref <= 0 then return nil end
  local S = H.Settings()
  local saving = S.minSaving or 0
  local limit = math.min(ref * (1 - (S.minDiscount or 0)), ref - saving)
  if e.vendor then
    local underVendor = math.min(e.vendor - 1, ref - saving)
    if underVendor > limit then limit = underVendor end
  end
  return limit
end

------------------------------------------------------------------------
-- What Hound's figures show for a row: a note on the left, a figure
-- on the right, and the figure's color.
------------------------------------------------------------------------
Browse.COLORS = {
  deal = { 0.30, 0.85, 0.30 },
  under = { 0.85, 0.80, 0.45 },
  over = { 0.70, 0.70, 0.70 },
  none = { 0.45, 0.45, 0.45 },
  reward = { 1, 1, 1 },
}

-- A crate or a writ whose turn-in can be priced shows what it pays and
-- how much a gold of the row's floor and the fill buys of it: "10
-- favor" and "4.2/g". Its discount is in the tooltip.
function Browse.CellText(e)
  if not e or e.qty == 0 then return "", "", Browse.COLORS.none end
  if e.perGold then
    local f = e.reward
    local note = string.format("%d %s", f.amount, f.kind == "crate" and "favor" or "rep")
    local mark = f.listed and "~" or ""
    return note, mark .. Browse.Rate(e.perGold) .. "/g", Browse.COLORS.reward
  end
  if not e.ref then return "no reference", "", Browse.COLORS.none end
  local note = H.MoneyShort(e.ref)
  if e.refSrc == "vendor" then note = "vendor " .. note end
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
