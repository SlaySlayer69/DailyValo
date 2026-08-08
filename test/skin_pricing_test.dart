import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/content/data/models/skin_pricing.dart';
import 'package:dailyvalo/src/features/content/data/models/weapon_skin.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final ContentCatalog catalog = Fixtures.catalog();

  group('SkinPricing', () {
    test('prices a gun at its rarity', () {
      // Prime Vandal is Premium in the fixture catalogue.
      expect(
        SkinPricing.priceOf(
          Fixtures.primeVandal(),
          catalog.tierOf(Fixtures.primeVandal()),
        ),
        1775,
      );
    });

    test('a melee costs twice its rarity', () {
      // Glitchpop Dagger is Ultra: 2,475 as a gun, 4,950 as a knife. Pricing
      // knives off the gun table would understate a collection badly, since
      // knives are what people collect.
      expect(
        SkinPricing.priceOf(
          Fixtures.glitchpopKnife(),
          catalog.tierOf(Fixtures.glitchpopKnife()),
        ),
        4950,
      );
    });

    test('a skin Riot never sold has no price at all', () {
      // Standard-issue and battlepass skins carry no content tier. Returning
      // zero would fold them into the total as free.
      expect(
        SkinPricing.priceOf(
          Fixtures.standardPhantom(),
          catalog.tierOf(Fixtures.standardPhantom()),
        ),
        isNull,
      );
    });

    test('covers every rarity the app filters by', () {
      expect(SkinPricing.gunPrices.keys.toSet(), <String>{
        'Select',
        'Deluxe',
        'Premium',
        'Exclusive',
        'Ultra',
      });
    });
  });

  group('CollectionValue', () {
    test('sums what it can price and counts what it cannot', () {
      final CollectionValue value = CollectionValue.of(
        <WeaponSkin>[
          Fixtures.primeVandal(), // Premium gun  1775
          Fixtures.reaverSheriff(), // Premium gun  1775
          Fixtures.glitchpopKnife(), // Ultra melee  4950
          Fixtures.standardPhantom(), // unpriced
        ],
        catalog.tierOf,
      );

      expect(value.totalVp, 1775 + 1775 + 4950);
      expect(value.pricedCount, 3);
      expect(value.unpricedCount, 1);
      expect(value.skinCount, 4);
      expect(value.isComplete, isFalse);
    });

    test('reports completeness when everything could be priced', () {
      final CollectionValue value = CollectionValue.of(
        <WeaponSkin>[Fixtures.primeVandal()],
        catalog.tierOf,
      );

      expect(value.isComplete, isTrue);
      expect(value.unpricedCount, 0);
      expect(value.totalVp, 1775);
    });

    test('an empty collection is worth nothing, not an error', () {
      final CollectionValue value = CollectionValue.of(
        const <WeaponSkin>[],
        catalog.tierOf,
      );

      expect(value.totalVp, 0);
      expect(value.skinCount, 0);
      expect(value.isComplete, isTrue);
    });

    test('unpriced skins never contribute to the total', () {
      final CollectionValue value = CollectionValue.of(
        <WeaponSkin>[Fixtures.standardPhantom()],
        catalog.tierOf,
      );

      expect(value.totalVp, 0);
      expect(value.pricedCount, 0);
      expect(value.unpricedCount, 1);
    });
  });
}
