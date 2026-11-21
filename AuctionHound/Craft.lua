-- Craft.lua: what a recipe's materials cost, and what the craft brings.
--
-- A recipe in the profession window, read from the client: the item it
-- makes and how many, and the reagents it requires, each slot's
-- cheapest choice where a slot takes more than one item. Each reagent
-- is priced as a crate's goods are (Crate.lua), at its market value,
-- or at what a vendor sells it for when a vendor window has shown it
-- cheaper (Vendor.lua). The product is priced the same way and taken
-- less the house's cut; what is left over the materials is the profit.
-- An optional reagent is no part of the cost. A recipe with a reagent
-- that has no price has no total, only what is priced so far, and no
-- profit; nor has one whose product has no price, an enchant say.
-- The panel beside the profession window shows it (UI/Craft.lua).
local ADDON, H = ...

local Craft = {}
H.Craft = Craft

local function api()
  return type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil
end

-- True when this client can read a recipe the way Hound does.
function Craft.Available()
  local T = api()
  return T and type(T.GetRecipeSchematic) == "function" and type(T.GetAllRecipeIDs) == "function" or false
end

-- A slot the craft cannot go without. The client says so itself; an
-- older schematic without the flag is read by its type, where a basic
-- reagent is the required kind.
local function required(slot)
  if slot.required ~= nil then return slot.required and true or false end
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  if basic and slot.reagentType ~= nil then return slot.reagentType == basic end
  return true
end

------------------------------------------------------------------------
-- A recipe, read. Returns nil for one the client has no schematic for,
-- or one that makes nothing fixed from fixed goods (salvage, a recraft,
-- gathering).
--
--   recipeID, name, icon, learned
--   itemID     what it makes, nil when it makes no item (an enchant)
--   made       units a craft makes: the mean of madeMin and madeMax
--   reagents   the required slots, in the window's order, each
--                qty     units a craft takes
--                items   the item IDs that fill it, any one of them
--   currency   true when a slot asks for a currency, which is not priced
--
-- A schematic does not change while the window is open, and the window
-- updates often, so cache, when given, keeps what each one gave by
-- recipe; the recipe's own info (learned, its name) is read every time.
------------------------------------------------------------------------
local function fromSchematic(s)
  local b = { itemID = s.outputItemID, name = s.name, icon = s.icon, reagents = {} }
  if b.itemID == 0 then b.itemID = nil end
  local lo = math.max(1, s.quantityMin or 1)
  local hi = math.max(lo, s.quantityMax or lo)
  b.madeMin, b.madeMax, b.made = lo, hi, (lo + hi) / 2
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    if required(slot) then
      local e = { qty = math.max(1, slot.quantityRequired or 1), items = {} }
      for _, g in ipairs(slot.reagents or {}) do
        if g.itemID and g.itemID > 0 then
          table.insert(e.items, g.itemID)
        elseif g.currencyID then
          b.currency = true
        end
      end
      if #e.items > 0 then table.insert(b.reagents, e) end
    end
  end
  return b
end

function Craft.Recipe(recipeID, cache)
  local T = api()
  if not T or not recipeID then return nil end
  local info = T.GetRecipeInfo and T.GetRecipeInfo(recipeID)
  if type(info) ~= "table" then info = {} end
  if info.isSalvageRecipe or info.isRecraft or info.isGatheringRecipe or info.isDummyRecipe then return nil end
  local b = cache and cache[recipeID]
  if b == nil then
    local s = T.GetRecipeSchematic(recipeID, false)
    b = type(s) == "table" and fromSchematic(s) or false
    if cache then cache[recipeID] = b end
  end
  if not b then return nil end
  return {
    recipeID = recipeID, name = info.name or b.name or ("recipe " .. recipeID), icon = info.icon or b.icon,
    learned = info.learned ~= false, itemID = b.itemID, reagents = b.reagents, currency = b.currency,
    madeMin = b.madeMin, madeMax = b.madeMax, made = b.made,
  }
end

-- The recipes of the profession open, read, the unlearned among them.
function Craft.Recipes(cache)
  local T = api()
  local out = {}
  if not Craft.Available() then return out end
  local ids = T.GetAllRecipeIDs() or {}
  for _, id in ipairs(ids) do
    local r = Craft.Recipe(id, cache)
    if r then table.insert(out, r) end
  end
  return out
end

------------------------------------------------------------------------
-- Prices
------------------------------------------------------------------------

-- One unit of a reagent: its market value, or a vendor's price when
-- that is lower or the house has none. Returns the price, its source
-- ("market" or "vendor"), and the stats when the house's was used.
function Craft.ReagentPrice(itemID)
  local unit, src, st = H.Crate.UnitPrice(itemID)
  local vendor = H.VendorBuy(itemID)
  if vendor and (not unit or vendor <= unit) then return vendor, "vendor", nil end
  return unit, src, st
end

-- A reagent's name, asked of the client when it has yet to load it.
local function nameOf(itemID)
  local name = H.ItemName(itemID)
  if string.sub(name, 1, 5) == "item:" then
    Craft.unnamed = true
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
  end
  return name
end

------------------------------------------------------------------------
-- A recipe, priced. Adds to the recipe read:
--
--   lines      one per reagent, each
--                itemID, qty, name
--                unit, src   the price of one, and where it came from
--                total       unit times qty
--                listed      units the last scan saw, when the house is
--                            the price and that is fewer than a craft takes
--   cost       the materials, whenever every reagent has a price
--   partial    what the reagents priced come to, when some have none
--   unpriced   how many reagents have no price
--   value, valueSrc   the product's price, one unit
--   sells      what a craft's units bring at the house, less its cut
--   profit     sells less cost, when both are known
--   margin     profit over cost
------------------------------------------------------------------------
function Craft.Price(r)
  if not r then return nil end
  r.lines, r.unpriced = {}, 0
  local sum = 0
  for _, slot in ipairs(r.reagents) do
    local best
    for _, id in ipairs(slot.items) do
      local unit, src, st = Craft.ReagentPrice(id)
      if unit and (not best or unit < best.unit) then best = { itemID = id, unit = unit, src = src, st = st } end
    end
    local e = { itemID = best and best.itemID or slot.items[1], qty = slot.qty }
    e.name = nameOf(e.itemID)
    if best then
      e.unit, e.src = best.unit, best.src
      e.total = e.unit * e.qty
      sum = sum + e.total
      if best.src ~= "vendor" then
        local listed = H.Crate.Listed(best.st)
        if listed and listed < e.qty then e.listed = listed end
      end
    else
      r.unpriced = r.unpriced + 1
    end
    table.insert(r.lines, e)
  end
  if r.currency then r.unpriced = r.unpriced + 1 end
  r.cost, r.partial = nil, nil
  if r.unpriced == 0 then r.cost = sum elseif sum > 0 then r.partial = sum end
  r.value, r.valueSrc, r.sells, r.profit, r.margin = nil, nil, nil, nil, nil
  if r.itemID then
    local unit, src = H.Crate.UnitPrice(r.itemID)
    if unit then
      r.value, r.valueSrc = unit, src
      r.sells = unit * r.made * (1 - H.Cut())
    end
  end
  if r.sells and r.cost then
    r.profit = r.sells - r.cost
    if r.cost > 0 then r.margin = r.profit / r.cost end
  end
  return r
end

function Craft.Read(recipeID)
  return Craft.Price(Craft.Recipe(recipeID))
end

-- Every recipe of the profession open, priced.
function Craft.ReadAll(cache)
  local out = Craft.Recipes(cache)
  for _, r in ipairs(out) do Craft.Price(r) end
  return out
end

------------------------------------------------------------------------
-- The lines a tooltip or the panel shows for a recipe: a reagent a
-- line, then the materials, what a craft sells for and the profit.
-- Each is { left, right, color }, as a crate's are.
------------------------------------------------------------------------
Craft.COLORS = {
  price = { 1, 1, 1 },
  none = { 0.5, 0.5, 0.5 },
  gain = { 0.30, 0.85, 0.30 },
  loss = { 0.90, 0.35, 0.30 },
}

-- "makes 2", or "makes 1-3" with the mean the price is taken at.
function Craft.MadeText(r)
  if r.madeMax > r.madeMin then return string.format("makes %d-%d", r.madeMin, r.madeMax) end
  return string.format("makes %d", r.made)
end

-- The price of one reagent, "v " before a vendor's, in the money form
-- given (H.Money by default); nil when it has none.
function Craft.EachText(e, money)
  if not e.unit then return nil end
  return (e.src == "vendor" and "v " or "") .. (money or H.Money)(e.unit)
end

-- After a reagent's name when the last scan saw too few for a craft.
function Craft.ListedNote(e)
  if not e.listed then return "" end
  if e.listed > 0 then return string.format(" |cffd9cc73(only %d listed)|r", e.listed) end
  return " |cffd9cc73(none listed)|r"
end

function Craft.ReagentLine(e)
  local left = string.format("%d %s", e.qty, e.name)
  if not e.unit then return { left, "no price", Craft.COLORS.none } end
  local each = H.Money(e.unit)
  if e.src == "vendor" then each = "vendor " .. each end
  left = left .. ", " .. each .. (e.qty > 1 and " each" or "") .. Craft.ListedNote(e)
  return { left, H.Money(e.total), Craft.COLORS.price }
end

function Craft.ProfitText(r, money)
  if not r.profit then return nil end
  local text = (r.profit >= 0 and "+" or "") .. (money or H.MoneyExact)(r.profit)
  if r.margin then text = text .. " (" .. H.Pct(r.margin, true) .. ")" end
  return text
end

-- The materials, the sale and the profit, in the money form given.
function Craft.SummaryLines(r, money)
  money = money or H.Money
  local C = Craft.COLORS
  local lines = {}
  if r.cost then
    lines[1] = { "materials", money(r.cost), C.price }
  elseif r.partial then
    lines[1] = { string.format("materials (%d without a price)", r.unpriced), "at least " .. money(r.partial), C.none }
  else
    lines[1] = { "materials", "no price", C.none }
  end
  if not r.itemID then
    lines[2] = { "sells", "makes no item", C.none }
  elseif r.sells then
    local made = ""
    if r.madeMax > r.madeMin then
      made = string.format("~%g ", r.made)
    elseif r.made > 1 then
      made = string.format("%d ", r.made)
    end
    lines[2] = { string.format("sells %sat %s, less %s cut", made, money(r.value), H.Pct(H.Cut())), money(r.sells), C.price }
  else
    lines[2] = { "sells", "no price", C.none }
  end
  local p = Craft.ProfitText(r, money == H.Money and H.MoneyExact or money)
  if p then
    lines[3] = { "profit", p, r.profit >= 0 and C.gain or C.loss }
  end
  return lines
end

-- Every line, the reagents indented under a header.
function Craft.Lines(r)
  local lines = { { "|cffe6b800Hound|r " .. Craft.MadeText(r), "", Craft.COLORS.none } }
  for _, e in ipairs(r.lines) do
    local l = Craft.ReagentLine(e)
    l[1] = "  " .. l[1]
    table.insert(lines, l)
  end
  for _, l in ipairs(Craft.SummaryLines(r)) do table.insert(lines, l) end
  return lines
end
