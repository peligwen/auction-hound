-- Priors.lua: what an item is worth when the market history is thin.
--
-- Three anchors: the vendor floor, what it costs to make, and what it
-- turns into. On launch day these are all a flipper has.
local ADDON, H = ...

local Priors = {}
H.Priors = Priors

local byOutput, byInput

local function index()
  if byOutput then return end
  byOutput, byInput = {}, {}
  for _, r in ipairs(H.Conversions or {}) do
    byOutput[r.out] = byOutput[r.out] or {}
    table.insert(byOutput[r.out], r)
    for _, inp in ipairs(r.inputs) do
      byInput[inp[1]] = byInput[inp[1]] or {}
      table.insert(byInput[inp[1]], r)
    end
  end
end

function Priors.RecipesMaking(itemID)
  index()
  return byOutput[itemID] or {}
end

function Priors.RecipesUsing(itemID)
  index()
  return byInput[itemID] or {}
end

function Priors.VendorSell(itemID)
  return H.VendorSell(itemID)
end

-- Market value for an item ID, or nil. Uses stored history only.
function Priors.MarketValue(itemID)
  local rec = H.Store.Get(tostring(itemID))
  if not rec then return nil end
  local st = H.Market.Stats(rec)
  return st.market, H.Market.Confidence(st)
end

-- Best known unit price for an input: vendor price, then market, then
-- crafted cost (bounded recursion).
function Priors.InputPrice(itemID, depth)
  depth = depth or 0
  local vendor = H.VendorBuy and H.VendorBuy[itemID]
  if vendor then return vendor, "vendor" end
  local mv = Priors.MarketValue(itemID)
  if mv then return mv, "market" end
  if depth < 3 then
    local cost = Priors.CraftCost(itemID, depth + 1)
    if cost then return cost, "crafted" end
  end
  return nil
end

-- Cheapest way to make one unit of the item from priced inputs.
-- Returns unit cost, recipe, and a breakdown array.
function Priors.CraftCost(itemID, depth)
  depth = depth or 0
  local best, bestRecipe, bestParts
  for _, r in ipairs(Priors.RecipesMaking(itemID)) do
    local total, parts, ok = 0, {}, true
    for _, inp in ipairs(r.inputs) do
      local price, src = Priors.InputPrice(inp[1], depth)
      if not price then ok = false break end
      total = total + price * inp[2]
      table.insert(parts, { id = inp[1], qty = inp[2], price = price, src = src })
    end
    if ok then
      local unit = total / r.outQty
      if not best or unit < best then best, bestRecipe, bestParts = unit, r, parts end
    end
  end
  if best then return H.Round(best), bestRecipe, bestParts end
  return nil
end

-- What one unit of the item is worth as an input, net of the other
-- inputs and the AH cut on the output. Returns value, recipe.
function Priors.MakesValue(itemID)
  local cut = H.Settings().cut or 0.05
  local best, bestRecipe
  for _, r in ipairs(Priors.RecipesUsing(itemID)) do
    local outMV = Priors.MarketValue(r.out)
    if outMV then
      local revenue = outMV * r.outQty * (1 - cut)
      local myQty, ok = 0, true
      for _, inp in ipairs(r.inputs) do
        if inp[1] == itemID then
          myQty = inp[2]
        else
          local price = Priors.InputPrice(inp[1])
          if not price then ok = false break end
          revenue = revenue - price * inp[2]
        end
      end
      if ok and myQty > 0 then
        local unit = revenue / myQty
        if not best or unit > best then best, bestRecipe = unit, r end
      end
    end
  end
  if best then return H.Round(best), bestRecipe end
  return nil
end

-- Reference price when history is too thin to trust. Returns value and
-- a short source label, or nil. Nothing at all with estimates off: the
-- anchors still show in the Item view, but no price is judged by them.
function Priors.Estimate(itemID)
  if not H.Settings().estimates then return nil end
  local cost = Priors.CraftCost(itemID)
  if cost then return cost, "crafted cost" end
  local makes = Priors.MakesValue(itemID)
  if makes then return makes, "value as an input" end
  return nil
end

-- Hard floor: the item is worth at least this much to anyone.
function Priors.Floor(itemID)
  local floor, src = 0, nil
  local vendor = Priors.VendorSell(itemID)
  if vendor and vendor > floor then floor, src = vendor, "vendor" end
  local makes = Priors.MakesValue(itemID)
  if makes and makes > floor then floor, src = makes, "conversion" end
  if src then return floor, src end
  return nil
end

------------------------------------------------------------------------
-- Connections for the item view: every recipe touching the item with
-- cost, value, spread per craft, and gold per hour at the labor setting.
------------------------------------------------------------------------
local function recipeEconomics(r)
  local cut = H.Settings().cut or 0.05
  local labor = (H.Settings().laborPerHour or 0) * 10000
  local cast = r.cast or H.DEFAULT_CAST or 3
  local inputCost, parts, ok = 0, {}, true
  for _, inp in ipairs(r.inputs) do
    local price, src = Priors.InputPrice(inp[1])
    table.insert(parts, { id = inp[1], qty = inp[2], price = price, src = src })
    if price then inputCost = inputCost + price * inp[2] else ok = false end
  end
  local outMV = Priors.MarketValue(r.out)
  local e = { recipe = r, parts = parts, inputCost = ok and inputCost or nil, outMV = outMV, cast = cast }
  if ok and outMV then
    e.revenue = outMV * r.outQty * (1 - cut)
    e.spread = e.revenue - inputCost
    e.perHour = e.spread * (3600 / cast)
    e.laborCost = labor * (cast / 3600)
    e.spreadAfterLabor = e.spread - e.laborCost
  end
  return e
end

function Priors.Connections(itemID)
  local out = { makes = {}, madeFrom = {} }
  for _, r in ipairs(Priors.RecipesMaking(itemID)) do
    table.insert(out.madeFrom, recipeEconomics(r))
  end
  for _, r in ipairs(Priors.RecipesUsing(itemID)) do
    table.insert(out.makes, recipeEconomics(r))
  end
  return out
end
