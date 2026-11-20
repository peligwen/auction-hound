-- Vendor.lua: buying any number of an item from a vendor in one go.
--
-- A vendor sells one purchase a right-click, and Blizzard's split box
-- on a shift-click stops at what one purchase may hold: 20 coal, so
-- 300 coal is fifteen trips through it. Hound makes those purchases
-- itself, one after another: each waits until the last has landed in
-- the bags, so a stop never leaves more than one on the way, and the
-- count bought is read from the bags, not assumed. It stops on the
-- game's own error (bags full, out of gold), when the vendor's window
-- closes, or when a purchase has gone unanswered for a few seconds.
--
-- Only items priced in gold are bought; anything that costs a currency
-- or another item is left to the vendor's own window. An item sold in
-- bundles (arrows by the 200, say) is bought a bundle a purchase, the
-- way a right-click buys it, and a count is rounded up to whole
-- bundles. The box to ask with is UI/Vendor.lua.
local ADDON, H = ...

local V = { open = false }
H.Vendor = V

V.TICK = 0.1      -- seconds between looks at the bags while buying
V.TIMEOUT = 5     -- a purchase unanswered this long stops the rest

-- The game's errors that end a run, by the name of the global holding
-- the text, and how Hound says it.
V.STOP_ERRORS = {
  { "ERR_INV_FULL", "your bags are full" },
  { "ERR_BAG_FULL", "your bags are full" },
  { "ERR_NOT_ENOUGH_MONEY", "out of gold" },
  { "ERR_ITEM_MAX_COUNT", "you can carry no more of it" },
  { "ERR_VENDOR_SOLD_OUT", "the vendor has no more" },
}

local function itemCount(itemID)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) or 0 end
  if type(GetItemCount) == "function" then return GetItemCount(itemID) or 0 end
  return 0
end

local function money()
  return type(GetMoney) == "function" and GetMoney() or 0
end

local function itemIDAt(index)
  if type(GetMerchantItemID) == "function" then
    local id = GetMerchantItemID(index)
    if id then return id end
  end
  local link = type(GetMerchantItemLink) == "function" and GetMerchantItemLink(index)
  return link and tonumber(string.match(link, "item:(%d+)")) or nil
end

------------------------------------------------------------------------
-- The vendor's items, read. Nil where there is none.
--
--   index, itemID, name
--   price      copper a purchase
--   bundle     units a purchase: 1, or 200 for arrows sold by the 200
--   stock      purchases the vendor has left; nil when it never runs out
--   max        the most units one purchase may hold, as the split box has
--   gold       false when it costs anything but gold
--   buyable    false when the game says you cannot buy it
------------------------------------------------------------------------
function V.Info(index)
  if not index then return nil end
  local name, price, bundle, avail, purchasable, extended
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local i = C_MerchantFrame.GetItemInfo(index)
    if type(i) == "table" then
      name, price, bundle, avail = i.name, i.price, i.stackCount, i.numAvailable
      purchasable, extended = i.isPurchasable, i.hasExtendedCost
    end
  end
  if name == nil and type(GetMerchantItemInfo) == "function" then
    local _
    name, _, price, bundle, avail, purchasable, _, extended = GetMerchantItemInfo(index)
  end
  local itemID = itemIDAt(index)
  if not name or not itemID then return nil end
  bundle = math.max(1, bundle or 1)
  local max = type(GetMerchantItemMaxStack) == "function" and GetMerchantItemMaxStack(index) or 1
  return {
    index = index, itemID = itemID, name = name,
    price = price or 0, bundle = bundle,
    stock = (avail and avail >= 0) and avail or nil,
    max = math.max(1, max or 1),
    gold = not extended,
    buyable = purchasable ~= false,
  }
end

function V.Count()
  return type(GetMerchantNumItems) == "function" and GetMerchantNumItems() or 0
end

-- The vendor's index for an item, and the item read; nil when the
-- vendor does not sell it.
function V.Find(itemID)
  if not itemID then return nil end
  for i = 1, V.Count() do
    if itemIDAt(i) == itemID then return i, V.Info(i) end
  end
  return nil
end

-- The vendor's items whose name holds text, any case. A name that is
-- the text exactly is the only match.
function V.FindByName(text)
  local want = string.lower(text or "")
  if want == "" then return {} end
  local out = {}
  for i = 1, V.Count() do
    local info = V.Info(i)
    if info then
      local name = string.lower(info.name)
      if name == want then return { info } end
      if string.find(name, want, 1, true) then table.insert(out, info) end
    end
  end
  return out
end

-- Units one call buys: a bundle for an item sold in bundles, as a
-- right-click does, else as many as one purchase may hold.
function V.PerCall(info)
  if info.bundle > 1 then return info.bundle end
  return info.max
end

------------------------------------------------------------------------
-- Room in the bags for more of an item: the empty slots of every bag
-- that takes it, a stack's worth each, and what its own stacks there
-- still hold. The reagent bag takes crafting reagents only, and a
-- profession bag only its own kind. An estimate: the game decides.
------------------------------------------------------------------------
local function takes(bag, itemID)
  local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if reagentBag and bag == reagentBag then
    local reagent = C_Item and C_Item.GetItemInfo and select(17, C_Item.GetItemInfo(itemID))
    return reagent and true or false
  end
  if C_Container and C_Container.GetContainerNumFreeSlots then
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    if family and family ~= 0 then
      local mine = C_Item and C_Item.GetItemFamily and C_Item.GetItemFamily(itemID)
      return bit and bit.band and mine and bit.band(mine, family) ~= 0 or false
    end
  end
  return true
end

function V.Room(itemID)
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return nil end
  local stack = H.MaxStack(itemID) or 1
  local room = 0
  for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    if n > 0 and takes(bag, itemID) then
      for slot = 1, n do
        local s = C_Container.GetContainerItemInfo(bag, slot)
        if not s then
          room = room + stack
        elseif s.itemID == itemID then
          room = room + math.max(0, stack - (s.stackCount or 0))
        end
      end
    end
  end
  return room
end

------------------------------------------------------------------------
-- What a count comes to.
--
--   units    the count rounded up to whole bundles
--   cost     copper for them
--   afford   the most units the gold buys; nil for a free item
--   stock    the most units the vendor has; nil when it never runs out
--   room     about how many more the bags hold
--   most     the least of those three: what Max asks for
--   why      what stops the count outright, the gold or the stock
--   warn     the bags, which may be wrong: the purchase is tried anyway
------------------------------------------------------------------------
function V.Plan(info, qty)
  qty = math.max(0, math.floor(tonumber(qty) or 0))
  local purchases = math.ceil(qty / info.bundle)
  local p = { units = purchases * info.bundle, cost = purchases * info.price }
  if info.price > 0 then p.afford = math.floor(money() / info.price) * info.bundle end
  if info.stock then p.stock = info.stock * info.bundle end
  p.room = V.Room(info.itemID)
  for _, cap in pairs({ a = p.afford, s = p.stock, r = p.room }) do
    if not p.most or cap < p.most then p.most = cap end
  end
  if p.most then p.most = math.floor(p.most / info.bundle) * info.bundle end
  if p.afford and p.units > p.afford then
    p.why = string.format("you can afford %d", p.afford)
  elseif p.stock and p.units > p.stock then
    p.why = string.format("the vendor has %d", p.stock)
  elseif p.room and p.units > p.room then
    p.warn = string.format("your bags hold about %d more", p.room)
  end
  return p
end

-- The count the box starts at: the last count bought of the item, else
-- one full stack of it.
function V.DefaultQty(info)
  local last = H.db and H.db.vendorQty and H.db.vendorQty[info.itemID]
  if last and last > 0 then return last end
  local stack = H.MaxStack(info.itemID) or 1
  return math.ceil(stack / info.bundle) * info.bundle
end

function V.Remember(itemID, qty)
  if not H.db or not itemID or not qty or qty <= 0 then return end
  H.db.vendorQty = H.db.vendorQty or {}
  H.db.vendorQty[itemID] = qty
end

------------------------------------------------------------------------
-- The run.
--
--   V.job    itemID, name, price, bundle; want, the units asked for;
--            start, the count in the bags before; sent, units asked of
--            the vendor so far; got, units arrived; sentAt, while a
--            purchase is on its way; stopping, why it is to end
------------------------------------------------------------------------
local function progress()
  H.Events:Fire("VENDOR_PROGRESS", V.job)
end

-- Ends the run and says in chat what it bought. Returns the units.
function V.Finish(why)
  local job = V.job
  V.job = nil
  if V.ticker then
    V.ticker:Cancel()
    V.ticker = nil
  end
  if not job then return 0 end
  local got = math.max(0, itemCount(job.itemID) - job.start)
  local cost = H.Money(math.floor(got / job.bundle) * job.price)
  if why then
    H.Printf("bought %d of %d x %s for %s; stopped: %s", got, job.want, job.name, cost, why)
  else
    H.Printf("bought %d x %s for %s", got, job.name, cost)
  end
  H.Events:Fire("VENDOR_DONE", job, why)
  return got
end

-- One look at the bags: a purchase landed, the run done, or the next
-- purchase made.
function V.Step()
  local job = V.job
  if not job then return end
  job.got = itemCount(job.itemID) - job.start
  if job.sentAt and job.got >= job.sent then job.sentAt = nil end
  if job.got >= job.want then return V.Finish() end
  if job.sentAt then
    if H.Now() - job.sentAt >= V.TIMEOUT then
      return V.Finish(job.stopping or "the vendor stopped answering")
    end
    return
  end
  if job.stopping then return V.Finish(job.stopping) end
  local index, info = V.Find(job.itemID)
  if not info then return V.Finish("the vendor no longer sells it") end
  local n = math.min(V.PerCall(info), job.want - job.sent)
  if info.stock then
    if info.stock <= 0 then return V.Finish("the vendor has no more") end
    n = math.min(n, info.stock * info.bundle)
  end
  if info.price > 0 and money() < (n / info.bundle) * info.price then
    return V.Finish("out of gold")
  end
  job.sent = job.sent + n
  job.last = n
  job.sentAt = H.Now()
  if info.bundle > 1 then
    BuyMerchantItem(index)
  else
    BuyMerchantItem(index, n)
  end
  progress()
end

-- Starts buying qty units of the item at the vendor's index. Returns
-- true, or false and why not.
function V.Start(index, qty)
  if V.job then return false, "still buying " .. V.job.name end
  local info = V.Info(index)
  if not info then return false, "the vendor has nothing there" end
  if not info.gold then return false, info.name .. " costs more than gold; buy it in the vendor's window" end
  if not info.buyable then return false, "you cannot buy " .. info.name end
  local p = V.Plan(info, qty)
  if p.units <= 0 then return false, "nothing to buy" end
  if p.why then return false, p.why end
  V.Remember(info.itemID, math.floor(tonumber(qty) or 0))
  V.job = {
    itemID = info.itemID, name = info.name, price = info.price, bundle = info.bundle,
    want = p.units, start = itemCount(info.itemID), sent = 0, got = 0,
  }
  V.ticker = C_Timer.NewTicker(V.TICK, V.Step)
  V.Step()
  return true
end

-- Ends the run once the purchase on its way has landed.
function V.Stop(why)
  local job = V.job
  if not job then return end
  job.stopping = job.stopping or why or "you stopped it"
  V.Step()
end

function V.IsOpen()
  if V.open then return true end
  return type(MerchantFrame) == "table" and MerchantFrame.IsShown and MerchantFrame:IsShown() and true or false
end

------------------------------------------------------------------------
-- What vendors sell for: a reagent a vendor always has (thread, a vial,
-- flux, salt) is priced at that in a recipe's materials (Craft.lua),
-- whenever it is cheaper than the house. Noted from every vendor
-- window opened, copper a unit, for every character: only gold prices,
-- and only goods the vendor never runs out of, since a limited one is
-- no steady supply. The latest price seen stands.
------------------------------------------------------------------------
function V.NotePrices()
  if not H.db then return 0 end
  H.db.vendorBuy = H.db.vendorBuy or {}
  local n = 0
  for i = 1, V.Count() do
    local info = V.Info(i)
    if info and info.gold and not info.stock and info.price > 0 then
      H.db.vendorBuy[info.itemID] = info.price / info.bundle
      n = n + 1
    end
  end
  return n
end

-- Copper a unit a vendor sells the item for, or nil when no vendor
-- window has shown it.
function H.VendorBuy(itemID)
  local t = H.db and H.db.vendorBuy
  return t and itemID and t[itemID] or nil
end

H.RegisterEvent("MERCHANT_SHOW", function()
  V.open = true
  V.NotePrices()
end)
H.RegisterEvent("MERCHANT_UPDATE", function() if V.open then V.NotePrices() end end)

H.RegisterEvent("MERCHANT_CLOSED", function()
  V.open = false
  V.Stop("the vendor's window closed")
end)

-- The game's error for a purchase it refused: that purchase never
-- lands, so the run ends now. The text comes second on this client,
-- first on older ones.
H.RegisterEvent("UI_ERROR_MESSAGE", function(...)
  local job = V.job
  if not job or not job.sentAt then return end
  for i = 1, select("#", ...) do
    local msg = select(i, ...)
    if type(msg) == "string" then
      for _, e in ipairs(V.STOP_ERRORS) do
        if _G[e[1]] and msg == _G[e[1]] then
          job.sent = job.sent - (job.last or 0)
          job.sentAt = nil
          V.Finish(e[2])
          return
        end
      end
    end
  end
end)
