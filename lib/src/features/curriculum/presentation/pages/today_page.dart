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
import 'reading_blocks_page.dart';
import 'unit_screen.dart';

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

          // ── بطاقة أهداف اليوم (المحاضرات المثبتة حصرياً) ──
          _TodayGoalCard(
            snapshot: _goals!,
            onOpenLecture: _openUnit,
            onOpenReviews: () => context.push(RoutePaths.dailyReview),
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── شريط المراجعات الثانوي (SRS) — رقم بسيط منفصل عن الحلقة ──
          _ReviewStrip(
            dueCards: _goals!.dueCards,
            onOpenReviews: () => context.push(RoutePaths.dailyReview),
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── كتل القراءة العميقة (المقترح D) ──
          _ReadingBlocksEntryCard(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<Widget>(
                  builder: (_) => const ReadingBlocksPage(),
                ),
              );
            },
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── كتل الفسيولوجيا السريرية ──
          _PhysiologyBlocksEntryCard(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<Widget>(
                  builder: (_) => const UnitScreen(unitId: 'l_physiology_clinical'),
                ),
              );
            },
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

/// شريط المراجعات الثانوي (Decoupling) — البطاقات المستحقة عرض
/// منفصل أسفل بطاقة الأهداف: رقم بسيط بلا نسبة ولا تأثير على الحلقة.
/// صفر → «لا توجد مراجعات حالياً» بلا نقرة. أكثر → نقرة تفتح
/// جلسة المراجعة اليومية.
class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({
    required this.dueCards,
    required this.onOpenReviews,
  });

  final int dueCards;

  final VoidCallback onOpenReviews;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool hasDue = dueCards > 0;
    final Color accent = hasDue ? AppColors.gold(b) : AppColors.success(b);

    return AppCard(
      onTap: hasDue ? onOpenReviews : null,
      child: Row(
        children: <Widget>[
          Icon(
            hasDue
                ? Icons.style_rounded
                : Icons.check_circle_outline_rounded,
            size: 22,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              hasDue
                  ? 'بطاقات مستحقة للمراجعة: $dueCards'
                  : 'لا توجد مراجعات حالياً',
              style: AppType.body.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: hasDue ? AppColors.text(b) : AppColors.textSecondary(b),
              ),
            ),
          ),
          if (hasDue)
            Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: AppColors.textSecondary(b),
            ),
        ],
      ),
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
