import 'package:flutter/material.dart';

import '../../core/utils/responsive_layout.dart';
import '../../theme/tokens.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'app_illustration.dart';
import 'app_svg_icon.dart';

/// ─────────────────────────────────────────────────────────────────────
/// حالة فراغ موحدة — تميمة/رسالة + عنوان + وصف + زر إجراء اختياري.
///
/// الرسمة تُحل بالأولوية:
/// 1. طقم التمائم SVG الجديد (assets/icons/empty/...) — brain mascot.
/// 2. الإليستريشن القديم (assets/illustrations/empty/...).
/// 3. أيقونة مادية داخل دائرة (fallback أخير).
/// ─────────────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.illustrationId,
    this.mascot,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;

  /// معرّف الإليستريشن القديم — إن توفر يظهر محل الأيقونة.
  final String? illustrationId;

  /// معرّف تميمة الطقم الجديد (empty_review_peaceful... إلخ) —
  /// الأولوية الأعلى عند التوفر.
  final String? mascot;

  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// خريطة التمائم المتاحة — مسار كامل لكل معرف.
  static const Map<String, String> _mascotAssets = <String, String>{
    'peaceful': 'empty/empty_review_peaceful',
    'celebrating': 'empty/empty_done_celebrating',
    'puzzled': 'empty/empty_search_puzzled',
    'proud': 'empty/empty_no_mistakes',
  };

  Widget _buildVisual(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;

    // 1) تميمة الطقم الجديد.
    final String? mascotAsset =
        mascot != null ? _mascotAssets[mascot] : null;
    if (mascotAsset != null) {
      return AppSvgIcon(
        mascotAsset,
        size: 132,
        color: AppColors.text(b), // currentColor داخل SVG.
        fallback: icon,
      );
    }

    // 2) إليستريشن قديم إن حُدد ووُجد.
    if (illustrationId != null &&
        AppIllustration.hasResolvedPath(illustrationId!, b)) {
      return AppIllustration(illustrationId!, size: 120);
    }

    // 3) الأيقونة المادية داخل دائرة.
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(b),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border(b)),
      ),
      child: Icon(
        icon,
        size: 40,
        color: AppColors.textSecondary(b),
        semanticLabel: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildVisual(context),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(
                    color: AppColors.textSecondary(b),
                    height: 1.6,
                  ),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
                minHeight: 48,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// BottomSheet موحّد — بمقبض سحب ونصف قطر 20 وحد خارجي.
/// ─────────────────────────────────────────────────────────────────────
class AppSheet extends StatelessWidget {
  const AppSheet({
    required this.child,
    this.title,
    this.maxHeightFactor,
    super.key,
  });

  final Widget child;

  /// عنوان يظهر أعلى المحتوى (اختياري).
  final String? title;

  /// ارتفاع أقصى كنسبة من الشاشة (null = تلقائي).
  final double? maxHeightFactor;

  /// يفتح الشيت من أي سياق — موضع واحد لكل شيتات التطبيق.
  ///
  /// **تجاوب**: على التابلت يُقيد العرض بـ 400 موسّطاً (ResponsiveSheet)
  /// — بلا امتداد مشوه بعرض الشاشة. الموبايل: لا يتغير شيء.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    double? maxHeightFactor,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.bgDark.withValues(alpha: 0.54),
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => ResponsiveSheet(
        child: AppSheet(
          title: title,
          maxHeightFactor: maxHeightFactor,
          child: builder(sheetContext),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final MediaQueryData mq = MediaQuery.of(context);

    Widget sheet = AppCard(
      radius: AppRadius.sheet,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
          // مقبض السحب.
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: AppColors.textSecondary(b).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (title != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: AppSpacing.screenH,
              child: Text(
                title!,
                textAlign: TextAlign.center,
                style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: Padding(
              padding: AppSpacing.screenH,
              child: SingleChildScrollView(child: child),
            ),
          ),
          // حشوة أسفل لوحة المفاتيح إن كانت مفتوحة.
          SizedBox(height: mq.viewInsets.bottom),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );

    if (maxHeightFactor != null) {
      sheet = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: mq.size.height * maxHeightFactor!,
        ),
        child: sheet,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: sheet,
    );
  }
}
