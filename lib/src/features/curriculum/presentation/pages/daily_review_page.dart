import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/srs_repository.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة «مراجعة اليوم» — الجرعة اليومية من بطاقات SRS المستحقة
/// (كل الوحدات)، بنفس نمط جلسة البطاقات: قلب ثم تقييم ذاتي.
class DailyReviewPage extends StatefulWidget {
  const DailyReviewPage({super.key});

  @override
  State<DailyReviewPage> createState() => _DailyReviewPageState();
}

class _DailyReviewPageState extends State<DailyReviewPage> {
  bool _loading = true;
  String? _error;

  List<SrsCard> _cards = const [];
  int _index = 0;
  bool _revealed = false;
  int _known = 0;
  int _unknown = 0;

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
      final List<SrsCard> cards = await SrsRepository.dueToday(limit: 50);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل المراجعة.';
        _loading = false;
      });
    }
  }

  Future<void> _answer(bool knew) async {
    final SrsCard card = _cards[_index];

    try {
      await SrsRepository.recordAnswer(card.cardId, knew);
      await DatabaseHelper.instance.addXpEvent(
        kind: XpEventKind.review,
        refId: card.cardId,
        xp: knew ? 3 : 1,
      );
    } catch (_) {
      // صمت مقصود.
    }

    setState(() {
      knew ? _known++ : _unknown++;
      _revealed = false;
    });

    if (_index + 1 >= _cards.length) {
      try {
        await DatabaseHelper.instance.grantDailyStreakBonus();
        await DatabaseHelper.instance.unlockEarnedBadges();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      setState(() => _index++);
    }
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
          'مراجعة اليوم',
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
              : _cards.isEmpty
                  ? EmptyState(
                      icon: Icons.celebration_rounded,
                      mascot: 'peaceful',
                      title: 'عقلك رتّب كل شيء اليوم! 🧠',
                      subtitle:
                          'لا بطاقات مستحقة للمراجعة — التثبيت يعمل بصمت'
                          ' خلف الكواليس، والذاكرة تبني نفسها الآن.',
                    )
                  : _buildBody(b),
    );
  }

  Widget _buildBody(Brightness b) {
    final SrsCard card = _cards[_index];

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              Expanded(
                child: ProgressBar(
                  progress: _index / _cards.length,
                  height: 6,
                  color: AppColors.gold(b),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '${_index + 1}/${_cards.length}',
                textDirection: TextDirection.ltr,
                style: AppType.caption
                    .copyWith(fontWeight: FontWeight.w800, color: AppColors.text(b)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: GestureDetector(
                onTap: () {
                  AppHaptics.selection();
                  setState(() => _revealed = !_revealed);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  decoration: BoxDecoration(
                    color: _revealed
                        ? AppColors.successContainer(b)
                        : AppColors.surface(b),
                    borderRadius: BorderRadius.circular(AppRadius.card + 4),
                    border: Border.all(
                      color: _revealed
                          ? AppColors.success(b).withValues(alpha: 0.5)
                          : AppColors.border(b),
                      width: _revealed ? 2 : 1,
                    ),
                    boxShadow: AppShadows.card(b),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.layers_rounded,
                              size: 14, color: AppColors.gold(b)),
                          const SizedBox(width: 4),
                          Text(
                            'Box ${card.box}/5',
                            textDirection: TextDirection.ltr,
                            style: AppType.caption.copyWith(
                                fontFamily: AppType.latinFamily,
                                color: AppColors.textSecondary(b)),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (!_revealed)
                        Text(
                          card.frontText,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          style: AppType.termWord.copyWith(
                            fontSize: 20,
                            height: 1.5,
                            color: AppColors.text(b),
                          ),
                        )
                      else
                        Text(
                          card.backText,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: AppType.body.copyWith(
                            fontSize: 16,
                            height: 1.7,
                            fontFamily: AppType.latinFamily,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text(b),
                          ),
                        ),
                      if (!_revealed) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        Center(
                          child: Text(
                            'انقر للكشف',
                            style: AppType.caption.copyWith(
                                color: AppColors.textSecondary(b)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: _revealed
              ? Row(
                  children: <Widget>[
                    Expanded(
                      child: AppButton(
                        label: 'لم أعرفها',
                        icon: Icons.close_rounded,
                        type: AppButtonType.secondary,
                        onPressed: () => _answer(false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppButton(
                        label: 'عرفتها',
                        icon: Icons.check_rounded,
                        onPressed: () => _answer(true),
                      ),
                    ),
                  ],
                )
              : AppButton(
                  label: 'اكشف الإجابة',
                  icon: Icons.flip_rounded,
                  onPressed: () {
                    AppHaptics.selection();
                    setState(() => _revealed = true);
                  },
                ),
        ),
      ],
    );
  }
}
