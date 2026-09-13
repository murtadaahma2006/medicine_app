import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// خلية إحصائية — أيقونة + قيمة + تسمية في مربع موحد.
/// ─────────────────────────────────────────────────────────────────────
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.tint,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String value;
  final String label;

  /// لون الأيقونة (ذهبي لXP · أحمر للسلسلة · لون مستوى...).
  final Color? tint;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;
    final Color iconColor = tint ?? theme.colorScheme.primary;

    final Widget tile = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: AppMotion.ease,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.colorScheme.outline),
        boxShadow: AppShadows.card(b),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 24, color: iconColor, semanticLabel: label),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppType.cardTitle.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.text(b),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppType.caption.copyWith(color: AppColors.textSecondary(b)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: tile,
      ),
    );
  }
}
