package com.dailyvalo.dailyvalo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * The home screen widget: four skin renders in a 2x2 grid on black, each framed
 * in the colour of its rarity. No text — a home screen is glanced at, and the
 * artwork is what makes a skin recognisable in half a second.
 *
 * The frame colour is applied by tinting each tile's background and insetting
 * the image by the border width. RemoteViews cannot restyle a drawable at
 * runtime, but it can set a background colour, so a tinted box behind a
 * black-backed image is the way to get a per-tile border out of it.
 *
 * Artwork arrives as file paths written by Flutter. Decoding happens here,
 * inside the app's own process, and the bitmaps go to the launcher through the
 * RemoteViews parcel — a `file://` URI from app-private storage would not be
 * readable by the launcher's process.
 */
class DailyShopWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.daily_shop_widget)

            TILES.forEachIndexed { index, tile ->
                bindTile(views, widgetData, index, tile)
            }

            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindTile(
        views: RemoteViews,
        widgetData: SharedPreferences,
        index: Int,
        tile: Tile,
    ) {
        val path = widgetData.getString("dv_image_$index", null)
        val bitmap = path
            ?.takeIf { it.isNotBlank() && File(it).exists() }
            ?.let { BitmapFactory.decodeFile(it) }

        if (bitmap == null) {
            // INVISIBLE, not GONE: the tiles are weighted, so removing one
            // would resize the other three and break the 2x2 grid. An empty
            // slot holds its place.
            views.setViewVisibility(tile.frameId, View.INVISIBLE)
            return
        }

        views.setViewVisibility(tile.frameId, View.VISIBLE)
        views.setImageViewBitmap(tile.imageId, bitmap)
        views.setInt(
            tile.frameId,
            "setBackgroundColor",
            parseColor(widgetData.getString("dv_color_$index", null)),
        )
    }

    /** Falls back to the app's neutral border rather than dropping the frame. */
    private fun parseColor(value: String?): Int = try {
        if (value.isNullOrBlank()) FALLBACK_COLOR else Color.parseColor(value)
    } catch (e: IllegalArgumentException) {
        FALLBACK_COLOR
    }

    private data class Tile(val frameId: Int, val imageId: Int)

    companion object {
        private val FALLBACK_COLOR = Color.parseColor("#FF39404A")

        private val TILES = listOf(
            Tile(R.id.tile_frame_0, R.id.tile_image_0),
            Tile(R.id.tile_frame_1, R.id.tile_image_1),
            Tile(R.id.tile_frame_2, R.id.tile_image_2),
            Tile(R.id.tile_frame_3, R.id.tile_image_3),
        )
    }
}
