import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// درجات الثقة (قبلة الثقة — Butterfield & Metcalfe).
///
/// الخطأ عالي الثقة + التصحيح الفوري = أقوى وحدة ترميز ممكنة
/// (Hypercorrection). أخطاء «متأكد جداً» تُسجَّل في confidence_log
/// وتُحجز لمراجعة +24h/+7d فوق جدول SRS.
/// ─────────────────────────────────────────────────────────────────────
enum GateConfidence {
  guess(0, 'خمّنت'),
  sure(1, 'متأكد'),
  superSure(2, 'متأكد جداً');

  const GateConfidence(this.value, this.labelAr);

  final int value;
  final String labelAr;
}

/// ─────────────────────────────────────────────────────────────────────
/// بوابة الشرح (Reverse Interrogation — المقترح A).
///
/// سؤال MCQ واحد قبل فتح القارئ — من بنك أسئلة الشرح نفسه
/// (concept_id) بصفر تأليف محتوى. حتى لو أخطأت — **خاصة لو أخطأت** —
/// تتحول القراءة من «استقبال» إلى قنص موجّه: تقرأ لتكتشف أين كنت واهماً.
///
/// التدفق:
/// 1. سؤال + مقياس ثقة من 3 درجات (سحبة أفقية واحدة).
/// 2. كشف فوري مع explanation_ar — لحظة التصحيح المفرط.
/// 3. زر «اقرأ الشرح — تعرّف أين أخطأت» → يرجع نتيجة البوابة:
///    {wrongSections: [فهارس الأقسام التي تجيب السؤال]} لتمييزها
///    كهرمانياً في القارئ.
/// ─────────────────────────────────────────────────────────────────────
class ConceptGateSheet extends StatefulWidget {
  const ConceptGateSheet({
    required this.conceptTitle,
    required this.mcq,
    super.key,
  });

  final String conceptTitle;
  final Map<String, Object?> mcq;

  /// يفتح البوابة إن كان للشرح سؤال بوابة صالح — يرجع null إن غاب
  /// (المستدعي يفتح القارئ مباشرة بلا بوابة).
  static Future<Map<String, Object?>?> show(
    BuildContext context, {
    required String conceptTitle,
    required Map<String, Object?> mcq,
  }) {
    return showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      // تجاوب: على التابلت يُقيد العرض (موبايل: بلا أثر).
      builder: (_) => ResponsiveSheet(
        child: ConceptGateSheet(
          conceptTitle: conceptTitle,
          mcq: mcq,
        ),
      ),
    );
  }

  @override
  State<ConceptGateSheet> createState() => _ConceptGateSheetState();
}

class _ConceptGateSheetState extends State<ConceptGateSheet> {
  GateConfidence? _confidence;
  int? _selected;

  List<String> get _options {
    try {
      final dynamic decoded = jsonDecode(widget.mcq['options_json']! as String);
      if (decoded is List) {
        return decoded.map((dynamic s) => s.toString()).toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  int get _correctIndex => (widget.mcq['correct_index'] as num?)?.toInt() ?? 0;

  List<int> get _focusSections {
    final String? raw = widget.mcq['focus_sections_json'] as String?;
    if (raw == null) return const <int>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const <int>[];
      return <int>[
        for (final dynamic v in decoded)
          if (v is num) v.toInt(),
      ];
    } catch (_) {
      return const <int>[];
    }
  }

  bool get _isCorrect => _selected == _correctIndex;

  Future<void> _answer(int optionIndex) async {
    if (_selected != null) return;
    setState(() => _selected = optionIndex);
    AppHaptics.selection();

    // سجل الثقة + الإجابة في confidence_log (ذهب لجدول الثقة).
    if (_confidence != null) {
      try {
        await DatabaseHelper.instance.logConfidence(
          questionId: widget.mcq['id']! as String,
          confidence: _confidence!.value,
          wasCorrect: optionIndex == _correctIndex,
        );
      } catch (_) {
        // صمت مقصود.
      }
    }

    // الخطأ عالي الثقة — نبأ النبأ (التصحيح المفرط).
    if (optionIndex != _correctIndex && _confidence == GateConfidence.superSure) {
      AppHaptics.error();
    }
  }

  void _proceedToReader() {
    Navigator.of(context).pop(<String, Object?>{
      'answered': _selected != null,
      'was_correct': _isCorrect,
      'focus_sections': _focusSections,
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Size size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: _selected != null, // لا هروب قبل الإجابة — احتكاك إيجابي.
      child: Container(
        constraints: BoxConstraints(maxHeight: size.height * 0.88),
        decoration: BoxDecoration(
          color: AppColors.surface(b),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          border: Border.all(color: AppColors.border(b)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ── ترويسة ──
                Row(
                  children: <Widget>[
                    Icon(Icons.psychology_alt_rounded,
                        size: 22, color: AppColors.gold(b)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'قبل أن تقرأ — بوابة الشرح',
                        style: AppType.cardTitle.copyWith(fontSize: 17),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'جاوب بسرعة ثم اقرأ لتكتشف أين كنت واهماً — حتى لو أخطأت،'
                  ' الخطأ هنا أثمن من الصواب.',
                  style: AppType.body.copyWith(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.textSecondary(b),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── نص السؤال ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt(b),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border(b)),
                  ),
                  child: Text(
                    widget.mcq['question_stem']! as String,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                    style: AppType.body.copyWith(
                      fontSize: 15.5,
                      height: 1.65,
                      fontFamily: AppType.latinFamily,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text(b),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── مقياس الثقة (قبل الخيارات — سحبة واحدة) ──
                if (_selected == null) ...<Widget>[
                  Text(
                    'كم واثق من جوابك القادم؟',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      for (final GateConfidence c in GateConfidence.values)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs),
                            child: _ConfidenceChip(
                              confidence: c,
                              selected: _confidence == c,
                              onTap: () =>
                                  setState(() => _confidence = c),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── الخيارات ──
                for (int i = 0; i < _options.length; i++)
                  ExerciseOptionButton(
                    label: _options[i],
                    latin: true,
                    onTap: _selected == null ? () => _answer(i) : null,
                    state: _selected == null
                        ? null
                        : i == _correctIndex
                            ? OptionState.correct
                            : i == _selected
                                ? OptionState.wrong
                                : OptionState.dimmed,
                  ),

                // ── الكشف + زر المتابعة ──
                if (_selected != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: _isCorrect
                          ? AppColors.successContainer(b)
                          : AppColors.errorContainer(b),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: (_isCorrect
                                ? AppColors.success(b)
                                : AppColors.error(b))
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              _isCorrect
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              size: 20,
                              color: _isCorrect
                                  ? AppColors.success(b)
                                  : AppColors.error(b),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              _isCorrect
                                  ? 'إجابة صحيحة — اقرأ لتثبيتها'
                                  : 'كنت واهماً هنا — الآن اقرأ لتصحيحه',
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w800,
                                color: _isCorrect
                                    ? AppColors.success(b)
                                    : AppColors.error(b),
                              ),
                            ),
                          ],
                        ),
                        if (!_isCorrect) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            widget.mcq['explanation_ar']! as String,
                            style: AppType.body.copyWith(
                              height: 1.7,
                              fontSize: 13.5,
                              color: AppColors.text(b),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _proceedToReader,
                      child: Text(
                        _isCorrect
                            ? 'اقرأ الشرح'
                            : 'اقرأ الشرح — تعرّف أين أخطأت',
                        style: AppType.body.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شريحة ثقة واحدة.
class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({
    required this.confidence,
    required this.selected,
    required this.onTap,
  });

  final GateConfidence confidence;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: 'الثقة: ${confidence.labelAr}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.scaled(context, AppMotion.feedback),
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryTint(b) : AppColors.surfaceAlt(b),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? primary : AppColors.border(b),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            confidence.labelAr,
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
