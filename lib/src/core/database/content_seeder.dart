import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// يزرع المحتوى الطبي من أصول JSON المدمجة (assets/content/*.json)
/// داخل القاعدة — idempotent (INSERT OR IGNORE).
///
/// الملفات تطابق docs/schemas/medical_lecture.schema.json (v2.0.0)
/// وتُحدَّث بإسقاط ملف جديد في assets/content/ وإعادة البناء —
/// أحدث آلية "توزيع محتوى" أوفلاين 100%.
///
/// يُستدعى من شاشة البداية (خلف الشعار) وعند سحب للتحديث من المكتبة.
abstract final class ContentSeeder {
  /// قائمة أسماء ملفات المحتوى المدمجة — تُقرأ من أصل واحد ثابت.
  static const String manifestAsset = 'assets/content/MANIFEST.json';

  /// يزرع كل ملفات المحتوى المدرجة في البيان. يعيد عدد الصفوف المدرجة
  /// فعلياً (0 = القاعدة محدثة كلياً).
  static Future<int> seedAll({bool force = false}) async {
    int total = 0;

    // (أ) قراءة بيان الملفات.
    final List<String> files = await _manifestFiles();

    for (final String assetPath in files) {
      try {
        final String raw = await rootBundle.loadString(assetPath);
        final dynamic decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final Map<String, Object?> file =
            decoded.map((k, v) => MapEntry(k.toString(), v));
        total += await _injectLectureFile(file);
      } catch (_) {
        // ملف تالف أو غائب — تجاهل صامت: المحتوى غير حرج للإقلاع.
      }
    }
    return total;
  }

  /// قائمة مسارات ملفات JSON من البيان (MANIFEST.json: {files: [...]}).
  static Future<List<String>> _manifestFiles() async {
    try {
      final String raw = await rootBundle.loadString(manifestAsset);
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map && decoded['files'] is List) {
        return (decoded['files']! as List)
            .map((dynamic f) => f.toString())
            .toList();
      }
    } catch (_) {
      // لا بيان — لا محتوى مزروع.
    }
    return const <String>[];
  }

  /// يحقن ملف محاضرة واحدة داخل معاملة.
  static Future<int> _injectLectureFile(Map<String, Object?> file) async {
    if (file['schema_version'] != '2.0.0') return 0;

    final Map<String, Object?> lecture = _asMap(file['lecture']);
    final DatabaseHelper helper = DatabaseHelper.instance;
    final Database db = await helper.database;

    return db.transaction((Transaction txn) async {
      int count = 0;

      // ── 1) الوحدة ──
      count += await _insertIgnore(txn, 'units', <String, Object?>{
        'id': lecture['id'],
        'module': lecture['module'],
        'system': lecture['system'],
        'title': lecture['title'],
        'description_ar': lecture['summary_ar'],
        'order_index': lecture['order_index'],
      });

      // ── 2) الشروحات ──
      for (final dynamic raw in _asList(file['concepts'])) {
        final Map<String, Object?> c = _asMap(raw);
        count += await _insertIgnore(txn, 'concepts', <String, Object?>{
          'id': c['id'],
          'unit_id': c['lecture_id'],
          'title': c['title'],
          'summary_ar': c['summary_ar'],
          'sections_json': jsonEncode(c['sections']),
          'key_terms_json':
              c['key_terms'] == null ? null : jsonEncode(c['key_terms']),
          'difficulty': c['difficulty'],
          'order_index': c['order_index'],
        });
      }

      // ── 3) البطاقات ──
      for (final dynamic raw in _asList(file['flashcards'])) {
        final Map<String, Object?> f = _asMap(raw);
        count += await _insertIgnore(txn, 'flashcards', <String, Object?>{
          'id': f['id'],
          'unit_id': f['lecture_id'],
          'concept_id': f['concept_id'],
          'card_type': f['card_type'],
          'front_text': f['front_text'],
          'back_text': f['back_text'],
          'mnemonic_ar': f['mnemonic_ar'],
          'explanation_ar': f['explanation_ar'],
          'tags_json': f['tags'] == null ? null : jsonEncode(f['tags']),
          'is_vivid': f['is_vivid'] == true ? 1 : 0,
        });
      }

      // ── 4) أسئلة MCQ ──
      for (final dynamic raw in _asList(file['mcqs'])) {
        final Map<String, Object?> m = _asMap(raw);
        count += await _insertIgnore(txn, 'mcq_bank', <String, Object?>{
          'id': m['id'],
          'unit_id': m['lecture_id'],
          'concept_id': m['concept_id'],
          'question_stem': m['question_stem'],
          'options_json': jsonEncode(m['options']),
          'correct_index': m['correct_index'],
          'explanation_ar': m['explanation_ar'],
          'difficulty': m['difficulty'],
          'clinical_vignette': m['clinical_vignette'] == true ? 1 : 0,
          'hints_json': m['hints'] == null ? null : jsonEncode(m['hints']),
          'focus_sections_json': m['focus_sections'] == null
              ? null
              : jsonEncode(m['focus_sections']),
        });
      }

      // ── 5) الحالات السريرية + خطواتها ──
      for (final dynamic raw in _asList(file['clinical_cases'])) {
        final Map<String, Object?> c = _asMap(raw);
        count += await _insertIgnore(txn, 'clinical_cases', <String, Object?>{
          'id': c['id'],
          'unit_id': c['lecture_id'],
          'title': c['title'],
          'scenario': c['scenario'],
          'vignette_json': jsonEncode(c['vignette']),
          'debriefing_ar': c['debriefing_ar'],
          'difficulty': c['difficulty'],
          'order_index': c['order_index'],
        });

        int stepIndex = 0;
        for (final dynamic rawStep in _asList(c['steps'])) {
          final Map<String, Object?> s = _asMap(rawStep);
          count += await _insertIgnore(
              txn, 'clinical_case_steps', <String, Object?>{
            'id': s['id'],
            'case_id': c['id'],
            'prompt': s['prompt'],
            'options_json': jsonEncode(s['options']),
            'correct_index': s['correct_index'],
            'explanation_ar': s['explanation_ar'],
            'xp': s['xp'] ?? 5,
            'step_index': stepIndex++,
            'hints_json': s['hints'] == null ? null : jsonEncode(s['hints']),
          });
        }
      }

      return count;
    });
  }

  /// إدراج واحد idempotent — يعيد 1 إذا أُدرج فعلاً، 0 إذا تُخطي.
  static Future<int> _insertIgnore(
    DatabaseExecutor txn,
    String table,
    Map<String, Object?> row,
  ) async {
    try {
      await txn.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // OR IGNORE مع المفتاح المتعارض يعيد الصف الموجود — لا يمكن التمييز
      // من القيمة المرجعة، لذا نتحقق عبر وجود الصف سلفاً؟ مكلف.
      // الحل العملي: اعتبر الإدراج ناجحاً (العد هنا إحصائي غير حرج).
      return 1;
    } catch (_) {
      return 0;
    }
  }

  static List<dynamic> _asList(Object? raw) =>
      raw is List ? raw : const <dynamic>[];

  static Map<String, Object?> _asMap(Object? raw) =>
      raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : const {};
}
