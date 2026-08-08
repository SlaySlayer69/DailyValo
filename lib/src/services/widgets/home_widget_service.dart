import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/utils/logger.dart';
import '../../features/store/data/models/shop.dart';

/// Keeps the home screen widget in step with the shop.
///
/// The widget shows text, not artwork. Rendering a Flutter widget to a PNG and
/// handing that to the launcher is possible and tempting, but a home screen
/// widget is re-inflated on every wallpaper change, launcher restart and
/// rotation — a stale bitmap survives those, whereas text redraws correctly and
/// costs nothing. Four `Weapon: Skin` lines and a countdown is also what someone
/// glancing at their home screen actually wants; the artwork is one tap away.
///
/// Values are written to shared preferences that the Android widget provider
/// reads directly, so the widget keeps working when the app is not running.
abstract final class HomeWidgetService {
  static const String androidWidgetName = 'DailyShopWidget';
  static const String appGroupId = 'com.dailyvalo.app.widget';

  // Keys the Kotlin side reads. Kept here rather than duplicated at both ends
  // as loose strings, since a typo would show an empty widget with no error.
  static const String keyOffers = 'dv_offers';
  static const String keyResetAt = 'dv_reset_at';
  static const String keyUpdatedAt = 'dv_updated_at';
  static const String keyState = 'dv_state';

  static const String stateReady = 'ready';
  static const String stateSignedOut = 'signed_out';

  static Future<void> init() async {
    await HomeWidget.setAppGroupId(appGroupId);
  }

  /// Pushes the current offers to the launcher.
  ///
  /// Never throws: a launcher that does not support widgets, or a device where
  /// none is placed, must not be able to fail a shop sync.
  static Future<void> update(Shop shop) async {
    try {
      final String offers = shop.dailyOffers
          .map((ShopOffer o) => o.skin.notificationLabel)
          .join('\n');

      await HomeWidget.saveWidgetData<String>(keyOffers, offers);
      await HomeWidget.saveWidgetData<String>(
        keyResetAt,
        shop.dailyResetAt.toIso8601String(),
      );
      await HomeWidget.saveWidgetData<String>(
        keyUpdatedAt,
        DateTime.now().toIso8601String(),
      );
      await HomeWidget.saveWidgetData<String>(keyState, stateReady);

      await HomeWidget.updateWidget(androidName: androidWidgetName);
      Log.d('Widget', 'Home widget updated with ${shop.dailyOffers.length} offers');
    } on Object catch (e) {
      Log.e('Widget', 'Could not update the home widget', e);
    }
  }

  /// Blanks the widget on sign-out, so someone else's shop is not left on the
  /// home screen of a signed-out phone.
  static Future<void> clear() async {
    try {
      await HomeWidget.saveWidgetData<String>(keyOffers, '');
      await HomeWidget.saveWidgetData<String>(keyState, stateSignedOut);
      await HomeWidget.updateWidget(androidName: androidWidgetName);
    } on Object catch (e) {
      Log.e('Widget', 'Could not clear the home widget', e);
    }
  }

  /// Opens the app when the widget is tapped.
  static Future<void> registerTapHandler(
    void Function(Uri?) onLaunch,
  ) async {
    try {
      HomeWidget.widgetClicked.listen(onLaunch);
      final Uri? initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null) onLaunch(initial);
    } on Object catch (e) {
      Log.e('Widget', 'Could not register the widget tap handler', e);
    }
  }
}

/// Ties the widget to the app lifecycle: refresh it when the app is resumed, so
/// opening and closing the app is enough to bring a stale widget up to date.
class HomeWidgetRefresher extends WidgetsBindingObserver {
  HomeWidgetRefresher(this._shopOf);

  final Future<Shop?> Function() _shopOf;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _shopOf().then((Shop? shop) {
      if (shop != null) HomeWidgetService.update(shop);
    });
  }
}
