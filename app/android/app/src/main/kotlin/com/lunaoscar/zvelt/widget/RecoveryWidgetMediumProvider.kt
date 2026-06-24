package com.lunaoscar.zvelt.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import com.lunaoscar.zvelt.MainActivity
import com.lunaoscar.zvelt.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class RecoveryWidgetMediumProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val score       = widgetData.getString("recovery_score",             "0")?.toIntOrNull() ?: 0
        val status      = widgetData.getString("recovery_status",            "") ?: ""
        val message     = widgetData.getString("recovery_message",           "") ?: ""
        val cta         = widgetData.getString("recovery_recommendation_cta","") ?: ""
        val aiRec       = widgetData.getString("recovery_ai_rec",            "") ?: ""
        val sleepLabel  = widgetData.getString("recovery_sleep_label",       "—") ?: "—"
        val sleepRating = widgetData.getString("recovery_sleep_rating",      "—") ?: "—"
        val sleepBar    = widgetData.getString("recovery_sleep_bar",         "0")?.toIntOrNull() ?: 0
        val stressVal   = widgetData.getString("recovery_stress_value",      "—") ?: "—"
        val stressRat   = widgetData.getString("recovery_stress_rating",     "—") ?: "—"
        val stressBar   = widgetData.getString("recovery_stress_bar",        "0")?.toIntOrNull() ?: 0
        val hrvLabel    = widgetData.getString("recovery_hrv_label",         "—") ?: "—"
        val hrvRating   = widgetData.getString("recovery_hrv_rating",        "—") ?: "—"
        val hrvBar      = widgetData.getString("recovery_hrv_bar",           "0")?.toIntOrNull() ?: 0

        val views = RemoteViews(context.packageName, R.layout.recovery_widget_medium)

        // Score + status
        views.setTextViewText(R.id.recovery_med_score, "$score%")
        val displayStatus = status.ifBlank { context.getString(R.string.widget_recovery_ready) }
        views.setTextViewText(R.id.recovery_med_status, displayStatus)
        views.setTextColor(R.id.recovery_med_status, scoreColor(score))

        // Message + cta
        views.setTextViewText(R.id.recovery_med_message, message)
        views.setTextViewText(R.id.recovery_med_cta, cta)

        // Sleep
        views.setTextViewText(R.id.recovery_sleep_value, sleepLabel)
        views.setTextViewText(R.id.recovery_sleep_rating, sleepRating)
        views.setTextColor(R.id.recovery_sleep_rating, ratingColor(sleepRating))
        views.setProgressBar(R.id.recovery_sleep_bar, 100, sleepBar.coerceIn(0, 100), false)

        // Stress
        views.setTextViewText(R.id.recovery_stress_value, stressVal)
        views.setTextViewText(R.id.recovery_stress_rating, stressRat)
        views.setTextColor(R.id.recovery_stress_rating, ratingColor(stressRat))
        views.setProgressBar(R.id.recovery_stress_bar, 100, stressBar.coerceIn(0, 100), false)

        // HRV
        views.setTextViewText(R.id.recovery_hrv_value, hrvLabel)
        views.setTextViewText(R.id.recovery_hrv_rating, hrvRating)
        views.setTextColor(R.id.recovery_hrv_rating, ratingColor(hrvRating))
        views.setProgressBar(R.id.recovery_hrv_bar, 100, hrvBar.coerceIn(0, 100), false)

        // AI recommendation
        val displayAiRec = aiRec.ifBlank { context.getString(R.string.widget_recovery_ai_default) }
        views.setTextViewText(R.id.recovery_ai_rec, displayAiRec)

        // Click
        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.recovery_medium_root, pi)
        views.setOnClickPendingIntent(R.id.recovery_ai_row, pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }

    private fun scoreColor(score: Int): Int = when {
        score >= 70 -> Color.parseColor("#2EEA7A")
        score >= 40 -> Color.parseColor("#FFB020")
        else        -> Color.parseColor("#FF4D4D")
    }

    // "Good" / "Low" (stress) → green; "Fair" / "Moderate" → amber; "Poor" / "High" → red
    private fun ratingColor(rating: String): Int = when (rating.lowercase().trim()) {
        "good", "low", "excellent"  -> Color.parseColor("#2EEA7A")
        "fair", "moderate"          -> Color.parseColor("#FFB020")
        "poor", "high"              -> Color.parseColor("#FF4D4D")
        else                        -> Color.parseColor("#A9B0C0")
    }
}
