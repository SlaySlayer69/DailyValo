import 'content_tier.dart';
import 'weapon_skin.dart';

/// Resolves a skin's rarity. Passed in rather than taking the catalogue
/// directly, so the catalogue can depend on this file without a cycle.
typedef TierResolver = ContentTier? Function(WeaponSkin skin);

/// How skins and rarities are ordered anywhere the user browses them.
///
/// Both orders are explicit lists rather than anything derived from the API.
/// Weapon categories come back from `valorant-api.com` in no meaningful order,
/// and while content tiers do carry a numeric `rank`, ordering by it would tie
/// the UI to a Riot-side numbering that has no reason to stay put. Naming the
/// order here means it reads the way the in-game buy menu does, and a new tier
/// lands predictably at the end instead of silently in the middle.
abstract final class SkinOrdering {
  /// Buy-menu order. Melee has no slot in the menu and goes last.
  static const List<String> weaponCategories = <String>[
    'Sidearm',
    'SMG',
    'Shotgun',
    'Rifle',
    'Sniper',
    'Heavy',
    'Melee',
  ];

  /// Rarity, rarest first — the order the filter chips appear in, and the
  /// order skins are listed in within one weapon.
  static const List<String> rarities = <String>[
    'Ultra',
    'Exclusive',
    'Premium',
    'Deluxe',
    'Select',
  ];

  /// Position of a weapon category; anything unrecognised sorts last.
  static int categoryIndex(String category) {
    final int i = weaponCategories.indexOf(category);
    return i == -1 ? weaponCategories.length : i;
  }

  /// Position of a rarity, rarest = 0; anything unrecognised sorts last.
  static int rarityIndex(String? devName) {
    if (devName == null) return rarities.length;
    final int i = rarities.indexOf(devName);
    return i == -1 ? rarities.length : i;
  }

  /// Weapon category, then weapon name, then rarity, then skin name.
  ///
  /// The trailing name comparison is what makes the result stable: two skins
  /// for the same weapon at the same rarity would otherwise land in whatever
  /// order the catalogue happened to hold them, which changes between fetches.
  static int compare(WeaponSkin a, WeaponSkin b, TierResolver tierOf) {
    final int byCategory = categoryIndex(
      a.weaponCategory,
    ).compareTo(categoryIndex(b.weaponCategory));
    if (byCategory != 0) return byCategory;

    final int byWeapon = a.weaponName.toLowerCase().compareTo(
      b.weaponName.toLowerCase(),
    );
    if (byWeapon != 0) return byWeapon;

    final int byRarity = rarityIndex(
      tierOf(a)?.devName,
    ).compareTo(rarityIndex(tierOf(b)?.devName));
    if (byRarity != 0) return byRarity;

    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  /// [compare] applied to a copy — the caller's list is left alone.
  static List<WeaponSkin> sorted(
    Iterable<WeaponSkin> skins,
    TierResolver tierOf,
  ) => skins.toList()
    ..sort((WeaponSkin a, WeaponSkin b) => compare(a, b, tierOf));
}
