import 'package:dio/dio.dart';

import '../../../../core/constants/riot_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../player/data/models/player_profile.dart';
import '../models/competitive_standing.dart';
import '../models/rank_attempt.dart';
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
  /// the same as being unranked — conflating the two renders every outage as a
  /// confident "Unranked".
  ///
  /// Riot exposes rank through more than one endpoint and their availability
  /// varies by account, so each is tried in turn and the first usable answer
  /// wins. [actUuids] should be newest first: the MMR record is keyed by
  /// season, and a player who has not played this act still has a standing
  /// from the previous one.
  ///
  /// [attempts], when supplied, is filled with what each source did — including
  /// the response's top-level keys on a miss, which is what makes an unexpected
  /// payload shape diagnosable from the device instead of guessed at.
  Future<CompetitiveStanding?> fetchCompetitiveStanding({
    required String shard,
    required String puuid,
    List<String> actUuids = const <String>[],
    List<RankAttempt>? attempts,
  }) async {
    final CompetitiveStanding? fromRecord = await _standingFromMmrRecord(
      shard: shard,
      puuid: puuid,
      actUuids: actUuids,
      attempts: attempts,
    );
    if (fromRecord != null && !fromRecord.isUnranked) return fromRecord;

    final CompetitiveStanding? fromMatches = await _standingFromUpdates(
      shard: shard,
      puuid: puuid,
      queue: 'competitive',
      attempts: attempts,
    );
    if (fromMatches != null && !fromMatches.isUnranked) return fromMatches;

    final CompetitiveStanding? unfiltered = await _standingFromUpdates(
      shard: shard,
      puuid: puuid,
      queue: null,
      attempts: attempts,
    );
    if (unfiltered != null && !unfiltered.isUnranked) return unfiltered;

    // If any source answered, the player really is unranked; if they all
    // failed, we do not know.
    return fromRecord ?? fromMatches ?? unfiltered;
  }

  Future<CompetitiveStanding?> _standingFromMmrRecord({
    required String shard,
    required String puuid,
    required List<String> actUuids,
    List<RankAttempt>? attempts,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        RiotConstants.mmrPlayer(shard, puuid),
      );
      final Map<String, dynamic> body = _asMap(response.data);
      if (body.isEmpty) {
        attempts?.add(
          RankAttempt(
            'MMR record',
            ok: true,
            note: 'unreadable body (${_shapeOf(response.data)})',
          ),
        );
        return null;
      }

      final Map<String, dynamic> seasons = _asMap(
        _asMap(
          _asMap(body['QueueSkills'])['competitive'],
        )['SeasonalInfoBySeasonID'],
      );

      // Walk acts newest first, so a gap in the current act falls back to the
      // most recent one the player actually placed in.
      for (final String uuid in actUuids) {
        final Map<String, dynamic> act = _asMap(seasons[uuid]);
        final int tier = (act['CompetitiveTier'] as num?)?.toInt() ?? 0;
        if (tier > 0) {
          attempts?.add(
            const RankAttempt('MMR record (seasonal)', ok: true),
          );
          return CompetitiveStanding(
            tier: tier,
            rankedRating: (act['RankedRating'] as num?)?.toInt() ?? 0,
          );
        }
      }

      final Map<String, dynamic> latest = _asMap(
        body['LatestCompetitiveUpdate'],
      );
      final int latestTier = (latest['TierAfterUpdate'] as num?)?.toInt() ?? 0;
      if (latestTier > 0) {
        attempts?.add(const RankAttempt('MMR record (latest)', ok: true));
        return CompetitiveStanding(
          tier: latestTier,
          rankedRating:
              (latest['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
        );
      }

      attempts?.add(
        RankAttempt(
          'MMR record',
          ok: true,
          note: 'no rank · ${seasons.length} seasons · keys ${_keys(body)}',
        ),
      );
      return const CompetitiveStanding.unranked();
    } on DioException catch (e) {
      final int? status = e.response?.statusCode;
      attempts?.add(
        RankAttempt(
          'MMR record',
          ok: false,
          note: 'HTTP ${status ?? e.type.name}',
        ),
      );
      Log.e('Store', 'MMR record unavailable ($status)', e);
      return null;
    }
  }

  Future<CompetitiveStanding?> _standingFromUpdates({
    required String shard,
    required String puuid,
    required String? queue,
    List<RankAttempt>? attempts,
  }) async {
    final String label =
        'Match history${queue == null ? ' (all queues)' : ' (competitive)'}';
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        RiotConstants.competitiveUpdates(shard, puuid, queue: queue),
      );
      final Map<String, dynamic> body = _asMap(response.data);
      final Object? matches = body['Matches'];

      if (matches is! List) {
        // Report the shape rather than a bare "no matches": an unexpected
        // payload and an empty history are entirely different problems.
        attempts?.add(
          RankAttempt(
            label,
            ok: true,
            note: body.isEmpty
                ? 'unreadable body (${_shapeOf(response.data)})'
                : 'no Matches · keys ${_keys(body)}',
          ),
        );
        return const CompetitiveStanding.unranked();
      }

      // Scan rather than taking the head: placement and unrated results carry
      // TierAfterUpdate 0 and would otherwise mask a perfectly good rank.
      for (final Object? raw in matches) {
        final Map<String, dynamic> m = _asMap(raw);
        final int tier = (m['TierAfterUpdate'] as num?)?.toInt() ?? 0;
        if (tier > 0) {
          attempts?.add(
            RankAttempt(label, ok: true, note: '${matches.length} matches'),
          );
          return CompetitiveStanding(
            tier: tier,
            rankedRating: (m['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
          );
        }
      }

      attempts?.add(
        RankAttempt(
          label,
          ok: true,
          note: '${matches.length} matches, none rated',
        ),
      );
      return const CompetitiveStanding.unranked();
    } on DioException catch (e) {
      final int? status = e.response?.statusCode;
      attempts?.add(
        RankAttempt(label, ok: false, note: 'HTTP ${status ?? e.type.name}'),
      );
      Log.e('Store', '$label unavailable ($status)', e);
      return null;
    }
  }

  /// Top-level keys, truncated. Structure only — never values, which on these
  /// endpoints include account identifiers.
  static String _keys(Map<String, dynamic> body) {
    final List<String> keys = body.keys.take(6).toList();
    return '[${keys.join(', ')}${body.length > 6 ? ', …' : ''}]';
  }

  /// What the body actually deserialised to, when it was not a JSON object.
  static String _shapeOf(Object? data) {
    if (data == null) return 'null';
    if (data is String) {
      return 'String, ${data.length} chars';
    }
    return data.runtimeType.toString();
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};
}
