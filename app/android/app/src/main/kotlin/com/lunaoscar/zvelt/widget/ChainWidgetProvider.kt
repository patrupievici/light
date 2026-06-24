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

class ChainWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val streak         = widgetData.getString("today_streak",              "0")?.toIntOrNull() ?: 0
        val weekRaw        = widgetData.getString("week_completion",           "") ?: ""
        val lastWorkout    = widgetData.getString("last_workout_name",         "") ?: ""
        val lastWorkoutTime= widgetData.getString("last_workout_time_label",   "") ?: ""
        val lastDurationMin= widgetData.getString("last_workout_duration_min", "")?.toIntOrNull()
        val todayIdx       = widgetData.getString("today_week_day",            "0")?.toIntOrNull() ?: 0

        val completion = parseWeekCompletion(weekRaw)

        val views = RemoteViews(context.packageName, R.layout.chain_widget_large)

        // Streak label
        views.setTextViewText(
            R.id.chain_streak_label,
            if (streak > 0) "$streak days" else "",
        )

        // 7-circle chain bitmap
        views.setImageViewBitmap(
            R.id.chain_circles_image,
            createChainBitmap(completion, todayIdx),
        )

        // Last workout card
        if (lastWorkout.isBlank()) {
            views.setTextViewText(R.id.chain_last_workout_name, context.getString(R.string.widget_chain_no_workout))
            views.setTextViewText(R.id.chain_last_workout_time, "")
            views.setTextViewText(R.id.chain_last_workout_duration, "")
        } else {
            views.setTextViewText(R.id.chain_last_workout_name, lastWorkout)
            views.setTextViewText(R.id.chain_last_workout_time, lastWorkoutTime)
            views.setTextViewText(
                R.id.chain_last_workout_duration,
                if (lastDurationMin != null) "${lastDurationMin}m" else "",
            )
        }

        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.chain_root, pi)
        views.setOnClickPendingIntent(R.id.chain_cta,  pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }

    // ── Chain circles bitmap ─────────────────────────────────────────────────
    // 7 circles in a row:
    //   done    → orange filled circle + white checkmark
    //   today   → dashed orange ring (not yet done for today)
    //   future  → dark filled circle
    // Width is the full widget width budget; circles are equally spaced.

    private fun createChainBitmap(completion: BooleanArray, todayIdx: Int): Bitmap {
        val w      = 700
        val h      = 112
        val count  = 7
        val radius = 40f
        val cx     = w / count.toFloat()
        val cy     = h / 2f

        val bmp    = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style       = Paint.Style.STROKE
            strokeWidth = 5f
            color       = Color.parseColor("#FF5A1F")
            pathEffect  = DashPathEffect(floatArrayOf(12f, 8f), 0f)
        }
        val checkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style       = Paint.Style.STROKE
            strokeWidth = 5f
            strokeCap   = Paint.Cap.ROUND
            strokeJoin  = Paint.Join.ROUND
            color       = Color.WHITE
        }

        for (i in 0 until count) {
            val centerX = cx * i + cx / 2f
            val done    = completion.getOrElse(i) { false }
            val isToday = (i == todayIdx)

            when {
                done -> {
                    // Filled orange circle
                    fillPaint.color = Color.parseColor("#FF5A1F")
                    canvas.drawCircle(centerX, cy, radius, fillPaint)
                    // White checkmark: M-18,0 L-5.5,13 L18,-13 (relative to center)
                    val path = Path().apply {
                        moveTo(centerX - 15f, cy)
                        lineTo(centerX - 3.5f, cy + 13f)
                        lineTo(centerX + 15f, cy - 14f)
                    }
                    canvas.drawPath(path, checkPaint)
                }
                isToday -> {
                    // Dark bg + dashed orange ring
                    fillPaint.color = Color.parseColor("#1A1A22")
                    canvas.drawCircle(centerX, cy, radius, fillPaint)
                    canvas.drawCircle(centerX, cy, radius - ringPaint.strokeWidth / 2f, ringPaint)
                }
                else -> {
                    // Dark filled circle (future / missed)
                    fillPaint.color = Color.parseColor("#1E1E26")
                    canvas.drawCircle(centerX, cy, radius, fillPaint)
                }
            }
        }

        return bmp
    }

    private fun parseWeekCompletion(raw: String): BooleanArray {
        if (raw.isBlank()) return BooleanArray(7) { false }
        val parts = raw.split(",")
        return BooleanArray(7) { i -> parts.getOrNull(i)?.trim() == "1" }
    }
}
