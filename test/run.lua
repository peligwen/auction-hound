-- test/run.lua: headless checks for the parts that do not need a client.
--   lua5.1 test/run.lua [-v]
package.path = "./test/?.lua;" .. package.path
local Stub = require("wowstub")
Stub.echo = arg[1] == "-v"

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    print(string.format("FAIL: %s (got %s, want %s)", msg, tostring(a), tostring(b)))
  else
    passed = passed + 1
  end
end
local function near(a, b, tol, msg)
  if not a or math.abs(a - b) > tol then
    failed = failed + 1
    print(string.format("FAIL: %s (got %s, want ~%s)", msg, tostring(a), tostring(b)))
  else
    passed = passed + 1
  end
end

------------------------------------------------------------------------
-- Items used by the tests
------------------------------------------------------------------------
Stub.DefineItem(2770, "Copper Ore", { sell = 5, commodity = true })
Stub.DefineItem(2840, "Copper Bar", { sell = 10, commodity = true })
Stub.DefineItem(2771, "Tin Ore", { sell = 12, commodity = true })
Stub.DefineItem(3576, "Tin Bar", { sell = 20, commodity = true })
Stub.DefineItem(2841, "Bronze Bar", { sell = 30, commodity = true })
Stub.DefineItem(2934, "Ruined Leather Scraps", { sell = 2, commodity = true })
Stub.DefineItem(2318, "Light Leather", { sell = 15, commodity = true })
Stub.DefineItem(4340, "Salt", { sell = 125, commodity = true })
Stub.DefineItem(783, "Light Hide", { sell = 20, commodity = true })
Stub.DefineItem(4231, "Cured Light Hide", { sell = 40, commodity = true })
Stub.DefineItem(6096, "Apprentice's Shirt", { sell = 1, equip = "INVTYPE_BODY", commodity = false, stack = 1, ilvl = 1 })
Stub.DefineItem(15001, "Wolf Bracers", { sell = 500, equip = "INVTYPE_WRIST", commodity = false, stack = 1, ilvl = 20 })
Stub.DefineItem(9999, "Slow To Load", { sell = 1, commodity = true, loaded = false })
Stub.DefineItem(7777, "Junk Gizmo", { sell = 5000, commodity = true })

local H = Stub.LoadAddon("AuctionHound")
Stub.FireEvent("ADDON_LOADED", "AuctionHound")
Stub.FireEvent("PLAYER_LOGIN")

------------------------------------------------------------------------
-- Util
------------------------------------------------------------------------
eq(H.marketKey, "US-ClassicBetaPvP2-Horde", "market key")
eq(H.PlainMoney(123456), "12g 34s 56c", "plain money")
eq(H.MoneyShort(123456), "12.3g", "short money gold")
eq(H.MoneyShort(4599), "45s", "short money silver")
eq(H.KeyString({ itemID = 2770 }), "2770", "commodity key")
eq(H.KeyString({ itemID = 15001, itemLevel = 20, itemSuffix = -14 }), "15001:20:-14", "item key with suffix")
eq(H.KeyFromLink("|cffffffff|Hitem:15001:0:0:0:0:0:-14:0:60:0:0:0:0|h[Wolf Bracers of the Monkey]|h|r"), "15001:20:-14", "key from link")
eq(H.KeyFromLink("|cffffffff|Hitem:2770:0:0:0:0:0:0:0:60:0:0:0:0|h[Copper Ore]|h|r"), "2770", "commodity key from link")
eq(H.KeyForItemID(2770), "2770", "key for commodity id")
eq(H.KeyForItemID(15001), nil, "equippable needs a link")
eq(H.ItemIDFromKey("15001:20:-14"), 15001, "item id from key")
eq(H.CommodityStatus(2770), true, "commodity status from item key info")
eq(H.CommodityStatus(15001), false, "item status from item key info")
eq(H.CommodityStatus(9999), nil, "commodity status unknown until the item is cached")
eq(H.CommodityStatus(nil), nil, "commodity status of nothing")
check(not pcall(C_AuctionHouse.GetItemCommodityStatus, C_AuctionHouse.MakeItemKey(2770)),
  "stub rejects an item key for GetItemCommodityStatus, as the client does")
Stub.SetBag(4, 1, 2770, 3)
eq(H.CommodityStatusAt(ItemLocation:CreateFromBagAndSlot(4, 1)), true, "commodity status by bag location")
Stub.SetBag(4, 1, 15001, 1)
eq(H.CommodityStatusAt(ItemLocation:CreateFromBagAndSlot(4, 1)), false, "item status by bag location")
Stub.SetBag(4, 1, nil)
eq(H.CommodityStatusAt(ItemLocation:CreateFromBagAndSlot(4, 1)), nil, "empty slot has no status")
eq(H.MaxStack(2770), 20, "max stack from item info")
eq(H.MaxStack(9999), nil, "max stack unknown until cached")
eq(H.DayLabel(H.DayIndex(Stub.now)), os.date("%m/%d", H.DayIndex(Stub.now) * 86400 + 43200), "day label")

------------------------------------------------------------------------
-- Market value
------------------------------------------------------------------------
local M = H.Market
do
  -- flat ladder: 100 units at 10c
  local mv, min, total, n = M.ValueFromListings({ { p = 10, q = 50 }, { p = 10, q = 50 } })
  eq(mv, 10, "flat ladder mv")
  eq(min, 10, "flat ladder min")
  eq(total, 100, "flat ladder total")

  -- one 1c unit among 200 at 100c: min is 1, mv stays near 100
  local mv2, min2 = M.ValueFromListings({ { p = 1, q = 1 }, { p = 100, q = 200 } })
  eq(min2, 1, "trap unit is the floor")
  check(mv2 >= 95, "trap unit does not drag market value: " .. tostring(mv2))

  -- expensive wall never touches the value
  local mv3 = M.ValueFromListings({ { p = 100, q = 60 }, { p = 110, q = 40 }, { p = 5000, q = 500 } })
  check(mv3 <= 110, "expensive wall ignored: " .. tostring(mv3))

  -- rising ladder: include 15%, extend to 30% while steps are gentle
  local list = {}
  for i = 1, 20 do table.insert(list, { p = 100 + i * 5, q = 5 }) end
  local mv4 = M.ValueFromListings(list)
  check(mv4 >= 105 and mv4 <= 125, "gentle ladder value in the cheap slice: " .. tostring(mv4))

  local ladder = M.Ladder({ { p = 10, q = 5 }, { p = 10, q = 5 }, { p = 11, q = 10 }, { p = 50, q = 100 } })
  eq(#ladder, 3, "ladder merges equal prices")
  eq(ladder[1].q, 10, "ladder merged quantity")
  eq(M.UnitsWithin(ladder, 0.1), 20, "units within 10% of floor")
end

------------------------------------------------------------------------
-- Store: encode, aggregate, retention
------------------------------------------------------------------------
local Store = H.Store
do
  local day0 = Stub.now - 20 * 86400
  for d = 0, 19 do
    for s = 0, 2 do
      local t = day0 + d * 86400 + s * 3600 * 4
      Store.AddScanSample("2770", t, { { p = 100 + d * 2, q = 300 - s * 40 }, { p = 130 + d * 2, q = 100 } })
    end
  end
  local rec = Store.Get("2770")
  local ndays = 0
  for _ in pairs(rec.days) do ndays = ndays + 1 end
  eq(ndays, 20, "twenty daily buckets")
  eq(#rec.pts, 60, "sixty scan points kept")
  local lastDay = H.DayIndex(day0 + 19 * 86400)
  eq(rec.days[lastDay].s, 3, "three samples on the last day")
  eq(rec.moved[lastDay], 80, "moved proxy counts vanished units")

  local encoded = Store.Encode(rec)
  local back = Store.Decode(encoded)
  eq(#back.pts, 60, "roundtrip points")
  eq(back.days[lastDay].mv, rec.days[lastDay].mv, "roundtrip mv")
  eq(back.moved[lastDay], 80, "roundtrip moved")
  check(not string.find(encoded, "|", 1, true), "encoding has no pipe characters")

  eq(Store.Flush(), 1, "flush writes one dirty record")
  check(type(AuctionHoundDB.markets[H.marketKey].items["2770"]) == "string", "saved as a string")
  Store._ResetCache()
  local rec2 = Store.Get("2770")
  eq(#rec2.pts, 60, "reload from saved string")

  -- retention: 100 days ago vanishes after a new sample
  rec2.days[H.DayIndex(Stub.now) - 100] = { mv = 1, min = 1, qty = 1, n = 1, s = 1 }
  Store.AddScanSample("2770", Stub.now, { { p = 140, q = 200 } })
  eq(rec2.days[H.DayIndex(Stub.now) - 100], nil, "old day dropped")

  local st = M.Stats(rec2, Stub.now)
  check(st.market and st.market > 100, "stats market: " .. tostring(st.market))
  eq(st.days, 21, "stats days counted")
  check(st.hist and st.hist < st.market, "30 day mean below recent in a rising market")
  check(st.trend and st.trend > 0, "rising trend: " .. tostring(st.trend))
  check(st.stab and st.stab < 0.2, "stability: " .. tostring(st.stab))
  check(st.moved and st.moved > 0, "moved per day: " .. tostring(st.moved))
  near(M.Confidence(st), 1, 0.01, "full confidence with deep history")
  local series = M.DailySeries(rec2, 30, Stub.now)
  eq(#series, 30, "thirty day series")
  eq(series[30].day, H.DayIndex(Stub.now), "series ends today")
  check(series[1].mv == nil, "series has gaps before history began")
end

------------------------------------------------------------------------
-- Priors and conversions
------------------------------------------------------------------------
local P = H.Priors
do
  Store.AddScanSample("2840", Stub.now, { { p = 300, q = 100 } })      -- copper bar 3s
  Store.AddScanSample("2771", Stub.now, { { p = 250, q = 100 } })      -- tin ore
  Store.AddScanSample("2841", Stub.now, { { p = 400, q = 100 } })      -- bronze bar 4s
  Store.AddScanSample("2318", Stub.now, { { p = 90, q = 100 } })       -- light leather
  local cost, recipe = P.CraftCost(2840)
  eq(cost, (P.MarketValue(2770)), "copper bar craft cost equals ore market value")
  eq(recipe.name, "Smelt Copper", "copper bar recipe")
  local tinCost = P.CraftCost(3576)
  eq(tinCost, 250, "tin bar from tin ore market")
  local bronzeCost = P.CraftCost(2841)
  eq(bronzeCost, 275, "bronze bar cost is half of copper plus tin bars")
  local makes, r = P.MakesValue(2770)
  -- copper ore as input to copper bar at 300 less 5% cut = 285
  eq(makes, 285, "copper ore value as smelting input")
  local scrapValue = P.MakesValue(2934)
  eq(scrapValue, 29, "scrap value is a third of light leather after cut")
  local est, src = P.Estimate(2934)
  eq(est, 29, "estimate for scraps falls back to conversion value")
  eq(src, "value as an input", "estimate source label")
  local floor, fsrc = P.Floor(7777)
  eq(floor, 5000, "vendor floor")
  eq(fsrc, "vendor", "vendor floor source")
  local conn = P.Connections(2840)
  eq(#conn.madeFrom, 1, "copper bar made from one recipe")
  eq(#conn.makes, 1, "copper bar feeds bronze")
  check(conn.makes[1].spread ~= nil, "bronze spread computed")
  check(conn.makes[1].perHour ~= nil, "bronze gold per hour computed")
  -- salt is vendor priced
  local hidePrice, hsrc = P.InputPrice(4340)
  eq(hidePrice, 500, "salt priced from vendor table")
  eq(hsrc, "vendor", "salt source")
end

------------------------------------------------------------------------
-- Full scan through the replicate API
------------------------------------------------------------------------
do
  Stub.FireEvent("AUCTION_HOUSE_SHOW")
  eq(H.atAH, true, "at the auction house")
  Stub.ah.replicate = {
    { itemID = 2770, count = 20, buyout = 2000 },    -- 100c per unit
    { itemID = 2770, count = 5, buyout = 600 },      -- 120c
    { itemID = 2770, count = 1, buyout = 0, minBid = 50 }, -- bid only, skipped
    { itemID = 15001, count = 1, buyout = 50000, suffix = -14 },
    { itemID = 15001, count = 1, buyout = 70000, suffix = -14 },
    { itemID = 15001, count = 1, buyout = 20000, suffix = -15 },
    { itemID = 9999, count = 10, buyout = 1000 },    -- not loaded until requested
  }
  for i = 1, 3000 do
    table.insert(Stub.ah.replicate, { itemID = 2771, count = 10, buyout = 2500 })
  end
  AuctionHoundDB.lastFull = 0
  Store.Wipe()
  eq(H.Scan.StartFull(), true, "full scan starts")
  eq(Stub.ah.replicateCalls, 1, "replicate requested")
  Stub.Advance(1)          -- event fires
  eq(H.Scan.state, "processing", "processing after replicate event")
  Stub.Pump()              -- batches
  Stub.Advance(1)          -- retry for the unloaded item
  Stub.Pump()
  eq(H.Scan.state, "idle", "scan finished")
  local rec = Store.Get("2770")
  check(rec ~= nil, "copper ore stored")
  eq(rec.pts[1].min, 100, "copper unit price from stack buyout")
  eq(rec.pts[1].qty, 25, "copper units counted")
  check(Store.Get("15001:20:-14") ~= nil, "suffix variant stored separately")
  check(Store.Get("15001:20:-15") ~= nil, "other suffix stored separately")
  eq(Store.Get("15001:20:-14").pts[1].min, 50000, "item floor by variant")
  check(Store.Get("9999") ~= nil, "late-loading item resolved on retry")
  check((Stub.loadRequests or 0) >= 1, "late-loading item was requested from the server")
  eq(Store.Get("2771").pts[1].qty, 30000, "three thousand rows aggregated")
  local last = Store.LastScan()
  eq(last.kind, "full", "scan logged")
  Stub.Pump()
  check(type(AuctionHoundDB.markets[H.marketKey].items["2770"]) == "string", "async flush wrote the record")
  eq(Store.Flush(), 0, "nothing left for the sync flush")
  eq(last.skipped, 0, "nothing unresolved")
  local ok, why = H.Scan.FullScanReady()
  eq(ok, false, "throttle blocks a second scan")
  check(string.find(why, "available in"), "throttle message: " .. tostring(why))
  eq(H.db.names[2770], "Copper Ore", "name cached from scan")
end

------------------------------------------------------------------------
-- Snipe pass: browse, confirm, score, buy
------------------------------------------------------------------------
do
  -- seed solid history: copper ore market ~100c for ten days, moves 200 a day
  Store.Wipe()
  AuctionHoundDB.lastFull = 0
  for d = 10, 0, -1 do
    local t = Stub.now - d * 86400
    Store.AddScanSample("2770", t, { { p = 100, q = 500 }, { p = 110, q = 500 } })
    Store.AddScanSample("2770", t + 3600, { { p = 100, q = 300 }, { p = 110, q = 500 } })
    Store.AddScanSample("2771", t, { { p = 1000, q = 50 } })      -- tin ore, 10s, no movement
    Store.AddScanSample("2771", t + 3600, { { p = 1000, q = 50 } })
    Store.AddScanSample("2318", t, { { p = 300, q = 100 } })
  end
  -- falling knife: bronze was 1000 a week ago and is 500 today
  for d = 10, 0, -1 do
    local t = Stub.now - d * 86400
    local price = d >= 3 and 1000 or 500
    Store.AddScanSample("2841", t, { { p = price, q = 100 } })
    Store.AddScanSample("2841", t + 3600, { { p = price, q = 90 } })
  end

  Stub.ah.browse = {
    { itemKey = C_AuctionHouse.MakeItemKey(2770), minPrice = 40, totalQuantity = 800 },   -- 60% off, liquid
    { itemKey = C_AuctionHouse.MakeItemKey(2771), minPrice = 600, totalQuantity = 5 },     -- 40% off, dead market
    { itemKey = C_AuctionHouse.MakeItemKey(2841), minPrice = 300, totalQuantity = 20 },    -- under a falling reference
    { itemKey = C_AuctionHouse.MakeItemKey(2934), minPrice = 10, totalQuantity = 50 },     -- no history, prior only
    { itemKey = C_AuctionHouse.MakeItemKey(7777), minPrice = 4000, totalQuantity = 3 },    -- under vendor
    { itemKey = C_AuctionHouse.MakeItemKey(2318), minPrice = 290, totalQuantity = 100 },   -- not a deal
    { itemKey = C_AuctionHouse.MakeItemKey(15001, 20, -14), minPrice = 30000, totalQuantity = 1 }, -- no history, no prior
  }
  Stub.ah.searchResults = {
    ["2770"] = { commodity = true, listings = { { 40, 30 }, { 45, 20 }, { 100, 500 } } },
    ["2771"] = { commodity = true, listings = { { 600, 5 }, { 1000, 50 } } },
    ["2841"] = { commodity = true, listings = { { 300, 20 }, { 500, 100 } } },
    ["2934"] = { commodity = true, listings = { { 10, 50 } } },
    ["7777"] = { commodity = true, listings = { { 4000, 3 } } },
  }
  Stub.ah.commodityPrice[2770] = 45

  local done = false
  eq(H.Snipe.Run(function() done = true end), true, "snipe pass starts")
  for _ = 1, 40 do Stub.Advance(1) Stub.Pump() end
  eq(done, true, "snipe pass completes")
  eq(H.Snipe.lastBrowse.count, 7, "browsed every page")
  eq(H.Snipe.lastCandidates, 5, "five candidates under the discount line")

  local byKey = {}
  for _, r in ipairs(H.Snipe.results) do byKey[r.key] = r end
  check(byKey["2318"] == nil, "light leather is not a deal")
  check(byKey["15001:20:-14"] == nil, "no reference means no row")

  local copper = byKey["2770"]
  check(copper ~= nil, "copper ore is a result")
  eq(copper.dealQty, 50, "copper deal units are those at or under the line")
  eq(copper.unit, 40, "copper unit is the floor")
  eq(copper.score, 5, "copper scores five")
  check(copper.netTotal > 0, "copper net positive")
  local reasons = table.concat(copper.reasons, ";")
  check(string.find(reasons, "solid history"), "copper reasons mention history: " .. reasons)
  check(string.find(reasons, "moves ~"), "copper reasons mention sale rate: " .. reasons)

  local tin = byKey["2771"]
  check(tin ~= nil, "tin ore is a result")
  check(tin.score < copper.score, "dead market scores lower than liquid market")
  check(string.find(table.concat(tin.reasons, ";"), "slow market"), "tin flagged as slow market")

  local bronze = byKey["2841"]
  check(bronze ~= nil, "bronze bar is a result")
  check(string.find(table.concat(bronze.reasons, ";"), "falling"), "bronze flagged as falling: " .. table.concat(bronze.reasons, ";"))

  local scraps = byKey["2934"]
  check(scraps ~= nil, "scraps priced from prior")
  eq(scraps.refSrc, "prior:value as an input", "scraps reference source")
  check(string.find(table.concat(scraps.reasons, ";"), "no usable history"), "scraps flagged as prior")

  local junk = byKey["7777"]
  check(junk ~= nil and junk.vendorFlip, "junk under vendor is a vendor flip")
  eq(junk.score, 5, "vendor flip scores five")

  eq(H.Snipe.results[1].score, 5, "results sorted by score")

  -- buy copper: quote 45 is under the 75 limit, so it confirms
  eq(H.Snipe.Buy(copper, 50), true, "buy starts")
  Stub.Advance(1)
  eq(#Stub.ah.purchases, 1, "purchase confirmed")
  eq(Stub.ah.purchases[1].qty, 50, "bought all deal units")
  Stub.Advance(1)
  check(H.Snipe.pending == nil, "purchase settled")
  eq(#AuctionHoundDB.ledger, 1, "ledger records the buy")
  eq(AuctionHoundDB.ledger[1].unit, 45, "ledger unit is the quoted price")
  check(byKey["2770"] ~= nil and (function() for _, r in ipairs(H.Snipe.results) do if r.key == "2770" then return false end end return true end)(), "bought row removed")

  -- price moved above the limit: cancel
  Stub.ah.commodityPrice[2771] = 900
  eq(H.Snipe.Buy(tin, 5), true, "tin buy starts")
  Stub.Advance(1)
  eq(Stub.ah.cancelled, 1, "cancelled when the quote moved")
  eq(#Stub.ah.purchases, 1, "no second purchase")
  check(H.Snipe.pending == nil, "pending cleared after cancel")
end

------------------------------------------------------------------------
-- Item purchase and throttle retry
------------------------------------------------------------------------
do
  Store.AddScanSample("15001:20:-14", Stub.now - 86400, { { p = 60000, q = 1 }, { p = 65000, q = 1 } })
  Store.AddScanSample("15001:20:-14", Stub.now, { { p = 60000, q = 1 }, { p = 65000, q = 1 } })
  Stub.ah.browse = { { itemKey = C_AuctionHouse.MakeItemKey(15001, 20, -14), minPrice = 30000, totalQuantity = 1 } }
  Stub.ah.searchResults["15001:20:-14"] = { commodity = false, listings = { { 30000, 1, 4242 }, { 60000, 1, 4243 } } }
  H.Snipe.Clear()
  -- throttle: first send is not ready, becomes ready later
  Stub.ah.ready = false
  Stub.ah.lastQuery = nil
  eq(H.Snipe.Run(), true, "item pass starts while throttled")
  Stub.Advance(2)
  eq(Stub.ah.lastQuery, nil, "query held until the throttle clears")
  Stub.ah.ready = true
  Stub.FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  check(Stub.ah.lastQuery ~= nil, "query sent when ready")
  for _ = 1, 10 do Stub.Advance(1) Stub.Pump() end
  local row = H.Snipe.results[1]
  check(row ~= nil, "item row present")
  eq(row.isCommodity, false, "row is an item")
  eq(row.auctionID, 4242, "cheapest auction id kept")
  eq(row.dealQty, 1, "one unit")
  eq(H.Snipe.Buy(row), true, "item buy starts")
  Stub.Advance(1)
  eq(Stub.ah.purchases[#Stub.ah.purchases].auctionID, 4242, "bought by auction id")
  eq(Stub.ah.purchases[#Stub.ah.purchases].amount, 30000, "bought at buyout")
  check(H.Snipe.pending == nil, "item purchase settled")

  -- watchdog resets a wedged browse
  Stub.ah.browse = {}
  C_AuctionHouse.SendBrowseQuery = function() end
  H.Scan.Browse({}, function() end)
  eq(H.Scan.state, "browsing", "browse in flight")
  Stub.Advance(31)
  eq(H.Scan.state, "idle", "watchdog reset the browse")

  -- a purchase that never answers is dropped
  local silent = { key = "2770", itemID = 2770, name = "Copper Ore", isCommodity = true, dealQty = 5, unit = 40, maxUnit = 75 }
  local realStart = C_AuctionHouse.StartCommoditiesPurchase
  C_AuctionHouse.StartCommoditiesPurchase = function() end
  eq(H.Snipe.Buy(silent, 5), true, "silent buy starts")
  eq(H.Snipe.Buy(silent, 5), false, "second buy refused while one is in flight")
  Stub.Advance(H.Snipe.BUY_TIMEOUT + 1)
  check(H.Snipe.pending == nil, "purchase timeout clears the pending buy")
  C_AuctionHouse.StartCommoditiesPurchase = realStart

  -- the confirm step wants a hardware event: the next click confirms
  local purchasesBefore = #Stub.ah.purchases
  local realConfirm = C_AuctionHouse.ConfirmCommoditiesPurchase
  C_AuctionHouse.ConfirmCommoditiesPurchase = function() error("requires a hardware event") end
  Stub.ah.commodityPrice[2770] = 45
  Stub.printed = {}
  eq(H.Snipe.Buy(silent, 5), true, "guarded buy starts")
  Stub.Advance(1)
  check(H.Snipe.pending ~= nil and H.Snipe.pending.needsConfirm, "purchase waits for a click to confirm")
  check(string.find(table.concat(Stub.printed, "\n"), "press Buy again", 1, true), "asks for another click")
  eq(#Stub.ah.purchases, purchasesBefore, "nothing bought yet")
  C_AuctionHouse.ConfirmCommoditiesPurchase = realConfirm
  eq(H.Snipe.Buy(silent, 5), true, "second click confirms")
  eq(#Stub.ah.purchases, purchasesBefore + 1, "purchase confirmed from the click")
  eq(Stub.ah.purchases[#Stub.ah.purchases].qty, 5, "confirmed quantity")
  Stub.Advance(1)
  check(H.Snipe.pending == nil, "guarded purchase settled")
  eq(AuctionHoundDB.ledger[#AuctionHoundDB.ledger].unit, 45, "ledger unit is the quote")
end

------------------------------------------------------------------------
-- Fan: plan math
------------------------------------------------------------------------
local F = H.Fan
do
  near(F.NormalQuantile(0.5), 0, 1e-9, "normal quantile at the median")
  near(F.NormalQuantile(0.975), 1.959964, 1e-5, "normal quantile at 97.5%")
  near(F.NormalQuantile(0.1), -1.281552, 1e-5, "normal quantile at 10%")
  near(F.NormalQuantile(0.01), -2.326348, 1e-5, "normal quantile in the tail")

  eq(H.ParseMoney("1g 20s 5c"), 12005, "parse money long form")
  eq(H.ParseMoney("1.5g"), 15000, "parse money decimal gold")
  eq(H.ParseMoney("45s"), 4500, "parse money silver")
  eq(H.ParseMoney("250"), 250, "parse money bare copper")
  eq(H.ParseMoney(""), nil, "parse money empty")
  eq(H.ParseMoney("abc"), nil, "parse money junk")

  local lin = F.Plan({ center = 1000, step = 0.05, batches = 5, perBatch = 10, shape = "linear" })
  eq(#lin.batches, 5, "linear plan has five batches")
  eq(lin.batches[1].unit, 900, "linear low end")
  eq(lin.batches[2].unit, 950, "linear even step")
  eq(lin.batches[3].unit, 1000, "linear center")
  eq(lin.batches[5].unit, 1100, "linear high end")
  eq(lin.units, 50, "linear units")
  eq(lin.gross, 50000, "linear gross")
  eq(lin.net, 47500, "linear net after the cut")
  eq(lin.low, 900, "plan low")
  eq(lin.high, 1100, "plan high")

  local bell = F.Plan({ center = 1000, step = 0.05, batches = 5, perBatch = 10, shape = "bell" })
  eq(#bell.batches, 5, "bell plan has five batches")
  eq(bell.batches[1].unit, 900, "bell keeps the low end")
  eq(bell.batches[3].unit, 1000, "bell keeps the center")
  eq(bell.batches[5].unit, 1100, "bell keeps the high end")
  check(bell.batches[2].unit > lin.batches[2].unit, "bell pulls the second batch toward the center")
  check(bell.batches[4].unit < lin.batches[4].unit, "bell pulls the fourth batch toward the center")
  check(bell.batches[3].unit - bell.batches[2].unit < bell.batches[2].unit - bell.batches[1].unit, "bell gaps narrow toward the center")
  local seven = F.Plan({ center = 10000, step = 0.05, batches = 7, perBatch = 1, shape = "bell" })
  check(seven.batches[4].unit - seven.batches[3].unit < seven.batches[2].unit - seven.batches[1].unit, "bell of seven bunches in the middle")
  eq(seven.batches[1].unit, 8500, "bell of seven spans the linear range")
  local three = F.Plan({ center = 1000, step = 0.05, batches = 3, perBatch = 1, shape = "bell" })
  eq(three.batches[2].unit, 1000, "bell of three is centered")

  local above = F.Plan({ center = 1000, step = 0.05, batches = 4, perBatch = 10, spread = "above" })
  eq(above.batches[1].unit, 1000, "above starts at the center")
  eq(above.batches[4].unit, 1150, "above ends three steps up")
  local below = F.Plan({ center = 1000, step = 0.05, batches = 4, perBatch = 10, spread = "below" })
  eq(below.batches[4].unit, 1000, "below ends at the center")
  eq(below.batches[1].unit, 850, "below starts three steps down")

  local flat = F.Plan({ center = 1000, step = 0, batches = 3, perBatch = 10, shape = "bell" })
  eq(#flat.batches, 3, "zero step keeps every batch")
  eq(flat.batches[1].unit, 1000, "zero step first batch at the center")
  eq(flat.batches[2].unit, 1000, "zero step second batch at the center")
  eq(flat.batches[3].unit, 1000, "zero step third batch at the center")
  eq(flat.low, flat.high, "zero step has no range")
  local neg = F.Plan({ center = 1000, step = -0.05, batches = 3, perBatch = 10 })
  eq(neg.batches[3].unit, 1000, "negative step reads as zero")

  local one = F.Plan({ center = 1000, step = 0.05, batches = 1, perBatch = 10 })
  eq(#one.batches, 1, "single batch")
  eq(one.batches[1].unit, 1000, "single batch at the center")

  local tiny = F.Plan({ center = 3, step = 0.05, batches = 5, perBatch = 1 })
  local distinct, seen = true, {}
  for _, b in ipairs(tiny.batches) do
    if seen[b.unit] or b.unit < 1 then distinct = false end
    seen[b.unit] = true
  end
  check(distinct, "tiny prices stay distinct and positive")

  local short = F.Plan({ center = 1000, step = 0.05, batches = 5, perBatch = 10, avail = 25 })
  eq(#short.batches, 3, "short plan drops empty batches")
  eq(short.batches[3].qty, 5, "short plan trims the last batch")
  check(short.short, "short plan flagged")
  eq(short.units, 25, "short plan units")
  check(not lin.short, "full plan not flagged short")

  local vend = F.Plan({ center = 1000, step = 0.1, batches = 5, perBatch = 1, vendor = 850 })
  check(vend.batches[1].belowVendor, "cheapest batch under vendor flagged")
  check(not vend.batches[3].belowVendor, "center batch not flagged")
end

------------------------------------------------------------------------
-- Fan: bags, posting, own sales
------------------------------------------------------------------------
do
  Stub.SetBag(0, 1, 2770, 20)
  Stub.SetBag(0, 2, 2770, 20)
  Stub.SetBag(1, 3, 2770, 15)
  Stub.SetBag(0, 5, 15001, 1, { suffix = -14 })
  Stub.SetBag(0, 6, 15001, 1, { suffix = -14 })
  Stub.SetBag(2, 1, 7777, 5)
  local bags = F.Bags()
  eq(bags["2770"].count, 55, "copper ore counted across stacks")
  eq(#bags["2770"].stacks, 3, "three copper stacks")
  eq(bags["15001:20:-14"].count, 2, "bracers keyed by variant")
  eq(F.BagCount("2771"), 0, "nothing of tin ore")

  local anchor, src = F.Anchor("2770", 2770)
  eq(src, "market", "anchor from market history")
  check(anchor and anchor > 0, "anchor value")
  local _, nsrc = F.Anchor("424242", 424242)
  eq(nsrc, "none", "no anchor without history")
  local noPlan, noWhy = F.Setup({ key = "424242" })
  eq(noPlan, nil, "no plan without a price")
  check(string.find(noWhy or "", "center"), "asks for a center price")

  eq(H.atAH, true, "still at the auction house")
  local plan, err = F.Setup({ key = "2770", perBatch = 10, step = 0.10, batches = 5, shape = "linear", spread = "around" })
  check(plan ~= nil, "fan set up: " .. tostring(err))
  eq(#plan.batches, 5, "five batches planned")
  eq(plan.units, 50, "fifty units planned")
  eq(plan.centerSrc, "market", "plan centered on market")
  eq(plan.isCommodity, true, "copper is a commodity")
  eq(plan.batches[1].deposit, 30, "deposit from the client")
  eq(H.Settings().fanBatches, 5, "batches remembered")
  near(H.Settings().fanStep, 0.10, 1e-9, "step remembered")
  eq(F.NextIndex(), 1, "first batch is next")
  check(not F.InProgress(), "nothing posted yet")

  eq(F.PostNext(), true, "first batch posts")
  eq(F.PostNext(), false, "second batch waits for the first")
  check(F.InProgress(), "fan in progress while posting")
  local again = F.Setup({ key = "2770" })
  eq(again, nil, "no replanning mid-fan")
  Stub.Advance(1)
  eq(#Stub.ah.posted, 1, "one auction posted")
  eq(Stub.ah.posted[1].qty, 10, "posted ten units")
  eq(Stub.ah.posted[1].unit, plan.batches[1].unit, "posted the cheapest batch first")
  eq(Stub.ah.posted[1].duration, 3, "posted for 48 hours")
  eq(Stub.ah.posted[1].commodity, true, "posted as a commodity")
  eq(F.NextIndex(), 2, "plan advanced")
  check(F.InProgress(), "fan in progress between batches")
  eq(plan.batches[1].post.status, "active", "post active")
  check(plan.batches[1].post.auctionID ~= nil, "post has an auction id")
  eq(F.BatchStatus(plan.batches[1]), "active", "batch status reads active")
  eq(F.BatchStatus(plan.batches[2]), "pending", "next batch pending")
  for _ = 2, 5 do
    eq(F.PostNext(), true, "batch posts")
    Stub.Advance(1)
  end
  eq(#Stub.ah.posted, 5, "five auctions posted")
  eq(F.PostNext(), false, "complete fan refuses to post")
  check(not F.InProgress(), "fan no longer in progress")
  eq(Stub.BagCount(2770), 5, "five ore left in the bags")
  eq(#H.Store.Posts("2770"), 5, "five posts stored")
  eq(#H.Store.Posts(), 5, "five posts in all")
  check(type(AuctionHoundDB.markets[H.marketKey].posts) == "table", "posts live in the market record")

  -- items post one per slot
  local p2, err2 = F.Setup({ key = "15001:20:-14", perBatch = 1, step = 0.1, batches = 2, center = 50000 })
  check(p2 ~= nil, "item fan set up: " .. tostring(err2))
  eq(p2.isCommodity, false, "bracers are items")
  eq(p2.centerSrc, "set", "center given")
  eq(F.PostNext(), true, "first bracers post")
  Stub.Advance(1)
  eq(F.PostNext(), true, "second bracers post")
  Stub.Advance(1)
  eq(#Stub.ah.posted, 7, "seven auctions posted")
  eq(Stub.ah.posted[7].commodity, false, "posted as an item")
  check(Stub.ah.posted[6].slot ~= Stub.ah.posted[7].slot, "items came from different slots")
  eq(Stub.BagCount(15001), 0, "no bracers left")

  -- running out of stock
  local p3 = F.Setup({ key = "7777", perBatch = 5, step = 0.1, batches = 3, center = 10000 })
  eq(#p3.batches, 1, "plan trimmed to what is on hand")
  check(p3.short, "short flagged")
  Stub.SetBag(2, 1, nil)
  eq(F.PostNext(), false, "nothing to post once the bags are empty")
  F.Reset()
  check(F.plan == nil, "reset clears the plan")

  -- own sales through the owned auction list
  local posts = H.Store.Posts("2770")
  local a1, a2, a3, a4, a5 = posts[1].auctionID, posts[2].auctionID, posts[3].auctionID, posts[4].auctionID, posts[5].auctionID
  Stub.Owned(a1).status = Enum.AuctionStatus.Sold
  Stub.Owned(a2).quantity = 4
  local ledgerBefore = #AuctionHoundDB.ledger
  check(F.Reconcile(Stub.ah.owned, Stub.now) > 0, "reconcile reports changes")
  eq(posts[1].status, "sold", "sold auction marked sold")
  eq(posts[1].sold, 10, "sold auction counts all units")
  check(not posts[1].inferred, "sold status is confirmed")
  eq(posts[2].sold, 6, "partial fill counted")
  eq(posts[2].status, "active", "partial fill still active")
  eq(#AuctionHoundDB.ledger, ledgerBefore + 2, "two sale ledger entries")
  eq(AuctionHoundDB.ledger[#AuctionHoundDB.ledger].kind, "sale", "ledger kind is sale")
  eq(AuctionHoundDB.ledger[#AuctionHoundDB.ledger].qty, 6, "ledger sale quantity")
  eq(F.PostStatus(posts[2]), "sold 6/10", "partial status text")
  eq(F.Reconcile(Stub.ah.owned, Stub.now), 0, "repeat reconcile is quiet")

  Stub.RemoveOwned(a3)
  F.Reconcile(Stub.ah.owned, Stub.now)
  eq(posts[3].status, "active", "fresh post missing from the list is left alone")
  F.Reconcile(Stub.ah.owned, Stub.now + F.SETTLE)
  eq(posts[3].status, "sold", "vanished early counts as sold")
  check(posts[3].inferred, "vanished early is inferred")
  eq(posts[3].sold, 10, "inferred sale counts all units")
  eq(F.PostStatus(posts[3]), "sold (inferred)", "inferred status text")

  Stub.RemoveOwned(a4)
  posts[4].t = Stub.now - 49 * 3600
  F.Reconcile(Stub.ah.owned, Stub.now)
  eq(posts[4].status, "expired", "vanished after expiry counts as expired")
  eq(posts[4].sold, 0, "expired sold nothing")

  Stub.FireEvent("AUCTION_CANCELED", a5)
  eq(posts[5].status, "cancelled", "cancel event marks the post")

  local cl = H.Market.Clearing(posts, Stub.now)
  eq(cl.soldUnits, 26, "clearing sold units")
  eq(cl.inferredUnits, 10, "clearing inferred units")
  eq(cl.unsoldUnits, 10, "clearing unsold units")
  eq(cl.soldMax, posts[3].unit, "clearing sold max")
  eq(cl.soldMin, posts[1].unit, "clearing sold min")
  eq(cl.unsoldMin, posts[4].unit, "clearing unsold min")
  eq(cl.activeUnits, 4, "clearing active units")
  eq(cl.n, 4, "cancelled post not counted")
  local line = F.ClearingLine(cl, Stub.now)
  check(string.find(line, "sold 26 up to", 1, true), "clearing line: " .. line)
  check(string.find(line, "10 inferred", 1, true), "clearing line mentions inferred")
  check(string.find(line, "10 unsold from", 1, true), "clearing line mentions unsold")
  check(string.find(line, "4 listed", 1, true), "clearing line mentions listed")
  eq(F.ClearingLine(nil), "no sales recorded", "clearing line without data")
  eq(H.Market.Clearing({}, Stub.now), nil, "clearing of nothing is nil")

  local a2v, a2s = F.Anchor("2770", 2770, Stub.now)
  eq(a2s, "sold", "anchor now follows sales")
  eq(a2v, posts[3].unit, "anchor is the best sold price")

  -- mail: confirms the inferred sale, catches a fill the list missed,
  -- and corrects an expiry that was really a sale
  Stub.mail = {
    { invoiceType = "seller", itemName = "Copper Ore", bid = posts[3].unit * 10, count = 10 },
    { invoiceType = "seller", itemName = "Copper Ore", bid = posts[2].unit * 8, count = 8 },
    { invoiceType = "seller", itemName = "Copper Ore", bid = posts[4].unit * 10, count = 10 },
    { invoiceType = "buyer", itemName = "Copper Ore", bid = posts[1].unit, count = 1 },
    { invoiceType = "seller", itemName = "Nothing We Sold", bid = 100, count = 1 },
  }
  eq(F.ScanMail(Stub.now), 3, "three invoices matched")
  check(not posts[3].inferred, "mail confirms the inferred sale")
  eq(posts[3].status, "sold", "confirmed sale stays sold")
  eq(posts[2].sold, 8, "mail raises the sold count")
  eq(posts[2].status, "active", "partly sold batch still active")
  eq(posts[4].status, "sold", "mail turns a false expiry into a sale")
  eq(posts[4].sold, 10, "corrected sale counts all units")
  eq(F.ScanMail(Stub.now), 3, "rescanning the same mail changes nothing")
  eq(posts[2].sold, 8, "no double counting from mail")
  Stub.mail = {}
  cl = H.Market.Clearing(posts, Stub.now)
  eq(cl.soldUnits, 38, "clearing after mail")
  eq(cl.inferredUnits, 0, "nothing inferred after mail")
  eq(cl.unsoldUnits, 0, "nothing unsold after mail")

  -- opening the auction house checks on open posts
  local q = Stub.ah.ownedQueries
  Stub.FireEvent("AUCTION_HOUSE_SHOW")
  Stub.Advance(3)
  eq(Stub.ah.ownedQueries, q + 1, "owned auctions queried on open")
  Stub.ah.ready = false
  eq(F.RefreshOwned(true), false, "refresh waits for the throttle")
  Stub.ah.ready = true
  Stub.Advance(4)
  eq(Stub.ah.ownedQueries, q + 2, "refresh retried when ready")

  -- no reply from the auction house, then the auction turns out to exist
  Stub.SetBag(3, 1, 2771, 40)
  local p4 = F.Setup({ key = "2771", perBatch = 10, step = 0.05, batches = 2, center = 1000 })
  local realPost = C_AuctionHouse.PostCommodity
  C_AuctionHouse.PostCommodity = function() end
  eq(F.PostNext(), true, "post with no reply starts")
  Stub.Advance(F.POST_TIMEOUT + 1)
  check(F.pending == nil, "watchdog cleared the pending post")
  eq(p4.batches[1].status, "failed", "batch marked failed")
  eq(p4.batches[1].post.status, "failed", "post marked failed")
  eq(F.NextIndex(), 1, "failed batch is still next")
  check(not F.InProgress(), "a failed first batch leaves the fan open")
  C_AuctionHouse.PostCommodity = realPost
  table.insert(Stub.ah.owned, { auctionID = 7001, itemKey = C_AuctionHouse.MakeItemKey(2771), status = 0, quantity = 10, buyoutAmount = p4.batches[1].unit })
  F.Reconcile(Stub.ah.owned, Stub.now)
  eq(p4.batches[1].post.status, "active", "orphan auction adopted")
  eq(p4.batches[1].post.auctionID, 7001, "adopted auction id")
  eq(F.NextIndex(), 2, "adoption advances the plan")

  -- refused by the auction house
  C_AuctionHouse.PostCommodity = function() Stub.FireEvent("AUCTION_HOUSE_SHOW_ERROR", 1) end
  eq(F.PostNext(), true, "refused post starts")
  check(F.pending == nil, "refusal clears the pending post")
  eq(p4.batches[2].status, "failed", "refused batch marked failed")
  eq(#H.Store.Posts("2771"), 1, "refused post not stored")
  C_AuctionHouse.PostCommodity = realPost

  -- auction house closes mid-post
  eq(F.PostNext(), true, "retry starts")
  Stub.FireEvent("AUCTION_HOUSE_CLOSED")
  check(F.pending == nil, "closing the auction house clears the pending post")
  eq(p4.batches[2].status, "failed", "interrupted batch marked failed")
  Stub.FireEvent("AUCTION_HOUSE_SHOW")
  Stub.Advance(3)
  F.Reset()

  -- a paged owned list never counts a missing auction as gone
  Stub.SetBag(3, 2, 2771, 40)
  local p5 = F.Setup({ key = "2771", perBatch = 10, step = 0.05, batches = 3, center = 1000 })
  for _ = 1, 3 do eq(F.PostNext(), true, "paged test batch posts") Stub.Advance(1) end
  local paged = H.Store.Posts("2771")
  local lastPost = paged[#paged]
  eq(lastPost.status, "active", "last post active before paging")
  Stub.ah.ownedPageSize = 2
  Stub.ah.ownedMore = 0
  F.RefreshOwned(true)
  Stub.Advance(1)
  eq(Stub.ah.ownedMore, 0, "more results not yet requested")
  Stub.Advance(1)
  check(Stub.ah.ownedMore >= 1, "more owned results requested")
  eq(lastPost.status, "active", "post on a later page not marked gone")
  for _ = 1, 30 do
    if C_AuctionHouse.HasFullOwnedAuctionResults() then break end
    Stub.Advance(1)
  end
  check(C_AuctionHouse.HasFullOwnedAuctionResults(), "owned list completed")
  check(Stub.ah.ownedMore >= 2, "every page requested: " .. tostring(Stub.ah.ownedMore))
  eq(lastPost.status, "active", "post found once the list is complete")
  Stub.RemoveOwned(lastPost.auctionID)
  F.Reconcile(Stub.ah.owned, Stub.now + F.SETTLE, true)
  eq(lastPost.status, "active", "partial reconcile leaves missing posts alone")
  F.Reconcile(Stub.ah.owned, Stub.now + F.SETTLE)
  eq(lastPost.status, "sold", "full reconcile resolves it")
  Stub.ah.ownedPageSize = nil
  F.Reset()

  -- pruning keeps recent and open posts
  local list = H.Store.Posts()
  local before = #list
  table.insert(list, 1, { t = Stub.now - 40 * 86400, key = "2770", itemID = 2770, qty = 1, unit = 1, status = "expired", sold = 0 })
  table.insert(list, 1, { t = Stub.now - 40 * 86400, key = "2770", itemID = 2770, qty = 1, unit = 1, status = "active", sold = 0 })
  H.Store.PrunePosts(Stub.now)
  eq(#list, before + 1, "old resolved post pruned, old open post kept")
end

------------------------------------------------------------------------
-- Tooltip and slash commands
------------------------------------------------------------------------
do
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 2770, hyperlink = "|cffffffff|Hitem:2770:0:0:0:0:0:0:0:60:0:0:0:0|h[Copper Ore]|h|r" })
  check(#GameTooltip.lines >= 3, "tooltip lines added: " .. #GameTooltip.lines)
  check(string.find(GameTooltip.lines[2], "market"), "tooltip has market line")
  check(string.find(GameTooltip.lines[#GameTooltip.lines], "yours"), "tooltip has own sales line")
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 424242 })
  eq(#GameTooltip.lines, 0, "no tooltip lines without history")
  -- sales without scan history still show
  Stub.DefineItem(31337, "Odd Trinket", { sell = 1, commodity = true })
  H.Store.AddPost({ t = Stub.now - 3600, key = "31337", itemID = 31337, name = "Odd Trinket", qty = 2, unit = 777, status = "sold", sold = 2, soldAt = Stub.now - 60 })
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 31337 })
  eq(#GameTooltip.lines, 2, "tooltip with sales but no scans")
  check(string.find(GameTooltip.lines[2], "sold 2"), "tooltip sales line: " .. tostring(GameTooltip.lines[2]))

  Stub.printed = {}
  SlashCmdList.HOUND("fan")
  check(string.find(Stub.printed[#Stub.printed] or "", "no fan planned"), "fan command without a plan")
  Stub.SetBag(0, 1, 2770, 40)
  SlashCmdList.HOUND("fan 2770 8 4 3 bell above 2s")
  check(H.Fan.plan ~= nil and H.Fan.plan.key == "2770", "fan command plans")
  eq(H.Fan.plan.perBatch, 8, "fan command per batch")
  near(H.Fan.plan.step, 0.04, 1e-9, "fan command step")
  eq(H.Fan.plan.requested, 3, "fan command batches")
  eq(H.Fan.plan.shape, "bell", "fan command shape")
  eq(H.Fan.plan.spread, "above", "fan command spread")
  eq(H.Fan.plan.center, 200, "fan command center")
  eq(H.Fan.plan.batches[1].unit, 200, "above fan starts at the center")
  SlashCmdList.HOUND("fan 2770 5 0 3")
  near(H.Fan.plan.step, 0, 1e-9, "fan command accepts a zero step")
  eq(H.Fan.plan.batches[1].unit, H.Fan.plan.batches[3].unit, "zero step fan is flat")
  SlashCmdList.HOUND("fan |cffffffff|Hitem:2770:0:0:0:0:0:0:0:60:0:0:0:0|h[Copper Ore]|h|r 5 5% 2 24h")
  eq(H.Fan.plan.duration, 2, "fan command duration")
  near(H.Fan.plan.step, 0.05, 1e-9, "fan command percent step")
  eq(H.Fan.plan.centerSrc, "sold", "fan command centers on sales when it can")
  Stub.printed = {}
  SlashCmdList.HOUND("fan")
  check(#Stub.printed >= 3, "fan command describes the plan")
  check(string.find(Stub.printed[1] or "", "(commodity)", 1, true), "plan line names the commodity: " .. tostring(Stub.printed[1]))
  Stub.printed = {}
  SlashCmdList.HOUND("stats 2770")
  check(string.find(table.concat(Stub.printed, "\n"), "yours:"), "stats prints own sales")
  Stub.printed = {}
  SlashCmdList.HOUND("stats 31337")
  check(string.find(table.concat(Stub.printed, "\n"), "yours:"), "stats prints own sales without scans")
  local postedBefore = #Stub.ah.posted
  SlashCmdList.HOUND("post")
  Stub.Advance(1)
  eq(#Stub.ah.posted, postedBefore + 1, "post command posts a batch")
  H.Fan.Reset()

  Stub.printed = {}
  SlashCmdList.HOUND("stats 2770")
  check(#Stub.printed >= 3, "stats prints")
  Stub.printed = {}
  SlashCmdList.HOUND("labor 80")
  eq(H.Settings().laborPerHour, 80, "labor setting")
  SlashCmdList.HOUND("cut 5")
  near(H.Settings().cut, 0.05, 0.0001, "cut setting")
  SlashCmdList.HOUND("discount 30")
  near(H.Settings().minDiscount, 0.30, 0.0001, "discount setting")
  SlashCmdList.HOUND("key |cffffffff|Hitem:15001:0:0:0:0:0:-14:0:60:0:0:0:0|h[Wolf Bracers]|h|r")
  check(string.find(Stub.printed[#Stub.printed], "15001:20:%-14"), "key command")
end

------------------------------------------------------------------------
-- UI builds headlessly and survives events
------------------------------------------------------------------------
do
  UIParent = CreateFrame("Frame", "UIParent")
  local ok, err = pcall(H.UI.EnsurePanel)
  check(ok, "panel builds: " .. tostring(err))
  ok, err = pcall(H.UI.ShowView, "item")
  check(ok, "item view explains itself before an item is picked: " .. tostring(err))
  eq(H.UI.FindKey("2770"), "2770", "find by item id")
  eq(H.UI.FindKey("copper ore"), "2770", "find by name")
  eq(H.UI.FindKey("  Tin O "), "2771", "find by part of a name")
  eq(H.UI.FindKey("|cffffffff|Hitem:15001:0:0:0:0:0:-14:0:60:0:0:0:0|h[Wolf Bracers]|h|r"), "15001:20:-14", "find by link")
  eq(H.UI.FindKey("no such thing"), nil, "find nothing")
  eq(H.UI.FindKey(""), nil, "find with nothing typed")
  ok, err = pcall(H.UI.Toggle)
  check(ok, "window toggles: " .. tostring(err))
  ok, err = pcall(H.UI.ShowView, "markets")
  check(ok, "markets view: " .. tostring(err))
  ok, err = pcall(H.UI.ShowItem, "2770")
  check(ok, "item view: " .. tostring(err))
  ok, err = pcall(H.UI.ShowView, "snipe")
  check(ok, "snipe view: " .. tostring(err))
  ok, err = pcall(H.UI.ShowView, "fan")
  check(ok, "fan view: " .. tostring(err))
  ok, err = pcall(H.UI.ShowFan, "2770")
  check(ok, "fan view with an item: " .. tostring(err))
  check(H.Fan.plan ~= nil and H.Fan.plan.key == "2770", "fan view planned the item")
  H.Fan.Reset()
  SlashCmdList.HOUND("fan 2770 3 5 3 3s")
  eq(H.Fan.plan.center, 300, "chat plan has its center")
  ok, err = pcall(H.UI.ShowFan, "2770")
  check(ok, "fan view after a chat plan: " .. tostring(err))
  eq(H.Fan.plan.center, 300, "showing the view keeps the chat plan")
  eq(H.Fan.plan.centerSrc, "set", "showing the view keeps the given center")
  ok, err = pcall(H.Events.Fire, H.Events, "FAN_UPDATED")
  check(ok, "fan refresh: " .. tostring(err))
  ok, err = pcall(Stub.FireEvent, "BAG_UPDATE_DELAYED")
  check(ok, "fan bag refresh: " .. tostring(err))
  ok, err = pcall(H.UI.ShowItem, "2770")
  check(ok, "item view with sales: " .. tostring(err))
  H.Fan.Reset()
  ok, err = pcall(H.Events.Fire, H.Events, "SNIPE_UPDATED")
  check(ok, "snipe refresh: " .. tostring(err))
  ok, err = pcall(H.Events.Fire, H.Events, "SCAN_DONE", "full")
  check(ok, "scan done refresh: " .. tostring(err))
  ok, err = pcall(H.UI.UpdateStatus)
  check(ok, "status: " .. tostring(err))

  -- auction house tab hook with a fake Blizzard frame
  AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
  AuctionHouseFrame.Tabs = { CreateFrame("Button"), CreateFrame("Button"), CreateFrame("Button") }
  AuctionHouseFrame.displayMode = nil
  -- the Blizzard frame only moves the highlight for modes in this table
  local buyMode = { "SearchBar" }
  AuctionHouseFrame.tabsForDisplayMode = { [buyMode] = 1 }
  AuctionHouseFrame.selectedTab = 1
  function AuctionHouseFrame:SetDisplayMode(mode)
    self.displayMode = mode
    local tab = self.tabsForDisplayMode and self.tabsForDisplayMode[mode]
    if tab then PanelTemplates_SetTab(self, tab) end
  end
  PanelTemplates_SetNumTabs = function() end
  PanelTemplates_SetTab = function(frame, id) frame.selectedTab = id end
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "auction house hook: " .. tostring(err))
  eq(#AuctionHouseFrame.Tabs, 4, "tab added")
  eq(AuctionHouseFrame.tabsForDisplayMode[H.UI.displayMode], 4, "hound mode registered with the frame")
  AuctionHouseFrame:SetDisplayMode(H.UI.displayMode)
  check(AuctionHoundPanel.shown, "panel shown in the auction house")
  eq(AuctionHouseFrame.selectedTab, 4, "hound tab highlighted")
  local hp = AuctionHoundPanel.header.points
  eq(hp[#hp - 1][1], "TOPLEFT", "header anchored at the top left")
  eq(hp[#hp - 1][4], H.UI.AH_INSETS.header, "header starts clear of the portrait")
  AuctionHouseFrame:SetDisplayMode(buyMode)
  check(not AuctionHoundPanel.shown, "panel hidden on another tab")
  eq(AuctionHouseFrame.selectedTab, 1, "buy tab highlighted again")
  -- a frame without the mode table still gets the highlight from the hook
  AuctionHouseFrame.tabsForDisplayMode = nil
  AuctionHouseFrame.selectedTab = 1
  AuctionHouseFrame:SetDisplayMode(H.UI.displayMode)
  eq(AuctionHouseFrame.selectedTab, 4, "hound tab highlighted without the mode table")
  AuctionHouseFrame.tabsForDisplayMode = { [buyMode] = 1 }
  AuctionHouseFrame:SetDisplayMode(buyMode)

  -- template missing: tab creation fails gracefully
  H.UI.ahHooked = false
  Stub.badTemplates = { AuctionHouseFrameDisplayModeTabTemplate = true, PanelTabButtonTemplate = true, CharacterFrameTabButtonTemplate = true }
  Stub.printed = {}
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "hook survives a missing template: " .. tostring(err))
  check(string.find(Stub.printed[#Stub.printed] or "", "could not add"), "missing template reported")
end

------------------------------------------------------------------------
-- Logout flush
------------------------------------------------------------------------
do
  Stub.FireEvent("PLAYER_LOGOUT")
  local m = AuctionHoundDB.markets[H.marketKey]
  check(type(m.items["2770"]) == "string", "logout flushed to strings")
  local total = 0
  for _ in pairs(m.items) do total = total + 1 end
  check(total >= 5, "several items saved: " .. total)
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
