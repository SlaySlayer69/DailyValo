import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Renders a widget that is not on screen into a PNG.
///
/// A widget only paints if it is in the tree, so this mounts the card in an
/// `Overlay` and shifts it far off to the side. `Offstage` and `Opacity(0)` both
/// skip painting entirely — the capture comes back blank — and translating is
/// the one trick that keeps layout and paint intact while staying invisible.
abstract final class WidgetCapture {
  /// Long enough to cover `RemoteImage`'s 180ms fade-in. Capturing sooner
  /// catches the artwork mid-fade and produces a washed-out card.
  static const Duration _settle = Duration(milliseconds: 320);

  /// Somewhere the card cannot be seen at any screen size.
  static const Offset _offScreen = Offset(-20000, 0);

  /// Paints [build] at [pixelRatio] and returns the PNG bytes.
  ///
  /// [imageUrls] are fetched into the image cache first: a network image that
  /// has not resolved yet paints as its placeholder, and the shared card would
  /// go out with four grey boxes where the skins should be.
  static Future<Uint8List> toPng({
    required BuildContext context,
    required WidgetBuilder build,
    List<String> imageUrls = const <String>[],
    double pixelRatio = 2,
  }) async {
    // Resolved before the first await: after one, `context` may belong to a
    // widget that has been disposed.
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);

    await _warmImages(context, imageUrls);
    final GlobalKey boundaryKey = GlobalKey();
    final Completer<void> painted = Completer<void>();

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext overlayContext) => Transform.translate(
        offset: _offScreen,
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: boundaryKey,
            // The card sets its own width; unbounded height lets it be as tall
            // as its content rather than the screen.
            child: Builder(builder: build),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!painted.isCompleted) painted.complete();
      });
      await painted.future;
      await Future<void>.delayed(_settle);

      final RenderRepaintBoundary? boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('The share card was never laid out.');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) throw StateError('The share card produced no image.');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
  }

  /// Resolves every image up front, ignoring the ones that fail — a single
  /// missing skin render should not stop the whole card.
  static Future<void> _warmImages(
    BuildContext context,
    List<String> urls,
  ) async {
    final Iterable<Future<void>> loads = urls
        .where((String u) => u.isNotEmpty)
        .map(
          (String url) => precacheImage(
            CachedNetworkImageProvider(url),
            context,
            onError: (Object _, StackTrace? _) {},
          ),
        );
    await Future.wait(loads);
  }
}
