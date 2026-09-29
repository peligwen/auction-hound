-- Store.lua: per-market price history with a compact string encoding.
--
-- Each item key maps to one string in SavedVariables. Records are decoded
-- lazily on first access and re-encoded at flush time, so login stays
-- fast and the saved file stays small.
--
-- Record layout (decoded):
--   days  = { [dayIndex] = { mv, min, qty, n, s } }   daily aggregates
--   pts   = { { t, mv, min, qty, n }, ... }           recent scan points
--   moved = { [dayIndex] = units }                    consumed-units proxy
local ADDON, H = ...

local Store = {}
H.Store = Store

local cache = {}   -- key -> decoded record
local dirty = {}   -- key -> true

local FORMAT = "1"

------------------------------------------------------------------------
-- Encoding
------------------------------------------------------------------------
-- Numbers go through %.0f, never %d: the client's %d holds a 32-bit
-- integer and raises past it, and 2^31 copper is only 214,748 gold,
-- under one listing posted near the gold cap. %.0f prints any whole
-- number a double holds exactly, up to 2^53. Every field here is
-- already rounded, so the string reads the same.
local function encode(rec)
  local days, pts, moved = {}, {}, {}
  local order = {}
  for d in pairs(rec.days) do table.insert(order, d) end
  table.sort(order)
  for _, d in ipairs(order) do
    local b = rec.days[d]
    table.insert(days, string.format("%.0f:%.0f:%.0f:%.0f:%.0f:%.0f", d, b.mv, b.min, b.qty, b.n, b.s))
  end
  for _, p in ipairs(rec.pts) do
    table.insert(pts, string.format("%.0f:%.0f:%.0f:%.0f:%.0f", math.floor(p.t / 60), p.mv, p.min, p.qty, p.n))
  end
  order = {}
  for d in pairs(rec.moved) do table.insert(order, d) end
  table.sort(order)
  for _, d in ipairs(order) do
    table.insert(moved, string.format("%.0f:%.0f", d, rec.moved[d]))
  end
  return FORMAT .. "#D" .. table.concat(days, ",") .. "#P" .. table.concat(pts, ",") .. "#M" .. table.concat(moved, ",")
end

local function decode(str)
  local rec = { days = {}, pts = {}, moved = {} }
  if type(str) ~= "string" then return rec end
  local daysStr = string.match(str, "#D([^#]*)") or ""
  local ptsStr = string.match(str, "#P([^#]*)") or ""
  local movedStr = string.match(str, "#M([^#]*)") or ""
  for entry in string.gmatch(daysStr, "[^,]+") do
    local d, mv, min, qty, n, s = strsplit(":", entry)
    d = tonumber(d)
    if d then
      rec.days[d] = { mv = tonumber(mv) or 0, min = tonumber(min) or 0, qty = tonumber(qty) or 0, n = tonumber(n) or 0, s = tonumber(s) or 1 }
    end
  end
  for entry in string.gmatch(ptsStr, "[^,]+") do
    local tmin, mv, min, qty, n = strsplit(":", entry)
    tmin = tonumber(tmin)
    if tmin then
      table.insert(rec.pts, { t = tmin * 60, mv = tonumber(mv) or 0, min = tonumber(min) or 0, qty = tonumber(qty) or 0, n = tonumber(n) or 0 })
    end
  end
  for entry in string.gmatch(movedStr, "[^,]+") do
    local d, units = strsplit(":", entry)
    d = tonumber(d)
    if d then rec.moved[d] = tonumber(units) or 0 end
  end
  return rec
end

Store.Encode = encode
Store.Decode = decode

------------------------------------------------------------------------
-- Access
------------------------------------------------------------------------
local function market()
  return H.market
end

function Store.Get(key)
  local rec = cache[key]
  if rec then return rec end
  local m = market()
  if not m then return nil end
  local str = m.items[key]
  if not str then return nil end
  rec = decode(str)
  cache[key] = rec
  return rec
end

function Store.GetOrCreate(key)
  local rec = Store.Get(key)
  if rec then return rec end
  rec = { days = {}, pts = {}, moved = {} }
  cache[key] = rec
  dirty[key] = true
  return rec
end

function Store.Has(key)
  local m = market()
  return cache[key] ~= nil or (m ~= nil and m.items[key] ~= nil)
end

function Store.Count()
  local m = market()
  if not m then return 0 end
  local n = 0
  for _ in pairs(m.items) do n = n + 1 end
  for k in pairs(cache) do
    if not m.items[k] then n = n + 1 end
  end
  return n
end

function Store.Keys()
  local m = market()
  local out, seen = {}, {}
  if m then
    for k in pairs(m.items) do table.insert(out, k); seen[k] = true end
  end
  for k in pairs(cache) do
    if not seen[k] then table.insert(out, k) end
  end
  return out
end

function Store.Touch(key)
  dirty[key] = true
  local rec = cache[key]
  if rec then rec.stats = nil end
end

------------------------------------------------------------------------
-- Ingest one scan sample for a key.
-- listings: array of { p = unit price, q = quantity }
------------------------------------------------------------------------
function Store.AddScanSample(key, t, listings)
  local mv, min, qty, n = H.Market.ValueFromListings(listings)
  if not mv then return nil end
  local rec = Store.GetOrCreate(key)
  local S = H.Settings()
  local day = H.DayIndex(t)

  local b = rec.days[day]
  if b then
    local s = b.s + 1
    b.mv = H.Round((b.mv * b.s + mv) / s)
    b.qty = H.Round((b.qty * b.s + qty) / s)
    b.n = H.Round((b.n * b.s + n) / s)
    if min < b.min then b.min = min end
    b.s = s
  else
    rec.days[day] = { mv = mv, min = min, qty = qty, n = n, s = 1 }
  end

  -- consumed-units proxy: quantity that vanished since a recent scan.
  -- A lower bound, since new listings offset it; gaps over eight hours
  -- are ignored because expiries start to dominate.
  local prev = rec.pts[#rec.pts]
  if prev and t - prev.t <= 8 * 3600 and t > prev.t and prev.qty > qty then
    rec.moved[day] = (rec.moved[day] or 0) + (prev.qty - qty)
  end

  table.insert(rec.pts, { t = t, mv = mv, min = min, qty = qty, n = n })
  local keepPoints = S.keepPoints or 120
  while #rec.pts > keepPoints do table.remove(rec.pts, 1) end

  local keepDays = S.keepDays or 90
  local cutoff = day - keepDays
  for d in pairs(rec.days) do
    if d < cutoff then rec.days[d] = nil end
  end
  for d in pairs(rec.moved) do
    if d < cutoff then rec.moved[d] = nil end
  end

  rec.stats = nil
  dirty[key] = true
  return rec
end

------------------------------------------------------------------------
-- Persistence
------------------------------------------------------------------------
-- A record that will not encode is reported once and skipped, keeping
-- the string saved before it. The flush moves on, so one bad record
-- neither loses the others at logout nor raises the same error every
-- frame until a reload.
local function save(m, key, rec)
  local ok, str = pcall(encode, rec)
  if ok then
    m.items[key] = str
  else
    geterrorhandler()(ADDON .. ": could not save " .. tostring(key) .. ": " .. tostring(str))
  end
  return ok
end

function Store.Flush()
  local m = market()
  if not m then return 0 end
  local n = 0
  for key in pairs(dirty) do
    local rec = cache[key]
    if rec and save(m, key, rec) then n = n + 1 end
  end
  dirty = {}
  return n
end

-- Encode dirty records a few hundred per frame so a big scan never
-- stalls the client. Flush() still does the rest synchronously at logout.
local flushFrame = CreateFrame("Frame")
flushFrame:Hide()
Store.FLUSH_BATCH = 300
flushFrame:SetScript("OnUpdate", function()
  local m = market()
  if not m then flushFrame:Hide() return end
  local n = 0
  for key in pairs(dirty) do
    local rec = cache[key]
    if rec then save(m, key, rec) end
    dirty[key] = nil
    n = n + 1
    if n >= Store.FLUSH_BATCH then return end
  end
  flushFrame:Hide()
end)

function Store.FlushAsync()
  if next(dirty) then flushFrame:Show() end
end

function Store.LogScan(entry)
  local m = market()
  if not m then return end
  table.insert(m.scans, entry)
  while #m.scans > 50 do table.remove(m.scans, 1) end
end

function Store.LastScan()
  local m = market()
  if not m then return nil end
  return m.scans[#m.scans]
end

function Store.SetName(itemID, name)
  if H.db and name then H.db.names[itemID] = name end
end

function Store.Wipe()
  local m = market()
  if m then
    m.items = {}
    m.scans = {}
  end
  cache = {}
  dirty = {}
end

function Store.Ledger(entry)
  if not H.db then return end
  table.insert(H.db.ledger, entry)
  while #H.db.ledger > 500 do table.remove(H.db.ledger, 1) end
end

------------------------------------------------------------------------
-- Our own posts, per market. Plain tables: there are few of them and
-- they are the one record of what buyers actually paid.
------------------------------------------------------------------------
Store.KEEP_POSTS = 400
Store.KEEP_POST_DAYS = 30

local function postList()
  local m = market()
  if not m then return nil end
  m.posts = m.posts or {}
  return m.posts
end

-- All posts, or those for one key, oldest first.
function Store.Posts(key)
  local list = postList()
  if not list then return {} end
  if not key then return list end
  local out = {}
  for _, p in ipairs(list) do
    if p.key == key then table.insert(out, p) end
  end
  return out
end

local function resolved(p)
  return p.status == "sold" or p.status == "expired" or p.status == "cancelled" or p.status == "failed"
end

function Store.PrunePosts(now)
  local list = postList()
  if not list then return end
  now = now or H.Now()
  local cutoff = now - Store.KEEP_POST_DAYS * 86400
  local i = 1
  while i <= #list do
    if resolved(list[i]) and list[i].t < cutoff then table.remove(list, i) else i = i + 1 end
  end
  while #list > Store.KEEP_POSTS do table.remove(list, 1) end
end

function Store.AddPost(post)
  local list = postList()
  if not list then return end
  for _, p in ipairs(list) do
    if p == post then return end
  end
  table.insert(list, post)
  Store.PrunePosts(post.t)
end

------------------------------------------------------------------------
-- Our purchases, per market: plain tables like the posts, what we paid.
------------------------------------------------------------------------
Store.KEEP_BUYS = 400
Store.KEEP_BUY_DAYS = 30

local function buyList()
  local m = market()
  if not m then return nil end
  m.buys = m.buys or {}
  return m.buys
end

-- All purchases, or those for one key, oldest first.
function Store.Buys(key)
  local list = buyList()
  if not list then return {} end
  if not key then return list end
  local out = {}
  for _, b in ipairs(list) do
    if b.key == key then table.insert(out, b) end
  end
  return out
end

function Store.PruneBuys(now)
  local list = buyList()
  if not list then return end
  now = now or H.Now()
  local cutoff = now - Store.KEEP_BUY_DAYS * 86400
  local i = 1
  while i <= #list do
    if (list[i].t or 0) < cutoff then table.remove(list, i) else i = i + 1 end
  end
  while #list > Store.KEEP_BUYS do table.remove(list, 1) end
end

function Store.AddBuy(b)
  local list = buyList()
  if not list then return end
  table.insert(list, b)
  Store.PruneBuys(b.t)
end

-- Test hook: drop the decode cache without touching saved data.
function Store._ResetCache()
  cache = {}
  dirty = {}
end
