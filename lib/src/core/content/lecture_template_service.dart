import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'specialty_domains.dart';

/// نتيجة تصدير قالب المحاضرة.
class TemplateExportResult {
  const TemplateExportResult({required this.ok, this.filePath, this.messageAr});

  final bool ok;
  final String? filePath;
  final String? messageAr;
}

/// خدمة تصدير قالب محاضرة JSON لكل تخصص سريري — عقد البيانات v2.3
/// كاملاً (specialty · golden_tip · concepts · flashcards · mcqs ·
/// clinical_cases) بنفس صيغة استيراد «استيراد محاضرة» حرفياً.
///
/// **فلسفة القالب**: مثال معبّأ واحد لكل نوع عنصر (شرح واحد، 3 بطاقات،
/// 3 أسئلة، حالة بخطوتين — الحصص الدنيا لعقد البيانات) يجعل الملف
/// **قابلاً للاستيراد فوراً** كاختبار سلامة للدورة كاملة: صدّر → عدّل
/// → استورد. المستخدم يستبدل قيم الأمثلة بمحتواه ويزيد العناصر —
/// لا يبدأ من صفر ولا يخمن أسماء الحقول.
///
/// **v21 — قوالب التخصصات**: [specialty] يحدد كائن lecture بالكامل
/// (specialty/module/system بقيم وتعليقات موجّهة لتخصص المؤلف) واسم
/// الملف: lecture_template_internal_medicine.json ... — مصدر الحقيقة
/// للقوائم [SpecialtyDomains].
abstract final class LectureTemplateService {
  /// يولّد القالب ويكتبه إلى ملف مؤقت قابل للمشاركة (share sheet)
  /// أو الحفظ في تطبيق «الملفات» — رد مهذب عند أي فشل (لا استثناءات).
  ///
  /// [specialty] يحدد القالب واسم الملف: lecture_template_surgery.json
  /// مثلاً — قيمة غير معروفة تُرفض مهذباً (لا سقوط صامت لتخصص آخر).
  static Future<TemplateExportResult> export(
    String specialty, {
    Future<Directory> Function()? tempDirProvider,
  }) async {
    if (!SpecialtyDomains.isValid(specialty)) {
      return const TemplateExportResult(
        ok: false,
        messageAr: 'تخصص غير معروف — المسموح: باطنية، جراحة، نسائية.',
      );
    }
    try {
      // 1. تحديد اسم الملف بحسب التخصص
      String schemaName;
      if (specialty == 'surgery') {
        schemaName = 'surgery_lecture.schema.json';
      } else if (specialty == 'obgyn') {
        schemaName = 'obgyn_lecture.schema.json';
      } else {
        schemaName = 'medical_lecture.schema.json'; // التخصص الباطني
      }

      // 2. جلب المخطط الكامل من الملفات المحلية
      final String schemaContent =
          await rootBundle.loadString('docs/schemas/$schemaName');

      // 3. كتابة المحتوى لملف مؤقت لمشاركته
      final Directory tempDir =
          await (tempDirProvider?.call() ?? getTemporaryDirectory());
      final String path = p.join(
        tempDir.path,
        'lecture_template_$specialty.json',
      );
      await File(path).writeAsString(
        schemaContent,
        flush: true,
        mode: FileMode.write,
      );

      debugPrint(
        'LectureTemplateService: exported $specialty template '
        'to $path',
      );
      return TemplateExportResult(ok: true, filePath: path);
    } catch (error) {
      debugPrint('LectureTemplateService: فشل التصدير ($error)');
      return const TemplateExportResult(
        ok: false,
        messageAr: 'تعذّر إنشاء ملف القالب — تحقق من مساحة التخزين أو تأكد من وجود ملفات الـ Schemas.',
      );
    }
  }
}
