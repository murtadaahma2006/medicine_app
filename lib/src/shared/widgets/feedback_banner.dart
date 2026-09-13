import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/app_haptics.dart';
import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// شريط التغذية الراجعة الموحد لكل تمارين التطبيق.
///
/// صحيح: أخضر بأيقونة تدخل بنابض (easeOutBack) + haptic خفيف.
/// خطأ: أحمر يهتز (3 هزّات صغيرة) + إظهار الصواب إن وُجد.
///
/// يُدمج داخل ExerciseScaffold أسفل الزر الرئيسي (المرحلة 4) أو
/// يُستخدم standalone في الشاشات المرحّلة لاحقاً.
/// ─────────────────────────────────────────────────────────────────────
class FeedbackBanner extends StatefulWidget {
  const FeedbackBanner({
    required this.correct,
    required this.message,
    this.correctAnswer,
    this.explanation,
    super.key,
  });

  /// هل الإجابة صحيحة؟
  final bool correct;

  /// الرسالة الرئيسية («أحسنت!» / «ليست صحيحة»).
  final String message;

  /// الجواب الصحيح (يعرض بخط ألماني LTR) عند الخطأ — اختياري.
  final String? correctAnswer;

  /// شرح تعليمي إضافي — اختياري.
  final String? explanation;

  @override
  State<FeedbackBanner> createState() => _FeedbackBannerState();
}

class _FeedbackBannerState extends State<FeedbackBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake;
  late final Animation<double> _shakeAnim;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // اهتزاز أفقي: 3 هزّات متخافتة (sin بتردد 3).
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shake, curve: Curves.linear),
    );
  }

  // MediaQuery لا يُقرأ في initState — didChangeDependencies هو موضعه.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.correct) {
      AppHaptics.light();
    } else {
      AppHaptics.error();
      if (!MediaQuery.disableAnimationsOf(context)) {
        _shake.forward();
      }
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color okColor = AppColors.success(b);
    final Color errColor = AppColors.error(b);
    final Color color = widget.correct ? okColor : errColor;
    final Color container =
        widget.correct ? AppColors.successContainer(b) : AppColors.errorContainer(b);

    final bool animOn = !MediaQuery.disableAnimationsOf(context);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shakeAnim,
        builder: (BuildContext context, Widget? child) {
          // إزاحة الاهتزاز: sin(3·2π·t)·8·(1-t) — تبدأ قوية وتخفت.
          final double t = _shakeAnim.value;
          final double dx = widget.correct || !animOn
              ? 0
              : 8 * math.sin(3 * 2 * math.pi * t) * (1 - t);
          return Transform.translate(
            offset: Offset(dx, 0),
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: animOn ? AppMotion.standard : Duration.zero,
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: container,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // أيقونة تدخل بنابض (صحيح) أو ثابتة (خطأ).
                  animOn
                      ? ScaleIn(
                          duration: AppMotion.celebration,
                          curve: AppMotion.popIn,
                          child: _icon(color),
                        )
                      : _icon(color),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: AppType.cardTitle.copyWith(
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.correctAnswer != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _CorrectAnswer(text: widget.correctAnswer!),
              ],
              if (widget.explanation != null &&
                  widget.explanation!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.explanation!,
                  style: AppType.body.copyWith(
                    color: AppColors.textSecondary(b),
                    height: 1.5,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon(Color color) {
    // علامة صح ترسم ذاتها عند الإجابة الصحيحة — «شطب حي».
    if (widget.correct) {
      return Semantics(
        label: 'إجابة صحيحة',
        child: SelfDrawingCheck(size: 26, color: color),
      );
    }
    return Icon(Icons.close_rounded,
        color: color, size: 26, semanticLabel: 'إجابة خاطئة');
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// علامة صح تُرسم ذاتياً — الخط يُرسم من نقطة البداية خلال 180ms
/// (حس «الشطب الحي» كأن يدك هي التي رسمته) ثم نبضة صغيرة.
/// ─────────────────────────────────────────────────────────────────────
class SelfDrawingCheck extends StatefulWidget {
  const SelfDrawingCheck({
    this.size = 26,
    this.color = const Color(0xFF1E8E4E),
    super.key,
  });

  final double size;
  final Color color;

  @override
  State<SelfDrawingCheck> createState() => _SelfDrawingCheckState();
}

class _SelfDrawingCheckState extends State<SelfDrawingCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..forward();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Icon(Icons.check_rounded,
          size: widget.size, color: widget.color);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _draw,
        builder: (BuildContext context, Widget? child) {
          final double t = _draw.value;
          // نبضة صغيرة في النهاية — الحياة بعد الرسم.
          final double scale =
              t >= 1 ? 1 : 0.9 + 0.1 * AppMotion.popIn.transform(t);
          return Transform.scale(
            scale: scale,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _CheckPainter(progress: t, color: widget.color),
            ),
          );
        },
      ),
    );
  }
}

/// رسّام علامة الصح — قوسان يرسمان بالتتابع (قصيرة ثم طويلة).
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // نقطتا المسار — علامة صح كلاسيكية داخل المربع.
    final Offset p1 = Offset(size.width * 0.22, size.height * 0.52);
    final Offset p2 = Offset(size.width * 0.44, size.height * 0.74);
    final Offset p3 = Offset(size.width * 0.80, size.height * 0.26);

    // القوس الأول (30% من الزمن) ثم الثاني (70%).
    if (progress <= 0.3) {
      final double t = progress / 0.3;
      canvas.drawLine(
          p1, Offset.lerp(p1, p2, t)!, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
      final double t = (progress - 0.3) / 0.7;
      canvas.drawLine(p2, Offset.lerp(p2, p3, t)!, paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// رقاقة «+N ⚡» صغيرة تنبثق من مكان الإجابة الصحيحة — توضع فوق زر
/// الخيار الصحيح؛ ترتفع 24px وتتلاشى خلال 600ms (نسخة مصغرة محلية
/// من XP الطائر العام — لدفع فوري قبل رقاقة الطابور).
///
/// ── ظهور بنابض — يلف ScaleTransition بمنحنى easeOutBack. ──
class ScaleIn extends StatelessWidget {
  const ScaleIn({
    required this.child,
    this.duration = AppMotion.standard,
    this.curve = AppMotion.popIn,
    super.key,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.4, end: 1),
      duration: duration,
      curve: curve,
      builder: (BuildContext context, double v, Widget? c) =>
          Transform.scale(scale: v, child: c),
      child: child,
    );
  }
}

/// سطر الجواب الصحيح — داخل رقاقة خضراء فاتحة.
class _CorrectAnswer extends StatelessWidget {
  const _CorrectAnswer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color okColor = AppColors.success(b);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: okColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.lightbulb_rounded,
              size: 18, color: okColor, semanticLabel: 'الجواب الصحيح'),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              style: AppType.termWord.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text(b),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
