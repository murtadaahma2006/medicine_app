import 'package:flutter/foundation.dart' show debugPrint;
import 'package:home_widget/home_widget.dart';

import '../database/database_helper.dart';
import '../database/srs_repository.dart';
import '../profile/learner_profile.dart';

/// حمولة بيانات الويدجت — قيم عرض قابلة للاختبار بلا قنوات منصة.
class HomeWidgetPayload {
  const HomeWidgetPayload({
    required this.dueCards,
    required this.dailyProgress,
    required this.medicalTip,
    required this.completedToday,
    required this.generatedAtIso,
  });

  /// عدد البطاقات المستحقة للمراجعة اليوم.
  final int dueCards;

  /// نسبة الإنجاز اليومي (0–100) من الهدف اليومي.
  final int dailyProgress;

  /// الدروس/الأنشطة المكتملة اليوم (تقييمات + جلسات بطاقات).
  final int completedToday;

  /// معلومة طبية سريعة تتبدل يومياً.
  final String medicalTip;

  /// ISO UTC لحظة الحساب (تشخيص/حداثة البيانات).
  final String generatedAtIso;

  /// عتبة «التراكم كبير» — الرقم يظهر أحمر عند تجاوزها.
  static const int highDueThreshold = 15;

  bool get isDueHigh => dueCards >= highDueThreshold;

  Map<String, Object?> toMap() => <String, Object?>{
        'due_cards': dueCards,
        'daily_progress': dailyProgress,
        'completed_today': completedToday,
        'medical_tip': medicalTip,
        'generated_at': generatedAtIso,
      };
}

/// خدمة ويدجت الشاشة الرئيسية — تعرض عدد البطاقات المستحقة، تقدم
/// اليوم، ومعلومة طبية سريعة، وتحدّثها في الخلفية (workmanager).
///
/// **العقد مع الطبقات الأصلية (Native)**:
/// - Android: AppWidgetProvider يقرأ SharedPreferences
///   (HomeWidgetPlugin) ويبني RemoteViews.
/// - iOS: WidgetKit TimelineProvider يقرأ AppGroup UserDefaults
///   (group.medicine_app.shared).
/// - الضغط على الويدجت يفتح `medicineapp://daily-review`.
///
/// **حداثة البيانات**: تحديث فوري عند كل إجابة/إكمال (من الشاشات)،
/// وعند فتح التطبيق، ودورياً في الخلفية كل ~6 ساعات.
abstract final class HomeWidgetService {
  /// معرف AppGroup (iOS) — نفسه في إعدادات Xcode وملف Swift.
  static const String appGroupId = 'group.medicine_app.shared';

  /// اسم iOS لويدجت WidgetKit (Target اسمه MedicineWidget).
  static const String iosWidgetName = 'MedicineWidget';

  /// URI للضغط على الويدجت — يفتح «المراجعة اليومية» مباشرة.
  static const String dailyReviewUri = 'medicineapp://daily-review';

  // ── مفاتيح الحمولة (موحدة بين Dart وKotlin وSwift) ──
  static const String keyDueCards = 'due_cards';
  static const String keyDailyProgress = 'daily_progress';
  static const String keyMedicalTip = 'medical_tip';
  static const String keyCompletedToday = 'completed_today';
  static const String keyGeneratedAt = 'generated_at';

  /// بنك المعلومات الطبية السريعة — تُختار واحدة حسب اليوم.
  static const List<String> medicalTips = <String>[
    'لا تعطِ Beta-blockers لمريض الربو — قد تسبب قصمةً شعبية شديدة.',
    'البنسلين هو السبب الأول لصدمة الحساسية anaphylaxis الدوائية.',
    'حصى الكلى الصغيرة <5mm تُعالج تحفظياً — شرب ومراقبة.',
    'ضيق التنفس الليلي المفاجئ = قصور قلب احتقاني حتى يثبت العكس.',
    'انخفاض الضغط + ألم بطني: استبعد حمل خارج الرحم عند كل امرأة بسن الإنجاب.',
    'CHF: قلة الصوديوم تتبع مدرات العروة — راقب K+ وMg2+.',
    'التهاب الشغاف يشتبه به مع أي حمى مجهولة السبب + نفخة جديدة.',
    'DKA: عالج الجفاف أولاً — الأنسولين بعد استقرار الدوران.',
    'Asthma: الجرعة المتكررة للSalbutamol آمنة في النوبة الحادة.',
    'النزف الهضمي العلوي: PPI وريدي + إنعاش قبل التنظير.',
  ];

  /// اختيار المعلومة اليومية — دالة نقية (نفس اليوم = نفس المعلومة).
  static String tipForDate(DateTime dateUtc) {
    final int dayOfYear = dateUtc.difference(
      DateTime.utc(dateUtc.year, 1, 1),
    ).inDays;
    final int dayNumber = dateUtc.year * 1000 + dayOfYear;
    return medicalTips[dayNumber % medicalTips.length];
  }

  // ─────────────────── حساب الحمولة (نقي — بلا قنوات) ───────────────────

  /// يحسب حمولة الويدجت من القاعدة والتفضيلات — بلا أي استدعاء منصة،
  /// قابل للاختبار على FFI بالكامل.
  static Future<HomeWidgetPayload> computePayload() async {
    final DatabaseHelper db = DatabaseHelper.instance;

    // (1) البطاقات المستحقة اليوم (Leitner).
    final int due = await SrsRepository.dueTodayCount();

    // (2) أنشطة اليوم: أحداث XP منذ بداية اليوم UTC.
    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime dayStartUtc =
        DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final List<Map<String, Object?>> todayEvents =
        await db.xpEventsSince(dayStartUtc.toIso8601String());

    // الأنشطة المكتملة اليوم = تقييمات + بطاقات مُراجَعة.
    final int completedToday = todayEvents
        .where((Map<String, Object?> e) =>
            e['kind'] == 'assessment' || e['kind'] == 'flashcard')
        .length;

    // (3) الهدف اليومي من تفضيلات المستخدم (الافتراضي 10 بطاقات).
    final int goal = await LearnerProfile.dailyGoal();

    // نسبة الإنجاز 0–100 من الهدف (سقف 100).
    final int progress = goal <= 0
        ? 0
        : ((completedToday / goal) * 100).clamp(0, 100).toInt();

    return HomeWidgetPayload(
      dueCards: due,
      dailyProgress: progress,
      completedToday: completedToday,
      medicalTip: tipForDate(nowUtc),
      generatedAtIso: nowUtc.toIso8601String(),
    );
  }

  // ─────────────────── المزامنة مع الطبقة الأصلية ───────────────────

  /// يكتب الحمولة إلى القنوات الأصلية (SharedPreferences في Android ·
  /// AppGroup UserDefaults في iOS) ويطلب تحديث الويدجت.
  static Future<void> sync(HomeWidgetPayload payload) async {
    try {
      // AppGroup أولاً (iOS يكتب فيه) — بلا أثر في Android.
      await HomeWidget.setAppGroupId(appGroupId);

      await HomeWidget.saveWidgetData<String>(
          keyDueCards, payload.dueCards.toString());
      await HomeWidget.saveWidgetData<String>(
          keyDailyProgress, payload.dailyProgress.toString());
      await HomeWidget.saveWidgetData<String>(
          keyMedicalTip, payload.medicalTip);
      await HomeWidget.saveWidgetData<String>(
          keyCompletedToday, payload.completedToday.toString());
      await HomeWidget.saveWidgetData<String>(
          keyGeneratedAt, payload.generatedAtIso);

      await HomeWidget.updateWidget(
        iOSName: iosWidgetName,
        androidName: 'MedicineHomeWidgetProvider',
      );
    } catch (error) {
      // الويدجت تحسين غير حركي — فشل المزامنة لا يكسر أي شيء.
      debugPrint('HomeWidgetService.sync فشل: $error');
    }
  }

  /// حساب + مزامنة دفعة واحدة — يستدعى من الواجهة والخلفية.
  static Future<void> refresh() async {
    final HomeWidgetPayload payload = await computePayload();
    await sync(payload);
  }

  // ─────────────────── الخلفية (Workmanager) ───────────────────

  /// رد نداء الخلفية — نفس المفتاح المستعمل في MainActivity (Kotlin)
  /// وفي تسجيل Workmanager الدوري (كل 6 ساعات).
  static const String backgroundTaskKey = 'medicineAppWidgetRefresh';

  /// يسجّل رد نداء Dart (تنفيذ المهمة في isolate خلفي) — يُستدعى
  /// من main؛ native (WorkManager/WidgetKit) يستدعيه للتحديث الخلفي.
  static Future<void> registerBackgroundTask() async {
    await HomeWidget.registerInteractivityCallback(_backgroundCallback);
  }

  /// رد نداء workmanager/home_widget — بعزل منفصل بلا Widgets.
  @pragma('vm:entry-point')
  static Future<void> _backgroundCallback(Uri? uri) async {
    await refresh();
  }

  // ─────────────────── استقبال الضغط (Deep Link) ───────────────────

  /// تهيئة استقبال نقرة الويدجت — يستدعى بعد أول إطار في main.
  /// يفتح «المراجعة اليومية» عند وصول medicineapp://daily-review.
  static Future<void> initClickRouting() async {
    try {
      // النقرة التي فتحت التطبيق من حالة موت كامل.
      final Uri? initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      _handleWidgetUri(initial);

      // النقرات والتطبيق حي (stream).
      HomeWidget.widgetClicked.listen(_handleWidgetUri);
    } catch (error) {
      debugPrint('HomeWidgetService.initClickRouting فشل: $error');
    }
  }

  static void _handleWidgetUri(Uri? uri) {
    if (uri == null) return;
    if (uri.toString().contains('daily-review')) {
      // التوجيه عبر معالج يسجله main — تفكيك الاعتماد الدائري.
      _clickHandler?.call();
    }
  }

  /// معالج نقرة الويدجت — يضبطه main بتوجيه go_router مباشرة.
  static void Function()? _clickHandler;

  static void setClickHandler(void Function() handler) {
    _clickHandler = handler;
  }
}
