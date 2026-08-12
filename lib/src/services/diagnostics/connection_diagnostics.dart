import 'package:dio/dio.dart';

import '../../app/dependencies.dart';
import '../../core/constants/riot_constants.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/platform/battery_optimisation.dart';
import '../../features/auth/data/models/riot_session.dart';
import '../../features/store/data/models/competitive_standing.dart';
import '../../features/store/data/models/rank_attempt.dart';
import '../background/background_run_log.dart';
import '../notifications/notification_schedule.dart';
import '../notifications/notification_service.dart';

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
      // Reported even here — in fact especially here. A signed-out app with a
      // good cookie should have restored itself at start-up, so seeing one
      // present says the recovery failed rather than that there was nothing to
      // recover from.
      results.add(await _refreshCookieCheck());
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

    results.add(await _refreshCookieCheck());
    results.add(_backgroundCheck());
    results.add(await _scheduledCheck());
    results.add(await _permissionCheck());
    results.add(await _exactAlarmCheck());
    results.add(_lastRunCheck());
    results.add(await _batteryCheck());

    return results;
  }

  /// Whether Android is *allowed* to run the background check.
  ///
  /// Paired with the line above on purpose. "Never run" plus "optimised" is a
  /// complete diagnosis and the fix is two taps in system settings; "never run"
  /// plus "exempt" means something else entirely and the app has a bug.
  Future<DiagnosticResult> _batteryCheck() async {
    final bool? exempt = await const BatteryOptimisation().isExempt();
    if (exempt == null) {
      return const DiagnosticResult(
        'Battery optimisation',
        ok: false,
        detail: 'Could not be read',
      );
    }
    return DiagnosticResult(
      'Battery optimisation',
      ok: exempt,
      detail: exempt
          ? 'Unrestricted — background checks may run'
          : 'Restricted — Android may never start the nightly check',
    );
  }

  /// Whether Android has actually been starting the background check.
  ///
  /// Everything else on this screen describes the app's own state; this is the
  /// one line about a thing the app does not control. A notification that
  /// depends on a nightly worker has two completely different failure modes —
  /// the worker never ran, or it ran and something went wrong — and they are
  /// indistinguishable from the outside. Zero runs after a night points at
  /// battery optimisation or app standby, which no amount of code here fixes.
  DiagnosticResult _lastRunCheck() {
    final BackgroundRunLog? log = BackgroundRunLog.read(_deps.localStore);
    if (log == null) {
      return const DiagnosticResult(
        'Background check',
        ok: false,
        detail: 'Never run — Android has not started it since install',
      );
    }

    final String when = _shortTime(log.at);
    if (!log.finished) {
      return DiagnosticResult(
        'Background check',
        ok: false,
        detail:
            'Started $when and never finished (run ${log.runs}) — killed '
            'partway through',
      );
    }

    return DiagnosticResult(
      'Background check',
      ok: log.outcome == BackgroundRunLog.ok,
      detail: '$when, run ${log.runs}: ${log.detail ?? log.outcome}',
    );
  }

  static String _shortTime(DateTime at) {
    final DateTime local = at.toLocal();
    final String hhmm =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final DateTime today = DateTime.now();
    final bool sameDay =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    return sameDay ? hhmm : '${local.day}.${local.month}. $hhmm';
  }

  /// Whether Android will show anything we post at all.
  ///
  /// Denying the prompt once, months ago, is indistinguishable from every other
  /// cause of "no notification arrived" unless something says so out loud.
  Future<DiagnosticResult> _permissionCheck() async {
    final bool enabled = await _deps.notifications.areNotificationsEnabled();
    return DiagnosticResult(
      'Notification permission',
      ok: enabled,
      detail: enabled
          ? 'Granted'
          : 'Blocked in system settings — nothing can be shown',
    );
  }

  /// Punctuality, separately from delivery.
  ///
  /// Only meaningful with a delivery time set: without the permission the alarm
  /// is batched into Android's next maintenance window, which is how a 09:00
  /// notification turns up at 09:20 with nothing actually broken.
  Future<DiagnosticResult> _exactAlarmCheck() async {
    final NotificationSchedule schedule = NotificationSchedule.read(
      _deps.localStore,
    );
    if (!schedule.enabled) {
      return const DiagnosticResult(
        'Exact delivery',
        ok: true,
        detail: 'Not applicable — delivery is immediate',
      );
    }

    final bool exact = await _deps.notifications.canScheduleExactly();
    return DiagnosticResult(
      'Exact delivery',
      ok: exact,
      detail: exact
          ? 'Allowed — arrives at ${schedule.label}'
          : 'Alarms & reminders not permitted — can arrive up to ~20 min late',
    );
  }

  /// The single thing that decides whether the background worker can do
  /// anything at all.
  ///
  /// Without this cookie the worker cannot renew an expired token, so it skips
  /// every run — and the only symptom is a notification that never arrives,
  /// which looks identical to a notification the app decided not to send.
  Future<DiagnosticResult> _refreshCookieCheck() async {
    final bool present = await _deps.authApi.hasSessionCookie();
    return DiagnosticResult(
      'Refresh cookie',
      ok: present,
      detail: present
          ? 'Stored — background refresh can run'
          : 'Missing — the app will sign itself out when the token lapses '
                'and no notifications will be scheduled',
    );
  }

  DiagnosticResult _backgroundCheck() {
    final NotificationSchedule schedule = NotificationSchedule.read(
      _deps.localStore,
    );
    final bool wantsShop = _deps.localStore.setting<bool>(
      SettingKeys.shopNotificationsEnabled,
      true,
    );

    return DiagnosticResult(
      'Shop notification',
      ok: wantsShop && _deps.canFetchShop,
      detail: !wantsShop
          ? 'Switched off in settings'
          : !_deps.canFetchShop
          ? 'Cannot run — not signed in'
          : schedule.enabled
          ? 'On, delivered at ${schedule.label}'
          : 'On, delivered at shop reset',
    );
  }

  /// What Android is actually holding for us.
  ///
  /// A delivery time only produces a notification if an alarm was queued, and
  /// this is the one place that difference is visible: an empty queue with the
  /// setting on means the rotation was never detected, not that the alarm was
  /// dropped.
  Future<DiagnosticResult> _scheduledCheck() async {
    final NotificationSchedule schedule = NotificationSchedule.read(
      _deps.localStore,
    );
    final Set<int> pending = await _deps.notifications.pendingIds();

    // Named, not counted. "1 waiting for 09:30" was shown for a test queued
    // one minute out, because the line printed the *setting* rather than
    // anything Android had actually been told — the plugin does not report the
    // time an alarm is set for. Saying which alarm it is, is the honest limit.
    final List<String> waiting = <String>[
      if (pending.contains(NotificationService.shopNotificationId))
        'shop digest',
      if (pending.contains(NotificationService.wishlistNotificationId))
        'wishlist alert',
      if (pending.contains(NotificationService.testNotificationId)) 'test',
    ];

    if (!schedule.enabled) {
      return DiagnosticResult(
        'Queued notifications',
        ok: true,
        detail: waiting.isEmpty
            ? 'None — delivery is immediate, so nothing waits'
            : 'Waiting: ${waiting.join(', ')}',
      );
    }

    return DiagnosticResult(
      'Queued notifications',
      ok: waiting.isNotEmpty,
      detail: waiting.isEmpty
          ? 'None queued — nothing has detected a shop rotation yet'
          : 'Waiting: ${waiting.join(', ')} (delivery set to ${schedule.label})',
    );
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
