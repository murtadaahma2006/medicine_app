import 'package:flutter/services.dart';

/// ─────────────────────────────────────────────────────────────────────
/// خريطة Haptics الموحدة (المرحلة 6 — طبقة التحفيز الحركية).
///
/// خفيف: الأزرار والإجابة الصحيحة (موجود مسبقاً في المكونات).
/// متوسط: الشارات ورفع المستوى — الاحتفالات فقط.
/// selection: قلب البطاقات واختيار الخيارات (لفتة التقاط).
///
/// وجهة واحدة لكل اهتزازات التطبيق — أي haptic جديد يضاف هنا لا يُستدعى
/// HapticFeedback مباشرة من الشاشات.
/// ─────────────────────────────────────────────────────────────────────
abstract final class AppHaptics {
  /// رد فعل خفيف — أزرار عامة (AppButton يستعمله داخلياً) وتصنيفات صغيرة.
  static void light() => HapticFeedback.lightImpact();

  /// احتفال متوسط — شارة جديدة أو رفع مستوى (مرة واحدة عند الحدث).
  static void celebrate() => HapticFeedback.mediumImpact();

  /// لفتة التقاط — قلب بطاقة أو اختيار خيار (selection change).
  static void selection() => HapticFeedback.selectionClick();

  /// خطأ — اهتزاز قوي (FeedbackBanner يستعمله داخلياً).
  static void error() => HapticFeedback.heavyImpact();

  /// النمط الثلاثي الاحتفالي — نقرة-نقرة-صدمة (tick-tick-BOOM).
  /// يُستدعى عند «انكسار» حلقة رفع المستوى: نقرتان صغيرتان أثناء
  /// الامتلاء الدرامي ثم صدمة عند الانفجار الذهبي.
  static Future<void> levelUpTriple() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await HapticFeedback.heavyImpact();
  }
}
