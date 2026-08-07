import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/store/data/datasources/storefront_parser.dart';
import 'package:dailyvalo/src/features/store/data/models/shop.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final ContentCatalog catalog = Fixtures.catalog();
  final StorefrontSnapshot snapshot = StorefrontParser.parse(
    Fixtures.storefrontJson(),
    now: DateTime(2026, 8, 7, 12),
  );

  group('Shop.resolve', () {
    test('joins offer uuids to names, artwork and rarity', () {
      final Shop shop = Shop.resolve(snapshot: snapshot, catalog: catalog);

      expect(shop.dailyOffers, hasLength(3));
      final ShopOffer first = shop.dailyOffers.first;
      expect(first.skin.displayName, 'Prime Vandal');
      expect(first.price, 1775);
      expect(first.tier?.devName, 'Premium');
    });

    test('flags offers the player already owns', () {
      final Shop shop = Shop.resolve(
        snapshot: snapshot,
        catalog: catalog,
        ownedSkinUuids: <String>{Fixtures.reaverSheriffLevel1Uuid},
      );

      final Map<String, bool> ownedByName = <String, bool>{
        for (final ShopOffer o in shop.dailyOffers)
          o.skin.displayName: o.isOwned,
      };
      expect(ownedByName['Reaver Sheriff'], isTrue);
      expect(ownedByName['Prime Vandal'], isFalse);
    });

    test('surfaces wishlist hits', () {
      final Shop shop = Shop.resolve(
        snapshot: snapshot,
        catalog: catalog,
        wishlistedSkinUuids: <String>{
          Fixtures.glitchpopKnifeSkinUuid,
          // A wishlisted skin that is *not* in today's shop must not match.
          'some-other-skin',
        },
      );

      expect(shop.wishlistHits, hasLength(1));
      expect(shop.wishlistHits.single.skin.displayName, 'Glitchpop Dagger');
    });

    test('drops offers the catalogue does not know rather than blank cards',
        () {
      final StorefrontSnapshot withUnknown = StorefrontSnapshot(
        dailyOffers: <RawOffer>[
          const RawOffer(offerId: 'brand-new-patch-skin', cost: 1775),
          RawOffer(offerId: Fixtures.primeVandalLevel1Uuid, cost: 1775),
        ],
        dailyResetAt: DateTime(2026, 8, 8),
        nightMarketOffers: const <RawNightMarketOffer>[],
        nightMarketEndsAt: null,
        capturedAt: DateTime(2026, 8, 7),
      );

      final Shop shop = Shop.resolve(
        snapshot: withUnknown,
        catalog: catalog,
      );

      expect(shop.dailyOffers, hasLength(1));
      expect(shop.dailyOffers.single.skin.displayName, 'Prime Vandal');
    });

    test('computes night market savings', () {
      final Shop shop = Shop.resolve(snapshot: snapshot, catalog: catalog);

      expect(shop.hasNightMarket, isTrue);
      final NightMarketDeal deal = shop.nightMarket.single;
      expect(deal.savings, 1775 - 1242);
      expect(deal.discountPercent, 30);
    });

    test('never reports a negative countdown', () {
      final Shop past = Shop.resolve(
        snapshot: StorefrontSnapshot(
          dailyOffers: <RawOffer>[
            RawOffer(offerId: Fixtures.primeVandalLevel1Uuid, cost: 1775),
          ],
          dailyResetAt: DateTime.now().subtract(const Duration(hours: 2)),
          nightMarketOffers: const <RawNightMarketOffer>[],
          nightMarketEndsAt: null,
          capturedAt: DateTime.now(),
        ),
        catalog: catalog,
      );

      expect(past.timeUntilReset, Duration.zero);
    });
  });
}
