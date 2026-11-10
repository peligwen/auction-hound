-- Writ.lua: what it costs to fill a Craftsman's Writ.
--
-- A writ asks for one crafted item, a Lesser Wizard's Robe say, and
-- the item may be bought as well as made. Data/Writs.lua holds the
-- item by writ; this prices it at the auction house the way a crate's
-- goods are priced (Crate.lua) and says when none is there to buy.
-- The writ's tooltip shows the lines (Tooltip.lua) and /hound writ
-- prints them.
local ADDON, H = ...

local Writ = {}
H.Writ = Writ

------------------------------------------------------------------------
-- A writ, read. Returns nil for an item that is no writ.
--
--   item, qty   what it asks for, and how many
--   name        the item's name
--   rank, rep   the writ's rank, and the reputation one of it pays
--   unit, src   the price of one, and where it came from
--   total       unit times qty
--   listed      units the last scan saw, when that is fewer than the
--               writ asks for: it cannot be bought whole at the house
--   scanAge     seconds since the last full scan, nil without one
------------------------------------------------------------------------
function Writ.Read(itemID, now)
  local w = H.Writs and H.Writs[itemID]
  if not w then return nil end
  now = now or H.Now()
  local scan = H.Store.LastScan()
  local rank = H.WritRanks[w[4]]
  local unit, src, st = H.Crate.UnitPrice(w[1])
  local r = {
    itemID = itemID, item = w[1], qty = w[2], name = H.Crate.GoodName(w[1], w[3]),
    rank = rank.name, rep = rank.rep, unit = unit, src = src,
    scanAge = scan and (now - scan.t) or nil,
  }
  if unit then
    r.total = unit * r.qty
    local listed = H.Crate.Listed(st)
    if listed and listed < r.qty then r.listed = listed end
  end
  return r
end

------------------------------------------------------------------------
-- The lines a tooltip or the chat shows for a writ: a header with its
-- rank and what it pays, then the item with its price on the right.
-- Each is { left, right, color }, as a crate's are. One item is only
-- named; more than one carries the count and the price of each.
------------------------------------------------------------------------
function Writ.Lines(r)
  local C = H.Crate.COLORS
  local age = ""
  if r.scanAge then
    age = "scanned " .. H.Ago(r.scanAge)
  elseif not r.unit then
    age = "no scan yet"
  end
  local left = "  " .. r.name
  if r.qty > 1 then left = string.format("  %d %s", r.qty, r.name) end
  local right, color = "no price", C.none
  if r.unit then
    local mark = r.src == "crafted" and "~" or ""
    if r.qty > 1 then left = left .. string.format(", %s%s each", mark, H.Money(r.unit)) end
    if r.listed then
      left = left .. (r.listed > 0 and string.format(", |cffd9cc73only %d listed|r", r.listed) or ", |cffd9cc73none listed|r")
    end
    right, color = mark .. H.Money(r.total), C.price
  end
  return {
    { string.format("|cffe6b800Hound|r %s writ, %d reputation", r.rank, r.rep), age, C.none },
    { left, right, color },
  }
end

function Writ.AddTooltipLines(tooltip, itemID)
  local r = Writ.Read(itemID)
  if not r then return false end
  H.Crate.Paint(tooltip, Writ.Lines(r))
  return true
end

-- /hound writ <link or id>: the same lines in chat, or the item's ID
-- when it is no writ the data knows, which is the thing to report.
function Writ.Describe(itemID)
  local r = Writ.Read(itemID)
  if not r then
    H.Printf("%s (item %d) is not a writ Hound knows", H.ItemName(itemID), itemID)
    return false
  end
  local lines = Writ.Lines(r)
  H.Printf("Craftsman's Writ: %s (item %d)", r.name, itemID)
  H.Print(string.format("  %s%s", string.gsub(lines[1][1], "^|cffe6b800Hound|r ", ""), lines[1][2] ~= "" and (", " .. lines[1][2]) or ""))
  H.Print(string.format("%s: %s", lines[2][1], lines[2][2]))
  return true
end
