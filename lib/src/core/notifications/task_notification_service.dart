import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// خدمة الإشعارات المحلية الخاصة بالمهام (Tasks) العاملة في الخلفية.
abstract final class TaskNotificationService {
  static const String _channelId = 'task-notifications';
  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings darwin = DarwinInitializationSettings(
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

      // Request Android 13 permissions
      await plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('TaskNotificationService: فشل التهيئة ($e)');
    }
  }

  /// إرسال إشعار فوري عند اكتمال مهمة.
  static Future<void> showTaskCompleted(String title, String body) async {
    await _ensureInitialized();
    if (_plugin == null) return;

    try {
      final NotificationDetails details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'مهام الذكاء الاصطناعي',
          channelDescription: 'إشعارات اكتمال معالجة المحاضرات',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      // استخدام timestamp كمعرف فريد للإشعار
      final int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _plugin!.show(id, title, body, details);
    } catch (e) {
      debugPrint('TaskNotificationService: فشل إرسال الإشعار ($e)');
    }
  }
}
