import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Tiny logging shim.
///
/// Deliberately a no-op in release builds: the request/response bodies flowing
/// through this app contain access tokens, and log buffers on Android are
/// readable by more things than you would like.
abstract final class Log {
  static void d(String tag, Object? message) {
    if (!kDebugMode) return;
    developer.log('$message', name: 'DailyValo/$tag');
  }

  static void e(String tag, Object? message, [Object? error, StackTrace? st]) {
    if (!kDebugMode) return;
    developer.log(
      '$message',
      name: 'DailyValo/$tag',
      level: 1000,
      error: error,
      stackTrace: st,
    );
  }
}
