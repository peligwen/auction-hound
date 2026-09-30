-- Market.lua: turning listings and history into numbers a flipper can use.
local ADDON, H = ...

local Market = {}
H.Market = Market

------------------------------------------------------------------------
-- Market value from one scan's listings.
--
-- Sort by unit price. Always include the cheapest 15% of units, keep
-- adding listings up to 30% of units while each step is no more than
-- 20% above the previous listing, then drop anything beyond 1.5 standard
-- deviations and take the quantity-weighted mean. A single absurd wall
-- of expensive listings never touches the value; a single 1c unit is
-- damped by the units around it.
--
-- listings: array of { p = unit price, q = quantity }
-- returns mv, min, totalQty, numListings
------------------------------------------------------------------------
function Market.ValueFromListings(listings)
  if not listings or #listings == 0 then return nil end
  table.sort(listings, function(a, b) return a.p < b.p end)
  local total = 0
  for _, l in ipairs(listings) do total = total + l.q end
  local minPrice = listings[1].p

  local target15 = total * 0.15
  local target30 = total * 0.30
  local included, units, prev = {}, 0, nil
  for _, l in ipairs(listings) do
    if units < target15 then
      table.insert(included, l)
      units = units + l.q
    elseif units < target30 and prev and l.p <= prev.p * 1.2 then
      table.insert(included, l)
      units = units + l.q
    else
      break
    end
    prev = l
  end

  local sum, wsum = 0, 0
  for _, l in ipairs(included) do
    sum = sum + l.p * l.q
    wsum = wsum + l.q
  end
  local mean = sum / wsum
  local var = 0
  for _, l in ipairs(included) do
    var = var + l.q * (l.p - mean) ^ 2
  end
  local sd = math.sqrt(var / wsum)

  local sum2, wsum2 = 0, 0
  for _, l in ipairs(included) do
    if sd == 0 or math.abs(l.p - mean) <= 1.5 * sd then
      sum2 = sum2 + l.p * l.q
      wsum2 = wsum2 + l.q
    end
  end
  local mv = wsum2 > 0 and (sum2 / wsum2) or mean
  return H.Round(mv), minPrice, total, #listings
end

------------------------------------------------------------------------
-- Price ladder: cumulative units at each price step, cheapest first.
-- Answers "how many units sit within X% of the floor".
------------------------------------------------------------------------
function Market.Ladder(listings)
  local sorted = {}
  for _, l in ipairs(listings) do table.insert(sorted, l) end
  table.sort(sorted, function(a, b) return a.p < b.p end)
  local out, cum = {}, 0
  for _, l in ipairs(sorted) do
    cum = cum + l.q
    if #out > 0 and out[#out].p == l.p then
      out[#out].cum = cum
      out[#out].q = out[#out].q + l.q
    else
      table.insert(out, { p = l.p, q = l.q, cum = cum })
    end
  end
  return out
end

function Market.UnitsWithin(ladder, pct)
  if #ladder == 0 then return 0 end
  local limit = ladder[1].p * (1 + pct)
  local units = 0
  for _, step in ipairs(ladder) do
    if step.p <= limit then units = step.cum else break end
  end
  return units
end

------------------------------------------------------------------------
-- How long a floor has been on offer, as the scans saw it: the run of
-- latest scan points whose floor is this price, within a small
-- tolerance for a copper's undercut. Returns the seconds since the
-- first point of the run and the number of points; 0 and 0 when the
-- latest scan had a different floor, so this one is new since it; nil
-- without a record or points. A floor the scans have kept seeing has
-- been passed over by every buyer in between.
------------------------------------------------------------------------
Market.FLOOR_TOL = 0.02

function Market.FloorAge(rec, floor, now)
  if not rec or not floor or floor <= 0 or #rec.pts == 0 then return nil end
  now = now or H.Now()
  local first, n = nil, 0
  for i = #rec.pts, 1, -1 do
    local p = rec.pts[i]
    if p.min and math.abs(p.min - floor) <= floor * Market.FLOOR_TOL then
      first, n = p, n + 1
    else
      break
    end
  end
  if not first then return 0, 0 end
  return math.max(0, now - first.t), n
end

------------------------------------------------------------------------
-- Stats over a stored record.
--
--   market  decay-weighted mean of daily values over the last 14 days
--   recent  value from the latest scan
--   min     floor at the latest scan
--   hist    plain mean of daily values over 30 days
--   trend   recent versus the previous week's mean, as a fraction
--   stab    coefficient of variation of daily values over 14 days
--   qty     units listed at the latest scan
--   moved   estimated units consumed per day over the last week
--   days, samples, age
------------------------------------------------------------------------
function Market.Stats(rec, now)
  now = now or H.Now()
  local today = H.DayIndex(now)
  if rec.stats and rec.stats.day == today and rec.stats.at == (rec.pts[#rec.pts] and rec.pts[#rec.pts].t) then
    return rec.stats
  end

  local st = { day = today, days = 0, samples = 0 }
  local wsum, sum = 0, 0
  local histSum, histN = 0, 0
  local vals14 = {}
  local weekSum, weekN = 0, 0

  for d = today - 29, today do
    local b = rec.days[d]
    if b then
      local age = today - d
      st.days = st.days + 1
      st.samples = st.samples + b.s
      histSum = histSum + b.mv
      histN = histN + 1
      if age <= 13 then
        local w = 0.5 ^ (age / 3.5)
        sum = sum + b.mv * w
        wsum = wsum + w
        table.insert(vals14, b.mv)
      end
      if age >= 1 and age <= 7 then
        weekSum = weekSum + b.mv
        weekN = weekN + 1
      end
    end
  end

  if wsum > 0 then st.market = H.Round(sum / wsum) end
  if histN > 0 then st.hist = H.Round(histSum / histN) end

  local last = rec.pts[#rec.pts]
  if last then
    st.recent = last.mv
    st.min = last.min
    st.qty = last.qty
    st.n = last.n
    st.age = now - last.t
    st.at = last.t
  end

  if st.recent and weekN > 0 then
    local weekMean = weekSum / weekN
    if weekMean > 0 then st.trend = st.recent / weekMean - 1 end
  end

  if #vals14 >= 3 then
    local mean = H.Mean(vals14)
    if mean and mean > 0 then st.stab = H.StdDev(vals14, mean) / mean end
  end

  local movedSum, movedDays = 0, 0
  for d = today - 7, today do
    if rec.days[d] then
      movedDays = movedDays + 1
      movedSum = movedSum + (rec.moved[d] or 0)
    end
  end
  if movedDays >= 2 then st.moved = movedSum / movedDays end

  rec.stats = st
  return st
end

-- 0..1 confidence in the market value, from history depth alone.
function Market.Confidence(st)
  if not st or not st.market then return 0 end
  local d = math.min(1, st.days / 7)
  local s = math.min(1, st.samples / 12)
  return 0.6 * d + 0.4 * s
end

------------------------------------------------------------------------
-- What buyers paid us: the outcomes of our own posts for one key over
-- the last 30 days. Returns nil when there is nothing to say.
--
--   soldUnits, soldMax, soldMin, soldMean, lastSoldAt
--   inferredUnits   sales deduced from an auction vanishing early
--   unsoldUnits, unsoldMin   units that expired, and the cheapest price
--                            that failed to sell
--   activeUnits     still listed
--   n               posts counted
------------------------------------------------------------------------
Market.CLEARING_DAYS = 30

function Market.Clearing(posts, now)
  now = now or H.Now()
  local cl = { soldUnits = 0, inferredUnits = 0, unsoldUnits = 0, n = 0 }
  local wsum = 0
  for _, p in ipairs(posts or {}) do
    local counted = p.status == "active" or p.status == "sold" or p.status == "expired"
    if counted and now - p.t <= Market.CLEARING_DAYS * 86400 then
      cl.n = cl.n + 1
      local sold = p.sold or 0
      if sold > 0 then
        cl.soldUnits = cl.soldUnits + sold
        wsum = wsum + sold * p.unit
        if p.inferred then cl.inferredUnits = cl.inferredUnits + sold end
        if not cl.soldMax or p.unit > cl.soldMax then cl.soldMax = p.unit end
        if not cl.soldMin or p.unit < cl.soldMin then cl.soldMin = p.unit end
        if p.soldAt and (not cl.lastSoldAt or p.soldAt > cl.lastSoldAt) then cl.lastSoldAt = p.soldAt end
      end
      if p.status == "expired" and sold < p.qty then
        cl.unsoldUnits = cl.unsoldUnits + (p.qty - sold)
        if not cl.unsoldMin or p.unit < cl.unsoldMin then cl.unsoldMin = p.unit end
      end
      if p.status == "active" then
        cl.activeUnits = (cl.activeUnits or 0) + (p.qty - sold)
      end
    end
  end
  if cl.n == 0 then return nil end
  if cl.soldUnits > 0 then cl.soldMean = H.Round(wsum / cl.soldUnits) end
  return cl
end

-- Daily series for graphs: chronological array of { day, mv, min, qty, s }.
function Market.DailySeries(rec, numDays, now)
  now = now or H.Now()
  local today = H.DayIndex(now)
  local out = {}
  for d = today - numDays + 1, today do
    local b = rec.days[d]
    if b then
      table.insert(out, { day = d, mv = b.mv, min = b.min, qty = b.qty, s = b.s, moved = rec.moved[d] })
    else
      table.insert(out, { day = d })
    end
  end
  return out
end
