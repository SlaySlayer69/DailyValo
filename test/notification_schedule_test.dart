import 'dart:io';

import 'package:dailyvalo/src/core/constants/storage_keys.dart';
import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:dailyvalo/src/services/notifications/notification_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationSchedule timing', () {
    const NotificationSchedule at1830 = NotificationSchedule(
      enabled: true,
      minuteOfDay: 18 * 60 + 30,
    );

    test('delivers later the same day when the time is still ahead', () {
      expect(
        at1830.nextDeliveryAfter(DateTime(2026, 8, 8, 2, 5)),
        DateTime(2026, 8, 8, 18, 30),
      );
    });

    test('rolls to tomorrow once the time has passed', () {
      expect(
        at1830.nextDeliveryAfter(DateTime(2026, 8, 8, 19)),
        DateTime(2026, 8, 9, 18, 30),
      );
    });

    test('a sync landing exactly on the minute schedules for tomorrow', () {
      // zonedSchedule rejects a date that is not strictly in the future, so
      // "now" must never be returned.
      final DateTime now = DateTime(2026, 8, 8, 18, 30);
      expect(at1830.nextDeliveryAfter(now), DateTime(2026, 8, 9, 18, 30));
      expect(at1830.nextDeliveryAfter(now).isAfter(now), isTrue);
    });

    test('the result is always in the future, whatever the hour', () {
      for (int hour = 0; hour < 24; hour++) {
        for (final int minuteOfDay in <int>[0, 1, 9 * 60, 23 * 60 + 59]) {
          final NotificationSchedule s = NotificationSchedule(
            enabled: true,
            minuteOfDay: minuteOfDay,
          );
          final DateTime now = DateTime(2026, 8, 8, hour, 30);
          expect(
            s.nextDeliveryAfter(now).isAfter(now),
            isTrue,
            reason: 'time $minuteOfDay from hour $hour',
          );
        }
      }
    });

    test('midnight is a real choice, not a fallback to today', () {
      const NotificationSchedule midnight = NotificationSchedule(
        enabled: true,
        minuteOfDay: 0,
      );
      expect(
        midnight.nextDeliveryAfter(DateTime(2026, 8, 8, 0, 30)),
        DateTime(2026, 8, 9),
      );
    });

    test('crossing a month boundary rolls the date properly', () {
      expect(
        at1830.nextDeliveryAfter(DateTime(2026, 8, 31, 20)),
        DateTime(2026, 9, 1, 18, 30),
      );
    });
  });

  group('NotificationSchedule formatting', () {
    test('renders a zero-padded 24-hour label', () {
      expect(
        const NotificationSchedule(enabled: true, minuteOfDay: 9 * 60).label,
        '09:00',
      );
      expect(
        const NotificationSchedule(
          enabled: true,
          minuteOfDay: 18 * 60 + 5,
        ).label,
        '18:05',
      );
      expect(
        const NotificationSchedule(enabled: true, minuteOfDay: 0).label,
        '00:00',
      );
      expect(
        const NotificationSchedule(enabled: true, minuteOfDay: 1439).label,
        '23:59',
      );
    });

    test('splits into hour and minute', () {
      const NotificationSchedule s = NotificationSchedule(
        enabled: true,
        minuteOfDay: 7 * 60 + 45,
      );
      expect(s.hour, 7);
      expect(s.minute, 45);
    });
  });

  group('NotificationSchedule persistence', () {
    late Directory tempDir;
    late LocalStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dailyvalo_notify');
      store = await LocalStore.initAt(tempDir.path);
    });

    tearDown(() async {
      await LocalStore.reset();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('defaults to off, which keeps the pre-2.2 behaviour', () {
      final NotificationSchedule s = NotificationSchedule.read(store);
      expect(s.enabled, isFalse);
      expect(s.minuteOfDay, NotificationSchedule.defaultMinuteOfDay);
    });

    test('reads back what the settings sheet wrote', () async {
      await store.putSetting(SettingKeys.notifyAtFixedTime, true);
      await store.putSetting(SettingKeys.notifyTimeOfDay, 20 * 60 + 15);

      final NotificationSchedule s = NotificationSchedule.read(store);
      expect(s.enabled, isTrue);
      expect(s.label, '20:15');
    });

    test('clamps a stored time that is outside a day', () async {
      // A value like this can only come from a corrupted box or a hand edit,
      // but left alone it would push every notification a day out.
      await store.putSetting(SettingKeys.notifyTimeOfDay, 5000);
      expect(NotificationSchedule.read(store).minuteOfDay, 1439);

      await store.putSetting(SettingKeys.notifyTimeOfDay, -60);
      expect(NotificationSchedule.read(store).minuteOfDay, 0);
    });

    test('copyWith clamps too, so the picker cannot store nonsense', () {
      expect(
        NotificationSchedule.immediate.copyWith(minuteOfDay: 99999).minuteOfDay,
        1439,
      );
    });
  });
}
