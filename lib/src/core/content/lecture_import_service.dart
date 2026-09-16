import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import 'specialty_domains.dart';

/// نتيجة التحقق من ملف محاضرة (بدون زرع).
class LectureValidationResult {
  const LectureValidationResult({
    required this.ok,
    this.messageAr,
    this.title,
    this.module,
    this.conceptCount = 0,
    this.flashcardCount = 0,
    this.mcqCount = 0,
    this.caseCount = 0,
    this.alreadyExists = false,
  });

  final bool ok;
  final String? messageAr;
  final String? title;
  final String? module;
  final int conceptCount;
  final int flashcardCount;
  final int mcqCount;
  final int caseCount;

  /// المحاضرة موجودة مسبقاً في القاعدة (سيتم تخطيها — idempotent).
  final bool alreadyExists;
}

/// نتيجة الاستيراد الكامل (تحقق + زرع).
class LectureImportResult {
  const LectureImportResult({
    required this.ok,
    required this.messageAr,
    this.title,
    this.insertedRows = 0,
    this.skipped = false,
  });

  final bool ok;
  final String messageAr;
  final String? title;
  final int insertedRows;

  /// true = المحاضرة موجودة مسبقاً وتخطاها الاستيراد.
  final bool skipped;
}

/// خدمة استيراد المحاضرات من ملفات JSON على الجهاز
/// (Downloads أو أي مسار) — نفس عقد البيانات v2.0.0
/// (docs/schemas/medical_lecture.schema.json).
///
/// **الضمانات**:
/// - تحقق بنيوي صارم مطابق للـ Schema قبل أي كتابة.
/// - الزرع داخل معاملة واحدة — فشل منتصف الملف لا يترك أثراً جزئياً.
/// - INSERT OR IGNORE — آمن عند إعادة الاستيراد (idempotent).
/// - لا يمس بيانات المستخدم (تقدم/إجابات/XP) إطلاقاً.
abstract final class LectureImportService {
  // ── القوائم المسموحة (v21: عبر كل التخصصات — مصدر الحقيقة
  //    SpecialtyDomains؛ القوائم هنا مجموع مسموح للتحقق البنيوي) ──
  static final Set<String> _modules = SpecialtyDomains.allModules;
  static final Set<String> _systems = SpecialtyDomains.allSystems;

  // ───────────────────────────── التحقق ─────────────────────────────

  /// يتحقق من ملف على القرص ويعيد ملخصاً بلا كتابة في القاعدة.
  static Future<LectureValidationResult> validateFile(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      return const LectureValidationResult(
        ok: false,
        messageAr: 'الملف غير موجود.',
      );
    }

    Map<String, Object?> data;
    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const LectureValidationResult(
          ok: false,
          messageAr: 'بنية الملف غير صحيحة — المتوقع كائن JSON.',
        );
      }
      data = decoded.map(
        (Object? k, Object? v) => MapEntry(k.toString(), v),
      );
    } catch (_) {
      return const LectureValidationResult(
        ok: false,
        messageAr: 'الملف تالف أو ليس بصيغة JSON.',
      );
    }

    final String? error = validateMap(data);
    if (error != null) {
      return LectureValidationResult(ok: false, messageAr: error);
    }

    final Map<String, Object?> lecture =
        (data['lecture']! as Map).map(_stringEntry);
    final String lectureId = lecture['id']! as String;

    // هل الوحدة موجودة مسبقاً؟ (زرع idempotent — معلومة للمستخدم).
    final bool exists = await _unitExists(lectureId);

    return LectureValidationResult(
      ok: true,
      title: lecture['title']! as String,
      module: lecture['module']! as String,
      conceptCount: _asList(data['concepts']).length,
      flashcardCount: _asList(data['flashcards']).length,
      mcqCount: _asList(data['mcqs']).length,
      caseCount: _asList(data['clinical_cases']).length,
      alreadyExists: exists,
    );
  }

  /// تحقق بنيوي كامل من decoded JSON (Map مسطح بمفاتيح String).
  /// يعيد null عند الصلاحية أو رسالة خطأ عربية عند الفشل.
  static String? validateMap(Map<String, Object?> data) {
    if (data['schema_version'] != '2.0.0') {
      return 'الملف ليس بنسخة العقد 2.0.0 — لا يمكن الاستيراد '
          '(schema_version = ${data['schema_version']}).';
    }

    final Map<String, Object?>? lecture = _asMap(data['lecture']);
    if (lecture == null) return 'قسم lecture مفقود أو تالف.';

    // — الوحدة —
    if (!_validId(lecture['id'])) return 'معرف المحاضرة مفقود أو بصيغة خاطئة.';
    if (lecture['title'] is! String ||
        (lecture['title']! as String).trim().length < 3) {
      return 'عنوان المحاضرة مفقود أو أقصر من 3 أحرف.';
    }
    // — v2.3 (اختياري): التخصص السريري الأب specialty —
    if (lecture['specialty'] != null &&
        !DatabaseHelper.specialties.contains(lecture['specialty'])) {
      return 'التخصص السريري (specialty) غير معروف: '
          '${lecture['specialty']} — المسموح: '
          '${DatabaseHelper.specialties.join(', ')}.';
    }
    // v21: مجموع مسموح عبر التخصصات (SpecialtyDomains) — رسالة
    // الخطأ تعرض القائمة الكاملة المسموحة لتوجيه المؤلف.
    if (!_modules.contains(lecture['module'])) {
      return 'التخصص (module) غير معروف: ${lecture['module']} — '
          'المسموح: ${SpecialtyDomains.allModules.join(', ')}.';
    }
    if (!_systems.contains(lecture['system'])) {
      return 'الجهاز (system) غير معروف: ${lecture['system']} — '
          'المسموح: ${SpecialtyDomains.allSystems.join(', ')}.';
    }
    final Map<String, Object?>? source = _asMap(lecture['source']);
    if (source == null ||
        source['file_name'] is! String ||
        (source['file_name']! as String).length < 5 ||
        source['page_count'] is! int ||
        (source['page_count']! as int) < 1) {
      return 'بيانات المصدر (source) ناقصة أو تالفة.';
    }
    if (lecture['order_index'] is! int ||
        (lecture['order_index']! as int) < 0) {
      return 'ترتيب المحاضرة (order_index) مفقود أو غير صالح.';
    }

    // — v2.2 (اختياري): لؤلؤة اليوم golden_tip — نص أو مصفوفة نصوص —
    final Object? goldenTip = lecture['golden_tip'];
    if (goldenTip != null) {
      final List<String> tips = goldenTip is List
          ? <String>[
              for (final dynamic t in goldenTip)
                if (t is String) t.trim(),
            ]
          : goldenTip is String
              ? <String>[goldenTip.trim()]
              : const <String>[];
      if (goldenTip is! String && goldenTip is! List) {
        return 'golden_tip يجب أن يكون نصاً أو مصفوفة نصوص.';
      }
      if (tips.any((String t) => t.length < 10 || t.length > 280)) {
        return 'كل لؤلؤة في golden_tip يجب أن تكون 10–280 حرفاً.';
      }
      if (goldenTip is List && (goldenTip.isEmpty || goldenTip.length > 10)) {
        return 'golden_tip يجب أن تحوي 1–10 لآلئ.';
      }
      if (tips.isEmpty) {
        return 'golden_tip لا يقبل قيمة فارغة — احذف الحقل أو املأه.';
      }
    }

    // — الحصص الإلزامية (Data Contract) —
    final List<Map<String, Object?>> concepts = _rows(data, 'concepts');
    final List<Map<String, Object?>> flashcards = _rows(data, 'flashcards');
    final List<Map<String, Object?>> mcqs = _rows(data, 'mcqs');
    final List<Map<String, Object?>> cases = _rows(data, 'clinical_cases');

    if (concepts.isEmpty) return 'لا شروحات (concepts) في الملف — المطلوب ≥1.';
    if (flashcards.length < 3) {
      return 'البطاقات أقل من 3 — الحد الأدنى لعقد البيانات.';
    }
    if (mcqs.length < 3) {
      return 'الأسئلة أقل من 3 — الحد الأدنى لعقد البيانات.';
    }
    if (cases.isEmpty) {
      return 'لا حالات سريرية (clinical_cases) — المطلوب ≥1.';
    }

    final String lectureId = lecture['id']! as String;
    final Set<String> seenIds = <String>{lectureId};

    // — الشروحات —
    for (int i = 0; i < concepts.length; i++) {
      final String? e = _checkConcept(concepts[i], lectureId, seenIds, i + 1);
      if (e != null) return e;
    }

    // — البطاقات —
    for (int i = 0; i < flashcards.length; i++) {
      final String? e =
          _checkFlashcard(flashcards[i], lectureId, seenIds, i + 1);
      if (e != null) return e;
    }

    // — أسئلة MCQ —
    for (int i = 0; i < mcqs.length; i++) {
      final String? e = _checkMcq(mcqs[i], lectureId, seenIds, i + 1);
      if (e != null) return e;
    }

    // — الحالات السريرية —
    for (int i = 0; i < cases.length; i++) {
      final String? e = _checkCase(cases[i], lectureId, seenIds, i + 1);
      if (e != null) return e;
    }

    return null; // سليم كلياً.
  }

  static String? _checkConcept(
    Map<String, Object?> c,
    String lectureId,
    Set<String> seenIds,
    int index,
  ) {
    final String label = 'الشرح #$index';
    if (!_validId(c['id'])) return '$label: معرف مفقود أو بصيغة خاطئة.';
    if (!seenIds.add(c['id']! as String)) {
      return '$label: معرف مكرر (${c['id']}).';
    }
    if (c['lecture_id'] != lectureId) {
      return '$label: lecture_id لا يطابق معرف المحاضرة.';
    }
    if (c['title'] is! String || (c['title']! as String).trim().length < 3) {
      return '$label: العنوان مفقود أو أقصر من 3 أحرف.';
    }
    if (c['difficulty'] != 'core' && c['difficulty'] != 'advanced') {
      return '$label: الصعوبة يجب أن تكون core أو advanced.';
    }
    if (c['order_index'] is! int || (c['order_index']! as int) < 0) {
      return '$label: order_index مفقود أو غير صالح.';
    }
    final List<dynamic> sections = _asList(c['sections']);
    if (sections.isEmpty) return '$label: لا أقسام (sections).';
    for (int s = 0; s < sections.length; s++) {
      final Map<String, Object?>? sec = _asMap(sections[s]);
      if (sec == null) return '$label: القسم #${s + 1} تالف.';
      if (sec['heading'] is! String ||
          (sec['heading']! as String).trim().length < 3) {
        return '$label: القسم #${s + 1} بلا عنوان صالح.';
      }
      if (sec['body_text'] is! String ||
          (sec['body_text']! as String).trim().length < 100) {
        return '$label: القسم «${sec['heading']}» نصه أقل من 100 حرف.';
      }
      // — v2.1 (اختياري): سؤال اعتراضي مدمج check —
      final Map<String, Object?>? check = _asMap(sec['check']);
      if (check != null) {
        if (check['prompt'] is! String ||
            (check['prompt']! as String).trim().length < 10) {
          return '$label: القسم #${s + 1} — check.prompt قصير جداً.';
        }
        final List<dynamic> cOptions = _asList(check['options']);
        if (cOptions.length < 2 || cOptions.length > 5) {
          return '$label: القسم #${s + 1} — check.options يجب أن تكون 2–5.';
        }
        for (final dynamic o in cOptions) {
          if (o is! String || o.trim().isEmpty) {
            return '$label: القسم #${s + 1} — check.options نصوص مباشرة فقط.';
          }
        }
        if (check['correct_index'] is! int ||
            (check['correct_index']! as int) < 0 ||
            (check['correct_index']! as int) >= cOptions.length) {
          return '$label: القسم #${s + 1} — check.correct_index خارج النطاق.';
        }
        if (check['explanation_ar'] != null &&
            (check['explanation_ar'] is! String ||
                (check['explanation_ar']! as String).trim().length < 10)) {
          return '$label: القسم #${s + 1} — check.explanation_ar قصير جداً.';
        }
      }
    }
    // مسرد المصطلحات (اختياري — لكن عناصره إن وُجدت يجب أن تكون سليمة).
    for (final dynamic t in _asList(c['key_terms'])) {
      final Map<String, Object?>? term = _asMap(t);
      if (term == null ||
          term['term'] is! String ||
          (term['term']! as String).length < 2 ||
          term['definition_ar'] is! String ||
          (term['definition_ar']! as String).length < 5) {
        return '$label: مسرد المصطلحات يحوي عنصراً تالفاً.';
      }
    }
    return null;
  }

  static String? _checkFlashcard(
    Map<String, Object?> f,
    String lectureId,
    Set<String> seenIds,
    int index,
  ) {
    final String label = 'البطاقة #$index';
    if (!_validId(f['id'])) return '$label: معرف مفقود أو بصيغة خاطئة.';
    if (!seenIds.add(f['id']! as String)) {
      return '$label: معرف مكرر (${f['id']}).';
    }
    if (f['lecture_id'] != lectureId) {
      return '$label: lecture_id لا يطابق معرف المحاضرة.';
    }
    if (f['card_type'] != 'basic') {
      return '$label: card_type يجب أن يكون basic في العقد v2.0.';
    }
    if (f['front_text'] is! String ||
        (f['front_text']! as String).trim().length < 10) {
      return '$label: وجه البطاقة أقصر من 10 أحرف.';
    }
    if (f['back_text'] is! String ||
        (f['back_text']! as String).trim().length < 20) {
      return '$label: ظهر البطاقة أقصر من 20 حرفاً.';
    }
    // — v2.1 (اختياري): is_vivid —
    if (f['is_vivid'] != null && f['is_vivid'] is! bool) {
      return '$label: is_vivid يجب أن يكون true/false.';
    }
    return null;
  }

  static String? _checkMcq(
    Map<String, Object?> m,
    String lectureId,
    Set<String> seenIds,
    int index,
  ) {
    final String label = 'السؤال #$index';
    if (!_validId(m['id'])) return '$label: معرف مفقود أو بصيغة خاطئة.';
    if (!seenIds.add(m['id']! as String)) {
      return '$label: معرف مكرر (${m['id']}).';
    }
    if (m['lecture_id'] != lectureId) {
      return '$label: lecture_id لا يطابق معرف المحاضرة.';
    }
    if (m['question_stem'] is! String ||
        (m['question_stem']! as String).trim().length < 30) {
      return '$label: نص السؤال أقصر من 30 حرفاً.';
    }
    final List<dynamic> options = _asList(m['options']);
    if (options.length < 3 || options.length > 5) {
      return '$label: الخيارات يجب أن تكون 3 إلى 5.';
    }
    for (final dynamic o in options) {
      if (o is! String || o.trim().isEmpty) {
        return '$label: الخيارات يجب أن تكون نصوصاً مباشرة.';
      }
    }
    if (m['correct_index'] is! int ||
        (m['correct_index']! as int) < 0 ||
        (m['correct_index']! as int) >= options.length) {
      return '$label: correct_index خارج نطاق الخيارات.';
    }
    if (m['explanation_ar'] is! String ||
        (m['explanation_ar']! as String).trim().length < 30) {
      return '$label: الشرح العربي أقصر من 30 حرفاً.';
    }
    if (m['difficulty'] != 'core' && m['difficulty'] != 'advanced') {
      return '$label: الصعوبة يجب أن تكون core أو advanced.';
    }
    if (m['clinical_vignette'] is! bool) {
      return '$label: clinical_vignette يجب أن يكون true/false.';
    }

    // — v2.1 (اختياري): جسر التلميح + فهارس أقسام التركيز —
    final List<dynamic> hints = _asList(m['hints']);
    if (hints.isNotEmpty) {
      if (hints.length > 3) {
        return '$label: hints يجب ألا تتجاوز 3 مستويات.';
      }
      for (final dynamic h in hints) {
        if (h is! String || h.trim().length < 3) {
          return '$label: عناصر hints يجب أن تكون نصوصاً صالحة.';
        }
      }
    }
    final List<dynamic> focus = _asList(m['focus_sections']);
    if (focus.isNotEmpty) {
      for (final dynamic f in focus) {
        if (f is! int || f < 0) {
          return '$label: focus_sections يجب أن تكون أعداداً صحيحة ≥0.';
        }
      }
    }
    return null;
  }

  static String? _checkCase(
    Map<String, Object?> c,
    String lectureId,
    Set<String> seenIds,
    int index,
  ) {
    final String label = 'الحالة #$index';
    if (!_validId(c['id'])) return '$label: معرف مفقود أو بصيغة خاطئة.';
    if (!seenIds.add(c['id']! as String)) {
      return '$label: معرف مكرر (${c['id']}).';
    }
    if (c['lecture_id'] != lectureId) {
      return '$label: lecture_id لا يطابق معرف المحاضرة.';
    }
    if (c['title'] is! String || (c['title']! as String).trim().length < 3) {
      return '$label: العنوان مفقود أو أقصر من 3 أحرف.';
    }
    if (c['scenario'] is! String ||
        (c['scenario']! as String).trim().length < 50) {
      return '$label: السيناريو أقصر من 50 حرفاً.';
    }
    final Map<String, Object?>? vignette = _asMap(c['vignette']);
    if (vignette == null) return '$label: الـ vignette مفقود.';
    if (vignette['age'] is! int ||
        (vignette['age']! as int) < 1 ||
        (vignette['age']! as int) > 120) {
      return '$label: عمر المريض (age) مفقود أو خارج النطاق.';
    }
    if (vignette['sex'] != 'male' && vignette['sex'] != 'female') {
      return '$label: الجنس (sex) يجب أن يكون male أو female.';
    }
    if (vignette['chief_complaint'] is! String ||
        (vignette['chief_complaint']! as String).length < 5) {
      return '$label: الشكوى الرئيسية مفقودة أو قصيرة جداً.';
    }
    if (vignette['history'] is! String) {
      return '$label: التاريخ المرضي (history) مفقود.';
    }
    if (vignette['exam'] is! String) {
      return '$label: الفحص (exam) مفقود.';
    }
    final List<dynamic> steps = _asList(c['steps']);
    if (steps.length < 2) {
      return '$label: تحتاج خطوتي قرار على الأقل.';
    }
    for (int s = 0; s < steps.length; s++) {
      final Map<String, Object?>? step = _asMap(steps[s]);
      if (step == null) return '$label: الخطوة #${s + 1} تالفة.';
      final String sLabel = '$label · الخطوة #${s + 1}';
      if (!_validId(step['id'])) return '$sLabel: معرف مفقود أو خاطئ.';
      if (!seenIds.add(step['id']! as String)) {
        return '$sLabel: معرف مكرر (${step['id']}).';
      }
      if (step['prompt'] is! String ||
          (step['prompt']! as String).trim().length < 10) {
        return '$sLabel: نص القرار أقصر من 10 أحرف.';
      }
      final List<dynamic> options = _asList(step['options']);
      if (options.length < 3 || options.length > 5) {
        return '$sLabel: الخيارات يجب أن تكون 3 إلى 5.';
      }
      for (final dynamic o in options) {
        if (o is! String || o.trim().isEmpty) {
          return '$sLabel: الخيارات يجب أن تكون نصوصاً مباشرة.';
        }
      }
      if (step['correct_index'] is! int ||
          (step['correct_index']! as int) < 0 ||
          (step['correct_index']! as int) >= options.length) {
        return '$sLabel: correct_index خارج نطاق الخيارات.';
      }
      if (step['explanation_ar'] is! String ||
          (step['explanation_ar']! as String).trim().length < 20) {
        return '$sLabel: الشرح العربي أقصر من 20 حرفاً.';
      }
      if (step['xp'] != null &&
          (step['xp'] is! int ||
              (step['xp']! as int) < 1 ||
              (step['xp']! as int) > 20)) {
        return '$sLabel: قيمة xp خارج النطاق (1–20).';
      }
    }
    if (c['debriefing_ar'] is! String ||
        (c['debriefing_ar']! as String).trim().length < 80) {
      return '$label: التلخيص العربي أقصر من 80 حرفاً.';
    }
    if (c['difficulty'] != 'core' && c['difficulty'] != 'advanced') {
      return '$label: الصعوبة يجب أن تكون core أو advanced.';
    }
    if (c['order_index'] is! int || (c['order_index']! as int) < 0) {
      return '$label: order_index مفقود أو غير صالح.';
    }
    return null;
  }

  // ───────────────────────────── الاستيراد ─────────────────────────────

  /// يتحقق ثم يزرع محاضرة من ملف على القرص — داخل معاملة واحدة.
  static Future<LectureImportResult> importFile(String path) async {
    // (1) قراءة + فك JSON.
    final File file = File(path);
    if (!await file.exists()) {
      return const LectureImportResult(
        ok: false,
        messageAr: 'الملف غير موجود.',
      );
    }
    Map<String, Object?> data;
    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const LectureImportResult(
          ok: false,
          messageAr: 'بنية الملف غير صحيحة — المتوقع كائن JSON.',
        );
      }
      data = decoded.map(_stringEntry);
    } catch (_) {
      return const LectureImportResult(
        ok: false,
        messageAr: 'الملف تالف أو ليس بصيغة JSON.',
      );
    }

    // (2) التحقق البنيوي الصارم.
    final String? error = validateMap(data);
    if (error != null) {
      return LectureImportResult(ok: false, messageAr: error);
    }

    final Map<String, Object?> lecture =
        (data['lecture']! as Map).map(_stringEntry);
    final String lectureId = lecture['id']! as String;
    final String title = lecture['title']! as String;

    // (3) موجودة مسبقاً؟ — تخطٍ مهذب (idempotent).
    if (await _unitExists(lectureId)) {
      return LectureImportResult(
        ok: true,
        title: title,
        skipped: true,
        messageAr: 'المحاضرة «$title» موجودة مسبقاً — تم التخطي.',
      );
    }

    // (4) الزرع — معاملة واحدة.
    try {
      final DatabaseHelper helper = DatabaseHelper.instance;
      final Database db = await helper.database;
      final int count = await _seed(db, data);
      return LectureImportResult(
        ok: true,
        title: title,
        insertedRows: count,
        messageAr: 'تم استيراد «$title» بنجاح '
            '($count عنصراً جديداً).',
      );
    } catch (error) {
      debugPrint('LectureImportService: فشل الاستيراد ($error)');
      return const LectureImportResult(
        ok: false,
        messageAr: 'فشل الاستيراد — لم تتأثر بياناتك الحالية.',
      );
    }
  }

  /// الزرع الفعلي — مطابق لمنطق ContentSeeder._injectLectureFile
  /// لكن داخل معاملة صريحة (أي فشل يتراجع كلياً).
  static Future<int> _seed(Database db, Map<String, Object?> file) async {
    final Map<String, Object?> lecture =
        (file['lecture']! as Map).map(_stringEntry);

    return db.transaction((Transaction txn) async {
      int count = 0;

      // ── 1) الوحدة ──
      count += await _insertIgnore(txn, 'units', <String, Object?>{
        'id': lecture['id'],
        // v2.3: التخصص السريري — الباطنية افتراضاً (عقد متوافق رجعياً).
        'specialty': lecture['specialty'] ?? DatabaseHelper.defaultSpecialty,
        'module': lecture['module'],
        'system': lecture['system'],
        'title': lecture['title'],
        'description_ar': lecture['summary_ar'],
        'order_index': lecture['order_index'],
        // v2.2: لؤلؤة اليوم — نفس تطبيع الـ seeder.
        'golden_tip': _goldenTipOf(lecture['golden_tip']),
      });

      // ── 2) الشروحات ──
      for (final dynamic raw in _asList(file['concepts'])) {
        final Map<String, Object?> c = (raw as Map).map(_stringEntry);
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
        final Map<String, Object?> f = (raw as Map).map(_stringEntry);
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
        final Map<String, Object?> m = (raw as Map).map(_stringEntry);
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
        final Map<String, Object?> c = (raw as Map).map(_stringEntry);
        count += await _insertIgnore(
            txn, 'clinical_cases', <String, Object?>{
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
          final Map<String, Object?> s = (rawStep as Map).map(_stringEntry);
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

  static Future<bool> _unitExists(String lectureId) async {
    try {
      final DatabaseHelper helper = DatabaseHelper.instance;
      final Database db = await helper.database;
      final List<Map<String, Object?>> rows = await db.query(
        'units',
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <String>[lectureId],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false; // قاعدة غير مفتوحة بعد — نترك INSERT OR IGNORE يتكفل.
    }
  }

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
      return 1;
    } catch (_) {
      return 0;
    }
  }

  // ───────────────────────────── أدوات ─────────────────────────────

  static MapEntry<String, Object?> _stringEntry(Object? k, Object? v) =>
      MapEntry(k.toString(), v);

  static bool _validId(Object? raw) =>
      raw is String && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(raw);

  /// تطبيع golden_tip (عقد v2.2): نص يمر كما هو، مصفوفة تُدمج بفواصل
  /// أسطر — مطابق لمنطق ContentSeeder كي لا يتباعد المساران أبداً.
  static String? _goldenTipOf(Object? raw) {
    if (raw is String) {
      final String trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (raw is List) {
      final List<String> tips = <String>[
        for (final dynamic t in raw)
          if (t is String && t.trim().isNotEmpty) t.trim(),
      ];
      return tips.isEmpty ? null : tips.join('\n');
    }
    return null;
  }

  static List<dynamic> _asList(Object? raw) =>
      raw is List ? raw : const <dynamic>[];

  static Map<String, Object?>? _asMap(Object? raw) => raw is Map
      ? raw.map((Object? k, Object? v) => MapEntry(k.toString(), v))
      : null;

  static List<Map<String, Object?>> _rows(
    Map<String, Object?> data,
    String key,
  ) {
    final List<Map<String, Object?>> out = <Map<String, Object?>>[];
    for (final dynamic raw in _asList(data[key])) {
      if (raw is Map) {
        out.add(raw.map(_stringEntry));
      }
    }
    return out;
  }
}
