package com.dailyvalo.dailyvalo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * The home screen widget: today's four offers and the time left to buy them.
 *
 * Reads the values Flutter wrote through `home_widget`, so it renders correctly
 * while the app is not running — which is the normal case for a widget.
 *
 * The countdown is recomputed here on every update rather than being written by
 * Flutter as a string. Android re-inflates a widget on wallpaper changes,
 * launcher restarts and rotation, and a baked-in "4h 12m" would survive all of
 * them and quietly lie.
 */
class DailyShopWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.daily_shop_widget).apply {
                val state = widgetData.getString(KEY_STATE, null)
                val offers = widgetData.getString(KEY_OFFERS, null)

                if (state == STATE_SIGNED_OUT || offers.isNullOrBlank()) {
                    setTextViewText(R.id.widget_offers, context.getString(R.string.widget_empty))
                    setTextViewText(R.id.widget_countdown, "")
                } else {
                    setTextViewText(R.id.widget_offers, offers)
                    setTextViewText(
                        R.id.widget_countdown,
                        countdownLabel(context, widgetData.getString(KEY_RESET_AT, null)),
                    )
                }

                // Any tap opens the app on the shop tab.
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun countdownLabel(context: Context, resetAt: String?): String {
        if (resetAt.isNullOrBlank()) return ""

        val remaining = try {
            Duration.between(Instant.now(), Instant.parse(resetAt))
        } catch (e: DateTimeParseException) {
            return ""
        }

        // Past the reset the cached offers are stale by definition. Saying so is
        // more honest than counting down from zero.
        if (remaining.isNegative) return context.getString(R.string.widget_refreshing)

        val hours = remaining.toHours()
        val minutes = remaining.toMinutes() % 60
        return context.getString(R.string.widget_resets_in, hours, minutes)
    }

    companion object {
        private const val KEY_OFFERS = "dv_offers"
        private const val KEY_RESET_AT = "dv_reset_at"
        private const val KEY_STATE = "dv_state"
        private const val STATE_SIGNED_OUT = "signed_out"
    }
}
