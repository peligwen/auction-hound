-- Scan.lua: talking to the auction house.
--
-- Three kinds of request, one at a time:
--   full     ReplicateItems, the whole AH, throttled to one per 15 minutes
--   browse   paged browse results, one floor price per item key
--   search   every listing for one item key
-- Every request goes through the throttle gate so a dropped message is
-- retried instead of silently lost.
local ADDON, H = ...

local Scan = {}
H.Scan = Scan

local AH = C_AuctionHouse

Scan.state = "idle"
Scan.FULL_INTERVAL = 15 * 60 + 5
Scan.BATCH = 1500
Scan.MAX_RETRIES = 6

-- Rows are processed a batch per frame so a huge listing never freezes
-- the client.
local stepFrame = CreateFrame("Frame")
stepFrame:Hide()
stepFrame:SetScript("OnUpdate", function() Scan.Step() end)

-- Set to false if /hound debug rep shows per-unit buyouts for stacks.
Scan.REPLICATE_BUYOUT_IS_TOTAL = true

local function setState(s)
  Scan.state = s
  H.Events:Fire("SCAN_STATUS")
end

local function sortsByPrice()
  return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

------------------------------------------------------------------------
-- Throttle gate
------------------------------------------------------------------------
local pendingSend = nil
local lastSend = nil

-- Sends are marked as Hound's own so the throttle module leaves their
-- drops to the scanner and replays only Blizzard's.
local function send(fn)
  local T = H.Throttle
  if T then T.sending = true end
  local ok, err = pcall(fn)
  if T then T.sending = false end
  if not ok then error(err, 0) end
end

function Scan.SendWhenReady(fn)
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    pendingSend = fn
    return false
  end
  lastSend = fn
  send(fn)
  return true
end

H.RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  local fn = pendingSend
  pendingSend = nil
  if fn then
    lastSend = fn
    send(fn)
  end
end)

-- Only a scan in flight has anything to retry; a drop while idle is
-- someone else's message, and replaying an old query would clobber
-- whatever the Buy tab is showing.
H.RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
  if Scan.state ~= "idle" and lastSend and not pendingSend then
    pendingSend = lastSend
  end
end)

------------------------------------------------------------------------
-- Watchdog so a lost event never wedges the scanner
------------------------------------------------------------------------
local watchdog

local function armWatchdog(seconds, label)
  if watchdog then watchdog:Cancel() end
  watchdog = C_Timer.NewTimer(seconds, function()
    watchdog = nil
    if Scan.state ~= "idle" then
      H.Printf("%s timed out, resetting", label)
      Scan.Abort()
    end
  end)
end

local function disarmWatchdog()
  if watchdog then watchdog:Cancel() end
  watchdog = nil
end

function Scan.Abort()
  stepFrame:Hide()
  disarmWatchdog()
  pendingSend = nil
  local cb = Scan.browse and Scan.browse.cb
  local scb = Scan.search and Scan.search.cb
  Scan.byKey, Scan.browse, Scan.search = nil, nil, nil
  setState("idle")
  if cb then cb(nil, true) end
  if scb then scb(nil) end
end

H.Events:On("AH_CLOSED", function()
  if Scan.state ~= "idle" then Scan.Abort() end
end)

------------------------------------------------------------------------
-- Full scan
------------------------------------------------------------------------
function Scan.LastFull()
  return (H.db and H.db.lastFull) or 0
end

function Scan.FullScanWait()
  return math.max(0, Scan.FULL_INTERVAL - (H.Now() - Scan.LastFull()))
end

function Scan.FullScanReady()
  if not H.atAH then return false, "not at the auction house" end
  if Scan.state ~= "idle" then return false, "scan in progress" end
  local wait = Scan.FullScanWait()
  if wait > 0 then
    return false, string.format("full scan available in %d:%02d", math.floor(wait / 60), wait % 60)
  end
  return true
end

function Scan.StartFull()
  local ok, why = Scan.FullScanReady()
  if not ok then H.Print(why) return false end
  Scan.startedAt = H.Now()
  setState("replicating")
  armWatchdog(45, "full scan")
  AH.ReplicateItems()
  return true
end

H.RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", function()
  if Scan.state == "replicating" then Scan.BeginProcess() end
end)

local function unitPrice(buyout, count)
  if Scan.REPLICATE_BUYOUT_IS_TOTAL then
    return math.ceil(buyout / count)
  end
  return buyout
end

local function addListing(key, price, count)
  local bucket = Scan.byKey[key]
  if not bucket then
    bucket = {}
    Scan.byKey[key] = bucket
  end
  bucket[price] = (bucket[price] or 0) + count
end

function Scan.ProcessRow(i)
  local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo = AH.GetReplicateItemInfo(i)
  if not itemID or not count or count == 0 then return end
  if not buyout or buyout == 0 then return end
  local link = AH.GetReplicateItemLink(i)
  local key
  if link then
    key = H.KeyFromLink(link, itemID)
  else
    key = H.KeyForItemID(itemID)
  end
  if not key then
    table.insert(Scan.missing, i)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return
  end
  addListing(key, unitPrice(buyout, count), count)
  if name and hasAllInfo then H.Store.SetName(itemID, name) end
end

function Scan.BeginProcess()
  disarmWatchdog()
  setState("processing")
  Scan.total = AH.GetNumReplicateItems() or 0
  Scan.index = 0
  Scan.byKey = {}
  Scan.missing = {}
  Scan.retries = 0
  stepFrame:Show()
end

function Scan.Step()
  if Scan.state ~= "processing" then stepFrame:Hide() return end
  local stop = math.min(Scan.index + Scan.BATCH, Scan.total)
  for i = Scan.index, stop - 1 do Scan.ProcessRow(i) end
  Scan.index = stop
  H.Events:Fire("SCAN_STATUS")
  if Scan.index >= Scan.total then
    stepFrame:Hide()
    Scan.RetryMissing()
  end
end

function Scan.RetryMissing()
  if #Scan.missing == 0 or Scan.retries >= Scan.MAX_RETRIES then
    Scan.Finish()
    return
  end
  Scan.retries = Scan.retries + 1
  local batch = Scan.missing
  Scan.missing = {}
  C_Timer.After(0.5, function()
    if Scan.state ~= "processing" then return end
    for _, i in ipairs(batch) do Scan.ProcessRow(i) end
    Scan.RetryMissing()
  end)
end

function Scan.Finish()
  local t = H.Now()
  local keys, listings = 0, 0
  for key, bucket in pairs(Scan.byKey) do
    local arr = {}
    for price, qty in pairs(bucket) do
      table.insert(arr, { p = price, q = qty })
      listings = listings + 1
    end
    H.Store.AddScanSample(key, t, arr)
    keys = keys + 1
  end
  local skipped = #Scan.missing
  Scan.byKey = nil
  Scan.missing = {}
  if H.db then H.db.lastFull = t end
  H.Store.LogScan({ t = t, kind = "full", rows = Scan.total, keys = keys, secs = t - (Scan.startedAt or t), skipped = skipped })
  H.Store.FlushAsync()
  setState("idle")
  H.Printf("full scan: %d listings, %d items, %d unresolved, %ds", Scan.total, keys, skipped, t - (Scan.startedAt or t))
  H.Events:Fire("SCAN_DONE", "full")
end

------------------------------------------------------------------------
-- Auto scan: with the setting on, a full scan starts whenever one is
-- allowed while the auction house is open. Checked every few seconds
-- and shortly after the house opens.
------------------------------------------------------------------------
Scan.AUTO_INTERVAL = 20

function Scan.AutoTick()
  if not H.Settings().autoScan then return false end
  if not Scan.FullScanReady() then return false end
  return Scan.StartFull()
end

Scan.autoTicker = C_Timer.NewTicker(Scan.AUTO_INTERVAL, Scan.AutoTick)
H.Events:On("AH_OPENED", function() C_Timer.After(3, Scan.AutoTick) end)

function Scan.DebugReplicate(n)
  local total = AH.GetNumReplicateItems and AH.GetNumReplicateItems() or 0
  H.Printf("replicate rows available: %d", total)
  for i = 0, math.min(n, total) - 1 do
    local name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner, _, _, itemID, hasAllInfo = AH.GetReplicateItemInfo(i)
    H.Printf("[%d] %s id=%s count=%s buyout=%s minBid=%s owner=%s all=%s link=%s",
      i, tostring(name), tostring(itemID), tostring(count), tostring(buyout), tostring(minBid),
      tostring(owner), tostring(hasAllInfo), tostring(AH.GetReplicateItemLink(i)))
  end
end

------------------------------------------------------------------------
-- Browse: floor price per item key, paged
------------------------------------------------------------------------
function Scan.Browse(opts, cb)
  if not H.atAH then cb(nil, true) return false, "not at the auction house" end
  if Scan.state ~= "idle" then cb(nil, true) return false, "scan in progress" end
  opts = opts or {}
  Scan.browse = { pages = 0, maxPages = opts.maxPages or 40, cb = cb, results = nil, waiting = true }
  setState("browsing")
  armWatchdog(30, "browse")
  Scan.SendWhenReady(function()
    AH.SendBrowseQuery({
      searchString = opts.search or "",
      sorts = sortsByPrice(),
      filters = {},
      itemClassFilters = {},
      minLevel = 0,
      maxLevel = 0,
    })
  end)
  return true
end

local function browseMore()
  local b = Scan.browse
  if not b or b.waiting then return end
  if AH.HasFullBrowseResults() or b.pages >= b.maxPages then
    Scan.FinishBrowse(not AH.HasFullBrowseResults())
    return
  end
  b.waiting = true
  armWatchdog(30, "browse")
  Scan.SendWhenReady(function() AH.RequestMoreBrowseResults() end)
end

function Scan.FinishBrowse(partial)
  local b = Scan.browse
  Scan.browse = nil
  disarmWatchdog()
  setState("idle")
  if b and b.cb then b.cb(b.results or {}, partial) end
end

H.RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  local b = Scan.browse
  if Scan.state ~= "browsing" or not b then return end
  b.waiting = false
  b.pages = math.max(b.pages, 1)
  b.results = AH.GetBrowseResults()
  H.Events:Fire("SCAN_STATUS")
  browseMore()
end)

H.RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function()
  local b = Scan.browse
  if Scan.state ~= "browsing" or not b then return end
  b.waiting = false
  b.pages = b.pages + 1
  b.results = AH.GetBrowseResults()
  H.Events:Fire("SCAN_STATUS")
  browseMore()
end)

------------------------------------------------------------------------
-- Search: every listing for one item key
-- cb(listings, isCommodity) where listings = { { p, q, auctionID, owners, timeLeft } }
------------------------------------------------------------------------
function Scan.Search(itemKey, cb)
  if not H.atAH then cb(nil) return false, "not at the auction house" end
  if Scan.state ~= "idle" then cb(nil) return false, "scan in progress" end
  Scan.search = { key = itemKey, keyStr = H.KeyString(itemKey), cb = cb }
  setState("searching")
  armWatchdog(20, "search")
  Scan.SendWhenReady(function()
    AH.SendSearchQuery(itemKey, sortsByPrice(), false)
  end)
  return true
end

local function finishSearch(listings, isCommodity)
  local s = Scan.search
  Scan.search = nil
  disarmWatchdog()
  setState("idle")
  if s and s.cb then s.cb(listings, isCommodity) end
end

-- The house's answer to a search, as listings. Depth reads them too.
function Scan.CommodityListings(itemID)
  local listings = {}
  local n = AH.GetNumCommoditySearchResults(itemID) or 0
  for i = 1, n do
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice and r.quantity and r.quantity > 0 then
      table.insert(listings, { p = r.unitPrice, q = r.quantity, auctionID = r.auctionID, timeLeft = r.timeLeftSeconds, owners = r.owners, mine = r.containsOwnerItem })
    end
  end
  return listings
end

function Scan.ItemListings(itemKey)
  local listings = {}
  local n = AH.GetNumItemSearchResults(itemKey) or 0
  for i = 1, n do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 then
      table.insert(listings, { p = r.buyoutAmount, q = r.quantity or 1, auctionID = r.auctionID, timeLeft = r.timeLeft, owners = r.owners, mine = r.containsOwnerItem })
    end
  end
  return listings
end

H.RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  local s = Scan.search
  if Scan.state ~= "searching" or not s or s.key.itemID ~= itemID then return end
  finishSearch(Scan.CommodityListings(itemID), true)
end)

H.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  local s = Scan.search
  if Scan.state ~= "searching" or not s or not itemKey then return end
  if H.KeyString(itemKey) ~= s.keyStr and itemKey.itemID ~= s.key.itemID then return end
  finishSearch(Scan.ItemListings(itemKey), false)
end)
