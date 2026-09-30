-- Tooltip.lua: a few Hound lines on item tooltips.
local ADDON, H = ...

local function addLines(tooltip, itemID, link)
  if not H.db or not H.Settings().tooltip then return end
  local key = link and H.KeyFromLink(link, itemID) or tostring(itemID)
  if not key then return end
  local rec = H.Store.Get(key)
  local st = rec and H.Market.Stats(rec) or nil
  if st and not st.market then st = nil end
  local cl = H.Market.Clearing(H.Store.Posts(key))
  if cl and cl.soldUnits == 0 and cl.unsoldUnits == 0 then cl = nil end
  if not st and not cl then return end
  tooltip:AddLine(" ")
  if st then
    tooltip:AddDoubleLine("|cffe6b800Hound|r market", H.Money(st.market), 1, 0.82, 0, 1, 1, 1)
    if st.min then
      tooltip:AddDoubleLine("  floor / listed", string.format("%s / %d", H.Money(st.min), st.qty or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if st.hist then
      tooltip:AddDoubleLine("  30 day", H.Money(st.hist), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local parts = {}
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
end

H.Events:On("LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
      local _, link = tt:GetItem()
      if link then
        local itemID = tonumber(string.match(link, "item:(%d+)"))
        if itemID then addLines(tt, itemID, link) end
      end
    end)
  end
end)

H.Tooltip = { AddLines = addLines, OnTooltip = onTooltip }
