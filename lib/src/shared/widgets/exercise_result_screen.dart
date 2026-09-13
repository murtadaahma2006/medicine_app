import 'package:flutter/material.dart';

import '../../core/motivation/celebration_queue.dart';
import '../../theme/tokens.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'confetti.dart';
import 'progress.dart';

/// ─────────────────────────────────────────────────────────────────────
/// شاشة النتيجة الموحدة لكل تمارين التطبيق (المرحلة 4).
///
/// - حلقة [ProgressRing] تمتلئ بحركة (لا CircularProgressIndicator).
/// - عدادات تصاعدية للنسبة والصحيح/الإجمالي (TweenAnimationBuilder).
/// - كونفيتي موحد [ConfettiBurst] عند ≥90% — المشهد الوحيد في التطبيق.
/// - ملخص XP مكتسب + إيموجي/رسالة حسب الأداء.
/// - أزرار: إعادة الجلسة (اختياري) + العودة + أزرار إضافية مخصصة.
///
/// تستقبل بيانات صرفة (لا متحكم) — كل جلسة تمرر قيمها.
/// ─────────────────────────────────────────────────────────────────────
class ExerciseResultScreen extends StatelessWidget {
  const ExerciseResultScreen({
    required this.score,
    required this.total,
    this.title = 'انتهت الجلسة!',
    this.xpEarned,
    this.newBadges = const <String>[],
    this.onRetry,
    this.onExit,
    this.additionalActions = const <Widget>[],
    this.retryLabel = 'إعادة الجلسة',
    this.exitLabel = 'العودة',
    super.key,
  });

  final int score;
  final int total;

  /// عنوان علوي — «اختبار الوحدة» مثلاً.
  final String title;

  /// XP مكتسب من الجلسة (يعرض في رقاقة ⚡).
  final int? xpEarned;

  /// شارات مكتسبة (نصها فقط هنا — الاحتفال البصري للمرحلة 6).
  final List<String> newBadges;

  final VoidCallback? onRetry;
  final VoidCallback? onExit;
  final List<Widget> additionalActions;

  final String retryLabel;
  final String exitLabel;

  static String messageFor(int percent) {
    if (percent >= 90) return 'ممتاز! 🌟';
    if (percent >= 70) return 'جيد جداً! 👏';
    if (percent >= 50) return 'جيد — استمر 💪';
    return 'تحتاج مراجعة 📖';
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final int percent =
        total == 0 ? 0 : ((score / total) * 100).round().clamp(0, 100);

    // لون الحلقة يتدرج مع الأداء.
    final Color ringColor = percent >= 70
        ? AppColors.success(b)
        : percent >= 50
            ? AppColors.gold(b)
            : AppColors.error(b);

    // كونفيتي عند الامتياز — مرة واحدة بعد أول إطار. يؤجل إن كان حدث
    // احتفالي جارٍ (طابور المرحلة 6 يطلقه عند حاجته الخاصة) — الحراسة
    // الثابتة في ConfettiBurst تمنع التداخل مزدوجة.
    if (percent >= 90 && !MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted &&
            !CelebrationQueue.instance.hasBigEventsPending) {
          ConfettiBurst.show(context);
        }
      });
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // ── الحلقة الكبيرة الممتلئة ──
              ProgressRing(
                progress: percent / 100,
                size: 190,
                stroke: 13,
                color: ringColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // عدّاد النسبة التصاعدي.
                    _CountUp(
                      value: percent,
                      suffix: '%',
                      style: AppType.screenTitle.copyWith(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        color: ringColor,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // عدّاد الصحيح/الإجمالي.
                    _CountUp(
                      value: score,
                      prefix: '',
                      suffix: ' من $total',
                      style: AppType.body.copyWith(
                        color: AppColors.textSecondary(b),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // ── الرسالة ──
              Text(
                messageFor(percent),
                style:
                    AppType.screenTitle.copyWith(color: AppColors.text(b)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── ملخص XP + شارات ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (xpEarned != null && xpEarned! > 0)
                    _XpChip(xp: xpEarned!),
                  if (xpEarned != null && xpEarned! > 0 && newBadges.isNotEmpty)
                    const SizedBox(width: AppSpacing.sm),
                  if (newBadges.isNotEmpty)
                    Text(
                      '🏅 ${newBadges.length} ${newBadges.length == 1 ? 'شارة جديدة' : 'شارات جديدة'}',
                      style: AppType.caption
                          .copyWith(color: AppColors.goldText(b)),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.xxxl),

              // ── الأزرار ──
              if (onRetry != null) ...<Widget>[
                AppButton(
                  label: retryLabel,
                  icon: Icons.replay_rounded,
                  onPressed: onRetry,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (additionalActions.isNotEmpty) ...<Widget>[
                ...additionalActions,
                const SizedBox(height: AppSpacing.md),
              ],
              AppButton(
                label: exitLabel,
                icon: Icons.arrow_forward_rounded,
                type: AppButtonType.ghost,
                onPressed: onExit ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عدّاد تصاعدي — من 0 إلى value خلال 900ms بأرقام جدولية.
class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
  });

  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text('$prefix$value$suffix', style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: Tween<int>(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: AppMotion.ease,
      builder: (BuildContext context, int v, Widget? _) => Text(
        '$prefix$v$suffix',
        textDirection: TextDirection.ltr,
        style: style,
      ),
    );
  }
}

/// رقاقة XP ذهبية.
class _XpChip extends StatelessWidget {
  const _XpChip({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color gold = AppColors.gold(b);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs + 1),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bolt_rounded, size: 16, color: gold),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '+$xp',
            textDirection: TextDirection.ltr,
            style: AppType.caption.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: gold,
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// شاشة نتيجة التقييم الموحدة — نسخة أقسام (مثلاً: بطاقات/أسئلة/حالات).
///
/// نفس الهوية (حلقة + عدادات + كونفيتي) + صف أشرطة درجات الأقسام
/// والتوصية — لأي جلسة تقييم متعددة الأقسام.
/// ─────────────────────────────────────────────────────────────────────
class ExamResultScreen extends StatelessWidget {
  const ExamResultScreen({
    required this.totalPercent,
    required this.passed,
    required this.recommendation,
    required this.sections,
    this.sessionTitle,
    this.xpEarned,
    this.onExit,
    super.key,
  });

  /// النسبة الكلية (0-100).
  final int totalPercent;

  /// هل اجتاز (≥60)؟
  final bool passed;

  final String recommendation;

  /// (اسم القسم، نسبته 0-100).
  final List<(String, int)> sections;

  /// عنوان الجلسة المعروض تحت النتيجة.
  final String? sessionTitle;

  /// XP مكتسب من أقسام الجلسة (يعرض في رقاقة ⚡ إن > 0).
  final int? xpEarned;

  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color ringColor =
        passed ? AppColors.success(b) : AppColors.error(b);

    if (totalPercent >= 90 && !MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted &&
            !CelebrationQueue.instance.hasBigEventsPending) {
          ConfettiBurst.show(context);
        }
      });
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                passed ? 'مبارك! 🎓' : 'لم تكتمل بعد',
                style:
                    AppType.screenTitle.copyWith(color: AppColors.text(b)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                sessionTitle ?? 'جلسة تقييم',
                style: AppType.body
                    .copyWith(color: AppColors.textSecondary(b)),
              ),
              const SizedBox(height: AppSpacing.xxl),

              ProgressRing(
                progress: totalPercent / 100,
                size: 170,
                stroke: 12,
                color: ringColor,
                child: _CountUp(
                  value: totalPercent,
                  suffix: '%',
                  style: AppType.screenTitle.copyWith(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: ringColor,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // ── أشرطة الأقسام ──
              AppCard(
                child: Column(
                  children: <Widget>[
                    for (final (String, int) s in sections) ...<Widget>[
                      _SectionBar(label: s.$1, percent: s.$2),
                      if (s != sections.last)
                        const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── رقاقة XP (أقسام الجلسة تمنح فوراً) ──
              if (xpEarned != null && xpEarned! > 0) ...<Widget>[
                _XpChip(xp: xpEarned!),
                const SizedBox(height: AppSpacing.lg),
              ],

              // ── التوصية ──
              Text(
                recommendation,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(
                  color: AppColors.textSecondary(b),
                  height: 1.6,
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              AppButton(
                label: 'العودة',
                icon: Icons.arrow_forward_rounded,
                type: AppButtonType.ghost,
                onPressed: onExit ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.label, required this.percent});

  final String label;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style:
                    AppType.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '$percent%',
              textDirection: TextDirection.ltr,
              style: AppType.caption.copyWith(
                fontWeight: FontWeight.w800,
                color: percent >= 60
                    ? AppColors.success(b)
                    : AppColors.error(b),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ProgressBar(
          progress: percent / 100,
          height: 7,
          color: percent >= 60
              ? AppColors.success(b)
              : AppColors.error(b),
        ),
      ],
    );
  }
}
