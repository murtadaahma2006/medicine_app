import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/agent/models/models.dart';
import 'package:medicine_app/src/core/agent/task_repository.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  group('Hermes Agent Pipeline DB Schema (v30) & TaskRepository', () {
    late DatabaseHelper helper;
    late TaskRepository repository;

    setUp(() async {
      helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
      repository = TaskRepository(dbHelper: helper);
    });

    tearDown(() {
      repository.dispose();
    });

    test('ينشئ جدول agent_tasks وجدول agent_steps ضمن المخطط v30', () async {
      final List<Map<String, Object?>> rows = await helper.rawQueryParameterized(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final Set<String> tables =
          rows.map((r) => r['name']! as String).toSet();

      expect(tables.contains(DatabaseHelper.tableAgentTasks), isTrue);
      expect(tables.contains(DatabaseHelper.tableAgentSteps), isTrue);
    });

    test('يقوم بإنشاء مهمة جديدة وجلبها بنجاح', () async {
      final task = await repository.createTask(
        id: 'task-001',
        filePath: '/storage/pdfs/cardiology.pdf',
        title: 'أمراض القلب والشرايين',
        payload: '{"module": "cardiology"}',
      );

      expect(task.id, 'task-001');
      expect(task.status, AgentTaskStatus.queued);
      expect(task.progress, 0.0);

      final fetchedTask = await repository.getTaskById('task-001');
      expect(fetchedTask, isNotNull);
      expect(fetchedTask!.title, 'أمراض القلب والشرايين');
      expect(fetchedTask.filePath, '/storage/pdfs/cardiology.pdf');
    });

    test('يقوم بتحديث حالة المهمة ونسبة التقدم ونصوص الحالة', () async {
      await repository.createTask(
        id: 'task-002',
        filePath: '/storage/pdfs/respiratory.pdf',
        title: 'أمراض الجهاز التنفسي',
      );

      await repository.updateTaskStatus(
        'task-002',
        AgentTaskStatus.running,
        statusText: 'جاري استخراج المفاهيم...',
      );

      var task = await repository.getTaskById('task-002');
      expect(task!.status, AgentTaskStatus.running);
      expect(task.currentStatusText, 'جاري استخراج المفاهيم...');

      await repository.updateTaskProgress(
        'task-002',
        0.45,
        statusText: 'تم توليد 45% من الأسئلة',
      );

      task = await repository.getTaskById('task-002');
      expect(task!.progress, 0.45);
      expect(task.currentStatusText, 'تم توليد 45% من الأسئلة');
    });

    test('يقوم بإنشاء واسترجاع خطوات المهمة بالترتيب التسلسلي', () async {
      final initialSteps = [
        const AgentStep(
          id: 'step-1',
          taskId: 'task-003',
          sequenceIndex: 0,
          type: AgentStepType.extractConcepts,
        ),
        const AgentStep(
          id: 'step-2',
          taskId: 'task-003',
          sequenceIndex: 1,
          type: AgentStepType.generateMcqs,
        ),
      ];

      await repository.createTask(
        id: 'task-003',
        filePath: '/storage/pdfs/gastro.pdf',
        title: 'أمراض الهضم',
        initialSteps: initialSteps,
      );

      final steps = await repository.getStepsForTask('task-003');
      expect(steps.length, 2);
      expect(steps[0].id, 'step-1');
      expect(steps[0].sequenceIndex, 0);
      expect(steps[0].type, 'extract_concepts');
      expect(steps[1].id, 'step-2');
      expect(steps[1].sequenceIndex, 1);

      // تحديث خطوة
      final updatedStep1 = steps[0].copyWith(
        status: AgentStepStatus.done,
        outputPayload: '{"concepts_count": 12}',
        attempts: 1,
      );
      await repository.updateStep(updatedStep1);

      final reFetchedSteps = await repository.getStepsForTask('task-003');
      expect(reFetchedSteps[0].status, AgentStepStatus.done);
      expect(reFetchedSteps[0].outputPayload, '{"concepts_count": 12}');
      expect(reFetchedSteps[0].attempts, 1);
    });

    test('حذف المهمة يؤدي إلى حذف الخطوات التابعة لها تلقائياً (Cascade)', () async {
      await repository.createTask(
        id: 'task-004',
        filePath: '/storage/pdfs/renal.pdf',
        title: 'أمراض الكلى',
        initialSteps: [
          const AgentStep(
            id: 'step-del-1',
            taskId: 'task-004',
            sequenceIndex: 0,
            type: AgentStepType.extractConcepts,
          ),
        ],
      );

      expect((await repository.getStepsForTask('task-004')).length, 1);

      await repository.deleteTask('task-004');

      expect(await repository.getTaskById('task-004'), isNull);
      expect((await repository.getStepsForTask('task-004')).length, 0);
    });

    test('يدعم مجرى watchTasks البث التفاعلي للمهام', () async {
      final stream = repository.watchTasks();

      expect(
        stream,
        emitsThrough(
          predicate<List<AgentTask>>(
            (tasks) => tasks.any((t) => t.id == 'task-stream-01'),
          ),
        ),
      );

      await repository.createTask(
        id: 'task-stream-01',
        filePath: '/storage/pdfs/neuro.pdf',
        title: 'أمراض الأعصاب',
      );
    });
  });
}
