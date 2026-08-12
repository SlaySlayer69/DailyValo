import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Android's battery optimisation, as it applies to this app.
///
/// This is the single thing outside the app that can stop the nightly shop
/// check outright, and it does so silently: WorkManager accepts the task and
/// reports it enqueued, and Android simply never starts it. Every symptom is
/// identical to a check that ran and found nothing new — which is exactly the
/// ambiguity that makes "no notification arrived" so hard to act on.
///
/// Foreground only: reading it goes through the Activity, so the background
/// isolate cannot ask.
class BatteryOptimisation {
  const BatteryOptimisation();

  static const MethodChannel _channel = MethodChannel(
    'com.dailyvalo.app/power',
  );

  /// True when the app is exempt and background work may run freely, false
  /// when it is optimised, and **null when the answer is unknown** — an
  /// unreachable channel must not read as "everything is fine".
  Future<bool?> isExempt() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    } on Object catch (e) {
      Log.e('Power', 'Could not read the battery optimisation state', e);
      return null;
    }
  }

  /// Opens the system screen where the exemption is granted. Returns false if
  /// no such screen could be opened.
  Future<bool> openSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openBatterySettings') ?? false;
    } on Object catch (e) {
      Log.e('Power', 'Could not open the battery settings', e);
      return false;
    }
  }
}
