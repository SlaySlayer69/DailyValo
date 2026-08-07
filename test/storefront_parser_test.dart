import 'package:dailyvalo/src/core/errors/app_exception.dart';
import 'package:dailyvalo/src/features/store/data/datasources/storefront_parser.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 7, 12);

  group('StorefrontParser', () {
    test('reads daily offers with their Valorant Point prices', () {
      final StorefrontSnapshot snapshot = StorefrontParser.parse(
        Fixtures.storefrontJson(),
        now: now,
      );

      expect(snapshot.dailyOffers, hasLength(3));
      expect(
        snapshot.dailyOffers.first.offerId,
        Fixtures.primeVandalLevel1Uuid,
      );
      expect(snapshot.dailyOffers.first.cost, 1775);
      expect(snapshot.dailyOffers.last.cost, 4950);
    });

    test('turns Riot\'s relative countdown into an absolute reset time', () {
      final StorefrontSnapshot snapshot = StorefrontParser.parse(
        Fixtures.storefrontJson(),
        now: now,
      );

      // 3600s remaining, captured at 12:00 -> resets at 13:00.
      expect(snapshot.dailyResetAt, DateTime(2026, 8, 7, 13));
    });

    test('expiry is judged against the wall clock, not the capture time', () {
      // Deliberately relative to now: `isExpired` asks whether the shop has
      // rotated *since*, so pinning it to a fixed timestamp makes the test
      // pass or fail depending on the hour it happens to run.
      final DateTime realNow = DateTime.now();

      expect(
        StorefrontParser.parse(
          Fixtures.storefrontJson(),
          now: realNow,
        ).isExpired,
        isFalse,
        reason: 'a shop with an hour left has not expired',
      );

      expect(
        StorefrontParser.parse(
          Fixtures.storefrontJson(),
          now: realNow.subtract(const Duration(hours: 2)),
        ).isExpired,
        isTrue,
        reason: 'a 1h window captured 2h ago has lapsed',
      );
    });

    test('parses the night market with discount and base price', () {
      final StorefrontSnapshot snapshot = StorefrontParser.parse(
        Fixtures.storefrontJson(),
        now: now,
      );

      expect(snapshot.hasNightMarket, isTrue);
      final RawNightMarketOffer deal = snapshot.nightMarketOffers.single;
      expect(deal.basePrice, 1775);
      expect(deal.discountedPrice, 1242);
      expect(deal.discountPercent, 30);
      expect(deal.isSeen, isTrue);
      expect(snapshot.nightMarketEndsAt, DateTime(2026, 8, 9, 12));
    });

    test('reports no night market when BonusStore is absent', () {
      final StorefrontSnapshot snapshot = StorefrontParser.parse(
        Fixtures.storefrontJson(withNightMarket: false),
        now: now,
      );

      expect(snapshot.hasNightMarket, isFalse);
      expect(snapshot.nightMarketOffers, isEmpty);
      expect(snapshot.nightMarketEndsAt, isNull);
    });

    test('throws a ParseException rather than showing an empty shop', () {
      expect(
        () => StorefrontParser.parse(const <String, dynamic>{}),
        throwsA(isA<ParseException>()),
      );
      expect(
        () => StorefrontParser.parse(const <String, dynamic>{
          'SkinsPanelLayout': <String, dynamic>{
            'SingleItemOffers': <String>[],
          },
        }),
        throwsA(isA<ParseException>()),
      );
    });

    test('falls back to the sole cost entry if the VP uuid ever changes', () {
      expect(
        StorefrontParser.valorantPointCost(<String, dynamic>{
          'some-future-uuid': 2475,
        }),
        2475,
      );
      // Ambiguous multi-currency cost: refuse to guess.
      expect(
        StorefrontParser.valorantPointCost(<String, dynamic>{
          'a': 1,
          'b': 2,
        }),
        0,
      );
    });

    test('offer identity survives a JSON round trip', () {
      final StorefrontSnapshot original = StorefrontParser.parse(
        Fixtures.storefrontJson(),
        now: now,
      );
      final StorefrontSnapshot restored = StorefrontSnapshot.fromJson(
        original.toJson(),
      );

      expect(restored.dailyOfferIds, original.dailyOfferIds);
      expect(restored.dailyResetAt, original.dailyResetAt);
      expect(
        restored.nightMarketOffers.single.discountedPrice,
        original.nightMarketOffers.single.discountedPrice,
      );
    });
  });
}
