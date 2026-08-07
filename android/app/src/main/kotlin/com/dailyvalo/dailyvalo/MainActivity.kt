package com.dailyvalo.dailyvalo

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and exposes the WebView cookie jar to Dart.
 *
 * Why this exists: after the user signs in through Riot's own login page in a
 * WebView, the durable half of that session is the `ssid` cookie. It is
 * `HttpOnly`, so `document.cookie` cannot see it — only the native
 * [CookieManager] can. And the cookie is what lets the *background isolate*
 * mint fresh tokens later without a WebView (which needs an Activity and
 * therefore cannot run from WorkManager).
 *
 * `webview_flutter_android` does expose a `getCookies` helper, but it splits
 * each cookie on every `=` and keeps only the last segment — which silently
 * truncates an opaque token containing `=`. A truncated `ssid` would log the
 * user in once and then quietly break every later refresh, so this returns the
 * raw `Cookie:` header and lets Dart parse it correctly.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.dailyvalo.app/webview_cookies"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Returns the raw "a=1; b=2" header for [url], or null.
                "getCookieHeader" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("bad_args", "A url is required.", null)
                    } else {
                        result.success(runCatching {
                            CookieManager.getInstance().getCookie(url)
                        }.getOrNull())
                    }
                }

                // Persists the in-memory cookie jar to disk. Without this a
                // process death shortly after sign-in loses the session.
                "flush" -> {
                    runCatching { CookieManager.getInstance().flush() }
                    result.success(null)
                }

                // Used on sign-out so the next sign-in really asks for
                // credentials instead of silently reusing the old session.
                "clear" -> {
                    runCatching {
                        CookieManager.getInstance().removeAllCookies(null)
                        CookieManager.getInstance().flush()
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
