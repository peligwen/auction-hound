-- Depth.lua: the listings behind a browse row, read on demand.
--
-- A browse row carries one price, the floor, and one count, every unit
-- listed. Whether the floor is a stack or a single unit before the
-- price steps up is the difference between a deal and a tease, and
-- only a search for that item answers it. With the Depth toggle on the
-- Deals view, each row on screen there gets one search through the
-- throttle, one at a time, and its ladder is kept for as long as the
-- row still shows the same floor and count. A row about to be bought
-- is searched first, Depth on or off: buying takes its listings. The
-- Buy tab shows a ladder once one is read and never asks for one. The
-- frame work lives in UI/Deals.lua.
local ADDON, H = ...

local AH = C_AuctionHouse
local D = { cache = {}, wants = {}, order = {}, urgent = {} }
H.Depth = D

D.TTL = 300          -- seconds a ladder is trusted with the row unchanged
D.FAIL_TTL = 60      -- seconds before a search that gave nothing is tried again
D.TIMEOUT = 10       -- seconds to wait for the house's answer

local function keyOf(row)
  if type(row) ~= "table" or type(row.itemKey) ~= "table" or not row.itemKey.itemID then return nil end
  return H.KeyFromItemKey(row.itemKey)
end

-- The ladder for a row, or nil when none is fresh. A row whose floor
-- or count moved since the search is stale: the listings changed.
function D.Get(row)
  local key = keyOf(row)
  local c = key and D.cache[key]
  if not c or not c.L then return nil end
  if H.Now() - c.t > D.TTL then return nil end
  if c.min ~= (row.minPrice or 0) or c.qty ~= (row.totalQuantity or 0) then return nil end
  return c.L
end

-- A recent empty answer holds only while the row still shows the
-- same floor and count; a row that moved is asked again.
local function failedRecently(key, min, qty)
  local c = D.cache[key]
  if not c or c.L or H.Now() - c.t >= D.FAIL_TTL then return false end
  return c.min == min and c.qty == qty
end

-- True when the house answered a recent search for the row with no
-- listings at all, so nothing is coming until it is asked again.
function D.Failed(row)
  local key = keyOf(row)
  return key and failedRecently(key, row.minPrice or 0, row.totalQuantity or 0) or false
end

-- The listings behind a fresh ladder, and whether the house answered
-- them as a commodity, or nil.
function D.Listings(row)
  if not D.Get(row) then return nil end
  local c = D.cache[keyOf(row)]
  return c.listings, c.commodity
end

local function want(row)
  local key = keyOf(row)
  if not key or (row.totalQuantity or 0) == 0 then return nil end
  local w = D.wants[key]
  if not w then
    w = { key = key, itemKey = row.itemKey, itemID = row.itemKey.itemID }
    D.wants[key] = w
  end
  w.min, w.qty = row.minPrice or 0, row.totalQuantity or 0
  return w
end

-- Asks for a row's depth. Returns the ladder when one is fresh; else
-- the row joins the queue and nil comes back until the answer lands.
function D.Want(row)
  local L = D.Get(row)
  if L then return L end
  local w = want(row)
  if not w then return nil end
  local queued = false
  for _, k in ipairs(D.order) do if k == w.key then queued = true break end end
  if not queued then table.insert(D.order, w.key) end
  D.Tick()
  return nil
end

-- The rows on screen, top first, as the queue: a row scrolled away
-- since it was asked for is no longer searched. The search out stays
-- out, and a row about to be bought keeps its place at the front.
function D.SetWanted(rows)
  local keep = {}
  for key in pairs(D.urgent) do keep[key] = D.wants[key] end
  D.wants, D.order = {}, {}
  for key, w in pairs(keep) do
    D.wants[key] = w
    table.insert(D.order, key)
  end
  for _, row in ipairs(rows or {}) do
    if not D.Get(row) then
      local w = want(row)
      if w and not keep[w.key] then table.insert(D.order, w.key) end
    end
  end
  D.Tick()
end

-- A row about to be bought: searched next, Depth on or off, even after
-- an empty answer. Returns the ladder when one is fresh already.
function D.Urgent(row)
  local L = D.Get(row)
  if L then return L end
  local w = want(row)
  if not w then return nil end
  D.urgent[w.key] = true
  w.retry = true
  for i = #D.order, 1, -1 do
    if D.order[i] == w.key then table.remove(D.order, i) end
  end
  table.insert(D.order, 1, w.key)
  D.Tick()
  return nil
end

function D.Forget(key)
  D.urgent[key] = nil
  if D.wants[key] then
    D.wants[key] = nil
    for i = #D.order, 1, -1 do
      if D.order[i] == key then table.remove(D.order, i) end
    end
  end
end

function D.Clear()
  D.cache, D.wants, D.order, D.urgent = {}, {}, {}, {}
end

-- The gate says whether a search may go out now: the Deals view
-- decides, since only it knows whether its list is showing.
function D.SetGate(fn)
  D.gate = fn
end

local function urgentWaiting()
  return next(D.urgent) ~= nil
end

-- Whether a search may go out: at the house, between full scans, and
-- either for a row about to be bought or, with Depth on, while the
-- Deals view shows.
function D.Open()
  if not H.atAH or H.Scan.state ~= "idle" then return false end
  if urgentWaiting() then return true end
  if not H.Settings().browseDepth then return false end
  if D.gate and not D.gate() then return false end
  return true
end

function D.Reading()
  return D.inflight ~= nil or (#D.order > 0 and D.Open())
end

local function sortsByPrice()
  return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

-- With Depth off only a row about to be bought goes out; the rest wait
-- in the queue for the toggle.
local function nextWant()
  local i = 1
  local depthOn = H.Settings().browseDepth and (not D.gate or D.gate())
  while i <= #D.order do
    local key = D.order[i]
    local w = D.wants[key]
    if not w then
      table.remove(D.order, i)
    elseif D.urgent[key] or depthOn then
      table.remove(D.order, i)
      D.wants[key] = nil
      local c = D.cache[key]
      local fresh = c and c.L and H.Now() - c.t <= D.TTL and c.min == w.min and c.qty == w.qty
      if fresh then
        -- read while it waited: whoever asked hears of it, after this
        -- pass through the queue is over
        if D.urgent[key] then
          D.urgent[key] = nil
          C_Timer.After(0, function() H.Events:Fire("DEPTH_UPDATED", key, c.L) end)
        end
      elseif w.retry or not failedRecently(key, w.min, w.qty) then
        return w
      else
        D.urgent[key] = nil
      end
    else
      i = i + 1
    end
  end
  return nil
end

-- One search at a time. The throttle queue sends it when the house is
-- ready; the answer, or the timeout, frees the slot for the next.
function D.Tick()
  if D.inflight or not D.Open() then return false end
  if H.Throttle.Pending() then return false end
  local w = nextWant()
  if not w then return false end
  D.inflight = w
  w.sent = H.Now()
  w.timer = C_Timer.NewTimer(D.TIMEOUT, function()
    if D.inflight == w then D.Finish(w, nil) end
  end)
  H.Throttle.Send(function()
    AH.SendSearchQuery(w.itemKey, sortsByPrice(), false)
  end)
  H.Events:Fire("DEPTH_STATUS")
  return true
end

function D.Finish(w, listings, commodity)
  if w.timer then w.timer:Cancel() end
  D.inflight = nil
  D.urgent[w.key] = nil
  local L = listings and #listings > 0 and H.Ladder.Build(listings, w.key, w.itemID) or false
  D.cache[w.key] = { L = L, t = H.Now(), min = w.min, qty = w.qty, listings = L and listings or nil, itemID = w.itemID, commodity = commodity }
  D.Tick()
  H.Events:Fire("DEPTH_UPDATED", w.key, L)
end

-- A setting that moves the reference or the deal limit (estimates, the
-- minimum discount) changes what a ladder says, not the listings behind
-- it: every ladder held is read again from them, without a search.
function D.Rebuild()
  local changed = false
  for key, c in pairs(D.cache) do
    if c.L and c.listings then
      c.L = H.Ladder.Build(c.listings, key, c.itemID)
      changed = true
    end
  end
  if changed then H.Events:Fire("DEPTH_UPDATED") end
end

H.RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  local w = D.inflight
  if not w or w.itemID ~= itemID then return end
  D.Finish(w, H.Scan.CommodityListings(itemID), true)
end)

H.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  local w = D.inflight
  if not w or not itemKey then return end
  if H.KeyFromItemKey(itemKey) ~= w.key and itemKey.itemID ~= w.itemID then return end
  D.Finish(w, H.Scan.ItemListings(itemKey), false)
end)

H.RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() D.Tick() end)
H.Events:On("SCAN_STATUS", function() if H.Scan.state == "idle" then D.Tick() end end)
H.Events:On("SCAN_DONE", D.Clear)
H.Events:On("AH_OPENED", D.Clear)
H.Events:On("SETTINGS_CHANGED", D.Rebuild)
H.Events:On("AH_CLOSED", function()
  local w = D.inflight
  if w and w.timer then w.timer:Cancel() end
  D.inflight = nil
  D.Clear()
end)
