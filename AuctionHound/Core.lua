-- Core.lua: saved variables, settings, market scoping, slash commands.
local ADDON, H = ...

H.DEFAULTS = {
  cut = 0.05,            -- auction house cut on the faction AH
  minDiscount = 0.25,    -- a floor this far under reference counts as a deal
  minSaving = 0,         -- and at least this many copper a unit under it; 0 is no such floor
  satHours = 1,          -- a floor the scans have seen at its price this long is no longer a deal; 0 judges by price alone
  snipePages = 40,       -- Buy tab: result pages fetched on their own with a toggle on
  autoScan = false,      -- start a full scan whenever one is allowed at the AH
  browseSort = false,    -- Buy tab: order rows by discount off reference
  browseDeals = false,   -- Buy tab: only rows under reference by the minimum, percent and copper
  browseHistory = false, -- Buy tab: only rows whose reference is market history
  browseNotMine = false, -- Buy tab: hide rows that hold one of your auctions
  browseDepth = false,   -- Buy tab: search each row on screen for the units at its floor
  estimates = true,      -- crafted cost and value as an input stand in for the reference while history is thin
  laborPerHour = 50,     -- gold per hour, used for conversion profit per hour
  plainMoney = false,    -- text money instead of coin icons
  tooltip = true,        -- add Hound lines to item tooltips
  keepDays = 90,         -- daily history retention
  keepPoints = 120,      -- scan-level points kept per item
  fanPerBatch = 5,       -- units per batch when fanning a listing
  fanStep = 0.05,        -- price gap between batches, fraction of the center
  fanBatches = 5,        -- batches per fan
  fanShape = "linear",   -- linear | bell
  fanSpread = "around",  -- around | above | below the center
  postDuration = 3,      -- 1 = 12h, 2 = 24h, 3 = 48h
}

H.atAH = false

function H.Settings()
  return AuctionHoundDB and AuctionHoundDB.settings or H.DEFAULTS
end

-- One history per region, ruleset and faction. Forever is realmless, so
-- the realm name is the ruleset name; the neutral AH is deferred.
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

function H.InitDB()
  if type(AuctionHoundDB) ~= "table" then AuctionHoundDB = {} end
  local db = AuctionHoundDB
  db.version = db.version or 1
  db.settings = db.settings or {}
  for k, v in pairs(H.DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  db.markets = db.markets or {}
  db.names = db.names or {}
  db.ledger = db.ledger or {}
  db.lastFull = db.lastFull or 0
  H.marketKey = H.MarketKey()
  db.markets[H.marketKey] = db.markets[H.marketKey] or { items = {}, scans = {} }
  H.market = db.markets[H.marketKey]
  H.market.posts = H.market.posts or {}
  H.db = db
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
  H.atAH = true
  H.Events:Fire("AH_OPENED")
end)

H.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
  H.atAH = false
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
  H.Print("  /hound fan <link> [per batch] [step %] [batches] [bell|linear] [around|above|below] [center, e.g. 1g20s] [12h|24h|48h]")
  H.Print("                    plan a fan of auctions for an item in your bags; alone, show the current plan")
  H.Print("  /hound post       post the next batch of the fan (bind it to a key)")
  H.Print("  /hound labor <gold per hour> / cut <percent>")
  H.Print("  /hound discount [percent] [copper a unit]   the minimum a deal clears, e.g. 25 5s")
  H.Print("  /hound sat <hours>          a floor on offer this long is no longer a deal; 0 judges by price alone")
  H.Print("  /hound estimates on|off     crafted cost and value as an input as the reference while history is thin")
  H.Print("  /hound debug rep [n]        print raw full-scan rows")
  H.Print("  /hound debug buy [n]        print the Buy tab's first rows: the house's key, the history key, the reference")
  H.Print("  /hound wipe       erase this market's history (your own posts are kept)")
end

commands.fan = function(rest)
  local Fan = H.Fan
  if not rest or rest == "" then Fan.Describe() return end
  local link, id = linkFromArgs(rest)
  if not link then
    id = tonumber(string.match(rest, "^%s*(%d+)"))
    if id then link = "item:" .. id end
  end
  if not link then H.Print("usage: /hound fan <item link or id> [per batch] [step %] [batches] [bell] [above|below] [center]") return end
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
    if l == "bell" or l == "linear" then
      o.shape = l
    elseif l == "around" or l == "above" or l == "below" then
      o.spread = l
    elseif hours then
      local h = tonumber(hours)
      o.duration = h <= 12 and 1 or (h <= 24 and 2 or 3)
    elseif string.match(l, "^[%d%.]+%%$") then
      table.insert(nums, tonumber(string.match(l, "^([%d%.]+)%%$")))
    elseif tonumber(l) then
      table.insert(nums, tonumber(l))
    elseif string.match(l, "^[%d%.]+[gsc]") then
      o.center = H.ParseMoney(l)
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
    H.Printf("  market %s  min %s  30d %s  listed %s  trend %s  stability %s",
      H.Money(st.market or 0), H.Money(st.min or 0), H.Money(st.hist or 0),
      tostring(st.qty or 0), H.Pct(st.trend, true), H.Pct(st.stab))
    H.Printf("  %d days, %d scans, last %s, moved ~%s/day",
      st.days, st.samples, H.Ago(st.age), st.moved and H.Round(st.moved) or "?")
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

commands.labor = function(rest)
  local v = tonumber(rest)
  if not v then H.Printf("labor is %d gold per hour", H.Settings().laborPerHour) return end
  H.Settings().laborPerHour = v
  H.Printf("labor set to %d gold per hour", v)
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

-- Sat: a floor the scans have seen at the same price for this long
-- has been passed over by every buyer since, so it is under the
-- reference but no longer a deal. Zero judges by price alone.
commands.sat = function(rest)
  local S = H.Settings()
  local v = tonumber(rest)
  if v then
    S.satHours = math.max(0, v)
    H.Events:Fire("SETTINGS_CHANGED", "satHours")
  elseif rest and rest ~= "" then
    H.Print("usage: /hound sat <hours>")
    return
  end
  if (S.satHours or 0) > 0 then
    H.Printf("a floor on offer for %s hours or more is no longer a deal", tostring(S.satHours))
  else
    H.Print("sat is off: floors are judged by price alone")
  end
end

-- Estimates: with history thin, the crafted cost or the value as an
-- input stands in for the reference. An item whose own price has
-- settled under its crafted cost reads as a deal forever that way, so
-- they can be turned off: the reference is then history, thin or not,
-- or the vendor price.
commands.estimates = function(rest)
  local S = H.Settings()
  local v = string.lower(rest or "")
  if v == "on" or v == "off" then
    S.estimates = v == "on"
    H.Events:Fire("SETTINGS_CHANGED", "estimates")
  elseif v ~= "" then
    H.Print("usage: /hound estimates on|off")
    return
  end
  if S.estimates then
    H.Print("estimates are on: crafted cost and value as an input stand in for the reference while history is thin")
  else
    H.Print("estimates are off: the reference is history or the vendor price, or nothing")
  end
end

commands.wipe = function()
  H.Store.Wipe()
  H.Printf("history for %s erased", H.marketKey)
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
