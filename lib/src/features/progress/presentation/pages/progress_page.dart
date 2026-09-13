import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/motivation_repository.dart';
import '../../../../core/motivation/motivation_model.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة الإحصاءات والتحفيز — الشاشة التوقيعية (المرحلة 5).
///
/// بطاقة المستوى (حلقة نحو المستوى التالي) · صف السلسلة · التقويم
/// الحراري (خلاياه تدخل بتتابع 40ms لكل عمود) · شبكة الشارات بهوية
/// النظام · عدادات إنجاز تتصاعد (TweenAnimationBuilder) — كل شيء
/// من مكتبة نظام التصميم.
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  MotivationSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final MotivationSnapshot snapshot =
          await MotivationRepository.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل الإحصائيات. تحقق من سلامة قاعدة البيانات.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        backgroundColor: AppColors.background(b),
        title: Text('إحصائياتي',
            style: AppType.caption
                .copyWith(fontSize: 14, color: AppColors.textSecondary(b))),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push(RoutePaths.reminder),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'التذكير اليومي',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || _snapshot == null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: _error ?? 'لا توجد بيانات.',
                  actionLabel: 'إعادة المحاولة',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: <Widget>[
                      _LevelCard(snapshot: _snapshot!),
                      const SizedBox(height: AppSpacing.betweenCards),
                      _StreakRow(snapshot: _snapshot!),
                      const SizedBox(height: AppSpacing.betweenCards),
                      const _StreakCalendar(),
                      const SizedBox(height: AppSpacing.betweenCards),
                      _BadgesGrid(snapshot: _snapshot!),
                      const SizedBox(height: AppSpacing.betweenCards),
                      _StatsSection(snapshot: _snapshot!),
                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────── بطاقة المستوى ───────────────────────────

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.snapshot});

  final MotivationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final LearnerLevel level = LearnerLevel.forXp(snapshot.totalXp);
    final LearnerLevel? next = level.next;
    final double progress = level.progressToNext(snapshot.totalXp);

    // «X نقطة حتى [المستوى التالي]» أو «أعلى مستوى!».
    final String progressLabel = next == null
        ? 'أعلى مستوى!'
        : '${next.minXp - snapshot.totalXp} نقطة حتى ${next.titleAr}';

    return AppCard(
      accent: AppColors.gold(b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              ProgressRing(
                progress: progress,
                size: 72,
                stroke: 7,
                color: AppColors.gold(b),
                showKnob: next != null,
                child: Text(level.emoji,
                    style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(level.titleAr,
                        style: AppType.cardTitle
                            .copyWith(color: AppColors.text(b))),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${snapshot.totalXp} XP',
                      textDirection: TextDirection.ltr,
                      style: AppType.termWord.copyWith(
                        fontSize: 20,
                        color: AppColors.primary(b),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ProgressBar(
            progress: progress,
            height: 10,
            color: AppColors.gold(b),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            progressLabel,
            style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── صف السلسلة ───────────────────────────

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.snapshot});

  final MotivationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AppCard(
      color: AppColors.primaryTint(b),
      child: Row(
        children: <Widget>[
          AppIllustration('badge_streak3', size: 48, borderRadius: BorderRadius.circular(12),),
          const SizedBox(width: AppSpacing.md),
          // عدّاد السلسلة يتصاعد.
          _CountUp(
            value: snapshot.currentStreak,
            style: AppType.termWord.copyWith(
              fontSize: 34,
              color: AppColors.primary(b),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'أيام متتابعة',
                  style: AppType.cardTitle.copyWith(
                      fontSize: 17, color: AppColors.text(b)),
                ),
                Text(
                  'أطول سلسلة: ${snapshot.longestStreak}',
                  style: AppType.body.copyWith(
                      color: AppColors.textSecondary(b)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────── تقويم السلسلة الحراري ──────────────────────

/// تقويم نشاط آخر 35 يوماً (5 أسابيع × 7) — خلايا تتوهج بالأيام
/// النشطة، وأعمدته تدخل بتتابع (40ms لكل عمود — أسبوع).
///
/// مصدر الأيام: أيام النشاط من xp_events حصراً (نفس قرار مصدر السلاسل
/// الموثق في MotivationRepository).
class _StreakCalendar extends StatefulWidget {
  const _StreakCalendar();

  @override
  State<_StreakCalendar> createState() => _StreakCalendarState();
}

class _StreakCalendarState extends State<_StreakCalendar> {
  Set<String>? _activeDays;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<String> days = await MotivationRepository.activeDays();
      if (!mounted) return;
      setState(() => _activeDays = days.toSet());
    } catch (_) {
      if (!mounted) return;
      setState(() => _activeDays = <String>{});
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Set<String>? activeDays = _activeDays;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIllustration('icon_calendar', size: 24, borderRadius: BorderRadius.circular(8),),
              const SizedBox(width: AppSpacing.sm),
              Text('آخر ٥ أسابيع',
                  style:
                      AppType.cardTitle.copyWith(color: AppColors.text(b))),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (activeDays == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Column(
              children: <Widget>[
                // عمود (أسبوع) يدخل بتتابع 40ms — الأقدم أولاً.
                for (int week = 0; week < 5; week++)
                  _WeekRow(
                    week: week,
                    activeDays: activeDays,
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.success(b).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text('نشاط',
                  style: AppType.caption
                      .copyWith(color: AppColors.textSecondary(b))),
              const SizedBox(width: AppSpacing.md),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(b),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text('راحة',
                  style: AppType.caption
                      .copyWith(color: AppColors.textSecondary(b))),
            ],
          ),
        ],
      ),
    );
  }
}

/// صف أسبوع واحد — يدخل بتدرج (40ms × رقمه) مرة واحدة.
class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.week, required this.activeDays});

  final int week;
  final Set<String> activeDays;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool animOn = !MediaQuery.disableAnimationsOf(context);

    Widget row = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (int day = 0; day < 7; day++)
            _buildCell(b, week, day),
        ],
      ),
    );

    if (!animOn) return row;
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: AppMotion.scaled(
            context, Duration(milliseconds: 300 + week * 40)),
        curve: AppMotion.ease,
        builder: (BuildContext context, double v, Widget? child) => Opacity(
          opacity: v,
          child: Transform.scale(
            scale: 0.9 + 0.1 * v,
            child: child,
          ),
        ),
        child: row,
      ),
    );
  }

  /// خلية يوم واحد: التاريخ = اليوم - (34 - index).
  Widget _buildCell(Brightness b, int week, int day) {
    // العمود الأول (أقصى اليمين بصرياً في RTL هو index 0) = الأقدم.
    final int daysAgo = 34 - (week * 7 + day);
    final DateTime date =
        DateTime.now().toUtc().subtract(Duration(days: daysAgo));
    final String key = date.toIso8601String().substring(0, 10);
    final bool active = activeDays.contains(key);
    final bool isToday = daysAgo == 0;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: active
            ? AppColors.success(b).withValues(alpha: 0.9)
            : AppColors.surfaceAlt(b),
        borderRadius: BorderRadius.circular(AppRadius.chip - 4),
        border: isToday
            ? Border.all(color: AppColors.primary(b), width: 2)
            : Border.all(color: AppColors.border(b)),
      ),
      child: active
          ? Center(
              child: Icon(
                Icons.check_rounded,
                size: 16,
                color: AppColors.surface(b),
              ),
            )
          : null,
    );
  }
}

// ─────────────────────────── شبكة الشارات ───────────────────────────

class _BadgesGrid extends StatelessWidget {
  const _BadgesGrid({required this.snapshot});

  final MotivationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final List<(BadgeDef, bool)> states = snapshot.badgeStates();
    final int unlockedCount =
        states.where(((BadgeDef, bool) s) => s.$2).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('الشارات',
                  style: AppType.cardTitle.copyWith(
                      color: AppColors.text(b))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint(b),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$unlockedCount / ${states.length}',
                  textDirection: TextDirection.ltr,
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary(b),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 0.85,
            children: <Widget>[
              for (final (BadgeDef, bool) state in states)
                _BadgeCell(def: state.$1, unlocked: state.$2),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgeCell extends StatelessWidget {
  const _BadgeCell({required this.def, required this.unlocked});

  final BadgeDef def;
  final bool unlocked;

  void _showDetails(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    AppSheet.show<void>(
      context,
      title: def.titleAr,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ميدالية SVG — أو إيموجي بديل آمن.
          BadgeIcon(
            def.id,
            size: 88,
            locked: !unlocked,
            emojiFallback: def.emoji,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            def.descriptionAr,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(
                color: AppColors.textSecondary(b), height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            unlocked ? 'مفتوحة ✓' : 'مقفلة — تستحق المطاردة!',
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: unlocked
                  ? AppColors.success(b)
                  : AppColors.textSecondary(b),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDetails(context),
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: AnimatedOpacity(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.transition,
          opacity: unlocked ? 1.0 : 0.85,
          child: Container(
            decoration: BoxDecoration(
              color: unlocked
                  ? AppColors.successContainer(b).withValues(alpha: 0.6)
                  : AppColors.surfaceAlt(b),
              borderRadius: BorderRadius.circular(AppRadius.field),
              border: Border.all(
                color: unlocked
                    ? AppColors.success(b).withValues(alpha: 0.7)
                    : AppColors.border(b),
                width: unlocked ? 1.6 : 1,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // ميدالية SVG — مقفلة تظهر كظل صامت (silhouette)
                  // بشفافية 15% يديرها BadgeIcon داخلياً.
                  BadgeIcon(
                    def.id,
                    size: 44,
                    locked: !unlocked,
                    emojiFallback: def.emoji,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs),
                    child: Text(
                      def.titleAr,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                          color: unlocked
                              ? AppColors.text(b)
                              : AppColors.textSecondary(b).withValues(alpha: 0.6),
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── إحصاءات رقمية ───────────────────────────

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.snapshot});

  final MotivationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader('إنجازاتك بالأرقام'),
        _StatCard(
          icon: Icons.school_rounded,
          label: 'شروحات مكتملة',
          value: snapshot.completedLessons,
        ),
        _StatCard(
          icon: Icons.style_rounded,
          label: 'مجموعات بطاقات مكتملة',
          value: snapshot.completedVocabSets,
        ),
        _StatCard(
          icon: Icons.quiz_rounded,
          label: 'جلسات مثالية (أسئلة MCQ)',
          value: snapshot.perfectMcqSessions,
        ),
        _StatCard(
          icon: Icons.medical_services_rounded,
          label: 'قرارات سريرية صحيحة',
          value: snapshot.correctCaseSteps,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryTint(b),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Icon(icon,
                  color: AppColors.primary(b), size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppType.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.text(b)),
              ),
            ),
            // القيمة تتصاعد تصاعدياً عند البناء.
            _CountUp(
              value: value,
              style: AppType.termWord.copyWith(
                fontSize: 24,
                color: AppColors.primary(b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// عدّاد تصاعدي — من 0 إلى value خلال 900ms (أرقام جدولية).
///
/// نسخة مطابقة لعقل _CountUp في شاشة النتيجة الموحدة — مكررة هنا
/// خصوصاً لأن النسخة هناك خاصة بمكوّن النتيجة (private)؛ توحيد كامل
/// يمر عبر نقلها لمكتبة المكونات في المرحلة 7 (جرد التوحيد).
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text('$value',
          textDirection: TextDirection.ltr, style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: Tween<int>(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: AppMotion.ease,
      builder: (BuildContext context, int v, Widget? _) => Text(
        '$v',
        textDirection: TextDirection.ltr,
        style: style,
      ),
    );
  }
}
