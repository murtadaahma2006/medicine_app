import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/motivation_repository.dart';
import '../../../../core/motivation/motivation_model.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../data/unit_repository.dart';
import '../../domain/unit.dart';
import 'reading_blocks_page.dart';
import 'unit_screen.dart';

/// شاشة «اليوم» — اللسان الأول: مركز الجلسة اليومية.
///
/// البنية:
/// - ترحيب حسب وقت اليوم + شريحة السلسلة 🔥.
/// - بطاقة حلقة أهداف اليوم الموحدة (محاضرات مثبتة + بطاقات مستحقة)
///   — الحلقة والرسالة يُشتقان من `TodayGoalsSnapshot` (checkTodayStatus).
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
      final List<Unit> units = await repo.getAllUnits();

      // أول محاضرة لم يُكمل تقييمها — «تابع من حيث توقفت».
      Unit? next;
      for (final Unit unit in units) {
        final List<Map<String, Object?>> rows =
            await db.rawQueryParameterized(
          'SELECT status FROM ${DatabaseHelper.tableUserProgress} '
          "WHERE item_type = 'drill' AND item_id = ? LIMIT 1",
          <Object?>['assess-${unit.id}'],
        );
        if (rows.isEmpty || rows.first['status'] != 'completed') {
          next = unit;
          break;
        }
      }

      // بقية القراءات.
      final TodayGoalsSnapshot goals = await repo.todayGoals();
      final MotivationSnapshot motivation =
          await MotivationRepository.snapshot();
      final int flashcards = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableFlashcards}',
      );

      if (!mounted) return;
      setState(() {
        _nextUnit = next;
        _goals = goals;
        _streak = motivation.currentStreak;
        _xp = motivation.totalXp;
        _completedLessons = motivation.completedLessons;
        _flashcardCount = flashcards;
        _loading = false;
      });
    } catch (_) {
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
    final Brightness b = Theme.of(context).colorScheme.brightness;

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
    if (_goals == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        children: <Widget>[
          // ── ترحيب + السلسلة ──
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _greeting,
                      style: AppType.screenTitle.copyWith(
                        color: AppColors.text(b),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'جاهز لجلستك اليومية؟',
                      style: AppType.body
                          .copyWith(color: AppColors.textSecondary(b)),
                    ),
                  ],
                ),
              ),
              StreakChip(streak: _streak),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── بطاقة أهداف اليوم الموحدة (محاضرات + بطاقات) ──
          _TodayGoalCard(
            snapshot: _goals!,
            onOpenLecture: _openUnit,
            onOpenReviews: () => context.push(RoutePaths.dailyReview),
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── كتل القراءة العميقة (المقترح D) ──
          _ReadingBlocksEntryCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
              builder: (_) => const ReadingBlocksPage(),
            )),
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── تابع من حيث توقفت ──
          if (_nextUnit != null)
            _ContinueCard(
              unit: _nextUnit!,
              onTap: () => _openUnit(_nextUnit!),
            ),

          const SizedBox(height: AppSpacing.xxl),

          // ── صف إحصاءات مصغر ──
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

          const SizedBox(height: AppSpacing.xxxl),
        ],
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
}

/// بطاقة أهداف اليوم الموحدة — **مقياس الشمال الجديد**: الحلقة
/// تُحتسب من إكمال المحاضرات المثبتة **مع** البطاقات المستحقة (سهم
/// واحد لكل محاضرة + سهم لحزمة المراجعة)، فلا «اكتمل يومك» والمحاضرة
/// المثبتة بانتظارك.
///
/// الرسائل (checkTodayStatus عبر `TodayGoalsSnapshot.phase`):
/// - محاضرات مثبتة غير مكتملة → «لديك محاضرات بانتظارك اليوم!»
/// - لا محاضرات (أو اكتملت) + بطاقات مستحقة → «لديك مراجعات مستحقة»
/// - الاثنان مكتملان → «مهام اليوم مكتملة 🌟»
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
    final bool allDone = phase == TodayPhase.done;

    final Color accent = allDone
        ? AppColors.success(b)
        : phase == TodayPhase.lectures
            ? Theme.of(context).colorScheme.primary
            : AppColors.gold(b);

    final String title = switch (phase) {
      TodayPhase.lectures => 'لديك محاضرات بانتظارك اليوم!',
      TodayPhase.reviews => 'لديك مراجعات مستحقة',
      TodayPhase.done => 'مهام اليوم مكتملة 🌟',
    };
    final String subtitle = switch (phase) {
      TodayPhase.lectures =>
        'أكمل محاضراتك المثبتة أولاً — ثم راجع بطاقاتك',
      TodayPhase.reviews =>
        'النظام جدولها بناءً على تقدمك — راجعها الآن',
      TodayPhase.done => 'أحسنت — عد غداً أو ابدأ محاضرة جديدة',
    };

    final Widget card = AppCard(
      onTap: phase == TodayPhase.reviews
          ? widget.onOpenReviews
          : snapshot.pendingPinned.isNotEmpty
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
                showKnob: !allDone,
                child: Text(
                  allDone
                      ? '✓'
                      : '${(snapshot.progress * 100).round()}%',
                  textDirection: TextDirection.ltr,
                  style: AppType.cardTitle.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: allDone ? 24 : 14,
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

          // ── هدف المراجعة (SRS) ──
          const SizedBox(height: AppSpacing.sm),
          _PinnedGoalRow(
            unit: null,
            dueCards: snapshot.dueCards,
            completed: snapshot.dueCards == 0,
            onTap: widget.onOpenReviews,
          ),
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

/// صف هدف واحد في بطاقة أهداف اليوم — محاضرة مثبتة (باسمها وحالتها)
/// أو حزمة مراجعة البطاقات المستحقة (unit == null).
class _PinnedGoalRow extends StatelessWidget {
  const _PinnedGoalRow({
    required this.unit,
    required this.completed,
    required this.onTap,
    this.dueCards,
  });

  final Unit? unit;
  final bool completed;
  final VoidCallback onTap;

  /// عدد البطاقات المستحقة (عندما unit == null).
  final int? dueCards;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color done = AppColors.success(b);
    final Color pending = AppColors.gold(b);

    // نص الصف: عنوان المحاضرة المثبتة أو ملخص بطاقات المراجعة.
    final Unit? pinnedUnit = unit;
    final String label = pinnedUnit == null
        ? (dueCards == 0
            ? 'بطاقات اليوم مكتملة'
            : 'مراجعة $dueCards بطاقة مستحقة')
        : pinnedUnit.title;
    final TextDirection direction =
        pinnedUnit == null ? TextDirection.rtl : TextDirection.ltr;

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
                label,
                textDirection: direction,
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
