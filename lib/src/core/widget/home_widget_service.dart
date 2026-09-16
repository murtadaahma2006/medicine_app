import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:home_widget/home_widget.dart';

import '../database/database_helper.dart';
import '../database/srs_repository.dart';

/// حمولة بيانات الويدجت — قيم عرض قابلة للاختبار بلا قنوات منصة.
class HomeWidgetPayload {
  const HomeWidgetPayload({
    required this.dueCards,
    required this.dailyProgress,
    required this.medicalTip,
    required this.completedToday,
    required this.generatedAtIso,
    this.pendingPinnedTitles = const <String>[],
    this.pinnedTotal = 0,
    this.clinicalPearl = '',
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

  /// عناوين المحاضرات المثبتة غير المكتملة (سقف 3 — الجزء «أهدافي»).
  final List<String> pendingPinnedTitles;

  /// إجمالي المثبتات غير المكتملة بلا سقف — منه يحسب الويدجت
  /// «+N أخرى» (لاحظ: يختلف عن طول [pendingPinnedTitles] المقطوع).
  final int pinnedTotal;

  /// لؤلؤة اليوم — golden_tip عشوائية من أي محاضرة (الجزء السفلي).
  /// فارغة عند غيابها → الويدجت يعرض بنك المعلومات الثابت.
  final String clinicalPearl;

  /// عتبة «التراكم كبير» — الرقم يظهر أحمر عند تجاوزها.
  static const int highDueThreshold = 15;

  /// أقصى عدد محاضرات تُرسل للويدجت (سعة العرض في الشاشة الصغيرة).
  static const int maxPinnedTitles = 3;

  bool get isDueHigh => dueCards >= highDueThreshold;

  /// كم محاضرة وراء السقف — «+N أخرى» (لا سالب أبداً).
  int get extraPinnedCount => pinnedTotal - maxPinnedTitles;

  /// عناوين المثبتات نصاً واحداً مدمجاً بفواصل — عقد Native XML/Kotlin
  /// (سطر واحد لكل محاضرة في الويدجت عبر split على "|").
  /// الفواصل تُنزع من العنوان نفسه كي لا ينشق خطياً (عقد الإرسال).
  String get pendingPinnedJoined => pendingPinnedTitles
      .map((String t) => t.replaceAll('|', '⁄'))
      .join(' | ');

  Map<String, Object?> toMap() => <String, Object?>{
        'due_cards': dueCards,
        'daily_progress': dailyProgress,
        'completed_today': completedToday,
        'medical_tip': medicalTip,
        'generated_at': generatedAtIso,
        'pinned_titles': pendingPinnedJoined,
        'pinned_count': pendingPinnedTitles.length,
        // العدد الكلي غير المقطوع — منه يُشتق «+N أخرى» في Native.
        'pinned_total': pinnedTotal,
        'clinical_pearl': clinicalPearl,
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
  static const String keyPinnedTitles = 'pinned_titles';
  static const String keyPinnedCount = 'pinned_count';
  static const String keyPinnedTotal = 'pinned_total';
  static const String keyClinicalPearl = 'clinical_pearl';

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

    // (2) أنشطة اليوم: أحداث XP منذ بداية اليوم **المحلي** — عدّاد
    //     «اليوم» في الويدجت يتبع يوم المستخدم لا منتصف ليل UTC
    //     (كان يتصفر 3 فجراً بتوقيت UTC+3).
    final DateTime nowLocal = DateTime.now();
    final DateTime dayStartLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final List<Map<String, Object?>> todayEvents =
        await db.xpEventsSince(dayStartLocal.toUtc().toIso8601String());

    // الأنشطة المكتملة اليوم = تقييمات + بطاقات مُراجَعة.
    final int completedToday = todayEvents
        .where((Map<String, Object?> e) =>
            e['kind'] == 'assessment' || e['kind'] == 'flashcard')
        .length;

    // (3) نسبة الإنجاز اليومي (بناءً على المهام الفعلية المستحقة والمكتملة).
    final int totalToday = completedToday + due;
    final int progress = totalToday == 0
        ? 0
        : ((completedToday / totalToday) * 100).clamp(0, 100).toInt();

    // (4) أهدافي — المحاضرات المثبتة غير المكتملة: العناوين بسقف 3
    //     للعرض + العدد الكلي الحقيقي (عدّاد «+N أخرى»).
    final List<String> pinnedTitles =
        await db.getPendingPinnedLectureTitles(
      limit: HomeWidgetPayload.maxPinnedTitles,
    );
    final int pinnedTotal = await db.countPendingPinnedLectures();

    // (5) لؤلؤة اليوم — golden_tip عشوائية؛ عند غيابها بنك المعلومات
    //     الثابت (تتبدل يومياً) يضمن أن الجزء السفلي ليس فارغاً أبداً.
    final String? goldenTip = await db.getRandomGoldenTip();
    final String pearl = goldenTip ?? tipForDate(nowLocal.toUtc());

    return HomeWidgetPayload(
      dueCards: due,
      dailyProgress: progress,
      completedToday: completedToday,
      medicalTip: tipForDate(nowLocal.toUtc()),
      generatedAtIso: DateTime.now().toUtc().toIso8601String(),
      pendingPinnedTitles: pinnedTitles,
      pinnedTotal: pinnedTotal,
      clinicalPearl: pearl,
    );
  }

  // ─────────────────── المزامنة مع الطبقة الأصلية ───────────────────

  /// يكتب الحمولة إلى القنوات الأصلية (SharedPreferences في Android ·
  /// AppGroup UserDefaults في iOS) ويطلب تحديث الويدجت.
  static Future<void> sync(HomeWidgetPayload payload) async {
    try {
      // AppGroup أولاً (iOS يكتب فيه) — في Android سيغير مسار التخزين الافتراضي لذا نقصره على iOS.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(appGroupId);
      }

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

      // v19: أهدافي — عناوين المثبتات مدمجة بـ " | " (عد + نص واحد)
      // والويدجت الأصلي يقسمها لأسطر. pinned_total = العدد الكلي
      // غير المقطوع (عدّاد «+N أخرى» في Native). لؤلؤة اليوم نص مستقل.
      await HomeWidget.saveWidgetData<String>(
          keyPinnedTitles, payload.pendingPinnedJoined);
      await HomeWidget.saveWidgetData<String>(
          keyPinnedCount, payload.pendingPinnedTitles.length.toString());
      await HomeWidget.saveWidgetData<String>(
          keyPinnedTotal, payload.pinnedTotal.toString());
      await HomeWidget.saveWidgetData<String>(
          keyClinicalPearl, payload.clinicalPearl);

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

  /// نية نقرة معلّقة — وصلت أثناء الإقلاع (شاشة البداية) قبل أن
  /// يجهز الراوتر للتوجيه الآمن. تُستهلك عند التوجيه النهائي لشاشة
  /// البداية (راجع [consumePendingNavigation]).
  static bool _pendingDailyReview = false;

  /// هل اكتمل الإقلاع (تجاوزنا شاشة البداية)؟ قبلها أي نقرة ويدجت
  /// تُسجَّل نيةً لا توجيهاً مباشراً — شاشة البداية ستوجّه حسبها،
  /// وتوجيهها الافتراضي بعد 900ms لن يسحق شيئاً.
  static bool _startupFinished = false;

  /// تُستدعى من شاشة البداية لحظة توجيهها النهائي — بعدها نقرات
  /// الويدجت توجيه فوري عبر معالج main.
  static void markStartupFinished() => _startupFinished = true;

  /// تسجيل نية «المراجعة اليومية» يدوياً — يُستخدم دفاعياً من معالج
  /// main إن وصلت النقرة قبل بناء الـ navigator.
  static void setPendingDailyReview() => _pendingDailyReview = true;

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
      if (_startupFinished) {
        // التطبيق حي بعد الإقلاع — توجيه فوري عبر معالج main
        // (تفكيك الاعتماد الدائري: الخدمة لا تعرف الراوتر).
        _clickHandler?.call();
      } else {
        // إقلاع بارد: الراوتر/الشاشات لم تكتمل — سجّل النية
        // ويستهلكها التوجيه النهائي لشاشة البداية.
        _pendingDailyReview = true;
      }
    }
  }

  /// معالج نقرة الويدجت — يضبطه main بتوجيه go_router مباشر.
  static void Function()? _clickHandler;

  static void setClickHandler(void Function() handler) {
    _clickHandler = handler;
  }

  /// يستهلك نية «المراجعة اليومية» المعلّقة إن وُجدت — يعيد true
  /// وعلى المستدعي (شاشة البداية) توجيه المستخدم إليها بدل وجهته
  /// الافتراضية. استدعاء واحد يمسح النية (لا توجيه مزدوج).
  static bool consumePendingNavigation() {
    final bool pending = _pendingDailyReview;
    _pendingDailyReview = false;
    return pending;
  }
}
