import 'package:dio/dio.dart';

import '../../../../core/constants/riot_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../player/data/models/player_profile.dart';
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

  /// Current competitive tier and RR, from the most recent ranked update.
  ///
  /// Returns `(0, 0)` when the player is unranked this act — the endpoint
  /// simply returns an empty match list, which is not an error.
  Future<({int tier, int rankedRating})> fetchCompetitiveStanding({
    required String shard,
    required String puuid,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        RiotConstants.competitiveUpdates(shard, puuid),
      );
      final Object? matches = _asMap(response.data)['Matches'];
      if (matches is! List || matches.isEmpty) {
        return (tier: 0, rankedRating: 0);
      }
      final Map<String, dynamic> latest = _asMap(matches.first);
      return (
        tier: (latest['TierAfterUpdate'] as num?)?.toInt() ?? 0,
        rankedRating: (latest['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      // Rank is decoration; never fail the header over it.
      Log.e('Store', 'Competitive standing lookup failed', e);
      return (tier: 0, rankedRating: 0);
    }
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};
}
