import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/database/database_helper.dart';
import '../core/profile/learner_profile.dart';
import '../routing/app_router.dart';
import '../shared/widgets/celebrations.dart';
import '../theme/app_theme.dart';

/// الجذر الرئيسي للتطبيق.
///
/// التنقل عبر go_router ([MaterialApp.router] + [appRouter]): مسار الجذر
/// `/` هو Splash ثم يوجّه للرئيسية أو الأونبوردنغ حسب أول تشغيل.
///
/// **الوضع الداكن**: [ThemeMode] يُقرأ من [LearnerProfile] عند الإقلاع ثم
/// يتغير حياً عبر [LearnerTheme.of] — InheritedWidget خفيف تسمع له شاشة
/// الإعدادات فتحدّث الجذر بلا إعادة تشغيل.
///
/// **v20 — الثيم الديناميكي بالتخصص**: التخصص النشط يُقرأ من
/// [LearnerProfile] عند الإقلاع ويُبنى الثيم (فاتح/داكن) بلونه —
/// كحلي الباطنية · أخضر الجراحة · أرجواني النسائية. تغيير التخصص
/// من شريط المسار/المكتبة يصل الجذر عبر MainScreen فيُعاد بناء
/// الثيم فوراً في كل التطبيق. الأسطح والنصوص والحدود ثابتة —
/// التخصص يمس الأساسي وحاوياته فقط.
///
/// الواجهة عربية بالكامل: locale عربية + RTL عبر
/// [GlobalMaterialLocalizations] (ترجمات Material الرسمية للعربية).
class MedicalLearningApp extends StatefulWidget {
  const MedicalLearningApp({super.key});

  @override
  State<MedicalLearningApp> createState() => _MedicalLearningAppState();
}

class _MedicalLearningAppState extends State<MedicalLearningApp>
    with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;

  /// التخصص السريري النشط — أساس الثيم الديناميكي (v20).
  String _specialty = 'internal_medicine';

  // ── زمن الاستخدام اليومي (v21) ──
  // نتتبع إجمالي الوقت الذي يمكث فيه التطبيق في المقدمة عبر دورة
  // الحياة، فنجمّعه (بالملي-ثانية) في [study_seconds] داخل daily_stats
  // عند نهاية كل فترة مقدمة. لا نكتب كل ثانية — نجمّع ثم نكتب دفعة
  // واحدة عند خروج التطبيق إلى الخلفية (paused) أو عند إطاره.
  DateTime _foregroundSince = DateTime.now();
  int _pendingStudyMs = 0;

  /// يكتب الزمن المتراكم في daily_stats ويصفّر العدّاد.
  /// يتجاهل الشظايا القصيرة (< 500ms) — منع ضجيج التوقيت.
  void _flushStudyTime() {
    final int ms = _pendingStudyMs;
    _pendingStudyMs = 0;
    if (ms < 500) return;
    DatabaseHelper.instance.recordStudySeconds((ms / 1000).floor());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
  }

  @override
  void dispose() {
    _flushStudyTime();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // أي انتقال خارج «المقدمة» (inactive/paused/hidden/detached) يُنهي
    // فترة المقدمة التي بدأت عند آخر resumed: نجمع ما انقضى ونصفّر
    // المؤقّت حتى لا يُحسب زمن الخلفية أبداً.
    if (state == AppLifecycleState.resumed) {
      _foregroundSince = DateTime.now();
      return;
    }
    _pendingStudyMs +=
        DateTime.now().difference(_foregroundSince).inMilliseconds;
    _foregroundSince = DateTime.now();
    // عند الإيقاف الكامل (خلفية) نكتب الآن — العملية قد تُقتل بعدها.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _flushStudyTime();
    }
  }

  Future<void> _loadPrefs() async {
    final String savedTheme = await LearnerProfile.themeMode();
    final String savedSpecialty = await LearnerProfile.activeSpecialty();
    if (!mounted) return;
    setState(() {
      _themeMode = LearnerProfile.themeModeFrom(savedTheme);
      _specialty = savedSpecialty;
    });
  }

  /// تسمع له شاشة الإعدادات عبر InheritedWidget عند تغيير المظهر.
  void _onThemeChanged() => _loadPrefs();

  /// تغيير التخصص النشط (من شريط المسار/المكتبة عبر MainScreen):
  /// حفظ دائم + إعادة بناء الثيم بلون التخصص الجديد فوراً.
  Future<void> onSpecialtyChanged(String specialty) async {
    if (specialty == _specialty) return;
    await LearnerProfile.setActiveSpecialty(specialty);
    if (!mounted) return;
    setState(() => _specialty = specialty);
  }

  @override
  Widget build(BuildContext context) {
    return LearnerTheme(
      notifier: _onThemeChanged,
      specialty: _specialty,
      onSpecialtyChanged: onSpecialtyChanged,
      child: MaterialApp.router(
        // ── الإعدادات الأساسية ──
        title: 'MedOS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.forSpecialty(_specialty, Brightness.light),
        darkTheme: AppTheme.forSpecialty(_specialty, Brightness.dark),
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

/// قناة بث تغيّر المظهر/التخصص: أي شاشة تستدعي [LearnerTheme.of] تسجّل
/// نفسها مستمعاً، و[notifier] يستدعيه الجذر فيعيد قراءة الوضع ويُعيد
/// البناء.
class LearnerTheme extends InheritedWidget {
  const LearnerTheme({
    required this.notifier,
    required this.specialty,
    required this.onSpecialtyChanged,
    required super.child,
    super.key,
  });

  /// نداء يخبر الجذر بتغيير المظهر المحفوظ.
  final VoidCallback notifier;

  /// التخصص النشط الحالي — للقراءة من أي مكان تحت الجذر (نفس مفتاح
  /// حفظ SpecialtyScope — وحدة حقيقة واحدة).
  final String specialty;

  /// رفع تغيير التخصص لجذر التطبيق — يحفظ ويعيد بناء الثيم بلونه.
  final ValueChanged<String> onSpecialtyChanged;

  /// استدعاء جانبي: تسجيل الاعتماد (إعادة البناء عند التغيير) +
  /// إرجاع القناة.
  static LearnerTheme? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LearnerTheme>();

  @override
  bool updateShouldNotify(LearnerTheme oldWidget) =>
      oldWidget.notifier != notifier ||
      oldWidget.specialty != specialty ||
      oldWidget.onSpecialtyChanged != onSpecialtyChanged;
}
