import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// شارة التخصص الطبي — بلون التخصص الرسمي تتكيف مع الوضع الداكن.
/// ─────────────────────────────────────────────────────────────────────
class ModuleBadge extends StatelessWidget {
  const ModuleBadge(this.module, {this.large = false, super.key});

  /// رمز التخصص: cardiology / pulmonology / ...
  final String module;

  /// نسخة أكبر (رأس شاشة الوحدة).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color color = AppColors.module(module, b);
    // نظام «الحاوية أولاً»: خلفية = حاوية التخصص الممزوجة بالسطح،
    // والنص = نسخة «نص» أغمق في الفاتح (تباين AA).
    final Color container = AppColors.moduleContainer(module, b);
    final Color textColor = AppColors.moduleText(module, b);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? AppSpacing.lg : AppSpacing.sm + 2,
        vertical: large ? AppSpacing.xs + 1 : 2.5,
      ),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        AppColors.moduleNameAr(module),
        style: TextStyle(
          fontFamily: AppType.arabicFamily,
          fontSize: large ? 16 : 12,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// رأس قسم بعنوان + شريط التوقيع الثلاثي (رمادي/أحمر/ذهبي).
///
/// عنصر التوقيع يظهر هنا وفي الشعار فقط — باعتدال شديد.
/// ─────────────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.subtitle, super.key});

  /// عنوان القسم.
  final String title;

  /// سطر وصف اختياري تحت العنوان.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        // شريط التوقيع الثلاثي — رمادي/أحمر/ذهبي.
        const SignatureStripe(),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// الشريط الثلاثي للتوقيع — 3 قطع ملونة رفيعة.
class SignatureStripe extends StatelessWidget {
  const SignatureStripe({this.width = 44, this.height = 3, super.key});

  /// عرض كل قطعة.
  final double width;

  /// سماكة الشريط.
  final double height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _seg(AppColors.signatureGray, width * 0.45),
            const SizedBox(width: 2),
            _seg(AppColors.signatureRed, width * 0.33),
            const SizedBox(width: 2),
            _seg(AppColors.signatureGold, width * 0.22),
          ],
        ),
      ),
    );
  }

  Widget _seg(Color c, double w) {
    return Container(
      width: w,
      height: height,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(height),
      ),
    );
  }
}
