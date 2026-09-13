import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/profile/learner_profile.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة الأونبوردنغ — خطوتان: اختيار التخصص + هدف يومي.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0; // 0 = تخصص، 1 = هدف.
  String? _module;
  int _goal = 10;

  static const List<(String, String, String)> _moduleOptions =
      <(String, String, String)>[
    ('cardiology', 'القلب والأوعية', '❤️'),
    ('pulmonology', 'التنفس', '🫁'),
    ('gastroenterology', 'الجهاز الهضمي', '🫃'),
    ('endocrinology', 'الغدد والسكري', '🧬'),
    ('nephrology', 'الكلى', '🫘'),
    ('neurology', 'الأعصاب', '🧠'),
  ];

  Future<void> _finish() async {
    await LearnerProfile.setPlacementModule(_module ?? 'cardiology');
    await LearnerProfile.setDailyGoal(_goal);
    await LearnerProfile.markOnboarded();
    if (!mounted) return;
    // الرئيسية عبر الراوتر — نحل محل كل المكدس فلا عودة للأونبوردنغ.
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints constraints) {
              final double screenH = MediaQuery.sizeOf(ctx).height;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: <Widget>[
                        const Spacer(flex: 2),

                        // --- صورة الخطوة (تختفي على الشاشات الصغيرة) ---
                        if (screenH >= 580) ...<Widget>[
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AppIllustration(
                                _step == 0 ? 'onboarding_level' : 'onboarding_goal',
                                size: (screenH * 0.18).clamp(80.0, 160.0),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],

                        // --- رأس الترحيب ---
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: Image.asset(
                            'assets/brand/final/logo_mark.png',
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Text('🩺', style: TextStyle(fontSize: 56)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'أهلاً بك في منصة الطب الباطني!',
                          style: AppType.screenTitle.copyWith(
                            fontSize: 21,
                            color: AppColors.text(b),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'سؤالان سريعان لنبدأ رحلتك بشكل صحيح',
                          style: AppType.body
                              .copyWith(color: AppColors.textSecondary(b)),
                          textAlign: TextAlign.center,
                        ),

                        const Spacer(),

                        // --- الخطوة 1: التخصص ---
                        if (_step == 0) ...<Widget>[
                          for (int i = 0; i < _moduleOptions.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(height: AppSpacing.sm + 2),
                            _ModuleOption(
                              emoji: _moduleOptions[i].$3,
                              title: _moduleOptions[i].$2,
                              selected: _module == _moduleOptions[i].$1,
                              onTap: () =>
                                  setState(() => _module = _moduleOptions[i].$1),
                            ),
                          ],
                          const Spacer(),
                          AppButton(
                            label: 'التالي',
                            trailingIcon: Icons.arrow_back_rounded,
                            onPressed: _module == null
                                ? null
                                : () => setState(() => _step = 1),
                          ),
                        ]

                        // --- الخطوة 2: الهدف اليومي ---
                        else ...<Widget>[
                          Text(
                            'كم بطاقة تريد مراجعتها يومياً؟',
                            style: AppType.screenTitle.copyWith(
                              fontSize: 19,
                              color: AppColors.text(b),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Row(
                            children: <int>[5, 10, 15, 20].map((int goal) {
                              final bool selected = _goal == goal;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs + 2),
                                  child: _GoalChip(
                                    value: goal,
                                    selected: selected,
                                    onTap: () =>
                                        setState(() => _goal = goal),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'تستطيع تغييره لاحقاً من الإعدادات — وستظهر بطاقاتك '
                            'المستحقة في «مراجعة اليوم» على الرئيسية.',
                            textAlign: TextAlign.center,
                            style: AppType.body.copyWith(
                              fontSize: 13.5,
                              color: AppColors.textSecondary(b),
                            ),
                          ),
                          const Spacer(),
                          AppButton(
                            label: 'ابدأ الدراسة',
                            icon: Icons.flag_rounded,
                            onPressed: _finish,
                          ),
                        ],

                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// خيار تخصص واحد.
class _ModuleOption extends StatelessWidget {
  const _ModuleOption({
    required this.emoji,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Material(
      color: selected ? AppColors.primaryTint(b) : AppColors.surface(b),
      borderRadius: BorderRadius.circular(AppRadius.card + 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card + 2),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.feedback,
          curve: AppMotion.ease,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card + 2),
            border: Border.all(
              color: selected
                  ? AppColors.primary(b)
                  : AppColors.border(b),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: AppSpacing.md + 2),
              Expanded(
                child: Text(
                  title,
                  style: AppType.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text(b),
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: AppColors.primary(b), size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريحة هدف يومي واحدة.
class _GoalChip extends StatelessWidget {
  const _GoalChip({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Material(
      color: selected ? AppColors.primary(b) : AppColors.surface(b),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.feedback,
          curve: AppMotion.ease,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  selected ? AppColors.primary(b) : AppColors.border(b),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '$value',
                textDirection: TextDirection.ltr,
                style: AppType.cardTitle.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color:
                      selected ? Colors.white : AppColors.text(b),
                ),
              ),
              Text(
                'بطاقة',
                style: AppType.caption.copyWith(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.textSecondary(b),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
