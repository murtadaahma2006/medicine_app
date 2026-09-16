import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

/// مزوّد مجلد المستندات — توفّره طبقة الواجهة عبر path_provider
/// (الحقن يبقي الخدمة نقية وقابلة للاختبار على FFI بلا قنوات المنصة).
typedef DocumentsDirProvider = Future<Directory> Function();

/// مصدر مجلد المستندات الفعلي (يضبط مرة من main أو الواجهة).
/// الافتراضي: مجلد مؤقت (بيئات الاختبار) — الإنتاج يضبط path_provider.
DocumentsDirProvider documentsDirProvider =
    () async => Directory.systemTemp;

/// خدمة النسخ الاحتياطي — تصدير/استيراد بيانات المستخدم
/// باستخدام "النسخ الشامل" (Universal Backup).
///
/// **الضمانات**:
/// - **التصدير**: يتم إغلاق القاعدة لضمان اكتمال الكتابة (WAL flush)،
///   ثم نسخ ملف `.db` كاملاً، وحقن `SharedPreferences` داخله.
///   هذا يضمن حفظ كافة جداول المحتوى والتقدم الحالية والمستقبلية.
/// - **الاستيراد**: يدعم استيراد `.db` الجديد أو `.json` القديم (كخيار تراجعي).
///   عند استيراد `.db`، تُستبدل القاعدة بالكامل بعد استخراج التفضيلات.
abstract final class BackupService {
  /// الملف داخل Documents/MedicineApp/Backups.
  static Future<Directory> backupDir() async {
    final Directory root = await documentsDirProvider();
    final Directory dir =
        Directory(p.join(root.path, 'MedicineApp', 'Backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// اسم الملف الموحد: مخطط + طابع زمني + امتداد .db.
  static String fileNameFor(DateTime now) =>
      'medical_backup_v${DatabaseHelper.databaseVersion}_'
      '${now.millisecondsSinceEpoch}.db';

  // ───────────────────────────── التصدير ─────────────────────────────

  /// يصدّر نسخة كاملة لملف القاعدة مع حقن التفضيلات.
  static Future<BackupExportResult> export({
    Map<String, Object?>? preferences,
  }) async {
    try {
      final DatabaseHelper helper = DatabaseHelper.instance;

      // 1. الإغلاق الآمن لفرض دمج تغييرات الـ WAL في الملف الأساسي
      await helper.close();

      final String dbDir = await getDatabasesPath();
      final String originalDbPath = p.join(dbDir, DatabaseHelper.databaseName);

      final Directory bDir = await backupDir();
      final String backupPath = p.join(bDir.path, fileNameFor(DateTime.now()));

      // 2. نسخ الملف الفيزيائي بالكامل
      await File(originalDbPath).copy(backupPath);

      // 3. إعادة فتح القاعدة الأساسية ليستمر التطبيق بالعمل طبيعياً
      await helper.database;

      // 4. حقن التفضيلات (SharedPreferences) داخل ملف النسخة الاحتياطية كجدول مخفي
      if (preferences != null && preferences.isNotEmpty) {
        final Database backupDb = await openDatabase(backupPath);
        await backupDb.execute(
          'CREATE TABLE IF NOT EXISTS _preferences_backup (key TEXT PRIMARY KEY, value_json TEXT)',
        );
        final Batch batch = backupDb.batch();
        preferences.forEach((String key, Object? value) {
          batch.insert(
            '_preferences_backup',
            <String, Object?>{'key': key, 'value_json': jsonEncode(value)},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
        await batch.commit(noResult: true);
        await backupDb.close();
      }

      return BackupExportResult(
        ok: true,
        filePath: backupPath,
        itemCount: preferences?.length ?? 0,
      );
    } catch (error) {
      debugPrint('BackupService: فشل التصدير ($error)');
      // في حال الفشل، نضمن إعادة فتح القاعدة الأساسية لكي لا يتعطل التطبيق
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      
      return const BackupExportResult(
        ok: false,
        messageAr: 'تعذّر إنشاء النسخة الاحتياطية — تحقق من مساحة التخزين.',
      );
    }
  }

  // ───────────────────────────── الاستيراد ─────────────────────────────

  /// يستورد نسخة احتياطية: يقرر ما إذا كان الملف .db جديد أو .json قديم.
  static Future<BackupImportResult> importFromFile(
    String path, {
    void Function(Map<String, Object?> prefs)? onPreferences,
  }) async {
    final File file = File(path);
    if (!await file.exists()) {
      return const BackupImportResult(
        ok: false,
        messageAr: 'الملف غير موجود.',
      );
    }

    final String extension = p.extension(path).toLowerCase();
    if (extension == '.json') {
      return _importLegacyJson(path, onPreferences: onPreferences);
    } else if (extension == '.db') {
      return _importUniversalDb(path, onPreferences: onPreferences);
    } else {
      return const BackupImportResult(
        ok: false,
        messageAr: 'صيغة الملف غير مدعومة (فقط .db أو .json).',
      );
    }
  }

  /// الاستيراد الشامل (Universal Backup) باستبدال ملف القاعدة الفيزيائي.
  static Future<BackupImportResult> _importUniversalDb(
    String path, {
    void Function(Map<String, Object?> prefs)? onPreferences,
  }) async {
    Database? importedDb;
    try {
      // 1. فتح ملف النسخة كقاعدة بيانات للتحقق منه واستخراج التفضيلات
      importedDb = await openDatabase(path, readOnly: true);
      
      final List<Map<String, Object?>> tables = await importedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      
      // تحقق بسيط من صحة القاعدة الطبية
      if (!tables.any((Map<String, Object?> t) => t['name'] == DatabaseHelper.tableUnits)) {
        await importedDb.close();
        return const BackupImportResult(
          ok: false,
          messageAr: 'الملف المختار ليس نسخة احتياطية صالحة لـ MedOS.',
        );
      }

      // استخراج التفضيلات المحقونة (إن وجدت)
      if (tables.any((Map<String, Object?> t) => t['name'] == '_preferences_backup')) {
        final List<Map<String, Object?>> prefsRows = await importedDb.query('_preferences_backup');
        final Map<String, Object?> extractedPrefs = <String, Object?>{};
        for (final Map<String, Object?> row in prefsRows) {
          extractedPrefs[row['key'] as String] = jsonDecode(row['value_json'] as String);
        }
        if (extractedPrefs.isNotEmpty) {
          onPreferences?.call(extractedPrefs);
        }
      }
      
      await importedDb.close();

      // 2. الاستبدال الفيزيائي لقاعدة بيانات التطبيق
      final DatabaseHelper helper = DatabaseHelper.instance;
      // إغلاق القاعدة لفك القفل عنها
      await helper.close();

      final String dbDir = await getDatabasesPath();
      final String liveDbPath = p.join(dbDir, DatabaseHelper.databaseName);

      // مسح ملفات WAL و SHM المؤقتة إن وجدت لتجنب التلف بعد استبدال الملف الأساسي
      final File walFile = File('$liveDbPath-wal');
      final File shmFile = File('$liveDbPath-shm');
      if (walFile.existsSync()) await walFile.delete();
      if (shmFile.existsSync()) await shmFile.delete();

      // الكتابة فوق الملف المباشر
      await File(path).copy(liveDbPath);

      // لن نقوم بإعادة فتح القاعدة هنا، سيقوم الـ UI بإعادة توجيه المستخدم لـ SplashPage 
      // والتي ستقوم بتحميل القاعدة من الصفر بشكل طبيعي وآمن.
      
      return const BackupImportResult(
        ok: true,
        messageAr: 'تمت الاستعادة بنجاح. سيتم إعادة تشغيل التطبيق.',
      );
    } catch (error) {
      debugPrint('BackupService: فشل الاستيراد الشامل ($error)');
      await importedDb?.close();
      // محاولة إنقاذ القاعدة الحالية
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      return const BackupImportResult(
        ok: false,
        messageAr: 'فشل استيراد القاعدة — بياناتك الحالية لم تتأثر.',
      );
    }
  }

  /// الاستيراد القديم (Legacy JSON) لدعم النسخ السابقة (Backward Compatibility).
  static Future<BackupImportResult> _importLegacyJson(
    String path, {
    void Function(Map<String, Object?> prefs)? onPreferences,
  }) async {
    final File file = File(path);
    Map<String, Object?> data;
    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const BackupImportResult(
          ok: false,
          messageAr: 'الملف ليس نسخة احتياطية صالحة.',
        );
      }
      data = decoded.map(
        (Object? k, Object? v) => MapEntry(k.toString(), v),
      );
    } catch (_) {
      return const BackupImportResult(
        ok: false,
        messageAr: 'الملف تالف أو ليس بصيغة JSON.',
      );
    }

    final String? structuralError = _validateStructure(data);
    if (structuralError != null) {
      return BackupImportResult(ok: false, messageAr: structuralError);
    }

    final int schemaVersion = data['schema_version']! as int;
    if (schemaVersion != DatabaseHelper.databaseVersion) {
      return BackupImportResult(
        ok: false,
        messageAr: 'نسخة بمخطط مغاير ($schemaVersion مقابل '
            '${DatabaseHelper.databaseVersion}).',
      );
    }

    try {
      final DatabaseHelper helper = DatabaseHelper.instance;
      final Database db = await helper.database;
      final Object? tablesRaw = data['data'];
      if (tablesRaw is! Map) {
        return const BackupImportResult(
          ok: false,
          messageAr: 'بيانات النسخة تالفة.',
        );
      }
      final Map<String, Object?> tables = _stringKeyed(tablesRaw);

      await db.transaction((Transaction txn) async {
        await txn.delete(DatabaseHelper.tableUserProgress);
        await txn.delete(DatabaseHelper.tableCorrections);
        await txn.delete(DatabaseHelper.tableXpEvents);
        await txn.delete(DatabaseHelper.tableSrsCards);
        await txn.delete(DatabaseHelper.tableUnlockedBadges);

        await _insertRows(
            txn, DatabaseHelper.tableUserProgress, tables['user_progress']);
        await _insertRows(
            txn, DatabaseHelper.tableCorrections, tables['corrections']);
        await _insertRows(
            txn, DatabaseHelper.tableXpEvents, tables['xp_events']);
        await _insertRows(
            txn, DatabaseHelper.tableSrsCards, tables['srs_cards']);
        await _insertRows(txn, DatabaseHelper.tableUnlockedBadges,
            tables['unlocked_badges']);
      });

      final Object? rawPrefs = tables['preferences'];
      final Map<String, Object?> prefs =
          rawPrefs is Map ? _stringKeyed(rawPrefs) : const <String, Object?>{};
      if (prefs.isNotEmpty) {
        onPreferences?.call(prefs);
      }

      return BackupImportResult(
        ok: true,
        messageAr: 'تمت الاستعادة بنجاح من ملف JSON القديم. سيتم إعادة التشغيل.',
        itemCount: _countRows(data),
      );
    } catch (error) {
      debugPrint('BackupService: فشل الاستيراد القديم ($error)');
      return const BackupImportResult(
        ok: false,
        messageAr: 'فشل الاستيراد — بياناتك الحالية لم تتأثر.',
      );
    }
  }

  static int _countRows(Map<String, Object?> data) {
    final Object? raw = data['data'];
    if (raw is! Map) return 0;
    int count = 0;
    for (final Object? v in raw.values) {
      if (v is List) count += v.length;
    }
    return count;
  }

  static String? _validateStructure(Map<String, Object?> data) {
    if (data['schema_version'] is! int) {
      return 'الملف ينقصه رقم المخطط أو تالف.';
    }
    if (data['app'] != 'medicine_app') {
      return 'الملف ليس نسخة احتياطية لهذا التطبيق.';
    }
    final Object? tablesRaw = data['data'];
    if (tablesRaw is! Map) {
      return 'بيانات النسخة تالفة (قسم data مفقود).';
    }
    final Map<Object?, Object?> tables = tablesRaw;
    const List<String> required = <String>[
      'user_progress',
      'corrections',
      'xp_events',
      'srs_cards',
      'unlocked_badges',
    ];
    for (final String key in required) {
      if (tables[key] is! List) {
        return 'النسخة ينقصها جدول «$key» أو تالف.';
      }
    }
    return null;
  }

  static Map<String, Object?> _stringKeyed(Map raw) =>
      raw.map((Object? k, Object? v) => MapEntry(k.toString(), v));

  static List<Map<String, Object?>> _asRows(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map(_stringKeyed)
          .map<Map<String, Object?>>(
              (Map<String, Object?> m) => m)
          .toList()
      : <Map<String, Object?>>[];

  static Future<void> _insertRows(
    DatabaseExecutor txn,
    String table,
    Object? raw,
  ) async {
    for (final Map<String, Object?> row in _asRows(raw)) {
      await txn.insert(table, row);
    }
  }
}

/// نتيجة التصدير.
class BackupExportResult {
  const BackupExportResult({
    required this.ok,
    this.filePath,
    this.messageAr,
    this.itemCount = 0,
  });

  final bool ok;
  final String? filePath;
  final String? messageAr;
  final int itemCount;
}

/// نتيجة الاستيراد.
class BackupImportResult {
  const BackupImportResult({
    required this.ok,
    required this.messageAr,
    this.itemCount = 0,
  });

  final bool ok;
  final String messageAr;
  final int itemCount;
}
