-- UI/Confirm.lua: Hound's own buy confirm, for units of a commodity or
-- one auction of an item. It is Hound's frame entirely: the house's own
-- confirm and Buy button are never pressed (UI/House.lua has why).
--
-- The house wants a hardware event for each step that spends: asking
-- for a commodity's price, confirming it, and a bid. So the confirm
-- moves through stages, and its one button does what the stage needs:
--
--   reading   the item's listings are being read; nothing to press
--   price     a commodity's units are known: the button asks the house
--             for a price on them
--   quoting   the house was asked; waiting on its price
--   ready     the price is in: the button buys
--
-- A double-click on Blizzard's commodity list already knows the units:
-- it asks for the price itself and opens the confirm at quoting, so a
-- buy is one click more. The
-- units box sets how many of a commodity to buy; a change asks for a
-- new price. Cancel, Escape, or leaving the house calls it all off.
local ADDON, H = ...

local UI = H.UI
local AH = C_AuctionHouse
local C = {}
UI.Confirm = C

C.pending = nil

local function money()
  return type(GetMoney) == "function" and GetMoney() or nil
end

local function itemName(p)
  return H.ItemName(p.itemID)
end

function C.Text()
  local p, f = C.pending, C.frame
  if not p or not f then return end
  local commodity = p.kind == "commodity"
  if commodity and p.qty then
    f.title:SetText(string.format("Buy %d x %s", p.qty, itemName(p)))
  else
    f.title:SetText("Buy " .. itemName(p))
  end
  local short = false
  if p.stage == "reading" then
    f.total:SetText("reading the listings")
  elseif p.stage == "price" then
    f.total:SetText(p.estimate and ("about " .. H.Money(p.estimate)) or "")
  elseif p.stage == "quoting" then
    f.total:SetText("asking the house for a price")
  elseif p.total then
    if commodity then
      f.total:SetText(string.format("%s, %s each", H.Money(p.total), H.Money(p.unit or H.Round(p.total / p.qty))))
    else
      f.total:SetText(H.Money(p.total))
    end
    local m = money()
    short = m ~= nil and m < p.total
  end
  f.note:SetText(short and "not enough gold" or (p.note or ""))
  f.buy:SetText(p.stage == "price" and "Get price" or "Buy")
  if p.stage == "price" or (p.stage == "ready" and not short) then f.buy:Enable() else f.buy:Disable() end
  if commodity and p.stage ~= "reading" then
    f.units:Show()
    f.unitsLabel:Show()
    local want = tostring(p.qty or "")
    if f.units:GetText() ~= want and not f.units:HasFocus() then
      f.filling = true
      f.units:SetText(want)
      f.filling = false
    end
  else
    f.units:Hide()
    f.unitsLabel:Hide()
  end
end

-- Hides the confirm; a commodity purchase the house was asked for and
-- not told to make is called off.
function C.Close()
  local p = C.pending
  C.pending = nil
  if p and p.started and not p.confirmed and AH.CancelCommoditiesPurchase then AH.CancelCommoditiesPurchase() end
  if C.frame and C.frame:IsShown() then C.frame:Hide() end
end

-- Asks the house for a price on the units: from a hardware event only.
local function startPurchase(p)
  if p.started and not p.confirmed and AH.CancelCommoditiesPurchase then AH.CancelCommoditiesPurchase() end
  p.started, p.unit, p.total = true, nil, nil
  p.stage = "quoting"
  AH.StartCommoditiesPurchase(p.itemID, p.qty)
end

-- The button: a price asked for, or the purchase made.
function C.Click()
  local p = C.pending
  if not p then return false end
  if p.stage == "price" then
    if not p.qty or p.qty <= 0 then return false end
    startPurchase(p)
    C.Text()
    return true
  end
  if p.stage ~= "ready" or not p.total then return false end
  local m = money()
  if m and m < p.total then return false end
  p.confirmed = true
  if p.kind == "commodity" then
    H.Printf("buying %d x %s for %s", p.qty, itemName(p), H.Money(p.total))
    AH.ConfirmCommoditiesPurchase(p.itemID, p.qty)
  else
    H.Printf("buying %s for %s", itemName(p), H.Money(p.total))
    AH.PlaceBid(p.auctionID, p.total)
  end
  C.pending = nil
  C.frame:Hide()
  return true
end

-- A new count of a commodity's units: a price asked for before no
-- longer holds, so the button asks again.
function C.SetUnits(n)
  local p = C.pending
  if not p or p.kind ~= "commodity" or p.stage == "reading" then return end
  n = math.floor(tonumber(n) or 0)
  if p.max then n = math.min(n, p.max) end
  if n <= 0 or n == p.qty then return end
  if p.started and not p.confirmed and AH.CancelCommoditiesPurchase then AH.CancelCommoditiesPurchase() end
  p.started, p.unit, p.total = false, nil, nil
  p.qty = n
  p.estimate = p.priceOf and p.priceOf(n) or nil
  p.stage = "price"
  C.Text()
end

local function build()
  local f = UI.Create("Frame", "AuctionHoundBuyConfirm", UIParent, "BackdropTemplate")
  f:SetSize(300, 126)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  f.title = UI.Text(f, "GameFontNormal", "", "CENTER")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
  f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -16)
  f.total = UI.Text(f, "GameFontHighlight", "", "CENTER")
  f.total:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
  f.total:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -6)
  f.note = UI.Text(f, "GameFontRedSmall", "", "CENTER")
  f.note:SetPoint("TOPLEFT", f.total, "BOTTOMLEFT", 0, -2)
  f.note:SetPoint("TOPRIGHT", f.total, "BOTTOMRIGHT", 0, -2)
  f.units = UI.EditBox(f, 60, function(text)
    if not f.filling then C.SetUnits(text) end
  end)
  f.units:SetPoint("BOTTOM", f, "BOTTOM", 20, 42)
  if f.units.SetNumeric then f.units:SetNumeric(true) end
  f.unitsLabel = UI.Text(f, "GameFontHighlightSmall", "units", "RIGHT")
  f.unitsLabel:SetPoint("RIGHT", f.units, "LEFT", -8, 0)
  f.buy = UI.Button(f, "Buy", 100, 22, function() C.Click() end)
  f.buy:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
  f.cancel = UI.Button(f, "Cancel", 100, 22, function() C.Close() end)
  f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
  f:Hide()
  UI.WatchEscape(f)
  f:HookScript("OnHide", function() if C.pending then C.Close() end end)
  return f
end

-- Opens the confirm under the cursor on a purchase p, closing any other
-- first. p: kind, itemID, itemKey, and what the stage needs.
function C.Open(p)
  if C.pending then C.Close() end
  C.frame = C.frame or build()
  C.pending = p
  p.t = H.Now()
  C.Text()
  C.frame:Show()
  UI.CenterOnCursor(C.frame)
  return p
end

-- From a hardware event: the house is asked for a price on qty units
-- of a commodity, and the confirm waits on it. max caps the units box;
-- priceOf(n), when given, is what n units come to by the listings read.
function C.Commodity(itemID, qty, max, priceOf)
  local p = C.Open({ kind = "commodity", itemID = itemID, qty = qty, max = max, priceOf = priceOf, stage = "price" })
  startPurchase(p)
  C.Text()
  return p
end

-- The confirm while the listings it needs are read: kind is known or
-- nil, the rest is filled in by C.Offer.
function C.Reading(itemKey, key)
  return C.Open({ itemID = itemKey.itemID, itemKey = itemKey, key = key, stage = "reading" })
end

-- What the listings offer, for a confirm still reading them: for a
-- commodity the units and what they come to, which a click turns into
-- the house's price; for an item the auction, ready to buy.
function C.Offer(o)
  local p = C.pending
  if not p or p.stage ~= "reading" then return end
  for k, v in pairs(o) do p[k] = v end
  p.stage = p.kind == "commodity" and "price" or "ready"
  C.Text()
end

-- Nothing to buy after all: chat says why and the confirm goes.
function C.Fail(why)
  if why then H.Print(why) end
  C.pending = nil
  if C.frame then C.frame:Hide() end
end

H.RegisterEvent("COMMODITY_PRICE_UPDATED", function(unit, total)
  local p = C.pending
  if not p or p.kind ~= "commodity" or p.stage ~= "quoting" then return end
  p.unit, p.total = unit, total
  p.stage = "ready"
  C.Text()
end)

-- No price from the house: whatever it said before, the purchase it
-- was asked for cannot be made.
H.RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", function()
  local p = C.pending
  if not p or p.kind ~= "commodity" or not p.started or p.confirmed then return end
  C.Fail(string.format("the house has no price for %d x %s now", p.qty, itemName(p)))
end)

H.RegisterEvent("PLAYER_MONEY", function() if C.pending then C.Text() end end)
H.Events:On("AH_CLOSED", function() C.Close() end)
