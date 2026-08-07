import '../../../../core/utils/formatters.dart';

/// A colour variant of a skin. Buying the skin unlocks variant 1; the rest are
/// unlocked with Radianite.
class SkinChroma {
  const SkinChroma({
    required this.uuid,
    required this.displayName,
    this.displayIcon,
    this.fullRender,
    this.swatch,
    this.streamedVideo,
  });

  final String uuid;
  final String displayName;

  /// Small icon; frequently null for the base variant.
  final String? displayIcon;

  /// The big transparent PNG used on the detail page.
  final String? fullRender;

  /// Colour dot shown in the variant picker.
  final String? swatch;

  /// Riot-hosted preview clip, when the variant has unique VFX.
  final String? streamedVideo;

  bool get hasVideo => streamedVideo != null && streamedVideo!.isNotEmpty;

  /// Chroma names arrive as `Prime Vandal Level 1 Variant 2 Blue`; the caller
  /// only wants `Variant 2 Blue`.
  String shortName(String skinName) {
    final String trimmed = displayName.replaceFirst(skinName, '').trim();
    final int variantAt = trimmed.indexOf('Variant');
    if (variantAt >= 0) return trimmed.substring(variantAt).trim();
    return trimmed.isEmpty ? 'Default' : trimmed;
  }

  factory SkinChroma.fromJson(Map<String, dynamic> json) => SkinChroma(
    uuid: json['uuid'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Variant',
    displayIcon: json['displayIcon'] as String?,
    fullRender: json['fullRender'] as String?,
    swatch: json['swatch'] as String?,
    streamedVideo: json['streamedVideo'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'displayName': displayName,
    'displayIcon': displayIcon,
    'fullRender': fullRender,
    'swatch': swatch,
    'streamedVideo': streamedVideo,
  };
}

/// One upgrade tier of a skin. `levelItem` says what the tier actually adds.
class SkinLevel {
  const SkinLevel({
    required this.uuid,
    required this.displayName,
    this.levelItem,
    this.displayIcon,
    this.streamedVideo,
  });

  final String uuid;
  final String displayName;

  /// e.g. `EEquippableSkinLevelItem::VFX`. Null on the base level.
  final String? levelItem;

  final String? displayIcon;
  final String? streamedVideo;

  bool get hasVideo => streamedVideo != null && streamedVideo!.isNotEmpty;

  /// `EEquippableSkinLevelItem::Finisher` -> `Finisher`; base level -> `Base`.
  String get upgradeLabel {
    final String tail = Formatters.enumTail(levelItem);
    return switch (tail) {
      '' => 'Base skin',
      'VFX' => 'Visual effects',
      'SoundEffects' => 'Sound effects',
      'Animation' => 'Animation',
      'Finisher' => 'Finisher',
      'Voiceover' => 'Voiceover',
      'KillCounter' => 'Kill counter',
      'InspectAndKill' => 'Inspect & kill effects',
      'Randomizer' => 'Randomizer',
      'TopFrag' => 'Top frag banner',
      _ => tail,
    };
  }

  factory SkinLevel.fromJson(Map<String, dynamic> json) => SkinLevel(
    uuid: json['uuid'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Level',
    levelItem: json['levelItem'] as String?,
    displayIcon: json['displayIcon'] as String?,
    streamedVideo: json['streamedVideo'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'displayName': displayName,
    'levelItem': levelItem,
    'displayIcon': displayIcon,
    'streamedVideo': streamedVideo,
  };
}

/// A weapon skin, flattened so it carries its parent weapon's name.
///
/// The storefront never mentions the weapon — it returns a *skin level* UUID
/// and nothing else — so denormalising the weapon name here is what makes
/// `Vandal: Prime` renderable (and the notification text possible).
class WeaponSkin {
  const WeaponSkin({
    required this.uuid,
    required this.displayName,
    required this.weaponUuid,
    required this.weaponName,
    required this.weaponCategory,
    required this.levels,
    required this.chromas,
    this.contentTierUuid,
    this.themeUuid,
    this.displayIcon,
    this.wallpaper,
  });

  final String uuid;

  /// The skin line name as shown in game, e.g. `Prime Vandal`.
  final String displayName;

  final String weaponUuid;

  /// e.g. `Vandal`, `Melee`.
  final String weaponName;

  /// `EEquippableCategory::Rifle` -> stored as `Rifle`.
  final String weaponCategory;

  final List<SkinLevel> levels;
  final List<SkinChroma> chromas;

  /// Rarity. Null for default/standard skins, which have no tier.
  final String? contentTierUuid;
  final String? themeUuid;

  final String? displayIcon;

  /// Full-bleed key art. Only premium lines have one.
  final String? wallpaper;

  /// The UUID the storefront uses to offer this skin — level 1.
  String get offerUuid => levels.isNotEmpty ? levels.first.uuid : uuid;

  /// Best artwork available, in descending order of how good it looks on a card.
  String? get artwork {
    for (final SkinChroma chroma in chromas) {
      if (chroma.fullRender != null && chroma.fullRender!.isNotEmpty) {
        return chroma.fullRender;
      }
    }
    if (displayIcon != null && displayIcon!.isNotEmpty) return displayIcon;
    for (final SkinLevel level in levels) {
      if (level.displayIcon != null && level.displayIcon!.isNotEmpty) {
        return level.displayIcon;
      }
    }
    return null;
  }

  /// Levels beyond the base one — what the user pays Radianite to unlock.
  List<SkinLevel> get upgradeLevels =>
      levels.length <= 1 ? const <SkinLevel>[] : levels.sublist(1);

  bool get hasChromas => chromas.length > 1;

  /// Standard-issue skins ("Vandal", "Classic") have no content tier and are
  /// never sold, so they are filtered out of pickers.
  bool get isPurchasable => contentTierUuid != null;

  /// `Vandal: Prime` — the exact shape the shop notification uses.
  String get notificationLabel => '$weaponName: $displayName';

  factory WeaponSkin.fromJson(
    Map<String, dynamic> json, {
    required String weaponUuid,
    required String weaponName,
    required String weaponCategory,
  }) {
    return WeaponSkin(
      uuid: json['uuid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown skin',
      weaponUuid: weaponUuid,
      weaponName: weaponName,
      weaponCategory: weaponCategory,
      contentTierUuid: json['contentTierUuid'] as String?,
      themeUuid: json['themeUuid'] as String?,
      displayIcon: json['displayIcon'] as String?,
      wallpaper: json['wallpaper'] as String?,
      levels: _list(json['levels'])
          .map(SkinLevel.fromJson)
          .toList(growable: false),
      chromas: _list(json['chromas'])
          .map(SkinChroma.fromJson)
          .toList(growable: false),
    );
  }

  /// Round-trips through the Hive cache. Note this stores the *flattened*
  /// shape, so it is not interchangeable with the raw API payload.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'displayName': displayName,
    'weaponUuid': weaponUuid,
    'weaponName': weaponName,
    'weaponCategory': weaponCategory,
    'contentTierUuid': contentTierUuid,
    'themeUuid': themeUuid,
    'displayIcon': displayIcon,
    'wallpaper': wallpaper,
    'levels': levels.map((SkinLevel l) => l.toJson()).toList(),
    'chromas': chromas.map((SkinChroma c) => c.toJson()).toList(),
  };

  factory WeaponSkin.fromCacheJson(Map<String, dynamic> json) => WeaponSkin(
    uuid: json['uuid'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Unknown skin',
    weaponUuid: json['weaponUuid'] as String? ?? '',
    weaponName: json['weaponName'] as String? ?? '',
    weaponCategory: json['weaponCategory'] as String? ?? '',
    contentTierUuid: json['contentTierUuid'] as String?,
    themeUuid: json['themeUuid'] as String?,
    displayIcon: json['displayIcon'] as String?,
    wallpaper: json['wallpaper'] as String?,
    levels: _list(json['levels'])
        .map(SkinLevel.fromJson)
        .toList(growable: false),
    chromas: _list(json['chromas'])
        .map(SkinChroma.fromJson)
        .toList(growable: false),
  );

  static List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
