import 'dart:io';

import 'package:dailyvalo/src/core/constants/storage_keys.dart';
import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:dailyvalo/src/services/notifications/notification_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  // The real IANA database, so the DST cases below are the actual rules rather
  // than a hand-rolled approximation of them.
  tz_data.initializeTimeZones();
  final tz.Location berlin = tz.getLocation('Europe/Berlin');
  final tz.Location utc = tz.UTC;

  const NotificationSchedule at0900 = NotificationSchedule(
    enabled: true,
    minuteOfDay: 9 * 60,
  );
  const NotificationSchedule at1830 = NotificationSchedule(
    enabled: true,
    minuteOfDay: 18 * 60 + 30,
  );

  group('NotificationSchedule timing', () {
    test('delivers later the same day when the time is still ahead', () {
      expect(
        at1830.nextDeliveryAfter(tz.TZDateTime(berlin, 2026, 8, 8, 2, 5)),
        tz.TZDateTime(berlin, 2026, 8, 8, 18, 30),
      );
    });

    test('rolls to tomorrow once the time has passed', () {
      expect(
        at1830.nextDeliveryAfter(tz.TZDateTime(berlin, 2026, 8, 8, 19)),
        tz.TZDateTime(berlin, 2026, 8, 9, 18, 30),
      );
    });

    test('a sync landing exactly on the minute schedules for tomorrow', () {
      // zonedSchedule rejects a date that is not strictly in the future, so
      // "now" must never be returned.
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 8, 8, 18, 30);
      expect(
        at1830.nextDeliveryAfter(now),
        tz.TZDateTime(berlin, 2026, 8, 9, 18, 30),
      );
      expect(at1830.nextDeliveryAfter(now).isAfter(now), isTrue);
    });

    test('crossing a month boundary rolls the date properly', () {
      expect(
        at1830.nextDeliveryAfter(tz.TZDateTime(berlin, 2026, 8, 31, 20)),
        tz.TZDateTime(berlin, 2026, 9, 1, 18, 30),
      );
    });

    test('crossing a year boundary rolls the date properly', () {
      expect(
        at0900.nextDeliveryAfter(tz.TZDateTime(berlin, 2026, 12, 31, 10)),
        tz.TZDateTime(berlin, 2027, 1, 1, 9),
      );
    });

    test('the result keeps the zone it was given', () {
      final tz.TZDateTime out = at0900.nextDeliveryAfter(
        tz.TZDateTime(berlin, 2026, 8, 8, 2),
      );
      expect(out.location, berlin);
    });
  });

  // The whole reason this works in TZDateTime rather than DateTime: adding a
  // duration to midnight lands an hour out on the days the clocks change.
  group('NotificationSchedule across a clock change', () {
    test('spring forward — 09:00 is still 09:00 on the shortest day', () {
      // Germany, 2026-03-29: 02:00 becomes 03:00. That day is 23 hours long.
      final tz.TZDateTime delivery = at0900.nextDeliveryAfter(
        tz.TZDateTime(berlin, 2026, 3, 29, 2, 0),
      );

      expect(delivery.hour, 9);
      expect(delivery.minute, 0);
      expect(delivery.day, 29);
      // CEST — the offset that is in force after the change, not before it.
      expect(delivery.timeZoneOffset, const Duration(hours: 2));
    });

    test('spring forward — the previous evening still targets 09:00', () {
      final tz.TZDateTime delivery = at0900.nextDeliveryAfter(
        tz.TZDateTime(berlin, 2026, 3, 28, 20),
      );

      expect(delivery.day, 29);
      expect(delivery.hour, 9);
      // 20:00 CET to 09:00 CEST is 12 hours, not 13: the hour is skipped.
      expect(
        delivery.difference(tz.TZDateTime(berlin, 2026, 3, 28, 20)),
        const Duration(hours: 12),
      );
    });

    test('fall back — 09:00 is still 09:00 on the longest day', () {
      // Germany, 2026-10-25: 03:00 becomes 02:00. That day is 25 hours long.
      final tz.TZDateTime delivery = at0900.nextDeliveryAfter(
        tz.TZDateTime(berlin, 2026, 10, 24, 20),
      );

      expect(delivery.day, 25);
      expect(delivery.hour, 9);
      expect(delivery.timeZoneOffset, const Duration(hours: 1));
      // 20:00 CEST to 09:00 CET is 14 hours, not 13.
      expect(
        delivery.difference(tz.TZDateTime(berlin, 2026, 10, 24, 20)),
        const Duration(hours: 14),
      );
    });

    test('a wall-clock time that does not exist still lands in the future', () {
      // 02:30 never happens on 2026-03-29 in Berlin. Whatever the database
      // normalises it to, it must not be in the past — zonedSchedule would
      // reject that outright.
      const NotificationSchedule at0230 = NotificationSchedule(
        enabled: true,
        minuteOfDay: 2 * 60 + 30,
      );
      final tz.TZDateTime from = tz.TZDateTime(berlin, 2026, 3, 29, 1, 0);
      final tz.TZDateTime delivery = at0230.nextDeliveryAfter(from);

      expect(delivery.isAfter(from), isTrue);
    });

    test('an ambiguous wall-clock time resolves to one of the two', () {
      // 02:30 happens twice on 2026-10-25. Either is acceptable; being in the
      // future is not optional.
      const NotificationSchedule at0230 = NotificationSchedule(
        enabled: true,
        minuteOfDay: 2 * 60 + 30,
      );
      final tz.TZDateTime from = tz.TZDateTime(berlin, 2026, 10, 25, 1, 0);
      final tz.TZDateTime delivery = at0230.nextDeliveryAfter(from);

      expect(delivery.isAfter(from), isTrue);
      expect(delivery.hour, 2);
      expect(delivery.minute, 30);
    });

    test('a zone without DST is unaffected', () {
      final tz.TZDateTime delivery = at0900.nextDeliveryAfter(
        tz.TZDateTime(utc, 2026, 3, 29, 2),
      );
      expect(delivery, tz.TZDateTime(utc, 2026, 3, 29, 9));
      expect(delivery.timeZoneOffset, Duration.zero);
    });

    test('every hour of a clock-change day yields a future delivery', () {
      // Sweeps both transitions at every configurable hour, because "always in
      // the future" is the one property zonedSchedule will not tolerate a hole
      // in.
      for (final List<int> day in <List<int>>[
        <int>[2026, 3, 29],
        <int>[2026, 10, 25],
      ]) {
        for (int hour = 0; hour < 24; hour++) {
          for (final int minuteOfDay in <int>[0, 150, 9 * 60, 1439]) {
            final NotificationSchedule s = NotificationSchedule(
              enabled: true,
              minuteOfDay: minuteOfDay,
            );
            final tz.TZDateTime from = tz.TZDateTime(
              berlin,
              day[0],
              day[1],
              day[2],
              hour,
              30,
            );
            expect(
              s.nextDeliveryAfter(from).isAfter(from),
              isTrue,
              reason: 'minute $minuteOfDay from ${day.join('-')} $hour:30',
            );
          }
        }
      }
    });
  });

  // The bug these pin down: the delivery time used to be computed from *now*,
  // so a background check that Android deferred until after the chosen hour
  // scheduled the digest for that hour tomorrow, and the day it was about went
  // by in silence. Anchoring to the rotation is what fixes it.
  group('NotificationSchedule delivery for a rotation', () {
    // 00:00 UTC reset, which is 02:00 in Berlin.
    final tz.TZDateTime rotation = tz.TZDateTime(berlin, 2026, 8, 8, 2);

    test('schedules for the chosen time when it is still ahead', () {
      expect(
        at0900.deliveryFor(
          rotatedAt: rotation,
          now: tz.TZDateTime(berlin, 2026, 8, 8, 2, 3),
        ),
        tz.TZDateTime(berlin, 2026, 8, 8, 9),
      );
    });

    test('says "now" when the chosen time already went by', () {
      // The worker finally ran at 09:20 — exactly the reported case. Waiting
      // until 09:00 tomorrow would skip today's shop entirely.
      expect(
        at0900.deliveryFor(
          rotatedAt: rotation,
          now: tz.TZDateTime(berlin, 2026, 8, 8, 9, 20),
        ),
        isNull,
      );
    });

    test('says "now" on the exact minute rather than scheduling a day out', () {
      // `zonedSchedule` rejects a date that is not strictly in the future, so
      // this instant has to resolve to an immediate post.
      expect(
        at0900.deliveryFor(
          rotatedAt: rotation,
          now: tz.TZDateTime(berlin, 2026, 8, 8, 9),
        ),
        isNull,
      );
    });

    test('a whole day late still delivers, not two days late', () {
      // A phone left off overnight: the rotation is old, the chosen time long
      // gone. It should post now, not queue for tomorrow.
      expect(
        at0900.deliveryFor(
          rotatedAt: rotation,
          now: tz.TZDateTime(berlin, 2026, 8, 9, 14),
        ),
        isNull,
      );
    });

    test('a delivery time before the reset lands the following night', () {
      // 01:00 is earlier in the day than the 02:00 rotation, so the next time
      // the clock reads 01:00 is tomorrow — and the shop is still this one.
      const NotificationSchedule at0100 = NotificationSchedule(
        enabled: true,
        minuteOfDay: 60,
      );
      expect(
        at0100.deliveryFor(
          rotatedAt: rotation,
          now: tz.TZDateTime(berlin, 2026, 8, 8, 2, 3),
        ),
        tz.TZDateTime(berlin, 2026, 8, 9, 1),
      );
    });

    test('is always "now" while the schedule is off', () {
      expect(
        NotificationSchedule.immediate.deliveryFor(
          rotatedAt: rotation,
          now: tz.TZDateTime(berlin, 2026, 8, 8, 2, 3),
        ),
        isNull,
      );
    });

    test('a rotation in the future is clamped to now', () {
      // A nonsense countdown from Riot, or a device clock behind the server's.
      // Without the clamp this would schedule a day and a half out.
      expect(
        at0900.deliveryFor(
          rotatedAt: tz.TZDateTime(berlin, 2026, 8, 9, 2),
          now: tz.TZDateTime(berlin, 2026, 8, 8, 3),
        ),
        tz.TZDateTime(berlin, 2026, 8, 8, 9),
      );
    });

    test('resolves against the real offset on the day the clocks go back', () {
      // 25-hour day. The digest for the 02:00 rotation still lands at 09:00
      // wall clock, not 08:00.
      final tz.TZDateTime at = at0900.deliveryFor(
        rotatedAt: tz.TZDateTime(berlin, 2026, 10, 25, 2),
        now: tz.TZDateTime(berlin, 2026, 10, 25, 2, 5),
      )!;
      expect(at.hour, 9);
      expect(at.day, 25);
    });

    test('works in UTC too, for a device with no zone of its own', () {
      expect(
        at0900.deliveryFor(
          rotatedAt: tz.TZDateTime(utc, 2026, 8, 8),
          now: tz.TZDateTime(utc, 2026, 8, 8, 0, 3),
        ),
        tz.TZDateTime(utc, 2026, 8, 8, 9),
      );
    });
  });

  group('NotificationSchedule formatting', () {
    test('renders a zero-padded 24-hour label', () {
      expect(at0900.label, '09:00');
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
