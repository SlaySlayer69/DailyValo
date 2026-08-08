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

    test('fills the accessory store from the real catalogue', () {
      final StorefrontSnapshot snapshot = demo.buildStorefront(catalog);

      expect(snapshot.hasAccessories, isTrue);
      final Set<String> known = catalog.accessories.keys.toSet();
      for (final RawAccessoryOffer offer in snapshot.accessoryOffers) {
        expect(offer.cost, greaterThan(0));
        expect(offer.rewardIds, isNotEmpty);
        expect(known, containsAll(offer.rewardIds));
      }
    });

    test('never offers the same accessory twice in one store', () {
      final List<String> rewards = demo
          .buildStorefront(catalog)
          .accessoryOffers
          .expand((RawAccessoryOffer o) => o.rewardIds)
          .toList();

      expect(rewards.toSet(), hasLength(rewards.length));
    });

    test('the accessory reset is a weekly one, well past the daily reset', () {
      final StorefrontSnapshot snapshot = demo.buildStorefront(catalog);

      expect(
        snapshot.accessoryResetAt!.isAfter(snapshot.dailyResetAt),
        isTrue,
        reason: 'a shared countdown would defeat the point of the section',
      );
      expect(
        DemoStoreSource.nextAccessoryReset(
          DateTime.utc(2026, 8, 7, 15, 30),
        ).toUtc(),
        // Friday the 7th -> next Wednesday, the 12th.
        DateTime.utc(2026, 8, 12),
      );
    });

    test('the accessory reset never lands on today', () {
      // Walk a full week so the modular arithmetic cannot silently return the
      // same midnight it started from on one particular weekday.
      for (int day = 1; day <= 7; day++) {
        final DateTime from = DateTime.utc(2026, 8, day, 9);
        expect(
          DemoStoreSource.nextAccessoryReset(from).isAfter(from),
          isTrue,
          reason: 'reset from 2026-08-$day must be in the future',
        );
      }
    });

    test('features a bundle with a real name and its own end time', () {
      final StorefrontSnapshot snapshot = demo.buildStorefront(catalog);

      expect(snapshot.hasBundles, isTrue);
      final RawBundleOffer bundle = snapshot.bundles.single;
      expect(catalog.bundleByUuid(bundle.bundleUuid), isNotNull);
      expect(bundle.discountedPrice, lessThan(bundle.basePrice));
      expect(bundle.discountPercent, inInclusiveRange(1, 99));
      expect(bundle.endsAt.isAfter(snapshot.dailyResetAt), isTrue);
    });

    test('the demo bundle\'s items add up to its price', () {
      // A bundle whose parts do not sum to its total is the first thing anyone
      // would notice on the detail page.
      final RawBundleOffer bundle = demo.buildStorefront(catalog).bundles.single;

      expect(bundle.items, isNotEmpty);
      expect(bundle.itemCount, bundle.items.length);
      expect(
        bundle.items.fold(0, (int s, RawBundleItem i) => s + i.basePrice),
        bundle.basePrice,
      );
      expect(
        bundle.items.fold(0, (int s, RawBundleItem i) => s + i.discountedPrice),
        bundle.discountedPrice,
      );
    });

    test('the demo bundle includes one free item', () {
      final RawBundleOffer bundle = demo.buildStorefront(catalog).bundles.single;
      final Iterable<RawBundleItem> free = bundle.items.where(
        (RawBundleItem i) => i.isFree,
      );

      expect(free, hasLength(1));
      expect(free.single.isPromoItem, isTrue);
      expect(
        free.single.basePrice,
        greaterThan(0),
        reason: 'without a base price there is nothing to strike through',
      );
    });

    test('every demo bundle item resolves against the catalogue', () {
      final RawBundleOffer bundle = demo.buildStorefront(catalog).bundles.single;

      for (final RawBundleItem item in bundle.items) {
        final bool resolves =
            catalog.skinByOfferUuid(item.itemId) != null ||
            catalog.accessoryByUuid(item.itemId) != null;
        expect(resolves, isTrue, reason: '${item.itemId} resolved to nothing');
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
      expect(snapshot.hasAccessories, isFalse);
      expect(snapshot.accessoryResetAt, isNull);
      expect(snapshot.hasBundles, isFalse);
    });

    test('demo wallet and rank are populated', () {
      expect(demo.buildWallet().valorantPoints, greaterThan(0));
      expect(demo.buildCompetitiveStanding().tier, 22);
    });
  });
}
