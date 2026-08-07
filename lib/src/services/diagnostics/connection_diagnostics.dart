import 'package:dio/dio.dart';

import '../../app/dependencies.dart';
import '../../core/constants/riot_constants.dart';
import '../../features/auth/data/models/riot_session.dart';
import '../../features/store/data/models/competitive_standing.dart';
import '../../features/store/data/models/rank_attempt.dart';

/// One probe result.
class DiagnosticResult {
  const DiagnosticResult(this.label, {required this.ok, this.detail});

  final String label;
  final bool ok;
  final String? detail;
}

/// Probes each backend the header and shop depend on, individually.
///
/// The repositories deliberately absorb failures so one dead endpoint cannot
/// blank the UI — which is right for users and useless for debugging. This
/// walks the same endpoints and reports exactly what each one returned, so a
/// problem on someone else's account can be described precisely instead of
/// guessed at across a round trip.
class ConnectionDiagnostics {
  const ConnectionDiagnostics(this._deps);

  final AppDependencies _deps;

  Future<List<DiagnosticResult>> run() async {
    final List<DiagnosticResult> results = <DiagnosticResult>[];

    final RiotSession? session = _deps.sessions.session;
    if (session == null) {
      results.add(
        DiagnosticResult(
          'Session',
          ok: _deps.isDemoMode,
          detail: _deps.isDemoMode ? 'Demo mode' : 'Not signed in',
        ),
      );
      return results;
    }

    results.add(
      DiagnosticResult(
        'Session',
        ok: !session.isExpired,
        detail:
            '${session.riotId} · shard ${session.shard} · '
            '${session.isExpired ? 'token expired' : 'token valid'}',
      ),
    );

    results.add(
      await _probe(
        'Wallet (VP / RP)',
        () => _deps.gameDio.get<dynamic>(
          RiotConstants.wallet(session.shard, session.puuid),
        ),
      ),
    );
    // Rank is resolved through several endpoints; report what each one did
    // rather than a single pass/fail that hides which source is broken.
    final String? act = await _deps.content.currentActUuid();
    final List<String> actUuids = await _deps.content.actUuidsNewestFirst();
    final List<RankAttempt> attempts = <RankAttempt>[];
    final CompetitiveStanding? standing = await _deps.storeApi
        .fetchCompetitiveStanding(
          shard: session.shard,
          puuid: session.puuid,
          actUuids: actUuids,
          attempts: attempts,
        );

    results.add(
      DiagnosticResult(
        'Rank',
        ok: standing != null && !standing.isUnranked,
        detail: standing == null
            ? 'every source failed'
            : standing.isUnranked
            ? 'all sources answered; no rank found'
            : 'tier ${standing.tier} · ${standing.rankedRating} RR',
      ),
    );
    for (final RankAttempt attempt in attempts) {
      results.add(
        DiagnosticResult(
          '   ${attempt.source}',
          ok: attempt.ok,
          detail: attempt.note,
        ),
      );
    }
    results.add(
      await _probe(
        'Storefront',
        () => _deps.gameDio.post<dynamic>(
          RiotConstants.storefrontV3(session.shard, session.puuid),
          data: const <String, dynamic>{},
        ),
      ),
    );
    results.add(
      await _probe(
        'Collection',
        () => _deps.gameDio.get<dynamic>(
          RiotConstants.entitlementsByType(
            session.shard,
            session.puuid,
            RiotConstants.itemTypeSkinLevels,
          ),
        ),
      ),
    );

    results.add(
      DiagnosticResult(
        'Current act',
        ok: act != null,
        detail: act == null
            ? 'unresolved — rank falls back to the last rated match'
            : '$act (${actUuids.length} acts known)',
      ),
    );

    results.add(
      DiagnosticResult(
        'Client version',
        ok: true,
        detail: _deps.clientVersion.value,
      ),
    );

    results.add(
      DiagnosticResult(
        'Notifications',
        ok: await _deps.notifications.areNotificationsEnabled(),
        detail: 'Android permission',
      ),
    );

    return results;
  }

  Future<DiagnosticResult> _probe(
    String label,
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final Response<dynamic> response = await call();
      return DiagnosticResult(
        label,
        ok: true,
        detail: 'HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      final int? status = e.response?.statusCode;
      return DiagnosticResult(
        label,
        ok: false,
        detail: status != null ? 'HTTP $status' : e.type.name,
      );
    } on Object catch (e) {
      return DiagnosticResult(label, ok: false, detail: '$e');
    }
  }
}
