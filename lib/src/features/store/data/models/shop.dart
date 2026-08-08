import '../../../content/data/models/accessory_item.dart';
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

/// A weekly Accessory Store entry with its items resolved.
class AccessoryOffer {
  const AccessoryOffer({
    required this.offerId,
    required this.items,
    required this.price,
  });

  final String offerId;

  /// Usually one item; occasionally a small bundle of them.
  final List<AccessoryItem> items;

  /// Price in Kingdom Credits.
  final int price;

  AccessoryItem get primary => items.first;

  /// `Spray` / `Gun Buddy` / `Player Card` / `Title`, or a count when the offer
  /// grants several things at once.
  String get subtitle =>
      items.length == 1 ? primary.kind.label : '${items.length} items';
}

/// One resolved item inside a bundle.
///
/// A bundle mixes weapon skins with sprays, buddies, cards and titles, so this
/// holds either — whichever the uuid resolved to. A skin carries its full
/// catalogue entry, which is what makes the row openable into the same detail
/// page the shop uses.
class BundleItem {
  const BundleItem({
    required this.itemId,
    required this.basePrice,
    required this.price,
    this.skin,
    this.tier,
    this.accessory,
    this.amount = 1,
    this.isPromoItem = false,
  });

  final String itemId;

  /// Price on its own, outside the bundle.
  final int basePrice;

  /// Price as part of this bundle.
  final int price;

  /// Set when the item is a weapon or melee skin — the only kind with artwork,
  /// chromas and preview clips worth opening.
  final WeaponSkin? skin;
  final ContentTier? tier;

  /// Set when the item is a spray, buddy, card or title.
  final AccessoryItem? accessory;

  final int amount;
  final bool isPromoItem;

  /// Riot throws one item in for nothing. "Free" is the honest word for it;
  /// "0 VP" reads like a price.
  bool get isFree => price == 0;

  bool get isDiscounted => price < basePrice;

  /// True when there is a detail page worth opening.
  bool get isPreviewable => skin != null;

  String get displayName =>
      skin?.displayName ?? accessory?.displayName ?? 'Unknown item';

  /// `Vandal` / `Spray` / `Gun Buddy` — what kind of thing this is.
  String get subtitle =>
      skin?.weaponName ?? accessory?.kind.label ?? 'Bundle item';

  String? get artwork => skin?.displayIcon ?? skin?.artwork ?? accessory?.artwork;
}

/// A Featured Bundle with its artwork and name resolved.
class BundleOffer {
  const BundleOffer({
    required this.uuid,
    required this.basePrice,
    required this.price,
    required this.discountPercent,
    required this.itemCount,
    required this.endsAt,
    this.info,
    this.items = const <BundleItem>[],
    this.wholesaleOnly = false,
  });

  final String uuid;
  final int basePrice;
  final int price;
  final int discountPercent;
  final int itemCount;

  /// When the bundle leaves the shop. Bundles run for a week or two, on their
  /// own schedule — nothing to do with the daily reset.
  final DateTime endsAt;

  /// Null when the catalogue does not know this bundle yet, which happens for
  /// a day or two after Riot ships a new one.
  final BundleInfo? info;

  /// What is in the bundle, skins first — they are what anyone opens a bundle
  /// to look at, and the accessories are padding by comparison.
  final List<BundleItem> items;

  /// True when the bundle can only be bought whole.
  final bool wholesaleOnly;

  bool get hasItems => items.isNotEmpty;

  /// Items thrown in for nothing.
  List<BundleItem> get freeItems =>
      items.where((BundleItem i) => i.isFree).toList(growable: false);

  String get displayName => info?.displayName ?? 'Featured Bundle';

  int get savings => basePrice - price;

  bool get isDiscounted => price < basePrice;

  Duration get timeRemaining {
    final Duration d = endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}

/// The fully resolved store, ready to render.
class Shop {
  const Shop({
    required this.dailyOffers,
    required this.dailyResetAt,
    required this.nightMarket,
    required this.nightMarketEndsAt,
    required this.capturedAt,
    this.accessories = const <AccessoryOffer>[],
    this.accessoryResetAt,
    this.bundles = const <BundleOffer>[],
  });

  final List<ShopOffer> dailyOffers;
  final DateTime dailyResetAt;

  /// Empty when no Night Market is running.
  final List<NightMarketDeal> nightMarket;
  final DateTime? nightMarketEndsAt;

  /// Weekly Accessory Store offers, priced in Kingdom Credits.
  final List<AccessoryOffer> accessories;

  /// The accessory store rotates weekly, on its own clock — it needs a separate
  /// countdown from the daily shop rather than sharing one.
  final DateTime? accessoryResetAt;

  /// Featured Bundles, each with its own end time.
  final List<BundleOffer> bundles;

  final DateTime capturedAt;

  bool get hasNightMarket => nightMarket.isNotEmpty;
  bool get hasAccessories => accessories.isNotEmpty;
  bool get hasBundles => bundles.isNotEmpty;

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

    // --- Accessory Store ---------------------------------------------------
    final List<AccessoryOffer> accessories = <AccessoryOffer>[];
    for (final RawAccessoryOffer raw in snapshot.accessoryOffers) {
      final List<AccessoryItem> items = raw.rewardIds
          .map(catalog.accessoryByUuid)
          .whereType<AccessoryItem>()
          .toList(growable: false);
      // An offer whose rewards are all unknown would render as a blank row.
      if (items.isEmpty) continue;
      accessories.add(
        AccessoryOffer(offerId: raw.offerId, items: items, price: raw.cost),
      );
    }

    // --- Featured Bundles --------------------------------------------------
    // Bundles are kept even when the catalogue does not know them yet: the
    // price and countdown are still useful, and a new bundle is exactly when
    // someone opens the app.
    final List<BundleOffer> bundles = snapshot.bundles
        .map(
          (RawBundleOffer raw) => BundleOffer(
            uuid: raw.bundleUuid,
            basePrice: raw.basePrice,
            price: raw.discountedPrice,
            discountPercent: raw.discountPercent,
            itemCount: raw.itemCount,
            endsAt: raw.endsAt,
            info: catalog.bundleByUuid(raw.bundleUuid),
            items: _resolveBundleItems(raw.items, catalog),
            wholesaleOnly: raw.wholesaleOnly,
          ),
        )
        .toList(growable: false);

    return Shop(
      dailyOffers: daily,
      dailyResetAt: snapshot.dailyResetAt,
      nightMarket: market,
      nightMarketEndsAt: snapshot.nightMarketEndsAt,
      accessories: accessories,
      accessoryResetAt: snapshot.accessoryResetAt,
      bundles: bundles,
      capturedAt: snapshot.capturedAt,
    );
  }

  /// Resolves a bundle's contents, skins first.
  ///
  /// The uuid is tried as a skin before an accessory rather than trusting
  /// `ItemTypeID`: Riot uses several type ids for skin-shaped things (a level,
  /// a chroma), the catalogue already indexes all of them, and a lookup that
  /// succeeds is better evidence than a type id we would have to keep a list
  /// of. Unresolvable items are dropped — a row with no name and no picture
  /// tells the reader nothing.
  ///
  /// Skins are listed first because they are what anyone opens a bundle to
  /// look at; the sprays and cards are padding by comparison.
  static List<BundleItem> _resolveBundleItems(
    List<RawBundleItem> raw,
    ContentCatalog catalog,
  ) {
    final List<BundleItem> skins = <BundleItem>[];
    final List<BundleItem> extras = <BundleItem>[];

    for (final RawBundleItem item in raw) {
      final WeaponSkin? skin = catalog.skinByOfferUuid(item.itemId);
      if (skin != null) {
        skins.add(
          BundleItem(
            itemId: item.itemId,
            basePrice: item.basePrice,
            price: item.discountedPrice,
            skin: skin,
            tier: catalog.tierOf(skin),
            amount: item.amount,
            isPromoItem: item.isPromoItem,
          ),
        );
        continue;
      }

      final AccessoryItem? accessory = catalog.accessoryByUuid(item.itemId);
      if (accessory == null) continue;
      extras.add(
        BundleItem(
          itemId: item.itemId,
          basePrice: item.basePrice,
          price: item.discountedPrice,
          accessory: accessory,
          amount: item.amount,
          isPromoItem: item.isPromoItem,
        ),
      );
    }

    return <BundleItem>[...skins, ...extras];
  }
}
