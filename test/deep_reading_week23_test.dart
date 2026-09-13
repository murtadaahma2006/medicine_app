import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Future<DatabaseHelper> fresh() async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
    return helper;
  }

  /// بنية محاضرة مصغّرة كاملة (وحدة + شرح 3 أقسام + MCQ مرتبط).
  Future<void> seedMiniLecture(DatabaseHelper helper) async {
    await helper.insertUnit(<String, Object?>{
      'id': 'u1',
      'module': 'cardiology',
      'system': 'cardiovascular',
      'title': 'Heart Failure',
      'order_index': 0,
    });
    await helper.insertConcept(<String, Object?>{
      'id': 'c1',
      'unit_id': 'u1',
      'title': 'Pathophysiology',
      'sections_json': '[{"heading":"H1","body_text":"${'x' * 100}"},'
          '{"heading":"H2","body_text":"${'y' * 100}"}]',
      'order_index': 0,
    });
    await helper.insertMcq(<String, Object?>{
      'id': 'q1',
      'unit_id': 'u1',
      'concept_id': 'c1',
      'question_stem': 'What is the main pathophysiology of heart failure?',
      'options_json': '["a","b","c"]',
      'correct_index': 1,
      'explanation_ar': 'شرح وافٍ للإجابة الصحيحة والبدائل الخاطئة.',
      'difficulty': 'core',
      'clinical_vignette': 0,
    });
  }

  group('المخطط v16 (أعمدة العقد v2.1 + البوابة)', () {
    test('onCreate ينشئ الأعمدة الجديدة', () async {
      final DatabaseHelper helper = await fresh();

      // أعمدة mcq_bank الجديدة.
      final List<Map<String, Object?>> mcqCols =
          await helper.rawQueryParameterized(
        'PRAGMA table_info(${DatabaseHelper.tableMcqBank})',
      );
      final Set<String> mcqNames = <String>{
        for (final Map<String, Object?> c in mcqCols)
          c['name']! as String,
      };
      expect(mcqNames.contains('hints_json'), isTrue);
      expect(mcqNames.contains('focus_sections_json'), isTrue);

      // أعمدة flashcards/clinical_case_steps/concept_reads.
      final List<Map<String, Object?>> cardCols =
          await helper.rawQueryParameterized(
        'PRAGMA table_info(${DatabaseHelper.tableFlashcards})',
      );
      expect(
        <String>{
          for (final Map<String, Object?> c in cardCols) c['name']! as String,
        }.contains('is_vivid'),
        isTrue,
      );

      final List<Map<String, Object?>> stepCols =
          await helper.rawQueryParameterized(
        'PRAGMA table_info(${DatabaseHelper.tableClinicalCaseSteps})',
      );
      expect(
        <String>{
          for (final Map<String, Object?> c in stepCols) c['name']! as String,
        }.contains('hints_json'),
        isTrue,
      );

      final List<Map<String, Object?>> readCols =
          await helper.rawQueryParameterized(
        'PRAGMA table_info(${DatabaseHelper.tableConceptReads})',
      );
      expect(
        <String>{
          for (final Map<String, Object?> c in readCols) c['name']! as String,
        }.contains('gate_passed'),
        isTrue,
      );
    });

    test('الترحيل v15 → v16 يضيف الأعمدة فوق قاعدة قائمة بلا فقد بيانات',
        () async {
      // بناء قاعدة v15 يدوياً بجدول units فقط + بيانات.
      final sqflite.DatabaseFactory ffi = databaseFactoryFfi;
      final String path =
          '${await ffi.getDatabasesPath()}\\test_v15_migration.db';
      await ffi.deleteDatabase(path);

      final sqflite.Database dbV15 = await ffi.openDatabase(
        path,
        options: sqflite.OpenDatabaseOptions(
          version: 15,
          onCreate: (sqflite.Database db, int v) async {
            await db.execute(
              'CREATE TABLE ${DatabaseHelper.tableUnits} ('
              'id TEXT PRIMARY KEY, module TEXT NOT NULL, '
              'system TEXT NOT NULL, title TEXT NOT NULL, '
              'description_ar TEXT, order_index INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE ${DatabaseHelper.tableMcqBank} ('
              'id TEXT PRIMARY KEY, unit_id TEXT NOT NULL, concept_id TEXT, '
              'question_stem TEXT NOT NULL, options_json TEXT NOT NULL, '
              'correct_index INTEGER NOT NULL, explanation_ar TEXT NOT NULL, '
              "difficulty TEXT NOT NULL DEFAULT 'core', "
              'clinical_vignette INTEGER NOT NULL DEFAULT 0)',
            );
            await db.insert(DatabaseHelper.tableUnits, <String, Object?>{
              'id': 'u1',
              'module': 'cardiology',
              'system': 'cardiovascular',
              'title': 'Heart Failure',
              'order_index': 0,
            });
          },
        ),
      );
      await dbV15.close();

      // فتح عبر v16 — الترحيل يضيف الأعمدة.
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(ffi, path);

      final List<Map<String, Object?>> mcqCols =
          await helper.rawQueryParameterized(
        'PRAGMA table_info(${DatabaseHelper.tableMcqBank})',
      );
      final Set<String> names = <String>{
        for (final Map<String, Object?> c in mcqCols) c['name']! as String,
      };
      expect(names.contains('hints_json'), isTrue);
      expect(names.contains('focus_sections_json'), isTrue);

      // البيانات القائمة محفوظة.
      final List<Map<String, Object?>> units = await helper.getAllUnits();
      expect(units.length, 1);
      expect(units.first['title'], 'Heart Failure');

      await ffi.deleteDatabase(path);
    });
  });

  group('بوابة الشرح (Reverse Interrogation)', () {
    test('getGateMcqForConcept يجلب أول MCQ مرتبط بالشرح', () async {
      final DatabaseHelper helper = await fresh();
      await seedMiniLecture(helper);

      final Map<String, Object?>? gate =
          await helper.getGateMcqForConcept('c1');
      expect(gate, isNotNull);
      expect(gate!['id'], 'q1');
      expect(gate['concept_id'], 'c1');

      // شرح بلا أسئلة → null (fallback المسح المسبق).
      expect(await helper.getGateMcqForConcept('ghost'), isNull);
    });

    test('getMcqsForConcept يجلب كل أسئلة الشرح (نقاط الاعتراض)', () async {
      final DatabaseHelper helper = await fresh();
      await seedMiniLecture(helper);
      await helper.insertMcq(<String, Object?>{
        'id': 'q2',
        'unit_id': 'u1',
        'concept_id': 'c1',
        'question_stem': 'Another question about heart failure?',
        'options_json': '["a","b","c"]',
        'correct_index': 0,
        'explanation_ar': 'شرح وافٍ آخر للسؤال الثاني في البنك.',
        'difficulty': 'core',
        'clinical_vignette': 0,
      });

      final List<Map<String, Object?>> mcqs =
          await helper.getMcqsForConcept('c1');
      expect(mcqs.length, 2);
    });

    test('markGatePassed وسم مجتاز ثم conceptGatePassed يقرؤه', () async {
      final DatabaseHelper helper = await fresh();
      await seedMiniLecture(helper);

      expect(await helper.conceptGatePassed('c1'), isFalse);
      await helper.markGatePassed('c1');
      expect(await helper.conceptGatePassed('c1'), isTrue);

      // وسم بلا سجل قراءة سابق ينشئ صفاً (gate_passed=1, read_count=0).
      final Map<String, Object?>? row = await helper.getConceptRead('c1');
      expect(row?['gate_passed'], 1);
      expect(row?['read_count'], 0);
    });
  });

  group('دقائق التركيز (مقياس الشمال)', () {
    test('focusedMinutesRecent يجمع أياماً متعددة', () async {
      final DatabaseHelper helper = await fresh();

      // جلسات عبر يومين.
      final String today =
          DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final String yesterday = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);

      final List<Map<String, Object?>> rows = <Map<String, Object?>>[
        <String, Object?>{
          'kind': 'reading',
          'ref_id': 'u1',
          'started_at': '$today"T10:00:00Z"',
          'ended_at': '$today"T10:05:00Z"',
          'focused_seconds': 300,
        },
        <String, Object?>{
          'kind': 'reading',
          'ref_id': 'u2',
          'started_at': '$today"T12:00:00Z"',
          'ended_at': '$today"T12:02:00Z"',
          'focused_seconds': 120,
        },
        <String, Object?>{
          'kind': 'flashcards',
          'ref_id': 'u1',
          'started_at': '$yesterday"T09:00:00Z"',
          'ended_at': '$yesterday"T09:07:00Z"',
          'focused_seconds': 420,
        },
      ];
      for (final Map<String, Object?> row in rows) {
        await helper.rawQueryParameterized(
          'INSERT INTO ${DatabaseHelper.tableFlowSessions} '
          '(kind, ref_id, started_at, ended_at, focused_seconds) '
          'VALUES (?, ?, ?, ?, ?)',
          <Object?>[
            row['kind'],
            row['ref_id'],
            row['started_at'],
            row['ended_at'],
            row['focused_seconds'],
          ],
        );
      }

      final List<MapEntry<String, int>> recent =
          await helper.focusedMinutesRecent(7);
      final Map<String, int> byDay = <String, int>{
        for (final MapEntry<String, int> e in recent) e.key: e.value,
      };
      expect(byDay[today], 7); // (300+120)/60.
      expect(byDay[yesterday], 7); // 420/60.
    });
  });

  group('كتل القراءة (غوصة متداخلة الأجهزة)', () {
    test('getUnfinishedConcepts يستبعد المكتمل ويجلب الباقي', () async {
      final DatabaseHelper helper = await fresh();
      await seedMiniLecture(helper);
      // شرح ثانٍ من جهاز آخر.
      await helper.insertUnit(<String, Object?>{
        'id': 'u2',
        'module': 'nephrology',
        'system': 'renal',
        'title': 'AKI',
        'order_index': 1,
      });
      await helper.insertConcept(<String, Object?>{
        'id': 'c2',
        'unit_id': 'u2',
        'title': 'AKI Stages',
        'sections_json': '[{"heading":"H","body_text":"${'z' * 100}"}]',
        'order_index': 0,
      });

      // قبل أي قراءة: كلاهما غير مكتمل.
      List<Map<String, Object?>> unfinished =
          await helper.getUnfinishedConcepts(limit: 6);
      expect(unfinished.length, 2);

      // أكمل الأول → يختفي.
      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      unfinished = await helper.getUnfinishedConcepts(limit: 6);
      expect(unfinished.length, 1);
      expect(unfinished.first['id'], 'c2');
    });

    test('averageSectionDwellSeconds يحسب من sections_json', () async {
      final DatabaseHelper helper = await fresh();
      await seedMiniLecture(helper);

      // بلا سجلات → 0.
      expect(await helper.averageSectionDwellSeconds(), 0);

      // سجل بقسمين 10s و 20s → المتوسط 15.
      await helper.recordConceptRead(
        conceptId: 'c1',
        completed: true,
        sectionDwellSeconds: <String, int>{'0': 10, '1': 20},
      );
      expect(await helper.averageSectionDwellSeconds(), 15);
    });
  });
}
