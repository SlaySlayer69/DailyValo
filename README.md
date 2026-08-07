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
| **Daily Shop** | The four daily offers with high-res artwork, weapon + skin name, VP price, rarity, and a live countdown to reset. |
| **Night Market** | Discounted offers with original price, discount percentage and total savings. Says so plainly when no market is running. |
| **Wishlist** | Searchable picker over the full skin catalogue; entries in today's shop are flagged inline. |
| **Collection** | Every skin you own, grouped and counted by rarity. |

Everywhere: a persistent header with your Riot ID, competitive rank, and VP/RP
balances. Tapping any skin opens a detail page with the full render, every
colour variant, and each upgrade level labelled with what it unlocks (VFX,
sound effects, animation, finisher, …).

**Preview clips.** Riot publishes short MP4s for most levels and for chromas
with unique VFX. Tapping a level plays its clip; a `PREVIEW` button on the
artwork plays the clip for the selected variant, falling back to the base
skin's when that variant has none. A still image cannot show you what a
finisher does.

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

---

## Getting started

```bash
flutter pub get
flutter run                 # debug build on a connected device/emulator
flutter test                # 90 unit tests, no device needed
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
    │   ├── store/                   Storefront, night market, demo source
    │   ├── wishlist/                Hive-backed wishlist + picker
    │   ├── collection/              Owned skins
    │   ├── skin_detail/             Artwork, chromas, upgrade levels
    │   └── home/                    Tab shell + settings sheet
    └── services/
        ├── notifications/           Channels and the two notification shapes
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

90 unit tests, no device or network required:

```
test/
├── storefront_parser_test.dart     Riot payload → snapshot, incl. malformed input
├── content_catalog_test.dart       UUID → skin resolution, cache round trip
├── shop_resolution_test.dart       Joining offers to names/owned/wishlist state
├── wishlist_repository_test.dart   Hive persistence and shop matching
├── notification_format_test.dart   Locks in the two notification body formats
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

* **Bundles.** `FeaturedBundle` is parsed past, not surfaced.
* **Accessory store.** Kingdom Credit offers are read into the wallet but have
  no tab.
* **Localisation.** The UI is English-only; the *content* language is already
  wired through (`SettingKeys.language` → `valorant-api.com?language=`), so
  adding `flutter_localizations` would finish the job.
* **iOS.** The Dart is platform-agnostic, but only the Android host project is
  configured, and iOS background execution would need `BGTaskScheduler`
  identifiers in `Info.plist`.
