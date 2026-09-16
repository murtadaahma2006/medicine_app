import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/database/srs_repository.dart';
import 'package:medicine_app/src/core/database/user_progress.dart';
import 'package:medicine_app/src/features/curriculum/data/unit_repository.dart';
import 'package:medicine_app/src/features/curriculum/domain/unit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات أهداف اليوم (v18) — checkTodayStatus الموحد + التثبيت
/// الذكي: المحاضرات المثبتة غير المكتملة مع البطاقات المستحقة، مع
/// التنظيف التلقائي (المكتملة فوراً + المهملة بعد 48 ساعة).
///
/// يغطي: getPinnedUnitsWithCompletion (اشتقاق الإكمال) · unpinUnit /
/// unpinUnitIfCompleted (الإلغاء التلقائي) · cleanUpStalePins (v18) ·
/// TodayGoalsSnapshot (المراحل والحلقة) · todayGoals (اللقطة الكاملة).
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
        'pinned_at': DateTime.now().toUtc().toIso8601String(),
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
      expect(unit?['pinned_at'], isNotNull, reason: 'c2 لم يُقرأ بعد');
    });

    test('يكتمل الهدف لحظة اكتمال الشروح → يُفك التثبيت', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await helper.recordConceptRead(conceptId: 'c1', completed: true);
      await helper.recordConceptRead(conceptId: 'c2', completed: true);
      await helper.unpinUnitIfCompleted('u1');

      final Map<String, Object?>? unit = await helper.getUnitById('u1');
      expect(unit?['pinned_at'], isNull);
      // u2 ما زالت مثبتة (لم تكتمل).
      expect((await helper.getUnitById('u2'))?['pinned_at'], isNotNull);
    });

    test('unpinUnit يفك التثبيت دائماً (يدوي)', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await helper.unpinUnit('u2');
      expect((await helper.getUnitById('u2'))?['pinned_at'], isNull);
      expect((await helper.getUnitById('u1'))?['pinned_at'], isNotNull);
    });
  });

  group('cleanUpStalePins — التنظيف التلقائي (v18)', () {
    test('المحاضرة المكتملة تُفكّ فوراً', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      // u2 تكتمل بتقييمها → فك فوري رغم حداثة التثبيت.
      await markAssessmentPassed(helper, 'u2');
      final List<String> unpinned = await helper.cleanUpStalePins();

      expect(unpinned, contains('u2'));
      expect((await helper.getUnitById('u2'))?['pinned_at'], isNull);
      // u1 الناقصة لم تُمسّ.
      expect((await helper.getUnitById('u1'))?['pinned_at'], isNotNull);
    });

    test('المهملة (>48 ساعة) تُفكّ تلقائياً', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      // تثبيت عمره 3 أيام — تجاوز عتبة الإهمال بوضوح.
      final Database db = await helper.database;
      await db.rawUpdate(
        'UPDATE ${DatabaseHelper.tableUnits} SET pinned_at = ? WHERE id = ?',
        <Object?>[
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 72))
              .toIso8601String(),
          'u2',
        ],
      );

      final List<String> unpinned = await helper.cleanUpStalePins();
      expect(unpinned, contains('u2'));
      expect((await helper.getUnitById('u2'))?['pinned_at'], isNull);
      // u1 حديثة التثبيت → باقية.
      expect((await helper.getUnitById('u1'))?['pinned_at'], isNotNull);
    });

    test('الحديثة (<48 ساعة) وغير المكتملة تبقى مثبتة', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      // تثبيت عمره 47 ساعة — ساعة واحدة قبل العتبة.
      final Database db = await helper.database;
      await db.rawUpdate(
        'UPDATE ${DatabaseHelper.tableUnits} SET pinned_at = ? WHERE id = ?',
        <Object?>[
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 47))
              .toIso8601String(),
          'u2',
        ],
      );

      final List<String> unpinned = await helper.cleanUpStalePins();
      expect(unpinned, isEmpty);
      expect((await helper.getUnitById('u2'))?['pinned_at'], isNotNull);
    });

    test('المكتملة المهملة تُفكّ مرة واحدة (لا تكرار في القائمة)', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      await markAssessmentPassed(helper, 'u2');
      final Database db = await helper.database;
      await db.rawUpdate(
        'UPDATE ${DatabaseHelper.tableUnits} SET pinned_at = ? WHERE id = ?',
        <Object?>[
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 72))
              .toIso8601String(),
          'u2',
        ],
      );

      final List<String> unpinned = await helper.cleanUpStalePins();
      // شرطا الإكمال والإهمال يصيبان نفس المحاضرة — فك واحد لا اثنان.
      expect(unpinned.length, 1);
      expect(unpinned.first, 'u2');
    });

    test('لا مثبتات → قائمة فارغة بلا أخطاء', () async {
      final DatabaseHelper helper = await fresh();
      expect(await helper.cleanUpStalePins(), isEmpty);
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

    test('لا مثبتات + لا بطاقات → none (حلقة فارغة برسالة تثبيت)', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[],
        completedPinned: <Unit>[],
        dueCards: 0,
      );
      expect(s.phase, TodayPhase.none);
      expect(s.hasWork, isFalse);
      expect(s.progress, 0);
    });

    test('لا مثبتات مع بطاقات مستحقة → none رغم البطاقات (فصل تام)', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[],
        completedPinned: <Unit>[],
        dueCards: 12,
      );
      // الحلقة والرسالة الرئيسية لا تتحرك للبطاقات — شريطها فقط.
      expect(s.phase, TodayPhase.none);
      expect(s.progress, 0);
      expect(s.hasWork, isTrue, reason: 'لكن يبقى عمل (المراجعة)');
    });

    test('محاضرة واحدة ناقصة → الحلقة 0% مهما بلغت البطاقات', () {
      // الحالة الرياضية المشكلة سابقاً: بطاقات صفر + محاضرة ناقصة
      // كانت تعطي 50% — الآن المحاضرات وحدها تقود النسبة.
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[u1],
        completedPinned: <Unit>[],
        dueCards: 0,
      );
      expect(s.phase, TodayPhase.lectures);
      expect(s.hasWork, isTrue);
      expect(s.pendingPinned.length, 1);
      expect(s.progress, 0);

      // نفس المحاضرة مع 7 بطاقات مستحقة → النسبة نفسها تماماً.
      const TodayGoalsSnapshot withCards = TodayGoalsSnapshot(
        pinned: <Unit>[u1],
        completedPinned: <Unit>[],
        dueCards: 7,
      );
      expect(withCards.progress, 0);
      expect(withCards.phase, TodayPhase.lectures);
    });

    test('محاضرة من محاضرتين مكتملة → 50% (البطاقات لا تشارك)', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[u1, u2],
        completedPinned: <Unit>[u1],
        dueCards: 5,
      );
      expect(s.phase, TodayPhase.lectures);
      expect(s.pendingPinned.length, 1);
      // سابقاً كانت (1+0)/(2+1) — الآن محاضرات فقط: 1/2.
      expect(s.progress, closeTo(1 / 2, 0.001));
    });

    test('كل المثبتات مكتملة → done وإن بقيت بطاقات مستحقة', () {
      const TodayGoalsSnapshot s = TodayGoalsSnapshot(
        pinned: <Unit>[u1, u2],
        completedPinned: <Unit>[u1, u2],
        dueCards: 3,
      );
      // الرسالة الرئيسية «أنجزت أهدافك» — البطاقات شريطها المنفصل.
      expect(s.phase, TodayPhase.done);
      expect(s.pendingPinned, isEmpty);
      expect(s.progress, 1);
      expect(s.hasWork, isTrue, reason: 'المراجعات بعمل لكن خارج الحلقة');
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

    test('لقطة اليوم تدخل عبر التنظيف أولاً — المهملة لا تظهر', () async {
      final DatabaseHelper helper = await fresh();
      await seedPinnedLectures(helper);

      // u2 مهملة (>48h) وغير مكتملة — تنظيف اليوم يجب أن يمسحها قبل
      // بناء اللقطة كي لا يرى المستخدم هدفاً ميتاً في جدوله.
      final Database db = await helper.database;
      await db.rawUpdate(
        'UPDATE ${DatabaseHelper.tableUnits} SET pinned_at = ? WHERE id = ?',
        <Object?>[
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 72))
              .toIso8601String(),
          'u2',
        ],
      );

      final TodayGoalsSnapshot s = await UnitRepository().todayGoals();
      expect(s.pinned.length, 1, reason: 'u2 المهملة فُكّت قبل اللقطة');
      expect(s.pinned.first.id, 'u1');
    });
  });
}
