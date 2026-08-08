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

  /// The next moment matching the configured time, strictly after [from].
  ///
  /// Strictly, so a sync that happens to run exactly at the chosen minute
  /// schedules for tomorrow rather than for a moment that has already passed —
  /// `zonedSchedule` rejects a date that is not in the future.
  DateTime nextDeliveryAfter(DateTime from) {
    final DateTime today = DateTime(
      from.year,
      from.month,
      from.day,
    ).add(Duration(minutes: minuteOfDay));
    return today.isAfter(from) ? today : today.add(const Duration(days: 1));
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
