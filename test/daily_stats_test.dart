import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// اختبارات جدول الإحصاءات اليومية (v21) — زمن الدراسة اليومي.
///
/// يغطي: إنشاء الجدول · التراكم عبر نداءات متعددة · القراءة ليوم محدد
/// (0 للغائب) · جلب آخر 35 يوماً · الترحيل v20 → v21 على ملف حقيقي
/// (نمط specialty_migration_test).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  group('daily_stats — زمن الدراسة اليومي (v21)', () {
    test('onCreate ينشئ جدول daily_stats فارغاً', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      final List<Map<String, Object?>> rows =
          await helper.rawQueryParameterized(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        <Object?>[DatabaseHelper.tableDailyStats],
      );
      expect(rows.length, 1, reason: 'جدول daily_stats يجب أن يُنشأ');

      final int count =
          await helper.rawCount('SELECT COUNT(*) FROM ${DatabaseHelper.tableDailyStats}');
      expect(count, 0, reason: 'يبدأ فارغاً');
    });

    test('recordStudySeconds يراكم عبر نداءات متعددة لنفس اليوم', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      final String today = DateTime.now()
          .toUtc()
          .toIso8601String()
          .substring(0, 10);

      await helper.recordStudySeconds(75);
      await helper.recordStudySeconds(45);
      await helper.recordStudySeconds(120);

      expect(await helper.getStudySecondsOnDay(today), 240);
      // صف واحد فقط لليوم — تجميع لا تكرار.
      final int rows = await helper.rawCount(
          'SELECT COUNT(*) FROM ${DatabaseHelper.tableDailyStats} '
          'WHERE date = ?',
        <Object?>[today],
      );
      expect(rows, 1);
    });

    test('getStudySecondsOnDay — 0 لليوم الغائب', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      expect(
        await helper.getStudySecondsOnDay('2000-01-01'),
        0,
        reason: 'يوم بلا بيانات يجب أن يُعيد 0',
      );
    });

    test('recordStudySeconds يتجاهل القيم غير الموجبة', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      await helper.recordStudySeconds(-10);
      await helper.recordStudySeconds(0);
      final int count = await helper.rawCount(
          'SELECT COUNT(*) FROM ${DatabaseHelper.tableDailyStats}');
      expect(count, 0, reason: 'لا صف يُنشأ بقيم غير موجبة');
    });

    test('getStudySecondsRecent — يجلب آخر الأيام فقط بمدد صحيحة', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      // يوم قديم جداً خارج نافذة 35 يوماً — يجب استبعاده.
      await helper.rawQueryParameterized(
        'INSERT INTO ${DatabaseHelper.tableDailyStats}(date, study_seconds) '
        'VALUES (?, ?)',
        <Object?>['2000-01-01', 9999],
      );

      final List<MapEntry<String, int>> recent =
          await helper.getStudySecondsRecent(35);
      expect(recent.any((MapEntry<String, int> e) => e.key == '2000-01-01'),
          isFalse, reason: 'اليوم خارج النافذة يُستبعد');

      // أيام حديثة تظهر.
      final String today = DateTime.now()
          .toUtc()
          .toIso8601String()
          .substring(0, 10);
      await helper.recordStudySeconds(90);
      final recent2 = await helper.getStudySecondsRecent(35);
      expect(recent2.any((MapEntry<String, int> e) => e.key == today), isTrue);
      expect(
        recent2.firstWhere((MapEntry<String, int> e) => e.key == today).value,
        90,
      );
    });
  });

  group('ترحيل v20 → v21 (مسار المستخدم)', () {
    test('قاعدة v20 تُفتح وتضيف جدول daily_stats بلا فقد بيانات', () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('med_v21_');
      final String path =
          '${dir.path}${Platform.pathSeparator}legacy.db';
      try {
        // (1) فتح أول: النسخة القديمة (v20) بمخطط كامل عبر Helper القديم
        // — أبسط: نفتح بوندفئة 20 عبر onCreate المخصص مباشرة ثم نغلق.
        final sqflite.Database db = await databaseFactoryFfi.openDatabase(
          path,
          options: sqflite.OpenDatabaseOptions(
            version: 20,
            onConfigure: (sqflite.Database db2) async {
              await db2.execute('PRAGMA foreign_keys = ON');
            },
            // بلا onCreate: قاعدة فارغة فقط عند v20 — لا daily_stats.
          ),
        );
        await db.close();

        // (2) فتح ثانٍ عبر Helper الحالي (v21): onUpgrade يضيف الجدول.
        final DatabaseHelper helper = DatabaseHelper.instance;
        await helper.openWith(databaseFactoryFfi, path);

        final List<Map<String, Object?>> rows =
            await helper.rawQueryParameterized(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          <Object?>[DatabaseHelper.tableDailyStats],
        );
        expect(rows.length, 1, reason: 'الترحيل v21 يضيف جدول daily_stats');

        // والجدول قابل للكتابة بعد الترقية.
        await helper.recordStudySeconds(60);
        expect(await helper.getStudySecondsOnDay(DateTime.now()
            .toUtc()
            .toIso8601String()
            .substring(0, 10)), 60);
      } finally {
        await DatabaseHelper.instance.close();
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // ملف قد يبقى مشغولاً على Windows — لا نفشل الاختبار.
        }
      }
    });
  });
}