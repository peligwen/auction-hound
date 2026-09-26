-- Core.lua: saved variables, settings, market scoping, slash commands.
local ADDON, H = ...

H.DEFAULTS = {
  cut = 0.05,            -- auction house cut on the faction AH
  minDiscount = 0.25,    -- snipe candidates must sit at least this far under reference
  snipePages = 40,       -- browse pages per snipe pass
  confirmTop = 12,       -- candidates confirmed with a targeted search per pass
  laborPerHour = 50,     -- gold per hour, used for conversion profit per hour
  plainMoney = false,    -- text money instead of coin icons
  tooltip = true,        -- add Hound lines to item tooltips
  keepDays = 90,         -- daily history retention
  keepPoints = 120,      -- scan-level points kept per item
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
  H.Print("  /hound snipe      run a snipe pass (at the auction house)")
  H.Print("  /hound stats <link or id>   show stored stats")
  H.Print("  /hound key <link>           show the history key for a link")
  H.Print("  /hound labor <gold per hour> / cut <percent> / discount <percent>")
  H.Print("  /hound debug rep [n]        print raw full-scan rows")
  H.Print("  /hound wipe       erase this market's history")
end

commands.scan = function()
  if H.Scan then H.Scan.StartFull() end
end

commands.snipe = function()
  if H.Snipe then H.Snipe.Run() end
end

commands.stats = function(rest)
  local link, id = linkFromArgs(rest)
  if not link then H.Print("usage: /hound stats <item link or id>") return end
  local key = id and tostring(id) or H.KeyFromLink(link)
  if not key then H.Print("could not read that link") return end
  local rec = H.Store.Get(key)
  if not rec then H.Printf("no history for %s", key) return end
  local st = H.Market.Stats(rec)
  H.Printf("%s [%s]", H.ItemName(H.ItemIDFromKey(key)), key)
  H.Printf("  market %s  min %s  30d %s  listed %s  trend %s  stability %s",
    H.Money(st.market or 0), H.Money(st.min or 0), H.Money(st.hist or 0),
    tostring(st.qty or 0), H.Pct(st.trend, true), H.Pct(st.stab))
  H.Printf("  %d days, %d scans, last %s, moved ~%s/day",
    st.days, st.samples, H.Ago(st.age), st.moved and H.Round(st.moved) or "?")
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

commands.discount = function(rest)
  local v = tonumber(rest)
  if not v then H.Printf("minimum snipe discount is %d%%", H.Settings().minDiscount * 100) return end
  H.Settings().minDiscount = v / 100
  H.Printf("minimum snipe discount set to %d%%", v)
end

commands.wipe = function()
  H.Store.Wipe()
  H.Printf("history for %s erased", H.marketKey)
end

commands.debug = function(rest)
  local what, n = strsplit(" ", rest or "")
  if what == "rep" then
    H.Scan.DebugReplicate(tonumber(n) or 5)
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
