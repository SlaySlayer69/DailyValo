import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../services/logging/log_file.dart';

/// Severity, in the order it is worth reading.
enum LogLevel {
  trace('T'),
  debug('D'),
  warn('W'),
  error('E');

  const LogLevel(this.mark);

  /// One character, so the level never dominates a line.
  final String mark;
}

/// The app's logging.
///
/// Two destinations with deliberately different rules.
///
/// **The console** takes everything, in debug builds only. That has always been
/// the case here, for a good reason: the payloads flowing through this app
/// carry access tokens, and Android's log buffer is readable by more things
/// than you would like.
///
/// **The file** takes everything too, but only while the user has switched
/// logging on in the developer tools, and only after passing through
/// redaction. It exists because the interesting failures in this app happen in
/// a background isolate, overnight, on somebody else's phone — where no console
/// is attached and no amount of reasoning substitutes for a record of what
/// actually happened.
///
/// Off, this costs one boolean check per call.
abstract final class Log {
  /// Set from the stored setting during bootstrap, in both isolates.
  static bool toFile = false;

  /// `ui` or `bg`. Stamped on every line: the background worker's behaviour is
  /// the reason the file log exists, and a log that does not distinguish the
  /// two would hide exactly what it was built to show.
  static String isolate = 'ui';

  static void t(String tag, Object? message) =>
      _write(LogLevel.trace, tag, message);

  static void d(String tag, Object? message) =>
      _write(LogLevel.debug, tag, message);

  static void w(String tag, Object? message) =>
      _write(LogLevel.warn, tag, message);

  static void e(String tag, Object? message, [Object? error, StackTrace? st]) =>
      _write(LogLevel.error, tag, message, error, st);

  static void _write(
    LogLevel level,
    String tag,
    Object? message, [
    Object? error,
    StackTrace? st,
  ]) {
    if (kDebugMode) {
      developer.log(
        '$message',
        name: 'DailyValo/$tag',
        level: level == LogLevel.error ? 1000 : 500,
        error: error,
        stackTrace: st,
      );
    }

    if (!toFile) return;
    final LogFile? file = LogFile.instance;
    if (file == null) return;

    file.write(_format(level, tag, message, error, st));
  }

  /// `12:04:31.882 D [bg] Worker: Task fired: shopResetCheck`
  ///
  /// Time first because the questions asked of this log are almost always about
  /// order and gaps — when did the worker run, how long was it between the
  /// rotation and the alarm.
  static String _format(
    LogLevel level,
    String tag,
    Object? message,
    Object? error,
    StackTrace? st,
  ) {
    final DateTime now = DateTime.now();
    final StringBuffer line = StringBuffer()
      ..write(_clock(now))
      ..write(' ${level.mark} [$isolate] ')
      ..write('$tag: $message');

    if (error != null) line.write('\n    error: $error');
    // Stack traces only for errors, and only the top of them: the frames that
    // matter are the app's own, and a full trace per error turns the log into
    // something nobody reads.
    if (st != null) {
      final List<String> frames = st.toString().split('\n');
      for (final String frame in frames.take(8)) {
        if (frame.trim().isEmpty) continue;
        line.write('\n    $frame');
      }
    }
    return line.toString();
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}
