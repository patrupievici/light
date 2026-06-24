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
import java.text.NumberFormat
import java.util.Locale

class XpMediumWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val xpCurrent  = widgetData.getString("today_xp_current", "0")?.toIntOrNull() ?: 0
        val xpGoal     = widgetData.getString("today_xp_goal",    "3000")?.toIntOrNull() ?: 3000
        val xpPercent  = widgetData.getString("today_xp_percent", "0")?.toIntOrNull() ?: 0
        val kcal       = widgetData.getString("today_kcal",        "0")?.toIntOrNull() ?: 0
        val steps      = widgetData.getString("today_steps",       "0")?.toIntOrNull() ?: 0
        val activeMins = widgetData.getString("today_active_min",  "0")?.toIntOrNull() ?: 0
        val weekRaw    = widgetData.getString("week_xp_percents",  "") ?: ""
        val todayIdx   = widgetData.getString("today_week_day",    "0")?.toIntOrNull() ?: 0

        val weekPercents = parseWeekPercents(weekRaw)

        val views = RemoteViews(context.packageName, R.layout.xp_widget_medium)

        // XP amount label: "2,150 / 3,000 XP"
        val fmt = NumberFormat.getNumberInstance(Locale.US)
        views.setTextViewText(
            R.id.xp_medium_amount,
            "${fmt.format(xpCurrent)} / ${fmt.format(xpGoal)} XP",
        )

        // Progress bar
        views.setProgressBar(R.id.xp_medium_progress, 100, xpPercent.coerceIn(0, 100), false)
        views.setTextViewText(R.id.xp_medium_percent, "$xpPercent%")

        // Stats
        views.setTextViewText(R.id.xp_medium_kcal,  fmt.format(kcal))
        views.setTextViewText(R.id.xp_medium_steps, fmt.format(steps))
        views.setTextViewText(R.id.xp_medium_min,   activeMins.toString())

        // Bar chart
        views.setImageViewBitmap(R.id.xp_medium_chart, createBarChartBitmap(weekPercents, todayIdx))

        // Click → open app
        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.xp_medium_root, pi)
        views.setOnClickPendingIntent(R.id.xp_medium_cta,  pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }

    // ── Bar chart bitmap ─────────────────────────────────────────────────────
    // Draws 7 bars (Mon→Sun) with day labels below.
    // Current day is orange (#FF5A1F); others are dark (#1E1E26).
    // Empty/zero bars get a minimum 4 px height so they're still visible.

    private fun createBarChartBitmap(percents: IntArray, todayIdx: Int): Bitmap {
        val w           = 420
        val h           = 80
        val labelH      = 16f
        val chartH      = h - labelH
        val barCount    = 7
        val barW        = 36f
        val totalBarPx  = barW * barCount
        val spacing     = (w - totalBarPx) / (barCount + 1)

        val bmp    = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize  = 13f
            textAlign = Paint.Align.CENTER
        }

        val days = arrayOf("M", "T", "W", "T", "F", "S", "S")

        for (i in 0 until barCount) {
            val x    = spacing + i * (barW + spacing)
            val pct  = percents.getOrElse(i) { 0 }.coerceIn(0, 100) / 100f
            val barH = maxOf(pct * (chartH - 4f), 4f)
            val top  = chartH - barH

            barPaint.color = if (i == todayIdx)
                Color.parseColor("#FF5A1F")
            else
                Color.parseColor("#1E1E26")

            canvas.drawRoundRect(
                RectF(x, top, x + barW, chartH),
                6f, 6f,
                barPaint,
            )

            // Day label
            labelPaint.color = if (i == todayIdx)
                Color.parseColor("#FF5A1F")
            else
                Color.parseColor("#A9B0C0")

            canvas.drawText(days[i], x + barW / 2f, h.toFloat() - 1f, labelPaint)
        }

        return bmp
    }

    private fun parseWeekPercents(raw: String): IntArray {
        if (raw.isBlank()) return IntArray(7) { 0 }
        val parts = raw.split(",")
        return IntArray(7) { i -> parts.getOrNull(i)?.trim()?.toIntOrNull() ?: 0 }
    }
}
