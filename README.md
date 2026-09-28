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
- **Buy tab.** A Hound column on Blizzard's own browse list: the
  reference for each row and how far the floor sits under it, green
  when it clears the minimum discount, amber under reference, grey
  above. A strip above the headers sorts by discount, keeps only deals,
  only rows with real history, or hides rows holding your own auctions,
  and sets the minimum. With a toggle on, the remaining result pages
  load without scrolling. The usual category tree, search box and
  filters do the narrowing; clicking a row buys through Blizzard's
  frames as always.
- **Auctions tab.** A Total column on Blizzard's list of your auctions:
  buyout times units. Hovering the total shows the house's cut, the
  deposit paid and what is left after both. The Bid column is hidden,
  so item names get its room. The deposit is noted whenever an auction
  is posted, from the Fan view or from Blizzard's own Sell tab, and
  shows in the History view too.
- **Listing ladder.** Clicking a Buy tab row opens Blizzard's buy frame
  for that item, and Hound reads the listings there: an info block with
  the reference, how many units sit at or under the deal limit and
  what they cost, the floor and the next price step, and the value of
  these listings alone. On the commodity list each units figure takes
  the verdict's color, green for a deal and amber under reference; the
  item list gets a discount column. A floor far under the next step is
  flagged in blue as low in the list, reference or not.
- **History.** Every auction of yours the addon has seen, with what
  became of it: active, sold, expired or cancelled, units and gold. Fan
  batches and auctions posted from Blizzard's own Sell tab alike; the
  owned list is read once per visit and anything new is adopted.
- **Auto scan.** A checkbox beside the scan timer starts a full scan
  whenever the house allows one, every fifteen minutes while you stand
  at the auctioneer.
- **Snipe.** The older batch pass: browses the whole AH for floors under
  reference, confirms the best candidates with a targeted search, and
  scores each from one to five with plain-language reasons. Buys
  commodities with a re-quote check and items by auction id. It stays
  until the Buy tab's listing view can do the same job.
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
  likely is, with a few out at the tails. A step of zero posts every
  batch at the same price, which is how to re-list and get back to the
  front of the queue at that price. One click posts one batch. Every
  money column in Hound's tables shows the exact figure down to the
  copper wherever the column has room; only a figure too wide for its
  column drops the copper, then rounds.
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
  a window) with five views. Snipe runs passes and buys. Markets lists
  every item with history. Item is one item in depth: stats, the daily
  graph, anchors, connections and your own sales, reached by
  double-clicking a row elsewhere or typing a name, id or link into its
  find box. Fan plans and posts batches. History lists your auctions
  and their outcomes. Sortable tables, a bar graph of daily value with
  floor and volume, sparklines per row.

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
API and tested headlessly. Each step below exercises one more client
call than the one before. Work down the list in order and report the
first thing that breaks. Anything not marked verified is open, however
plausible it looks.

Found so far in the beta: `GetItemCommodityStatus` wants a bag location,
not an item key (commodity status now comes from `GetItemKeyInfo`); the
auction house frame only moves its tab highlight for its own modes, so
the Hound tab is now selected by hand; the frame's portrait hangs down
the left edge, so the view buttons now start to the right of it.

1. **Open the auction house.** Verified: no error, the Hound tab is
   there. Re-check after the fixes above: the Hound tab stays lit while
   the panel is up, and nothing sits under the portrait. Adjust
   `UI.AH_INSETS` at the top of `AuctionHound/UI/Frame.lua` if anything
   still overlaps.
2. **Full scan.** Open: a scan ran and stored items, but the price
   check has not been done. `/hound debug rep 5` prints raw rows. Check
   that row `[0]` exists (indices are 0-based) and whether `buyout` for
   a stack is the total or the per-unit price. If it is per unit, set
   `Scan.REPLICATE_BUYOUT_IS_TOTAL = false` in `AuctionHound/Scan.lua`.
   The chat summary should report few or no unresolved rows.
3. **Keys.** Open. `/hound key <link>` for an "of the X" green must
   match the key the Markets view shows for the same item after the
   scan, or history and snipe will not line up for gear. For an item
   you have never seen this session the key may print as `nil` once;
   run it again after the item loads.
4. **Tooltips.** Open. Hover a scanned item in your bags: the Hound
   market line appears. Hover something never scanned: no lines, no
   error.
5. **Buy tab.** Open, and new. Pick any category or search: every row
   gets a Hound column, the reference on the left and the discount on
   the right, green for a deal, amber under reference, grey above, and
   "no reference" for an item the addon knows nothing about. Tick
   "Sort by off": deals rise to the top and the count on the right
   climbs as the remaining pages load. Tick "Deals only", then "Not
   mine" with one of your own auctions in the list. Change the minimum
   and watch the colors move. Report if the strip overlaps the column
   headers, if the star column lost its place, or if the list stops
   loading pages (the count says "stopped at N pages" at the cap).
6. **Snipe pass.** Open. Run one and let it finish; the results table
   fills and the status line counts confirmations. Then buy one cheap
   commodity. The chat line should show the quoted unit price and the
   ledger entry. If the client refuses the confirm step without a
   click, the chat says "press Buy again": press it, and report that it
   needed the second click. Then buy one non-commodity (a green) by
   auction id.
7. **Persistence.** Verified: the item count survives `/reload`.
8. **Item view.** Open, and new: with nothing picked it now explains
   itself. Type part of a name in its find box and press Enter; then
   shift-click a link into the box.
9. **Fan, commodity.** Open. Open the Fan tab, pick a cheap commodity
   from your bags, and post one batch (`/hound fan [Copper Ore] 5 5 2`
   then `/hound post` works too). The plan line names it a `commodity`.
   The chat line after posting should name the batch. If posting fails
   with a hardware-event error, bind a key to a macro with `/hound
   post` and post from that.
10. **Fan, item.** Open. Do the same with a green from your bags. The
   plan line names it an `item`, and each batch posts one unit.
11. **Fan, flat.** Open. A step of `0` posts every batch at the center
    price. Post two batches of the same commodity that way and confirm
    the Blizzard Auctions tab shows two separate auctions at one price.
12. **Your posts.** Open. Open the Blizzard Auctions tab, then the Fan
    view: the batches show as active in the "Your posts" table. Cancel
    one from the Blizzard tab; it should flip to cancelled.
13. **Sales.** Open. Sell something. The next time you open the auction
    house (or check your mail with the addon loaded), the Fan view and
    `/hound stats` should show it under "yours".
14. **Auctions tab total.** Open, and new. On Blizzard's Auctions tab
    the columns read Name, Buyout, Total, Time Left: the Bid column is
    gone. For a commodity stack the total must read units times the
    unit price shown beside it. If this client lets a non-commodity
    stack, post one and report whether its Buyout column shows the unit
    price or the whole stack; the total assumes the unit price. Hover
    a row anywhere along it, and again over the total: the row should
    light up both times without an error.
15. **Auto scan.** Open, and new. Tick "auto scan" at the right of the
    status line. With the timer at zero a scan starts at once; leave
    the house open and the next one should start by itself when the
    timer runs out. Untick it and confirm nothing starts.
16. **History.** Open, and new. Open the History view. Every auction
    you have up should be listed as active, including ones posted from
    Blizzard's Sell tab, after the house has been open a few seconds.
    Sell, cancel or let one expire, and the row should change on the
    next visit. The line at the top sums the last thirty days. Post
    something from Blizzard's Sell tab and its Deposit column should
    fill in once the house lists it.
17. **Auctions tab cut and deposit.** Open, and new. Hover a total:
    the tooltip names the cut, the deposit for anything posted while
    the addon was loaded (and says so when it was not), and what is
    left. A click on the total should still select the row.
18. **Listing ladder.** Open, and new. Click a commodity row on the Buy
    tab: under the Buy button a four-line block should name the
    reference, the units at or under the limit, the floor and next
    step, and the value of the listings; the units figures in the list
    should turn green for deals and amber under reference. Click a
    non-commodity row: the block sits between the item header and the
    auction list, and a Hound column shows each auction's discount.
    Report if the block overlaps the Buy button or the item header, or
    if the list's headers sit under the block.

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
/hound discount <pct>  minimum discount for a deal, on the Buy tab and in passes, default 25
/hound debug rep [n]   print raw full-scan rows
/hound wipe            erase this market's history (your own posts are kept)
```

A fan by example: `/hound fan [Copper Ore] 10 5 5 bell` posts five
batches of ten, five percent apart, bunched toward the center. Center
defaults to the best price you sold the item for in the last two weeks,
else the market value; `above` or `below` puts the center at the cheap
or the dear end instead of the middle. A step of `0` puts every batch at
the center price. Then `/hound post` five times, or click Post in the
Fan view. Blizzard requires a hardware event for each auction, so
batches never post on their own.

## How the pieces fit

The addon lives in `AuctionHound/`; `test/` and this file sit beside it.

```
Scan.lua     ReplicateItems (full), SendBrowseQuery (floors), SendSearchQuery (listings)
Store.lua    per-market history, compact strings, async flush
Market.lua   value from listings, ladder, stats, confidence
Priors.lua   vendor, crafted cost, value as input, connections economics
Snipe.lua    candidates, confirmation, scoring, buying, ledger
Browse.lua   the Buy tab's read of each row: reference, discount, verdict, order
Ladder.lua   one item's listings read against the reference: deal depth, next step, strays
Fan.lua      fan plans (linear or bell), posting, own-sales tracking
Tooltip.lua  tooltip lines
UI/          table, graph, sparkline, pips; panel, views, AH tab, window;
             the Buy tab column and filter strip, the buy frames' ladder
             block and colors, the Auctions tab total column (Cells.xml
             holds the cells)
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
in TOC order; XML files are read for the mixin and font strings each
template declares, so a cell template and its mixin must agree.
`test/run.lua` runs the full scan, auto scan, snipe, purchase, tooltip,
slash command, Buy tab column and filter, listing ladder, Auctions tab
column, deposit notes, auction adoption and history, and UI
construction paths. Where the beta has
corrected a call's signature, the stub enforces it, so the mistake
cannot come back quietly.

## Roadmap

- Buy tab: depth on demand for the rows on screen, one throttled
  search each, so the browse list can show units at the floor
- Retire the snipe pass once the Buy tab covers its buying
- Guild sync over addon messages, with distributed full scans
- Neutral auction house as a second market and cross-faction spreads
- Disenchant tables as a third prior
- Own sales from mail, for exact sale rates on markets you sell in
- Watchlists for targeted snipe passes
- Time-of-day view for the Oceanic overlap
