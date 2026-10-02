import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// خدمة إدارة منع تعليق الشاشة والجهاز (Wakelock Service).
///
/// تضمن بقاء الجهاز يعمل أثناء معالجة ملفات الـ PDF الثقيلة لمنع تعليق النظام (iOS Suspend)،
/// مع إيقاف التشغيل التلقائي لحفظ طاقة البطارية فور انتهاء أو توقف المهمة.
abstract final class WakelockService {
  /// تفعيل منع النوم أثناء معالجة المهمة
  static Future<void> enable() async {
    try {
      await WakelockPlus.enable();
      debugPrint('WakelockService: Wakelock ENABLED (iOS/Android suspend prevention active)');
    } catch (e) {
      debugPrint('WakelockService: Failed to enable wakelock: $e');
    }
  }

  /// إيقاف منع النوم لحفظ بطارية الجهاز
  static Future<void> disable() async {
    try {
      await WakelockPlus.disable();
      debugPrint('WakelockService: Wakelock DISABLED (Battery preserved)');
    } catch (e) {
      debugPrint('WakelockService: Failed to disable wakelock: $e');
    }
  }
}
