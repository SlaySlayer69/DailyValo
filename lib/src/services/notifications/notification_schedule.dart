import 'package:timezone/timezone.dart' as tz;

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_store.dart';

/// When the user wants to hear about their shop.
///
/// Off by default, which keeps the original behaviour: the shop rotates at
/// 00:00 UTC and the notification follows as soon as the app notices. That is
/// the right default — it is the freshest possible answer — but 00:00 UTC is
/// the middle of the night in some of Europe, and a digest that lands at 02:00
/// has been sitting in the shade unread by morning.
///
/// Turned on, the *detection* still happens at reset; only the delivery moves.
/// Nothing about the shop changes between reset and the chosen hour, so a
/// notification held back is still accurate when it arrives.
///
/// The chosen time is a **wall clock** in the device's own timezone, not an
/// offset from UTC. That distinction is the whole reason this works in terms of
/// `TZDateTime` rather than plain `DateTime`: "09:00" has to mean 09:00 on the
/// last Sunday in March too, and simple date arithmetic gets that wrong by an
/// hour because it adds absolute time across a clock change.
class NotificationSchedule {
  const NotificationSchedule({
    required this.enabled,
    required this.minuteOfDay,
  });

  /// 09:00 — chosen rather than 00:00 so that enabling the toggle without
  /// touching the time visibly moves the notification, instead of appearing to
  /// do nothing.
  static const int defaultMinuteOfDay = 9 * 60;

  static const NotificationSchedule immediate = NotificationSchedule(
    enabled: false,
    minuteOfDay: defaultMinuteOfDay,
  );

  final bool enabled;

  /// Minutes since local midnight, 0–1439.
  final int minuteOfDay;

  int get hour => minuteOfDay ~/ 60;
  int get minute => minuteOfDay % 60;

  /// `18:05`, in 24-hour form. Riot's own reset timers are 24-hour, and the
  /// rest of the app already shows times that way.
  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static NotificationSchedule read(LocalStore store) => NotificationSchedule(
    enabled: store.setting<bool>(SettingKeys.notifyAtFixedTime, false),
    minuteOfDay: _clamp(
      store.setting<int>(SettingKeys.notifyTimeOfDay, defaultMinuteOfDay),
    ),
  );

  /// The next moment the clock reads [label] in [from]'s zone, strictly after
  /// [from].
  ///
  /// Built from wall-clock components rather than by adding a duration, so the
  /// timezone database resolves the offset that will actually be in effect on
  /// that date. Adding `Duration(hours: 9)` to midnight yields 10:00 on the day
  /// the clocks go forward.
  ///
  /// Strictly after, so a sync running exactly on the chosen minute schedules
  /// for tomorrow — `zonedSchedule` rejects a date that is not in the future.
  tz.TZDateTime nextDeliveryAfter(tz.TZDateTime from) {
    final tz.Location location = from.location;

    final tz.TZDateTime today = tz.TZDateTime(
      location,
      from.year,
      from.month,
      from.day,
      hour,
      minute,
    );
    if (today.isAfter(from)) return today;

    // Day + 1 rather than `add(Duration(days: 1))`, for the same reason: the
    // next calendar day at this wall-clock time may be 23 or 25 hours away.
    return tz.TZDateTime(
      location,
      from.year,
      from.month,
      from.day + 1,
      hour,
      minute,
    );
  }

  /// When the digest for a shop that rotated at [rotatedAt] should be
  /// delivered, given it is now [now].
  ///
  /// Null means **post it immediately**, for either of two reasons: the
  /// schedule is off, or the chosen time for this rotation has already gone by.
  ///
  /// That second case is not a corner: the shop rotates at 00:00 UTC — 02:00
  /// here — and the check that notices is a background worker Android is free
  /// to defer for hours while the phone is asleep in Doze. Taking the delivery
  /// time from *now* rather than from the rotation meant a worker that finally
  /// ran at 09:30 scheduled the 09:00 digest for 09:00 **tomorrow**, and the
  /// day it was actually about passed in silence. Anchoring to the rotation
  /// keeps "the 09:00 delivery of today's shop" a fixed instant no matter when
  /// we get around to noticing.
  tz.TZDateTime? deliveryFor({
    required tz.TZDateTime rotatedAt,
    required tz.TZDateTime now,
  }) {
    if (!enabled) return null;

    // A rotation cannot be in the future; if the reset time we were handed says
    // otherwise, trust the clock rather than scheduling a day out on bad data.
    final tz.TZDateTime from = rotatedAt.isAfter(now) ? now : rotatedAt;

    final tz.TZDateTime target = nextDeliveryAfter(from);
    // Not `isBefore`: `zonedSchedule` rejects a date that is not strictly in
    // the future, and a target landing on this exact instant is due anyway.
    if (!target.isAfter(now)) return null;
    return target;
  }

  NotificationSchedule copyWith({bool? enabled, int? minuteOfDay}) =>
      NotificationSchedule(
        enabled: enabled ?? this.enabled,
        minuteOfDay: _clamp(minuteOfDay ?? this.minuteOfDay),
      );

  /// Guards against a corrupted or hand-edited preference putting the delivery
  /// time outside a day, which would push every notification a day out.
  static int _clamp(int minutes) {
    if (minutes < 0) return 0;
    if (minutes > 1439) return 1439;
    return minutes;
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationSchedule &&
      other.enabled == enabled &&
      other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => Object.hash(enabled, minuteOfDay);

  @override
  String toString() =>
      enabled ? 'NotificationSchedule($label)' : 'NotificationSchedule(off)';
}
