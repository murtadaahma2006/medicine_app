import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/profile/learner_profile.dart';
import '../routing/app_router.dart';
import '../shared/widgets/celebrations.dart';
import '../theme/app_theme.dart';

/// الجذر الرئيسي للتطبيق.
///
/// التنقل عبر go_router ([MaterialApp.router] + [appRouter]): مسار الجذر
/// `/` هو Splash ثم يوجّه للرئيسية أو الأونبوردنغ حسب أول تشغيل.
///
/// الوضع الداكن: [ThemeMode] يُقرأ من [LearnerProfile] عند الإقلاع ثم
/// يتغير حياً عبر [LearnerTheme.of] — InheritedWidget خفيف تسمع له شاشة
/// الإعدادات فتحدّث الجذر بلا إعادة تشغيل.
///
/// الواجهة عربية بالكامل: locale عربية + RTL عبر
/// [GlobalMaterialLocalizations] (ترجمات Material الرسمية للعربية).
class MedicalLearningApp extends StatefulWidget {
  const MedicalLearningApp({super.key});

  @override
  State<MedicalLearningApp> createState() => _MedicalLearningAppState();
}

class _MedicalLearningAppState extends State<MedicalLearningApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final String saved = await LearnerProfile.themeMode();
    if (!mounted) return;
    setState(() => _themeMode = LearnerProfile.themeModeFrom(saved));
  }

  /// تسمع له شاشة الإعدادات عبر InheritedWidget عند تغيير المظهر.
  void _onThemeChanged() => _loadThemeMode();

  @override
  Widget build(BuildContext context) {
    return LearnerTheme(
      notifier: _onThemeChanged,
      child: MaterialApp.router(
        title: 'منصة الطب الباطني',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar')],
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: appRouter,
        builder: (BuildContext context, Widget? child) {
          final Widget content = child ?? const SizedBox.shrink();
          return Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                builder: (BuildContext ctx) => CelebrationHost(child: content),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// قناة بث تغيّر المظهر: أي شاشة تستدعي [LearnerTheme.of] تسجّل نفسها
/// مستمعاً، و[notifier] يستدعيه الجذر فيعيد قراءة الوضع ويُعيد البناء.
class LearnerTheme extends InheritedWidget {
  const LearnerTheme({
    required this.notifier,
    required super.child,
    super.key,
  });

  /// نداء يخبر الجذر بتغيّر المظهر المحفوظ.
  final VoidCallback notifier;

  /// استدعاء جانبي: تسجيل الاعتماد (إعادة البناء عند التغيير) +
  /// إرجاع القناة.
  static LearnerTheme? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LearnerTheme>();

  @override
  bool updateShouldNotify(LearnerTheme oldWidget) =>
      oldWidget.notifier != notifier;
}
