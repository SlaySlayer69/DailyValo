import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Reads the native WebView cookie jar.
///
/// Needed because the RSO session cookie is `HttpOnly` — invisible to
/// JavaScript — and because the background isolate has to be able to refresh
/// tokens with plain HTTP, long after the WebView is gone.
class WebViewCookieReader {
  const WebViewCookieReader();

  static const MethodChannel _channel = MethodChannel(
    'com.dailyvalo.app/webview_cookies',
  );

  /// Parses the raw `Cookie:` header for [url] into name → value.
  ///
  /// Splits each pair on the **first** `=` only: cookie values are opaque and
  /// routinely contain `=` (base64 padding, JWT-ish blobs), and splitting on
  /// every occurrence silently truncates them.
  static Map<String, String> parseCookieHeader(String? header) {
    if (header == null || header.trim().isEmpty) return <String, String>{};

    final Map<String, String> cookies = <String, String>{};
    for (final String pair in header.split(';')) {
      final String trimmed = pair.trim();
      if (trimmed.isEmpty) continue;

      final int separator = trimmed.indexOf('=');
      // A bare flag with no '=' carries no value we could use.
      if (separator <= 0) continue;

      final String name = trimmed.substring(0, separator).trim();
      final String value = trimmed.substring(separator + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) cookies[name] = value;
    }
    return cookies;
  }

  /// All cookies the WebView holds for [url].
  Future<Map<String, String>> cookiesFor(String url) async {
    if (kIsWeb) return <String, String>{};
    try {
      final String? header = await _channel.invokeMethod<String>(
        'getCookieHeader',
        <String, dynamic>{'url': url},
      );
      return parseCookieHeader(header);
    } on PlatformException catch (e) {
      Log.e('Cookies', 'Could not read the WebView cookie jar', e);
      return <String, String>{};
    } on MissingPluginException catch (e) {
      Log.e('Cookies', 'Cookie channel unavailable on this platform', e);
      return <String, String>{};
    }
  }

  /// Writes the in-memory jar to disk, so a process death right after sign-in
  /// does not lose the session.
  Future<void> flush() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('flush');
    } on Object catch (e) {
      Log.e('Cookies', 'Cookie flush failed', e);
    }
  }

  /// Wipes the jar. Called on sign-out so the next sign-in genuinely prompts
  /// rather than silently resuming the previous account.
  Future<void> clear() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on Object catch (e) {
      Log.e('Cookies', 'Cookie clear failed', e);
    }
  }
}
