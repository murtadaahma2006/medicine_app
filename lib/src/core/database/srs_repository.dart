import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// بطاقة مراجعة واحدة — بطاقة محتوى + نوعها.
class SrsCard {
  const SrsCard({
    required this.cardId,
    required this.frontText,
    required this.backText,
    required this.type,
    required this.box,
  });

  /// معرف البطاقة (جدول flashcards).
  final String cardId;

  /// وجه البطاقة (السؤال الاسترجاعي) — إنجليزي.
  final String frontText;

  /// ظهر البطاقة (الإجابة التفصيلية) — إنجليزي.
  final String backText;

  /// نوع البطاقة — v14: 'basic' (قابل للتوسعة مستقبلاً).
  final String type;

  /// صندوق Leitner الحالي (1..5).
  final int box;
}

/// مستودع التكرار المتباعد — خوارزمية Leitner بصناديق 1..5.
///
/// الفلسفة (موثقة للمراجعة):
/// - كل بطاقة محتوى لها «بطاقة SRS» مستقلة عن تقدم الوحدات — التعلم
///   الحقيقي لا يرتبط بجلسة معينة بل بتكرار رؤيتها بفواصل متزايدة.
/// - **الصناديق وفواصلها (أيام من الآن):** 1→1 · 2→2 · 3→4 · 4→8 · 5→16.
///   إجابة صحيحة = ترقية صندوق + جدولة الفاصل الجديد. إجابة خاطئة =
///   هبوط للصندوق 1 (إعادة البناء من الأساس) + جدولة الغد.
/// - **الاستحقاق:** بطاقة مستحقة اليوم إذا next_due ≤ نهاية اليوم (UTC).
/// - كل التواريخ ISO UTC — متطابقة مع اصطلاح بقية القاعدة.
abstract final class SrsRepository {
  /// فترات الصناديق بالأيام — index = صندوق - 1.
  static const List<int> _boxIntervalsDays = <int>[1, 2, 4, 8, 16];

  /// يبني التاريخ المستحق القادم بصيغة ISO UTC.
  static String _dueAfter(int box, DateTime nowUtc) {
    final int days = _boxIntervalsDays[box - 1];
    return nowUtc.add(Duration(days: days)).toIso8601String();
  }

  /// نهاية اليوم UTC بصيغة ISO — البطاقات المستحقة قبلها تُعدّ «اليوم».
  static String _endOfTodayUtc() {
    final DateTime now = DateTime.now().toUtc();
    final DateTime end = DateTime.utc(now.year, now.month, now.day, 23, 59, 59);
    return end.toIso8601String();
  }

  // ───────────────────────── إجابات وتحديثات ─────────────────────────

  /// يسجل إجابة على بطاقة (ترقية عند الصحة، هبوط للصندوق 1 عند الخطأ).
  /// ينشئ البطاقة عند أول إجابة إن لم توجد (idempotent-create).
  static Future<void> recordAnswer(String cardId, bool correct) async {
    final Database db = await DatabaseHelper.instance.database;
    final DateTime now = DateTime.now().toUtc();

    final List<Map<String, Object?>> existing = await db.query(
      DatabaseHelper.tableSrsCards,
      where: 'flashcard_id = ? AND card_type = ?',
      whereArgs: <Object?>[cardId, 'basic'],
      limit: 1,
    );

    if (existing.isEmpty) {
      final int startBox = correct ? 2 : 1;
      await db.insert(
        DatabaseHelper.tableSrsCards,
        <String, Object?>{
          'flashcard_id': cardId,
          'box': startBox,
          'streak_ok': correct ? 1 : 0,
          'streak_bad': correct ? 0 : 1,
          'last_review': now.toIso8601String(),
          'next_due': _dueAfter(startBox, now),
          'card_type': 'basic',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    final int currentBox = (existing.first['box'] as num?)?.toInt() ?? 1;
    final int nextBox = correct ? nextBoxAfter(currentBox, true) : 1;

    await db.update(
      DatabaseHelper.tableSrsCards,
      <String, Object?>{
        'box': nextBox,
        'streak_ok': correct
            ? ((existing.first['streak_ok'] as num?)?.toInt() ?? 0) + 1
            : 0,
        'streak_bad': correct
            ? 0
            : ((existing.first['streak_bad'] as num?)?.toInt() ?? 0) + 1,
        'last_review': now.toIso8601String(),
        'next_due': _dueAfter(nextBox, now),
      },
      where: 'flashcard_id = ? AND card_type = ?',
      whereArgs: <Object?>[cardId, 'basic'],
    );
  }

  // ───────────────────────── الاستعلامات ─────────────────────────

  /// البطاقات المستحقة اليوم مرتبة بالأقدمية — الجرعة اليومية للمراجعة.
  static Future<List<SrsCard>> dueToday() async {
    final Database db = await DatabaseHelper.instance.database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT f.id AS card_id, f.front_text, f.back_text,
             s.card_type AS s_type, s.box AS s_box
      FROM ${DatabaseHelper.tableSrsCards} s
      JOIN ${DatabaseHelper.tableFlashcards} f ON f.id = s.flashcard_id
      WHERE s.next_due <= ?
      ORDER BY s.next_due ASC
    ''', <Object?>[_endOfTodayUtc()]);

    return rows
        .map<SrsCard>(
          (Map<String, Object?> row) => SrsCard(
            cardId: row['card_id']! as String,
            frontText: row['front_text']! as String,
            backText: row['back_text']! as String,
            type: (row['s_type'] as String?) ?? 'basic',
            box: (row['s_box'] as num?)?.toInt() ?? 1,
          ),
        )
        .toList();
  }

  /// عدد البطاقات المستحقة اليوم (للحلقات والشارات).
  static Future<int> dueTodayCount() async {
    final Database db = await DatabaseHelper.instance.database;
    final int? count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM ${DatabaseHelper.tableSrsCards} '
      'WHERE next_due <= ?',
      <Object?>[_endOfTodayUtc()],
    ));
    return count ?? 0;
  }

  /// إجمالي البطاقات النشطة في نظام SRS.
  static Future<int> totalCards() async {
    final Database db = await DatabaseHelper.instance.database;
    final int? count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM ${DatabaseHelper.tableSrsCards}',
    ));
    return count ?? 0;
  }

  /// توزيع البطاقات على الصناديق.
  static Future<Map<int, int>> boxDistribution() async {
    final Database db = await DatabaseHelper.instance.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT box, COUNT(*) AS c FROM ${DatabaseHelper.tableSrsCards} '
      'GROUP BY box ORDER BY box',
    );
    return <int, int>{
      for (final Map<String, Object?> row in rows)
        (row['box'] as num).toInt(): (row['c'] as num).toInt(),
    };
  }

  /// صيغة نقية (للاختبار): الصندوق التالي بعد إجابة.
  static int nextBoxAfter(int currentBox, bool correct) {
    if (!correct) return 1;
    return currentBox >= 5 ? 5 : currentBox + 1;
  }
}
