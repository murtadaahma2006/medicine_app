import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────
/// نطاقات التخصصات السريرية (v21) — مصدر الحقيقة الوحيد لعلاقة
/// التخصص الأب → المواد الفرعية (module) → الأجهزة (system).
///
/// **العقد**: كل التخصصات تشترك في نفس بنية عقد البيانات v2.3 —
/// يختلف فقط كائن lecture (specialty/module/system) وقوائم enum
/// الخاصة به. الملف الواحد يخدم ثلاثة مستهلكين:
///   1. LectureImportService — التحقق البنيوي عند الاستيراد.
///   2. LectureTemplateService — توليد القوالب في الإعدادات.
///   3. الواجهة — الأسماء العربية والأيقونات والألوان المرئية.
///
/// القوائم هنا هي **مجموع مسموح** (union) عبر التخصصات: القاعدة لا
/// تحظر تقاطعات مقصودة (urinary يخدم النسائية والجراحة معاً) — لكن
/// القالب المُصدَّر يوجه المؤلف دائماً إلى القائمة الأساس لتخصصه.
/// ─────────────────────────────────────────────────────────────────────
abstract final class SpecialtyDomains {
  /// النطاق الكامل لتخصص واحد.
  static const Map<String, (String, List<String>, List<String>)> _domains =
      <String, (String, List<String>, List<String>)>{
    'internal_medicine': (
      'الباطنية',
      <String>[
        'cardiology', 'pulmonology', 'nephrology', 'gastroenterology',
        'endocrinology', 'hematology', 'infectious', 'rheumatology',
        'neurology', 'oncology',
      ],
      <String>[
        'cardiovascular', 'respiratory', 'renal', 'gastrointestinal',
        'endocrine', 'immune', 'nervous', 'musculoskeletal',
        'hematologic', 'integumentary',
      ],
    ),
    'surgery': (
      'الجراحة',
      <String>[
        'general_surgery', 'orthopedics', 'neurosurgery', 'urology',
        'plastic_surgery', 'pediatric_surgery', 'surgical_oncology',
        'trauma',
      ],
      <String>[
        'gastrointestinal', 'musculoskeletal', 'nervous', 'renal',
        'integumentary', 'endocrine', 'cardiovascular', 'hematologic',
        'immune', 'respiratory',
      ],
    ),
    'obgyn': (
      'النسائية والتوليد',
      <String>[
        'obstetrics', 'gynecology', 'gynecologic_oncology',
        'reproductive_endocrinology', 'maternal_fetal_medicine',
      ],
      <String>[
        'reproductive', 'urinary', 'endocrine', 'gastrointestinal',
        'cardiovascular', 'hematologic', 'immune', 'nervous',
      ],
    ),
  };

  /// كل التخصصات بترتيب العقد (باطنية، جراحة، نسائية).
  static const List<String> all = <String>[
    'internal_medicine',
    'surgery',
    'obgyn',
  ];

  /// هل التخصص معروف؟
  static bool isValid(String? specialty) =>
      specialty != null && _domains.containsKey(specialty);

  /// الاسم العربي للتخصص.
  static String nameAr(String specialty) =>
      _domains[specialty]?.$1 ?? specialty;

  /// المواد (module) الموجهة لتخصص — القائمة الأساس للتأليف.
  static List<String> modulesOf(String specialty) =>
      _domains[specialty]?.$2 ?? _domains['internal_medicine']!.$2;

  /// الأجهزة (system) الموجهة لتخصص — القائمة الأساس للتأليف.
  static List<String> systemsOf(String specialty) =>
      _domains[specialty]?.$3 ?? _domains['internal_medicine']!.$3;

  /// مجموع كل المواد المسموح بها عبر التخصصات (للتحقق البنيوي).
  /// getter متغير لا const: تفكيك records داخل بنية const غير مدعوم.
  static final Set<String> allModules = <String>{
    for (final MapEntry<String, (String, List<String>, List<String>)> e
        in _domains.entries)
      ...e.value.$2,
  };

  /// مجموع كل الأجهزة المسموح بها عبر التخصصات (للتحقق البنيوي).
  static final Set<String> allSystems = <String>{
    for (final MapEntry<String, (String, List<String>, List<String>)> e
        in _domains.entries)
      ...e.value.$3,
  };

  /// اقتراح أفضل تخصص لقيمة module مجهولة (مثلاً: إرشاد رسائل
  /// الخطأ بأن module جراحي يكمل بقية حقول الجراحة).
  static String? suggestSpecialtyForModule(String module) {
    for (final MapEntry<String, (String, List<String>, List<String>)> e
        in _domains.entries) {
      if (e.value.$2.contains(module)) return e.key;
    }
    return null;
  }

  /// أيقونة التخصص — لواجهة اختيار القالب.
  static IconData iconOf(String specialty) => switch (specialty) {
        'surgery' => Icons.healing_rounded,
        'obgyn' => Icons.child_friendly_rounded,
        _ => Icons.local_hospital_rounded,
      };

  /// وصف قصير للتخصص — لواجهة اختيار القالب.
  static String descriptionAr(String specialty) => switch (specialty) {
        'surgery' => 'general · ortho · neuro · uro · plastic · peds',
        'obgyn' => 'obstetrics · gynecology · oncology · REI · MFM',
        _ => 'cardio · pulmo · nephro · gastro · endo · hema · ID',
      };
}
