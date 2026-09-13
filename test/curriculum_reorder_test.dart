import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/features/curriculum/data/unit_repository.dart';
import 'package:medicine_app/src/features/curriculum/domain/unit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات مسار التعلم القائم على الأجهزة — إعادة الترتيب والنقل.
///
/// يغطي: reorderUnitWithinSystem (order_index) · moveUnitToSystem
/// (system + order_index) · ثبات الترتيب عند إعادة القراءة.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Future<void> seedUnits(DatabaseHelper helper) async {
    // جهازان: قلب (3 محاضرات) وتنفس (2 محاضرة).
    const List<(String, String, String, int)> seed =
        <(String, String, String, int)>[
      ('cardio-001', 'cardiology', 'cardiovascular', 0),
      ('cardio-002', 'cardiology', 'cardiovascular', 1),
      ('cardio-003', 'cardiology', 'cardiovascular', 2),
      ('pulmo-001', 'pulmonology', 'respiratory', 0),
      ('pulmo-002', 'pulmonology', 'respiratory', 1),
    ];
    for (final (String, String, String, int) s in seed) {
      await helper.insertUnit(<String, Object?>{
        'id': s.$1,
        'module': s.$2,
        'system': s.$3,
        'title': 'Lecture ${s.$1}',
        'order_index': s.$4,
      });
    }
  }

  test('reorderUnitWithinSystem يعيد الترقيم تسلسلياً ويصمد', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
    await seedUnits(helper);

    const UnitRepository repo = UnitRepository();

    // اسحب cardio-001 (0) إلى نهاية الجهاز (index 2).
    await repo.reorderUnitWithinSystem('cardiovascular', 'cardio-001', 2);

    final List<String> cardioOrder = await _systemOrder(repo, 'cardiovascular');
    expect(cardioOrder, <String>['cardio-002', 'cardio-003', 'cardio-001']);

    // الجهاز الآخر لم يتأثر.
    final List<String> pulmoOrder = await _systemOrder(repo, 'respiratory');
    expect(pulmoOrder, <String>['pulmo-001', 'pulmo-002']);

    // ثبات: القراءة الثانية تعطي نفس الترتيب (محفوظ في القاعدة).
    expect(await _systemOrder(repo, 'cardiovascular'), cardioOrder);
  });

  test('moveUnitToSystem ينقل ويحدث system وorder_index معاً', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
    await seedUnits(helper);

    const UnitRepository repo = UnitRepository();

    // انقل pulmo-001 (وضعت بالخطأ في التنفس) إلى القلب في المقدمة.
    await repo.moveUnitToSystem('pulmo-001', 'cardiovascular', targetIndex: 0);

    // system تغيّر فعلاً في القاعدة.
    final List<String> cardioOrder = await _systemOrder(repo, 'cardiovascular');
    expect(cardioOrder, <String>['pulmo-001', 'cardio-001', 'cardio-002', 'cardio-003']);

    final List<String> pulmoOrder = await _systemOrder(repo, 'respiratory');
    expect(pulmoOrder, <String>['pulmo-002']);

    // الترتيب التسلسلي محفوظ: 0..n-1 بلا فجوات.
    final List<int> cardioIdx = await _systemOrderIndexes(repo, 'cardiovascular');
    expect(cardioIdx, <int>[0, 1, 2, 3]);
  });

  test('moveUnitToSystem بدون targetIndex يلحق بنهاية الجهاز', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
    await seedUnits(helper);

    const UnitRepository repo = UnitRepository();
    await repo.moveUnitToSystem('cardio-003', 'respiratory');

    final List<String> pulmoOrder = await _systemOrder(repo, 'respiratory');
    expect(pulmoOrder, <String>['pulmo-001', 'pulmo-002', 'cardio-003']);
    final List<String> cardioOrder = await _systemOrder(repo, 'cardiovascular');
    expect(cardioOrder, <String>['cardio-001', 'cardio-002']);
  });

  test('applyUnitArrangement ذرّي — كل التحديثات داخل معاملة واحدة', () async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);
    await seedUnits(helper);

    // تحديث دفعة: عكس ترتيب القلب كاملاً.
    await helper.applyUnitArrangement(
      unitId: 'cardio-001',
      orders: <String, int>{
        'cardio-001': 2,
        'cardio-002': 1,
        'cardio-003': 0,
      },
    );

    const UnitRepository repo = UnitRepository();
    expect(await _systemOrder(repo, 'cardiovascular'),
        <String>['cardio-003', 'cardio-002', 'cardio-001']);
  });
}

/// ترتيب معرفات وحدات جهاز معين كما ستُعرض (حسب order_index).
Future<List<String>> _systemOrder(UnitRepository repo, String system) async {
  final List<Unit> units = await _unitsOf(repo, system);
  return <String>[for (final Unit u in units) u.id];
}

/// قيم order_index لوحدات جهاز معين بترتيب العرض.
Future<List<int>> _systemOrderIndexes(
    UnitRepository repo, String system) async {
  final List<Unit> units = await _unitsOf(repo, system);
  return <int>[for (final Unit u in units) u.orderIndex];
}

Future<List<Unit>> _unitsOf(UnitRepository repo, String system) async {
  final List<Unit> all = await repo.getAllUnits();
  return <Unit>[
    for (final Unit u in all)
      if (u.system == system) u,
  ]..sort((Unit a, Unit b) => a.orderIndex.compareTo(b.orderIndex));
}
