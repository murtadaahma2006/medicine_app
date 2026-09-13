import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/database/xp_event.dart';
import 'package:medicine_app/src/features/curriculum/data/unit_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات حذف المحاضرة بالكامل (Cascading Delete).
///
/// يثبت أن deleteLectureData يمس المحاضرة وكل ما يتصل بها:
/// المفاهيم · البطاقات · الأسئلة · الحالات وخطواتها · تقدم
/// المستخدم (user_progress/corrections/srs_cards/xp_events) —
/// و**لا يمس** بيانات محاضرة أخرى مجاورة.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('deleteLectureData يمسح كل الجداول المرتبطة ولا يمس الجيران',
      () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    // ── (أ) محاضرتان: الهدف (del-001) وجارة سليمة (keep-001) ──
    await _seedLecture('del-001', 'Target Lecture');
    await _seedLecture('keep-001', 'Keeper Lecture');

    // ── (ب) تقدم مستخدم حقيقي على الهدف: كل الأنماط الموثقة ──
    // flashcard_set (item_id = unitId مجرداً — اتفاقية التخزين)
    // + mcq + assess + حالة سريرية.
    await _rawProgress('flashcard_set', 'del-001');
    await _rawProgress('drill', 'mcq-del-001');
    await _rawProgress('drill', 'assess-del-001');
    await _rawProgress('drill', 'case-del-001-case1');
    // تقدم الجارة — يجب أن يبقى.
    await _rawProgress('drill', 'mcq-keep-001');

    // ── (ج) بطاقة SRS (تقدم Leitner) لبطاقة المحاضرة الهدف ──
    final Database db = await helper.database;
    await db.insert(
      DatabaseHelper.tableSrsCards,
      <String, Object?>{
        'flashcard_id': 'del-001-f1',
        'box': 3,
        'streak_ok': 2,
        'streak_bad': 0,
        'last_review': '2026-09-10',
        'next_due': '2026-09-14',
        'card_type': 'basic',
      },
    );

    // ── (د) سجل إجابات (corrections) بكل أنماط المفاتيح ──
    await _rawCorrection('mcq-del-001', 'del-001-q1');
    await _rawCorrection('assess-del-001', 'del-001-q2');
    await _rawCorrection('case-del-001-case1', 'del-001-case1-s1');
    // جار يجب أن يبقى:
    await _rawCorrection('mcq-keep-001', 'keep-001-q1');

    // ── (هـ) أحداث XP مرتبطة بعناصر المحاضرة ──
    await helper.addXpEvent(
        kind: XpEventKind.flashcard, refId: 'del-001-f1', xp: 3);
    await helper.addXpEvent(kind: XpEventKind.mcq, refId: 'mcq-del-001', xp: 5);
    await helper.addXpEvent(
        kind: XpEventKind.assessment, refId: 'assess-del-001', xp: 20);
    // حدث حر — لا مرجع — يجب أن يبقى (سلسلة/شارة مثلاً).
    await helper.addXpEvent(kind: XpEventKind.streak, refId: null, xp: 2);
    // حدث للجارة — يبقى.
    await helper.addXpEvent(kind: XpEventKind.mcq, refId: 'mcq-keep-001', xp: 5);

    // ── (و) التنفيذ: حذف المحاضرة الهدف ──
    await helper.deleteLectureData('del-001');

    // ── (ز) التحقق: كل ما يخص الهدف مُسح ──
    expect(await _count(db, 'units', "id = 'del-001'"), 0);
    expect(await _count(db, 'concepts', "unit_id = 'del-001'"), 0);
    expect(await _count(db, 'flashcards', "unit_id = 'del-001'"), 0);
    expect(await _count(db, 'mcq_bank', "unit_id = 'del-001'"), 0);
    expect(await _count(db, 'clinical_cases', "unit_id = 'del-001'"), 0);
    expect(await _count(db, 'clinical_case_steps', "id LIKE 'del-001-%'"), 0);
    expect(await _count(db, 'srs_cards', "flashcard_id LIKE 'del-001-%'"), 0);
    expect(
      await _count(db, 'user_progress',
          "item_id LIKE '%del-001%' OR item_id LIKE '%del-001-case1%'"),
      0,
    );
    expect(
      await _count(db, 'corrections', "drill_id LIKE '%del-001%'"),
      0,
    );
    expect(
      await _count(db, 'xp_events',
          "ref_id LIKE '%del-001%' AND ref_id IS NOT NULL"),
      0,
    );

    // ── (ح) التحقق: الجارة سليمة كلياً (لا حذف مفرط) ──
    expect(await _count(db, 'units', "id = 'keep-001'"), 1);
    expect(await _count(db, 'concepts', "unit_id = 'keep-001'"), 1);
    expect(await _count(db, 'flashcards', "unit_id = 'keep-001'"), 3);
    expect(await _count(db, 'mcq_bank', "unit_id = 'keep-001'"), 3);
    expect(await _count(db, 'clinical_cases', "unit_id = 'keep-001'"), 1);
    expect(await _count(db, 'user_progress', "item_id = 'mcq-keep-001'"), 1);
    expect(await _count(db, 'corrections', "drill_id = 'mcq-keep-001'"), 1);
    expect(await _count(db, 'xp_events', "ref_id = 'mcq-keep-001'"), 1);
    // حدث السلسلة بلا مرجع — بقي.
    expect(await _count(db, 'xp_events', "kind = 'streak'"), 1);
  });

  test('deleteLecture (repository) يرجع true ويزيل المحاضرة', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
    await _seedLecture('solo-001', 'Solo Lecture');

    const UnitRepository repo = UnitRepository();
    final bool ok = await repo.deleteLecture('solo-001');

    expect(ok, isTrue);
    final List<Map<String, Object?>> units = await helper.getAllUnits();
    expect(units.where((Map<String, Object?> u) => u['id'] == 'solo-001'),
        isEmpty);
  });

  test('deleteLecture على معرف غير موجود = true (idempotent بلا أثر)',
      () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    const UnitRepository repo = UnitRepository();
    final bool ok = await repo.deleteLecture('ghost-001');
    expect(ok, isTrue);
  });
}

// ───────────────────────────── أدوات البناء ─────────────────────────────

/// محاضرة كاملة (شرح + 3 بطاقات + 3 أسئلة + حالة بخطوتين).
Future<void> _seedLecture(String id, String title) async {
  final DatabaseHelper helper = DatabaseHelper.instance;
  final Database db = await helper.database;

  await db.insert(DatabaseHelper.tableUnits, <String, Object?>{
    'id': id,
    'module': 'cardiology',
    'system': 'cardiovascular',
    'title': title,
    'order_index': 0,
  });
  await db.insert(DatabaseHelper.tableConcepts, <String, Object?>{
    'id': '$id-c1',
    'unit_id': id,
    'title': 'Concept of $title',
    'sections_json': '[]',
    'difficulty': 'core',
    'order_index': 0,
  });
  for (int i = 1; i <= 3; i++) {
    await db.insert(DatabaseHelper.tableFlashcards, <String, Object?>{
      'id': '$id-f$i',
      'unit_id': id,
      'card_type': 'basic',
      'front_text': 'Front $i',
      'back_text': 'Back $i answer',
    });
    await db.insert(DatabaseHelper.tableMcqBank, <String, Object?>{
      'id': '$id-q$i',
      'unit_id': id,
      'question_stem': 'Stem $i of $title',
      'options_json': '["a","b","c"]',
      'correct_index': 0,
      'explanation_ar': 'شرح',
      'difficulty': 'core',
      'clinical_vignette': 0,
    });
  }
  await db.insert(DatabaseHelper.tableClinicalCases, <String, Object?>{
    'id': '$id-case1',
    'unit_id': id,
    'title': 'Case of $title',
    'scenario': 'Scenario' * 10,
    'vignette_json': '{}',
    'debriefing_ar': 'd' * 80,
    'difficulty': 'core',
    'order_index': 0,
  });
  for (int s = 1; s <= 2; s++) {
    await db.insert(DatabaseHelper.tableClinicalCaseSteps, <String, Object?>{
      'id': '$id-case1-s$s',
      'case_id': '$id-case1',
      'prompt': 'Step $s decision',
      'options_json': '["x","y","z"]',
      'correct_index': 0,
      'explanation_ar': 'شرح',
      'xp': 5,
      'step_index': s - 1,
    });
  }
}

/// إدراج صف تقدم خام مباشرة.
Future<void> _rawProgress(String itemType, String itemId) async {
  final DatabaseHelper helper = DatabaseHelper.instance;
  final Database db = await helper.database;
  await db.insert(DatabaseHelper.tableUserProgress, <String, Object?>{
    'item_type': itemType,
    'item_id': itemId,
    'status': 'completed',
    'score': 80,
    'times_reviewed': 1,
    'last_practiced_at': '2026-09-10',
    'updated_at': '2026-09-10',
  });
}

/// إدراج محاولة إجابة خام مباشرة (سجل corrections).
Future<void> _rawCorrection(String drillId, String questionId) async {
  final DatabaseHelper helper = DatabaseHelper.instance;
  final Database db = await helper.database;
  await db.insert(DatabaseHelper.tableCorrections, <String, Object?>{
    'drill_id': drillId,
    'question_id': questionId,
    'user_answer': 'answer',
    'correct_answer': 'answer',
    'is_correct': 1,
    'mistake_type': 'exact',
    'attempted_at': '2026-09-10T10:00:00Z',
  });
}

Future<int> _count(Database db, String table, String where) async {
  final List<Map<String, Object?>> rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM $table WHERE $where',
  );
  return (rows.first['c']! as num).toInt();
}
