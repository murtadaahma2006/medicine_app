import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/agent/agent_runtime.dart';
import 'package:medicine_app/src/core/agent/ai_gateway.dart';
import 'package:medicine_app/src/core/agent/models/models.dart';
import 'package:medicine_app/src/core/agent/task_repository.dart';
import 'package:medicine_app/src/core/content/lecture_import_service.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('E2E Integration Test: Content Factory Pipeline', () {
    late DatabaseHelper helper;
    late TaskRepository repository;
    late AgentRuntime runtime;
    late String dummyPdfPath;

    setUp(() async {
      helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
      repository = TaskRepository(dbHelper: helper);

      final tempDir = Directory.systemTemp.createTempSync('e2e_test');
      final dummyPdf = File('${tempDir.path}/dummy_lecture.pdf');
      dummyPdf.writeAsBytesSync([1, 2, 3, 4]);
      dummyPdfPath = dummyPdf.path;

      final mockGateway = AiGateway(
        apiCallHandler: (systemPrompt, userMessage, {filePath, fileBytes, provider}) async {
          final dummyJson = {
            "schema_version": "2.0.0",
            "lecture": {
              "id": "unit_e2e_1",
              "specialty": "internal_medicine",
              "module": "cardiology",
              "system": "cardiovascular",
              "title": "Dummy E2E Lecture",
              "summary_ar": "الملخص العربي",
              "order_index": 1,
              "golden_tip": "Golden tip here",
              "source": {
                 "file_name": "dummy_lecture.pdf",
                 "page_count": 10
              }
            },
            "concepts": [
              {
                "id": "concept_1",
                "lecture_id": "unit_e2e_1",
                "title": "Concept 1",
                "summary_ar": "شرح",
                "difficulty": "core",
                "order_index": 1,
                "sections": [
                  {
                    "heading": "Heading 1",
                    "body_text": "This text must be at least one hundred characters long. 1234567890 1234567890 1234567890 1234567890 1234567890 1234567890."
                  }
                ]
              }
            ],
            "flashcards": [
              {
                "id": "fc_1",
                "lecture_id": "unit_e2e_1",
                "concept_id": "concept_1",
                "card_type": "basic",
                "front_text": "Front 1 text long enough",
                "back_text": "Back 1 text long enough",
                "mnemonic_ar": "Mnemonic",
                "explanation_ar": "Explanation is required here.",
                "is_vivid": true
              },
              {
                "id": "fc_2",
                "lecture_id": "unit_e2e_1",
                "concept_id": "concept_1",
                "card_type": "basic",
                "front_text": "Front 2 text long enough",
                "back_text": "Back 2 text long enough",
                "mnemonic_ar": "Mnemonic",
                "explanation_ar": "Explanation is required here.",
                "is_vivid": false
              },
              {
                "id": "fc_3",
                "lecture_id": "unit_e2e_1",
                "concept_id": "concept_1",
                "card_type": "basic",
                "front_text": "Front 3 text long enough",
                "back_text": "Back 3 text long enough",
                "mnemonic_ar": "Mnemonic",
                "explanation_ar": "Explanation is required here.",
                "is_vivid": false
              }
            ],
            "mcqs": [
              {
                "id": "mcq_1",
                "lecture_id": "unit_e2e_1",
                "concept_id": "concept_1",
                "question_stem": "This is a question stem that is definitely longer than 30 characters.",
                "options": ["A", "B", "C", "D"],
                "correct_index": 0,
                "explanation_ar": "Explanation must be long enough.",
                "difficulty": "core",
                "clinical_vignette": false
              },
              {
                "id": "mcq_2",
                "lecture_id": "unit_e2e_1",
                "concept_id": "concept_1",
                "question_stem": "This is a question stem 2 that is definitely longer than 30 characters.",
                "options": ["A", "B", "C", "D"],
                "correct_index": 1,
                "explanation_ar": "Explanation must be long enough.",
                "difficulty": "core",
                "clinical_vignette": false
              },
              {
                "id": "mcq_3",
                "lecture_id": "unit_e2e_1",
                "concept_id": "concept_1",
                "question_stem": "This is a question stem 3 that is definitely longer than 30 characters.",
                "options": ["A", "B", "C", "D"],
                "correct_index": 2,
                "explanation_ar": "Explanation must be long enough.",
                "difficulty": "core",
                "clinical_vignette": false
              }
            ],
            "clinical_cases": [
              {
                "id": "case_1",
                "lecture_id": "unit_e2e_1",
                "title": "Case 1",
                "scenario": "Scenario must be at least fifty characters long so we add extra text to pass.",
                "debriefing_ar": "Debriefing must be at least 80 characters long so we add extra text to pass this validation safely. 1234567890.",
                "difficulty": "core",
                "order_index": 1,
                "vignette": {
                  "age": 30,
                  "sex": "male",
                  "chief_complaint": "Severe Chest Pain",
                  "history": "History of pain",
                  "exam": "Exam shows pain"
                },
                "steps": [
                  {
                    "id": "step_1",
                    "prompt": "What is the best next step?",
                    "options": ["Step A", "Step B", "Step C"],
                    "correct_index": 0,
                    "explanation_ar": "Explanation must be 20 characters.",
                    "xp": 5
                  },
                  {
                    "id": "step_2",
                    "prompt": "What is the definitive treatment?",
                    "options": ["Treat A", "Treat B", "Treat C"],
                    "correct_index": 1,
                    "explanation_ar": "Explanation must be 20 characters.",
                    "xp": 5
                  }
                ]
              }
            ]
          };
          return jsonEncode(dummyJson);
        },
        sleepHandler: (delay) {},
      );

      runtime = AgentRuntime(repository: repository, gateway: mockGateway);
    });

    tearDown(() async {
      repository.dispose();
      await helper.close();
      try {
        final f = File(dummyPdfPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    });

    test('Full Pipeline: Create Task -> Running -> Done -> Approve -> Curriculum DB', () async {
      final task = await repository.createTask(
        id: 'task_e2e_1',
        filePath: dummyPdfPath,
        title: 'Dummy E2E Lecture',
        initialSteps: [
          AgentStep(
            id: 'step_e2e_1',
            taskId: 'task_e2e_1',
            type: 'extract_concepts',
            sequenceIndex: 0,
            status: AgentStepStatus.pending,
          )
        ],
      );

      expect(task.status, AgentTaskStatus.queued);

      await runtime.runTask(task);

      final updatedTask = await repository.getTaskById('task_e2e_1');
      expect(updatedTask, isNotNull);
      expect(updatedTask!.status, AgentTaskStatus.pendingApproval);
      expect(updatedTask.payload, isNotNull);

      final Map<String, dynamic> assembled = jsonDecode(updatedTask.payload!) as Map<String, dynamic>;
      final Map<String, dynamic> extractedJson = (assembled['extract_concepts'] as Map<String, dynamic>?) ?? {};

      final result = await LectureImportService.importFromJsonString(jsonEncode(extractedJson));
      if (!result.ok) {
        print('Validation Error: ${result.messageAr}');
      }
      expect(result.ok, isTrue);

      await repository.updateTaskStatus(
        updatedTask.id,
        AgentTaskStatus.done,
        statusText: result.messageAr,
      );

      final db = await helper.database;
      final units = await db.query('units', where: 'id = ?', whereArgs: ['unit_e2e_1']);
      expect(units.length, 1);
      expect(units.first['title'], 'Dummy E2E Lecture');

      final concepts = await db.query('concepts', where: 'unit_id = ?', whereArgs: ['unit_e2e_1']);
      expect(concepts.length, 1);
      expect(concepts.first['title'], 'Concept 1');
    });
  });
}
