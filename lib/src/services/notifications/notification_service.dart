import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

    // Needed before anything can be handed to `zonedSchedule`.
    tz_data.initializeTimeZones();

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
  /// Inexact on purpose. Exact alarms need `SCHEDULE_EXACT_ALARM`, which
  /// Android 14 gates behind a special-access screen and which Play treats as a
  /// restricted permission — a heavy ask for a shop digest that is no less
  /// useful a few minutes late.
  Future<void> scheduleDailyShop(List<String> offerLabels, DateTime at) async {
    if (offerLabels.isEmpty) return;

    await _plugin.zonedSchedule(
      id: shopNotificationId,
      title: kAppName,
      body: _shopBody(offerLabels),
      scheduledDate: _at(at),
      notificationDetails: _shopDetails(offerLabels),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: NotificationPayload.dailyShop,
    );
    Log.d('Notify', 'Daily shop notification scheduled for $at');
  }

  Future<void> scheduleWishlistHit({
    required DateTime at,
    List<String> matchedLabels = const <String>[],
  }) async {
    await _plugin.zonedSchedule(
      id: wishlistNotificationId,
      title: kAppName,
      body: _wishlistBody,
      scheduledDate: _at(at),
      notificationDetails: _wishlistDetails(matchedLabels),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: NotificationPayload.wishlistHit,
    );
    Log.d('Notify', 'Wishlist alert scheduled for $at');
  }

  /// Drops any pending scheduled delivery.
  ///
  /// Called before scheduling a new one, so a second rotation detected before
  /// the first was delivered replaces it rather than queueing two digests.
  Future<void> cancelScheduled() async {
    await _plugin.cancel(id: shopNotificationId);
    await _plugin.cancel(id: wishlistNotificationId);
  }

  /// The instant, expressed in UTC.
  ///
  /// `zonedSchedule` wants a `TZDateTime`, and naming the device's IANA zone
  /// would mean another plugin just to read it. UTC sidesteps that: the alarm
  /// is set from an absolute instant either way, and the local time of day has
  /// already been resolved into one by [NotificationSchedule].
  static tz.TZDateTime _at(DateTime when) =>
      tz.TZDateTime.from(when.toUtc(), tz.UTC);

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
