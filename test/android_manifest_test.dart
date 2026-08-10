import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the manifest declarations that scheduled notifications depend on.
///
/// This exists because of a failure with no symptom. `zonedSchedule` hands
/// AlarmManager a PendingIntent aimed at
/// `ScheduledNotificationReceiver`; if that receiver is not declared, the alarm
/// is still registered and still appears in `pendingNotificationRequests` —
/// the app's own diagnostics reported "1 waiting" and every other check green —
/// but when it fires there is nothing to deliver the broadcast to and it is
/// dropped silently. Immediate `show()` calls keep working throughout, so the
/// feature looks healthy right up until someone sets a delivery time.
///
/// flutter_local_notifications stopped declaring these in its own manifest in
/// v16, which means an upgrade can quietly take them away again. Dart tests
/// never build the Android app, so nothing else in this suite would notice.
void main() {
  final File manifest = File('android/app/src/main/AndroidManifest.xml');

  late String xml;

  setUpAll(() {
    expect(
      manifest.existsSync(),
      isTrue,
      reason: 'run tests from the repository root',
    );
    xml = manifest.readAsStringSync();
  });

  group('AndroidManifest — scheduled notifications', () {
    test('declares the receiver that delivers a scheduled notification', () {
      expect(
        xml,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
        ),
        reason: 'without it every scheduled notification is silently dropped',
      );
    });

    test('declares the boot receiver that re-arms alarms', () {
      expect(
        xml,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
        ),
        reason: 'AlarmManager forgets everything across a reboot',
      );
    });

    test('the boot receiver listens for a reboot and an app update', () {
      // MY_PACKAGE_REPLACED matters as much as BOOT_COMPLETED here: installing
      // a new build also clears pending alarms.
      for (final String action in <String>[
        'android.intent.action.BOOT_COMPLETED',
        'android.intent.action.MY_PACKAGE_REPLACED',
      ]) {
        expect(xml, contains(action), reason: '$action is not handled');
      }
    });

    test('holds the permissions the scheduling path needs', () {
      for (final String permission in <String>[
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.RECEIVE_BOOT_COMPLETED',
        'android.permission.SCHEDULE_EXACT_ALARM',
      ]) {
        expect(xml, contains(permission), reason: '$permission is missing');
      }
    });

    test('keeps the plugin classes from being stripped in release', () {
      // R8 cannot see the reflective and Gson-driven uses inside the plugin,
      // and a release build is the only place this would ever show up.
      final File rules = File('android/app/proguard-rules.pro');
      expect(rules.existsSync(), isTrue);
      expect(rules.readAsStringSync(), contains('com.dexterous.**'));
    });
  });
}
