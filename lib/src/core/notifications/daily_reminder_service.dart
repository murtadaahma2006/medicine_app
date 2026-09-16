import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// خدمة التذكيرات اليومية المحلية — أوفلاين 100%.
///
/// الضمانات:
/// - لا ترمي استثناءات أبداً؛ غياب دعم المنصة = صمت لطيف.
/// - تذكير واحد يومي قابل للجدولة/الإلغاء، ويحفظ حالته محلياً
///   عبر shared_preferences (المفتاحان: enabled وhour).
abstract final class DailyReminderService {
  static const String _pluginInstanceId = 'daily-reminder';

  /// معرف الإشعار الثابت — يُستبدل كل يوم بلا تراكم.
  static const int _notificationId = 42;

  static const String _prefEnabled = 'reminder.enabled';
  static const String _prefHour = 'reminder.hour';

  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _initialized = false;

  /// هل التذكير مفعّل؟ (الحالة المحفوظة — لا يحتاج تهيئة الإضافة).
  static Future<bool> isEnabled() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// ساعة التذكير المفضلة (24h). الافتراضي 8:00 مساءً.
  static Future<int> scheduledHour() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_prefHour) ?? 20;
    } catch (_) {
      return 20;
    }
  }

  /// يفعّل/يعطّل التذكير اليومي ويعيد الجدولة عند التفعيل.
  static Future<void> setEnabled({required bool enabled, int hour = 20}) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, enabled);
      await prefs.setInt(_prefHour, hour);
      if (!enabled) {
        await _cancel();
        return;
      }
      await _ensureInitialized();
      await _scheduleDaily(hour);
    } catch (error) {
      debugPrint('DailyReminder: تعذر ضبط التذكير ($error)');
    }
  }

  /// يغيّر ساعة التذكير (يعيد الجدولة فقط إن كان مفعّلاً).
  static Future<void> setHour(int hour) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefHour, hour);
      if (await isEnabled()) {
        await _ensureInitialized();
        await _scheduleDaily(hour);
      }
    } catch (error) {
      debugPrint('DailyReminder: تعذر تغيير الساعة ($error)');
    }
  }

  // ─────────────────────────── الداخلية ───────────────────────────

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
      // Android 13+ (API 33): الإشعارات معطلة افتراضياً — الطلب مرة واحدة.
      await _requestAndroidPermissions(plugin);
    } catch (error) {
      // بيئات الاختبار وسطح المكتب بلا إعدادات منصة → صمت.
      debugPrint('DailyReminder: التهيئة غير متاحة هنا ($error)');
      _initialized = false;
    }
  }

  /// يطلب إذن POST_NOTIFICATIONS على Android 13+ (v19 من الإضافة).
  /// في الإصدارات الأقدم (وiOS بعد التهيئة أعلاه) يعيد true مباشرة.
  static Future<void> _requestAndroidPermissions(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    try {
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (error) {
      // رفض المستخدم أو منصة بلا إشعارات — لا يُسقط التطبيق.
      debugPrint('DailyReminder: إذن الإشعارات غير متاح ($error)');
    }
  }

  static Future<void> _scheduleDaily(int hour) async {
    final FlutterLocalNotificationsPlugin? plugin = _plugin;
    if (plugin == null) return;
    try {
      await plugin.cancel(_notificationId);

      final NotificationDetails details = NotificationDetails(
        android: AndroidNotificationDetails(
          _pluginInstanceId,
          'التذكير اليومي',
          channelDescription: 'تذكير بمواصلة التعلم',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      );

      // مطابق التوقيت القادم قبل الساعة المحددة.
      final DateTime now = DateTime.now();
      DateTime next = DateTime(now.year, now.month, now.day, hour);
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
      final tz.TZDateTime scheduled = tz.TZDateTime.from(next, tz.local);

      await plugin.zonedSchedule(
        _notificationId,
        'مراجعة الطب الباطني 🩺',
        'خمس دقائق تكفي لتقوية سلسلتك وترسيخ بطاقات اليوم.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexact,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (error) {
      debugPrint('DailyReminder: تعذرت الجدولة ($error)');
    }
  }

  static Future<void> _cancel() async {
    try {
      if (_plugin != null) {
        await _plugin!.cancel(_notificationId);
      }
    } catch (_) {
      // الصمت مقصود.
    }
  }

  /// نقطة فحص للتشخيص في نسخ debug فقط.
  static bool get initializedForTesting => kDebugMode && _initialized;
}
