import 'package:dailyvalo/src/features/content/data/models/accessory_item.dart';
import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/store/data/datasources/storefront_parser.dart';
import 'package:dailyvalo/src/features/store/data/models/shop.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 7, 12);
  final ContentCatalog catalog = Fixtures.catalog();

  StorefrontSnapshot parse({
    bool withAccessories = true,
    bool withBundles = true,
  }) => StorefrontParser.parse(
    Fixtures.storefrontJson(
      withAccessories: withAccessories,
      withBundles: withBundles,
    ),
    now: now,
  );

  group('Accessory store parsing', () {
    test('reads offers with their Kingdom Credit prices', () {
      final StorefrontSnapshot snapshot = parse();

      expect(snapshot.hasAccessories, isTrue);
      expect(snapshot.accessoryOffers, hasLength(5));

      final RawAccessoryOffer first = snapshot.accessoryOffers.first;
      expect(first.offerId, 'acc-1');
      expect(first.cost, 325);
      expect(first.rewardIds, <String>[Fixtures.sprayUuid]);
      expect(first.contractId, 'y1s1-accessory-contract');
    });

    test('keeps its own reset time, far past the daily one', () {
      final StorefrontSnapshot snapshot = parse();

      // 604800s (a week) from 12:00 on the 7th.
      expect(snapshot.accessoryResetAt, DateTime(2026, 8, 14, 12));
      expect(snapshot.dailyResetAt, DateTime(2026, 8, 7, 13));
      expect(
        snapshot.accessoryResetAt!.isAfter(snapshot.dailyResetAt),
        isTrue,
        reason: 'the two countdowns must not be conflated',
      );
    });

    test('reports no accessory store when the panel is absent', () {
      final StorefrontSnapshot snapshot = parse(withAccessories: false);

      expect(snapshot.hasAccessories, isFalse);
      expect(snapshot.accessoryOffers, isEmpty);
      expect(
        snapshot.accessoryResetAt,
        isNull,
        reason: 'no panel means no countdown, not a countdown of zero',
      );
    });

    test('prices in Kingdom Credits, never Valorant Points', () {
      expect(
        StorefrontParser.kingdomCreditCost(<String, dynamic>{
          '85ca954a-41f2-ce94-9b45-8ca3dd39a00d': 475,
        }),
        475,
      );
      // A sole entry is unambiguous enough to trust.
      expect(
        StorefrontParser.kingdomCreditCost(<String, dynamic>{'x': 300}),
        300,
      );
      // Two currencies and no known key: refuse to guess.
      expect(
        StorefrontParser.kingdomCreditCost(<String, dynamic>{'a': 1, 'b': 2}),
        0,
      );
    });
  });

  group('Accessory resolution', () {
    test('resolves every kind, including buddies granted by level uuid', () {
      final Shop shop = Shop.resolve(snapshot: parse(), catalog: catalog);

      // The offer with an unknown reward is dropped rather than rendered blank.
      expect(shop.accessories, hasLength(4));
      expect(shop.hasAccessories, isTrue);

      final List<AccessoryKind> kinds = shop.accessories
          .map((AccessoryOffer o) => o.primary.kind)
          .toList();
      expect(kinds, <AccessoryKind>[
        AccessoryKind.spray,
        AccessoryKind.buddy,
        AccessoryKind.playerCard,
        AccessoryKind.playerTitle,
      ]);

      final AccessoryOffer buddyOffer = shop.accessories[1];
      expect(
        buddyOffer.primary.displayName,
        'Polyfrog Buddy',
        reason: 'the level uuid must resolve to the buddy itself',
      );
      expect(buddyOffer.price, 475);
    });

    test('labels a single-item offer by kind and a multi-item one by count',
        () {
      final Shop shop = Shop.resolve(snapshot: parse(), catalog: catalog);
      expect(shop.accessories.first.subtitle, 'Spray');

      final Shop multi = Shop.resolve(
        snapshot: StorefrontSnapshot(
          dailyOffers: <RawOffer>[
            RawOffer(offerId: Fixtures.primeVandalLevel1Uuid, cost: 1775),
          ],
          dailyResetAt: now,
          nightMarketOffers: const <RawNightMarketOffer>[],
          nightMarketEndsAt: null,
          accessoryOffers: const <RawAccessoryOffer>[
            RawAccessoryOffer(
              offerId: 'acc-multi',
              cost: 900,
              rewardIds: <String>[Fixtures.sprayUuid, Fixtures.buddyUuid],
            ),
          ],
          capturedAt: now,
        ),
        catalog: catalog,
      );
      expect(multi.accessories.single.subtitle, '2 items');
    });

    test('titles carry their text, since they have no artwork at all', () {
      final Shop shop = Shop.resolve(snapshot: parse(), catalog: catalog);
      final AccessoryItem title = shop.accessories.last.primary;

      expect(title.isTextOnly, isTrue);
      expect(title.titleText, 'Legend');
      expect(title.artwork, isNull);
    });

    test('player cards prefer their wide art', () {
      final Shop shop = Shop.resolve(snapshot: parse(), catalog: catalog);
      expect(
        shop.accessories[2].primary.artwork,
        'https://media.valorant-api.com/cards/neptune-wide.png',
      );
    });
  });

  group('Featured bundles', () {
    test('parses price, discount, item count and end time', () {
      final StorefrontSnapshot snapshot = parse();

      expect(snapshot.hasBundles, isTrue);
      final RawBundleOffer bundle = snapshot.bundles.single;
      expect(
        bundle.bundleUuid,
        Fixtures.protocolBundleUuid,
        reason: 'DataAssetID matches the catalogue; ID does not',
      );
      expect(bundle.basePrice, 8700);
      expect(bundle.discountedPrice, 6789);
      // Riot sends 0.2197 as a fraction; the UI wants whole percent.
      expect(bundle.discountPercent, 22);
      expect(bundle.itemCount, 3);
      expect(bundle.endsAt, DateTime(2026, 8, 10, 12));
      expect(bundle.savings, 8700 - 6789);
    });

    test('reports no bundles when FeaturedBundle is absent', () {
      final StorefrontSnapshot snapshot = parse(withBundles: false);
      expect(snapshot.hasBundles, isFalse);
      expect(snapshot.bundles, isEmpty);
    });

    test('resolves the bundle name and key art', () {
      final Shop shop = Shop.resolve(snapshot: parse(), catalog: catalog);

      final BundleOffer bundle = shop.bundles.single;
      expect(bundle.displayName, 'Protocol 781-A');
      expect(
        bundle.info?.artwork,
        'https://media.valorant-api.com/bundles/protocol-v.png',
      );
      expect(bundle.isDiscounted, isTrue);
    });

    test('keeps an unknown bundle rather than dropping it', () {
      // A brand-new bundle is exactly when someone opens the app, and the price
      // and countdown are useful even before the mirror has indexed the name.
      final Shop shop = Shop.resolve(
        snapshot: StorefrontSnapshot(
          dailyOffers: <RawOffer>[
            RawOffer(offerId: Fixtures.primeVandalLevel1Uuid, cost: 1775),
          ],
          dailyResetAt: now,
          nightMarketOffers: const <RawNightMarketOffer>[],
          nightMarketEndsAt: null,
          bundles: <RawBundleOffer>[
            RawBundleOffer(
              bundleUuid: 'shipped-this-morning',
              basePrice: 9900,
              discountedPrice: 9900,
              discountPercent: 0,
              itemCount: 6,
              endsAt: now.add(const Duration(days: 7)),
            ),
          ],
          capturedAt: now,
        ),
        catalog: catalog,
      );

      final BundleOffer bundle = shop.bundles.single;
      expect(bundle.info, isNull);
      expect(bundle.displayName, 'Featured Bundle');
      expect(bundle.isDiscounted, isFalse);
    });

    test('never reports a negative countdown', () {
      final BundleOffer expired = BundleOffer(
        uuid: 'x',
        basePrice: 1,
        price: 1,
        discountPercent: 0,
        itemCount: 1,
        endsAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      expect(expired.timeRemaining, Duration.zero);
    });
  });

  group('Snapshot persistence', () {
    test('accessories and bundles survive a JSON round trip', () {
      final StorefrontSnapshot original = parse();
      final StorefrontSnapshot restored = StorefrontSnapshot.fromJson(
        original.toJson(),
      );

      expect(restored.accessoryOffers, hasLength(5));
      expect(restored.accessoryOffers.first.cost, 325);
      expect(
        restored.accessoryOffers.first.rewardIds,
        original.accessoryOffers.first.rewardIds,
      );
      expect(restored.accessoryResetAt, original.accessoryResetAt);
      expect(restored.bundles.single.endsAt, original.bundles.single.endsAt);
      expect(
        restored.bundles.single.discountedPrice,
        original.bundles.single.discountedPrice,
      );
    });

    test('the catalogue keeps accessories and bundles across its cache', () {
      final ContentCatalog restored = ContentCatalog.fromJson(catalog.toJson());

      expect(
        restored.accessoryByUuid(Fixtures.buddyLevelUuid)?.displayName,
        'Polyfrog Buddy',
      );
      expect(
        restored.accessoryByUuid(Fixtures.playerTitleUuid)?.titleText,
        'Legend',
      );
      expect(
        restored.bundleByUuid(Fixtures.protocolBundleUuid)?.displayName,
        'Protocol 781-A',
      );
    });
  });
}
