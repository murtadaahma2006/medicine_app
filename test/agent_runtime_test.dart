import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/agent/ai_gateway.dart';
import 'package:medicine_app/src/core/agent/agent_runtime.dart';
import 'package:medicine_app/src/core/agent/models/models.dart';
import 'package:medicine_app/src/core/agent/task_repository.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  group('Phase 2: Orchestrator & Gateway Tests', () {
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

    group('AiGateway & Exponential Backoff', () {
      test('ينفذ الخطوة بنجاح عند المحاولة الأولى', () async {
        final gateway = AiGateway(
          maxRetries: 3,
          initialBackoff: const Duration(milliseconds: 1),
          apiCallHandler: (system, user, {fileBytes, filePath, provider}) async => '{"status": "ok"}',
          sleepHandler: (_) {},
        );

        const step = AgentStep(
          id: 'step-gw-1',
          taskId: 'task-gw-1',
          sequenceIndex: 0,
          type: AgentStepType.extractConcepts,
        );

        final result = await gateway.executeStep(step);
        expect(result.status, AgentStepStatus.done);
        expect(result.outputPayload, '{"status": "ok"}');
        expect(result.attempts, 1);
      });

      test('يعيد المحاولة بتراجع أسي عند أخطاء 429 وتنجح المحاولة الثانية', () async {
        int callCount = 0;
        final delays = <Duration>[];

        final gateway = AiGateway(
          maxRetries: 3,
          initialBackoff: const Duration(milliseconds: 50),
          backoffMultiplier: 2.0,
          apiCallHandler: (system, user, {fileBytes, filePath, provider}) async {
            callCount++;
            if (callCount == 1) {
              throw Exception('HTTP 429: Rate Limit Exceeded');
            }
            return '{"retry": "success"}';
          },
          sleepHandler: (duration) => delays.add(duration),
        );

        const step = AgentStep(
          id: 'step-gw-2',
          taskId: 'task-gw-2',
          sequenceIndex: 0,
          type: AgentStepType.generateMcqs,
        );

        final result = await gateway.executeStep(step);
        expect(callCount, 2);
        expect(result.status, AgentStepStatus.done);
        expect(result.outputPayload, '{"retry": "success"}');
        expect(delays.length, 1);
        expect(delays[0].inMilliseconds, 50);
      });

      test('يرمي استثناء نهائياً بعد استنفاد محاولات maxRetries', () async {
        int callCount = 0;

        final gateway = AiGateway(
          maxRetries: 3,
          initialBackoff: const Duration(milliseconds: 1),
          apiCallHandler: (system, user, {fileBytes, filePath, provider}) async {
            callCount++;
            throw Exception('HTTP 429: Persistent Rate Limit');
          },
          sleepHandler: (_) {},
        );

        const step = AgentStep(
          id: 'step-gw-3',
          taskId: 'task-gw-3',
          sequenceIndex: 0,
          type: AgentStepType.generateFlashcards,
        );

        await expectLater(
          gateway.executeStep(step),
          throwsA(isA<AiGatewayException>()),
        );
        expect(callCount, 3);
      });
    });

    group('AgentRuntime Orchestrator & Checkpoint Resumption', () {
      test('ينفذ جميع خطوات المهمة بنجاح وينقلها إلى pending_approval', () async {
        final gateway = AiGateway(
          maxRetries: 2,
          initialBackoff: const Duration(milliseconds: 1),
          apiCallHandler: (system, user, {fileBytes, filePath, provider}) async => '{"result": "$user"}',
          sleepHandler: (_) {},
        );

        final runtime = AgentRuntime(repository: repository, gateway: gateway);

        final initialTask = await repository.createTask(
          id: 'task-rt-1',
          filePath: '/storage/pdfs/cardiology.pdf',
          title: 'طب القلب',
          initialSteps: const [
            AgentStep(
              id: 's1',
              taskId: 'task-rt-1',
              sequenceIndex: 0,
              type: AgentStepType.extractConcepts,
            ),
            AgentStep(
              id: 's2',
              taskId: 'task-rt-1',
              sequenceIndex: 1,
              type: AgentStepType.generateMcqs,
            ),
          ],
        );

        await runtime.runTask(initialTask);

        final completedTask = await repository.getTaskById('task-rt-1');
        expect(completedTask, isNotNull);
        expect(completedTask!.status, AgentTaskStatus.pendingApproval);
        expect(completedTask.progress, 1.0);
        expect(completedTask.payload, contains('extract_concepts'));
        expect(completedTask.payload, contains('generate_mcqs'));

        final steps = await repository.getStepsForTask('task-rt-1');
        expect(steps.every((s) => s.status == AgentStepStatus.done), isTrue);
      });

      test('تخطي الخطوات المكتملة سابقاً (Resumption / Checkpointing)', () async {
        int executedStepsCount = 0;

        final gateway = AiGateway(
          maxRetries: 2,
          initialBackoff: const Duration(milliseconds: 1),
          apiCallHandler: (system, user, {fileBytes, filePath, provider}) async {
            executedStepsCount++;
            return '{"step_executed": true}';
          },
          sleepHandler: (_) {},
        );

        final runtime = AgentRuntime(repository: repository, gateway: gateway);

        final initialTask = await repository.createTask(
          id: 'task-rt-2',
          filePath: '/storage/pdfs/respiratory.pdf',
          title: 'أمراض التنفس',
          initialSteps: const [
            AgentStep(
              id: 's-done-1',
              taskId: 'task-rt-2',
              sequenceIndex: 0,
              type: AgentStepType.extractConcepts,
              status: AgentStepStatus.done,
              outputPayload: '{"concepts": ["Asthma", "COPD"]}',
            ),
            AgentStep(
              id: 's-pending-2',
              taskId: 'task-rt-2',
              sequenceIndex: 1,
              type: AgentStepType.generateMcqs,
              status: AgentStepStatus.pending,
            ),
          ],
        );

        await runtime.runTask(initialTask);

        expect(executedStepsCount, 1);

        final finalTask = await repository.getTaskById('task-rt-2');
        expect(finalTask!.status, AgentTaskStatus.pendingApproval);
        expect(finalTask.progress, 1.0);
        expect(finalTask.payload, contains('Asthma'));
      });

      test('عند حدوث خطأ نهائي في خطوة، يتم تعليم الخطوة كـ failed والمهمة كـ paused ويتوقف التنفيذ بأمان', () async {
        final gateway = AiGateway(
          maxRetries: 2,
          initialBackoff: const Duration(milliseconds: 1),
          apiCallHandler: (system, user, {fileBytes, filePath, provider}) async {
            throw Exception('API Server Failure');
          },
          sleepHandler: (_) {},
        );

        final runtime = AgentRuntime(repository: repository, gateway: gateway);

        final initialTask = await repository.createTask(
          id: 'task-rt-3',
          filePath: '/storage/pdfs/renal.pdf',
          title: 'أمراض الكلى',
          initialSteps: const [
            AgentStep(
              id: 's-err-1',
              taskId: 'task-rt-3',
              sequenceIndex: 0,
              type: AgentStepType.extractConcepts,
            ),
          ],
        );

        await runtime.runTask(initialTask);

        final pausedTask = await repository.getTaskById('task-rt-3');
        expect(pausedTask, isNotNull);
        expect(pausedTask!.status, AgentTaskStatus.paused);
        expect(pausedTask.currentStatusText, contains('توقف المهمة مؤقتاً'));

        final steps = await repository.getStepsForTask('task-rt-3');
        expect(steps[0].status, AgentStepStatus.failed);
        expect(steps[0].lastError, contains('API Server Failure'));
      });

      test('يتعرف على JSON المشوه ويصلحه بنجاح من خلال حلقة الإصلاح الذاتي (Self-Healing Loop)', () async {
        int callCount = 0;
        final gateway = AiGateway(
          maxRetries: 1,
          initialBackoff: const Duration(milliseconds: 1),
          apiCallHandler: (system, user, {fileBytes, filePath, provider}) async {
            callCount++;
            if (system.contains('repair')) {
              return '{"repaired_json": true}';
            }
            return '{"invalid_json": '; // Truncated JSON causing FormatException
          },
          sleepHandler: (_) {},
        );

        final runtime = AgentRuntime(repository: repository, gateway: gateway);

        final initialTask = await repository.createTask(
          id: 'task-rt-self-heal',
          filePath: '/storage/pdfs/heal.pdf',
          title: 'اختبار الإصلاح الذاتي',
          initialSteps: const [
            AgentStep(
              id: 's-heal-1',
              taskId: 'task-rt-self-heal',
              sequenceIndex: 0,
              type: AgentStepType.extractConcepts,
            ),
          ],
        );

        await runtime.runTask(initialTask);

        final completedTask = await repository.getTaskById('task-rt-self-heal');
        expect(completedTask, isNotNull);
        expect(completedTask!.status, AgentTaskStatus.pendingApproval);
        expect(completedTask.payload, contains('repaired_json'));
        expect(callCount, 2); // 1 for initial execution + 1 for repair step
      });
    });
  });
}
