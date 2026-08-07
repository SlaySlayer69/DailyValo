/// What kind of accessory an offer contains.
enum AccessoryKind {
  spray('Spray'),
  buddy('Gun Buddy'),
  playerCard('Player Card'),
  playerTitle('Title'),
  unknown('Accessory');

  const AccessoryKind(this.label);

  final String label;

  /// Riot's `ItemTypeID` for each kind, as it appears in store rewards.
  static const String sprayTypeId = 'd5f120f8-ff8c-4aac-92ea-f2b5acbe9475';
  static const String buddyTypeId = 'dd3bf334-87f3-40bd-b043-682a57a8dc3a';
  static const String playerCardTypeId =
      '3f296c07-64c3-494c-923b-fe692a4fa1bd';
  static const String playerTitleTypeId =
      'de7caa6b-adf7-4588-bbd1-143831e786c6';

  static AccessoryKind fromTypeId(String? typeId) => switch (typeId) {
    sprayTypeId => AccessoryKind.spray,
    buddyTypeId => AccessoryKind.buddy,
    playerCardTypeId => AccessoryKind.playerCard,
    playerTitleTypeId => AccessoryKind.playerTitle,
    _ => AccessoryKind.unknown,
  };
}

/// A spray, gun buddy, player card or title — the things the weekly Accessory
/// Store sells for Kingdom Credits.
///
/// One flat type across four very differently shaped API payloads, because the
/// store treats them uniformly: an offer is a price plus a list of reward
/// UUIDs, and the UI only needs a name, an image and a kind.
class AccessoryItem {
  const AccessoryItem({
    required this.uuid,
    required this.displayName,
    required this.kind,
    this.displayIcon,
    this.wideArt,
    this.titleText,
  });

  final String uuid;
  final String displayName;
  final AccessoryKind kind;

  /// Square-ish icon. Null for titles, which are pure text.
  final String? displayIcon;

  /// Player cards only — the banner-shaped art, which is how they are
  /// recognised in game.
  final String? wideArt;

  /// Titles only, e.g. `Legend`.
  final String? titleText;

  /// Best available artwork for a list row.
  String? get artwork => wideArt ?? displayIcon;

  bool get isTextOnly => kind == AccessoryKind.playerTitle;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'displayName': displayName,
    'kind': kind.name,
    'displayIcon': displayIcon,
    'wideArt': wideArt,
    'titleText': titleText,
  };

  factory AccessoryItem.fromCacheJson(Map<String, dynamic> json) =>
      AccessoryItem(
        uuid: json['uuid'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Accessory',
        kind: AccessoryKind.values.firstWhere(
          (AccessoryKind k) => k.name == json['kind'],
          orElse: () => AccessoryKind.unknown,
        ),
        displayIcon: json['displayIcon'] as String?,
        wideArt: json['wideArt'] as String?,
        titleText: json['titleText'] as String?,
      );
}

/// A Featured Bundle's static content: name, key art, description.
class BundleInfo {
  const BundleInfo({
    required this.uuid,
    required this.displayName,
    this.displayIcon,
    this.verticalPromoImage,
    this.displayNameSubText,
    this.description,
  });

  final String uuid;
  final String displayName;

  /// Square logo art.
  final String? displayIcon;

  /// Tall key art Riot uses on the in-game bundle page.
  final String? verticalPromoImage;

  final String? displayNameSubText;
  final String? description;

  String? get artwork => verticalPromoImage ?? displayIcon;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'displayName': displayName,
    'displayIcon': displayIcon,
    'verticalPromoImage': verticalPromoImage,
    'displayNameSubText': displayNameSubText,
    'description': description,
  };

  factory BundleInfo.fromJson(Map<String, dynamic> json) => BundleInfo(
    uuid: json['uuid'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Bundle',
    displayIcon: json['displayIcon'] as String?,
    verticalPromoImage: json['verticalPromoImage'] as String?,
    displayNameSubText: json['displayNameSubText'] as String?,
    description: json['description'] as String?,
  );
}
