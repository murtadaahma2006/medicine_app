import '../motivation/motivation_model.dart';
import 'database_helper.dart';
import 'user_progress.dart';

/// مستودع تحفيز المتعلم — دوال قرائية تُجمّع [MotivationSnapshot]
/// من القاعدة المحلية.
///
/// العقد:
/// - قراءة صرفة: لا دالة هنا تكتب في أي جدول.
/// - كل الاستعلامات parameterized.
///
/// قرار معماري موثق — مصدر أيام السلسلة:
/// نحسب الأيام من **xp_events حصراً** (DISTINCT substr(created_at,1,10)).
abstract final class MotivationRepository {
  /// يجمع اللقطة الكاملة لحالة التحفيز في لحظة النداء.
  static Future<MotivationSnapshot> snapshot({Set<String>? unlocked}) async {
    final DatabaseHelper dbh = DatabaseHelper.instance;
    final Set<String> badges = unlocked ?? await dbh.getUnlockedBadgeIds();

    return MotivationSnapshot(
      totalXp: await dbh.sumXp(),
      currentStreak: await currentStreak(),
      longestStreak: await longestStreak(),
      completedLessons: await _countCompleted(ProgressItemType.lesson),
      completedVocabSets: await _countCompleted(ProgressItemType.flashcardSet),
      perfectMcqSessions: await perfectMcqSessions(),
      correctCaseSteps: await correctCaseSteps(),
      unlockedBadgeIds: badges,
    );
  }

  /// عدد عناصر مكتملة لنوع واحد من جدول التقدم.
  static Future<int> _countCompleted(ProgressItemType type) =>
      DatabaseHelper.instance.countCompletedByType(type);

  /// جلسات MCQ المكتملة بعلامة كاملة (100%).
  /// معرفات جلسات MCQ تبدأ بالبادئة mcq- (اتفاق المسارات).
  static Future<int> perfectMcqSessions() {
    return DatabaseHelper.instance.rawCount(
      '''
        SELECT COUNT(*) FROM ${DatabaseHelper.tableUserProgress}
        WHERE item_type = ? AND item_id LIKE ? AND score = 100 AND status = ?
      ''',
      <Object?>[
        progressItemTypeToCode(ProgressItemType.drill),
        'mcq-%',
        progressStatusToCode(ProgressStatus.completed),
      ],
    );
  }

  /// القرارات السريرية الصحيحة تراكمياً.
  /// خطوات الحالات السريرية ببادئة case- في drill_id (اتفاق المسارات).
  static Future<int> correctCaseSteps() {
    return DatabaseHelper.instance.rawCount(
      '''
        SELECT COUNT(*) FROM ${DatabaseHelper.tableCorrections}
        WHERE drill_id LIKE ? AND is_correct = 1
      ''',
      <Object?>['case-%'],
    );
  }

  // ─────────────────── حساب السلاسل من xp_events ───────────────────

  /// أيام النشاط (yyyy-MM-dd) مرتبة تصاعدياً.
  static Future<List<String>> activeDays() async {
    final List<Map<String, Object?>> rows =
        await DatabaseHelper.instance.rawQueryParameterized(
      'SELECT DISTINCT substr(created_at, 1, 10) AS d '
      'FROM ${DatabaseHelper.tableXpEvents} ORDER BY d ASC',
    );
    return <String>[
      for (final Map<String, Object?> row in rows) row['d']! as String,
    ];
  }

  /// السلسلة الحالية: عدد الأيام المتتابعة المنتهية عند اليوم أو الأمس.
  static Future<int> currentStreak() async =>
      streakEndingAt(await activeDays(), utcTodayOrYesterday());

  /// أطول سلسلة في كامل التاريخ.
  static Future<int> longestStreak() async => longestRun(await activeDays());

  // ── دوال التاريخ النقية (public للاختبار بدون قاعدة) ──

  /// ISO UTC لتاريخ اليوم بصيغة yyyy-MM-dd.
  static String utcToday() =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  /// التاريخان المقبولان كنهاية لسلسلة «حية»: اليوم والأمس.
  static List<String> utcTodayOrYesterday() {
    final DateTime now = DateTime.now().toUtc();
    final String today = now.toIso8601String().substring(0, 10);
    final String yesterday = now
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    return <String>[today, yesterday];
  }

  /// طول السلسلة المنتهية عند أحد [allowedEnds] (أطولها)، أو 0.
  static int streakEndingAt(List<String> days, List<String> allowedEnds) {
    if (days.isEmpty) return 0;

    final Set<String> daySet = days.toSet();
    int best = 0;
    for (final String end in allowedEnds) {
      if (!daySet.contains(end)) continue;
      int streak = 0;
      DateTime cursor = DateTime.parse('${end}T00:00:00.000Z');
      while (daySet.contains(cursor.toIso8601String().substring(0, 10))) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
      if (streak > best) best = streak;
    }
    return best;
  }

  /// أطول تتابع أيام متصل في القائمة.
  static int longestRun(List<String> days) {
    if (days.isEmpty) return 0;

    final List<DateTime> sorted = (days.toList()..sort())
        .map((String d) => DateTime.parse('${d}T00:00:00.000Z'))
        .toList();

    int longest = 1;
    int run = 1;
    for (int i = 1; i < sorted.length; i++) {
      final Duration gap = sorted[i].difference(sorted[i - 1]);
      if (gap == const Duration(days: 1)) {
        run++;
        if (run > longest) longest = run;
      } else if (gap > Duration.zero) {
        run = 1;
      }
    }
    return longest;
  }
}
