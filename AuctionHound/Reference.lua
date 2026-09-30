-- Reference.lua: the price everything is judged against.
--
-- Market history when it is deep enough, a prior (crafted cost, value
-- as an input) when it is not, and thin history as a last resort. With
-- estimates off the prior step is skipped: an item whose price has
-- settled well under its crafted cost would otherwise read as a deal
-- for as long as its history stays thin. History older than the two
-- weeks the market value spans still counts: the 30-day mean, else the
-- value at the last scan. The Buy tab, the listing ladder and the depth
-- reads all start here.
--
-- History is read as the lower of the two-week value and the value at
-- the latest scan. The two-week value follows a price that has fallen
-- and stayed down only over days, while the latest scan already has
-- the new low in its cheapest slice: from the next scan on, a floor
-- that has filled in is the price, not a discount. A stray under the
-- rest is too few units to move that slice, and still reads as a deal.
local ADDON, H = ...

local function judged(st)
  if st.recent and st.recent > 0 and st.recent < st.market then return st.recent end
  return st.market
end

-- Returns ref, source, confidence, stats. source is "market",
-- "prior:<kind>" or nil.
function H.Reference(key, itemID)
  local rec = H.Store.Get(key)
  local st = rec and H.Market.Stats(rec) or nil
  local conf = st and H.Market.Confidence(st) or 0
  if st and st.market and conf >= 0.3 then
    return judged(st), "market", conf, st
  end
  local prior, src = H.Priors.Estimate(itemID)
  if prior then
    return prior, "prior:" .. src, 0.2, st
  end
  if st and st.market then
    return judged(st), "market", conf, st
  end
  local old = st and (st.hist or st.recent)
  if old and old > 0 then
    return old, "market", 0, st
  end
  return nil, nil, 0, st
end

-- Where a reference came from, as a tooltip reads it.
function H.ReferenceSource(src, st)
  if src == "market" then
    if st and not st.market and st.age then
      return "history, last scanned " .. H.Ago(st.age)
    end
    if st and st.market and st.recent and st.recent > 0 and st.recent < st.market then
      return string.format("the last scan, under the two-week %s", H.Money(st.market))
    end
    return string.format("market, %d scans", st and st.samples or 0)
  end
  if src == "vendor" then return "vendor price" end
  return "estimate: " .. string.sub(src or "", 7)
end

-- The line shown where there is nothing to judge against.
function H.NoReferenceLine()
  if H.Settings().estimates then
    return "no reference: nothing scanned, no vendor or crafting anchor"
  end
  return "no reference: nothing scanned, no vendor price; estimates are off"
end
