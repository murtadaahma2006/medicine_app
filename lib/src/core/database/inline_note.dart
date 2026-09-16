/// ملاحظة داخلية مضمّنة في نص شرح (Inline Highlight — v22).
///
/// تمثّل صفاً من جدول `inline_notes`: نصٌ محدَّد من قبل المستخدم داخل
/// الشرح مرتبط بملاحظته الشخصية. تُستهلك من قارئ الشروحات لتمييز
/// النصوص المحفوظة وعرضها عند النقر.
class InlineNote {
  const InlineNote({
    required this.remarkId,
    required this.conceptId,
    required this.selectedText,
    required this.startIndex,
    required this.endIndex,
    required this.personalNote,
    this.colorCode,
    this.createdAt,
  });

  final int remarkId;
  final String conceptId;

  /// النص الحرفي الذي حدّده المستخدم داخل الشرح.
  final String selectedText;

  /// بداية التحديد
  final int startIndex;

  /// نهاية التحديد
  final int endIndex;

  /// ملاحظة المستخدم الشخصية المرتبطة بهذا النص.
  final String personalNote;

  /// رمز لوني اختياري (مستقبلي لألوان تمييز متعددة).
  final String? colorCode;

  final String? createdAt;

  /// هل هذه الملاحظة تحمل ملاحظة فعلية قابلة للعرض؟
  bool get hasNote => personalNote.trim().isNotEmpty;

  /// بناء من صف قاعدة البيانات.
  factory InlineNote.fromMap(Map<String, Object?> map) => InlineNote(
        remarkId: (map['id']! as num).toInt(),
        conceptId: map['concept_id']! as String,
        selectedText: map['selected_text']! as String,
        startIndex: (map['start_index'] as num?)?.toInt() ?? 0,
        endIndex: (map['end_index'] as num?)?.toInt() ?? 0,
        personalNote: (map['personal_note'] as String?) ?? '',
        colorCode: map['color_code'] as String?,
        createdAt: map['created_at'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'concept_id': conceptId,
        'selected_text': selectedText,
        'start_index': startIndex,
        'end_index': endIndex,
        'personal_note': personalNote,
        'color_code': colorCode,
        'created_at': createdAt,
      };

  @override
  bool operator ==(Object other) =>
      other is InlineNote && other.remarkId == remarkId;

  @override
  int get hashCode => remarkId.hashCode;
}