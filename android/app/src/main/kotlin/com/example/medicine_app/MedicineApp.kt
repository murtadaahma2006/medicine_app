package com.example.medicine_app

import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * تطبيق الجذر — يسجّل مهمة WorkManager الدورية لتحديث بيانات
 * ويدجت الشاشة الرئيسية كل 6 ساعات (حتى والتطبيق مغلق).
 *
 * ملاحظة: نوسع Application العادي (io.flutter.app.FlutterApplication
 * أزيل من Flutter الحديث — لم يعد موجوداً ولا حاجة له).
 *
 * آلية التنفيذ: MedicineWidgetWorker يرسل بثاً إلى
 * HomeWidgetBackgroundReceiver (من حزمة home_widget) بمفتاح URI —
 * المستقبل يشغّل isolate خلفياً ينفذ رد نداء Dart المسجّل
 * (HomeWidgetService._backgroundCallback) الذي يعيد حساب
 * due_cards/daily_progress/medical_tip ويكتبها ثم يطلب refresh.
 */
class MedicineApp : Application() {

    companion object {
        private const val WIDGET_WORK_NAME = "medicineAppWidgetRefresh"
    }

    override fun onCreate() {
        super.onCreate()

        // قيود خفيفة: بلا شبكة مطلوبة (التطبيق أوفلاين 100%).
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
            .build()

        val request = PeriodicWorkRequestBuilder<MedicineWidgetWorker>(
            6, TimeUnit.HOURS
        )
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            WIDGET_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
    }
}

/**
 * عامل التحديث الخلفي — بث بسيط إلى مستقبل home_widget الخلفي
 * الذي يشغّل رد نداء Dart في isolate منفصل.
 */
class MedicineWidgetWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val intent = Intent().apply {
                setClass(
                    applicationContext,
                    es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java
                )
                data = android.net.Uri.parse("medicineapp://widget-background-refresh")
                action = "es.antonborri.home_widget.action.BACKGROUND"
            }
            applicationContext.sendBroadcast(intent)
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }
}
