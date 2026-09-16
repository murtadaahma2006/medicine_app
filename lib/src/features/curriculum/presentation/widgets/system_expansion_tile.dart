import 'package:flutter/material.dart';

import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// ترويسة جهاز في مسار التعلم — أكورديون (Accordion) + شريط تقدم.
///
/// تعرض: أيقونة الجهاز + اسمه العربي + عدد المحاضرات المنجزة من
/// الإجمالي + شريط تقدم ملون + سهم توسيع/طي يدور مع الحالة.
///
/// المفاتيح الدلالية (Semantics) محفوظة: الزر موسّع/مطوي مفهوم
/// لقارئ الشاشة.
/// ─────────────────────────────────────────────────────────────────────
class SystemExpansionTile extends StatelessWidget {
  const SystemExpansionTile({
    required this.system,
    required this.lectureCount,
    required this.completedCount,
    required this.expanded,
    required this.onToggle,
    this.onDropHere,
    super.key,
  });

  /// رمز الجهاز (respiratory, cardiovascular, ...).
  final String system;

  final int lectureCount;

  /// عدد المحاضرات التي اكتمل تقييمها (assess-) في هذا الجهاز.
  final int completedCount;

  final bool expanded;

  final VoidCallback onToggle;

  /// إفلات محاضرة فوق هذه الترويسة (نقل بين الأجهزة) — اختياري.
  final VoidCallback? onDropHere;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color color = AppColors.module(SystemNames.moduleOf(system), b);
    final double progress =
        lectureCount == 0 ? 0 : completedCount / lectureCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        radius: AppRadius.card,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Semantics(
          button: true,
          expanded: expanded,
          label: '${SystemNames.ar(system)} — '
              '$completedCount من $lectureCount محاضرة',
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    // ── أيقونة الجهاز: طقم SVG المخصص داخل حاوية التخصص ──
                    ModuleIcon(
                      SystemNames.moduleOf(system),
                      size: 44,
                    ),
                    const SizedBox(width: AppSpacing.md),

                    // ── الاسم + العدد ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            SystemNames.ar(system),
                            style: AppType.body.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text(b),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$completedCount/$lectureCount محاضرة',
                            style: AppType.caption.copyWith(
                              color: AppColors.textSecondary(b),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── شريط التقدم الدائري الصغير ──
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          CircularProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            strokeWidth: 3.4,
                            color: color,
                            backgroundColor:
                                AppColors.surfaceAlt(b),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: TextStyle(
                              fontFamily: AppType.latinFamily,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text(b),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),

                    // ── سهم التوسعة ──
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppMotion.scaled(context, AppMotion.standard),
                      curve: AppMotion.ease,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary(b),
                      ),
                    ),
                  ],
                ),

                // ── شريط تقدم أفقي (خطي) أسفل الترويسة ──
                const SizedBox(height: AppSpacing.xs + 2),
                _SystemProgressBar(
                  progress: progress.clamp(0.0, 1.0),
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط تقدم أفقي رفيع بمنحنى نهايات — بلون الجهاز.
class _SystemProgressBar extends StatelessWidget {
  const _SystemProgressBar({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AnimatedContainer(
      duration: AppMotion.scaled(context, AppMotion.transition),
      curve: AppMotion.ease,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(b),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerRight,
        widthFactor: progress <= 0 ? 0.0001 : progress,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// أسماء الأجهزة بالعربية + أيقوناتها + تحويلها إلى تخصص مرئي.
/// ─────────────────────────────────────────────────────────────────────
abstract final class SystemNames {
  /// الاسم العربي للجهاز.
  static String ar(String system) => switch (system) {
        'cardiovascular' => 'جهاز القلب والأوعية',
        'respiratory' => 'الجهاز التنفسي',
        'renal' => 'الجهاز البولي',
        'gastrointestinal' => 'الجهاز الهضمي',
        'endocrine' => 'جهاز الغدد الصماء',
        'immune' => 'جهاز المناعة',
        'nervous' => 'الجهاز العصبي',
        'musculoskeletal' => 'الجهاز العضلي الهيكلي',
        'hematologic' => 'الجهاز الدوري (الدم)',
        'integumentary' => 'الجهاز الغلافي (الجلد)',
        // v21: أجهزة الجراحة/النسائية — نفس المستوى التشريحي.
        'reproductive' => 'الجهاز التناسلي',
        'urinary' => 'الجهاز البولي التناسلي',
        _ => system,
      };

  /// أيقونة مميزة لكل جهاز.
  static IconData icon(String system) => switch (system) {
        'cardiovascular' => Icons.favorite_rounded,
        'respiratory' => Icons.air_rounded,
        'renal' => Icons.water_drop_rounded,
        'gastrointestinal' => Icons.restaurant_rounded,
        'endocrine' => Icons.science_rounded,
        'immune' => Icons.shield_rounded,
        'nervous' => Icons.psychology_rounded,
        'musculoskeletal' => Icons.accessibility_new_rounded,
        'hematologic' => Icons.bloodtype_rounded,
        'integumentary' => Icons.face_retouching_natural_rounded,
        // v21: أجهزة الجراحة/النسائية.
        'reproductive' => Icons.child_friendly_rounded,
        'urinary' => Icons.water_drop_rounded,
        _ => Icons.local_hospital_rounded,
      };

  /// التخصص المرئي المكافئ — لاستعارة لونه من نظام الألوان.
  static String moduleOf(String system) => switch (system) {
        'cardiovascular' => 'cardiology',
        'respiratory' => 'pulmonology',
        'renal' => 'nephrology',
        'gastrointestinal' => 'gastroenterology',
        'endocrine' => 'endocrinology',
        'immune' => 'infectious',
        'nervous' => 'neurology',
        'musculoskeletal' => 'rheumatology',
        'hematologic' => 'hematology',
        'integumentary' => 'rheumatology',
        // v21: المواد الجراحية/النسائية — ألوانها من عائلات
        // الجراحة/النسائية (specialtyPrimary عبر ألوان المجموع).
        'reproductive' => 'gynecology',
        'urinary' => 'urology',
        _ => 'cardiology',
      };
}
