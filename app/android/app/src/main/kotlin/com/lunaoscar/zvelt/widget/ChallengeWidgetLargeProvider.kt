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

class ChallengeWidgetLargeProvider : HomeWidgetProvider() {

    private data class Entry(val name: String, val kcal: Int, val isMe: Boolean)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val name       = widgetData.getString("pack_challenge_name",  "") ?: ""
        val daysLeft   = widgetData.getString("pack_days_left_label", "") ?: ""
        val cta        = widgetData.getString("pack_cta",             "") ?: ""
        val lbRaw      = widgetData.getString("pack_leaderboard",     "") ?: ""

        val entries = parseLeaderboard(lbRaw)

        val views = RemoteViews(context.packageName, R.layout.challenge_widget_large)

        views.setTextViewText(
            R.id.challenge_name,
            name.ifBlank { context.getString(R.string.widget_challenge_title) },
        )
        views.setTextViewText(R.id.challenge_days_left, daysLeft)
        views.setTextViewText(
            R.id.challenge_cta_text,
            cta.ifBlank { context.getString(R.string.widget_challenge_cta_default) },
        )

        if (entries.isNotEmpty()) {
            views.setImageViewBitmap(
                R.id.challenge_leaderboard,
                createLeaderboardBitmap(entries),
            )
        }

        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
        views.setOnClickPendingIntent(R.id.challenge_large_root, pi)
        views.setOnClickPendingIntent(R.id.challenge_cta_row,    pi)

        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }

    // ── Leaderboard bitmap ───────────────────────────────────────────────────
    // Draws one row per entry: rank | avatar-circle | name | kcal | bar below

    private fun createLeaderboardBitmap(entries: List<Entry>): Bitmap {
        val bmpW    = 720
        val rowH    = 90
        val bmpH    = entries.size * rowH
        val bmp     = Bitmap.createBitmap(bmpW, bmpH, Bitmap.Config.ARGB_8888)
        val canvas  = Canvas(bmp)

        val fmt     = NumberFormat.getNumberInstance(Locale.US)
        val maxKcal = entries.maxOf { it.kcal }.coerceAtLeast(1)

        val purple    = Color.parseColor("#7B52FF")
        val meBg      = Color.parseColor("#15102A")
        val barTrack  = Color.parseColor("#1E1E26")
        val textWhite = Color.WHITE
        val textGray  = Color.parseColor("#A9B0C0")

        val rankPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize  = 28f
            textAlign = Paint.Align.CENTER
            typeface  = Typeface.DEFAULT_BOLD
        }
        val namePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize  = 26f
            textAlign = Paint.Align.LEFT
            color     = textWhite
        }
        val kcalPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize  = 26f
            textAlign = Paint.Align.RIGHT
            color     = textWhite
            typeface  = Typeface.DEFAULT_BOLD
        }
        val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        val initPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize  = 22f
            textAlign = Paint.Align.CENTER
            color     = textWhite
            typeface  = Typeface.DEFAULT_BOLD
        }

        val rankX       = 30f
        val avatarX     = 70f
        val avatarR     = 20f
        val nameX       = avatarX + avatarR + 12f
        val kcalX       = bmpW.toFloat() - 8f
        val barStartX   = nameX
        val barEndMaxX  = kcalX - 110f
        val barY        = 0f   // will be relative to row top
        val barH        = 8f

        for ((i, entry) in entries.withIndex()) {
            val rowTop  = i * rowH.toFloat()
            val textY   = rowTop + rowH * 0.44f

            // "Me" row highlight
            if (entry.isMe) {
                barPaint.color = meBg
                canvas.drawRect(0f, rowTop, bmpW.toFloat(), rowTop + rowH, barPaint)
            }

            // Rank number
            rankPaint.color = if (entry.isMe) purple else textGray
            canvas.drawText("${i + 1}", rankX, textY, rankPaint)

            // Avatar circle
            circlePaint.color = if (entry.isMe)
                Color.parseColor("#2A1F5C")
            else
                Color.parseColor("#2C2C38")
            val avatarCy = rowTop + rowH / 2f
            canvas.drawCircle(avatarX, avatarCy, avatarR, circlePaint)
            canvas.drawText(
                entry.name.take(1).uppercase(),
                avatarX, avatarCy + initPaint.textSize * 0.35f,
                initPaint,
            )

            // Name
            namePaint.color = textWhite
            canvas.drawText(entry.name, nameX, textY, namePaint)

            // Kcal (right-aligned)
            kcalPaint.color = textWhite
            canvas.drawText("${fmt.format(entry.kcal)} kcal", kcalX, textY, kcalPaint)

            // Progress bar track
            val barTop = rowTop + rowH * 0.62f
            barPaint.color = barTrack
            canvas.drawRoundRect(
                RectF(barStartX, barTop, barEndMaxX, barTop + barH),
                4f, 4f, barPaint,
            )
            // Progress bar fill
            val fillW = (entry.kcal.toFloat() / maxKcal) * (barEndMaxX - barStartX)
            barPaint.color = purple
            canvas.drawRoundRect(
                RectF(barStartX, barTop, barStartX + fillW, barTop + barH),
                4f, 4f, barPaint,
            )
        }

        return bmp
    }

    // Format: "Mihai:1870:0,Alex:1640:0,You:1520:1"
    private fun parseLeaderboard(raw: String): List<Entry> {
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { token ->
            val parts = token.trim().split(":")
            if (parts.size < 2) return@mapNotNull null
            val name  = parts[0].trim()
            val kcal  = parts[1].trim().toIntOrNull() ?: return@mapNotNull null
            val isMe  = parts.getOrNull(2)?.trim() == "1"
            Entry(name, kcal, isMe)
        }
    }
}
