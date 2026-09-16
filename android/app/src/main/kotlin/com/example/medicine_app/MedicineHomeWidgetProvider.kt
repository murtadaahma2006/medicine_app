package com.example.medicine_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * ويدجت الشاشة الرئيسية — منصة الطب الباطني (v19).
 *
 * بنية من جزأين:
 * - «أهدافي» 📌: عناوين المحاضرات المثبتة غير المكتملة (سقف 3 أسطر
 *   + «+N أخرى») — سطر أول بارز والباقي ثانوي.
 * - «لؤلؤة اليوم» 💡: معلومة طبية ذهبية عشوائية بخلفية كهرمانية.
 *
 * المصدر: SharedPreferences التي يكتبها Dart عبر home_widget
 * (نفس المفاتيح حرفياً: pinned_titles / pinned_count / clinical_pearl).
 * الضغط على الويدجت يفتح MainActivity بمفتاح medicineapp://daily-review.
 *
 * الوضع الداكن: الألوان معرّفة مرتين (values / values-night).
 */
class MedicineHomeWidgetProvider : HomeWidgetProvider() {

    companion object {
        // نفس مفاتيح HomeWidgetService في Dart — حرفياً.
        private const val KEY_PINNED_TITLES = "pinned_titles"
        private const val KEY_PINNED_TOTAL = "pinned_total"
        private const val KEY_PEARL = "clinical_pearl"

        /** سقف الأسطر المعروضة — نفس HomeWidgetPayload.maxPinnedTitles. */
        private const val MAX_LINES = 3
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        prefs: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            updateOneWidget(context, appWidgetManager, appWidgetId, prefs)
        }
    }

    private fun updateOneWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        prefs: android.content.SharedPreferences
    ) {
        val titles = prefs.getString(KEY_PINNED_TITLES, "")
            ?.split(" | ")
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        // العدد الكلي غير المقطوع (يستقرئه Dart بلا LIMIT) — عدّاد
        // «+N أخرى». السقف أدنى على الأقل لضمان الاتساق بين النص والعدد.
        val totalPinned = maxOf(
            prefs.getString(KEY_PINNED_TOTAL, "0")?.toIntOrNull() ?: 0,
            titles.size
        )
        val pearl = prefs.getString(KEY_PEARL, "") ?: ""

        val views =
            RemoteViews(context.packageName, R.layout.medicine_home_widget)

        // ══ الجزء العلوي: أهدافي ══
        val lineIds = intArrayOf(
            R.id.widget_goal_line_1,
            R.id.widget_goal_line_2,
            R.id.widget_goal_line_3
        )
        if (titles.isEmpty()) {
            // لا مثبتات — دعوة للتثبيت في السطر الأول فقط.
            views.setTextViewText(
                R.id.widget_goal_line_1,
                context.getString(R.string.widget_goals_empty)
            )
            views.setTextViewTextSize(R.id.widget_goal_line_1, 1, 11.5f)
            setViewVisibility(views, lineIds, visibleCount = 1)
        } else {
            // أول سطر بارز (نص أساسي عريض من الـ layout)، والباقي ثانوي.
            for (i in lineIds.indices) {
                if (i < titles.size && i < MAX_LINES) {
                    views.setTextViewText(lineIds[i], titles[i])
                }
            }
            setViewVisibility(
                views, lineIds,
                visibleCount = minOf(titles.size, MAX_LINES)
            )
        }

        // زيادة على السقف: «+N أخرى».
        val extra = totalPinned - MAX_LINES
        if (extra > 0) {
            views.setTextViewText(
                R.id.widget_goal_more,
                context.getString(R.string.widget_goal_more, extra)
            )
            views.setViewVisibility(R.id.widget_goal_more, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_goal_more, View.GONE)
        }

        // ══ الجزء السفلي: لؤلؤة اليوم ══
        views.setTextViewText(
            R.id.widget_pearl_text,
            if (pearl.isBlank())
                context.getString(R.string.widget_pearl_placeholder)
            else pearl
        )

        // ══ الضغط على الويدجت كله → «المراجعة اليومية» ══
        val launchIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("medicineapp://daily-review")
        )
        views.setOnClickPendingIntent(R.id.widget_root, launchIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    /** إظهار أسطر الأهداف الأولى فقط وإخفاء الباقي. */
    private fun setViewVisibility(
        views: RemoteViews,
        lineIds: IntArray,
        visibleCount: Int
    ) {
        for (i in lineIds.indices) {
            views.setViewVisibility(
                lineIds[i],
                if (i < visibleCount) View.VISIBLE else View.GONE
            )
        }
    }
}
