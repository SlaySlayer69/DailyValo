import '../../../../core/constants/riot_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/storefront_snapshot.dart';

/// Turns Riot's storefront payload into a [StorefrontSnapshot].
///
/// Split out of the API client so it can be tested against recorded payloads
/// without a network stack — this is the part most likely to break when Riot
/// reshapes the response, and the part where a silent mis-parse would show the
/// user the wrong prices.
abstract final class StorefrontParser {
  /// Parses a `/store/v2` or `/store/v3` storefront body.
  ///
  /// [now] is injectable so the absolute reset time derived from Riot's
  /// relative countdown is deterministic in tests.
  static StorefrontSnapshot parse(Map<String, dynamic> body, {DateTime? now}) {
    if (body.isEmpty) {
      throw const ParseException('The storefront response was empty.');
    }
    final DateTime timestamp = now ?? DateTime.now();

    final List<RawOffer> dailyOffers = _parseDailyOffers(body);
    if (dailyOffers.isEmpty) {
      throw const ParseException(
        'Riot returned a storefront with no daily offers.',
      );
    }

    final Map<String, dynamic> panel = _asMap(body['SkinsPanelLayout']);
    final int dailyRemaining =
        (panel['SingleItemOffersRemainingDurationInSeconds'] as num?)
            ?.toInt() ??
        0;

    final Map<String, dynamic> bonus = _asMap(body['BonusStore']);
    final List<RawNightMarketOffer> nightMarket = _parseNightMarket(bonus);
    final int? bonusRemaining =
        (bonus['BonusStoreRemainingDurationInSeconds'] as num?)?.toInt();

    final Map<String, dynamic> accessory = _asMap(body['AccessoryStore']);
    final List<RawAccessoryOffer> accessories = _parseAccessories(accessory);
    final int? accessoryRemaining =
        (accessory['AccessoryStoreRemainingDurationInSeconds'] as num?)
            ?.toInt();

    return StorefrontSnapshot(
      dailyOffers: dailyOffers,
      dailyResetAt: timestamp.add(Duration(seconds: dailyRemaining)),
      nightMarketOffers: nightMarket,
      nightMarketEndsAt: (nightMarket.isEmpty || bonusRemaining == null)
          ? null
          : timestamp.add(Duration(seconds: bonusRemaining)),
      accessoryOffers: accessories,
      // The accessory store rotates weekly, on its own schedule — never assume
      // it shares the daily reset.
      accessoryResetAt: accessoryRemaining == null
          ? null
          : timestamp.add(Duration(seconds: accessoryRemaining)),
      bundles: _parseBundles(body, timestamp),
      capturedAt: timestamp,
    );
  }

  static List<RawAccessoryOffer> _parseAccessories(
    Map<String, dynamic> accessory,
  ) {
    final Object? offers = accessory['AccessoryStoreOffers'];
    if (offers is! List) return const <RawAccessoryOffer>[];

    final List<RawAccessoryOffer> out = <RawAccessoryOffer>[];
    for (final Object? raw in offers) {
      final Map<String, dynamic> entry = _asMap(raw);
      final Map<String, dynamic> offer = _asMap(entry['Offer']);
      final String? offerId = offer['OfferID'] as String?;
      if (offerId == null) continue;

      final List<String> rewards = <String>[];
      final Object? rawRewards = offer['Rewards'];
      if (rawRewards is List) {
        for (final Object? reward in rawRewards) {
          final String? itemId = _asMap(reward)['ItemID'] as String?;
          if (itemId != null && itemId.isNotEmpty) rewards.add(itemId);
        }
      }

      out.add(
        RawAccessoryOffer(
          offerId: offerId,
          cost: kingdomCreditCost(offer['Cost']),
          rewardIds: rewards,
          contractId: entry['ContractID'] as String?,
        ),
      );
    }
    return out;
  }

  static List<RawBundleOffer> _parseBundles(
    Map<String, dynamic> body,
    DateTime now,
  ) {
    final Map<String, dynamic> featured = _asMap(body['FeaturedBundle']);
    final Object? bundles = featured['Bundles'];
    if (bundles is! List) return const <RawBundleOffer>[];

    final List<RawBundleOffer> out = <RawBundleOffer>[];
    for (final Object? raw in bundles) {
      final Map<String, dynamic> bundle = _asMap(raw);

      // `DataAssetID` is what matches valorant-api's bundle content; `ID` is
      // the storefront's own instance id and resolves to nothing.
      final String? uuid =
          bundle['DataAssetID'] as String? ?? bundle['ID'] as String?;
      if (uuid == null) continue;

      final Object? items = bundle['Items'];
      final int seconds =
          (bundle['DurationRemainingInSeconds'] as num?)?.toInt() ??
          (featured['BundleRemainingDurationInSeconds'] as num?)?.toInt() ??
          0;

      // Riot sends the discount as a fraction (0.2197); the UI wants percent.
      final num? fraction = bundle['TotalDiscountPercent'] as num?;

      out.add(
        RawBundleOffer(
          bundleUuid: uuid,
          basePrice: valorantPointCost(bundle['TotalBaseCost']),
          discountedPrice: valorantPointCost(bundle['TotalDiscountedCost']),
          discountPercent: fraction == null
              ? 0
              : (fraction * 100).round().clamp(0, 100),
          itemCount: items is List ? items.length : 0,
          endsAt: now.add(Duration(seconds: seconds)),
        ),
      );
    }
    return out;
  }

  /// Accessories are billed in Kingdom Credits, not Valorant Points.
  static int kingdomCreditCost(Object? cost) {
    final Map<String, dynamic> map = _asMap(cost);
    final Object? kc = map[RiotConstants.currencyKingdomCredits];
    if (kc is num) return kc.toInt();
    if (map.length == 1 && map.values.first is num) {
      return (map.values.first as num).toInt();
    }
    return 0;
  }

  static List<RawOffer> _parseDailyOffers(Map<String, dynamic> body) {
    final Map<String, dynamic> panel = _asMap(body['SkinsPanelLayout']);

    // Prices arrive in a parallel array keyed by offer id; index it once
    // rather than scanning it per offer.
    final Map<String, int> priceByOffer = <String, int>{};
    final Object? storeOffers = panel['SingleItemStoreOffers'];
    if (storeOffers is List) {
      for (final Object? raw in storeOffers) {
        final Map<String, dynamic> offer = _asMap(raw);
        final String? id = offer['OfferID'] as String?;
        if (id == null) continue;
        priceByOffer[id] = valorantPointCost(offer['Cost']);
      }
    }

    final List<RawOffer> offers = <RawOffer>[];
    final Object? offerIds = panel['SingleItemOffers'];
    if (offerIds is List) {
      for (final Object? raw in offerIds) {
        if (raw is! String) continue;
        offers.add(RawOffer(offerId: raw, cost: priceByOffer[raw] ?? 0));
      }
    }
    return offers;
  }

  static List<RawNightMarketOffer> _parseNightMarket(
    Map<String, dynamic> bonus,
  ) {
    final Object? bonusOffers = bonus['BonusStoreOffers'];
    if (bonusOffers is! List) return const <RawNightMarketOffer>[];

    final List<RawNightMarketOffer> out = <RawNightMarketOffer>[];
    for (final Object? raw in bonusOffers) {
      final Map<String, dynamic> entry = _asMap(raw);
      final Map<String, dynamic> offer = _asMap(entry['Offer']);
      final String? offerId = offer['OfferID'] as String?;
      if (offerId == null) continue;

      out.add(
        RawNightMarketOffer(
          offerId: offerId,
          basePrice: valorantPointCost(offer['Cost']),
          discountedPrice: valorantPointCost(entry['DiscountCosts']),
          discountPercent: (entry['DiscountPercent'] as num?)?.toInt() ?? 0,
          isSeen: entry['IsSeen'] as bool? ?? false,
        ),
      );
    }
    return out;
  }

  /// Costs arrive as `{"<currency-uuid>": <amount>}`. Skins are only ever sold
  /// for Valorant Points, so that is the key we read.
  static int valorantPointCost(Object? cost) {
    final Map<String, dynamic> map = _asMap(cost);
    final Object? vp = map[RiotConstants.currencyValorantPoints];
    if (vp is num) return vp.toInt();

    // Defensive: if Riot ever changes the VP uuid, a single-entry cost map is
    // unambiguous enough to trust rather than showing the user "0 VP".
    if (map.length == 1 && map.values.first is num) {
      return (map.values.first as num).toInt();
    }
    return 0;
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};
}
