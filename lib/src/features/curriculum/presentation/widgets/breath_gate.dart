import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// بوابة التنفس (Launch Ritual — 8 ثوان فقط: 4 شهيق + 2 ثبات + 2 زفير).
///
/// الانتباه المتبقي (Attention Residue — Leroy 2009): عند الانتقال من
/// مهمة لأخرى يبقى جزء من الانتباه عالقاً في السابقة. الطقس القصير
/// الموحد يمسح الـ Residue ويضع الـ Arousal في المنطقة المثالية.
///
/// الاحتكاك الإيجابي: زر البدء لا يتفعّل إلا بعد اكتمال الدورة —
/// تبطئ الدخول كي لا «يهجم» الدماغ على الجلسة وهو في وضع الهرولة.
/// ─────────────────────────────────────────────────────────────────────
class BreathGatePage extends StatefulWidget {
  const BreathGatePage({
    required this.sessionTitle,
    required this.onReady,
    super.key,
  });

  /// عنوان الجلسة القادمة (يظهر أثناء التنفس).
  final String sessionTitle;

  /// يُستدعى عند اكتمال الدورة — المستدعي يفتح الجلسة الفعلية.
  /// إن كانت null يُستعمل Navigator.pop(true) بدلاً منها.
  final VoidCallback? onReady;

  /// يفتح البوابة ثم [onReady] عند الجاهزية. يرجع true إن أكمل التنفس.
  static Future<bool> show(
    BuildContext context, {
    required String sessionTitle,
    VoidCallback? onReady,
  }) async {
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BreathGatePage(
          sessionTitle: sessionTitle,
          onReady: onReady,
        ),
      ),
    );
    return done ?? false;
  }

  @override
  State<BreathGatePage> createState() => _BreathGatePageState();
}

class _BreathGatePageState extends State<BreathGatePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8), // 4+2+2
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _phaseLabel {
    final double t = _c.value;
    if (t < 0.5) return 'شهيق';
    if (t < 0.75) return 'اثبت';
    return 'زفير';
  }

  void _start() {
    if (widget.onReady != null) {
      Navigator.of(context).pop();
      widget.onReady!();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background(b),
      body: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, _) {
          final double t = _c.value;
          // منحنى الحجم: 0→1 شهيق (أول 50%) · ثبات · 1→0 زفير (آخر 25%).
          final double scale = t < 0.5
              ? Curves.easeInOut.transform(t / 0.5)
              : t < 0.75
                  ? 1.0
                  : 1.0 - Curves.easeInOut.transform((t - 0.75) / 0.25);
          final bool done = _c.isCompleted;

          return SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl),
                    child: Text(
                      widget.sessionTitle,
                      textAlign: TextAlign.center,
                      style: AppType.cardTitle.copyWith(
                        fontSize: 18,
                        color: AppColors.text(b),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  // ── مربع التنفس ──
                  Transform.scale(
                    scale: 0.55 + 0.45 * scale,
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.10 + 0.22 * scale),
                        border: Border.all(width: 2, color: primary),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: AppMotion.scaled(
                              context, AppMotion.transition),
                          child: Text(
                            _phaseLabel,
                            key: ValueKey<String>(_phaseLabel),
                            style: AppType.cardTitle.copyWith(
                              fontSize: 22,
                              color: primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  // ── زر البدء — لا يتفعل إلا بعد اكتمال النفس ──
                  AnimatedOpacity(
                    duration: AppMotion.scaled(
                        context, AppMotion.transition),
                    opacity: done ? 1 : 0.25,
                    child: FilledButton(
                      onPressed: done ? _start : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxxl,
                          vertical: AppSpacing.md + 2,
                        ),
                      ),
                      child: Text(
                        'ابدأ الجلسة',
                        style: AppType.body.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    done ? 'أنت جاهز — انطلق' : 'تنفّس مع المربع…',
                    style: AppType.caption.copyWith(
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: TextButton(
                onPressed: _start,
                child: Text(
                  'تخطي',
                  style: AppType.body.copyWith(
                    color: AppColors.textSecondary(b),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
        },
      ),
    );
  }
}
