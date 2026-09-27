-- Util.lua: small helpers shared by every module. No game state lives here.
local ADDON, H = ...

H.VERSION = "0.1.0"
H.PREFIX = "|cffe6b800Hound|r: "

------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------
function H.Print(msg)
  local out = H.PREFIX .. tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(out)
  else
    print(out)
  end
end

function H.Printf(fmt, ...)
  H.Print(string.format(fmt, ...))
end

------------------------------------------------------------------------
-- Time
------------------------------------------------------------------------
function H.Now()
  if GetServerTime then return GetServerTime() end
  return time()
end

function H.DayIndex(t)
  return math.floor((t or H.Now()) / 86400)
end

function H.DayLabel(dayIdx)
  return date("%m/%d", dayIdx * 86400 + 43200)
end

function H.Ago(seconds)
  if not seconds then return "never" end
  if seconds < 90 then return string.format("%ds ago", seconds) end
  if seconds < 5400 then return string.format("%dm ago", math.floor(seconds / 60 + 0.5)) end
  if seconds < 172800 then return string.format("%.1fh ago", seconds / 3600) end
  return string.format("%dd ago", math.floor(seconds / 86400 + 0.5))
end

------------------------------------------------------------------------
-- Numbers
------------------------------------------------------------------------
function H.Round(x)
  return math.floor(x + 0.5)
end

function H.Clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function H.Mean(arr)
  local n = #arr
  if n == 0 then return nil end
  local s = 0
  for i = 1, n do s = s + arr[i] end
  return s / n
end

function H.StdDev(arr, mean)
  local n = #arr
  if n < 2 then return 0 end
  mean = mean or H.Mean(arr)
  local v = 0
  for i = 1, n do v = v + (arr[i] - mean) ^ 2 end
  return math.sqrt(v / n)
end

------------------------------------------------------------------------
-- Money. Prices are always integers in copper.
------------------------------------------------------------------------
local function plainMoney(copper)
  copper = H.Round(copper or 0)
  local neg = copper < 0
  if neg then copper = -copper end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out
  if g > 0 then
    out = string.format("%dg %02ds %02dc", g, s, c)
  elseif s > 0 then
    out = string.format("%ds %02dc", s, c)
  else
    out = string.format("%dc", c)
  end
  if neg then out = "-" .. out end
  return out
end

-- Short form for dense tables: 12.3g, 45s, 8c.
function H.MoneyShort(copper)
  copper = H.Round(copper or 0)
  local neg = copper < 0
  if neg then copper = -copper end
  local out
  if copper >= 10000 then
    local g = copper / 10000
    if g >= 100 then out = string.format("%dg", math.floor(g + 0.5))
    else out = string.format("%.1fg", g) end
  elseif copper >= 100 then
    out = string.format("%ds", math.floor(copper / 100))
  else
    out = string.format("%dc", copper)
  end
  if neg then out = "-" .. out end
  return out
end

-- Long form with coin icons when the client offers them.
function H.Money(copper)
  copper = H.Round(copper or 0)
  local settings = H.Settings and H.Settings()
  if settings and settings.plainMoney then return plainMoney(copper) end
  local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  if fn and copper >= 0 then
    return fn(copper)
  end
  return plainMoney(copper)
end

H.PlainMoney = plainMoney

-- Money typed by a person: "1g 20s 5c", "1.5g", "45s", or a bare number
-- of copper. Returns copper, or nil when nothing readable is there.
function H.ParseMoney(str)
  if type(str) == "number" then return H.Round(str) end
  str = string.lower(string.gsub(tostring(str or ""), "%s", ""))
  if str == "" then return nil end
  if string.match(str, "^%d+$") then return tonumber(str) end
  local total, any = 0, false
  for num, unit in string.gmatch(str, "([%d%.]+)([gsc])") do
    local v = tonumber(num)
    if v then
      any = true
      if unit == "g" then total = total + v * 10000
      elseif unit == "s" then total = total + v * 100
      else total = total + v end
    end
  end
  if not any then return nil end
  return H.Round(total)
end

function H.Pct(x, signed)
  if x == nil then return "-" end
  local v = H.Round(x * 100)
  if signed then
    if v > 0 then return "+" .. v .. "%" end
  end
  return v .. "%"
end

------------------------------------------------------------------------
-- Item keys.
-- Commodities and simple items are keyed by item ID. Equippable items
-- carry item level and suffix so "of the Bear" and "of the Monkey" never
-- share a history. The string form is what the store uses.
------------------------------------------------------------------------
function H.KeyString(itemKey)
  local id = itemKey.itemID
  local ilvl = itemKey.itemLevel or 0
  local suffix = itemKey.itemSuffix or 0
  local species = itemKey.battlePetSpeciesID or 0
  if ilvl == 0 and suffix == 0 and species == 0 then
    return tostring(id)
  end
  if species ~= 0 then
    return string.format("%d:%d:%d:%d", id, ilvl, suffix, species)
  end
  return string.format("%d:%d:%d", id, ilvl, suffix)
end

function H.KeyParts(key)
  local id, ilvl, suffix, species = strsplit(":", key)
  return tonumber(id), tonumber(ilvl) or 0, tonumber(suffix) or 0, tonumber(species) or 0
end

function H.ItemIDFromKey(key)
  return (tonumber(string.match(key, "^(%d+)")))
end

function H.ItemKeyFromString(key)
  local id, ilvl, suffix, species = H.KeyParts(key)
  if C_AuctionHouse and C_AuctionHouse.MakeItemKey then
    return C_AuctionHouse.MakeItemKey(id, ilvl, suffix, species)
  end
  return { itemID = id, itemLevel = ilvl, itemSuffix = suffix, battlePetSpeciesID = species }
end

-- True when the auction house treats this item as a commodity. Unknown
-- status is reported as nil so callers can wait for item data.
function H.CommodityStatus(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus) then return nil end
  local status = C_AuctionHouse.GetItemCommodityStatus(C_AuctionHouse.MakeItemKey(itemID))
  if status == Enum.ItemCommodityStatus.Commodity then return true end
  if status == Enum.ItemCommodityStatus.Item then return false end
  return nil
end

local function isEquippable(itemID)
  if not (C_Item and C_Item.GetItemInfoInstant) then return false end
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
  return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end
H.IsEquippable = isEquippable

-- Key for an item ID alone. Works for commodities and for items that have
-- no level or suffix variants. Returns nil when a link is required.
function H.KeyForItemID(itemID)
  local commodity = H.CommodityStatus(itemID)
  if commodity == true then return tostring(itemID) end
  if commodity == false and not isEquippable(itemID) then return tostring(itemID) end
  if commodity == nil and C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    if equipLoc == "" then return tostring(itemID) end
  end
  return nil
end

-- Key from an item link. The suffix is the seventh field of the item
-- string; item level comes from the client's detailed item level.
function H.KeyFromLink(link, itemID)
  local idStr, suffixStr = string.match(link or "", "|Hitem:(%d+):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*:(%-?%d*):")
  itemID = itemID or tonumber(idStr)
  if not itemID then return nil end
  local commodity = H.CommodityStatus(itemID)
  if commodity == true or not isEquippable(itemID) then
    return tostring(itemID)
  end
  local ilvl = 0
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    ilvl = C_Item.GetDetailedItemLevelInfo(link) or 0
  end
  local suffix = tonumber(suffixStr) or 0
  return H.KeyString({ itemID = itemID, itemLevel = ilvl, itemSuffix = suffix })
end

------------------------------------------------------------------------
-- Item info with graceful fallbacks while the item cache warms up.
------------------------------------------------------------------------
function H.ItemName(itemID)
  if C_Item and C_Item.GetItemInfo then
    local name = C_Item.GetItemInfo(itemID)
    if name then return name end
  end
  local db = AuctionHoundDB
  if db and db.names and db.names[itemID] then return db.names[itemID] end
  return "item:" .. tostring(itemID)
end

function H.ItemIcon(itemID)
  if C_Item and C_Item.GetItemIconByID then
    return C_Item.GetItemIconByID(itemID)
  end
  return nil
end

function H.ItemQuality(itemID)
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, quality = C_Item.GetItemInfoInstant(itemID)
    return quality
  end
  return nil
end

function H.ColoredName(itemID)
  local name = H.ItemName(itemID)
  local q = H.ItemQuality(itemID)
  if q and C_Item and C_Item.GetItemQualityColor then
    local _, _, _, hex = C_Item.GetItemQualityColor(q)
    if hex then return "|c" .. hex .. name .. "|r" end
  end
  return name
end

function H.VendorSell(itemID)
  if C_Item and C_Item.GetItemInfo then
    local sell = select(11, C_Item.GetItemInfo(itemID))
    if sell and sell > 0 then return sell end
  end
  return nil
end

------------------------------------------------------------------------
-- Tiny event bus for addon-internal notifications.
------------------------------------------------------------------------
H.Events = { handlers = {} }

function H.Events:On(name, fn)
  self.handlers[name] = self.handlers[name] or {}
  table.insert(self.handlers[name], fn)
end

function H.Events:Fire(name, ...)
  local list = self.handlers[name]
  if not list then return end
  for _, fn in ipairs(list) do fn(...) end
end

------------------------------------------------------------------------
-- Game events. One frame, many handlers per event.
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = eventHandlers[event]
  if not list then return end
  for _, fn in ipairs(list) do fn(...) end
end)

-- An event this client does not know is reported once and its handlers
-- simply never run, rather than aborting the file that asked for it.
function H.RegisterEvent(event, fn)
  if not eventHandlers[event] then
    eventHandlers[event] = {}
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then H.Print("this client has no " .. event .. " event; that feature is off") end
  end
  table.insert(eventHandlers[event], fn)
end

H.eventFrame = eventFrame
