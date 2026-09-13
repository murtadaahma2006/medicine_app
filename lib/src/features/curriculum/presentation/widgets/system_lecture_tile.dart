import 'package:flutter/material.dart';

import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../domain/unit.dart';
import 'system_expansion_tile.dart';

/// ─────────────────────────────────────────────────────────────────────
/// بطاقة المحاضرة داخل مسار التعلم (تحت ترويسة جهازها).
///
/// في الوضع العادي: بطاقة قابلة للنقر تفتح شاشة الوحدة + عقدة إكمال
/// + **زر تثبيت 📌** يضيف المحاضرة إلى «أهدافي لهذا اليوم».
/// في وضع «ترتيب يدوي»: مقبض سحب + زر «نقل» + زر حذف.
/// ─────────────────────────────────────────────────────────────────────
class SystemLectureTile extends StatelessWidget {
  const SystemLectureTile({
    required this.unit,
    required this.completed,
    required this.reorderMode,
    required this.index,
    required this.onOpen,
    required this.onMove,
    required this.onDelete,
    this.pinned = false,
    this.onTogglePin,
    super.key,
  });

  /// المحاضرة (الوحدة).
  final Unit unit;

  /// هل اكتمل تقييمها (assess-)؟
  final bool completed;

  /// وضع الترتيب اليدوي مفعّل؟
  final bool reorderMode;

  /// فهرس الصف داخل ReorderableListView — لمقبض السحب.
  final int index;

  final VoidCallback onOpen;

  /// فتح شيت «نقل إلى نظام آخر».
  final VoidCallback onMove;

  /// طلب حذف المحاضرة — يعرض التأكيد قبل التنفيذ.
  final VoidCallback onDelete;

  /// مثبتة لأهداف اليوم؟
  final bool pinned;

  /// تثبيت/فك تثبيت — null = إخفاء الزر (شاشات عرض فقط).
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color color =
        AppColors.module(SystemNames.moduleOf(unit.system), b);
    final String title = _cleanTitle(unit.title);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        accent: color,
        accentWidth: 4,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        onTap: reorderMode ? null : onOpen,
        child: Row(
          children: <Widget>[
            // ── علامة الإكمال أو الترقيم ──
            if (reorderMode)
            // مقبض السحب — يبدأ drag & drop فور لمسه.
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 22,
                    color: AppColors.textSecondary(b),
                    semanticLabel: 'اسحب لإعادة الترتيب',
                  ),
                ),
              )
            else
              _CompletedDot(completed: completed, color: color),

            const SizedBox(width: AppSpacing.md),

            // ── العنوان + الجهاز ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text(b),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${SystemNames.ar(unit.system)} · '
                    '${AppColors.moduleNameAr(unit.module)}',
                    style: AppType.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                ],
              ),
            ),

            // ── زر التثبيت 📌 — دائماً متاح في الوضع العادي ──
            if (!reorderMode && onTogglePin != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: _PinIconButton(
                  pinned: pinned,
                  onTap: onTogglePin!,
                ),
              ),

            // ── زرا النقل والحذف (وضع الترتيب) أو chevron ──
            if (reorderMode) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: _MoveIconButton(onTap: onMove),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: _DeleteIconButton(onTap: onDelete),
              ),
            ]
            else
              Icon(
                Icons.chevron_left_rounded,
                color: AppColors.textSecondary(b)
                    .withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }

  static String _cleanTitle(String raw) {
    String t = raw;
    if (t.startsWith('[') && t.contains(']')) {
      t = t.substring(1, t.indexOf(']'));
    }
    return t.trim();
  }
}

/// عقدة الإكمال — دائرة صغيرة ✓ إن اكتمل التقييم.
class _CompletedDot extends StatelessWidget {
  const _CompletedDot({
    required this.completed,
    required this.color,
  });

  final bool completed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!completed) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: color.withValues(alpha: 0.55),
            width: 2.2,
          ),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: const Icon(Icons.check_rounded,
          size: 14, color: Colors.white),
    );
  }
}

/// زر النقل (أيقونة) — يفتح شيت اختيار الجهاز الهدف.
class _MoveIconButton extends StatelessWidget {
  const _MoveIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'نقل إلى نظام آخر',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.drive_file_move_rounded,
            size: 20,
            color: Color(0xFF5B6879),
          ),
        ),
      ),
    );
  }
}

/// زر التثبيت 📌 — يضيف/يزيل المحاضرة من «أهدافي لهذا اليوم».
///
/// المثبتة: دبوس مملوء ذهبي (لون الهدف اليومي) + عند فك التثبيت
/// تتلاشى رقيقة. غير المثبتة: دبوس خارجي هادئ لا يزاحم العنوان.
class _PinIconButton extends StatelessWidget {
  const _PinIconButton({
    required this.pinned,
    required this.onTap,
  });

  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color active = AppColors.gold(b);

    return Semantics(
      button: true,
      label: pinned ? 'إزالة من أهداف اليوم' : 'تثبيت في أهداف اليوم',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedSwitcher(
            duration: AppMotion.scaled(context, AppMotion.feedback),
            switchInCurve: AppMotion.ease,
            switchOutCurve: AppMotion.out,
            transitionBuilder: (Widget child, Animation<double> anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              key: ValueKey<bool>(pinned),
              pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 20,
              color: pinned
                  ? active
                  : AppColors.textSecondary(b)
                      .withValues(alpha: 0.55),
              semanticLabel:
                  pinned ? 'مثبتة لأهداف اليوم' : 'تثبيت لأهداف اليوم',
            ),
          ),
        ),
      ),
    );
  }
}

/// زر الحذف (أيقونة) — يعرض حوار التأكيد قبل أي حذف.
class _DeleteIconButton extends StatelessWidget {
  const _DeleteIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color error = Theme.of(context).colorScheme.error;

    return Semantics(
      button: true,
      label: 'حذف المحاضرة',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 20,
            color: error,
            semanticLabel: 'حذف المحاضرة',
          ),
        ),
      ),
    );
  }
}
