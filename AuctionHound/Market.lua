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
-- Stats over a stored record.
--
--   market  decay-weighted mean of daily values over the last 14 days
--   recent  value from the latest scan
--   min     floor at the latest scan
--   floor   the latest floor seen: the latest scan's, or one the house
--           has shown since on the Buy tab or a search (Store.NoteFloor)
--   floorAt, floorAge   when that floor was seen, and how long ago
--   trend   recent versus the previous week's mean, as a fraction
--   qty     units listed at the latest scan
--   listed  decay-weighted mean of the units listed, over 14 days
--   cleared units seen to go to buyers between scans, per day over
--           the last week, when any were
--   clearing the mean price they went for over the last three days
--   days, samples, age
--
-- The figures are kept on the record until a scan, a floor noted or
-- the day moves them; the ages are worked out afresh at every call, so
-- a figure kept from the morning does not read as new at night.
------------------------------------------------------------------------
local function ages(st, now)
  st.age = st.at and (now - st.at) or nil
  st.floorAge = st.floorAt and (now - st.floorAt) or nil
  return st
end

function Market.Stats(rec, now)
  now = now or H.Now()
  local today = H.DayIndex(now)
  if rec.stats and rec.stats.day == today and rec.stats.at == (rec.pts[#rec.pts] and rec.pts[#rec.pts].t) then
    return ages(rec.stats, now)
  end

  local st = { day = today, days = 0, samples = 0 }
  local wsum, sum = 0, 0
  local weekSum, weekN = 0, 0
  local listedSum = 0

  for d = today - 29, today do
    local b = rec.days[d]
    if b then
      local age = today - d
      st.days = st.days + 1
      st.samples = st.samples + b.s
      if age <= 13 then
        local w = 0.5 ^ (age / 3.5)
        sum = sum + b.mv * w
        wsum = wsum + w
        listedSum = listedSum + (b.qty or 0) * w
      end
      if age >= 1 and age <= 7 then
        weekSum = weekSum + b.mv
        weekN = weekN + 1
      end
    end
  end

  if wsum > 0 then
    st.market = H.Round(sum / wsum)
    st.listed = listedSum / wsum
  end

  local last = rec.pts[#rec.pts]
  if last then
    st.recent = last.mv
    st.min = last.min
    st.qty = last.qty
    st.n = last.n
    st.at = last.t
  end
  st.floor, st.floorAt = st.min, st.at
  local seen = rec.seen
  if seen and (seen.min or 0) > 0 and (not st.at or seen.t > st.at) then
    st.floor, st.floorAt = seen.min, seen.t
  end

  if st.recent and weekN > 0 then
    local weekMean = weekSum / weekN
    if weekMean > 0 then st.trend = st.recent / weekMean - 1 end
  end

  local fillDays, fillUnits, fillUnits3, fillValue3 = 0, 0, 0, 0
  for d = today - 6, today do
    if rec.days[d] then
      fillDays = fillDays + 1
      local f = rec.fills and rec.fills[d]
      if f then
        fillUnits = fillUnits + f.u
        if today - d <= 2 then
          fillUnits3 = fillUnits3 + f.u
          fillValue3 = fillValue3 + f.v
        end
      end
    end
  end
  if fillDays > 0 and fillUnits > 0 then st.cleared = fillUnits / fillDays end
  if fillUnits3 > 0 then st.clearing = H.Round(fillValue3 / fillUnits3) end

  rec.stats = st
  return ages(st, now)
end

-- What has been seen to sell, as a tooltip reads it, or nil.
function Market.ClearedLine(st)
  if not st or not st.cleared then return nil end
  local line = string.format("cleared ~%d a day", H.Round(st.cleared))
  if st.clearing then line = line .. " at ~" .. H.Money(st.clearing) end
  return line
end

-- Whether this many units on offer is scarce for the item: under a
-- quarter of the units usually listed. With supply that thin, the low
-- asks are the deals, not the price.
Market.SCARCE = 0.25

function Market.Scarce(st, units)
  if not st or not st.listed or st.listed <= 0 or not units then return false end
  return units < Market.SCARCE * st.listed
end

------------------------------------------------------------------------
-- What buyers paid us: the outcomes of our own posts for one key over
-- the last 30 days. Returns nil when there is nothing to say.
--
--   soldUnits, soldMax, soldMin, soldMean, lastSoldAt   from sale mail
--   unsoldUnits, unsoldMin   units that expired, and the cheapest price
--                            that failed to sell
--   activeUnits     still listed
--   n               posts counted
------------------------------------------------------------------------
Market.CLEARING_DAYS = 30

function Market.Clearing(posts, now)
  now = now or H.Now()
  local cl = { soldUnits = 0, unsoldUnits = 0, n = 0 }
  local wsum = 0
  for _, p in ipairs(posts or {}) do
    local counted = p.status == "active" or p.status == "sold" or p.status == "expired" or p.status == "ended"
    if counted and now - p.t <= Market.CLEARING_DAYS * 86400 then
      cl.n = cl.n + 1
      local sold = p.sold or 0
      if sold > 0 then
        cl.soldUnits = cl.soldUnits + sold
        wsum = wsum + sold * p.unit
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
      local f = rec.fills and rec.fills[d]
      table.insert(out, { day = d, mv = b.mv, min = b.min, qty = b.qty, s = b.s, cleared = f and f.u or nil })
    else
      table.insert(out, { day = d })
    end
  end
  return out
end
