package com.lunaoscar.zvelt.widget

import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import com.lunaoscar.zvelt.MainActivity
import com.lunaoscar.zvelt.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent

internal object TodayWidgetBinder {

    private fun streakLine(context: Context, widgetData: SharedPreferences): String {
        val streak = widgetData.getString("today_streak", "0")?.toIntOrNull() ?: 0
        return context.getString(R.string.widget_streak_fmt, streak)
    }

    private fun workoutsLine(context: Context, widgetData: SharedPreferences): String {
        val total = widgetData.getString("today_workouts_total", "0")?.toIntOrNull() ?: 0
        return context.getString(R.string.widget_workouts_fmt, total)
    }

    private fun gapLine(context: Context, widgetData: SharedPreferences): CharSequence {
        val raw = widgetData.getString("today_gap_days", "") ?: ""
        return when {
            raw.isEmpty() -> context.getString(R.string.widget_gap_unknown)
            raw == "0" -> context.getString(R.string.widget_gap_today)
            else -> {
                val n = raw.toIntOrNull()
                if (n != null) {
                    context.resources.getQuantityString(R.plurals.widget_gap_days_ago, n, n)
                } else {
                    context.getString(R.string.widget_gap_unknown)
                }
            }
        }
    }

    private fun launchPendingIntent(context: Context) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)

    fun bindSmall(context: Context, widgetData: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.today_widget_small)
        views.setTextViewText(R.id.today_small_streak, streakLine(context, widgetData))
        views.setTextViewText(R.id.today_small_workouts, workoutsLine(context, widgetData))
        val atRisk = widgetData.getBoolean("today_at_risk", false)
        views.setViewVisibility(
            R.id.today_small_at_risk,
            if (atRisk) View.VISIBLE else View.GONE,
        )
        val pi = launchPendingIntent(context)
        views.setOnClickPendingIntent(R.id.today_small_root, pi)
        return views
    }

    fun bindStreak(context: Context, widgetData: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.streak_widget_small)
        val streak = widgetData.getString("today_streak", "0")?.toIntOrNull() ?: 0
        views.setTextViewText(R.id.streak_small_number, streak.toString())
        val atRisk = widgetData.getBoolean("today_at_risk", false)
        views.setViewVisibility(
            R.id.streak_small_at_risk,
            if (atRisk) View.VISIBLE else View.GONE,
        )
        val pi = launchPendingIntent(context)
        views.setOnClickPendingIntent(R.id.streak_small_root, pi)
        return views
    }

    fun bindMedium(context: Context, widgetData: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.today_widget_medium)
        views.setTextViewText(R.id.today_medium_streak, streakLine(context, widgetData))
        views.setTextViewText(R.id.today_medium_workouts, workoutsLine(context, widgetData))
        views.setTextViewText(R.id.today_medium_gap, gapLine(context, widgetData))
        val atRisk = widgetData.getBoolean("today_at_risk", false)
        views.setViewVisibility(
            R.id.today_medium_at_risk,
            if (atRisk) View.VISIBLE else View.GONE,
        )
        val pi = launchPendingIntent(context)
        views.setOnClickPendingIntent(R.id.today_medium_root, pi)
        views.setOnClickPendingIntent(R.id.today_medium_train, pi)
        views.setOnClickPendingIntent(R.id.today_medium_left, pi)
        return views
    }
}
