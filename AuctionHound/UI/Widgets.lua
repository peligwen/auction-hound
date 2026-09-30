-- UI/Widgets.lua: the few widgets the addon needs, built on plain frames
-- so nothing depends on Blizzard templates that may move.
local ADDON, H = ...

local UI = H.UI or {}
H.UI = UI

UI.GOLD = { 0.90, 0.75, 0.30 }
UI.DIM = { 0.35, 0.30, 0.18 }
UI.GREY = { 0.45, 0.45, 0.45 }
UI.GREEN = { 0.30, 0.80, 0.30 }
UI.RED = { 0.85, 0.30, 0.30 }

------------------------------------------------------------------------
-- Basics
------------------------------------------------------------------------
function UI.Create(kind, name, parent, template)
  if template then
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f end
  end
  return CreateFrame(kind, name, parent)
end

-- A cell on one of Blizzard's lists. The row's hover calls OnLineEnter
-- and OnLineLeave on every cell it holds, so a cell without them
-- crashes the row; Blizzard's cells inherit both from
-- TableBuilderCellMixin, and so do ours.
function UI.CellMixin()
  local m = {}
  if type(Mixin) == "function" and type(TableBuilderCellMixin) == "table" then
    Mixin(m, TableBuilderCellMixin)
  end
  if not m.OnLineEnter then function m:OnLineEnter() end end
  if not m.OnLineLeave then function m:OnLineLeave() end end
  return m
end

-- Blizzard's rows take the mouse for their highlight. A cell with a
-- tooltip takes it instead, so it hands the hover on to its row the
-- way Blizzard's own tooltip cells do.
function UI.RowScript(cell, name)
  local row = cell:GetParent()
  if row and type(ExecuteFrameScript) == "function" then
    ExecuteFrameScript(row, name)
  end
end

function UI.Text(parent, font, text, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  if text then fs:SetText(text) end
  return fs
end

function UI.Button(parent, text, width, height, onClick)
  local b = UI.Create("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 90, height or 22)
  b:SetText(text)
  if not b:GetFontString() then
    local fs = UI.Text(b, "GameFontNormalSmall", text, "CENTER")
    fs:SetPoint("CENTER")
    b.plainText = fs
  end
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.CheckButton(parent, label, onClick)
  local c = UI.Create("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(22, 22)
  local fs = UI.Text(c, "GameFontHighlightSmall", label)
  fs:SetPoint("LEFT", c, "RIGHT", 1, 0)
  c.label = fs
  if onClick then c:SetScript("OnClick", function(self) onClick(self:GetChecked()) end) end
  return c
end

function UI.EditBox(parent, width, onChange)
  local e = UI.Create("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnTextChanged", function(self) if onChange then onChange(self:GetText()) end end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

-- A button that steps through a short list of options on each click.
function UI.CycleButton(parent, width, options, onChange)
  local b = UI.Button(parent, options[1], width, 22)
  b.options = options
  b.index = 1
  function b:SetValue(v)
    for i, o in ipairs(self.options) do
      if o == v then self.index = i end
    end
    self:SetText(self.options[self.index])
    if self.plainText then self.plainText:SetText(self.options[self.index]) end
  end
  function b:GetValue() return self.options[self.index] end
  b:SetScript("OnClick", function(self)
    self.index = self.index % #self.options + 1
    self:SetValue(self.options[self.index])
    if onChange then onChange(self:GetValue(), self.index) end
  end)
  return b
end

function UI.Divider(parent)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetHeight(1)
  t:SetColorTexture(UI.DIM[1], UI.DIM[2], UI.DIM[3], 0.8)
  return t
end

------------------------------------------------------------------------
-- Sparkline: a row of tiny bars
------------------------------------------------------------------------
function UI.CreateSparkline(parent, width, height, n)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(width, height)
  s.bars = {}
  s.n = n
  local slot = width / n
  for i = 1, n do
    local t = s:CreateTexture(nil, "ARTWORK")
    t:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", (i - 1) * slot, 0)
    t:SetWidth(math.max(1, slot - 1))
    t:SetHeight(1)
    t:SetColorTexture(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.9)
    t:Hide()
    s.bars[i] = t
  end
  function s:SetValues(values)
    local max = 0
    for i = 1, self.n do
      local v = values and values[i]
      if v and v > max then max = v end
    end
    for i = 1, self.n do
      local v = values and values[i]
      local bar = self.bars[i]
      if v and max > 0 then
        bar:SetHeight(math.max(1, height * v / max))
        bar:Show()
      else
        bar:Hide()
      end
    end
  end
  return s
end

------------------------------------------------------------------------
-- Score pips: five small squares, lit up to the score
------------------------------------------------------------------------
function UI.CreatePips(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(5 * 9, 8)
  p.pips = {}
  for i = 1, 5 do
    local t = p:CreateTexture(nil, "ARTWORK")
    t:SetSize(7, 7)
    t:SetPoint("LEFT", p, "LEFT", (i - 1) * 9, 0)
    p.pips[i] = t
  end
  function p:SetScore(score)
    for i = 1, 5 do
      if i <= (score or 0) then
        self.pips[i]:SetColorTexture(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
      else
        self.pips[i]:SetColorTexture(UI.DIM[1], UI.DIM[2], UI.DIM[3], 0.6)
      end
    end
  end
  return p
end

------------------------------------------------------------------------
-- Table with sortable headers and its own scrollbar.
--
-- cols: array of
--   key      unique id
--   title    header text
--   width    pixels
--   align    LEFT | RIGHT | CENTER
--   kind     text | money | int | pct | spct | item | spark | score
--   value    function(row) -> raw value (used for sort and display)
--   text     optional function(row, raw) -> display string
--   desc     sort descending first
-- opts: rowHeight, sortKey, sortDesc, onSelect(row), onDouble(row), tooltip(row, frame)
------------------------------------------------------------------------
local function compare(a, b)
  if a == nil and b == nil then return false end
  if a == nil then return false end
  if b == nil then return true end
  if type(a) == "number" and type(b) == "number" then return a < b end
  return tostring(a) < tostring(b)
end

-- Money in a table cell: the exact figure when it fits the column,
-- else the same without the copper, else the short form. A price is
-- only ever rounded on screen when there is no room for it.
function UI.SetMoney(fs, copper, width)
  copper = H.Round(copper or 0)
  local fits = function()
    local w = fs.GetStringWidth and fs:GetStringWidth()
    return not width or type(w) ~= "number" or w <= width
  end
  fs:SetText(H.MoneyExact(copper))
  if fits() then return end
  if copper >= 10000 or copper <= -10000 then
    local whole = copper < 0 and -math.floor(-copper / 100) * 100 or math.floor(copper / 100) * 100
    fs:SetText(H.MoneyExact(whole))
    if fits() then return end
  end
  fs:SetText(H.MoneyShort(copper))
end

local function cellText(col, row, raw)
  if col.text then return col.text(row, raw) end
  if raw == nil then return "-" end
  local kind = col.kind or "text"
  if kind == "money" then return H.MoneyExact(raw) end
  if kind == "int" then return tostring(H.Round(raw)) end
  if kind == "pct" then return H.Pct(raw) end
  if kind == "spct" then return H.Pct(raw, true) end
  return tostring(raw)
end

function UI.CreateTable(parent, cols, opts)
  opts = opts or {}
  local t = CreateFrame("Frame", nil, parent)
  t.cols = cols
  t.rowHeight = opts.rowHeight or 16
  t.headerHeight = 18
  t.data = {}
  t.view = {}
  t.offset = 0
  t.rows = {}
  t.opts = opts
  t.sortKey = opts.sortKey
  t.sortDesc = opts.sortDesc
  t:SetClipsChildren(true)

  local bg = t:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.25)

  t.headers = {}
  local x = 0
  for i, col in ipairs(cols) do
    local hb = CreateFrame("Button", nil, t)
    hb:SetSize(col.width, t.headerHeight)
    hb:SetPoint("TOPLEFT", t, "TOPLEFT", x, 0)
    local hbg = hb:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.16, 0.13, 0.06, 0.9)
    local hl = hb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    local fs = UI.Text(hb, "GameFontNormalSmall", col.title, col.align or "LEFT")
    fs:SetPoint("LEFT", hb, "LEFT", 4, 0)
    fs:SetPoint("RIGHT", hb, "RIGHT", -11, 0)
    local arrow = hb:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", hb, "RIGHT", -2, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:Hide()
    hb.arrow = arrow
    hb.text = fs
    hb.col = col
    hb:SetScript("OnClick", function()
      local desc
      if t.sortKey == col.key then desc = not t.sortDesc else desc = col.desc or false end
      t:SetSort(col.key, desc)
    end)
    t.headers[i] = hb
    x = x + col.width
  end
  t.totalWidth = x

  local sb = CreateFrame("Slider", nil, t)
  sb:SetOrientation("VERTICAL")
  sb:SetWidth(10)
  sb:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, -t.headerHeight)
  sb:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
  sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  local sbg = sb:CreateTexture(nil, "BACKGROUND")
  sbg:SetAllPoints()
  sbg:SetColorTexture(0, 0, 0, 0.35)
  sb:SetMinMaxValues(0, 0)
  sb:SetValueStep(1)
  sb:SetValue(0)
  sb:SetScript("OnValueChanged", function(self, v)
    local o = math.floor((v or 0) + 0.5)
    if o ~= t.offset then
      t.offset = o
      t:Refresh(true)
    end
  end)
  t.scrollbar = sb
  t:EnableMouseWheel(true)
  t:SetScript("OnMouseWheel", function(_, delta) t:Scroll(-delta * 3) end)
  t:SetScript("OnSizeChanged", function() t:Layout() end)
  t:SetScript("OnShow", function() t:Layout() end)

  function t:NumVisible()
    local h = self:GetHeight() or 0
    return math.max(1, math.floor((h - self.headerHeight) / self.rowHeight))
  end

  function t:CreateRow(i)
    local row = CreateFrame("Button", nil, self)
    row:SetHeight(self.rowHeight)
    row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(self.headerHeight + (i - 1) * self.rowHeight))
    row:SetPoint("RIGHT", self.scrollbar, "LEFT", -1, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, 0.03)
    if i % 2 == 1 then stripe:Hide() end
    local sel = row:CreateTexture(nil, "BORDER")
    sel:SetAllPoints()
    sel:SetColorTexture(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.18)
    sel:Hide()
    row.selected = sel
    row.cells = {}
    local x = 0
    for c, col in ipairs(self.cols) do
      local cell
      if col.kind == "spark" then
        cell = UI.CreateSparkline(row, col.width - 8, self.rowHeight - 4, col.points or 30)
        cell:SetPoint("LEFT", row, "LEFT", x + 4, 0)
      elseif col.kind == "score" then
        cell = UI.CreatePips(row)
        cell:SetPoint("LEFT", row, "LEFT", x + 6, 0)
      elseif col.kind == "item" then
        cell = CreateFrame("Frame", nil, row)
        cell:SetSize(col.width, self.rowHeight)
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        local icon = cell:CreateTexture(nil, "ARTWORK")
        icon:SetSize(self.rowHeight - 2, self.rowHeight - 2)
        icon:SetPoint("LEFT", cell, "LEFT", 3, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local fs = UI.Text(cell, "GameFontHighlightSmall", nil, "LEFT")
        fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        fs:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
        cell.icon = icon
        cell.text = fs
      else
        cell = UI.Text(row, "GameFontHighlightSmall", nil, col.align or "LEFT")
        cell:SetPoint("LEFT", row, "LEFT", x + 4, 0)
        cell:SetWidth(col.width - 8)
      end
      row.cells[c] = cell
      x = x + col.width
    end
    row:SetScript("OnClick", function(self)
      if not self.row then return end
      t.selectedKey = self.row.key
      t:Refresh(true)
      if t.opts.onSelect then t.opts.onSelect(self.row) end
    end)
    row:SetScript("OnDoubleClick", function(self)
      if self.row and t.opts.onDouble then t.opts.onDouble(self.row) end
    end)
    row:SetScript("OnEnter", function(self)
      if self.row and t.opts.tooltip then t.opts.tooltip(self.row, self) end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
  end

  function t:Layout()
    local n = self:NumVisible()
    for i = 1, n do
      if not self.rows[i] then self.rows[i] = self:CreateRow(i) end
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
    self:Refresh(true)
  end

  function t:SetSort(key, desc)
    self.sortKey = key
    self.sortDesc = desc
    self:Refresh()
  end

  function t:Scroll(delta)
    local n = self:NumVisible()
    local maxOffset = math.max(0, #self.view - n)
    local o = H.Clamp(self.offset + delta, 0, maxOffset)
    if o ~= self.offset then
      self.offset = o
      self.scrollbar:SetValue(o)
      self:Refresh(true)
    end
  end

  function t:SetData(rows)
    self.data = rows or {}
    self:Refresh()
  end

  function t:Filter(fn)
    self.filter = fn
    self:Refresh()
  end

  function t:Selected()
    if not self.selectedKey then return nil end
    for _, row in ipairs(self.data) do
      if row.key == self.selectedKey then return row end
    end
    return nil
  end

  function t:Refresh(viewOnly)
    if not viewOnly then
      local view = {}
      for _, row in ipairs(self.data) do
        if not self.filter or self.filter(row) then table.insert(view, row) end
      end
      local col
      for _, c in ipairs(self.cols) do
        if c.key == self.sortKey then col = c end
      end
      if col and col.value then
        local desc = self.sortDesc
        local vals = {}
        for i, row in ipairs(view) do vals[row] = col.value(row) end
        table.sort(view, function(a, b)
          local va, vb = vals[a], vals[b]
          if va == vb then return false end
          if desc then return compare(vb, va) end
          return compare(va, vb)
        end)
      end
      self.view = view
      for i, hb in ipairs(self.headers) do
        if hb.col.key == self.sortKey then
          hb.arrow:Show()
          if self.sortDesc then hb.arrow:SetTexCoord(0, 0.5625, 0, 1) else hb.arrow:SetTexCoord(0, 0.5625, 1, 0) end
        else
          hb.arrow:Hide()
        end
      end
    end
    local n = self:NumVisible()
    local maxOffset = math.max(0, #self.view - n)
    if self.offset > maxOffset then self.offset = maxOffset end
    self.scrollbar:SetMinMaxValues(0, maxOffset)
    if maxOffset > 0 then self.scrollbar:Show() else self.scrollbar:Hide() end
    for i = 1, n do
      local row = self.rows[i]
      if row then
        local data = self.view[self.offset + i]
        row.row = data
        if data then
          for c, col in ipairs(self.cols) do
            local cell = row.cells[c]
            local raw = col.value and col.value(data) or nil
            if col.kind == "spark" then
              cell:SetValues(raw)
            elseif col.kind == "score" then
              cell:SetScore(raw)
            elseif col.kind == "item" then
              cell.icon:SetTexture(data.icon or H.ItemIcon(data.itemID) or 134400)
              cell.text:SetText(col.text and col.text(data, raw) or raw or "")
            else
              if col.kind == "money" and not col.text and raw ~= nil then
                UI.SetMoney(cell, raw, col.width - 8)
              else
                cell:SetText(cellText(col, data, raw))
              end
              if col.color then
                local r, g, b = col.color(data, raw)
                cell:SetTextColor(r or 1, g or 1, b or 1)
              end
            end
          end
          if self.selectedKey and data.key == self.selectedKey then row.selected:Show() else row.selected:Hide() end
          row:Show()
        else
          row:Hide()
        end
      end
    end
  end

  return t
end

------------------------------------------------------------------------
-- Bar graph: one bar per point, a darker inner bar for the floor, and a
-- volume strip underneath. Hovering a bar shows the numbers.
------------------------------------------------------------------------
function UI.CreateBarGraph(parent, opts)
  opts = opts or {}
  local g = CreateFrame("Frame", nil, parent)
  g.padLeft = 48
  g.padBottom = 14
  g.volHeight = opts.volHeight or 14
  g.points = {}
  g.bars = {}
  g.xlabels = {}

  local bg = g:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.25)

  g.ylabels = {}
  for i = 1, 3 do
    local fs = UI.Text(g, "GameFontDisableSmall", "", "RIGHT")
    fs:SetWidth(g.padLeft - 4)
    g.ylabels[i] = fs
  end
  g.title = UI.Text(g, "GameFontNormalSmall", opts.title or "", "LEFT")
  g.title:SetPoint("TOPLEFT", g, "TOPLEFT", g.padLeft, -1)
  g.empty = UI.Text(g, "GameFontDisableSmall", "no history yet", "CENTER")
  g.empty:SetPoint("CENTER")
  g.empty:Hide()

  function g:GetBar(i)
    local bar = self.bars[i]
    if bar then return bar end
    bar = CreateFrame("Frame", nil, self)
    bar.main = bar:CreateTexture(nil, "ARTWORK")
    bar.main:SetPoint("BOTTOMLEFT")
    bar.main:SetPoint("BOTTOMRIGHT")
    bar.main:SetColorTexture(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.85)
    bar.inner = bar:CreateTexture(nil, "OVERLAY")
    bar.inner:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 0)
    bar.inner:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    bar.inner:SetColorTexture(0.55, 0.38, 0.10, 0.95)
    bar.vol = bar:CreateTexture(nil, "ARTWORK")
    bar.vol:SetColorTexture(UI.GREY[1], UI.GREY[2], UI.GREY[3], 0.8)
    bar.hover = bar:CreateTexture(nil, "HIGHLIGHT")
    bar.hover:SetAllPoints()
    bar.hover:SetColorTexture(1, 1, 1, 0.12)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
      local p = self.point
      if not p or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(p.label or "")
      if p.y then GameTooltip:AddDoubleLine("market", H.Money(p.y), 1, 1, 1, 1, 1, 1) end
      if p.y2 then GameTooltip:AddDoubleLine("floor", H.Money(p.y2), 1, 1, 1, 1, 1, 1) end
      if p.vol then GameTooltip:AddDoubleLine("listed", tostring(H.Round(p.vol)), 1, 1, 1, 1, 1, 1) end
      if p.moved then GameTooltip:AddDoubleLine("moved", "~" .. tostring(H.Round(p.moved)), 1, 1, 1, 1, 1, 1) end
      if p.cleared then GameTooltip:AddDoubleLine("cleared", tostring(H.Round(p.cleared)), 1, 1, 1, 1, 1, 1) end
      if p.s then GameTooltip:AddDoubleLine("scans", tostring(p.s), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.bars[i] = bar
    return bar
  end

  function g:SetSeries(points)
    self.points = points or {}
    self:Layout()
  end

  function g:Layout()
    local w, h = self:GetWidth() or 0, self:GetHeight() or 0
    local n = #self.points
    local plotW = w - self.padLeft - 4
    local plotTop = 14
    local plotH = h - self.padBottom - self.volHeight - plotTop - 4
    if n == 0 or plotW <= 0 or plotH <= 0 then
      for _, bar in ipairs(self.bars) do bar:Hide() end
      for _, l in ipairs(self.xlabels) do l:Hide() end
      for _, l in ipairs(self.ylabels) do l:SetText("") end
      self.empty:Show()
      return
    end
    self.empty:Hide()
    local ymax, vmax = 0, 0
    for _, p in ipairs(self.points) do
      if p.y and p.y > ymax then ymax = p.y end
      if p.y2 and p.y2 > ymax then ymax = p.y2 end
      if p.vol and p.vol > vmax then vmax = p.vol end
    end
    if ymax == 0 then ymax = 1 end
    ymax = ymax * 1.08
    local slot = plotW / n
    local barW = math.max(1, slot - 1)
    local labelEvery = math.max(1, math.ceil(n / 6))
    local li = 0
    for i, p in ipairs(self.points) do
      local bar = self:GetBar(i)
      bar.point = p
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", self.padLeft + (i - 1) * slot, self.padBottom)
      bar:SetSize(barW, plotH + self.volHeight)
      if p.y then
        bar.main:SetHeight(math.max(1, plotH * p.y / ymax))
        bar.main:ClearAllPoints()
        bar.main:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, self.volHeight)
        bar.main:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, self.volHeight)
        bar.main:Show()
      else
        bar.main:Hide()
      end
      if p.y2 and barW >= 3 then
        bar.inner:SetHeight(math.max(1, plotH * p.y2 / ymax))
        bar.inner:ClearAllPoints()
        bar.inner:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, self.volHeight)
        bar.inner:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, self.volHeight)
        bar.inner:Show()
      else
        bar.inner:Hide()
      end
      if p.vol and vmax > 0 then
        bar.vol:ClearAllPoints()
        bar.vol:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        bar.vol:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        bar.vol:SetHeight(math.max(1, (self.volHeight - 2) * p.vol / vmax))
        bar.vol:Show()
      else
        bar.vol:Hide()
      end
      bar:Show()
      if (i - 1) % labelEvery == 0 and p.label then
        li = li + 1
        local l = self.xlabels[li]
        if not l then
          l = UI.Text(self, "GameFontDisableSmall", "", "LEFT")
          self.xlabels[li] = l
        end
        l:ClearAllPoints()
        l:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", self.padLeft + (i - 1) * slot, 0)
        l:SetText(p.label)
        l:Show()
      end
    end
    for i = n + 1, #self.bars do self.bars[i]:Hide() end
    for i = li + 1, #self.xlabels do self.xlabels[i]:Hide() end
    local levels = { 1, 0.5, 0 }
    for i, frac in ipairs(levels) do
      local fs = self.ylabels[i]
      fs:ClearAllPoints()
      fs:SetPoint("RIGHT", self, "BOTTOMLEFT", self.padLeft - 4, self.padBottom + self.volHeight + plotH * frac)
      fs:SetText(H.MoneyShort(ymax / 1.08 * frac))
    end
  end

  g:SetScript("OnSizeChanged", function() g:Layout() end)
  g:SetScript("OnShow", function() g:Layout() end)
  return g
end
