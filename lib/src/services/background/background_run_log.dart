import 'dart:convert';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/logger.dart';

/// What the background worker last did, kept where the UI can read it.
///
/// The worker runs in its own isolate, in a process the user never sees, at a
/// time Android chooses. When a notification does not arrive there is nothing
/// to look at: "the worker never ran", "it ran and could not sign in", "it ran
/// and found no rotation" and "it ran, scheduled the alarm, and the alarm was
/// dropped" all present as the same silence, and they have nothing in common.
///
/// So the worker writes down what happened and the diagnostics screen reads it
/// back. [runs] matters as much as the last outcome: zero after a night means
/// Android is not starting the task at all — a battery-management or
/// app-standby problem, nothing this code can fix — while a non-zero count
/// moves the question to what the run did.
class BackgroundRunLog {
  const BackgroundRunLog({
    required this.at,
    required this.task,
    required this.outcome,
    required this.runs,
    this.detail,
  });

  /// Recorded as soon as the worker has storage, before anything that can
  /// fail. A record still reading `started` when the UI reads it means the run
  /// died partway — killed by Android, or thrown past the handler.
  static const String started = 'started';
  static const String ok = 'ok';
  static const String failed = 'failed';

  final DateTime at;
  final String task;
  final String outcome;
  final int runs;
  final String? detail;

  bool get finished => outcome != started;

  static BackgroundRunLog? read(LocalStore store) {
    final String? raw = store.readCachedString(CacheKeys.lastBackgroundRun);
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return BackgroundRunLog(
        at: DateTime.parse(decoded['at'] as String),
        task: decoded['task'] as String? ?? 'unknown',
        outcome: decoded['outcome'] as String? ?? started,
        runs: decoded['runs'] as int? ?? 0,
        detail: decoded['detail'] as String?,
      );
    } on Object catch (e) {
      Log.e('Worker', 'Could not read the run log', e);
      return null;
    }
  }

  /// Overwrites the record. Never throws: a diagnostic that can break the thing
  /// it reports on is worse than no diagnostic.
  static Future<void> write(
    LocalStore store, {
    required String task,
    required String outcome,
    required int runs,
    String? detail,
  }) async {
    try {
      await store.writeCachedString(
        CacheKeys.lastBackgroundRun,
        jsonEncode(<String, dynamic>{
          'at': DateTime.now().toIso8601String(),
          'task': task,
          'outcome': outcome,
          'runs': runs,
          'detail': ?detail,
        }),
      );
    } on Object catch (e) {
      Log.e('Worker', 'Could not write the run log', e);
    }
  }

  /// The count carried forward, so a run that fails still increments it.
  static int nextRunCount(LocalStore store) => (read(store)?.runs ?? 0) + 1;
}
