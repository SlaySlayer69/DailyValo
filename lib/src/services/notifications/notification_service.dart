import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/utils/logger.dart';

/// The app name, used verbatim as the notification title.
const String kAppName = 'DailyValo';

/// Local notifications, in two deliberately different flavours.
///
/// **Daily shop (silent).** Fires when the four offers rotate. It is
/// informational — you did not ask to be woken at 02:00 for it — so it goes out
/// on a `Importance.low` channel with no sound, no vibration and no heads-up
/// banner. It still lands in the shade, which is the point.
///
/// **Wishlist (alert).** Fires only when something you are actually waiting for
/// shows up. High importance, sound, vibration, heads-up.
///
/// They are separate *channels*, not just separate payloads, because Android
/// lets the user tune each independently — someone can silence the daily digest
/// and keep the wishlist alert, without the app needing a settings screen for
/// it.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;

  // --- Channels --------------------------------------------------------------
  static const String _shopChannelId = 'dv_daily_shop';
  static const String _wishlistChannelId = 'dv_wishlist_alert';

  /// Stable ids so a re-fired notification replaces the previous one rather
  /// than stacking four copies of yesterday's shop in the shade.
  static const int shopNotificationId = 1001;
  static const int wishlistNotificationId = 1002;

  /// The test digest gets its own id so trying it out cannot evict a real
  /// delivery already queued for the morning.
  static const int testNotificationId = 1003;

  static const AndroidNotificationChannel _shopChannel =
      AndroidNotificationChannel(
        _shopChannelId,
        'Daily shop',
        description: 'A silent summary of your four daily offers at reset.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );

  static const AndroidNotificationChannel _wishlistChannel =
      AndroidNotificationChannel(
        _wishlistChannelId,
        'Wishlist alerts',
        description: 'Alerts you when a wishlisted skin appears in your shop.',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

  /// Must be called in every isolate that shows a notification — including the
  /// WorkManager one, which does not share state with `main()`.
  Future<void> init({
    DidReceiveNotificationResponseCallback? onTap,
  }) async {
    if (_initialised) return;

    await _initialiseTimeZone();

    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onTap,
    );

    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(_shopChannel);
      await android.createNotificationChannel(_wishlistChannel);
    }

    _initialised = true;
  }

  /// Loads the timezone database and points `tz.local` at the device's actual
  /// zone.
  ///
  /// Without this, `tz.local` is UTC, and a delivery time would have to be
  /// resolved with plain `DateTime` arithmetic — which gets the day the clocks
  /// change wrong by an hour, and cannot be reasoned about on a device whose
  /// zone the app never learned. Knowing the real zone also means the
  /// notification plugin re-derives the correct instant when it re-arms
  /// scheduled alarms after a reboot.
  ///
  /// Falls back to UTC rather than throwing: a wrong-by-an-offset notification
  /// is worth more than no notification, and the failure is logged.
  Future<void> _initialiseTimeZone() async {
    tz_data.initializeTimeZones();

    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final TimezoneInfo info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      Log.d('Notify', 'Local timezone: ${info.identifier}');
    } on Object catch (e) {
      Log.e('Notify', 'Could not read the device timezone; using UTC', e);
    }
  }

  /// Asks for POST_NOTIFICATIONS (Android 13+). A refusal is not fatal — the
  /// app works, it just cannot tell you about your shop.
  Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final bool? granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// Whether Android will let us aim an alarm at an exact minute.
  ///
  /// Denied by default on Android 14+, which is the difference between a
  /// notification set for 09:00 arriving at 09:00 and arriving whenever the
  /// device next comes out of Doze.
  Future<bool> canScheduleExactly() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      return await android?.canScheduleExactNotifications() ?? false;
    } on Object catch (e) {
      Log.e('Notify', 'Could not read exact-alarm permission', e);
      return false;
    }
  }

  /// Asks for the exact-alarm permission, sending the user to the system screen
  /// that grants it.
  ///
  /// Only worth asking once the user has actually chosen a delivery time — up
  /// to that point the app has no time to be exact about.
  Future<bool> requestExactScheduling() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      return await android?.requestExactAlarmsPermission() ?? false;
    } on Object catch (e) {
      Log.e('Notify', 'Could not request the exact-alarm permission', e);
      return false;
    }
  }

  /// Exact when Android allows it, inexact otherwise — never a failure.
  ///
  /// `exactAllowWhileIdle` throws if the permission is missing, so the check
  /// has to happen per schedule rather than once at start-up: the user can
  /// revoke it from system settings while the app is running.
  Future<AndroidScheduleMode> _scheduleMode() async {
    return await canScheduleExactly()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// The silent daily digest.
  ///
  /// Body format, exactly as specified:
  /// `Weapon: Skin Name - Weapon: Skin Name - Weapon: Skin Name - Weapon: Skin Name`
  ///
  /// [offerLabels] must already be in `Weapon: Skin` form — see
  /// `WeaponSkin.notificationLabel`.
  Future<void> showDailyShop(List<String> offerLabels) async {
    if (offerLabels.isEmpty) return;

    await _plugin.show(
      id: shopNotificationId,
      title: kAppName,
      body: _shopBody(offerLabels),
      notificationDetails: _shopDetails(offerLabels),
      payload: NotificationPayload.dailyShop,
    );
    Log.d('Notify', 'Daily shop notification posted');
  }

  /// The wishlist alert. Intentionally terse — the detail is in the app.
  Future<void> showWishlistHit({List<String> matchedLabels = const <String>[]}) async {
    await _plugin.show(
      id: wishlistNotificationId,
      title: kAppName,
      body: _wishlistBody,
      notificationDetails: _wishlistDetails(matchedLabels),
      payload: NotificationPayload.wishlistHit,
    );
    Log.d('Notify', 'Wishlist alert posted (${matchedLabels.length} matches)');
  }

  // --- Deferred delivery -----------------------------------------------------

  /// Posts the daily digest at [at] instead of now.
  ///
  /// Handing the alarm to Android rather than waking a background worker at the
  /// chosen time is deliberate: the OS delivers it whether or not the app gets
  /// scheduled, and it survives a reboot via the plugin's boot receiver. A
  /// WorkManager task aimed at 18:00 is at Doze's mercy and can slip by hours.
  ///
  /// Exact when the user has granted `SCHEDULE_EXACT_ALARM`, inexact when they
  /// have not. The distinction matters once a delivery time has been chosen:
  /// an inexact alarm is batched into whatever Doze maintenance window comes
  /// next, so "09:00" can land at 09:20 on a phone that slept through the
  /// night — which is exactly the complaint that prompted this. Falling back
  /// rather than demanding the permission keeps a refusal costing punctuality,
  /// not the notification.
  ///
  /// [at] is zone-aware: the plugin keeps the zone alongside the timestamp, so
  /// a reboot re-arms the alarm against the same wall clock rather than the
  /// same offset.
  Future<void> scheduleDailyShop(
    List<String> offerLabels,
    tz.TZDateTime at,
  ) async {
    if (offerLabels.isEmpty) return;

    await _plugin.zonedSchedule(
      id: shopNotificationId,
      title: kAppName,
      body: _shopBody(offerLabels),
      scheduledDate: at,
      notificationDetails: _shopDetails(offerLabels),
      androidScheduleMode: await _scheduleMode(),
      payload: NotificationPayload.dailyShop,
    );
    Log.d('Notify', 'Daily shop notification scheduled for $at');
  }

  Future<void> scheduleWishlistHit({
    required tz.TZDateTime at,
    List<String> matchedLabels = const <String>[],
  }) async {
    await _plugin.zonedSchedule(
      id: wishlistNotificationId,
      title: kAppName,
      body: _wishlistBody,
      scheduledDate: at,
      notificationDetails: _wishlistDetails(matchedLabels),
      androidScheduleMode: await _scheduleMode(),
      payload: NotificationPayload.wishlistHit,
    );
    Log.d('Notify', 'Wishlist alert scheduled for $at');
  }

  /// Queues a real digest a short way out, to prove the delivery path works.
  ///
  /// This exists because the obvious way to test the feature does not work and
  /// looks like a failure when it does not: moving the delivery time ten
  /// minutes ahead schedules nothing, since an alarm is only ever armed when a
  /// **rotation is detected**, and the shop rotates once a day. Someone
  /// checking that way waits ten minutes, gets nothing, and concludes the thing
  /// is still broken.
  ///
  /// Deliberately the same `zonedSchedule` call, the same channel and the same
  /// exact-or-inexact decision as the real digest, so a success here means
  /// permission, channel, timezone, alarm mode and Doze all work. The one thing
  /// it cannot cover is rotation detection.
  Future<void> scheduleTest({
    required tz.TZDateTime at,
    required List<String> offerLabels,
  }) async {
    final List<String> labels = offerLabels.isEmpty
        ? const <String>['Vandal: Prime Vandal', 'Sheriff: Reaver Sheriff']
        : offerLabels;

    await _plugin.zonedSchedule(
      id: testNotificationId,
      title: kAppName,
      body: _shopBody(labels),
      scheduledDate: at,
      notificationDetails: _shopDetails(labels),
      androidScheduleMode: await _scheduleMode(),
      payload: NotificationPayload.dailyShop,
    );
    Log.d('Notify', 'Test notification scheduled for $at');
  }

  /// Drops any pending scheduled delivery.
  ///
  /// Called before scheduling a new one, so a second rotation detected before
  /// the first was delivered replaces it rather than queueing two digests.
  Future<void> cancelScheduled() async {
    await _plugin.cancel(id: shopNotificationId);
    await _plugin.cancel(id: wishlistNotificationId);
  }

  /// Clears notifications that have **already been delivered**, leaving
  /// anything still queued for later alone.
  ///
  /// Called when the app is opened: once you have seen your shop in the app,
  /// the digest about it is spent. Until then it stays in the shade for as long
  /// as it takes — nothing here sets a timeout, and the notifications are not
  /// `ongoing`, so a swipe is the only other thing that removes one.
  ///
  /// The distinction from [cancelScheduled] is the whole point. `cancel(id:)`
  /// removes a posted notification *and* an alarm waiting under the same id,
  /// so clearing the shade indiscriminately on every app open would silently
  /// delete the 09:00 delivery of anyone who opened the app at 08:00. Only ids
  /// Android reports as currently showing are touched.
  Future<void> dismissDelivered() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    try {
      final List<ActiveNotification> active = await android
          .getActiveNotifications();
      for (final ActiveNotification n in active) {
        final int? id = n.id;
        if (id == shopNotificationId ||
            id == wishlistNotificationId ||
            id == testNotificationId) {
          await _plugin.cancel(id: id!);
        }
      }
    } on Object catch (e) {
      // Never fatal: the worst case is a notification the user swipes away.
      Log.e('Notify', 'Could not read the active notifications', e);
    }
  }

  static String _shopBody(List<String> offerLabels) => offerLabels.join(' - ');

  static const String _wishlistBody =
      'An item on your wishlist is in your shop!';

  NotificationDetails _shopDetails(List<String> offerLabels) {
    final String body = _shopBody(offerLabels);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _shopChannelId,
        _shopChannel.name,
        channelDescription: _shopChannel.description,
        importance: Importance.low,
        priority: Priority.low,
        // `silent` suppresses sound *and* the heads-up banner even if the
        // channel was later loosened by the user.
        silent: true,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        category: AndroidNotificationCategory.status,
        // Stated rather than left to the defaults, because "how long does it
        // stay?" is a real question about this notification. No `timeoutAfter`:
        // it never expires on its own. Not `ongoing`: a swipe dismisses it.
        // `autoCancel`: opening it from the shade counts as having read it, and
        // opening the app clears it via `dismissDelivered`.
        autoCancel: true,
        ongoing: false,
        // Four `Weapon: Skin` pairs do not fit on one collapsed line.
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: kAppName,
        ),
      ),
    );
  }

  NotificationDetails _wishlistDetails(List<String> matchedLabels) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _wishlistChannelId,
        _wishlistChannel.name,
        channelDescription: _wishlistChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.recommendation,
        // As above: no expiry, dismissible, cleared once you have been in.
        autoCancel: true,
        ongoing: false,
        // Expanding shows *which* skins matched without opening the app.
        styleInformation: matchedLabels.isEmpty
            ? null
            : BigTextStyleInformation(
                '$_wishlistBody\n\n${matchedLabels.join('\n')}',
                contentTitle: kAppName,
              ),
      ),
    );
  }

  /// How many notifications Android is holding for later.
  ///
  /// The difference between "the alarm was never set" and "the alarm was set
  /// and did not arrive" is otherwise invisible, and they have completely
  /// different causes.
  Future<int> pendingCount() async => (await pendingIds()).length;

  /// The ids Android is holding.
  ///
  /// Ids rather than a bare count, because the count alone is ambiguous in a
  /// way that misleads: a queued *test* and a queued morning digest both read
  /// as "1 waiting", and the plugin does not expose the time an alarm is set
  /// for, so the delivery time cannot be reported back either. Naming which
  /// one it is, is the most that can honestly be said.
  Future<Set<int>> pendingIds() async {
    try {
      final List<PendingNotificationRequest> pending = await _plugin
          .pendingNotificationRequests();
      return pending.map((PendingNotificationRequest r) => r.id).toSet();
    } on Object catch (e) {
      Log.e('Notify', 'Could not read pending notifications', e);
      return const <int>{};
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  /// The notification that launched the app, if any — lets a cold start from a
  /// wishlist alert open straight onto the shop.
  Future<NotificationAppLaunchDetails?> launchDetails() =>
      _plugin.getNotificationAppLaunchDetails();
}

/// Payload strings used to route a notification tap.
abstract final class NotificationPayload {
  static const String dailyShop = 'daily_shop';
  static const String wishlistHit = 'wishlist_hit';
}
