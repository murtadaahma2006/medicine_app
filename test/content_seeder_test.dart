import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/content_seeder.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// محتوى هيكلي مصغر — يطابق الـ Schema v2.0.0 شكلياً (بلا محتوى طبي
/// حقيقي — مجرد تحقق أن خط الأنابيب يزرع الجداول الصحيحة).
final String miniLectureJson = '''
{
  "schema_version": "2.0.0",
  "lecture": {
    "id": "test-001",
    "title": "Pipeline Test Lecture",
    "module": "cardiology",
    "system": "cardiovascular",
    "source": {"file_name": "test.pdf", "page_count": 1},
    "order_index": 99
  },
  "concepts": [
    {
      "id": "test-001-c1",
      "lecture_id": "test-001",
      "title": "Test Concept",
      "sections": [
        {"heading": "H", "body_text": "${'x' * 100}"}
      ],
      "difficulty": "core",
      "order_index": 1
    }
  ],
  "flashcards": [
    {
      "id": "test-001-f1",
      "lecture_id": "test-001",
      "card_type": "basic",
      "front_text": "Test front question?",
      "back_text": "Test back answer, long enough."
    }
  ],
  "mcqs": [
    {
      "id": "test-001-q1",
      "lecture_id": "test-001",
      "question_stem": "Test stem long enough for validation rules ok?",
      "options": ["A", "B", "C"],
      "correct_index": 1,
      "explanation_ar": "شرح تجريبي طويل بما يكفي لاجتياز التحقق",
      "difficulty": "core",
      "clinical_vignette": false
    }
  ],
  "clinical_cases": [
    {
      "id": "test-001-case1",
      "lecture_id": "test-001",
      "title": "Test Case",
      "scenario": "${'s' * 50}",
      "vignette": {
        "age": 50, "sex": "male",
        "chief_complaint": "Test complaint",
        "history": "h",
        "exam": "e"
      },
      "steps": [
        {
          "id": "test-001-case1-s1",
          "prompt": "First test decision prompt?",
          "options": ["x", "y", "z"],
          "correct_index": 0,
          "explanation_ar": "شرح عربي للقرار"
        },
        {
          "id": "test-001-case1-s2",
          "prompt": "Second test decision prompt?",
          "options": ["x", "y", "z"],
          "correct_index": 2,
          "explanation_ar": "شرح عربي للقرار"
        }
      ],
      "debriefing_ar": "${'d' * 80}",
      "difficulty": "core",
      "order_index": 1
    }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('injectLectureFile يزرع كل الجداول الخمسة idempotently', () async {
    await DatabaseHelper.instance.openWith(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );

    // تسجيل أصل JSON الوهمي للـ rootBundle (بيان + المحاضرة).
    final Map<String, List<int>> assets = <String, List<int>>{
      'assets/content/MANIFEST.json':
          utf8.encode(jsonEncode(<String, Object?>{
        'files': <String>['assets/content/test-001.json'],
      })),
      'assets/content/test-001.json': utf8.encode(miniLectureJson),
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final String path = utf8.decode(message!.buffer.asUint8List());
        final List<int>? bytes = assets[path];
        if (bytes == null) return null;
        return ByteData.view(Uint8List.fromList(bytes).buffer);
      },
    );

    // (1) أول زرع — يجب أن تُزرع 5 أنواع (وحدة/شرح/بطاقة/سؤال/حالة+خطوتان).
    final int first = await ContentSeeder.seedAll();
    expect(first, greaterThan(0));

    final DatabaseHelper db = DatabaseHelper.instance;
    expect((await db.getAllUnits(module: 'cardiology')).length, 1);
    expect((await db.getConceptsForUnit('test-001')).length, 1);
    expect((await db.getFlashcardsForUnit('test-001')).length, 1);
    expect((await db.getMcqsForUnit('test-001')).length, 1);
    expect((await db.getCasesForUnit('test-001')).length, 1);
    expect((await db.getStepsForCase('test-001-case1')).length, 2);

    // (2) إعادة الزرع — idempotent: لا تكرار في الجداول.
    await ContentSeeder.seedAll();
    expect((await db.getAllUnits(module: 'cardiology')).length, 1);
    expect((await db.getFlashcardsForUnit('test-001')).length, 1);
    expect((await db.getStepsForCase('test-001-case1')).length, 2);
  });
}
