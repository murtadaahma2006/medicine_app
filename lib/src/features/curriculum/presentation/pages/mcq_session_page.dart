import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/database/correction.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/user_progress.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../core/motivation/celebration_queue.dart';
import '../../../../core/motivation/flow_channel_controller.dart';
import '../../../../core/motivation/reward_engine.dart';
import '../../../../core/notifications/pin_expiry_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../../../core/widget/home_widget_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// جلسة أسئلة MCQ لوحدة واحدة: سؤال إنجليزي + خيارات نصية + شرح عربي
/// بعد كل إجابة. سجل الإجابات يُخزن في corrections وXP يُمنح للصحيحة.
///
/// نمطان عبر [isAssessment]:
/// - تدريب حر (افتراضي): مفتاح mcq-·unitId·، يكتمل أياً كانت النتيجة.
/// - التقييم الرسمي: مفتاح assess-·unitId· (ما يقرأه الخط الزمني)،
///   اجتياز من 70٪، مكافأة +20 XP، وشاشة النتيجة الموحدة ختاماً.
///
/// **محرّك المكافأة الطبقي (المقترح 4)**:
/// - الضربة الحمراء ×2 (12%) — مفاجأة نقية بنمط لمسي مركب.
/// - مضاعف التسارع — XP يزيد قرب نهاية الجرعة (1.0/1.25/1.5).
/// - وميض «منطقة الاندفاع» عند 70% + نبضة لمسية واحدة.
/// - البداية المزيفة — الشريط يبدأ من 15%.
/// - قناة الـ 85% — الصعوبة التكيفية بلا إعلان (سوى التدريب الحر).
class McqSessionPage extends StatefulWidget {
  const McqSessionPage({
    required this.unitId,
    this.isAssessment = false,
    super.key,
  });

  final String unitId;

  /// هل هذه جلسة التقييم الرسمية للوحدة؟
  final bool isAssessment;

  @override
  State<McqSessionPage> createState() => _McqSessionPageState();
}

class _McqSessionPageState extends State<McqSessionPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, Object?>> _questions = const [];
  int _index = 0;

  /// الخيار المختار لكل سؤال — null = لم يجب بعد.
  int? _selected;
  bool? _lastAnswerCorrect;

  int _correctCount = 0;
  final List<Correction> _corrections = <Correction>[];

  // ── محرّك المكافأة الطبقي ──
  final FlowChannelController _flow = FlowChannelController();
  int _streak = 0;

  /// شارة الضربة الحمراء الومضية — تعرض مرة ثم تتلاشى.
  bool _luckyStrike = false;

  /// وميض حدود «منطقة الاندفاع» عند 70% — مرة واحدة فقط.
  bool _sprintFlash = false;
  bool _sprintFired = false;

  String get _drillKey =>
      widget.isAssessment ? 'assess-${widget.unitId}' : 'mcq-${widget.unitId}';

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
      // الصعوبة التكيفية (سوى التقييم الرسمي — تقييم ثابت العناصر):
      // الجرعة تُرتَّب حسب إشارة القناة الحالية «وتحس» فقط.
      final List<Map<String, Object?>> questions = widget.isAssessment
          ? await DatabaseHelper.instance.getMcqsForUnit(widget.unitId)
          : await DatabaseHelper.instance.getMcqsForUnitAdaptive(
              widget.unitId,
              RewardEngine.difficultyOrderWeight(_flow.signal),
            );
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الأسئلة.';
        _loading = false;
      });
    }
  }

  List<String> _optionsOf(Map<String, Object?> q) {
    try {
      final dynamic decoded = jsonDecode(q['options_json']! as String);
      if (decoded is List) {
        return decoded.map((dynamic s) => s.toString()).toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> _select(int optionIndex) async {
    if (_selected != null) return; // أُجيب بالفعل.

    final Map<String, Object?> q = _questions[_index];
    final int correctIndex = (q['correct_index'] as num?)?.toInt() ?? 0;
    final bool isCorrect = optionIndex == correctIndex;
    final List<String> options = _optionsOf(q);

    // ── محرّك المكافأة: لمسيات + ضربة حمراء محتملة ──
    final bool lucky = RewardEngine.onAnswer(
      correct: isCorrect,
      streak: _streak,
    );

    setState(() {
      _selected = optionIndex;
      _lastAnswerCorrect = isCorrect;
      _luckyStrike = isCorrect && lucky;
      if (isCorrect) {
        _correctCount++;
        _streak++;
      } else {
        _streak = 0;
      }
    });

    // ── منطقة الاندفاع: عبور 70% → وميض + نبضة واحدة ──
    final int done = _index + 1;
    if (!_sprintFired &&
        done / _questions.length >= 0.70) {
      _sprintFired = true;
      RewardEngine.onSprintZone();
      setState(() => _sprintFlash = true);
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _sprintFlash = false);
      });
    }

    // ── قناة الـ 85%: تغذية النافذة المتحركة ──
    _flow.record(isCorrect);

    // سجل الإجابة + XP بمضاعف التسارع (والضربة ×2).
    try {
      _corrections.add(Correction(
        drillId: _drillKey,
        questionId: q['id']! as String,
        userAnswer: options.isNotEmpty ? options[optionIndex] : '',
        correctAnswer: options.isNotEmpty ? options[correctIndex] : '',
        isCorrect: isCorrect,
        mistakeType: isCorrect ? MistakeType.exact : MistakeType.wrong,
        attemptedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      if (isCorrect) {
        await DatabaseHelper.instance.addXpEvent(
          kind: XpEventKind.mcq,
          refId: q['id'] as String?,
          xp: RewardEngine.grantXp(
            base: 5,
            done: done,
            total: _questions.length,
            luckyStrike: lucky,
          ),
        );
      }
    } catch (error) {
      // فشل تسجيل الإجابة لا يوقف الجلسة — لكن يُشخَّص بدل الضياع.
      AppErrorLogger.instance.record(type: 'McqAnswer', error: error);
    }
  }

  Future<void> _next() async {
    if (_index + 1 >= _questions.length) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _selected = null;
      _lastAnswerCorrect = null;
    });
  }

  Future<void> _finish() async {
    final int percent = _questions.isEmpty
        ? 0
        : ((_correctCount / _questions.length) * 100).round();
    final bool passed = percent >= 70;

    // لقطة XP قبل الكسب — ل كشف رفع المستوى ختاماً (Motivator).
    final int beforeXp = await Motivator.currentXp();

    try {
      // كل كتابات الختام في معاملة واحدة (Batching): سجل الإجابات +
      // علامة التقدم + مكافأة الاجتياز + السلسلة + الشارات.
      final List<String> newBadges =
          await DatabaseHelper.instance.finalizeSession(
        corrections: _corrections,
        progress: UserProgress(
          itemType: ProgressItemType.drill,
          itemId: _drillKey,
          status: ProgressStatus.completed,
          timesReviewed: 1,
          score: percent,
          lastPracticedAt: DateTime.now().toUtc().toIso8601String(),
        ),
        bonusKind:
            widget.isAssessment && passed ? XpEventKind.assessment : null,
        bonusRefId: widget.unitId,
        bonusXp: widget.isAssessment && passed ? 20 : 0,
      );

      // أهداف اليوم: إتمام المحاضرة → إلغاء التثبيت تلقائياً
      // فتختفي من جدول اليوم وتكتمل حلقة الإنجاز — وإلغاء إشعار
      // انتهاء التثبيت المجدول (+48h) لأن الهدف تحقق قبل انتهائه.
      if (widget.isAssessment && passed) {
        await DatabaseHelper.instance.unpinUnit(widget.unitId);
        await PinExpiryService.cancelExpiryNotification(widget.unitId);
      }

      // الاحتفالات: شارات جديدة + رفع مستوى إن عُبر حدٌّ.
      await Motivator.detectLevelUp(beforeXp, newBadgeIds: newBadges);
    } catch (error) {
      AppErrorLogger.instance.record(
        type: 'McqSession',
        error: error,
      );
    }

    // تحديث ويدجت الشاشة الرئيسية — إنجاز اليوم تغيّر.
    unawaited(HomeWidgetService.refresh());

    if (!mounted) return;

    // رسالة التدريب الحر — تُعرض عبر رسنجر الشاشة الأم قبل أي pop
    // (استخدام context بعد pop = استخدام عنصر مهدم).
    final ScaffoldMessengerState? messenger =
        widget.isAssessment ? null : ScaffoldMessenger.maybeOf(context);

    // التقييم الرسمي: شاشة النتيجة الموحدة ثم إغلاق الجلسة.
    if (widget.isAssessment) {
      await Navigator.of(context).push(MaterialPageRoute<Widget>(
        builder: (_) => ExamResultScreen(
          totalPercent: percent,
          passed: passed,
          sessionTitle: 'اختبار المحاضرة',
          recommendation: passed
              ? 'أتممت التقييم بنجاح — تقدّم للمحاضرة التالية أو عالج أخطاءك.'
              : 'لم تجتز بعد (الحد 70٪) — راجع الشروحات والبطاقات ثم أعد المحاولة.',
          sections: <(String, int)>[
            ('أسئلة صحيحة', percent),
            ('أسئلة خاطئة', 100 - percent),
          ],
          xpEarned: passed ? 20 : 0,
          onExit: () => Navigator.of(context).pop(),
        ),
      ));
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // التدريب الحر: SnackBar بسيطة.
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            passed ? AppColors.success(Brightness.light) : AppColors.gold(Brightness.light),
        content: Text(
          passed
              ? 'أحسنت! النتيجة $percent% ($_correctCount من ${_questions.length})'
              : 'النتيجة: $percent% — راجع أخطاءك وحاول مجدداً',
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
          '${_index + 1} / ${_questions.length}',
          textDirection: TextDirection.ltr,
          style: AppType.caption
              .copyWith(fontWeight: FontWeight.w800, color: AppColors.text(b)),
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
              : _questions.isEmpty
                  ? const EmptyState(
                      icon: Icons.quiz_rounded,
                      title: 'لا أسئلة في هذه المحاضرة',
                      subtitle: 'ستظهر هنا متى توفر المحتوى',
                    )
                  : _buildQuestion(b),
    );
  }

  Widget _buildQuestion(Brightness b) {
    final Map<String, Object?> q = _questions[_index];
    final List<String> options = _optionsOf(q);
    final int correctIndex = (q['correct_index'] as num?)?.toInt() ?? 0;

    // توافق الآيباد: عمود الجلسة لا يتمدد على الشاشات الواسعة —
    // ResponsiveReadingColumn (موبايل: بلا أي أثر — القيد لا يعمل).
    return ResponsiveReadingColumn(
      child: AnimatedContainer(
        // ── وميض «منطقة الاندفاع» — حد أخضر خاطف 200ms عند 70% ──
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          border: _sprintFlash
              ? Border.all(color: AppColors.success(b), width: 2)
              : null,
        ),
        child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: ProgressBar(
                  // البداية المزيفة — الشريط يبدأ من 15% ممتلئاً.
                  progress: RewardEngine.displayProgress(
                    (_index + (_selected != null ? 1 : 0)) / _questions.length,
                  ),
                  height: 6,
                  color: AppColors.primary(b),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // ── شارة الضربة الحمراء الومضية ──
                      if (_luckyStrike)
                        Center(
                          child: AnimatedOpacity(
                            opacity: 1,
                            duration: AppMotion.scaled(
                                context, AppMotion.celebration),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.md),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.xs + 2,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: AppGradients.gold,
                                ),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(Icons.bolt_rounded,
                                      size: 16, color: AppColors.onGold),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    RewardEngine.luckyStrikeLabel,
                                    style: AppType.caption.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.onGold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ── نص السؤال ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surface(b),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.border(b)),
                        ),
                        child: Text(
                          q['question_stem']! as String,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: AppType.body.copyWith(
                            fontSize: 16,
                            height: 1.65,
                            fontFamily: AppType.latinFamily,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text(b),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // ── الخيارات ──
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

                      // ── الشرح العربي بعد الإجابة ──
                      if (_selected != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        _ExplanationCard(
                          explanation: q['explanation_ar']! as String,
                          correct: _lastAnswerCorrect == true,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: _index + 1 >= _questions.length
                              ? 'إنهاء الجلسة'
                              : 'السؤال التالي',
                          trailingIcon: Icons.arrow_back_rounded,
                          onPressed: _next,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// بطاقة الشرح العربي بعد الإجابة.
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
              Icon(
                correct
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                size: 20,
                color: okColor,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                correct ? 'إجابة صحيحة!' : 'إجابة خاطئة',
                style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w800, color: okColor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            explanation,
            style: AppType.body.copyWith(
                height: 1.7, fontSize: 14, color: AppColors.text(b)),
          ),
        ],
      ),
    );
  }
}
