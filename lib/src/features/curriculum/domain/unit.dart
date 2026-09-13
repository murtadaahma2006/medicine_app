/// نموذج الوحدة التعليمية (المحاضرة الطبية) — صف من جدول units.
class Unit {
  const Unit({
    required this.id,
    required this.module,
    required this.system,
    required this.title,
    required this.orderIndex,
    this.descriptionAr,
    this.isPinnedToday = false,
  });

  final String id;

  /// التخصص الطبي (cardiology, pulmonology, ...).
  final String module;

  /// جسم المنهج (cardiovascular, respiratory, ...).
  final String system;

  /// عنوان المحاضرة — إنجليزي.
  final String title;

  final int orderIndex;
  final String? descriptionAr;

  /// مثبتة لأهداف اليوم؟ (جدول اليوم الذي يبنيه المستخدم بنفسه).
  final bool isPinnedToday;

  factory Unit.fromMap(Map<String, Object?> map) {
    return Unit(
      id: map['id']! as String,
      module: (map['module'] as String?) ?? 'general',
      system: (map['system'] as String?) ?? 'general',
      title: map['title']! as String,
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      descriptionAr: map['description_ar'] as String?,
      isPinnedToday: (map['is_pinned_today'] as num?)?.toInt() == 1,
    );
  }

  /// نسخة بحقول محدّثة — لعمليات إعادة الترتيب والنقل بين الأجهزة
  /// والتثبيت.
  Unit copyWith({
    String? system,
    int? orderIndex,
    bool? isPinnedToday,
  }) =>
      Unit(
        id: id,
        module: module,
        system: system ?? this.system,
        title: title,
        orderIndex: orderIndex ?? this.orderIndex,
        descriptionAr: descriptionAr,
        isPinnedToday: isPinnedToday ?? this.isPinnedToday,
      );

  @override
  String toString() => 'Unit($id, $title)';
}
