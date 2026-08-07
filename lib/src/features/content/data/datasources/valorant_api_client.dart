import 'package:dio/dio.dart';

import '../../../../core/constants/valorant_api_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/accessory_item.dart';
import '../models/content_tier.dart';
import '../models/weapon_skin.dart';

/// Reads static game content from `valorant-api.com`.
///
/// No authentication, no rate limit worth worrying about, and the payloads are
/// immutable between patches — which is exactly why the repository above this
/// caches aggressively instead of re-fetching.
class ValorantApiClient {
  ValorantApiClient({required Dio dio, this.language = ValorantApiConstants.defaultLanguage})
    : _dio = dio;

  final Dio _dio;

  /// Riot locale tag, e.g. `en-US`, `de-DE`.
  final String language;

  /// Fetches every weapon *with its skins*, flattened.
  ///
  /// One request rather than `/weapons/skins` + `/weapons`, because the
  /// weapon-scoped payload is the only one that tells us which weapon a skin
  /// belongs to — and "Vandal: Prime" needs both halves.
  Future<List<WeaponSkin>> fetchSkins() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      ValorantApiConstants.weapons,
      queryParameters: <String, dynamic>{'language': language},
    );

    final List<Map<String, dynamic>> weapons = _dataList(response.data);
    final List<WeaponSkin> skins = <WeaponSkin>[];

    for (final Map<String, dynamic> weapon in weapons) {
      final String weaponUuid = weapon['uuid'] as String? ?? '';
      final String weaponName = weapon['displayName'] as String? ?? 'Unknown';
      final String category = _categoryOf(weapon['category'] as String?);
      final Object? rawSkins = weapon['skins'];
      if (rawSkins is! List) continue;

      for (final Object? raw in rawSkins) {
        if (raw is! Map<String, dynamic>) continue;
        skins.add(
          WeaponSkin.fromJson(
            raw,
            weaponUuid: weaponUuid,
            weaponName: weaponName,
            weaponCategory: category,
          ),
        );
      }
    }

    if (skins.isEmpty) {
      throw const ParseException('The content API returned no skins.');
    }
    return skins;
  }

  Future<Map<String, ContentTier>> fetchContentTiers() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      ValorantApiConstants.contentTiers,
      queryParameters: <String, dynamic>{'language': language},
    );

    final Map<String, ContentTier> tiers = <String, ContentTier>{};
    for (final Map<String, dynamic> json in _dataList(response.data)) {
      final ContentTier tier = ContentTier.fromJson(json);
      if (tier.uuid.isNotEmpty) tiers[tier.uuid] = tier;
    }
    return tiers;
  }

  /// Competitive ranks from the *current* episode.
  ///
  /// The endpoint returns one entry per episode; the last one is live. Older
  /// entries carry retired rank art, so taking the last is what keeps a
  /// player's badge current.
  Future<Map<int, CompetitiveTier>> fetchCompetitiveTiers() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      ValorantApiConstants.competitiveTiers,
      queryParameters: <String, dynamic>{'language': language},
    );

    final List<Map<String, dynamic>> episodes = _dataList(response.data);
    if (episodes.isEmpty) return <int, CompetitiveTier>{};

    final Object? rawTiers = episodes.last['tiers'];
    if (rawTiers is! List) return <int, CompetitiveTier>{};

    final Map<int, CompetitiveTier> out = <int, CompetitiveTier>{};
    for (final Object? raw in rawTiers) {
      if (raw is! Map<String, dynamic>) continue;
      final CompetitiveTier tier = CompetitiveTier.fromJson(raw);
      out[tier.tier] = tier;
    }
    return out;
  }

  /// UUID of the act running right now.
  ///
  /// Riot's MMR record indexes seasonal rank by act UUID, so without this the
  /// only rank we can read is whatever the last competitive match left behind.
  /// Returns null between acts, or if the payload shape ever changes — the
  /// caller falls back rather than failing.
  /// Sprays, gun buddies, player cards and titles, in one index.
  ///
  /// Keyed by **every** uuid that can appear as a store reward: the item's own
  /// uuid and each of its level uuids. Buddies and sprays are sold by level,
  /// and a buddy's level uuid is not its item uuid — indexing only the latter
  /// leaves the Accessory Store showing blank rows.
  Future<Map<String, AccessoryItem>> fetchAccessories() async {
    final List<Future<Response<dynamic>>> requests =
        <Future<Response<dynamic>>>[
          _get(ValorantApiConstants.sprays),
          _get(ValorantApiConstants.buddies),
          _get(ValorantApiConstants.playerCards),
          _get(ValorantApiConstants.playerTitles),
        ];
    final List<Response<dynamic>> responses = await Future.wait(requests);

    final Map<String, AccessoryItem> index = <String, AccessoryItem>{};

    void add(AccessoryItem item, Map<String, dynamic> raw) {
      if (item.uuid.isEmpty) return;
      index[item.uuid] = item;
      final Object? levels = raw['levels'];
      if (levels is! List) return;
      for (final Object? level in levels) {
        if (level is! Map<String, dynamic>) continue;
        final String? levelUuid = level['uuid'] as String?;
        if (levelUuid != null && levelUuid.isNotEmpty) {
          index.putIfAbsent(levelUuid, () => item);
        }
      }
    }

    for (final Map<String, dynamic> json in _dataList(responses[0].data)) {
      add(
        AccessoryItem(
          uuid: json['uuid'] as String? ?? '',
          displayName: json['displayName'] as String? ?? 'Spray',
          kind: AccessoryKind.spray,
          displayIcon:
              json['fullTransparentIcon'] as String? ??
              json['displayIcon'] as String?,
        ),
        json,
      );
    }

    for (final Map<String, dynamic> json in _dataList(responses[1].data)) {
      add(
        AccessoryItem(
          uuid: json['uuid'] as String? ?? '',
          displayName: json['displayName'] as String? ?? 'Gun Buddy',
          kind: AccessoryKind.buddy,
          displayIcon: json['displayIcon'] as String?,
        ),
        json,
      );
    }

    for (final Map<String, dynamic> json in _dataList(responses[2].data)) {
      add(
        AccessoryItem(
          uuid: json['uuid'] as String? ?? '',
          displayName: json['displayName'] as String? ?? 'Player Card',
          kind: AccessoryKind.playerCard,
          displayIcon: json['displayIcon'] as String?,
          wideArt: json['wideArt'] as String?,
        ),
        json,
      );
    }

    for (final Map<String, dynamic> json in _dataList(responses[3].data)) {
      add(
        AccessoryItem(
          uuid: json['uuid'] as String? ?? '',
          displayName: json['displayName'] as String? ?? 'Title',
          kind: AccessoryKind.playerTitle,
          titleText: json['titleText'] as String?,
        ),
        json,
      );
    }

    return index;
  }

  /// Static content for every bundle Riot has shipped, keyed by uuid.
  Future<Map<String, BundleInfo>> fetchBundles() async {
    final Response<dynamic> response = await _get(
      ValorantApiConstants.bundles,
    );

    final Map<String, BundleInfo> bundles = <String, BundleInfo>{};
    for (final Map<String, dynamic> json in _dataList(response.data)) {
      final BundleInfo bundle = BundleInfo.fromJson(json);
      if (bundle.uuid.isNotEmpty) bundles[bundle.uuid] = bundle;
    }
    return bundles;
  }

  Future<Response<dynamic>> _get(String url) => _dio.get<dynamic>(
    url,
    queryParameters: <String, dynamic>{'language': language},
  );

  /// Every act uuid, newest first.
  ///
  /// The MMR record is keyed by season uuid, and betting on a single "current"
  /// act is fragile: acts roll over, and a player who has not played this act
  /// still has a rank from the previous one. An ordered list lets the caller
  /// walk back until it finds a standing.
  Future<List<String>> fetchActUuidsNewestFirst() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      ValorantApiConstants.seasons,
    );

    final List<({DateTime start, String uuid})> acts =
        <({DateTime start, String uuid})>[];
    for (final Map<String, dynamic> season in _dataList(response.data)) {
      if (!(season['type'] as String? ?? '').contains('Act')) continue;
      final String? uuid = season['uuid'] as String?;
      final DateTime? start = DateTime.tryParse(
        season['startTime'] as String? ?? '',
      );
      if (uuid == null || start == null) continue;
      acts.add((start: start, uuid: uuid));
    }

    acts.sort(
      (({DateTime start, String uuid}) a, ({DateTime start, String uuid}) b) =>
          b.start.compareTo(a.start),
    );
    // Acts that have not started yet cannot hold a standing.
    final DateTime now = DateTime.now().toUtc();
    return acts
        .where((({DateTime start, String uuid}) a) => !a.start.isAfter(now))
        .map((({DateTime start, String uuid}) a) => a.uuid)
        .toList(growable: false);
  }

  Future<String?> fetchCurrentActUuid() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      ValorantApiConstants.seasons,
    );

    final DateTime now = DateTime.now().toUtc();
    for (final Map<String, dynamic> season in _dataList(response.data)) {
      // Episodes also appear in this list; only acts key the MMR record.
      final String type = season['type'] as String? ?? '';
      if (!type.contains('Act')) continue;

      final DateTime? start = DateTime.tryParse(
        season['startTime'] as String? ?? '',
      );
      final DateTime? end = DateTime.tryParse(
        season['endTime'] as String? ?? '',
      );
      if (start == null || end == null) continue;

      if (!now.isBefore(start.toUtc()) && now.isBefore(end.toUtc())) {
        return season['uuid'] as String?;
      }
    }
    return null;
  }

  /// The live `riotClientVersion` string PD endpoints expect.
  Future<String> fetchClientVersion() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      ValorantApiConstants.version,
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const ParseException('Malformed version payload.');
    }
    final Object? inner = data['data'];
    final String? version = inner is Map<String, dynamic>
        ? inner['riotClientVersion'] as String?
        : null;
    if (version == null || version.isEmpty) {
      throw const ParseException('Version payload had no riotClientVersion.');
    }
    return version;
  }

  /// `EEquippableCategory::Rifle` -> `Rifle`.
  static String _categoryOf(String? raw) {
    if (raw == null || raw.isEmpty) return 'Other';
    final int i = raw.lastIndexOf('::');
    return i == -1 ? raw : raw.substring(i + 2);
  }

  static List<Map<String, dynamic>> _dataList(Object? body) {
    if (body is! Map<String, dynamic>) {
      throw const ParseException('Unexpected content API envelope.');
    }
    final Object? data = body['data'];
    if (data is! List) {
      throw const ParseException('Content API returned no data array.');
    }
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
