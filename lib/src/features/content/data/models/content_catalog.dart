import '../../../../core/errors/app_exception.dart';
import 'content_tier.dart';
import 'weapon_skin.dart';

/// Everything static the app needs, resolved and indexed once.
///
/// Building the lookup maps up front turns every render-time question
/// ("which skin is offer `x`?") into an O(1) map read instead of a scan over
/// ~1600 skins — which matters, because the shop grid rebuilds on every tick of
/// the reset countdown.
class ContentCatalog {
  ContentCatalog({
    required this.skins,
    required this.tiers,
    required this.competitiveTiers,
    required this.language,
    required this.fetchedAt,
  }) : _byUuid = <String, WeaponSkin>{},
       _byOfferUuid = <String, WeaponSkin>{} {
    for (final WeaponSkin skin in skins) {
      _byUuid[skin.uuid] = skin;
      // Any level UUID can turn up as an offer id, so index them all.
      for (final SkinLevel level in skin.levels) {
        _byOfferUuid[level.uuid] = skin;
      }
      for (final SkinChroma chroma in skin.chromas) {
        _byOfferUuid.putIfAbsent(chroma.uuid, () => skin);
      }
    }
  }

  final List<WeaponSkin> skins;

  /// Rarity tiers, keyed by UUID.
  final Map<String, ContentTier> tiers;

  /// Competitive ranks, keyed by Riot's numeric tier.
  final Map<int, CompetitiveTier> competitiveTiers;

  final String language;
  final DateTime fetchedAt;

  final Map<String, WeaponSkin> _byUuid;
  final Map<String, WeaponSkin> _byOfferUuid;

  WeaponSkin? skinByUuid(String uuid) => _byUuid[uuid];

  /// Resolves a storefront offer id (a skin *level* uuid) to its skin.
  WeaponSkin? skinByOfferUuid(String offerUuid) =>
      _byOfferUuid[offerUuid] ?? _byUuid[offerUuid];

  ContentTier? tierOf(WeaponSkin skin) =>
      skin.contentTierUuid == null ? null : tiers[skin.contentTierUuid];

  CompetitiveTier competitiveTier(int tier) =>
      competitiveTiers[tier] ?? CompetitiveTier.unranked;

  /// Skins that can actually appear in a shop — i.e. excluding the standard
  /// issue weapons, which have no content tier and are never sold.
  late final List<WeaponSkin> purchasableSkins = skins
      .where((WeaponSkin s) => s.isPurchasable)
      .toList(growable: false);

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > const Duration(hours: 24);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'language': language,
    'fetchedAt': fetchedAt.toIso8601String(),
    'skins': skins.map((WeaponSkin s) => s.toJson()).toList(),
    'tiers': tiers.map(
      (String k, ContentTier v) => MapEntry<String, dynamic>(k, v.toJson()),
    ),
    'competitiveTiers': competitiveTiers.map(
      (int k, CompetitiveTier v) => MapEntry<String, dynamic>('$k', v.toJson()),
    ),
  };

  factory ContentCatalog.fromJson(Map<String, dynamic> json) {
    final Object? rawSkins = json['skins'];
    if (rawSkins is! List) {
      throw const ParseException('Cached catalogue is missing its skin list.');
    }
    return ContentCatalog(
      language: json['language'] as String? ?? 'en-US',
      fetchedAt:
          DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      skins: rawSkins
          .whereType<Map<String, dynamic>>()
          .map(WeaponSkin.fromCacheJson)
          .toList(growable: false),
      tiers: _mapOf<ContentTier>(json['tiers'], ContentTier.fromJson),
      competitiveTiers:
          _mapOf<CompetitiveTier>(
            json['competitiveTiers'],
            CompetitiveTier.fromJson,
          ).map(
            (String k, CompetitiveTier v) =>
                MapEntry<int, CompetitiveTier>(int.tryParse(k) ?? 0, v),
          ),
    );
  }

  static Map<String, T> _mapOf<T>(
    Object? raw,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (raw is! Map) return <String, T>{};
    final Map<String, T> out = <String, T>{};
    raw.forEach((Object? key, Object? value) {
      if (key is String && value is Map<String, dynamic>) {
        out[key] = parse(value);
      }
    });
    return out;
  }
}
