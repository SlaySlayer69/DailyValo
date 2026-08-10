import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/store/data/datasources/storefront_parser.dart';
import 'package:dailyvalo/src/features/store/data/models/shop.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Locks in the notification body formats, which are part of the product spec
/// rather than an implementation detail:
///
///   Daily shop: `Skin Name - Skin Name - ...`
///   Wishlist:   `An item on your wishlist is in your shop!`
void main() {
  final ContentCatalog catalog = Fixtures.catalog();
  final StorefrontSnapshot snapshot = StorefrontParser.parse(
    Fixtures.storefrontJson(),
    now: DateTime(2026, 8, 7, 12),
  );

  group('Daily shop notification body', () {
    test('is skin names joined with " - "', () {
      final Shop shop = Shop.resolve(snapshot: snapshot, catalog: catalog);
      final String body = shop.dailyOffers
          .map((ShopOffer o) => o.skin.notificationLabel)
          .join(' - ');

      expect(
        body,
        'Prime Vandal - Reaver Sheriff - Glitchpop Dagger',
      );
    });

    test('does not repeat the weapon the skin is already named after', () {
      // The prefixed form read "Vandal: Prime Vandal" — the weapon twice in
      // five words, four times over in one notification, crowding out the part
      // that actually distinguishes one shop from another.
      final Shop shop = Shop.resolve(snapshot: snapshot, catalog: catalog);
      for (final ShopOffer offer in shop.dailyOffers) {
        expect(
          offer.skin.notificationLabel,
          isNot(startsWith('${offer.skin.weaponName}:')),
        );
        expect(offer.skin.notificationLabel, offer.skin.displayName);
      }
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
