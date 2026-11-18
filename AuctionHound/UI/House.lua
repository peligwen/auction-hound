-- UI/House.lua: how Hound sits on Blizzard's auction house lists
-- without writing anything of Blizzard's.
--
-- The client blocks a protected call, using an item from the bags say,
-- when the code on the way to it has read a value an addon wrote, and
-- names the addon. The house's frame reads its lists on the way to
-- opening the bags when the house opens, so a data provider, a layout
-- or a redraw flag of Hound's on one of them gave every slot button its
-- bag number in Hound's name, and every item used from the bags after
-- that was blocked until /reload. So nothing is written on a list, a
-- row or a cell of Blizzard's, and none of Blizzard's own code is run
-- from Hound's:
--
--   * Blizzard's cells are met through secure hooks on their mixins'
--     methods: Blizzard's code runs first and untouched, Hound's after,
--     and the taint of Hound's stays with Hound's.
--   * What Hound shows on a row is its own frame, a child of the cell,
--     taking no mouse; a name is pulled in from the cell's edge to make
--     room, which moves a font string and writes no value.
--   * What Hound knows about a row is kept in its own tables, by row,
--     never on the row.
--   * Hover lines go on Blizzard's own tooltip for the row, from the
--     item tooltip's post-call, which the client makes securely.
--   * A list is never told to redraw: Hound repaints its own frames.
local ADDON, H = ...

local UI = H.UI
local House = {
  rows = setmetatable({}, { __mode = "k" }),     -- row -> { kind, rowData, cell, index }
  overlays = setmetatable({}, { __mode = "k" }), -- cell -> Hound's frame on it
  hooked = setmetatable({}, { __mode = "k" }),   -- rows whose double-click Hound answers
  tips = {},                                     -- kind -> fn(tooltip, rowData)
  doubles = {},                                  -- kind -> fn(rowData, row)
}
UI.House = House

-- True when frame sits somewhere under ancestor. A cell sits on its
-- row, the row on the scroll box's target, the target on the box and
-- the box on the list; a cell's own owner field is no guide, since the
-- name cells never get one.
function House.Under(frame, ancestor)
  if type(frame) ~= "table" or type(ancestor) ~= "table" then return false end
  local f = frame
  for _ = 1, 12 do
    if f == ancestor then return true end
    if type(f.GetParent) ~= "function" then return false end
    f = f:GetParent()
    if type(f) ~= "table" then return false end
  end
  return false
end

-- Runs fn(cell, ...) after a method of one of Blizzard's cell mixins,
-- for every cell made from the mixin from then on: the mixin is copied
-- into each cell as it is made, hook included. An error is said once
-- and that hook goes quiet, so a cell of Blizzard's never stops on
-- Hound's account. Returns whether the method was there to hook.
function House.HookCells(mixinName, method, what, fn)
  local mixin = _G[mixinName]
  if type(mixin) ~= "table" or type(mixin[method]) ~= "function" then return false end
  local broken = false
  hooksecurefunc(mixin, method, function(...)
    if broken then return end
    local ok, err = pcall(fn, ...)
    if not ok then
      broken = true
      H.Print(string.format("the %s stopped on an error, /reload to try again: %s", what, tostring(err)))
    end
  end)
  return true
end

-- Pulls a name cell's text in from the cell's right edge, so Hound's
-- frame there does not sit on it. The text is anchored to that edge
-- again whenever the name is drawn, so this follows every draw; the
-- truncation marker hangs from the same edge and moves too.
function House.MakeRoom(cell, width)
  if type(cell.Text) == "table" and cell.Text.SetPoint then
    cell.Text:SetPoint("RIGHT", cell, "RIGHT", -width, 0)
  end
  if type(cell.ExtraInfo) == "table" and cell.ExtraInfo.SetPoint then
    cell.ExtraInfo:SetPoint("RIGHT", cell, "RIGHT", -width, 0)
  end
end

-- Hound's frame on a cell, made by build(cell) the first time.
function House.Overlay(cell, build)
  local o = House.overlays[cell]
  if not o then
    o = build(cell)
    House.overlays[cell] = o
  end
  return o
end

-- Left button only: the rows take the right button too, for Blizzard's
-- favorites menu.
local function onDoubleClick(row, button)
  if button and button ~= "LeftButton" then return end
  local t = House.rows[row]
  local fn = t and House.doubles[t.kind]
  if fn then fn(t.rowData, row) end
end

-- The row a cell sits on, noted with what it shows and where it sits
-- in the list's data. Returns the row.
function House.Track(cell, kind, rowData, index)
  local row = type(cell) == "table" and cell.GetParent and cell:GetParent()
  if type(row) ~= "table" then return nil end
  local t = House.rows[row]
  if not t then
    t = {}
    House.rows[row] = t
  end
  t.kind, t.rowData, t.cell, t.index = kind, rowData, cell, index
  if not House.hooked[row] then
    House.hooked[row] = true
    if row.GetScript and row:GetScript("OnDoubleClick") then
      row:HookScript("OnDoubleClick", onDoubleClick)
    elseif row.SetScript then
      row:SetScript("OnDoubleClick", onDoubleClick)
    end
  end
  return row
end

function House.RowInfo(row)
  return House.rows[row]
end

-- fn(cell, rowData, row) for every row of a kind on screen, top first,
-- as the list itself fills them.
function House.Each(kind, fn)
  local shown = {}
  for row, t in pairs(House.rows) do
    if t.kind == kind and row.IsVisible and row:IsVisible() then table.insert(shown, row) end
  end
  table.sort(shown, function(a, b) return (House.rows[a].index or 0) < (House.rows[b].index or 0) end)
  for _, row in ipairs(shown) do
    local t = House.rows[row]
    fn(t.cell, t.rowData, row)
  end
end

function House.OnDoubleClick(kind, fn)
  House.doubles[kind] = fn
end

function House.OnTooltip(kind, fn)
  House.tips[kind] = fn
end

-- Called from the item tooltip's post-call: a tooltip Blizzard set up
-- for one of the rows gets the lines that row's kind adds.
function House.AddTooltipLines(tooltip)
  local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
  local t = owner and House.rows[owner]
  local fn = t and House.tips[t.kind]
  if fn then fn(tooltip, t.rowData) end
end
