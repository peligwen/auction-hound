-- Tooltip.lua: a few Hound lines on item tooltips, on a Waylaid Crate
-- the price of each bundle that fills it (Crate.lua), and on a
-- Craftsman's Writ the price of the item it asks for (Writ.lua).
--
-- An item's own lines are one by default, the floor at the latest
-- scan. Shift held shows the rest: the market value, the three-day
-- mean, the vendor price, the trend, what has cleared and your own
-- sales. A tooltip the client refreshes while it is up, a bag slot or
-- a house row, follows Shift as it goes down and up; a link clicked in
-- chat stays up to be read, so it always shows the rest. Junk gets no
-- Hound lines at all: the vendor is where it goes.
local ADDON, H = ...

-- A floor older than this says how old it is.
H.TOOLTIP_STALE = 86400

local function detailed(tooltip)
  if tooltip == ItemRefTooltip then return true end
  return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
end

local function floorLine(tooltip, st)
  local label = "|cffe6b800Hound|r floor"
  if st.age and st.age > H.TOOLTIP_STALE then
    label = label .. " |cff999999" .. H.Ago(st.age) .. "|r"
  end
  tooltip:AddDoubleLine(label, H.Money(st.min or st.market), 1, 0.82, 0, 1, 1, 1)
end

local function addLines(tooltip, itemID, link)
  if not H.db or not H.Settings().tooltip then return end
  if H.IsJunk(itemID) then return end
  local key = link and H.KeyFromLink(link, itemID) or tostring(itemID)
  if not key then return end
  local rec = H.Store.Get(key)
  local st = rec and H.Market.Stats(rec) or nil
  if st and not st.market then st = nil end

  if not detailed(tooltip) then
    if st then floorLine(tooltip, st) end
    return
  end

  local cl = H.Market.Clearing(H.Store.Posts(key))
  if cl and cl.soldUnits == 0 and cl.unsoldUnits == 0 then cl = nil end
  if not st and not cl then return end
  tooltip:AddLine(" ")
  if st then
    floorLine(tooltip, st)
    tooltip:AddDoubleLine("  market", H.Money(st.market), 0.8, 0.8, 0.8, 1, 1, 1)
    if st.avg3 then
      tooltip:AddDoubleLine("  3 day", H.Money(st.avg3), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local vendor = H.VendorSell(itemID)
    if vendor then
      tooltip:AddDoubleLine("  vendor", H.Money(vendor), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local parts = { string.format("%d listed", st.qty or 0) }
    if st.trend then table.insert(parts, "trend " .. H.Pct(st.trend, true)) end
    if st.cleared then
      table.insert(parts, string.format("cleared ~%d/day%s", H.Round(st.cleared), st.clearing and (" at ~" .. H.MoneyShort(st.clearing)) or ""))
    elseif st.moved then
      table.insert(parts, string.format("~%d/day", H.Round(st.moved)))
    end
    table.insert(parts, string.format("%d scans", st.samples))
    tooltip:AddDoubleLine("  " .. table.concat(parts, ", "), H.Ago(st.age), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
  end
  if cl then
    tooltip:AddDoubleLine(st and "  yours" or "|cffe6b800Hound|r yours", H.Fan.ClearingLine(cl), 0.8, 0.8, 0.8, 0.4, 0.9, 0.4)
  end
end

-- A crate has no history of its own, so its lines do not wait on any.
local function addCrate(tooltip, itemID)
  if not H.db or not H.Settings().tooltip then return end
  H.Crate.AddTooltipLines(tooltip, itemID)
end

-- A writ is sold at the house and may have a history; what it asks for
-- goes under that.
local function addWrit(tooltip, itemID)
  if not H.db or not H.Settings().tooltip then return end
  H.Writ.AddTooltipLines(tooltip, itemID)
end

local function onTooltip(tooltip, data)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  local itemID = data and data.id
  local link = data and data.hyperlink
  if not link and TooltipUtil and TooltipUtil.GetDisplayedItem then
    local _, l, id = TooltipUtil.GetDisplayedItem(tooltip)
    link = l
    itemID = itemID or id
  end
  if not itemID and link then
    itemID = tonumber(string.match(link, "item:(%d+)"))
  end
  if not itemID then return end
  addLines(tooltip, itemID, link)
  addCrate(tooltip, itemID)
  addWrit(tooltip, itemID)
end

H.Events:On("LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
      local _, link = tt:GetItem()
      if link then
        local itemID = tonumber(string.match(link, "item:(%d+)"))
        if itemID then
          addLines(tt, itemID, link)
          addCrate(tt, itemID)
          addWrit(tt, itemID)
        end
      end
    end)
  end
end)

H.Tooltip = { AddLines = addLines, AddCrate = addCrate, AddWrit = addWrit, OnTooltip = onTooltip }
