import 'package:flutter/material.dart';

import '../../core/utils/app_haptics.dart';
import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// الزر الموحد — كل زر في التطبيق يخرج من هنا.
///
/// الأنواع: primary (كحلي ممتلئ) · secondary (تنت) · ghost (شفاف بحد)
/// · danger (أحمر) — بحالات: عادي · معطّل · تحميل.
///
/// ردود الفعل: انكماش 0.97 عند الضغط (120ms) + haptic خفيف.
/// ─────────────────────────────────────────────────────────────────────
enum AppButtonType { primary, secondary, ghost, danger }

class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.type = AppButtonType.primary,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expanded = true,
    this.minHeight = 52,
    this.fontSize,
    super.key,
  });

  /// نص الزر.
  final String label;

  /// ماذا يحدث عند الضغط (null = معطّل).
  final VoidCallback? onPressed;

  /// نوع الزر البصري.
  final AppButtonType type;

  /// أيقونة قبل النص (اختياري).
  final IconData? icon;

  /// أيقونة بعد النص — chevron مثلاً (اختياري).
  final IconData? trailingIcon;

  /// هل يعرض مؤشر تحميل مكان النص ويعطّل الضغط؟
  final bool loading;

  /// يتمدد بعرض الحاوية؟ (افتراضياً نعم).
  final bool expanded;

  /// أقل ارتفاع — 52 لضمان منطقة لمس مريحة، ≥48 إمكانية وصول.
  final double minHeight;

  /// حجم خط الزر (بعض المواضع تريد أصغر).
  final double? fontSize;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  void _handleTap() {
    AppHaptics.light();
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool disabled = widget.onPressed == null || widget.loading;

    // ── ألوان النوع ──
    final Color bg;
    final Color fg;
    final Color border;
    switch (widget.type) {
      case AppButtonType.primary:
        bg = scheme.primary;
        fg = scheme.onPrimary;
        border = scheme.primary;
      case AppButtonType.secondary:
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
        border = scheme.primaryContainer;
      case AppButtonType.ghost:
        bg = Colors.transparent;
        fg = scheme.primary;
        border = scheme.outline;
      case AppButtonType.danger:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        border = scheme.errorContainer;
    }

    // اللون الفعلي — يبهت عند التعطيل.
    final Color effBg = disabled ? bg.withValues(alpha: 0.45) : bg;
    final Color effFg = disabled ? fg.withValues(alpha: 0.6) : fg;
    final Color effBorder = disabled ? border.withValues(alpha: 0.3) : border;

    // الحركة: انكماش 0.97 عند الضغط — 120ms رد فعل، ويُحترم تعطيل
    // حركات النظام.
    final bool animationsOn =
        !MediaQuery.disableAnimationsOf(context) && !disabled;
    final Duration press = AppMotion.scaled(context, AppMotion.feedback);

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(effFg),
            ),
          )
        else ...<Widget>[
          if (widget.icon != null) ...<Widget>[
            Icon(widget.icon, size: 20, color: effFg),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppType.arabicFamily,
                fontSize: widget.fontSize ?? 16,
                fontWeight: FontWeight.w700,
                color: effFg,
              ),
            ),
          ),
          if (widget.trailingIcon != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Icon(widget.trailingIcon, size: 18, color: effFg),
          ],
        ],
      ],
    );

    final Widget button = GestureDetector(
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapUp: disabled ? null : (_) => _setPressed(false),
      onTapCancel: disabled ? null : () => _setPressed(false),
      onTap: disabled ? null : _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed && animationsOn ? 0.97 : 1.0,
        duration: press,
        curve: AppMotion.ease,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: AppMotion.ease,
          constraints: BoxConstraints(minHeight: widget.minHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          decoration: BoxDecoration(
            color: effBg,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(
              color: effBorder,
              width: widget.type == AppButtonType.ghost ? 1.2 : 1,
            ),
          ),
          child: Center(child: content),
        ),
      ),
    );

    // سيمانتكس: زر باسم واضح حتى لو كان محتواه أيقونات.
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.loading ? 'جارٍ التحميل' : widget.label,
      child: widget.expanded
          ? SizedBox(width: double.infinity, child: button)
          : button,
    );
  }
}
