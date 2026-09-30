-- Ladder.lua: one item's listings read against the reference.
--
-- When a Buy tab row is clicked, Blizzard shows every listing for that
-- item sorted by price. This module turns those listings into a
-- verdict per price and a few lines a buyer can act on: where the deal
-- ends, where the price steps up, and whether the floor is a stray far
-- under the rest. The frame work lives in UI/Ladder.lua.
local ADDON, H = ...

local Ladder = {}
H.Ladder = Ladder

Ladder.GAP = 0.25          -- a floor this far under the next step is low in the list
Ladder.COLORS = {
  low = { 0.45, 0.85, 1.00 },
}

------------------------------------------------------------------------
-- Build from listings { { p = unit price, q = units, mine = bool } },
-- any order. key and itemID pick the reference. Returns nil without
-- listings.
--
--   steps           merged price steps, cheapest first: p, q, cum
--   units, floor, floorUnits, next, nextPct, lowFloor, mineUnits
--   age, scans, sat how long the scans have seen this floor, as the
--                   Buy tab reads it; sat demotes every deal to under
--   mv              value from these listings alone
--   within10        units within ten percent of the floor
--   ref, refSrc, conf, st, vendor
--   limit           the price a deal must sit at or under: the minimum
--                   discount off the reference, and the minimum copper
--                   a unit under it, whichever bites first; a floor
--                   under vendor is a deal too, copper minimum kept
--   dealUnits, dealCost
--   disc            the floor's discount off the reference
------------------------------------------------------------------------
function Ladder.Build(listings, key, itemID)
  if type(listings) ~= "table" or #listings == 0 then return nil end
  local S = H.Settings()
  local L = { key = key, itemID = itemID }
  L.steps = H.Market.Ladder(listings)
  L.units = L.steps[#L.steps].cum
  L.floor = L.steps[1].p
  L.floorUnits = L.steps[1].q
  local copy = {}
  for i, l in ipairs(listings) do copy[i] = { p = l.p, q = l.q } end
  L.mv = H.Market.ValueFromListings(copy)
  L.within10 = H.Market.UnitsWithin(L.steps, 0.10)
  L.mineUnits = 0
  for _, l in ipairs(listings) do
    if l.mine then L.mineUnits = L.mineUnits + l.q end
  end

  local ref, src, conf, st = H.Reference(key, itemID)
  local vendor = H.Priors.VendorSell(itemID)
  L.age, L.scans = H.Market.FloorAge(H.Store.Get(key), L.floor)
  L.sat = L.age ~= nil and (S.satHours or 0) > 0 and L.age >= S.satHours * 3600 or false
  if not ref and vendor and L.floor < vendor then
    ref, src, conf = vendor, "vendor", 1
  end
  L.ref, L.refSrc, L.conf, L.st, L.vendor = ref, src, conf or 0, st, vendor
  if ref and ref > 0 then
    local saving = S.minSaving or 0
    L.limit = math.min(ref * (1 - (S.minDiscount or 0)), ref - saving)
    if vendor then
      local underVendor = math.min(vendor - 1, ref - saving)
      if underVendor > L.limit then L.limit = underVendor end
    end
    L.dealUnits, L.dealCost = 0, 0
    for _, s in ipairs(L.steps) do
      if s.p <= L.limit then
        L.dealUnits = s.cum
        L.dealCost = L.dealCost + s.p * s.q
      else
        break
      end
    end
    L.disc = 1 - L.floor / ref
  end

  local nxt = L.steps[2]
  if nxt then
    L.next = nxt.p
    L.nextPct = nxt.p / L.floor - 1
    L.lowFloor = L.nextPct >= Ladder.GAP
  end
  return L
end

------------------------------------------------------------------------
-- One listing at unit price p: "deal", "under", "over" or "none", and
-- whether it is the flagged floor.
------------------------------------------------------------------------
function Ladder.Verdict(L, p)
  if not L or not p then return "none", false end
  local low = L.lowFloor and p == L.floor or false
  if not L.ref then return "none", low end
  if L.limit and p <= L.limit then
    if L.vendor and p < L.vendor then return "deal", low end
    return L.sat and "under" or "deal", low
  end
  if p < L.ref then return "under", low end
  return "over", low
end

-- The color for a verdict, or nil where Blizzard's own color should
-- stay (at or over the reference, or no reference at all).
function Ladder.Color(verdict, low)
  if low then return Ladder.COLORS.low end
  if verdict == "deal" then return H.Browse.COLORS.deal end
  if verdict == "under" then return H.Browse.COLORS.under end
  return nil
end

-- Discount text for one listing: "-37%", "+12%", or "" without a
-- reference.
function Ladder.Off(L, p)
  if not L or not L.ref or not p or L.ref <= 0 then return "" end
  return H.Pct(-(1 - p / L.ref), true)
end

------------------------------------------------------------------------
-- Four lines for the info block.
------------------------------------------------------------------------
local function relative(disc)
  local pct = H.Round(math.abs(disc) * 100)
  if disc > 0 then return string.format("%d%% under reference", pct) end
  if disc < 0 then return string.format("%d%% over reference", pct) end
  return "at reference"
end

function Ladder.Lines(L)
  if not L then return { "no listings loaded" } end
  local lines = {}
  if L.ref then
    lines[1] = string.format("reference %s  (%s)", H.Money(L.ref), H.ReferenceSource(L.refSrc, L.st))
  else
    lines[1] = H.NoReferenceLine()
  end

  if L.limit then
    if L.dealUnits > 0 and L.sat and not (L.vendor and L.floor < L.vendor) then
      lines[2] = string.format("%d units at or under %s, on offer %s: not a deal", L.dealUnits, H.Money(L.limit), H.Span(L.age))
    elseif L.dealUnits > 0 then
      lines[2] = string.format("%d units at or under %s, %s all in", L.dealUnits, H.Money(L.limit), H.Money(L.dealCost))
    elseif L.limit < 1 and (H.Settings().minSaving or 0) > 0 then
      lines[2] = string.format("no price here clears the %s a unit minimum; the floor is %s",
        H.Money(H.Settings().minSaving), relative(L.disc))
    else
      lines[2] = string.format("nothing at or under %s; the floor is %s", H.Money(L.limit), relative(L.disc))
    end
  else
    lines[2] = string.format("%d units listed, floor %s", L.units, H.Money(L.floor))
  end

  if L.next then
    lines[3] = string.format("floor %s x%d, next step %s (+%d%%)", H.Money(L.floor), L.floorUnits, H.Money(L.next), H.Round(L.nextPct * 100))
    if L.lowFloor then lines[3] = lines[3] .. "  |cff73d9fflow in the list|r" end
  else
    lines[3] = string.format("one price: %s x%d", H.Money(L.floor), L.floorUnits)
  end

  local parts = { string.format("value from these listings %s", H.Money(L.mv or L.floor)) }
  if L.within10 > L.floorUnits then
    table.insert(parts, string.format("%d units within 10%% of the floor", L.within10))
  end
  if L.mineUnits > 0 then
    table.insert(parts, string.format("%d yours", L.mineUnits))
  end
  lines[4] = table.concat(parts, ", ")
  return lines
end
