import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_redaction.dart';

/// The log on disk.
///
/// One file, appended to from both isolates, capped and rotated so it cannot
/// quietly eat a phone's storage. Every line carries which isolate wrote it —
/// `ui` or `bg` — because the whole reason this exists is that the background
/// worker's behaviour was invisible, and a log that mixes the two without
/// saying which is which would recreate the problem in a new form.
///
/// Writes are buffered and flushed on a short timer rather than written per
/// line: a detailed log is thousands of small appends, and one file open per
/// line would show up as jank. The buffer is flushed explicitly when the
/// background worker finishes, since that isolate is killed the moment it
/// returns and a timer that has not fired yet dies with it.
class LogFile {
  LogFile._(this._file);

  static const String _name = 'dailyvalo.log';
  static const String _previousName = 'dailyvalo.previous.log';

  /// Roughly a few thousand lines. Big enough to hold a night of background
  /// runs, small enough to send in a chat message.
  static const int maxBytes = 512 * 1024;

  static const Duration _flushEvery = Duration(seconds: 2);

  static LogFile? _instance;
  static LogFile? get instance => _instance;

  final File _file;
  final List<String> _buffer = <String>[];
  Timer? _timer;
  bool _flushing = false;

  /// Opens the log. Safe to call twice; the second call is a no-op.
  ///
  /// Returns null when the directory cannot be resolved — on a device where
  /// `path_provider` is unavailable the app must keep working without a log,
  /// not fail to start.
  static Future<LogFile?> open() async {
    final LogFile? existing = _instance;
    if (existing != null) return existing;

    try {
      final Directory support = await getApplicationSupportDirectory();
      final Directory dir = Directory('${support.path}/logs');
      if (!dir.existsSync()) await dir.create(recursive: true);
      return _instance = LogFile._(File('${dir.path}/$_name'));
    } on Object {
      return null;
    }
  }

  File get file => _file;

  /// Queues one already-formatted line. Redaction happens here, at the last
  /// point before the text becomes a file — see [LogRedaction].
  void write(String line) {
    _buffer.add(LogRedaction.apply(line));
    _timer ??= Timer(_flushEvery, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Writes everything queued. Never throws: losing a log line must not take
  /// down whatever was being logged about.
  Future<void> flush() async {
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;
    final String chunk = _buffer.join('\n');
    _buffer.clear();
    try {
      await _file.writeAsString(
        '$chunk\n',
        mode: FileMode.append,
        flush: true,
      );
      await _rotateIfLarge();
    } on Object {
      // Deliberately silent: reporting a logging failure through the logger is
      // how you get an infinite loop.
    } finally {
      _flushing = false;
    }
  }

  /// Keeps one generation. A log that truncates loses the beginning of the
  /// night, which is usually the interesting part; a log that grows forever is
  /// worse.
  Future<void> _rotateIfLarge() async {
    try {
      if (await _file.length() < maxBytes) return;
      final File previous = File('${_file.parent.path}/$_previousName');
      if (previous.existsSync()) await previous.delete();
      await _file.rename(previous.path);
    } on Object {
      // Ignored — see flush().
    }
  }

  /// The whole log, oldest generation first, ready to be shared.
  Future<String> readAll() async {
    await flush();
    final StringBuffer out = StringBuffer();
    final File previous = File('${_file.parent.path}/$_previousName');
    try {
      if (previous.existsSync()) out.writeln(await previous.readAsString());
      if (_file.existsSync()) out.write(await _file.readAsString());
    } on Object {
      return out.toString();
    }
    return out.toString();
  }

  Future<int> sizeInBytes() async {
    int total = 0;
    for (final File f in <File>[
      _file,
      File('${_file.parent.path}/$_previousName'),
    ]) {
      try {
        if (f.existsSync()) total += await f.length();
      } on Object {
        // Ignored.
      }
    }
    return total;
  }

  Future<void> clear() async {
    _buffer.clear();
    for (final File f in <File>[
      _file,
      File('${_file.parent.path}/$_previousName'),
    ]) {
      try {
        if (f.existsSync()) await f.delete();
      } on Object {
        // Ignored.
      }
    }
  }
}
