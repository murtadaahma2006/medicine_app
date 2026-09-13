import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// البطاقة الموحدة — سطح بحد 1px وظل ناعم جداً (هوية «حدود لا ظلال»).
///
/// اختياري: شريط جانبي بلون (عادة لون التخصص) — الحد الأيسر
/// في RTL (نهاية القراءة).
/// ─────────────────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.accent,
    this.accentWidth = 4,
    this.padding = AppSpacing.card,
    this.margin,
    this.color,
    this.onTap,
    this.radius = AppRadius.card,
    super.key,
  });

  /// محتوى البطاقة.
  final Widget child;

  /// لون الشريط الجانبي (لون التخصص عادة) — null = بلا شريط.
  final Color? accent;

  /// سماكة الشريط الجانبي.
  final double accentWidth;

  /// الحشو الداخلي — 16 افتراضياً.
  final EdgeInsetsGeometry padding;

  /// هامش خارجي — 0 افتراضياً (يديره الأب عبر AppSpacing.betweenCards).
  final EdgeInsetsGeometry? margin;

  /// لون السطح — سطح الثيم افتراضياً.
  final Color? color;

  /// نقرة على البطاقة كلها (بطاقة نشاط قابل للنقر مثلاً).
  final VoidCallback? onTap;

  /// نصف القطر — 16 افتراضياً.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;
    final Color surface = color ?? theme.colorScheme.surface;
    final Color border = theme.colorScheme.outline;

    final Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: AppMotion.ease,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: AppShadows.card(b),
        // الحد الداخلي المضيء — داكن فقط: السطح «يُضاء من الأعلى».
        gradient: null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: AppShadows.innerGlow(b),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: accent == null
            ? Padding(padding: padding, child: child)
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(width: accentWidth, color: accent),
                    Expanded(
                      child: Padding(padding: padding, child: child),
                    ),
                  ],
                ),
              ),
      ),
    );

    final Widget result = margin == null ? card : Padding(padding: margin!, child: card);

    if (onTap == null) return result;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: result,
        ),
      ),
    );
  }
}
