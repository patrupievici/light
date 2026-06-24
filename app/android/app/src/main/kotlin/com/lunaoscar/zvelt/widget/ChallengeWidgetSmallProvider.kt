package com.lunaoscar.zvelt.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.lunaoscar.zvelt.MainActivity
import com.lunaoscar.zvelt.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ChallengeWidgetSmallProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val name      = widgetData.getString("pack_challenge_name", "") ?: ""
        val myRank    = widgetData.getString("pack_my_rank",        "0")?.toIntOrNull() ?: 0
        val gapLabel  = widgetData.getString("pack_gap_label",      "") ?: ""
        val gapToLabel= widgetData.getString("pack_gap_to_label",   "") ?: ""

        val views = RemoteViews(context.packageName, R.layout.challenge_widget_small)

        views.setTextViewText(
            R.id.challenge_small_rank,
            if (myRank > 0) "#$myRank" else "#–",
        )
        views.setTextViewText(
            R.id.challenge_small_name,
            name.ifBlank { context.getString(R.string.widget_challenge_title) },
        )
        views.setTextViewText(R.id.challenge_small_gap,    gapLabel)
        views.setTextViewText(R.id.challenge_small_gap_to, gapToLabel)

        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.challenge_small_root, pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }
}
