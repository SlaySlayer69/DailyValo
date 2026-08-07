import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    final String body = offerLabels.join(' - ');

    await _plugin.show(
      id: shopNotificationId,
      title: kAppName,
      body: body,
      notificationDetails: NotificationDetails(
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
      ),
      payload: NotificationPayload.dailyShop,
    );
    Log.d('Notify', 'Daily shop notification posted');
  }

  /// The wishlist alert. Intentionally terse — the detail is in the app.
  Future<void> showWishlistHit({List<String> matchedLabels = const <String>[]}) async {
    const String body = 'An item on your wishlist is in your shop!';

    await _plugin.show(
      id: wishlistNotificationId,
      title: kAppName,
      body: body,
      notificationDetails: NotificationDetails(
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
                  '$body\n\n${matchedLabels.join('\n')}',
                  contentTitle: kAppName,
                ),
        ),
      ),
      payload: NotificationPayload.wishlistHit,
    );
    Log.d('Notify', 'Wishlist alert posted (${matchedLabels.length} matches)');
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
