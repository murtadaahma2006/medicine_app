package com.example.medicine_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * ويدجت الشاشة الرئيسية — منصة الطب الباطني.
 *
 * تعرض:
 * - عدد البطاقات المستحقة اليوم (أحمر عند التراكم ≥ 15).
 * - نسبة الإنجاز اليومي (شريط تقدم + نسبة مئوية).
 * - معلومة طبية سريعة تتبدل يومياً.
 *
 * المصدر: SharedPreferences التي يكتبها Dart عبر home_widget
 * (نفس المفاتيح حرفياً: due_cards / daily_progress / medical_tip).
 * الضغط على الويدجت يفتح MainActivity بمفتاح medicineapp://daily-review
 * — يصل Dart عبر initiallyLaunchedFromHomeWidget/widgetClicked
 * فيوجّه go_router إلى شاشة «المراجعة اليومية».
 *
 * الوضع الداكن: الألوان معرّفة مرتين (values / values-night) —
 * نظام Android يبدّلها تلقائياً بلا كود إضافي.
 */
class MedicineHomeWidgetProvider : HomeWidgetProvider() {

    companion object {
        // نفس مفاتيح HomeWidgetService في Dart — حرفياً.
        private const val KEY_DUE = "due_cards"
        private const val KEY_PROGRESS = "daily_progress"
        private const val KEY_TIP = "medical_tip"

        /** عتبة «التراكم كبير» — نفس قيمة Dart (highDueThreshold). */
        private const val HIGH_DUE_THRESHOLD = 15
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
        val due = prefs.getString(KEY_DUE, "0")?.toIntOrNull() ?: 0
        val progress = prefs.getString(KEY_PROGRESS, "0")?.toIntOrNull() ?: 0
        val tip = prefs.getString(KEY_TIP, "") ?: ""

        val views =
            RemoteViews(context.packageName, R.layout.medicine_home_widget)

        // ── الرقم الكبير: البطاقات المستحقة ──
        views.setTextViewText(R.id.widget_due_count, due.toString())

        // اللون: أحمر عند التراكم، كحلي (أساسي) خلافه.
        val dueColorRes = if (due >= HIGH_DUE_THRESHOLD) {
            R.color.widget_due_high
        } else {
            R.color.widget_due_normal
        }
        views.setTextColor(R.id.widget_due_count, context.getColor(dueColorRes))

        // ── شريط الإنجاز اليومي ──
        views.setProgressBar(
            R.id.widget_progress,
            100,
            progress.coerceIn(0, 100),
            false
        )
        views.setTextViewText(
            R.id.widget_progress_label,
            "إنجاز اليوم: $progress%"
        )

        // ── المعلومة الطبية ──
        views.setTextViewText(
            R.id.widget_tip,
            if (tip.isBlank()) "افتح التطبيق لبدء المراجعة اليومية" else tip
        )

        // ── الضغط على الويدجت كله → «المراجعة اليومية» ──
        val launchIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("medicineapp://daily-review")
        )
        views.setOnClickPendingIntent(R.id.widget_root, launchIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
