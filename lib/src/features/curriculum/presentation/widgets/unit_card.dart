import 'package:flutter/material.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// بطاقة وحدة تعليمية (محاضرة طبية) — AppCard بشريط جانبي بلون
/// التخصص + أيقونة التخصص من الطقم المخصص + شريط تقدم اختياري.
class UnitCard extends StatelessWidget {
  const UnitCard({
    required this.unitId,
    required this.module,
    required this.title,
    this.progress,
    this.onTap,
    super.key,
  });

  final String unitId;
  final String module;

  /// عنوان المحاضرة — إنجليزي.
  final String title;

  /// تقدم الوحدة 0.0–1.0 (null يخفي الشريط).
  final double? progress;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color moduleColor = AppColors.module(module, b);
    final double? progress = this.progress;

    return AppCard(
      onTap: onTap,
      accent: moduleColor,
      child: Row(
        children: <Widget>[
          // --- أيقونة الوحدة: طقم SVG المخصص (أو إيموجي عند غيابه) ---
          SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: ModuleIcon(
                module,
                size: 52,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // --- العنوان + شارة التخصص + شريط التقدم ---
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ModuleBadge(module),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        title,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: AppType.cardTitle.copyWith(
                            fontSize: 17, color: AppColors.text(b)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (progress != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  ProgressBar(
                    progress: progress.clamp(0.0, 1.0),
                    height: 5,
                    color: moduleColor,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_left_rounded,
              color: AppColors.textSecondary(b).withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}
