-- Snipe.lua: find listings under reference, explain why they are or are
-- not a deal, and buy them.
--
-- Pass:
--   1. browse the AH, one floor price per item key
--   2. keep keys whose floor sits under reference by the minimum discount
--   3. confirm the best candidates with a targeted search
--   4. score each with reasons a person can read
local ADDON, H = ...

local Snipe = {}
H.Snipe = Snipe

local AH = C_AuctionHouse

Snipe.results = {}
Snipe.running = false
Snipe.pending = nil
Snipe.BUY_TIMEOUT = 15    -- seconds before a purchase with no reply is dropped

------------------------------------------------------------------------
-- Reference price: market history when it is deep enough, priors when
-- it is not. Returns ref, source, confidence, stats.
------------------------------------------------------------------------
function Snipe.Reference(key, itemID)
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

------------------------------------------------------------------------
-- Scoring. Returns score 0..5 and an array of reasons.
------------------------------------------------------------------------
function Snipe.Score(c, st)
  local S = H.Settings()
  local reasons = {}
  local function add(r) table.insert(reasons, r) end

  local score = 2
  local disc = 1 - c.unit / c.ref
  c.discount = disc
  c.net = c.ref * (1 - S.cut) - c.unit
  c.netTotal = c.net * c.dealQty

  local vendor = H.Priors.VendorSell(c.itemID)
  if vendor and c.unit < vendor then
    c.vendorFlip = true
    c.net = vendor - c.unit
    c.netTotal = c.net * c.dealQty
    add(string.format("under vendor price %s: guaranteed vendor flip", H.MoneyShort(vendor)))
    return 5, reasons
  end

  if c.net <= 0 then
    add("no margin after the AH cut")
    return 0, reasons
  end

  if disc >= 0.5 then
    score = score + 2
    add(string.format("%d%% under reference", H.Round(disc * 100)))
  elseif disc >= 0.35 then
    score = score + 1
    add(string.format("%d%% under reference", H.Round(disc * 100)))
  else
    add(string.format("%d%% under reference", H.Round(disc * 100)))
  end

  if string.sub(c.refSrc, 1, 5) == "prior" then
    score = score - 1
    add("no usable history, reference is " .. string.sub(c.refSrc, 7))
  elseif st then
    if st.days < 3 or st.samples < 4 then
      score = score - 1
      add(string.format("thin history: %d scans over %d days", st.samples, st.days))
    elseif st.days >= 7 and st.samples >= 10 then
      score = score + 1
      add(string.format("solid history: %d scans over %d days", st.samples, st.days))
    end
    if st.age and st.age > 2 * 86400 then
      score = score - 1
      add("reference is " .. H.Ago(st.age))
    end
    if st.trend and st.trend <= -0.2 then
      score = score - 1
      add(string.format("price falling: %s versus last week", H.Pct(st.trend, true)))
    end
    if st.hist and st.market and st.market > st.hist * 1.5 then
      score = score - 1
      add("reference is a recent spike above the 30-day average")
    end
    if st.moved then
      if st.moved >= c.dealQty then
        score = score + 1
        add(string.format("moves ~%d a day", H.Round(st.moved)))
      elseif st.moved < c.dealQty / 5 then
        score = score - 1
        add(string.format("slow market: ~%d a day, deal is %d units", H.Round(st.moved), c.dealQty))
      else
        add(string.format("moves ~%d a day", H.Round(st.moved)))
      end
    else
      add("sale rate unknown")
    end
  end

  if c.isCommodity and c.dealQty == 1 then
    score = score - 1
    add("single unit")
  end

  if c.mine then
    add("includes your own listing")
    score = 0
  end

  return H.Clamp(score, 1, 5), reasons
end

------------------------------------------------------------------------
-- The pass
------------------------------------------------------------------------
local function buildCandidates(results)
  local S = H.Settings()
  local cands = {}
  for _, r in ipairs(results or {}) do
    if r.itemKey and r.minPrice and r.minPrice > 0 then
      local key = H.KeyString(r.itemKey)
      local itemID = r.itemKey.itemID
      local ref, src, conf, st = Snipe.Reference(key, itemID)
      local vendor = H.Priors.VendorSell(itemID)
      local underVendor = vendor and r.minPrice < vendor
      if underVendor and not ref then
        ref, src, conf = vendor, "vendor", 1
      end
      if ref and (underVendor or r.minPrice <= ref * (1 - S.minDiscount)) then
        table.insert(cands, {
          key = key, itemKey = r.itemKey, itemID = itemID,
          min = r.minPrice, total = r.totalQuantity or 0,
          ref = ref, refSrc = src, conf = conf, st = st, vendor = vendor,
        })
      end
    end
  end
  table.sort(cands, function(a, b)
    return (a.ref - a.min) * math.min(a.total, 20) > (b.ref - b.min) * math.min(b.total, 20)
  end)
  return cands
end

local function confirm(c, listings, isCommodity)
  local S = H.Settings()
  local maxUnit = c.ref * (1 - S.minDiscount)
  if c.vendor and c.vendor - 1 > maxUnit then maxUnit = c.vendor - 1 end
  local dealQty, cost, cheapest, mine = 0, 0, nil, false
  table.sort(listings, function(a, b) return a.p < b.p end)
  for _, l in ipairs(listings) do
    if l.p <= maxUnit then
      dealQty = dealQty + l.q
      cost = cost + l.p * l.q
      cheapest = cheapest or l
      if l.mine then mine = true end
    else
      break
    end
  end
  if dealQty == 0 or not cheapest then return nil end
  c.isCommodity = isCommodity
  c.dealQty = dealQty
  c.unit = cheapest.p
  c.avg = cost / dealQty
  c.maxUnit = maxUnit
  c.auctionID = cheapest.auctionID
  c.mine = mine
  c.ladder = H.Market.Ladder(listings)
  c.score, c.reasons = Snipe.Score(c, c.st)
  c.name = H.ItemName(c.itemID)
  c.at = H.Now()
  return c
end

local function confirmNext()
  local q = Snipe.queue
  if not q or q.index > #q.cands or q.index > q.limit or not H.atAH then
    Snipe.running = false
    Snipe.queue = nil
    Snipe.lastRun = H.Now()
    H.Events:Fire("SNIPE_DONE")
    H.Events:Fire("SCAN_STATUS")
    if Snipe.onDone then Snipe.onDone() end
    return
  end
  local c = q.cands[q.index]
  q.index = q.index + 1
  H.Scan.Search(c.itemKey, function(listings, isCommodity)
    if listings then
      local row = confirm(c, listings, isCommodity)
      if row and row.score > 0 then
        Snipe.Upsert(row)
      end
    end
    confirmNext()
  end)
end

function Snipe.Upsert(row)
  for i, r in ipairs(Snipe.results) do
    if r.key == row.key then
      Snipe.results[i] = row
      H.Events:Fire("SNIPE_UPDATED")
      return
    end
  end
  table.insert(Snipe.results, row)
  table.sort(Snipe.results, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.netTotal > b.netTotal
  end)
  H.Events:Fire("SNIPE_UPDATED")
end

function Snipe.Remove(key)
  for i, r in ipairs(Snipe.results) do
    if r.key == key then
      table.remove(Snipe.results, i)
      H.Events:Fire("SNIPE_UPDATED")
      return
    end
  end
end

function Snipe.Clear()
  Snipe.results = {}
  H.Events:Fire("SNIPE_UPDATED")
end

function Snipe.Run(onDone)
  if Snipe.running then H.Print("snipe pass already running") return false end
  if not H.atAH then H.Print("open the auction house first") return false end
  local S = H.Settings()
  Snipe.running = true
  Snipe.onDone = onDone
  Snipe.lastBrowse = nil
  H.Events:Fire("SCAN_STATUS")
  local ok = H.Scan.Browse({ maxPages = S.snipePages }, function(results, partial)
    if not results then
      Snipe.running = false
      H.Events:Fire("SCAN_STATUS")
      return
    end
    Snipe.lastBrowse = { count = #results, partial = partial, t = H.Now() }
    local cands = buildCandidates(results)
    Snipe.lastCandidates = #cands
    Snipe.queue = { cands = cands, index = 1, limit = S.confirmTop }
    confirmNext()
  end)
  if not ok then Snipe.running = false end
  return ok
end

------------------------------------------------------------------------
-- Buying. Commodities re-quote before confirming; items buy out the
-- cheapest confirmed listing.
------------------------------------------------------------------------
local function settle(p)
  if p.timer then p.timer:Cancel() end
  if Snipe.pending == p then Snipe.pending = nil end
end

local function armBuyTimeout(p)
  p.timer = C_Timer.NewTimer(Snipe.BUY_TIMEOUT, function()
    if Snipe.pending ~= p then return end
    settle(p)
    H.Printf("no reply from the auction house for %s; check your bags before trying again", p.row.name or p.row.key)
    H.Events:Fire("SCAN_STATUS")
  end)
end

-- The confirm step normally runs from the quote event. If this client
-- insists on a hardware event for it, the purchase waits for the next
-- click on Buy instead.
local function confirmCommodity(p)
  local ok = pcall(AH.ConfirmCommoditiesPurchase, p.row.itemID, p.qty)
  if ok then
    p.needsConfirm = nil
    return true
  end
  p.needsConfirm = true
  if p.timer then p.timer:Cancel() p.timer = nil end
  H.Printf("quoted %s each; the client wants a click to confirm, press Buy again", H.Money(p.quoted))
  H.Events:Fire("SCAN_STATUS")
  return false
end

function Snipe.Buy(row, qty)
  if not H.atAH then H.Print("open the auction house first") return false end
  local p = Snipe.pending
  if p then
    if p.needsConfirm and p.row == row then
      armBuyTimeout(p)
      return confirmCommodity(p)
    end
    H.Print("a purchase is already in flight")
    return false
  end
  qty = math.max(1, math.min(qty or row.dealQty, row.dealQty))
  if row.isCommodity then
    p = { row = row, qty = qty, maxUnit = row.maxUnit, t = H.Now() }
    Snipe.pending = p
    armBuyTimeout(p)
    AH.StartCommoditiesPurchase(row.itemID, qty)
  else
    if not row.auctionID then H.Print("no auction id for that listing") return false end
    p = { row = row, qty = 1, t = H.Now() }
    Snipe.pending = p
    armBuyTimeout(p)
    AH.PlaceBid(row.auctionID, row.unit)
  end
  H.Events:Fire("SCAN_STATUS")
  return true
end

local function recordPurchase(p, unit, qty)
  H.Store.Ledger({ t = H.Now(), key = p.row.key, itemID = p.row.itemID, qty = qty, unit = unit, ref = p.row.ref, kind = "buy" })
  H.Printf("bought %d x %s at %s (reference %s)", qty, p.row.name or p.row.key, H.Money(unit), H.Money(p.row.ref))
end

H.RegisterEvent("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
  local p = Snipe.pending
  if not p or not p.row.isCommodity or p.needsConfirm then return end
  if unitPrice and unitPrice <= p.maxUnit then
    p.quoted = unitPrice
    confirmCommodity(p)
  else
    if AH.CancelCommoditiesPurchase then AH.CancelCommoditiesPurchase() end
    settle(p)
    H.Printf("price moved to %s, above the %s limit; not buying", H.Money(unitPrice or 0), H.Money(p.maxUnit))
    Snipe.Remove(p.row.key)
    H.Events:Fire("SCAN_STATUS")
  end
end)

H.RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", function()
  local p = Snipe.pending
  if not p then return end
  settle(p)
  H.Print("those units are gone")
  Snipe.Remove(p.row.key)
  H.Events:Fire("SCAN_STATUS")
end)

H.RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
  local p = Snipe.pending
  if not p then return end
  settle(p)
  recordPurchase(p, p.quoted or p.row.unit, p.qty)
  Snipe.Remove(p.row.key)
  H.Events:Fire("SCAN_STATUS")
end)

H.RegisterEvent("COMMODITY_PURCHASE_FAILED", function()
  local p = Snipe.pending
  if not p then return end
  settle(p)
  H.Print("commodity purchase failed")
  H.Events:Fire("SCAN_STATUS")
end)

H.RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
  local p = Snipe.pending
  if not p or p.row.isCommodity then return end
  if auctionID and p.row.auctionID and auctionID ~= p.row.auctionID then return end
  settle(p)
  recordPurchase(p, p.row.unit, 1)
  Snipe.Remove(p.row.key)
  H.Events:Fire("SCAN_STATUS")
end)

H.RegisterEvent("AUCTION_HOUSE_SHOW_ERROR", function()
  local p = Snipe.pending
  if p then
    settle(p)
    H.Print("the auction house refused that purchase")
    H.Events:Fire("SCAN_STATUS")
  end
end)

H.Events:On("AH_CLOSED", function()
  if Snipe.pending then settle(Snipe.pending) end
  Snipe.running = false
  Snipe.queue = nil
end)
