import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../database/database_helper.dart';

/// خدمة إشعارات انتهاء التثبيت (v18) — أوفلاين 100%.
///
/// العقد:
/// - عند تثبيت محاضرة: إشعار مجدول بعد 48 ساعة بالضبط يحمل رسالة
///   «المحاضرة [اسم] معلقة منذ يومين! سيتم إلغاء تثبيتها الآن من أهدافك».
/// - عند فك التثبيت (يدوياً) أو إكمال المحاضرة قبل مرور الـ 48 ساعة:
///   إلغاء الإشعار المجدول المرتبط بمعرّف المحاضرة.
/// - عند إقلاع التطبيق أو دخول شاشة «اليوم»: `runAppCleanup` ينفّذ
///   `cleanUpStalePins` (المكتملة فوراً + المهملة >48h) ويلغي إشعارات
///   كل ما فُكّ تثبيته.
///
/// الضمانات (مطابقة لـ DailyReminderService):
/// - لا ترمي استثناءات أبداً؛ غياب دعم المنصة = صمت لطيف.
/// - معرّف الإشعار مشتق رقمياً من معرّف المحاضرة (id مستقر لكل
///   محاضرة عبر الجلسات) — لا تراكم ولا تسريب إشعارات.
abstract final class PinExpiryService {
  static const String _pluginInstanceId = 'pin-expiry';

  /// نطاق المعررفات الرقمية المخصصة لهذه الخدمة — عزل تام عن معرّف
  /// التذكير اليومي (42) وأي استخدام آخر للإضافة.
  static const int _idBase = 5000;

  /// طول الجدولة من لحظة التثبيت — نفس عتبة الإهمال في القاعدة.
  static const Duration expiryDelay = DatabaseHelper.stalePinThreshold;

  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _initialized = false;

  /// معرّف الإشعار الرقمي لمحاضرة — stable hash داخل النطاق المخصص.
  static int notificationIdFor(String unitId) =>
      _idBase + (unitId.hashCode & 0x7FFFFFFF) % (1 << 30);

  // ─────────────────── التهيئة (المشتركة مع باقي الإشعارات) ───────────────────

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      final FlutterLocalNotificationsPlugin plugin =
          FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings darwin =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const InitializationSettings settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );
      await plugin.initialize(settings);
      _plugin = plugin;
      _initialized = true;
    } catch (error) {
      // بيئات الاختبار وسطح المكتب بلا إعدادات منصة → صمت.
      debugPrint('PinExpiry: التهيئة غير متاحة هنا ($error)');
      _initialized = false;
    }
  }

  // ─────────────────── الجدولة والإلغاء ───────────────────

  /// يُستدعى لحظة تثبيت محاضرة — يجدول إشعار الإنذار بعد 48 ساعة.
  /// [pinnedAt] لحظة التثبيت (نفس ما كُتب في القاعدة) كي تكون الجدولة
  /// دقيقة بالضبط حتى لو تأخر هذا النداء لحظات.
  static Future<void> scheduleExpiryNotification({
    required String unitId,
    required String lectureTitle,
    required DateTime pinnedAt,
  }) async {
    await _ensureInitialized();
    final FlutterLocalNotificationsPlugin? plugin = _plugin;
    if (plugin == null) return;
    try {
      // إلغاء أي إشعار سابق لنفس المحاضرة أولاً — إعادة التثبيت
      // تستبدل الجدولة القديمة (لا تراكم).
      await plugin.cancel(notificationIdFor(unitId));

      final NotificationDetails details = NotificationDetails(
        android: AndroidNotificationDetails(
          _pluginInstanceId,
          'انتهاء تثبيت المحاضرات',
          channelDescription: 'تنبيه إلغاء تثبيت المحاضرات المعلقة منذ يومين',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      );

      // لحظة الانتهاء: تثبيت + 48 ساعة. إن مضت أصلاً (حالة نظرية)
      // لا نجدول في الماضي — كان القاعدة مسحتها أصلاً.
      final DateTime expiry = pinnedAt.add(expiryDelay);
      if (!expiry.isAfter(DateTime.now())) return;
      final tz.TZDateTime scheduled = tz.TZDateTime.from(expiry, tz.local);

      await plugin.zonedSchedule(
        notificationIdFor(unitId),
        'محاضرة معلقة منذ يومين 📌',
        'المحاضرة «$lectureTitle» معلقة منذ يومين! '
        'سيتم إلغاء تثبيتها الآن من أهدافك.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexact,
      );
    } catch (error) {
      debugPrint('PinExpiry: تعذرت الجدولة ($error)');
    }
  }

  /// إلغاء الإشعار المجدول لمحاضرة — يُستدعى عند فك التثبيت يدوياً
  /// أو عند إكمال المحاضرة قبل انتهاء الـ 48 ساعة.
  static Future<void> cancelExpiryNotification(String unitId) async {
    final FlutterLocalNotificationsPlugin? plugin = _plugin;
    if (plugin == null) return;
    try {
      await plugin.cancel(notificationIdFor(unitId));
    } catch (_) {
      // الصمت مقصود — الإلغاء غير حرج.
    }
  }

  // ─────────────────── التنظيف عند الاستخدام ───────────────────

  /// التنظيف الشامل — يُستدعى عند إقلاع التطبيق (خلف شاشة البداية)
  /// وعند دخول شاشة «اليوم»:
  ///
  /// 1. `cleanUpStalePins` القاعدة: فك المكتملة فوراً + المهملة
  ///    (>48 ساعة) داخل معاملة واحدة.
  /// 2. إلغاء إشعارات كل ما فُكّ (أياً كان سبب الفك).
  ///
  /// غير معلّق (unawaited-safe): يستدعيه المستدعي بلا انتظار.
  static Future<void> runAppCleanup() async {
    try {
      final List<String> unpinned =
          await DatabaseHelper.instance.cleanUpStalePins();
      for (final String unitId in unpinned) {
        unawaited(cancelExpiryNotification(unitId));
      }
    } catch (error) {
      debugPrint('PinExpiry: تعذر التنظيف ($error)');
    }
  }

  /// نقطة فحص للتشخيص في نسخ debug فقط.
  static bool get initializedForTesting => _initialized;
}
