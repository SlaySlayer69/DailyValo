/// Raw storefront data, exactly as Riot returns it — UUIDs and prices, no names.
///
/// This layer is kept separate from the resolved [Shop] on purpose:
///
/// * the background worker persists *this* to compare "did the shop reset?"
///   without needing the 4 MB content catalogue in memory;
/// * it round-trips to JSON losslessly;
/// * resolving names is a pure function of this plus the catalogue, so it can
///   happen later, on a different isolate, or not at all.
library;

/// One daily-shop entry.
class RawOffer {
  const RawOffer({required this.offerId, required this.cost});

  /// A skin *level* UUID — resolve via `ContentCatalog.skinByOfferUuid`.
  final String offerId;

  /// Price in Valorant Points.
  final int cost;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'offerId': offerId,
    'cost': cost,
  };

  factory RawOffer.fromJson(Map<String, dynamic> json) => RawOffer(
    offerId: json['offerId'] as String? ?? '',
    cost: (json['cost'] as num?)?.toInt() ?? 0,
  );
}

/// One Night Market entry: the same skin, discounted, revealed by tapping.
class RawNightMarketOffer {
  const RawNightMarketOffer({
    required this.offerId,
    required this.basePrice,
    required this.discountedPrice,
    required this.discountPercent,
    required this.isSeen,
  });

  final String offerId;

  /// Full price in VP.
  final int basePrice;

  /// What the player actually pays.
  final int discountedPrice;

  /// Riot's own percentage, 0–100.
  final int discountPercent;

  /// Whether the card has already been flipped in game.
  final bool isSeen;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'offerId': offerId,
    'basePrice': basePrice,
    'discountedPrice': discountedPrice,
    'discountPercent': discountPercent,
    'isSeen': isSeen,
  };

  factory RawNightMarketOffer.fromJson(Map<String, dynamic> json) =>
      RawNightMarketOffer(
        offerId: json['offerId'] as String? ?? '',
        basePrice: (json['basePrice'] as num?)?.toInt() ?? 0,
        discountedPrice: (json['discountedPrice'] as num?)?.toInt() ?? 0,
        discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
        isSeen: json['isSeen'] as bool? ?? false,
      );
}

/// One weekly Accessory Store entry: sprays, buddies, cards and titles, priced
/// in Kingdom Credits rather than Valorant Points.
class RawAccessoryOffer {
  const RawAccessoryOffer({
    required this.offerId,
    required this.cost,
    required this.rewardIds,
    this.contractId,
  });

  final String offerId;

  /// Price in Kingdom Credits.
  final int cost;

  /// Item uuids granted by the offer — usually one, occasionally several.
  /// These may be *level* uuids for buddies and sprays.
  final List<String> rewardIds;

  final String? contractId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'offerId': offerId,
    'cost': cost,
    'rewardIds': rewardIds,
    'contractId': contractId,
  };

  factory RawAccessoryOffer.fromJson(Map<String, dynamic> json) =>
      RawAccessoryOffer(
        offerId: json['offerId'] as String? ?? '',
        cost: (json['cost'] as num?)?.toInt() ?? 0,
        rewardIds:
            (json['rewardIds'] as List<dynamic>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[],
        contractId: json['contractId'] as String?,
      );
}

/// One entry inside a Featured Bundle.
///
/// Bundles price each item separately, which is the only way to answer the two
/// questions worth asking about a bundle: what is actually in it, and which
/// parts are thrown in for nothing.
class RawBundleItem {
  const RawBundleItem({
    required this.itemTypeId,
    required this.itemId,
    required this.basePrice,
    required this.discountedPrice,
    this.amount = 1,
    this.discountPercent = 0,
    this.isPromoItem = false,
  });

  /// Riot's `ItemTypeID` — a skin level, a spray, a buddy, a card, a title.
  final String itemTypeId;

  /// The uuid to resolve against the catalogue.
  final String itemId;

  /// What the item costs on its own, outside the bundle.
  final int basePrice;

  /// What it costs as part of this bundle. Zero for the promo item Riot throws
  /// in — which is worth showing as *free*, not as "0 VP".
  final int discountedPrice;

  final int amount;
  final int discountPercent;

  /// Riot's own flag for the giveaway item.
  final bool isPromoItem;

  bool get isFree => discountedPrice == 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'itemTypeId': itemTypeId,
    'itemId': itemId,
    'basePrice': basePrice,
    'discountedPrice': discountedPrice,
    'amount': amount,
    'discountPercent': discountPercent,
    'isPromoItem': isPromoItem,
  };

  factory RawBundleItem.fromJson(Map<String, dynamic> json) => RawBundleItem(
    itemTypeId: json['itemTypeId'] as String? ?? '',
    itemId: json['itemId'] as String? ?? '',
    basePrice: (json['basePrice'] as num?)?.toInt() ?? 0,
    discountedPrice: (json['discountedPrice'] as num?)?.toInt() ?? 0,
    amount: (json['amount'] as num?)?.toInt() ?? 1,
    discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
    isPromoItem: json['isPromoItem'] as bool? ?? false,
  );
}

/// A Featured Bundle as the storefront describes it.
class RawBundleOffer {
  const RawBundleOffer({
    required this.bundleUuid,
    required this.basePrice,
    required this.discountedPrice,
    required this.discountPercent,
    required this.itemCount,
    required this.endsAt,
    this.items = const <RawBundleItem>[],
    this.wholesaleOnly = false,
  });

  /// `DataAssetID` — the uuid that matches valorant-api's bundle content.
  final String bundleUuid;

  final int basePrice;
  final int discountedPrice;

  /// 0–100. Riot sends a fraction; this is already scaled.
  final int discountPercent;

  final int itemCount;

  /// Absolute time the bundle leaves the shop.
  final DateTime endsAt;

  /// What is in the bundle, each with its own price.
  final List<RawBundleItem> items;

  /// True when Riot sells the bundle only as a whole — no picking one skin out
  /// of it. This is the single most useful thing to know before opening the
  /// store, and it varies bundle to bundle.
  final bool wholesaleOnly;

  int get savings => basePrice - discountedPrice;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'bundleUuid': bundleUuid,
    'basePrice': basePrice,
    'discountedPrice': discountedPrice,
    'discountPercent': discountPercent,
    'itemCount': itemCount,
    'endsAt': endsAt.toIso8601String(),
    'items': items.map((RawBundleItem i) => i.toJson()).toList(),
    'wholesaleOnly': wholesaleOnly,
  };

  factory RawBundleOffer.fromJson(Map<String, dynamic> json) => RawBundleOffer(
    bundleUuid: json['bundleUuid'] as String? ?? '',
    basePrice: (json['basePrice'] as num?)?.toInt() ?? 0,
    discountedPrice: (json['discountedPrice'] as num?)?.toInt() ?? 0,
    discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
    itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
    endsAt:
        DateTime.tryParse(json['endsAt'] as String? ?? '') ?? DateTime.now(),
    items:
        (json['items'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(RawBundleItem.fromJson)
            .toList(growable: false) ??
        const <RawBundleItem>[],
    wholesaleOnly: json['wholesaleOnly'] as bool? ?? false,
  );
}

/// A point-in-time capture of the player's store.
class StorefrontSnapshot {
  const StorefrontSnapshot({
    required this.dailyOffers,
    required this.dailyResetAt,
    required this.nightMarketOffers,
    required this.nightMarketEndsAt,
    required this.capturedAt,
    this.accessoryOffers = const <RawAccessoryOffer>[],
    this.accessoryResetAt,
    this.bundles = const <RawBundleOffer>[],
  });

  final List<RawOffer> dailyOffers;

  /// Absolute time the four daily offers roll over. Derived once from Riot's
  /// relative `...RemainingDurationInSeconds` so the countdown stays correct
  /// across app restarts without re-fetching.
  final DateTime dailyResetAt;

  /// Empty when no Night Market is running.
  final List<RawNightMarketOffer> nightMarketOffers;

  final DateTime? nightMarketEndsAt;

  /// Weekly Accessory Store. Empty when Riot returns no accessory panel.
  final List<RawAccessoryOffer> accessoryOffers;

  /// The accessory store runs on its own weekly cadence, so it needs its own
  /// countdown — it does not roll over with the daily shop.
  final DateTime? accessoryResetAt;

  /// Featured Bundles, each with its own end time.
  final List<RawBundleOffer> bundles;

  final DateTime capturedAt;

  bool get hasNightMarket => nightMarketOffers.isNotEmpty;
  bool get hasAccessories => accessoryOffers.isNotEmpty;
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

  /// True once the countdown has run out, meaning a re-fetch will return a
  /// different set of four skins.
  bool get isExpired => !DateTime.now().isBefore(dailyResetAt);

  /// The four offer ids, order-independent — the identity used to decide
  /// whether the shop has actually rotated.
  Set<String> get dailyOfferIds =>
      dailyOffers.map((RawOffer o) => o.offerId).toSet();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'accessoryOffers': accessoryOffers
        .map((RawAccessoryOffer o) => o.toJson())
        .toList(),
    'accessoryResetAt': accessoryResetAt?.toIso8601String(),
    'bundles': bundles.map((RawBundleOffer b) => b.toJson()).toList(),
    'dailyOffers': dailyOffers.map((RawOffer o) => o.toJson()).toList(),
    'dailyResetAt': dailyResetAt.toIso8601String(),
    'nightMarketOffers': nightMarketOffers
        .map((RawNightMarketOffer o) => o.toJson())
        .toList(),
    'nightMarketEndsAt': nightMarketEndsAt?.toIso8601String(),
    'capturedAt': capturedAt.toIso8601String(),
  };

  factory StorefrontSnapshot.fromJson(Map<String, dynamic> json) {
    return StorefrontSnapshot(
      dailyOffers: _list(json['dailyOffers'])
          .map(RawOffer.fromJson)
          .toList(growable: false),
      dailyResetAt:
          DateTime.tryParse(json['dailyResetAt'] as String? ?? '') ??
          DateTime.now(),
      nightMarketOffers: _list(json['nightMarketOffers'])
          .map(RawNightMarketOffer.fromJson)
          .toList(growable: false),
      nightMarketEndsAt: DateTime.tryParse(
        json['nightMarketEndsAt'] as String? ?? '',
      ),
      accessoryOffers: _list(json['accessoryOffers'])
          .map(RawAccessoryOffer.fromJson)
          .toList(growable: false),
      accessoryResetAt: DateTime.tryParse(
        json['accessoryResetAt'] as String? ?? '',
      ),
      bundles: _list(json['bundles'])
          .map(RawBundleOffer.fromJson)
          .toList(growable: false),
      capturedAt:
          DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
