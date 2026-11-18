-- Fan.lua: fanned auctions. One item posted as a series of batches at
-- a price interval: x units per batch, z batches, the first at the
-- start price and each next one y percent of it dearer. A step of zero
-- puts every batch at the start price, which is how to re-list at one
-- price and land at the front of the queue again.
--
-- Posting needs a hardware event per auction, so one click (or one
-- /hound post) posts one batch and the plan advances.
--
-- Every auction of yours, a batch or one posted from Blizzard's own
-- Sell tab, is kept as a post for the History view with what became of
-- it; a sale is counted from its mail alone.
local ADDON, H = ...

local Fan = {}
H.Fan = Fan

local AH = C_AuctionHouse

Fan.plan = nil        -- the current plan, see Fan.Setup
Fan.pending = nil     -- batch in flight, waiting for AUCTION_HOUSE_AUCTION_CREATED

Fan.DURATIONS = { 12 * 3600, 24 * 3600, 48 * 3600 }   -- index is the API duration value
Fan.POST_TIMEOUT = 10     -- seconds before a post with no reply counts as failed
Fan.SETTLE = 120          -- seconds before a missing auction counts as gone
Fan.OTHERS_GRACE = 3600   -- seconds past its time before another character's post expires

------------------------------------------------------------------------
-- Plan math. Pure, no game state.
--   start     the first batch's unit price, in copper
--   step      the gap between batches as a fraction of the start price
--   batches   z
--   perBatch  x
--   avail     units on hand; batches beyond it are shortened or dropped
--   vendor    vendor sell price, to flag batches that would lose money
-- Batches come back cheapest first, every unit price distinct unless
-- the step is zero.
------------------------------------------------------------------------
function Fan.Plan(o)
  local z = math.max(1, math.floor(o.batches or 1))
  local x = math.max(1, math.floor(o.perBatch or 1))
  local start = o.start
  local stepFrac = math.max(0, o.step or 0)
  local plan = { start = start, step = stepFrac, perBatch = x, requested = z, batches = {} }
  local left = o.avail
  local prev
  for i = 1, z do
    local unit = math.max(1, H.Round(start * (1 + (i - 1) * stepFrac)))
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
  plan.net = H.Round(gross * (1 - (H.Cut and H.Cut() or 0)))
  plan.low = n > 0 and plan.batches[1].unit or nil
  plan.high = n > 0 and plan.batches[n].unit or nil
  return plan
end

-- Where a fan starts when no price is given: the item's latest floor
-- seen, else its market value. Nil without history.
function Fan.DefaultPrice(key)
  local rec = key and H.Store.Get(key)
  local st = rec and H.Market.Stats(rec) or nil
  local p = st and (st.floor or st.market)
  if p and p > 0 then return p end
  return nil
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

-- o: key, and optionally perBatch, step, batches, duration (1..3),
-- start. Missing values come from settings; a missing start is the
-- item's floor (Fan.DefaultPrice). Returns the plan, or nil and a
-- reason.
function Fan.Setup(o)
  if Fan.InProgress() then return nil, "a fan is in progress; reset it first" end
  local key = o.key
  local itemID = o.itemID or H.ItemIDFromKey(key)
  if not key or not itemID then return nil, "no item" end
  local S = H.Settings()
  local count, entry = Fan.BagCount(key)
  local start, src = o.start, "set"
  if not start then start, src = Fan.DefaultPrice(key), "floor" end
  if not start or start <= 0 then return nil, "no price for this item yet; give a start price" end

  local plan = Fan.Plan({
    start = start,
    step = o.step or S.fanStep,
    batches = o.batches or S.fanBatches,
    perBatch = o.perBatch or S.fanPerBatch,
    avail = count,
    vendor = H.VendorSell(itemID),
  })
  planSeq = planSeq + 1
  plan.id = planSeq
  plan.key = key
  plan.itemID = itemID
  plan.name = H.ItemName(itemID)
  plan.startSrc = src
  plan.duration = o.duration or S.postDuration or 3
  if not Fan.DURATIONS[plan.duration] then plan.duration = 3 end
  plan.avail = count
  plan.isCommodity = isCommodity(itemID, entry)
  for _, b in ipairs(plan.batches) do b.deposit = deposit(plan, b, entry) end

  S.fanStep, S.fanBatches, S.fanPerBatch, S.postDuration = plan.step, plan.requested, plan.perBatch, plan.duration

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
    fan = plan.id, batch = b.i, commodity = plan.isCommodity, deposit = b.deposit,
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
  local note = Fan.TakeNote(post.itemID, post.qty, post.unit)
  if note and not post.deposit then post.deposit = note.deposit end
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
-- Own sales. One signal: a seller invoice in the mailbox, naming the
-- item, the units and the price. Nothing else counts as a sale. The
-- owned list says when an auction is off the house, sold or gone,
-- and that marks it "ended" until its mail says what it sold; an
-- auction gone after its time is "expired". Sales were once deduced
-- from an auction gone before its time, and those were as often
-- expiries: Fan.PurgeInferred takes them out of the saved posts.
------------------------------------------------------------------------
function Fan.HasOpenPosts()
  for _, p in ipairs(H.Store.Posts() or {}) do
    if (p.status == "active" or p.status == "pending") and Fan.Mine(p) then return true end
  end
  return false
end

-- Whose a post is. The characters of a realm and faction share the
-- market's posts, and each sees only its own auctions and its own
-- mail, so what one sees settles only its own posts: another's
-- auctions are missing from its list, and another's sales are not in
-- its mailbox. A post saved before posts were kept by character has no
-- one (p.who is nil), and is claimed by the first character whose list
-- or mail shows it.
function Fan.Mine(p, who)
  who = who or H.Who()
  return p.who == who
end

local function markSold(p, soldTotal, now)
  soldTotal = math.min(soldTotal, p.qty)
  local delta = soldTotal - (p.sold or 0)
  if delta <= 0 then return false end
  p.sold = soldTotal
  p.soldAt = now
  H.Printf("sold %d x %s at %s", delta, p.name or p.key, H.Money(p.unit))
  return true
end

-- Every market's posts lose the sales once deduced from an auction
-- gone before its time. The ledger, while a saved file still has one,
-- says how many units of a post were guessed; without it the post's
-- sales all go. A post that was all inferred reads "ended", and its
-- mail can still make it a sale. Safe to run at every load: once
-- purged, nothing is flagged.
function Fan.PurgeInferred(db)
  if type(db) ~= "table" then return 0 end
  local ledger = db.ledger or {}
  local n = 0
  for _, m in pairs(db.markets or {}) do
    for _, p in ipairs(m.posts or {}) do
      if p.inferred then
        local guessed
        for i = #ledger, 1, -1 do
          local e = ledger[i]
          if e.kind == "sale" and e.inferred and e.key == p.key and e.unit == p.unit and e.t == p.soldAt then
            guessed = e.qty
            table.remove(ledger, i)
            break
          end
        end
        p.sold = math.max(0, (p.sold or 0) - (guessed or p.sold or 0))
        p.inferred = nil
        if p.sold == 0 then p.soldAt = nil end
        if p.status == "sold" and p.sold < (p.qty or 0) then p.status = "ended" end
        n = n + 1
      end
    end
  end
  return n
end

local SOLD = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1

------------------------------------------------------------------------
-- Every post, from the fan or from Blizzard's own Sell tab, leaves a
-- note of its deposit and duration for an hour, so the auction can
-- carry them once the owned list names it. The post calls are hooked
-- after the fact; the item is still in the bag until the house answers.
------------------------------------------------------------------------
local notes = {}
Fan.NOTE_TTL = 3600

local function itemIDAt(item)
  if C_Item and C_Item.GetItemID then
    local ok, id = pcall(C_Item.GetItemID, item)
    if ok and id then return id end
  end
  local bag, slot
  if type(item) == "table" then
    if item.GetBagAndSlot then
      local ok, b, sl = pcall(item.GetBagAndSlot, item)
      if ok then bag, slot = b, sl end
    else
      bag, slot = item.bagID, item.slotIndex
    end
  end
  if bag and slot and C_Container and C_Container.GetContainerItemID then
    return C_Container.GetContainerItemID(bag, slot)
  end
  return nil
end

function Fan.NotePost(item, duration, quantity, unit, commodity)
  local itemID = itemIDAt(item)
  if not itemID then return nil end
  local dep
  if commodity then
    if AH.CalculateCommodityDeposit then
      local ok, d = pcall(AH.CalculateCommodityDeposit, itemID, duration, quantity)
      if ok and type(d) == "number" then dep = d end
    end
  elseif AH.CalculateItemDeposit then
    local ok, d = pcall(AH.CalculateItemDeposit, item, duration, quantity)
    if ok and type(d) == "number" then dep = d end
  end
  local note = { t = H.Now(), itemID = itemID, qty = quantity, unit = unit, duration = duration, deposit = dep }
  table.insert(notes, note)
  while #notes > 50 do table.remove(notes, 1) end
  return note
end

-- The note for an auction that has just shown up, removed once taken.
function Fan.TakeNote(itemID, qty, unit, now)
  now = now or H.Now()
  for i = #notes, 1, -1 do
    local n = notes[i]
    if now - n.t > Fan.NOTE_TTL then
      table.remove(notes, i)
    elseif n.itemID == itemID and n.qty == qty and n.unit == unit then
      table.remove(notes, i)
      return n
    end
  end
  return nil
end

if AH and hooksecurefunc then
  if AH.PostCommodity then
    hooksecurefunc(AH, "PostCommodity", function(item, duration, quantity, unitPrice)
      Fan.NotePost(item, duration, quantity, unitPrice, true)
    end)
  end
  if AH.PostItem then
    hooksecurefunc(AH, "PostItem", function(item, duration, quantity, bid, buyout)
      Fan.NotePost(item, duration, quantity, buyout, false)
    end)
  end
end

-- The post record behind one of your auctions, or nil.
function Fan.PostForAuction(auctionID)
  if not auctionID then return nil end
  for _, p in ipairs(H.Store.Posts() or {}) do
    if p.auctionID == auctionID then return p end
  end
  return nil
end

-- Seconds an auction can still run, from the exact figure when the
-- client gives one, else the top of its time-left band.
local BAND_SECONDS = { [0] = 30 * 60, [1] = 2 * 3600, [2] = 12 * 3600, [3] = 48 * 3600 }

local function remaining(a)
  if a.timeLeftSeconds and a.timeLeftSeconds > 0 then return a.timeLeftSeconds end
  return BAND_SECONDS[a.timeLeft] or 48 * 3600
end

-- An auction of ours the store has never seen, posted from Blizzard's
-- own Sell tab or before the addon was installed. It joins the posts so
-- the history covers every auction, with the buyout read the way the
-- owned list gives it: the unit price while the auction is up, the
-- whole sum once it has sold. One already sold joins as ended, for its
-- mail to make it a sale.
local function adopt(a, key, now)
  local unit = a.buyoutAmount
  if not H.db or not unit or unit <= 0 then return false end
  local itemID = a.itemKey.itemID
  local qty = a.quantity or 1
  if a.status == SOLD and qty > 1 then unit = H.Round(unit / qty) end
  local post = {
    id = "a" .. tostring(a.auctionID), t = now, key = key, itemID = itemID, name = H.ItemName(itemID),
    qty = qty, unit = unit, dur = remaining(a), status = "active", sold = 0,
    auctionID = a.auctionID, adopted = true,
  }
  local note = Fan.TakeNote(itemID, qty, unit, now)
  if note then
    post.deposit = note.deposit
    post.dur = Fan.DURATIONS[note.duration] or post.dur
  end
  if a.status == SOLD then post.status = "ended" end
  H.Store.AddPost(post)
  return true
end

-- partial: the list is one page of several, so an auction that is not
-- in it may simply be on a later page.
function Fan.Reconcile(owned, now, partial)
  now = now or H.Now()
  local me = H.Who()
  local posts = H.Store.Posts() or {}
  owned = owned or {}
  local byID = {}
  for _, a in ipairs(owned) do
    if a.auctionID then byID[a.auctionID] = a end
  end

  -- Auctions the list knows and we do not: a fan batch that never got
  -- its id back (matched by its unit price, or by the whole sum once
  -- it has sold), else one to adopt.
  local changed = 0
  for _, a in ipairs(owned) do
    if a.auctionID and a.itemKey then
      local known = false
      for _, p in ipairs(posts) do if p.auctionID == a.auctionID then known = true break end end
      if not known then
        local key = H.KeyFromItemKey(a.itemKey)
        local matched = false
        for _, p in ipairs(posts) do
          local sum = a.status == SOLD and p.unit * (p.qty or 1) or p.unit
          if not p.auctionID and (p.status == "failed" or p.status == "pending") and p.key == key
            and sum == a.buyoutAmount and now - p.t <= 3600 and (p.who == nil or p.who == me) then
            p.auctionID = a.auctionID
            p.status = "active"
            p.who = me
            matched = true
            break
          end
        end
        if not matched and adopt(a, key, now) then changed = changed + 1 end
      end
    end
  end

  -- Off the house: the list says sold, or the auction is gone. Neither
  -- is a sale until its mail is seen. Gone before its time it may have
  -- sold, been cancelled elsewhere or run out early: ended. Gone after
  -- its time it expired. Only this character's own posts are missing
  -- for a reason: another's auctions are never on this list, and its
  -- posts are left alone until well past their time, when no house
  -- still holds them; they expire then, quietly, and the owner's mail
  -- can still make them sales.
  for _, p in ipairs(posts) do
    if p.status == "active" and p.auctionID then
      local a = byID[p.auctionID]
      if a and p.who == nil and me then
        p.who = me
        changed = changed + 1
      end
      if p.who ~= me then
        if now >= p.t + (p.dur or 0) + Fan.OTHERS_GRACE then
          p.status = "expired"
          changed = changed + 1
        end
      elseif a then
        if a.status == SOLD then
          p.status = "ended"
          changed = changed + 1
        end
      elseif not partial and now - p.t >= Fan.SETTLE then
        if now < p.t + (p.dur or 0) - 60 then
          p.status = "ended"
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

-- A neutral house's owned list holds its own auctions, none of the
-- faction house's: read against the posts it would end them all.
H.RegisterEvent("OWNED_AUCTIONS_UPDATED", function()
  if not (AH and AH.GetOwnedAuctions) or H.Neutral() then return end
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
  if not H.atAH or H.Neutral() or not (AH and AH.QueryOwnedAuctions) then return false end
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

-- Every visit asks for the owned list once, so auctions posted from
-- Blizzard's Sell tab are adopted and the history stays current.
H.Events:On("AH_OPENED", function()
  C_Timer.After(2, function() Fan.RefreshOwned(true) end)
end)

H.Events:On("AH_CLOSED", function()
  local p = Fan.pending
  if p then
    finishPost(p, "failed", string.format("auction house closed before batch %d was confirmed", p.batch.i))
  end
end)

-- Seller invoices in the mailbox, the one record of a sale. Visible
-- invoices are matched to posts by item name and unit price, and the
-- units they name are the units sold. The name a post was saved with
-- may be the placeholder of an item the client had yet to load, so the
-- name the client gives now counts too.
local function named(p, itemName)
  return p.name == itemName or (p.itemID ~= nil and H.ItemName(p.itemID) == itemName)
end

-- The post an invoice is for: this character's own, latest first, else
-- one no character has claimed yet (Fan.Mine), which it then claims.
-- Another character's posts are never matched: the mailbox is this
-- character's alone.
local function invoicePost(posts, seen, itemName, unit, me)
  local unclaimed
  for j = #posts, 1, -1 do
    local p = posts[j]
    if p.status ~= "cancelled" and math.abs(p.unit - unit) < 1 and named(p, itemName)
      and (seen[p] or 0) < p.qty then
      if p.who == me then return p end
      if p.who == nil and not unclaimed then unclaimed = p end
    end
  end
  if unclaimed then unclaimed.who = me end
  return unclaimed
end

-- A sale at a neutral house, told by its cut: the neutral houses take
-- 15% (H.NEUTRAL_CUT), a faction's house 5%. Hound keeps no post from a
-- neutral house, and its sales are matched to none, so one there of an
-- item at a price also posted at home sells nothing at home.
function Fan.NeutralSale(total, cut)
  if not cut or cut <= 0 or not total or total <= 0 then return false end
  return cut / total > (H.NEUTRAL_CUT + H.DEFAULTS.cut) / 2
end

function Fan.ScanMail(now)
  if not (GetInboxNumItems and GetInboxInvoiceInfo) then return 0 end
  local posts = H.Store.Posts()
  if not posts or #posts == 0 then return 0 end
  now = now or H.Now()
  local me = H.Who()
  local n = GetInboxNumItems() or 0
  local seen, matched = {}, 0
  for i = 1, n do
    local invoiceType, itemName, _, bid, buyout, _, cut, _, _, _, count = GetInboxInvoiceInfo(i)
    local total = (bid and bid > 0) and bid or (buyout or 0)
    if invoiceType == "seller" and itemName and count and count > 0 and not Fan.NeutralSale(total, cut) then
      local p = invoicePost(posts, seen, itemName, total / count, me)
      if p then
        seen[p] = (seen[p] or 0) + count
        matched = matched + 1
      end
    end
  end
  local changed = false
  for p, units in pairs(seen) do
    units = math.min(units, p.qty)
    if markSold(p, units, now) then changed = true end
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
  if p.status == "sold" then return "sold" end
  if (p.status == "active" or p.status == "ended") and sold > 0 then return string.format("sold %d/%d", sold, p.qty) end
  if p.status == "expired" and sold > 0 then return string.format("%d sold, %d expired", sold, p.qty - sold) end
  return p.status
end

-- A batch: pending, posting, posted or failed.
function Fan.BatchStatus(b)
  if b.status == "active" then return "posted" end
  return b.status
end

------------------------------------------------------------------------
-- Totals over recent posts for the History view: units and gold sold,
-- units that expired, were cancelled, or are still listed.
------------------------------------------------------------------------
function Fan.PostSummary(posts, now, days)
  now = now or H.Now()
  local cutoff = now - (days or H.Market.CLEARING_DAYS) * 86400
  local s = { sold = 0, gold = 0, expired = 0, cancelled = 0, active = 0, n = 0, days = days or H.Market.CLEARING_DAYS }
  for _, p in ipairs(posts or {}) do
    if (p.t or 0) >= cutoff then
      s.n = s.n + 1
      local sold = p.sold or 0
      local left = math.max(0, (p.qty or 0) - sold)
      s.sold = s.sold + sold
      s.gold = s.gold + sold * (p.unit or 0)
      if p.status == "expired" then
        s.expired = s.expired + left
      elseif p.status == "cancelled" then
        s.cancelled = s.cancelled + left
      elseif p.status == "active" or p.status == "pending" then
        s.active = s.active + left
      end
    end
  end
  return s
end

-- s from PostSummary; b, optional, from Buy.Summary over the same days.
function Fan.SummaryLine(s, b)
  local n = (s and s.n or 0) + (b and b.n or 0)
  if n == 0 then return "no auctions recorded yet" end
  local parts = {}
  if s and s.sold > 0 then table.insert(parts, string.format("sold %d for %s", s.sold, H.Money(s.gold))) end
  if b and b.units > 0 then table.insert(parts, string.format("bought %d for %s", b.units, H.Money(b.spent))) end
  if s and s.expired > 0 then table.insert(parts, string.format("%d expired", s.expired)) end
  if s and s.cancelled > 0 then table.insert(parts, string.format("%d cancelled", s.cancelled)) end
  if s and s.active > 0 then table.insert(parts, string.format("%d listed", s.active)) end
  if #parts == 0 then table.insert(parts, string.format("%d auctions", n)) end
  local days = (s and s.days) or (b and b.days) or H.Market.CLEARING_DAYS
  return string.format("%d days: %s", days, table.concat(parts, "  |  "))
end

function Fan.ClearingLine(cl, now)
  if not cl or (cl.soldUnits == 0 and cl.unsoldUnits == 0 and not cl.activeUnits) then return "no sales recorded" end
  now = now or H.Now()
  local parts = {}
  if cl.soldUnits > 0 then
    local s = string.format("sold %d up to %s", cl.soldUnits, H.Money(cl.soldMax))
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
  if not plan then H.Print("no fan planned; /hound fan <link> [per batch] [step %] [batches] [start price]") return end
  H.Printf("fan for %s (%s): %d batches of %d from %s (%s), %s apart, up to %s",
    plan.name, plan.isCommodity and "commodity" or "item", #plan.batches, plan.perBatch,
    H.Money(plan.low or plan.start), plan.startSrc, H.Pct(plan.step), H.Money(plan.high or 0))
  for _, b in ipairs(plan.batches) do
    H.Printf("  %d. %d at %s  %s%s", b.i, b.qty, H.Money(b.unit), Fan.BatchStatus(b), b.belowVendor and "  (under vendor)" or "")
  end
  if plan.short then H.Printf("  only %d units on hand", plan.avail) end
  local nxt = Fan.NextIndex()
  if nxt <= #plan.batches then
    H.Printf("  /hound post posts batch %d", nxt)
  end
end
