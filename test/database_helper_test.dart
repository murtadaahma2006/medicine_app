import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/database/user_progress.dart';
import 'package:medicine_app/src/core/database/xp_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  group('المخطط v14 (هيكل بلا محتوى)', () {
    test('onCreate ينشئ كل الجداول الطبية فارغة', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );

      // جداول المحتوى + جداول المستخدم — كلها موجودة.
      final List<String> expectedTables = <String>[
        DatabaseHelper.tableUnits,
        DatabaseHelper.tableConcepts,
        DatabaseHelper.tableFlashcards,
        DatabaseHelper.tableMcqBank,
        DatabaseHelper.tableClinicalCases,
        DatabaseHelper.tableClinicalCaseSteps,
        DatabaseHelper.tableUserProgress,
        DatabaseHelper.tableCorrections,
        DatabaseHelper.tableXpEvents,
        DatabaseHelper.tableUnlockedBadges,
        DatabaseHelper.tableSrsCards,
      ];
      final List<Map<String, Object?>> rows =
          await helper.rawQueryParameterized(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final Set<String> created =
          rows.map((Map<String, Object?> r) => r['name']! as String).toSet();
      for (final String t in expectedTables) {
        expect(created.contains(t), isTrue, reason: 'الجدول $t يجب أن يُنشأ');
      }

      // كلها فارغة — الهيكل فقط، بلا أي محتوى مزروع.
      for (final String t in expectedTables) {
        final int count =
            await helper.rawCount('SELECT COUNT(*) FROM $t');
        expect(count, 0, reason: 'الجدول $t يجب أن يبدأ فارغاً');
      }
    });

    test('إدراج وحدة طبية ثم استرجاعها', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      await helper.insertUnit(<String, Object?>{
        'id': 'cardio-001',
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'Heart Failure',
        'order_index': 1,
      });

      final List<Map<String, Object?>> units = await helper.getAllUnits();
      expect(units.length, 1);
      expect(units.first['title'], 'Heart Failure');
      expect(units.first['module'], 'cardiology');
    });

    test('upsertProgress ثم getProgress (دورة كاملة)', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      await helper.upsertProgress(const UserProgress(
        itemType: ProgressItemType.flashcardSet,
        itemId: 'cardio-001',
        status: ProgressStatus.completed,
        timesReviewed: 3,
        score: 100,
      ));

      final UserProgress? loaded =
          await helper.getProgress(ProgressItemType.flashcardSet, 'cardio-001');
      expect(loaded, isNotNull);
      expect(loaded!.status, ProgressStatus.completed);
      expect(loaded.score, 100);

      // إعادة الزرع (idempotent) — نفس السطر يُحدَّث لا يُكرَّر.
      await helper.upsertProgress(const UserProgress(
        itemType: ProgressItemType.flashcardSet,
        itemId: 'cardio-001',
        status: ProgressStatus.inProgress,
        timesReviewed: 4,
      ));

      final List<Map<String, Object?>> rows =
          await helper.rawQueryParameterized(
        'SELECT * FROM ${DatabaseHelper.tableUserProgress} '
        "WHERE item_type = 'flashcard_set'",
      );
      expect(rows.length, 1, reason: 'UPSERT يجب ألا يكرر السطر');
      expect(rows.first['times_reviewed'], 4);
    });

    test('addXpEvent + sumXp', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      expect(await helper.sumXp(), 0);

      await helper.addXpEvent(kind: XpEventKind.mcq, refId: 'q1', xp: 10);
      await helper.addXpEvent(kind: XpEventKind.caseStep, refId: 'c1-s1', xp: 5);

      expect(await helper.sumXp(), 15);
    });
  });
}
