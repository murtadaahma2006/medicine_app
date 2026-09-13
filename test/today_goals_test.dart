import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/database/srs_repository.dart';
import 'package:medicine_app/src/core/database/user_progress.dart';
import 'package:medicine_app/src/features/curriculum/data/unit_repository.dart';
import 'package:medicine_app/src/features/curriculum/domain/unit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات أهداف اليوم (v17) — checkTodayStatus الموحد:
/// الحلقة والرسالة في شاشة اليوم تُشتقان من محاضرات مثبتة **غير مكتملة**
/// مع البطاقات المستحقة — لا من البطاقات وحدها.
///
/// يغطي: getPinnedUnitsWithCompletion (اشتقاق الإكمال) · unpinUnit /
/// unpinUnitIfCompleted (الإلغاء التلقائي) · TodayGoalsSnapshot (المراحل
/// والحلقة) · todayGoals (اللقطة الكاملة).
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

  /// وحدتان: u1 بشرحين (قابلة للإكمال بالقراءة) وu2 بلا شروح
  /// (لا تكتمل إلا بتقييمها) — كلتاهما مثبتتان.
  Future<void> seedPinnedLectures(DatabaseHelper helper) async {
    for (final String id in <String>['u1', 'u2']) {
      await helper.insertUnit(<String, Object?>{
        'id': id,
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'Lecture $id',
        'order_index': id == 'u1' ? 0 : 1,
        'is_pinned_today': 1,
      });
    }
    await helper.insertConcept(<String, Object?>{
      'id': 'c1',
      'unit_id': 'u1',
      'title': 'Pathophysiology',
      'sections_json': '[]',
      'order_index': 0,
    });
    await helper.insertConcept(<String, Object?>{
      'id': 'c2',
      'unit_id': 'u1',
      'title': 'Diagnosis',
      'sections_json': '[]',
      'order_index': 1,
    });
  }

  Future<void> markAssessmentPassed(DatabaseHelper helper, String unitId,
      {int score = 100}) async {
    await helper.upsertProgress(UserProgress(
      itemType: ProgressItemType.drill,
      itemId: 'assess-$unitId',
      status: ProgressStatus.completed,
      timesReviewed: 1,
      score: score,
    ));
  }

  group('getPinnedUnitsWithCompletion — اشتقاق الإكمال', () {
    test('محاضرة مثبتة بلا أي تقدم → is_completed = 0', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      final List<Map<String, Object?>> rows =
          await helper.getPinnedUnitsWithCompletion();
      expect(rows.length, 2);
      expect(rows.every((Map<String, Object?> r) => r['is_completed'] == 0),
          isTrue);
    });

    test('قراءة كل الشروح كاملة → مكتملة (بلا تقييم)', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      // c1 مقروء، c2 لا → غير مكتملة بعد.
      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      List<Map<String, Object?>> rows =
          await helper.getPinnedUnitsWithCompletion();
      expect(
        rows.firstWhere((Map<String, Object?> r) => r['id'] == 'u1')
            ['is_completed'],
        0,
        reason: 'شرح واحد فقط — ناقصة',
      );

      // اكتمال c2 → u1 مكتملة بالقراءة العميقة.
      await helper.recordConceptRead(conceptId: 'c2', completed: true);
      rows = await helper.getPinnedUnitsWithCompletion();
      expect(
        rows.firstWhere((Map<String, Object?> r) => r['id'] == 'u1')
            ['is_completed'],
        1,
      );
    });

    test('قراءة جزئية (exit مبكر) لا تُكمل المحاضرة', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await helper.recordConceptRead(conceptId: 'c1', completed: false);
      final List<Map<String, Object?>> rows =
          await helper.getPinnedUnitsWithCompletion();
      expect(
        rows.firstWhere((Map<String, Object?> r) => r['id'] == 'u1')
            ['is_completed'],
        0,
      );
    });

    test('اجتياز التقييم الرسمي يكملها (حتى بلا شروح مقروءة)', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await markAssessmentPassed(helper, 'u2');
      final List<Map<String, Object?>> rows =
          await helper.getPinnedUnitsWithCompletion();
      expect(
        rows.firstWhere((Map<String, Object?> r) => r['id'] == 'u2')
            ['is_completed'],
        1,
      );
      // u1 ما زالت ناقصة.
      expect(
        rows.firstWhere((Map<String, Object?> r) => r['id'] == 'u1')
            ['is_completed'],
        0,
      );
    });

    test('محاضرة غير مثبتة لا تظهر أصلاً', () async {
      final DatabaseHelper helper = await fresh();
      await helper.insertUnit(<String, Object?>{
        'id': 'u0',
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'Not pinned',
        'order_index': 0,
      });
      await markAssessmentPassed(helper, 'u0');

      expect((await helper.getPinnedUnitsWithCompletion()), isEmpty);
    });
  });

  group('unpinUnitIfCompleted — الإلغاء التلقائي', () {
    test('لا يُلمس التثبيت ما دامت المحاضرة ناقصة', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      await helper.unpinUnitIfCompleted('u1');

      final Map<String, Object?>? unit = await helper.getUnitById('u1');
      expect(unit?['is_pinned_today'], 1, reason: 'c2 لم يُقرأ بعد');
    });

    test('يكتمل الهدف لحظة اكتمال الشروح → يُفك التثبيت', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      await helper.recordConceptRead(conceptId: 'c2', completed: true);
      await helper.unpinUnitIfCompleted('u1');

      final Map<String, Object?>? unit = await helper.getUnitById('u1');
      expect(unit?['is_pinned_today'], 0);
      // u2 ما زالت مثبتة (لم تكتمل).
      expect((await helper.getUnitById('u2'))?['is_pinned_today'], 1);
    });

    test('unpinUnit يفك التثبيت دائماً (يدوي)', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await helper.unpinUnit('u2');
      expect((await helper.getUnitById('u2'))?['is_pinned_today'], 0);
      expect((await helper.getUnitById('u1'))?['is_pinned_today'], 1);
    });
  });

  group('TodayGoalsSnapshot — المراحل والحلقة (نقي)', () {
    const Unit u1 = Unit(
      id: 'u1',
      module: 'cardiology',
      system: 'cardiovascular',
      title: 'L1',
      orderIndex: 0,
    );
    const Unit u2 = Unit(
      id: 'u2',
      module: 'cardiology',
      system: 'cardiovascular',
      title: 'L2',
      orderIndex: 1,
    );

    test('لا محاضرات + لا بطاقات → done (مهام اليوم مكتملة)', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[],
        completedPinned: <Unit>[],
        dueCards: 0,
      );
      expect(s.phase, TodayPhase.done);
      expect(s.hasWork, isFalse);
      expect(s.progress, 1);
    });

    test('محاضرات مثبتة غير مكتملة → lectures (الأولوية الأولى)', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[u1, u2],
        completedPinned: <Unit>[],
        dueCards: 7,
      );
      expect(s.phase, TodayPhase.lectures);
      expect(s.hasWork, isTrue);
      expect(s.pendingPinned.length, 2);
      // صفر أسهم مكتملة من ثلاثة (محاضرتان + حزمة البطاقات).
      expect(s.progress, 0);
    });

    test('محاضرات مكتملة + بطاقات مستحقة → reviews', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[u1],
        completedPinned: <Unit>[u1],
        dueCards: 5,
      );
      expect(s.phase, TodayPhase.reviews);
      expect(s.pendingPinned, isEmpty);
      expect(s.progress, closeTo(1 / 2, 0.001));
    });

    test('المحاضرات المكتملة تُستبقى في القائمة بشارة إتمام', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[u1, u2],
        completedPinned: <Unit>[u1],
        dueCards: 0,
      );
      // u2 ناقصة → مرحلة المحاضرات رغم اكتمال u1 والبطاقات.
      expect(s.phase, TodayPhase.lectures);
      expect(s.pendingPinned.length, 1);
      // سهم u1 المكتمل + سهم البطاقات المكتمل = 2 من 3.
      expect(s.progress, closeTo(2 / 3, 0.001));

      const TodayGoalsSnapshot s2 = TodayGoalsSnapshot(
        pinned: <Unit>[u1, u2],
        completedPinned: <Unit>[u1, u2],
        dueCards: 3,
      );
      expect(s2.phase, TodayPhase.reviews);
      expect(s2.pendingPinned, isEmpty);
      // سهمان مكتملان من ثلاثة.
      expect(s2.progress, closeTo(2 / 3, 0.001));
    });
  });

  group('todayGoals — اللقطة الكاملة على قاعدة حقيقية', () {
    test('بطاقات مستحقة + محاضرات ناقصة معاً في جملة واحدة', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      // بطاقة مستحقة الآن.
      await helper.insertFlashcard(<String, Object?>{
        'id': 'u1-f1',
        'unit_id': 'u1',
        'card_type': 'basic',
        'front_text': 'F',
        'back_text': 'B',
      });
      final db = await helper.database;
      await db.insert(DatabaseHelper.tableSrsCards, <String, Object?>{
        'flashcard_id': 'u1-f1',
        'box': 1,
        'streak_ok': 0,
        'streak_bad': 1,
        'last_review': DateTime.now().toUtc().toIso8601String(),
        'next_due': '2000-01-01T00:00:00.000Z',
        'card_type': 'basic',
      });

      final TodayGoalsSnapshot s = await UnitRepository().todayGoals();
      expect(s.pinned.length, 2);
      expect(s.completedPinned, isEmpty);
      expect(s.dueCards, 1);
      expect(s.phase, TodayPhase.lectures);
      expect(await SrsRepository.dueTodayCount(), 1);
    });

    test('إكمال القراءة ثم unpinUnitIfCompleted → المحاضرة تختفي من الأهداف',
        () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      await helper.recordConceptRead(conceptId: 'c2', completed: true);
      await helper.unpinUnitIfCompleted('u1');

      final TodayGoalsSnapshot s = await UnitRepository().todayGoals();
      expect(s.pinned.length, 1, reason: 'u1 اختفت — بقي u2');
      expect(s.pinned.first.id, 'u2');
      expect(s.phase, TodayPhase.lectures);
    });
  });
}
