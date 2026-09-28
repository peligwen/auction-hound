-- Throttle.lua: one queue for the auction house's throttled messages.
--
-- The house answers one throttled message at a time. Sending another
-- before the ready event drops it on the floor with no retry, so
-- everything Hound sends from the Buy tab goes through this queue,
-- which sends the next message only when the system says it is ready.
--
-- Blizzard's own frames send their queries straight away. While one of
-- ours is in flight, a click on a row or a new search would be dropped
-- and the buy frame left empty, so the queries they send are watched
-- and, when the drop event follows one, sent again once ready.
local ADDON, H = ...

local AH = C_AuctionHouse
local T = { queue = {} }
H.Throttle = T

T.REPLAY_WINDOW = 1.5   -- a drop this soon after a foreign query is that query

function T.Ready()
  return not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady() and true or false
end

function T.Pending()
  return #T.queue > 0
end

-- Runs fn, marking the messages it sends as ours.
local function run(fn)
  T.sending = true
  local ok, err = pcall(fn)
  T.sending = false
  if not ok then H.Print("throttled send failed: " .. tostring(err)) end
end

-- Sends now when the system is ready and nothing waits ahead of it,
-- else after the ready event, in order. Returns true when sent now.
function T.Send(fn)
  if T.Ready() and not T.Pending() then
    run(fn)
    return true
  end
  table.insert(T.queue, fn)
  return false
end

function T.Cancel(fn)
  for i = #T.queue, 1, -1 do
    if T.queue[i] == fn then table.remove(T.queue, i) end
  end
end

function T.Clear()
  T.queue = {}
  T.foreign = nil
end

H.RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  local fn = table.remove(T.queue, 1)
  if fn then run(fn) end
end)

------------------------------------------------------------------------
-- Foreign queries: Blizzard's, or another addon's. The last one seen
-- is replayed when a drop follows it closely.
------------------------------------------------------------------------
local function watch(name)
  if type(AH[name]) ~= "function" then return end
  hooksecurefunc(AH, name, function(...)
    if T.sending then return end
    local args = { ... }
    T.foreign = { name = name, args = args, n = select("#", ...), t = H.Now() }
  end)
end

T.WATCHED = { "SendSearchQuery", "SendBrowseQuery", "RequestMoreBrowseResults", "SendSellSearchQuery" }

for _, name in ipairs(T.WATCHED) do watch(name) end

H.RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
  local f = T.foreign
  if not f or H.Now() - f.t > T.REPLAY_WINDOW then return end
  T.foreign = nil
  T.replayed = (T.replayed or 0) + 1
  T.Send(function() AH[f.name](unpack(f.args, 1, f.n)) end)
end)

H.Events:On("AH_CLOSED", T.Clear)
