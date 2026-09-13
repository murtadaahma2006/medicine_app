import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// نقطة الاعتراض (Interception Point — المقترح B).
///
/// بعد كل 2–3 أقسام قراءة، تنفتح شاشة كاملة بحجاب معتم تفرض لحظة
/// استرجاع: سؤال MCQ غير مستهلك من أسئلة الشرح نفسه — أو، إن
/// استُهلكت كلها، «استرجاع حر»: لخّص النقاط الثلاث ثم قارن بالفعلية.
///
/// هذه النقاط أيضاً نبضات الحضور الطبيعية — كاشف الشرود مدمج في
/// السرد بلا أسئلة «هل ما زلت هنا؟» مزعجة.
///
/// [source]: مصدر السؤال:
/// - mcq: صف من mcq_bank (options_json/correct_index/explanation_ar).
/// - check: سؤال مدمج من sections_json.check (عقد v2.1).
/// - free: استرجاع حر بلا خيارات — keyPoints تُعرض بعد الكتابة.
/// ─────────────────────────────────────────────────────────────────────
class InterceptionSheet extends StatefulWidget {
  const InterceptionSheet({
    required this.source,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    this.explanationAr,
    this.mcqId,
    required this.freeKeyPoints,
    super.key,
  });

  /// مصدر السؤال: mcq (بنك الأسئلة) · check (مدمج v2.1) · free (استرجاع حر).
  final InterceptionSource source;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? explanationAr;
  final String? mcqId;

  /// النقاط المفتاحية الفعلية (وضع الاسترجاع الحر) — تُعرض بعد التلخيص.
  final List<String> freeKeyPoints;

  /// يفتح نقطة اعتراض ويستقبل النتيجة {wasCorrect, skipped}.
  static Future<Map<String, Object?>?> show(BuildContext context,
      {required Widget sheet}) {
    return showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  @override
  State<InterceptionSheet> createState() => _InterceptionSheetState();
}

enum InterceptionSource { mcq, check, free }

class _InterceptionSheetState extends State<InterceptionSheet> {
  int? _selected;
  final TextEditingController _freeController = TextEditingController();

  bool get _isCorrect => _selected == widget.correctIndex;
  bool get _isFree => widget.source == InterceptionSource.free;

  Future<void> _answer(int optionIndex) async {
    if (_selected != null) return;
    setState(() => _selected = optionIndex);
    AppHaptics.selection();

    // سجل الإجابة (mcq فقط — التضميني check لا يُسجَّل).
    if (widget.mcqId != null) {
      try {
        await DatabaseHelper.instance.logConfidence(
          questionId: widget.mcqId!,
          confidence: 1, // متأكد افتراضياً (بلا مقياس هنا — إيقاع القراءة).
          wasCorrect: optionIndex == widget.correctIndex,
        );
      } catch (_) {
        // صمت مقصود.
      }
    }
  }

  void _close({required bool wasCorrect, required bool skipped}) {
    Navigator.of(context).pop(<String, Object?>{
      'was_correct': wasCorrect,
      'skipped': skipped,
    });
  }

  @override
  void dispose() {
    _freeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Size size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: size.height * 0.9),
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
                    Icon(Icons.bolt_rounded,
                        size: 20, color: AppColors.gold(b)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'توقّف — لحظة استرجاع',
                      style: AppType.cardTitle.copyWith(fontSize: 17),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'بدون رجوع: جرّب أن تسترجع ما قرأته للتو — الاسترجاع'
                  ' يثبّت أكثر من إعادة القراءة.',
                  style: AppType.body.copyWith(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.textSecondary(b),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── جسم السؤال ──
                if (!_isFree) ...<Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt(b),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.border(b)),
                    ),
                    child: Text(
                      widget.prompt,
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
                  for (int i = 0; i < widget.options.length; i++)
                    ExerciseOptionButton(
                      label: widget.options[i],
                      latin: true,
                      onTap: _selected == null ? () => _answer(i) : null,
                      state: _selected == null
                          ? null
                          : i == widget.correctIndex
                              ? OptionState.correct
                              : i == _selected
                                  ? OptionState.wrong
                                  : OptionState.dimmed,
                    ),
                ] else ...<Widget>[
                  // ── الاسترجاع الحر ──
                  Text(
                    'لخّص بثلاث نقاط: ما النقاط المفتاحية لما قرأته؟',
                    style: AppType.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text(b),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _freeController,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText:
                          'اكتب نقاطك بحرية — لا تُصحَّح، المقارنة ذاتية…',
                      filled: true,
                      fillColor: AppColors.surfaceAlt(b),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.field),
                        borderSide: BorderSide(color: AppColors.border(b)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.field),
                        borderSide: BorderSide(color: AppColors.border(b)),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'قارن بالنقاط الفعلية',
                    onPressed: () => setState(() => _selected = 0),
                  ),
                ],

                // ── الكشف ──
                if (_selected != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  if (!_isFree && _selected != widget.correctIndex) ...<Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer(b),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                          color: AppColors.error(b).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        widget.explanationAr ?? '',
                        style: AppType.body.copyWith(
                          height: 1.7,
                          fontSize: 13.5,
                          color: AppColors.text(b),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_isFree) ...<Widget>[
                    // النقاط الفعلية للتقييم الذاتي.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint(b),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.border(b)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('النقاط الفعلية — قيّم نفسك:',
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.textSecondary(b),
                              )),
                          const SizedBox(height: AppSpacing.sm),
                          for (final String point in widget.freeKeyPoints)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.xs),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(Icons.bolt_rounded,
                                      size: 14,
                                      color: AppColors.gold(b)),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      point,
                                      textDirection: TextDirection.ltr,
                                      textAlign: TextAlign.start,
                                      style: AppType.body.copyWith(
                                        fontSize: 13,
                                        height: 1.5,
                                        fontFamily: AppType.latinFamily,
                                        color: AppColors.text(b),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: () =>
                          _close(wasCorrect: _isFree || _isCorrect, skipped: false),
                      child: Text(
                        'أكمل القراءة',
                        style: AppType.body.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () =>
                          _close(wasCorrect: false, skipped: true),
                      child: Text(
                        'تخطَّ هذه المرة',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
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
