import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/content/data/models/skin_ordering.dart';
import 'package:dailyvalo/src/features/content/data/models/weapon_skin.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// A skin with just enough shape to be ordered.
WeaponSkin skin({
  required String name,
  required String weapon,
  required String category,
  String? tierUuid,
}) => WeaponSkin.fromJson(
  <String, dynamic>{
    'uuid': '$weapon-$name',
    'displayName': name,
    'contentTierUuid': tierUuid,
    'levels': <Map<String, dynamic>>[
      <String, dynamic>{'uuid': '$weapon-$name-l1', 'displayName': name},
    ],
    'chromas': <Map<String, dynamic>>[],
  },
  weaponUuid: 'w-$weapon',
  weaponName: weapon,
  weaponCategory: category,
);

void main() {
  final ContentCatalog catalog = Fixtures.catalog();

  List<String> order(List<WeaponSkin> skins) =>
      SkinOrdering.sorted(skins, catalog.tierOf)
          .map((WeaponSkin s) => '${s.weaponName}/${s.displayName}')
          .toList();

  group('SkinOrdering', () {
    test('weapon classes follow the buy menu, not the alphabet', () {
      final List<WeaponSkin> input = <WeaponSkin>[
        skin(name: 'A', weapon: 'Odin', category: 'Heavy'),
        skin(name: 'A', weapon: 'Operator', category: 'Sniper'),
        skin(name: 'A', weapon: 'Classic', category: 'Sidearm'),
        skin(name: 'A', weapon: 'Vandal', category: 'Rifle'),
        skin(name: 'A', weapon: 'Judge', category: 'Shotgun'),
        skin(name: 'A', weapon: 'Spectre', category: 'SMG'),
      ];

      expect(order(input), <String>[
        'Classic/A',
        'Spectre/A',
        'Judge/A',
        'Vandal/A',
        'Operator/A',
        'Odin/A',
      ]);
    });

    test('weapons inside a class are alphabetical', () {
      final List<WeaponSkin> input = <WeaponSkin>[
        skin(name: 'A', weapon: 'Outlaw', category: 'Sniper'),
        skin(name: 'A', weapon: 'Marshal', category: 'Sniper'),
        skin(name: 'A', weapon: 'Operator', category: 'Sniper'),
      ];

      expect(order(input), <String>[
        'Marshal/A',
        'Operator/A',
        'Outlaw/A',
      ]);
    });

    test('rarity runs rarest first inside one weapon', () {
      final List<WeaponSkin> input = <WeaponSkin>[
        skin(
          name: 'Premium one',
          weapon: 'Vandal',
          category: 'Rifle',
          tierUuid: Fixtures.tierPremiumUuid,
        ),
        skin(
          name: 'Ultra one',
          weapon: 'Vandal',
          category: 'Rifle',
          tierUuid: Fixtures.tierUltraUuid,
        ),
      ];

      expect(order(input), <String>[
        'Vandal/Ultra one',
        'Vandal/Premium one',
      ]);
    });

    test('skins with no known rarity sort last, not first', () {
      final List<WeaponSkin> input = <WeaponSkin>[
        skin(name: 'Unknown tier', weapon: 'Vandal', category: 'Rifle'),
        skin(
          name: 'Premium one',
          weapon: 'Vandal',
          category: 'Rifle',
          tierUuid: Fixtures.tierPremiumUuid,
        ),
      ];

      expect(order(input), <String>[
        'Vandal/Premium one',
        'Vandal/Unknown tier',
      ]);
    });

    test('an unrecognised weapon class sorts last rather than first', () {
      final List<WeaponSkin> input = <WeaponSkin>[
        skin(name: 'A', weapon: 'Mystery', category: 'SomethingNew'),
        skin(name: 'A', weapon: 'Classic', category: 'Sidearm'),
      ];

      expect(order(input), <String>['Classic/A', 'Mystery/A']);
    });

    test('melee comes after every buyable class', () {
      final List<WeaponSkin> input = <WeaponSkin>[
        skin(name: 'A', weapon: 'Melee', category: 'Melee'),
        skin(name: 'A', weapon: 'Odin', category: 'Heavy'),
      ];

      expect(order(input), <String>['Odin/A', 'Melee/A']);
    });

    test('ties break on skin name, so the order is stable across fetches', () {
      final List<WeaponSkin> input = <WeaponSkin>[
        skin(
          name: 'Zephyr',
          weapon: 'Vandal',
          category: 'Rifle',
          tierUuid: Fixtures.tierPremiumUuid,
        ),
        skin(
          name: 'Araxys',
          weapon: 'Vandal',
          category: 'Rifle',
          tierUuid: Fixtures.tierPremiumUuid,
        ),
      ];

      expect(order(input), <String>['Vandal/Araxys', 'Vandal/Zephyr']);
      // Same list, opposite input order — the result must not follow the input.
      expect(order(input.reversed.toList()), <String>[
        'Vandal/Araxys',
        'Vandal/Zephyr',
      ]);
    });

    test('rarity chips are ordered rarest first', () {
      final List<String> shuffled = <String>[
        'Select',
        'Ultra',
        'Deluxe',
        'Exclusive',
        'Premium',
      ]..sort(
        (String a, String b) => SkinOrdering.rarityIndex(
          a,
        ).compareTo(SkinOrdering.rarityIndex(b)),
      );

      expect(shuffled, <String>[
        'Ultra',
        'Exclusive',
        'Premium',
        'Deluxe',
        'Select',
      ]);
    });

    test('the catalogue exposes its browse order and only sorts once', () {
      final ContentCatalog c = Fixtures.catalog();

      // Standard-issue weapons are excluded, same as purchasableSkins.
      expect(c.browsableSkins, hasLength(c.purchasableSkins.length));
      expect(
        c.browsableSkins.map((WeaponSkin s) => s.displayName),
        isNot(contains('Phantom')),
      );

      expect(
        identical(c.browsableSkins, c.browsableSkins),
        isTrue,
        reason: 'a late final must not re-sort on every read',
      );

      // Sidearm before Rifle before Melee, from the fixture catalogue.
      expect(
        c.browsableSkins.map((WeaponSkin s) => s.weaponCategory).toList(),
        <String>['Sidearm', 'Rifle', 'Melee'],
      );
    });

    test('rarity index is derived from the named order, not the API rank', () {
      // The fixture's Ultra tier carries rank 3 and Premium rank 2; the named
      // order has to win regardless of what Riot numbers them.
      expect(Fixtures.ultra.rank, 3);
      expect(
        SkinOrdering.rarityIndex('Ultra'),
        lessThan(SkinOrdering.rarityIndex('Premium')),
      );
      expect(SkinOrdering.rarityIndex(null), SkinOrdering.rarities.length);
      expect(
        SkinOrdering.rarityIndex('Mythic'),
        SkinOrdering.rarities.length,
      );
    });
  });

  group('ContentTier ordering helpers', () {
    test('every named rarity is a real content tier devName', () {
      // Guards against a typo in the list silently sending a whole rarity to
      // the end of the browse order.
      const Set<String> known = <String>{
        'Select',
        'Deluxe',
        'Premium',
        'Exclusive',
        'Ultra',
      };
      expect(SkinOrdering.rarities.toSet(), known);
    });
  });
}
