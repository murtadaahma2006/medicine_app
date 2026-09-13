import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
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
}
