# Changelog

Every released version of DailyValo. The release workflow reads the section for
a tag out of this file and uses it as the GitHub Release body, so the heading
format matters: one `## vX.Y.Z` per version, newest first.

## v3.0.0

**Share your shop as an image.** A share button on the Daily Shop and the Night
Market turns the offers into a clean card — app name centred at the top, the
skins side by side with the artwork given most of each tile — and hands it to
Android's share sheet, so it goes wherever you send things: WhatsApp, Discord,
a group chat, your gallery.

It is a purpose-built image, not a screenshot: no status bar, no half-scrolled
list, no date or heading taking up room, and the same card from every phone.

**Home screen widget.** Four tiles on black, each showing a skin from today's
shop framed in the colour of its rarity. No text — a home screen is glanced at,
and the artwork is what makes a skin recognisable in half a second. It updates
with the background check, so it stays current without opening the app, and
tapping it opens the shop.

**Export and import your wishlist.** Two buttons at the bottom of the wishlist —
in the middle of it when it is empty, which is exactly when you need the import.
Export writes a small file you can send anywhere or keep as a backup; import
merges it in, so restoring a backup never deletes what is already there and
importing twice changes nothing the second time.

**Collection value.** The Collection tab now shows what your skins are worth at
shop prices, and the number follows the rarity filter. It is labelled an
estimate on purpose: Riot publishes no prices and no purchase history, so this
is what these skins *cost*, never what you paid — Night Market and bundle
discounts leave no trace anywhere the app can read. Skins that were never sold,
like battlepass rewards, are counted separately instead of being guessed at.

## v2.2.2

**Notification time survives the clock change.** The delivery time is now a
wall clock in your own timezone rather than a fixed offset. Before this, on the
two days a year the clocks change, a notification set for 09:00 would have
arrived at 08:00 or 10:00 — the target was computed by adding hours to midnight,
and a duration does not know about daylight saving. Both transitions are now
resolved against the real timezone database.

## v2.2.1

**Featured Bundles open up.** Tap a bundle to see what is actually in it: every
skin and accessory with its own price, what each one costs on its own, and which
item Riot throws in for free. The page says up front whether you can buy items
separately or only the complete bundle — it varies per bundle and changes what
the prices mean.

Tapping a weapon or melee skin in the list opens the same detail page as the
daily shop, with the full render, chromas and preview clips.

**Release builds are properly signed.** Releases without a signing key are no
longer published by accident. They were signed with a throwaway key generated
per build, which meant no release could ever update another — you had to
uninstall and lose your wishlist every time. Publishing an unsigned test build
is now a deliberate choice, and a new workflow sets up a real signing key
without needing a computer.

## v2.2.0

**Notification time.** A new setting lets you pick when your notifications
arrive. Off by default, so they keep coming as soon as the shop rotates at
00:00 UTC — which is the middle of the night here. Turn it on, pick an hour,
and both notifications wait for it. The shop is still read at reset, so what
arrives at 09:00 is exactly what rotated at 02:00.

**Filter your collection by rarity.** The rarity counts above the grid are now
buttons. Tap Ultra to see only your Ultras, tap Premium as well to see both,
tap again to switch one off. The counts keep showing your full totals while a
filter is active, and a Clear button appears once anything is selected.

**Add skins is sorted properly.** The picker used to list ~1600 skins in
whatever order the API returned them. It now runs in buy-menu order — Sidearm,
SMG, Shotgun, Rifle, Sniper, Heavy, then melee — alphabetically by weapon inside
each class, and rarest first for each weapon. Searching keeps that order.

## v2.1.0

Tapping a skin in the wishlist opens its preview instead of removing it.

- The "Add skins" picker toggled the wishlist when you tapped a row, so tapping
  a skin already on your list silently removed it. Rows now open the detail
  page, exactly as they do in the shop and the collection.
- The heart is the only control that adds or removes, on both the picker and
  the wishlist itself.
- Removing a skin — by heart or by swipe — can now be undone, and the restored
  entry keeps its place in the list.
- Swiping to delete takes a longer drag, so it is not triggered by a tap that
  drifts sideways.

## v2.0.0

The shop tab grows two sections, each on its own clock.

- **Accessory Store**: sprays, gun buddies, player cards and titles, priced in
  Kingdom Credits, with its own weekly reset timer.
- **Featured Bundles**: key art, discount, item count and the time left before
  the bundle leaves the shop.
- Kingdom Credit balance added to the header.
- Fixed: the settings sheet opened only half-way, leaving *Sign out* off-screen.

## v1.5.0

- Fixed the competitive rank reading as *Unranked* for ranked accounts. Riot
  omits a JSON content type on the MMR routes, so the response arrived as an
  unparsed string and every lookup against it came back empty.

## v1.4.1

- Rank lookup walks back through previous acts instead of giving up on the
  current one.
- The diagnostics screen reports the shape of each response body, not just its
  status code.

## v1.4.0

- Rank is resolved from several sources rather than a single endpoint, with a
  diagnostics screen showing what each attempt returned.

## v1.3.1

- One failed endpoint no longer blanks the whole header. The Riot ID needs no
  network call and is shown regardless.

## v1.3.0

- Fixed the Radianite balance always reading zero — a corrupted currency UUID.
- First pass at showing the competitive rank.
- New app icon: a DV monogram in red, grey and black.

## v1.2.0

- Sign-in moved to Riot's own hosted login page in a WebView, so two-factor
  codes and the confirmation prompt in Riot Mobile behave as they do in a
  browser.

## v1.1.0

- Skin levels and chromas play Riot's preview clips instead of showing a still.
- Currency icons removed from the header.

## v1.0.0

First release.

- **Daily Shop** — the four daily offers with artwork, names, VP prices and
  rarity, under a live countdown to the 00:00 UTC reset.
- **Night Market** — discounted offers with the original price, the discount
  and your total savings.
- **Wishlist** — search the full skin catalogue and track what you are hunting
  for.
- **Collection** — every skin you own, grouped by rarity.
- Riot sign-in, with session tokens held in the Android Keystore.
- Two notifications on separate channels: a silent digest of your four offers at
  reset, and an alerting one when a wishlisted skin appears.
- Demo mode, using the real content catalogue and synthesised offers, so the app
  works with no Riot account at all.
