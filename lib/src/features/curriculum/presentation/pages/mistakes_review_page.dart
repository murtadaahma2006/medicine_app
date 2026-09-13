import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة «راجع أخطاءك» لوحدة واحدة — تحليل حقيقي من سجل corrections:
/// أسوأ الأسئلة (الأكثر خطأً) مع آخر إجابة خاطئة والإجابة الصحيحة.
///
/// تجمع سجلَي التدريب الحر (mcq-) والتقييم الرسمي (assess-) للوحدة.
class MistakesReviewPage extends StatefulWidget {
  const MistakesReviewPage({required this.unitId, super.key});

  final String unitId;

  @override
  State<MistakesReviewPage> createState() => _MistakesReviewPageState();
}

class _MistakesReviewPageState extends State<MistakesReviewPage> {
  bool _loading = true;
  String? _error;

  /// سؤال → عدد الأخطاء (من كلتا البادرتين).
  final Map<String, int> _wrongCounts = <String, int>{};

  /// سؤال → تفاصيل آخر خطأ.
  final Map<String, Map<String, Object?>> _latestWrong = <String, Map<String, Object?>>{};

  /// سؤال → نص السؤال الإنجليزي من mcq_bank (قد يكون السؤال MCQ أو خطوة حالة).
  final Map<String, String> _prompts = <String, String>{};

  int _totalAttempts = 0;
  int _totalWrong = 0;

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

      _wrongCounts.clear();
      _latestWrong.clear();
      _prompts.clear();
      _totalAttempts = 0;
      _totalWrong = 0;

      // سجل الجلستين: التدريب الحر والتقييم الرسمي.
      for (final String prefix in <String>[
        'mcq-${widget.unitId}',
        'assess-${widget.unitId}',
        'case-%',
      ]) {
        final bool isCasePattern = prefix == 'case-%';

        // عدد المحاولات والأخطاء.
        _totalAttempts += await db.rawCount(
          'SELECT COUNT(*) FROM ${DatabaseHelper.tableCorrections} '
          'WHERE drill_id LIKE ?',
          <Object?>[isCasePattern ? 'case-%' : prefix],
        );

        // آخر محاولة خاطئة لكل سؤال (استعلام موحد في database_helper).
        final List<Map<String, Object?>> wrongs = await db
            .latestWrongAttempts(
          isCasePattern ? 'case-%' : prefix,
          limit: 50,
        );
        _totalWrong += wrongs.length;
        for (final Map<String, Object?> row in wrongs) {
          final String qid = row['question_id']! as String;
          _latestWrong[qid] = row;
        }

        // أسوأ الأسئلة مرتبة.
        final List<MapEntry<String, int>> weakest =
            await db.weakestQuestions(
          isCasePattern ? 'case-%' : prefix,
          limit: 50,
        );
        for (final MapEntry<String, int> e in weakest) {
          _wrongCounts[e.key] = (_wrongCounts[e.key] ?? 0) + e.value;
        }
      }

      // جلب نصوص الأسئلة من بنك MCQ (لأسئلة البنك مباشرة).
      final List<Map<String, Object?>> mcqs =
          await db.getMcqsForUnit(widget.unitId);
      for (final Map<String, Object?> q in mcqs) {
        _prompts[q['id']! as String] = q['question_stem']! as String;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحليل الأخطاء.';
        _loading = false;
      });
    }
  }

  /// أشرطة السجل مرتبة تنازلياً حسب عدد الأخطاء.
  List<MapEntry<String, int>> get _sorted =>
      _wrongCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        backgroundColor: AppColors.background(b),
        title: Text(
          'راجع أخطاءك',
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
              : _sorted.isEmpty
                  ? const EmptyState(
                      icon: Icons.celebration_rounded,
                      mascot: 'proud',
                      title: 'صحتك الفكرية ممتازة!',
                      subtitle:
                          'لا أخطاء متبقية للمراجعة — إما لم تتمرن بعد'
                          ' أو إجاباتك كلها صحيحة. استمر بهذا الإيقاع!',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.lg,
                        ),
                        children: <Widget>[
                          // ── ملخص إحصائي ──
                          _SummaryRow(
                            attempts: _totalAttempts,
                            wrong: _totalWrong,
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // ── بطاقات الأسوأ ──
                          for (final MapEntry<String, int> entry in _sorted)
                            _MistakeCard(
                              questionId: entry.key,
                              times: entry.value,
                              prompt: _prompts[entry.key] ??
                                  _latestWrong[entry.key]?['question_id']
                                      as String? ??
                                  entry.key,
                              latest: _latestWrong[entry.key],
                            ),
                          const SizedBox(height: AppSpacing.xxxl),
                        ],
                      ),
                    ),
    );
  }
}

/// صف ملخص: محاولات مقابل أخطاء.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.attempts, required this.wrong});

  final int attempts;
  final int wrong;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Row(
      children: <Widget>[
        Expanded(
          child: StatTile(
            icon: Icons.quiz_rounded,
            value: '$attempts',
            label: 'إجابة مسجلة',
            tint: AppColors.primary(b),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            icon: Icons.cancel_rounded,
            value: '$wrong',
            label: 'إجابة خاطئة',
            tint: AppColors.error(b),
          ),
        ),
      ],
    );
  }
}

/// بطاقة خطأ واحد: السؤال + آخر إجابة خاطئة مقابل الصحيحة.
class _MistakeCard extends StatelessWidget {
  const _MistakeCard({
    required this.questionId,
    required this.times,
    required this.prompt,
    required this.latest,
  });

  final String questionId;
  final int times;
  final String prompt;
  final Map<String, Object?>? latest;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        accent: AppColors.error(b),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_outline_rounded,
                    size: 18, color: AppColors.error(b)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'أخطيت $times ${times == 1 ? 'مرة' : 'مرات'}',
                  style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.error(b)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              prompt,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.body.copyWith(
                fontSize: 14,
                height: 1.6,
                fontFamily: AppType.latinFamily,
                fontWeight: FontWeight.w600,
                color: AppColors.text(b),
              ),
            ),
            if (latest != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _AnswerRow(
                icon: Icons.close_rounded,
                color: AppColors.error(b),
                label: 'إجابتك',
                text: (latest!['user_answer'] as String?) ?? '',
              ),
              _AnswerRow(
                icon: Icons.check_rounded,
                color: AppColors.success(b),
                label: 'الصحيحة',
                text: (latest!['correct_answer'] as String?) ?? '',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// سطر إجابة واحد (خاطئة/صحيحة).
class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$label: ',
            style: AppType.caption
                .copyWith(color: AppColors.textSecondary(b)),
          ),
          Expanded(
            child: Text(
              text,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              style: AppType.body.copyWith(
                  fontSize: 13,
                  fontFamily: AppType.latinFamily,
                  color: AppColors.text(b)),
            ),
          ),
        ],
      ),
    );
  }
}
