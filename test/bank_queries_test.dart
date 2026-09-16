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

    // null = كل الأجهزة.
    final List<Map<String, Object?>> all =
        await helper.getUnitsBySystem(null);
    expect(all.length, 3);
  });

  group('v20 — التخصص السريري (specialty)', () {
    /// زرع متعدد التخصصات: باطنية (موجودة عبر seed) + جراحة + نسائية.
    Future<void> seedSpecialties() async {
      await seed();
      final DatabaseHelper helper = DatabaseHelper.instance;

      // جراحة: محاضرتان (appendectomy + cholecystectomy).
      for (final (String, String, String, int) s in const <(String, String,
          String, int)>[
        ('surg-001', 'general_surgery', 'gastrointestinal', 0),
        ('surg-002', 'general_surgery', 'gastrointestinal', 1),
      ]) {
        await helper.insertUnit(<String, Object?>{
          'id': s.$1,
          'specialty': 'surgery',
          'module': s.$2,
          'system': s.$3,
          'title': 'Surgery Lecture ${s.$1}',
          'order_index': s.$4,
        });
        await helper.insertFlashcard(<String, Object?>{
          'id': '${s.$1}-f1',
          'unit_id': s.$1,
          'card_type': 'basic',
          'front_text': 'Surgery front of ${s.$1}',
          'back_text': 'Surgery back answer long enough',
        });
      }

      // نسائية: محاضرة واحدة.
      await helper.insertUnit(<String, Object?>{
        'id': 'obgyn-001',
        'specialty': 'obgyn',
        'module': 'gynecology',
        'system': 'endocrine',
        'title': 'ObGyn Lecture obgyn-001',
        'order_index': 0,
      });
      await helper.insertFlashcard(<String, Object?>{
        'id': 'obgyn-001-f1',
        'unit_id': 'obgyn-001',
        'card_type': 'basic',
        'front_text': 'ObGyn front question here',
        'back_text': 'ObGyn back answer long enough',
      });
    }

    test('الافتراض باطنية — seed بلا specialty يسند internal_medicine',
        () async {
      await seed();
      final DatabaseHelper helper = DatabaseHelper.instance;

      // seed() يزرع بلا specialty → عمود DEFAULT يسند الباطنية.
      final List<Map<String, Object?>> rows =
          await helper.getUnitsBySpecialty('internal_medicine');
      expect(rows.length, 3);
      expect(
        rows.every(
            (Map<String, Object?> r) => r['specialty'] == 'internal_medicine'),
        isTrue,
      );

      // لا جراحة ولا نسائية بعد.
      expect(await helper.getUnitsBySpecialty('surgery'), isEmpty);
      expect(await helper.getUnitsBySpecialty('obgyn'), isEmpty);
    });

    test('getUnitsBySpecialty + getDistinctSpecialties — عزل تام',
        () async {
      await seedSpecialties();
      final DatabaseHelper helper = DatabaseHelper.instance;

      // التخصصات الموجودة بترتيب العقد (باطنية أولاً).
      final List<String> specialties =
          await helper.getDistinctSpecialties();
      expect(specialties,
          <String>['internal_medicine', 'surgery', 'obgyn']);

      // كل تخصص يرى محاضراته فقط.
      expect((await helper.getUnitsBySpecialty('internal_medicine')).length,
          3);
      expect((await helper.getUnitsBySpecialty('surgery')).length, 2);
      expect((await helper.getUnitsBySpecialty('obgyn')).length, 1);

      // فلترة الأجهزة داخل تخصص واحد: gastrointestinal فيه محاضرتا
      // الجراحة (seed الأصلي باطنياً في القلب والتنفس فقط) — بلا
      // وسيط يظهر جهاز الهضم عبر كل التخصصات.
      expect(
        (await helper.getUnitsBySystem('gastrointestinal')).length,
        2,
        reason: 'بلا وسيط: جهاز الهضم من كل التخصصات (محاضرتا الجراحة)',
      );
      expect(
        (await helper.getUnitsBySystem('gastrointestinal',
            specialty: 'surgery'))
            .length,
        2,
      );
      expect(
        (await helper.getUnitsBySystem('gastrointestinal',
            specialty: 'internal_medicine'))
            .length,
        0,
        reason: 'الباطنية بلا محاضرات هضمية في هذا الزرع',
      );
      expect(
        await helper.getDistinctSystems(specialty: 'surgery'),
        <String>['gastrointestinal'],
      );
    });

    test('بنوك المكتبة تُفلتر بالتخصص — بطاقات', () async {
      await seedSpecialties();
      final DatabaseHelper helper = DatabaseHelper.instance;

      // بلا فلتر: كل البطاقات (6 باطنية + 2 جراحة + 1 نسائية).
      final List<Map<String, Object?>> all = await helper.getFlashcards();
      expect(all.length, 9);

      // فلتر الجراحة وحدها.
      final List<Map<String, Object?>> surgery =
          await helper.getFlashcards(specialty: 'surgery');
      expect(surgery.length, 2);
      expect(
        surgery.every((Map<String, Object?> f) =>
            f['unit_id']!.toString().startsWith('surg')),
        isTrue,
      );

      // دمج specialty + system (نسائية داخل endocrine).
      final List<Map<String, Object?>> obgynEndocrine =
          await helper.getFlashcards(
              specialty: 'obgyn', system: 'endocrine');
      expect(obgynEndocrine.length, 1);
    });

    test('بنوك المكتبة تُفلتر بالتخصص — أسئلة وحالات', () async {
      await seedSpecialties();
      final DatabaseHelper helper = DatabaseHelper.instance;

      // MCQ: الباطنية فقط (الأسئلة زُرعت في seed() لها وحدها).
      final List<Map<String, Object?>> imMcqs =
          await helper.getMcqs(specialty: 'internal_medicine');
      expect(imMcqs.length, 6);
      expect(await helper.getMcqs(specialty: 'surgery'), isEmpty);

      // الحالات: نفس العزل.
      expect(
        (await helper.getCases(specialty: 'internal_medicine')).length,
        3,
      );
      expect(await helper.getCases(specialty: 'obgyn'), isEmpty);
    });
  });
}
