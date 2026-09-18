import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart' show AppTypography;
import 'tokens.dart';

/// الثيم الموحد للتطبيق (فاتح + داكن) مبني كلياً من [tokens.dart].
///
/// مبدأ الهوية: «حدود لا ظلال» — كل سطح بحد 1px وظل ناعم جداً.
/// ColorScheme يُبنى يدوياً (لا fromSeed) لتطابق قيم الهوية حرفياً
/// في الوضعين وتثبيت ألوان derived (containers) على قيم الأساسي.
///
/// **v20 — الثيم الديناميكي بالتخصص**: [specialty] يبدّل الأساسي
/// (primary/container) بكل لون التخصص — كحلي الباطنية، أخضر
/// الجراحة، أرجواني النسائية. الباقي (أسطح/نصوص/حدود/حالة) ثابت
/// من الـ tokens — التخصص يمس الهوية اللونية فقط لا قابلية
/// القراءة. الافتراضي باطنية = الثيم التاريخي حرفياً.
abstract final class AppTheme {
  /// الثيم التاريخي (باطنية) — توافق رجعي كامل مع كل المستدعين.
  static ThemeData get light => forSpecialty(
        'internal_medicine',
        Brightness.light,
      );

  static ThemeData get dark => forSpecialty(
        'internal_medicine',
        Brightness.dark,
      );

  /// ثيم تخصص سريري — قلب نظام الألوان الديناميكي (v20).
  static ThemeData forSpecialty(
    String specialty,
    Brightness brightness,
  ) =>
      _build(brightness, specialty);

  static ThemeData _build(
    Brightness brightness, [
    String specialty = 'internal_medicine',
  ]) {
    final bool dark = brightness == Brightness.dark;

    // ── الألوان الأساسية من الـtokens ──
    // v20: الأساسي/حاوياته من لوحة التخصص؛ الباقي ثابت هوية.
    final Color primary =
        AppColors.specialtyPrimary(specialty, brightness);
    final Color primaryContainer =
        AppColors.specialtyContainer(specialty, brightness);
    final Color onPrimaryContainer =
        AppColors.specialtyOnContainer(specialty, brightness);
    final Color background = AppColors.background(brightness);
    final Color surface = AppColors.surface(brightness);
    final Color surfaceAlt = AppColors.surfaceAlt(brightness);
    final Color onSurface = AppColors.text(brightness);
    final Color onSurfaceVariant = AppColors.textSecondary(brightness);
    final Color outline = AppColors.border(brightness);
    final Color error = AppColors.error(brightness);

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: AppColors.success(brightness),
      onSecondary: Colors.white,
      secondaryContainer: AppColors.successContainer(brightness),
      onSecondaryContainer: dark ? const Color(0xFFB9E9C8) : const Color(0xFF0B3D20),
      tertiary: AppColors.gold(brightness),
      onTertiary: AppColors.onGold,
      tertiaryContainer: dark ? const Color(0xFF4A3614) : const Color(0xFFFFE7C2),
      onTertiaryContainer: AppColors.onGold,
      error: error,
      onError: Colors.white,
      errorContainer: AppColors.errorContainer(brightness),
      onErrorContainer: dark ? const Color(0xFFF5C6C6) : const Color(0xFF410002),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceAlt,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outline,
      shadow: dark ? const Color(0xFF000000) : const Color(0xFF144070),
      scrim: const Color(0xFF0F1520),
      inverseSurface: dark ? AppColors.textLight : AppColors.textDark,
      onInverseSurface: dark ? AppColors.bgLight : AppColors.bgDark,
      inversePrimary: dark ? AppColors.primaryLight : AppColors.primaryDark,
      surfaceTint: primary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: AppTypography.buildTextTheme(brightness),
      scaffoldBackgroundColor: background,
      fontFamily: AppType.arabicFamily,
      
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.scaled,
          ),
          TargetPlatform.iOS: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.scaled,
          ),
          TargetPlatform.macOS: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.scaled,
          ),
        },
      ),
      
      // إزالة التأثيرات الدائرية (Ripple/Splash) المزعجة خصوصاً من أشرطة التنقل
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: AppType.arabicFamily,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        shape: Border(
          bottom: BorderSide(color: outline, width: 1),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: outline),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryContainer,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.selected)) return Colors.white;
          return onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.selected)) return primary;
          return surfaceAlt;
        }),
        trackOutlineColor:
            WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.selected)) return primary;
          return outline;
        }),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: surfaceAlt,
        thumbColor: primary,
        overlayColor: primaryContainer,
      ),

      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: primary),

      // الدفء المحافظ: خلفية الـNavigationBar (الأسفل) كريمي خفيف
      // منسجم مع السطح البديل الدافئ — دون المساس بالخلفية الأساسية.
      bottomAppBarTheme: BottomAppBarThemeData(
        color: surfaceAlt,
        surfaceTintColor: Colors.transparent,
      ),

      dividerTheme: DividerThemeData(color: outline),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Color(0x8A0F1520),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.text(brightness),
        contentTextStyle: TextStyle(
          fontFamily: AppType.arabicFamily,
          color: AppColors.background(brightness),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
