package de.stonerspots.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONException
import org.json.JSONObject
import java.io.File

private fun visibleIf(condition: Boolean) = if (condition) View.VISIBLE else View.GONE

/**
 * Opens [route] in the app. Flutter hands an intent's data to the router as
 * the location, on a cold start as well as to a running app.
 */
private fun openRoute(context: Context, route: String): PendingIntent {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(route), context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    return PendingIntent.getActivity(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/** Shows what the app worked out while it was open (`nearest_spot.dart`). */
class NearestSpotWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) = render(context, manager, id)

    companion object {
        // Outside the backed up files: the name of the nearest spot gives
        // away where the user was, which must not leave the device.
        private fun stateFile(context: Context) = File(context.noBackupFilesDir, "nearest_spot.json")

        fun save(context: Context, json: String) {
            stateFile(context).writeText(json)
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, NearestSpotWidget::class.java))
                .forEach { render(context, manager, it) }
        }

        private fun load(context: Context): JSONObject? = try {
            stateFile(context).takeIf { it.exists() }?.let { JSONObject(it.readText()) }
        } catch (_: JSONException) {
            null
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val height = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            val state = load(context)
            val views = RemoteViews(context.packageName, R.layout.widget_nearest)
            views.setViewVisibility(R.id.widget_header, visibleIf(height >= 70))
            val spot = state?.takeIf { it.optString("state") == "spot" }
            if (spot != null) {
                val tags = spot.optString("tags")
                views.setTextViewText(R.id.widget_name, spot.optString("name"))
                views.setTextViewText(R.id.widget_meta, spot.optString("meta"))
                views.setTextViewText(R.id.widget_tags, tags)
                views.setViewVisibility(R.id.widget_tags, visibleIf(tags.isNotEmpty() && height >= 100))
            } else {
                val message = when (state?.optString("state")) {
                    "no_location" -> R.string.widget_nearest_empty_location
                    "no_spots" -> R.string.widget_nearest_empty_spots
                    else -> R.string.widget_nearest_empty_new
                }
                views.setTextViewText(R.id.widget_meta, context.getString(message))
                views.setViewVisibility(R.id.widget_name, View.GONE)
                views.setViewVisibility(R.id.widget_tags, View.GONE)
            }
            val route = spot?.let { "/spot/${it.optInt("id")}" } ?: "/"
            views.setOnClickPendingIntent(android.R.id.background, openRoute(context, route))
            manager.updateAppWidget(id, views)
        }
    }
}

/** Two shortcuts. `/spot/new` needs a login: the router's redirect sees to it. */
class QuickActionsWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) = render(context, manager, id)

    private fun render(context: Context, manager: AppWidgetManager, id: Int) {
        val width = manager.getAppWidgetOptions(id)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val views = RemoteViews(context.packageName, R.layout.widget_quick_actions)
        // Icons only when the two buttons get too narrow for their labels.
        val labels = visibleIf(width == 0 || width >= 150)
        views.setViewVisibility(R.id.widget_open_map_label, labels)
        views.setViewVisibility(R.id.widget_add_spot_label, labels)
        views.setOnClickPendingIntent(R.id.widget_open_map, openRoute(context, "/"))
        views.setOnClickPendingIntent(R.id.widget_add_spot, openRoute(context, "/spot/new"))
        manager.updateAppWidget(id, views)
    }
}
