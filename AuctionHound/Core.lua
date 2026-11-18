-- Core.lua: saved variables, settings, market scoping, slash commands.
local ADDON, H = ...

H.DEFAULTS = {
  cut = 0.05,            -- auction house cut on the faction AH
  minDiscount = 0.25,    -- a floor this far under reference counts as a deal
  minSaving = 0,         -- and at least this many copper a unit under it; 0 is no such floor
  autoScan = false,      -- start a full scan whenever one is allowed at the AH
  dealsSource = "house", -- Deals view: "house", the house's search results; "scan", the last full scan
  dealsOnly = true,      -- Deals view: only the rows that are deals
  dealsHistory = false,  -- Deals view: only rows judged against market history
  dealsHideMine = false, -- Deals view: leave out rows with an auction of yours
  dealsQuality = 0,      -- Deals view: the lowest quality shown; 0 shows all
  dealsClass = -1,       -- Deals view: the item class shown; -1 shows all
  dealsMaxPrice = 0,     -- Deals view: the dearest floor shown, copper a unit; 0 for no cap
  plainMoney = false,    -- text money instead of coin icons
  tooltip = true,        -- add Hound lines to item tooltips
  overlay = true,        -- hold Shift with the bags or bank open: each slot's worth, at the house or the vendor
  keepDays = 90,         -- daily history retention
  keepPoints = 120,      -- scan-level points kept per item
  fanPerBatch = 5,       -- units per batch when fanning a listing
  fanStep = 0.05,        -- price gap between batches, fraction of the start price
  fanBatches = 5,        -- batches per fan
  postDuration = 3,      -- 1 = 12h, 2 = 24h, 3 = 48h
}

-- Settings and saved data of features since taken out: dropped from
-- the saved file the first time this version loads.
H.RETIRED_SETTINGS = { "estimates", "laborPerHour", "satHours", "browseDepth", "fanShape", "fanSpread" }

H.atAH = false

function H.Settings()
  return AuctionHoundDB and AuctionHoundDB.settings or H.DEFAULTS
end

-- One history per region, ruleset and faction. Forever is realmless, so
-- the realm name is the ruleset name. A neutral house keeps none
-- (H.Neutral).
function H.MarketKey()
  local region = "XX"
  if GetCurrentRegion then
    local names = { "US", "KR", "EU", "TW", "CN" }
    region = names[GetCurrentRegion() or 0] or ("R" .. tostring(GetCurrentRegion()))
  end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
  realm = string.gsub(realm, "[%s%-]", "")
  local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
  return region .. "-" .. realm .. "-" .. faction
end

-- The character playing, as "Name-Realm": the one whose auctions the
-- owned list shows and whose mail the mailbox holds. Every character of
-- a realm and faction shares the market and its posts, and each post
-- notes whose it is. Nil while the client has no name for the player.
function H.Who()
  local name = UnitName and UnitName("player")
  if type(name) ~= "string" or name == "" then return nil end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  return name .. "-" .. string.gsub(realm, "[%s%-]", "")
end

------------------------------------------------------------------------
-- Which house is open. The goblin towns' houses, in Booty Bay,
-- Gadgetzan and Everlook, are neutral: both factions' goods, at prices
-- of their own, for a cut of 15%. Taking their listings into this
-- faction's history confused its numbers, so at a neutral house Hound
-- keeps nothing: no scan, no floor, no post and no purchase is saved
-- (Store.lua drops any that gets that far). What it shows there is this
-- faction's numbers beside the neutral house's own listings: the
-- figures on the Buy tab and in the Deals view are the neutral price
-- against this faction's history.
--
-- Known by the auctioneer: a faction house's are the city's, Alliance
-- or Horde, and a neutral house's are neither. When the client names no
-- auctioneer, by the town. /hound house says which, and can set it for
-- the visit.
------------------------------------------------------------------------
H.NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
H.NEUTRAL_CUT = 0.15

-- "faction" or "neutral", and how that was told.
function H.DetectHouse()
  if UnitExists and UnitExists("npc") and UnitFactionGroup then
    local f = UnitFactionGroup("npc")
    if f == "Alliance" or f == "Horde" then return "faction", "the auctioneer is " .. f end
    return "neutral", "the auctioneer is neither Alliance nor Horde"
  end
  for _, fn in ipairs({ GetSubZoneText, GetMinimapZoneText, GetZoneText }) do
    local zone = type(fn) == "function" and fn() or nil
    if zone and H.NEUTRAL_TOWNS[zone] then return "neutral", "the house is in " .. zone end
  end
  return "faction", "no auctioneer named, and not in a neutral town"
end

-- True at a neutral house.
function H.Neutral()
  return H.atAH and H.house == "neutral" or false
end

-- The house's cut of a sale: the neutral house's there, else the
-- setting.
function H.Cut()
  if H.Neutral() then return H.NEUTRAL_CUT end
  return H.Settings().cut or 0
end

H.NEUTRAL_NOTE = "a neutral house: Hound keeps nothing from here, and its figures are this house's listings against your faction's prices (/hound house)"

function H.InitDB()
  if type(AuctionHoundDB) ~= "table" then AuctionHoundDB = {} end
  local db = AuctionHoundDB
  db.version = db.version or 1
  db.settings = db.settings or {}
  for k, v in pairs(H.DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  for _, k in ipairs(H.RETIRED_SETTINGS) do db.settings[k] = nil end
  db.markets = db.markets or {}
  db.names = db.names or {}
  db.lastFull = db.lastFull or 0
  H.marketKey = H.MarketKey()
  db.markets[H.marketKey] = db.markets[H.marketKey] or { items = {}, scans = {} }
  H.market = db.markets[H.marketKey]
  H.market.posts = H.market.posts or {}
  H.db = db
  local purged = H.Fan and H.Fan.PurgeInferred(db) or 0
  if purged > 0 then
    H.Printf("%d auction%s once counted as sold for leaving the house early no longer count; only a sale's mail does",
      purged, purged == 1 and "" or "s")
  end
  -- the ledger was written and never read; the purge above was its last use
  db.ledger = nil
  if (db.version or 1) < 2 then
    if H.Store then H.Store.DropMoved(db) end
    db.version = 2
  end
  return db
end

------------------------------------------------------------------------
-- Lifecycle events
------------------------------------------------------------------------
H.RegisterEvent("ADDON_LOADED", function(name)
  if name == ADDON then
    H.InitDB()
    H.Events:Fire("DB_READY")
  elseif name == "Blizzard_AuctionHouseUI" then
    H.Events:Fire("AH_UI_LOADED")
  end
end)

H.RegisterEvent("PLAYER_LOGIN", function()
  if not H.db then H.InitDB() end
  H.Events:Fire("LOGIN")
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    H.Events:Fire("AH_UI_LOADED")
  elseif IsAddOnLoaded and IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    H.Events:Fire("AH_UI_LOADED")
  end
end)

H.RegisterEvent("PLAYER_LOGOUT", function()
  if H.Store then H.Store.Flush() end
end)

H.RegisterEvent("AUCTION_HOUSE_SHOW", function()
  H.house, H.houseWhy = H.DetectHouse()
  H.atAH = true
  if H.house == "neutral" then H.Print(H.NEUTRAL_NOTE) end
  H.Events:Fire("AH_OPENED")
end)

H.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
  H.atAH = false
  H.house, H.houseWhy = nil, nil
  H.Events:Fire("AH_CLOSED")
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function linkFromArgs(rest)
  local link = string.match(rest or "", "(|c%x+|Hitem:[^|]+|h%[[^%]]*%]|h|r)")
  if link then return link end
  local id = tonumber(rest)
  if id then return "item:" .. id, id end
  return nil
end

local commands = {}

commands.help = function()
  H.Print("commands:")
  H.Print("  /hound            toggle the window")
  H.Print("  /hound scan       full scan (at the auction house)")
  H.Print("  /hound stats <link or id>   show stored stats")
  H.Print("  /hound key <link>           show the history key for a link")
  H.Print("  /hound crate <link or id>   price the bundles that fill a Waylaid Crate")
  H.Print("  /hound writ <link or id>    price the item a Craftsman's Writ asks for")
  H.Print("  /hound fan <link> [per batch] [step %] [batches] [start price, e.g. 1g20s] [12h|24h|48h]")
  H.Print("                    plan a fan of auctions for an item in your bags; alone, show the current plan")
  H.Print("  /hound post       post the next batch of the fan (bind it to a key)")
  H.Print("  /hound vendor [count] <link, id or name>   at a vendor, buy any number at once (or Alt-click the item)")
  H.Print("  /hound cut <percent>        the house's cut, default 5")
  H.Print("  /hound discount [percent] [copper a unit]   the minimum a deal clears, e.g. 25 5s")
  H.Print("  /hound overlay [on|off|test]  hold Shift with the bags or bank open to see what each slot is worth")
  H.Print("  /hound debug rep [n]        print raw full-scan rows")
  H.Print("  /hound debug buy [n]        print the Buy tab's first rows: the house's key, the history key, the reference")
  H.Print("  /hound markets    list the markets stored: each region, realm and faction played")
  H.Print("  /hound house [faction|neutral]   which house this is; a neutral one keeps nothing")
  H.Print("  /hound wipe [market]   erase this market's history (your own posts are kept), or another market whole")
end

commands.fan = function(rest)
  local Fan = H.Fan
  if not rest or rest == "" then Fan.Describe() return end
  local link, id = linkFromArgs(rest)
  if not link then
    id = tonumber(string.match(rest, "^%s*(%d+)"))
    if id then link = "item:" .. id end
  end
  if not link then H.Print("usage: /hound fan <item link or id> [per batch] [step %] [batches] [start price] [12h|24h|48h]") return end
  local tail
  if id then
    tail = string.gsub(rest, "^%s*%d+", "", 1)
  else
    tail = string.gsub(rest, "|c%x+|Hitem:[^|]+|h%[[^%]]*%]|h|r", "", 1)
  end
  local key = id and (H.KeyForItemID(id) or tostring(id)) or H.KeyFromLink(link)
  if not key then H.Print("could not read that link") return end
  local o = { key = key, itemID = H.ItemIDFromKey(key) }
  local nums = {}
  for tok in string.gmatch(tail, "%S+") do
    local l = string.lower(tok)
    local hours = string.match(l, "^(%d+)h$")
    if hours then
      local h = tonumber(hours)
      o.duration = h <= 12 and 1 or (h <= 24 and 2 or 3)
    elseif string.match(l, "^[%d%.]+%%$") then
      table.insert(nums, tonumber(string.match(l, "^([%d%.]+)%%$")))
    elseif tonumber(l) then
      table.insert(nums, tonumber(l))
    elseif string.match(l, "^[%d%.]+[gsc]") then
      o.start = H.ParseMoney(l)
    end
  end
  if nums[1] then o.perBatch = nums[1] end
  if nums[2] then o.step = nums[2] / 100 end
  if nums[3] then o.batches = nums[3] end
  local plan, err = Fan.Setup(o)
  if not plan then H.Print(err) return end
  Fan.Describe()
  if H.UI and H.UI.ShowFan and H.UI.IsShown and H.UI.IsShown() then H.UI.ShowFan(key) end
end

commands.post = function()
  H.Fan.PostNext()
end

-- At a vendor: the bulk-buy box for an item, the count filled in.
commands.vendor = function(rest)
  H.UI.Vendor.Command(rest)
end

commands.scan = function()
  if H.Scan then H.Scan.StartFull() end
end

commands.stats = function(rest)
  local link, id = linkFromArgs(rest)
  if not link then H.Print("usage: /hound stats <item link or id>") return end
  local key = id and tostring(id) or H.KeyFromLink(link)
  if not key then H.Print("could not read that link") return end
  local rec = H.Store.Get(key)
  local cl = H.Market.Clearing(H.Store.Posts(key))
  if not rec and not cl then H.Printf("no history for %s", key) return end
  H.Printf("%s [%s]", H.ItemName(H.ItemIDFromKey(key)), key)
  if rec then
    local st = H.Market.Stats(rec)
    H.Printf("  market %s  floor %s (%s)  listed %s  trend %s",
      H.Money(st.market or 0), H.Money(st.floor or 0), H.Ago(st.floorAge),
      tostring(st.qty or 0), H.Pct(st.trend, true))
    H.Printf("  %d days, %d scans, last %s", st.days, st.samples, H.Ago(st.age))
    local cleared = H.Market.ClearedLine(st)
    if cleared then H.Printf("  %s (units gone between scans before they could expire)", cleared) end
  end
  if cl then H.Printf("  yours: %s", H.Fan.ClearingLine(cl)) end
end

commands.key = function(rest)
  local link = linkFromArgs(rest)
  if not link then H.Print("usage: /hound key <item link>") return end
  H.Printf("key for %s is %s", link, tostring(H.KeyFromLink(link)))
end

-- A Waylaid Crate's bundles, priced, as its tooltip shows them. For an
-- item the data does not know as a crate it prints the item's ID, which
-- is what to report when a crate's tooltip shows no Hound lines.
commands.crate = function(rest)
  local link, id = linkFromArgs(rest)
  id = id or (link and tonumber(string.match(link, "item:(%d+)")))
  if not id then H.Print("usage: /hound crate <crate link or id>") return end
  H.Crate.Describe(id)
end

-- A Craftsman's Writ's item, priced, as its tooltip shows it, or the
-- ID of an item the data does not know as a writ.
commands.writ = function(rest)
  local link, id = linkFromArgs(rest)
  id = id or (link and tonumber(string.match(link, "item:(%d+)")))
  if not id then H.Print("usage: /hound writ <writ link or id>") return end
  H.Writ.Describe(id)
end

commands.cut = function(rest)
  local v = tonumber(rest)
  if not v then H.Printf("cut is %d%%", H.Settings().cut * 100) return end
  H.Settings().cut = v / 100
  H.Printf("cut set to %d%%", v)
end

-- The minimum a deal must clear: a percentage off the reference, and
-- copper a unit under it, whichever is more. The copper floor is what
-- keeps a three-copper item at half price off the deals: it is fifty
-- percent under, and not worth the click.
local function minimumLine(S)
  local line = string.format("%d%%", H.Round((S.minDiscount or 0) * 100))
  if (S.minSaving or 0) > 0 then
    line = line .. string.format(" or %s a unit, whichever is more", H.MoneyExact(S.minSaving))
  end
  return line
end

commands.discount = function(rest)
  local S = H.Settings()
  local pct, saving
  for tok in string.gmatch(rest or "", "%S+") do
    local l = string.lower(tok)
    local p = tonumber(string.match(l, "^([%d%.]+)%%?$"))
    local c = string.match(l, "^[%d%.]+[gsc]") and H.ParseMoney(l)
    if p then
      pct = p / 100
    elseif c then
      saving = c
    else
      H.Print("usage: /hound discount [percent] [copper a unit, e.g. 5s]")
      return
    end
  end
  if pct or saving then
    if pct then S.minDiscount = pct end
    if saving then S.minSaving = saving end
    H.Printf("minimum discount set to %s", minimumLine(S))
    H.Events:Fire("SETTINGS_CHANGED", "minDiscount")
  else
    H.Printf("minimum discount is %s", minimumLine(S))
  end
end

commands.overlay = function(rest)
  local S = H.Settings()
  local v = string.lower(rest or "")
  if v == "test" then
    H.Bags.StartTest()
    return
  elseif v == "on" or v == "off" then
    S.overlay = v == "on"
    H.Events:Fire("SETTINGS_CHANGED", "overlay")
  elseif v ~= "" then
    H.Print("usage: /hound overlay [on|off|test]")
    return
  end
  if S.overlay then
    H.Print("the bag overlay is on: hold Shift with the bags or bank open to see what each slot is worth")
  else
    H.Print("the bag overlay is off")
  end
  if v == "" and H.Bags then H.Bags.Report() end
end

-- Every market in the saved file: this one, and any other realm,
-- faction or region played. A market from the beta comes along if its
-- saved variables were copied to the live game, and is never read
-- again; /hound wipe <market> drops one by name.
commands.markets = function()
  local keys = {}
  for key in pairs(H.db.markets) do table.insert(keys, key) end
  table.sort(keys)
  H.Printf("%d market%s stored:", #keys, #keys == 1 and "" or "s")
  for _, key in ipairs(keys) do
    local m = H.db.markets[key]
    local items = 0
    if key == H.marketKey then
      items = H.Store.Count()
    else
      for _ in pairs(m.items or {}) do items = items + 1 end
    end
    local last = m.scans and m.scans[#m.scans]
    H.Printf("  %s: %d items, %s%s", key, items,
      last and ("last scan " .. H.Ago(H.Now() - last.t)) or "never scanned",
      key == H.marketKey and " (this one)" or "")
  end
end

-- Alone, erases this market's history and keeps your posts. With the
-- name of another market, drops that market whole, posts and all:
-- there is no one left to show them to.
commands.wipe = function(rest)
  if rest and rest ~= "" and rest ~= H.marketKey then
    if not H.db.markets[rest] then
      H.Printf("no market named %s; /hound markets lists them", rest)
      return
    end
    H.db.markets[rest] = nil
    H.Printf("market %s erased, with its posts and purchases", rest)
    return
  end
  H.Store.Wipe()
  H.Printf("history for %s erased", H.marketKey)
end

-- Which house is open and how Hound told; with "faction" or "neutral",
-- that is what it is until you leave, should the auctioneer mislead.
commands.house = function(rest)
  local v = string.lower(rest or "")
  if v ~= "" and v ~= "faction" and v ~= "neutral" then
    H.Print("usage: /hound house [faction|neutral]")
    return
  end
  if not H.atAH then
    H.Print("not at an auction house")
    return
  end
  if v ~= "" and v ~= H.house then
    H.house, H.houseWhy = v, "you said so, until you leave"
    H.Events:Fire("HOUSE_CHANGED")
  end
  if H.house == "neutral" then
    H.Printf("%s (%s)", H.NEUTRAL_NOTE, H.houseWhy or "")
  else
    H.Printf("your faction's house: Hound keeps its prices (%s)", H.houseWhy or "")
  end
end

commands.debug = function(rest)
  local what, n = strsplit(" ", rest or "")
  if what == "rep" then
    H.Scan.DebugReplicate(tonumber(n) or 5)
  elseif what == "buy" then
    H.Browse.Debug(tonumber(n) or 5)
  else
    H.Printf("market %s, %d items, at AH: %s, scan state: %s",
      H.marketKey, H.Store.Count(), tostring(H.atAH), H.Scan and H.Scan.state or "?")
  end
end

function H.SlashCommand(msg)
  msg = msg or ""
  local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" then
    if H.UI and H.UI.Toggle then H.UI.Toggle() else commands.help() end
    return
  end
  local fn = commands[string.lower(cmd)]
  if fn then fn(rest) else commands.help() end
end

SLASH_HOUND1 = "/hound"
SLASH_HOUND2 = "/ahound"
SlashCmdList["HOUND"] = H.SlashCommand
