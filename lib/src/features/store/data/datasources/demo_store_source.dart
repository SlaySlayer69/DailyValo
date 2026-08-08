import 'dart:math';

import '../../../content/data/models/accessory_item.dart';
import '../../../content/data/models/content_catalog.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../../player/data/models/player_profile.dart';
import '../models/competitive_standing.dart';
import '../models/storefront_snapshot.dart';

/// Generates a plausible store from the *real* content catalogue, with no Riot
/// account involved.
///
/// This is not a mock in the testing sense — it is a first-class app mode. It
/// exists because:
///
/// * the UI can be reviewed, screenshotted and demoed without anyone handing
///   over Riot credentials;
/// * every screen has something to render on first launch;
/// * the notification and wishlist-matching logic can be exercised end to end
///   on a device, on demand, instead of waiting for 00:00 UTC.
///
/// Artwork, names, rarities and chromas are all genuine — only the *offers*
/// are synthesised.
class DemoStoreSource {
  const DemoStoreSource();

  /// Riot rotates the daily shop at 00:00 UTC.
  static DateTime nextShopReset([DateTime? from]) {
    final DateTime now = (from ?? DateTime.now()).toUtc();
    final DateTime midnight = DateTime.utc(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    return midnight.toLocal();
  }

  /// The accessory store rotates weekly, not daily — so its countdown has to be
  /// visibly further out than the daily one, which is the whole reason it gets
  /// its own timer in the UI.
  static DateTime nextAccessoryReset([DateTime? from]) {
    final DateTime midnight = nextShopReset(from).toUtc();
    // Days until the next Wednesday 00:00 UTC, never zero.
    final int ahead = (DateTime.wednesday - midnight.weekday + 7) % 7;
    return midnight.add(Duration(days: ahead)).toLocal();
  }

  /// Typical VP price for each rarity, so the demo shop reads correctly.
  static const Map<String, int> _priceByTier = <String, int>{
    'Select': 875,
    'Deluxe': 1275,
    'Premium': 1775,
    'Ultra': 2475,
    'Exclusive': 2175,
  };

  static int priceFor(ContentTier? tier) =>
      _priceByTier[tier?.devName] ?? 1775;

  /// Builds today's demo storefront.
  ///
  /// Seeded by the calendar day so the shop is stable for the whole day and
  /// genuinely rotates at reset — which is what makes the "shop changed"
  /// detection in the background worker testable.
  StorefrontSnapshot buildStorefront(ContentCatalog catalog) {
    final DateTime now = DateTime.now();
    final int daySeed = now.toUtc().difference(DateTime.utc(2020)).inDays;
    final List<WeaponSkin> pool = catalog.purchasableSkins;

    if (pool.isEmpty) {
      return StorefrontSnapshot(
        dailyOffers: const <RawOffer>[],
        dailyResetAt: nextShopReset(now),
        nightMarketOffers: const <RawNightMarketOffer>[],
        nightMarketEndsAt: null,
        capturedAt: now,
      );
    }

    final List<WeaponSkin> daily = _pick(pool, 4, Random(daySeed));
    final List<RawOffer> offers = daily
        .map(
          (WeaponSkin s) => RawOffer(
            offerId: s.offerUuid,
            cost: priceFor(catalog.tierOf(s)),
          ),
        )
        .toList(growable: false);

    // A Night Market runs for roughly two weeks per act; mirror that cadence so
    // the tab shows both the active and the empty state over time.
    final bool nightMarketActive = (daySeed ~/ 14).isEven;
    final List<RawNightMarketOffer> market = nightMarketActive
        ? _buildNightMarket(catalog, pool, Random(daySeed ~/ 14))
        : const <RawNightMarketOffer>[];

    final List<RawAccessoryOffer> accessories = _buildAccessoryStore(
      catalog,
      Random(daySeed ~/ 7),
    );

    return StorefrontSnapshot(
      dailyOffers: offers,
      dailyResetAt: nextShopReset(now),
      nightMarketOffers: market,
      nightMarketEndsAt: nightMarketActive
          ? nextShopReset(now).add(const Duration(days: 6))
          : null,
      accessoryOffers: accessories,
      accessoryResetAt: accessories.isEmpty ? null : nextAccessoryReset(now),
      bundles: _buildBundles(catalog, now, Random(daySeed ~/ 7)),
      capturedAt: now,
    );
  }

  /// What each kind of accessory typically costs in Kingdom Credits.
  static const Map<AccessoryKind, int> _creditsByKind = <AccessoryKind, int>{
    AccessoryKind.spray: 325,
    AccessoryKind.buddy: 475,
    AccessoryKind.playerCard: 375,
    AccessoryKind.playerTitle: 550,
    AccessoryKind.unknown: 400,
  };

  /// Four weekly accessory offers, drawn from the real catalogue.
  ///
  /// The catalogue indexes each item under several uuids (item *and* level), so
  /// the values are de-duplicated before picking — otherwise the same spray
  /// could turn up twice in one store.
  List<RawAccessoryOffer> _buildAccessoryStore(
    ContentCatalog catalog,
    Random random,
  ) {
    final Map<String, AccessoryItem> unique = <String, AccessoryItem>{};
    for (final AccessoryItem item in catalog.accessories.values) {
      unique[item.uuid] = item;
    }
    if (unique.isEmpty) return const <RawAccessoryOffer>[];

    final List<AccessoryItem> pool = unique.values.toList(growable: false);
    final Set<int> chosen = <int>{};
    final int count = min(4, pool.length);
    while (chosen.length < count) {
      chosen.add(random.nextInt(pool.length));
    }

    return chosen.map((int i) {
      final AccessoryItem item = pool[i];
      return RawAccessoryOffer(
        offerId: 'demo-accessory-${item.uuid}',
        cost: _creditsByKind[item.kind] ?? 400,
        rewardIds: <String>[item.uuid],
      );
    }).toList(growable: false);
  }

  /// One featured bundle, mid-run, at Riot's usual ~22% bundle discount.
  List<RawBundleOffer> _buildBundles(
    ContentCatalog catalog,
    DateTime now,
    Random random,
  ) {
    final List<BundleInfo> pool = catalog.bundles.values.toList(
      growable: false,
    );
    if (pool.isEmpty) return const <RawBundleOffer>[];

    final BundleInfo bundle = pool[random.nextInt(pool.length)];
    final List<RawBundleItem> items = _buildBundleItems(catalog, random);

    // Derived from the items rather than hard-coded, so the detail page adds up
    // — a bundle whose parts do not sum to its price is the first thing anyone
    // would notice.
    final int base = items.fold(
      0,
      (int sum, RawBundleItem i) => sum + i.basePrice,
    );
    final int discounted = items.fold(
      0,
      (int sum, RawBundleItem i) => sum + i.discountedPrice,
    );

    return <RawBundleOffer>[
      RawBundleOffer(
        bundleUuid: bundle.uuid,
        basePrice: base,
        discountedPrice: discounted,
        discountPercent: base == 0
            ? 0
            : ((base - discounted) * 100 / base).round(),
        itemCount: items.length,
        endsAt: now.add(const Duration(days: 9, hours: 4)),
        items: items,
        // Riot's own bundles are mostly breakable; showing the more common case
        // means the demo matches what a real account usually sees.
        wholesaleOnly: false,
      ),
    ];
  }

  /// Four skins at a bundle discount, plus a free accessory if one is known.
  List<RawBundleItem> _buildBundleItems(
    ContentCatalog catalog,
    Random random,
  ) {
    final List<WeaponSkin> pool = catalog.purchasableSkins;
    if (pool.isEmpty) return const <RawBundleItem>[];

    final List<RawBundleItem> items = <RawBundleItem>[];
    for (final WeaponSkin skin in _pick(pool, min(4, pool.length), random)) {
      final int base = priceFor(catalog.tierOf(skin));
      items.add(
        RawBundleItem(
          itemTypeId: _skinLevelTypeId,
          itemId: skin.offerUuid,
          basePrice: base,
          // Riot's bundle discount lands around 20–25% per item.
          discountedPrice: (base * 0.78).round(),
          discountPercent: 22,
        ),
      );
    }

    // The giveaway item — always priced at zero, which is what makes the
    // "free in bundle" path visible without a Riot account.
    final AccessoryItem? extra = catalog.accessories.values
        .where((AccessoryItem a) => a.kind == AccessoryKind.playerCard)
        .firstOrNull;
    if (extra != null) {
      items.add(
        RawBundleItem(
          itemTypeId: AccessoryKind.playerCardTypeId,
          itemId: extra.uuid,
          basePrice: 375,
          discountedPrice: 0,
          discountPercent: 100,
          isPromoItem: true,
        ),
      );
    }

    return items;
  }

  /// Riot's `ItemTypeID` for a weapon skin level, as bundles report it.
  static const String _skinLevelTypeId =
      'e7c63390-eda7-46e0-bb7a-a6abdacd2433';

  List<RawNightMarketOffer> _buildNightMarket(
    ContentCatalog catalog,
    List<WeaponSkin> pool,
    Random random,
  ) {
    // Riot's discounts land on 12–49%, in steps.
    const List<int> discounts = <int>[12, 15, 18, 21, 24, 27, 32, 38, 43, 49];

    return _pick(pool, 6, random).map((WeaponSkin skin) {
      final int base = priceFor(catalog.tierOf(skin));
      final int percent = discounts[random.nextInt(discounts.length)];
      final int discounted = (base * (100 - percent) / 100).round();
      return RawNightMarketOffer(
        offerId: skin.offerUuid,
        basePrice: base,
        discountedPrice: discounted,
        discountPercent: percent,
        isSeen: random.nextBool(),
      );
    }).toList(growable: false);
  }

  Wallet buildWallet() => const Wallet(
    valorantPoints: 3420,
    radianitePoints: 65,
    kingdomCredits: 8150,
  );

  /// A believable slice of the catalogue marked as owned.
  Set<String> buildOwnedSkinLevels(ContentCatalog catalog) {
    final List<WeaponSkin> pool = catalog.purchasableSkins;
    if (pool.isEmpty) return <String>{};
    return _pick(pool, min(48, pool.length), Random(7))
        .map((WeaponSkin s) => s.offerUuid)
        .toSet();
  }

  /// Ascendant 2, 47 RR.
  CompetitiveStanding buildCompetitiveStanding() =>
      const CompetitiveStanding(tier: 22, rankedRating: 47);

  /// Distinct random picks without mutating [pool].
  static List<WeaponSkin> _pick(
    List<WeaponSkin> pool,
    int count,
    Random random,
  ) {
    if (pool.length <= count) return List<WeaponSkin>.of(pool);
    final Set<int> chosen = <int>{};
    while (chosen.length < count) {
      chosen.add(random.nextInt(pool.length));
    }
    return chosen.map((int i) => pool[i]).toList(growable: false);
  }
}
