import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات الاستعلامات الديناميكية للبنوك (Smart Filtering).
///
/// يغطي: getFlashcards/getMcqs/getCases بكل تركيبات
/// (system × lectureId × isRandom) + getStudiedFlashcards
/// (المراجعة العشوائية المدروسة) + getUnitsBySystem/getDistinctSystems.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Future<void> seed() async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    // جهازان: قلب (محاضرتان) + تنفس (محاضرة واحدة).
    const List<(String, String, String, int)> units =
        <(String, String, String, int)>[
      ('cardio-001', 'cardiology', 'cardiovascular', 0),
      ('cardio-002', 'cardiology', 'cardiovascular', 1),
      ('pulmo-001', 'pulmonology', 'respiratory', 0),
    ];
    for (final (String, String, String, int) u in units) {
      await helper.insertUnit(<String, Object?>{
        'id': u.$1,
        'module': u.$2,
        'system': u.$3,
        'title': 'Lecture ${u.$1}',
        'order_index': u.$4,
      });
      // بطاقتان لكل محاضرة (إجمالي 6).
      for (int i = 1; i <= 2; i++) {
        await helper.insertFlashcard(<String, Object?>{
          'id': '${u.$1}-f$i',
          'unit_id': u.$1,
          'card_type': 'basic',
          'front_text': 'Front $i of ${u.$1}',
          'back_text': 'Back $i answer long enough',
        });
        await helper.insertMcq(<String, Object?>{
          'id': '${u.$1}-q$i',
          'unit_id': u.$1,
          'question_stem': 'Stem $i of ${u.$1}',
          'options_json': '["a","b","c"]',
          'correct_index': 0,
          'explanation_ar': 'شرح',
          'difficulty': 'core',
          'clinical_vignette': 0,
        });
      }
      // حالة واحدة لكل محاضرة (إجمالي 3).
      final dynamic db = await helper.database;
      await db.insert(
        DatabaseHelper.tableClinicalCases,
        <String, Object?>{
          'id': '${u.$1}-case1',
          'unit_id': u.$1,
          'title': 'Case of ${u.$1}',
          'scenario': 'Scenario' * 10,
          'vignette_json': '{}',
          'debriefing_ar': 'd' * 80,
          'difficulty': 'core',
          'order_index': 0,
        },
      );
    }
  }

  test('getFlashcards — بلا فلاتر: كل البطاقات بترتيب المنهج', () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;

    final List<Map<String, Object?>> all = await helper.getFlashcards();
    expect(all.length, 6);

    // الترتيب الزمني: (order_index المحاضرة, معرفها) ثم معرف البطاقة.
    // cardio-001/pulmo-001 كلاهما order_index=0 — الحسم بمعرف المحاضرة.
    expect(all.first['id'], 'cardio-001-f1');
    expect(all[1]['id'], 'cardio-001-f2');
    expect(all[2]['id'], 'pulmo-001-f1');
    expect(all[3]['id'], 'pulmo-001-f2');
    // ثم محاضرات index=1.
    expect(all[4]['id'], 'cardio-002-f1');
    expect(all[5]['id'], 'cardio-002-f2');
  });

  test('getFlashcards — فلترة الجهاز', () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;

    final List<Map<String, Object?>> respiratory =
        await helper.getFlashcards(system: 'respiratory');
    expect(respiratory.length, 2);
    expect(respiratory.every(
        (Map<String, Object?> f) => f['unit_id'] == 'pulmo-001'), isTrue);
  });

  test('getFlashcards — فلترة المحاضرة داخل الجهاز', () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;

    final List<Map<String, Object?>> cards =
        await helper.getFlashcards(lectureId: 'cardio-002');
    expect(cards.length, 2);
    expect(cards.every(
        (Map<String, Object?> f) => f['unit_id'] == 'cardio-002'), isTrue);
  });

  test('getFlashcards — isRandom يعطي نفس المجموعة بترتيب متغير الغالب',
      () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;

    final List<Map<String, Object?>> sorted =
        await helper.getFlashcards(system: 'cardiovascular');
    final List<Map<String, Object?>> shuffled =
        await helper.getFlashcards(system: 'cardiovascular', isRandom: true);

    // نفس المجموعة (4 بطاقات القلب) — قد يتغير الترتيب أو لا،
    // لكن الاستعلام يجب أن يعمل ويعيد الصف نفسها.
    expect(shuffled.length, 4);
    expect(
      shuffled.map((Map<String, Object?> f) => f['id']).toSet(),
      sorted.map((Map<String, Object?> f) => f['id']).toSet(),
    );
  });

  test('getFlashcards — limit يقص النتائج', () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;

    final List<Map<String, Object?>> limited =
        await helper.getFlashcards(limit: 3);
    expect(limited.length, 3);
  });

  test('getMcqs/getCases — نفس عقد الفلترة', () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;

    expect((await helper.getMcqs()).length, 6);
    expect((await helper.getMcqs(system: 'renal')).length, 0);
    expect((await helper.getMcqs(lectureId: 'pulmo-001')).length, 2);

    expect((await helper.getCases()).length, 3);
    expect((await helper.getCases(system: 'cardiovascular')).length, 2);
    expect((await helper.getCases(limit: 1)).length, 1);
  });

  test('getStudiedFlashcards — فقط المحاضرات ذات سجل تقدم', () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;
    final dynamic db = await helper.database;

    // (أ) بلا تقدم — لا بطاقات مدروسة.
    expect((await helper.getStudiedFlashcards()).length, 0);

    // (ب) المستخدم أكمل مجموعة بطاقات cardio-001 فقط (flashcard_set).
    await db.insert(DatabaseHelper.tableUserProgress, <String, Object?>{
      'item_type': 'flashcard_set',
      'item_id': 'cardio-001',
      'status': 'in_progress',
      'times_reviewed': 1,
      'last_practiced_at': '2026-09-10',
      'updated_at': '2026-09-10',
    });
    // وتدرّب على أسئلة pulmo-001 (drill: mcq-).
    await db.insert(DatabaseHelper.tableUserProgress, <String, Object?>{
      'item_type': 'drill',
      'item_id': 'mcq-pulmo-001',
      'status': 'in_progress',
      'times_reviewed': 1,
      'last_practiced_at': '2026-09-10',
      'updated_at': '2026-09-10',
    });

    // المدروس = بطاقات cardio-001 (2) + pulmo-001 (2) = 4 — لا تكرار
    // ولا بطاقات cardio-002 (لم تُدرس).
    final List<Map<String, Object?>> studied =
        await helper.getStudiedFlashcards();
    expect(studied.length, 4);
    expect(
      studied.map((Map<String, Object?> f) => f['unit_id']).toSet(),
      <String>{'cardio-001', 'pulmo-001'},
    );

    // (ج) فلترة الجهاز على المدروس: القلب فقط = 2.
    final List<Map<String, Object?>> cardioStudied =
        await helper.getStudiedFlashcards(system: 'cardiovascular');
    expect(cardioStudied.length, 2);
    expect(cardioStudied.every(
        (Map<String, Object?> f) => f['unit_id'] == 'cardio-001'), isTrue);
  });

  test('getUnitsBySystem + getDistinctSystems', () async {
    await seed();
    final DatabaseHelper helper = DatabaseHelper.instance;

    final List<String> systems = await helper.getDistinctSystems();
    expect(systems, <String>['cardiovascular', 'respiratory']);

    final List<Map<String, Object?>> cardio =
        await helper.getUnitsBySystem('cardiovascular');
    expect(cardio.length, 2);

    // null = كل الوحدات مرتبة.
    final List<Map<String, Object?>> all =
        await helper.getUnitsBySystem(null);
    expect(all.length, 3);
  });
}
