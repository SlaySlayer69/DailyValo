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

/// A point-in-time capture of the player's store.
class StorefrontSnapshot {
  const StorefrontSnapshot({
    required this.dailyOffers,
    required this.dailyResetAt,
    required this.nightMarketOffers,
    required this.nightMarketEndsAt,
    required this.capturedAt,
  });

  final List<RawOffer> dailyOffers;

  /// Absolute time the four daily offers roll over. Derived once from Riot's
  /// relative `...RemainingDurationInSeconds` so the countdown stays correct
  /// across app restarts without re-fetching.
  final DateTime dailyResetAt;

  /// Empty when no Night Market is running.
  final List<RawNightMarketOffer> nightMarketOffers;

  final DateTime? nightMarketEndsAt;

  final DateTime capturedAt;

  bool get hasNightMarket => nightMarketOffers.isNotEmpty;

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
