import 'package:flutter/material.dart'
    show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات المتعلم اليومية المحلية — أول تشغيل والهدف اليومي والمظهر.
///
/// مفاتيح SharedPreferences: onboarding.done + daily.goal.cards +
/// theme.mode + placement.level.
/// لا ترمي استثناءات أبداً (نفس فلسفة بقية الخدمات).
abstract final class LearnerProfile {
  static const String _prefOnboarded = 'onboarding.done';
  static const String _prefGoal = 'daily.goal.cards';
  static const String _prefModule = 'placement.module';
  static const String _prefTheme = 'theme.mode';

  // ── القراءة العميقة (محرّك الأسبوع الأول) ──
  static const String _prefAnchorsEnabled = 'reading.anchors.enabled';
  static const String _prefAnchorStrength = 'reading.anchors.strength';

  /// هل أكمل أول تشغيل (اختبار التحديد + الهدف)؟
  static Future<bool> isOnboarded() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefOnboarded) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// وسم إكمال أول تشغيل.
  static Future<void> markOnboarded() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefOnboarded, true);
    } catch (_) {
      // صمت مقصود.
    }
  }

  /// الهدف اليومي بالبطاقات (5/10/15/20 — الافتراضي 10).
  static Future<int> dailyGoal() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_prefGoal) ?? 10;
    } catch (_) {
      return 10;
    }
  }

  /// ضبط الهدف اليومي.
  static Future<void> setDailyGoal(int cards) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefGoal, cards);
    } catch (_) {
      // صمت مقصود.
    }
  }

  /// التخصص المحدد من الأونبوردنغ (null = لم يختر).
  static Future<String?> placementModule() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefModule);
    } catch (_) {
      return null;
    }
  }

  /// حفظ التخصص المفضل.
  static Future<void> setPlacementModule(String module) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefModule, module);
    } catch (_) {
      // صمت مقصود.
    }
  }

  /// وضع المظهر المحفوظ: 'light' | 'dark' | 'system' (الافتراضي system).
  static Future<String> themeMode() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefTheme) ?? 'system';
    } catch (_) {
      return 'system';
    }
  }

  /// ضبط وضع المظهر.
  static Future<void> setThemeMode(String mode) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTheme, mode);
    } catch (_) {
      // صمت مقصود.
    }
  }

  /// تحويل الرمز المخزن إلى [ThemeMode].
  static ThemeMode themeModeFrom(String code) => switch (code) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  // ───────────── القراءة العميقة (مراسي التثبيت) ─────────────

  /// هل مراسي التثبيت مفعّلة؟ (الافتراضي **مفعّل** — القراءة الأولى
  /// هي موطن الاستفادة، والقارئ يعطّلها تلقائياً عند إعادة القراءة).
  static Future<bool> anchorsEnabled() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefAnchorsEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setAnchorsEnabled(bool enabled) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAnchorsEnabled, enabled);
    } catch (_) {
      // صمت مقصود.
    }
  }

  /// قوة المرساة المخزنة (code: '30'/'40'/'60' — الافتراضي '40').
  static Future<String> anchorStrengthCode() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefAnchorStrength) ?? '40';
    } catch (_) {
      return '40';
    }
  }

  static Future<void> setAnchorStrengthCode(String code) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefAnchorStrength, code);
    } catch (_) {
      // صمت مقصود.
    }
  }
}
