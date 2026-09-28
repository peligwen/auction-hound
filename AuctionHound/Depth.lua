-- Depth.lua: the listings behind a Buy tab row, read on demand.
--
-- A browse row carries one price, the floor, and one count, every unit
-- listed. Whether the floor is a stack or a single unit before the
-- price steps up is the difference between a deal and a tease, and
-- only a search for that item answers it. With the Depth toggle on,
-- each row on screen gets one search through the throttle, one at a
-- time, and its ladder is kept for as long as the row still shows the
-- same floor and count. The frame work lives in UI/Browse.lua.
local ADDON, H = ...

local AH = C_AuctionHouse
local D = { cache = {}, wants = {}, order = {} }
H.Depth = D

D.TTL = 300          -- seconds a ladder is trusted with the row unchanged
D.FAIL_TTL = 60      -- seconds before a search that gave nothing is tried again
D.TIMEOUT = 10       -- seconds to wait for the house's answer

local function keyOf(row)
  if type(row) ~= "table" or type(row.itemKey) ~= "table" or not row.itemKey.itemID then return nil end
  return H.KeyString(row.itemKey)
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

-- Asks for a row's depth. Returns the ladder when one is fresh; else
-- the row joins the queue and nil comes back until the answer lands.
function D.Want(row)
  local L = D.Get(row)
  if L then return L end
  local key = keyOf(row)
  if not key or (row.totalQuantity or 0) == 0 then return nil end
  if not D.wants[key] then
    D.wants[key] = { key = key, itemKey = row.itemKey, itemID = row.itemKey.itemID, min = row.minPrice or 0, qty = row.totalQuantity or 0 }
    table.insert(D.order, key)
  else
    local w = D.wants[key]
    w.min, w.qty = row.minPrice or 0, row.totalQuantity or 0
  end
  D.Tick()
  return nil
end

function D.Forget(key)
  if D.wants[key] then
    D.wants[key] = nil
    for i = #D.order, 1, -1 do
      if D.order[i] == key then table.remove(D.order, i) end
    end
  end
end

function D.Clear()
  D.cache, D.wants, D.order = {}, {}, {}
end

-- The gate says whether a search may go out now: the Buy tab decides,
-- since only it knows whether its list is showing and paging.
function D.SetGate(fn)
  D.gate = fn
end

function D.Open()
  if not H.atAH or not H.Settings().browseDepth then return false end
  if H.Scan.state ~= "idle" then return false end
  if D.gate and not D.gate() then return false end
  return true
end

function D.Reading()
  return D.inflight ~= nil or (#D.order > 0 and D.Open())
end

local function sortsByPrice()
  return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

local function nextWant()
  while #D.order > 0 do
    local key = table.remove(D.order, 1)
    local w = D.wants[key]
    D.wants[key] = nil
    if w and not failedRecently(key, w.min, w.qty) then
      local c = D.cache[key]
      local fresh = c and c.L and H.Now() - c.t <= D.TTL and c.min == w.min and c.qty == w.qty
      if not fresh then return w end
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

function D.Finish(w, listings)
  if w.timer then w.timer:Cancel() end
  D.inflight = nil
  local L = listings and #listings > 0 and H.Ladder.Build(listings, w.key, w.itemID) or false
  D.cache[w.key] = { L = L, t = H.Now(), min = w.min, qty = w.qty, listings = L and listings or nil, itemID = w.itemID }
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
  D.Finish(w, H.Scan.CommodityListings(itemID))
end)

H.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  local w = D.inflight
  if not w or not itemKey then return end
  if H.KeyString(itemKey) ~= w.key and itemKey.itemID ~= w.itemID then return end
  D.Finish(w, H.Scan.ItemListings(itemKey))
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
