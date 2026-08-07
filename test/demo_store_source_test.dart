import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/content/data/models/weapon_skin.dart';
import 'package:dailyvalo/src/features/store/data/datasources/demo_store_source.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  const DemoStoreSource demo = DemoStoreSource();
  final ContentCatalog catalog = Fixtures.catalog();

  group('DemoStoreSource', () {
    test('produces the same shop twice in a row on the same day', () {
      final StorefrontSnapshot a = demo.buildStorefront(catalog);
      final StorefrontSnapshot b = demo.buildStorefront(catalog);

      expect(a.dailyOfferIds, b.dailyOfferIds);
    });

    test('only ever offers purchasable skins', () {
      final StorefrontSnapshot snapshot = demo.buildStorefront(catalog);
      final Set<String> sellable = catalog.purchasableSkins
          .map((WeaponSkin s) => s.offerUuid)
          .toSet();

      for (final RawOffer offer in snapshot.dailyOffers) {
        expect(sellable, contains(offer.offerId));
      }
    });

    test('prices offers by rarity', () {
      final StorefrontSnapshot snapshot = demo.buildStorefront(catalog);
      for (final RawOffer offer in snapshot.dailyOffers) {
        expect(offer.cost, greaterThan(0));
      }

      expect(DemoStoreSource.priceFor(Fixtures.ultra), 2475);
      expect(DemoStoreSource.priceFor(Fixtures.premium), 1775);
      // Unknown/absent tier still gets a sane price rather than 0.
      expect(DemoStoreSource.priceFor(null), 1775);
    });

    test('resets at the next 00:00 UTC', () {
      final DateTime reset = DemoStoreSource.nextShopReset(
        DateTime.utc(2026, 8, 7, 15, 30),
      );
      expect(reset.toUtc(), DateTime.utc(2026, 8, 8));
    });

    test('reset time is always in the future', () {
      expect(
        demo.buildStorefront(catalog).dailyResetAt.isAfter(DateTime.now()),
        isTrue,
      );
    });

    test('night market entries are genuinely discounted', () {
      // The cadence is date-driven, so only assert when one is running.
      final StorefrontSnapshot snapshot = demo.buildStorefront(catalog);
      for (final RawNightMarketOffer deal in snapshot.nightMarketOffers) {
        expect(deal.discountedPrice, lessThan(deal.basePrice));
        expect(deal.discountPercent, inInclusiveRange(1, 99));
      }
    });

    test('handles an empty catalogue without throwing', () {
      final ContentCatalog empty = ContentCatalog(
        skins: const <WeaponSkin>[],
        tiers: const <String, Never>{},
        competitiveTiers: const <int, Never>{},
        language: 'en-US',
        fetchedAt: DateTime.now(),
      );

      final StorefrontSnapshot snapshot = demo.buildStorefront(empty);
      expect(snapshot.dailyOffers, isEmpty);
      expect(snapshot.hasNightMarket, isFalse);
    });

    test('demo wallet and rank are populated', () {
      expect(demo.buildWallet().valorantPoints, greaterThan(0));
      expect(demo.buildCompetitiveStanding().tier, 22);
    });
  });
}
