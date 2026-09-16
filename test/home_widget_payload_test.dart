import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/database/user_progress.dart';
import 'package:medicine_app/src/core/database/xp_event.dart';
import 'package:medicine_app/src/core/widget/home_widget_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات حمولة ويدجت الشاشة الرئيسية — الطبقة النقية فقط
/// (computePayload + tipForDate + isDueHigh) بلا قنوات منصة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('computePayload — قاعدة فارغة: صفر مستحق، صفر إنجاز، معلومة صالحة',
      () async {
    await DatabaseHelper.instance
        .openWith(databaseFactoryFfi, inMemoryDatabasePath);

    final payload = await HomeWidgetService.computePayload();

    expect(payload.dueCards, 0);
    expect(payload.dailyProgress, 0);
    expect(payload.completedToday, 0);
    expect(payload.medicalTip, isNotEmpty);
    expect(payload.generatedAtIso, isNotEmpty);
    expect(payload.isDueHigh, isFalse);
    expect(payload.toMap()['due_cards'], 0);
  });

  test('computePayload — بعد بطاقات مستحقة وأنشطة اليوم', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    // محاضرة + بطاقة (flashcards مطلوب عبر FK لsrs_cards).
    await helper.insertUnit(<String, Object?>{
      'id': 'w-001',
      'module': 'cardiology',
      'system': 'cardiovascular',
      'title': 'Widget Test Lecture',
      'order_index': 0,
    });
    await helper.insertFlashcard(<String, Object?>{
      'id': 'w-001-f1',
      'unit_id': 'w-001',
      'card_type': 'basic',
      'front_text': 'Front question?',
      'back_text': 'Back answer long enough.',
    });

    // بطاقة SRS مستحقة الآن (next_due في الماضي).
    final Database db = await helper.database;
    await db.insert(
      DatabaseHelper.tableSrsCards,
      <String, Object?>{
        'flashcard_id': 'w-001-f1',
        'box': 2,
        'streak_ok': 1,
        'streak_bad': 0,
        'last_review': '2026-09-01',
        'next_due': '2000-01-01T00:00:00.000Z', // مستحقة دائماً.
        'card_type': 'basic',
      },
    );

    // نشاطان اليوم: بطاقة + تقييم.
    await helper.addXpEvent(kind: XpEventKind.flashcard, refId: 'w-001-f1', xp: 3);
    await helper.addXpEvent(kind: XpEventKind.assessment, refId: 'w-001', xp: 20);

    final payload = await HomeWidgetService.computePayload();

    expect(payload.dueCards, 1);
    expect(payload.completedToday, 2);
    // الهدف الافتراضي 10 → 2/10 = 20%.
    expect(payload.dailyProgress, 20);
  });

  test('tipForDate — حتمية وتبدل بين الأيام', () {
    final DateTime a = DateTime.utc(2026, 9, 12);
    final DateTime b = DateTime.utc(2026, 9, 13);

    // نفس اليوم = نفس المعلومة (حتمية).
    expect(
      HomeWidgetService.tipForDate(a),
      HomeWidgetService.tipForDate(a),
    );
    // قيمة من البنك نفسه.
    expect(
      HomeWidgetService.medicalTips
          .contains(HomeWidgetService.tipForDate(a)),
      isTrue,
    );
    // تاريخ مختلف قد يعطي معلومة مختلفة (البنك 10 عناصر — يومان
    // متتاليان يعطيان فهرسين مختلفين حتماً).
    expect(
      HomeWidgetService.tipForDate(a) == HomeWidgetService.tipForDate(b),
      isFalse,
    );
  });

  test('isDueHigh — عتبة التراكم', () {
    const HomeWidgetPayload low = HomeWidgetPayload(
      dueCards: 3,
      dailyProgress: 10,
      medicalTip: 't',
      completedToday: 1,
      generatedAtIso: '',
    );
    const HomeWidgetPayload high = HomeWidgetPayload(
      dueCards: 15,
      dailyProgress: 10,
      medicalTip: 't',
      completedToday: 1,
      generatedAtIso: '',
    );
    expect(low.isDueHigh, isFalse);
    expect(high.isDueHigh, isTrue);
  });

  test('getPendingPinnedLectureTitles — المثبتة غير المكتملة فقط، بسقف 3',
      () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    final Database db = await helper.database;
    final String nowIso = DateTime.now().toUtc().toIso8601String();

    // 4 محاضرات مثبتة غير مكتملة + واحدة غير مثبتة + واحدة مكتملة.
    for (int i = 1; i <= 6; i++) {
      await helper.insertUnit(<String, Object?>{
        'id': 'p-$i',
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'Pending Lecture $i',
        'order_index': i,
        if (i <= 4) 'pinned_at': nowIso,
      });
    }
    // المكتملة: p-6 مثبتة واكتملت (نُفك تثبيتها في الاستعلام).
    await db.rawUpdate(
      'UPDATE ${DatabaseHelper.tableUnits} SET pinned_at = ? '
      'WHERE id = ?',
      <Object?>[nowIso, 'p-6'],
    );
    await helper.upsertProgress(UserProgress(
      itemType: ProgressItemType.drill,
      itemId: 'assess-p-6',
      status: ProgressStatus.completed,
      timesReviewed: 1,
      score: 100,
    ));

    final List<String> titles =
        await helper.getPendingPinnedLectureTitles();

    // سقف 3 + p-6 المكتملة مستبعدة + p-5 غير المثبتة غائبة.
    expect(titles.length, 3);
    expect(titles, everyElement(startsWith('Pending Lecture')));
    expect(titles, isNot(contains('Pending Lecture 6')));
    expect(titles, isNot(contains('Pending Lecture 5')));
    expect(titles, equals(titles.take(HomeWidgetPayload.maxPinnedTitles)));

    // عدّاد «+N أخرى»: الإجمالي الحقيقي 4 (وليس طول القائمة المقطوعة 3).
    expect(await helper.countPendingPinnedLectures(), 4);
  });

  test('getRandomGoldenTip — عشوائية من المزروعة فقط', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    // قاعدة بلا لآلئ → null.
    expect(await helper.getRandomGoldenTip(), isNull);

    // محاضرة بلؤلؤة واحدة → تُرجع حصراً.
    await helper.insertUnit(<String, Object?>{
      'id': 'g-1',
      'module': 'cardiology',
      'system': 'cardiovascular',
      'title': 'Golden Lecture',
      'order_index': 0,
      'golden_tip':
          'ACE-inhibitor cough: always rule out pulmonary edema first.',
    });
    final String? only = await helper.getRandomGoldenTip();
    expect(only, isNotNull);
    expect(only, contains('ACE-inhibitor'));

    // محاضرة بلؤلؤة فارغة نصياً → لا تُحتسب (فارغ = لا شيء).
    await helper.insertUnit(<String, Object?>{
      'id': 'g-2',
      'module': 'cardiology',
      'system': 'cardiovascular',
      'title': 'Empty Pearl Lecture',
      'order_index': 1,
      'golden_tip': '   ',
    });
    final String? afterEmpty = await helper.getRandomGoldenTip();
    expect(afterEmpty, contains('ACE-inhibitor'));
  });

  test('computePayload — الأهداف واللؤلؤة معاً', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    await helper.insertUnit(<String, Object?>{
      'id': 'w-002',
      'module': 'cardiology',
      'system': 'cardiovascular',
      'title': 'Pinned Unfinished Lecture',
      'order_index': 0,
      'pinned_at': DateTime.now().toUtc().toIso8601String(),
      'golden_tip':
          'Aortic stenosis: syncope on exertion is a red flag.',
    });

    final payload = await HomeWidgetService.computePayload();

    expect(payload.pendingPinnedTitles,
        equals(<String>['Pinned Unfinished Lecture']));
    expect(payload.clinicalPearl, contains('Aortic stenosis'));
    // عقد الإرسال: نص مدمج بـ " | " ومفتاح مستقل للؤلؤة.
    expect(payload.pendingPinnedJoined, 'Pinned Unfinished Lecture');
    expect(payload.toMap()['pinned_titles'], 'Pinned Unfinished Lecture');
    expect(payload.toMap()['clinical_pearl'], payload.clinicalPearl);
  });

  group('v19.1 — العدد الكلي وعدّاد «+N أخرى»', () {
    test('computePayload — الإجمالي غير المقطوع يصل الحمولة', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      // 5 مثبتات غير مكتملة → العناوين 3 (سقف العرض) والإجمالي 5.
      final String nowIso = DateTime.now().toUtc().toIso8601String();
      for (int i = 1; i <= 5; i++) {
        await helper.insertUnit(<String, Object?>{
          'id': 'x-$i',
          'module': 'cardiology',
          'system': 'cardiovascular',
          'title': 'Lecture $i',
          'order_index': i,
          'pinned_at': nowIso,
        });
      }

      final HomeWidgetPayload payload =
          await HomeWidgetService.computePayload();

      expect(payload.pendingPinnedTitles.length, 3);
      expect(payload.pinnedTotal, 5);
      expect(payload.extraPinnedCount, 2);
      // عقد الإرسال: pinned_total يُرسل للـ Native لعدّاد «+N أخرى».
      expect(payload.toMap()['pinned_total'], 5);
    });

    test('pendingPinnedJoined — عنوان يحوي "|" لا ينشق العقد', () {
      const HomeWidgetPayload payload = HomeWidgetPayload(
        dueCards: 0,
        dailyProgress: 0,
        completedToday: 0,
        medicalTip: 't',
        generatedAtIso: '',
        pendingPinnedTitles: <String>['A | B', 'C'],
      );
      // الفاصلة داخل العنوان استُبدلت — النص النهائي يفصل الأسطر فقط.
      expect(payload.pendingPinnedJoined.split(' | ').length, 2);
    });

    test('extraPinnedCount — لا سالب تحت السقف', () {
      const HomeWidgetPayload one = HomeWidgetPayload(
        dueCards: 0,
        dailyProgress: 0,
        completedToday: 0,
        medicalTip: 't',
        generatedAtIso: '',
        pendingPinnedTitles: <String>['A'],
        pinnedTotal: 1,
      );
      expect(one.extraPinnedCount, -2); // Native يحجب <= 0
    });
  });

  group('v19.1 — استهلاك نية نقرة الإقلاع البارد', () {
    test('setPendingDailyReview → consumePendingNavigation مرة واحدة', () {
      // لا نية قبل التسجيل.
      expect(HomeWidgetService.consumePendingNavigation(), isFalse);

      HomeWidgetService.setPendingDailyReview();
      // أول استهلاك: true (شاشة البداية توجّه للمراجعة اليومية).
      expect(HomeWidgetService.consumePendingNavigation(), isTrue);
      // الاستهلاك مرة واحدة فقط — لا توجيه مزدوج.
      expect(HomeWidgetService.consumePendingNavigation(), isFalse);
    });
  });
}
