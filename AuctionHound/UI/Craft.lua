-- UI/Craft.lua: Hound's panel beside the profession window.
--
-- At the top, the recipe picked: each reagent with its price, what the
-- materials come to, what a craft sells for less the house's cut, and
-- the profit (Craft.lua). Under it, every recipe of the profession in a
-- list of Hound's own, sorted by profit, the best first; any header
-- sorts by its column. The recipe picked is the one picked in the
-- window's own list, or a row clicked in Hound's; a double-click asks
-- the client to open that recipe in the window. The panel hangs off
-- the window's right edge; its close button puts it away for every
-- profession, and a small Hound tab on the window's edge, or /hound
-- craft, brings it back.
--
-- Nothing of Blizzard's is written or run (README, Taint): the window
-- is met by HookScript on its show and hide and a secure hook on its
-- recipe form's Init, which hands over the recipe picked. Hound's
-- frames are children of the window, so they go with it, and only
-- read the window's own field for the recipe it shows. A double-click
-- asks the client through C_TradeSkillUI, never the window's code.
local ADDON, H = ...

local UI = H.UI
local Craft = H.Craft
local P = {}
UI.Craft = P

P.WIDTH = 390
P.LINES = 8        -- reagent lines for the recipe picked; more fold into one
P.DELAY = 0.5      -- seconds the window's updates are gathered for before a rebuild

local C = Craft.COLORS

local function host() return type(ProfessionsFrame) == "table" and ProfessionsFrame or nil end

local function form()
  local f = host()
  local page = f and f.CraftingPage
  return type(page) == "table" and page.SchematicForm or nil
end

function P.Visible()
  local f = host()
  return P.frame and P.frame:IsShown() and f and f:IsShown() and true or false
end

------------------------------------------------------------------------
-- The recipe picked
------------------------------------------------------------------------

-- The lines for the recipe picked: its name and what it makes, a line
-- per reagent, then the materials, the sale and the profit.
function P.PickedLines(r)
  if not r then return { { "Pick a recipe: its materials are priced here", "", C.none } } end
  local out = { { r.name, Craft.MadeText(r), C.none } }
  local n = #r.lines
  for i, e in ipairs(r.lines) do
    if i == P.LINES and n > P.LINES then
      local rest, any = 0, false
      for j = i, n do
        if r.lines[j].total then rest, any = rest + r.lines[j].total, true end
      end
      table.insert(out, { string.format("  and %d more", n - i + 1), any and H.Money(rest) or "", C.price })
      break
    end
    local l = Craft.ReagentLine(e)
    l[1] = "  " .. l[1]
    table.insert(out, l)
  end
  for _, l in ipairs(Craft.SummaryLines(r)) do table.insert(out, l) end
  return out
end

function P.RenderPicked()
  local f = P.frame
  if not f then return end
  local lines = P.PickedLines(P.picked)
  for i, row in ipairs(f.lines) do
    local l = lines[i]
    if l then
      row.left:SetText(l[1])
      row.right:SetText(l[2])
      if i == 1 then row.left:SetTextColor(1, 0.82, 0) else row.left:SetTextColor(0.8, 0.8, 0.8) end
      row.right:SetTextColor(l[3][1], l[3][2], l[3][3])
    else
      row.left:SetText("")
      row.right:SetText("")
    end
  end
end

-- Picks a recipe for the top of the panel, and in Hound's list.
function P.Pick(recipeID)
  P.recipeID = recipeID
  P.picked = nil
  for _, r in ipairs(P.rows or {}) do
    if r.recipeID == recipeID then P.picked = r end
  end
  if not P.picked and recipeID then P.picked = Craft.Price(Craft.Recipe(recipeID, P.cache)) end
  if P.table then
    P.table.selectedKey = recipeID
    P.table:Refresh(true)
  end
  P.RenderPicked()
end

-- The window's own pick, as its recipe form was handed it.
function P.OnInit(recipeInfo)
  local id = type(recipeInfo) == "table" and recipeInfo.recipeID or nil
  if not id then return end
  if P.frame then P.Pick(id) else P.recipeID = id end
end

-- Asks the client to show the recipe in the window. Its own handler
-- picks it there, which hands it back to Hound through the form.
function P.Open(recipeID)
  local T = C_TradeSkillUI
  if type(T) == "table" and type(T.OpenRecipe) == "function" and recipeID then
    T.OpenRecipe(recipeID)
    return true
  end
  return false
end

------------------------------------------------------------------------
-- Hound's list of the profession's recipes
------------------------------------------------------------------------
local function profitColor(row)
  if not row.profit then return 0.5, 0.5, 0.5 end
  local c = row.profit >= 0 and C.gain or C.loss
  return c[1], c[2], c[3]
end

local function rowTooltip(r, frame)
  if not GameTooltip then return end
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  if r.itemID then
    GameTooltip:SetItemByID(r.itemID)
  else
    GameTooltip:AddLine(r.name, 1, 1, 1)
  end
  H.Crate.Paint(GameTooltip, Craft.Lines(r))
  if not r.learned then GameTooltip:AddLine("not learned yet", 0.6, 0.6, 0.6) end
  GameTooltip:AddLine("click to price it above; double-click to open it in the window", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local COLUMNS = {
  { key = "name", title = "Recipe", width = 150, kind = "item",
    value = function(r) return r.name end,
    text = function(r) return r.learned and r.name or ("|cff808080" .. r.name .. "|r") end },
  { key = "cost", title = "Cost", width = 64, kind = "money", align = "RIGHT", value = function(r) return r.cost end },
  { key = "sells", title = "Sells", width = 64, kind = "money", align = "RIGHT", desc = true, value = function(r) return r.sells end },
  { key = "profit", title = "Profit", width = 74, kind = "money", align = "RIGHT", desc = true,
    value = function(r) return r.profit end, color = profitColor },
}
P.COLUMNS = COLUMNS

local function passes(r)
  return r.learned or H.Settings().craftUnlearned
end

function P.Counts()
  local shown, priced, gain = 0, 0, 0
  for _, r in ipairs(P.rows or {}) do
    if passes(r) then
      shown = shown + 1
      if r.cost then priced = priced + 1 end
      if r.profit and r.profit > 0 then gain = gain + 1 end
    end
  end
  return shown, priced, gain
end

function P.StatusText()
  local shown, priced, gain = P.Counts()
  local text = string.format("%d recipes, %d priced, %d at a profit", shown, priced, gain)
  local last = H.Store.LastScan()
  if not last then return text .. "; no scan yet" end
  return text
end

-- Reads every recipe of the profession again, and the one picked.
function P.Rebuild()
  if not P.frame then return end
  Craft.unnamed = false
  P.cache = P.cache or {}
  P.rows = Craft.ReadAll(P.cache)
  for _, r in ipairs(P.rows) do r.key = r.recipeID end
  P.table:SetData(P.rows)
  P.frame.status:SetText(P.StatusText())
  P.Pick(P.recipeID)
  -- names the client had yet to load come in a moment later
  if Craft.unnamed and (P.renames or 0) < 3 then
    P.renames = (P.renames or 0) + 1
    P.Schedule(1)
  elseif not Craft.unnamed then
    P.renames = 0
  end
end

-- Gathers the window's bursts of updates into one rebuild.
function P.Schedule(delay)
  if P.pending then return end
  P.pending = true
  C_Timer.After(delay or P.DELAY, function()
    P.pending = false
    if P.Visible() then P.Rebuild() end
  end)
end

------------------------------------------------------------------------
-- The panel and the tab that brings it back
------------------------------------------------------------------------
local function build(parent)
  local f = UI.Create("Frame", "AuctionHoundCraft", parent, "BackdropTemplate")
  f:SetWidth(P.WIDTH)
  f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 0, 0)
  f:EnableMouse(true)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  f.title = UI.Text(f, "GameFontNormal", "Hound: recipe costs")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
  f.close = UI.Button(f, "x", 22, 20, function() P.SetShown(false) end)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)

  f.lines = {}
  local y = -36
  for i = 1, 1 + P.LINES + 3 do
    local row = {}
    row.left = UI.Text(f, i == 1 and "GameFontHighlight" or "GameFontHighlightSmall", "", "LEFT")
    row.left:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y)
    row.left:SetPoint("RIGHT", f, "RIGHT", -118, 0)
    row.right = UI.Text(f, "GameFontHighlightSmall", "", "RIGHT")
    row.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y)
    row.right:SetWidth(100)
    f.lines[i] = row
    y = y - (i == 1 and 18 or 14)
  end

  local div = UI.Divider(f)
  div:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - 4)
  div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y - 4)

  f.unlearned = UI.CheckButton(f, "Unlearned too", function(on)
    H.Settings().craftUnlearned = on and true or false
    P.table:Refresh()
    f.status:SetText(P.StatusText())
  end)
  f.unlearned:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - 10)
  f.unlearned:SetChecked(H.Settings().craftUnlearned and true or false)
  f.status = UI.Text(f, "GameFontHighlightSmall", "", "RIGHT")
  f.status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y - 14)
  f.status:SetPoint("LEFT", f.unlearned.label, "RIGHT", 8, 0)

  P.table = UI.CreateTable(f, COLUMNS, {
    sortKey = "profit", sortDesc = true, rowHeight = 16,
    onSelect = function(r) P.Pick(r.recipeID) end,
    onDouble = function(r) P.Open(r.recipeID) end,
    tooltip = rowTooltip,
  })
  P.table:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - 36)
  P.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
  P.table:Filter(passes)
  return f
end

local function buildTab(parent)
  local b = UI.Button(parent, "Hound", 60, 22, function() P.SetShown(true) end)
  b:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -40)
  return b
end

-- Shows the panel or the tab, as the setting says, while the window is up.
function P.Place()
  local f = host()
  if not f or not f:IsShown() then return end
  local on = H.Settings().craftPanel and true or false
  if on and not P.frame then
    P.frame = build(f)
    P.table:Layout()
    if not P.recipeID then
      local sf = form()
      local info = sf and sf.currentRecipeInfo
      if type(info) == "table" then P.recipeID = info.recipeID end
    end
  end
  if not on and not P.tab then P.tab = buildTab(f) end
  if P.frame then
    if on then P.frame:Show() else P.frame:Hide() end
  end
  if P.tab then
    if on then P.tab:Hide() else P.tab:Show() end
  end
  if on then P.Rebuild() end
end

function P.SetShown(on)
  H.Settings().craftPanel = on and true or false
  P.Place()
end

------------------------------------------------------------------------
-- /hound craft [on|off]
------------------------------------------------------------------------
function P.Command(rest)
  local v = string.lower(rest or "")
  local S = H.Settings()
  if v == "on" or v == "off" then
    P.SetShown(v == "on")
  elseif v == "" then
    P.SetShown(not S.craftPanel)
  else
    H.Print("usage: /hound craft [on|off]")
    return
  end
  if S.craftPanel then
    H.Print("recipe costs are on: Hound's panel opens beside the profession window")
  else
    H.Print("recipe costs are off: the Hound tab on the profession window's edge, or /hound craft, brings them back")
  end
end

------------------------------------------------------------------------
-- Meeting the window. It is Blizzard's own addon, loaded the first time
-- a profession opens.
------------------------------------------------------------------------
local function safely(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not P.failed then
    P.failed = true
    H.Print(what .. " stopped on an error: " .. tostring(err))
  end
end

local function install()
  if P.installed then return true end
  local f = host()
  if not f or type(f.HookScript) ~= "function" or not Craft.Available() then return false end
  P.installed = true
  f:HookScript("OnShow", function()
    -- a profession opened afresh reads its schematics afresh
    P.cache = nil
    safely("the recipe costs", P.Place)
  end)
  local sf = form()
  if sf and type(sf.Init) == "function" then
    hooksecurefunc(sf, "Init", function(_, recipeInfo) safely("the recipe costs", P.OnInit, recipeInfo) end)
  end
  if f:IsShown() then safely("the recipe costs", P.Place) end
  return true
end
P.Install = install

H.Events:On("LOGIN", install)
H.RegisterEvent("ADDON_LOADED", function(name)
  if name == "Blizzard_Professions" then install() end
end)
H.RegisterEvent("TRADE_SKILL_SHOW", function()
  if not install() then
    if not P.said then
      P.said = true
      H.Print("this client's profession window is not one Hound can read; recipe costs are off")
    end
    return
  end
  if P.Visible() then P.Schedule(0) end
end)
H.RegisterEvent("TRADE_SKILL_LIST_UPDATE", function()
  if P.Visible() then P.Schedule() end
end)
H.Events:On("SCAN_DONE", function()
  if P.Visible() then P.Schedule() end
end)
