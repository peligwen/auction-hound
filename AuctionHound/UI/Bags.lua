-- UI/Bags.lua: what each bag slot is worth, while Shift is held.
--
-- With the bags open, holding Shift puts a small figure over every
-- slot: the stack at the house's floor from the latest scan, or at the
-- vendor's price when the vendor pays more than the house would after
-- its cut. Junk and anything soulbound go to the vendor, so they show
-- the vendor's price alone; a slot with neither price shows nothing.
-- The house figure is gold, the vendor's gray. Letting go of Shift
-- takes it all down. /hound overlay off turns it off.
--
-- The figures are Hound's own frames, laid over Blizzard's bag buttons
-- by anchor alone: nothing is written on a bag frame or a button, no
-- script of theirs is run, and none of ours takes the mouse, so a
-- click goes to the button under it as always. Only Blizzard's own
-- bags are read; a bag addon that replaces them gets no figures.
local ADDON, H = ...

local Bags = { overlays = {}, shown = 0 }
H.Bags = Bags

Bags.REFRESH = 0.25            -- seconds between repaints while Shift is held
Bags.HOUSE_COLOR = { 1, 0.82, 0 }
Bags.VENDOR_COLOR = { 0.72, 0.72, 0.72 }

------------------------------------------------------------------------
-- What one slot is worth, and where to sell it.
--
-- Returns the copper the stack fetches and "house" or "vendor", or nil
-- when there is nothing to say. The house figure is the floor at the
-- latest scan for every unit, as the tooltip shows it; the vendor
-- figure is the vendor's price for every unit, and it wins when the
-- house would pay less once its cut is taken.
------------------------------------------------------------------------
function Bags.Value(itemID, count, link, bound)
  if not itemID then return nil end
  count = count or 1
  local vendorUnit = H.VendorSell(itemID)
  local vendor = vendorUnit and vendorUnit * count or nil
  if bound or H.IsJunk(itemID) then
    if vendor then return vendor, "vendor" end
    return nil
  end
  local key = link and H.KeyFromLink(link, itemID) or H.KeyForItemID(itemID) or tostring(itemID)
  local rec = key and H.Store.Get(key)
  local st = rec and H.Market.Stats(rec) or nil
  local unit = st and st.market and (st.min or st.market) or nil
  local house = unit and unit * count or nil
  local cut = H.Settings().cut or 0
  if house and (not vendor or house * (1 - cut) > vendor) then return house, "house" end
  if vendor then return vendor, "vendor" end
  return nil
end

-- The same for a slot in the bags, read from the client.
function Bags.SlotValue(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info or not info.itemID then return nil end
  return Bags.Value(info.itemID, info.stackCount, info.hyperlink, info.isBound)
end

------------------------------------------------------------------------
-- Blizzard's bag buttons, read and never written. A button of the
-- modern bags knows its bag; a classic one is numbered within a frame
-- whose ID is the bag.
------------------------------------------------------------------------
local function bagFrames()
  local out = {}
  if ContainerFrameCombinedBags then table.insert(out, ContainerFrameCombinedBags) end
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local f = _G["ContainerFrame" .. i]
    if f then table.insert(out, f) end
  end
  return out
end

local function slotOf(frame, button)
  local bag
  if type(button.GetBagID) == "function" then bag = button:GetBagID() end
  if bag == nil then bag = frame:GetID() end
  return bag, button:GetID()
end

-- Calls fn(button, bag, slot) for every bag button on screen.
function Bags.EachButton(fn)
  for _, frame in ipairs(bagFrames()) do
    if frame:IsShown() then
      local buttons = type(frame.Items) == "table" and frame.Items or nil
      if not buttons then
        buttons = {}
        local name = frame:GetName()
        local n = frame.size
        if not n and C_Container and C_Container.GetContainerNumSlots then
          n = C_Container.GetContainerNumSlots(frame:GetID() or 0)
        end
        for i = 1, n or 0 do
          local b = name and _G[name .. "Item" .. i]
          if b then table.insert(buttons, b) end
        end
      end
      for _, button in ipairs(buttons) do
        if button:IsShown() then
          local bag, slot = slotOf(frame, button)
          if bag and slot then fn(button, bag, slot) end
        end
      end
    end
  end
end

------------------------------------------------------------------------
-- The figures.
------------------------------------------------------------------------
local function newOverlay()
  local o = CreateFrame("Frame", nil, UIParent)
  o:EnableMouse(false)
  local bg = o:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", o, "TOPLEFT", 1, -1)
  bg:SetPoint("TOPRIGHT", o, "TOPRIGHT", -1, -1)
  bg:SetHeight(12)
  bg:SetColorTexture(0, 0, 0, 0.65)
  local text = o:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  text:SetPoint("TOP", o, "TOP", 0, -1)
  text:SetJustifyH("CENTER")
  text:SetWordWrap(false)
  o.bg, o.text = bg, text
  o:Hide()
  return o
end

local function place(o, button)
  o:ClearAllPoints()
  o:SetAllPoints(button)
  if button.GetFrameStrata then o:SetFrameStrata(button:GetFrameStrata() or "MEDIUM") end
  if button.GetFrameLevel then o:SetFrameLevel((button:GetFrameLevel() or 0) + 5) end
end

-- Paints every slot on screen; returns how many figures are up.
function Bags.Paint()
  local n = 0
  Bags.EachButton(function(button, bag, slot)
    local value, where = Bags.SlotValue(bag, slot)
    if not value then return end
    n = n + 1
    local o = Bags.overlays[n]
    if not o then
      o = newOverlay()
      Bags.overlays[n] = o
    end
    place(o, button)
    local color = where == "house" and Bags.HOUSE_COLOR or Bags.VENDOR_COLOR
    o.text:SetText(H.MoneyShort(value))
    o.text:SetTextColor(color[1], color[2], color[3])
    o.where, o.value, o.bag, o.slot = where, value, bag, slot
    o:Show()
  end)
  for i = n + 1, #Bags.overlays do Bags.overlays[i]:Hide() end
  Bags.shown = n
  return n
end

function Bags.Clear()
  for _, o in ipairs(Bags.overlays) do o:Hide() end
  Bags.shown = 0
end

------------------------------------------------------------------------
-- Shift down puts the figures up, Shift up takes them down. While it
-- is held they are painted again a few times a second, so a bag opened
-- or a stack moved meanwhile is followed.
------------------------------------------------------------------------
local function wanted()
  if not H.db or not H.Settings().overlay then return false end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
  return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
end

local function stopTicker()
  if Bags.ticker then
    Bags.ticker:Cancel()
    Bags.ticker = nil
  end
end

function Bags.Update()
  if wanted() then
    Bags.Paint()
    if not Bags.ticker then Bags.ticker = C_Timer.NewTicker(Bags.REFRESH, Bags.Update) end
  else
    stopTicker()
    Bags.Clear()
  end
end

H.RegisterEvent("MODIFIER_STATE_CHANGED", function(key)
  if key == "LSHIFT" or key == "RSHIFT" then Bags.Update() end
end)
H.RegisterEvent("PLAYER_REGEN_DISABLED", function() stopTicker() Bags.Clear() end)
H.Events:On("SETTINGS_CHANGED", function(what)
  if what == "overlay" then Bags.Update() end
end)
