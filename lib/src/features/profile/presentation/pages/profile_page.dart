import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/motivation_repository.dart';
import '../../../../core/database/user_progress.dart';
import '../../../../core/motivation/motivation_model.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../progress/presentation/pages/focus_minutes_page.dart';

/// شاشة «ملفّي» — اللسان الرابع، محسّنة بالمرحلة 5.
///
/// - بطاقة رأس بشخصية المتعلم: مستواه من نقاط الخبرة (LearnerLevel)
///   + حلقة نحو المستوى التالي + السلسلة 🔥.
/// - رصف إحصاءات عبر [StatTile] الموحد (وحدة/مفردة/XP/درس/مجموعة/سلسلة).
/// - بطاقة نقاط الضعف + روابط سريعة (إحصائياتي/الإعدادات).
/// - شريط «تقدّمك» عبر [ProgressBar] متحرك (مجموعات مفردات من الوحدات).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  String? _error;
  int _unitsCount = 0;
  int _vocabCount = 0;
  int _xp = 0;
  int _completedLessons = 0;
  int _completedVocabSets = 0;
  int _streak = 0;
  int _longestStreak = 0;
  int _focusMinutesToday = 0;
  MotivationSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final DatabaseHelper helper = DatabaseHelper.instance;
      final List<Map<String, Object?>> units =
          await helper.getAllUnits();
      final int vocab = await helper.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableFlashcards}',
      );
      final MotivationSnapshot motivation =
          await MotivationRepository.snapshot();
      final int xp = motivation.totalXp;
      final int completed = await helper.countCompletedByType(
        ProgressItemType.lesson,
      );
      // مجموعات البطاقات المكتملة — أساس شريط «تقدّمك».
      final int completedVocabSets = await helper.countCompletedByType(
        ProgressItemType.flashcardSet,
      );
      // دقائق التركيز اليوم (مقياس الشمال — من flow_sessions).
      final String today =
          DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final int focusSeconds = await helper.focusedSecondsOnDay(today);
      if (!mounted) return;
      setState(() {
        _unitsCount = units.length;
        _vocabCount = vocab;
        _xp = xp;
        _completedLessons = completed;
        _completedVocabSets = completedVocabSets;
        _streak = motivation.currentStreak;
        _longestStreak = motivation.longestStreak;
        _focusMinutesToday = (focusSeconds / 60).floor();
        _snapshot = motivation;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الملف الشخصي.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return ColoredBox(
      color: AppColors.background(b),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  actionLabel: 'إعادة المحاولة',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: <Widget>[
                      // ── بطاقة رأس بشخصية المتعلم ──
                      _LearnerHeaderCard(
                        xp: _xp,
                        streak: _streak,
                        snapshot: _snapshot,
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // ── دقائق التركيز — مقياس الشمال البارز ──
                      _FocusMinutesCard(
                        minutesToday: _focusMinutesToday,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute<Widget>(
                          builder: (_) => const FocusMinutesPage(),
                        )),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // ── رصف الإحصاءات الموحد ──
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: StatTile(
                              icon: Icons.menu_book_rounded,
                              value: '$_unitsCount',
                              label: 'محاضرة',
                              tint: AppColors.primary(b),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: StatTile(
                              icon: Icons.style_rounded,
                              value: '$_vocabCount',
                              label: 'بطاقة',
                              tint: AppColors.success(b),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
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
                              icon: Icons.check_circle_rounded,
                              value: '$_completedLessons',
                              label: 'شرحاً مكتمل',
                              tint: AppColors.primary(b),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: StatTile(
                              icon: Icons.local_fire_department_rounded,
                              value: '$_streak',
                              label: 'أيام سلسلة',
                              tint: AppColors.error(b),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: StatTile(
                              icon: Icons.military_tech_rounded,
                              value: '$_longestStreak',
                              label: 'أطول سلسلة',
                              tint: AppColors.gold(b),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // ── شريط تقدّم المحاضرات (المنهج) ──
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('تقدم المنهج',
                                style: AppType.cardTitle.copyWith(
                                    color: AppColors.text(b))),
                            const SizedBox(height: AppSpacing.md),
                            ProgressBar(
                              progress: _unitsCount == 0
                                  ? 0
                                  : (_completedLessons / _unitsCount)
                                      .clamp(0.0, 1.0),
                              height: 10,
                              color: AppColors.success(b),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '$_completedLessons / $_unitsCount مكتمل',
                              style: AppType.body.copyWith(
                                  color: AppColors.textSecondary(b)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.betweenCards),

                      // ── روابط سريعة ──
                      _QuickLinksCard(),
                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
    );
  }
}

/// بطاقة دقائق التركيز — الرقم الأهم فوق XP (مقياس الشمال).
class _FocusMinutesCard extends StatelessWidget {
  const _FocusMinutesCard({
    required this.minutesToday,
    required this.onTap,
  });

  final int minutesToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color accent = AppColors.success(b);

    return AppCard(
      onTap: onTap,
      accent: accent,
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(Icons.timer_outlined, size: 26, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'دقائق التركيز اليوم',
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary(b),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$minutesToday دقيقة قراءة مركّزة — هذا هو الرقم المهم',
                  style: AppType.cardTitle.copyWith(
                    fontSize: 16,
                    color: AppColors.text(b),
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

/// بطاقة رأس المتعلم — مستواه من XP + حلقة نحو التالي + السلسلة.
class _LearnerHeaderCard extends StatelessWidget {
  const _LearnerHeaderCard({
    required this.xp,
    required this.streak,
    this.snapshot,
  });

  final int xp;
  final int streak;
  final MotivationSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final LearnerLevel level = LearnerLevel.forXp(xp);
    final LearnerLevel? next = level.next;
    final double progress = level.progressToNext(xp);
    final String progressLabel = next == null
        ? 'أعلى مستوى!'
        : '${next.minXp - xp} نقطة حتى ${next.titleAr}';

    return AppCard(
      accent: AppColors.gold(b),
      child: Row(
        children: <Widget>[
          // حلقة المستوى: إيموجي المستوى داخل حلقة نحو التالي.
          ProgressRing(
            progress: progress,
            size: 68,
            stroke: 6,
            color: AppColors.gold(b),
            showKnob: next != null,
            child: Text(
              level.emoji,
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${level.titleAr} · $progressLabel',
                  style: AppType.cardTitle.copyWith(
                      fontSize: 17, color: AppColors.text(b)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$xp نقطة خبرة',
                  style: AppType.body.copyWith(
                      color: AppColors.textSecondary(b)),
                ),
                if (snapshot != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: <Widget>[
                      Icon(Icons.local_fire_department_rounded,
                          size: 15,
                          color: streak > 0
                              ? AppColors.gold(b)
                              : AppColors.textSecondary(b)),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'سلسلة $streak يوم${streak == 1 ? '' : 'اً'}'
                        '${snapshot!.longestStreak > streak ? ' · الأطول ${snapshot!.longestStreak}' : ''}',
                        style: AppType.caption.copyWith(
                            color: AppColors.textSecondary(b)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة الروابط السريعة — إحصائياتي وشاراتي + الإعدادات.
class _QuickLinksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: Icon(Icons.insights_rounded,
                color: AppColors.primary(b)),
            title: Text('إحصائياتي وشاراتي',
                style: AppType.body.copyWith(
                    fontWeight: FontWeight.w700, color: AppColors.text(b))),
            subtitle: Text(
              'المستوى، السلسلة اليومية، الشارات، وأفضل النتائج',
              style: AppType.body.copyWith(
                  fontSize: 12.5, color: AppColors.textSecondary(b)),
            ),
            trailing: Icon(Icons.chevron_left_rounded,
                color: AppColors.textSecondary(b)),
            onTap: () => context.push(RoutePaths.progress),
          ),
          Divider(
            height: 1,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
            color: AppColors.border(b),
          ),
          ListTile(
            leading: Icon(Icons.settings_rounded,
                color: AppColors.primary(b)),
            title: Text('الإعدادات',
                style: AppType.body.copyWith(
                    fontWeight: FontWeight.w700, color: AppColors.text(b))),
            subtitle: Text(
              'التذكير اليومي والنسخ الاحتياطي',
              style: AppType.body.copyWith(
                  fontSize: 12.5, color: AppColors.textSecondary(b)),
            ),
            trailing: Icon(Icons.chevron_left_rounded,
                color: AppColors.textSecondary(b)),
            onTap: () => context.push(RoutePaths.settings),
          ),
        ],
      ),
    );
  }
}
