import 'package:flutter/material.dart';

import '../../../../core/profile/learner_profile.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../curriculum/presentation/widgets/fixation_spans.dart';

/// ─────────────────────────────────────────────────────────────────────
/// إعدادات القراءة العميقة — مراسي التثبيت والتايبوغرافيا.
///
/// - مفتاح تفعيل المراسي (افتراضي: مفعّل) — تُطبَّق على القراءة
///   الأولى فقط تلقائياً.
/// - قوة المرساة: خفيفة 30% · متوازنة 40% (افتراضي) · قوية 60%.
/// - معاينة حية بنص طبي إنجليزي حقيقي — يرى المستخدم الأثر قبل
///   الحفظ.
/// ─────────────────────────────────────────────────────────────────────
class FixationSettingsPage extends StatefulWidget {
  const FixationSettingsPage({super.key});

  @override
  State<FixationSettingsPage> createState() => _FixationSettingsPageState();
}

class _FixationSettingsPageState extends State<FixationSettingsPage> {
  bool _loading = true;
  bool _enabled = true;
  FixationStrength _strength = FixationStrength.standard;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool enabled = await LearnerProfile.anchorsEnabled();
    final String code = await LearnerProfile.anchorStrengthCode();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _strength = FixationStrength.fromCode(code);
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await LearnerProfile.setAnchorsEnabled(value);
  }

  Future<void> _changeStrength(FixationStrength s) async {
    setState(() => _strength = s);
    await LearnerProfile.setAnchorStrengthCode(s.code);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('القراءة العميقة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
              children: <Widget>[
                // ── شرح الميزة ──
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'مراسي التثبيت أثناء القراءة',
                        style: AppType.cardTitle.copyWith(fontSize: 17),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'تعرّض بداية كل كلمة إنجليزية في الشروحات — عينك '
                        'تقفز كلماتٍ كاملة بدل مسحها حرفاً حرفاً، فتقرأ '
                        'أسرع مع تركيز أعلى. تعمل في **القراءة الأولى** '
                        'فقط؛ عند إعادة القراءة تُطفأ تلقائياً لأن النص '
                        'المألوف يحتاج البنية لا البصريات.',
                        style: AppType.body.copyWith(
                          fontSize: 13.5,
                          height: 1.7,
                          color: AppColors.textSecondary(b),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── مفتاح التفعيل ──
                AppCard(
                  child: SwitchListTile(
                    value: _enabled,
                    onChanged: _toggle,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'تفعيل مراسي التثبيت',
                      style: AppType.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'تسريع قراءة الشروحات الطويلة',
                      style: AppType.body.copyWith(
                        fontSize: 12.5,
                        color: AppColors.textSecondary(b),
                      ),
                    ),
                  ),
                ),

                if (_enabled) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),

                  // ── قوة المرساة ──
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'قوة المرساة',
                          style: AppType.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'نسبة بداية الكلمة التي تُعرَّض',
                          style: AppType.body.copyWith(
                            fontSize: 12.5,
                            color: AppColors.textSecondary(b),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: <Widget>[
                            for (final FixationStrength s
                                in FixationStrength.values)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs),
                                  child: _StrengthOption(
                                    strength: s,
                                    selected: _strength == s,
                                    onTap: () => _changeStrength(s),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // ── معاينة حية ──
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'معاينة حية',
                          style: AppType.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text.rich(
                          TextSpan(
                            style: focusBodyStyle(b),
                            children: buildAnchoredSpans(
                              'Hyperkalemia is defined as a serum potassium '
                              'concentration above 5.0 mmol/L. Peaked T waves '
                              'are the earliest ECG finding, followed by '
                              'widening of the QRS complex.',
                              focusBodyStyle(b),
                              strength: _strength,
                            ),
                          ),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
    );
  }
}

/// خيار قوة مرساة واحد.
class _StrengthOption extends StatelessWidget {
  const _StrengthOption({
    required this.strength,
    required this.selected,
    required this.onTap,
  });

  final FixationStrength strength;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;
    final Color primary = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: 'قوة المرساة: ${strength.labelAr}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.scaled(context, AppMotion.feedback),
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primaryTint(b) : AppColors.surfaceAlt(b),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? primary : AppColors.border(b),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            strength.labelAr,
            style: AppType.caption.copyWith(
              color: selected ? primary : AppColors.textSecondary(b),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
