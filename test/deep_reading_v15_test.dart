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

  group('المخطط v15 (جداول محرّك القراءة العميقة)', () {
    test('onCreate ينشئ الجداول الثلاثة الجديدة فارغة', () async {
      final DatabaseHelper helper = await fresh();

      final List<String> newTables = <String>[
        DatabaseHelper.tableConceptReads,
        DatabaseHelper.tableFlowSessions,
        DatabaseHelper.tableConfidenceLog,
      ];
      final List<Map<String, Object?>> rows =
          await helper.rawQueryParameterized(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final Set<String> created =
          rows.map((Map<String, Object?> r) => r['name']! as String).toSet();
      for (final String t in newTables) {
        expect(created.contains(t), isTrue, reason: 'الجدول $t يجب أن يُنشأ');
        final int count = await helper.rawCount('SELECT COUNT(*) FROM $t');
        expect(count, 0, reason: 'الجدول $t يجب أن يبدأ فارغاً');
      }
    });

    test('الترحيل v14 → v15 يضيف الجداول فوق قاعدة قائمة', () async {
      // بناء قاعدة v14 يدوياً (فتح مباشر بالإصدار القديم).
      final sqflite.DatabaseFactory ffi = databaseFactoryFfi;
      final String path =
          '${await ffi.getDatabasesPath()}\\test_v14_migration.db';
      await ffi.deleteDatabase(path);

      final sqflite.Database dbV14 = await ffi.openDatabase(
        path,
        options: sqflite.OpenDatabaseOptions(
          version: 14,
          onCreate: (sqflite.Database db, int v) async {
            // حاوٍ مصغّر لجدول قائم + بيانات.
            await db.execute(
              'CREATE TABLE ${DatabaseHelper.tableUnits} ('
              'id TEXT PRIMARY KEY, module TEXT NOT NULL, '
              'system TEXT NOT NULL, title TEXT NOT NULL, '
              'description_ar TEXT, order_index INTEGER NOT NULL DEFAULT 0)',
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
      await dbV14.close();

      // فتحها عبر DatabaseHelper (v15) — يجب أن يرحّل بلا فقد البيانات.
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(ffi, path);

      final List<String> v15Tables = <String>[
        DatabaseHelper.tableConceptReads,
        DatabaseHelper.tableFlowSessions,
        DatabaseHelper.tableConfidenceLog,
      ];
      for (final String t in v15Tables) {
        final int count = await helper.rawCount('SELECT COUNT(*) FROM $t');
        expect(count, 0, reason: 'الجدول الجديد $t فارغ بعد الترحيل');
      }
      // الجدول القائم محفوظ ببياناته.
      final List<Map<String, Object?>> units = await helper.getAllUnits();
      expect(units.length, 1);
      expect(units.first['title'], 'Heart Failure');

      await ffi.deleteDatabase(path);
    });
  });

  group('concept_reads — سجل قراءة الشروحات', () {
    test('recordConceptRead: أول قراءة ترجع 0 ثم تتزايد', () async {
      final DatabaseHelper helper = await fresh();
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
        'sections_json': '[]',
        'order_index': 0,
      });

      // أول قراءة — previousReads = 0 (مراسي مفعّلة في الواجهة).
      final int first = await helper.recordConceptRead(
        conceptId: 'c1',
        completed: true,
        sectionDwellSeconds: <String, int>{'0': 42, '1': 17},
      );
      expect(first, 0);

      // ثاني قراءة — previousReads = 1.
      final int second = await helper.recordConceptRead(
        conceptId: 'c1',
        completed: true,
      );
      expect(second, 1);

      // العدادات والسجل.
      expect(await helper.conceptReadCount('c1'), 2);
      final Map<String, Object?>? row = await helper.getConceptRead('c1');
      expect(row?['completed'], 1);
    });

    test('إكمال جزئي ثم كامل → completed تبقى 1 (لا تراجع)', () async {
      final DatabaseHelper helper = await fresh();
      await helper.insertUnit(<String, Object?>{
        'id': 'u1',
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'HF',
        'order_index': 0,
      });
      await helper.insertConcept(<String, Object?>{
        'id': 'c1',
        'unit_id': 'u1',
        'title': 'T',
        'sections_json': '[]',
        'order_index': 0,
      });

      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      await helper.recordConceptRead(conceptId: 'c1', completed: false);
      final Map<String, Object?>? row = await helper.getConceptRead('c1');
      expect(row?['completed'], 1, reason: 'الإتمام لا يتراجع');
      expect(row?['read_count'], 2);
    });

    test('مفهوم غير مقروء → readCount = 0', () async {
      final DatabaseHelper helper = await fresh();
      expect(await helper.conceptReadCount('never-read'), 0);
      expect(await helper.getConceptRead('never-read'), isNull);
    });
  });

  group('flow_sessions — دقائق التركيز', () {
    test('دورة كاملة: فتح ← إغلاق ← مجموع اليوم', () async {
      final DatabaseHelper helper = await fresh();

      final int s1 = await helper.startFlowSession(kind: 'reading', refId: 'u1');
      final int s2 =
          await helper.startFlowSession(kind: 'flashcards', refId: 'f1');
      expect(s1, greaterThan(0));
      expect(s2, greaterThan(s1));

      await helper.endFlowSession(s1, 300);
      await helper.endFlowSession(s2, 120);

      final String today =
          DateTime.now().toUtc().toIso8601String().substring(0, 10);
      expect(await helper.focusedSecondsOnDay(today), 420);
    });

    test('جلسة مفتوحة (بلا إغلاق) لا تُحسب في مجموع اليوم', () async {
      final DatabaseHelper helper = await fresh();
      await helper.startFlowSession(kind: 'mcq');

      final String today =
          DateTime.now().toUtc().toIso8601String().substring(0, 10);
      expect(await helper.focusedSecondsOnDay(today), 0);
    });

    test('نوع جلسة غير مسموح يُرفض بقيد CHECK', () async {
      final DatabaseHelper helper = await fresh();
      expect(
        () => helper.startFlowSession(kind: 'invalid'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('confidence_log — قبلة الثقة', () {
    test('logConfidence يسجّل الإجابة بدرجة الثقة', () async {
      final DatabaseHelper helper = await fresh();

      await helper.logConfidence(
        questionId: 'q1',
        confidence: 2, // متأكد جداً
        wasCorrect: false, // وأخطأ — خطأ عالي الثقة (ذهب التصحيح المفرط)
      );
      await helper.logConfidence(
        questionId: 'q1',
        confidence: 0,
        wasCorrect: true,
      );

      final List<Map<String, Object?>> rows =
          await helper.rawQueryParameterized(
        'SELECT * FROM ${DatabaseHelper.tableConfidenceLog} '
        'ORDER BY id',
      );
      expect(rows.length, 2);
      expect(rows.first['confidence'], 2);
      expect(rows.first['was_correct'], 0);
      expect(rows.last['confidence'], 0);
      expect(rows.last['was_correct'], 1);
    });

    test('درجة ثقة خارج النطاق تُقصّ إلى 0..2', () async {
      final DatabaseHelper helper = await fresh();
      await helper.logConfidence(
        questionId: 'q9',
        confidence: 7, // خارج النطاق → يقص إلى 2.
        wasCorrect: true,
      );
      final List<Map<String, Object?>> rows =
          await helper.rawQueryParameterized(
        'SELECT confidence FROM ${DatabaseHelper.tableConfidenceLog}',
      );
      expect(rows.first['confidence'], 2);
    });
  });

  group('deleteLectureData ينظف جداول v15', () {
    test('حذف المحاضرة يمسح concept_reads/confidence_log/flow_sessions',
        () async {
      final DatabaseHelper helper = await fresh();
      await helper.insertUnit(<String, Object?>{
        'id': 'u1',
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'HF',
        'order_index': 0,
      });
      await helper.insertConcept(<String, Object?>{
        'id': 'c1',
        'unit_id': 'u1',
        'title': 'T',
        'sections_json': '[]',
        'order_index': 0,
      });
      await helper.insertMcq(<String, Object?>{
        'id': 'q1',
        'unit_id': 'u1',
        'question_stem': 'stem?',
        'options_json': '["a","b","c"]',
        'correct_index': 0,
        'explanation_ar': 'شرح',
        'difficulty': 'core',
        'clinical_vignette': 0,
      });

      // تعبئة جداول v15.
      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      await helper.logConfidence(questionId: 'q1', confidence: 2, wasCorrect: false);
      final int s =
          await helper.startFlowSession(kind: 'reading', refId: 'u1');
      await helper.endFlowSession(s, 100);

      // حذف المحاضرة.
      await helper.deleteLectureData('u1');

      expect(
        await helper.rawCount(
            'SELECT COUNT(*) FROM ${DatabaseHelper.tableConceptReads}'),
        0,
        reason: 'concept_reads يجب أن يُنظف',
      );
      expect(
        await helper.rawCount(
            'SELECT COUNT(*) FROM ${DatabaseHelper.tableConfidenceLog}'),
        0,
        reason: 'confidence_log يجب أن يُنظف',
      );
      expect(
        await helper.rawCount(
            'SELECT COUNT(*) FROM ${DatabaseHelper.tableFlowSessions} '
            "WHERE ref_id = 'u1'"),
        0,
        reason: 'flow_sessions المرتبطة تُحذف',
      );
    });
  });

  group('jsonEncodeSorted — خرج حتمي', () {
    test('المفاتيح مرتبة رقمياً (كسلاسل) بغض النظر عن ترتيب الإدخال', () {
      final String a = DatabaseHelper.jsonEncodeSorted(<String, int>{
        '2': 5,
        '0': 10,
        '10': 3,
      });
      final String b = DatabaseHelper.jsonEncodeSorted(<String, int>{
        '10': 3,
        '2': 5,
        '0': 10,
      });
      expect(a, b);
      expect(a, '{"0":10,"10":3,"2":5}');
    });
  });
}
