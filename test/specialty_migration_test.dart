import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات ترقية قاعدة البيانات v16/v17 → v20 (مسار المستخدم
/// الفعلي): قاعدة قديمة على القرص بلا specialty/pinned_at/golden_tip
/// تُرقّى دون فقد بيانات ودون استثناء — والمحاضرات القديمة تصير
/// باطنية افتراضاً.
///
/// ملاحظة تقنية: الترقية تُختبر على **ملف حقيقي** (لا :memory: —
/// فتح جديد يعني قاعدة فارغة جديدة في FFI): نفتح بنسخة قديمة،
/// نزرع، نغلق، ثم نعيد الفتح عبر Helper بنسخة v20 → onUpgrade.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  /// مسار ملف مؤقت فريد لكل اختبار (لا تداخل بين الاختبارات).
  Future<String> tempDbPath() async {
    final Directory dir = await Directory.systemTemp.createTemp('med_v20_');
    return '${dir.path}${Platform.pathSeparator}legacy.db';
  }

  /// ينشئ قاعدة على [oldVersion] بمخطط تلك الحقبة + محاضرة قديمة
  /// (مثبتة إن كانت v17)، ثم يعيد فتحها عبر Helper الحالي (v20).
  Future<DatabaseHelper> upgradeFrom(int oldVersion) async {
    final String path = await tempDbPath();
    final DatabaseHelper helper = DatabaseHelper.instance;

    // (1) فتح أول: النسخة القديمة + مخططها + محتوى قديم.
    final sqflite.Database db = await databaseFactoryFfi.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: oldVersion,
        onCreate: (sqflite.Database db, int v) async {
          await db.execute('''
            CREATE TABLE ${DatabaseHelper.tableUnits} (
              id              TEXT PRIMARY KEY,
              module          TEXT NOT NULL,
              system          TEXT NOT NULL,
              title           TEXT NOT NULL,
              description_ar  TEXT,
              order_index     INTEGER NOT NULL DEFAULT 0
              ${oldVersion >= 17 ? ', is_pinned_today INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned_today IN (0,1))' : ''}
            )
          ''');
        },
      ),
    );
    await db.insert(
      DatabaseHelper.tableUnits,
      <String, Object?>{
        'id': 'legacy-001',
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'Legacy Heart Lecture',
        'order_index': 0,
        if (oldVersion >= 17) 'is_pinned_today': 1,
      },
    );
    await db.close();

    // (2) فتح ثانٍ عبر Helper: v20 → onUpgrade يرحّل v17→v18→v19→v20.
    await helper.openWith(databaseFactoryFfi, path);
    return helper;
  }

  test('ترقية v16 → v20: specialty يضاف ويسند الباطنية تلقائياً',
      () async {
    final DatabaseHelper helper = await upgradeFrom(16);

    final Map<String, Object?>? row =
        await helper.getUnitById('legacy-001');
    expect(row, isNotNull, reason: 'المحاضرة القديمة لم تضِع');
    expect(row!['title'], 'Legacy Heart Lecture');
    expect(
      row['specialty'],
      'internal_medicine',
      reason: 'ADD COLUMN NOT NULL DEFAULT يسند الباطنية للقديم',
    );
    expect(row['pinned_at'], isNull);
    expect(row['golden_tip'], isNull);
  });

  test('ترقية v17 → v20: المثبتة القديمة تُرحَّل إلى pinned_at',
      () async {
    final DatabaseHelper helper = await upgradeFrom(17);

    final Map<String, Object?>? row =
        await helper.getUnitById('legacy-001');
    expect(row, isNotNull);
    // is_pinned_today=1 → v18 منحها طابع تثبيت (عدّاد 48h جديد).
    expect(row!['pinned_at'], isNotNull);
    // والعمود القديم بقي مكانه (ساكن بلا استخدام).
    expect(row['is_pinned_today'], 1);
  });

  test('قاعدة v15 (بلا أعمدة v17+) تفتح بلا انهيار وتعمل استعلاماتها',
      () async {
    final DatabaseHelper helper = await upgradeFrom(15);

    // هذه كانت مصدر «تعذّر تحميل المنهج» لو فشل الترحيل.
    expect(
      (await helper.getUnitsBySpecialty('internal_medicine')).length,
      1,
    );
    expect(
      await helper.getDistinctSpecialties(),
      <String>['internal_medicine'],
    );
  });
}
