import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// حلقة تقدم متحركة — تمتلئ بسلاسة عند البناء (TweenAnimationBuilder)
/// من 0 إلى [progress]. تُستخدم في الهدف اليومي وشاشة النتيجة.
/// ─────────────────────────────────────────────────────────────────────
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.progress,
    required this.child,
    this.size = 120,
    this.stroke = 10,
    this.color,
    this.trackColor,
    this.showKnob = true,
    super.key,
  });

  /// 0.0 → 1.0.
  final double progress;

  /// محتوى وسط الحلقة.
  final Widget child;

  final double size;
  final double stroke;
  final Color? color;
  final Color? trackColor;

  /// نقطة صغيرة في نهاية القوس — لمسة حيّة.
  final bool showKnob;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color ringColor = color ?? theme.colorScheme.primary;
    final Color track = trackColor ?? theme.colorScheme.surfaceContainer;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: AppMotion.scaled(context, AppMotion.celebration),
      curve: AppMotion.ease,
      builder: (BuildContext context, double value, Widget? child) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _RingPainter(
                    progress: value,
                    color: ringColor,
                    trackColor: track,
                    stroke: stroke,
                    knob: showKnob,
                  ),
                ),
              ),
              child ?? const SizedBox.shrink(),
            ],
          ),
        );
      },
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.stroke,
    required this.knob,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double stroke;
  final bool knob;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double radius = math.min(size.width, size.height) / 2;
    final Offset center = rect.center;
    final double r = radius - stroke / 2;

    // المسار الخلفي.
    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, r, track);

    if (progress <= 0) return;

    // القوس.
    final Paint arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final double sweep = 2 * math.pi * progress;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        -math.pi / 2, sweep, false, arc);

    // عقدة النهاية.
    if (knob && progress < 1) {
      final Paint dot = Paint()..color = color;
      final Offset knobPos = Offset(
        center.dx + r * math.cos(-math.pi / 2 + sweep),
        center.dy + r * math.sin(-math.pi / 2 + sweep),
      );
      canvas.drawCircle(knobPos, stroke * 0.36, dot);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// ─────────────────────────────────────────────────────────────────────
/// شريط تقدم أفقي متحرك — يمتلئ بسلاسة، لا قفزاً.
/// ─────────────────────────────────────────────────────────────────────
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    required this.progress,
    this.height = 8,
    this.color,
    this.trackColor,
    this.radius,
    super.key,
  });

  /// 0.0 → 1.0.
  final double progress;

  final double height;
  final Color? color;
  final Color? trackColor;

  /// نصف قطر — pill افتراضياً.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color c = color ?? theme.colorScheme.primary;
    final Color track = trackColor ?? theme.colorScheme.surfaceContainer;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? height / 2),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
          duration: AppMotion.scaled(context, AppMotion.transition),
          curve: AppMotion.ease,
          builder: (BuildContext context, double value, Widget? bar) {
            return Stack(
              children: <Widget>[
                Container(
                  height: height,
                  color: track,
                ),
                FractionallySizedBox(
                  widthFactor: value <= 0 ? 0.0001 : value,
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius:
                          BorderRadius.circular(radius ?? height / 2),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// شريط تقدم مجزأ — لجلسات التمارين: مقطع لكل سؤال، يمتلئ المقاطع
/// المنجزة والمقطع الجاري يمتلئ جزئياً (تأكيد فوري للعلم الحسن).
/// ─────────────────────────────────────────────────────────────────────
class SegmentedProgressBar extends StatelessWidget {
  const SegmentedProgressBar({
    required this.current,
    required this.total,
    this.partial = 0,
    this.height = 6,
    super.key,
  });

  /// عدد الأسئلة المنجزة (مقاطع ممتلئة).
  final int current;

  /// العدد الكلي.
  final int total;

  /// تقدم جزئي داخل المقطع الجاري (0→1) — اختياري.
  final double partial;

  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color done = theme.colorScheme.primary;
    final Color active = theme.colorScheme.primary;
    final Color track = theme.colorScheme.surfaceContainer;

    return Semantics(
      label: 'التقدم: $current من $total',
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < total; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: AppMotion.ease,
                    height: height,
                    decoration: BoxDecoration(
                      color: i < current
                          ? done
                          : i == current
                              ? active.withValues(alpha: 0.55)
                              : track,
                      borderRadius: BorderRadius.circular(height),
                    ),
                    // المقطع الجاري: تعبئة جزئية داخلية.
                    child: i == current && partial > 0
                        ? FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: partial.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: active,
                                borderRadius: BorderRadius.circular(height),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
