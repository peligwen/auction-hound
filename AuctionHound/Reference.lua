-- Reference.lua: the price everything is judged against.
--
-- Market history when it is deep enough, a prior (vendor, crafted cost,
-- value as an input) when it is not, and thin history as a last resort.
-- The Buy tab, the listing ladder and the depth reads all start here.
local ADDON, H = ...

-- Returns ref, source, confidence, stats. source is "market",
-- "prior:<kind>" or nil.
function H.Reference(key, itemID)
  local rec = H.Store.Get(key)
  local st = rec and H.Market.Stats(rec) or nil
  local conf = st and H.Market.Confidence(st) or 0
  if st and st.market and conf >= 0.3 then
    return st.market, "market", conf, st
  end
  local prior, src = H.Priors.Estimate(itemID)
  if prior then
    return prior, "prior:" .. src, 0.2, st
  end
  if st and st.market then
    return st.market, "market", conf, st
  end
  return nil, nil, 0, st
end
