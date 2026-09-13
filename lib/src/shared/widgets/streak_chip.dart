import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// شريحة السلسلة اليومية 🔥 — موضعها «اليوم» (المرحلة 6).
///
/// النبض: حلقة scale خفيفة (1→1.06 خلال 2.4s تتكرر) — خافتة لا تصرخ.
/// لا تنبض الشريحة إن كانت السلسلة صفراً (لا شيء يحتفل به) وتتوقف
/// تلقائياً خارج الشاشة (IndexedStack يوقف tickers اللسان المخفي في
/// نسخة Flutter الحالية — Visibility.maintain + TickerMode).
///
/// تحترم إيقاف حركات النظام (MediaQuery.disableAnimations).
/// ─────────────────────────────────────────────────────────────────────
class StreakChip extends StatefulWidget {
  const StreakChip({required this.streak, super.key});

  /// عدد أيام السلسلة الحالية.
  final int streak;

  @override
  State<StreakChip> createState() => _StreakChipState();
}

class _StreakChipState extends State<StreakChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void didUpdateWidget(StreakChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (تعطيل الحركات) لا يُقرأ في initState.
    _syncPulse();
  }

  void _syncPulse() {
    final bool shouldPulse =
        widget.streak > 0 && !MediaQuery.disableAnimationsOf(context);
    if (shouldPulse && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
    } else if (!shouldPulse && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    // لون اللهب يتدرج مع طول السلسلة — كهرماني ينضج نحو الذهبي
    // عند المعالم (7 أيام ذهبي، 30 يوم ذهبي مشع).
    final Color fire = AppFlame.forStreak(widget.streak, b);
    final bool active = widget.streak > 0;

    final Widget chip = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color:
            active ? fire.withValues(alpha: 0.14) : AppColors.surfaceAlt(b),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
            color:
                active ? fire.withValues(alpha: 0.45) : AppColors.border(b)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('🔥', style: TextStyle(fontSize: 16)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${widget.streak}',
            textDirection: TextDirection.ltr,
            style: AppType.caption.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: active ? fire : AppColors.textSecondary(b),
            ),
          ),
        ],
      ),
    );

    if (_pulse == null) return chip;

    return RepaintBoundary(
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 1.06)
            .animate(CurvedAnimation(parent: _pulse!, curve: AppMotion.ease)),
        child: chip,
      ),
    );
  }
}
