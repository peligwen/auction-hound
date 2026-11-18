-- Reference.lua: the price everything is judged against.
--
-- Market history: the two-week value, or the value at the latest scan
-- when that is lower. The two-week value follows a price that has
-- fallen and stayed down only over days, while the latest scan already
-- has the new low in its cheapest slice: from the next scan on, a
-- floor that has filled in is the price, not a discount. A stray under
-- the rest is too few units to move that slice, and still reads as a
-- deal. Nor does the latest scan count while supply is scarce, under a
-- quarter of the units usually listed: the few cheap units left are
-- then the deals, not the price. History older than the two weeks the
-- market value spans still counts, as the value at the last scan. The
-- vendor price stands in for an item with no history where the floor
-- sits under it (Browse.lua). The Buy tab and the Deals view start here.
local ADDON, H = ...

local function judged(st)
  if st.recent and st.recent > 0 and st.recent < st.market and not H.Market.Scarce(st, st.qty) then
    return st.recent
  end
  return st.market
end

-- Returns ref, source, stats. source is "market" or nil.
function H.Reference(key)
  local rec = H.Store.Get(key)
  local st = rec and H.Market.Stats(rec) or nil
  if st and st.market then return judged(st), "market", st end
  if st and st.recent and st.recent > 0 then return st.recent, "market", st end
  return nil, nil, st
end

-- Where a reference came from, as a tooltip reads it.
function H.ReferenceSource(src, st)
  if src == "market" then
    if st and not st.market and st.age then
      return "history, last scanned " .. H.Ago(st.age)
    end
    if st and st.market and st.recent and st.recent > 0 and st.recent < st.market
        and not H.Market.Scarce(st, st.qty) then
      return string.format("the last scan, under the two-week %s", H.Money(st.market))
    end
    return string.format("market, %d scans", st and st.samples or 0)
  end
  if src == "vendor" then return "vendor price" end
  return "no reference"
end

-- The line shown where there is nothing to judge against.
function H.NoReferenceLine()
  return "no reference: nothing scanned, no vendor price"
end
