# DailyValo

An unofficial Valorant shop and skin tracker for Android, built with Flutter.

DailyValo shows your daily store, the Night Market when one is running, a
wishlist you can be alerted on, your skin collection and the full skin
catalogue — with artwork, chromas and upgrade levels, and a record of how long
each skin has been absent from your shop. It tells you when your shop rotates,
at an hour you pick, and separately when something you are actually hunting for
shows up.

> DailyValo is not affiliated with, endorsed by, or sponsored by Riot Games. It
> uses the same undocumented client endpoints the official desktop client uses,
> and is read-only — it never buys, equips or changes anything.
> See [Security and Riot's APIs](#security-and-riots-apis).

**Current version: v3.5.0** · Android 7.0+ (`minSdk 24`) · 327 tests

---

## Features

| Tab | What it does |
| --- | --- |
| **Daily Shop** | The four daily offers with artwork, weapon and skin name, VP price and rarity, under a live countdown to reset. Below them the **Accessory Store** — sprays, buddies, cards and titles in Kingdom Credits, with anything you already own marked — and the **Featured Bundles**: tap one to see every item in it, what each costs alone, which is free, and whether the bundle can be split. |
| **Night Market** | Discounted offers with the original price, the discount and your total savings. Says so plainly when no market is running. |
| **Wishlist** | Searchable picker over the full catalogue in buy-menu order. Entries in today's shop are flagged. Exportable and importable as a file, and copyable to another account. |
| **Collection** | Every skin you own, grouped and counted by rarity. The counts double as filters, and the tab shows what the selection is worth at shop prices. |
| **Catalogue** | Every skin Riot has ever sold. Search by skin or weapon name; filter by rarity, weapon class, owned or not, and wishlisted; sort by weapon, name, rarity, price or **longest unseen**. |

A persistent header carries your Riot ID, competitive rank and your Valorant
Point, Radianite and Kingdom Credit balances. Tapping any skin opens a detail
page with the full render, every colour variant, and each upgrade level labelled
with what it unlocks.

**Preview clips.** Riot publishes short clips for most levels and for chromas
with unique VFX; a still image cannot show you what a finisher does.

**The drought counter.** Every skin says when it was last in your shop — *last
seen 47 days ago*, *never seen*, or *in your shop today* — on its detail page,
on the wishlist and on every catalogue tile.

Riot publishes no shop history: the storefront is a snapshot of today, and no
endpoint will tell you when a skin last came up. So the app writes it down as
each rotation goes past, and records the day it started watching. That is why
"never seen" reads *not seen in the 19 days tracked so far*: on a fresh install
the shorter sentence would be a claim about the app dressed up as a claim about
your shop. The record is per account and survives a sign-out, because nothing
can rebuild it.

**Three clocks, not one.** The daily skins roll over at 00:00 UTC, the Accessory
Store rotates weekly, and each bundle leaves on its own date — so each section
carries its own countdown and refetches when it reaches zero.

**Sharing.** A share button on the Daily Shop and the Night Market renders the
offers as a card and hands it to the share sheet. A purpose-built image, not a
screenshot.

**Home screen widget.** Four tiles in a 2×2 grid on black, each showing a skin
from today's shop framed in the colour of its rarity. Updates with the
background check; tapping it opens the shop.

### Accounts

Several Riot accounts can be signed in at once. Everything is kept per account:
shop, collection, wishlist, rank, wallet, notifications and the drought record.
Tapping your Riot ID in the header switches between them; *Add account* and
*Sign out of all accounts* live at the bottom of settings.

Signing one account out leaves the others signed in and keeps that account's
wishlist, so adding it back picks it up again.

Accounts are identified by puuid rather than Riot ID — a Riot ID can be changed,
and two accounts can hold the same one at different times.

### Notifications

Three notifications on three Android channels, so any of them can be turned down
from Android's own settings without touching the others.

| | Daily shop | Wishlist hit | Night Market |
| --- | --- | --- | --- |
| Fires when | The four offers rotate | A wishlisted skin is among them | A Night Market opens |
| Title | The account's name, e.g. `SlaySlayer` | The account's name | The account's name |
| Body | `Prime Vandal - Reaver Sheriff - Ion Phantom - Karambit` | `An item on your wishlist is in your shop!` | `Night Market is open — 6 discounted skins, up to -47%` |

All three alert with sound and a banner. Each signed-in account gets its own, so
two accounts rotating at the same time produce two notifications rather than one
replacing the other.

The Night Market alert fires once per market rather than daily while one runs,
names any wishlisted skins in it when expanded, and is checked on every
background run rather than only when the daily shop rotates — a market lasts
days, and hearing about it on day three is most of the way to not hearing about
it at all.

**Delivery time.** By default the shop and wishlist alerts fire as soon as the
rotation is noticed, which lands at 02:00 in much of Europe. Settings ▸
*Notification time* holds them back to an hour you pick. Detection still happens
at reset, so what arrives at 09:30 is exactly what rotated at 02:00.

It does not hold the Night Market alert back: those two describe a shop that
cannot change until tomorrow, while a market is already counting down.

The chosen time is a wall clock in your own timezone, resolved against the IANA
database — so 09:30 is still 09:30 on the two days a year the clocks move. The
alarm is exact where Android permits it; the permission is requested when you
switch the delivery time on, and refusing it costs punctuality rather than the
notification.

None of them expires on its own and none is sticky: one stays until it is
swiped, opened, or cleared by opening the app.

**If one does not arrive**, Settings ▸ *Allow background checks* opens the system
screen that lifts battery optimisation. It is the one setting that can stop the
nightly check outright while everything inside the app looks healthy.

### Developer mode

Off by default, at the bottom of settings. It reveals:

* **Diagnostics** — every Riot endpoint probed separately with what it returned,
  plus notification permission, exact-alarm permission, queued alarms, whether
  the background check has been running, and whether battery optimisation is
  restricting it.
* **Test the shop notification** — queues your real digest a minute out through
  the same path a reset uses. Moving the delivery time ten minutes ahead tests
  nothing: an alarm is armed only when a rotation is *detected*, once a day.
* **Detailed log** — records requests, the shop check, notification scheduling
  and each background run, and exports as a dated file. Tokens and the session
  cookie are stripped before anything is written, so the file is safe to send.

---

## Getting started

```bash
flutter pub get
flutter run                 # debug build on a connected device/emulator
flutter test                # 327 unit tests, no device needed
flutter analyze             # zero warnings expected
```

Requires Flutter 3.44+ / Dart 3.12+. Android only for now.

Releases are built and published by GitHub Actions — see
[`docs/RELEASING.md`](docs/RELEASING.md).

### Demo mode

Tap **Explore in demo mode** on the sign-in screen. No Riot account, no
credentials, no network calls to Riot at all.

It is a first-class app mode, not a stub: the *real* content catalogue is
fetched from `valorant-api.com`, so artwork, names, rarities, chromas and
upgrade levels are genuine — only the offers are synthesised. They are seeded by
the calendar day, so the shop is stable for 24 hours and rotates at 00:00 UTC,
which means the reset detection and the notification pipeline can be exercised
end to end without waiting for a real reset.

---

## Architecture

Feature-first, with a `data` / `presentation` split inside each feature and a
shared `core`.

```
lib/
├── main.dart                        Bootstrap: graph → workmanager → runApp
└── src/
    ├── app/
    │   ├── dependencies.dart        The object graph
    │   ├── providers.dart           Riverpod view over the graph
    │   └── theme/                   Colours, type scale, ThemeData
    ├── core/
    │   ├── constants/               Riot endpoints, UUIDs, storage keys
    │   ├── errors/                  Sealed AppException family
    │   ├── network/                 Dio factories, interceptors, session manager
    │   ├── platform/                Battery-optimisation channel
    │   ├── storage/                 Secure token store, Hive façade
    │   └── utils/                   JWT reader, formatters, logger
    ├── features/
    │   ├── auth/                    RSO login, account registry, silent re-auth
    │   ├── content/                 valorant-api.com catalogue + cache
    │   ├── player/                  Riot ID, rank, wallet → header
    │   ├── store/                   Storefront, night market, accessories,
    │   │                            bundles, demo source
    │   ├── wishlist/                Hive-backed wishlist + picker
    │   ├── collection/              Owned skins
    │   ├── catalogue/               Every skin, searchable and sortable
    │   ├── skin_detail/             Artwork, chromas, upgrade levels
    │   └── home/                    Tab shell + settings sheet
    └── services/
        ├── notifications/           Channels, schedule, the three shapes
        ├── logging/                 File sink and redaction
        ├── widgets/                 Home screen widget bridge
        └── background/             WorkManager dispatcher + sync service
```

**The object graph lives outside Riverpod.** `AppDependencies.bootstrap()`
builds it as a plain object, scoped to one account. The WorkManager isolate
starts cold — no widget tree, no `ProviderScope`, no shared state with `main()`
— and builds the same graph for each signed-in account in turn. Riverpod is a
thin read-only view over it for the widgets, so switching accounts swaps the
graph rather than mutating anything.

**Data flow.**

```
valorant-api.com ──► ContentRepository ──┐
                     (Hive, 24h stale)   │
                                         ├──► Shop.resolve ──► UI
Riot PD /storefront ─► StoreRepository ──┤
                       (Hive snapshot)   │
Hive wishlist ─────► WishlistRepository ─┘
```

The storefront returns nothing but UUIDs and prices; everything human-readable
comes from joining them against the content catalogue. That is why the raw
`StorefrontSnapshot` and the resolved `Shop` are separate types — the background
worker compares snapshots without ever loading the 4 MB catalogue.

**Detecting a rotation.** The current offer ids are compared against *the ones
the user was last told about*, a record with its own storage key written only
after a notification has gone out. Comparing against the cached shop instead
looks equivalent and is not: that cache is overwritten by every fetch, including
the one the Daily Shop tab makes when the app opens.

---

## Security and Riot's APIs

Sign-in happens in a **WebView on Riot's own hosted login page**. The app never
sees the password, and two-factor codes and the Riot Mobile confirmation prompt
behave exactly as they do in a browser. Later refreshes replay the RSO cookie
against `/authorize`, which is what lets the background isolate renew a session
without a WebView.

### What is stored, and where

| Data | Where | Why |
| --- | --- | --- |
| Password | **Nowhere** | Typed into Riot's own page; never seen by the app. |
| RSO `ssid` cookie | Android Keystore, per account | Mints fresh access tokens without the password. Revocable server-side by you. |
| Access / entitlements / id tokens | Android Keystore, per account | Expire in ~1 hour; refreshed silently. |
| Wishlist, catalogue, shop snapshot | Hive (plain files), per account | Not sensitive. Nothing credential-shaped goes in a Hive box. |
| Detailed log | A plain file, only while switched on | Tokens and the session cookie are stripped at the point of writing, so the file is safe to share. |

Signing out of an account deletes its credentials and cached server data; its
wishlist is kept, since only you could reconstruct it. Signing out of the last
account cancels all background work and clears the home screen widget.

### Two things worth knowing before you ship this

1. **These endpoints are undocumented.** They are the same ones the official
   client uses and are stable in practice, but Riot owes no compatibility here.
   Riot's third-party developer policy prohibits automating gameplay and
   misrepresenting affiliation; a read-only shop viewer is the same shape as the
   many community trackers that exist, but read the current policy yourself
   before publishing. Every endpoint and constant is centralised in
   `core/constants/riot_constants.dart`, so an upstream change is a one-file fix.

2. **The app does not handle credentials at all.** Keep it that way —
   reintroducing a password field would both weaken this and break sign-in for
   push-protected accounts.

---

## Testing

327 unit tests, no device or network required. `flutter test` runs them all.

The suite leans on the places where being wrong is invisible: the notification
body formats (product spec, not implementation detail), the delivery time across
both clock-change days, per-account storage isolation, the manifest entries
scheduled alarms depend on, that a Night Market is announced once per market
rather than once per background run, that the drought counter never claims more
history than the device has, and that no credential can reach the exportable
log.

`tool/check_readme.dart` keeps this file honest — see below.

---

## Keeping this file current

The version and test count above are checked, not remembered:

```bash
dart tool/check_readme.dart          # fails if a stated fact has drifted
dart tool/check_readme.dart --write  # updates them in place
```

It runs as part of every release, so a published version always ships a README
that matches it. Prose is still a human job; this only guarantees the numbers.

---

## Known gaps

The interface is English and stays that way — a decision, not an unfinished
job. Skin names, rarities and bundle titles still follow
`SettingKeys.language`, since those come from `valorant-api.com` and are Riot's
own translations.

* **iOS.** The Dart is platform-agnostic, but only the Android host project is
  configured, and iOS background execution would need `BGTaskScheduler`
  identifiers in `Info.plist`.
