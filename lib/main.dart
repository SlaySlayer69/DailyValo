import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/app.dart';
import 'src/app/dependencies.dart';
import 'src/app/providers.dart';
import 'src/core/utils/logger.dart';
import 'src/services/background/background_scheduler.dart';
import 'src/services/notifications/notification_service.dart';

/// Entry point.
///
/// Order matters here:
///
/// 1. bind Flutter, so plugins can be called;
/// 2. build the object graph (opens Hive, restores the session) — everything
///    else depends on it;
/// 3. register the WorkManager dispatcher, which must happen on every launch
///    because Android needs the callback handle re-published after a reboot;
/// 4. only then run the app, so the first frame already has real state and the
///    UI never renders a signed-out screen to a signed-in user.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF101216),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final AppDependencies deps = await AppDependencies.bootstrap();

  // Awaited, not fired-and-forgotten: some PD endpoints reject a stale
  // X-Riot-ClientVersion, and racing the first authenticated request against
  // this fetch made one endpoint fail while the rest succeeded. The call is
  // internally bounded to 8s and never throws, so start-up cannot hang on it.
  await deps.content.syncClientVersion();

  await BackgroundScheduler.initialise();
  if (deps.canFetchShop) {
    await BackgroundScheduler.registerPeriodicCheck();
  }

  final int initialTab = await _tabFromLaunchNotification(deps.notifications);

  runApp(
    ProviderScope(
      overrides: <Override>[
        appDependenciesProvider.overrideWithValue(deps),
      ],
      child: DailyValoApp(initialTab: initialTab),
    ),
  );
}

/// Opens the Wishlist tab when the app was launched by a wishlist alert, and
/// the shop otherwise.
Future<int> _tabFromLaunchNotification(NotificationService notifications) async {
  try {
    final NotificationAppLaunchDetails? details = await notifications
        .launchDetails();
    if (details?.didNotificationLaunchApp != true) return 0;

    final String? payload = details?.notificationResponse?.payload;
    return payload == NotificationPayload.wishlistHit ? 2 : 0;
  } on Object catch (e) {
    Log.e('Main', 'Could not read launch notification', e);
    return 0;
  }
}

/// Local `unawaited` to avoid importing `dart:async` for a single call.
void unawaited(Future<void> future) {
  future.catchError((Object e, StackTrace st) {
    Log.e('Main', 'Unawaited task failed', e, st);
  });
}
