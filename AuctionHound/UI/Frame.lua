-- UI/Frame.lua: the panel, its views, the AH tab and the window. The
-- Deals view is built in UI/Deals.lua.
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
      elseif S.Unanswered() then
        -- the house counts its own 15 minutes; ours had run out, its had not
        table.insert(parts, "the house did not answer the last scan request")
      else
        table.insert(parts, "full scan ready")
      end
    end
  end
  table.insert(parts, string.format("%d items", H.Store.Count()))
  return table.concat(parts, "  |  ")
end

UI.StatusLine = statusLine

function UI.UpdateStatus()
  if statusText then statusText:SetText(statusLine()) end
  if UI.autoScanBox then UI.autoScanBox:SetChecked(H.Settings().autoScan and true or false) end
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
    { key = "min", title = "Floor", width = 72, align = "RIGHT", kind = "money", value = function(r) return r.st.floor end, desc = true },
    { key = "qty", title = "Listed", width = 54, align = "RIGHT", kind = "int", value = function(r) return r.st.qty end, desc = true },
    { key = "cleared", title = "Cleared", width = 54, align = "RIGHT", kind = "int", value = function(r) return r.st.cleared and H.Round(r.st.cleared) end, desc = true },
    { key = "trend", title = "Trend", width = 54, align = "RIGHT", kind = "spct", value = function(r) return r.st.trend end, desc = true,
      color = function(r, raw) if not raw then return 0.6, 0.6, 0.6 end if raw > 0.05 then return 0.4, 0.9, 0.4 end if raw < -0.05 then return 0.9, 0.4, 0.4 end return 1, 1, 1 end },
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
  graph:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)

  -- With no item chosen the view says what it is for.
  function v:Refresh()
    if self.key then self:Show_(self.key) return end
    icon:SetTexture(134400)
    name:SetText("Item")
    keyText:SetText(self.err or "one item's history  |  " .. H.marketKey)
    self.err = nil
    statsLeft:SetText("Pick an item: double-click a row in Markets, pick one in the Fan tab's bag list, or type part of a name, an item id or a link in the find box and press Enter.")
    statsRight:SetText("Shows market value, floor, trend, units cleared, the daily graph, the vendor price, and what you sold it for.")
    graph:SetSeries({})
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
      local demand = H.Market.ClearedLine(st) or "none seen to clear yet"
      statsLeft:SetText(string.format("market %s   floor %s   trend %s\nlisted %d   %s\n%d scans over %d days   last %s",
        H.Money(st.market), H.Money(st.floor or 0), H.Pct(st.trend, true),
        st.qty or 0, demand, st.samples, st.days, H.Ago(st.age)))
      graph:SetSeries(UI.SeriesFor(rec))
    else
      statsLeft:SetText("no history for this item yet")
      graph:SetSeries({})
    end
    local right = {}
    local vendor = H.VendorSell(itemID)
    table.insert(right, vendor and ("vendor " .. H.Money(vendor)) or "no vendor price")
    local cl = H.Market.Clearing(H.Store.Posts(key))
    if cl then table.insert(right, "yours: " .. H.Fan.ClearingLine(cl)) end
    statsRight:SetText(table.concat(right, "\n"))
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
    table.insert(out, { label = H.DayLabel(p.day), y = p.mv, y2 = p.min, vol = p.qty, cleared = p.cleared, s = p.s })
  end
  return out
end

------------------------------------------------------------------------
-- Fan view: one item from the bags, posted as batches at a price
-- interval. The start price, the step, the batches and the units in
-- each make the plan; one click posts one batch.
------------------------------------------------------------------------
local function statusColor(text)
  if not text then return 0.6, 0.6, 0.6 end
  if string.find(text, "sold", 1, true) then return 0.4, 0.9, 0.4 end
  if string.find(text, "expired", 1, true) or text == "failed" then return 0.9, 0.4, 0.4 end
  if text == "active" or text == "posted" or text == "posting" then return 1, 1, 1 end
  if text == "bought" then return 0.45, 0.85, 1.0 end
  return 0.6, 0.6, 0.6
end

local function buildFanView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  local Fan = H.Fan

  -- left: what is in the bags
  local bagsTitle = UI.Text(v, "GameFontNormalSmall", "In bags", "LEFT")
  bagsTitle:SetPoint("TOPLEFT", v, "TOPLEFT", 4, -5)
  local bagCols = {
    { key = "item", title = "Item", width = 156, kind = "item", value = function(r) return r.name end },
    { key = "count", title = "Units", width = 42, align = "RIGHT", kind = "int", value = function(r) return r.count end, desc = true },
    { key = "floor", title = "Floor", width = 64, align = "RIGHT", kind = "money", value = function(r) return r.floor end, desc = true },
  }
  local bags = UI.CreateTable(v, bagCols, {
    sortKey = "floor", sortDesc = true,
    onSelect = function(row) v:Select(row.key) end,
    tooltip = function(row, frame)
      if not GameTooltip then return end
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(row.itemID)
      GameTooltip:Show()
    end,
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
  local sub = UI.Text(right, "GameFontDisableSmall", "", "LEFT")
  sub:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -3)
  sub:SetPoint("RIGHT", right, "RIGHT", 0, 0)

  -- the plan's five figures, on one row
  local function changed() if not v.loading then v:Replan() end end
  local function field(label, width, prev)
    local l = UI.Text(right, "GameFontDisableSmall", label, "LEFT")
    if prev then
      l:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    else
      l:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
    end
    local box = UI.EditBox(right, width, changed)
    box:SetPoint("LEFT", l, "RIGHT", 8, 0)
    box.label = l
    return box
  end
  local start = field("start", 76)
  local step = field("step %", 34, start)
  local batches = field("batches", 30, step)
  local perBatch = field("per batch", 34, batches)
  local duration = UI.CycleButton(right, 42, { "12h", "24h", "48h" }, changed)
  duration:SetPoint("LEFT", perBatch, "RIGHT", 8, 0)
  v.start, v.step, v.batches, v.perBatch, v.duration = start, step, batches, perBatch, duration

  local summary = UI.Text(right, "GameFontDisableSmall", "", "LEFT")
  summary:SetPoint("TOPLEFT", start.label, "BOTTOMLEFT", 0, -10)
  summary:SetPoint("RIGHT", right, "RIGHT", 0, 0)

  local planCols = {
    { key = "i", title = "#", width = 26, align = "RIGHT", value = function(r) return r.b.i end },
    { key = "unit", title = "Unit", width = 84, align = "RIGHT", kind = "money", value = function(r) return r.b.unit end,
      color = function(r) if r.b.belowVendor then return 0.9, 0.4, 0.4 end return 1, 1, 1 end },
    { key = "qty", title = "Units", width = 44, align = "RIGHT", kind = "int", value = function(r) return r.b.qty end },
    { key = "dep", title = "Deposit", width = 70, align = "RIGHT", kind = "money", value = function(r) return r.b.deposit end },
    { key = "status", title = "Status", width = 80, value = function(r) return Fan.BatchStatus(r.b) end,
      color = function(r, raw) return statusColor(raw) end },
  }
  local planTbl = UI.CreateTable(right, planCols, { sortKey = "i" })
  v.planTbl = planTbl
  planTbl:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -4, -6)
  planTbl:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  planTbl:SetHeight(18 + 10 * 16)

  local postBtn = UI.Button(right, "Post", 110, 22, function() Fan.PostNext() end)
  postBtn:SetPoint("TOPLEFT", planTbl, "BOTTOMLEFT", 0, -6)
  local resetBtn = UI.Button(right, "Reset", 56, 22, function() Fan.Reset() v:Replan() end)
  resetBtn:SetPoint("LEFT", postBtn, "RIGHT", 4, 0)
  local planInfo = UI.Text(right, "GameFontDisableSmall", "", "LEFT")
  planInfo:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
  planInfo:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  v.postBtn = postBtn

  local function setBoxes(o)
    v.loading = true
    start:SetText(o.start and (string.gsub(H.MoneyExact(o.start), " ", "")) or "")
    step:SetText(tostring(H.Round(o.step * 1000) / 10))
    batches:SetText(tostring(o.batches))
    perBatch:SetText(tostring(o.perBatch))
    duration:SetValue(({ "12h", "24h", "48h" })[o.duration] or "48h")
    v.loading = false
  end

  function v:RebuildBags()
    local rows = {}
    for key, e in pairs(Fan.Bags()) do
      table.insert(rows, { key = key, itemID = e.itemID, name = H.ItemName(e.itemID), count = e.count, floor = Fan.DefaultPrice(key) })
    end
    bags:SetData(rows)
    self.bagsAt = H.Now()
  end

  -- A new item starts at its floor, with the last plan's step, batches
  -- and units.
  function v:Select(key)
    if Fan.InProgress() and Fan.plan.key ~= key then
      self.err = "a fan is in progress; reset it before planning another"
      self:Refresh()
      return
    end
    self.key = key
    local S = H.Settings()
    setBoxes({ start = Fan.DefaultPrice(key), step = S.fanStep, batches = S.fanBatches, perBatch = S.fanPerBatch, duration = S.postDuration })
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
      start = H.ParseMoney(start:GetText()),
      perBatch = tonumber(perBatch:GetText()),
      batches = tonumber(batches:GetText()),
      duration = ({ ["12h"] = 1, ["24h"] = 2, ["48h"] = 3 })[duration:GetValue()],
    }
    local stepPct = tonumber(step:GetText())
    if stepPct then o.step = stepPct / 100 end
    local plan, err = Fan.Setup(o)
    if plan then self.shown = plan.id end
    self.err = err
    self:Refresh()
  end

  function v:Refresh()
    local plan = Fan.plan
    if plan and plan.id ~= self.shown then
      -- planned elsewhere, from chat say: its figures fill the boxes
      self.key, self.shown = plan.key, plan.id
      setBoxes({ start = plan.start, step = plan.step, batches = plan.requested, perBatch = plan.perBatch, duration = plan.duration })
    end
    if not self.key then
      icon:SetTexture(134400)
      name:SetText("pick an item from your bags")
      sub:SetText("")
      summary:SetText("")
      planTbl:SetData({})
      postBtn:SetText("Post")
      planInfo:SetText(self.err or "")
      return
    end
    local itemID = H.ItemIDFromKey(self.key)
    icon:SetTexture(H.ItemIcon(itemID) or 134400)
    name:SetText(H.ColoredName(itemID))
    local floor = Fan.DefaultPrice(self.key)
    sub:SetText(string.format("%d in bags  |  floor %s", Fan.BagCount(self.key), floor and H.Money(floor) or "not scanned"))
    if plan and plan.key == self.key then
      summary:SetText(string.format("%s to %s  |  %d units, %s gross, %s net%s",
        H.Money(plan.low or 0), H.Money(plan.high or 0), plan.units, H.Money(plan.gross), H.Money(plan.net),
        plan.short and "  |  short on units" or ""))
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
      summary:SetText("")
      planTbl:SetData({})
      postBtn:SetText("Post")
    end
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
local HISTORY_FILTERS = { "All", "Active", "Sold", "Bought", "Ended", "Cancelled" }

local function historyMatches(p, f)
  if f == "All" then return true end
  if f == "Active" then return p.status == "active" or p.status == "pending" end
  if f == "Sold" then return p.status == "sold" or (p.sold or 0) > 0 end
  if f == "Bought" then return p.status == "bought" end
  if f == "Ended" then return p.status == "expired" or p.status == "ended" end
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
  for _, def in ipairs({ { "markets", "Markets" }, { "deals", "Deals" }, { "item", "Item" }, { "fan", "Fan" }, { "history", "History" } }) do
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

  statusText = UI.Text(panel, "GameFontDisableSmall", "", "RIGHT")
  statusText:SetPoint("RIGHT", autoBox, "LEFT", -10, 0)
  statusText:SetPoint("LEFT", header, "TOPLEFT", x + 6, -11)

  local line = UI.Divider(panel)
  line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -26)
  line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -26)

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -UI.BODY_TOP)
  body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  panel.body = body

  views.markets = buildMarketsView(body)
  views.deals = UI.BuildDealsView(body)
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

function UI.WatchEscape(w)
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
  w:HookScript("OnShow", armEscape)
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
  UI.WatchEscape(window)
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
