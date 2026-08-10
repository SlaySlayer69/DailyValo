# DailyValo

An unofficial Valorant shop and skin tracker for Android, built with Flutter.

DailyValo shows your daily store, the Night Market when one is running, a
wishlist you can be alerted on, and your skin collection — with full artwork,
chromas and upgrade levels. It notifies you at shop reset, silently, and only
buzzes when something you are actually hunting for shows up.

> DailyValo is not affiliated with, endorsed by, or sponsored by Riot Games. It
> uses the same undocumented client endpoints the official desktop client uses.
> See [Security and Riot's APIs](#security-and-riots-apis).

---

## Features

| Tab | What it does |
| --- | --- |
| **Daily Shop** | The four daily offers with high-res artwork, weapon + skin name, VP price, rarity, and a live countdown to reset. Below them, the **Accessory Store** (sprays, buddies, cards, titles in Kingdom Credits) on its own weekly countdown, and the **Featured Bundles** with their key art, discount and time left — tap one to see every item in it, what each costs alone, which is free, and whether the bundle can be split. |
| **Night Market** | Discounted offers with original price, discount percentage and total savings. Says so plainly when no market is running. |
| **Wishlist** | Exportable and importable as a file. Searchable picker over the full skin catalogue, in buy-menu order — weapon class, then weapon, then rarity. Entries in today's shop are flagged inline. Tapping a skin opens its detail page, here as everywhere else — the heart is the only control that adds or removes, and removal is undoable. |
| **Collection** | Every skin you own, grouped and counted by rarity. The rarity counts double as filters — tap Ultra and Premium to see only those — and the tab shows what the selection is worth at shop prices. |

Everywhere: a persistent header with your Riot ID, competitive rank, and your
Valorant Point, Radianite and Kingdom Credit balances. Tapping any skin opens a detail page with the full render, every
colour variant, and each upgrade level labelled with what it unlocks (VFX,
sound effects, animation, finisher, …).

**Preview clips.** Riot publishes short MP4s for most levels and for chromas
with unique VFX. Tapping a level plays its clip; a `PREVIEW` button on the
artwork plays the clip for the selected variant, falling back to the base
skin's when that variant has none. A still image cannot show you what a
finisher does.

**Three clocks, not one.** The shop tab runs three independent countdowns
because Riot runs three independent schedules: the four daily skins roll over at
00:00 UTC, the Accessory Store rotates weekly, and each Featured Bundle leaves
on its own date. Sharing one timer would have shown the wrong number on two of
the three sections, so each section carries its own — and each refetches the
storefront when it reaches zero, rather than displaying `00:00:00` over stale
offers.

### Notifications

Two notifications, two Android channels, deliberately different:

| | Daily shop | Wishlist hit |
| --- | --- | --- |
| Fires when | The four offers rotate | A wishlisted skin is among them |
| Importance | `low` — silent, no heads-up | `high` — sound + vibration |
| Title | `DailyValo` | `DailyValo` |
| Body | `Vandal: Prime Vandal - Sheriff: Reaver Sheriff - Phantom: Ion - Melee: Karambit` | `An item on your wishlist is in your shop!` |

Separate channels mean a user can silence the daily digest and keep the
wishlist alert from Android's own settings, with no in-app toggle required
(though there are toggles too, under the header's ⋮ menu).

**What counts as "new".** A rotation is detected by comparing the current offer
ids against *the ones the user was last told about* — a record with its own
storage key, written only after a notification has actually gone out. The
obvious shortcut, comparing against the cached shop, is wrong in a way that is
invisible until someone complains: that cache is overwritten by every fetch,
including the one the Daily Shop tab makes when the app opens. Opening the app
at 02:00 to look at the fresh shop wrote the new offers into the baseline before
anything compared against them, so the rotation was consumed silently and its
notification could never fire. `test/notification_baseline_test.dart` pins the
separation, including that a cache write leaves the baseline alone and that
"never notified" stays distinguishable from "notified about an empty shop".

The check runs on first frame as well as on resume. `didChangeAppLifecycleState`
is not called on a cold start — the app is already `resumed` when the observer
is registered — so wiring it to resume alone meant launching from the launcher,
which is how anyone opens the app at two in the morning, checked nothing.

**Delivery time.** By default both fire as soon as the rotation is noticed,
which is the freshest answer but lands at 02:00 in much of Europe. Settings ▸
*Notification time* holds them back to an hour you pick. Detection still happens
at reset — only the delivery moves, and nothing about the shop changes in
between, so a held notification is still correct when it arrives. The alarm is
handed to Android via `zonedSchedule` rather than waking a worker at the chosen
hour: the OS delivers it whether or not the app gets scheduled, and it survives
a reboot.

The alarm is **exact when Android permits it and inexact when it does not**.
`SCHEDULE_EXACT_ALARM` is declared and requested at the moment the delivery time
is switched on — the only moment the app has a time to be punctual about — and a
refusal costs punctuality rather than the notification. It matters more than it
sounds: an inexact alarm is batched into the next Doze maintenance window, so a
digest set for 09:00 can land at 09:20 on a phone that slept through the night,
with nothing actually broken. The diagnostics screen reports which of the two is
in force.

Delivery is anchored to the **rotation**, not to the moment the app noticed it.
Computing it from *now* meant a background check that Android deferred past the
chosen hour scheduled the digest for that hour *tomorrow*, and the day it was
about passed in silence — a phone asleep from 02:00 to 09:20 got nothing at all.
`deliveryFor` resolves the first occurrence of the chosen wall clock after the
rotation, and posts immediately when that instant is already behind us.

Nothing sets a timeout on either notification and neither is `ongoing`, so one
stays in the shade until it is swiped, opened, or cleared by opening the app.
That last part cancels only ids Android reports as *currently showing*:
`cancel(id:)` removes a posted notification and a queued alarm under the same
id alike, so clearing the shade indiscriminately would silently delete the 09:00
delivery of anyone who opened the app at 08:00.

The chosen time is a **wall clock in the device's own timezone**, read via
`flutter_timezone` and resolved against the IANA database. That is not
pedantry: computing the target by adding nine hours to midnight lands at 10:00
on the day the clocks go forward, because a duration is absolute and a clock
change is not. Building the moment from wall-clock components in a real zone
gets both transitions right, and the notification plugin stores the zone
alongside the alarm so a reboot re-arms against the same wall clock rather than
the same offset. Both clock-change days are covered by tests against the real
database.

**Sharing.** The share button renders a purpose-built card off-screen and hands
the PNG to Android's share sheet — not a screenshot, so there is no status bar,
no half-scrolled list, and it looks the same from every phone. The skins sit
side by side with the artwork given most of each tile: a shop is something you
*look* at, so the name and price are the caption rather than the subject.

Two constraint traps live here, both of which shipped broken once and are now
pinned by tests. An overlay child is limited to the screen, so a card asking for
1420 logical pixels was silently rendered at the phone's 411 with 1420-scale
type inside it. And `OverflowBox` forwards the parent's *minimum* constraints
unless told otherwise, which inflates a card narrower than the screen to screen
size and bakes a margin of empty background into the image. `test/share_card_test.dart`
asserts the exact canvas width for one, four and six offers, that the wordmark
is centred to within a pixel, and that long names such as *Singularity Sheriff*
are not cut to an ellipsis.

**The home screen widget** is four skin renders in a 2x2 grid on black, each
framed in the colour of its rarity, with no text at all. A grid rather than a
row of four: a weapon render is wide, and four tiles side by side are tall
strips that waste most of their height on empty background while shrinking the
skin to fit the narrow width. RemoteViews cannot load a URL, so the
artwork is downloaded by the app and the paths handed to the widget provider,
which decodes them in the app's own process and passes bitmaps through the
RemoteViews parcel — a `file://` URI from app-private storage is not readable by
the launcher. The frame is a tinted box behind a black-backed image, because
RemoteViews can set a background colour but cannot restyle a drawable's stroke.

**What a collection is worth.** Riot publishes no prices and no purchase
history, so the Collection total is derived from the price points Riot uses per
rarity — doubled for melee, which is priced differently and is exactly what
people collect. That makes it an estimate of what the skins *cost*, never of
what was paid: Night Market and bundle discounts leave no trace the app can
read. Skins that were never sold are counted separately rather than guessed at.

---

## Getting started

```bash
flutter pub get
flutter run                 # debug build on a connected device/emulator
flutter test                # 208 unit tests, no device needed
flutter analyze             # zero warnings expected
```

Requires Flutter 3.44+ / Dart 3.12+. Android only for now (`minSdk 24`).

### Demo mode

Tap **Explore in demo mode** on the sign-in screen. No Riot account, no
credentials, no network calls to Riot at all.

Demo mode is a first-class app mode, not a stub: it fetches the *real* content
catalogue from `valorant-api.com`, so all artwork, names, rarities, chromas and
upgrade levels are genuine — only the offers are synthesised. They are seeded by
the calendar day, so the shop is stable for 24 hours and genuinely rotates at
00:00 UTC, which means the reset detection and notification pipeline can be
exercised end to end without waiting for a real reset.

Use **Settings → Check my shop now** to run the background worker's exact logic
on demand.

---

## Architecture

Feature-first, with a `data` / `presentation` split inside each feature and a
shared `core`.

```
lib/
├── main.dart                        Bootstrap: graph → workmanager → runApp
└── src/
    ├── app/
    │   ├── app.dart                 MaterialApp + AuthGate
    │   ├── dependencies.dart        The object graph (see below)
    │   ├── providers.dart           Riverpod view over the graph
    │   └── theme/                   Colours, type scale, ThemeData
    ├── core/
    │   ├── constants/               Riot endpoints, UUIDs, storage keys
    │   ├── errors/                  Sealed AppException family
    │   ├── network/                 Dio factories, auth + error interceptors,
    │   │                            session manager, client-version holder
    │   ├── storage/                 Secure token store, Hive façade
    │   ├── utils/                   JWT reader, formatters, logger
    │   └── widgets/                 RemoteImage, Countdown, state views
    ├── features/
    │   ├── auth/                    RSO login, MFA, silent re-auth
    │   ├── content/                 valorant-api.com catalogue + cache
    │   ├── player/                  Riot ID, rank, wallet → header
    │   ├── store/                   Storefront, night market, accessories,
    │   │                            bundles, demo source
    │   ├── wishlist/                Hive-backed wishlist + picker
    │   ├── collection/              Owned skins
    │   ├── skin_detail/             Artwork, chromas, upgrade levels
    │   └── home/                    Tab shell + settings sheet
    └── services/
        ├── notifications/           Channels and the two notification shapes
        ├── widgets/                 Home screen widget bridge
        └── background/              WorkManager dispatcher + sync service
```

### The object graph lives outside Riverpod

`AppDependencies.bootstrap()` builds the entire graph as a plain object. It is
called **twice per device**: once by `main()`, once by the WorkManager isolate.

That is the reason it is not a set of Riverpod providers. A background isolate
has no widget tree, no `ProviderScope`, and no shared state with `main()` — it
starts cold. Building the graph as a plain class means the worker and the UI are
provably wired the same way, and `app/providers.dart` is a thin read-only view
over it for the widgets.

### Data flow

```
valorant-api.com ──► ContentRepository ──┐
                     (Hive, 24h stale)   │
                                         ├──► Shop.resolve ──► UI
Riot PD /storefront ─► StoreRepository ──┤
                       (Hive snapshot)   │
Hive wishlist ─────► WishlistRepository ─┘
```

The storefront returns nothing but UUIDs and prices. Everything human-readable
comes from joining those UUIDs against the content catalogue — which is why the
raw `StorefrontSnapshot` and the resolved `Shop` are separate types. The
background worker persists and compares snapshots without ever loading the 4 MB
catalogue.

### Riot's content types are not uniform

Dio only parses a response body when its `content-type` announces JSON. Riot
does that on the wallet, storefront and entitlements routes but **not** on the
MMR ones — those return the same JSON under a content type Dio leaves alone, so
`response.data` arrives as a `String`.

Every map lookup against a string yields nothing, so a 19 KB rank record read
as "no rank" and the header confidently displayed *Unranked* for a ranked
player. HTTP 200, no exception, nothing in the logs. `JsonResponseInterceptor`
normalises this for every PD client, and the parsing layer decodes a raw string
too rather than trusting that it was already handled.

### Detecting a shop reset

Not by clock. By **comparing the persisted set of offer ids** to the freshly
fetched one.

A wall clock is not trustworthy here: the device may be asleep past 00:00 UTC,
Doze can defer a worker for hours, the timezone can change mid-flight, and the
user can travel. The offer set is the only honest signal that a rotation
happened, and it is idempotent — a double fire costs one wasted request.

Two overlapping schedules feed it:

* a **one-off** task aimed three minutes after the next known reset (accurate,
  re-armed on every sync);
* a **periodic** task every six hours (catches the one-off being dropped by
  Doze, app standby, or a reboot).

Plus a foreground check on app resume, since that costs the user nothing.

### State management

Riverpod 2, no code generation. `AsyncNotifier` for the shop and player header,
`Notifier` for the wishlist and app mode, `Provider.family` for per-skin
wishlist state so a heart tap rebuilds one card rather than the grid.

The countdown timer is deliberately **not** in app state — a second-resolution
clock in a provider would rebuild the whole shop sixty times a minute. It lives
in a `StatefulWidget` that repaints only the four characters that changed.

---

## Security and Riot's APIs

### App icon

A DV monogram: grey D, red V, near-black where the two planes cross, on a dark
radial ground. Ships as an adaptive icon (background + foreground + monochrome
layers) plus legacy square and round PNGs for API 24–25. The glyph is
constrained to a 48x44 box inside the 108 grid so every corner stays within the
66dp keyline circle — otherwise round and squircle launcher masks slice the V.
`tool/generate_app_icon.py` regenerates every density.

### What is stored, and where

| Data | Where | Why |
| --- | --- | --- |
| Password | **Nowhere** | Typed into Riot's own page in a WebView; never seen by the app. |
| RSO `ssid` cookie | Android Keystore (AES-GCM, RSA-wrapped) | Mints fresh access tokens without the password. Revocable by the user server-side. |
| Access / entitlements / id tokens | Android Keystore | Expire in ~1 hour; refreshed silently. |
| Wishlist, catalogue, shop snapshot | Hive (plain files) | Not sensitive. Nothing credential-shaped ever goes in a Hive box. |

Sign-out deletes every credential and cancels all background work. The
`Log` helper is a no-op in release builds, because request bodies in this app
carry bearer tokens and Android log buffers are readable by more things than
you would like.

### The auth flow

Sign-in happens in a **WebView on Riot's own hosted login page**. The app never
sees the password.

```
(WebView) GET /authorize          → user signs in on Riot's page
                                    (2FA, captcha, Riot Mobile push — all theirs)
          → 303 playvalorant.com/opt_in#access_token=…
POST entitlements/api/token/v1    → X-Riot-Entitlements-JWT
POST /userinfo                    → PUUID + Riot ID
PUT  /pas/v1/product/valorant     → PAS token → live affinity → PD shard
```

The direct username/password endpoint was tried first and removed. It cannot
complete a sign-in for any account Riot protects with push confirmation or a
captcha: it answers `auth_failure` even when the password is correct, which is
indistinguishable from a typo and impossible for a user to act on.

Later refreshes skip the WebView entirely: the `ssid` cookie captured from its
jar is replayed against `GET /authorize`, which 303s back with a fresh token
pair. That is what lets the **background isolate** refresh tokens — a WebView
needs an Activity and cannot run from WorkManager.

The cookie is read through a small `MethodChannel` rather than
`webview_flutter`'s own `getCookies`, which splits each cookie on every `=` and
keeps the last segment — silently truncating an opaque token that contains one.
A truncated `ssid` would sign you in once and then quietly break every refresh
afterwards.

The cookie is re-read on **every app resume**, not just at sign-in, and a stored
one is enough to rebuild a whole session on its own — `signInWithStoredCookie`
needs nothing from a previous session, because a session is exactly what a token
pair plus an entitlements JWT already is. Both of those exist because the
failure they prevent is close to silent. If the capture at sign-in came back
empty, or Riot rotated the cookie since, the next refresh fails with
`requiresReLogin`, the session manager signs you out, and the visible symptom is
a *Login with Riot* button that signs you straight in again without asking for
anything — mildly annoying, and easy to live with. What is not visible is that
`canFetchShop` is now false, so every background run skips, no rotation is ever
detected, and no notification is ever scheduled. Nothing arrives to tell you
nothing arrived.

### Two things worth knowing before you ship this

1. **These endpoints are undocumented.** They are the same ones the official
   client uses, and they are stable in practice, but Riot owes no compatibility
   here. Riot's third-party developer policy prohibits automating gameplay and
   misrepresenting affiliation; a read-only shop viewer is the same shape as
   the many community trackers that exist, but you should read the current
   policy yourself before publishing. Every endpoint and constant is centralised
   in `core/constants/riot_constants.dart` so an upstream change is a one-file
   fix.

2. **The app no longer handles credentials at all.** Sign-in is a WebView on
   Riot's page; DailyValo only ever receives the redirect at the end. Keep it
   that way — reintroducing a password field would both weaken this and break
   sign-in for push-protected accounts.

---

## Testing

208 unit tests, no device or network required:

```
test/
├── storefront_parser_test.dart     Riot payload → snapshot, incl. malformed input
├── content_catalog_test.dart       UUID → skin resolution, cache round trip
├── shop_resolution_test.dart       Joining offers to names/owned/wishlist state
├── accessories_and_bundles_test.dart
│                                   Accessory/bundle parsing, resolution,
│                                   bundle contents, separate reset clocks
├── wishlist_repository_test.dart   Hive persistence and shop matching
├── notification_format_test.dart   Locks in the two notification body formats
├── notification_schedule_test.dart Delivery time: rotation-anchored, real DST days
├── notification_baseline_test.dart "Already told them about these?" vs the shop cache
├── demo_store_source_test.dart     Determinism, pricing, reset timing
├── session_and_utils_test.dart     JWT claims, token expiry, shard routing
├── web_login_test.dart             Cookie-header parsing, redirect detection
├── wallet_and_rank_test.dart       Currency UUIDs, unranked-vs-unknown
├── store_api_test.dart             PD endpoint parsing and fallbacks (stubbed HTTP)
└── support/fixtures.dart           Realistic API payloads
```

The notification format test exists because those strings are product spec, not
implementation detail — a refactor should not be able to change them silently.

---

## Known gaps

Deliberately out of scope for this pass, in rough priority order:

* **Bundle contents.** A bundle shows its key art, price, discount and item
  count, but not the list of skins inside it — that needs a second lookup per
  bundle against the catalogue's item references.
* **Accessory ownership.** Owned sprays, buddies and cards are not flagged the
  way owned skins are; the entitlements call for those item types is not wired
  up yet.
* **Localisation.** The UI is English-only; the *content* language is already
  wired through (`SettingKeys.language` → `valorant-api.com?language=`), so
  adding `flutter_localizations` would finish the job.
* **iOS.** The Dart is platform-agnostic, but only the Android host project is
  configured, and iOS background execution would need `BGTaskScheduler`
  identifiers in `Info.plist`.
