# Auction Hound

A slim auction house companion for World of Warcraft: Forever. It keeps
price history, finds listings that are actually deals, and shows how
items connect through crafting. Built for one flipper's taste, with a
classic look, on the modern auction house API.

Status: solo prototype. The logic is covered by a headless test suite.
The client integration is being checked in the beta one step at a time;
the checklist below is where that stands.

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
- **Fan.** Post one item as a series of batches at spaced prices: x
  units per batch, z batches, y percent apart. Scans only show what
  sellers ask; the one sure sign of what buyers pay is a sale of your
  own, so each batch is a probe. Linear spacing puts the batches at even
  steps. Bell spacing keeps the same range but places them at normal
  quantiles, so most sit near the center where the clearing price most
  likely is, with a few out at the tails. One click posts one batch.
- **Own sales.** Every batch is tracked. A sold status or a shrinking
  quantity in your auction list, an auction that vanishes before it
  could expire, or a seller invoice in the mailbox each mark units sold
  at that price; an auction that vanishes after its time marks them
  unsold. The result is a sold / unsold bracket per item, shown in the
  Item view, the tooltip and `/hound stats`, and the next fan centers on
  the best price buyers actually paid.
- **Tooltips.** Market, floor, 30-day mean, trend and estimated units
  moved per day on every item tooltip, plus your own sold / unsold line.
- **UI.** A tab inside the Blizzard auction house frame (or `/hound` for
  a window) with four views: Snipe, Markets, Item, Fan. Sortable tables,
  a bar graph of daily value with floor and volume, sparklines per row.

Deferred on purpose: guild sync, the neutral auction house, disenchant
tables.

## Install

1. Copy the `AuctionHound` folder from this repository into
   `World of Warcraft/_classic_beta_/Interface/AddOns/`, so the TOC sits
   at `Interface/AddOns/AuctionHound/AuctionHound.toc`. The folder name
   must stay `AuctionHound` to match the TOC. Everything else in the
   repository (README, tests) stays out of the game folder.
2. Enable it on the character screen. It targets interface 16001.
3. In game, `/hound` opens the window; the Hound tab appears in the
   auction house.

## First session checklist

The addon was written against the documented retail 12.x auction house
API and tested headlessly. The first beta session found one call with
the wrong argument (`GetItemCommodityStatus` wants a bag location, not
an item key; commodity status now comes from `GetItemKeyInfo`). Work
down this list in order and report the first thing that breaks; each
step exercises one more client call than the one before.

1. **Open the auction house.** No error, the Hound tab is there, and the
   panel fits inside the frame. Adjust `UI.AH_INSETS` at the top of
   `AuctionHound/UI/Frame.lua` if it overlaps the title or the money
   bar.
2. **Full scan.** `/hound scan`, then `/hound debug rep 5` prints raw
   rows. Check that row `[0]` exists (indices are 0-based) and whether
   `buyout` for a stack is the total or the per-unit price. If it is per
   unit, set `Scan.REPLICATE_BUYOUT_IS_TOTAL = false` in
   `AuctionHound/Scan.lua`. The chat summary should report few or no
   unresolved rows.
3. **Keys.** `/hound key <link>` for an "of the X" green must match the
   key the Markets view shows for the same item after the scan, or
   history and snipe will not line up for gear. For an item you have
   never seen this session the key may print as `nil` once; run it
   again after the item loads.
4. **Tooltips.** Hover a scanned item in your bags: the Hound market
   line appears. Hover something never scanned: no lines, no error.
5. **Snipe pass.** Run one and let it finish; the results table fills
   and the status line counts confirmations. Then buy one cheap
   commodity. The chat line should show the quoted unit price and the
   ledger entry. If the client refuses the confirm step without a
   click, the chat says "press Buy again": press it, and report that it
   needed the second click. Then buy one non-commodity (a green) by
   auction id.
6. **Persistence.** `/reload`, then `/hound debug`. The item count must
   survive.
7. **Fan, commodity.** Open the Fan tab, pick a cheap commodity from
   your bags, and post one batch (`/hound fan [Copper Ore] 5 5 2` then
   `/hound post` works too). The plan line names it a `commodity`. The
   chat line after posting should name the batch. If posting fails with
   a hardware-event error, bind a key to a macro with `/hound post` and
   post from that.
8. **Fan, item.** Do the same with a green from your bags. The plan
   line names it an `item`, and each batch posts one unit.
9. **Your posts.** Open the Blizzard Auctions tab, then the Fan view:
   the batches show as active in the "Your posts" table. Cancel one from
   the Blizzard tab; it should flip to cancelled.
10. **Sales.** Sell something. The next time you open the auction house
    (or check your mail with the addon loaded), the Fan view and
    `/hound stats` should show it under "yours".

## Commands

```
/hound                 toggle the window
/hound scan            full scan (once per 15 minutes, at the AH)
/hound snipe           run a snipe pass (at the AH)
/hound stats <link>    stored stats for an item, and what you sold it for
/hound key <link>      the history key for a link
/hound fan <link> [per batch] [step %] [batches] [bell|linear] [around|above|below] [center] [12h|24h|48h]
                       plan a fan for an item in your bags; alone, show the plan
/hound post            post the next batch of the fan (bind it to a key)
/hound labor <g/h>     your time, used for gold per hour
/hound cut <pct>       auction house cut, default 5
/hound discount <pct>  minimum discount for a snipe candidate, default 25
/hound debug rep [n]   print raw full-scan rows
/hound wipe            erase this market's history (your own posts are kept)
```

A fan by example: `/hound fan [Copper Ore] 10 5 5 bell` posts five
batches of ten, five percent apart, bunched toward the center. Center
defaults to the best price you sold the item for in the last two weeks,
else the market value; `above` or `below` puts the center at the cheap
or the dear end instead of the middle. Then `/hound post` five times, or
click Post in the Fan view. Blizzard requires a hardware event for each
auction, so batches never post on their own.

## How the pieces fit

The addon lives in `AuctionHound/`; `test/` and this file sit beside it.

```
Scan.lua     ReplicateItems (full), SendBrowseQuery (floors), SendSearchQuery (listings)
Store.lua    per-market history, compact strings, async flush
Market.lua   value from listings, ladder, stats, confidence
Priors.lua   vendor, crafted cost, value as input, connections economics
Snipe.lua    candidates, confirmation, scoring, buying, ledger
Fan.lua      fan plans (linear or bell), posting, own-sales tracking
Tooltip.lua  tooltip lines
UI/          table, graph, sparkline, pips; panel, views, AH tab, window
Data/        conversion recipes with classic item ids
```

History is scoped by region, ruleset and faction, for example
`US-ClassicBetaPvP2-Horde`. Commodities are keyed by item id; equippable
items by `id:level:suffix` so suffix variants never share a record. Your
own posts live in the same market record, as plain tables, for 30 days
after they resolve.

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

From the repository root:

```
lua5.1 test/run.lua        # or: lua5.1 test/run.lua -v
```

`test/wowstub.lua` fakes the client: frames, timers, item info, the
auction house calls and events. It loads the addon from `AuctionHound/`
in TOC order. `test/run.lua` runs the full scan, snipe, purchase,
tooltip, slash command and UI construction paths. Where the beta has
corrected a call's signature, the stub enforces it, so the mistake
cannot come back quietly.

## Roadmap

- Guild sync over addon messages, with distributed full scans
- Neutral auction house as a second market and cross-faction spreads
- Disenchant tables as a third prior
- Own sales from mail, for exact sale rates on markets you sell in
- Watchlists for targeted snipe passes
- Time-of-day view for the Oceanic overlap
