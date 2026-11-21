-- UI/Craft.lua: Hound's panel beside the profession window.
--
-- At the top, the recipe picked: its reagents in a small table of their
-- own, the units, the price of one and the total, then what the
-- materials come to, what a craft sells for less the house's cut, and
-- the profit (Craft.lua). Under it, every recipe of the profession in a
-- list of Hound's own, sorted by profit, the best first; any header
-- sorts by its column. The recipe picked is the one picked in the
-- window's own list, which Hound's list scrolls to, or a row clicked in
-- Hound's; a double-click asks the client to open that recipe in the
-- window. The panel hangs off the window's right edge, clear of
-- anything the window hangs there itself (its profession tabs); its
-- close button puts it away for every profession, and a small Hound
-- tab, or /hound craft, brings it back.
--
-- Nothing of Blizzard's is written or run (README, Taint): the window
-- is met by HookScript on its show and a secure hook on its recipe
-- form's Init, which hands over the recipe picked. Hound's frames are
-- children of the window, so they go with it, and only read the
-- window's own field for the recipe it shows and where its pieces sit.
-- A double-click asks the client through C_TradeSkillUI, never the
-- window's code.
local ADDON, H = ...

local UI = H.UI
local Craft = H.Craft
local P = {}
UI.Craft = P

P.WIDTH = 420
P.MAX_LINES = 8    -- reagent lines at most; a recipe with more folds the rest into one
P.DELAY = 0.5      -- seconds the window's updates are gathered for before a rebuild
-- How far right of the window's edge the panel sits when nothing hanging
-- off the edge can be measured: clear of the profession tabs as the
-- live client draws them. Whatever is measured further out wins.
P.EDGE_GAP = 56
P.ROW = 16         -- a reagent or total line's height

local C = Craft.COLORS
local money = H.MoneyExact

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

local function upper(text) return (string.gsub(text, "^%l", string.upper)) end

------------------------------------------------------------------------
-- Where the panel goes: right of the window's edge and of anything the
-- window hangs off it, read from where its pieces sit two levels down.
-- Only frames that start at the edge count, and not past a tab's width
-- or two, so nothing far off moves the panel across the screen.
------------------------------------------------------------------------
function P.Gap()
  local f = host()
  local gap = P.EDGE_GAP
  if not f or type(f.GetRight) ~= "function" or type(f.GetChildren) ~= "function" then return gap end
  local fs = f:GetEffectiveScale() or 1
  local right = f:GetRight()
  if type(right) ~= "number" or fs <= 0 then return gap end
  right = right * fs
  local far = right
  local function look(frame, depth)
    for _, c in ipairs({ frame:GetChildren() }) do
      if c ~= P.frame and c ~= P.tab and type(c.IsShown) == "function" and c:IsShown() then
        local l, r = c:GetLeft(), c:GetRight()
        local cs = c:GetEffectiveScale() or 1
        if type(l) == "number" and type(r) == "number" then
          l, r = l * cs, r * cs
          if l >= right - 30 * fs and r > far and r <= right + 160 * fs then far = r end
        end
        if depth < 2 then look(c, depth + 1) end
      end
    end
  end
  look(f, 1)
  return math.max(gap, math.ceil((far - right) / fs) + 4)
end

------------------------------------------------------------------------
-- The recipe picked
------------------------------------------------------------------------

-- The reagent rows for a recipe: name, each and total, up to n of them,
-- the last folding in any past it.
function P.ReagentRows(r, n)
  local out = {}
  local count = #r.lines
  for i, e in ipairs(r.lines) do
    if i == n and count > n then
      local rest, any = 0, false
      for j = i, count do
        if r.lines[j].total then rest, any = rest + r.lines[j].total, true end
      end
      table.insert(out, { name = string.format("and %d more", count - i + 1), each = "", total = any and money(rest) or "no price" })
      break
    end
    table.insert(out, {
      itemID = e.itemID, src = e.src,
      name = string.format("%d %s", e.qty, e.name) .. Craft.ListedNote(e),
      each = Craft.EachText(e, money) or "",
      total = e.total and money(e.total) or "no price",
      priced = e.total ~= nil,
    })
  end
  return out
end

local function paint(fs, text, c)
  fs:SetText(text or "")
  if c then fs:SetTextColor(c[1], c[2], c[3]) end
end

function P.RenderPicked()
  local f = P.frame
  if not f then return end
  local r = P.picked
  local h = f.head
  if not r then
    h.icon:Hide()
    paint(h.name, "Pick a recipe to price it", C.none)
    paint(h.made, "")
  else
    h.icon:SetTexture(r.icon or (r.itemID and H.ItemIcon(r.itemID)) or 134400)
    h.icon:Show()
    paint(h.name, r.name, { 1, 0.82, 0 })
    paint(h.made, Craft.MadeText(r), C.none)
  end
  local rows = r and P.ReagentRows(r, P.lines) or {}
  for i, row in ipairs(f.reagents) do
    local e = rows[i]
    row.itemID, row.src = e and e.itemID, e and e.src
    paint(row.name, e and e.name, { 0.85, 0.85, 0.85 })
    paint(row.each, e and e.each, { 0.65, 0.65, 0.65 })
    paint(row.total, e and e.total, e and e.priced and C.price or C.none)
  end
  local sums = r and Craft.SummaryLines(r, money) or {}
  for i, t in ipairs(f.totals) do
    local l = sums[i]
    paint(t.left, l and upper(l[1]), { 0.8, 0.8, 0.8 })
    paint(t.right, l and l[2], l and l[3])
  end
  if r then f.rule:Show() else f.rule:Hide() end
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

-- Scrolls Hound's list to a recipe when it is off the rows shown.
function P.Reveal(recipeID)
  local t = P.table
  if not t then return end
  for i, r in ipairs(t.view) do
    if r.recipeID == recipeID then
      local n = t:NumVisible()
      if i > t.offset and i <= t.offset + n then return end
      local o = H.Clamp(i - 1 - math.floor(n / 2), 0, math.max(0, #t.view - n))
      t.offset = o
      t.scrollbar:SetValue(o)
      t:Refresh(true)
      return
    end
  end
end

-- The window's own pick, as its recipe form was handed it.
function P.OnInit(recipeInfo)
  local id = type(recipeInfo) == "table" and recipeInfo.recipeID or nil
  if not id then return end
  if P.frame then
    P.Pick(id)
    P.Reveal(id)
  else
    P.recipeID = id
  end
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
  { key = "name", title = "Recipe", width = 176, kind = "item",
    value = function(r) return r.name end,
    text = function(r) return r.learned and r.name or ("|cff808080" .. r.name .. "|r") end },
  { key = "cost", title = "Cost", width = 66, kind = "money", align = "RIGHT", value = function(r) return r.cost end },
  { key = "sells", title = "Sells", width = 66, kind = "money", align = "RIGHT", desc = true, value = function(r) return r.sells end },
  { key = "profit", title = "Profit", width = 70, kind = "money", align = "RIGHT", desc = true,
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
  if not H.Store.LastScan() then return text .. "; no scan yet" end
  return text
end

-- The reagent lines the profession needs: as many as its longest
-- recipe takes, so the block is no taller than it has to be and stays
-- put from one recipe to the next.
function P.LinesFor(rows)
  local n = 1
  for _, r in ipairs(rows or {}) do n = math.max(n, #r.reagents) end
  return math.min(n, P.MAX_LINES)
end

-- Reads every recipe of the profession again, and the one picked.
function P.Rebuild()
  if not P.frame then return end
  Craft.unnamed = false
  P.cache = P.cache or {}
  P.rows = Craft.ReadAll(P.cache)
  for _, r in ipairs(P.rows) do r.key = r.recipeID end
  local n = P.LinesFor(P.rows)
  if n ~= P.lines then P.Layout(n) end
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

-- A line of three: a name, the price of one and the total. A reagent's
-- is a button of Hound's own, so hovering it shows the reagent.
local EACH_W, TOTAL_W = 84, 88
local function threeColumns(parent, font)
  local row = {}
  row.name = UI.Text(parent, font, "", "LEFT")
  row.each = UI.Text(parent, font, "", "RIGHT")
  row.total = UI.Text(parent, font, "", "RIGHT")
  row.total:SetWidth(TOTAL_W)
  row.each:SetWidth(EACH_W)
  return row
end

local function reagentTooltip(owner, row)
  if not row.itemID or not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(row.itemID)
  if row.src == "vendor" then
    GameTooltip:AddLine("Hound prices it at a vendor's price, under the house's", 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

local function buildReagentRow(f)
  local b = CreateFrame("Button", nil, f)
  b:SetHeight(P.ROW)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  local row = threeColumns(b, "GameFontHighlightSmall")
  row.button = b
  row.total:SetPoint("RIGHT", b, "RIGHT", -2, 0)
  row.each:SetPoint("RIGHT", row.total, "LEFT", -6, 0)
  row.name:SetPoint("LEFT", b, "LEFT", 8, 0)
  row.name:SetPoint("RIGHT", row.each, "LEFT", -6, 0)
  b:SetScript("OnEnter", function(self) reagentTooltip(self, row) end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return row
end

local function buildTotalRow(f, font)
  local t = {}
  t.left = UI.Text(f, font, "", "LEFT")
  t.right = UI.Text(f, font, "", "RIGHT")
  t.right:SetWidth(180)
  return t
end

-- Lays the panel out under the reagent block, n lines tall.
function P.Layout(n)
  local f = P.frame
  P.lines = n
  local y = f.reagentTop
  for i, row in ipairs(f.reagents) do
    local b = row.button
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - (i - 1) * P.ROW)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y - (i - 1) * P.ROW)
    if i <= n then b:Show() else b:Hide() end
  end
  y = y - n * P.ROW - 4
  f.rule:ClearAllPoints()
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 22, y)
  f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y)
  y = y - 4
  for i, t in ipairs(f.totals) do
    local h = i == #f.totals and 18 or P.ROW
    t.left:ClearAllPoints()
    t.left:SetPoint("TOPLEFT", f, "TOPLEFT", 22, y - 1)
    t.left:SetPoint("RIGHT", t.right, "LEFT", -6, 0)
    t.right:ClearAllPoints()
    t.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y - 1)
    y = y - h
  end
  y = y - 6
  f.divider:ClearAllPoints()
  f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
  f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y)
  f.unlearned:ClearAllPoints()
  f.unlearned:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - 6)
  f.status:ClearAllPoints()
  f.status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y - 10)
  f.status:SetPoint("LEFT", f.unlearned.label, "RIGHT", 8, 0)
  P.table:ClearAllPoints()
  P.table:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - 32)
  P.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
  P.table:Layout()
end

-- Puts the panel, or the tab, right of the window and what hangs off it.
local function anchor(frame, parent, gap, down)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", gap, down or 0)
  if not down then frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", gap, 0) end
end

local function build(parent)
  local f = UI.Create("Frame", "AuctionHoundCraft", parent, "BackdropTemplate")
  f:SetWidth(P.WIDTH)
  f:EnableMouse(true)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  f.title = UI.Text(f, "GameFontNormal", "Hound: recipe costs")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
  -- the client's own close button, its click Hound's alone: the
  -- template's would hand the panel to the window manager
  f.close = UI.Create("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(28, 28)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", function() P.SetShown(false) end)

  -- the recipe: its icon and name, and what it makes
  local h = {}
  h.icon = f:CreateTexture(nil, "ARTWORK")
  h.icon:SetSize(20, 20)
  h.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -40)
  h.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  h.made = UI.Text(f, "GameFontHighlightSmall", "", "RIGHT")
  h.made:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -45)
  h.name = UI.Text(f, "GameFontNormal", "", "LEFT")
  h.name:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
  h.name:SetPoint("RIGHT", h.made, "LEFT", -8, 0)
  f.head = h

  -- the reagents' column titles, then a line for each
  local cols = threeColumns(f, "GameFontDisableSmall")
  cols.total:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -66)
  cols.each:SetPoint("RIGHT", cols.total, "LEFT", -6, 0)
  cols.name:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -66)
  cols.name:SetText("Reagents")
  cols.each:SetText("each")
  cols.total:SetText("total")
  f.columns = cols
  f.reagentTop = -80
  f.reagents = {}
  for i = 1, P.MAX_LINES do f.reagents[i] = buildReagentRow(f) end

  -- the sums under a rule: materials, sale, profit
  f.rule = UI.Divider(f)
  f.totals = {
    buildTotalRow(f, "GameFontHighlightSmall"),
    buildTotalRow(f, "GameFontHighlightSmall"),
    buildTotalRow(f, "GameFontHighlight"),
  }

  f.divider = UI.Divider(f)
  f.unlearned = UI.CheckButton(f, "Unlearned too", function(on)
    H.Settings().craftUnlearned = on and true or false
    P.table:Refresh()
    f.status:SetText(P.StatusText())
  end)
  f.unlearned:SetChecked(H.Settings().craftUnlearned and true or false)
  f.status = UI.Text(f, "GameFontHighlightSmall", "", "RIGHT")

  P.table = UI.CreateTable(f, COLUMNS, {
    sortKey = "profit", sortDesc = true, rowHeight = 16,
    onSelect = function(r) P.Pick(r.recipeID) end,
    onDouble = function(r) P.Open(r.recipeID) end,
    tooltip = rowTooltip,
  })
  P.table:Filter(passes)
  P.frame = f
  P.Layout(3)
  return f
end

local function buildTab(parent)
  local b = UI.Button(parent, "Hound", 64, 22, function() P.SetShown(true) end)
  return b
end

-- Shows the panel or the tab, as the setting says, while the window is up.
function P.Place()
  local f = host()
  if not f or not f:IsShown() then return end
  local on = H.Settings().craftPanel and true or false
  if on and not P.frame then
    build(f)
    if not P.recipeID then
      local sf = form()
      local info = sf and sf.currentRecipeInfo
      if type(info) == "table" then P.recipeID = info.recipeID end
    end
  end
  if not on and not P.tab then P.tab = buildTab(f) end
  local gap = P.Gap()
  P.gap = gap
  if P.frame then
    anchor(P.frame, f, gap)
    if on then P.frame:Show() else P.frame:Hide() end
  end
  if P.tab then
    anchor(P.tab, f, gap, -40)
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
