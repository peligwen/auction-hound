-- Crate.lua: what it costs to fill a Waylaid Crate.
--
-- A crate names the bundles that fill it, twenty copper ore or twenty
-- tin ore say, and any one of them does. Data/Crates.lua holds the
-- bundles by crate; this prices each at the auction house and says
-- which is cheapest to buy. The crate's tooltip shows the lines
-- (Tooltip.lua) and /hound crate prints them.
local ADDON, H = ...

local Crate = {}
H.Crate = Crate

-- One unit of a good, as the house prices it: the market value its own
-- tooltip shows, or history older than the two weeks that value spans
-- (the 30-day mean, else the last scan it was seen in). With neither,
-- and estimates on, what it costs to make. Returns the price, where it
-- came from ("market" or "crafted") and the stats, or nil. The item a
-- writ asks for is priced here too (Writ.lua), gear included.
function Crate.UnitPrice(itemID)
  local rec = H.Store.Plain(itemID)
  local st = rec and H.Market.Stats(rec) or nil
  local price = st and (st.market or st.hist or st.recent)
  if price and price > 0 then return price, "market", st end
  if H.Settings().estimates then
    local cost = H.Priors.CraftCost(itemID)
    if cost and cost > 0 then return cost, "crafted", st end
  end
  return nil, nil, st
end

-- Units of a good the last full scan saw on offer: nil when no scan
-- has run in this market, 0 when the good was not in it. A record's
-- last point is the scan's own time, kept to the minute once saved.
function Crate.Listed(st)
  local scan = H.Store.LastScan()
  if not scan then return nil end
  if not st or not st.at or st.at < scan.t - 60 then return 0 end
  return st.qty or 0
end

-- A good's name: the client's, or the data's English one while the
-- client has yet to load the item, which is then asked for.
local function goodName(itemID, fallback)
  local name = H.ItemName(itemID)
  if fallback and string.sub(name, 1, 5) == "item:" then
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return fallback
  end
  return name
end
Crate.GoodName = goodName

------------------------------------------------------------------------
-- A crate, read. Returns nil for an item that is no crate.
--
--   name      the crate's name after "Waylaid Crate: "
--   bundles   in the tooltip's order, each
--               itemID, qty, name
--               unit, src   the price of one, and where it came from
--               total       unit times qty
--               listed      units the last scan saw, when that is fewer
--                           than the bundle takes: it cannot be bought
--                           whole at the house
--   priced    how many bundles have a price
--   best      index of the cheapest bundle the house could fill, when
--             more than one is priced
--   scanAge   seconds since the last full scan, nil without one
------------------------------------------------------------------------
function Crate.Read(itemID, now)
  local c = H.Crates and H.Crates[itemID]
  if not c then return nil end
  now = now or H.Now()
  local scan = H.Store.LastScan()
  local out = { itemID = itemID, name = c.name, bundles = {}, priced = 0, scanAge = scan and (now - scan.t) or nil }
  local best
  for i, b in ipairs(c.bundles) do
    local unit, src, st = Crate.UnitPrice(b[1])
    local e = { itemID = b[1], qty = b[2], name = goodName(b[1], b[3]), unit = unit, src = src }
    if unit then
      e.total = unit * e.qty
      out.priced = out.priced + 1
      local listed = Crate.Listed(st)
      if listed and listed < e.qty then
        e.listed = listed
      elseif not best or e.total < out.bundles[best].total then
        best = i
      end
    end
    out.bundles[i] = e
  end
  if out.priced > 1 then out.best = best end
  return out
end

------------------------------------------------------------------------
-- The lines a tooltip or the chat shows for a crate: a header, then
-- one line per bundle with the units and the price of one on the left
-- and the bundle's total on the right. Each is { left, right, color }.
-- An estimate carries a "~", the way the Buy tab marks one.
------------------------------------------------------------------------
Crate.COLORS = {
  best = { 0.30, 0.85, 0.30 },
  price = { 1, 1, 1 },
  none = { 0.5, 0.5, 0.5 },
}

function Crate.Lines(r)
  local lines = {}
  local head = #r.bundles > 1 and "any one bundle fills it" or "fills it"
  local age = ""
  if r.scanAge then
    age = "scanned " .. H.Ago(r.scanAge)
  elseif r.priced == 0 then
    age = "no scan yet"
  end
  lines[1] = { "|cffe6b800Hound|r " .. head, age, Crate.COLORS.none }
  for i, e in ipairs(r.bundles) do
    local left = string.format("  %d %s", e.qty, e.name)
    local right, color = "no price", Crate.COLORS.none
    if e.unit then
      local mark = e.src == "crafted" and "~" or ""
      left = left .. string.format(", %s%s each", mark, H.Money(e.unit))
      if e.listed then
        left = left .. (e.listed > 0 and string.format(", |cffd9cc73only %d listed|r", e.listed) or ", |cffd9cc73none listed|r")
      end
      right = mark .. H.Money(e.total)
      color = i == r.best and Crate.COLORS.best or Crate.COLORS.price
    end
    lines[#lines + 1] = { left, right, color }
  end
  return lines
end

-- Lines onto a tooltip, set apart by a blank one: the header in a
-- tooltip's own gold, the rest grey, each right side in its color.
function Crate.Paint(tooltip, lines)
  tooltip:AddLine(" ")
  for i, line in ipairs(lines) do
    local c = line[3]
    if i == 1 then
      tooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, c[1], c[2], c[3])
    else
      tooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, c[1], c[2], c[3])
    end
  end
end

function Crate.AddTooltipLines(tooltip, itemID)
  local r = Crate.Read(itemID)
  if not r then return false end
  Crate.Paint(tooltip, Crate.Lines(r))
  return true
end

-- /hound crate <link or id>: the same lines in chat, or the item's ID
-- when it is no crate the data knows, which is the thing to report.
function Crate.Describe(itemID)
  local r = Crate.Read(itemID)
  if not r then
    H.Printf("%s (item %d) is not a crate Hound knows", H.ItemName(itemID), itemID)
    return false
  end
  H.Printf("Waylaid Crate: %s (item %d)", r.name, itemID)
  for i, line in ipairs(Crate.Lines(r)) do
    if i == 1 then
      H.Print(string.format("  %s%s", string.gsub(line[1], "^|cffe6b800Hound|r ", ""), line[2] ~= "" and (", " .. line[2]) or ""))
    else
      H.Print(string.format("%s: %s%s", line[1], line[2], i - 1 == r.best and " (cheapest)" or ""))
    end
  end
  return true
end
