import '../../../content/data/models/content_catalog.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/weapon_skin.dart';
import 'storefront_snapshot.dart';

/// A daily-shop entry with its artwork and names resolved.
class ShopOffer {
  const ShopOffer({
    required this.offerId,
    required this.skin,
    required this.price,
    this.tier,
    this.isOwned = false,
    this.isWishlisted = false,
  });

  final String offerId;
  final WeaponSkin skin;

  /// Price in Valorant Points.
  final int price;

  final ContentTier? tier;

  /// Already in the player's collection — worth flagging, since Riot will
  /// happily show you a skin you own.
  final bool isOwned;

  final bool isWishlisted;

  ShopOffer copyWith({bool? isOwned, bool? isWishlisted}) => ShopOffer(
    offerId: offerId,
    skin: skin,
    price: price,
    tier: tier,
    isOwned: isOwned ?? this.isOwned,
    isWishlisted: isWishlisted ?? this.isWishlisted,
  );
}

/// A Night Market entry with its discount resolved.
class NightMarketDeal {
  const NightMarketDeal({
    required this.offerId,
    required this.skin,
    required this.basePrice,
    required this.price,
    required this.discountPercent,
    required this.isSeen,
    this.tier,
    this.isWishlisted = false,
  });

  final String offerId;
  final WeaponSkin skin;
  final int basePrice;
  final int price;
  final int discountPercent;

  /// Whether the card has been revealed in game.
  final bool isSeen;

  final ContentTier? tier;
  final bool isWishlisted;

  int get savings => basePrice - price;
}

/// The fully resolved store, ready to render.
class Shop {
  const Shop({
    required this.dailyOffers,
    required this.dailyResetAt,
    required this.nightMarket,
    required this.nightMarketEndsAt,
    required this.capturedAt,
  });

  final List<ShopOffer> dailyOffers;
  final DateTime dailyResetAt;

  /// Empty when no Night Market is running.
  final List<NightMarketDeal> nightMarket;
  final DateTime? nightMarketEndsAt;

  final DateTime capturedAt;

  bool get hasNightMarket => nightMarket.isNotEmpty;

  Duration get timeUntilReset {
    final Duration d = dailyResetAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Duration? get timeUntilNightMarketEnds {
    final DateTime? end = nightMarketEndsAt;
    if (end == null) return null;
    final Duration d = end.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// Wishlisted skins currently on offer — the trigger for the alert
  /// notification, and the banner at the top of the shop tab.
  List<ShopOffer> get wishlistHits =>
      dailyOffers.where((ShopOffer o) => o.isWishlisted).toList(growable: false);

  /// Joins raw offer UUIDs to the content catalogue.
  ///
  /// Offers whose UUID is unknown to the catalogue are dropped rather than
  /// rendered as a blank card — that happens for a day or two after a patch
  /// adds skins the community mirror has not indexed yet.
  factory Shop.resolve({
    required StorefrontSnapshot snapshot,
    required ContentCatalog catalog,
    Set<String> ownedSkinUuids = const <String>{},
    Set<String> wishlistedSkinUuids = const <String>{},
  }) {
    final List<ShopOffer> daily = <ShopOffer>[];
    for (final RawOffer raw in snapshot.dailyOffers) {
      final WeaponSkin? skin = catalog.skinByOfferUuid(raw.offerId);
      if (skin == null) continue;
      daily.add(
        ShopOffer(
          offerId: raw.offerId,
          skin: skin,
          price: raw.cost,
          tier: catalog.tierOf(skin),
          isOwned: ownedSkinUuids.contains(skin.offerUuid),
          isWishlisted: wishlistedSkinUuids.contains(skin.uuid),
        ),
      );
    }

    final List<NightMarketDeal> market = <NightMarketDeal>[];
    for (final RawNightMarketOffer raw in snapshot.nightMarketOffers) {
      final WeaponSkin? skin = catalog.skinByOfferUuid(raw.offerId);
      if (skin == null) continue;
      market.add(
        NightMarketDeal(
          offerId: raw.offerId,
          skin: skin,
          basePrice: raw.basePrice,
          price: raw.discountedPrice,
          discountPercent: raw.discountPercent,
          isSeen: raw.isSeen,
          tier: catalog.tierOf(skin),
          isWishlisted: wishlistedSkinUuids.contains(skin.uuid),
        ),
      );
    }

    return Shop(
      dailyOffers: daily,
      dailyResetAt: snapshot.dailyResetAt,
      nightMarket: market,
      nightMarketEndsAt: snapshot.nightMarketEndsAt,
      capturedAt: snapshot.capturedAt,
    );
  }
}
