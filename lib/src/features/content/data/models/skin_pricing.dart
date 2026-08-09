import 'content_tier.dart';
import 'weapon_skin.dart';

/// What a skin costs at full price in the shop.
///
/// Riot does not publish prices anywhere — not in the content API, not in the
/// player's inventory. The storefront quotes a price only for the handful of
/// skins on offer today. So a collection's worth cannot be looked up; it has to
/// be derived from the price points Riot actually uses, which are fixed per
/// rarity and have not moved in years.
///
/// That makes every total an **estimate**, and the UI has to say so. Two things
/// it can never be:
///
/// * **What was paid.** Night Market and bundle purchases were discounted, and
///   Riot exposes no purchase history at all — not the price, not the date, not
///   even that a discount applied. A skin bought at 40% off is indistinguishable
///   from one bought at full price.
/// * **Complete.** Battlepass and event-reward skins were never sold, and a few
///   promotional skins sit outside the normal tiers. Those are counted
///   separately rather than guessed at.
abstract final class SkinPricing {
  /// Riot's standard price points for a gun skin, by rarity.
  static const Map<String, int> gunPrices = <String, int>{
    'Select': 875,
    'Deluxe': 1275,
    'Premium': 1775,
    'Exclusive': 2175,
    'Ultra': 2475,
  };

  /// Melee skins cost twice the gun price at the same rarity — a Premium knife
  /// is 3,550 where a Premium rifle is 1,775. Pricing knives off the gun table
  /// would understate a collection by thousands of VP, since knives are exactly
  /// what people collect.
  static const int meleeMultiplier = 2;

  static const String meleeCategory = 'Melee';

  /// Full shop price in VP, or null when the skin has no rarity we can price —
  /// battlepass and event rewards, which were never on sale.
  static int? priceOf(WeaponSkin skin, ContentTier? tier) {
    final int? base = gunPrices[tier?.devName];
    if (base == null) return null;
    return skin.weaponCategory == meleeCategory ? base * meleeMultiplier : base;
  }
}

/// What a set of owned skins is worth, and how much of it could be priced.
class CollectionValue {
  const CollectionValue({
    required this.totalVp,
    required this.pricedCount,
    required this.unpricedCount,
  });

  static const CollectionValue empty = CollectionValue(
    totalVp: 0,
    pricedCount: 0,
    unpricedCount: 0,
  );

  /// Sum of the full shop prices of every skin that has one.
  final int totalVp;

  final int pricedCount;

  /// Skins with no sale price — battlepass and event rewards. Reported rather
  /// than folded in at zero, so the total is not quietly wrong.
  final int unpricedCount;

  int get skinCount => pricedCount + unpricedCount;

  bool get isComplete => unpricedCount == 0;

  /// Prices [skins] with [tierOf], skipping anything Riot never sold.
  static CollectionValue of(
    Iterable<WeaponSkin> skins,
    ContentTier? Function(WeaponSkin) tierOf,
  ) {
    int total = 0;
    int priced = 0;
    int unpriced = 0;

    for (final WeaponSkin skin in skins) {
      final int? price = SkinPricing.priceOf(skin, tierOf(skin));
      if (price == null) {
        unpriced++;
        continue;
      }
      total += price;
      priced++;
    }

    return CollectionValue(
      totalVp: total,
      pricedCount: priced,
      unpricedCount: unpriced,
    );
  }
}
