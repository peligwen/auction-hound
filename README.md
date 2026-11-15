# Auction Hound

A slim auction house companion for World of Warcraft: Forever. It keeps
price history, finds listings that are actually deals, and shows how
items connect through crafting. Built for one flipper's taste, with a
classic look, on the modern auction house API.

Status: solo prototype. The logic is covered by a headless test suite.
The client integration was checked in the beta one step at a time. The
game has since launched (November 4, 2026, patch 1.60.1); the checklist
below is where that stands, and what changed between the beta and
launch is listed at its head.

## What it does

- **History.** A full scan at the auction house records every listing.
  Each item keeps daily aggregates for 90 days and the last 120 scan
  points. Records are stored as compact strings so login stays fast.
  Each scan also keeps its ladders for the next: units gone from a
  price between two scans went to a buyer, unless their time-left
  band says they could have expired in between, and those fills are
  noted per day with what they went for.
- **Market value.** A robust estimate from the cheapest slice of units
  with outliers trimmed, then decay-weighted over two weeks. A wall of
  expensive listings or a single one-copper unit does not move it. The
  reference a floor is judged against is that two-week value or the
  value at the latest scan, whichever is lower: a price that has fallen
  and stayed down sits in the latest scan's cheapest slice long before
  the two-week value follows it. Not while supply is scarce, under a
  quarter of the units usually listed: the few cheap units left are
  then the deals, not the price.
- **Buy tab.** Hound's figures on every row of Blizzard's own browse
  list, at the right end of the item's name: the reference on the
  left, and how far the floor sits under it on the right, green when
  it clears the minimum discount, amber under reference, grey above.
  The list keeps Blizzard's order and its own columns; Hound's figures
  are its own frames laid over the rows (see Taint). Hovering a row
  adds Hound's reading to the row's own tooltip. A strip above the
  headers sets the minimum: a percentage off the reference, and copper
  a unit under it, whichever is more, and counts the rows shown and
  the deals among them. A three-copper item at half price is fifty
  percent off and still not worth the click; with the copper minimum
  at 5s it reads amber, not green, and leaves the deal count, while a
  20s item at half price stays. The row's tooltip names the minimum
  that held it back. Tick "Depth" and each row on screen gets one
  search of its own, one at a time through the house's throttle: the
  note then ends in the units at the floor ("12.3g x40"), and the
  row's tooltip shows its ladder, the units at or under the limit, the
  next price step and the value of the listings. A ladder is kept
  while the row still shows the same floor and count. The ladder's own
  value, the cheapest slice of its units, caps the reference when it
  sits under history, the way the latest scan does: a floor the market
  has moved to reads as the price before the next scan, the note
  showing the listings' value, while a stray under the rest is too few
  units to move it and still reads as a deal. Not while supply is
  scarce, when the few cheap units left are the deals. The reference is
  the market price from the scan's history, or the value at the latest
  scan when that is lower, never the listings on screen, and the figure
  is the floor's percentage under it: a floor that has filled in at a
  new low is the price from the next scan on, a stray under the rest
  is still a deal, and an item never scanned reads "no reference". A
  floor the scans have kept seeing at its price for an hour or more
  has been passed over by every buyer since: it reads amber, under the
  reference but not a deal, and the row's tooltip says how long it has
  been on offer and over how many scans, or that it is new since the
  last scan. The hour is the `sat` setting; a floor under the vendor
  price is a deal however long it sat. A row meets its history by item
  ID whatever item level the house gives it; only gear keeps its level
  and suffix. History older than the two weeks the market value spans
  still counts: the 30-day mean, else the last scan. The usual
  category tree, search box and filters do the narrowing; clicking a
  row buys through Blizzard's frames as always. Sorting by discount
  and the "Deals only", "History only" and "Not mine" toggles are
  gone: putting Blizzard's list in another order means writing its
  data provider, which is what blocked items in the bags.
- **Auctions tab.** What each of your auctions brings in, at the right
  end of its name on Blizzard's list: buyout times units for an
  auction still up; a sold auction waiting in the mail already shows
  the whole sum, and the total reads it as such. Hovering the row adds
  the house's cut, the deposit paid and what is left after both to
  the row's own tooltip. Blizzard's columns stay as they are, Bid
  included. The deposit is noted whenever an auction is posted, from
  the Fan view or from Blizzard's own Sell tab, and shows in the
  History view too.
- **Listing ladder.** Clicking a Buy tab row opens Blizzard's buy frame
  for that item, and Hound reads the listings there: an info block with
  the reference, how many units sit at or under the deal limit and
  what they cost, the floor and the next price step, and the value of
  these listings alone. The listings' own value caps the reference
  there the same way, and the block says so. On the commodity list
  each units figure takes the verdict's color, green for a deal and
  amber under reference; on the item list each auction's discount sits
  at the right end of its row. A floor the scans have seen on offer
  past the sat hours reads amber on both, and the block says how long.
  A floor far under the next step is flagged in blue as low in the
  list, reference or not. Double-click a listing to buy it: an item is
  bought out on the spot, and a commodity row asks the house for a
  price on every unit up to it, less your own, and Hound's own confirm
  opens under the cursor with the total, for one more click.
- **History.** Every auction of yours the addon has seen, with what
  became of it: active, sold, expired or cancelled, units and gold. Fan
  batches and auctions posted from Blizzard's own Sell tab alike; the
  owned list is read once per visit and anything new is adopted. Every
  purchase of yours too, commodity or item, with the units and what
  you paid, under its own filter; the summary line sums sales and
  purchases over thirty days.
- **Auto scan.** A checkbox beside the scan timer starts a full scan
  whenever the house allows one, every fifteen minutes while you stand
  at the auctioneer.
- **Priors.** When history is thin, vendor price, crafted cost and value
  as a crafting input stand in as the reference. That is what makes the
  Buy tab usable in launch week. An item whose price has settled well
  under its crafted cost reads as a deal for as long as its history
  stays thin, so the crafted cost and input value can be turned off:
  untick "estimates" on the Hound tab, or `/hound estimates off`, and
  the reference is history alone, thin or old, plus the vendor price.
  The Item view still shows what an item costs to make either way.
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
- **Tooltips.** One line by default: the floor at the latest scan, with
  its age when that is more than a day: "AH floor 5s 89c". On a stack
  the stack's price follows in brackets ("AH floor 5s 89c (17s 67c)"),
  to read against the game's sell price, which is the whole stack's.
  Hold Shift for the rest: market value, the three-day mean, units
  listed, trend and the units cleared a day at what price (or the units
  moved estimate where no fills have been seen), plus your own sold /
  unsold line. The vendor price is left to the game's own line. A
  tooltip the client refreshes while it is up, a bag slot or a house
  row, follows Shift as it goes down and up; a link clicked in chat
  always shows the rest. Junk gets no Hound lines: the vendor is where
  it goes. A Buy tab row's tooltip and the Item view carry the
  cleared line too, and the Item view the three-day mean.
- **Bag overlay.** With the bags or the bank open, hold Shift: every
  slot shows what its stack is worth, at the house's floor from the latest scan
  on a dark strip, or at the vendor's price on a blue strip when the
  vendor pays more than the house would after its cut. The figure is
  one coin, in the game's gold, silver or copper with its coin icon
  (1.2 gold, 12 gold, 45 silver; the coin's letter with plain money
  set). Junk and anything soulbound show the vendor's price alone; a
  slot with neither shows nothing. Letting go takes it down, and it
  stays out of combat. Blizzard's own bags and bank only: a bag addon
  that replaces them gets no figures. `/hound overlay` says what it can see
  right now, and `/hound overlay off` turns it off.
- **Waylaid Crates.** A crate's own tooltip lists the bundles that fill
  it, twenty copper ore or twenty tin ore say, and any one of them
  does. Hound adds a header naming the Merchant's Favor the crate pays
  when turned in, then a line for each bundle: the units, the good, the
  market price of one and the bundle's total, with the cheapest fill
  the house can sell in green. The favor is the guides' figure: a raw
  crate (herbs, ore, textiles, curiosities) pays 5 a tier, 5, 10 and
  15, and a worked one (fabrics, ingots, parts) twice that. No guide
  has the Artisan tier yet, so an Artisan crate's header says its favor
  is not known. A good the last scan saw fewer of than
  the bundle takes says so ("only 6 listed", "none listed") and is
  passed over for the green. A good with no history is priced by what
  it costs to make, marked "~", while estimates are on; otherwise the
  line reads "no price". The header says how old the scan is.
  `/hound crate <link>` prints the same lines in chat. All thirty
  crates are covered, their bundles kept as data by crate ID.
- **Craftsman's Writs.** A writ asks for one crafted item, a Lesser
  Wizard's Robe say, and the item may be bought as well as made. Hound
  adds two lines to the writ's tooltip: its rank and the reputation it
  pays, and the item with its market price, priced as a crate's goods
  are. Gear is found in the history by its item ID, whatever level the
  scan filed it under. An item the last scan did not see says "none
  listed" beside the price history gives it; one never seen reads "no
  price". The one writ that asks for more than one of its item, two
  hundred Crafted Solid Shot, shows the price of each and the total.
  `/hound writ <link>` prints the same lines in chat. All 150 writs
  are covered, kept as data by writ ID.
- **Crates and writs on the Buy tab.** A crate or writ is bought for
  what it pays, not for its discount, so its row's figures read the
  reward and what a gold buys of it: "10 favor" and "4.2/g", "75 rep"
  and "30/g". The gold is the row's floor and the cheapest fill
  together, the bundle a crate's tooltip shows in green or the item a
  writ asks for, priced the same way. A fill priced by what it costs
  to make, or one the last scan saw too few of, marks the rate "~".
  The row's tooltip gives the rate and the sum, crate plus fill,
  before the usual reference and floor lines. A crate whose favor is
  not known yet, or whose fill has no price, reads like any other row.
- **UI.** A tab inside the Blizzard auction house frame (or `/hound` for
  a window) with four views. Markets lists every item with history. Item is one item in depth: stats, the daily
  graph, anchors, connections and your own sales, reached by
  double-clicking a row elsewhere or typing a name, id or link into its
  find box. Fan plans and posts batches. History lists your auctions
  and their outcomes. Sortable tables, a bar graph of daily value with
  floor and volume, sparklines per row.

Deferred on purpose: guild sync, the neutral auction house, disenchant
tables.

## Install

1. Copy the `AuctionHound` folder from this repository into
   `World of Warcraft/_forever_/Interface/AddOns/`, so the TOC sits
   at `Interface/AddOns/AuctionHound/AuctionHound.toc`. That is the
   live game's folder; the beta's, `_classic_beta_`, is not read by
   it, so a copy left there does nothing. The folder name must stay
   `AuctionHound` to match the TOC. Everything else in the repository
   (README, tests) stays out of the game folder.
2. Enable it on the character screen. It targets interface 16001, the
   number the game launched with.
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
the Hound tab is now selected by hand, and it now stays out of the
frame's own tab list, tab count and display modes altogether (see
Taint below), which left the frame's own tab showing through the
panel, so the panel now sits on a solid cover well above it; the
frame's portrait hangs down
the left edge, so the view buttons now start to the right of it; the
Buy tab read most rows as "no reference" with plenty of history
stored, since a browse row's item key can carry an item level even
for ore and cloth, where the scan keys all but gear by item ID alone
(rows, searches and owned auctions are now read by the scan's rule).

Since the beta: the game launched as patch 1.60.1, still interface
16001, so the TOC stands. Going by Blizzard's beta notes and the
patch's list of API changes, as far as they could be read, nothing the
addon calls was removed or renamed, and the restrictions on addons
that came over from the modern client ("secrets") cover combat and
unit data, which Hound never reads. An event the client no longer
knows is named in chat as the addon loads, and only its feature is
off. None of this has been run on the live client yet, so the steps
below are still the real test. What did change around the addon:

- **The folder.** The live game keeps addons and saved variables
  under `_forever_`. History is kept per market, and a live realm is
  a new market, so nothing from the beta is read on live. If the
  beta's saved variables were copied across, its markets sit unused
  in the file: `/hound markets` lists what is stored and `/hound wipe
  <market>` drops one.
- **The house.** It now shows item suffixes and their stats itself,
  and its browse list gained a column for the level an item can be
  equipped at (Blizzard's notes of October 1 and 16, after the
  addon's last beta session). Hound's figures sit at the end of the
  name whatever the house lays out: step 5. Suffixes are what a gear key is
  built from: step 3.
- **Closing.** The client fires `AUCTION_HOUSE_CLOSED` twice when you
  walk away from the auctioneer, by a beta tester's report. Every
  close handler is safe to run twice, and the tests now close the
  house twice with a scan, a queued message and a post in flight.
- **Other scanners.** The house allows one full scan every 15 minutes
  whichever addon asks, and gives no answer when it refuses. With
  another addon scanning, or after a scan of Hound's own was cut short
  by closing the house, auto scan used to ask again every minute and
  say "timed out" each time. It now says once that no answer came,
  waits five minutes, and still reads an answer that lands late:
  step 14.
- **Recipes.** Salt, coal and the cured hides were checked against
  Forever's item records for the patch. Three ids were wrong and are
  fixed: salt (it was gray dye's), and cured medium and heavy hide.

1. **Open the auction house.** Verified: no error, the Hound tab is
   there. Re-check after the fixes above: the Hound tab lights and the
   Buy tab dims while the panel is up, nothing of the Buy tab (its
   search box, categories or results) shows through the panel or
   answers the mouse under it, clicking Buy or Sell brings their tab
   back with everything on it and takes the panel down, and nothing
   sits under the portrait. Adjust `UI.AH_INSETS` at the top of
   `AuctionHound/UI/Frame.lua` if anything still overlaps, and
   `UI.AH_LEVELS` beside it if any piece of the Buy tab still pokes
   through. Then leave
   the house, open `/hound`, press Escape: the window closes. Right-click
   a recipe in your bags to learn it, and use any other item: no
   "blocked from an action only available to the Blizzard UI" popup.
   If one does appear, in the addon's name or another's, type
   `/console taintLog 2`, `/reload`, do the same thing again, and send
   `Logs/taint.log` from the game folder: it names the call that was
   blocked and the value that was read to get there.
2. **Full scan.** Open: a scan ran and stored items, but the price
   check has not been done. `/hound debug rep 5` prints raw rows. Check
   that row `[0]` exists (indices are 0-based) and whether `buyout` for
   a stack is the total or the per-unit price. If it is per unit, set
   `Scan.REPLICATE_BUYOUT_IS_TOTAL = false` in `AuctionHound/Scan.lua`.
   The chat summary should report few or no unresolved rows.
3. **Keys.** Open. `/hound key <link>` for an "of the X" green must
   match the key the Markets view shows for the same item after the
   scan, or history and the Buy tab will not line up for gear. For an item
   you have never seen this session the key may print as `nil` once;
   run it again after the item loads. The house has started showing
   suffixes itself since this step was written, so it is also the one
   that says whether its item keys still carry them the way a link
   does.
4. **Tooltips.** Open, and changed. Hover a scanned item in your
   bags: one Hound line, "AH floor". Hold Shift with the tooltip up:
   the rest appears (market, 3 day, listed and trend, yours; the
   vendor price is the game's own line, not Hound's), and goes again
   when Shift is let go. Click the item's link in chat:
   that tooltip shows the rest without Shift. Hover a gray item: no
   Hound lines. Hover something never scanned: no lines, no error.
   Report a tooltip that does not follow Shift while it is up, saying
   where it was (bags, the house, a quest reward, the Hound window).
   New: hover a stack of a scanned item in your bags. The floor line
   reads "AH floor" and ends in the stack's price in brackets, which
   should be the floor times the count; a single shows the floor
   alone. Do the same in the bank, and with a bag addon if you use
   one. Report a stack whose line shows no stack price, saying where
   it was.
5. **Buy tab.** Open, and rebuilt. Pick any category or search: every
   row shows Hound's figures at the right end of its name, the
   reference on the left and the discount on the right, green for a
   deal, amber under reference, grey above, and "no reference" for an
   item the addon knows nothing about. Blizzard's columns should be
   exactly as they are without the addon: no Hound column, the star at
   the edge. A long name should end short of the figures (with "..."),
   not run under them; if names are cut too short or the figures sit
   on them, `B.COLUMN_WIDTH` and `B.ROOM` at the top of
   `AuctionHound/UI/Browse.lua` are the widths to change. Hover a row:
   its usual tooltip should end in a "Hound on the Buy tab" part with
   the reference and the floor. Clicking a row still opens the buy
   frame. Any item the scan has seen must show a reference, estimates
   on or off; if a row says "no reference" for an item in the Markets
   view, `/hound debug buy 5` prints the first rows with the item
   level the house gave, the history key, and whether history is
   stored under it. The count on the right of the strip reads "N rows,
   M deals". Change the minimum and watch the colors and the deal count
   move at once. Type `5s` into the second box beside the percentage:
   cheap rows at "-50%" should turn from green to amber, their tooltips
   saying only a few copper a unit stand under the reference, and the
   deal count should drop while a dearer row at the same percentage
   stays green; `/hound discount` should read the box back. Report if
   the strip overlaps the column headers or the status on its right,
   or if a row's figures belong to another row after scrolling. On a
   gear category the house's own column for the level an item can be
   equipped at sits between the name and the units, and the figures
   should still sit at the end of the name.
6. **Persistence.** Verified: the item count survives `/reload`.
7. **Item view.** Open, and new: with nothing picked it now explains
   itself. Type part of a name in its find box and press Enter; then
   shift-click a link into the box.
8. **Fan, commodity.** Open. Open the Fan tab, pick a cheap commodity
   from your bags, and post one batch (`/hound fan [Copper Ore] 5 5 2`
   then `/hound post` works too). The plan line names it a `commodity`.
   The chat line after posting should name the batch. If posting fails
   with a hardware-event error, bind a key to a macro with `/hound
   post` and post from that.
9. **Fan, item.** Open. Do the same with a green from your bags. The
   plan line names it an `item`, and each batch posts one unit.
10. **Fan, flat.** Open. A step of `0` posts every batch at the center
    price. Post two batches of the same commodity that way and confirm
    the Blizzard Auctions tab shows two separate auctions at one price.
11. **Your posts.** Open. Open the Blizzard Auctions tab, then the Fan
    view: the batches show as active in the "Your posts" table. Cancel
    one from the Blizzard tab; it should flip to cancelled.
12. **Sales.** Open. Sell something. The next time you open the auction
    house (or check your mail with the addon loaded), the Fan view and
    `/hound stats` should show it under "yours".
13. **Auctions tab total.** Open, and rebuilt. On Blizzard's Auctions
    tab the columns are Blizzard's own, Bid included, and each auction's
    total sits at the right end of its name. For a commodity stack
    still up the total must read units times the unit price shown under
    Buyout. Found in the beta: a sold auction waiting in the mail shows
    its buyout as the whole sum, and the total used to multiply it by
    the units again; it now reads it as it is, so a sold row's total
    must equal its Buyout, and its tooltip says "sold, the whole
    auction". A long name should end short of the total, not run under
    it; `A.COLUMN_WIDTH` and `A.ROOM` at the top of
    `AuctionHound/UI/Auctions.lua` are the widths to change.
14. **Auto scan.** Open, and new. Tick "auto scan" at the right of the
    status line. With the timer at zero a scan starts at once; leave
    the house open and the next one should start by itself when the
    timer runs out. Untick it and confirm nothing starts. If another
    addon has just had its own full scan, or one of Hound's was cut
    short by closing the house, the house does not answer the next
    request: chat should say "no answer to the full scan after 45s"
    once, then nothing for five minutes, and a scan should follow by
    itself once the house allows one.
15. **History.** Open, and new. Open the History view. Every auction
    you have up should be listed as active, including ones posted from
    Blizzard's Sell tab, after the house has been open a few seconds.
    Sell, cancel or let one expire, and the row should change on the
    next visit. The line at the top sums the last thirty days. Post
    something from Blizzard's Sell tab and its Deposit column should
    fill in once the house lists it.
16. **Auctions tab cut and deposit.** Open, and rebuilt. Hover a row:
    its own tooltip should end in a "Hound total" part naming the cut,
    the deposit for anything posted while the addon was loaded (and
    saying so when it was not), and what is left. Clicking the row
    selects it as without the addon.
17. **Listing ladder.** Open. Click a commodity row on the Buy
    tab: under the Buy button a four-line block should name the
    reference, the units at or under the limit, the floor and next
    step, and the value of the listings; the units figures in the list
    should turn green for deals and amber under reference, and white
    again for a row over the reference after scrolling. Click a
    non-commodity row: the block sits between the item header and the
    auction list, and each auction's discount sits at the right end of
    its row, the list's own columns untouched. Report if the block
    overlaps the Buy button or the item header, or if the list's
    headers sit under the block.
18. **Depth.** Open. On the Buy tab tick "Depth": the status
    on the right should say "reading depth" and, row by row from the
    top, the notes should gain "xN" for the units at the floor. Hover
    a row for the ladder in its tooltip. Scroll: rows coming into view
    are read too. While it reads, click a row: the buy frame must still
    fill with that item's listings (a query dropped by the throttle is
    sent again), and type a new search: the results must still arrive.
    A row for an item never scanned stays "no reference" once its depth
    is read. Report if any click leaves an empty buy frame, or if the
    count on the right stops changing while rows still lack their "xN".
19. **Estimates.** Open, and new. Find a Buy tab row whose note starts
    with "~" (an estimate; the row's tooltip names it). Untick
    "estimates" beside "auto scan" on the Hound tab: the row should
    lose the "~" and read its own thin history, or "no reference", at
    once, with its color following, and no scan or search in between.
    With Depth on, hover the row: the ladder should name history, not
    the estimate. `/hound estimates on` brings them back and the box
    follows. Report if the box overlaps the status line.
20. **Purchases.** Open, and new. Buy a commodity through the house's
    own dialog and an item through its Buyout button. Chat should say
    "bought N x item for X" each time, and the History view should
    list both under the "Bought" filter with the units and the price
    paid, the summary line adding "bought N for X". A bid under the
    buyout should record nothing. Report if a purchase goes unnoted,
    or is noted twice. Found on live: a Red Mageweave Bag bought at
    its buyout of 1g 87s was noted as "bought 16 x Red Mageweave Bag
    (11s 69c each)". The house gave its listing a quantity of 16, and
    the units noted were that count. A buyout brings one auction, and
    an auction holds no more than a stack, so the count now stops at
    one stack: one for a bag or a piece of gear. Buy a bag or a green
    at its buyout: chat should say "bought <item> for X" with no
    count. Before buying, look at the item buy frame's quantity
    column: if a bag or gear row shows a count there (16, say), report
    whether the count drops by one after the buyout or the row goes.
    That says whether the house folds identical auctions into one row,
    which the scan reads as that many units at the row's price.
21. **Quick buyout.** Open, and rebuilt. On the item buy frame,
    double-click an auction: it should be bought out at once, chat
    saying "buying ... for X" and then "bought ...". On the commodity
    buy frame, double-click a row: Hound's own confirm should open
    under the cursor, kept on the screen at its edges, naming every
    unit up to that row less your own ("Buy 45 x Copper Ore"), then
    the house's quote, total and each. Its Buy button lights once the
    quote is in, and one click there buys; chat says "buying ..." and
    then "bought ...". Cancel, Escape or walking away calls the
    purchase off; a quote over your gold leaves Buy dark and says so.
    The house's own Buy button and dialog work as without the addon,
    Hound never presses or moves them. Report if nothing happens on a
    double-click, if the units or the quote are wrong, or if the house
    complains about a hardware event (the quote is asked for from the
    double-click and the purchase from the Buy click, both hardware
    events).
22. **Latest scan.** Open, and new. Find an item whose price has
    fallen and stayed down, with plenty of units at the new low. Its
    Buy tab row should read grey or amber at that price, and the row's
    tooltip should name the reference as the last scan under the
    two-week value. A stray unit far under the rest of its listings
    should still read green. Report a row that reads green for a floor
    the whole market sits at.
23. **Sat.** Open, and new. With auto scan on, find a green row and
    leave it. If nobody buys it, after an hour of scans it should turn
    amber, the row's tooltip saying "on offer 1.0h over N scans: not a
    deal", and clicking it should show the same on the buy frame.
    `/hound sat 0` should turn it green again at once, `/hound sat 1`
    amber. Report a row that stays green past the hour, or one that
    turns amber while the scans have not seen its floor.
24. **Wall.** Open, and new. With Depth on, find a row whose floor most
    of its units sit at, well under history. Once its depth is read
    the figures should show the listings' value as the reference and no
    discount, and the tooltip's Hound part should say "these listings,
    under history". A row with one cheap unit under a wall at the old
    price should stay green. Report a wall that stays green with its
    depth read, or a stray that goes grey.
25. **Fills.** Open, and new. With auto scan on, leave the house open
    for two scans. The second scan's chat line should end in "N units
    cleared since the last" when anything sold in between, and `/hound
    stats <link>` on a busy item should show "cleared ~N a day at ~X";
    the item's tooltip and its Buy tab row's tooltip carry the same
    line. Buy something yourself between two scans: it should count.
    Report a scan line that never reports fills on a busy market, or a
    stats line claiming fills for an item nobody trades.
26. **Waylaid Crates.** Open, and new. After a full scan, hover a crate
    whose label has been read ("Waylaid Crate: Apprentice Ore"): under
    the crate's own list there should be a Hound header and one line
    per bundle, in the same order, with the price of one and the
    bundle's total, the cheapest in green. The units and goods must
    match the crate's own list line for line; the bundles are data
    from the launch build's item records and have not been read off a
    crate in game. If no Hound lines show, type `/hound crate ` and
    shift-click the crate: for an item the data does not know it
    prints the item's ID, which is the thing to report along with the
    crate's list. Report what a partly filled crate's tooltip says as
    well: the lines price the whole bundle whatever is already in it.
    New: the header names the Merchant's Favor the crate pays ("10
    Merchant's Favor, any one bundle fills it"). Turn one in and check
    the favor the quest gives against it; the figures are the guides',
    not read in game. For an Artisan crate the header says the favor is
    not known yet: report what one pays, and the eight Artisan crates
    get their figure.
27. **Craftsman's Writs.** Open, and new. After a full scan, hover a
    writ ("Craftsman's Writ: Lesser Wizard's Robe"), in the bags or on
    the house: under its own text there should be a Hound header with
    the writ's rank and reputation, then the item it asks for with a
    price on the right. Hover the item itself and compare: the price
    should be its "Hound market" line. The writs are data from the
    launch build's item and quest records and have not been read off
    a writ in game; the reputation by rank (75, 125, 200) is the
    guides' figure. Try a writ for a piece of gear and one for a
    potion: gear is the case to watch, since the scan files it under
    its item level. Report a writ whose item is on the house and in
    the Markets view but shows "no price" or "none listed", with what
    `/hound key` says for the item's link. If no Hound lines show,
    type `/hound writ ` and shift-click the writ: for an item the data
    does not know it prints the item's ID.
28. **Bag overlay.** Open, and in part verified. On live the figures
    first drew under the bags; set on the bag buttons themselves they
    show. They are now in the game's coin colors with the coin's icon,
    the house's on a dark strip and the vendor's on a blue one. Open
    the bags and hold Shift: a small figure sits over the top of each
    slot with a price, and goes when Shift is let go. Gray items and
    soulbound ones sit on the blue strip, at the vendor's price. Check
    the icons fit the slot beside the figure and the colors read on
    both strips. Click, shift-click and drag items with it up:
    everything must work as it does without the addon. Open another
    bag while holding Shift: its slots fill in within a moment.
    `/hound overlay` alone says how many bag frames it found open, how
    many slots it read and how many have a price, names any bag addon
    that is loaded, and repeats the error it stopped on, if any;
    `/hound overlay test` puts the figures up for 10 seconds without
    Shift, says how the first one is drawn, and at the end whether
    Hound saw Shift held. Report figures that sit off their slots,
    overlap the stack count, or show under the bag art;
    `/hound overlay off` turns it off meanwhile. Bag addons (Bagnon,
    AdiBags and the like) are not covered. New: the bank. Open it and
    hold Shift: each slot of the tab shown gets its figure the same
    way, and another tab picked while Shift is held fills in within a
    moment. `/hound overlay` adds "and the bank" to what it sees while
    the bank is open. Report bank figures that sit off their slots or
    stay up after the bank is closed.
29. **Bags blocked, at the house and away from it.** Open: found in
    Blizzard's own code and fixed by the rebuild, not yet seen fixed in
    game. Reported on live: a right-click on an item in the bags (a
    Cozy Sleeping Bag at the house, and any item long after leaving
    it) brought up "blocked from an action only available to the
    Blizzard UI" in Hound's name, until `/reload`. Read from the live
    client's UI code (1.60.1, the house's frames and the bag code):
    Hound wrote its data provider and layout on Blizzard's browse list,
    its layout on the item buy list and the Auctions tab's list, marked
    those lists for a redraw from its own code, built its cells inside
    Blizzard's table builder, and pressed the house's Buy button for a
    double-click. When the house opens, the frame switches to the Buy
    view, which shows the browse list and reads those values, and then,
    in the same call, opens the bags. Opening the bags hands each slot
    button its bag number, so that number was written in Hound's name
    too, and every right-click reads it before it uses the item, which
    is protected. It came and went because a button's bag number is
    only written when it changes: the house had to be what opened the
    bags while the buttons were new or reshuffled, the first time after
    logging in or `/reload` being the sure case. All of that is gone
    (see Taint). To confirm: `/console taintLog 1`, `/reload`, do not
    open the bags, open the house, click a Buy tab row, double-click a
    commodity and cancel, close the house, walk away and right-click a
    potion or food in the bags. It should go through, with nothing in
    Hound's name in `Logs/taint.log`. Do the same at the house with a
    soulbound usable item after clicking a Buy tab row. Report any
    blocked action, with the log.
30. **Crates and writs on the Buy tab.** Open. After a full
    scan, search "Waylaid Crate": each crate row whose favor is known
    should read "N favor" on the left of its figures and a rate such as
    "4.2/g" on the right. Hover the row: Hound's part of its tooltip
    gives the rate and the sum, the crate's floor plus the fill its own
    tooltip shows in green. Do the same with "Craftsman's Writ", where
    the note reads "N rep". Report a rate that does not match the sum
    in its own tooltip, or a crate whose fill differs from the green
    line in the crate's tooltip.

## Taint

The client blocks a protected call, using an item from the bags say,
whenever the code on the way to it has read a value an addon wrote, and
it names the addon. The blame follows the value, not the action, so
the popup can name Hound for something far from the house.

What did it: the house's frame reads its lists on the way to opening
the bags when the house opens, and Hound had written on those lists
(its data provider and layout, a redraw flag, cells of its own built
by Blizzard's table builder) and pressed the house's Buy button from
its own code. So the bags' slot buttons took their bag numbers in
Hound's name, and every item used from the bags after that was
blocked until `/reload` (step 29). Before that, a line in Blizzard's
`UISpecialFrames` list and the Hound tab's place in the frame's own tab
list did the same and went (Escape now closes the window from a key
handler on the window itself, out of combat; the tab sits beside the
frame's tabs and is worked by hand).

The rules the code keeps, in `UI/House.lua` for the house's lists:

- Hook Blizzard functions with `hooksecurefunc` and their scripts with
  `HookScript`, never replace either. Blizzard's cells are met through
  secure hooks on their mixins' methods, before the list makes any.
- Write nothing on a Blizzard frame, list, row or cell. What Hound
  knows about a row is kept in its own tables, by row.
- Run none of Blizzard's own code from Hound's: no list told to
  redraw, no button of Blizzard's pressed, nothing of Blizzard's shown
  or hidden, since its scripts would run in Hound's name. Hound's own
  frames are repainted instead, and Hound's own confirm asks the house
  for a commodity's price.
- Put Hound's figures in Hound's own frames, children of Blizzard's
  cells that take no mouse. Moving a font string of Blizzard's (a name
  pulled in to make room) writes no value and is allowed.
- Add hover lines to Blizzard's own tooltip for a row from the item
  tooltip's post-call, which the client makes securely.

What that costs: Blizzard's list keeps its own order and columns, so
the Buy tab no longer sorts or filters rows, and the Auctions tab keeps
its Bid column. The panel sits on a solid cover over the frame's own
tab rather than hiding it, and the confirm dialog is Hound's own. The
bag overlay keeps the same rules: its figures are Hound's own frames,
set on the bag and bank buttons as children that take no mouse, and no
field is written on a bag frame, the bank or a button.

The tests hold the code to these rules (see Tests): a write on a
Blizzard object, or Blizzard's own code run, with the addon's code on
the way to it fails the run, and so does a function of the addon's
left in a field of Blizzard's.

## Commands

```
/hound                 toggle the window
/hound scan            full scan (once per 15 minutes, at the AH)
/hound stats <link>    stored stats for an item, and what you sold it for
/hound key <link>      the history key for a link
/hound crate <link>    price the bundles that fill a Waylaid Crate, as its tooltip does
/hound writ <link>     price the item a Craftsman's Writ asks for, as its tooltip does
/hound fan <link> [per batch] [step %] [batches] [bell|linear] [around|above|below] [center] [12h|24h|48h]
                       plan a fan for an item in your bags; alone, show the plan
/hound post            post the next batch of the fan (bind it to a key)
/hound labor <g/h>     your time, used for gold per hour
/hound cut <pct>       auction house cut, default 5
/hound discount [pct] [money]  the minimum a deal clears: a percentage off the reference, default 25,
                       and copper a unit under it, e.g. 25 5s; whichever is more; 0c for no copper floor
/hound sat <hours>     a floor on offer this long is no longer a deal, default 1; 0 judges by price alone
/hound estimates on|off  crafted cost and value as an input as the reference while history is thin, default on
/hound overlay [on|off]  hold Shift with the bags or bank open to see what each slot is worth, default on;
                       alone, what it sees in the bags right now
/hound overlay test    the figures up for 10 seconds without Shift, and how they are drawn
/hound debug rep [n]   print raw full-scan rows
/hound debug buy [n]   print the Buy tab's first rows: the house's item level, the history key, the reference
/hound markets         list the markets stored: each region, realm and faction played
/hound wipe [market]   erase this market's history (your own posts are kept); with another
                       market's name, drop that market whole
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
Scan.lua     ReplicateItems (full), fills between scans, and any search answer as listings
Throttle.lua one queue for throttled messages; Blizzard's dropped queries sent again
Store.lua    per-market history, compact strings, async flush
Market.lua   value from listings, ladder, stats, confidence
Priors.lua   vendor, crafted cost, value as input, connections economics
Reference.lua the reference: history when deep enough, the two-week value or the
             latest scan's, whichever is lower; else a prior, else older history
Browse.lua   the Buy tab's read of each row: reference, discount, saving, verdict;
             what a crate or writ pays a gold of its floor and fill
Ladder.lua   one item's listings read against the reference: deal depth, next step, strays
Depth.lua    the ladder behind each Buy tab row on screen, one search each, on demand
Fan.lua      fan plans (linear or bell), posting, own-sales tracking
Buy.lua      purchases noted from the house's calls, for the History view
Crate.lua    a Waylaid Crate's favor and bundles, each priced; the cheapest the house can fill
Writ.lua     the item a Craftsman's Writ asks for, priced the same way
Tooltip.lua  tooltip lines
UI/          table, graph, sparkline; panel, views, AH tab, window;
             House.lua: how Hound sits on the house's lists without
             writing on them; the Buy tab figures and strip, the buy
             frames' ladder block, colors and Hound's own commodity
             confirm, the Auctions tab total; the Shift overlay on the
             bags and bank (Bags.lua)
Data/        conversion recipes with classic item ids; the Waylaid
             Crates, the favor each pays and the bundles that fill
             them; the Craftsman's Writs and the item each asks for
```

History is scoped by region, realm and faction: `US-ClassicBetaPvP2-Horde`
was the beta's market, and `/hound markets` lists the ones stored.
Commodities are keyed by item id; equippable
items by `id:level:suffix` so suffix variants never share a record. An
item key from the house (a Buy tab row, a search, an owned auction) is
read by the same rule, whatever item level it carries. Your
own posts live in the same market record, as plain tables, for 30 days
after they resolve.

### Units moved, and cleared

Blizzard exposes no sales feed. The moved estimate is the quantity that
vanished between two scans no more than eight hours apart, which is a
lower bound since new listings offset it. It is labelled as an estimate
everywhere and treated as the weakest input.

Cleared is the better read of the same thing. A scan keeps its ladders,
price by price, and the next scan within four hours counts the units
gone from each price. The house gives every listing a time-left band,
and a band's floor says how long the listing had for sure: units in a
band that could have run out over the gap are taken off the count
first. What is left went to a buyer, at that price. It is still a lower
bound, since new listings at a price hide fills there and a cancelled
auction looks like a sale, and it accrues only while scans follow each
other, which auto scan does. The stats carry the units cleared a day
over the last week and the mean price they went for over the last
three days; the scan's chat line reports the units cleared since the
scan before. This is the one input that says what buyers pay rather
than what sellers ask, and the reference will lean on it as it fills
in.

## Tests

From the repository root:

```
lua5.1 test/run.lua        # or: lua5.1 test/run.lua -v
```

`test/wowstub.lua` fakes the client: frames, timers, item info, the
auction house calls and events, and Blizzard's own list cells and rows
as the live client's UI code has them. It loads the addon from
`AuctionHound/` in TOC order. It also keeps a model of taint: a field
written on a Blizzard object, or a stand-in for Blizzard's own code
run, with the addon's code on the stack is recorded, the walk stopping
where the client starts a clean execution (an event, a timer), and a
function of the addon's found in a Blizzard object's field is too; the
run fails on any of them. `test/run.lua` runs the full scan, auto scan,
reference, tooltip with and without Shift, the bag overlay, slash
command, the Buy tab figures and the rows' tooltips, depth on demand
through a modelled throttle, listing ladder, Auctions tab total, deposit notes,
auction adoption and history, purchases and the quick buyout, the
Waylaid Crate and Craftsman's Writ lines and their rows on the Buy
tab, a full scan the house does
not answer, the house closing twice, and UI construction paths. Where the beta has
corrected a call's signature, the stub enforces it, so the mistake
cannot come back quietly; the client's 32-bit `%d`, which a price near
the gold cap overflows, is enforced the same way.

## Roadmap

- Guild sync over addon messages, with distributed full scans
- Neutral auction house as a second market and cross-faction spreads
- Disenchant tables as a third prior
- A deals list of Hound's own, sorted by discount and filtered, beside
  Blizzard's browse list rather than on it, now that the Buy tab can
  no longer put Blizzard's list in another order
- Watchlists: items to flag on the Buy tab whatever the discount
- Time-of-day view for the Oceanic overlap
- Waylaid Crates: read a partly filled crate's tooltip and price only
  what is still missing; the Artisan tier's favor once a turn-in has
  been read
- Craftsman's Writs: the recipes behind the 150 items, so a writ whose
  item is not on the house shows what it costs to make
