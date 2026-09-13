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
/// إلى ملف JSON واحد قابل للمشاركة.
///
/// **الضمانات**:
/// - **التصدير**: كل جداول المستخدم (user_progress, corrections,
///   xp_events, srs_cards, unlocked_badges) + التفضيلات
///   مع رقم المخطط وطابع زمني — لا يمس المحتوى أبداً.
/// - **الاستيراد**: تحقق بنيوي صارم ثم استبدال التقدم الحالي داخل
///   **معاملة واحدة** — الاستثناء الوحيد المسموح فيه DELETE (قاعدة
///   القسم 2): **جداول المستخدم فقط**، المحتوى لا يُمس.
/// - رفض مهذب لكل الحالات (ملف تالف/مخطط مغاير/مفاتيح ناقصة) — لا
///   استثناءات تصل المستخدم، وفشل الاستيراد لا يمس بياناته الحالية.
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

  /// اسم الملف الموحد: مخطط + طابع زمني.
  static String fileNameFor(DateTime now) =>
      'medical_backup_v${DatabaseHelper.databaseVersion}_'
      '${now.millisecondsSinceEpoch}.json';

  // ───────────────────────────── التصدير ─────────────────────────────

  /// يصدّر نسخة JSON كاملة. [preferences] يجمعها المستدعي من
  /// SharedPreferences (تفكيك الاعتماد — قابل للاختبار).
  static Future<BackupExportResult> export({
    Map<String, Object?>? preferences,
  }) async {
    try {
      final DatabaseHelper helper = DatabaseHelper.instance;
      final Database db = await helper.database;

      final Map<String, Object?> data = <String, Object?>{
        'schema_version': DatabaseHelper.databaseVersion,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'app': 'medicine_app',
        'data': <String, Object?>{
          'user_progress':
              await db.query(DatabaseHelper.tableUserProgress),
          'corrections':
              await db.query(DatabaseHelper.tableCorrections),
          'xp_events': await db.query(DatabaseHelper.tableXpEvents),
          'srs_cards': await db.query(DatabaseHelper.tableSrsCards),
          'unlocked_badges':
              await db.query(DatabaseHelper.tableUnlockedBadges),
          'preferences': preferences ?? const <String, Object?>{},
        },
      };

      final Directory dir = await backupDir();
      final File file =
          File(p.join(dir.path, fileNameFor(DateTime.now())));
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(data));

      return BackupExportResult(
        ok: true,
        filePath: file.path,
        itemCount: _countRows(data),
      );
    } catch (error) {
      debugPrint('BackupService: فشل التصدير ($error)');
      return const BackupExportResult(
        ok: false,
        messageAr: 'تعذّر إنشاء النسخة الاحتياطية — تحقق من مساحة التخزين.',
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

  // ───────────────────────────── الاستيراد ─────────────────────────────

  /// يستورد نسخة احتياطية: تحقق بنيوي ثم استبدال داخل معاملة واحدة.
  /// [onPreferences] يستقبل التفضيلات ليعيد تطبيقها خارج القاعدة.
  static Future<BackupImportResult> importFromFile(
    String path, {
    void Function(Map<String, Object?> prefs)? onPreferences,
  }) async {
    // (1) قراءة + فك JSON.
    final File file = File(path);
    if (!await file.exists()) {
      return const BackupImportResult(
        ok: false,
        messageAr: 'الملف غير موجود.',
      );
    }
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

    // (2) تحقق بنيوي — رفض مهذل بتفاصيل السبب.
    final String? structuralError = _validateStructure(data);
    if (structuralError != null) {
      return BackupImportResult(ok: false, messageAr: structuralError);
    }

    // (3) توافق رقم المخطط — رفض مهذل عند الاختلاف (القرار الموثق:
    //     لا ترقية آلية داخل ملف استعادة — سلامة البيانات أولاً).
    final int schemaVersion = data['schema_version']! as int;
    if (schemaVersion != DatabaseHelper.databaseVersion) {
      return BackupImportResult(
        ok: false,
        messageAr: 'نسخة بمخطط مغاير ($schemaVersion مقابل '
            '${DatabaseHelper.databaseVersion}) — لا يمكن الاستيراد '
            'بأمان. استخدم نسخة من نفس إصدار التطبيق.',
      );
    }

    // (4) الاستبدال — معاملة واحدة، جداول المستخدم فقط.
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
        // الاستثناء الوحيد المسموح بـDELETE — بيانات المستخدم فقط.
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

      // (5) التفضيلات — تطبيق خارج القاعدة عبر المستدعي.
      final Object? rawPrefs = tables['preferences'];
      final Map<String, Object?> prefs =
          rawPrefs is Map ? _stringKeyed(rawPrefs) : const <String, Object?>{};
      if (prefs.isNotEmpty) {
        onPreferences?.call(prefs);
      }

      return BackupImportResult(
        ok: true,
        messageAr: 'تمت الاستعادة بنجاح.',
        itemCount: _countRows(data),
      );
    } catch (error) {
      debugPrint('BackupService: فشل الاستيراد ($error)');
      return const BackupImportResult(
        ok: false,
        messageAr: 'فشل الاستيراد — بياناتك الحالية لم تتأثر.',
      );
    }
  }

  /// فحص بنيوي: المفاتيح الإلزامية وأنواعها وقوائم الجداول.
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
    return null; // سليم بنيوياً.
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
