import '../../../core/database/database_helper.dart';
import '../../../core/database/srs_repository.dart';
import '../../../core/notifications/pin_expiry_service.dart';
import '../../../core/utils/error_logger.dart';
import '../domain/unit.dart';

/// لقطة أهداف اليوم — محاضرات مثبتة + بطاقات SRS مستحقة في جملة
/// واحدة. النموذج نقي (بلا Flutter) فيصلح للاختبار على FFI.
///
/// **v2 — فصل المراجعات (Decoupling)**: حلقة التقدم والرسالة الرئيسية
/// تعكسان المحاضرات المثبتة **حصرياً** — البطاقات المستحقة شريط ثانوي
/// منفصل أسفلها ولا تدخل في نسبة الإنجاز اليومية مهما بلغ عددها.
class TodayGoalsSnapshot {
  const TodayGoalsSnapshot({
    required this.pinned,
    required this.completedPinned,
    required this.dueCards,
  });

  /// المحاضرات المثبتة كلها بترتيب المنهج.
  final List<Unit> pinned;

  /// منها ما أُكمل (تقييم مجتاز أو كل الشروح مقروءة).
  final List<Unit> completedPinned;

  /// البطاقات المستحقة اليوم (SRS) — عرض ثانوي منفصل عن الحلقة.
  final int dueCards;

  /// المحاضرات المثبتة غير المكتملة — «لديك محاضرات بانتظارك».
  List<Unit> get pendingPinned => <Unit>[
        for (final Unit u in pinned)
          if (!completedPinned.any((Unit c) => c.id == u.id)) u,
      ];

  /// هل بقي عمل اليوم؟ (محاضرة مثبتة غير مكتملة **أو** بطاقات مستحقة)
  /// — إشارة تشغيل عامة فقط؛ لا تدخل في الحلقة (المراجعات لها شريطها
  /// الخاص المنفصل).
  bool get hasWork => pendingPinned.isNotEmpty || dueCards > 0;

  /// نسبة إنجاز أهداف اليوم 0.0 → 1.0 — **محاضرات مثبتة فقط**:
  /// (المكتملة / إجمالي المثبتة). البطاقات المستحقة لا تلمس هذه
  /// النسبة أبداً — الهدف اليومي الحقيقي للطالب محاضراته المثبتة.
  /// لا مثبتات → 0.0 (حلقة فارغة برسالة دعوة للتثبيت).
  double get progress => pinned.isEmpty
      ? 0.0
      : (completedPinned.length / pinned.length).clamp(0.0, 1.0);

  /// مرحلة الحالة الموحدة — **المحاضرات وحدها تقود الرسالة الرئيسية**:
  /// none → لا مثبتات · lectures → بانتظارك · done → كلها مكتملة.
  TodayPhase get phase {
    if (pinned.isEmpty) return TodayPhase.none;
    if (pendingPinned.isNotEmpty) return TodayPhase.lectures;
    return TodayPhase.done;
  }
}

/// مراحل يوم الدراسة. (خرجت مرحلة المراجعات — البطاقات المستحقة
/// شريط ثانوي مستقل ولا تقود الرسالة الرئيسية للحلقة.)
enum TodayPhase { none, lectures, done }


/// مستودع الوحدات — يجلب قائمة الوحدات (المحاضرات الطبية) من القاعدة
/// ويدير إعادة ترتيبها ونقلها بين الأجهزة (system-based curriculum).
class UnitRepository {
  const UnitRepository();

  DatabaseHelper get _helper => DatabaseHelper.instance;

  /// كل الوحدات (أو حسب التخصص الفرعي module) مرتبة.
  Future<List<Unit>> getAllUnits({String? module}) async {
    final List<Map<String, Object?>> rows =
        await _helper.getAllUnits(module: module);
    return rows.map<Unit>(Unit.fromMap).toList();
  }

  /// وحدات تخصص سريري كامل (v20) — أساس شريط (باطنية|جراحة|نسائية)
  /// في شاشة المسار. [specialty] null = كل التخصصات.
  Future<List<Unit>> getUnitsBySpecialty(String? specialty) async {
    final List<Map<String, Object?>> rows =
        await _helper.getUnitsBySpecialty(specialty);
    return rows.map<Unit>(Unit.fromMap).toList();
  }

  /// وحدة واحدة بمعرّفها.
  Future<Unit?> getById(String unitId) async {
    final Map<String, Object?>? row = await _helper.getUnitById(unitId);
    return row == null ? null : Unit.fromMap(row);
  }

  // ─────────────────── أهداف اليوم (v18: التثبيت الذكي) ───────────────────

  /// يثبّت/يفكّ تثبيت محاضرة — يرجع الحالة الجديدة (true = مثبتة).
  /// تثبيت → جدولة إشعار الانتهاء (+48h) · فك → إلغاء الإشعار.
  Future<bool> togglePinnedToday(Unit unit) async {
    final String unitId = unit.id;
    final bool nowPinned =
        await _helper.toggleUnitPinnedToday(unitId);
    // الإشعار خارج مسار القاعدة: فشله لا يُسقط التثبيت (صمت لطيف).
    if (nowPinned) {
      final Map<String, Object?>? row = await _helper.getUnitById(unitId);
      final String? pinnedAtRaw = row?['pinned_at'] as String?;
      if (pinnedAtRaw != null) {
        await PinExpiryService.scheduleExpiryNotification(
          unitId: unitId,
          lectureTitle: unit.title,
          pinnedAt: DateTime.parse(pinnedAtRaw),
        );
      }
    } else {
      await PinExpiryService.cancelExpiryNotification(unitId);
    }
    return nowPinned;
  }

  /// المحاضرات المثبتة لأهداف اليوم (بترتيب المنهج).
  Future<List<Unit>> getPinnedUnits() async {
    final List<Map<String, Object?>> rows = await _helper.getPinnedUnits();
    return rows.map<Unit>(Unit.fromMap).toList();
  }

  /// لقطة أهداف اليوم الكاملة — checkTodayStatus: محاضرات مثبتة مع
  /// حالة إكمالها (مشتقة ديناميكياً في القاعدة) + بطاقات SRS مستحقة.
  /// **تدخل التنظيف أولاً**: المكتملة والمهملة (>48h) تُفكّ ويُلغى
  /// إشعارها قبل بناء اللقطة — فلا يرى المستخدم هدفاً ميتاً أبداً.
  Future<TodayGoalsSnapshot> todayGoals() async {
    await PinExpiryService.runAppCleanup();
    final List<Map<String, Object?>> rows =
        await _helper.getPinnedUnitsWithCompletion();
    final List<Unit> pinned = rows.map<Unit>(Unit.fromMap).toList();
    final List<Unit> completed = <Unit>[
      for (int i = 0; i < rows.length; i++)
        if ((rows[i]['is_completed'] as num?)?.toInt() == 1) pinned[i],
    ];
    final int due = await SrsRepository.dueTodayCount();
    return TodayGoalsSnapshot(
      pinned: pinned,
      completedPinned: completed,
      dueCards: due,
    );
  }

  // ─────────────────── إعادة الترتيب والنقل (Reorder & Move) ───────────────────

  /// يعيد ترتيب وحدة داخل جهازها (نفس النظام).
  ///
  /// [newOrderIndex] = الموقع الجديد (فهرس صفري داخل الجهاز بعد السحب).
  /// يعيد ترقيم وحدات الجهاز كاملة 0..n-1 بمواقعها الجديدة داخل
  /// **معاملة واحدة** — فلا فجوات ولا تعارضات، والترتيب محفوظ فوراً
  /// ولا يضيع عند إعادة تشغيل التطبيق.
  Future<void> reorderUnitWithinSystem(
    String system,
    String unitId,
    int newOrderIndex,
  ) async {
    final List<Unit> units = await _unitsOfSystem(system);
    final int oldIndex = units.indexWhere((Unit u) => u.id == unitId);
    if (oldIndex < 0) return;

    final Unit moved = units.removeAt(oldIndex);
    units.insert(newOrderIndex.clamp(0, units.length), moved);

    await _helper.applyUnitArrangement(
      unitId: unitId,
      orders: _ordersOf(units),
    );
  }

  /// ينقل وحدة إلى جهاز آخر — يحدّث `system` و`order_index` معاً
  /// داخل معاملة واحدة ذرّية (بلا حالة وسطية حتى لو انقطع التنفيذ).
  ///
  /// [targetIndex] = موضع الإدراج داخل الجهاز الهدف (null = الإلحاق
  /// بنهايته — السلوك عند الإفلات فوق ترويسة الجهاز أو النقل من الشيت).
  Future<void> moveUnitToSystem(
    String unitId,
    String targetSystem, {
    int? targetIndex,
  }) async {
    // الجهاز الهدف بدون الوحدة المنقولة + الوحدة نفسها من القاعدة.
    final List<Unit> target = await _unitsOfSystem(targetSystem);
    final Unit? moving = await getById(unitId);
    if (moving == null) return;

    final List<Unit> targetNoMoving = <Unit>[
      for (final Unit u in target)
        if (u.id != unitId) u,
    ];
    final int insertAt = (targetIndex ?? targetNoMoving.length)
        .clamp(0, targetNoMoving.length);
    targetNoMoving.insert(insertAt, moving);

    await _helper.applyUnitArrangement(
      unitId: unitId,
      newSystem: targetSystem,
      orders: _ordersOf(targetNoMoving),
    );
  }

  /// حذف محاضرة بالكامل — المحتوى والتقدم معاً (حذف متسلسل يدوي
  /// داخل معاملة واحدة). يُستدعى بعد تأكيد المستخدم الصريح فقط.
  ///
  /// يعيد true عند النجاح (أو عدم وجود المحاضرة أصلاً) وfalse عند
  /// الفشل — بلا استثناءات تصل الواجهة. الفشل يُسجَّل في ErrorLogger
  /// (كان صامتاً تماماً — فقدان بيانات بلا أثر يُشخَّص).
  Future<bool> deleteLecture(String unitId) async {
    try {
      await _helper.deleteLectureData(unitId);
      return true;
    } catch (error, stack) {
      AppErrorLogger.instance.record(
        type: 'DeleteLecture',
        error: error,
        stack: stack,
      );
      return false;
    }
  }

  // ───────────────────────────── أدوات ─────────────────────────────

  Future<List<Unit>> _unitsOfSystem(String system) async {
    final List<Unit> all = await getAllUnits();
    return <Unit>[
      for (final Unit u in all)
        if (u.system == system) u,
    ]..sort((Unit a, Unit b) => a.orderIndex.compareTo(b.orderIndex));
  }

  /// خريطة id → order_index للقائمة المرتبة الجديدة (ترقيم تسلسلي كامل).
  static Map<String, int> _ordersOf(List<Unit> ordered) {
    final Map<String, int> out = <String, int>{};
    for (int i = 0; i < ordered.length; i++) {
      out[ordered[i].id] = i;
    }
    return out;
  }
}
