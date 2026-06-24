package com.lunaoscar.zvelt.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.*
import android.widget.RemoteViews
import com.lunaoscar.zvelt.MainActivity
import com.lunaoscar.zvelt.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class RecoveryWidgetSmallProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val score  = widgetData.getString("recovery_score",  "0")?.toIntOrNull() ?: 0
        val status = widgetData.getString("recovery_status", "") ?: ""

        val views = RemoteViews(context.packageName, R.layout.recovery_widget_small)

        views.setImageViewBitmap(R.id.recovery_ring_image, createRingBitmap(score))
        views.setTextViewText(R.id.recovery_score_text, "$score%")

        val displayStatus = status.ifBlank { context.getString(R.string.widget_recovery_ready) }
        views.setTextViewText(R.id.recovery_status_text, displayStatus)
        views.setTextColor(R.id.recovery_status_text, scoreColor(score))

        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.recovery_small_root, pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }

    private fun createRingBitmap(progressPercent: Int): Bitmap {
        val size        = 256
        val bmp         = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas      = Canvas(bmp)
        val cx          = size / 2f
        val cy          = size / 2f
        val strokeWidth = size * 0.135f
        val radius      = cx - strokeWidth / 2f - 6f
        val oval        = RectF(cx - radius, cy - radius, cx + radius, cy + radius)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style            = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            color            = Color.parseColor("#1C1C22")
            strokeCap        = Paint.Cap.ROUND
        }
        canvas.drawArc(oval, -90f, 360f, false, trackPaint)

        val sweep = 360f * progressPercent.coerceIn(0, 100) / 100f
        if (sweep > 1f) {
            val ringColor = scoreColor(progressPercent)
            val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style            = Paint.Style.STROKE
                this.strokeWidth = strokeWidth
                strokeCap        = Paint.Cap.ROUND
                color            = ringColor
            }
            canvas.drawArc(oval, -90f, sweep, false, arcPaint)
        }

        return bmp
    }

    private fun scoreColor(score: Int): Int = when {
        score >= 70 -> Color.parseColor("#2EEA7A")
        score >= 40 -> Color.parseColor("#FFB020")
        else        -> Color.parseColor("#FF4D4D")
    }
}
