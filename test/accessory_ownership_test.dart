import 'package:dailyvalo/src/features/content/data/models/accessory_item.dart';
import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/store/data/datasources/storefront_parser.dart';
import 'package:dailyvalo/src/features/store/data/models/shop.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Owned sprays, buddies, cards and titles.
///
/// Skins have been flagged as owned since v1.0.0; accessories never were,
/// because their entitlements live behind four separate item types and none of
/// them were wired up. The question they answer — "do I already have this?" —
/// otherwise costs a trip into the game to settle.
void main() {
  final ContentCatalog catalog = Fixtures.catalog();
  final StorefrontSnapshot snapshot = StorefrontParser.parse(
    Fixtures.storefrontJson(),
    now: DateTime(2026, 8, 7, 12),
  );

  Shop resolve({Set<String> owned = const <String>{}}) => Shop.resolve(
    snapshot: snapshot,
    catalog: catalog,
    ownedAccessoryUuids: owned,
  );

  group('Accessory ownership', () {
    test('nothing is marked when the entitlements never answered', () {
      // An empty set has to mean "not known", not "owns none" — the calls are
      // allowed to fail without the store claiming an empty inventory.
      for (final AccessoryOffer offer in resolve().accessories) {
        expect(offer.isOwned, isFalse);
      }
    });

    test('an offer whose only item you own is marked', () {
      final Shop shop = resolve();
      final AccessoryOffer single = shop.accessories.firstWhere(
        (AccessoryOffer o) => o.items.length == 1,
      );

      final Shop marked = resolve(
        owned: <String>{single.primary.uuid},
      );
      expect(
        marked.accessories
            .firstWhere((AccessoryOffer o) => o.offerId == single.offerId)
            .isOwned,
        isTrue,
      );
    });

    test('owning one item of a multi-item offer is not owning the offer', () {
      final Shop shop = resolve();
      final AccessoryOffer? multi = shop.accessories
          .where((AccessoryOffer o) => o.items.length > 1)
          .cast<AccessoryOffer?>()
          .firstWhere((AccessoryOffer? o) => true, orElse: () => null);
      if (multi == null) return; // The fixture has none; nothing to assert.

      final Shop marked = resolve(owned: <String>{multi.items.first.uuid});
      // An offer granting a spray you have and a buddy you do not is still
      // worth buying; calling it owned would talk you out of it.
      expect(
        marked.accessories
            .firstWhere((AccessoryOffer o) => o.offerId == multi.offerId)
            .isOwned,
        isFalse,
      );
    });

    test('an unrelated uuid marks nothing', () {
      final Shop marked = resolve(owned: <String>{'not-in-this-shop'});
      for (final AccessoryOffer offer in marked.accessories) {
        expect(offer.isOwned, isFalse);
      }
    });
  });

  group('The entitlement types asked about', () {
    test('covers every kind that can appear in the store', () {
      // A kind added to the enum without a type id here would silently never
      // be flagged, and nothing else would notice.
      expect(AccessoryKind.entitlementTypeIds, hasLength(4));
      expect(
        AccessoryKind.entitlementTypeIds.toSet(),
        <String>{
          AccessoryKind.sprayTypeId,
          AccessoryKind.buddyTypeId,
          AccessoryKind.playerCardTypeId,
          AccessoryKind.playerTitleTypeId,
        },
      );
    });

    test('every id is a distinct, well-formed UUID', () {
      final RegExp uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      );
      for (final String id in AccessoryKind.entitlementTypeIds) {
        expect(uuid.hasMatch(id), isTrue, reason: '$id is not a UUID');
      }
      expect(AccessoryKind.entitlementTypeIds.toSet(), hasLength(4));
    });

    test('is not the skin type, which is fetched separately', () {
      // Sending the skin type here would return thousands of level ids and
      // mark accessories owned at random.
      expect(
        AccessoryKind.entitlementTypeIds,
        isNot(contains('e7c63390-eda7-46e0-bb7a-a6abdacd2433')),
      );
    });
  });
}
