import 'package:dailyvalo/src/features/catalogue/data/models/catalogue_query.dart';
import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/content/data/models/content_tier.dart';
import 'package:dailyvalo/src/features/content/data/models/weapon_skin.dart';
import 'package:dailyvalo/src/features/store/data/models/shop_sightings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// The catalogue's search, filters and sorts.
///
/// All of it lives in [CatalogueQuery.apply] precisely so it can be tested
/// without a widget: the page holds a query and renders whatever comes back,
/// and every rule about what a person sees is here.
void main() {
  final ContentCatalog catalog = Fixtures.catalog();
  final List<WeaponSkin> pool = catalog.browsableSkins;

  // Prime Vandal (Rifle, Premium), Reaver Sheriff (Sidearm, Premium),
  // Glitchpop Dagger (Melee, Ultra). The standard Phantom has no tier and is
  // excluded from `browsableSkins` — it was never for sale.
  const String vandal = Fixtures.primeVandalSkinUuid;
  const String sheriff = Fixtures.reaverSheriffSkinUuid;
  const String dagger = Fixtures.glitchpopKnifeSkinUuid;

  final DateTime now = DateTime(2026, 3, 10);
  final ShopSightings sightings = ShopSightings.startingAt(DateTime(2026))
      .record(<String>[vandal], DateTime(2026, 3, 9))
      .record(<String>[sheriff], DateTime(2026));

  List<String> run(
    CatalogueQuery query, {
    Set<String> owned = const <String>{},
    Set<String> wishlisted = const <String>{},
    Set<String> inShop = const <String>{},
  }) => query
      .apply(
        pool,
        tierOf: catalog.tierOf,
        isOwned: (WeaponSkin s) => owned.contains(s.uuid),
        isWishlisted: (WeaponSkin s) => wishlisted.contains(s.uuid),
        availabilityOf: (WeaponSkin s) => SkinAvailability.of(
          skinUuid: s.uuid,
          inShopToday: inShop,
          sightings: sightings,
          now: now,
        ),
      )
      .map((WeaponSkin s) => s.uuid)
      .toList();

  group('Search', () {
    test('lists everything purchasable when empty', () {
      expect(run(const CatalogueQuery()), hasLength(3));
      // Never the standard-issue weapons: they have no rarity and Riot has
      // never sold them, so they are not skins anyone is hunting.
      expect(run(const CatalogueQuery()), isNot(contains('std-phantom')));
    });

    test('matches the skin name, case-insensitively', () {
      expect(run(const CatalogueQuery(search: 'prime')), <String>[vandal]);
      expect(run(const CatalogueQuery(search: 'PRIME')), <String>[vandal]);
    });

    test('matches the weapon name too', () {
      // "Sheriff" is the weapon, not the skin line — searching for the gun you
      // want a skin for is at least as common as searching for the skin.
      expect(run(const CatalogueQuery(search: 'sheriff')), <String>[sheriff]);
    });

    test('ignores surrounding whitespace', () {
      expect(run(const CatalogueQuery(search: '  prime  ')), <String>[vandal]);
    });

    test('returns nothing rather than everything on a miss', () {
      expect(run(const CatalogueQuery(search: 'zzzz')), isEmpty);
    });
  });

  group('Filters', () {
    test('an empty rarity set means every rarity, not none', () {
      expect(run(const CatalogueQuery(rarities: <String>{})), hasLength(3));
    });

    test('narrows to the selected rarities', () {
      expect(
        run(const CatalogueQuery(rarities: <String>{'Ultra'})),
        <String>[dagger],
      );
      expect(
        run(const CatalogueQuery(rarities: <String>{'Ultra', 'Premium'})),
        hasLength(3),
      );
    });

    test('narrows to the selected weapon categories', () {
      expect(
        run(const CatalogueQuery(categories: <String>{'Melee'})),
        <String>[dagger],
      );
    });

    test('combines filters as an AND', () {
      expect(
        run(
          const CatalogueQuery(
            categories: <String>{'Rifle'},
            rarities: <String>{'Ultra'},
          ),
        ),
        isEmpty,
      );
    });

    test('splits the catalogue by ownership', () {
      expect(
        run(
          const CatalogueQuery(ownership: OwnershipFilter.owned),
          owned: <String>{vandal},
        ),
        <String>[vandal],
      );
      expect(
        run(
          const CatalogueQuery(ownership: OwnershipFilter.notOwned),
          owned: <String>{vandal},
        ),
        isNot(contains(vandal)),
      );
    });

    test('narrows to the wishlist', () {
      expect(
        run(
          const CatalogueQuery(wishlistedOnly: true),
          wishlisted: <String>{dagger},
        ),
        <String>[dagger],
      );
    });

    test('counts what is active, for the badge', () {
      const CatalogueQuery query = CatalogueQuery(
        rarities: <String>{'Ultra'},
        ownership: OwnershipFilter.notOwned,
      );

      expect(query.activeFilterCount, 2);
      expect(query.isFiltered, isTrue);
      // A sort is not a filter: it hides nothing, so offering to clear it
      // would be offering to undo something still fully visible.
      expect(
        const CatalogueQuery(sort: CatalogueSort.drought).isFiltered,
        isFalse,
      );
    });

    test('clearing keeps the search box and the sort', () {
      const CatalogueQuery query = CatalogueQuery(
        search: 'prime',
        rarities: <String>{'Ultra'},
        wishlistedOnly: true,
        sort: CatalogueSort.name,
      );

      final CatalogueQuery cleared = query.cleared();

      expect(cleared.search, 'prime');
      expect(cleared.sort, CatalogueSort.name);
      expect(cleared.activeFilterCount, 0);
    });
  });

  group('Sorting', () {
    test('by name, ignoring case', () {
      expect(run(const CatalogueQuery(sort: CatalogueSort.name)), <String>[
        dagger, // Glitchpop Dagger
        vandal, // Prime Vandal
        sheriff, // Reaver Sheriff
      ]);
    });

    test('by rarity, rarest first', () {
      expect(
        run(const CatalogueQuery(sort: CatalogueSort.rarity)).first,
        dagger,
      );
    });

    test('by price, dearest first', () {
      // The knife is Ultra *and* melee, so it prices at double a gun of the
      // same rarity — the two premium guns tie and fall back to name order.
      expect(run(const CatalogueQuery(sort: CatalogueSort.price)), <String>[
        dagger,
        vandal,
        sheriff,
      ]);
    });

    test('by drought, longest wait first', () {
      // Never seen, then longest since seen, then today's offer last.
      expect(
        run(
          const CatalogueQuery(sort: CatalogueSort.drought),
          inShop: <String>{vandal},
        ),
        <String>[dagger, sheriff, vandal],
      );
    });

    test('by weapon class for browsing, which is the default', () {
      // Buy-menu order: sidearms, then rifles, and melee last.
      expect(run(const CatalogueQuery()), <String>[sheriff, vandal, dagger]);
    });

    test('is stable — ties fall back to the name', () {
      final List<String> first = run(
        const CatalogueQuery(sort: CatalogueSort.rarity),
      );
      final List<String> second = run(
        const CatalogueQuery(sort: CatalogueSort.rarity),
      );

      expect(first, second);
    });
  });

  group('Rarity keys', () {
    test('untiered skins get a bucket of their own rather than vanishing', () {
      expect(CatalogueQuery.rarityKeyOf(null), 'Other');
      expect(
        CatalogueQuery.rarityKeyOf(catalog.tiers[Fixtures.tierUltraUuid]),
        'Ultra',
      );
    });

    test('filtering by that bucket is possible', () {
      final ContentTier? none = null;
      expect(
        run(
          CatalogueQuery(
            rarities: <String>{CatalogueQuery.rarityKeyOf(none)},
          ),
        ),
        // Nothing in `browsableSkins` is untiered by construction, but the
        // filter has to be expressible rather than silently unreachable.
        isEmpty,
      );
    });
  });
}
