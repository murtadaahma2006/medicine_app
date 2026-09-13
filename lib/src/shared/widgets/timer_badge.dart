import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// شارة مؤقت حية — لجلسة الامتحان. تصفرّ آخر دقيقة (أحمر + نبض).
///
/// نسخة الامتحان من ExerciseScaffold (المرحلة 4) ستضعها في الرأس.
/// ─────────────────────────────────────────────────────────────────────
class TimerBadge extends StatefulWidget {
  const TimerBadge({
    required this.duration,
    this.onTimeout,
    this.autoStart = true,
    super.key,
  });

  /// مدة القسم بالكامل.
  final Duration duration;

  /// ماذا عند النفاد — عادة ينهي القسم وينتقل للتالي.
  final VoidCallback? onTimeout;

  /// يبدأ العد فور البناء (افتراضي) أو بانتظار [start()].
  final bool autoStart;

  @override
  State<TimerBadge> createState() => TimerBadgeState();
}

/// State عام — الشاشة تستطيع إيقاف/إعادة العد عبر GlobalKey إن لزم.
class TimerBadgeState extends State<TimerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  Timer? _ticker;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _progress = Tween<double>(begin: 1, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.autoStart) start();
  }

  /// يبدأ العد التنازلي (idempotent).
  void start() {
    _remaining = widget.duration;
    _scheduleTick();
  }

  /// يوقف العد مؤقتاً (تبديل أقسام).
  void pause() => _ticker?.cancel();

  /// يستأنف من حيث توقف.
  void resume() {
    if (_remaining > Duration.zero && _ticker == null) _scheduleTick();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Duration _remaining = Duration.zero;
  bool _urgent = false;

  void _scheduleTick() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _remaining = _remaining - const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _remaining = Duration.zero;
          _finished = true;
          t.cancel();
        }
      });
      // آخر دقيقة: نبض + إيقاف الحلقة.
      if (_remaining <= const Duration(minutes: 1)) {
        _urgent = true;
        _controller.repeat(reverse: true);
      } else {
        _urgent = false;
        if (_controller.isAnimating) _controller.stop();
      }
      if (_finished) widget.onTimeout?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color urgentColor = AppColors.error(b);
    final Color normalColor = AppColors.textSecondary(b);

    final String mm = (_remaining.inMinutes).toString().padLeft(2, '0');
    final String ss =
        (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    final Widget badge = AnimatedBuilder(
      animation: _progress,
      builder: (BuildContext context, Widget? child) => Transform.scale(
        scale: _urgent ? _progress.value : 1,
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs + 1),
        decoration: BoxDecoration(
          color: _urgent
              ? urgentColor.withValues(alpha: 0.12)
              : AppColors.surfaceAlt(b),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
              color: _urgent ? urgentColor : AppColors.border(b)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _urgent ? Icons.timer_rounded : Icons.schedule_rounded,
              size: 16,
              color: _urgent ? urgentColor : normalColor,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$mm:$ss',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: AppType.latinFamily,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _urgent ? urgentColor : normalColor,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures()
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      label: 'الوقت المتبقي $mm:$ss',
      liveRegion: true,
      child: RepaintBoundary(child: badge),
    );
  }
}
