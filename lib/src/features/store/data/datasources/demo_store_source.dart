import 'dart:math';

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

    return StorefrontSnapshot(
      dailyOffers: offers,
      dailyResetAt: nextShopReset(now),
      nightMarketOffers: market,
      nightMarketEndsAt: nightMarketActive
          ? nextShopReset(now).add(const Duration(days: 6))
          : null,
      capturedAt: now,
    );
  }

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
