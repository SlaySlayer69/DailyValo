import 'dart:io';

import 'package:dailyvalo/src/core/constants/storage_keys.dart';
import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:dailyvalo/src/services/background/background_run_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// The record the background worker leaves behind.
///
/// It exists because the worker is unobservable: another isolate, in a process
/// nobody sees, at a time Android chooses. "The worker never ran", "it ran and
/// could not sign in", "it ran and found nothing new" and "it ran and scheduled
/// an alarm that was dropped" all look identical from the outside — no
/// notification — and have nothing in common as problems.
void main() {
  late Directory tempDir;
  late LocalStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dailyvalo_runlog');
    store = await LocalStore.initAt(tempDir.path);
  });

  tearDown(() async {
    await LocalStore.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('BackgroundRunLog', () {
    test('reads back nothing on a device that has never run one', () {
      expect(BackgroundRunLog.read(store), isNull);
      // Which is the whole point: it is distinguishable from a run that
      // happened and did nothing.
      expect(BackgroundRunLog.nextRunCount(store), 1);
    });

    test('round trips a completed run', () async {
      await BackgroundRunLog.write(
        store,
        task: 'shopResetCheck',
        outcome: BackgroundRunLog.ok,
        runs: 3,
        detail: 'Rotation found, queued for 09:15',
      );

      final BackgroundRunLog log = BackgroundRunLog.read(store)!;
      expect(log.task, 'shopResetCheck');
      expect(log.outcome, BackgroundRunLog.ok);
      expect(log.runs, 3);
      expect(log.detail, 'Rotation found, queued for 09:15');
      expect(log.finished, isTrue);
    });

    test('a run that never finished stays marked as started', () async {
      // Written first thing, so a worker Android kills partway through leaves
      // this behind rather than nothing — the difference between "cut off" and
      // "never started".
      await BackgroundRunLog.write(
        store,
        task: 'shopPeriodicCheck',
        outcome: BackgroundRunLog.started,
        runs: 1,
      );

      final BackgroundRunLog log = BackgroundRunLog.read(store)!;
      expect(log.finished, isFalse);
      expect(log.detail, isNull);
    });

    test('counts every run, including the ones that failed', () async {
      await BackgroundRunLog.write(
        store,
        task: 't',
        outcome: BackgroundRunLog.failed,
        runs: BackgroundRunLog.nextRunCount(store),
        detail: 'NotAuthenticatedException',
      );
      expect(BackgroundRunLog.read(store)!.runs, 1);

      await BackgroundRunLog.write(
        store,
        task: 't',
        outcome: BackgroundRunLog.ok,
        runs: BackgroundRunLog.nextRunCount(store),
        detail: 'Shop unchanged',
      );
      // A count that only advanced on success would report "1 run" after a
      // night of failures, which reads as "Android barely ran it" — the
      // opposite of what happened.
      expect(BackgroundRunLog.read(store)!.runs, 2);
    });

    test('survives a sign-out', () async {
      await BackgroundRunLog.write(
        store,
        task: 't',
        outcome: BackgroundRunLog.ok,
        runs: 5,
      );

      await store.clearUserData();

      // It is evidence about Android's scheduling, not about the account, and
      // it is needed most while someone is debugging a sign-in problem.
      expect(BackgroundRunLog.read(store), isNotNull);
      expect(BackgroundRunLog.read(store)!.runs, 5);
    });

    test('a corrupt record reads as null instead of throwing', () async {
      await store.writeCachedString(CacheKeys.lastBackgroundRun, '{not json');
      expect(BackgroundRunLog.read(store), isNull);
    });

    test('a record missing its timestamp reads as null', () async {
      await store.writeCachedString(
        CacheKeys.lastBackgroundRun,
        '{"task":"t","outcome":"ok","runs":1}',
      );
      expect(BackgroundRunLog.read(store), isNull);
    });
  });
}
