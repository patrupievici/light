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

class XpWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val xpPercent = widgetData.getString("today_xp_percent", "0")?.toIntOrNull() ?: 0
        val kcal      = widgetData.getString("today_kcal",       "0")?.toIntOrNull() ?: 0
        val streak    = widgetData.getString("today_streak",     "0")?.toIntOrNull() ?: 0

        val views = RemoteViews(context.packageName, R.layout.xp_widget_small)

        views.setImageViewBitmap(R.id.xp_ring_image, createRingBitmap(xpPercent))
        views.setTextViewText(R.id.xp_percent_text, "$xpPercent%")
        views.setTextViewText(R.id.xp_kcal_value,   kcal.toString())
        views.setTextViewText(R.id.xp_streak_value,  streak.toString())
        views.setTextViewText(
            R.id.xp_footer_text,
            context.getString(R.string.widget_xp_footer, xpPercent),
        )

        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.xp_widget_root, pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }

    // ── Ring bitmap ──────────────────────────────────────────────────────────
    // Draws a circular arc track + an orange→amber progress arc on a transparent
    // 256×256 bitmap. The ImageView in the layout centres/scales it automatically.

    private fun createRingBitmap(progressPercent: Int): Bitmap {
        val size   = 256
        val bmp    = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        val cx          = size / 2f
        val cy          = size / 2f
        val strokeWidth = size * 0.135f
        val radius      = cx - strokeWidth / 2f - 6f
        val oval        = RectF(cx - radius, cy - radius, cx + radius, cy + radius)

        // Background track
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style           = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            color           = Color.parseColor("#1C1C22")
            strokeCap       = Paint.Cap.ROUND
        }
        canvas.drawArc(oval, -90f, 360f, false, trackPaint)

        // Progress arc — orange → amber sweep gradient
        val sweep = 360f * progressPercent.coerceIn(0, 100) / 100f
        if (sweep > 1f) {
            val gradient = SweepGradient(
                cx, cy,
                intArrayOf(
                    Color.parseColor("#FF5A1F"),
                    Color.parseColor("#FFB020"),
                    Color.parseColor("#FF5A1F"),
                ),
                floatArrayOf(0f, 0.5f, 1f),
            )
            // Rotate so the arc starts at 12 o'clock (SweepGradient starts at 3 o'clock)
            val matrix = Matrix()
            matrix.setRotate(-90f, cx, cy)
            gradient.setLocalMatrix(matrix)

            val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style           = Paint.Style.STROKE
                this.strokeWidth = strokeWidth
                strokeCap       = Paint.Cap.ROUND
                shader          = gradient
            }
            canvas.drawArc(oval, -90f, sweep, false, arcPaint)
        }

        return bmp
    }
}
