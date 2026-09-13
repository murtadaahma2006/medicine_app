import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// الكونفيتي الموحد — المشهد الوحيد في كل التطبيق (المرحلة 4/6).
///
/// CustomPainter خفيف بنفسنا: ~120 جزيئاً بألوان الهوية (كحلي/ذهبي/
/// أحمر تعليمي/أخضر نجاح)، 2 ثانية، تسقط بدوران ومواث — بلا أي حزمة.
///
/// الاستخدام: ConfettiBurst.show(context) — يدير OverlayEntry داخلياً
/// ويُزيله تلقائياً. لا يظهر احتفالان فوق بعضهما أبداً (حراسة static).
/// ─────────────────────────────────────────────────────────────────────
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  /// مشهد واحد فقط في كل لحظة (حراسة static — لا احتفالان فوق بعضهما).
  static bool _showing = false;

  /// يطلق كونفيتي فوق كل الشاشة من أي سياق.
  static void show(BuildContext context) {
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    if (_showing) return; // جولة جارية — نتجاهل الطلب الثاني.
    _showing = true;

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext ctx) => const _ConfettiOverlay(),
    );
    overlay.insert(entry);

    // إزالة تلقائية بعد اكتمال المدة + هامش.
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      _showing = false;
      try {
        entry.remove();
      } catch (_) {
        // الـOverlay أُتلف قبل المهلة (مثلاً بإغلاق التطبيق) — آمن.
      }
    });
  }

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    // 120 جزيئاً بألوان الهوية — ذهبي أكثرها (هوية الإنجاز).
    final math.Random rng = math.Random();
    final List<Color> palette = <Color>[
      AppColors.goldLight,
      AppColors.goldLight,
      AppColors.primaryLight,
      AppColors.successLight,
      AppColors.signatureRed,
    ];
    _particles = List<_Particle>.generate(120, (int i) {
      return _Particle(
        x: rng.nextDouble(),
        y: -0.05 - rng.nextDouble() * 0.25,
        speedY: 0.55 + rng.nextDouble() * 0.5,
        driftX: (rng.nextDouble() - 0.5) * 0.5,
        size: 4 + rng.nextDouble() * 5,
        rotation: rng.nextDouble() * 2 * math.pi,
        rotationSpeed: (rng.nextDouble() - 0.5) * 10,
        color: palette[i % palette.length],
        isCircle: rng.nextBool(),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? _) {
            return CustomPaint(
              size: Size.infinite,
              painter: _ConfettiPainter(
                progress: _controller.value,
                particles: _particles,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// الجزيئات منفصلة عن الحركة — OverlayEntry يستضيف [ConfettiBurst].
class _ConfettiOverlay extends StatelessWidget {
  const _ConfettiOverlay();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(child: ConfettiBurst());
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.speedY,
    required this.driftX,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    required this.color,
    required this.isCircle,
  });

  final double x;
  final double y;
  final double speedY;
  final double driftX;
  final double size;
  final double rotation;
  final double rotationSpeed;
  final Color color;
  final bool isCircle;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.particles});

  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;

    for (final _Particle p in particles) {
      // التخافت: كامل ثم يتلاشى آخر 30%.
      final double fade = progress > 0.7 ? 1 - (progress - 0.7) / 0.3 : 1.0;
      final Color color =
          p.color.withValues(alpha: (fade * 0.9).clamp(0.0, 1.0));

      final double t = progress;
      final double px = (p.x + p.driftX * t * t) * size.width;
      // سقوط متسارع + مويث خافت.
      final double py = (p.y + p.speedY * t + 0.15 * math.sin(t * 12 + p.rotation)) *
          size.height;
      if (py > size.height + 20) continue;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation + p.rotationSpeed * t);

      final Paint paint = Paint()..color = color;
      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.55,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.particles != particles;
}
