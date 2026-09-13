import 'package:flutter/material.dart';

import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// لوحة الفلترة الذكية — أعلى كل شاشة بنك (بطاقات/أسئلة/حالات).
///
/// **المكوّنات**:
/// - قائمة منسدلة للجهاز (System) — «الكل» أو أحد الأجهزة الموجودة.
/// - قائمة منسدلة للمحاضرة — **تتحدث ديناميكياً** حسب الجهاز المختار.
/// - مبدل ترتيب (SegmentedButton): «ترتيب المنهج» ↔ «ترتيب عشوائي».
/// - زر بارز (اختياري): «مراجعة عشوائية لما تمت دراسته».
///
/// الحالة تُدار من الشاشة الأم — اللوحة عرض فقط (stateless)
/// فتنعكس أي تغييرات فوراً على ListView عبر onXxx callbacks.
/// ─────────────────────────────────────────────────────────────────────
class BankFilterPanel extends StatelessWidget {
  const BankFilterPanel({
    required this.systems,
    required this.selectedSystem,
    required this.lectures,
    required this.selectedLectureId,
    required this.isRandom,
    required this.onSystemChanged,
    required this.onLectureChanged,
    required this.onSortChanged,
    this.showStudiedReviewButton = false,
    this.studiedCount,
    this.onStudiedReview,
    super.key,
  });

  /// الأجهزة المتاحة (من getDistinctSystems).
  final List<String> systems;

  /// الجهاز المختار — null = «الكل».
  final String? selectedSystem;

  /// محاضرات الجهاز المختار (تتغذى من getUnitsBySystem).
  final List<Map<String, Object?>> lectures;

  /// المحاضرة المختارة — null = «الكل».
  final String? selectedLectureId;

  /// وضع الترتيب: false = زمني (المنهج) · true = عشوائي.
  final bool isRandom;

  final ValueChanged<String?> onSystemChanged;
  final ValueChanged<String?> onLectureChanged;
  final ValueChanged<bool> onSortChanged;

  /// إظهار زر «مراجعة ما دُرس» (لبنك البطاقات فقط).
  final bool showStudiedReviewButton;

  /// عدد البطاقات المدروسة المتاحة (يعطّل الزر عند 0).
  final int? studiedCount;

  /// فتح جلسة المراجعة العشوائية المدروسة.
  final VoidCallback? onStudiedReview;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── صف القوائم المنسدلة: الجهاز ثم المحاضرة ──
          Row(
            children: <Widget>[
              Expanded(
                child: _FilterDropdown(
                  label: 'الجهاز',
                  icon: _systemIcon(selectedSystem),
                  value: selectedSystem,
                  items: <_DropdownItem>[
                    const _DropdownItem(value: null, label: 'كل الأجهزة'),
                    for (final String s in systems)
                      _DropdownItem(value: s, label: _systemAr(s)),
                  ],
                  onChanged: onSystemChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _FilterDropdown(
                  label: 'المحاضرة',
                  icon: Icons.menu_book_rounded,
                  value: selectedLectureId,
                  items: <_DropdownItem>[
                    const _DropdownItem(value: null, label: 'كل المحاضرات'),
                    for (final Map<String, Object?> l in lectures)
                      _DropdownItem(
                        value: l['id']! as String,
                        label: _cleanTitle(l['title']! as String),
                      ),
                  ],
                  onChanged: onLectureChanged,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── مبدل الترتيب: منهجي ↔ عشوائي ──
          Row(
            children: <Widget>[
              Icon(Icons.sort_rounded,
                  size: 18, color: AppColors.textSecondary(b)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.format_list_numbered_rounded, size: 18),
                      label: Text('ترتيب المنهج'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.shuffle_rounded, size: 18),
                      label: Text('ترتيب عشوائي'),
                    ),
                  ],
                  selected: <bool>{isRandom},
                  onSelectionChanged: (Set<bool> s) =>
                      onSortChanged(s.first),
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll<TextStyle>(
                      AppType.caption.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── زر المراجعة العشوائية المدروسة (بطاقات فقط) ──
          if (showStudiedReviewButton) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: studiedCount == null
                  ? 'مراجعة عشوائية لما تمت دراسته'
                  : 'مراجعة المدروس عشوائياً ($studiedCount بطاقة)',
              icon: Icons.auto_awesome_rounded,
              type: AppButtonType.secondary,
              minHeight: 46,
              onPressed:
                  (studiedCount ?? 0) > 0 ? onStudiedReview : null,
            ),
          ],
        ],
      ),
    );
  }

  static String _systemAr(String system) => switch (system) {
        'cardiovascular' => 'القلب والأوعية',
        'respiratory' => 'التنفسي',
        'renal' => 'البولي',
        'gastrointestinal' => 'الهضمي',
        'endocrine' => 'الغدد الصماء',
        'immune' => 'المناعة',
        'nervous' => 'العصبي',
        'musculoskeletal' => 'العضلي الهيكلي',
        'hematologic' => 'الدم',
        'integumentary' => 'الجلد',
        _ => system,
      };

  static IconData _systemIcon(String? system) => switch (system) {
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
        _ => Icons.hub_rounded,
      };

  static String _cleanTitle(String raw) {
    String t = raw;
    if (t.startsWith('[') && t.contains(']')) {
      t = t.substring(1, t.indexOf(']'));
    }
    return t.trim();
  }
}

/// عنصر قائمة منسدلة — القيمة قد تكون null («الكل»).
class _DropdownItem {
  const _DropdownItem({required this.value, required this.label});

  final String? value;
  final String label;
}

/// القائمة المنسدلة الموحدة — حقل بحد + سهم، يعرض label المختار.
class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String? value;
  final List<_DropdownItem> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final _DropdownItem? current = items
        .where((_DropdownItem i) => i.value == value)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AppType.caption.copyWith(
            color: AppColors.textSecondary(b),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt(b),
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: AppColors.border(b)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary(b)),
              style: AppType.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.text(b),
              ),
              items: <DropdownMenuItem<String?>>[
                for (final _DropdownItem item in items)
                  DropdownMenuItem<String?>(
                    value: item.value,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (String? v) => onChanged(v),
              selectedItemBuilder: (BuildContext ctx) => <Widget>[
                for (final _DropdownItem item in items)
                  if (item.value == (current?.value ?? value))
                    Row(
                      children: <Widget>[
                        Icon(icon,
                            size: 16,
                            color: AppColors.primary(
                                Theme.of(ctx).colorScheme.brightness)),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.body.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text(Theme.of(ctx)
                                  .colorScheme
                                  .brightness),
                            ),
                          ),
                        ),
                      ],
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
