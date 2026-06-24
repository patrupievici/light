package com.lunaoscar.zvelt.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.lunaoscar.zvelt.MainActivity
import com.lunaoscar.zvelt.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class DayStreakWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val streak  = widgetData.getString("today_streak",  "0")?.toIntOrNull() ?: 0
        val atRisk  = widgetData.getBoolean("today_at_risk", false)

        val views = RemoteViews(context.packageName, R.layout.day_streak_widget_small)

        views.setTextViewText(R.id.day_streak_number, streak.toString())
        views.setViewVisibility(
            R.id.day_streak_at_risk,
            if (atRisk) android.view.View.VISIBLE else android.view.View.GONE,
        )

        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.day_streak_root, pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }
}
