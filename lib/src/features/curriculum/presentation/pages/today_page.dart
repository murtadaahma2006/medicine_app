import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/motivation_repository.dart';
import '../../../../core/motivation/motivation_model.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../data/unit_repository.dart';
import '../../domain/unit.dart';
import 'concept_reader_page.dart';
import 'reading_blocks_page.dart';
import 'unit_screen.dart';
import '../widgets/global_search_delegate.dart';
import '../../../ai_chat/presentation/widgets/drug_reference_bottom_sheet.dart';

/// شاشة «اليوم» — اللسان الأول: مركز الجلسة اليومية.
///
/// البنية:
/// - ترحيب حسب وقت اليوم + شريحة السلسلة 🔥.
/// - بطاقة أهداف اليوم (المحاضرات المثبتة **حصرياً**) — الحلقة
///   نسبة (المكتملة/المثبتة) والرسالة تعكسان المحاضرات وحدها،
///   مشتقة من `TodayGoalsSnapshot` (checkTodayStatus).
/// - شريط مراجعات ثانوي منفصل (SRS) — رقم بسيط لا يدخل في الحلقة.
/// - قائمة محاضرات أهداف اليوم (مثبتة) بحالة الإكمال لكل واحدة.
/// - بطاقة «تابع من حيث توقفت» — أول محاضرة لم يكتمل تقييمها.
/// - صف إحصاءات مصغر (XP · سلسلة · شروحات مكتملة · بطاقات).
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _loading = true;
  String? _error;

  // أهداف اليوم الموحدة (محاضرات مثبتة + بطاقات مستحقة).
  TodayGoalsSnapshot? _goals;

  // «تابع من حيث توقفت».
  Unit? _nextUnit;

  // السلسلة والإحصاءات المصغرة.
  int _streak = 0;
  int _xp = 0;
  int _completedLessons = 0;
  int _flashcardCount = 0;
  
  // سجلات المرضى
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final UnitRepository repo = UnitRepository();

      // القراءات المستقلة بالتوازي (بدل التسلسل) — أما «تابع من حيث
      // توقفت» فاستعلام واحد: أول محاضرة بترتيب المنهج لم يُكمل
      // تقييمها (بلا حلقة N+1 فوق كل وحدة).
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        repo.getAllUnits(),
        repo.todayGoals(),
        MotivationRepository.snapshot(),
        db.rawQueryParameterized(
          'SELECT u.id FROM ${DatabaseHelper.tableUnits} u '
          'WHERE NOT EXISTS ('
          '  SELECT 1 FROM ${DatabaseHelper.tableUserProgress} p '
          "  WHERE p.item_type = 'drill' AND p.item_id = 'assess-' || u.id "
          "  AND p.status = 'completed') "
          'ORDER BY u.order_index ASC, u.id ASC LIMIT 1',
        ),
        db.rawCount(
          'SELECT COUNT(*) FROM ${DatabaseHelper.tableFlashcards}',
        ),
        db.getPatientRecords(),
      ]);

      final List<Unit> units = results[0] as List<Unit>;
      final List<Map<String, Object?>> nextRows =
          results[3] as List<Map<String, Object?>>;

      // أول محاضرة لم يُكمل تقييمها — «تابع من حيث توقفت».
      final Unit? next = nextRows.isEmpty
          ? null
          : units.firstWhere(
              (Unit u) => u.id == nextRows.first['id'],
              orElse: () => units.first,
            );

      if (!mounted) return;
      setState(() {
        _nextUnit = next;
        _goals = results[1] as TodayGoalsSnapshot;
        final MotivationSnapshot motivation =
            results[2] as MotivationSnapshot;
        _streak = motivation.currentStreak;
        _xp = motivation.totalXp;
        _completedLessons = motivation.completedLessons;
        _flashcardCount = results[4] as int;
        _records = results[5] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (error) {
      AppErrorLogger.instance.record(type: 'TodayPage', error: error);
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل لوحة اليوم.';
        _loading = false;
      });
    }
  }

  String get _greeting {
    final int hour = DateTime.now().hour;
    if (hour < 5) return 'ليلة موفقة';
    if (hour < 12) return 'صباح الخير';
    if (hour < 17) return 'نهارك سعيد';
    return 'مساء الخير';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Brightness b = scheme.brightness;

    // ── Loading / Error / Empty guards ────────────────────────────────────
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
    if (_goals == null) return const SizedBox.shrink();

    // ── Root: CustomScrollView — single scroll physics, zero nesting ──────
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[

          // ── Greeting header & search bar ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.lg,
                bottom: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _greeting,
                              style: AppType.screenTitle
                                  .copyWith(color: AppColors.text(b)),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'جاهز لجلستك اليومية؟',
                              style: AppType.body.copyWith(
                                  color: AppColors.textSecondary(b)),
                            ),
                          ],
                        ),
                      ),
                      StreakChip(streak: _streak),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  // Global search bar (fake TextField — opens delegate).
                  GestureDetector(
                    onTap: () => showSearch<void>(
                      context: context,
                      delegate: GlobalSearchDelegate(),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt(b),
                        borderRadius: BorderRadius.circular(AppRadius.field),
                        border: Border.all(color: AppColors.border(b)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.search_rounded,
                              color: AppColors.primary(b), size: 24),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'ابحث عن أي مصطلح طبي...',
                            style: AppType.body.copyWith(
                                color: AppColors.textSecondary(b),
                                fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Today Goal Card ───────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            sliver: SliverToBoxAdapter(
              child: _TodayGoalCard(
                snapshot: _goals!,
                onOpenLecture: _openUnit,
                onOpenReviews: () => context.push(RoutePaths.dailyReview),
              ),
            ),
          ),



          // ── Continue-where-you-left-off card ─────────────────────────
          if (_nextUnit != null)
            SliverPadding(
              padding: const EdgeInsets.only(
                  left: AppSpacing.xl,
                  right: AppSpacing.xl,
                  top: AppSpacing.betweenCards),
              sliver: SliverToBoxAdapter(
                child: _ContinueCard(
                  unit: _nextUnit!,
                  onTap: () => _openReader(_nextUnit!),
                ),
              ),
            ),

          // ── Deep Reading Blocks ───────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.betweenCards),
            sliver: SliverToBoxAdapter(
              child: _ReadingBlocksEntryCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<Widget>(
                      builder: (_) => const ReadingBlocksPage()),
                ),
              ),
            ),
          ),

          // ── Quick Clinical Tools ──────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.betweenCards),
            sliver: const SliverToBoxAdapter(
              child: _QuickClinicalToolsSection(),
            ),
          ),

          // ── Clinical Physiology Blocks ────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.betweenCards),
            sliver: SliverToBoxAdapter(
              child: _PhysiologyBlocksEntryCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<Widget>(
                    builder: (_) =>
                        const UnitScreen(unitId: 'l_physiology_clinical'),
                  ),
                ),
              ),
            ),
          ),

          // ── Patient Records header & "New Record" button ──────────────
          SliverPadding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              top: AppSpacing.xxl,
              bottom: AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'الردهات (سجلات المرضى)',
                    style:
                        AppType.cardTitle.copyWith(color: AppColors.text(b)),
                  ),
                  FilledButton.icon(
                    onPressed: _showHistoryTypeSelector,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('سجل جديد'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Patient Records — empty state ─────────────────────────────
          if (_records.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt(b),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border(b)),
                  ),
                  child: Center(
                    child: Column(
                      children: <Widget>[
                        Icon(Icons.folder_open_rounded,
                            size: 48,
                            color: AppColors.primary(b)
                                .withValues(alpha: 0.5)),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'لا توجد سجلات حالياً',
                          style: AppType.body.copyWith(
                              color: AppColors.textSecondary(b)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          // ── Patient Records — lazy list (no shrinkWrap, no NeverScroll) ─
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) =>
                      _buildRecordItem(context, _records[index], b, scheme),
                  childCount: _records.length,
                ),
              ),
            ),

          // ── Stats strip ───────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              top: AppSpacing.xxxl,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: StatTile(
                          icon: Icons.bolt_rounded,
                          value: '$_xp',
                          label: 'نقطة خبرة',
                          tint: AppColors.gold(b),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: StatTile(
                          icon: Icons.local_fire_department_rounded,
                          value: '$_streak',
                          label: 'أيام سلسلة',
                          tint: AppColors.error(b),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: StatTile(
                          icon: Icons.check_circle_rounded,
                          value: '$_completedLessons',
                          label: 'شرحاً مكتمل',
                          tint: AppColors.success(b),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: StatTile(
                          icon: Icons.style_rounded,
                          value: '$_flashcardCount',
                          label: 'بطاقة',
                          tint: AppColors.primary(b),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom breathing room ─────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
        ],
      ),
    );
  }

  /// Builds a single patient-record card for the [SliverList].
  Widget _buildRecordItem(
    BuildContext context,
    Map<String, dynamic> record,
    Brightness b,
    ColorScheme scheme,
  ) {
    final String alias = record['patient_alias'] as String;
    final DateTime createdAt =
        DateTime.parse(record['created_at'] as String).toLocal();

    int answersCount = 0;
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(record['responses_json'] as String)
              as Map<String, dynamic>;
      answersCount = decoded.length;
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () => context.push(RoutePaths.recordDetails, extra: record),
        child: ListTile(
          contentPadding: const EdgeInsets.all(AppSpacing.md),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Text(
              alias.isNotEmpty ? alias[0].toUpperCase() : '؟',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            alias,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.calendar_today,
                        size: 14, color: AppColors.textSecondary(b)),
                    const SizedBox(width: 4),
                    Text(
                      '${createdAt.year}/${createdAt.month}/${createdAt.day} '
                      '${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                      style:
                          TextStyle(color: AppColors.textSecondary(b)),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.assignment,
                        size: 14, color: AppColors.textSecondary(b)),
                    const SizedBox(width: 4),
                    Text(
                      '$answersCount حقول',
                      style:
                          TextStyle(color: AppColors.textSecondary(b)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _confirmDelete(record['id'] as int),
          ),
        ),
      ),
    );
  }

  /// يفتح المحاضرة ثم يعيد بناء أهداف اليوم عند العودة — الإتمام
  /// (وإلغاء التثبيت التلقائي) يحدثان خلف الشاشة فتكفي إعادة الجلب.
  Future<void> _openUnit(Unit unit) async {
    await Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) => UnitScreen(unitId: unit.id),
    ));
    if (mounted) await _load();
  }

  /// يفتح قارئ الشروحات مباشرة (لمتابعة القراءة من حيث توقفت).
  Future<void> _openReader(Unit unit) async {
    await Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) => ConceptReaderPage(unitId: unit.id),
    ));
    if (mounted) await _load();
  }

  void _showHistoryTypeSelector() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'اختر نوع السجل',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await context.push(RoutePaths.activeHistory, extra: 'assets/data/history_template.json');
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.edit_document, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text('سجل شامل (ردهات)', style: TextStyle(fontSize: 16)),
                  ),
                  style: ElevatedButton.styleFrom(
                    alignment: Alignment.centerRight,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await context.push(RoutePaths.activeHistory, extra: 'assets/data/basic_history_template.json');
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.flash_on, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text('سجل موجز (عيادة)', style: TextStyle(fontSize: 16)),
                  ),
                  style: ElevatedButton.styleFrom(
                    alignment: Alignment.centerRight,
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await context.push(RoutePaths.smartGuide);
                  },
                  icon: const Icon(Icons.lightbulb, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text('الموجه الذكي (AI Guide)', style: TextStyle(fontSize: 16)),
                  ),
                  style: ElevatedButton.styleFrom(
                    alignment: Alignment.centerRight,
                    backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(int id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('حذف السجل'),
        content: const Text('هل أنت متأكد من حذف هذا السجل؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deletePatientRecord(id);
      if (mounted) await _load();
    }
  }
}

/// بطاقة أهداف اليوم — الهدف اليومي الحقيقي هو **المحاضرات المثبتة
/// حصرياً**: الحلقة تحسب (المكتملة / إجمالي المثبتة) ولا تدخل
/// البطاقات المستحقة في النسبة مهما بلغ عددها.
///
/// الرسائل الرئيسية (checkTodayStatus عبر `TodayGoalsSnapshot.phase`):
/// - لا محاضرات مثبتة → حلقة فارغة + «لا توجد أهداف، ثبّت محاضرة للبدء»
/// - محاضرات مثبتة غير مكتملة → «لديك محاضرات بانتظارك اليوم!»
/// - كل المثبتات مكتملة → «أنجزت جميع أهدافك اليوم! 🌟» (الاحتفال
///   مشروط بمثبتات > 0 — إتمام البطاقات وحده لا يحتفل)
///
/// **شريط المراجعات (Decoupling)**: البطاقات المستحقة شريط ثانوي
/// منفصل أسفل الحلقة يعرض رقماً بسيطاً («بطاقات مستحقة للمراجعة: X»
/// أو «لا توجد مراجعات حالياً») — بلا نسبة ولا اكتمال داخل الحلقة.
class _TodayGoalCard extends StatefulWidget {
  const _TodayGoalCard({
    required this.snapshot,
    required this.onOpenLecture,
    required this.onOpenReviews,
  });

  final TodayGoalsSnapshot snapshot;

  /// فتح محاضرة من أهداف اليوم.
  final void Function(Unit unit) onOpenLecture;

  /// فتح جلسة مراجعة البطاقات المستحقة.
  final VoidCallback onOpenReviews;

  @override
  State<_TodayGoalCard> createState() => _TodayGoalCardState();
}

class _TodayGoalCardState extends State<_TodayGoalCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _helloPulse;

  @override
  void initState() {
    super.initState();
    // نبضة الافتتاح — تُجدولة بعد 800ms من البناء الأول (لحظة توقيع
    // موروثة من بطاقة الهدف القديمة).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) return;
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _helloPulse = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 480),
        )..forward().whenCompleteOrCancel(() {
            _helloPulse?.dispose();
            _helloPulse = null;
            if (mounted) setState(() {});
          });
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _helloPulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final TodayGoalsSnapshot snapshot = widget.snapshot;
    final TodayPhase phase = snapshot.phase;

    // الاحتفال (✓ في الحلقة + رسالة الإنجاز) مشروط بمثبتات > 0
    // وكلها مكتملة — لا احتفال لمجرد خلو البطاقات المستحقة.
    final bool allDone = phase == TodayPhase.done && snapshot.pinned.isNotEmpty;

    final Color accent = allDone
        ? AppColors.success(b)
        : phase == TodayPhase.lectures
            ? Theme.of(context).colorScheme.primary
            : AppColors.textSecondary(b);

    final String title = switch (phase) {
      TodayPhase.none => 'لا توجد أهداف',
      TodayPhase.lectures => 'لديك محاضرات بانتظارك اليوم!',
      TodayPhase.done => 'أنجزت جميع أهدافك اليوم! 🌟',
    };
    final String subtitle = switch (phase) {
      TodayPhase.none => 'ثبّت محاضرة من شاشة المسار لتظهر هنا',
      TodayPhase.lectures => 'أكمل محاضراتك المثبتة لتُنجز يومك',
      TodayPhase.done => 'أحسنت — عد غداً أو ثبّت محاضرة جديدة',
    };

    final Widget card = AppCard(
      // النقر يفتح أول محاضرة معلقة؛ الاكتمال بلا مثبتات لا وجهة له.
      onTap: snapshot.pendingPinned.isNotEmpty
          ? () => widget.onOpenLecture(snapshot.pendingPinned.first)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ProgressRing(
                progress: snapshot.progress,
                size: 64,
                stroke: 6,
                color: accent,
                showKnob: phase == TodayPhase.lectures,
                child: allDone
                    ? Icon(
                        Icons.check_rounded,
                        size: 26,
                        color: AppColors.success(b),
                      )
                    : phase == TodayPhase.none
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'ثبّت محاضرة',
                                textAlign: TextAlign.center,
                                style: AppType.caption.copyWith(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary(b),
                                ),
                              ),
                            ),
                          )
                        : Text(
                            '${(snapshot.progress * 100).round()}%',
                            textDirection: TextDirection.ltr,
                            style: AppType.cardTitle.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppType.cardTitle.copyWith(
                          fontSize: 17, color: AppColors.text(b)),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: AppType.body.copyWith(
                          fontSize: 12.5, color: AppColors.textSecondary(b)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── أهداف المحاضرات المثبتة ──
          if (snapshot.pinned.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(
                height: 1,
                color: AppColors.textSecondary(b).withValues(alpha: 0.15)),
            const SizedBox(height: AppSpacing.sm),
            for (final Unit unit in snapshot.pinned)
              _PinnedGoalRow(
                unit: unit,
                completed: snapshot.completedPinned
                    .any((Unit c) => c.id == unit.id),
                onTap: () => widget.onOpenLecture(unit),
              ),
          ],
        ],
      ),
    );

    // نبضة الافتتاح فوق البطاقة كلها.
    if (_helloPulse == null) return card;
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 1.02).animate(
          CurvedAnimation(parent: _helloPulse!, curve: AppMotion.ease)),
      child: card,
    );
  }
}



/// صف هدف واحد في بطاقة أهداف اليوم — محاضرة مثبتة باسمها وحالة
/// إتمامها. (البطاقات المستحقة انتقلت لشريط _ReviewStrip المنفصل.)
class _PinnedGoalRow extends StatelessWidget {
  const _PinnedGoalRow({
    required this.unit,
    required this.completed,
    required this.onTap,
  });

  final Unit unit;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color done = AppColors.success(b);
    final Color pending = AppColors.gold(b);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: InkWell(
        onTap: completed ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Row(
          children: <Widget>[
            Icon(
              completed
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: completed ? done : pending,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                unit.title,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: completed
                      ? AppColors.textSecondary(b)
                      : AppColors.text(b),
                  decoration: completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (!completed)
              Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: AppColors.textSecondary(b),
              ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة «كتل القراءة العميقة» — بوابة الجرعات القرائية (المقترح D).
class _ReadingBlocksEntryCard extends StatelessWidget {
  const _ReadingBlocksEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color accent = Theme.of(context).colorScheme.primary;

    return AppCard(
      onTap: onTap,
      accent: accent,
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const Center(
              child: Text('🌊', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('كتل القراءة العميقة',
                    style:
                        AppType.cardTitle.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  'غوصة شروح متداخلة الأجهزة — قلب جلستك اليومي',
                  style: AppType.body.copyWith(
                    fontSize: 12.5,
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded,
              color: AppColors.textSecondary(b)),
        ],
      ),
    );
  }
}

/// بطاقة «كتل القراءة العميقة» الخاصة بالفسيولوجيا السريرية.
class _PhysiologyBlocksEntryCard extends StatelessWidget {
  const _PhysiologyBlocksEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color accent = Theme.of(context).colorScheme.secondary;

    return AppCard(
      onTap: onTap,
      accent: accent,
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF009688), Color(0xFF00796B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const Center(
              child: Text('🧬', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('الفسيولوجيا السريرية',
                    style:
                        AppType.cardTitle.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  'فهم الأساس الفسيولوجي والربط السريري والدوائي',
                  style: AppType.body.copyWith(
                    fontSize: 12.5,
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded,
              color: AppColors.textSecondary(b)),
        ],
      ),
    );
  }
}

/// بطاقة «تابع من حيث توقفت» — أول محاضرة غير مكتملة.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.unit, required this.onTap});

  final Unit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color moduleColor = AppColors.module(unit.module, b);

    return AppCard(
      onTap: onTap,
      accent: moduleColor,
      child: Row(
        children: <Widget>[
          ModuleIcon(
            unit.module,
            size: 52,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('تابع من حيث توقفت',
                    style: AppType.caption
                        .copyWith(color: AppColors.textSecondary(b))),
                const SizedBox(height: 2),
                Text(
                  unit.title,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style:
                      AppType.body.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                ModuleBadge(unit.module),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary(b)),
        ],
      ),
    );
  }
}

/// قسم الأدوات السريرية السريعة (Quick Clinical Tools)
class _QuickClinicalToolsSection extends StatelessWidget {
  const _QuickClinicalToolsSection();

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'أدوات سريرية سريعة',
            style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _ClinicalToolCard(
                title: 'حاسبات طبية',
                icon: Icons.calculate_rounded,
                color: Theme.of(context).colorScheme.primary,
                onTap: () => context.push('/clinical-tools/calculators'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ClinicalToolCard(
                title: 'القيم المخبرية',
                icon: Icons.science_rounded,
                color: Theme.of(context).colorScheme.secondary,
                onTap: () => context.push('/clinical-tools/lab-values'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ClinicalToolCard(
                title: 'دليل الأدوية',
                icon: Icons.medical_information_rounded,
                color: const Color(0xFF009688), // Teal medical accent
                onTap: () => DrugReferenceBottomSheet.show(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClinicalToolCard extends StatelessWidget {
  const _ClinicalToolCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 28, color: color),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: AppType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.text(b),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
