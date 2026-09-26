-- UI/Frame.lua: the panel, its three views, the AH tab and the window.
local ADDON, H = ...

local UI = H.UI

-- Where the panel sits inside the Blizzard auction house frame.
UI.AH_INSETS = { left = 8, top = 30, right = 8, bottom = 34 }
UI.WINDOW_SIZE = { 780, 500 }

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
  elseif S.state == "browsing" then
    table.insert(parts, string.format("browsing page %d", S.browse and S.browse.pages or 0))
  elseif S.state == "searching" and H.Snipe.queue then
    table.insert(parts, string.format("confirming %d / %d", H.Snipe.queue.index - 1, math.min(#H.Snipe.queue.cands, H.Snipe.queue.limit)))
  elseif H.Snipe.pending then
    table.insert(parts, "buying")
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
end

------------------------------------------------------------------------
-- Snipe view
------------------------------------------------------------------------
local function buildSnipeView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()

  local scanBtn = UI.Button(v, "Snipe Pass", 90, 22, function() H.Snipe.Run() end)
  scanBtn:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  local stopBtn = UI.Button(v, "Stop", 50, 22, function() H.Scan.Abort() H.Snipe.running = false H.Events:Fire("SCAN_STATUS") end)
  stopBtn:SetPoint("LEFT", scanBtn, "RIGHT", 4, 0)
  local clearBtn = UI.Button(v, "Clear", 50, 22, function() H.Snipe.Clear() end)
  clearBtn:SetPoint("LEFT", stopBtn, "RIGHT", 4, 0)

  local auto = UI.CheckButton(v, "Auto every 60s", function(checked) v.auto = checked end)
  auto:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)

  local buyAll = UI.Button(v, "Buy All", 70, 22)
  buyAll:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, 0)
  local buyOne = UI.Button(v, "Buy 1", 56, 22)
  buyOne:SetPoint("RIGHT", buyAll, "LEFT", -4, 0)

  local info = UI.Text(v, "GameFontDisableSmall", "", "LEFT")
  info:SetPoint("TOPLEFT", scanBtn, "BOTTOMLEFT", 2, -3)
  info:SetPoint("RIGHT", v, "RIGHT", -4, 0)

  local cols = {
    { key = "item", title = "Item", width = 210, kind = "item", value = function(r) return r.name end },
    { key = "qty", title = "Units", width = 46, align = "RIGHT", kind = "int", value = function(r) return r.dealQty end, desc = true },
    { key = "unit", title = "Unit", width = 72, align = "RIGHT", kind = "money", value = function(r) return r.unit end },
    { key = "ref", title = "Reference", width = 78, align = "RIGHT", kind = "money", value = function(r) return r.ref end,
      color = function(r) if string.sub(r.refSrc or "", 1, 5) == "prior" then return 0.7, 0.7, 0.7 end return 1, 1, 1 end },
    { key = "off", title = "Off", width = 48, align = "RIGHT", kind = "pct", value = function(r) return r.discount end, desc = true },
    { key = "net", title = "Net total", width = 84, align = "RIGHT", kind = "money", value = function(r) return r.netTotal end, desc = true,
      color = function(r, raw) if raw and raw > 0 then return 0.4, 0.9, 0.4 end return 0.9, 0.4, 0.4 end },
    { key = "score", title = "Score", width = 60, kind = "score", value = function(r) return r.score end, desc = true },
  }

  local reasons = UI.Text(v, "GameFontHighlightSmall", "", "LEFT")
  reasons:SetWordWrap(true)
  reasons:SetHeight(44)
  reasons:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 4, 2)
  reasons:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -4, 2)

  local function showReasons(row)
    if not row then reasons:SetText("") return end
    local head = string.format("%s  |  %s reference (%s), %d units at or under %s",
      H.ColoredName(row.itemID), H.Money(row.ref), row.refSrc or "?", row.dealQty, H.Money(row.maxUnit))
    reasons:SetText(head .. "\n" .. table.concat(row.reasons or {}, "  |  "))
  end

  local tbl = UI.CreateTable(v, cols, {
    sortKey = "score", sortDesc = true,
    onSelect = showReasons,
    onDouble = function(row) UI.ShowItem(row.key) end,
    tooltip = function(row, frame)
      if not GameTooltip then return end
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(row.itemID)
      GameTooltip:Show()
    end,
  })
  tbl:SetPoint("TOPLEFT", info, "BOTTOMLEFT", -2, -3)
  tbl:SetPoint("BOTTOMRIGHT", reasons, "TOPRIGHT", 4, 4)
  v.table = tbl

  buyAll:SetScript("OnClick", function()
    local row = tbl:Selected()
    if row then H.Snipe.Buy(row, row.dealQty) else H.Print("select a row first") end
  end)
  buyOne:SetScript("OnClick", function()
    local row = tbl:Selected()
    if row then H.Snipe.Buy(row, 1) else H.Print("select a row first") end
  end)

  function v:Refresh()
    tbl:SetData(H.Snipe.results)
    local b = H.Snipe.lastBrowse
    if b then
      info:SetText(string.format("%d results  |  browsed %d items%s, %d candidates, %s",
        #H.Snipe.results, b.count, b.partial and " (partial)" or "", H.Snipe.lastCandidates or 0, H.Ago(H.Now() - b.t)))
    else
      info:SetText("run a pass at the auction house to look for deals")
    end
    showReasons(tbl:Selected())
  end

  H.Events:On("SNIPE_UPDATED", function() if v:IsShown() then v:Refresh() end end)
  H.Events:On("SNIPE_DONE", function() if v:IsShown() then v:Refresh() end end)

  v.ticker = C_Timer.NewTicker(60, function()
    if v.auto and H.atAH and not H.Snipe.running and H.Scan.state == "idle" then H.Snipe.Run() end
  end)

  return v
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

  function v:Show_(key)
    self.key = key
    local itemID = H.ItemIDFromKey(key)
    icon:SetTexture(H.ItemIcon(itemID) or 134400)
    name:SetText(H.ColoredName(itemID))
    keyText:SetText("key " .. key .. "  |  " .. H.marketKey)
    local rec = H.Store.Get(key)
    local st = rec and H.Market.Stats(rec) or nil
    if st and st.market then
      statsLeft:SetText(string.format("market %s   floor %s   30 day %s\nlisted %d   moved ~%s a day   trend %s\nswing %s   %d scans over %d days   last %s",
        H.Money(st.market), H.Money(st.min or 0), H.Money(st.hist or 0),
        st.qty or 0, st.moved and tostring(H.Round(st.moved)) or "?", H.Pct(st.trend, true),
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

function UI.SeriesFor(rec)
  local out = {}
  for _, p in ipairs(H.Market.DailySeries(rec, 30)) do
    table.insert(out, { label = H.DayLabel(p.day), y = p.mv, y2 = p.min, vol = p.qty, moved = p.moved, s = p.s })
  end
  return out
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

function UI.EnsurePanel()
  if panel then return panel end
  panel = CreateFrame("Frame", "AuctionHoundPanel", UIParent)
  panel:Hide()

  local x = 0
  for _, def in ipairs({ { "snipe", "Snipe" }, { "markets", "Markets" }, { "item", "Item" } }) do
    local b = UI.Button(panel, def[2], 76, 22, function() UI.ShowView(def[1]) end)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
    tabButtons[def[1]] = b
    x = x + 80
  end

  statusText = UI.Text(panel, "GameFontDisableSmall", "", "RIGHT")
  statusText:SetPoint("RIGHT", panel, "TOPRIGHT", -2, -11)
  statusText:SetPoint("LEFT", panel, "TOPLEFT", x + 6, -11)

  local line = UI.Divider(panel)
  line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -26)
  line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -26)

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -32)
  body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  panel.body = body

  views.snipe = buildSnipeView(body)
  views.markets = buildMarketsView(body)
  views.item = buildItemView(body)

  H.Events:On("SCAN_STATUS", UI.UpdateStatus)
  H.Events:On("SCAN_DONE", UI.UpdateStatus)
  panel.ticker = C_Timer.NewTicker(5, function() if panel:IsShown() then UI.UpdateStatus() end end)
  panel:SetScript("OnShow", UI.UpdateStatus)

  UI.ShowView("snipe")
  return panel
end

------------------------------------------------------------------------
-- Standalone window
------------------------------------------------------------------------
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
  tinsert(UISpecialFrames, "AuctionHoundWindow")
  return window
end

local function placePanel(parent, insets)
  panel:SetParent(parent)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", parent, "TOPLEFT", insets.left, -insets.top)
  panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -insets.right, insets.bottom)
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
------------------------------------------------------------------------
UI.displayMode = { "HoundFrame" }

local function hookAuctionHouse()
  local ah = AuctionHouseFrame
  if not ah or UI.ahHooked then return end
  UI.ahHooked = true
  UI.EnsurePanel()

  local holder = CreateFrame("Frame", nil, ah)
  holder:SetAllPoints()
  holder:Hide()
  ah.HoundFrame = holder

  local ok, err = pcall(function()
    local id = #ah.Tabs + 1
    local tab
    for _, template in ipairs({ "AuctionHouseFrameDisplayModeTabTemplate", "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" }) do
      local created, f = pcall(CreateFrame, "Button", "AuctionHouseFrameTab" .. id, ah, template)
      if created and f then tab = f break end
    end
    if not tab then error("no tab template available") end
    tab:SetID(id)
    tab:SetText("Hound")
    tab.displayMode = UI.displayMode
    tab:SetPoint("LEFT", ah.Tabs[id - 1], "RIGHT", -15, 0)
    table.insert(ah.Tabs, tab)
    if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(ah, id) end
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
    if not tab:GetScript("OnClick") then
      tab:SetScript("OnClick", function() ah:SetDisplayMode(UI.displayMode) end)
    end
    UI.ahTab = tab
  end)
  if not ok then
    H.Print("could not add the auction house tab (" .. tostring(err) .. "); use /hound for the window")
  end

  hooksecurefunc(ah, "SetDisplayMode", function(frame, mode)
    if mode == UI.displayMode then
      if window and window:IsShown() then window:Hide() end
      placePanel(frame, UI.AH_INSETS)
      holder:Show()
      panel:Show()
      UI.UpdateStatus()
      if frame.SetTitle then pcall(frame.SetTitle, frame, "Auction Hound") end
    else
      holder:Hide()
      if panel:GetParent() == frame then panel:Hide() end
    end
  end)
end

H.Events:On("AH_UI_LOADED", hookAuctionHouse)
H.Events:On("AH_OPENED", function()
  hookAuctionHouse()
  UI.UpdateStatus()
end)
H.Events:On("AH_CLOSED", function()
  UI.UpdateStatus()
end)
