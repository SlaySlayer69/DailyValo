import '../../../content/data/models/weapon_skin.dart';

/// A skin the user is watching for.
///
/// The display fields are denormalised on purpose: the background worker has to
/// build a notification body without loading the 4 MB content catalogue, and
/// the wishlist tab has to render before the catalogue finishes parsing.
class WishlistEntry {
  const WishlistEntry({
    required this.skinUuid,
    required this.offerUuid,
    required this.skinName,
    required this.weaponName,
    required this.addedAt,
    this.contentTierUuid,
    this.imageUrl,
  });

  /// `WeaponSkin.uuid` — the wishlist's primary key.
  final String skinUuid;

  /// `WeaponSkin.offerUuid`, i.e. the level-1 UUID the storefront uses.
  /// Stored so a shop match is a plain set intersection.
  final String offerUuid;

  final String skinName;
  final String weaponName;
  final DateTime addedAt;
  final String? contentTierUuid;
  final String? imageUrl;

  String get label => '$weaponName: $skinName';

  factory WishlistEntry.fromSkin(WeaponSkin skin) => WishlistEntry(
    skinUuid: skin.uuid,
    offerUuid: skin.offerUuid,
    skinName: skin.displayName,
    weaponName: skin.weaponName,
    contentTierUuid: skin.contentTierUuid,
    imageUrl: skin.artwork,
    addedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'skinUuid': skinUuid,
    'offerUuid': offerUuid,
    'skinName': skinName,
    'weaponName': weaponName,
    'contentTierUuid': contentTierUuid,
    'imageUrl': imageUrl,
    'addedAt': addedAt.toIso8601String(),
  };

  factory WishlistEntry.fromJson(Map<String, dynamic> json) => WishlistEntry(
    skinUuid: json['skinUuid'] as String? ?? '',
    offerUuid: json['offerUuid'] as String? ?? '',
    skinName: json['skinName'] as String? ?? 'Unknown skin',
    weaponName: json['weaponName'] as String? ?? '',
    contentTierUuid: json['contentTierUuid'] as String?,
    imageUrl: json['imageUrl'] as String?,
    addedAt:
        DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
