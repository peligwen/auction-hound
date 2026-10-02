-- UI/Frame.lua: the panel, its five views, the AH tab and the window.
local ADDON, H = ...

local UI = H.UI

-- Where the panel sits inside the Blizzard auction house frame. The
-- frame's portrait (the auctioneer) hangs 62px down its left edge, so
-- the row of view buttons starts to the right of it; the body below is
-- clear of it already.
UI.AH_INSETS = { left = 8, top = 30, right = 8, bottom = 34, header = 52 }
UI.WINDOW_SIZE = { 780, 500 }
-- The panel's body starts this far under its top: the row of view
-- buttons and the divider. In the house that is also where the body
-- comes clear of the portrait.
UI.BODY_TOP = 32
-- How many frame levels the panel's seat sits above the house frame.
-- The frame's own mode stays shown underneath (see the tab section),
-- and its deepest list cells are a handful of levels up.
UI.AH_LEVELS = 20

local panel, window
local views = {}
local current
local statusText

------------------------------------------------------------------------
-- Status line
------------------------------------------------------------------------
local function statusLine()
  local S = H.Scan
  local parts = {}
  if S.state == "replicating" then
    table.insert(parts, "waiting for the full listing")
  elseif S.state == "processing" then
    table.insert(parts, string.format("processing %d / %d", S.index or 0, S.total or 0))
  elseif H.Fan and H.Fan.pending then
    table.insert(parts, "posting")
  else
    local last = H.Store.LastScan()
    if last then
      table.insert(parts, "last full scan " .. H.Ago(H.Now() - last.t))
    else
      table.insert(parts, "no full scan yet")
    end
    if H.atAH then
      local wait = S.FullScanWait()
      if wait > 0 then
        table.insert(parts, string.format("next in %d:%02d", math.floor(wait / 60), wait % 60))
      else
        table.insert(parts, "full scan ready")
      end
    end
  end
  table.insert(parts, string.format("%d items", H.Store.Count()))
  return table.concat(parts, "  |  ")
end

function UI.UpdateStatus()
  if statusText then statusText:SetText(statusLine()) end
  if UI.autoScanBox then UI.autoScanBox:SetChecked(H.Settings().autoScan and true or false) end
  if UI.estimatesBox then UI.estimatesBox:SetChecked(H.Settings().estimates and true or false) end
end

------------------------------------------------------------------------
-- Markets view
------------------------------------------------------------------------
local function buildMarketsView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()

  local scanBtn = UI.Button(v, "Full Scan", 90, 22, function() H.Scan.StartFull() end)
  scanBtn:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)

  local filterBox = UI.EditBox(v, 180, function(text) v.filterText = string.lower(text or "") v:ApplyFilter() end)
  filterBox:SetPoint("LEFT", scanBtn, "RIGHT", 12, 0)
  local filterLabel = UI.Text(v, "GameFontDisableSmall", "filter", "LEFT")
  filterLabel:SetPoint("LEFT", filterBox, "RIGHT", 6, 0)

  local minDays = UI.CheckButton(v, "3+ days only", function(checked) v.minDays = checked and 3 or 0 v:ApplyFilter() end)
  minDays:SetPoint("LEFT", filterLabel, "RIGHT", 14, 0)

  local refreshBtn = UI.Button(v, "Refresh", 70, 22, function() v:Rebuild() end)
  refreshBtn:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, 0)

  local cols = {
    { key = "item", title = "Item", width = 200, kind = "item", value = function(r) return r.name end },
    { key = "market", title = "Market", width = 72, align = "RIGHT", kind = "money", value = function(r) return r.st.market end, desc = true },
    { key = "min", title = "Floor", width = 72, align = "RIGHT", kind = "money", value = function(r) return r.st.min end, desc = true },
    { key = "qty", title = "Listed", width = 54, align = "RIGHT", kind = "int", value = function(r) return r.st.qty end, desc = true },
    { key = "moved", title = "~/day", width = 50, align = "RIGHT", kind = "int", value = function(r) return r.st.moved end, desc = true },
    { key = "trend", title = "Trend", width = 54, align = "RIGHT", kind = "spct", value = function(r) return r.st.trend end, desc = true,
      color = function(r, raw) if not raw then return 0.6, 0.6, 0.6 end if raw > 0.05 then return 0.4, 0.9, 0.4 end if raw < -0.05 then return 0.9, 0.4, 0.4 end return 1, 1, 1 end },
    { key = "stab", title = "Swing", width = 50, align = "RIGHT", kind = "pct", value = function(r) return r.st.stab end },
    { key = "days", title = "Days", width = 42, align = "RIGHT", kind = "int", value = function(r) return r.st.days end, desc = true },
    { key = "spark", title = "30 days", width = 100, kind = "spark", points = 30, value = function(r) return r.spark end },
  }

  local tbl = UI.CreateTable(v, cols, {
    sortKey = "market", sortDesc = true,
    onSelect = function(row) UI.ShowItem(row.key) end,
    tooltip = function(row, frame)
      if not GameTooltip then return end
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(row.itemID)
      GameTooltip:Show()
    end,
  })
  tbl:SetPoint("TOPLEFT", scanBtn, "BOTTOMLEFT", 0, -6)
  tbl:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)
  v.table = tbl
  v.minDays = 0
  v.filterText = ""

  function v:ApplyFilter()
    tbl:Filter(function(row)
      if self.minDays > 0 and row.st.days < self.minDays then return false end
      if self.filterText ~= "" and not string.find(string.lower(row.name), self.filterText, 1, true) then return false end
      return true
    end)
  end

  function v:Rebuild()
    local rows = {}
    local now = H.Now()
    for _, key in ipairs(H.Store.Keys()) do
      local rec = H.Store.Get(key)
      if rec then
        local st = H.Market.Stats(rec, now)
        if st.market then
          local itemID = H.ItemIDFromKey(key)
          local spark = {}
          for i, p in ipairs(H.Market.DailySeries(rec, 30, now)) do spark[i] = p.mv end
          table.insert(rows, { key = key, itemID = itemID, name = H.ItemName(itemID), st = st, spark = spark })
        end
      end
    end
    tbl:SetData(rows)
    self:ApplyFilter()
    self.builtAt = now
  end

  v:SetScript("OnShow", function(self)
    if not self.builtAt or H.Now() - self.builtAt > 30 then self:Rebuild() end
  end)
  H.Events:On("SCAN_DONE", function() if v:IsShown() then v:Rebuild() end end)

  return v
end

------------------------------------------------------------------------
-- Item view
------------------------------------------------------------------------
local function buildItemView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()

  local icon = v:CreateTexture(nil, "ARTWORK")
  icon:SetSize(28, 28)
  icon:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local name = UI.Text(v, "GameFontNormal", "", "LEFT")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
  local keyText = UI.Text(v, "GameFontDisableSmall", "", "LEFT")
  keyText:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)

  local back = UI.Button(v, "Markets", 70, 22, function() UI.ShowView("markets") end)
  back:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, 0)
  local fanBtn = UI.Button(v, "Fan", 50, 22, function() if v.key then UI.ShowFan(v.key) end end)
  fanBtn:SetPoint("RIGHT", back, "LEFT", -4, 0)

  -- find box: part of a name, an item id, or a link (shift-click one in)
  local find = UI.EditBox(v, 170)
  find:SetPoint("RIGHT", fanBtn, "LEFT", -12, 0)
  find:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    local key = UI.FindKey(text)
    if key then
      self:SetText("")
      self:ClearFocus()
      UI.ShowItem(key)
    else
      v.err = "nothing scanned matches \"" .. tostring(text) .. "\""
      v:Refresh()
    end
  end)
  local findLabel = UI.Text(v, "GameFontDisableSmall", "find", "LEFT")
  findLabel:SetPoint("RIGHT", find, "LEFT", -8, 0)
  if type(ChatEdit_InsertLink) == "function" and hooksecurefunc then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      if link and find:HasFocus() then find:SetText(link) end
    end)
  end
  v.find = find

  local statsLeft = UI.Text(v, "GameFontHighlightSmall", "", "LEFT")
  statsLeft:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
  statsLeft:SetWidth(330)
  statsLeft:SetHeight(58)
  statsLeft:SetWordWrap(true)
  local statsRight = UI.Text(v, "GameFontHighlightSmall", "", "LEFT")
  statsRight:SetPoint("TOPLEFT", statsLeft, "TOPRIGHT", 10, 0)
  statsRight:SetPoint("RIGHT", v, "RIGHT", 0, 0)
  statsRight:SetHeight(58)
  statsRight:SetWordWrap(true)

  local graph = UI.CreateBarGraph(v, { title = "daily market value, floor inside, listed units below" })
  graph:SetPoint("TOPLEFT", statsLeft, "BOTTOMLEFT", 0, -6)
  graph:SetPoint("RIGHT", v, "RIGHT", 0, 0)
  graph:SetHeight(150)

  local connTitle = UI.Text(v, "GameFontNormalSmall", "Connections", "LEFT")
  connTitle:SetPoint("TOPLEFT", graph, "BOTTOMLEFT", 0, -8)

  local cols = {
    { key = "recipe", title = "Recipe", width = 170, value = function(r) return r.label end },
    { key = "dir", title = "", width = 74, value = function(r) return r.dir end,
      color = function() return 0.7, 0.7, 0.7 end },
    { key = "inputs", title = "Inputs", width = 80, align = "RIGHT", kind = "money", value = function(r) return r.e.inputCost end },
    { key = "output", title = "Output", width = 80, align = "RIGHT", kind = "money", value = function(r) return r.e.revenue end },
    { key = "spread", title = "Spread", width = 80, align = "RIGHT", kind = "money", value = function(r) return r.e.spread end, desc = true,
      color = function(r, raw) if not raw then return 0.6, 0.6, 0.6 end if raw > 0 then return 0.4, 0.9, 0.4 end return 0.9, 0.4, 0.4 end },
    { key = "gph", title = "g/h", width = 60, align = "RIGHT", value = function(r) return r.e.perHour end,
      text = function(r, raw) if not raw then return "-" end return string.format("%d", math.floor(raw / 10000)) end },
    { key = "skill", title = "Skill", width = 50, align = "RIGHT", value = function(r) return r.e.recipe.skill end,
      text = function(r, raw) return string.format("%s %d", string.sub(r.e.recipe.prof, 1, 4), raw or 0) end },
  }
  local conn = UI.CreateTable(v, cols, {
    sortKey = "spread", sortDesc = true,
    onDouble = function(row) UI.ShowItem(tostring(row.otherID)) end,
    tooltip = function(row, frame)
      if not GameTooltip then return end
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:AddLine(row.label)
      for _, part in ipairs(row.e.parts) do
        GameTooltip:AddDoubleLine(string.format("%d x %s", part.qty, H.ItemName(part.id)),
          part.price and (H.Money(part.price * part.qty) .. " (" .. (part.src or "?") .. ")") or "unpriced", 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddDoubleLine(string.format("%d x %s", row.e.recipe.outQty, H.ItemName(row.e.recipe.out)),
        row.e.outMV and H.Money(row.e.outMV * row.e.recipe.outQty) or "unpriced", 1, 0.82, 0, 1, 1, 1)
      if row.e.laborCost then
        GameTooltip:AddDoubleLine("labor per craft", H.Money(row.e.laborCost), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
      end
      if row.e.recipe.note then GameTooltip:AddLine(row.e.recipe.note, 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end,
  })
  conn:SetPoint("TOPLEFT", connTitle, "BOTTOMLEFT", 0, -2)
  conn:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)

  -- With no item chosen the view says what it is for.
  function v:Refresh()
    if self.key then self:Show_(self.key) return end
    icon:SetTexture(134400)
    name:SetText("Item")
    keyText:SetText(self.err or "one item's history, anchors and connections  |  " .. H.marketKey)
    self.err = nil
    statsLeft:SetText("Pick an item: double-click a row in Markets, pick one in the Fan tab's bag list, or type part of a name, an item id or a link in the find box and press Enter.")
    statsRight:SetText("Shows market value, floor, 30 day mean, trend, units moved, the daily graph, vendor and crafting anchors, what it is made from and what it makes, and what you sold it for.")
    graph:SetSeries({})
    conn:SetData({})
  end

  function v:Show_(key)
    self.key = key
    local itemID = H.ItemIDFromKey(key)
    icon:SetTexture(H.ItemIcon(itemID) or 134400)
    name:SetText(H.ColoredName(itemID))
    keyText:SetText((self.err and (self.err .. "  |  ") or "") .. "key " .. key .. "  |  " .. H.marketKey)
    self.err = nil
    local rec = H.Store.Get(key)
    local st = rec and H.Market.Stats(rec) or nil
    if st and st.market then
      local demand = H.Market.ClearedLine(st) or string.format("moved ~%s a day", st.moved and tostring(H.Round(st.moved)) or "?")
      statsLeft:SetText(string.format("market %s   floor %s   30 day %s\nlisted %d   %s   trend %s\nswing %s   %d scans over %d days   last %s",
        H.Money(st.market), H.Money(st.min or 0), H.Money(st.hist or 0),
        st.qty or 0, demand, H.Pct(st.trend, true),
        H.Pct(st.stab), st.samples, st.days, H.Ago(st.age)))
      graph:SetSeries(UI.SeriesFor(rec))
    else
      statsLeft:SetText("no history for this item yet")
      graph:SetSeries({})
    end
    local right = {}
    local vendor = H.Priors.VendorSell(itemID)
    if vendor then table.insert(right, "vendor " .. H.Money(vendor)) end
    local cost, recipe = H.Priors.CraftCost(itemID)
    if cost then table.insert(right, string.format("costs %s to make (%s)", H.Money(cost), recipe.name)) end
    local makes, r2 = H.Priors.MakesValue(itemID)
    if makes then table.insert(right, string.format("worth %s as an input (%s)", H.Money(makes), r2.name)) end
    if #right == 0 then table.insert(right, "no vendor or conversion anchors") end
    local cl = H.Market.Clearing(H.Store.Posts(key))
    if cl then table.insert(right, "yours: " .. H.Fan.ClearingLine(cl)) end
    statsRight:SetText(table.concat(right, "\n"))

    local rows = {}
    local c = H.Priors.Connections(itemID)
    for _, e in ipairs(c.madeFrom) do
      local other = e.recipe.inputs[1] and e.recipe.inputs[1][1]
      table.insert(rows, { key = "from" .. e.recipe.out .. "_" .. tostring(other), label = e.recipe.name, dir = "made from", e = e, otherID = other })
    end
    for _, e in ipairs(c.makes) do
      table.insert(rows, { key = "to" .. e.recipe.out, label = e.recipe.name, dir = "makes", e = e, otherID = e.recipe.out })
    end
    conn:SetData(rows)
  end

  return v
end

-- The history key for what a person typed: a link, an item id, or part
-- of a name among the items scanned in this market. Returns nil when
-- nothing matches.
function UI.FindKey(text)
  text = string.match(tostring(text or ""), "^%s*(.-)%s*$")
  if text == "" then return nil end
  if string.find(text, "|Hitem:", 1, true) then return H.KeyFromLink(text) end
  local id = tonumber(text)
  if id then return H.KeyForItemID(id) or tostring(id) end
  local q = string.lower(text)
  local best, bestLen
  for _, key in ipairs(H.Store.Keys()) do
    local n = string.lower(H.ItemName(H.ItemIDFromKey(key)))
    if n == q then return key end
    if string.find(n, q, 1, true) and (not bestLen or #n < bestLen) then best, bestLen = key, #n end
  end
  if best then return best end
  if H.db and H.db.names then
    for itemID, n in pairs(H.db.names) do
      if string.lower(n) == q then return H.KeyForItemID(itemID) or tostring(itemID) end
    end
  end
  return nil
end

function UI.SeriesFor(rec)
  local out = {}
  for _, p in ipairs(H.Market.DailySeries(rec, 30)) do
    table.insert(out, { label = H.DayLabel(p.day), y = p.mv, y2 = p.min, vol = p.qty, moved = p.moved, s = p.s })
  end
  return out
end

------------------------------------------------------------------------
-- Fan view: post one item as a ladder of batches and watch what sells
------------------------------------------------------------------------
local function statusColor(text)
  if not text then return 0.6, 0.6, 0.6 end
  if string.find(text, "sold", 1, true) then return 0.4, 0.9, 0.4 end
  if string.find(text, "expired", 1, true) or text == "failed" then return 0.9, 0.4, 0.4 end
  if text == "active" or text == "posting" then return 1, 1, 1 end
  if text == "bought" then return 0.45, 0.85, 1.0 end
  return 0.6, 0.6, 0.6
end

local function buildFanView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  local Fan = H.Fan

  local function itemTooltip(row, frame)
    if not GameTooltip then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:Show()
  end

  -- left: what is in the bags
  local bagsTitle = UI.Text(v, "GameFontNormalSmall", "In bags", "LEFT")
  bagsTitle:SetPoint("TOPLEFT", v, "TOPLEFT", 4, -5)
  local bagCols = {
    { key = "item", title = "Item", width = 156, kind = "item", value = function(r) return r.name end },
    { key = "count", title = "Units", width = 42, align = "RIGHT", kind = "int", value = function(r) return r.count end, desc = true },
    { key = "anchor", title = "Center", width = 64, align = "RIGHT", kind = "money", value = function(r) return r.anchor end, desc = true,
      color = function(r) if r.anchorSrc == "sold" then return 0.4, 0.9, 0.4 end if r.anchor then return 1, 1, 1 end return 0.6, 0.6, 0.6 end },
  }
  local bags = UI.CreateTable(v, bagCols, {
    sortKey = "anchor", sortDesc = true,
    onSelect = function(row) v:Select(row.key) end,
    tooltip = itemTooltip,
  })
  bags:SetPoint("TOPLEFT", bagsTitle, "BOTTOMLEFT", -4, -2)
  bags:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0)
  bags:SetWidth(262)

  -- right: the plan
  local right = CreateFrame("Frame", nil, v)
  right:SetPoint("TOPLEFT", v, "TOPLEFT", 274, 0)
  right:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)

  local icon = right:CreateTexture(nil, "ARTWORK")
  icon:SetSize(22, 22)
  icon:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local name = UI.Text(right, "GameFontNormal", "pick an item from your bags", "LEFT")
  name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  local checkBtn = UI.Button(right, "Check Sales", 90, 22, function()
    if not Fan.RefreshOwned(true) then H.Print("open the auction house to check your auctions") end
  end)
  checkBtn:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
  local sub = UI.Text(right, "GameFontDisableSmall", "", "LEFT")
  sub:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -3)
  sub:SetPoint("RIGHT", right, "RIGHT", 0, 0)

  -- controls
  local function changed() if not v.loading then v:Replan() end end
  local function field(label, width, prev, gap)
    local l = UI.Text(right, "GameFontDisableSmall", label, "LEFT")
    if prev then
      l:SetPoint("LEFT", prev, "RIGHT", gap or 10, 0)
    else
      l:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
    end
    local box = UI.EditBox(right, width, changed)
    box:SetPoint("LEFT", l, "RIGHT", 10, 0)
    box.label = l
    return box
  end
  local perBatch = field("per batch", 34)
  local step = field("step %", 34, perBatch)
  local batches = field("batches", 34, step)
  local shape = UI.CycleButton(right, 56, Fan.SHAPES, changed)
  shape:SetPoint("LEFT", batches, "RIGHT", 12, 0)
  local spread = UI.CycleButton(right, 58, Fan.SPREADS, changed)
  spread:SetPoint("LEFT", shape, "RIGHT", 4, 0)
  local duration = UI.CycleButton(right, 42, { "12h", "24h", "48h" }, changed)
  duration:SetPoint("LEFT", spread, "RIGHT", 4, 0)

  local centerLabel = UI.Text(right, "GameFontDisableSmall", "center", "LEFT")
  centerLabel:SetPoint("TOPLEFT", perBatch.label, "BOTTOMLEFT", 0, -12)
  local center = UI.EditBox(right, 90, changed)
  center:SetPoint("LEFT", centerLabel, "RIGHT", 10, 0)
  local centerHint = UI.Text(right, "GameFontDisableSmall", "", "LEFT")
  centerHint:SetPoint("LEFT", center, "RIGHT", 8, 0)
  centerHint:SetPoint("RIGHT", right, "RIGHT", 0, 0)

  -- the plan
  local planCols = {
    { key = "i", title = "#", width = 26, align = "RIGHT", value = function(r) return r.b.i end },
    { key = "unit", title = "Unit", width = 74, align = "RIGHT", kind = "money", value = function(r) return r.b.unit end,
      color = function(r) if r.b.belowVendor then return 0.9, 0.4, 0.4 end return 1, 1, 1 end },
    { key = "qty", title = "Units", width = 44, align = "RIGHT", kind = "int", value = function(r) return r.b.qty end },
    { key = "gross", title = "Gross", width = 74, align = "RIGHT", kind = "money", value = function(r) return r.b.unit * r.b.qty end },
    { key = "net", title = "Net", width = 74, align = "RIGHT", kind = "money",
      value = function(r) return H.Round(r.b.unit * r.b.qty * (1 - H.Settings().cut) - (r.b.deposit or 0)) end },
    { key = "dep", title = "Deposit", width = 62, align = "RIGHT", kind = "money", value = function(r) return r.b.deposit end },
    { key = "status", title = "Status", width = 110, value = function(r) return Fan.BatchStatus(r.b) end,
      color = function(r, raw) return statusColor(raw) end },
  }
  local planTbl = UI.CreateTable(right, planCols, { sortKey = "i" })
  v.planTbl = planTbl
  planTbl:SetPoint("TOPLEFT", centerLabel, "BOTTOMLEFT", -4, -8)
  planTbl:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  planTbl:SetHeight(18 + 7 * 16)

  local postBtn = UI.Button(right, "Post", 110, 22, function() Fan.PostNext() end)
  postBtn:SetPoint("TOPLEFT", planTbl, "BOTTOMLEFT", 0, -6)
  local resetBtn = UI.Button(right, "Reset", 56, 22, function() Fan.Reset() v:Replan() end)
  resetBtn:SetPoint("LEFT", postBtn, "RIGHT", 4, 0)
  local planInfo = UI.Text(right, "GameFontDisableSmall", "", "LEFT")
  planInfo:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
  planInfo:SetPoint("RIGHT", right, "RIGHT", 0, 0)

  -- past posts for the item
  local postsTitle = UI.Text(right, "GameFontNormalSmall", "Your posts", "LEFT")
  postsTitle:SetPoint("TOPLEFT", postBtn, "BOTTOMLEFT", 4, -8)
  local postCols = {
    { key = "t", title = "When", width = 70, value = function(r) return r.p.t end, desc = true,
      text = function(r, raw) return H.Ago(H.Now() - raw) end },
    { key = "unit", title = "Unit", width = 74, align = "RIGHT", kind = "money", value = function(r) return r.p.unit end },
    { key = "qty", title = "Units", width = 44, align = "RIGHT", kind = "int", value = function(r) return r.p.qty end },
    { key = "sold", title = "Sold", width = 44, align = "RIGHT", kind = "int", value = function(r) return r.p.sold or 0 end,
      color = function(r, raw) if raw and raw > 0 then return 0.4, 0.9, 0.4 end return 0.6, 0.6, 0.6 end },
    { key = "status", title = "Status", width = 110, value = function(r) return Fan.PostStatus(r.p) end,
      color = function(r, raw) return statusColor(raw) end },
  }
  local postsTbl = UI.CreateTable(right, postCols, { sortKey = "t", sortDesc = true })
  postsTbl:SetPoint("TOPLEFT", postsTitle, "BOTTOMLEFT", -4, -2)
  postsTbl:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)

  local function setBoxes(o)
    v.loading = true
    perBatch:SetText(tostring(o.perBatch))
    step:SetText(tostring(H.Round(o.step * 1000) / 10))
    batches:SetText(tostring(o.batches))
    shape:SetValue(o.shape)
    spread:SetValue(o.spread)
    duration:SetValue(({ "12h", "24h", "48h" })[o.duration] or "48h")
    center:SetText(o.centerText or "")
    v.loading = false
  end

  function v:RebuildBags()
    local rows = {}
    for key, e in pairs(Fan.Bags()) do
      local anchor, src = Fan.Anchor(key, e.itemID)
      table.insert(rows, { key = key, itemID = e.itemID, name = H.ItemName(e.itemID), count = e.count, anchor = anchor, anchorSrc = src })
    end
    bags:SetData(rows)
    self.bagsAt = H.Now()
  end

  function v:Select(key)
    if Fan.InProgress() and Fan.plan.key ~= key then
      self.err = "a fan is in progress; reset it before planning another"
      self:Refresh()
      return
    end
    self.key = key
    local S = H.Settings()
    setBoxes({ perBatch = S.fanPerBatch, step = S.fanStep, batches = S.fanBatches, shape = S.fanShape, spread = S.fanSpread, duration = S.postDuration })
    self:Replan()
  end

  function v:Replan()
    if not self.key then self:Refresh() return end
    if Fan.InProgress() then
      self.err = "a fan is in progress; reset it to change the plan"
      self:Refresh()
      return
    end
    local o = {
      key = self.key,
      perBatch = tonumber(perBatch:GetText()),
      batches = tonumber(batches:GetText()),
      shape = shape:GetValue(),
      spread = spread:GetValue(),
      duration = ({ ["12h"] = 1, ["24h"] = 2, ["48h"] = 3 })[duration:GetValue()],
      center = H.ParseMoney(center:GetText()),
    }
    local stepPct = tonumber(step:GetText())
    if stepPct then o.step = stepPct / 100 end
    local plan, err = Fan.Setup(o)
    self.err = err
    self:Refresh()
  end

  function v:Refresh()
    local plan = Fan.plan
    if plan and plan.key ~= self.key then
      -- planned elsewhere, for example from chat: show it
      self.key = plan.key
      setBoxes({ perBatch = plan.perBatch, step = plan.step, batches = plan.requested, shape = plan.shape, spread = plan.spread,
        duration = plan.duration, centerText = plan.centerSrc == "set" and H.PlainMoney(plan.center) or "" })
    end
    if not self.key then
      icon:SetTexture(134400)
      name:SetText("pick an item from your bags")
      sub:SetText("")
      centerHint:SetText("")
      planTbl:SetData({})
      postsTbl:SetData({})
      postBtn:SetText("Post")
      planInfo:SetText(self.err or "")
      return
    end
    local itemID = H.ItemIDFromKey(self.key)
    icon:SetTexture(H.ItemIcon(itemID) or 134400)
    name:SetText(H.ColoredName(itemID))
    local count = Fan.BagCount(self.key)
    local cl = H.Market.Clearing(H.Store.Posts(self.key))
    local anchor, src = Fan.Anchor(self.key, itemID)
    sub:SetText(string.format("%d in bags  |  %s  |  center %s (%s)", count, Fan.ClearingLine(cl),
      anchor and H.Money(anchor) or "-", src))
    if plan and plan.key == self.key then
      centerHint:SetText(string.format("%s from %s  |  %s to %s  |  %d units, %s gross, %s net%s",
        H.Money(plan.center), plan.centerSrc, H.Money(plan.low or 0), H.Money(plan.high or 0),
        plan.units, H.Money(plan.gross), H.Money(plan.net), plan.short and "  |  short on units" or ""))
      local rows = {}
      for i, b in ipairs(plan.batches) do table.insert(rows, { key = "b" .. i, b = b }) end
      planTbl:SetData(rows)
      local n = #plan.batches
      local nxt = Fan.NextIndex()
      if Fan.pending then
        postBtn:SetText("Posting...")
      elseif nxt <= n then
        postBtn:SetText(string.format("Post %d / %d", nxt, n))
      else
        postBtn:SetText(n > 0 and "Fan complete" or "Nothing to post")
      end
    else
      centerHint:SetText("")
      planTbl:SetData({})
      postBtn:SetText("Post")
    end
    local prows = {}
    for _, p in ipairs(H.Store.Posts(self.key)) do table.insert(prows, { key = "p" .. tostring(p.id), p = p }) end
    postsTbl:SetData(prows)
    planInfo:SetText(self.err or (H.atAH and "" or "open the auction house to post"))
  end

  v:SetScript("OnShow", function(self)
    if not self.bagsAt or H.Now() - self.bagsAt > 5 then self:RebuildBags() end
    self:Refresh()
  end)
  H.Events:On("FAN_UPDATED", function() if v:IsShown() then v:Refresh() end end)
  H.Events:On("AH_OPENED", function() if v:IsShown() then v:Refresh() end end)
  H.Events:On("AH_CLOSED", function() if v:IsShown() then v:Refresh() end end)
  H.RegisterEvent("BAG_UPDATE_DELAYED", function() if v:IsShown() then v:RebuildBags() v:Refresh() end end)

  return v
end

------------------------------------------------------------------------
-- History view: every auction of yours the addon has seen, fan batches
-- and Blizzard posts alike, with what became of each.
------------------------------------------------------------------------
local HISTORY_FILTERS = { "All", "Active", "Sold", "Bought", "Expired", "Cancelled" }

local function historyMatches(p, f)
  if f == "All" then return true end
  if f == "Active" then return p.status == "active" or p.status == "pending" end
  if f == "Sold" then return p.status == "sold" or (p.sold or 0) > 0 end
  if f == "Bought" then return p.status == "bought" end
  if f == "Expired" then return p.status == "expired" end
  if f == "Cancelled" then return p.status == "cancelled" end
  return true
end

local function buildHistoryView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()

  local filter = UI.CycleButton(v, 90, HISTORY_FILTERS, function() v:Refresh() end)
  filter:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  v.filter = filter
  local refreshBtn = UI.Button(v, "Refresh", 70, 22, function()
    if not H.Fan.RefreshOwned(true) then H.Print("open the auction house to check your auctions") end
  end)
  refreshBtn:SetPoint("LEFT", filter, "RIGHT", 6, 0)
  local summary = UI.Text(v, "GameFontDisableSmall", "", "LEFT")
  summary:SetPoint("LEFT", refreshBtn, "RIGHT", 12, 0)
  summary:SetPoint("RIGHT", v, "RIGHT", -4, 0)
  v.summary = summary

  local cols = {
    { key = "t", title = "When", width = 70, value = function(r) return r.p.t end, desc = true,
      text = function(r, raw) return H.Ago(H.Now() - raw) end },
    { key = "item", title = "Item", width = 190, kind = "item", value = function(r) return r.name end },
    { key = "qty", title = "Units", width = 46, align = "RIGHT", kind = "int", value = function(r) return r.p.qty end },
    { key = "unit", title = "Unit", width = 74, align = "RIGHT", kind = "money", value = function(r) return r.p.unit end },
    { key = "total", title = "Total", width = 84, align = "RIGHT", kind = "money", value = function(r) return r.p.total or (r.p.unit or 0) * (r.p.qty or 0) end, desc = true },
    { key = "dep", title = "Deposit", width = 62, align = "RIGHT", kind = "money", value = function(r) return r.p.deposit end },
    { key = "sold", title = "Sold", width = 44, align = "RIGHT", kind = "int", value = function(r) if r.p.status == "bought" then return nil end return r.p.sold or 0 end,
      color = function(r, raw) if raw and raw > 0 then return 0.4, 0.9, 0.4 end return 0.6, 0.6, 0.6 end },
    { key = "status", title = "Status", width = 120, value = function(r) return H.Fan.PostStatus(r.p) end,
      color = function(r, raw) return statusColor(raw) end },
  }
  local tbl = UI.CreateTable(v, cols, {
    sortKey = "t", sortDesc = true,
    onDouble = function(row) UI.ShowItem(row.itemKey) end,
    tooltip = function(row, frame)
      if not GameTooltip then return end
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(row.itemID)
      GameTooltip:Show()
    end,
  })
  tbl:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", 0, -6)
  tbl:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)
  v.table = tbl

  -- your auctions and your purchases, one table: a purchase is a row
  -- with the status "bought", what you paid in Unit and Total
  function v:Refresh()
    local posts = H.Store.Posts() or {}
    local buys = H.Store.Buys() or {}
    local rows = {}
    local f = filter:GetValue()
    for _, p in ipairs(posts) do
      if historyMatches(p, f) then
        table.insert(rows, {
          key = "p" .. tostring(p.id), itemKey = p.key, itemID = p.itemID,
          name = p.name or H.ItemName(p.itemID), p = p,
        })
      end
    end
    for _, b in ipairs(buys) do
      if historyMatches(b, f) then
        table.insert(rows, {
          key = "b" .. tostring(b.id), itemKey = b.key, itemID = b.itemID,
          name = b.name or H.ItemName(b.itemID), p = b,
        })
      end
    end
    tbl:SetData(rows)
    summary:SetText(H.Fan.SummaryLine(H.Fan.PostSummary(posts), H.Buy.Summary(buys)))
  end

  H.Events:On("FAN_UPDATED", function() if v:IsShown() then v:Refresh() end end)
  H.Events:On("BUY_RECORDED", function() if v:IsShown() then v:Refresh() end end)
  H.Events:On("AH_OPENED", function() if v:IsShown() then v:Refresh() end end)
  return v
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------
local tabButtons = {}

function UI.ShowView(name)
  UI.EnsurePanel()
  for k, v in pairs(views) do
    if k == name then v:Show() else v:Hide() end
  end
  current = name
  for k, b in pairs(tabButtons) do
    if k == name then
      b:SetAlpha(1)
      if b.plainText then b.plainText:SetTextColor(1, 0.82, 0) end
    else
      b:SetAlpha(0.7)
    end
  end
  local v = views[name]
  if v and v.Refresh then v:Refresh() end
end

function UI.ShowItem(key)
  UI.EnsurePanel()
  UI.ShowView("item")
  views.item:Show_(key)
end

function UI.ShowFan(key)
  UI.EnsurePanel()
  UI.ShowView("fan")
  local plan = H.Fan.plan
  if key and not (plan and plan.key == key) then views.fan:Select(key) end
end

function UI.IsShown()
  return panel ~= nil and panel:IsShown()
end

function UI.EnsurePanel()
  if panel then return panel end
  panel = CreateFrame("Frame", "AuctionHoundPanel", UIParent)
  panel:Hide()

  local header = CreateFrame("Frame", nil, panel)
  header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  header:SetHeight(22)
  panel.header = header

  local x = 0
  for _, def in ipairs({ { "markets", "Markets" }, { "item", "Item" }, { "fan", "Fan" }, { "history", "History" } }) do
    local b = UI.Button(header, def[2], 70, 22, function() UI.ShowView(def[1]) end)
    b:SetPoint("TOPLEFT", header, "TOPLEFT", x, 0)
    tabButtons[def[1]] = b
    x = x + 73
  end

  -- auto scan sits at the right end, beside the scan timer in the
  -- status line; the label is anchored first so the pair right-aligns
  local autoBox = UI.CheckButton(header, "auto scan", function(checked)
    H.Settings().autoScan = checked and true or false
    if checked then H.Scan.AutoTick() end
    UI.UpdateStatus()
  end)
  autoBox.label:ClearAllPoints()
  autoBox.label:SetPoint("RIGHT", panel, "TOPRIGHT", -4, -11)
  autoBox:SetPoint("RIGHT", autoBox.label, "LEFT", -1, 0)
  UI.autoScanBox = autoBox

  -- estimates sits to its left: whether crafted cost and value as an
  -- input stand in for the reference while an item's history is thin
  local estBox = UI.CheckButton(header, "estimates", function(checked)
    H.Settings().estimates = checked and true or false
    H.Events:Fire("SETTINGS_CHANGED", "estimates")
  end)
  estBox.label:ClearAllPoints()
  estBox.label:SetPoint("RIGHT", autoBox, "LEFT", -10, 0)
  estBox:SetPoint("RIGHT", estBox.label, "LEFT", -1, 0)
  UI.estimatesBox = estBox

  statusText = UI.Text(panel, "GameFontDisableSmall", "", "RIGHT")
  statusText:SetPoint("RIGHT", estBox, "LEFT", -10, 0)
  statusText:SetPoint("LEFT", header, "TOPLEFT", x + 6, -11)

  local line = UI.Divider(panel)
  line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -26)
  line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -26)

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -UI.BODY_TOP)
  body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  panel.body = body

  views.markets = buildMarketsView(body)
  views.item = buildItemView(body)
  views.fan = buildFanView(body)
  views.history = buildHistoryView(body)
  UI.views = views

  H.Events:On("SCAN_STATUS", UI.UpdateStatus)
  H.Events:On("SCAN_DONE", UI.UpdateStatus)
  H.Events:On("SETTINGS_CHANGED", UI.UpdateStatus)
  panel.ticker = C_Timer.NewTicker(5, function() if panel:IsShown() then UI.UpdateStatus() end end)
  panel:SetScript("OnShow", UI.UpdateStatus)

  UI.ShowView("markets")
  return panel
end

------------------------------------------------------------------------
-- Standalone window
------------------------------------------------------------------------
local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Escape closes the window. The usual way is a line in Blizzard's
-- UISpecialFrames list, but a line an addon writes there taints every
-- walk of that list by Blizzard's own code, and a protected call made
-- after such a walk is blocked in the name of whichever addon wrote
-- last, whatever it was doing; that list was the one piece of Blizzard
-- state Hound wrote that is read away from the house. So the key is
-- read on the window itself, and every other key is passed on.
-- Changing what is passed on is protected in combat, so the keyboard
-- is only taken out of combat: in combat the key does nothing and the
-- close button does the job.
local function armEscape(w)
  if inCombat() then return end
  w:SetPropagateKeyboardInput(true)
  w:EnableKeyboard(true)
end

local function watchEscape(w)
  w:SetScript("OnKeyDown", function(self, key)
    if inCombat() then return end
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      -- the keyboard is let go with the window, so nothing is swallowed
      -- if it is shown again in combat; OnShow takes it back
      self:EnableKeyboard(false)
      self:Hide()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  w:SetScript("OnShow", armEscape)
  H.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if w:IsShown() then armEscape(w) end
  end)
end

local function ensureWindow()
  if window then return window end
  window = UI.Create("Frame", "AuctionHoundWindow", UIParent, "BackdropTemplate")
  window:SetSize(UI.WINDOW_SIZE[1], UI.WINDOW_SIZE[2])
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", function(self) self:StartMoving() end)
  window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  window:SetFrameStrata("HIGH")
  window:SetClampedToScreen(true)
  if window.SetBackdrop then
    window:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  local title = UI.Text(window, "GameFontNormal", "Auction Hound", "CENTER")
  title:SetPoint("TOP", window, "TOP", 0, -16)
  local close = UI.Create("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() window:Hide() end)
  if not close.GetNormalTexture or not close:GetNormalTexture() then
    close:SetSize(22, 22)
    local fs = UI.Text(close, "GameFontNormal", "x", "CENTER")
    fs:SetPoint("CENTER")
  end
  window:Hide()
  watchEscape(window)
  return window
end

local function placePanel(parent, insets)
  panel:SetParent(parent)
  -- one level above the seat's cover in the house; the window has no
  -- cover and nothing else of its own that deep
  panel:SetFrameLevel(parent:GetFrameLevel() + 2)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", parent, "TOPLEFT", insets.left, -insets.top)
  panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -insets.right, insets.bottom)
  if panel.header then
    panel.header:ClearAllPoints()
    panel.header:SetPoint("TOPLEFT", panel, "TOPLEFT", insets.header or 0, 0)
    panel.header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  end
end

function UI.Toggle()
  UI.EnsurePanel()
  ensureWindow()
  if window:IsShown() then
    window:Hide()
    panel:Hide()
    return
  end
  placePanel(window, { left = 16, top = 36, right = 16, bottom = 16 })
  window:Show()
  panel:Show()
  UI.UpdateStatus()
end

------------------------------------------------------------------------
-- Auction house tab
--
-- The tab is a button of Blizzard's own tab template hung after the
-- last of the frame's tabs, and that is all it shares with them. It
-- stays out of the frame's tab list, tab count and display modes: the
-- frame's own code reads those on every mode change, an item
-- right-clicked in the bags with the house open included, and a value
-- an addon wrote there taints that code from then on, after which any
-- protected call made on the way is blocked in the addon's name. So
-- the tab is worked by hand. Its click seats the panel over the
-- frame's body and lights the tab, and the frame's own tabs are dimmed
-- with the template's cosmetics. Any mode change of the frame's own, a
-- tab click, a browse row, an item from the bags, takes the panel down
-- again: the hook runs after every call, a repeat of the current mode
-- included.
--
-- The frame's own mode stays as it is while the panel is up. Hiding
-- its frames would run their scripts in Hound's name, and whatever
-- they wrote would carry the taint; so they are covered instead. The
-- seat sits well above anything the frame draws in a mode of its own,
-- and a solid cover under the panel takes the view and the mouse. It
-- leaves the portrait's corner alone, the way the view buttons do.
------------------------------------------------------------------------
local ahHolder

UI.COVER = { 0.08, 0.07, 0.05 }

local function buildCover(seat, insets)
  local cover = CreateFrame("Frame", "AuctionHoundCover", seat)
  cover:SetPoint("TOPLEFT", seat, "TOPLEFT", insets.left, -insets.top)
  cover:SetPoint("BOTTOMRIGHT", seat, "BOTTOMRIGHT", -insets.right, insets.bottom)
  cover:SetFrameLevel(seat:GetFrameLevel() + 1)
  cover:EnableMouse(true)
  -- the header row, to the right of the portrait
  local top = cover:CreateTexture(nil, "BACKGROUND")
  top:SetPoint("TOPLEFT", cover, "TOPLEFT", insets.header or 0, 0)
  top:SetPoint("BOTTOMRIGHT", cover, "TOPRIGHT", 0, -UI.BODY_TOP)
  top:SetColorTexture(UI.COVER[1], UI.COVER[2], UI.COVER[3], 1)
  -- the body, clear of the portrait already
  local body = cover:CreateTexture(nil, "BACKGROUND")
  body:SetPoint("TOPLEFT", cover, "TOPLEFT", 0, -UI.BODY_TOP)
  body:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", 0, 0)
  body:SetColorTexture(UI.COVER[1], UI.COVER[2], UI.COVER[3], 1)
  cover.top, cover.body = top, body
  return cover
end

local function lightTabs(ah, hound)
  local tab = UI.ahTab
  if hound then
    if tab and PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
    if PanelTemplates_DeselectTab and type(ah.Tabs) == "table" then
      for _, t in ipairs(ah.Tabs) do pcall(PanelTemplates_DeselectTab, t) end
    end
  else
    if tab and PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
    if PanelTemplates_UpdateTabs then pcall(PanelTemplates_UpdateTabs, ah) end
  end
end

function UI.ShowInAuctionHouse()
  local ah = AuctionHouseFrame
  if not ah or not ahHolder then return end
  if window and window:IsShown() then window:Hide() end
  placePanel(ahHolder, UI.AH_INSETS)
  ahHolder:Show()
  panel:Show()
  UI.UpdateStatus()
  lightTabs(ah, true)
  if ah.SetTitle then pcall(ah.SetTitle, ah, "Auction Hound") end
end

function UI.HideInAuctionHouse()
  local ah = AuctionHouseFrame
  if not ah or not ahHolder or not ahHolder:IsShown() then return end
  ahHolder:Hide()
  if panel:GetParent() == ahHolder then panel:Hide() end
  lightTabs(ah, false)
end

local function hookAuctionHouse()
  local ah = AuctionHouseFrame
  if not ah or UI.ahHooked then return end
  UI.ahHooked = true
  UI.EnsurePanel()

  -- the panel's seat: a child of the frame, never a field on it, and
  -- above whatever the frame shows of its own
  ahHolder = CreateFrame("Frame", nil, ah)
  ahHolder:SetAllPoints()
  ahHolder:SetFrameLevel(ah:GetFrameLevel() + UI.AH_LEVELS)
  ahHolder:Hide()
  buildCover(ahHolder, UI.AH_INSETS)

  local ok, err = pcall(function()
    local tabs = type(ah.Tabs) == "table" and ah.Tabs or nil
    local last = tabs and tabs[#tabs]
    if not last then error("the frame has no tabs") end
    local tab
    for _, template in ipairs({ "AuctionHouseFrameDisplayModeTabTemplate", "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" }) do
      local created, f = pcall(CreateFrame, "Button", "AuctionHoundTab", ah, template)
      if created and f then tab = f break end
    end
    if not tab then error("no tab template available") end
    tab:SetText("Hound")
    tab:SetPoint("LEFT", last, "RIGHT", -15, 0)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
    if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
    -- the template's own click would hand the frame a mode of ours
    tab:SetScript("OnClick", function() UI.ShowInAuctionHouse() end)
    UI.ahTab = tab
  end)
  if not ok then
    H.Print("could not add the auction house tab (" .. tostring(err) .. "); use /hound for the window")
  end

  hooksecurefunc(ah, "SetDisplayMode", function() UI.HideInAuctionHouse() end)
end

H.Events:On("AH_UI_LOADED", hookAuctionHouse)
H.Events:On("AH_OPENED", function()
  hookAuctionHouse()
  UI.UpdateStatus()
end)
H.Events:On("AH_CLOSED", function()
  UI.UpdateStatus()
end)
