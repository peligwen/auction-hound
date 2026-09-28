-- Fan.lua: price fanning. Post one item as a series of batches at spaced
-- prices, then watch which batches sell.
--
-- Scans tell us what sellers ask. The only sure sign of what buyers pay
-- is a sale of our own, so every batch is a probe: a batch that sells
-- says the market clears at or above that price, a batch that expires
-- says it does not. The outcomes are kept per item and the next fan
-- centers on what actually sold.
--
-- A fan is x units per batch, z batches, y apart. Linear spacing puts
-- the batches at even steps. Bell spacing keeps the same range but
-- places batches at normal quantiles, so they bunch near the center
-- with a few probes out at the tails.
--
-- Posting needs a hardware event per auction, so one click (or one
-- /hound post) posts one batch and the plan advances.
local ADDON, H = ...

local Fan = {}
H.Fan = Fan

local AH = C_AuctionHouse

Fan.plan = nil        -- the current plan, see Fan.Setup
Fan.pending = nil     -- batch in flight, waiting for AUCTION_HOUSE_AUCTION_CREATED

Fan.SHAPES = { "linear", "bell" }
Fan.SPREADS = { "around", "above", "below" }
Fan.DURATIONS = { 12 * 3600, 24 * 3600, 48 * 3600 }   -- index is the API duration value
Fan.POST_TIMEOUT = 10     -- seconds before a post with no reply counts as failed
Fan.SETTLE = 120          -- seconds before a missing auction counts as gone
Fan.RECENT_SALE = 14 * 86400

------------------------------------------------------------------------
-- Inverse normal CDF, Acklam's rational approximation. Accurate to
-- about 1e-9, which is far more than a price ladder needs.
------------------------------------------------------------------------
local A = { -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00 }
local B = { -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01 }
local C = { -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00 }
local D = { 7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00 }

function Fan.NormalQuantile(p)
  if p <= 0 then return -math.huge end
  if p >= 1 then return math.huge end
  if p < 0.02425 then
    local q = math.sqrt(-2 * math.log(p))
    return (((((C[1] * q + C[2]) * q + C[3]) * q + C[4]) * q + C[5]) * q + C[6])
      / ((((D[1] * q + D[2]) * q + D[3]) * q + D[4]) * q + 1)
  elseif p <= 1 - 0.02425 then
    local q = p - 0.5
    local r = q * q
    return (((((A[1] * r + A[2]) * r + A[3]) * r + A[4]) * r + A[5]) * r + A[6]) * q
      / (((((B[1] * r + B[2]) * r + B[3]) * r + B[4]) * r + B[5]) * r + 1)
  else
    local q = math.sqrt(-2 * math.log(1 - p))
    return -(((((C[1] * q + C[2]) * q + C[3]) * q + C[4]) * q + C[5]) * q + C[6])
      / ((((D[1] * q + D[2]) * q + D[3]) * q + D[4]) * q + 1)
  end
end

------------------------------------------------------------------------
-- Plan math. Pure, no game state.
------------------------------------------------------------------------

-- Positions of z batches in step units, centered on zero.
--   linear  -2, -1, 0, 1, 2
--   bell    same end points, the rest at normal quantiles so the
--           middle batches sit closer together
function Fan.Positions(z, shape)
  local out = {}
  if z <= 1 then out[1] = 0 return out end
  local half = (z - 1) / 2
  if shape == "bell" then
    local edge = Fan.NormalQuantile((z - 0.5) / z)
    for i = 1, z do
      out[i] = Fan.NormalQuantile((i - 0.5) / z) / edge * half
    end
  else
    for i = 1, z do out[i] = i - 1 - half end
  end
  return out
end

-- Build a plan.
--   center    anchor price in copper
--   step      gap between batches as a fraction of center; zero puts
--             every batch at the center, which is how to re-list at
--             one price and land at the front of the queue again
--   batches   z
--   perBatch  x
--   shape     linear | bell
--   spread    around (center in the middle) | above (center is the
--             cheapest batch) | below (center is the dearest)
--   avail     units on hand; batches beyond it are shortened or dropped
--   vendor    vendor sell price, to flag batches that would lose money
-- Batches come back cheapest first, every unit price distinct unless
-- the step is zero.
function Fan.Plan(o)
  local z = math.max(1, math.floor(o.batches or 1))
  local x = math.max(1, math.floor(o.perBatch or 1))
  local center = o.center
  local stepFrac = math.max(0, o.step or 0)
  local step = stepFrac * center
  local shape = o.shape == "bell" and "bell" or "linear"
  local spread = o.spread
  if spread ~= "above" and spread ~= "below" then spread = "around" end
  local pos = Fan.Positions(z, shape)
  local shift = 0
  if spread == "above" then shift = -pos[1] elseif spread == "below" then shift = -pos[z] end

  local plan = { center = center, step = stepFrac, shape = shape, spread = spread, perBatch = x, requested = z, batches = {} }
  local left = o.avail
  local prev
  for i = 1, z do
    local unit = math.max(1, H.Round(center + (pos[i] + shift) * step))
    if stepFrac > 0 and prev and unit <= prev then unit = prev + 1 end
    prev = unit
    local qty = x
    if left then
      qty = math.min(x, left)
      left = left - qty
    end
    if qty > 0 then
      table.insert(plan.batches, {
        i = i, unit = unit, qty = qty, status = "pending",
        belowVendor = (o.vendor ~= nil and unit <= o.vendor) or false,
      })
    end
  end

  local n = #plan.batches
  plan.short = o.avail ~= nil and (n < z or (n > 0 and plan.batches[n].qty < x)) or false
  local units, gross = 0, 0
  for _, b in ipairs(plan.batches) do
    units = units + b.qty
    gross = gross + b.qty * b.unit
  end
  plan.units = units
  plan.gross = gross
  plan.net = H.Round(gross * (1 - ((H.Settings and H.Settings().cut) or 0)))
  plan.low = n > 0 and plan.batches[1].unit or nil
  plan.high = n > 0 and plan.batches[n].unit or nil
  return plan
end

------------------------------------------------------------------------
-- What to center on when the user does not say: the best price buyers
-- paid us recently, else the market value, else a prior.
------------------------------------------------------------------------
function Fan.Anchor(key, itemID, now)
  now = now or H.Now()
  itemID = itemID or H.ItemIDFromKey(key)
  local cl = H.Market.Clearing(H.Store.Posts(key), now)
  if cl and cl.soldMax and cl.lastSoldAt and now - cl.lastSoldAt <= Fan.RECENT_SALE then
    return cl.soldMax, "sold"
  end
  local rec = H.Store.Get(key)
  local st = rec and H.Market.Stats(rec, now) or nil
  if st and st.market then return st.market, "market" end
  local prior, src = H.Priors.Estimate(itemID)
  if prior then return prior, src end
  return nil, "none"
end

------------------------------------------------------------------------
-- Bags
------------------------------------------------------------------------
local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
  return 0
end

local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return info.itemID, info.stackCount or 1, info.hyperlink, info.isLocked
  elseif GetContainerItemInfo then
    local _, count, locked, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
    return itemID, count or 1, link, locked
  end
  return nil
end

local function locationFor(stack)
  if ItemLocation and ItemLocation.CreateFromBagAndSlot then
    return ItemLocation:CreateFromBagAndSlot(stack.bag, stack.slot)
  end
  return { bagID = stack.bag, slotIndex = stack.slot }
end

local function sellable(stack)
  if not (AH and AH.IsSellItemValid) then return true end
  local ok, valid = pcall(AH.IsSellItemValid, locationFor(stack), false)
  if not ok then return true end
  return valid ~= false
end

-- Every stack in the bags that could be posted, grouped by history key.
-- Returns { [key] = { key, itemID, count, stacks = { { bag, slot, count } } } }
function Fan.Bags()
  local out = {}
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for bag = 0, last do
    for slot = 1, numSlots(bag) do
      local itemID, count, link, locked = slotInfo(bag, slot)
      if itemID and count and count > 0 and not locked then
        local key = link and H.KeyFromLink(link, itemID) or H.KeyForItemID(itemID)
        local stack = { bag = bag, slot = slot, count = count }
        if key and sellable(stack) then
          local e = out[key]
          if not e then
            e = { key = key, itemID = itemID, count = 0, stacks = {} }
            out[key] = e
          end
          e.count = e.count + count
          table.insert(e.stacks, stack)
        end
      end
    end
  end
  return out
end

function Fan.BagCount(key)
  local e = Fan.Bags()[key]
  return e and e.count or 0, e
end

-- Commodity or item decides which post call to make. Ask about the bag
-- stack first (the sell frame's own check), then the item key, then
-- guess from the stack size.
local function isCommodity(itemID, entry)
  local c
  if entry and entry.stacks[1] then c = H.CommodityStatusAt(locationFor(entry.stacks[1])) end
  if c == nil then c = H.CommodityStatus(itemID) end
  if c ~= nil then return c end
  local stack = H.MaxStack(itemID)
  if stack then return stack > 1 and not H.IsEquippable(itemID) end
  return not H.IsEquippable(itemID)
end

------------------------------------------------------------------------
-- Setting up a plan for an item on hand
------------------------------------------------------------------------
-- Index of the next batch to post: the first with no live auction.
function Fan.NextIndex()
  local plan = Fan.plan
  if not plan then return 1 end
  for i, b in ipairs(plan.batches) do
    if not b.post or b.post.status == "failed" then return i end
  end
  return #plan.batches + 1
end

-- True once some batches are posted and others are not.
function Fan.InProgress()
  local plan = Fan.plan
  if not plan then return false end
  if Fan.pending then return true end
  local posted = false
  for _, b in ipairs(plan.batches) do
    if b.post and b.post.status ~= "failed" then posted = true break end
  end
  return posted and Fan.NextIndex() <= #plan.batches
end

local function deposit(plan, b, entry)
  if not AH then return nil end
  if plan.isCommodity then
    if AH.CalculateCommodityDeposit then
      local ok, d = pcall(AH.CalculateCommodityDeposit, plan.itemID, plan.duration, b.qty)
      if ok and type(d) == "number" then return d end
    end
  elseif AH.CalculateItemDeposit and entry and entry.stacks[1] then
    local ok, d = pcall(AH.CalculateItemDeposit, locationFor(entry.stacks[1]), plan.duration, b.qty)
    if ok and type(d) == "number" then return d end
  end
  return nil
end

local planSeq, postSeq = 0, 0

-- o: key, and optionally perBatch, step, batches, shape, spread,
-- duration (1..3), center. Missing values come from settings; a missing
-- center comes from Fan.Anchor. Returns the plan, or nil and a reason.
function Fan.Setup(o)
  if Fan.InProgress() then return nil, "a fan is in progress; reset it first" end
  local key = o.key
  local itemID = o.itemID or H.ItemIDFromKey(key)
  if not key or not itemID then return nil, "no item" end
  local S = H.Settings()
  local count, entry = Fan.BagCount(key)
  local center, src = o.center, "set"
  if not center then center, src = Fan.Anchor(key, itemID) end
  if not center or center <= 0 then return nil, "no reference price for this item; give a center price" end

  local plan = Fan.Plan({
    center = center,
    step = o.step or S.fanStep,
    batches = o.batches or S.fanBatches,
    perBatch = o.perBatch or S.fanPerBatch,
    shape = o.shape or S.fanShape,
    spread = o.spread or S.fanSpread,
    avail = count,
    vendor = H.Priors.VendorSell(itemID),
  })
  planSeq = planSeq + 1
  plan.id = planSeq
  plan.key = key
  plan.itemID = itemID
  plan.name = H.ItemName(itemID)
  plan.centerSrc = src
  plan.duration = o.duration or S.postDuration or 3
  if not Fan.DURATIONS[plan.duration] then plan.duration = 3 end
  plan.avail = count
  plan.isCommodity = isCommodity(itemID, entry)
  for _, b in ipairs(plan.batches) do b.deposit = deposit(plan, b, entry) end

  S.fanStep, S.fanBatches, S.fanPerBatch = plan.step, plan.requested, plan.perBatch
  S.fanShape, S.fanSpread, S.postDuration = plan.shape, plan.spread, plan.duration

  Fan.plan = plan
  Fan.pending = nil
  H.Events:Fire("FAN_UPDATED")
  return plan
end

function Fan.Reset()
  if Fan.pending and Fan.pending.timer then Fan.pending.timer:Cancel() end
  Fan.plan = nil
  Fan.pending = nil
  H.Events:Fire("FAN_UPDATED")
end

------------------------------------------------------------------------
-- Posting, one batch per call
------------------------------------------------------------------------
local function pickStack(entry, qty, commodity)
  if not entry then return nil end
  local best
  for _, s in ipairs(entry.stacks) do
    if commodity then
      if s.count >= qty then return s end
      if not best or s.count > best.count then best = s end
    else
      if not best then best = s end
    end
  end
  return best
end

local function finishPost(p, status, why)
  if p.timer then p.timer:Cancel() end
  Fan.pending = nil
  p.batch.status = status
  if status == "failed" then p.post.status = "failed" end
  if why then H.Print(why) end
  H.Events:Fire("FAN_UPDATED")
  H.Events:Fire("SCAN_STATUS")
end

function Fan.PostNext()
  local plan = Fan.plan
  if not plan then H.Print("no fan planned; pick an item first") return false end
  if not H.atAH then H.Print("open the auction house first") return false end
  if Fan.pending then H.Print("still posting the last batch") return false end
  local b = plan.batches[Fan.NextIndex()]
  if not b then H.Print("fan complete") return false end
  if not (AH and (AH.PostCommodity or AH.PostItem)) then H.Print("posting is not available in this client") return false end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    H.Print("the auction house is busy, try again in a moment")
    return false
  end
  local _, entry = Fan.BagCount(plan.key)
  local stack = pickStack(entry, b.qty, plan.isCommodity)
  if not stack then H.Printf("no %s left in your bags", plan.name) return false end
  local qty = plan.isCommodity and math.min(b.qty, entry.count) or math.min(b.qty, stack.count)
  if qty < 1 then H.Printf("no %s left in your bags", plan.name) return false end

  postSeq = postSeq + 1
  local post = {
    id = H.Now() * 100 + (postSeq % 100), t = H.Now(), key = plan.key, itemID = plan.itemID, name = plan.name,
    qty = qty, unit = b.unit, dur = Fan.DURATIONS[plan.duration], status = "pending", sold = 0,
    fan = plan.id, batch = b.i, commodity = plan.isCommodity,
  }
  local p = { post = post, batch = b, plan = plan }
  Fan.pending = p
  b.status = "posting"
  b.post = post
  p.timer = C_Timer.NewTimer(Fan.POST_TIMEOUT, function()
    if Fan.pending == p then
      H.Store.AddPost(post)
      finishPost(p, "failed", string.format("no reply from the auction house for batch %d; check your auctions", b.i))
    end
  end)
  if plan.isCommodity then
    AH.PostCommodity(locationFor(stack), plan.duration, qty, b.unit)
  else
    AH.PostItem(locationFor(stack), plan.duration, qty, nil, b.unit)
  end
  H.Events:Fire("FAN_UPDATED")
  H.Events:Fire("SCAN_STATUS")
  return true
end

H.RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED", function(auctionID)
  local p = Fan.pending
  if not p then return end
  local post = p.post
  post.auctionID = auctionID
  post.status = "active"
  H.Store.AddPost(post)
  local total = #p.plan.batches
  finishPost(p, "active")
  H.Printf("posted %d x %s at %s each (%d of %d)%s", post.qty, post.name, H.Money(post.unit),
    p.batch.i, total, Fan.NextIndex() > total and "; fan complete" or "")
end)

H.RegisterEvent("AUCTION_HOUSE_SHOW_ERROR", function()
  local p = Fan.pending
  if not p then return end
  finishPost(p, "failed", string.format("the auction house refused batch %d", p.batch.i))
end)

------------------------------------------------------------------------
-- Own sales. Three signals, any of which may arrive first:
--   owned auctions   status Sold, or fewer units than we posted
--   vanished early   an auction gone before it could expire was bought
--   mail             a seller invoice names the item, units and price
------------------------------------------------------------------------
function Fan.HasOpenPosts()
  for _, p in ipairs(H.Store.Posts() or {}) do
    if p.status == "active" or p.status == "pending" then return true end
  end
  return false
end

local function markSold(p, soldTotal, inferred, now)
  soldTotal = math.min(soldTotal, p.qty)
  local delta = soldTotal - (p.sold or 0)
  if delta <= 0 then return false end
  p.sold = soldTotal
  p.soldAt = now
  p.inferred = inferred and true or nil
  H.Store.Ledger({ t = now, key = p.key, itemID = p.itemID, qty = delta, unit = p.unit, kind = "sale", inferred = inferred or nil })
  H.Printf("sold %d x %s at %s%s", delta, p.name or p.key, H.Money(p.unit), inferred and " (inferred)" or "")
  return true
end

local SOLD = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1

-- partial: the list is one page of several, so an auction that is not
-- in it may simply be on a later page.
function Fan.Reconcile(owned, now, partial)
  now = now or H.Now()
  local posts = H.Store.Posts()
  if not posts or #posts == 0 then return 0 end
  owned = owned or {}
  local byID = {}
  for _, a in ipairs(owned) do
    if a.auctionID then byID[a.auctionID] = a end
  end

  -- adopt auctions we posted but never got an id for
  for _, a in ipairs(owned) do
    if a.auctionID and a.itemKey then
      local known = false
      for _, p in ipairs(posts) do if p.auctionID == a.auctionID then known = true break end end
      if not known then
        local key = H.KeyString(a.itemKey)
        for _, p in ipairs(posts) do
          if not p.auctionID and (p.status == "failed" or p.status == "pending") and p.key == key
            and p.unit == a.buyoutAmount and now - p.t <= 3600 then
            p.auctionID = a.auctionID
            p.status = "active"
            break
          end
        end
      end
    end
  end

  local changed = 0
  for _, p in ipairs(posts) do
    if p.status == "active" and p.auctionID then
      local a = byID[p.auctionID]
      if a then
        local soldNow
        if a.status == SOLD then
          soldNow = p.qty
        elseif a.quantity and a.quantity < p.qty then
          soldNow = p.qty - a.quantity
        end
        if soldNow and markSold(p, soldNow, false, now) then changed = changed + 1 end
        if a.status == SOLD and p.status ~= "sold" then
          p.status = "sold"
          changed = changed + 1
        end
      elseif not partial and now - p.t >= Fan.SETTLE then
        if now < p.t + (p.dur or 0) - 60 then
          markSold(p, p.qty, true, now)
          p.status = "sold"
        else
          p.status = "expired"
          if (p.sold or 0) < p.qty then
            H.Printf("%d x %s at %s expired unsold", p.qty - (p.sold or 0), p.name or p.key, H.Money(p.unit))
          end
        end
        changed = changed + 1
      end
    end
  end
  if changed > 0 then H.Events:Fire("FAN_UPDATED") end
  return changed
end

H.RegisterEvent("OWNED_AUCTIONS_UPDATED", function()
  if not (AH and AH.GetOwnedAuctions) then return end
  local full = true
  if AH.HasFullOwnedAuctionResults then full = AH.HasFullOwnedAuctionResults() end
  Fan.Reconcile(AH.GetOwnedAuctions(), nil, not full)
  if not full and AH.RequestMoreOwnedAuctions then
    C_Timer.After(0.5, function()
      if not H.atAH then return end
      if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then return end
      AH.RequestMoreOwnedAuctions()
    end)
  end
end)

H.RegisterEvent("AUCTION_CANCELED", function(auctionID)
  if not auctionID then return end
  for _, p in ipairs(H.Store.Posts() or {}) do
    if p.auctionID == auctionID and p.status == "active" then
      p.status = "cancelled"
      H.Events:Fire("FAN_UPDATED")
      return
    end
  end
end)

local function sortsByPrice()
  return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

-- Ask for the owned auction list. force skips the open-posts check.
function Fan.RefreshOwned(force, retries)
  if not H.atAH or not (AH and AH.QueryOwnedAuctions) then return false end
  if not force and not Fan.HasOpenPosts() then return false end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    retries = retries or 0
    if retries < 3 then
      C_Timer.After(3, function() Fan.RefreshOwned(force, retries + 1) end)
    end
    return false
  end
  AH.QueryOwnedAuctions(sortsByPrice())
  return true
end

H.Events:On("AH_OPENED", function()
  C_Timer.After(2, function() Fan.RefreshOwned() end)
end)

H.Events:On("AH_CLOSED", function()
  local p = Fan.pending
  if p then
    finishPost(p, "failed", string.format("auction house closed before batch %d was confirmed", p.batch.i))
  end
end)

-- Seller invoices in the mailbox. Visible invoices are matched to posts
-- by item name and unit price; a match confirms an inferred sale and
-- raises the sold count when the owned list has not caught up.
function Fan.ScanMail(now)
  if not (GetInboxNumItems and GetInboxInvoiceInfo) then return 0 end
  local posts = H.Store.Posts()
  if not posts or #posts == 0 then return 0 end
  now = now or H.Now()
  local n = GetInboxNumItems() or 0
  local seen, matched = {}, 0
  for i = 1, n do
    local invoiceType, itemName, _, bid, buyout, _, _, _, _, _, count = GetInboxInvoiceInfo(i)
    if invoiceType == "seller" and itemName and count and count > 0 then
      local total = (bid and bid > 0) and bid or (buyout or 0)
      local unit = total / count
      for j = #posts, 1, -1 do
        local p = posts[j]
        if p.name == itemName and p.status ~= "cancelled" and math.abs(p.unit - unit) < 1
          and (seen[p] or 0) < p.qty then
          seen[p] = (seen[p] or 0) + count
          matched = matched + 1
          break
        end
      end
    end
  end
  local changed = false
  for p, units in pairs(seen) do
    units = math.min(units, p.qty)
    if units > (p.sold or 0) then
      markSold(p, units, false, now)
      changed = true
    elseif p.inferred and units >= (p.sold or 0) then
      p.inferred = nil
      changed = true
    end
    if (p.sold or 0) >= p.qty and p.status ~= "sold" then
      p.status = "sold"
      changed = true
    end
  end
  if changed then H.Events:Fire("FAN_UPDATED") end
  return matched
end

H.RegisterEvent("MAIL_INBOX_UPDATE", function() Fan.ScanMail() end)

------------------------------------------------------------------------
-- Words for the UI and chat
------------------------------------------------------------------------
function Fan.PostStatus(p)
  local sold = p.sold or 0
  if p.status == "sold" then return p.inferred and "sold (inferred)" or "sold" end
  if p.status == "active" and sold > 0 then return string.format("sold %d/%d", sold, p.qty) end
  if p.status == "expired" and sold > 0 then return string.format("%d sold, %d expired", sold, p.qty - sold) end
  return p.status
end

function Fan.BatchStatus(b)
  if b.post and b.post.status ~= "pending" then return Fan.PostStatus(b.post) end
  return b.status
end

function Fan.ClearingLine(cl, now)
  if not cl or (cl.soldUnits == 0 and cl.unsoldUnits == 0 and not cl.activeUnits) then return "no sales recorded" end
  now = now or H.Now()
  local parts = {}
  if cl.soldUnits > 0 then
    local s = string.format("sold %d up to %s", cl.soldUnits, H.Money(cl.soldMax))
    if cl.inferredUnits > 0 then s = s .. string.format(" (%d inferred)", cl.inferredUnits) end
    if cl.lastSoldAt then s = s .. ", last " .. H.Ago(now - cl.lastSoldAt) end
    table.insert(parts, s)
  end
  if cl.unsoldUnits > 0 then
    table.insert(parts, string.format("%d unsold from %s", cl.unsoldUnits, H.Money(cl.unsoldMin)))
  end
  if cl.activeUnits and cl.activeUnits > 0 then
    table.insert(parts, string.format("%d listed", cl.activeUnits))
  end
  return table.concat(parts, ", ")
end

function Fan.Describe()
  local plan = Fan.plan
  if not plan then H.Print("no fan planned; /hound fan <link> [per batch] [step %] [batches] [bell] [above|below]") return end
  H.Printf("fan for %s (%s): %d batches of %d, %s %s, center %s (%s), %s to %s",
    plan.name, plan.isCommodity and "commodity" or "item", #plan.batches, plan.perBatch, plan.shape, plan.spread,
    H.Money(plan.center), plan.centerSrc, H.Money(plan.low or 0), H.Money(plan.high or 0))
  for _, b in ipairs(plan.batches) do
    H.Printf("  %d. %d at %s  %s%s", b.i, b.qty, H.Money(b.unit), Fan.BatchStatus(b), b.belowVendor and "  (under vendor)" or "")
  end
  if plan.short then H.Printf("  only %d units on hand", plan.avail) end
  local nxt = Fan.NextIndex()
  if nxt <= #plan.batches then
    H.Printf("  /hound post posts batch %d", nxt)
  end
end
