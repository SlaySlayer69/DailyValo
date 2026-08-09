import 'dart:io';
import 'dart:ui' show Color;

import 'package:dio/dio.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';
import '../../features/content/data/models/content_tier.dart';
import '../../features/store/data/models/shop.dart';

/// Keeps the home screen widget in step with the shop.
///
/// The widget is four skin renders on black, each framed in its rarity colour.
/// No text at all — a home screen is glanced at, and the artwork is what makes
/// a skin recognisable in half a second. Names and prices are one tap away.
///
/// RemoteViews cannot load a URL, so the artwork is downloaded here and the
/// file paths handed to the Android side, which decodes them in this same
/// process and passes bitmaps to the launcher. Values go through the shared
/// preferences `home_widget` manages, so the widget keeps rendering when the
/// app is not running.
abstract final class HomeWidgetService {
  static const String androidWidgetName = 'DailyShopWidget';
  static const String appGroupId = 'com.dailyvalo.app.widget';

  /// Four, matching the shop. More would be unreadable at widget size.
  static const int tileCount = 4;

  // Keys the Kotlin side reads. Kept in one place rather than as loose strings
  // at both ends, since a typo would show an empty widget and no error.
  static String imageKey(int index) => 'dv_image_$index';
  static String colorKey(int index) => 'dv_color_$index';
  static const String keyState = 'dv_state';

  static const String stateReady = 'ready';
  static const String stateEmpty = 'empty';

  /// Fallback frame colour for a skin whose rarity is unknown — the app's own
  /// `borderStrong`, so it reads as deliberate rather than broken.
  static const String _fallbackColor = '#FF39404A';

  static final Dio _http = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      // A widget update is background work behind a shop sync that has already
      // finished; it must not hold anything open for long.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static Future<void> init() async {
    await HomeWidget.setAppGroupId(appGroupId);
  }

  /// Pushes the current offers to the launcher.
  ///
  /// Never throws: a launcher without widget support, a device with none
  /// placed, or a CDN hiccup must not be able to fail a shop sync.
  static Future<void> update(Shop shop) async {
    try {
      final List<ShopOffer> offers = shop.dailyOffers
          .take(tileCount)
          .toList(growable: false);

      if (offers.isEmpty) {
        await clear();
        return;
      }

      final Directory dir = await _imageDirectory();

      for (int i = 0; i < tileCount; i++) {
        if (i >= offers.length) {
          await HomeWidget.saveWidgetData<String>(imageKey(i), '');
          continue;
        }

        final ShopOffer offer = offers[i];
        // Written to a stable per-slot filename rather than one per skin: the
        // directory would otherwise grow by four files every day forever.
        final String? path = await _download(
          offer.skin.displayIcon ?? offer.skin.artwork,
          File('${dir.path}/tile_$i.png'),
        );

        await HomeWidget.saveWidgetData<String>(imageKey(i), path ?? '');
        await HomeWidget.saveWidgetData<String>(
          colorKey(i),
          _argb(offer.tier),
        );
      }

      await HomeWidget.saveWidgetData<String>(keyState, stateReady);
      await HomeWidget.updateWidget(androidName: androidWidgetName);
      Log.d('Widget', 'Home widget updated with ${offers.length} tiles');
    } on Object catch (e) {
      Log.e('Widget', 'Could not update the home widget', e);
    }
  }

  /// Blanks the widget on sign-out, so one account's shop is not left on the
  /// home screen of a signed-out phone.
  static Future<void> clear() async {
    try {
      for (int i = 0; i < tileCount; i++) {
        await HomeWidget.saveWidgetData<String>(imageKey(i), '');
      }
      await HomeWidget.saveWidgetData<String>(keyState, stateEmpty);
      await HomeWidget.updateWidget(androidName: androidWidgetName);
    } on Object catch (e) {
      Log.e('Widget', 'Could not clear the home widget', e);
    }
  }

  /// Opens the app when the widget is tapped.
  static Future<void> registerTapHandler(void Function(Uri?) onLaunch) async {
    try {
      HomeWidget.widgetClicked.listen(onLaunch);
      final Uri? initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null) onLaunch(initial);
    } on Object catch (e) {
      Log.e('Widget', 'Could not register the widget tap handler', e);
    }
  }

  /// `#AARRGGBB`, which is what `Color.parseColor` on the Android side wants.
  static String _argb(ContentTier? tier) {
    final Color? color = tier?.color;
    if (color == null) return _fallbackColor;
    return '#FF${_hex(color.r)}${_hex(color.g)}${_hex(color.b)}';
  }

  static String _hex(double channel) =>
      (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');

  /// Returns the written path, or null when the artwork could not be fetched —
  /// in which case that tile renders empty rather than the whole widget failing.
  static Future<String?> _download(String? url, File target) async {
    if (url == null || url.isEmpty) return null;
    try {
      final Response<List<int>> response = await _http.get<List<int>>(url);
      final List<int>? bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    } on Object catch (e) {
      Log.e('Widget', 'Could not fetch tile artwork', e);
      return null;
    }
  }

  static Future<Directory> _imageDirectory() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory('${base.path}/widget');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
