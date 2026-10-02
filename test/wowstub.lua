-- test/wowstub.lua: just enough of the WoW client to load and exercise
-- the addon headlessly under Lua 5.1.
local Stub = {}

------------------------------------------------------------------------
-- Globals the addon expects
------------------------------------------------------------------------
function strsplit(delim, str, limit)
  local out = {}
  local start = 1
  while true do
    local i = string.find(str, delim, start, true)
    if not i or (limit and #out >= limit - 1) then
      table.insert(out, string.sub(str, start))
      break
    end
    table.insert(out, string.sub(str, start, i - 1))
    start = i + #delim
  end
  return unpack(out)
end

function strjoin(delim, ...) return table.concat({ ... }, delim) end

-- The client's string.format keeps a %d argument in a 32-bit integer
-- and raises past it, where this Lua prints the number whole. Enforced
-- here so a copper value handed to %d fails the tests the way it failed
-- in the beta: 2^31 copper is only 214,748 gold.
local rawformat = string.format
function string.format(fmt, ...)
  local n = 0
  for conv in string.gmatch(fmt, "%%[-+ #0]*%d*%.?%d*([%a%%])") do
    if conv ~= "%" then
      n = n + 1
      if conv == "d" or conv == "i" then
        local v = tonumber((select(n, ...)))
        if v and (v > 2147483647 or v < -2147483648) then
          error(rawformat("integer overflow attempting to store %.0f", v), 2)
        end
      end
    end
  end
  return rawformat(fmt, ...)
end

-- Errors handed to the client's handler instead of raised.
Stub.errors = {}
function geterrorhandler()
  return function(msg) table.insert(Stub.errors, msg) if Stub.echo then print(msg) end end
end

function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
tremove = table.remove
UISpecialFrames = {}
SlashCmdList = {}
UIParent = nil

Stub.printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(Stub.printed, msg) if Stub.echo then print(msg) end end }

Stub.now = 1760000000
function GetServerTime() return Stub.now end
time = function() return Stub.now end
date = function(fmt, t) return os.date(fmt, t) end

function GetCurrentRegion() return 1 end
function GetNormalizedRealmName() return "ClassicBetaPvP2" end
function UnitFactionGroup() return "Horde" end

Enum = {
  AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 },
  ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
  AuctionHouseTimeLeftBand = { Short = 0, Medium = 1, Long = 2, VeryLong = 3 },
  AuctionStatus = { Active = 0, Sold = 1 },
  TooltipDataType = { Item = 0 },
}

------------------------------------------------------------------------
-- Bags and mail
------------------------------------------------------------------------
NUM_BAG_SLOTS = 4
Stub.bags = {}         -- [bag][slot] = { itemID, count, suffix }
Stub.bagSlots = 16

function Stub.SetBag(bag, slot, itemID, count, opts)
  Stub.bags[bag] = Stub.bags[bag] or {}
  if not itemID or (count or 0) <= 0 then
    Stub.bags[bag][slot] = nil
  else
    Stub.bags[bag][slot] = { itemID = itemID, count = count, suffix = opts and opts.suffix or 0 }
  end
end

function Stub.BagCount(itemID)
  local n = 0
  for _, slots in pairs(Stub.bags) do
    for _, s in pairs(slots) do if s.itemID == itemID then n = n + s.count end end
  end
  return n
end

local function stackLink(s)
  local it = Stub.items[s.itemID]
  return string.format("|cffffffff|Hitem:%d:0:0:0:0:0:%d:0:60:0:0:0:0|h[%s]|h|r", s.itemID, s.suffix or 0, it and it.name or "?")
end

-- Take units out of the bags, the given slot first, then any other
-- stack of the same item. Returns the units actually removed.
local function takeFromBags(bag, slot, qty)
  local s = Stub.bags[bag] and Stub.bags[bag][slot]
  if not s then return 0 end
  local itemID, taken = s.itemID, 0
  local function take(b, sl, st)
    local n = math.min(st.count, qty - taken)
    st.count = st.count - n
    taken = taken + n
    if st.count == 0 then Stub.bags[b][sl] = nil end
  end
  take(bag, slot, s)
  for b, slots in pairs(Stub.bags) do
    for sl, st in pairs(slots) do
      if taken < qty and st.itemID == itemID then take(b, sl, st) end
    end
  end
  return taken
end

C_Container = {
  GetContainerNumSlots = function(bag) return Stub.bagSlots end,
  GetContainerItemID = function(bag, slot)
    local s = Stub.bags[bag] and Stub.bags[bag][slot]
    return s and s.itemID or nil
  end,
  GetContainerItemInfo = function(bag, slot)
    local s = Stub.bags[bag] and Stub.bags[bag][slot]
    if not s then return nil end
    return { itemID = s.itemID, stackCount = s.count, hyperlink = stackLink(s), isLocked = false, iconFileID = 134400 }
  end,
}

ItemLocation = {
  CreateFromBagAndSlot = function(_, bag, slot)
    return { bagID = bag, slotIndex = slot, IsValid = function() return true end }
  end,
}
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5

Stub.mail = {}         -- array of { invoiceType, itemName, bid, buyout, count }
function GetInboxNumItems() return #Stub.mail, #Stub.mail end
function GetInboxInvoiceInfo(i)
  local m = Stub.mail[i]
  if not m then return nil end
  return m.invoiceType, m.itemName, m.playerName or "Buyer", m.bid or 0, m.buyout or 0, m.deposit or 0,
    m.consignment or 0, 0, 0, 0, m.count or 1, m.commerce or false
end

------------------------------------------------------------------------
-- Item database used by C_Item
------------------------------------------------------------------------
Stub.items = {}
function Stub.DefineItem(id, name, opts)
  opts = opts or {}
  Stub.items[id] = { name = name, sell = opts.sell or 0, equip = opts.equip or "", stack = opts.stack or 20, commodity = opts.commodity, quality = opts.quality or 1, ilvl = opts.ilvl or 1, loaded = opts.loaded ~= false }
end

C_Item = {
  GetItemInfo = function(id)
    id = tonumber(string.match(tostring(id), "(%d+)"))
    local it = Stub.items[id]
    if not it or not it.loaded then return nil end
    return it.name, "item:" .. id, it.quality, it.ilvl, 1, "Trade Goods", "Metal", it.stack, it.equip, 134400, it.sell
  end,
  GetItemInfoInstant = function(id)
    id = tonumber(string.match(tostring(id), "(%d+)"))
    local it = Stub.items[id]
    if not it or not it.loaded then return nil end
    return id, "Trade Goods", "Metal", it.equip, 134400, 7, 0
  end,
  GetDetailedItemLevelInfo = function(link)
    local id = tonumber(string.match(tostring(link), "item:(%d+)"))
    local it = Stub.items[id]
    return it and it.ilvl or 0
  end,
  GetItemIconByID = function() return 134400 end,
  GetItemID = function(loc)
    local s = type(loc) == "table" and Stub.bags[loc.bagID] and Stub.bags[loc.bagID][loc.slotIndex]
    return s and s.itemID or nil
  end,
  GetItemQualityColor = function(q) return 1, 1, 1, "ffffffff" end,
  RequestLoadItemDataByID = function(id)
    Stub.loadRequests = (Stub.loadRequests or 0) + 1
    local it = Stub.items[id]
    if it then it.loaded = true end
  end,
}

C_CurrencyInfo = { GetCoinTextureString = function(c) return tostring(c) .. "c*" end }

------------------------------------------------------------------------
-- Timers
------------------------------------------------------------------------
Stub.timers = {}
local function newTimer(delay, fn, iterations)
  local t = { due = Stub.now + delay, fn = fn, interval = iterations and delay or nil, remaining = iterations, cancelled = false, delay = delay }
  if iterations == nil and delay ~= nil and t.interval == nil then t.once = true end
  function t:Cancel() self.cancelled = true end
  function t:IsCancelled() return self.cancelled end
  table.insert(Stub.timers, t)
  return t
end
C_Timer = {
  After = function(delay, fn) newTimer(delay, fn) end,
  NewTimer = function(delay, fn) return newTimer(delay, fn) end,
  NewTicker = function(delay, fn, iterations)
    local t = newTimer(delay, fn)
    t.once = false
    t.interval = delay
    t.remaining = iterations
    return t
  end,
}

Stub.frames = {}

-- Run timers that are due, then one OnUpdate for every shown frame.
function Stub.RunTimers()
  local ran = 0
  for _, f in ipairs(Stub.frames) do
    if f.shown and f.scripts.OnUpdate then
      f.scripts.OnUpdate(f, 0.016)
      ran = ran + 1
    end
  end
  local list = Stub.timers
  for _, t in ipairs(list) do
    if not t.cancelled and t.due <= Stub.now then
      t.fn(t)
      ran = ran + 1
      if t.once then
        t.cancelled = true
      else
        t.due = Stub.now + t.interval
        if t.remaining then
          t.remaining = t.remaining - 1
          if t.remaining <= 0 then t.cancelled = true end
        end
      end
    end
  end
  local keep = {}
  for _, t in ipairs(Stub.timers) do if not t.cancelled then table.insert(keep, t) end end
  Stub.timers = keep
  return ran
end

function Stub.Advance(seconds)
  local target = Stub.now + seconds
  while Stub.now < target do
    Stub.now = math.min(target, Stub.now + 1)
    Stub.RunTimers()
  end
end

-- Pump zero-delay tickers until none run
function Stub.Pump(max)
  for _ = 1, max or 1000 do
    if Stub.RunTimers() == 0 then return end
  end
end

------------------------------------------------------------------------
-- Frames: a permissive object that records events and scripts
------------------------------------------------------------------------
Stub.eventFrames = {}
local Frame = {}
-- Unknown CamelCase names are treated as no-op widget methods; anything
-- else is a plain data field and reads as nil, as it would in the client.
Frame.__index = function(t, k)
  local v = rawget(Frame, k)
  if v ~= nil then return v end
  if type(k) == "string" and string.match(k, "^[A-Z]") then
    return function() return nil end
  end
  return nil
end

local function newObject(kind)
  local o = setmetatable({ kind = kind, scripts = {}, events = {}, shown = true, children = {}, width = 400, height = 300, text = "", points = {} }, Frame)
  return o
end

function Frame:RegisterEvent(e) self.events[e] = true Stub.eventFrames[self] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn) local old = self.scripts[name] self.scripts[name] = function(...) if old then old(...) end fn(...) end end
function Frame:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:CreateTexture() return newObject("Texture") end
function Frame:CreateFontString() return newObject("FontString") end
function Frame:SetText(t) self.text = t end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #tostring(self.text or "") * 6 end
function Frame:SetSize(w, h) self.width, self.height = w, h if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end end
function Frame:SetWidth(w) self.width = w end
function Frame:SetHeight(h) self.height = h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetParent(p) self.parent = p end
function Frame:GetParent() return self.parent end
function Frame:SetPoint(...) table.insert(self.points, { ... }) end
function Frame:ClearAllPoints() self.points = {} end
function Frame:GetNumPoints() return #self.points end
function Frame:GetPoint(i) local p = self.points[i or 1] if p then return unpack(p, 1, 5) end end
function Frame:EnableMouse(v) self.mouse = v end
function Frame:IsMouseEnabled() return self.mouse == true end
-- levels are relative to the parent, as the client keeps them
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel()
  if self.level then return self.level end
  local p = self.parent
  return (type(p) == "table" and p.GetFrameLevel and p:GetFrameLevel() or 0) + 1
end
function Frame:SetScale(s) self.scale = s end
function Frame:GetEffectiveScale()
  local p = self.parent
  return (self.scale or 1) * (type(p) == "table" and p.GetEffectiveScale and p:GetEffectiveScale() or 1)
end
function Frame:SetID(id) self.id = id end
function Frame:GetID() return self.id end
function Frame:SetChecked(v) self.checked = v end
function Frame:Click(button) local fn = self.scripts.OnClick if fn then fn(self, button or "LeftButton") end end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:GetChecked() return self.checked end
function Frame:SetValue(v) self.value = v if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
function Frame:GetValue() return self.value or 0 end
function Frame:GetFontString() return self.fontString end
function Frame:GetNormalTexture() return newObject("Texture") end

function Frame:GetItem() return nil end
function Frame:EnableKeyboard(v) self.keyboard = v end
function Frame:SetPropagateKeyboardInput(v) self.propagate = v end

function CreateFrame(kind, name, parent, template)
  if template and Stub.badTemplates and Stub.badTemplates[template] then
    error("Couldn't find inherited node: " .. template)
  end
  local f = newObject(kind)
  f.name = name
  f.parent = parent
  f.template = template
  table.insert(Stub.frames, f)
  if template == "UIPanelButtonTemplate" then f.fontString = newObject("FontString") end
  local t = template and Stub.templates[template]
  if t then
    if t.mixin and _G[t.mixin] then
      for k, v in pairs(_G[t.mixin]) do f[k] = v end
    end
    for _, key in ipairs(t.fontStrings) do f[key] = newObject("FontString") end
  end
  if name then _G[name] = f end
  return f
end

function Mixin(obj, ...)
  for i = 1, select("#", ...) do
    for k, v in pairs((select(i, ...))) do obj[k] = v end
  end
  return obj
end

function CreateFromMixins(...)
  return Mixin({}, ...)
end

function IsShiftKeyDown() return Stub.shift == true end
Stub.cursor = { 500, 300 }   -- screen pixels, from the bottom left
function GetCursorPosition() return Stub.cursor[1], Stub.cursor[2] end
function InCombatLockdown() return Stub.combat == true end
function GetMoney() return Stub.money or 100000000 end

function ExecuteFrameScript(frame, name, ...)
  local fn = frame:GetScript(name)
  if fn then fn(frame, ...) end
end

-- Blizzard_SharedXML/TableBuilder.lua: a row's hover reaches every
-- cell it holds, so a cell without OnLineEnter crashes the row. The
-- client raises "attempt to call a nil value"; so does this.
TableBuilderElementMixin = {}
function TableBuilderElementMixin:Init() end
function TableBuilderElementMixin:Populate() end

TableBuilderCellMixin = CreateFromMixins(TableBuilderElementMixin)
function TableBuilderCellMixin:OnLineEnter() end
function TableBuilderCellMixin:OnLineLeave() end

TableBuilderRowMixin = CreateFromMixins(TableBuilderElementMixin)
function TableBuilderRowMixin:OnLineEnter() end
function TableBuilderRowMixin:OnLineLeave() end
function TableBuilderRowMixin:OnEnter()
  self:OnLineEnter()
  for _, cell in ipairs(self.cells) do
    local fn = rawget(cell, "OnLineEnter")
    if not fn then error("attempt to call a nil value (method 'OnLineEnter')") end
    fn(cell)
  end
end
function TableBuilderRowMixin:OnLeave()
  self:OnLineLeave()
  for _, cell in ipairs(self.cells) do
    local fn = rawget(cell, "OnLineLeave")
    if not fn then error("attempt to call a nil value (method 'OnLineLeave')") end
    fn(cell)
  end
end

function hooksecurefunc(tbl, name, fn)
  if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
  local orig = tbl[name]
  tbl[name] = function(...)
    local r = { orig(...) }
    fn(...)
    return unpack(r)
  end
end

-- The house's throttle, when a test turns Stub.ah.throttleModel on: a
-- send while busy is dropped with the drop event and never answered;
-- otherwise the system is busy until the answer lands, then ready
-- again with the ready event. Off, sends go straight through as before.
function Stub.Throttled(deliver)
  if not Stub.ah.throttleModel then
    deliver(function() end)
    return
  end
  if not Stub.ah.ready then
    Stub.ah.dropped = (Stub.ah.dropped or 0) + 1
    C_Timer.After(0, function() Stub.FireEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED") end)
    return
  end
  Stub.ah.ready = false
  deliver(function()
    Stub.ah.ready = true
    Stub.FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  end)
end

function Stub.FireEvent(event, ...)
  for f in pairs(Stub.eventFrames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------
local function newTooltip()
  local t = newObject("GameTooltip")
  t.lines = {}
  function t:AddLine(text) table.insert(self.lines, tostring(text)) end
  function t:AddDoubleLine(a, b) table.insert(self.lines, tostring(a) .. " | " .. tostring(b)) end
  function t:ClearLines() self.lines = {} end
  function t:SetOwner() end
  function t:SetItemByID(id) self.itemID = id end
  return t
end
GameTooltip = newTooltip()
ItemRefTooltip = newTooltip()
TooltipDataProcessor = {
  AddTooltipPostCall = function(kind, fn) Stub.tooltipHandler = fn end,
}

------------------------------------------------------------------------
-- Auction house
------------------------------------------------------------------------
Stub.ah = {
  replicate = {},        -- array of rows { itemID, count, buyout, name, link, hasAllInfo, minBid }
  browse = {},           -- array of BrowseResultInfo
  browsePageSize = 3,
  browseServed = 0,
  searchResults = {},    -- keyStr -> { commodity = bool, listings = { {unitPrice, quantity, auctionID} } }
  ready = true,
  purchases = {},
  commodityPrice = {},   -- itemID -> quoted unit price
  posted = {},           -- our posts: { auctionID, itemID, qty, unit, duration, commodity, bag, slot }
  owned = {},            -- OwnedAuctionInfo rows returned by GetOwnedAuctions
  nextAuctionID = 9000,
  ownedQueries = 0,
}

local function postAuction(loc, duration, qty, unit, commodity)
  local s = Stub.bags[loc.bagID] and Stub.bags[loc.bagID][loc.slotIndex]
  if not s then Stub.FireEvent("AUCTION_HOUSE_SHOW_ERROR", 1) return end
  local itemID, suffix = s.itemID, s.suffix or 0
  local it = Stub.items[itemID]
  if Stub.BagCount(itemID) < qty then
    C_Timer.After(1, function() Stub.FireEvent("AUCTION_HOUSE_SHOW_ERROR", 1) end)
    return
  end
  Stub.ah.nextAuctionID = Stub.ah.nextAuctionID + 1
  local id = Stub.ah.nextAuctionID
  table.insert(Stub.ah.posted, { auctionID = id, itemID = itemID, qty = qty, unit = unit, duration = duration, commodity = commodity, bag = loc.bagID, slot = loc.slotIndex })
  local ilvl = (suffix ~= 0 or (it and it.equip ~= "")) and (it and it.ilvl or 0) or 0
  -- the item leaves the bag and the auction appears when the house answers
  C_Timer.After(1, function()
    takeFromBags(loc.bagID, loc.slotIndex, qty)
    table.insert(Stub.ah.owned, {
      auctionID = id, itemKey = C_AuctionHouse.MakeItemKey(itemID, ilvl, suffix), status = Enum.AuctionStatus.Active,
      quantity = qty, buyoutAmount = unit, timeLeftSeconds = duration * 12 * 3600, timeLeft = 3,
    })
    Stub.FireEvent("AUCTION_HOUSE_AUCTION_CREATED", id)
  end)
end

function Stub.RemoveOwned(auctionID)
  for i, a in ipairs(Stub.ah.owned) do
    if a.auctionID == auctionID then table.remove(Stub.ah.owned, i) return true end
  end
  return false
end

function Stub.Owned(auctionID)
  for _, a in ipairs(Stub.ah.owned) do if a.auctionID == auctionID then return a end end
  return nil
end

C_AuctionHouse = {
  MakeItemKey = function(id, ilvl, suffix, species)
    return { itemID = id, itemLevel = ilvl or 0, itemSuffix = suffix or 0, battlePetSpeciesID = species or 0 }
  end,
  -- Takes a bag location, as the client does. Passing an item key here
  -- was the first error the beta raised, so the stub raises it too.
  GetItemCommodityStatus = function(loc)
    if type(loc) ~= "table" or loc.bagID == nil or loc.slotIndex == nil then
      error("bad argument #1 to 'GetItemCommodityStatus' (Usage: local isCommodity = C_AuctionHouse.GetItemCommodityStatus(item))")
    end
    local s = Stub.bags[loc.bagID] and Stub.bags[loc.bagID][loc.slotIndex]
    local it = s and Stub.items[s.itemID]
    if not it or it.commodity == nil then return Enum.ItemCommodityStatus.Unknown end
    return it.commodity and Enum.ItemCommodityStatus.Commodity or Enum.ItemCommodityStatus.Item
  end,
  -- nil until the item is cached, like the client.
  GetItemKeyInfo = function(key)
    Stub.ah.keyInfoCalls = (Stub.ah.keyInfoCalls or 0) + 1
    local it = Stub.items[key.itemID]
    if not it or not it.loaded or it.commodity == nil then return nil end
    return {
      itemName = it.name, isCommodity = it.commodity, isEquipment = it.equip ~= "",
      quality = it.quality, iconFileID = 134400, isPet = false, battlePetLink = nil, appearanceLink = nil,
    }
  end,
  IsThrottledMessageSystemReady = function() return Stub.ah.ready end,

  ReplicateItems = function()
    Stub.ah.replicateCalls = (Stub.ah.replicateCalls or 0) + 1
    C_Timer.After(1, function() Stub.FireEvent("REPLICATE_ITEM_LIST_UPDATE") end)
  end,
  GetNumReplicateItems = function() return #Stub.ah.replicate end,
  GetReplicateItemInfo = function(i)
    local r = Stub.ah.replicate[i + 1]
    if not r then return nil end
    local it = Stub.items[r.itemID]
    local loaded = it and it.loaded
    local name = loaded and it.name or nil
    return name, 134400, r.count, 1, true, 1, "", r.minBid or 0, 0, r.buyout, 0, nil, nil, r.owner, nil, 0, r.itemID, loaded and true or false
  end,
  GetReplicateItemLink = function(i)
    local r = Stub.ah.replicate[i + 1]
    if not r then return nil end
    local it = Stub.items[r.itemID]
    if not (it and it.loaded) then return nil end
    return r.link or string.format("|cffffffff|Hitem:%d:0:0:0:0:0:%d:0:60:0:0:0:0|h[%s]|h|r", r.itemID, r.suffix or 0, it.name)
  end,
  GetReplicateItemTimeLeft = function(i)
    local r = Stub.ah.replicate[i + 1]
    return r and r.timeLeft or 3
  end,

  SendBrowseQuery = function(query)
    Stub.Throttled(function(done)
      Stub.ah.lastQuery = query
      Stub.ah.browseServed = math.min(#Stub.ah.browse, Stub.ah.browsePageSize)
      C_Timer.After(1, function() Stub.FireEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") done() end)
    end)
  end,
  GetBrowseResults = function()
    local out = {}
    for i = 1, Stub.ah.browseServed do out[i] = Stub.ah.browse[i] end
    return out
  end,
  HasFullBrowseResults = function() return Stub.ah.browseServed >= #Stub.ah.browse end,
  RequestMoreBrowseResults = function()
    Stub.Throttled(function(done)
      Stub.ah.browseServed = math.min(#Stub.ah.browse, Stub.ah.browseServed + Stub.ah.browsePageSize)
      C_Timer.After(1, function() Stub.FireEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {}) done() end)
    end)
  end,

  SendSearchQuery = function(itemKey)
    Stub.Throttled(function(done)
      Stub.ah.searchCalls = (Stub.ah.searchCalls or 0) + 1
      local keyStr = tostring(itemKey.itemID)
      if (itemKey.itemLevel or 0) ~= 0 or (itemKey.itemSuffix or 0) ~= 0 then
        keyStr = string.format("%d:%d:%d", itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0)
      end
      Stub.ah.lastSearchKey = keyStr
      local res = Stub.ah.searchResults[keyStr]
      Stub.ah.currentSearch = res
      C_Timer.After(1, function()
        if res and res.commodity then
          Stub.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", itemKey.itemID)
        else
          Stub.FireEvent("ITEM_SEARCH_RESULTS_UPDATED", itemKey)
        end
        done()
      end)
    end)
  end,
  GetNumCommoditySearchResults = function() return Stub.ah.currentSearch and #Stub.ah.currentSearch.listings or 0 end,
  GetCommoditySearchResultInfo = function(itemID, i)
    local l = Stub.ah.currentSearch.listings[i]
    return { itemID = itemID, unitPrice = l[1], quantity = l[2], auctionID = l[3] or i, timeLeftSeconds = 3600, containsOwnerItem = l.mine or false }
  end,
  GetNumItemSearchResults = function() return Stub.ah.currentSearch and #Stub.ah.currentSearch.listings or 0 end,
  GetItemSearchResultInfo = function(itemKey, i)
    local l = Stub.ah.currentSearch.listings[i]
    return { itemKey = itemKey, buyoutAmount = l[1], quantity = l[2] or 1, auctionID = l[3] or i, timeLeft = 2, owners = { "Someone" }, containsOwnerItem = l.mine or false }
  end,

  StartCommoditiesPurchase = function(itemID, qty)
    Stub.ah.started = { itemID = itemID, qty = qty }
    local unit = Stub.ah.commodityPrice[itemID]
    C_Timer.After(1, function()
      if unit then Stub.FireEvent("COMMODITY_PRICE_UPDATED", unit, unit * qty)
      else Stub.FireEvent("COMMODITY_PRICE_UNAVAILABLE") end
    end)
  end,
  ConfirmCommoditiesPurchase = function(itemID, qty)
    table.insert(Stub.ah.purchases, { itemID = itemID, qty = qty })
    C_Timer.After(1, function() Stub.FireEvent("COMMODITY_PURCHASE_SUCCEEDED") end)
  end,
  CancelCommoditiesPurchase = function() Stub.ah.cancelled = (Stub.ah.cancelled or 0) + 1 end,
  PlaceBid = function(auctionID, amount)
    table.insert(Stub.ah.purchases, { auctionID = auctionID, amount = amount })
    C_Timer.After(1, function() Stub.FireEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID) end)
  end,

  PostCommodity = function(loc, duration, qty, unit) postAuction(loc, duration, qty, unit, true) end,
  PostItem = function(loc, duration, qty, bid, buyout) postAuction(loc, duration, qty, buyout, false) end,
  CalculateCommodityDeposit = function(itemID, duration, qty) return qty * duration end,
  CalculateItemDeposit = function(loc, duration, qty) return 100 * duration end,
  IsSellItemValid = function(loc) return true end,
  QueryOwnedAuctions = function(sorts)
    Stub.ah.ownedQueries = Stub.ah.ownedQueries + 1
    Stub.ah.ownedServed = Stub.ah.ownedPageSize and math.min(#Stub.ah.owned, Stub.ah.ownedPageSize) or #Stub.ah.owned
    C_Timer.After(1, function() Stub.FireEvent("OWNED_AUCTIONS_UPDATED") end)
  end,
  GetOwnedAuctions = function()
    if not Stub.ah.ownedPageSize then return Stub.ah.owned end
    local out = {}
    for i = 1, math.min(Stub.ah.ownedServed or 0, #Stub.ah.owned) do out[i] = Stub.ah.owned[i] end
    return out
  end,
  GetNumOwnedAuctions = function() return #C_AuctionHouse.GetOwnedAuctions() end,
  GetOwnedAuctionInfo = function(i) return C_AuctionHouse.GetOwnedAuctions()[i] end,
  HasFullOwnedAuctionResults = function()
    return not Stub.ah.ownedPageSize or (Stub.ah.ownedServed or 0) >= #Stub.ah.owned
  end,
  RequestMoreOwnedAuctions = function()
    Stub.ah.ownedMore = (Stub.ah.ownedMore or 0) + 1
    Stub.ah.ownedServed = math.min(#Stub.ah.owned, (Stub.ah.ownedServed or 0) + Stub.ah.ownedPageSize)
    C_Timer.After(1, function() Stub.FireEvent("OWNED_AUCTIONS_UPDATED") end)
  end,
}

------------------------------------------------------------------------
-- Blizzard's browse results frame, enough of it for the Buy tab hooks:
-- an item list with a data provider and a table builder layout, and the
-- two methods the addon hooks. Render() runs the layout and populates a
-- cell per row and column the way the client's table builder would.
------------------------------------------------------------------------
function Stub.NewItemList()
  local list = CreateFrame("Frame")
  list.Background = newObject("Texture")
  list.textureHeightClassic = 414

  function list:SetDataProvider(started, getEntry, getNum, full)
    self.searchStartedFunc, self.getEntry, self.getNumEntries, self.hasFullResultsFunc = started, getEntry, getNum, full
  end
  function list:SetTableBuilderLayout(fn) self.tableBuilderLayoutFunction = fn end
  function list:DirtyScrollFrame() self.dirty = true end
  -- Every column the layout adds gets a header frame the way the
  -- client's AddColumnInternal builds one: a sortable column carries
  -- its sort order, an unsortable one its text. Rows are buttons with
  -- the client's row mixin, so a hover reaches every cell.
  function list:Render()
    local tb = { columns = {}, all = {}, released = {} }
    function tb:GetColumns() return self.columns end
    function tb:GetHeaderPoolCollection()
      return { Release = function(_, frame) frame:Hide() tb.released[frame] = true return true end }
    end
    local function add(owner, sortOrder, headerText, template, ...)
      local header = newObject("Button")
      header.sortOrder, header.text = sortOrder, headerText
      local col = { owner = owner, header = headerText or sortOrder, headerFrame = header, template = template, args = { ... } }
      function col:GetHeaderFrame() return self.headerFrame end
      table.insert(tb.columns, col)
      table.insert(tb.all, col)
      return col
    end
    function tb:AddFixedWidthColumn(owner, padding, width, l, r, sortOrder, template, ...) return add(owner, sortOrder, nil, template, ...) end
    function tb:AddFillColumn(owner, padding, fill, l, r, sortOrder, template, ...) return add(owner, sortOrder, nil, template, ...) end
    function tb:AddUnsortableFixedWidthColumn(owner, padding, width, l, r, header, template, ...) return add(owner, nil, header, template, ...) end
    function tb:AddUnsortableFillColumn(owner, padding, fill, l, r, header, template, ...) return add(owner, nil, header, template, ...) end
    self.tableBuilderLayoutFunction(tb)
    local rows, rowFrames = {}, {}
    for i = 1, self.getNumEntries() do
      local rowData = self.getEntry(i)
      local row = Mixin(newObject("Button"), TableBuilderRowMixin)
      row.rowData, row.cells = rowData, {}
      for _, col in ipairs(tb.columns) do
        local cell = CreateFrame("Frame", nil, row, col.template)
        -- Blizzard's cells all derive from the cell mixin; the addon's
        -- come from Cells.xml and must bring their own
        if not Stub.templates[col.template] then Mixin(cell, TableBuilderCellMixin) end
        if cell.Init then cell:Init(col.owner, unpack(col.args)) end
        cell.rowData = rowData
        if cell.Populate then cell:Populate(rowData, i) end
        table.insert(row.cells, cell)
      end
      rows[i] = row.cells
      rowFrames[i] = row
    end
    return { columns = tb.columns, all = tb.all, released = tb.released, rows = rows, rowFrames = rowFrames }
  end
  return list
end

function Stub.NewBrowseFrame()
  local br = CreateFrame("Frame")
  br.browseResults = {}
  local list = Stub.NewItemList()
  br.ItemList = list

  function br:SetupTableBuilder(extra)
    self.ItemList:SetTableBuilderLayout(function(tb)
      tb:AddFixedWidthColumn(self, 0, 146, 0, 14, "price", "AuctionHouseTableCellMinPriceTemplate")
      tb:AddFillColumn(self, 0, 1.0, 10, 0, "name", "AuctionHouseTableCellItemDisplayTemplate", true, extra ~= nil)
      if extra then tb:AddFixedWidthColumn(self, 0, 55, 10, 0, "level", "AuctionHouseTableCellLevelTemplate") end
      tb:AddUnsortableFixedWidthColumn(self, 0, 83, 10, 0, "Qty", "AuctionHouseTableCellQuantityTemplate")
      tb:AddFixedWidthColumn(self, 0, 29, 10, 5, nil, "AuctionHouseTableCellFavoriteTemplate")
    end)
  end
  function br:UpdateBrowseResults(added)
    self.browseResults = C_AuctionHouse.GetBrowseResults()
    self.ItemList:DirtyScrollFrame()
  end
  br:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  br:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  br:SetScript("OnEvent", function(self, event, added)
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then self:UpdateBrowseResults() else self:UpdateBrowseResults(added or {}) end
  end)
  list:SetDataProvider(function() return true end, function(i) return br.browseResults[i] end, function() return #br.browseResults end, C_AuctionHouse.HasFullBrowseResults)
  br:SetupTableBuilder(nil)
  return br
end

-- Blizzard's Auctions tab: the list of your own auctions with its
-- four columns and the owned auction data provider.
function Stub.NewAuctionsFrame()
  local af = CreateFrame("Frame")
  local list = Stub.NewItemList()
  af.AllAuctionsList = list
  list:SetTableBuilderLayout(function(tb)
    local S = Enum.AuctionHouseSortOrder
    tb:AddFillColumn(af, 0, 1.0, 10, 0, S.Name, "AuctionHouseTableCellAuctionsItemDisplayTemplate")
    tb:AddFixedWidthColumn(af, 0, 145, 10, 0, S.Bid, "AuctionHouseTableCellAllAuctionsBidTemplate")
    tb:AddFixedWidthColumn(af, 0, 145, 10, 0, S.Buyout, "AuctionHouseTableCellAllAuctionsBuyoutTemplate")
    tb:AddFixedWidthColumn(af, 0, 50, 0, 10, S.TimeRemaining, "AuctionHouseTableCellTimeLeftTemplate")
  end)
  list:SetDataProvider(function() return true end, C_AuctionHouse.GetOwnedAuctionInfo, C_AuctionHouse.GetNumOwnedAuctions, C_AuctionHouse.HasFullOwnedAuctionResults)
  return af
end

-- Blizzard's commodity buy frame: the buy display on the left and the
-- narrow list of unit price and units, whose cells the addon colors.
function Stub.NewCommoditiesBuyFrame()
  local frame = CreateFrame("Frame")
  frame.BuyDisplay = CreateFrame("Frame")
  -- the display holds the units selected in the list (the client sets
  -- them from a row click) and its Buy button asks the house for a
  -- quote on them; the client's dialog then confirms
  frame.BuyDisplay.quantity = 0
  function frame.BuyDisplay:SetQuantity(q) self.quantity = q end
  function frame.BuyDisplay:GetQuantity() return self.quantity end
  frame.BuyDisplay.BuyButton = CreateFrame("Button", nil, frame.BuyDisplay)
  frame.BuyDisplay.BuyButton:SetScript("OnClick", function()
    Stub.ah.buyClicks = (Stub.ah.buyClicks or 0) + 1
    C_AuctionHouse.StartCommoditiesPurchase(frame.itemID, frame.BuyDisplay.quantity)
    -- the client's dialog opens inside the click, the quote landing later
    local dialog = type(AuctionHouseFrame) == "table" and AuctionHouseFrame.BuyDialog
    if dialog then dialog:Show() end
  end)
  local list = Stub.NewItemList()
  frame.ItemList = list
  list:SetTableBuilderLayout(function(tb)
    tb:AddFixedWidthColumn(list, 0, 150, 10, 0, nil, "AuctionHouseTableCellUnitPriceTemplate")
    tb:AddFillColumn(list, 0, 1.0, 0, 10, nil, "AuctionHouseTableCellCommoditiesQuantityTemplate")
  end)
  function frame:SetItemIDAndPrice(itemID, price)
    self.itemID = itemID
    list.itemID = itemID
    list:SetDataProvider(function() return itemID ~= nil end,
      function(i) return C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i) end,
      function() return C_AuctionHouse.GetNumCommoditySearchResults(itemID) end,
      function() return true end)
  end
  return frame
end

-- Blizzard's confirm dialog for a commodity, hung in the middle of the
-- house frame, shown by the Buy button above.
function Stub.NewBuyDialog(ah)
  local dialog = CreateFrame("Frame", nil, ah)
  dialog:SetSize(400, 200)
  dialog:SetPoint("CENTER", ah, "CENTER", 0, 0)
  dialog:Hide()
  return dialog
end

-- Blizzard's item buy frame: the item header and the wide auction list.
function Stub.NewItemBuyFrame()
  local frame = CreateFrame("Frame")
  frame.ItemDisplay = CreateFrame("Button")
  local list = Stub.NewItemList()
  frame.ItemList = list
  list:SetTableBuilderLayout(function(tb)
    tb:AddFixedWidthColumn(frame, 0, 145, 10, 0, "bid", "AuctionHouseTableCellBidTemplate")
    tb:AddFixedWidthColumn(frame, 0, 150, 10, 0, "buyout", "AuctionHouseTableCellBuyoutTemplate")
    tb:AddFillColumn(frame, 0, 1.0, 10, 0, nil, "AuctionHouseTableCellItemQuantityLeftTemplate")
    tb:AddFixedWidthColumn(frame, 0, 24, 0, 0, nil, "AuctionHouseTableCellExtraInfoTemplate")
    tb:AddFixedWidthColumn(frame, 0, 140, 10, 10, nil, "AuctionHouseTableCellTimeLeftBandTemplate")
  end)
  function frame:SetItemKey(itemKey)
    self.itemKey = itemKey
    list:SetDataProvider(function() return itemKey ~= nil end,
      function(i) return C_AuctionHouse.GetItemSearchResultInfo(itemKey, i) end,
      function() return C_AuctionHouse.GetNumItemSearchResults(itemKey) end,
      function() return true end)
  end
  return frame
end

------------------------------------------------------------------------
-- Loading the addon in TOC order. XML files only register their
-- virtual templates: the mixin and the font strings each declares.
------------------------------------------------------------------------
Stub.templates = {}

-- Blizzard's units cell on the commodity lists: the addon hooks its
-- Populate to color the figure.
AuctionHouseTableCellCommoditiesQuantityMixin = CreateFromMixins(TableBuilderCellMixin, {
  Init = function(self, owner) self.owner = owner end,
  Populate = function(self, rowData) self.Text:SetText(tostring(rowData.quantity or 0)) end,
})
Stub.templates["AuctionHouseTableCellCommoditiesQuantityTemplate"] = { mixin = "AuctionHouseTableCellCommoditiesQuantityMixin", fontStrings = { "Text" } }

local function loadTemplates(path)
  local f = io.open(path)
  if not f then error("missing " .. path) end
  local xml = f:read("*a")
  f:close()
  for name, body in xml:gmatch('<Frame name="([%w_]+)"(.-)</Frame>') do
    local t = { mixin = body:match('^[^>]*mixin="([%w_]+)"'), fontStrings = {} }
    for key in body:gmatch('<FontString parentKey="([%w_]+)"') do table.insert(t.fontStrings, key) end
    Stub.templates[name] = t
  end
end

function Stub.LoadAddon(root)
  local ns = {}
  local toc = io.open(root .. "/AuctionHound.toc")
  local files = {}
  for line in toc:lines() do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then
      table.insert(files, (line:gsub("\\", "/")))
    end
  end
  toc:close()
  for _, f in ipairs(files) do
    if f:match("%.xml$") then
      loadTemplates(root .. "/" .. f)
    else
      local chunk, err = loadfile(root .. "/" .. f)
      if not chunk then error(err) end
      chunk("AuctionHound", ns)
    end
  end
  return ns
end

return Stub
