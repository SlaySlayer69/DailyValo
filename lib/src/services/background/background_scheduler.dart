import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/dependencies.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/logger.dart';
import '../logging/log_file.dart';
import 'background_run_log.dart';
import 'shop_sync_service.dart';

/// Task identifiers. `uniqueName` deduplicates in WorkManager's queue;
/// `taskName` is what the dispatcher switches on.
abstract final class BackgroundTasks {
  /// Safety net: runs regardless of whether the targeted check fired.
  static const String periodicUnique = 'dv.shop.periodic';
  static const String periodicName = 'shopPeriodicCheck';

  /// Scheduled to land just after the next known shop reset.
  static const String resetUnique = 'dv.shop.reset';
  static const String resetName = 'shopResetCheck';
}

/// WorkManager's entry point.
///
/// Must be a top-level function annotated `@pragma('vm:entry-point')` — Android
/// spins up a *fresh* Dart isolate with no access to anything `main()` set up,
/// and the annotation is what stops tree-shaking from removing it in release.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    // Plugins whose implementation lives in Dart rather than in the Android
    // engine register here. WorkManager builds a `FlutterEngine`, which brings
    // up the Android-side registrant but not this one, and a plugin that is
    // missing throws on first use — which in this isolate means the whole run
    // dies before it can schedule anything.
    DartPluginRegistrant.ensureInitialized();

    Log.d('Worker', 'Task fired: $task');

    // Opened before the graph, and separately from it, so that a failure
    // anywhere in `bootstrap` is still recorded. Everything below is written
    // down: the run log is the only window into an isolate nobody can watch.
    LocalStore? store;
    int runs = 0;
    try {
      store = await LocalStore.init();
      runs = BackgroundRunLog.nextRunCount(store);
      await BackgroundRunLog.write(
        store,
        task: task,
        outcome: BackgroundRunLog.started,
        runs: runs,
      );
    } on Object catch (e, st) {
      Log.e('Worker', 'Could not open storage', e, st);
    }

    Future<void> note(String outcome, String detail) async {
      if (store != null) {
        await BackgroundRunLog.write(
          store,
          task: task,
          outcome: outcome,
          runs: runs,
          detail: detail,
        );
      }
    }

    try {
      // A complete, independent object graph — see AppDependencies.
      final AppDependencies deps = await AppDependencies.bootstrap(
        isBackground: true,
      );

      if (!deps.canFetchShop) {
        Log.d('Worker', 'Nothing to sync (signed out)');
        await note(BackgroundRunLog.ok, 'Signed out — nothing to check');
        return true;
      }

      final ShopSyncOutcome outcome = await ShopSyncService(deps).sync();
      Log.d(
        'Worker',
        'Sync done: changed=${outcome.shopChanged}, '
            'wishlistHits=${outcome.wishlistMatches.length}',
      );

      // Re-arm the targeted check for the next reset we now know about.
      final DateTime? next = outcome.nextResetAt;
      if (next != null) await BackgroundScheduler.scheduleResetCheck(next);

      await note(BackgroundRunLog.ok, _describe(outcome));
      return true;
    } on Object catch (e, st) {
      Log.e('Worker', 'Background sync failed', e, st);
      await note(BackgroundRunLog.failed, e.toString());
      // Returning false asks WorkManager to retry with backoff. A transient
      // network blip is exactly the case that deserves one.
      return false;
    } finally {
      // This isolate is killed the instant the callback returns, taking any
      // unflushed log lines with it — and the background run is the part the
      // log exists for.
      await LogFile.instance?.flush();
    }
  });
}

/// A sentence about a sync, for the diagnostics screen.
String _describe(ShopSyncOutcome outcome) {
  final String? skipped = outcome.skipped;
  if (skipped != null) return 'Skipped — $skipped';
  if (!outcome.shopChanged) return 'Shop unchanged';

  final DateTime? deferred = outcome.notificationsDeferredUntil;
  final String hits = outcome.wishlistMatches.isEmpty
      ? ''
      : ', ${outcome.wishlistMatches.length} wishlist hit(s)';
  return deferred == null
      ? 'Rotation found, notified straight away$hits'
      : 'Rotation found, queued for '
            '${deferred.hour.toString().padLeft(2, '0')}:'
            '${deferred.minute.toString().padLeft(2, '0')}$hits';
}

/// Registers and re-arms the background work.
///
/// Two overlapping schedules, on purpose:
///
/// * a **one-off** task aimed a few minutes after the next known shop reset —
///   accurate, and the reason a notification arrives close to 00:00 UTC;
/// * a **periodic** task every six hours — Android may defer or drop the
///   one-off (Doze, app standby buckets, reboot), and this guarantees the miss
///   is caught within a few hours instead of never.
///
/// Both funnel into the same idempotent [ShopSyncService], so a double fire
/// costs one wasted request and nothing else.
abstract final class BackgroundScheduler {
  /// Android throttles periodic work below 15 minutes; six hours is well clear
  /// of that and cheap on battery.
  static const Duration periodicFrequency = Duration(hours: 6);

  /// Riot's countdown and the device clock disagree by a few seconds; land
  /// after the rotation, not on top of it.
  static const Duration resetGrace = Duration(minutes: 3);

  static Future<void> initialise() async {
    if (kIsWeb) return;
    await Workmanager().initialize(backgroundCallbackDispatcher);
  }

  /// Starts the recurring safety-net check. Idempotent — calling it on every
  /// launch just updates the existing registration.
  static Future<void> registerPeriodicCheck() async {
    if (kIsWeb) return;
    await Workmanager().registerPeriodicTask(
      BackgroundTasks.periodicUnique,
      BackgroundTasks.periodicName,
      frequency: periodicFrequency,
      initialDelay: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 10),
    );
    Log.d('Scheduler', 'Periodic check registered');
  }

  /// Aims a one-off check just after [resetAt].
  ///
  /// Replaces any previously scheduled reset check, so re-arming on every sync
  /// keeps exactly one in the queue.
  static Future<void> scheduleResetCheck(DateTime resetAt) async {
    if (kIsWeb) return;

    final DateTime target = resetAt.add(resetGrace);
    Duration delay = target.difference(DateTime.now());

    // A reset already in the past means we are behind; check shortly rather
    // than scheduling into negative time.
    if (delay.isNegative) delay = const Duration(minutes: 5);

    await Workmanager().registerOneOffTask(
      BackgroundTasks.resetUnique,
      BackgroundTasks.resetName,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
    Log.d('Scheduler', 'Reset check scheduled in ${delay.inMinutes} min');
  }

  /// Called on sign-out — no account, no reason to keep waking the device.
  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await Workmanager().cancelByUniqueName(BackgroundTasks.periodicUnique);
    await Workmanager().cancelByUniqueName(BackgroundTasks.resetUnique);
    Log.d('Scheduler', 'All background work cancelled');
  }
}
