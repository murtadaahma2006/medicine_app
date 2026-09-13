import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../curriculum/data/unit_repository.dart';
import '../../../curriculum/domain/unit.dart';
import '../widgets/system_expansion_tile.dart';
import '../widgets/system_lecture_tile.dart';
import 'unit_screen.dart';

/// شاشة «المسار» v2 — منهج قائم على الأجهزة (System-based Curriculum).
///
/// **البنية**:
/// - تجميع تلقائي حسب حقل `system` في القاعدة (Respiratory,
///   Cardiovascular, ...) — لا قائمة مسطحة بعد اليوم.
/// - كل جهاز ExpansionTile (أكورديون): ترويسة تحمل اسم الجهاز
///   + شريط تقدم (المحاضرات المنجزة من الإجمالي).
/// - قائمة موحدة ReorderableListView تشمل ترويسات الأجهزة نفسها
///   كبوابات: سحب محاضرة فوق ترويسة جهاز آخر = نقلها إليه فوراً.
/// - وضع «ترتيب» يفعّل مقبض سحب بجانب كل محاضرة.
/// - كل تغيير (ترتيب/نقل) يُكتب لـ SQLite فوراً (order_index + system).
///
/// حالة الإكمال من قاعدة التقدم الحقيقية:
/// `user_progress(drill, assess-<unitId>) == completed`.
class CurriculumPage extends StatefulWidget {
  const CurriculumPage({super.key});

  @override
  State<CurriculumPage> createState() => _CurriculumPageState();
}

class _CurriculumPageState extends State<CurriculumPage> {
  late final UnitRepository _repo;

  /// الوحدات بترتيبها الكامل (مسطّح عبر الأجهزة، الأجهزة مرتبة داخلياً).
  List<Unit> _units = const <Unit>[];

  /// أنظمة العرض بالترتيب المطلوب ظهورها.
  List<String> _systems = const <String>[];

  /// الأجهزة الموسعة (expanded) — افتراضياً أول جهاز فقط.
  final Set<String> _expandedSystems = <String>{};

  final Set<String> _completedUnitIds = <String>{};

  /// وضع الترتيب اليدوي — يظهر مقابض السحب ويفعّل إعادة الترتيب.
  bool _reorderMode = false;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = const UnitRepository();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Unit> units = await _repo.getAllUnits();

      // حالة كل الوحدات باستعلام واحد: معرفات تقييماتها المكتملة.
      final DatabaseHelper db = DatabaseHelper.instance;
      final List<Map<String, Object?>> doneRows =
          await db.rawQueryParameterized(
        'SELECT item_id FROM ${DatabaseHelper.tableUserProgress} '
            'WHERE item_type = ? AND status = ? AND item_id LIKE ?',
        <Object?>[_drillCode, 'completed', 'assess-%'],
      );
      final Set<String> completed = <String>{
        for (final Map<String, Object?> row in doneRows)
          (row['item_id']! as String).replaceFirst('assess-', ''),
      };

      // التجميع حسب system — الترتيب: أول ظهور في القاعدة
      // (units مرتبة بـ module, order_index من getAllUnits).
      final LinkedHashSetBuilder systemsInOrder = LinkedHashSetBuilder();
      for (final Unit unit in units) {
        systemsInOrder.add(unit.system);
      }
      final List<String> systems = systemsInOrder.items;

      if (!mounted) return;
      setState(() {
        _units = units;
        _systems = systems;
        _completedUnitIds.clear();
        _completedUnitIds.addAll(completed);
        if (_expandedSystems.isEmpty && systems.isNotEmpty) {
          _expandedSystems.add(systems.first);
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل المنهج.';
        _loading = false;
      });
    }
  }

  static const String _drillCode = 'drill';

  // ─────────────────── قائمة العرض المسطّحة (ترويسات + محاضرات) ───────────────────

  /// عناصر القائمة الموحدة: إما ترويسة جهاز (gateway) أو محاضرة.
  /// الترتيب: ترويسة ثم محاضرات جهازها الموسّع (أو لا شيء إن كان مطوياً).
  List<_Row> _buildRows() {
    final List<_Row> rows = <_Row>[];
    for (final String system in _systems) {
      rows.add(_Row.header(system));
      if (_expandedSystems.contains(system)) {
        for (final Unit unit in _unitsOfSystem(system)) {
          rows.add(_Row.unit(system, unit));
        }
      }
    }
    return rows;
  }

  List<Unit> _unitsOfSystem(String system) => <Unit>[
        for (final Unit u in _units)
          if (u.system == system) u,
      ]..sort((Unit a, Unit b) => a.orderIndex.compareTo(b.orderIndex));

  bool _isUnitCompleted(String unitId) =>
      _completedUnitIds.contains(unitId);

  int _completedCountOf(String system) => <String>[
        for (final Unit u in _unitsOfSystem(system))
          if (_isUnitCompleted(u.id)) u.id,
      ].length;

  // ─────────────────── إعادة الترتيب والنقل (Reorder & Move) ───────────────────

  /// يستدعيه ReorderableListView عند إفلات أي عنصر.
  ///
  /// [oldFlatIndex]/[newFlatIndex] بفهارس القائمة المسطّحة الموحدة
  /// (ترويسات + محاضرات). منطق الترجمة:
  /// 1. تُسحب ترويسة جهاز → تجاهل (ترتيب الأجهزة ثابت).
  /// 2. تُسحب محاضرة وتُفلت فوق ترويسة جهاز آخر → **نقل** إليه (append).
  /// 3. تُسحب محاضرة وتُفلت بين محاضرات جهاز آخر → **نقل** إلى موضعها.
  /// 4. تُفلت داخل جهازها نفسه → **إعادة ترتيب** محلية.
  ///
  /// في كل الحالات يُكتب order_index (+ system عند النقل) إلى SQLite
  /// فوراً — فلا يضيع التخصيص عند إعادة تشغيل التطبيق.
  Future<void> _onReorder(int oldFlatIndex, int newFlatIndex) async {
    final List<_Row> rows = _buildRows();
    if (oldFlatIndex < 0 || oldFlatIndex >= rows.length) return;
    final _Row dragged = rows[oldFlatIndex];
    if (dragged.unit == null) return; // ترويسة جهاز — ثابتة.

    // تعديل فهرس الإفلات (اتفاقية ReorderableListView عند السحب لأسفل).
    if (newFlatIndex > oldFlatIndex) newFlatIndex -= 1;
    if (newFlatIndex < 0) newFlatIndex = 0;
    if (newFlatIndex >= rows.length) newFlatIndex = rows.length - 1;

    final Unit unit = dragged.unit!;
    final String sourceSystem = dragged.system;

    // ── (1) الإفلات فوق ترويسة جهاز آخر → نقل بنهايته ──
    if (rows[newFlatIndex].isHeader) {
      final String headerSystem = rows[newFlatIndex].system;
      if (headerSystem != sourceSystem) {
        await _moveUnit(unit, headerSystem);
      }
      return;
    }

    // ── تحديد الجهاز الذي يضم نقطة الإفلات وترجمتها لفهرس داخلي ──
    // نقطة الإفلات تقع بين صفين — الجهاز الهدف هو جهاز الصف المُفلت عليه.
    final _Row dropRow = rows[newFlatIndex];
    final String targetSystem = dropRow.system;

    if (targetSystem != sourceSystem) {
      // ── (2) الإفلات بين محاضرات جهاز آخر → نقل إلى ذلك الموضع ──
      final int targetIndex = _unitIndexOfRow(rows, newFlatIndex);
      await _moveUnit(unit, targetSystem, targetIndex: targetIndex);
      return;
    }

    // ── (3) إعادة ترتيب داخل نفس الجهاز ──
    final int newSystemIndex = _unitIndexOfRow(rows, newFlatIndex);
    if (newSystemIndex < 0) return;
    await _repo.reorderUnitWithinSystem(
      sourceSystem,
      unit.id,
      newSystemIndex,
    );
    await _load();
  }

  /// يترجم فهرس الصف المسطّح إلى فهرس المحاضرة داخل قائمة جهازها.
  ///
  /// العدّ: عدد صفوف المحاضرات في نفس الجهاز قبل هذا الصف. الإفلات
  /// فوق الصف i يعني «قبل المحاضرة رقم k» — وهو فهرس الإدراج الصحيح
  /// في قائمة المحاضرات بعد إزالة المسحوبة (سلوك move semantics).
  static int _unitIndexOfRow(List<_Row> rows, int flatIndex) {
    int seen = 0;
    final String system = rows[flatIndex].system;
    for (int i = 0; i < flatIndex; i++) {
      final _Row r = rows[i];
      if (!r.isHeader && r.system == system) seen++;
    }
    return seen;
  }

  // ─────────────────── النقل بين الأجهزة ───────────────────

  /// ينقل وحدة إلى جهاز آخر — يوسّع الجهاز الهدف، يحدّث القاعدة
  /// فوراً، ثم يعرض تأكيداً نصياً.
  Future<void> _moveUnit(
    Unit unit,
    String targetSystem, {
    int? targetIndex,
  }) async {
    await _repo.moveUnitToSystem(
      unit.id,
      targetSystem,
      targetIndex: targetIndex,
    );
    // توسيع الجهاز الهدف ليرى المستخدم محاضرته المنقولة.
    setState(() => _expandedSystems.add(targetSystem));
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'نُقلت «${_cleanTitle(unit.title)}» إلى '
              '${_systemNameAr(targetSystem)}'),
          duration: const Duration(milliseconds: 1800),
        ),
      );
    }
  }

  /// زر «نقل إلى نظام آخر» — شيت اختيار الجهاز الهدف.
  Future<void> _showMoveSheet(Unit unit) async {
    final String? target = await AppSheet.show<String>(
      context,
      title: 'نقل «${_cleanTitle(unit.title)}»',
      maxHeightFactor: 0.6,
      builder: (BuildContext sheetContext) => _MoveSheetList(
        systems: _systems,
        currentSystem: unit.system,
        onPick: (String system) => Navigator.of(sheetContext).pop(system),
      ),
    );
    if (target == null || target == unit.system) return;
    await _moveUnit(unit, target);
  }

  // ─────────────────── أهداف اليوم (التثبيت v17) ───────────────────

  /// تثبيت/فك تثبيت محاضرة — تحديث محلي فوري (بلا إعادة تحميل كامل
  /// كي لا يفقد المستخدم موضع تمريره) + SnackBar تأكيد خفيف.
  Future<void> _togglePin(Unit unit) async {
    final bool nowPinned = await _repo.togglePinnedToday(unit.id);
    if (!mounted) return;

    setState(() {
      final int i = _units.indexWhere((Unit u) => u.id == unit.id);
      if (i >= 0) {
        _units[i] = _units[i].copyWith(isPinnedToday: nowPinned);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowPinned
              ? 'أُضيفت «${_cleanTitle(unit.title)}» إلى أهداف اليوم 📌'
              : 'أُزيلت «${_cleanTitle(unit.title)}» من أهداف اليوم',
        ),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  // ─────────────────── حذف المحاضرة (Delete Lecture) ───────────────────

  /// زر الحذف — حوار تحذيري صريح قبل أي مس نهائي للبيانات.
  ///
  /// النص يفصّل ما سيُمسح (المفاهيم، البطاقات، الأسئلة، الحالات،
  /// وتقدم المستخدم فيها نهائياً) حتى يكون قرار المستخدم مستنيراً.
  Future<void> _confirmDelete(Unit unit) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('حذف المحاضرة'),
        content: Text(
          'هل أنت متأكد من حذف «${_cleanTitle(unit.title)}»؟\n\n'
          'سيتم مسح جميع المفاهيم، البطاقات، الأسئلة، الحالات '
          'السريرية، وتقدمك فيها نهائياً.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteUnit(unit);
  }

  /// ينفّذ الحذف بعد التأكيد — حذف متسلسل كامل داخل معاملة واحدة
  /// (deleteLectureData) ثم يحدّث الواجهة فوراً.
  Future<void> _deleteUnit(Unit unit) async {
    final bool ok = await _repo.deleteLecture(unit.id);
    if (!mounted) return;

    if (ok) {
      // تحديث فوري: إزالة المحاضرة من الحالة وإعادة بناء المجموعات —
      // تختفي من الـ ExpansionTile دون إعادة تشغيل التطبيق.
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'حُذفت «${_cleanTitle(unit.title)}» نهائياً.'),
            duration: const Duration(milliseconds: 2000),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر الحذف — حاول مرة أخرى.'),
          duration: Duration(milliseconds: 2000),
        ),
      );
    }
  }

  // ───────────────────────────── البناء ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'إعادة المحاولة',
        onAction: _load,
      );
    }
    if (_units.isEmpty) {
      return const EmptyState(
        icon: Icons.school_rounded,
        title: 'لا محاضرات بعد',
        subtitle: 'سيظهر المنهج الطبي هنا بعد حقن المحتوى',
      );
    }

    final List<_Row> rows = _buildRows();

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: _load,
          child: ReorderableListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            buildDefaultDragHandles: false,
            itemCount: rows.length,
            onReorder: _onReorder,
            proxyDecorator: (Widget child, int index, Animation<double> a) {
              // ظل أعمق أثناء السحب — رد فعل بصري واضح.
              return AnimatedBuilder(
                animation: a,
                builder: (BuildContext c, Widget? ch) {
                  return Material(
                    color: Colors.transparent,
                    elevation: 0,
                    child: ch,
                  );
                },
                child: child,
              );
            },
            itemBuilder: (BuildContext context, int index) {
              final _Row row = rows[index];
              final String key =
                  row.isHeader ? 'hdr-${row.system}' : row.unit!.id;

              if (row.isHeader) {
                // ── ترويسة الجهاز (أكورديون) ──
                final List<Unit> systemUnits = _unitsOfSystem(row.system);
                final int done = _completedCountOf(row.system);
                final bool expanded =
                    _expandedSystems.contains(row.system);

                return SystemExpansionTile(
                  key: ValueKey<String>(key),
                  system: row.system,
                  lectureCount: systemUnits.length,
                  completedCount: done,
                  expanded: expanded,
                  onToggle: () => _toggleExpanded(row.system),
                  onDropHere: () {}, // الإفلات يُعالج في onReorder.
                );
              }

              // ── صف المحاضرة ──
              final Unit unit = row.unit!;
              final bool completed = _isUnitCompleted(unit.id);

              return SystemLectureTile(
                key: ValueKey<String>(key),
                unit: unit,
                completed: completed,
                reorderMode: _reorderMode,
                index: index,
                pinned: unit.isPinnedToday,
                onTogglePin: () => _togglePin(unit),
                onOpen: () => _openUnit(unit),
                onMove: () => _showMoveSheet(unit),
                onDelete: () => _confirmDelete(unit),
              );
            },
          ),
        ),

        // ── زر وضع الترتيب عائم ──
        Positioned(
          bottom: AppSpacing.lg,
          left: AppSpacing.xl,
          child: _ReorderModeChip(
            active: _reorderMode,
            onToggle: () => setState(() => _reorderMode = !_reorderMode),
          ),
        ),
      ],
    );
  }

  void _toggleExpanded(String system) {
    setState(() {
      if (!_expandedSystems.remove(system)) {
        _expandedSystems.add(system);
      }
    });
  }

  Future<void> _openUnit(Unit unit) async {
    await Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) => UnitScreen(unitId: unit.id),
    ));
    // عند العودة — تحديث حالة الإكمال (قد أكمل التقييم داخل الوحدة).
    await _load();
  }

  static String _cleanTitle(String raw) {
    String t = raw;
    if (t.startsWith('[') && t.contains(']')) {
      t = t.substring(1, t.indexOf(']'));
    }
    return t.trim();
  }

  static String _systemNameAr(String system) =>
      SystemNames.ar(system);
}

/// ─────────────────────────────────────────────────────────────────────
/// عناصر القائمة الموحدة — إما ترويسة جهاز أو محاضرة تابعة له.
/// ─────────────────────────────────────────────────────────────────────
class _Row {
  const _Row.header(this.system)
      : unit = null;

  const _Row.unit(this.system, this.unit);

  final String system;
  final Unit? unit;

  bool get isHeader => unit == null;
}

/// يجمع عناصر فريدة بترتيب الإدراج (LinkedHashSet خفيف).
class LinkedHashSetBuilder {
  final List<String> items = <String>[];
  final Set<String> _seen = <String>{};

  void add(String value) {
    if (_seen.add(value)) items.add(value);
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// شيت اختيار الجهاز الهدف عند «نقل إلى نظام آخر».
/// ─────────────────────────────────────────────────────────────────────
class _MoveSheetList extends StatelessWidget {
  const _MoveSheetList({
    required this.systems,
    required this.currentSystem,
    required this.onPick,
  });

  final List<String> systems;
  final String currentSystem;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String system in systems)
          AppCard(
            onTap: system == currentSystem ? null : () => onPick(system),
            color: system == currentSystem
                ? AppColors.surfaceAlt(b)
                : null,
            child: Row(
              children: <Widget>[
                Icon(
                  SystemNames.icon(system),
                  size: 22,
                  color: AppColors.module(
                      _moduleOfSystem(system), b),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    SystemNames.ar(system),
                    style: AppType.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text(b),
                    ),
                  ),
                ),
                if (system == currentSystem)
                  Text(
                    '(النظام الحالي)',
                    style: AppType.caption.copyWith(
                      color: AppColors.textSecondary(b),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String _moduleOfSystem(String system) =>
      SystemNames.moduleOf(system);
}

/// ─────────────────────────────────────────────────────────────────────
/// زر وضع الترتيب العائم.
/// ─────────────────────────────────────────────────────────────────────
class _ReorderModeChip extends StatelessWidget {
  const _ReorderModeChip({
    required this.active,
    required this.onToggle,
  });

  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: active ? primary : AppColors.surface(b),
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onToggle,
        child: AnimatedContainer(
          duration: AppMotion.scaled(context, AppMotion.feedback),
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: active ? primary : AppColors.border(b),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                active
                    ? Icons.check_rounded
                    : Icons.swap_vert_rounded,
                size: 18,
                color: active ? Colors.white : primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                active ? 'تم — اضغط للحفظ' : 'ترتيب يدوي',
                style: AppType.caption.copyWith(
                  color: active ? Colors.white : AppColors.text(b),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
