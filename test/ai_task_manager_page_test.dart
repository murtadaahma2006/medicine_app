import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/agent/agent_runtime.dart';
import 'package:medicine_app/src/core/agent/models/models.dart';
import 'package:medicine_app/src/core/agent/task_repository.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/features/profile/presentation/pages/ai_task_manager_page.dart';
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

  group('Phase 3: AiTaskManagerPage Dashboard & TaskCard Widget Tests', () {
    late DatabaseHelper helper;
    late TaskRepository repository;
    late AgentRuntime runtime;

    setUp(() async {
      helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
      repository = TaskRepository(dbHelper: helper);
      runtime = AgentRuntime(repository: repository);
    });

    tearDown(() {
      repository.dispose();
    });

    Widget createWidgetUnderTest() {
      return MaterialApp(
        home: AiTaskManagerPage(
          repository: repository,
          runtime: runtime,
        ),
      );
    }

    testWidgets('تعرض حالة فارغة عند عدم وجود مهام معالجة', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('لا توجد مهام معالجة حالياً'), findsOneWidget);
      expect(find.text('مصنع المحتوى (MedOS Factory)'), findsOneWidget);
    });

    testWidgets('تعرض بطاقة المهمة وتتفاعل مع الأزرار والإجراءات', (WidgetTester tester) async {
      await repository.createTask(
        id: 'task-ui-1',
        filePath: '/storage/pdfs/cardiology_lecture.pdf',
        title: 'محاضرة قصور القلب',
        status: AgentTaskStatus.pendingApproval,
        progress: 1.0,
        currentStatusText: 'اكتملت جميع الخطوات - بانتظار الموافقة',
        payload: '{"sample": "data"}',
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('محاضرة قصور القلب'), findsOneWidget);
      expect(find.text('بانتظار الموافقة'), findsOneWidget);
      expect(find.text('اعتماد واستيراد ✔'), findsOneWidget);

      // الضغط على زر الاعتماد والاستيراد
      await tester.tap(find.text('اعتماد واستيراد ✔'));
      await tester.pumpAndSettle();

      // يتغير رأس البطاقة إلى مكتمل ومستورد
      expect(find.text('مكتمل ومستورد'), findsOneWidget);
    });
  });
}
