import 'package:sqflite/sqflite.dart';

/// مستودع الإحصاءات القرائي لسجل الإجابات (corrections) — عام.
///
/// العقد:
/// - دوال ثابتة نقية (قراءة فقط): لا تكتب ولا تعدّل أي صف أبداً.
/// - كل الاستعلامات parameterized (حماية من SQL Injection).
/// - [drillKey] هو معرف جلسة التدريب المخزن في عمود drill_id.
///
/// الأداء: فلترة الأخطاء تستفيد من الفهرس الجزئي idx_corrections_wrong،
/// والترتيب الزمني من idx_corrections_time(attempted_at).
abstract final class WritingStats {
  /// إجمالي المحاولات المسجلة لجلسة تدريب واحدة.
  static Future<int> attemptsForDrill(Database db, String drillKey) async {
    final int? result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM corrections WHERE drill_id = ?',
        <Object?>[drillKey],
      ),
    );
    return result ?? 0;
  }

  /// عدد المحاولات الصحيحة (is_correct = 1) لنفس الجلسة.
  static Future<int> correctForDrill(Database db, String drillKey) async {
    final int? result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM corrections '
        'WHERE drill_id = ? AND is_correct = 1',
        <Object?>[drillKey],
      ),
    );
    return result ?? 0;
  }

  /// توزيع أنواع الأخطاء لجلسة التدريب:
  /// مفتاح = رمز نوع الخطأ (exact/spelling/wrong)،
  /// قيمة = عدد مراته بين الصفوف غير الصحيحة فقط.
  static Future<Map<String, int>> mistakeBreakdown(
    Database db,
    String drillKey,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT mistake_type, COUNT(*) AS c FROM corrections '
      'WHERE drill_id = ? AND is_correct = 0 '
      'GROUP BY mistake_type ORDER BY c DESC',
      <Object?>[drillKey],
    );
    return <String, int>{
      for (final Map<String, Object?> row in rows)
        row['mistake_type']! as String: row['c']! as int,
    };
  }

  /// معرفات الأسئلة الأكثر خطأً في الجلسة مرتبة تنازلياً.
  static Future<List<String>> weakestQuestions(
    Database db,
    String drillKey, {
    int limit = 5,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT question_id, COUNT(*) AS c FROM corrections '
      'WHERE drill_id = ? AND is_correct = 0 '
      'GROUP BY question_id ORDER BY c DESC, question_id ASC LIMIT ?',
      <Object?>[drillKey, limit],
    );
    return <String>[
      for (final Map<String, Object?> row in rows)
        row['question_id']! as String,
    ];
  }
}
