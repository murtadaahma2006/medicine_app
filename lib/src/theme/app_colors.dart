import 'package:flutter/material.dart';

import 'tokens.dart' as tokens;
export 'tokens.dart' show AppType, AppSpacing, AppRadius, AppMotion, AppShadows;

/// ─────────────────────────────────────────────────────────────────────
/// طبقة توافق مؤقتة — تُبقي الواجهة التاريخية لهذا الملف.
///
/// tokens.dart هو المصدر الوحيد للحقيقة الآن؛ الأسماء هنا مهجورة.
/// ─────────────────────────────────────────────────────────────────────

/// الواجهة القديمة للموقع: كل شيء عبر بادئة tokens (لا تعارض أسماء).
@Deprecated('استورد tokens.dart')
abstract final class AppColors {
  static const Color primary = Color(0xFF1B3B6F);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFD6E4FF);
  static const Color onPrimaryContainer = Color(0xFF0A2A55);

  static const Color secondary = Color(0xFF2E7D32);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFC8EFC5);
  static const Color onSecondaryContainer = Color(0xFF00210A);

  static const Color tertiary = Color(0xFFE8A33D);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFFFE7C2);
  static const Color onTertiaryContainer = Color(0xFF3D2A08);

  static const Color error = Color(0xFFD64545);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFBEAEA);
  static const Color onErrorContainer = Color(0xFF410002);

  static const Color surface = Color(0xFFFDFBF7);
  static const Color onSurface = Color(0xFF1B1B1F);
  static const Color surfaceVariant = Color(0xFFE3E1EC);
  static const Color onSurfaceVariant = Color(0xFF46464F);

  static const Color outline = Color(0xFF77767F);

  /// لون التخصص من رمزه.
  @Deprecated('استخدم tokens.AppColors.module')
  static Color moduleColor(String module) =>
      tokens.AppColors.module(module, Brightness.light);
}

/// ─────────────────────────────────────────────────────────────────────
/// هوية الخطوط: Cairo للعربية — ملفات TTF مدمجة.
/// تستند أحجامها إلى [AppType] من tokens.
/// ─────────────────────────────────────────────────────────────────────
abstract final class AppTypography {
  static const String primaryFamily = tokens.AppType.arabicFamily;
  static const String arabicFamily = tokens.AppType.arabicFamily;
  static const String latinFamily = tokens.AppType.latinFamily;

  static TextTheme buildTextTheme(Brightness brightness) {
    final Color displayColor =
        brightness == Brightness.dark ? Colors.white : const Color(0xFF1B1B1F);
    return TextTheme(
      displayLarge: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: displayColor),
      displayMedium: TextStyle(
          fontFamily: latinFamily,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: displayColor),
      headlineMedium: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: displayColor),
      headlineSmall: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: displayColor),
      titleLarge: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: displayColor),
      titleMedium: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: displayColor),
      bodyLarge: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 16,
          height: 1.5,
          color: displayColor),
      bodyMedium: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 14,
          height: 1.45,
          color: displayColor.withValues(alpha: 0.9)),
      bodySmall: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 12,
          height: 1.4,
          color: displayColor.withValues(alpha: 0.75)),
      labelLarge: TextStyle(
          fontFamily: primaryFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: displayColor),
    );
  }
}
