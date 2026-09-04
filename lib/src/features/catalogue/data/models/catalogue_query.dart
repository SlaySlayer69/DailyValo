import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/skin_ordering.dart';
import '../../../content/data/models/skin_pricing.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../../store/data/models/shop_sightings.dart';

/// Whether the list is narrowed by what the account already has.
enum OwnershipFilter {
  any('All skins'),
  owned('Owned'),
  notOwned('Not owned');

  const OwnershipFilter(this.label);

  final String label;
}

/// The order the catalogue is listed in.
enum CatalogueSort {
  /// Weapon class, then weapon, then rarity — the in-game buy menu order, and
  /// the only one in which "the Vandal skins" are a contiguous block.
  browse('Weapon'),

  name('Name (A–Z)'),

  rarity('Rarity (rarest first)'),

  price('Price (high to low)'),

  /// Longest wait first: never seen, then most days since, then today's offers.
  /// The whole reason the sightings are recorded.
  drought('Longest unseen');

  const CatalogueSort(this.label);

  final String label;
}

/// Everything the catalogue page filters and sorts by, in one value.
///
/// A value type rather than a pile of fields on the page's state, so the whole
/// query can be compared, reset, and — the point — tested without a widget:
/// [apply] is a pure function over a skin list, and it is where every rule
/// about what shows up actually lives.
class CatalogueQuery {
  const CatalogueQuery({
    this.search = '',
    this.rarities = const <String>{},
    this.categories = const <String>{},
    this.ownership = OwnershipFilter.any,
    this.wishlistedOnly = false,
    this.sort = CatalogueSort.browse,
  });

  /// Matched against the skin name and the weapon name, case-insensitively.
  final String search;

  /// Tier `devName`s. Empty means every rarity — deselecting the last chip has
  /// to bring the catalogue back, not empty the page.
  final Set<String> rarities;

  /// Weapon categories (`Rifle`, `Melee`, …). Empty means all.
  final Set<String> categories;

  final OwnershipFilter ownership;

  final bool wishlistedOnly;

  final CatalogueSort sort;

  /// Whether anything at all is narrowing the list. The sort is excluded on
  /// purpose: reordering hides nothing, so offering to "clear" it would be
  /// offering to undo something the user can still see all of.
  bool get isFiltered =>
      search.isNotEmpty ||
      rarities.isNotEmpty ||
      categories.isNotEmpty ||
      ownership != OwnershipFilter.any ||
      wishlistedOnly;

  /// How many filters are active, for the badge on the filter button.
  int get activeFilterCount =>
      (rarities.isEmpty ? 0 : 1) +
      (categories.isEmpty ? 0 : 1) +
      (ownership == OwnershipFilter.any ? 0 : 1) +
      (wishlistedOnly ? 1 : 0);

  CatalogueQuery copyWith({
    String? search,
    Set<String>? rarities,
    Set<String>? categories,
    OwnershipFilter? ownership,
    bool? wishlistedOnly,
    CatalogueSort? sort,
  }) => CatalogueQuery(
    search: search ?? this.search,
    rarities: rarities ?? this.rarities,
    categories: categories ?? this.categories,
    ownership: ownership ?? this.ownership,
    wishlistedOnly: wishlistedOnly ?? this.wishlistedOnly,
    sort: sort ?? this.sort,
  );

  /// Drops every filter but keeps the sort and the search box.
  ///
  /// The search text is left alone because it is visible in its own field with
  /// its own clear button; wiping it from a "clear filters" tap would remove
  /// something the user is looking at from a control that is not next to it.
  CatalogueQuery cleared() =>
      CatalogueQuery(search: search, sort: sort);

  /// Filters and sorts [skins].
  ///
  /// The resolvers are passed in rather than a catalogue and a set of providers,
  /// so this stays a plain function over data: the page supplies closures over
  /// what it has, and the tests supply maps.
  List<WeaponSkin> apply(
    Iterable<WeaponSkin> skins, {
    required ContentTier? Function(WeaponSkin) tierOf,
    required bool Function(WeaponSkin) isOwned,
    required bool Function(WeaponSkin) isWishlisted,
    required SkinAvailability Function(WeaponSkin) availabilityOf,
  }) {
    final String needle = search.trim().toLowerCase();

    final List<WeaponSkin> matches = skins.where((WeaponSkin skin) {
      if (needle.isNotEmpty &&
          !skin.displayName.toLowerCase().contains(needle) &&
          !skin.weaponName.toLowerCase().contains(needle)) {
        return false;
      }
      if (rarities.isNotEmpty &&
          !rarities.contains(tierOf(skin)?.devName ?? _noTier)) {
        return false;
      }
      if (categories.isNotEmpty && !categories.contains(skin.weaponCategory)) {
        return false;
      }
      if (wishlistedOnly && !isWishlisted(skin)) return false;

      return switch (ownership) {
        OwnershipFilter.any => true,
        OwnershipFilter.owned => isOwned(skin),
        OwnershipFilter.notOwned => !isOwned(skin),
      };
    }).toList();

    _sort(matches, tierOf, availabilityOf);
    return matches;
  }

  void _sort(
    List<WeaponSkin> skins,
    ContentTier? Function(WeaponSkin) tierOf,
    SkinAvailability Function(WeaponSkin) availabilityOf,
  ) {
    switch (sort) {
      case CatalogueSort.browse:
        // Already the catalogue's own order, but the list may have arrived from
        // anywhere, so sort rather than assume.
        skins.sort(
          (WeaponSkin a, WeaponSkin b) => SkinOrdering.compare(a, b, tierOf),
        );

      case CatalogueSort.name:
        skins.sort(_byName);

      case CatalogueSort.rarity:
        skins.sort((WeaponSkin a, WeaponSkin b) {
          final int byRarity = SkinOrdering.rarityIndex(
            tierOf(a)?.devName,
          ).compareTo(SkinOrdering.rarityIndex(tierOf(b)?.devName));
          return byRarity != 0 ? byRarity : _byName(a, b);
        });

      case CatalogueSort.price:
        skins.sort((WeaponSkin a, WeaponSkin b) {
          // Unpriced skins — battlepass and event rewards — go last rather than
          // leading the list at zero VP.
          final int byPrice = (SkinPricing.priceOf(b, tierOf(b)) ?? -1).compareTo(
            SkinPricing.priceOf(a, tierOf(a)) ?? -1,
          );
          return byPrice != 0 ? byPrice : _byName(a, b);
        });

      case CatalogueSort.drought:
        // Cached per skin: `availabilityOf` reads a map and allocates, and a
        // comparison-sort calls it O(n log n) times over ~1600 skins.
        final Map<String, int> rank = <String, int>{
          for (final WeaponSkin s in skins)
            s.uuid: availabilityOf(s).droughtRank,
        };
        skins.sort((WeaponSkin a, WeaponSkin b) {
          final int byDrought = (rank[b.uuid] ?? 0).compareTo(rank[a.uuid] ?? 0);
          return byDrought != 0 ? byDrought : _byName(a, b);
        });
    }
  }

  static int _byName(WeaponSkin a, WeaponSkin b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

  /// The bucket for skins with no rarity at all. Named rather than left as a
  /// null so it can be a chip like any other.
  static const String _noTier = 'Other';

  /// The rarity key a skin filters under, including the untiered bucket.
  static String rarityKeyOf(ContentTier? tier) => tier?.devName ?? _noTier;
}
