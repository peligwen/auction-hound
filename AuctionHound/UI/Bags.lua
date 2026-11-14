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
-- The figures are Hound's own frames, each set on a bag button as a
-- child so it draws on the button's layer and hides with its bag. No
-- field is written on a bag frame or a button, no script of theirs is
-- run, and none of ours takes the mouse, so a click goes to the button
-- under it as always. Only Blizzard's own bags are read; a bag addon
-- that replaces them gets no figures. /hound overlay says what it can
-- see, and /hound overlay test puts the figures up without Shift.
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

-- A figure laid over a button from UIParent drew under the bags on
-- live, so it now goes on the button itself, a few levels up.
local function place(o, button)
  if o:GetParent() ~= button then o:SetParent(button) end
  o:ClearAllPoints()
  o:SetAllPoints(button)
  local strata = button.GetFrameStrata and button:GetFrameStrata()
  if strata then o:SetFrameStrata(strata) end
  o:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 0) + 3)
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
    o.where, o.value, o.bag, o.slot, o.button = where, value, bag, slot, button
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
-- Shift held puts the figures up, Shift let go takes them down. The
-- key is read every frame, as the tooltip reads it, rather than waited
-- on as an event. While it is held the figures are painted again a few
-- times a second, so a bag opened or a stack moved meanwhile is
-- followed. An error while painting is said once in chat and the
-- figures stay down until /hound overlay on.
------------------------------------------------------------------------
local function wanted()
  if not H.db or not H.Settings().overlay then return false end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
  return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
end

local since = 0

function Bags.Tick(elapsed)
  local test = Bags.test
  if test then
    test.frames = test.frames + 1
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then test.shift = true end
  end
  if Bags.broken then return end
  if not (test or wanted()) then
    if Bags.up then
      Bags.up = false
      Bags.Clear()
    end
    return
  end
  since = since + (elapsed or 0)
  if Bags.up and since < Bags.REFRESH then return end
  since = 0
  Bags.up = true
  local ok, err = pcall(Bags.Paint)
  if not ok then
    Bags.broken = tostring(err)
    Bags.up = false
    pcall(Bags.Clear)
    H.Print("the bag overlay stopped on an error, /hound overlay on tries again: " .. Bags.broken)
  end
end

Bags.driver = CreateFrame("Frame")
Bags.driver:SetScript("OnUpdate", function(_, elapsed) Bags.Tick(elapsed) end)

------------------------------------------------------------------------
-- /hound overlay test: the figures up for a few seconds without Shift,
-- what the first of them is drawn as, and at the end whether Hound's
-- frame ran and saw Shift held. It tells a figure drawn out of sight
-- from a Shift that never reads as held.
------------------------------------------------------------------------
Bags.TEST_SECONDS = 10

local function describe(f)
  if not f then return "none" end
  local w, h = f:GetWidth(), f:GetHeight()
  return string.format("%s level %s, %sx%s, %s",
    tostring(f.GetFrameStrata and f:GetFrameStrata() or "?"), tostring(f:GetFrameLevel()),
    tostring(w and H.Round(w)), tostring(h and H.Round(h)),
    f:IsVisible() and "visible" or "not visible")
end

function Bags.EndTest()
  local test = Bags.test
  if not test then return end
  Bags.test = nil
  H.Print(string.format("overlay test over: Hound's frame ran %d times, and Shift %s",
    test.frames, test.shift and "was seen held" or "was never seen held"))
  Bags.up = false
  Bags.Clear()
  Bags.Tick(0)
end

function Bags.StartTest()
  if Bags.test and Bags.test.timer then Bags.test.timer:Cancel() end
  Bags.test = { frames = 0, shift = false }
  Bags.test.timer = C_Timer.NewTimer(Bags.TEST_SECONDS, Bags.EndTest)
  Bags.broken = nil
  Bags.up = false
  Bags.Tick(0)
  if Bags.broken then return end
  H.Print(string.format("overlay test: %d figure%s up for %d seconds without Shift; hold Shift a moment meanwhile",
    Bags.shown, Bags.shown == 1 and "" or "s", Bags.TEST_SECONDS))
  local o = Bags.overlays[1]
  if Bags.shown > 0 and o then
    H.Print(string.format("  first figure, bag %s slot %s: %s", tostring(o.bag), tostring(o.slot), describe(o)))
    H.Print("  its button: " .. describe(o.button))
  end
end

H.Events:On("SETTINGS_CHANGED", function(what)
  if what ~= "overlay" then return end
  Bags.broken = nil
  Bags.up = false
  Bags.Clear()
  Bags.Tick(0)
end)

------------------------------------------------------------------------
-- What the overlay sees right now, for /hound overlay: the bags open,
-- the slots read from them, the slots with a price, and any bag addon
-- loaded, since one that draws its own bags leaves Blizzard's shut.
------------------------------------------------------------------------
Bags.BAG_ADDONS = { "Baganator", "Bagnon", "AdiBags", "ArkInventory", "BetterBags",
  "Combuctor", "LiteBag", "Inventorian", "Sorted", "ElvUI" }

local function loaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) and true or false end
  if type(IsAddOnLoaded) == "function" then return IsAddOnLoaded(name) and true or false end
  return false
end

function Bags.Survey()
  local s = { open = 0, slots = 0, priced = 0, addons = {} }
  for _, frame in ipairs(bagFrames()) do
    if frame:IsShown() then s.open = s.open + 1 end
  end
  Bags.EachButton(function(_, bag, slot)
    s.slots = s.slots + 1
    if Bags.SlotValue(bag, slot) then s.priced = s.priced + 1 end
  end)
  for _, name in ipairs(Bags.BAG_ADDONS) do
    if loaded(name) then table.insert(s.addons, name) end
  end
  return s
end

function Bags.Report()
  if Bags.broken then H.Print("  it stopped on an error: " .. Bags.broken) end
  local ok, s = pcall(Bags.Survey)
  if not ok then
    H.Print("  reading the bags failed: " .. tostring(s))
    return
  end
  if s.open == 0 then
    H.Print("  no Blizzard bag is open right now; open them and ask again")
  else
    H.Print(string.format("  now: %d bag frame%s open, %d slot%s read, %d with a price",
      s.open, s.open == 1 and "" or "s", s.slots, s.slots == 1 and "" or "s", s.priced))
  end
  if #s.addons > 0 then
    H.Print("  loaded: " .. table.concat(s.addons, ", ") .. "; a bag addon that draws its own bags gets no figures")
  end
end
