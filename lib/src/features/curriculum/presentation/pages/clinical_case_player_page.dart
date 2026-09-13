import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/database/correction.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../widgets/fixation_spans.dart';

/// مشغل حالة سريرية واحدة (OSCE style):
/// - غلاف السيناريو (vignette): العمر/الجنس/الشكوى/التاريخ/العلامات/الفحوصات.
/// - خطوات قرار متسلسلة: كل خطوة سؤال إنجليزي + خيارات + شرح عربي بعد
///   الإجابة + XP فوري للقرار الصحيح.
/// - Debriefing عربي ختامي.
class ClinicalCasePlayerPage extends StatefulWidget {
  const ClinicalCasePlayerPage({required this.caseId, super.key});

  final String caseId;

  @override
  State<ClinicalCasePlayerPage> createState() =>
      _ClinicalCasePlayerPageState();
}

class _ClinicalCasePlayerPageState extends State<ClinicalCasePlayerPage> {
  bool _loading = true;
  String? _error;

  Map<String, Object?>? _caseRow;
  List<Map<String, Object?>> _steps = const [];

  int _stepIndex = 0;
  int? _selected;
  bool? _lastCorrect;
  int _earnedXp = 0;
  int _correctSteps = 0;
  final List<Correction> _corrections = <Correction>[];

  String get _drillKey => 'case-${widget.caseId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final Map<String, Object?>? caseRow = await db.getCaseById(widget.caseId);
      if (caseRow == null) {
        if (!mounted) return;
        setState(() {
          _error = 'الحالة غير موجودة.';
          _loading = false;
        });
        return;
      }
      final List<Map<String, Object?>> steps =
          await db.getStepsForCase(widget.caseId);
      if (!mounted) return;
      setState(() {
        _caseRow = caseRow;
        _steps = steps;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الحالة.';
        _loading = false;
      });
    }
  }

  List<String> _optionsOf(Map<String, Object?> step) {
    try {
      final dynamic decoded = jsonDecode(step['options_json']! as String);
      if (decoded is List) {
        return decoded.map((dynamic s) => s.toString()).toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> _select(int optionIndex) async {
    if (_selected != null) return;

    final Map<String, Object?> step = _steps[_stepIndex];
    final int correctIndex = (step['correct_index'] as num?)?.toInt() ?? 0;
    final bool isCorrect = optionIndex == correctIndex;
    final int xp = (step['xp'] as num?)?.toInt() ?? 5;
    final List<String> options = _optionsOf(step);

    setState(() {
      _selected = optionIndex;
      _lastCorrect = isCorrect;
      if (isCorrect) {
        _correctSteps++;
        _earnedXp += xp;
      }
    });
    AppHaptics.selection();

    try {
      _corrections.add(Correction(
        drillId: _drillKey,
        questionId: step['id']! as String,
        userAnswer: options.isNotEmpty ? options[optionIndex] : '',
        correctAnswer: options.isNotEmpty ? options[correctIndex] : '',
        isCorrect: isCorrect,
        mistakeType: isCorrect ? MistakeType.exact : MistakeType.wrong,
        attemptedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // XP فوري لكل قرار صحيح (نوع case_step — قرار المواصفة).
      if (isCorrect) {
        await DatabaseHelper.instance.addXpEvent(
          kind: XpEventKind.caseStep,
          refId: step['id'] as String?,
          xp: xp,
        );
      }
    } catch (_) {
      // صمت مقصود.
    }
  }

  Future<void> _next() async {
    if (_stepIndex + 1 >= _steps.length) {
      await _finish();
      return;
    }
    setState(() {
      _stepIndex++;
      _selected = null;
      _lastCorrect = null;
    });
  }

  Future<void> _finish() async {
    try {
      await DatabaseHelper.instance.insertCorrections(_corrections);
      await DatabaseHelper.instance.grantDailyStreakBonus();
      await DatabaseHelper.instance.unlockEarnedBadges();
    } catch (_) {
      // صمت مقصود.
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.gold(Brightness.light),
        content: Text(
          'اكتملت الحالة — $_correctSteps من ${_steps.length} قرارات صحيحة (+$_earnedXp XP)',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        backgroundColor: AppColors.background(b),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _caseRow == null ? '' : (_caseRow!['title'] as String? ?? ''),
          textDirection: TextDirection.ltr,
          style: AppType.caption
              .copyWith(fontSize: 13, color: AppColors.textSecondary(b)),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  actionLabel: 'إعادة المحاولة',
                  onAction: _load,
                )
              : _buildCase(b),
    );
  }

  Widget _buildCase(Brightness b) {
    final Map<String, Object?> vignette = _parseJsonMap(_caseRow!['vignette_json']);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: ProgressBar(
            progress:
                (_stepIndex + (_selected != null ? 1 : 0)) / _steps.length,
            height: 6,
            color: AppColors.error(b),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ── بطاقة السيناريو (تظهر في الخطوة الأولى) ──
                if (_stepIndex == 0) ...<Widget>[
                  _VignetteCard(vignette: vignette),
                  const SizedBox(height: AppSpacing.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      _caseRow!['scenario']! as String,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                      style: AppType.body.copyWith(
                          height: 1.65,
                          fontFamily: AppType.focusFamily,
                          fontSize: 15,
                          color: AppColors.focusText(b)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── مؤشر الخطوة ──
                Row(
                  children: <Widget>[
                    Icon(Icons.medical_services_rounded,
                        size: 16, color: AppColors.error(b)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'الخطوة ${_stepIndex + 1} من ${_steps.length}',
                      style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.error(b)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── سؤال القرار ──
                ..._buildStep(b),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStep(Brightness b) {
    final Map<String, Object?> step = _steps[_stepIndex];
    final List<String> options = _optionsOf(step);
    final int correctIndex = (step['correct_index'] as num?)?.toInt() ?? 0;

    return <Widget>[
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface(b),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border(b)),
        ),
        child: Text(
          step['prompt']! as String,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.start,
          style: AppType.body.copyWith(
            fontSize: 15.5,
            height: 1.6,
            fontFamily: AppType.latinFamily,
            fontWeight: FontWeight.w600,
            color: AppColors.text(b),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      for (int i = 0; i < options.length; i++)
        ExerciseOptionButton(
          label: options[i],
          latin: true,
          onTap: _selected == null ? () => _select(i) : null,
          state: _selected == null
              ? null
              : i == correctIndex
                  ? OptionState.correct
                  : i == _selected
                      ? OptionState.wrong
                      : OptionState.dimmed,
        ),

      if (_selected != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        _ExplanationCard(
          explanation: step['explanation_ar']! as String,
          correct: _lastCorrect == true,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: _stepIndex + 1 >= _steps.length ? 'خاتمة الحالة' : 'الخطوة التالية',
          trailingIcon: Icons.arrow_back_rounded,
          onPressed: _next,
        ),
      ],

      // ── Debriefing في الخطوة الأخيرة بعد الإجابة ──
      if (_selected != null && _stepIndex + 1 >= _steps.length) ...<Widget>[
        const SizedBox(height: AppSpacing.lg),
        _DebriefingCard(debriefing: _caseRow!['debriefing_ar']! as String),
      ],
    ];
  }

  static Map<String, Object?> _parseJsonMap(Object? rawJson) {
    if (rawJson is! String || rawJson.trim().isEmpty) return const {};
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return const {};
  }
}

/// بطاقة بيانات المريض (vignette).
class _VignetteCard extends StatelessWidget {
  const _VignetteCard({required this.vignette});

  final Map<String, Object?> vignette;

  Map<String, Object?> get _vitals {
    final dynamic raw = vignette['vitals'];
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return const {};
  }

  List<Map<String, Object?>> get _labs {
    final dynamic raw = vignette['labs'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final String age = (vignette['age'] ?? '').toString();
    final String sex = ((vignette['sex'] as String?) ?? '').toLowerCase();
    final String sexAr = sex == 'male' ? 'ذكر' : sex == 'female' ? 'أنثى' : '';

    return AppCard(
      accent: AppColors.error(b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.person_rounded,
                  size: 20, color: AppColors.error(b)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$age عاماً · $sexAr',
                style: AppType.body.copyWith(
                    fontWeight: FontWeight.w800, color: AppColors.text(b)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            (vignette['chief_complaint'] as String?) ?? '',
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: AppType.body.copyWith(
                fontFamily: AppType.latinFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.error(b)),
          ),
          const SizedBox(height: AppSpacing.md),

          if (_vitals.isNotEmpty) _Section(
            icon: Icons.monitor_heart_rounded,
            title: 'Vitals',
            lines: <String>[
              for (final MapEntry<String, Object?> e in _vitals.entries)
                '${e.key.toUpperCase()}: ${e.value}',
            ],
          ),
          if ((vignette['history'] as String?)?.isNotEmpty == true)
            _Section(
              icon: Icons.history_rounded,
              title: 'History',
              lines: <String>[vignette['history']! as String],
            ),
          if ((vignette['exam'] as String?)?.isNotEmpty == true)
            _Section(
              icon: Icons.accessibility_new_rounded,
              title: 'Physical Exam',
              lines: <String>[vignette['exam']! as String],
            ),
          if (_labs.isNotEmpty)
            _Section(
              icon: Icons.science_rounded,
              title: 'Labs',
              lines: <String>[
                for (final Map<String, Object?> lab in _labs)
                  '${lab['name']}: ${lab['value']} (${lab['flag']})',
              ],
            ),
          if ((vignette['imaging'] as String?)?.isNotEmpty == true)
            _Section(
              icon: Icons.image_rounded,
              title: 'Imaging',
              lines: <String>[vignette['imaging']! as String],
            ),
        ],
      ),
    );
  }
}

/// قسم صغير داخل بطاقة المريض — سطر عنوان إنجليزي + أسطر محتوى.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 15, color: AppColors.textSecondary(b)),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                title,
                textDirection: TextDirection.ltr,
                style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: AppType.latinFamily,
                    color: AppColors.textSecondary(b)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final String line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                style: AppType.body.copyWith(
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: AppType.latinFamily,
                    color: AppColors.textSecondary(b)),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة الشرح العربي بعد كل قرار — بنمط القراءة العميقة العربية:
/// 17sp/1.8 + شريط مسار قراءة بلون النتيجة.
class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({required this.explanation, required this.correct});

  final String explanation;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color okColor =
        correct ? AppColors.success(b) : AppColors.error(b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: correct
            ? AppColors.successContainer(b)
            : AppColors.errorContainer(b),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: okColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              correct
                  ? SelfDrawingCheck(size: 20, color: okColor)
                  : Icon(Icons.close_rounded,
                      size: 20, color: okColor),
              const SizedBox(width: AppSpacing.sm),
              Text(
                correct ? 'قرار صحيح' : 'قرار غير optimal',
                style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w800, color: okColor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // شريط مسار القراءة — توجيه عمودي للعين في النص العربي.
          ClinicalParagraph(
            text: explanation,
            accent: okColor,
          ),
        ],
      ),
    );
  }
}

/// بطاقة الخاتمة العربية (debriefing) — وضع القراءة العميقة.
class _DebriefingCard extends StatelessWidget {
  const _DebriefingCard({required this.debriefing});

  final String debriefing;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AppCard(
      accent: AppColors.gold(b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.school_rounded, size: 20, color: AppColors.gold(b)),
              const SizedBox(width: AppSpacing.sm),
              Text('خلاصة الحالة',
                  style: AppType.cardTitle.copyWith(
                      fontSize: 16, color: AppColors.text(b))),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClinicalParagraph(
            text: debriefing,
            accent: AppColors.gold(b),
          ),
        ],
      ),
    );
  }
}
