# Auction Hound

A slim auction house companion for World of Warcraft: Forever. It keeps
price history, finds listings that are actually deals, and shows how
items connect through crafting. Built for one flipper's taste, with a
classic look, on the modern auction house API.

Status: solo prototype. The logic is covered by a headless test suite;
the client integration still needs its first session in the beta (see
the checklist below).

## What it does

- **History.** A full scan at the auction house records every listing.
  Each item keeps daily aggregates for 90 days and the last 120 scan
  points. Records are stored as compact strings so login stays fast.
- **Market value.** A robust estimate from the cheapest slice of units
  with outliers trimmed, then decay-weighted over two weeks. A wall of
  expensive listings or a single one-copper unit does not move it.
- **Snipe.** Browses the AH for floors under reference, confirms the best
  candidates with a targeted search, and scores each from one to five
  with plain-language reasons: thin history, falling price, dead market,
  recent spike, single unit, vendor flip. Buys commodities with a
  re-quote check and items by auction id.
- **Priors.** When history is thin, vendor price, crafted cost and value
  as a crafting input stand in as the reference. That is what makes the
  snipe usable in launch week.
- **Connections.** Smelting, leather, hides and bolts, with input cost,
  output value, spread per craft and gold per hour at your labor rate.
- **Tooltips.** Market, floor, 30-day mean, trend and estimated units
  moved per day on every item tooltip.
- **UI.** A tab inside the Blizzard auction house frame (or `/hound` for
  a window) with three views: Snipe, Markets, Item. Sortable tables, a
  bar graph of daily value with floor and volume, sparklines per row.

Deferred on purpose: guild sync, the neutral auction house, disenchant
tables, own-sales tracking.

## Install

1. Copy or clone this repository into
   `World of Warcraft/_classic_beta_/Interface/AddOns/AuctionHound`.
   The folder name must be `AuctionHound` to match the TOC.
2. Enable it on the character screen. It targets interface 16001.
3. In game, `/hound` opens the window; the Hound tab appears in the
   auction house.

## First session checklist

The addon was written against the documented retail 12.x auction house
API and tested headlessly. Please verify these in the beta before
trusting the numbers:

1. Open the auction house, run `/hound scan`. Then `/hound debug rep 5`
   prints raw rows. Check that row `[0]` exists (indices are 0-based) and
   whether `buyout` for a stack is the total or the per-unit price. If it
   is per unit, set `Scan.REPLICATE_BUYOUT_IS_TOTAL = false` in
   `Scan.lua`.
2. Compare `/hound key <link>` for an "of the X" green with the key the
   Markets view shows for the same item after a snipe pass. They must
   match, or history and snipe will not line up for gear.
3. Confirm the Hound tab appears and the panel fits inside the frame.
   Adjust `UI.AH_INSETS` at the top of `UI/Frame.lua` if it overlaps the
   title or the money bar.
4. Run a snipe pass and buy one cheap commodity. The chat line should
   show the quoted unit price and the ledger entry.
5. `/reload`, then `/hound debug`. The item count must survive.

## Commands

```
/hound                 toggle the window
/hound scan            full scan (once per 15 minutes, at the AH)
/hound snipe           run a snipe pass (at the AH)
/hound stats <link>    stored stats for an item
/hound key <link>      the history key for a link
/hound labor <g/h>     your time, used for gold per hour
/hound cut <pct>       auction house cut, default 5
/hound discount <pct>  minimum discount for a snipe candidate, default 25
/hound debug rep [n]   print raw full-scan rows
/hound wipe            erase this market's history
```

## How the pieces fit

```
Scan.lua     ReplicateItems (full), SendBrowseQuery (floors), SendSearchQuery (listings)
Store.lua    per-market history, compact strings, async flush
Market.lua   value from listings, ladder, stats, confidence
Priors.lua   vendor, crafted cost, value as input, connections economics
Snipe.lua    candidates, confirmation, scoring, buying, ledger
Tooltip.lua  tooltip lines
UI/          table, graph, sparkline, pips; panel, views, AH tab, window
Data/        conversion recipes with classic item ids
```

History is scoped by region, ruleset and faction, for example
`US-ClassicBetaPvP2-Horde`. Commodities are keyed by item id; equippable
items by `id:level:suffix` so suffix variants never share a record.

### Scoring

Every candidate starts at two. Discount of 35 percent adds one, 50
percent adds two. Solid history adds one; thin history, a stale
reference, a falling price, a spike over the 30-day mean, a slow
market, or a single commodity unit each subtract one. Anything with no
margin after the cut scores zero and is dropped. Anything under vendor
price scores five and is labelled a vendor flip. The reasons are shown
under the table when a row is selected.

### Units moved

Blizzard exposes no sales feed. The estimate is the quantity that
vanished between two scans no more than eight hours apart, which is a
lower bound since new listings offset it. It is labelled as an estimate
everywhere and treated as the weakest input.

## Tests

```
lua5.1 test/run.lua        # or: lua5.1 test/run.lua -v
```

`test/wowstub.lua` fakes the client: frames, timers, item info, the
auction house calls and events. `test/run.lua` runs the full scan,
snipe, purchase, tooltip, slash command and UI construction paths.

## Roadmap

- Guild sync over addon messages, with distributed full scans
- Neutral auction house as a second market and cross-faction spreads
- Disenchant tables as a third prior
- Own sales from mail, for exact sale rates on markets you sell in
- Watchlists for targeted snipe passes
- Time-of-day view for the Oceanic overlap
