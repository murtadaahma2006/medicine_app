import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/content/lecture_import_service.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// محاضرة مصغرة صالحة — نفس عينة الـ seeder test.
Map<String, Object?> _validLecture({String id = 'imp-001'}) {
  return <String, Object?>{
    'schema_version': '2.0.0',
    'lecture': <String, Object?>{
      'id': id,
      'title': 'Import Test Lecture',
      'module': 'pulmonology',
      'system': 'respiratory',
      'source': <String, Object?>{'file_name': 'test.pdf', 'page_count': 2},
      'order_index': 50,
    },
    'concepts': <dynamic>[
      <String, Object?>{
        'id': '$id-c1',
        'lecture_id': id,
        'title': 'Concept One',
        'sections': <dynamic>[
          <String, Object?>{
            'heading': 'Heading',
            'body_text': 'x' * 100,
          }
        ],
        'difficulty': 'core',
        'order_index': 1,
      },
    ],
    'flashcards': <dynamic>[
      for (int i = 1; i <= 3; i++)
        <String, Object?>{
          'id': '$id-f$i',
          'lecture_id': id,
          'card_type': 'basic',
          'front_text': 'Front question number $i?',
          'back_text': 'Back answer number $i, long enough.',
        },
    ],
    'mcqs': <dynamic>[
      for (int i = 1; i <= 3; i++)
        <String, Object?>{
          'id': '$id-q$i',
          'lecture_id': id,
          'question_stem': 'Stem number $i long enough for rules ok?',
          'options': <String>['A', 'B', 'C'],
          'correct_index': 1,
          'explanation_ar': 'شرح عربي طويل بما يكفي لاجتياز التحقق',
          'difficulty': 'core',
          'clinical_vignette': false,
        },
    ],
    'clinical_cases': <dynamic>[
      <String, Object?>{
        'id': '$id-case1',
        'lecture_id': id,
        'title': 'Case One',
        'scenario': 's' * 50,
        'vignette': <String, Object?>{
          'age': 60,
          'sex': 'male',
          'chief_complaint': 'Cough',
          'history': 'h',
          'exam': 'e',
        },
        'steps': <dynamic>[
          <String, Object?>{
            'id': '$id-case1-s1',
            'prompt': 'First decision prompt?',
            'options': <String>['x', 'y', 'z'],
            'correct_index': 0,
            'explanation_ar': 'شرح عربي طويل بما يكفي لهذا القرار',
          },
          <String, Object?>{
            'id': '$id-case1-s2',
            'prompt': 'Second decision prompt?',
            'options': <String>['x', 'y', 'z'],
            'correct_index': 2,
            'explanation_ar': 'شرح عربي طويل بما يكفي لهذا القرار',
          },
        ],
        'debriefing_ar': 'd' * 80,
        'difficulty': 'core',
        'order_index': 1,
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('validateMap يقبل محاضرة صالحة ويرفض كل الانتهاكات', () {
    // صالح.
    expect(LectureImportService.validateMap(_validLecture()), isNull);

    // إصدار مخطط خاطئ.
    final Map<String, Object?> badVersion = _validLecture()
      ..['schema_version'] = '1.0.0';
    expect(
      LectureImportService.validateMap(badVersion),
      contains('2.0.0'),
    );

    // تخصص غير معروف.
    final Map<String, Object?> badModule = _validLecture();
    (badModule['lecture']! as Map<String, Object?>)['module'] = 'dentistry';
    expect(
      LectureImportService.validateMap(badModule),
      contains('module'),
    );

    // بطاقات أقل من 3.
    final Map<String, Object?> fewCards = _validLecture()
      ..['flashcards'] = <dynamic>[];
    expect(
      LectureImportService.validateMap(fewCards),
      contains('البطاقات'),
    );

    // correct_index خارج النطاق.
    final Map<String, Object?> badIndex = _validLecture();
    (badIndex['mcqs']! as List<dynamic>).first['correct_index'] = 5;
    expect(
      LectureImportService.validateMap(badIndex),
      contains('correct_index'),
    );

    // معرف مكرر.
    final Map<String, Object?> dupId = _validLecture();
    (dupId['mcqs']! as List<dynamic>)[1]['id'] =
        (dupId['mcqs']! as List<dynamic>)[0]['id'];
    expect(
      LectureImportService.validateMap(dupId),
      contains('مكرر'),
    );

    // section نصه أقل من 100 حرف.
    final Map<String, Object?> shortBody = _validLecture();
    ((shortBody['concepts']! as List<dynamic>).first['sections']!
            as List<dynamic>)
        .first['body_text'] = 'short';
    expect(
      LectureImportService.validateMap(shortBody),
      contains('100'),
    );
  });

  test('importFile يزرع المحاضرة ويكون idempotent', () async {
    await DatabaseHelper.instance.openWith(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );

    // استيراد أول — نجاح.
    final LectureImportResult first =
        await LectureImportService.importFile(
      await _writeTemp(_validLecture()),
    );
    expect(first.ok, isTrue);
    expect(first.skipped, isFalse);
    expect(first.insertedRows,
        1 + 1 + 3 + 3 + 1 + 2); // وحدة+شرح+بطاقات+أسئلة+حالة+خطوتان

    final DatabaseHelper db = DatabaseHelper.instance;
    expect((await db.getConceptsForUnit('imp-001')).length, 1);
    expect((await db.getFlashcardsForUnit('imp-001')).length, 3);
    expect((await db.getMcqsForUnit('imp-001')).length, 3);
    expect((await db.getCasesForUnit('imp-001')).length, 1);
    expect((await db.getStepsForCase('imp-001-case1')).length, 2);

    // استيراد ثانٍ لنفس الملف — تخطٍ مهذب بلا تكرار.
    final LectureImportResult second =
        await LectureImportService.importFile(
      await _writeTemp(_validLecture()),
    );
    expect(second.ok, isTrue);
    expect(second.skipped, isTrue);
    expect((await db.getFlashcardsForUnit('imp-001')).length, 3);
  });

  test('importFile يرفض ملفاً لا يطابق العقد', () async {
    await DatabaseHelper.instance.openWith(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );

    final Map<String, Object?> bad = _validLecture(id: 'imp-002')
      ..['schema_version'] = '0.0.9';
    final LectureImportResult result =
        await LectureImportService.importFile(await _writeTemp(bad));
    expect(result.ok, isFalse);
    expect(result.messageAr, contains('2.0.0'));

    // لا شيء زُرع.
    final DatabaseHelper db = DatabaseHelper.instance;
    expect((await db.getCasesForUnit('imp-002')).length, 0);
  });

  test('عقد v2.1: الحقول الاختيارية الجديدة تُقبل وتُزرع في أعمدتها',
      () async {
    await DatabaseHelper.instance.openWith(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );

    final Map<String, Object?> lecture = _validLecture(id: 'imp-v21');

    // focus_sections + hints على MCQ.
    (lecture['mcqs']! as List<dynamic>)[0]['focus_sections'] = <int>[0];
    (lecture['mcqs']! as List<dynamic>)[0]['hints'] = <String>['hint one'];
    // is_vivid على بطاقة.
    (lecture['flashcards']! as List<dynamic>)[0]['is_vivid'] = true;
    // check مدمج على قسم.
    ((lecture['concepts']! as List<dynamic>).first['sections']!
            as List<dynamic>)
        .first['check'] = <String, Object?>{
      'prompt': 'Quick embedded check?',
      'options': <String>['yes', 'no'],
      'correct_index': 0,
      'explanation_ar': 'شرح سريع كافٍ',
    };

    // صالح مع كل الحقول الجديدة.
    expect(LectureImportService.validateMap(lecture), isNull);

    final LectureImportResult result =
        await LectureImportService.importFile(await _writeTemp(lecture));
    expect(result.ok, isTrue);

    // الزرع كتب الأعمدة الجديدة.
    final DatabaseHelper db = DatabaseHelper.instance;
    final Map<String, Object?>? mcq = await db.getMcqById('imp-v21-q1');
    expect(mcq?['focus_sections_json'], '[0]');
    expect(mcq?['hints_json'], contains('hint one'));

    final Map<String, Object?>? card = await db.getFlashcardById('imp-v21-f1');
    expect(card?['is_vivid'], 1);
  });

  test('عقد v2.1: الانتهاكات في الحقول الاختيارية تُرفض', () {
    // focus_sections بعنصر غير رقمي.
    final Map<String, Object?> badFocus = _validLecture(id: 'v21-bad');
    (badFocus['mcqs']! as List<dynamic>)[0]['focus_sections'] = <String>['x'];
    expect(
      LectureImportService.validateMap(badFocus),
      contains('focus_sections'),
    );

    // hints بعنصر قصير.
    final Map<String, Object?> badHint = _validLecture(id: 'v21-bad');
    (badHint['mcqs']! as List<dynamic>)[0]['hints'] = <String>['ab'];
    expect(
      LectureImportService.validateMap(badHint),
      contains('hints'),
    );

    // is_vivid غير bool.
    final Map<String, Object?> badVivid = _validLecture(id: 'v21-bad');
    (badVivid['flashcards']! as List<dynamic>)[0]['is_vivid'] = 'yes';
    expect(
      LectureImportService.validateMap(badVivid),
      contains('is_vivid'),
    );

    // check بcorrect_index خارج النطاق.
    final Map<String, Object?> badCheck = _validLecture(id: 'v21-bad');
    (((badCheck['concepts']! as List<dynamic>).first['sections']!
                as List<dynamic>)
            .first as Map<String, Object?>)['check'] = <String, Object?>{
      'prompt': 'Quick embedded check?',
      'options': <String>['yes', 'no'],
      'correct_index': 5,
    };
    expect(
      LectureImportService.validateMap(badCheck),
      contains('check.correct_index'),
    );

    // الملفات القديمة (بلا حقول v2.1) تظل صالحة — التوافقية الخلفية.
    expect(LectureImportService.validateMap(_validLecture()), isNull);
  });
}

/// يكتب JSON إلى ملف مؤقت ويعيد مساره.
Future<String> _writeTemp(Map<String, Object?> data) async {
  final Directory dir = await Directory.systemTemp.createTemp('lecture_imp');
  final File file = File(
    '${dir.path}${Platform.pathSeparator}lecture.json',
  );
  await file.writeAsString(jsonEncode(data));
  return file.path;
}
