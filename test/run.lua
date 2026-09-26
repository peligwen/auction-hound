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

local H = Stub.LoadAddon(".")
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
end

------------------------------------------------------------------------
-- Tooltip and slash commands
------------------------------------------------------------------------
do
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 2770, hyperlink = "|cffffffff|Hitem:2770:0:0:0:0:0:0:0:60:0:0:0:0|h[Copper Ore]|h|r" })
  check(#GameTooltip.lines >= 3, "tooltip lines added: " .. #GameTooltip.lines)
  check(string.find(GameTooltip.lines[2], "market"), "tooltip has market line")
  GameTooltip.lines = {}
  Stub.tooltipHandler(GameTooltip, { id = 424242 })
  eq(#GameTooltip.lines, 0, "no tooltip lines without history")

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
  ok, err = pcall(H.UI.Toggle)
  check(ok, "window toggles: " .. tostring(err))
  ok, err = pcall(H.UI.ShowView, "markets")
  check(ok, "markets view: " .. tostring(err))
  ok, err = pcall(H.UI.ShowItem, "2770")
  check(ok, "item view: " .. tostring(err))
  ok, err = pcall(H.UI.ShowView, "snipe")
  check(ok, "snipe view: " .. tostring(err))
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
  function AuctionHouseFrame:SetDisplayMode(mode) self.displayMode = mode end
  PanelTemplates_SetNumTabs = function() end
  ok, err = pcall(function() H.Events:Fire("AH_UI_LOADED") end)
  check(ok, "auction house hook: " .. tostring(err))
  eq(#AuctionHouseFrame.Tabs, 4, "tab added")
  AuctionHouseFrame:SetDisplayMode(H.UI.displayMode)
  check(AuctionHoundPanel.shown, "panel shown in the auction house")
  AuctionHouseFrame:SetDisplayMode({ "SearchBar" })
  check(not AuctionHoundPanel.shown, "panel hidden on another tab")

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
