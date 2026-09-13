import 'package:flutter/material.dart';

import '../../core/utils/app_haptics.dart';
import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// زر خيار MCQ الموحد لكل تمارين التطبيق.
///
/// ثلاث حالات بعد الإجابة: صحيح (أخضر) · خاطئ مختار (أحمر) · باهت.
/// حركة موحدة: نبضة خضراء عند الظهور الصحيح (ScaleIn من feedback_banner).
/// ─────────────────────────────────────────────────────────────────────
enum OptionState { correct, wrong, dimmed }

class ExerciseOptionButton extends StatelessWidget {
  const ExerciseOptionButton({
    required this.label,
    required this.onTap,
    this.state,
    this.latin = false,
    this.minHeight = 52,
    super.key,
  });

  final String label;

  /// null = قبل الإجابة (عادي).
  final VoidCallback? onTap;
  final OptionState? state;

  /// نص لاتيني (مصطلح طبي إنجليزي)؟ (يفرض LTR + Nunito).
  final bool latin;

  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    // الألوان حسب الحالة.
    Color background = AppColors.surfaceAlt(b);
    Color foreground = AppColors.text(b);
    BorderSide side = BorderSide(color: AppColors.border(b));
    FontWeight weight = FontWeight.w600;

    switch (state) {
      case OptionState.correct:
        background = AppColors.successContainer(b);
        foreground = AppColors.success(b);
        side = BorderSide(color: AppColors.success(b), width: 2);
        weight = FontWeight.w800;
      case OptionState.wrong:
        background = AppColors.errorContainer(b);
        foreground = AppColors.error(b);
        side = BorderSide(color: AppColors.error(b), width: 2);
        weight = FontWeight.w700;
      case OptionState.dimmed:
        background = AppColors.surface(b);
        foreground = AppColors.textSecondary(b).withValues(alpha: 0.55);
        side = BorderSide(
            color: AppColors.border(b).withValues(alpha: 0.5));
      case null:
        break;
    }

    final Widget inner = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.fromBorderSide(side),
      ),
      child: Row(
        children: <Widget>[
          if (state != null) ...<Widget>[
            Icon(
              state == OptionState.correct
                  ? Icons.check_circle_rounded
                  : state == OptionState.wrong
                      ? Icons.cancel_rounded
                      : Icons.radio_button_unchecked_rounded,
              size: 22,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Text(
              label,
              textDirection: latin ? TextDirection.ltr : null,
              textAlign: latin ? TextAlign.start : null,
              style: TextStyle(
                fontFamily: latin ? AppType.latinFamily : null,
                fontSize: 16.5,
                fontWeight: weight,
                color: foreground,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AppHaptics.selection();
                  onTap!();
                },
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: inner,
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// زر الاستماع الكبير الموحد — دائرة 120-140 مع haptic عند الضغط.
/// ─────────────────────────────────────────────────────────────────────
class BigListenButton extends StatelessWidget {
  const BigListenButton({
    required this.onTap,
    this.size = 120,
    this.iconSize = 56,
    this.secondary,
    this.label,
    super.key,
  });

  final VoidCallback onTap;
  final double size;
  final double iconSize;

  /// زر ثانوي تحت الكبير (مثل «أعد ببطء») — اختياري.
  final Widget? secondary;

  /// تسمية أسفل الزر.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = AppColors.primary(b);

    final Widget circle = Semantics(
      button: true,
      label: label ?? 'استمع',
      child: Material(
        color: AppColors.primaryTint(b),
        shape: CircleBorder(
          side: BorderSide(color: primary, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            AppHaptics.selection();
            onTap();
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.volume_up_rounded,
                size: iconSize, color: primary),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RepaintBoundary(child: circle),
        if (label != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            label!,
            style: AppType.caption.copyWith(
                color: AppColors.textSecondary(b)),
          ),
        ],
        if (secondary != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          secondary!,
        ],
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// حقل الإجابة الكتابي الموحد — LTR + Nunito + زر فحص مدمج.
///
/// يعالج الكيبورد: [keyboardHandler] يُستدعى عند فتح الكيبورد لتمرير
/// الشاشة للحقل (Scrollable.ensureVisible).
/// ─────────────────────────────────────────────────────────────────────
class ExerciseTextField extends StatelessWidget {
  const ExerciseTextField({
    required this.controller,
    required this.onSubmitted,
    this.hint = 'اكتب إجابتك هنا...',
    this.maxLength = 80,
    this.maxLines = 1,
    this.enabled = true,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final bool enabled;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        maxLines: maxLines,
        maxLength: maxLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (String _) => onSubmitted(),
        style: TextStyle(
          fontFamily: AppType.latinFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text(b),
        ),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          filled: true,
          fillColor: AppColors.surface(b),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
            borderSide: BorderSide(color: AppColors.border(b)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
            borderSide: BorderSide(color: AppColors.border(b)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
            borderSide: BorderSide(
                color: AppColors.primary(b), width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
            borderSide: BorderSide(
                color: AppColors.border(b).withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }
}
