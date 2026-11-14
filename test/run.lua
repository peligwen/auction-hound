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

-- Hover every rendered row the way the client does: the row mixin
-- calls OnLineEnter and OnLineLeave on each cell, and a Hound cell
-- without them is the crash the beta reported. Blizzard's own cells
-- are outside the stub, so only ours are held to it.
local function hover(r, what)
  for i, row in ipairs(r.rowFrames) do
    for _, cell in ipairs(row.cells) do
      if type(cell.template) == "string" and cell.template:find("^AuctionHound") then
        check(rawget(cell, "OnLineEnter") ~= nil and rawget(cell, "OnLineLeave") ~= nil,
          what .. ": " .. cell.template .. " answers the row hover")
      end
    end
    local ok, err = pcall(function() row:OnEnter() row:OnLeave() end)
    check(ok, what .. " row " .. i .. " hover: " .. tostring(err))
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
Stub.DefineItem(4289, "Salt", { sell = 12, commodity = true })
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
eq(H.MoneyExact(123456), "12g 34s 56c", "exact money")
eq(H.MoneyExact(4599), "45s 99c", "exact money keeps the copper")
eq(H.MoneyExact(120000), "12g", "exact money drops empty parts")
eq(H.MoneyExact(100005), "10g 5c", "exact money skips an empty middle")
eq(H.MoneyExact(0), "0c", "exact zero")
eq(H.MoneyExact(-150), "-1s 50c", "exact money negative")
eq(H.KeyString({ itemID = 2770 }), "2770", "commodity key")
eq(H.KeyString({ itemID = 15001, itemLevel = 20, itemSuffix = -14 }), "15001:20:-14", "item key with suffix")
eq(H.KeyFromLink("|cffffffff|Hitem:15001:0:0:0:0:0:-14:0:60:0:0:0:0|h[Wolf Bracers of the Monkey]|h|r"), "15001:20:-14", "key from link")
eq(H.KeyFromLink("|cffffffff|Hitem:2770:0:0:0:0:0:0:0:60:0:0:0:0|h[Copper Ore]|h|r"), "2770", "commodity key from link")
eq(H.KeyForItemID(2770), "2770", "key for commodity id")
eq(H.KeyForItemID(15001), nil, "equippable needs a link")
eq(H.ItemIDFromKey("15001:20:-14"), 15001, "item id from key")
-- the house fills in an item level for anything; only gear keeps it
Stub.DefineItem(4500, "Traveler's Backpack Pattern", { sell = 50, commodity = false, stack = 1 })
eq(H.KeyFromItemKey(C_AuctionHouse.MakeItemKey(2770, 10)), "2770", "house key for a commodity with an item level reads as the scan's")
eq(H.KeyFromItemKey(C_AuctionHouse.MakeItemKey(2770, 10, 3)), "2770", "and with a suffix")
eq(H.KeyFromItemKey(C_AuctionHouse.MakeItemKey(4500, 25)), "4500", "an item that is not gear drops its level too")
eq(H.KeyFromItemKey(C_AuctionHouse.MakeItemKey(2770)), "2770", "a plain house key")
eq(H.KeyFromItemKey(C_AuctionHouse.MakeItemKey(15001, 20, -14)), "15001:20:-14", "gear keeps level and suffix")
eq(H.KeyFromItemKey(C_AuctionHouse.MakeItemKey(15001, 20, -14)),
  H.KeyFromLink("|cffffffff|Hitem:15001:0:0:0:0:0:-14:0:60:0:0:0:0|h[Wolf Bracers of the Monkey]|h|r"), "gear key meets the scan's")
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
eq(H.Span(2700), "45m", "short span in minutes")
eq(H.Span(5400), "1.5h", "short span in hours")
eq(H.Span(3 * 86400), "3d", "short span in days")

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
  rec.fills[lastDay] = { u = 12, v = 1440 }
  back = Store.Decode(Store.Encode(rec))
  eq(back.fills[lastDay] and back.fills[lastDay].u, 12, "roundtrip fills")
  eq(back.fills[lastDay] and back.fills[lastDay].v, 1440, "roundtrip fill value")
  check(next(Store.Decode("1#D#P#M").fills) == nil, "an old record decodes with empty fills")
  rec.fills[lastDay] = nil
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
  do
    local today, sum, n = H.DayIndex(Stub.now), 0, 0
    for d = today - 2, today do
      if rec2.days[d] then sum, n = sum + rec2.days[d].mv, n + 1 end
    end
    check(n > 0, "the last three days hold history")
    eq(st.avg3, H.Round(sum / n), "3 day mean is the plain mean of the last three days")
    check(st.avg3 > st.hist, "3 day mean above the 30 day mean in a rising market")
  end
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
-- Store: a listing near the gold cap, and a record that will not encode
------------------------------------------------------------------------
do
  -- 9,999,999g 99s 99c is past what the client's %d holds. Once a scan
  -- met a listing like it, the beta raised "integer overflow attempting
  -- to store" from the flush frame every frame until a reload.
  local cap = 99999999999
  local day = H.DayIndex(Stub.now)
  for _ = 1, 3 do
    Store.AddScanSample("424242", Stub.now, { { p = 15000, q = 2 } })
  end
  Store.AddScanSample("424242", Stub.now, { { p = cap, q = 2 } })
  local rec = Store.Get("424242")
  check(rec.days[day].mv > 2147483647, "day bucket averaged past 2^31: " .. tostring(rec.days[day].mv))
  local ok, encoded = pcall(Store.Encode, rec)
  check(ok, "gold cap record encodes: " .. tostring(encoded))
  local back = ok and Store.Decode(encoded) or { days = {}, pts = {} }
  eq(back.days[day] and back.days[day].mv, rec.days[day].mv, "gold cap day bucket roundtrips")
  eq(back.pts[4] and back.pts[4].mv, cap, "gold cap point roundtrips")
  eq(back.pts[4] and back.pts[4].min, cap, "gold cap floor roundtrips")
  Store.FlushAsync()
  local ran, err = pcall(Stub.RunTimers)
  check(ran, "flush frame saves the gold cap record: " .. tostring(err))
  check(type(AuctionHoundDB.markets[H.marketKey].items["424242"]) == "string", "gold cap record saved")
  eq(Store.Flush(), 0, "flush frame drained the dirty set")

  -- A day's fills add up units times price, so a busy commodity passes
  -- 2^31 copper long before any one listing does: 300,000 gold cleared
  -- in a day is one stack of ore a minute on a region's house.
  local busy = 3000000000
  Store.AddFills("424242", Stub.now, 250000, busy)
  ok, encoded = pcall(Store.Encode, rec)
  check(ok, "a day's fills past 2^31 copper encode: " .. tostring(encoded))
  back = ok and Store.Decode(encoded) or { fills = {} }
  eq(back.fills[day] and back.fills[day].v, busy, "the fill value roundtrips")
  eq(back.fills[day] and back.fills[day].u, 250000, "and its units")
  eq(Store.Flush(), 1, "the record saves with them")
  rec.fills[day] = nil
  Store.Touch("424242")
  Store.Flush()

  -- A record that cannot be encoded is reported once through the
  -- client's error handler and skipped; the record beside it still
  -- saves, and the frame stops instead of raising every frame.
  local bad = Store.GetOrCreate("424243")
  bad.days[day] = { mv = {}, min = 1, qty = 1, n = 1, s = 1 }
  Store.Touch("424243")
  Store.AddScanSample("424244", Stub.now, { { p = 300, q = 100 } })
  Stub.errors = {}
  Store.FlushAsync()
  ran, err = pcall(Stub.RunTimers)
  check(ran, "flush frame survives a record that will not encode: " .. tostring(err))
  eq(#Stub.errors, 1, "the bad record is reported once")
  check(Stub.errors[1] and string.find(Stub.errors[1], "424243", 1, true) ~= nil, "the report names the key")
  eq(AuctionHoundDB.markets[H.marketKey].items["424243"], nil, "nothing saved for the bad record")
  check(type(AuctionHoundDB.markets[H.marketKey].items["424244"]) == "string", "the record beside it still saves")
  eq(Store.Flush(), 0, "flush frame drained the dirty set past the bad record")
  ran, err = pcall(Stub.RunTimers)
  check(ran and #Stub.errors == 1, "the flush frame stopped instead of reporting again")
  Store.Touch("424243")
  eq(Store.Flush(), 0, "sync flush skips the bad record")
  eq(#Stub.errors, 2, "sync flush reports it once more")
  Stub.errors = {}
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
  -- salt and coal are vendor priced, by the ids the game gives them:
  -- 4340 is gray dye, and the cured medium and heavy hides are 4233 and
  -- 4236, where 4237 is a leather belt
  local hidePrice, hsrc = P.InputPrice(4289)
  eq(hidePrice, 50, "salt priced from vendor table")
  eq(hsrc, "vendor", "salt source")
  eq((P.InputPrice(3857)), 500, "coal priced from vendor table")
  eq(P.InputPrice(4340), nil, "gray dye is no salt")
  local made = {}
  for _, rcp in ipairs(H.Conversions) do made[rcp.name] = rcp.out end
  eq(made["Cured Medium Hide"], 4233, "cured medium hide by its own id")
  eq(made["Cured Heavy Hide"], 4236, "cured heavy hide by its own id")
  -- a cured hide is its raw hide and the salt, and steel its iron and coal
  Store.AddScanSample("4232", Stub.now, { { p = 800, q = 50 } })       -- medium hide 8s
  Store.AddScanSample("4235", Stub.now, { { p = 1500, q = 50 } })      -- heavy hide 15s
  Store.AddScanSample("3575", Stub.now, { { p = 1200, q = 50 } })      -- iron bar 12s
  eq((P.CraftCost(4233)), 850, "cured medium hide costs its hide and one salt")
  eq((P.CraftCost(4236)), 1650, "cured heavy hide costs its hide and three salt")
  eq((P.CraftCost(3859)), 1700, "steel costs its iron bar and the coal")
  -- no recipe makes its own input
  for _, rcp in ipairs(H.Conversions) do
    for _, inp in ipairs(rcp.inputs) do
      check(inp[1] ~= rcp.out and inp[2] > 0, rcp.name .. " takes something other than itself")
    end
  end
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
-- Fills: units gone between two scans before they could expire
------------------------------------------------------------------------
do
  Stub.DefineItem(90040, "Traded Widget", { sell = 0, commodity = true })
  Store.Wipe()
  H.Scan.prev = nil
  local function scan()
    AuctionHoundDB.lastFull = 0
    eq(H.Scan.StartFull(), true, "scan starts")
    Stub.Advance(1) Stub.Pump()
    Stub.Advance(1) Stub.Pump()
    eq(H.Scan.state, "idle", "scan done")
  end
  local function fillUnits(rec)
    local u = 0
    for _, f in pairs(rec.fills) do u = u + f.u end
    return u
  end
  Stub.ah.replicate = {
    { itemID = 90040, count = 10, buyout = 1000 },               -- 100c, plenty of time
    { itemID = 90040, count = 5, buyout = 500, timeLeft = 0 },   -- 100c, about to expire
    { itemID = 90040, count = 8, buyout = 960 },                 -- 120c
    { itemID = 90040, count = 4, buyout = 600, timeLeft = 1 },   -- 150c, under two hours left
  }
  scan()
  check(H.Scan.prev ~= nil and H.Scan.prev.byKey["90040"] ~= nil, "the scan keeps its ladders for the next")
  eq(H.Scan.prev.byKey["90040"][100], 15, "fifteen units at 100c, both bands")
  eq(H.Scan.prev.soon["90040"][100][0], 5, "five of them about to expire")
  check(next(Store.Get("90040").fills) == nil, "no fills from a first scan")
  check(not string.find(Stub.printed[#Stub.printed], "cleared", 1, true), "and the scan line says nothing of them")

  -- fifteen minutes on: the five expiring units are gone, two of the
  -- ten at 100c, all eight at 120c, and a new listing at 90c has come
  Stub.Advance(900)
  Stub.ah.replicate = {
    { itemID = 90040, count = 8, buyout = 800 },
    { itemID = 90040, count = 4, buyout = 600, timeLeft = 1 },
    { itemID = 90040, count = 6, buyout = 540 },
  }
  scan()
  local rec = Store.Get("90040")
  eq(fillUnits(rec), 10, "two at 100c and eight at 120c cleared; the five that could expire did not count")
  local day = H.DayIndex(Stub.now)
  eq(rec.fills[day] and rec.fills[day].v, 2 * 100 + 8 * 120, "at what they went for")
  check(string.find(Stub.printed[#Stub.printed], "10 units cleared since the last", 1, true),
    "the scan line reports them: " .. tostring(Stub.printed[#Stub.printed]))
  local st = H.Market.Stats(rec)
  eq(st.cleared, 10, "cleared per day")
  eq(st.clearing, 116, "the mean price they went at")
  eq(H.Market.ClearedLine(st), "cleared ~10 a day at ~" .. H.Money(116), "the line for it")
  GameTooltip.lines = {}
  Stub.shift = true
  Stub.tooltipHandler(GameTooltip, { id = 90040 })
  Stub.shift = false
  check(string.find(table.concat(GameTooltip.lines, "\n"), "cleared ~10/day at ~1s", 1, true),
    "the item tooltip shows it with Shift held: " .. table.concat(GameTooltip.lines, " | "))
  Stub.printed = {}
  SlashCmdList.HOUND("stats 90040")
  check(string.find(table.concat(Stub.printed, "\n"), "cleared ~10 a day at", 1, true), "stats shows it")
  eq(M.DailySeries(rec, 1, Stub.now)[1].cleared, 10, "the daily series carries it")

  -- an hour on: the four with under two hours left are gone, which
  -- could be expiry, and nothing else moved
  Stub.Advance(3600)
  Stub.ah.replicate = { { itemID = 90040, count = 8, buyout = 800 }, { itemID = 90040, count = 6, buyout = 540 } }
  scan()
  eq(fillUnits(rec), 10, "units that could have expired over the gap are not fills")

  -- a gap too long to read: nothing counted, but the ladders are kept
  Stub.Advance(5 * 3600)
  Stub.ah.replicate = { { itemID = 90040, count = 1, buyout = 100 } }
  scan()
  eq(fillUnits(rec), 10, "nothing read across five hours")
  Stub.Advance(900)
  Stub.ah.replicate = {}
  scan()
  eq(fillUnits(rec), 11, "the last unit gone counts against the scan before")

  -- the count itself, without the house
  local u, v = H.Scan.FillsBetween({ [100] = 10, [200] = 3 }, { [100] = { [1] = 4 } }, { [100] = 2 }, 1000)
  eq(u, 11, "eight gone at 100c, none of which could expire within a thousand seconds, plus three at 200c")
  eq(v, 8 * 100 + 3 * 200, "valued at their prices")
  u = H.Scan.FillsBetween({ [100] = 10 }, { [100] = { [1] = 4 } }, { [100] = 2 }, 2000)
  eq(u, 4, "over two thousand seconds the four could have expired")
  u = H.Scan.FillsBetween({ [100] = 10 }, nil, { [100] = 12 }, 900)
  eq(u, 0, "more units than before is no fill")
  Store.Wipe()
  H.Scan.prev = nil
end

------------------------------------------------------------------------
-- History seed: a solid market, a dead one, a falling one, and gear
------------------------------------------------------------------------
do
  -- copper ore market ~100c for ten days, moves 200 a day
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
  -- a green with a suffix
  Store.AddScanSample("15001:20:-14", Stub.now - 86400, { { p = 60000, q = 1 }, { p = 65000, q = 1 } })
  Store.AddScanSample("15001:20:-14", Stub.now, { { p = 60000, q = 1 }, { p = 65000, q = 1 } })

  -- the reference: deep history first, a prior when there is none
  local ref, src, conf = H.Reference("2770", 2770)
  eq(ref, 100, "copper ore reference is its market value")
  eq(src, "market", "and comes from history")
  check(conf >= 0.3, "with confidence")
  ref, src = H.Reference("2934", 2934)
  eq(src, "prior:value as an input", "scraps priced from a prior")
  ref, src = H.Reference("424242", 424242)
  eq(ref, nil, "nothing known, no reference")

  -- bronze fell from 10s to 5s and stayed: the two-week value still
  -- carries last week, but the latest scan has the whole market at 5s,
  -- and that is the reference
  local stB = select(4, H.Reference("2841", 2841))
  check(stB.market > 500, "bronze's two-week value still carries last week: " .. tostring(stB.market))
  eq((H.Reference("2841", 2841)), 500, "a settled drop is the reference from the next scan on")
  check(string.find(H.ReferenceSource("market", stB), "the last scan, under the two-week", 1, true),
    "and the source says so: " .. H.ReferenceSource("market", stB))
  -- a wall at a new low fills the latest scan's cheapest slice; a
  -- stray under the rest is too few units to move it
  Stub.DefineItem(90030, "Wall Widget", { sell = 0, commodity = true })
  Stub.DefineItem(90031, "Stray Widget", { sell = 0, commodity = true })
  for d = 10, 1, -1 do
    local t = Stub.now - d * 86400
    Store.AddScanSample("90030", t, { { p = 100, q = 200 } })
    Store.AddScanSample("90031", t, { { p = 100, q = 200 } })
  end
  Store.AddScanSample("90030", Stub.now, { { p = 60, q = 150 }, { p = 100, q = 50 } })
  Store.AddScanSample("90031", Stub.now, { { p = 60, q = 1 }, { p = 100, q = 200 } })
  eq((H.Reference("90030", 90030)), 60, "a wall at a new low is the reference")
  eq((H.Reference("90031", 90031)), 100, "a stray under the rest leaves the reference alone")
  check(string.find(H.ReferenceSource("market", select(4, H.Reference("90031", 90031))), "market, ", 1, true),
    "a reference the latest scan agrees with reads as market")
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
  local oreLink = "|cffffffff|Hitem:2770:0:0:0:0:0:0:0:60:0:0:0:0|h[Copper Ore]|h|r"
  local oreSt = H.Market.Stats(H.Store.Get("2770"))
  -- by default one line: the floor at the latest scan
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 2770, hyperlink = oreLink })
  eq(#GameTooltip.lines, 1, "the tooltip is one line by default: " .. table.concat(GameTooltip.lines, " | "))
  eq(GameTooltip.lines[1], "|cffe6b800Hound|r floor | " .. H.Money(oreSt.min), "and that line is the latest floor")
  -- Shift held: the rest, the three-day mean among it
  Stub.shift = true
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 2770, hyperlink = oreLink })
  local full = table.concat(GameTooltip.lines, "\n")
  check(#GameTooltip.lines >= 5, "Shift adds the rest: " .. table.concat(GameTooltip.lines, " | "))
  eq(GameTooltip.lines[2], "|cffe6b800Hound|r floor | " .. H.Money(oreSt.min), "the floor still heads it")
  check(string.find(full, "  market | " .. H.Money(oreSt.market), 1, true), "tooltip has the market line")
  check(string.find(full, "  3 day | " .. H.Money(oreSt.avg3), 1, true), "tooltip has the 3 day mean")
  check(not string.find(full, "30 day", 1, true), "and no 30 day line")
  check(not string.find(full, "vendor", 1, true), "no vendor line: the game's tooltip has its own")
  check(string.find(full, "listed", 1, true), "tooltip says how many are listed")
  check(string.find(GameTooltip.lines[#GameTooltip.lines], "yours"), "tooltip has own sales line")
  Stub.shift = false
  -- a link clicked in chat stays up to be read: always the rest
  ItemRefTooltip.lines = {}
  Stub.tooltipHandler(ItemRefTooltip, { id = 2770, hyperlink = oreLink })
  check(#ItemRefTooltip.lines >= 5, "a chat link's tooltip shows the rest without Shift")
  -- a floor last scanned days ago says how old it is
  do
    local saved = Stub.now
    Stub.now = Stub.now + 3 * 86400
    GameTooltip.lines = {}
    Stub.tooltipHandler(GameTooltip, { id = 2770, hyperlink = oreLink })
    check(string.find(GameTooltip.lines[1] or "", "3d ago", 1, true), "a stale floor says its age: " .. tostring(GameTooltip.lines[1]))
    Stub.now = saved
  end
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 424242 })
  eq(#GameTooltip.lines, 0, "no tooltip lines without history")
  -- junk gets no Hound lines, history or not: the vendor is where it goes
  Stub.DefineItem(4865, "Ruined Pelt", { sell = 5, commodity = true, quality = 0 })
  H.Store.AddScanSample("4865", Stub.now - 600, { { p = 300, q = 20 } })
  check(H.IsJunk(4865) and not H.IsJunk(2770), "junk is read by quality")
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 4865 })
  eq(#GameTooltip.lines, 0, "no Hound lines on junk")
  Stub.shift = true
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 4865 })
  eq(#GameTooltip.lines, 0, "nor with Shift held")
  Stub.shift = false
  -- sales without scan history show with Shift held
  Stub.DefineItem(31337, "Odd Trinket", { sell = 1, commodity = true })
  H.Store.AddPost({ t = Stub.now - 3600, key = "31337", itemID = 31337, name = "Odd Trinket", qty = 2, unit = 777, status = "sold", sold = 2, soldAt = Stub.now - 60 })
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 31337 })
  eq(#GameTooltip.lines, 0, "sales without scans: nothing by default, there is no floor")
  Stub.shift = true
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 31337 })
  Stub.shift = false
  eq(#GameTooltip.lines, 2, "tooltip with sales but no scans")
  check(string.find(GameTooltip.lines[2], "sold 2"), "tooltip sales line: " .. tostring(GameTooltip.lines[2]))

------------------------------------------------------------------------
-- Bag overlay: Shift held puts each slot's worth over the bags
------------------------------------------------------------------------
  do
    local Bags = H.Bags
    local oreFloor = H.Market.Stats(H.Store.Get("2770")).min
    -- what a slot is worth, and where to sell it
    local v, where = Bags.Value(2770, 20)
    eq(v, oreFloor * 20, "a stack with history: the floor for every unit")
    eq(where, "house", "sold at the house")
    v, where = Bags.Value(4865, 3)
    eq(v, 15, "junk: the vendor's price for every unit, whatever the house says")
    eq(where, "vendor", "sold to the vendor")
    v, where = Bags.Value(2770, 20, nil, true)
    eq(v, 100, "a soulbound stack: the vendor's price")
    eq(where, "vendor", "the house will not take it")
    Stub.DefineItem(4306, "Silk Cloth", { sell = 150, commodity = true })
    H.Store.AddScanSample("4306", Stub.now - 600, { { p = 155, q = 40 } })
    v, where = Bags.Value(4306, 2)
    eq(where, "vendor", "the vendor wins when the house pays less after its cut")
    eq(v, 300, "at the vendor's price")
    Stub.DefineItem(4307, "Unscanned Thing", { sell = 7, commodity = true })
    v, where = Bags.Value(4307, 4)
    eq(where, "vendor", "no history: the vendor's price")
    eq(v, 28, "for every unit")
    Stub.DefineItem(4308, "Worth Nothing", { sell = 0, commodity = true })
    eq(Bags.Value(4308, 1), nil, "no history and no vendor price: nothing to show")
    eq(Bags.Value(nil, 1), nil, "an empty slot shows nothing")

    -- one coin, in its color and with its icon
    local gold, silver, copper = "|cffffd700", "|cffc7c7cf", "|cffeda55f"
    local gi, si, ci = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t", "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t", "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t"
    eq(H.MoneyCoin(12000), gold .. "1.2|r" .. gi, "under 10 gold: a tenth of gold, in gold")
    eq(H.MoneyCoin(123456), gold .. "12|r" .. gi, "10 gold and up: whole gold")
    eq(H.MoneyCoin(99500), gold .. "10|r" .. gi, "9.95 gold rounds to 10, not 10.0")
    eq(H.MoneyCoin(4599), silver .. "45|r" .. si, "silver, in silver")
    eq(H.MoneyCoin(75), copper .. "75|r" .. ci, "copper, in copper")
    eq(H.MoneyCoin(0), copper .. "0|r" .. ci, "nothing is no copper")
    H.Settings().plainMoney = true
    eq(H.MoneyCoin(12000), gold .. "1.2g|r", "plain money: the coin's letter in its color")
    eq(H.MoneyCoin(4599), silver .. "45s|r", "silver's letter")
    H.Settings().plainMoney = false

    -- a classic bag frame: buttons numbered within a frame whose ID is the bag
    local bag0 = CreateFrame("Frame", "ContainerFrame1")
    bag0:SetID(0)
    bag0.size = 4
    for i = 1, 4 do
      local b = CreateFrame("Button", "ContainerFrame1Item" .. i, bag0)
      b:SetID(i)
    end
    local savedBags = Stub.bags
    Stub.bags = {}
    Stub.SetBag(0, 1, 2770, 20)
    Stub.SetBag(0, 2, 4865, 3)
    Stub.SetBag(0, 3, 4308, 1)
    -- a modern frame: buttons in a list, each knowing its bag
    local combined = CreateFrame("Frame", "ContainerFrameCombinedBags")
    combined.Items = {}
    local b = CreateFrame("Button", nil, combined)
    b:SetID(5)
    function b:GetBagID() return 1 end
    table.insert(combined.Items, b)
    local hidden = CreateFrame("Button", nil, combined)
    hidden:SetID(6)
    function hidden:GetBagID() return 1 end
    hidden:Hide()
    table.insert(combined.Items, hidden)
    Stub.SetBag(1, 5, 4306, 2)
    Stub.SetBag(1, 6, 2770, 1)

    local function fields(f)
      local keys = {}
      for k in pairs(f) do table.insert(keys, tostring(k)) end
      table.sort(keys)
      return table.concat(keys, ",")
    end
    local buttonsBefore = {}
    for i = 1, 4 do buttonsBefore[i] = fields(_G["ContainerFrame1Item" .. i]) end
    local frameBefore, modernBefore = fields(bag0), fields(b)

    -- Shift is read every frame by Hound's own driver, no event needed
    local function frame(dt) Bags.driver.scripts.OnUpdate(Bags.driver, dt or 0.016) end
    check(Bags.driver and Bags.driver:IsShown() and Bags.driver.scripts.OnUpdate, "a driver frame reads Shift every frame")
    frame()
    eq(Bags.shown, 0, "nothing without Shift")
    Stub.shift = true
    frame()
    eq(Bags.shown, 3, "Shift held: a figure on each slot with a price on the next frame, none on the rest or a hidden button")
    local byslot = {}
    for _, o in ipairs(Bags.overlays) do
      if o:IsShown() then byslot[o.bag .. ":" .. o.slot] = o end
    end
    local ore = byslot["0:1"]
    check(ore and ore.text:GetText() == H.MoneyCoin(oreFloor * 20) and ore.where == "house", "the ore's figure is its stack at the floor, in coin colors")
    check(ore and ore.bg.colorTexture and ore.bg.colorTexture[3] == Bags.HOUSE_STRIP[3], "on the house's strip")
    check(ore and not ore:IsMouseEnabled(), "and the figure takes no clicks")
    check(ore and ore.allPoints == _G.ContainerFrame1Item1, "laid over its own button")
    check(ore and ore:GetParent() == _G.ContainerFrame1Item1, "and set on it, so it draws on the button's layer")
    check(ore and ore:GetFrameLevel() == _G.ContainerFrame1Item1:GetFrameLevel() + 3, "a few levels above the button")
    check(byslot["1:5"] and byslot["1:5"].allPoints == b, "a modern button too")
    local same = fields(bag0) == frameBefore and fields(b) == modernBefore
    for i = 1, 4 do same = same and fields(_G["ContainerFrame1Item" .. i]) == buttonsBefore[i] end
    check(same, "nothing written on a bag frame or button")
    local junk = byslot["0:2"]
    check(junk and junk.where == "vendor" and junk.text:GetText() == H.MoneyCoin(15), "the junk's figure is the vendor's")
    check(junk and junk.bg.colorTexture and junk.bg.colorTexture[3] == Bags.VENDOR_STRIP[3], "on the vendor's strip")
    check(Bags.HOUSE_STRIP[3] ~= Bags.VENDOR_STRIP[3], "and the two strips differ")
    check(byslot["0:3"] == nil, "nothing on a slot with no price")
    check(byslot["1:5"] and byslot["1:5"].where == "vendor", "the modern frame's buttons are read by their bag")
    check(byslot["1:6"] == nil, "a hidden button gets no figure")

    -- a stack moved while Shift is held is followed on the next repaint
    Stub.SetBag(0, 3, 2770, 5)
    frame()
    eq(Bags.shown, 3, "not repainted every frame")
    frame(Bags.REFRESH)
    eq(Bags.shown, 4, "the repaint a moment later follows the bags")

    Stub.shift = false
    frame()
    eq(Bags.shown, 0, "Shift let go takes them down on the next frame")
    local up = 0
    for _, o in ipairs(Bags.overlays) do if o:IsShown() then up = up + 1 end end
    eq(up, 0, "every figure hidden")

    -- /hound overlay test: the figures up without Shift, and what they are drawn as
    Stub.printed = {}
    SlashCmdList.HOUND("overlay test")
    eq(Bags.shown, 4, "the test puts the figures up without Shift")
    local said = table.concat(Stub.printed, "\n")
    check(string.find(said, "4 figures up for 10 seconds", 1, true), "and says so: " .. said)
    check(string.find(said, "first figure, bag ", 1, true) and string.find(said, "its button: ", 1, true), "with how the first figure and its button are drawn")
    check(Bags.test and Bags.test.timer and Bags.test.timer.delay == Bags.TEST_SECONDS, "for a few seconds")
    frame(Bags.REFRESH)
    eq(Bags.shown, 4, "they stay up through the test without Shift")
    Stub.shift = true
    frame()
    Stub.shift = false
    frame()
    Stub.printed = {}
    Bags.test.timer.fn(Bags.test.timer)
    check(Bags.test == nil, "the test ends")
    eq(Bags.shown, 0, "and takes the figures down")
    check(string.find(Stub.printed[1] or "", "ran 4 times, and Shift was seen held", 1, true), "saying whether Hound's frame ran and saw Shift: " .. tostring(Stub.printed[1]))
    SlashCmdList.HOUND("overlay test")
    Stub.printed = {}
    Bags.EndTest()
    check(string.find(Stub.printed[1] or "", "was never seen held", 1, true), "or that it never saw Shift")

    -- what it sees, for /hound overlay
    Stub.printed = {}
    SlashCmdList.HOUND("overlay")
    said = table.concat(Stub.printed, "\n")
    check(string.find(said, "overlay is on", 1, true), "/hound overlay says it is on")
    check(string.find(said, "2 bag frames open, 5 slots read, 4 with a price", 1, true), "and what it sees: " .. said)

    -- off by command, and never in combat
    SlashCmdList.HOUND("overlay off")
    Stub.shift = true
    frame()
    eq(Bags.shown, 0, "off: nothing with Shift held")
    SlashCmdList.HOUND("overlay on")
    eq(Bags.shown, 4, "on again while Shift is held: the figures come up")
    check(string.find(Stub.printed[#Stub.printed] or "", "overlay is on", 1, true), "the command says so")
    Stub.combat = true
    frame()
    eq(Bags.shown, 0, "in combat they come down")
    frame(Bags.REFRESH)
    eq(Bags.shown, 0, "and stay down while Shift is held")
    Stub.combat = false
    frame()
    eq(Bags.shown, 4, "out of combat with Shift still held: back up")

    -- an error while painting is said once, and the figures stay down
    local realSlotValue = Bags.SlotValue
    Bags.SlotValue = function() error("boom") end
    Stub.printed = {}
    frame(Bags.REFRESH)
    eq(Bags.shown, 0, "an error takes the figures down")
    eq(#Stub.printed, 1, "and is said once")
    check(string.find(Stub.printed[1] or "", "boom", 1, true) and string.find(Stub.printed[1] or "", "overlay on", 1, true), "with the error and how to try again: " .. tostring(Stub.printed[1]))
    frame(Bags.REFRESH)
    eq(#Stub.printed, 1, "not again every frame")
    Stub.printed = {}
    SlashCmdList.HOUND("overlay")
    check(string.find(table.concat(Stub.printed, "\n"), "stopped on an error: ", 1, true), "/hound overlay repeats the error")
    Bags.SlotValue = realSlotValue
    SlashCmdList.HOUND("overlay on")
    eq(Bags.shown, 4, "/hound overlay on tries again")
    Stub.shift = false
    frame()
    eq(Bags.shown, 0, "and Shift let go takes them down")

    -- bags shut and a bag addon loaded: the report says so
    bag0:Hide()
    combined:Hide()
    local savedAddOns = C_AddOns
    C_AddOns = { IsAddOnLoaded = function(name) return name == "Baganator" end }
    Stub.printed = {}
    SlashCmdList.HOUND("overlay")
    said = table.concat(Stub.printed, "\n")
    check(string.find(said, "no Blizzard bag is open", 1, true), "/hound overlay with the bags shut says so")
    check(string.find(said, "Baganator", 1, true), "and names a bag addon that is loaded: " .. said)
    C_AddOns = savedAddOns

    _G.ContainerFrame1, _G.ContainerFrameCombinedBags = nil, nil
    for i = 1, 4 do _G["ContainerFrame1Item" .. i] = nil end
    Stub.bags = savedBags
  end

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
  SlashCmdList.HOUND("discount 25% 2s")
  near(H.Settings().minDiscount, 0.25, 0.0001, "discount setting with a percent sign")
  eq(H.Settings().minSaving, 200, "discount setting with a copper floor")
  SlashCmdList.HOUND("discount 0c")
  eq(H.Settings().minSaving, 0, "the copper floor cleared")
  SlashCmdList.HOUND("discount 30")
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

  -- the plan table shows each unit price to the copper
  local plan = H.UI.views.fan.planTbl
  plan:Layout()
  plan:Refresh(true)
  local b2 = H.Fan.plan.batches[2]
  check(b2 and b2.unit % 100 ~= 0, "second batch carries copper: " .. tostring(b2 and b2.unit))
  eq(plan.rows[2].cells[2].text, H.MoneyExact(b2.unit), "unit cell shows the exact price")
  check(not string.find(plan.rows[2].cells[2].text, "%."), "unit cell has no rounded gold")

  -- money cells only give up precision when the column has no room
  local fs = CreateFrame("Frame"):CreateFontString()
  H.UI.SetMoney(fs, 4599, 66)
  eq(fs.text, "45s 99c", "exact when it fits")
  H.UI.SetMoney(fs, 12345678, 66)
  eq(fs.text, "1234g 56s", "copper dropped when the exact form is too wide")
  H.UI.SetMoney(fs, 4599, 30)
  eq(fs.text, "45s", "short form when nothing else fits")
  H.UI.SetMoney(fs, 12345678, 40)
  eq(fs.text, "1235g", "short form for wide gold in a narrow column")
  H.UI.SetMoney(fs, -12345678, 66)
  eq(fs.text, "-1234g 56s", "negative money drops copper the same way")
  H.UI.SetMoney(fs, 12345678, nil)
  eq(fs.text, "1234g 56s 78c", "no width, no rounding")
  ok, err = pcall(H.Events.Fire, H.Events, "FAN_UPDATED")
  check(ok, "fan refresh: " .. tostring(err))
  ok, err = pcall(Stub.FireEvent, "BAG_UPDATE_DELAYED")
  check(ok, "fan bag refresh: " .. tostring(err))
  ok, err = pcall(H.UI.ShowItem, "2770")
  check(ok, "item view with sales: " .. tostring(err))
  H.Fan.Reset()
  ok, err = pcall(H.Events.Fire, H.Events, "SCAN_DONE", "full")
  check(ok, "scan done refresh: " .. tostring(err))
  ok, err = pcall(H.UI.UpdateStatus)
  check(ok, "status: " .. tostring(err))

  -- auction house tab hook with a fake Blizzard frame. The tab stays
  -- out of the frame's tab list, count and modes: a value an addon
  -- writes there taints the frame's own code (see UI/Frame.lua).
  AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
  AuctionHouseFrame.Tabs = { CreateFrame("Button"), CreateFrame("Button"), CreateFrame("Button") }
  AuctionHouseFrame.displayMode = nil
  AuctionHouseFrame.numTabs = 3
  AuctionHouseFrame.selectedTab = 1
  local buyMode = { "SearchBar" }
  local sellMode = { "ItemSellFrame" }
  AuctionHouseFrame.tabsForDisplayMode = { [buyMode] = 1, [sellMode] = 2 }
  function AuctionHouseFrame:SetDisplayMode(mode)
    if self.displayMode == mode then return end
    self.displayMode = mode
    local tab = self.tabsForDisplayMode[mode]
    if tab then PanelTemplates_SetTab(self, tab) end
  end
  local numTabsCalls = 0
  PanelTemplates_SetNumTabs = function(frame, n) numTabsCalls = numTabsCalls + 1 frame.numTabs = n end
  PanelTemplates_SelectTab = function(tab) tab.lit = true end
  PanelTemplates_DeselectTab = function(tab) tab.lit = false end
  PanelTemplates_UpdateTabs = function(frame)
    for i = 1, frame.numTabs do
      if i == frame.selectedTab then PanelTemplates_SelectTab(frame.Tabs[i]) else PanelTemplates_DeselectTab(frame.Tabs[i]) end
    end
  end
  PanelTemplates_SetTab = function(frame, id) frame.selectedTab = id PanelTemplates_UpdateTabs(frame) end
  -- the frame's own content in a mode of its own: a results frame
  -- with its list, scroll box and cells, each a level deeper
  local results = CreateFrame("Frame", nil, AuctionHouseFrame)
  local cells = CreateFrame("Frame", nil, CreateFrame("Frame", nil, CreateFrame("Frame", nil, results)))
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "auction house hook: " .. tostring(err))
  eq(#AuctionHouseFrame.Tabs, 3, "the frame's tab list is left alone")
  eq(AuctionHouseFrame.numTabs, 3, "the frame's tab count is left alone")
  eq(numTabsCalls, 0, "the frame's tab count is never set by the addon")
  local modes = 0
  for _ in pairs(AuctionHouseFrame.tabsForDisplayMode) do modes = modes + 1 end
  eq(modes, 2, "no mode of ours in the frame's mode table")
  eq(rawget(AuctionHouseFrame, "HoundFrame"), nil, "nothing of ours written on the frame")
  check(H.UI.ahTab ~= nil and H.UI.ahTab.parent == AuctionHouseFrame, "hound tab built inside the frame")
  check(H.UI.ahTab and H.UI.ahTab:GetScript("OnClick") ~= nil, "hound tab answers its own click")
  AuctionHouseFrame:SetDisplayMode(buyMode)
  H.UI.ahTab:Click()
  check(AuctionHoundPanel.shown, "panel shown in the auction house")
  check(AuctionHoundPanel.parent and AuctionHoundPanel.parent.parent == AuctionHouseFrame, "panel seated inside the frame")
  eq(AuctionHouseFrame.displayMode, buyMode, "the frame's own mode is untouched by the hound tab")
  eq(AuctionHouseFrame.selectedTab, 1, "the frame's own selection is untouched by the hound tab")
  check(H.UI.ahTab.lit, "hound tab lit")
  check(not AuctionHouseFrame.Tabs[1].lit, "buy tab dimmed while hound is up")
  local hp = AuctionHoundPanel.header.points
  eq(hp[#hp - 1][1], "TOPLEFT", "header anchored at the top left")
  eq(hp[#hp - 1][4], H.UI.AH_INSETS.header, "header starts clear of the portrait")
  -- the frame's own mode stays up underneath, untouched: the seat sits
  -- above its deepest cells and a solid cover under the panel takes
  -- the view and the mouse, the portrait's corner left alone
  local seat = AuctionHoundPanel.parent
  check(results.shown, "the frame's own frames are neither hidden nor moved")
  eq(#results.points, 0, "nor anchored anew")
  check(seat:GetFrameLevel() > cells:GetFrameLevel(), "the seat sits above the frame's deepest cells")
  eq(seat:GetFrameLevel(), AuctionHouseFrame:GetFrameLevel() + H.UI.AH_LEVELS, "by the levels set aside")
  local cover = AuctionHoundCover
  check(cover and cover.parent == seat, "a cover sits on the seat")
  eq(cover:GetFrameLevel(), seat:GetFrameLevel() + 1, "just above it")
  eq(AuctionHoundPanel:GetFrameLevel(), cover:GetFrameLevel() + 1, "with the panel above the cover")
  check(cover:IsMouseEnabled(), "the cover takes the mouse")
  eq(cover.points[1][4], H.UI.AH_INSETS.left, "the cover starts at the panel's left inset")
  eq(cover.points[1][5], -H.UI.AH_INSETS.top, "and its top inset")
  eq(cover.points[2][4], -H.UI.AH_INSETS.right, "to its right inset")
  eq(cover.points[2][5], H.UI.AH_INSETS.bottom, "and its bottom inset")
  eq(cover.top.points[1][4], H.UI.AH_INSETS.header, "the header strip starts clear of the portrait")
  eq(cover.top.points[2][5], -H.UI.BODY_TOP, "and ends where the body starts")
  eq(cover.body.points[1][5], -H.UI.BODY_TOP, "the body cover starts under the portrait")
  eq(cover.body.points[1][4], 0, "at the panel's left edge")
  -- the frame's own tab clicked for the mode it is already in
  AuctionHouseFrame:SetDisplayMode(buyMode)
  check(not AuctionHoundPanel.shown, "panel hidden on the frame's own tab")
  check(not seat.shown, "the cover goes down with the seat")
  check(results.shown, "and the frame's own frames were never touched")
  check(not H.UI.ahTab.lit, "hound tab dimmed again")
  check(AuctionHouseFrame.Tabs[1].lit, "buy tab lit again")
  -- a mode change of the frame's own, as a bag item or a browse row makes
  H.UI.ahTab:Click()
  check(AuctionHoundPanel.shown, "panel shown again")
  AuctionHouseFrame:SetDisplayMode(sellMode)
  check(not AuctionHoundPanel.shown, "panel hidden on a mode change")
  eq(AuctionHouseFrame.selectedTab, 2, "sell tab selected by the frame")
  check(AuctionHouseFrame.Tabs[2].lit and not AuctionHouseFrame.Tabs[1].lit, "sell tab lit, buy tab dimmed")
  -- the window and the tab do not show at once
  H.UI.ahTab:Click()
  H.UI.Toggle()
  check(AuctionHoundWindow.shown and AuctionHoundPanel.parent == AuctionHoundWindow, "window takes the panel from the house")
  eq(AuctionHoundPanel:GetFrameLevel(), AuctionHoundWindow:GetFrameLevel() + 2, "seated above the window's own pieces")
  AuctionHouseFrame:SetDisplayMode(buyMode)
  H.UI.ahTab:Click()
  check(not AuctionHoundWindow.shown, "hound tab closes the window")
  AuctionHouseFrame:SetDisplayMode(sellMode)

  -- Escape closes the window without a line in UISpecialFrames
  eq(#UISpecialFrames, 0, "no line of ours in UISpecialFrames")
  if not AuctionHoundWindow.shown then H.UI.Toggle() end
  check(AuctionHoundWindow.shown, "window up")
  check(AuctionHoundWindow.keyboard == true and AuctionHoundWindow.propagate == true, "window reads keys and passes them on")
  AuctionHoundWindow.scripts.OnKeyDown(AuctionHoundWindow, "A")
  eq(AuctionHoundWindow.propagate, true, "another key passes on")
  AuctionHoundWindow.scripts.OnKeyDown(AuctionHoundWindow, "ESCAPE")
  check(not AuctionHoundWindow.shown, "escape closes the window")
  check(AuctionHoundWindow.propagate == false and AuctionHoundWindow.keyboard == false, "escape used up, keyboard let go")
  -- in combat the key is left alone
  Stub.combat = true
  H.UI.Toggle()
  check(AuctionHoundWindow.shown and AuctionHoundWindow.keyboard == false, "shown in combat without the keyboard")
  AuctionHoundWindow.scripts.OnKeyDown(AuctionHoundWindow, "ESCAPE")
  check(AuctionHoundWindow.shown, "escape does nothing in combat")
  Stub.combat = false
  Stub.FireEvent("PLAYER_REGEN_ENABLED")
  check(AuctionHoundWindow.keyboard == true and AuctionHoundWindow.propagate == true, "keyboard taken back after combat")
  H.UI.Toggle()
  check(not AuctionHoundWindow.shown, "window down")

  -- template missing: tab creation fails gracefully
  H.UI.ahHooked = false
  Stub.badTemplates = { AuctionHouseFrameDisplayModeTabTemplate = true, PanelTabButtonTemplate = true, CharacterFrameTabButtonTemplate = true }
  Stub.printed = {}
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "hook survives a missing template: " .. tostring(err))
  check(string.find(Stub.printed[#Stub.printed] or "", "could not add"), "missing template reported")
end

------------------------------------------------------------------------
-- Buy tab: the Hound column and filter strip
------------------------------------------------------------------------
do
  Stub.badTemplates = nil
  local Browse = H.Browse
  H.atAH = true
  H.Settings().minDiscount = 0.25
  Browse.Invalidate()
  Stub.DefineItem(90001, "Plain Widget", { sell = 0, commodity = true })
  Stub.DefineItem(90002, "Vendor Widget", { sell = 1000, commodity = true })

  local refOre, srcOre = H.Reference("2770", 2770)
  check(refOre and refOre > 0, "copper ore has a reference")
  eq(srcOre, "market", "copper ore's reference is history")
  local function ore(frac, extra)
    local row = { itemKey = C_AuctionHouse.MakeItemKey(2770), minPrice = H.Round(refOre * frac), totalQuantity = 40 }
    for k, v in pairs(extra or {}) do row[k] = v end
    return row
  end
  local half, tenOff, over = ore(0.5), ore(0.9), ore(1.2)
  local none = { itemKey = C_AuctionHouse.MakeItemKey(90001), minPrice = 500, totalQuantity = 3 }
  local vendorRow = { itemKey = C_AuctionHouse.MakeItemKey(90002), minPrice = 800, totalQuantity = 3 }
  local mineRow = ore(0.4, { containsOwnerItem = true })
  local empty = { itemKey = C_AuctionHouse.MakeItemKey(2771), minPrice = 0, totalQuantity = 0 }

  -- reading one row
  local e = Browse.Evaluate(half)
  eq(e.key, "2770", "row keyed by item id")
  near(e.disc, 0.5, 0.02, "half the reference is 50% off")
  check(e.deal and e.history, "half price is a deal with history")
  local note, figure, color = Browse.CellText(e)
  eq(figure, "-50%", "cell figure is the discount")
  eq(note, H.MoneyShort(refOre), "cell note is the reference")
  eq(color, Browse.COLORS.deal, "deal colored green")
  e = Browse.Evaluate(tenOff)
  check(not e.deal, "ten percent off is not a deal at a 25% minimum")
  eq(select(3, Browse.CellText(e)), Browse.COLORS.under, "under reference colored amber")
  e = Browse.Evaluate(over)
  eq(select(2, Browse.CellText(e)), "+20%", "above reference reads as a premium")
  eq(select(3, Browse.CellText(e)), Browse.COLORS.over, "above reference colored grey")
  e = Browse.Evaluate(none)
  check(e.ref == nil and not e.deal, "unknown item has no reference")
  eq(select(1, Browse.CellText(e)), "no reference", "unknown item says so")
  e = Browse.Evaluate(vendorRow)
  check(e.vendorFlip and e.deal and not e.history, "under vendor is a deal without history")
  eq(e.refSrc, "vendor", "vendor price stands in as the reference")
  eq(select(1, Browse.CellText(e)), "vendor 10s", "vendor reference labelled")
  eq(select(2, Browse.CellText(e)), "-20%", "discount off the vendor price")
  e = Browse.Evaluate(mineRow)
  check(e.deal and e.mine, "own listing still evaluated")
  -- the house's browse rows carry an item level even for ore: the row
  -- still meets the history the scan keyed by item ID
  local leveled = { itemKey = C_AuctionHouse.MakeItemKey(2770, 10), minPrice = half.minPrice, totalQuantity = 40 }
  e = Browse.Evaluate(leveled)
  eq(e.key, "2770", "a row with an item level is keyed by item id")
  Stub.ah.browse, Stub.ah.browseServed = { leveled }, 1
  Stub.printed = {}
  SlashCmdList.HOUND("debug buy 3")
  local dbg = table.concat(Stub.printed, "\n")
  check(string.find(dbg, "level=10", 1, true) and string.find(dbg, "key=2770 stored=true", 1, true),
    "debug buy shows the house's level and the history key: " .. dbg)
  Stub.ah.browse, Stub.ah.browseServed = {}, 0
  check(e.history and e.ref == refOre, "and judged by the ore's history")
  check(e.deal, "half price with an item level is still a deal")
  eq(select(1, Browse.CellText(e)), H.MoneyShort(refOre), "its note is the reference")
  eq(select(2, Browse.CellText(Browse.Evaluate(empty))), "", "no units, no figure")
  eq(Browse.Evaluate({}), nil, "row without a key reads as nil")
  -- a floor that has filled in at a new low is the price from the next
  -- scan on; a stray under the rest is still a deal
  local wallRow = { itemKey = C_AuctionHouse.MakeItemKey(90030), minPrice = 60, totalQuantity = 200 }
  local strayLow = { itemKey = C_AuctionHouse.MakeItemKey(90031), minPrice = 60, totalQuantity = 201 }
  e = Browse.Evaluate(wallRow)
  check(e.history and not e.deal, "a wall at a new low is no deal against the latest scan")
  near(e.disc, 0, 1e-9, "its floor sits at the reference")
  eq(select(1, Browse.CellText(e)), H.MoneyShort(60), "the note is the latest scan's value")
  eq(select(3, Browse.CellText(e)), Browse.COLORS.over, "and the cell is grey")
  e = Browse.Evaluate(strayLow)
  check(e.deal, "a stray under the rest is a deal")
  near(e.disc, 0.4, 0.01, "forty percent under")

  -- the index
  local rows = { half, tenOff, over, none, vendorRow, mineRow, empty }
  local function getRow(i) return rows[i] end
  local idx = Browse.BuildIndex(#rows, getRow, {})
  eq(#idx, 7, "nothing on keeps every row")
  eq(idx[7], 7, "nothing on keeps the order")
  idx = Browse.BuildIndex(#rows, getRow, { sort = true })
  eq(table.concat(idx, ","), "6,1,5,2,3,4,7", "sorted: deals by discount, then under, over, none, empty")
  idx = Browse.BuildIndex(#rows, getRow, { deals = true })
  eq(table.concat(idx, ","), "1,5,6", "deals only")
  idx = Browse.BuildIndex(#rows, getRow, { deals = true, notMine = true })
  eq(table.concat(idx, ","), "1,5", "deals that are not mine")
  idx = Browse.BuildIndex(#rows, getRow, { history = true })
  eq(table.concat(idx, ","), "1,2,3,6,7", "history only drops the vendor and unknown rows")
  check(not Browse.Active({}), "no toggles: inactive")
  check(Browse.Active({ browseDeals = true }), "a toggle: active")

  -- the frame hook, with a fake Blizzard browse frame
  AuctionHouseFrame.BrowseResultsFrame = Stub.NewBrowseFrame()
  local br = AuctionHouseFrame.BrowseResultsFrame
  local BUI = H.UI.Browse
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "buy tab hook: " .. tostring(err))
  check(BUI.installed and BUI.strip ~= nil, "filter strip built")
  local lp = br.ItemList.points[#br.ItemList.points]
  eq(lp[1], "TOPLEFT", "list re-anchored at its top")
  eq(lp[5], -(BUI.STRIP_HEIGHT + 1), "list starts below the strip")
  eq(br.ItemList.Background.height, 414 - BUI.STRIP_HEIGHT - 1, "background shortened to match")
  eq(BUI.strip.min.text, "25", "minimum box shows the setting")

  -- a full result set arrives: the column shows on every row, before the star
  Stub.ah.browsePageSize = 10
  Stub.ah.browse = rows
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  local r = br.ItemList:Render()
  eq(#r.columns, 5, "hound column added")
  eq(r.columns[4].header, "Hound", "hound column sits before the star")
  eq(r.columns[5].template, "AuctionHouseTableCellFavoriteTemplate", "star keeps the edge")
  eq(#r.rows, 7, "every row shown with nothing toggled")
  hover(r, "buy tab")
  local cell = r.rows[1][4]
  eq(cell.Text.text, "-50%", "cell shows the discount")
  eq(cell.Sub.text, H.MoneyShort(refOre), "cell shows the reference")
  eq(cell.Text.color and cell.Text.color[2], Browse.COLORS.deal[2], "deal cell green")
  eq(r.rows[4][4].Sub.text, "no reference", "unknown item cell says so")
  eq(r.rows[5][4].Sub.text, "vendor 10s", "vendor cell labelled")
  eq(BUI.strip.status.text, "7 rows", "status counts rows")

  -- the category layout is rebuilt with an extra column: ours follows it
  br:SetupTableBuilder("Level")
  r = br.ItemList:Render()
  eq(#r.columns, 6, "hound column survives a relayout")
  eq(r.columns[5].header, "Hound", "still before the star after a relayout")
  br:SetupTableBuilder(nil)

  -- toggles filter and sort through the data provider
  BUI.strip.deals:SetChecked(true)
  BUI.strip.deals.scripts.OnClick(BUI.strip.deals)
  eq(H.Settings().browseDeals, true, "deals toggle saved")
  eq(br.ItemList.getNumEntries(), 3, "deals only through the provider")
  eq(br.ItemList.getEntry(2), vendorRow, "provider maps through the index")
  check(br.ItemList.dirty, "list marked for refresh")
  eq(BUI.strip.status.text, "3 of 7", "status counts the filtered rows")
  H.Settings().browseNotMine = true
  BUI.Rebuild()
  eq(br.ItemList.getNumEntries(), 2, "not mine drops the own listing")
  H.Settings().browseDeals, H.Settings().browseNotMine = false, false
  H.Settings().browseSort = true
  BUI.Rebuild()
  eq(br.ItemList.getEntry(1), mineRow, "sorted: biggest discount first")
  eq(br.ItemList.getEntry(7), empty, "sorted: empty key last")
  -- a search starts and Blizzard's rows empty out: the stale index steps aside
  br.browseResults = {}
  eq(br.ItemList.getNumEntries(), 0, "stale index ignored while a search is out")
  br:UpdateBrowseResults()
  eq(br.ItemList.getNumEntries(), 7, "index rebuilt with the results")

  -- the minimum box re-evaluates
  BUI.strip.min:SetText("60")
  BUI.strip.min.scripts.OnTextChanged(BUI.strip.min)
  eq(H.Settings().minDiscount, 0.6, "minimum box sets the discount")
  check(not Browse.Evaluate(half).deal, "half price is no deal at a 60% minimum")
  SlashCmdList.HOUND("discount 25")
  eq(BUI.strip.min.text, "25", "slash command updates the box")
  check(Browse.Evaluate(half).deal, "half price is a deal again")

  -- the copper minimum: a deal must also sit that far under the
  -- reference in copper a unit, so a one-silver item at half price is
  -- fifty percent off and still no deal
  H.Settings().browseSort = false
  BUI.Rebuild()
  eq(BUI.strip.saving.text, "0c", "copper box shows no floor")
  e = Browse.Evaluate(half)
  eq(e.saving, 50, "saving is the copper a unit under the reference")
  BUI.strip.saving:SetText("1s")
  BUI.strip.saving.scripts.OnTextChanged(BUI.strip.saving)
  eq(H.Settings().minSaving, 100, "copper box sets the minimum")
  e = Browse.Evaluate(half)
  check(not e.deal and e.small, "half price is no deal at 50c a unit under a 1s minimum")
  eq(select(2, Browse.CellText(e)), "-50%", "the figure still reads the percentage")
  eq(select(3, Browse.CellText(e)), Browse.COLORS.under, "and the row is amber")
  check(Browse.Evaluate(vendorRow).deal, "two silver under vendor clears it and stays a deal")
  eq(table.concat(Browse.BuildIndex(#rows, getRow, { deals = true }), ","), "5", "deals only drops the rows short of the copper minimum")
  r = br.ItemList:Render()
  eq(r.rows[1][4].Text.color and r.rows[1][4].Text.color[2], Browse.COLORS.under[2], "the cell turns amber")
  GameTooltip:ClearLines()
  r.rows[1][4]:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "50% under, but only 50c a unit; the minimum is 1s", 1, true),
    "the cell tooltip names the copper minimum: " .. table.concat(GameTooltip.lines, " | "))
  r.rows[1][4]:OnLeave()
  GameTooltip:ClearLines()
  BUI.strip.saving.scripts.OnEnter(BUI.strip.saving)
  check(string.find(table.concat(GameTooltip.lines, "\n"), "Minimum in copper", 1, true), "the box explains itself on hover")
  BUI.strip.saving.scripts.OnLeave(BUI.strip.saving)
  SlashCmdList.HOUND("discount 25 3s")
  eq(H.Settings().minSaving, 300, "slash command sets the copper minimum")
  eq(BUI.strip.saving.text, "3s", "and the box follows")
  e = Browse.Evaluate(vendorRow)
  check(not e.deal and e.small, "the vendor flip is no deal under a 3s minimum")
  Stub.printed = {}
  SlashCmdList.HOUND("discount")
  check(string.find(Stub.printed[1] or "", "25% or 3s a unit, whichever is more", 1, true), "the command reads both back: " .. tostring(Stub.printed[1]))
  Stub.printed = {}
  SlashCmdList.HOUND("discount 40 bogus")
  check(string.find(Stub.printed[1] or "", "usage", 1, true), "a bad token prints the usage")
  eq(H.Settings().minSaving, 300, "and changes nothing")
  near(H.Settings().minDiscount, 0.25, 0.0001, "not the percentage either")
  SlashCmdList.HOUND("discount 0c")
  eq(H.Settings().minSaving, 0, "0c clears the copper minimum")
  eq(BUI.strip.saving.text, "0c", "box shows no floor again")
  check(Browse.Evaluate(half).deal, "half price is a deal once more")
  H.Settings().browseSort = true
  BUI.Rebuild()

  -- with a toggle on, the remaining pages come in on their own
  Stub.ah.browsePageSize = 2
  C_AuctionHouse.SendBrowseQuery({})
  for _ = 1, 8 do Stub.Advance(1) Stub.Pump() end
  eq(Stub.ah.browseServed, 7, "all pages fetched with a toggle on")
  eq(BUI.pages, 3, "three more pages counted")
  eq(BUI.strip.status.text, "7 of 7", "status settles once full")
  -- with nothing on, the list waits for a scroll as before
  H.Settings().browseSort = false
  C_AuctionHouse.SendBrowseQuery({})
  for _ = 1, 4 do Stub.Advance(1) Stub.Pump() end
  eq(Stub.ah.browseServed, 2, "no fetching with nothing toggled")
  eq(BUI.strip.status.text, "2 rows", "status counts the first page")
  -- throttled: the request waits for the ready event
  H.Settings().browseSort = true
  Stub.ah.ready = false
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  eq(Stub.ah.browseServed, 2, "request held while throttled")
  check(string.find(BUI.strip.status.text, "loading more", 1, true), "status says it is loading")
  Stub.ah.ready = true
  Stub.FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  for _ = 1, 8 do Stub.Advance(1) Stub.Pump() end
  eq(Stub.ah.browseServed, 7, "held request sent when ready")
  -- a dropped request is asked for again once the system is ready
  local realMore = C_AuctionHouse.RequestMoreBrowseResults
  local drops = 0
  C_AuctionHouse.RequestMoreBrowseResults = function()
    drops = drops + 1
    C_AuctionHouse.RequestMoreBrowseResults = realMore
    Stub.ah.ready = false
    C_Timer.After(1, function() Stub.FireEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED") end)
  end
  C_AuctionHouse.SendBrowseQuery({})
  for _ = 1, 3 do Stub.Advance(1) Stub.Pump() end
  eq(drops, 1, "the first page request was dropped")
  eq(Stub.ah.browseServed, 2, "dropped request waits for the ready event")
  Stub.ah.ready = true
  Stub.FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  for _ = 1, 8 do Stub.Advance(1) Stub.Pump() end
  eq(Stub.ah.browseServed, 7, "dropped request asked for again")
  eq(H.Scan.state, "idle", "the scanner did not replay an old query")
  -- the page cap
  H.Settings().snipePages = 1
  C_AuctionHouse.SendBrowseQuery({})
  for _ = 1, 8 do Stub.Advance(1) Stub.Pump() end
  eq(Stub.ah.browseServed, 4, "stops at the page cap")
  check(string.find(BUI.strip.status.text, "stopped at 1 pages", 1, true), "status reports the cap: " .. BUI.strip.status.text)
  H.Settings().snipePages = 40
  -- the browse frame hidden (a row was clicked): no fetching until it shows again
  br:Hide()
  C_AuctionHouse.SendBrowseQuery({})
  for _ = 1, 4 do Stub.Advance(1) Stub.Pump() end
  eq(Stub.ah.browseServed, 2, "no fetching while the list is hidden")
  br:Show()
  for _ = 1, 8 do Stub.Advance(1) Stub.Pump() end
  eq(Stub.ah.browseServed, 7, "fetching resumes when the list shows")
  H.Settings().browseSort = false
  BUI.Rebuild()
end

------------------------------------------------------------------------
-- Sat: a floor the scans have kept seeing at its price for an hour or
-- more has been passed over; it is under the reference, not a deal
------------------------------------------------------------------------
do
  local Browse, S = H.Browse, H.Settings()
  local br = AuctionHouseFrame.BrowseResultsFrame
  eq(S.satHours, 1, "sat defaults to an hour")
  Stub.DefineItem(90032, "Sitting Widget", { sell = 0, commodity = true })
  -- ten days at 1s, then three units at 50c that the last seven scans,
  -- over ninety minutes, all saw sitting under the rest at 1s
  for d = 10, 1, -1 do
    Store.AddScanSample("90032", Stub.now - d * 86400, { { p = 100, q = 200 } })
  end
  for i = 6, 0, -1 do
    Store.AddScanSample("90032", Stub.now - i * 900, { { p = 50, q = 3 }, { p = 100, q = 200 } })
  end
  Browse.Invalidate()
  eq((H.Reference("90032", 90032)), 100, "three units at half price leave the reference at 1s")
  local rec = Store.Get("90032")
  local age, scans = H.Market.FloorAge(rec, 50)
  eq(age, 6 * 900, "the floor has been on offer since the first of the seven scans")
  eq(scans, 7, "over seven scans")
  eq((H.Market.FloorAge(rec, 51)), 6 * 900, "a copper's undercut is the same floor")
  age, scans = H.Market.FloorAge(rec, 40)
  eq(age, 0, "a floor under it is new since the last scan")
  eq(scans, 0, "seen by no scan")
  eq(H.Market.FloorAge(nil, 50), nil, "no record, no age")

  local sat = { itemKey = C_AuctionHouse.MakeItemKey(90032), minPrice = 50, totalQuantity = 203 }
  local fresh = { itemKey = C_AuctionHouse.MakeItemKey(90032), minPrice = 40, totalQuantity = 203 }
  local e = Browse.Evaluate(sat)
  near(e.disc, 0.5, 0.01, "half off the reference")
  check(e.sat and not e.deal, "but it has sat for ninety minutes: no deal")
  eq(select(3, Browse.CellText(e)), Browse.COLORS.under, "amber, not green")
  eq(select(2, Browse.CellText(e)), "-50%", "the figure still shows the discount")
  check(string.find(Browse.FloorLine(e), "on offer 1.5h over 7 scans: not a deal", 1, true),
    "the floor line says why: " .. Browse.FloorLine(e))
  e = Browse.Evaluate(fresh)
  check(e.new and e.deal and not e.sat, "a floor under it since the last scan is new, and a deal")
  check(string.find(Browse.FloorLine(e), "new since the scan", 1, true), "and the floor line says so: " .. Browse.FloorLine(e))
  eq(select(3, Browse.CellText(e)), Browse.COLORS.deal, "green")
  local pair = { sat, fresh }
  local function getRow(i) return pair[i] end
  eq(table.concat(Browse.BuildIndex(2, getRow, { sort = true }), ","), "2,1", "sorted, the fresh deal comes first")
  eq(#Browse.BuildIndex(2, getRow, { deals = true }), 1, "deals only drops the sitting floor")

  -- the cell tooltip on the Buy tab, with what has been seen to sell
  Store.AddFills("90032", Stub.now, 40, 40 * 100)
  Browse.Invalidate()
  Stub.ah.browse, Stub.ah.browseServed = { sat }, 1
  br:UpdateBrowseResults()
  local r = br.ItemList:Render()
  eq(r.rows[1][4].Text.color and r.rows[1][4].Text.color[1], Browse.COLORS.under[1], "the cell is amber")
  GameTooltip:ClearLines()
  r.rows[1][4]:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "on offer", 1, true), "the tooltip says the floor has sat")
  check(string.find(table.concat(GameTooltip.lines, "\n"), "cleared ~6 a day at", 1, true),
    "and what has cleared, forty units over the week's seven scan days: " .. table.concat(GameTooltip.lines, " | "))
  r.rows[1][4]:OnLeave()

  -- the buy frame's ladder reads the same age
  local listings = { { p = 50, q = 3 }, { p = 100, q = 200 } }
  local L = H.Ladder.Build(listings, "90032", 90032)
  check(L.sat, "the ladder reads the floor's age")
  eq(H.Ladder.Verdict(L, 50), "under", "a sitting floor is under, not a deal, on the buy frame")
  check(string.find(H.Ladder.Lines(L)[2], "on offer", 1, true), "and its line says why: " .. H.Ladder.Lines(L)[2])

  -- the hours are a setting
  SlashCmdList.HOUND("sat 2")
  eq(S.satHours, 2, "the sat command sets the hours")
  check(Browse.Evaluate(sat).deal, "at two hours, ninety minutes is still a deal")
  SlashCmdList.HOUND("sat 0")
  check(string.find(Stub.printed[#Stub.printed], "sat is off", 1, true), "and says when it is off")
  e = Browse.Evaluate(sat)
  check(e.deal and not e.sat, "off: judged by price alone")
  L = H.Ladder.Build(listings, "90032", 90032)
  eq(H.Ladder.Verdict(L, 50), "deal", "on the buy frame too")
  SlashCmdList.HOUND("sat 1")
  check(not Browse.Evaluate(sat).deal, "and back")

  -- a floor under the vendor price is a deal however long it sat
  Stub.DefineItem(90033, "Sitting Vendor Widget", { sell = 1000, commodity = true })
  for i = 6, 0, -1 do
    Store.AddScanSample("90033", Stub.now - i * 900, { { p = 800, q = 2 }, { p = 1500, q = 50 } })
  end
  Browse.Invalidate()
  e = Browse.Evaluate({ itemKey = C_AuctionHouse.MakeItemKey(90033), minPrice = 800, totalQuantity = 52 })
  check(e.sat and e.vendorFlip and e.deal, "a vendor flip never sits")
  L = H.Ladder.Build({ { p = 800, q = 2 }, { p = 1500, q = 50 } }, "90033", 90033)
  eq(H.Ladder.Verdict(L, 800), "deal", "on the buy frame too")
  check(not string.find(H.Ladder.Lines(L)[2], "not a deal", 1, true), "and the line does not say otherwise")
end

------------------------------------------------------------------------
-- Estimates off: the reference is history alone
------------------------------------------------------------------------
do
  local Browse, S = H.Browse, H.Settings()
  local br, BUI = AuctionHouseFrame.BrowseResultsFrame, H.UI.Browse
  Stub.DefineItem(2319, "Medium Leather", { sell = 40, commodity = true })
  -- light leather has ten days at 3s, so medium leather costs 12s to
  -- make; its own price has settled at 7s, but one scan is too thin
  -- to trust, so the crafted cost calls it a deal
  Store.AddScanSample("2319", Stub.now, { { p = 700, q = 200 } })
  Browse.Invalidate()
  eq(S.estimates, true, "estimates on by default")
  eq((P.CraftCost(2319)), 1200, "medium leather costs four light leather")
  local ref, src, conf = H.Reference("2319", 2319)
  eq(ref, 1200, "thin history: the crafted cost is the reference")
  eq(src, "prior:crafted cost", "and says so")
  local row = { itemKey = C_AuctionHouse.MakeItemKey(2319), minPrice = 700, totalQuantity = 40 }
  local e = Browse.Evaluate(row)
  check(e.deal and not e.history, "the settled price reads as a deal against the crafted cost")
  eq(select(1, Browse.CellText(e)), "~" .. H.MoneyShort(1200), "the note marks the estimate")
  eq(select(2, Browse.CellText(e)), "-42%", "and the discount off it")
  Stub.ah.browse = { row }
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  local r = br.ItemList:Render()
  GameTooltip:ClearLines()
  r.rows[1][4]:OnEnter()
  local tip = table.concat(GameTooltip.lines, "\n")
  check(string.find(tip, "estimate: crafted cost", 1, true), "tooltip names the estimate: " .. tip)
  check(string.find(tip, "untick estimates", 1, true), "tooltip points at the toggle")
  r.rows[1][4]:OnLeave()

  -- off by command: the row is judged by its own thin history
  SlashCmdList.HOUND("estimates off")
  eq(S.estimates, false, "command turns estimates off")
  check(string.find(Stub.printed[#Stub.printed], "estimates are off", 1, true), "and says so")
  eq(P.Estimate(2319), nil, "no estimate while off")
  ref, src, conf = H.Reference("2319", 2319)
  eq(ref, 700, "off: thin history is the reference")
  eq(src, "market", "and counts as history")
  check(conf < 0.3, "with its low confidence")
  e = Browse.Evaluate(row)
  check(not e.deal and e.history, "the settled price is no deal against its own history")
  near(e.disc, 0, 1e-9, "the floor sits at reference")
  eq(select(1, Browse.CellText(e)), H.MoneyShort(700), "the note loses the estimate mark")
  r = br.ItemList:Render()
  eq(r.rows[1][4].Sub.text, H.MoneyShort(700), "the cell followed without a scan")
  eq(H.Reference("2934", 2934), nil, "off: nothing scanned means no reference")
  local leveledLeather = { itemKey = C_AuctionHouse.MakeItemKey(2319, 15), minPrice = 700, totalQuantity = 40 }
  e = Browse.Evaluate(leveledLeather)
  check(e.history and e.ref == 700, "off: a row with an item level still finds its history")
  -- history older than the market value's two weeks still counts
  Stub.DefineItem(90010, "Old Widget", { sell = 0, commodity = true })
  Stub.DefineItem(90011, "Ancient Widget", { sell = 0, commodity = true })
  Store.AddScanSample("90010", Stub.now - 20 * 86400, { { p = 3000, q = 10 } })
  Store.AddScanSample("90011", Stub.now - 45 * 86400, { { p = 5000, q = 10 } })
  ref, src, conf = H.Reference("90010", 90010)
  eq(ref, 3000, "off: twenty-day-old history is the reference")
  eq(src, "market", "and counts as history")
  eq(conf, 0, "with no confidence")
  eq((H.Reference("90011", 90011)), 5000, "off: the last scan's value when nothing is within thirty days")
  check(string.find(H.ReferenceSource(src, select(4, H.Reference("90010", 90010))), "last scanned 20d ago", 1, true),
    "the source says how old: " .. H.ReferenceSource(src, select(4, H.Reference("90010", 90010))))
  Browse.Invalidate()
  e = Browse.Evaluate({ itemKey = C_AuctionHouse.MakeItemKey(90010), minPrice = 1500, totalQuantity = 5 })
  check(e.history and e.deal, "old history judges a Buy tab row")
  eq(select(1, Browse.CellText(e)), H.MoneyShort(3000), "and reads as history")
  local _, asrc = H.Fan.Anchor("2934", 2934)
  eq(asrc, "none", "off: the fan has no prior to center on")
  check(string.find(H.NoReferenceLine(), "estimates are off", 1, true), "the no-reference line says why")
  local cost = P.CraftCost(2319)
  eq(cost, 1200, "the Item view still knows what it costs to make")
  check(P.MakesValue(2318) ~= nil, "and what light leather is worth as an input")
  ok, err = pcall(H.UI.ShowItem, "2319")
  check(ok, "item view with estimates off: " .. tostring(err))

  -- the box on the Hound tab follows the setting, and sets it
  local box = H.UI.estimatesBox
  check(box ~= nil, "estimates box exists")
  eq(box.checked, false, "box followed the command")
  box:SetChecked(true)
  box.scripts.OnClick(box)
  eq(S.estimates, true, "box turns estimates back on")
  e = Browse.Evaluate(row)
  check(e.deal and not e.history, "the crafted cost is the reference again")
  SlashCmdList.HOUND("estimates")
  check(string.find(Stub.printed[#Stub.printed], "estimates are on", 1, true), "the bare command reports the state")
  SlashCmdList.HOUND("estimates sideways")
  check(string.find(Stub.printed[#Stub.printed], "usage", 1, true), "anything else gets the usage")
  eq(S.estimates, true, "and changes nothing")
  local _, asrc2 = H.Fan.Anchor("2934", 2934)
  eq(asrc2, "value as an input", "on: the fan centers on the prior again")
  check(string.find(H.NoReferenceLine(), "crafting anchor", 1, true), "the no-reference line names the anchors again")
  Stub.ah.browse = {}
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
end

------------------------------------------------------------------------
-- Auctions tab total, auto scan, and the auction history
------------------------------------------------------------------------
do
  local F = H.Fan
  H.atAH = true

  -- Total column on Blizzard's list of your auctions
  Stub.ah.ownedPageSize = nil
  Stub.ah.owned = {
    { auctionID = 8101, itemKey = C_AuctionHouse.MakeItemKey(2770), status = 0, quantity = 20, buyoutAmount = 150, timeLeftSeconds = 3600 },
    { auctionID = 8102, itemKey = C_AuctionHouse.MakeItemKey(2771), status = 0, quantity = 1, bidAmount = 900, timeLeftSeconds = 3600 },
  }
  AuctionHouseFrame.AuctionsFrame = Stub.NewAuctionsFrame()
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "auctions tab hook: " .. tostring(err))
  check(H.UI.Auctions.installed, "total column installed")
  local r = AuctionHouseFrame.AuctionsFrame.AllAuctionsList:Render()
  eq(#r.columns, 4, "total column added, bid column gone")
  eq(r.columns[2].template, "AuctionHouseTableCellAllAuctionsBuyoutTemplate", "buyout follows the name")
  eq(r.columns[3].header, "Total", "total column sits before time left")
  eq(r.columns[4].template, "AuctionHouseTableCellTimeLeftTemplate", "time left keeps the edge")
  local bidCol
  for _, col in ipairs(r.all) do if col.template == "AuctionHouseTableCellAllAuctionsBidTemplate" then bidCol = col end end
  check(bidCol ~= nil, "blizzard still built the bid column")
  eq(bidCol.headerFrame.shown, false, "bid header hidden")
  check(r.released[bidCol.headerFrame], "bid header released to its pool")
  eq(r.rows[1][3].Text.text, H.Money(150 * 20), "total is buyout times units")
  eq(r.rows[2][3].Text.text, "", "no buyout, no total")
  hover(r, "auctions tab")

  -- auto scan: off by default, and only when a scan is allowed
  Stub.ah.replicate = {}
  AuctionHoundDB.lastFull = Stub.now - H.Scan.FULL_INTERVAL - 1
  H.Settings().autoScan = false
  eq(H.Scan.AutoTick(), false, "auto scan stays off")
  eq(H.Scan.state, "idle", "no scan started while off")
  local box = H.UI.autoScanBox
  check(box ~= nil, "auto scan box exists")
  box:SetChecked(true)
  box.scripts.OnClick(box)
  eq(H.Settings().autoScan, true, "box turns auto scan on")
  eq(H.Scan.state, "replicating", "a ready scan starts from the click")
  Stub.Advance(2) Stub.Pump()
  eq(H.Scan.state, "idle", "auto scan finished")
  eq(H.Scan.AutoTick(), false, "not ready again yet")
  local stale = Stub.now - H.Scan.FULL_INTERVAL - 1
  AuctionHoundDB.lastFull = stale
  Stub.Advance(H.Scan.AUTO_INTERVAL + 1)
  check(H.Scan.state ~= "idle" or AuctionHoundDB.lastFull > stale, "ticker started the next scan")
  Stub.Advance(2) Stub.Pump()
  eq(H.Scan.state, "idle", "ticker scan finished")
  H.Settings().autoScan = false
  H.UI.UpdateStatus()
  eq(box.checked, false, "box follows the setting")

  -- adoption: an auction of ours the store never saw joins the posts
  local before = #H.Store.Posts()
  Stub.ah.owned = {
    { auctionID = 8201, itemKey = C_AuctionHouse.MakeItemKey(2770, 10), status = 0, quantity = 5, buyoutAmount = 700, timeLeftSeconds = 3600 },
    { auctionID = 8202, itemKey = C_AuctionHouse.MakeItemKey(2771), status = 0, quantity = 1, bidAmount = 900 },
    { auctionID = 8203, itemKey = C_AuctionHouse.MakeItemKey(2840), status = Enum.AuctionStatus.Sold, quantity = 3, buyoutAmount = 500, timeLeft = 2 },
  }
  local printed = #Stub.printed
  local ledger = #AuctionHoundDB.ledger
  check(F.Reconcile(Stub.ah.owned, Stub.now) >= 2, "adoption counts as a change")
  local posts = H.Store.Posts()
  eq(#posts, before + 2, "two auctions adopted, the bid-only one skipped")
  local adopted, soldOne
  for _, p in ipairs(posts) do
    if p.auctionID == 8201 then adopted = p end
    if p.auctionID == 8203 then soldOne = p end
  end
  check(adopted and adopted.adopted and adopted.status == "active", "active auction adopted as active")
  eq(adopted.key, "2770", "adopted under the scan's key, item level and all")
  eq(adopted.unit, 700, "adopted unit is the buyout")
  eq(adopted.qty, 5, "adopted units")
  eq(adopted.dur, 3600, "remaining time from the exact figure")
  check(soldOne and soldOne.status == "sold" and soldOne.sold == 3, "sold auction adopted as a sale")
  eq(soldOne.unit, 167, "a sold auction's buyout is the whole sum: the unit is its share")
  eq(soldOne.dur, 12 * 3600, "remaining time from the band")
  eq(#Stub.printed, printed, "adopted sale is quiet: " .. tostring(Stub.printed[#Stub.printed]))
  eq(AuctionHoundDB.ledger[#AuctionHoundDB.ledger].kind, "sale", "adopted sale in the ledger")
  eq(F.Reconcile(Stub.ah.owned, Stub.now), 0, "repeat reconcile adopts nothing")
  -- a batch that sold before its id came back: the owned list shows the
  -- whole sum, and the post is matched by it rather than adopted twice
  local quick = { id = "q1", t = Stub.now, key = "2841", itemID = 2841, name = "Bronze Bar", qty = 4, unit = 777, status = "pending", sold = 0 }
  H.Store.AddPost(quick)
  table.insert(Stub.ah.owned, { auctionID = 8204, itemKey = C_AuctionHouse.MakeItemKey(2841), status = Enum.AuctionStatus.Sold, quantity = 4, buyoutAmount = 4 * 777, timeLeft = 2 })
  local n = #H.Store.Posts()
  F.Reconcile(Stub.ah.owned, Stub.now)
  eq(#H.Store.Posts(), n, "the sold batch is not adopted a second time")
  eq(quick.auctionID, 8204, "the batch took the auction's id")
  eq(quick.status, "sold", "and reads as sold")
  eq(quick.sold, 4, "in full")
  -- gone before it could expire: bought
  Stub.RemoveOwned(8201)
  F.Reconcile(Stub.ah.owned, Stub.now + F.SETTLE)
  eq(adopted.status, "sold", "adopted auction that vanished early counts as sold")
  check(adopted.inferred, "the sale is marked inferred")

  -- summary over recent posts
  local now = Stub.now
  local sample = {
    { t = now - 100, qty = 5, unit = 100, sold = 5, status = "sold" },
    { t = now - 200, qty = 10, unit = 50, sold = 6, status = "expired" },
    { t = now - 300, qty = 3, unit = 20, sold = 0, status = "cancelled" },
    { t = now - 400, qty = 2, unit = 30, sold = 0, status = "active" },
    { t = now - 40 * 86400, qty = 9, unit = 999, sold = 9, status = "sold" },
  }
  local sm = F.PostSummary(sample, now)
  eq(sm.n, 4, "summary counts the last 30 days")
  eq(sm.sold, 11, "summary units sold")
  eq(sm.gold, 5 * 100 + 6 * 50, "summary gold sold")
  eq(sm.expired, 4, "summary units expired")
  eq(sm.cancelled, 3, "summary units cancelled")
  eq(sm.active, 2, "summary units listed")
  local line = F.SummaryLine(sm)
  check(string.find(line, "^30 days: sold 11 for "), "summary line leads with sales: " .. line)
  check(string.find(line, "4 expired", 1, true) and string.find(line, "3 cancelled", 1, true) and string.find(line, "2 listed", 1, true), "summary line has every count")
  eq(F.SummaryLine(F.PostSummary({}, now)), "no auctions recorded yet", "empty summary")

  -- the History view
  ok, err = pcall(H.UI.ShowView, "history")
  check(ok, "history view: " .. tostring(err))
  local hv = H.UI.views.history
  eq(#hv.table.data, #H.Store.Posts(), "history lists every post")
  local soldCount = 0
  for _, p in ipairs(H.Store.Posts()) do if p.status == "sold" or (p.sold or 0) > 0 then soldCount = soldCount + 1 end end
  hv.filter:SetValue("Sold")
  hv:Refresh()
  eq(#hv.table.data, soldCount, "sold filter keeps the sales")
  hv.filter:SetValue("Cancelled")
  hv:Refresh()
  for _, row in ipairs(hv.table.data) do eq(row.p.status, "cancelled", "cancelled filter keeps only cancelled") end
  hv.filter:SetValue("All")
  hv:Refresh()
  check(string.find(hv.summary.text, "days:", 1, true), "history shows the summary: " .. hv.summary.text)
  H.UI.ShowView("markets")
end

------------------------------------------------------------------------
-- The listing ladder, deposit notes, and the Auctions tab cell
------------------------------------------------------------------------
do
  local Ladder = H.Ladder
  local F = H.Fan
  H.atAH = true
  H.Settings().minDiscount = 0.25
  H.Browse.Invalidate()
  local refOre = H.Reference("2770", 2770)
  local function at(frac) return H.Round(refOre * frac) end

  -- the ladder from listings
  local L = Ladder.Build({ { p = at(0.4), q = 30 }, { p = at(0.45), q = 20 }, { p = at(1.0), q = 500, mine = true } }, "2770", 2770)
  check(L ~= nil, "ladder built")
  eq(#L.steps, 3, "three price steps")
  eq(L.floor, at(0.4), "floor is the cheapest step")
  eq(L.units, 550, "units summed")
  eq(L.dealUnits, 50, "units at or under the limit")
  eq(L.dealCost, at(0.4) * 30 + at(0.45) * 20, "cost of the deal units")
  eq(L.mineUnits, 500, "own units counted")
  check(not L.lowFloor, "a small step is not a low floor")
  eq(Ladder.Verdict(L, at(0.4)), "deal", "floor is a deal")
  eq(Ladder.Verdict(L, at(0.9)), "under", "under the reference but not a deal")
  eq(Ladder.Verdict(L, at(1.0)), "over", "at the reference is over")
  eq(Ladder.Color("deal", false), H.Browse.COLORS.deal, "deal color")
  eq(Ladder.Color("over", false), nil, "over keeps Blizzard's color")
  eq(Ladder.Off(L, at(0.5)), "-50%", "discount text for a listing")
  local lines = Ladder.Lines(L)
  eq(#lines, 4, "four lines")
  check(string.find(lines[1], "^reference "), "line one names the reference: " .. lines[1])
  check(string.find(lines[2], "50 units at or under", 1, true), "line two counts the deal: " .. lines[2])
  check(string.find(lines[3], "next step", 1, true) and not string.find(lines[3], "low in the list", 1, true), "line three has the next step: " .. lines[3])
  check(string.find(lines[4], "500 yours", 1, true), "line four counts yours: " .. lines[4])

  -- a stray far under the rest
  L = Ladder.Build({ { p = 100, q = 1 }, { p = 200, q = 10 } }, "2770", 2770)
  check(L.lowFloor, "a floor half the next step is low")
  eq(select(2, Ladder.Verdict(L, 100)), true, "the floor listing is flagged")
  eq(select(2, Ladder.Verdict(L, 200)), false, "the next step is not")
  eq(Ladder.Color("deal", true), Ladder.COLORS.low, "flagged listing takes the low color")
  check(string.find(Ladder.Lines(L)[3], "low in the list", 1, true), "line three says so")

  -- a wall: the listings' own value sits under history and caps the
  -- reference, so a floor the market has moved to is no deal before
  -- the next scan sees it; a stray under the rest leaves it alone
  L = Ladder.Build({ { p = at(0.5), q = 400 }, { p = at(1.0), q = 100 } }, "2770", 2770)
  check(L.capped and L.ref == at(0.5), "four hundred of five hundred units at half price set the reference")
  eq(L.under, refOre, "under the history it would have been")
  eq(Ladder.Verdict(L, at(0.5)), "over", "the wall's floor is at the reference, no deal")
  eq(Ladder.Off(L, at(0.5)), "0%", "and reads as no discount")
  check(string.find(Ladder.Lines(L)[1], "these listings, under history", 1, true), "line one says so: " .. Ladder.Lines(L)[1])
  L = Ladder.Build({ { p = at(0.5), q = 3 }, { p = at(1.0), q = 497 } }, "2770", 2770)
  check(not L.capped and L.ref == refOre, "three units at half price leave history as the reference")
  eq(Ladder.Verdict(L, at(0.5)), "deal", "and are a deal")
  -- scarce: with a fraction of the usual units listed, the few cheap
  -- ones are the deals, not the price
  check(H.Market.Scarce(select(4, H.Reference("2770", 2770)), 5), "five units of ore is scarce")
  L = Ladder.Build({ { p = at(0.5), q = 5 } }, "2770", 2770)
  check(not L.capped and L.ref == refOre, "five units alone at half price: history stays the reference")
  eq(Ladder.Verdict(L, at(0.5)), "deal", "and they are a deal")

  -- no reference, vendor reference, nothing
  L = Ladder.Build({ { p = 500, q = 3 } }, "90001", 90001)
  eq(L.ref, nil, "unknown item has no reference")
  eq(Ladder.Verdict(L, 500), "none", "no verdict without a reference")
  eq(Ladder.Off(L, 500), "", "no discount text without a reference")
  check(string.find(Ladder.Lines(L)[1], "no reference", 1, true), "line one says there is no reference")
  L = Ladder.Build({ { p = 100, q = 1 }, { p = 200, q = 10 }, { p = 210, q = 10 } }, "90001", 90001)
  eq(L.ref, nil, "a stray floor is not a reference: only the market is")
  eq(Ladder.Verdict(L, 100), "none", "so no verdict for it")
  check(L.lowFloor, "it is still flagged low in the list")
  L = Ladder.Build({ { p = 800, q = 3 }, { p = 1200, q = 2 } }, "90002", 90002)
  eq(L.refSrc, "vendor", "vendor price stands in")
  eq(L.limit, 999, "limit sits just under the vendor price")
  eq(L.dealUnits, 3, "units under vendor are the deal")
  -- the copper minimum moves the limit too, under vendor included
  H.Settings().minSaving = 60
  L = Ladder.Build({ { p = at(0.4), q = 30 }, { p = at(0.45), q = 20 }, { p = at(1.0), q = 500 } }, "2770", 2770)
  eq(L.limit, at(0.4), "the copper minimum sets the limit when it bites first")
  eq(L.dealUnits, 30, "only the floor clears it")
  eq(Ladder.Verdict(L, at(0.45)), "under", "the next step is under, not a deal")
  H.Settings().minSaving = 300
  L = Ladder.Build({ { p = 800, q = 3 }, { p = 1200, q = 2 } }, "90002", 90002)
  eq(L.limit, 700, "under vendor still has to clear the copper minimum")
  eq(L.dealUnits, 0, "two silver under vendor is short of three")
  eq(Ladder.Verdict(L, 800), "under", "so the floor is under, not a deal")
  check(string.find(Ladder.Lines(L)[2], "nothing at or under", 1, true), "line two says so: " .. Ladder.Lines(L)[2])
  H.Settings().minSaving = 5000
  L = Ladder.Build({ { p = 800, q = 3 }, { p = 1200, q = 2 } }, "90002", 90002)
  eq(L.dealUnits, 0, "a minimum over the reference leaves no deal")
  check(string.find(Ladder.Lines(L)[2], "no price here clears", 1, true), "and line two says why: " .. Ladder.Lines(L)[2])
  H.Settings().minSaving = 0
  eq(Ladder.Build({}, "2770", 2770), nil, "no listings, no ladder")
  eq(Ladder.Lines(nil)[1], "no listings loaded", "no ladder, one line")

  -- the buy frames, and the house's confirm dialog for a commodity
  AuctionHouseFrame.CommoditiesBuyFrame = Stub.NewCommoditiesBuyFrame()
  AuctionHouseFrame.ItemBuyFrame = Stub.NewItemBuyFrame()
  AuctionHouseFrame.BuyDialog = Stub.NewBuyDialog(AuctionHouseFrame)
  local LU = H.UI.Ladder
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "buy frame hooks: " .. tostring(err))
  check(LU.installed and LU.block.commodity and LU.block.item, "info blocks built")
  local cf = AuctionHouseFrame.CommoditiesBuyFrame
  Stub.ah.currentSearch = { commodity = true, listings = { { at(0.4), 30 }, { at(0.45), 20 }, { at(2.0), 500 } } }
  cf:SetItemIDAndPrice(2770, at(0.4))
  eq(LU.block.commodity.lines[1].text, "reading the listings", "block waits for results")
  Stub.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2771)
  eq(LU.current.commodity, nil, "another item's results are ignored")
  Stub.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
  check(LU.current.commodity and LU.current.commodity.floor == at(0.4), "commodity ladder built from the results")
  check(string.find(LU.block.commodity.lines[1].text, "^reference "), "block shows the reference")
  local r = cf.ItemList:Render()
  eq(#r.columns, 2, "commodity list keeps its two columns")
  local qtyCell = r.rows[1][2]
  eq(qtyCell.Text.text, "30", "units cell still populated by Blizzard")
  eq(qtyCell.Text.color and qtyCell.Text.color[2], H.Browse.COLORS.deal[2], "deal units colored green")
  eq(r.rows[3][2].Text.color, nil, "units over reference keep their color")
  -- a sell list cell with another owner is left alone
  local other = CreateFrame("Frame", nil, nil, "AuctionHouseTableCellCommoditiesQuantityTemplate")
  other:Init(CreateFrame("Frame"))
  other:Populate({ unitPrice = at(0.4), quantity = 5 })
  eq(other.Text.color, nil, "another list's cell untouched")

  local itf = AuctionHouseFrame.ItemBuyFrame
  local tinKey = C_AuctionHouse.MakeItemKey(2771)
  local refTin = H.Reference("2771", 2771)
  check(refTin and refTin > 0, "tin ore has a reference")
  Stub.ah.currentSearch = { listings = { { H.Round(refTin * 0.4), 1 }, { H.Round(refTin * 1.1), 1 }, { nil, 1 } } }
  itf:SetItemKey(tinKey)
  eq(LU.block.item.lines[1].text, "reading the auctions", "item block waits for results")
  Stub.FireEvent("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(2770))
  eq(LU.current.item, nil, "another key's results are ignored")
  Stub.FireEvent("ITEM_SEARCH_RESULTS_UPDATED", tinKey)
  check(LU.current.item and LU.current.item.units == 2, "item ladder counts auctions with a buyout")
  check(LU.current.item.lowFloor, "a stray auction far under the next is flagged")
  r = itf.ItemList:Render()
  eq(#r.columns, 6, "hound column added to the auction list")
  eq(r.columns[5].header, "Hound", "hound column sits before time left")
  eq(r.rows[1][5].Text.text, "-60%", "discount off the reference per auction")
  eq(r.rows[1][5].Text.color[3], Ladder.COLORS.low[3], "flagged auction colored")
  eq(r.rows[2][5].Text.text, "+10%", "premium shown as a premium")
  eq(r.rows[3][5].Text.text, "", "bid-only auction shows nothing")
  hover(r, "item buy frame")
  local lp = itf.ItemList.points[#itf.ItemList.points]
  eq(lp[5], -(14 + LU.BLOCK_HEIGHT + 4), "auction list starts below the block")
  eq(itf.ItemList.Background.height, 414 - LU.BLOCK_HEIGHT - 4, "background shortened to match")

  -- deposit notes: every post leaves one; an adopted auction takes it
  Stub.SetBag(0, 1, 2770, 40)
  local loc = ItemLocation:CreateFromBagAndSlot(0, 1)
  C_AuctionHouse.PostCommodity(loc, 2, 5, 300)
  local note = F.TakeNote(2770, 5, 300)
  check(note ~= nil, "post left a note")
  eq(note.deposit, 5 * 2, "note carries the deposit")
  eq(note.duration, 2, "note carries the duration")
  eq(F.TakeNote(2770, 5, 300), nil, "a note is taken once")
  Stub.Advance(1) Stub.Pump()
  Stub.ah.owned = {}
  C_AuctionHouse.PostCommodity(loc, 3, 4, 250)
  Stub.Advance(1) Stub.Pump()
  eq(#Stub.ah.owned, 1, "the house listed the auction")
  local posted = Stub.ah.owned[1]
  F.Reconcile(Stub.ah.owned, Stub.now)
  local adopted = F.PostForAuction(posted.auctionID)
  check(adopted and adopted.adopted, "auction posted from Blizzard's tab adopted")
  eq(adopted.deposit, 4 * 3, "adopted auction carries its deposit")
  eq(adopted.dur, 48 * 3600, "adopted auction carries its duration")
  local fanPost
  for _, p in ipairs(H.Store.Posts()) do if p.fan and p.deposit then fanPost = p break end end
  check(fanPost ~= nil, "fan posts carry their deposit")

  -- the Auctions tab cell: the total, with cut and deposit on hover
  H.Settings().cut = 0.05
  r = AuctionHouseFrame.AuctionsFrame.AllAuctionsList:Render()
  local cell = r.rows[1][3]
  eq(cell.Text.text, H.Money(250 * 4), "total is buyout times units")
  eq(rawget(cell, "Sub"), nil, "nothing written beside the total")
  local row, hovered = r.rowFrames[1], {}
  row:SetScript("OnEnter", function() hovered.entered = true end)
  row:SetScript("OnLeave", function() hovered.left = true end)
  GameTooltip:ClearLines()
  cell:OnEnter()
  check(hovered.entered, "hovering the total lights the row")
  local tip = table.concat(GameTooltip.lines, "\n")
  check(string.find(tip, "cut 5% | -" .. H.Money(50), 1, true), "tooltip names the cut: " .. tip)
  check(string.find(tip, "deposit paid | " .. H.Money(12), 1, true), "tooltip names the deposit: " .. tip)
  check(string.find(tip, "left after cut and deposit | " .. H.Money(1000 - 50 - 12), 1, true), "tooltip nets the deposit out")
  cell:OnLeave()
  check(hovered.left, "leaving the total clears the row")
  eq(rawget(cell, "OnMouseUp"), nil, "the cell leaves clicks to the row")
  cell:Populate({ auctionID = 1, quantity = 1 })
  eq(cell.Text.text, "", "no buyout, no total")
  cell:Populate({ auctionID = 424242, quantity = 2, buyoutAmount = 700 })
  GameTooltip:ClearLines()
  cell:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "deposit not recorded", 1, true), "tooltip says when the deposit is unknown")
  cell:OnLeave()

  -- a sold auction waiting in the mail shows its buyout as the whole sum
  cell:Populate({ auctionID = 424243, quantity = 20, buyoutAmount = 3000, status = Enum.AuctionStatus.Sold })
  eq(cell.Text.text, H.Money(3000), "a sold auction's total is its buyout, not times units again")
  GameTooltip:ClearLines()
  cell:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "sold, the whole auction | " .. H.Money(3000), 1, true), "tooltip says the buyout is the whole auction")
  cell:OnLeave()
  cell:Populate({ auctionID = 424244, quantity = 20, buyoutAmount = 150, status = Enum.AuctionStatus.Active })
  eq(cell.Text.text, H.Money(3000), "an open auction's total is still buyout times units")
end

------------------------------------------------------------------------
-- Purchases: noted from the house's calls and listed in the History
-- view, and the double-click that makes them
------------------------------------------------------------------------
do
  local Buy, LU = H.Buy, H.UI.Ladder
  local cf, itf = AuctionHouseFrame.CommoditiesBuyFrame, AuctionHouseFrame.ItemBuyFrame
  H.atAH = true
  Stub.ah.purchases = {}
  eq(#H.Store.Buys(), 0, "no purchases yet")

  -- a commodity through the house's own flow: quote, then confirm
  Stub.ah.commodityPrice[2770] = 95
  C_AuctionHouse.StartCommoditiesPurchase(2770, 50)
  Stub.Advance(1) Stub.Pump()
  eq(Buy.commodity and Buy.commodity.total, 95 * 50, "the quote is noted")
  eq(#H.Store.Buys(), 0, "nothing recorded before the confirm")
  C_AuctionHouse.ConfirmCommoditiesPurchase(2770, 50)
  Stub.Advance(1) Stub.Pump()
  eq(#H.Store.Buys(), 1, "the purchase is recorded on success")
  local b = H.Store.Buys()[1]
  eq(b.key, "2770", "keyed by the item")
  eq(b.qty, 50, "units bought")
  eq(b.total, 95 * 50, "what was paid")
  eq(b.unit, 95, "per unit")
  eq(b.status, "bought", "status")
  check(b.commodity, "marked as a commodity")
  eq(Buy.commodity, nil, "nothing pending after")
  check(string.find(Stub.printed[#Stub.printed], "bought 50 x Copper Ore for " .. H.Money(4750), 1, true), "chat names the purchase: " .. Stub.printed[#Stub.printed])
  eq(AuctionHoundDB.ledger[#AuctionHoundDB.ledger].kind, "buy", "purchase in the ledger")
  -- a purchase that fails leaves nothing
  C_AuctionHouse.StartCommoditiesPurchase(2770, 5)
  Stub.Advance(1) Stub.Pump()
  Stub.FireEvent("COMMODITY_PURCHASE_FAILED")
  eq(Buy.commodity, nil, "a failed purchase is dropped")
  Stub.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
  eq(#H.Store.Buys(), 1, "and a stray success records nothing")
  -- a cancelled quote is forgotten
  C_AuctionHouse.StartCommoditiesPurchase(2770, 5)
  Stub.Advance(1) Stub.Pump()
  C_AuctionHouse.CancelCommoditiesPurchase()
  eq(Buy.commodity, nil, "a cancelled purchase is dropped")
  -- a confirm the quote never reached is said, not recorded
  C_AuctionHouse.StartCommoditiesPurchase(2770, 5)
  C_AuctionHouse.ConfirmCommoditiesPurchase(2770, 5)
  Stub.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
  check(string.find(Stub.printed[#Stub.printed], "no price to note", 1, true), "a confirm without a quote is said")
  eq(#H.Store.Buys(), 1, "and not recorded")
  Stub.Advance(1) Stub.Pump()
  eq(#H.Store.Buys(), 1, "the late quote and success record nothing either")

  -- an item: the search names the auction, the bid at its buyout buys it
  local key = C_AuctionHouse.MakeItemKey(15001, 20, -14)
  Stub.ah.currentSearch = { listings = { { 60000, 1, 801 }, { 65000, 1, 802 }, { nil, 1, 803 } } }
  itf:SetItemKey(key)
  Stub.FireEvent("ITEM_SEARCH_RESULTS_UPDATED", key)
  check(Buy.Seen(801) and Buy.Seen(801).buyout == 60000, "auctions from the search are known by id")
  eq(Buy.NoteBid(801, 50000), false, "a bid under the buyout is not a purchase")
  C_AuctionHouse.PlaceBid(801, 60000)
  Stub.Advance(1) Stub.Pump()
  eq(#H.Store.Buys(), 2, "the buyout is recorded when the house completes it")
  b = H.Store.Buys()[2]
  eq(b.key, "15001:20:-14", "keyed by the variant")
  eq(b.total, 60000, "what was paid")
  eq(b.qty, 1, "one unit")
  eq(b.auctionID, 801, "the auction noted")
  check(string.find(Stub.printed[#Stub.printed], "bought Wolf Bracers for " .. H.Money(60000), 1, true), "chat names the item: " .. Stub.printed[#Stub.printed])
  C_AuctionHouse.PlaceBid(802, 40000)
  Stub.Advance(1) Stub.Pump()
  eq(#H.Store.Buys(), 2, "a plain bid records nothing")
  eq(Buy.NoteBid(999, 100), false, "an auction no search listed is not followed")

  -- the History view lists them, and the summary counts them
  ok, err = pcall(H.UI.ShowView, "history")
  check(ok, "history view with purchases: " .. tostring(err))
  local hv = H.UI.views.history
  hv.filter:SetValue("Bought")
  hv:Refresh()
  eq(#hv.table.data, 2, "bought filter lists every purchase")
  eq(hv.table.data[1].p.status, "bought", "row carries the purchase")
  eq(H.Fan.PostStatus(hv.table.data[1].p), "bought", "status text")
  hv.table:Layout()
  hv.table:Refresh(true)
  local rr = hv.table.rows[1]
  eq(rr.cells[8].text, "bought", "status cell reads bought")
  check(rr.cells[7].text ~= "0", "a purchase has no sold count")
  eq(rr.cells[5].text, H.MoneyExact(60000), "total cell shows what was paid")
  hv.filter:SetValue("Sold")
  hv:Refresh()
  for _, row in ipairs(hv.table.data) do check(row.p.status ~= "bought", "sold filter leaves purchases out") end
  hv.filter:SetValue("All")
  hv:Refresh()
  check(string.find(hv.summary.text, "bought 51 for " .. H.Money(4750 + 60000), 1, true), "summary counts the purchases: " .. hv.summary.text)
  local bs = Buy.Summary(H.Store.Buys(), Stub.now)
  eq(bs.units, 51, "purchase summary units")
  eq(bs.spent, 64750, "purchase summary gold")
  eq(H.Fan.SummaryLine(nil, bs), "30 days: bought 51 for " .. H.Money(64750), "summary line with purchases alone")
  eq(H.Fan.SummaryLine(H.Fan.PostSummary({}, Stub.now), Buy.Summary({}, Stub.now)), "no auctions recorded yet", "nothing at all")
  H.UI.ShowView("markets")

  -- a double-click on the item list buys the auction outright
  Stub.ah.currentSearch = { listings = { { 60000, 1, 811 }, { 65000, 1, 812 }, { nil, 1, 813 } } }
  itf:SetItemKey(key)
  Stub.FireEvent("ITEM_SEARCH_RESULTS_UPDATED", key)
  local r = itf.ItemList:Render()
  local row = r.rowFrames[1]
  check(row.scripts.OnDoubleClick ~= nil, "auction rows answer a double-click")
  eq(row.houndKind, "item", "the row knows its list")
  local n = #Stub.ah.purchases
  Stub.money = 100
  Stub.shift = false
  row.scripts.OnDoubleClick(row)
  eq(#Stub.ah.purchases, n, "no purchase without the gold")
  check(string.find(Stub.printed[#Stub.printed], "not enough gold", 1, true), "and it says so")
  Stub.printed[#Stub.printed + 1] = ""
  Stub.shift = true
  row.scripts.OnDoubleClick(row)
  check(string.find(Stub.printed[#Stub.printed], "not enough gold", 1, true), "shift held makes no difference")
  Stub.shift = false
  Stub.money = nil
  row.scripts.OnDoubleClick(row)
  eq(#Stub.ah.purchases, n + 1, "a plain double-click places the bid")
  eq(Stub.ah.purchases[n + 1].auctionID, 811, "on that auction")
  eq(Stub.ah.purchases[n + 1].amount, 60000, "at its buyout")
  check(string.find(Stub.printed[#Stub.printed], "buying Wolf Bracers for " .. H.Money(60000), 1, true), "chat says what is being bought")
  Stub.Advance(1) Stub.Pump()
  eq(#H.Store.Buys(), 3, "and the purchase is recorded")
  local bidOnly = r.rowFrames[3]
  bidOnly.scripts.OnDoubleClick(bidOnly)
  eq(#Stub.ah.purchases, n + 1, "a bid-only auction is not bought")
  check(string.find(Stub.printed[#Stub.printed], "no buyout", 1, true), "and it says so")
  -- rows are reused as the list scrolls: a repopulated row buys its new listing
  r.rows[2][5]:Populate(C_AuctionHouse.GetItemSearchResultInfo(key, 1))
  eq(r.rowFrames[2].houndRow.auctionID, 811, "the row follows its cell's listing")

  -- on the commodity list the house's own Buy button is pressed for
  -- the units selected, and its dialog confirms
  Stub.ah.currentSearch = { commodity = true, listings = { { 90, 30 }, { 95, 20 }, { 200, 500 } } }
  cf:SetItemIDAndPrice(2770, 90)
  Stub.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
  r = cf.ItemList:Render()
  row = r.rowFrames[2]
  check(row.scripts.OnDoubleClick ~= nil, "commodity rows answer a double-click")
  eq(row.houndKind, "commodity", "the row knows its list")
  Stub.ah.buyClicks = 0
  cf.BuyDisplay:SetQuantity(0)
  row.scripts.OnDoubleClick(row)
  eq(Stub.ah.buyClicks, 0, "nothing selected, nothing pressed")
  check(string.find(Stub.printed[#Stub.printed], "select the units first", 1, true), "and it says so")
  cf.BuyDisplay:SetQuantity(50)          -- the client's first click selected two rows
  Stub.ah.commodityPrice[2770] = 95
  UIParent:SetSize(1600, 900)
  Stub.cursor = { 500, 300 }
  row.scripts.OnDoubleClick(row)
  eq(Stub.ah.buyClicks, 1, "the house's Buy button is pressed")
  eq(Stub.ah.started and Stub.ah.started.qty, 50, "for the units selected")
  check(string.find(Stub.printed[#Stub.printed], "50 units", 1, true), "chat points at the house's dialog")
  -- the house's dialog opened inside the press, and meets the cursor
  local dialog = AuctionHouseFrame.BuyDialog
  check(LU.dialog == dialog, "the house's dialog is watched")
  check(dialog.shown, "the house's dialog is up")
  eq(#dialog.points, 1, "its anchor is replaced, not added to")
  local dp = dialog.points[1]
  check(dp[1] == "CENTER" and dp[2] == UIParent and dp[3] == "BOTTOMLEFT", "the dialog is centered on a point of the screen")
  eq(dp[4], 500, "under the cursor, across")
  eq(dp[5], 300, "and up")
  eq(LU.dialogToCursor, nil, "nothing is left armed after the press")
  Stub.Advance(1) Stub.Pump()                              -- the quote lands in the dialog
  C_AuctionHouse.ConfirmCommoditiesPurchase(2770, 50)     -- the click in it
  Stub.Advance(1) Stub.Pump()
  eq(#H.Store.Buys(), 4, "the purchase is recorded")
  eq(H.Store.Buys()[4].total, 95 * 50, "at the quoted total")
  dialog:Hide()
  -- at the screen's edge the dialog is kept on it, shift or not
  Stub.cursor = { 10, 890 }
  Stub.shift = true
  row.scripts.OnDoubleClick(row)
  Stub.shift = false
  eq(Stub.ah.buyClicks, 2, "shift held makes no difference")
  dp = dialog.points[1]
  eq(dp[4], 200, "kept on the screen, across")
  eq(dp[5], 800, "and up")
  C_AuctionHouse.CancelCommoditiesPurchase()
  dialog:Hide()
  -- a scaled house: the anchor is in the dialog's own units
  AuctionHouseFrame:SetScale(0.5)
  Stub.cursor = { 500, 300 }
  row.scripts.OnDoubleClick(row)
  dp = dialog.points[1]
  eq(dp[4], 1000, "the anchor is in the dialog's own units, across")
  eq(dp[5], 600, "and up")
  AuctionHouseFrame:SetScale(1)
  C_AuctionHouse.CancelCommoditiesPurchase()
  dialog:Hide()
  -- the house's own Buy button puts the dialog back where the house keeps it
  cf.BuyDisplay.BuyButton:Click()
  eq(Stub.ah.buyClicks, 4, "the house's own press")
  eq(#dialog.points, 1, "the dialog's own anchor is back, alone")
  dp = dialog.points[1]
  check(dp[1] == "CENTER" and dp[2] == AuctionHouseFrame and dp[3] == "CENTER" and dp[4] == 0 and dp[5] == 0, "where the house keeps it")
  C_AuctionHouse.CancelCommoditiesPurchase()
  dialog:Hide()
  -- and left there by the next press of its own
  cf.BuyDisplay.BuyButton:Click()
  eq(#dialog.points, 1, "the dialog's own anchor is left alone")
  C_AuctionHouse.CancelCommoditiesPurchase()
  dialog:Hide()
  -- a client without the button says so
  local saved = cf.BuyDisplay.BuyButton
  cf.BuyDisplay.BuyButton = nil
  row.scripts.OnDoubleClick(row)
  check(string.find(Stub.printed[#Stub.printed], "Buy button was not found", 1, true), "a missing Buy button is reported")
  eq(LU.dialogToCursor, nil, "and nothing is armed")
  cf.BuyDisplay.BuyButton = saved
  Stub.ah.purchases = {}
end

------------------------------------------------------------------------
-- Depth on demand: one search per row on screen, through the throttle
------------------------------------------------------------------------
do
  local Depth, BUI, T = H.Depth, H.UI.Browse, H.Throttle
  local br = AuctionHouseFrame.BrowseResultsFrame
  local S = H.Settings()
  H.atAH = true
  S.browseSort, S.browseDeals, S.browseHistory, S.browseNotMine, S.browseDepth = false, false, false, false, false
  H.Browse.Invalidate()
  Depth.Clear()
  local refOre = H.Reference("2770", 2770)
  local refTin = H.Reference("2771", 2771)
  local oreRow = { itemKey = C_AuctionHouse.MakeItemKey(2770), minPrice = H.Round(refOre * 0.5), totalQuantity = 60 }
  local tinRow = { itemKey = C_AuctionHouse.MakeItemKey(2771), minPrice = H.Round(refTin * 0.9), totalQuantity = 10 }
  local emptyRow = { itemKey = C_AuctionHouse.MakeItemKey(2840), minPrice = 0, totalQuantity = 0 }
  Stub.ah.searchResults["2770"] = { commodity = true, listings = { { oreRow.minPrice, 12 }, { H.Round(refOre * 0.55), 8 }, { H.Round(refOre * 1.1), 40 } } }
  Stub.ah.searchResults["2771"] = { commodity = true, listings = { { tinRow.minPrice, 10 } } }
  Stub.ah.browsePageSize = 10
  Stub.ah.browse = { oreRow, tinRow, emptyRow }
  Stub.ah.throttleModel = true
  Stub.ah.ready = true
  Stub.ah.searchCalls, Stub.ah.dropped, T.replayed = 0, 0, 0
  br:Show()
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  eq(Stub.ah.ready, true, "the model frees the house once the browse answers")

  -- off: the column reads the row alone
  local r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 0, "depth off: no searches")
  eq(r.rows[1][4].Sub.text, H.MoneyShort(refOre), "depth off: the note is the reference alone")
  GameTooltip:ClearLines()
  r.rows[1][4]:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "tick Depth", 1, true), "tooltip points at the toggle")
  r.rows[1][4]:OnLeave()

  -- on: the rows on screen are searched one at a time
  BUI.strip.depth:SetChecked(true)
  BUI.strip.depth.scripts.OnClick(BUI.strip.depth)
  eq(S.browseDepth, true, "depth toggle saved")
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 1, "one search out for the first row")
  eq(Stub.ah.lastSearchKey, "2770", "the first row's item searched")
  check(Depth.Reading(), "reading while a search is out")
  check(string.find(BUI.strip.status.text, "reading depth", 1, true), "status says so: " .. BUI.strip.status.text)
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 1, "a second render sends nothing more while one is out")
  GameTooltip:ClearLines()
  r.rows[1][4]:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "reading the listings", 1, true), "tooltip says it is reading")
  r.rows[1][4]:OnLeave()
  br.ItemList.dirty = false
  Stub.Advance(1) Stub.Pump()
  local L = Depth.Get(oreRow)
  check(L ~= nil, "ore depth cached")
  eq(L and L.floorUnits, 12, "twelve units at the floor")
  check(br.ItemList.dirty, "list refreshed when the depth lands")
  eq(Stub.ah.searchCalls, 2, "the next row searched once the house is ready")
  eq(Stub.ah.lastSearchKey, "2771", "the second row's item searched")
  Stub.Advance(1) Stub.Pump()
  eq(Stub.ah.searchCalls, 2, "the empty row is never searched")
  check(not Depth.Reading(), "reading done")
  check(not string.find(BUI.strip.status.text, "reading depth", 1, true), "status settles: " .. BUI.strip.status.text)
  r = br.ItemList:Render()
  eq(r.rows[1][4].Sub.text, H.MoneyShort(refOre) .. " x12", "cell shows the units at the floor")
  eq(r.rows[2][4].Sub.text, H.MoneyShort(refTin) .. " x10", "second cell too")
  eq(r.rows[3][4].Sub.text, "", "empty row shows nothing")
  hover(r, "buy tab with depth")

  -- the tooltip carries the ladder
  GameTooltip:ClearLines()
  r.rows[1][4]:OnEnter()
  local tip = table.concat(GameTooltip.lines, "\n")
  check(string.find(tip, "20 units at or under", 1, true), "tooltip has the deal line: " .. tip)
  check(string.find(tip, "next step", 1, true), "tooltip has the step line")
  r.rows[1][4]:OnLeave()

  -- unchanged rows keep their depth across a new result set
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 2, "unchanged rows keep their depth")

  -- a moved floor stales the depth, and the row is read again
  oreRow.minPrice = oreRow.minPrice - 1
  eq(Depth.Get(oreRow), nil, "a moved floor stales the depth")
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 3, "the moved row is searched again")
  Stub.Advance(1) Stub.Pump()
  check(Depth.Get(oreRow) ~= nil, "and cached again")

  -- the gate: nothing goes out while the list is hidden or a page is loading
  tinRow.totalQuantity = 11
  br:Hide()
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 3, "no search while the list is hidden")
  br:Show()
  eq(Stub.ah.searchCalls, 4, "showing the list sends the waiting search")
  Stub.Advance(1) Stub.Pump()
  tinRow.totalQuantity = 12
  BUI.loading = true
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 4, "no search while a page is on its way")
  BUI.loading = false
  Depth.Tick()
  eq(Stub.ah.searchCalls, 5, "the search goes out once the page is in")
  Stub.Advance(1) Stub.Pump()

  -- a full scan holds it, and its end lets it go
  tinRow.totalQuantity = 13
  H.Scan.state = "browsing"
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 5, "no search during a scan")
  H.Scan.state = "idle"
  H.Events:Fire("SCAN_STATUS")
  eq(Stub.ah.searchCalls, 6, "the search goes out once the scan is idle")
  Stub.Advance(1) Stub.Pump()

  -- Blizzard's own query while ours is out: dropped by the house, then
  -- sent again by Hound once the house is ready
  tinRow.totalQuantity = 14
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, 7, "a depth search is out")
  eq(Stub.ah.ready, false, "the house is busy with it")
  Stub.ah.lastSearchKey = nil
  C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(2840), {}, false)
  Stub.Pump()
  eq(Stub.ah.dropped, 1, "the click's query was dropped")
  eq(Stub.ah.lastSearchKey, nil, "and not served")
  Stub.Advance(1) Stub.Pump()
  eq(T.replayed, 1, "hound sent the click's query again")
  eq(Stub.ah.lastSearchKey, "2840", "the click's query was served")
  eq(Stub.ah.searchCalls, 8, "one more send, none of it ours")
  Stub.Advance(1) Stub.Pump()
  -- an old foreign query is not what a later drop is about
  Stub.ah.lastSearchKey = nil
  Stub.FireEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
  eq(T.replayed, 1, "a drop long after the query replays nothing")

  -- an empty answer is remembered for a while, and the tooltip says so
  Stub.ah.searchResults["2771"] = { commodity = true, listings = {} }
  tinRow.totalQuantity = 15
  r = br.ItemList:Render()
  Stub.Advance(1) Stub.Pump()
  eq(Depth.Get(tinRow), nil, "an empty answer gives no ladder")
  check(Depth.Failed(tinRow), "and is remembered as a failure")
  local calls = Stub.ah.searchCalls
  r = br.ItemList:Render()
  eq(Stub.ah.searchCalls, calls, "not asked again straight away")
  GameTooltip:ClearLines()
  r.rows[2][4]:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "no listings", 1, true), "tooltip says the house had nothing")
  r.rows[2][4]:OnLeave()
  Stub.ah.searchResults["2771"] = { commodity = true, listings = { { tinRow.minPrice, 10 } } }

  -- a search the house never answers times out and frees the slot
  tinRow.totalQuantity = 16
  local realSearch = C_AuctionHouse.SendSearchQuery
  C_AuctionHouse.SendSearchQuery = function() Stub.ah.ready = false end
  r = br.ItemList:Render()
  check(Depth.inflight ~= nil, "silent search in flight")
  Stub.Advance(Depth.TIMEOUT + 1) Stub.Pump()
  check(Depth.inflight == nil, "silent search timed out")
  eq(Depth.Get(tinRow), nil, "nothing cached for it")
  C_AuctionHouse.SendSearchQuery = realSearch
  Stub.ah.ready = true

  -- a setting that moves the reference re-reads the ladders held from
  -- their listings, without another search
  local leatherRow = { itemKey = C_AuctionHouse.MakeItemKey(2319), minPrice = 700, totalQuantity = 40 }
  Stub.ah.searchResults["2319"] = { commodity = true, listings = { { 700, 40 } } }
  Stub.ah.browse = { oreRow, tinRow, leatherRow }
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  r = br.ItemList:Render()
  for _ = 1, 4 do Stub.Advance(1) Stub.Pump() end
  local LL = Depth.Get(leatherRow)
  check(LL ~= nil, "leather depth cached")
  eq(LL and LL.refSrc, "prior:crafted cost", "its ladder is read against the crafted cost")
  eq(LL and LL.dealUnits, 40, "and the floor counts as a deal")
  calls = Stub.ah.searchCalls
  br.ItemList.dirty = false
  SlashCmdList.HOUND("estimates off")
  LL = Depth.Get(leatherRow)
  eq(LL and LL.refSrc, "market", "estimates off: the ladder is read against history")
  eq(LL and LL.dealUnits, 0, "and nothing is a deal at its own price")
  eq(Stub.ah.searchCalls, calls, "without another search")
  check(br.ItemList.dirty, "list refreshed for the re-read")
  r = br.ItemList:Render()
  eq(r.rows[3][4].Sub.text, H.MoneyShort(700) .. " x40", "the cell shows history with the units at the floor")
  SlashCmdList.HOUND("estimates on")
  eq(Depth.Get(leatherRow).refSrc, "prior:crafted cost", "and back on")
  eq(Stub.ah.searchCalls, calls, "still no search")
  -- the minimum discount moves the deal limit the same way
  SlashCmdList.HOUND("discount 50")
  eq(Depth.Get(leatherRow).dealUnits, 0, "a higher minimum re-reads the ladder: no deal at 42% off")
  SlashCmdList.HOUND("discount 25")
  eq(Depth.Get(leatherRow).dealUnits, 40, "and back")
  eq(Stub.ah.searchCalls, calls, "none of it searched")
  -- and the copper minimum: five silver a unit under is short of six
  SlashCmdList.HOUND("discount 25 6s")
  eq(Depth.Get(leatherRow).dealUnits, 0, "a copper minimum re-reads the ladder: 5s a unit under is short of 6s")
  SlashCmdList.HOUND("discount 25 0c")
  eq(Depth.Get(leatherRow).dealUnits, 40, "and back again")
  eq(Stub.ah.searchCalls, calls, "still none of it searched")

  -- the column reads the floor against the market alone: an unscanned
  -- row stays without a reference once its depth is read, and a row
  -- with an item level still meets its history
  Stub.DefineItem(90020, "Unscanned Widget", { sell = 0, commodity = true })
  SlashCmdList.HOUND("estimates off")
  local strayRow = { itemKey = C_AuctionHouse.MakeItemKey(90020, 12), minPrice = 100, totalQuantity = 21 }
  local leveledOre = { itemKey = C_AuctionHouse.MakeItemKey(2770, 10), minPrice = H.Round(refOre * 0.5), totalQuantity = 30 }
  Stub.ah.searchResults["90020:12:0"] = { commodity = true, listings = { { 100, 1 }, { 200, 10 }, { 210, 10 } } }
  Stub.ah.searchResults["2770:10:0"] = { commodity = true, listings = { { leveledOre.minPrice, 30 } } }
  S.browseDepth = true
  Stub.ah.browse = { strayRow, leveledOre }
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  r = br.ItemList:Render()
  for _ = 1, 4 do Stub.Advance(1) Stub.Pump() end
  check(Depth.Get(strayRow) ~= nil, "the unscanned row's depth is read")
  local se = H.Browse.Evaluate(strayRow)
  check(se.ref == nil and not se.deal, "and it still has no reference")
  r = br.ItemList:Render()
  eq(r.rows[1][4].Sub.text, "no reference", "its cell says so")
  eq(r.rows[1][4].Text.text, "", "with no figure")
  local LO = Depth.Get(leveledOre)
  eq(LO and LO.refSrc, "market", "the leveled ore's ladder is read against its history")
  eq(r.rows[2][4].Sub.text, H.MoneyShort(refOre) .. " x30", "its cell shows the market price")
  eq(r.rows[2][4].Text.text, "-50%", "and the floor's percentage under it")
  eq(H.Browse.BuildIndex(2, function(i) return ({ strayRow, leveledOre })[i] end, { deals = true })[1], 2,
    "deals only keeps the row under market")
  SlashCmdList.HOUND("estimates on")

  -- a wall behind a row: with its depth read, the listings' value sits
  -- under history and is the reference, so the row is no deal before
  -- the next scan, drops out of "Deals only", and its tooltip says so
  local wallRow = { itemKey = C_AuctionHouse.MakeItemKey(2318), minPrice = 150, totalQuantity = 120 }
  Stub.ah.searchResults["2318"] = { commodity = true, listings = { { 150, 100 }, { 300, 20 } } }
  Stub.ah.browse = { wallRow }
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  local we = H.Browse.Evaluate(wallRow)
  check(we.deal and not we.capped, "half price reads as a deal before the depth is read")
  local function wallOnly() return wallRow end
  eq(#H.Browse.BuildIndex(1, wallOnly, { deals = true }), 1, "and passes deals only")
  r = br.ItemList:Render()
  for _ = 1, 4 do Stub.Advance(1) Stub.Pump() end
  local LW = Depth.Get(wallRow)
  check(LW and LW.capped, "the depth finds the listings' value under history")
  we = H.Browse.Evaluate(wallRow)
  check(we.capped and not we.deal, "with the depth read, the row is no deal")
  eq(we.ref, 150, "its reference is the listings' value")
  eq(#H.Browse.BuildIndex(1, wallOnly, { deals = true }), 0, "and deals only drops it")
  r = br.ItemList:Render()
  eq(r.rows[1][4].Sub.text, H.MoneyShort(150) .. " x100", "the cell notes the listings' value and the units at the floor")
  eq(r.rows[1][4].Text.text, "0%", "no discount off it")
  GameTooltip:ClearLines()
  r.rows[1][4]:OnEnter()
  check(string.find(table.concat(GameTooltip.lines, "\n"), "these listings, under history", 1, true), "the tooltip says the listings set the reference")
  r.rows[1][4]:OnLeave()
  -- a stray under the rest leaves history as the reference
  local strayUnder = { itemKey = C_AuctionHouse.MakeItemKey(2318), minPrice = 150, totalQuantity = 121 }
  Stub.ah.searchResults["2318"] = { commodity = true, listings = { { 150, 1 }, { 300, 120 } } }
  Stub.ah.browse = { strayUnder }
  C_AuctionHouse.SendBrowseQuery({})
  Stub.Advance(1) Stub.Pump()
  r = br.ItemList:Render()
  for _ = 1, 4 do Stub.Advance(1) Stub.Pump() end
  check(Depth.Get(strayUnder) ~= nil and not Depth.Get(strayUnder).capped, "one unit at half price leaves history alone")
  we = H.Browse.Evaluate(strayUnder)
  check(we.deal and not we.capped and we.ref == 300, "and the row is a deal")
  r = br.ItemList:Render()
  eq(r.rows[1][4].Text.text, "-50%", "its cell shows the discount off history")

  -- leaving the house forgets it all
  H.Events:Fire("AH_CLOSED")
  eq(Depth.Get(oreRow), nil, "cache cleared on close")
  check(not T.Pending(), "queue cleared on close")
  H.atAH = true
  Stub.ah.throttleModel = false
  S.browseDepth = false
  Depth.Clear()
end

------------------------------------------------------------------------
-- A full scan the house does not answer. It allows one every fifteen
-- minutes whichever addon asks, and says nothing when it refuses; a
-- region's house can also be slow with one. Auto scan must not ask
-- again every minute, and an answer that lands after the wait is
-- still the scan that was asked for.
------------------------------------------------------------------------
do
  local Sc = H.Scan
  eq(Sc.state, "idle", "no scan under way")
  Stub.ah.replicate = {}
  Stub.ah.replicateSilent = true
  AuctionHoundDB.lastFull = Stub.now - Sc.FULL_INTERVAL - 1
  H.Settings().autoScan = true
  local calls = Stub.ah.replicateCalls
  Stub.printed = {}
  eq(Sc.AutoTick(), true, "auto scan asks for a scan")
  eq(Stub.ah.replicateCalls, calls + 1, "once")
  Stub.Advance(Sc.REPLY_TIMEOUT + 1)
  eq(Sc.state, "idle", "and gives up when no answer comes")
  check(string.find(table.concat(Stub.printed, "\n"), "no answer to the full scan", 1, true),
    "saying so: " .. table.concat(Stub.printed, " | "))
  check(string.find(H.UI.StatusLine(), "the house did not answer the last scan request", 1, true),
    "the status line says so too, not that a scan is ready: " .. H.UI.StatusLine())
  Stub.Advance(120)
  eq(Stub.ah.replicateCalls, calls + 1, "auto scan leaves the house alone for a while after")
  eq(Sc.AutoTick(), false, "asked by hand or by the ticker")
  local logged = #AuctionHoundDB.markets[H.marketKey].scans
  Stub.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
  check(Sc.state ~= "idle", "the answer, late, is still read: " .. Sc.state)
  Stub.Advance(2) Stub.Pump()
  eq(Sc.state, "idle", "to the end")
  eq(#AuctionHoundDB.markets[H.marketKey].scans, logged + 1, "and logged as the scan it is")
  check(AuctionHoundDB.lastFull >= Stub.now - 3, "with the fifteen minutes counted from it")
  Stub.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
  eq(Sc.state, "idle", "a second list is not a second scan")

  -- with no answer at all, auto scan asks again once the wait is over
  AuctionHoundDB.lastFull = Stub.now - Sc.FULL_INTERVAL - 1
  calls = Stub.ah.replicateCalls
  eq(Sc.AutoTick(), true, "auto scan asks again when a scan is due")
  Stub.Advance(Sc.REPLY_TIMEOUT + 1)
  eq(Sc.state, "idle", "unanswered again")
  Stub.Advance(Sc.RETRY_AFTER - 60)
  eq(Stub.ah.replicateCalls, calls + 1, "still waiting inside the retry time")
  -- a list that turns up with the house closed is nobody's scan
  H.atAH = false
  logged = #AuctionHoundDB.markets[H.marketKey].scans
  Stub.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
  Stub.Pump()
  eq(#AuctionHoundDB.markets[H.marketKey].scans, logged, "a list landing with the house closed is not read")
  H.atAH = true
  Stub.Advance(60 + Sc.AUTO_INTERVAL + 1)
  eq(Stub.ah.replicateCalls, calls + 2, "and past it the ticker asks once more")
  -- a scan asked for by hand is not held back by the wait
  Stub.Advance(Sc.REPLY_TIMEOUT + 1)
  eq(Sc.state, "idle", "unanswered a third time")
  calls = Stub.ah.replicateCalls
  SlashCmdList.HOUND("scan")
  eq(Stub.ah.replicateCalls, calls + 1, "/hound scan asks at once")
  Stub.ah.replicateSilent = false
  Stub.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
  Stub.Advance(2) Stub.Pump()
  eq(Sc.state, "idle", "and its answer is read")
  check(not string.find(H.UI.StatusLine(), "did not answer", 1, true), "the status line is back to the timer: " .. H.UI.StatusLine())
  H.Settings().autoScan = false
end

------------------------------------------------------------------------
-- Waylaid Crates: each bundle that fills one, priced in its tooltip
------------------------------------------------------------------------
do
  local Crate = H.Crate
  local S = H.Settings()

  -- the data: thirty crates and ninety-six bundles, each a real choice
  -- of goods, no good in two crates, and no crate filling a crate
  local crates, bundles, where = 0, 0, {}
  for id, c in pairs(H.Crates) do
    crates = crates + 1
    check(type(id) == "number" and id >= 248682 and id <= 248713, "crate id in the crates' range: " .. tostring(id))
    check(type(c.name) == "string" and c.name ~= "", "crate " .. tostring(id) .. " has a name")
    check(type(c.bundles) == "table" and #c.bundles >= 2, tostring(c.name) .. " offers a choice of bundles")
    for _, b in ipairs(c.bundles or {}) do
      bundles = bundles + 1
      local label = tostring(c.name) .. " / " .. tostring(b[3])
      check(type(b[1]) == "number" and b[1] > 0 and not H.Crates[b[1]], label .. ": a good, not a crate")
      check(type(b[2]) == "number" and b[2] >= 1 and b[2] == math.floor(b[2]), label .. ": whole units")
      check(type(b[3]) == "string" and b[3] ~= "", label .. ": a name to fall back on")
      check(where[b[1]] == nil, label .. ": in one crate only, not also in " .. tostring(where[b[1]]))
      where[b[1]] = c.name
    end
  end
  eq(crates, 30, "thirty crates")
  eq(bundles, 96, "ninety-six bundles")
  -- as the crates' own tooltips list them
  local ore = H.Crates[248683]
  eq(ore.name, "Apprentice Ore", "the apprentice ore crate")
  eq(ore.bundles[1][1], 2770, "its first bundle is copper ore")
  eq(ore.bundles[1][2], 20, "twenty of it")
  eq(ore.bundles[2][1], 2771, "or tin ore")
  eq(H.Crates[248697].bundles[3][1], 11370, "dark iron ore by the id that is mined, not the quest item's")
  eq(H.Crates[248707].bundles[4][2], 45, "forty-five gold power cores")
  eq(H.Crates[248712].bundles[1][2], 2, "two dark iron bars")
  eq(H.Crates[248705].bundles[3][1], 4233, "cured medium hide by its own id")
  eq(H.Crates[248549], nil, "the unread crate names no goods")
  eq(Crate.Read(2770), nil, "an ore is no crate")
  eq(Crate.Read(248549), nil, "nor is the crate not yet read")

  -- Journeyman Ore: ten silver ore or twenty iron ore, both in the
  -- scan just run
  Stub.DefineItem(248687, "Waylaid Crate: Journeyman Ore", { stack = 1, commodity = false })
  Stub.DefineItem(2775, "Silver Ore", { sell = 75, commodity = true })
  Stub.DefineItem(2772, "Iron Ore", { sell = 150, commodity = true })
  local function scan(t, samples)
    for key, listing in pairs(samples) do
      Store.AddScanSample(key, t, { { p = listing[1], q = listing[2] } })
    end
    Store.LogScan({ t = t, kind = "full", rows = 0, keys = 0, secs = 0, skipped = 0 })
  end
  scan(Stub.now, { ["2775"] = { 1500, 40 }, ["2772"] = { 600, 500 } })

  local r = Crate.Read(248687)
  eq(r.name, "Journeyman Ore", "the crate is read")
  eq(#r.bundles, 2, "with its two bundles")
  eq(r.priced, 2, "both priced")
  eq(r.bundles[1].unit, 1500, "silver ore at its market value")
  eq(r.bundles[1].total, 15000, "ten of it")
  eq(r.bundles[1].src, "market", "from history")
  eq(r.bundles[2].total, 12000, "twenty iron ore")
  eq(r.bundles[1].listed, nil, "forty listed covers ten")
  eq(r.best, 2, "the iron is the cheaper fill")
  eq(r.scanAge, 0, "the scan is fresh")
  eq((Crate.UnitPrice(2775)), (P.MarketValue(2775)), "a good is priced as its own tooltip prices it")

  local lines = Crate.Lines(r)
  eq(#lines, 3, "a header and a line per bundle")
  eq(lines[1][1], "|cffe6b800Hound|r any one bundle fills it", "the header says one is enough")
  eq(lines[1][2], "scanned 0s ago", "and how old the prices are")
  eq(lines[2][1], "  10 Silver Ore, " .. H.Money(1500) .. " each", "units, name and the price of one")
  eq(lines[2][2], H.Money(15000), "the bundle's total on the right")
  eq(lines[2][3], Crate.COLORS.price, "the dearer bundle in white")
  eq(lines[3][1], "  20 Iron Ore, " .. H.Money(600) .. " each", "the second bundle")
  eq(lines[3][2], H.Money(12000), "its total")
  eq(lines[3][3], Crate.COLORS.best, "the cheapest in green")

  -- the crate's tooltip carries them, with nothing else of Hound's:
  -- a crate has no history of its own
  GameTooltip:ClearLines()
  Stub.tooltipHandler(GameTooltip, { id = 248687, hyperlink = "|cffffffff|Hitem:248687:0:0:0:0:0:0:0:60:0:0:0:0|h[Waylaid Crate: Journeyman Ore]|h|r" })
  eq(#GameTooltip.lines, 4, "a blank line, the header and the bundles: " .. table.concat(GameTooltip.lines, " / "))
  eq(GameTooltip.lines[1], " ", "set apart from the crate's own lines")
  eq(GameTooltip.lines[3], "  10 Silver Ore, " .. H.Money(1500) .. " each | " .. H.Money(15000), "silver ore line in the tooltip")
  eq(GameTooltip.lines[4], "  20 Iron Ore, " .. H.Money(600) .. " each | " .. H.Money(12000), "iron ore line in the tooltip")
  eq(GameTooltip.rightColors[4][2], Crate.COLORS.best[2], "the cheapest total is green there too")
  eq(GameTooltip.rightColors[3][2], Crate.COLORS.price[2], "and the other is not")
  -- without the item id in the tooltip data, the displayed link gives it
  GameTooltip:ClearLines()
  TooltipUtil = { GetDisplayedItem = function() return "Waylaid Crate: Journeyman Ore", "|cffffffff|Hitem:248687:0:0:0:0:0:0:0:60:0:0:0:0|h[x]|h|r", 248687 end }
  Stub.tooltipHandler(GameTooltip, {})
  eq(#GameTooltip.lines, 4, "the crate is known by its link as well")
  TooltipUtil = nil
  -- an item that is no crate gets no crate lines, and a comparison
  -- tooltip is left alone
  GameTooltip:ClearLines()
  Stub.tooltipHandler(GameTooltip, { id = 248549 })
  eq(#GameTooltip.lines, 0, "nothing on the crate not yet read")
  local other = { lines = {}, AddLine = function(self, t) table.insert(self.lines, t) end, AddDoubleLine = function(self, a) table.insert(self.lines, a) end }
  Stub.tooltipHandler(other, { id = 248687 })
  eq(#other.lines, 0, "only the main tooltips are written on")
  S.tooltip = false
  GameTooltip:ClearLines()
  Stub.tooltipHandler(GameTooltip, { id = 248687 })
  eq(#GameTooltip.lines, 0, "and none at all with tooltips off")
  S.tooltip = true

  -- the cheaper bundle is no use when the house cannot fill it: four
  -- silver ore listed where ten are needed
  Stub.now = Stub.now + 900
  scan(Stub.now, { ["2775"] = { 100, 4 }, ["2772"] = { 600, 500 } })
  r = Crate.Read(248687)
  check(r.bundles[1].total < r.bundles[2].total, "silver is now the cheaper on paper")
  eq(r.bundles[1].listed, 4, "but only four are listed")
  eq(r.best, 2, "so the iron is still the fill to buy")
  lines = Crate.Lines(r)
  check(string.find(lines[2][1], "only 4 listed", 1, true), "the line says so: " .. lines[2][1])
  eq(lines[2][3], Crate.COLORS.price, "and is not the green one")

  -- a good the last scan did not see at all still has its price, and
  -- the line says none is listed
  Stub.now = Stub.now + 900
  scan(Stub.now, { ["2772"] = { 600, 500 } })
  r = Crate.Read(248687)
  check(r.bundles[1].unit ~= nil, "silver keeps a price from its history")
  eq(r.bundles[1].listed, 0, "with none in the last scan")
  check(string.find(Crate.Lines(r)[2][1], "none listed", 1, true), "none listed: " .. Crate.Lines(r)[2][1])
  eq(r.best, 2, "iron is the one to buy")
  eq(r.scanAge, 0, "against the newest scan")
  -- a saved record keeps its points to the minute; the scan's own point
  -- must still read as seen in it
  local at = Stub.now - (Stub.now % 60)
  eq(Crate.Listed({ at = at, qty = 500 }), 500, "a point saved to the minute is still the last scan's")
  eq(Crate.Listed({ at = Stub.now - 900, qty = 500 }), 0, "the scan before is not")
  eq(Crate.Listed(nil), 0, "and a good with no record has none listed")

  -- Expert Ingots: mithril, steel or gold bars. Only gold bars are on
  -- the house; mithril and steel are priced by what they cost to make,
  -- marked as estimates, and are not there to buy
  Stub.DefineItem(248709, "Waylaid Crate: Expert Ingots", { stack = 1, commodity = false, quality = 2 })
  Stub.DefineItem(3860, "Mithril Bar", { sell = 400, commodity = true })
  Stub.DefineItem(3859, "Steel Bar", { sell = 60, commodity = true })
  Stub.DefineItem(3577, "Gold Bar", { sell = 600, commodity = true })
  Stub.now = Stub.now + 900
  scan(Stub.now, { ["3858"] = { 900, 300 }, ["3575"] = { 1200, 300 }, ["3577"] = { 5000, 100 }, ["2772"] = { 600, 500 } })
  S.estimates = true
  r = Crate.Read(248709)
  eq(r.priced, 3, "all three bundles priced")
  eq(r.bundles[1].src, "crafted", "mithril bars by their crafted cost")
  eq(r.bundles[1].unit, (P.CraftCost(3860)), "which is the ore's")
  eq(r.bundles[2].unit, (P.MarketValue(3575)) + 500, "steel by its iron bar and the vendor's coal")
  eq(r.bundles[2].total, 15 * ((P.MarketValue(3575)) + 500), "fifteen of them")
  eq(r.bundles[3].src, "market", "gold bars from the house")
  eq(r.bundles[1].listed, 0, "no mithril bar is listed")
  eq(r.best, 3, "so gold bars are the fill the house can sell, dearer or not")
  lines = Crate.Lines(r)
  eq(lines[2][1], "  20 Mithril Bar, ~" .. H.Money(r.bundles[1].unit) .. " each, |cffd9cc73none listed|r", "an estimate carries its mark")
  eq(lines[2][2], "~" .. H.Money(r.bundles[1].total), "on the total too")
  eq(lines[4][3], Crate.COLORS.best, "gold bars in green")
  -- estimates off: history or nothing
  S.estimates = false
  r = Crate.Read(248709)
  eq(r.priced, 1, "with estimates off only the gold bars have a price")
  eq(r.bundles[1].unit, nil, "mithril bars have none")
  eq(r.best, nil, "and one price alone is not called the cheapest")
  lines = Crate.Lines(r)
  eq(lines[2][1], "  20 Mithril Bar", "the bundle is still named")
  eq(lines[2][2], "no price", "and says it has no price")
  eq(lines[2][3], Crate.COLORS.none, "in grey")
  eq(lines[4][3], Crate.COLORS.price, "the one price in white")
  S.estimates = true

  -- history older than the two weeks the market value spans still
  -- prices a good: the 30-day mean
  Stub.DefineItem(2776, "Gold Ore", { sell = 500, commodity = true })
  Store.AddScanSample("2776", Stub.now - 20 * 86400, { { p = 4000, q = 30 } })
  local unit, src = Crate.UnitPrice(2776)
  eq(unit, 4000, "a good last seen three weeks ago keeps that price")
  eq(src, "market", "as history")
  r = Crate.Read(248692)
  eq(r.bundles[1].listed, 0, "and reads as not listed now")

  -- a good the client has not loaded goes by the name in the data, and
  -- is asked for, so the next hover has the client's own
  Stub.loadRequests = 0
  r = Crate.Read(248697)
  eq(r.bundles[1].name, "Truesilver Ore", "the data's name stands in")
  eq(r.bundles[3].name, "Dark Iron Ore", "for each good")
  check(Stub.loadRequests >= 3, "and the items are requested: " .. tostring(Stub.loadRequests))
  eq(r.priced, 0, "nothing scanned, nothing priced")
  eq(r.best, nil, "and no cheapest")
  lines = Crate.Lines(r)
  eq(lines[1][1], "|cffe6b800Hound|r any one bundle fills it", "the header still names the rule")
  eq(lines[4][2], "no price", "each bundle says it has no price")
  Stub.DefineItem(7911, "Echtsilbererz", { sell = 1, commodity = true })
  eq(Crate.Read(248697).bundles[1].name, "Echtsilbererz", "the client's name wins once it is there")

  -- before any scan in this market there is no age to give and no
  -- listed count to hold a bundle to
  local m = AuctionHoundDB.markets[H.marketKey]
  local scans = m.scans
  m.scans = {}
  r = Crate.Read(248697)
  eq(r.scanAge, nil, "no scan, no age")
  eq(Crate.Lines(r)[1][2], "no scan yet", "the header says so")
  r = Crate.Read(248687)
  eq(r.bundles[1].listed, nil, "and a price is not held to a scan that never ran")
  eq(Crate.Lines(r)[1][2], "", "nor given an age")
  m.scans = scans

  -- /hound crate prints the same, and names the id of anything else
  Stub.printed = {}
  SlashCmdList.HOUND("crate 248687")
  local out = table.concat(Stub.printed, "\n")
  check(string.find(out, "Waylaid Crate: Journeyman Ore (item 248687)", 1, true), "the command names the crate: " .. out)
  check(string.find(out, "any one bundle fills it, scanned", 1, true), "its header")
  check(string.find(out, "20 Iron Ore, " .. H.Money(600) .. " each: " .. H.Money(12000) .. " (cheapest)", 1, true), "and the cheapest bundle")
  eq(#Stub.printed, 4, "a title, the header and a line per bundle")
  Stub.printed = {}
  SlashCmdList.HOUND("crate |cffffffff|Hitem:248687:0:0:0:0:0:0:0:60:0:0:0:0|h[Waylaid Crate: Journeyman Ore]|h|r")
  check(string.find(table.concat(Stub.printed, "\n"), "Journeyman Ore (item 248687)", 1, true), "a link works as well")
  Stub.printed = {}
  SlashCmdList.HOUND("crate 2770")
  check(string.find(Stub.printed[1] or "", "Copper Ore (item 2770) is not a crate Hound knows", 1, true), "anything else is named with its id: " .. tostring(Stub.printed[1]))
  Stub.printed = {}
  SlashCmdList.HOUND("crate")
  check(string.find(Stub.printed[1] or "", "usage: /hound crate", 1, true), "and a bare command gives its usage")
end

------------------------------------------------------------------------
-- Craftsman's Writs: the item one asks for, priced in its tooltip
------------------------------------------------------------------------
do
  local Writ, Crate = H.Writ, H.Crate
  local S = H.Settings()

  -- the data: 150 writs in one run of IDs, each asking for one thing
  -- no other writ asks for, in three ranks
  local writs, perRank, asked, many = 0, { 0, 0, 0 }, {}, 0
  for id, w in pairs(H.Writs) do
    writs = writs + 1
    local label = "writ " .. tostring(id) .. " / " .. tostring(w[3])
    check(type(id) == "number" and id >= 264011 and id <= 264160, label .. ": in the writs' range")
    check(type(w[1]) == "number" and w[1] > 0 and not H.Writs[w[1]] and not H.Crates[w[1]], label .. ": an item, not a writ or a crate")
    check(type(w[2]) == "number" and w[2] >= 1 and w[2] == math.floor(w[2]), label .. ": whole units")
    check(type(w[3]) == "string" and w[3] ~= "", label .. ": a name to fall back on")
    check(H.WritRanks[w[4]] ~= nil, label .. ": a rank")
    check(asked[w[1]] == nil, label .. ": asked for by one writ only, not also " .. tostring(asked[w[1]]))
    asked[w[1]] = id
    if H.WritRanks[w[4]] then perRank[w[4]] = perRank[w[4]] + 1 end
    if w[2] > 1 then many = many + 1 end
    -- the ranks run in blocks: journeyman, expert, artisan
    eq(w[4], id <= 264055 and 1 or id <= 264115 and 2 or 3, label .. ": ranked by its place in the run")
  end
  eq(writs, 150, "150 writs")
  eq(perRank[1], 45, "45 journeyman")
  eq(perRank[2], 60, "60 expert")
  eq(perRank[3], 45, "45 artisan")
  eq(many, 1, "one writ alone asks for more than one of its item")
  eq(H.WritRanks[1].rep, 75, "a journeyman writ pays 75")
  eq(H.WritRanks[2].rep, 125, "an expert one 125")
  eq(H.WritRanks[3].rep, 200, "an artisan one 200")
  -- as the writs' own quests give them
  eq(H.Writs[264047][1], 5766, "the robe writ asks for the lesser wizard's robe")
  eq(H.Writs[264047][2], 1, "one of it")
  eq(H.Writs[264037][1], 8069, "the shot writ asks for crafted solid shot")
  eq(H.Writs[264037][2], 200, "two hundred of it")
  eq(H.Writs[264011][1], 3391, "the first writ in the run is the ogre strength elixir's")
  eq(H.Writs[264124][1], 246948, "distilled firewater by its Forever id")
  eq(H.Writs[264124][4], 3, "an artisan writ")
  eq(H.Writs[264160][1], 21340, "the last is the soul pouch's")
  eq(H.Writs[262888], nil, "a sealed writ names no item")
  eq(Writ.Read(5766), nil, "a robe is no writ")
  eq(Writ.Read(262888), nil, "nor is a sealed one")
  eq(Writ.Read(248687), nil, "nor a crate")
  eq(Crate.Read(264047), nil, "and a writ is no crate")

  -- Lesser Wizard's Robe: gear, which the scan keys by the level its
  -- link reports. The writ knows only the item's ID and must find it
  Stub.DefineItem(264047, "Craftsman's Writ: Lesser Wizard's Robe", { stack = 1, commodity = false, quality = 3 })
  Stub.DefineItem(5766, "Lesser Wizard's Robe", { stack = 1, commodity = false, quality = 2, equip = "INVTYPE_ROBE", ilvl = 27, sell = 1338 })
  local robeLink = "|cff1eff00|Hitem:5766:0:0:0:0:0:0:0:60:0:0:0:0|h[Lesser Wizard's Robe]|h|r"
  local writLink = "|cff0070dd|Hitem:264047:0:0:0:0:0:0:0:60:0:0:0:0|h[Craftsman's Writ: Lesser Wizard's Robe]|h|r"
  local robeKey = H.KeyFromLink(robeLink, 5766)
  eq(robeKey, "5766:27:0", "the scan files the robe under its level")
  eq(H.KeyForItemID(5766), nil, "which the ID alone does not give")
  local function scan(t, samples)
    for key, listing in pairs(samples) do
      Store.AddScanSample(key, t, { { p = listing[1], q = listing[2] } })
    end
    Store.LogScan({ t = t, kind = "full", rows = 0, keys = 0, secs = 0, skipped = 0 })
  end
  Stub.now = Stub.now + 900
  eq(Writ.Read(264047).unit, nil, "before the robe is ever scanned the writ has no price")
  scan(Stub.now, { [robeKey] = { 12000, 3 } })
  eq(select(2, Store.Plain(5766)), robeKey, "the robe's record is found by its ID")
  eq(#Store.KeysOf(5766), 1, "a key made after the first lookup is known by its item")

  local r = Writ.Read(264047)
  eq(r.item, 5766, "the writ is read: its item")
  eq(r.qty, 1, "one of it")
  eq(r.name, "Lesser Wizard's Robe", "by the client's name")
  eq(r.rank, "Journeyman", "its rank")
  eq(r.rep, 75, "and what it pays")
  eq(r.unit, 12000, "the robe at its market value")
  eq(r.total, 12000, "which is the whole cost")
  eq(r.src, "market", "from history")
  eq(r.listed, nil, "three listed covers one")
  eq(r.scanAge, 0, "the scan is fresh")

  local lines = Writ.Lines(r)
  eq(#lines, 2, "a header and the item")
  eq(lines[1][1], "|cffe6b800Hound|r Journeyman writ, 75 reputation", "the header gives rank and reputation")
  eq(lines[1][2], "scanned 0s ago", "and how old the price is")
  eq(lines[2][1], "  Lesser Wizard's Robe", "one item is only named")
  eq(lines[2][2], H.Money(12000), "with its price on the right")
  eq(lines[2][3], Crate.COLORS.price, "in white")

  -- the writ's tooltip carries them
  GameTooltip:ClearLines()
  Stub.tooltipHandler(GameTooltip, { id = 264047, hyperlink = writLink })
  eq(#GameTooltip.lines, 3, "a blank line, the header and the item: " .. table.concat(GameTooltip.lines, " / "))
  eq(GameTooltip.lines[1], " ", "set apart from the writ's own lines")
  eq(GameTooltip.lines[2], "|cffe6b800Hound|r Journeyman writ, 75 reputation | scanned 0s ago", "the header in the tooltip")
  eq(GameTooltip.lines[3], "  Lesser Wizard's Robe | " .. H.Money(12000), "the robe and its price")
  -- a writ is sold at the house itself: its own history comes first,
  -- what it asks for after
  Stub.now = Stub.now + 900
  scan(Stub.now, { ["264047"] = { 3000, 2 }, [robeKey] = { 12000, 3 } })
  GameTooltip:ClearLines()
  Stub.tooltipHandler(GameTooltip, { id = 264047, hyperlink = writLink })
  local tip = table.concat(GameTooltip.lines, " / ")
  check(string.find(tip, "|cffe6b800Hound|r floor | " .. H.Money(3000), 1, true), "the writ's own floor: " .. tip)
  eq(GameTooltip.lines[#GameTooltip.lines], "  Lesser Wizard's Robe | " .. H.Money(12000), "and the robe's under it")
  eq(GameTooltip.lines[#GameTooltip.lines - 1], "|cffe6b800Hound|r Journeyman writ, 75 reputation | scanned 0s ago", "below the writ's header")
  -- the robe's own tooltip has no writ lines, a comparison tooltip is
  -- left alone, and tooltips off means off
  GameTooltip:ClearLines()
  Stub.tooltipHandler(GameTooltip, { id = 5766, hyperlink = robeLink })
  check(not string.find(table.concat(GameTooltip.lines, " / "), "writ", 1, true), "nothing about writs on the robe itself")
  local other = { lines = {}, AddLine = function(self, t) table.insert(self.lines, t) end, AddDoubleLine = function(self, a) table.insert(self.lines, a) end }
  Stub.tooltipHandler(other, { id = 264047 })
  eq(#other.lines, 0, "only the main tooltips are written on")
  S.tooltip = false
  GameTooltip:ClearLines()
  Stub.tooltipHandler(GameTooltip, { id = 264047, hyperlink = writLink })
  eq(#GameTooltip.lines, 0, "and none at all with tooltips off")
  S.tooltip = true

  -- a scan with no robe in it: the price stands from history, and the
  -- line says there is none to buy
  Stub.now = Stub.now + 900
  scan(Stub.now, { ["264047"] = { 3000, 2 } })
  r = Writ.Read(264047)
  eq(r.unit, 12000, "the robe keeps its price")
  eq(r.listed, 0, "with none in the last scan")
  lines = Writ.Lines(r)
  eq(lines[2][1], "  Lesser Wizard's Robe, |cffd9cc73none listed|r", "none listed")
  eq(lines[2][2], H.Money(12000), "the price still shown")

  -- the robe under its bare ID as well, from a scan the client had no
  -- level for: whichever record was seen last is the robe's, and one
  -- with a suffix is some other robe
  Stub.now = Stub.now + 900
  scan(Stub.now, { ["5766"] = { 9000, 1 }, ["5766:27:1203"] = { 50, 4 } })
  eq(#Store.KeysOf(5766), 3, "three records share the robe's ID")
  eq(select(2, Store.Plain(5766)), "5766", "the bare record is the newer")
  r = Writ.Read(264047)
  eq(r.unit, 9000, "and prices the robe")
  eq(r.listed, nil, "which is listed again")
  Stub.now = Stub.now + 900
  scan(Stub.now, { [robeKey] = { 11000, 2 }, ["5766:27:1203"] = { 50, 4 } })
  eq(select(2, Store.Plain(5766)), robeKey, "then the levelled one again")
  check(Writ.Read(264047).unit > 9000, "never the robe of the suffix: " .. tostring(Writ.Read(264047).unit))

  -- Crafted Solid Shot: the one writ that asks for a stack's worth
  Stub.DefineItem(8069, "Crafted Solid Shot", { stack = 200, commodity = true })
  scan(Stub.now, { ["8069"] = { 4, 500 }, [robeKey] = { 11000, 2 } })
  r = Writ.Read(264037)
  eq(r.qty, 200, "two hundred shot")
  eq(r.unit, 4, "at four copper")
  eq(r.total, 800, "eight silver the lot")
  lines = Writ.Lines(r)
  eq(lines[2][1], "  200 Crafted Solid Shot, " .. H.Money(4) .. " each", "more than one carries its count and the price of each")
  eq(lines[2][2], H.Money(800), "and the total on the right")
  Stub.now = Stub.now + 900
  scan(Stub.now, { ["8069"] = { 4, 120 } })
  r = Writ.Read(264037)
  eq(r.listed, 120, "a hundred and twenty listed where two hundred are asked for")
  check(string.find(Writ.Lines(r)[2][1], "only 120 listed", 1, true), "the line says so: " .. Writ.Lines(r)[2][1])

  -- an estimate carries its mark, as a crate's does
  lines = Writ.Lines({ name = "Unstable Trigger", qty = 1, rank = "Expert", rep = 125, unit = 500, total = 500, src = "crafted", scanAge = 60 })
  eq(lines[1][1], "|cffe6b800Hound|r Expert writ, 125 reputation", "an expert writ's header")
  eq(lines[2][2], "~" .. H.Money(500), "an estimated price is marked")
  lines = Writ.Lines({ name = "Crafted Solid Shot", qty = 200, rank = "Journeyman", rep = 75, unit = 5, total = 1000, src = "crafted", listed = 0, scanAge = 60 })
  eq(lines[2][1], "  200 Crafted Solid Shot, ~" .. H.Money(5) .. " each, |cffd9cc73none listed|r", "on the price of each as well")

  -- an item the client has not loaded goes by the data's name and is
  -- asked for; never scanned, it has no price
  Stub.loadRequests = 0
  r = Writ.Read(264029)
  eq(r.name, "Ornate Spyglass", "the data's name stands in")
  check(Stub.loadRequests >= 1, "and the item is requested")
  eq(r.unit, nil, "nothing scanned, nothing priced")
  eq(r.rank, "Journeyman", "the rank is known all the same")
  lines = Writ.Lines(r)
  eq(lines[2][1], "  Ornate Spyglass", "the item is still named")
  eq(lines[2][2], "no price", "and says it has no price")
  eq(lines[2][3], Crate.COLORS.none, "in grey")
  Stub.DefineItem(5507, "Verziertes Fernrohr", { stack = 1, commodity = false })
  eq(Writ.Read(264029).name, "Verziertes Fernrohr", "the client's name wins once it is there")
  eq(Writ.Read(264152).rank, "Artisan", "an artisan writ by its rank")
  eq(Writ.Read(264152).rep, 200, "and its 200")

  -- before any scan in this market there is no age to give and no
  -- listed count to hold a price to
  local m = AuctionHoundDB.markets[H.marketKey]
  local scans = m.scans
  m.scans = {}
  r = Writ.Read(264029)
  eq(r.scanAge, nil, "no scan, no age")
  eq(Writ.Lines(r)[1][2], "no scan yet", "the header says so")
  r = Writ.Read(264037)
  eq(r.listed, nil, "and a price is not held to a scan that never ran")
  eq(Writ.Lines(r)[1][2], "", "nor given an age")
  m.scans = scans

  -- /hound writ prints the same, and names the id of anything else
  Stub.printed = {}
  SlashCmdList.HOUND("writ 264047")
  local out = table.concat(Stub.printed, "\n")
  check(string.find(out, "Craftsman's Writ: Lesser Wizard's Robe (item 264047)", 1, true), "the command names the writ: " .. out)
  check(string.find(out, "Journeyman writ, 75 reputation, scanned", 1, true), "its header")
  check(string.find(out, "Lesser Wizard's Robe, |cffd9cc73none listed|r: " .. H.Money(Writ.Read(264047).total), 1, true), "and the robe with its price: " .. out)
  eq(#Stub.printed, 3, "a title, the header and the item")
  Stub.printed = {}
  SlashCmdList.HOUND("writ " .. writLink)
  check(string.find(table.concat(Stub.printed, "\n"), "Lesser Wizard's Robe (item 264047)", 1, true), "a link works as well")
  Stub.printed = {}
  SlashCmdList.HOUND("writ 5766")
  check(string.find(Stub.printed[1] or "", "Lesser Wizard's Robe (item 5766) is not a writ Hound knows", 1, true), "anything else is named with its id: " .. tostring(Stub.printed[1]))
  Stub.printed = {}
  SlashCmdList.HOUND("writ")
  check(string.find(Stub.printed[1] or "", "usage: /hound writ", 1, true), "and a bare command gives its usage")
  Stub.printed = {}
  SlashCmdList.HOUND("help")
  check(string.find(table.concat(Stub.printed, "\n"), "/hound writ <link or id>", 1, true), "the help lists the command")
end

------------------------------------------------------------------------
-- Launch: the live client closes the house twice on a walk-away, a
-- beta market may have come along in the saved file, and the TOC
-- names the build the game shipped
------------------------------------------------------------------------
do
  -- AUCTION_HOUSE_CLOSED fires twice when you walk away from the
  -- auctioneer. With a scan, a queued message and a post all in flight,
  -- the second close must find nothing left to do
  local F = H.Fan
  Stub.ah.replicateSilent = true
  AuctionHoundDB.lastFull = Stub.now - H.Scan.FULL_INTERVAL - 1
  F.Reset()
  Stub.SetBag(0, 1, 2770, 40)
  check(F.Setup({ key = "2770", itemID = 2770, center = 100, perBatch = 5, batches = 2, step = 0.05 }) ~= nil, "a fan is planned")
  check(F.PostNext(), "and its first batch sent")
  check(F.pending ~= nil, "the post waits on the house")
  eq(H.Scan.StartFull(), true, "a scan is asked for")
  Stub.ah.ready = false
  H.Throttle.Send(function() end)
  check(H.Throttle.Pending(), "and a message is queued")
  Stub.printed = {}
  local ok, err = pcall(function()
    Stub.FireEvent("AUCTION_HOUSE_CLOSED")
    Stub.FireEvent("AUCTION_HOUSE_CLOSED")
  end)
  check(ok, "two closes in a row raise nothing: " .. tostring(err))
  eq(H.atAH, false, "the house is closed")
  eq(H.Scan.state, "idle", "the scan is dropped")
  check(not H.Throttle.Pending(), "the queue is emptied")
  eq(F.pending, nil, "the post is given up on")
  local told = 0
  for _, line in ipairs(Stub.printed) do
    if string.find(line, "auction house closed before batch", 1, true) then told = told + 1 end
  end
  eq(told, 1, "and said so once, not twice")
  Stub.ah.ready = true
  Stub.ah.replicateSilent = false
  F.Reset()
  Stub.FireEvent("AUCTION_HOUSE_SHOW")
  eq(H.atAH, true, "the house opens again")

  -- markets: the saved file can hold more than this one, the beta's
  -- among them when its saved variables were copied to the live game
  local beta = "US-ClassicBetaPvP2-Alliance"
  AuctionHoundDB.markets[beta] = {
    items = { ["2770"] = "1#D#P#M#F", ["2771"] = "1#D#P#M#F" },
    scans = { { t = Stub.now - 30 * 86400, kind = "full" } }, posts = { { key = "2770" } },
  }
  local mine = H.Store.Count()
  Stub.printed = {}
  SlashCmdList.HOUND("markets")
  local out = table.concat(Stub.printed, "\n")
  check(string.find(out, "2 markets stored", 1, true), "both markets are counted: " .. out)
  check(string.find(out, beta .. ": 2 items, last scan 30d ago", 1, true), "the other market with its items and its age")
  check(string.find(out, H.marketKey .. ": " .. mine .. " items", 1, true), "this market with its own")
  check(string.find(out, "(this one)", 1, true), "and marked as the one in use")
  Stub.printed = {}
  SlashCmdList.HOUND("wipe US-Nowhere-Horde")
  check(string.find(Stub.printed[1] or "", "no market named US-Nowhere-Horde", 1, true), "a name that is not stored erases nothing")
  check(AuctionHoundDB.markets[beta] ~= nil and H.Store.Count() == mine, "neither market touched")
  SlashCmdList.HOUND("wipe " .. beta)
  eq(AuctionHoundDB.markets[beta], nil, "a market named is erased whole")
  eq(H.Store.Count(), mine, "and this market is left as it was")
  check(H.market == AuctionHoundDB.markets[H.marketKey], "still the market in use")

  -- the TOC and the code agree on the version, and the interface is
  -- the one Forever launched with
  local version, interface
  for line in io.lines("AuctionHound/AuctionHound.toc") do
    version = version or string.match(line, "^## Version:%s*(%S+)")
    interface = interface or string.match(line, "^## Interface:%s*(%S+)")
  end
  eq(version, H.VERSION, "TOC and code agree on the version")
  eq(interface, "16001", "interface 16001, patch 1.60.1")
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
