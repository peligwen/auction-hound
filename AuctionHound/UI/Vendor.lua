-- UI/Vendor.lua: Alt-click an item at a vendor to buy any number of it.
--
-- The box is Hound's own: the item, the count to buy (the last count
-- bought of it, else one stack), what that comes to, and a note when
-- the gold or the vendor's stock will not stretch to it, or the bags
-- look too full. Max fills in the most all three allow. Buy, or Enter
-- in the count, starts the purchases (Vendor.lua) and the box follows
-- them; Stop, Escape, or the vendor's window closing ends them after
-- the one on its way. /hound vendor [count] <item> opens it from chat.
--
-- Nothing of Blizzard's is written or run (README, Taint): the
-- Alt-click is met by a secure hook on the vendor's own handler for a
-- modified click, which Blizzard's code leaves alone for Alt, and only
-- the button's index and the window's tab are read.
local ADDON, H = ...

local UI = H.UI
local V = H.Vendor
local D = {}
UI.Vendor = D

local AMBER = { 1, 0.75, 0.2 }
local RED = { 1, 0.3, 0.3 }

local function setQtyText(f, n)
  local want = tostring(n or "")
  if f.units:GetText() ~= want and not (f.units.HasFocus and f.units:HasFocus()) then
    f.filling = true
    f.units:SetText(want)
    f.filling = false
  end
end

-- The price line: each unit's price, or a bundle's.
function D.EachLine(info)
  if info.bundle > 1 then
    return string.format("sold in %ds at %s", info.bundle, H.Money(info.price))
  end
  return H.Money(info.price) .. " each"
end

function D.Text()
  local f = D.frame
  if not f or not D.itemID then return end
  local job = V.job
  local _, info = V.Find(D.itemID)
  if not info and not job then
    D.Close()
    return
  end
  f.title:SetText("Buy " .. (info and info.name or H.ItemName(D.itemID)))
  if info then f.each:SetText(D.EachLine(info)) end
  if job then
    f.total:SetText(string.format("bought %d of %d", math.max(0, job.got or 0), job.want))
    f.note:SetText("")
    f.buy:SetText("Buying")
    f.buy:Disable()
    f.max:Disable()
    f.cancel:SetText("Stop")
    return
  end
  f.buy:SetText("Buy")
  f.max:Enable()
  f.cancel:SetText("Cancel")
  setQtyText(f, D.qty)
  local p = V.Plan(info, D.qty)
  D.plan = p
  if p.units > 0 then
    local line = string.format("%d for %s", p.units, H.Money(p.cost))
    if p.units ~= D.qty then line = line .. string.format(", in %ds", info.bundle) end
    f.total:SetText(line)
  else
    f.total:SetText("")
  end
  local c = p.why and RED or AMBER
  f.note:SetText(p.why or p.warn or "")
  f.note:SetTextColor(c[1], c[2], c[3])
  if p.units > 0 and not p.why then f.buy:Enable() else f.buy:Disable() end
end

function D.SetQty(text)
  D.qty = math.max(0, math.floor(tonumber(text) or 0))
  D.Text()
end

function D.Max()
  local p = D.plan
  if V.job or not p or not p.most or p.most <= 0 then return false end
  D.qty = p.most
  setQtyText(D.frame, D.qty)
  D.Text()
  return true
end

-- Starts the purchases. Returns true, or false and why.
function D.Buy()
  if V.job or not D.itemID then return false end
  local index = V.Find(D.itemID)
  local ok, why = V.Start(index, D.qty)
  if not ok then
    if why then H.Print(why) end
    return false, why
  end
  D.Text()
  return true
end

-- Hides the box; a run still going ends after the purchase on its way.
function D.Close()
  D.itemID = nil
  if D.frame and D.frame:IsShown() then D.frame:Hide() end
  if V.job then V.Stop("you stopped it") end
end

local function build()
  local f = UI.Create("Frame", "AuctionHoundVendorBuy", UIParent, "BackdropTemplate")
  f:SetSize(280, 150)
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
  f.each = UI.Text(f, "GameFontHighlightSmall", "", "CENTER")
  f.each:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.each:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -4)
  f.units = UI.EditBox(f, 60, function(text)
    if not f.filling then D.SetQty(text) end
  end)
  f.units:SetPoint("TOP", f.each, "BOTTOM", 0, -8)
  if f.units.SetNumeric then f.units:SetNumeric(true) end
  f.units:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    D.Buy()
  end)
  f.units:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    D.Close()
  end)
  f.unitsLabel = UI.Text(f, "GameFontHighlightSmall", "units", "RIGHT")
  f.unitsLabel:SetPoint("RIGHT", f.units, "LEFT", -8, 0)
  f.max = UI.Button(f, "Max", 50, 20, function() D.Max() end)
  f.max:SetPoint("LEFT", f.units, "RIGHT", 8, 0)
  f.total = UI.Text(f, "GameFontHighlight", "", "CENTER")
  f.total:SetPoint("TOP", f.units, "BOTTOM", 0, -6)
  f.total:SetPoint("LEFT", f, "LEFT", 16, 0)
  f.total:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  f.note = UI.Text(f, "GameFontNormalSmall", "", "CENTER")
  f.note:SetPoint("TOPLEFT", f.total, "BOTTOMLEFT", 0, -2)
  f.note:SetPoint("TOPRIGHT", f.total, "BOTTOMRIGHT", 0, -2)
  f.buy = UI.Button(f, "Buy", 100, 22, function() D.Buy() end)
  f.buy:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
  f.cancel = UI.Button(f, "Cancel", 100, 22, function() D.Close() end)
  f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
  f:Hide()
  UI.WatchEscape(f)
  f:HookScript("OnHide", function() if D.itemID then D.Close() end end)
  return f
end

-- Opens the box under the cursor for the item at the vendor's index,
-- the count set to qty or the box's own default. Returns true, or
-- false and why not.
function D.Open(index, qty)
  if V.job then return false, "still buying " .. V.job.name end
  local info = V.Info(index)
  if not info then return false, "the vendor has nothing there" end
  if not info.gold then return false, info.name .. " costs more than gold; buy it in the vendor's window" end
  D.frame = D.frame or build()
  D.itemID = info.itemID
  D.qty = qty and math.max(0, math.floor(qty)) or V.DefaultQty(info)
  D.Text()
  D.frame:Show()
  UI.CenterOnCursor(D.frame)
  if D.frame.units.SetFocus then
    D.frame.units:SetFocus()
    D.frame.units:HighlightText()
  end
  return true
end

------------------------------------------------------------------------
-- /hound vendor [count] <item link, id or name>
------------------------------------------------------------------------
local LINK = "|c%x+|Hitem:[^|]+|h%[[^%]]*%]|h|r"

function D.Command(rest)
  rest = rest or ""
  if not V.IsOpen() then
    H.Print("talk to a vendor first, then Alt-click an item or /hound vendor [count] <item>")
    return false
  end
  local link = string.match(rest, LINK)
  local tail = link and string.gsub(rest, LINK, " ", 1) or rest
  local nums, words = {}, {}
  for tok in string.gmatch(tail, "%S+") do
    local n = tonumber(tok)
    if n then table.insert(nums, n) else table.insert(words, tok) end
  end
  local qty, info
  if link then
    qty = nums[1]
    local _, found = V.Find(tonumber(string.match(link, "item:(%d+)")))
    info = found
  elseif #words > 0 then
    qty = nums[1]
    local found = V.FindByName(table.concat(words, " "))
    if #found > 1 then
      local names = {}
      for i = 1, math.min(5, #found) do table.insert(names, found[i].name) end
      H.Printf("which one: %s%s", table.concat(names, ", "), #found > 5 and ", ..." or "")
      return false
    end
    info = found[1]
  elseif #nums > 0 then
    qty = #nums > 1 and nums[1] or nil
    local _, found = V.Find(nums[#nums])
    info = found
  else
    H.Print("usage: /hound vendor [count] <item link, id or name>, at a vendor")
    return false
  end
  if not info then
    H.Print("this vendor does not sell that")
    return false
  end
  local ok, why = D.Open(info.index, qty)
  if not ok and why then H.Print(why) end
  return ok
end

------------------------------------------------------------------------
-- The Alt-click. Blizzard's vendor buttons send any modified click to
-- MerchantItemButton_OnModifiedClick, which links on Shift, dresses up
-- on Ctrl, splits on Shift, and does nothing on Alt; Hound's hook runs
-- after it. The buyback tab's buttons go the same way and are skipped.
------------------------------------------------------------------------
local function altOnly()
  if type(IsAltKeyDown) ~= "function" or not IsAltKeyDown() then return false end
  if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then return false end
  if type(IsControlKeyDown) == "function" and IsControlKeyDown() then return false end
  return true
end

function D.OnModifiedClick(button)
  if not altOnly() then return end
  local tab = type(MerchantFrame) == "table" and MerchantFrame.selectedTab
  if tab and tab ~= 1 then return end
  local index = type(button) == "table" and button.GetID and button:GetID()
  if not index or index <= 0 then return end
  local ok, why = D.Open(index)
  if not ok and why then H.Print(why) end
end

local function install()
  if D.installed then return end
  if type(MerchantItemButton_OnModifiedClick) ~= "function" then return end
  D.installed = true
  hooksecurefunc("MerchantItemButton_OnModifiedClick", function(button)
    local ok, err = pcall(D.OnModifiedClick, button)
    if not ok then H.Print("the vendor's Alt-click stopped on an error: " .. tostring(err)) end
  end)
end

install()
H.Events:On("LOGIN", install)
H.RegisterEvent("MERCHANT_SHOW", function()
  install()
  if not D.installed and not D.said then
    D.said = true
    H.Print("this client's vendor window has no handler Hound knows for Alt-click; /hound vendor [count] <item> still buys")
  end
end)

H.Events:On("VENDOR_PROGRESS", function() D.Text() end)
H.Events:On("VENDOR_DONE", function()
  if D.frame and D.frame:IsShown() then D.Close() end
end)
H.RegisterEvent("MERCHANT_CLOSED", function() if D.itemID then D.Close() end end)
H.RegisterEvent("PLAYER_MONEY", function()
  if D.frame and D.frame:IsShown() and not V.job then D.Text() end
end)
