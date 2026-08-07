import 'package:dio/dio.dart';

import '../../../../core/constants/riot_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../player/data/models/player_profile.dart';
import '../models/competitive_standing.dart';
import '../models/storefront_snapshot.dart';
import 'storefront_parser.dart';

/// Reads the player's store, wallet, collection and rank from Riot's Player
/// Data endpoints.
///
/// Auth headers are added by the interceptor on the injected [Dio]; nothing in
/// here touches tokens.
class RiotStoreApi {
  RiotStoreApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Fetches the storefront.
  ///
  /// Riot moved this from `GET /store/v2` to `POST /store/v3` and older clients
  /// still work — for now. We try v3 first and fall back, so the app survives
  /// whichever one they retire next.
  Future<StorefrontSnapshot> fetchStorefront({
    required String shard,
    required String puuid,
  }) async {
    Map<String, dynamic>? body;

    try {
      final Response<dynamic> v3 = await _dio.post<dynamic>(
        RiotConstants.storefrontV3(shard, puuid),
        data: const <String, dynamic>{},
      );
      body = _asMap(v3.data);
    } on DioException catch (e) {
      // A 404/405 means this shard is still on v2. Anything else (auth, rate
      // limiting) is a real failure and must not be masked by the fallback.
      final int? status = e.response?.statusCode;
      if (status != 404 && status != 405) rethrow;
      Log.d('Store', 'v3 storefront unavailable ($status), falling back to v2');
    }

    if (body == null || body.isEmpty) {
      final Response<dynamic> v2 = await _dio.get<dynamic>(
        RiotConstants.storefrontV2(shard, puuid),
      );
      body = _asMap(v2.data);
    }

    return StorefrontParser.parse(body);
  }

  Future<Wallet> fetchWallet({
    required String shard,
    required String puuid,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      RiotConstants.wallet(shard, puuid),
    );
    final Map<String, dynamic> balances = _asMap(
      _asMap(response.data)['Balances'],
    );

    int read(String currencyUuid) =>
        (balances[currencyUuid] as num?)?.toInt() ?? 0;

    return Wallet(
      valorantPoints: read(RiotConstants.currencyValorantPoints),
      radianitePoints: read(RiotConstants.currencyRadianitePoints),
      kingdomCredits: read(RiotConstants.currencyKingdomCredits),
    );
  }

  /// UUIDs of every skin *level* the player owns.
  ///
  /// Riot returns level ids, not skin ids, which is why the Collection tab
  /// matches on `WeaponSkin.offerUuid` rather than `WeaponSkin.uuid`.
  Future<Set<String>> fetchOwnedSkinLevels({
    required String shard,
    required String puuid,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      RiotConstants.entitlementsByType(
        shard,
        puuid,
        RiotConstants.itemTypeSkinLevels,
      ),
    );

    final Object? entitlements = _asMap(response.data)['Entitlements'];
    if (entitlements is! List) return <String>{};

    return entitlements
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> e) => e['ItemID'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// The player's current competitive tier and RR.
  ///
  /// Returns null when it genuinely could not be determined, which is *not*
  /// the same as being unranked — the previous version conflated the two and
  /// silently rendered every failure as "Unranked".
  ///
  /// Three sources, in descending order of trustworthiness:
  ///
  /// 1. `QueueSkills.competitive.SeasonalInfoBySeasonID[act]` — the act's
  ///    standing, which is what the in-game card shows. Needs [actUuid].
  /// 2. `LatestCompetitiveUpdate` — correct unless the act just rolled over.
  /// 3. `/competitiveupdates` — the last rated match, as a final fallback.
  Future<CompetitiveStanding?> fetchCompetitiveStanding({
    required String shard,
    required String puuid,
    String? actUuid,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        RiotConstants.mmrPlayer(shard, puuid),
      );
      final Map<String, dynamic> body = _asMap(response.data);

      if (actUuid != null) {
        final Map<String, dynamic> seasons = _asMap(
          _asMap(
            _asMap(body['QueueSkills'])['competitive'],
          )['SeasonalInfoBySeasonID'],
        );
        final Map<String, dynamic> act = _asMap(seasons[actUuid]);
        final int tier = (act['CompetitiveTier'] as num?)?.toInt() ?? 0;
        if (tier > 0) {
          return CompetitiveStanding(
            tier: tier,
            rankedRating: (act['RankedRating'] as num?)?.toInt() ?? 0,
          );
        }
      }

      final Map<String, dynamic> latest = _asMap(
        body['LatestCompetitiveUpdate'],
      );
      final int latestTier =
          (latest['TierAfterUpdate'] as num?)?.toInt() ?? 0;
      if (latestTier > 0) {
        return CompetitiveStanding(
          tier: latestTier,
          rankedRating:
              (latest['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
        );
      }

      // The record exists and simply has no rank in it: genuinely unranked.
      if (body.isNotEmpty) return const CompetitiveStanding.unranked();
    } on DioException catch (e) {
      Log.e('Store', 'MMR record unavailable (${e.response?.statusCode})', e);
    }

    return _fetchStandingFromLastMatch(shard: shard, puuid: puuid);
  }

  Future<CompetitiveStanding?> _fetchStandingFromLastMatch({
    required String shard,
    required String puuid,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        RiotConstants.competitiveUpdates(shard, puuid),
      );
      final Object? matches = _asMap(response.data)['Matches'];
      if (matches is! List || matches.isEmpty) {
        return const CompetitiveStanding.unranked();
      }
      final Map<String, dynamic> latest = _asMap(matches.first);
      return CompetitiveStanding(
        tier: (latest['TierAfterUpdate'] as num?)?.toInt() ?? 0,
        rankedRating:
            (latest['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      // Rank is decoration; never fail the header over it. But say so, rather
      // than claiming the player is unranked.
      Log.e('Store', 'Competitive updates unavailable', e);
      return null;
    }
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};
}
