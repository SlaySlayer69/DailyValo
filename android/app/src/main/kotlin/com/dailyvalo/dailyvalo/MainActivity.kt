package com.dailyvalo.dailyvalo

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
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
        const val POWER_CHANNEL = "com.dailyvalo.app/power"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        configurePowerChannel(flutterEngine)

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

    /**
     * Whether Android is willing to run this app's background work, and a way
     * to change its mind.
     *
     * Battery optimisation is the one thing that can stop the nightly shop
     * check outright, and it does so invisibly: WorkManager accepts the task,
     * reports it as enqueued, and Android simply never starts it. From inside
     * the app that is indistinguishable from a task that ran and found nothing
     * — which is why the answer belongs on the diagnostics screen instead of in
     * a list of things to try.
     *
     * [openSettings] deliberately opens the general list rather than firing
     * `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. That direct request needs a
     * permission Play treats as restricted, and it is not worth holding for a
     * shop tracker when the same screen is two taps away.
     */
    private fun configurePowerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            POWER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    result.success(
                        runCatching {
                            val power =
                                getSystemService(Context.POWER_SERVICE) as PowerManager
                            power.isIgnoringBatteryOptimizations(packageName)
                        }.getOrNull(),
                    )
                }

                "openBatterySettings" -> {
                    val opened = runCatching {
                        startActivity(
                            Intent(
                                Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS,
                            ),
                        )
                        true
                    }.getOrElse {
                        // Some OEM builds ship without that screen; the app's
                        // own settings page always exists and gets there too.
                        runCatching {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null),
                                ),
                            )
                            true
                        }.getOrDefault(false)
                    }
                    result.success(opened)
                }

                else -> result.notImplemented()
            }
        }
    }
}
