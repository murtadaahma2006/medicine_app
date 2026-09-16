/// نموذج الوحدة التعليمية (المحاضرة الطبية) — صف من جدول units.
class Unit {
  const Unit({
    required this.id,
    required this.module,
    required this.system,
    required this.title,
    required this.orderIndex,
    this.specialty = 'internal_medicine',
    this.descriptionAr,
    this.pinnedAt,
  });

  final String id;

  /// التخصص السريري الأب (v20) — باطنية/جراحة/نسائية. الافتراضي
  /// الباطنية: كل محتوى المنصة قبل التوسع كان باطناً خالصاً، والقاعدة
  /// تسندها للمحاضرات القائمة تلقائياً عند الترقية.
  final String specialty;

  /// التخصص الطبي (cardiology, pulmonology, ...).
  final String module;

  /// جسم المنهج (cardiovascular, respiratory, ...).
  final String system;

  /// عنوان المحاضرة — إنجليزي.
  final String title;

  final int orderIndex;
  final String? descriptionAr;

  /// لحظة تثبيت المحاضرة لأهداف اليوم (v18) — null = غير مثبتة.
  /// أساس عدّاد الـ 48 ساعة (التنظيف التلقائي للإهمال).
  final DateTime? pinnedAt;

  /// مثبتة لأهداف اليوم؟ — مشتقة من وجود طابع التثبيت.
  bool get isPinnedToday => pinnedAt != null;

  factory Unit.fromMap(Map<String, Object?> map) {
    return Unit(
      id: map['id']! as String,
      // حماية مزدوجة: القيم القديمة (ما قبل v20) لا تحمل الحقل
      // أصلاً (null)، والقيم الشاذة (غير String) تسقط إلى الباطنية
      // بدل انهيار الـ Parsing — لا استثناء يصل الواجهة من هنا.
      specialty: map['specialty'] is String
          ? map['specialty']! as String
          : 'internal_medicine',
      module: (map['module'] as String?) ?? 'general',
      system: (map['system'] as String?) ?? 'general',
      title: map['title']! as String,
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      descriptionAr: map['description_ar'] as String?,
      pinnedAt: map['pinned_at'] == null
          ? null
          : DateTime.tryParse(map['pinned_at']! as String),
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
        specialty: specialty,
        module: module,
        system: system ?? this.system,
        title: title,
        orderIndex: orderIndex ?? this.orderIndex,
        descriptionAr: descriptionAr,
        pinnedAt: isPinnedToday == null
            ? pinnedAt
            : (isPinnedToday ? DateTime.now() : null),
      );

  @override
  String toString() => 'Unit($id, $title)';
}
