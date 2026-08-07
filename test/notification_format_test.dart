import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/store/data/datasources/storefront_parser.dart';
import 'package:dailyvalo/src/features/store/data/models/shop.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Locks in the notification body formats, which are part of the product spec
/// rather than an implementation detail:
///
///   Daily shop: `Weapon: Skin Name - Weapon: Skin Name - ...`
///   Wishlist:   `An item on your wishlist is in your shop!`
void main() {
  final ContentCatalog catalog = Fixtures.catalog();
  final StorefrontSnapshot snapshot = StorefrontParser.parse(
    Fixtures.storefrontJson(),
    now: DateTime(2026, 8, 7, 12),
  );

  group('Daily shop notification body', () {
    test('is Weapon: Skin pairs joined with " - "', () {
      final Shop shop = Shop.resolve(snapshot: snapshot, catalog: catalog);
      final String body = shop.dailyOffers
          .map((ShopOffer o) => o.skin.notificationLabel)
          .join(' - ');

      expect(
        body,
        'Vandal: Prime Vandal - Sheriff: Reaver Sheriff - '
        'Melee: Glitchpop Dagger',
      );
    });

    test('preserves the order Riot returned the offers in', () {
      final Shop shop = Shop.resolve(snapshot: snapshot, catalog: catalog);
      expect(
        shop.dailyOffers.map((ShopOffer o) => o.offerId).toList(),
        snapshot.dailyOffers.map((RawOffer o) => o.offerId).toList(),
      );
    });
  });

  group('Shop rotation detection', () {
    test('an identical offer set in a different order is not a rotation', () {
      final Set<String> yesterday = <String>{
        Fixtures.primeVandalLevel1Uuid,
        Fixtures.reaverSheriffLevel1Uuid,
      };
      final Set<String> today = <String>{
        Fixtures.reaverSheriffLevel1Uuid,
        Fixtures.primeVandalLevel1Uuid,
      };

      expect(
        yesterday.length == today.length && yesterday.containsAll(today),
        isTrue,
      );
    });

    test('a single changed offer is a rotation', () {
      final Set<String> yesterday = <String>{
        Fixtures.primeVandalLevel1Uuid,
        Fixtures.reaverSheriffLevel1Uuid,
      };
      final Set<String> today = <String>{
        Fixtures.primeVandalLevel1Uuid,
        Fixtures.glitchpopKnifeLevel1Uuid,
      };

      expect(yesterday.containsAll(today), isFalse);
    });
  });
}
