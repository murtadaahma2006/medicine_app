import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/srs_repository.dart';
import '../../../../core/database/user_progress.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../core/motivation/reward_engine.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/widget/home_widget_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// جلسة بطاقات وحدة واحدة — قلب البطاقة (سؤال إنجليزي ← إجابة إنجليزية)
/// ثم تقييم ذاتي: «عرفتها» / «لم أعرفها» يغذي خوارزمية Leitner مباشرة.
///
/// التقدم يُسجل في user_progress (flashcard_set × unitId) عند اكتمال
/// كل البطاقات، وXP يُمنح لكل بطاقة.
class FlashcardSessionPage extends StatefulWidget {
  const FlashcardSessionPage({required this.unitId, super.key});

  final String unitId;

  @override
  State<FlashcardSessionPage> createState() => _FlashcardSessionPageState();
}

class _FlashcardSessionPageState extends State<FlashcardSessionPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, Object?>> _cards = const [];
  int _index = 0;
  bool _revealed = false;
  int _known = 0;
  int _unknown = 0;

  // ── محرّك المكافأة الطبقي (المقترح 4) ──
  int _streak = 0;
  bool _luckyStrike = false;

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
      final List<Map<String, Object?>> cards =
          await DatabaseHelper.instance.getFlashcardsForUnit(widget.unitId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل البطاقات.';
        _loading = false;
      });
    }
  }

  Future<void> _answer(bool knew) async {
    final Map<String, Object?> card = _cards[_index];
    final String cardId = card['id']! as String;

    // ── محرّك المكافأة: لمسيات + ضربة حمراء (على «عرفتها» فقط —
    // الخطأ لا يُكافأ) + مضاعف التسارع قرب نهاية الجرعة ──
    bool lucky = false;
    if (knew) {
      lucky = RewardEngine.onAnswer(correct: true, streak: _streak);
      _streak++;
    } else {
      _streak = 0;
      AppHaptics.light();
    }

    // (أ) تغذية SRS فوراً — خوارزمية Leitner.
    try {
      await SrsRepository.recordAnswer(cardId, knew);
      await DatabaseHelper.instance.addXpEvent(
        kind: XpEventKind.flashcard,
        refId: cardId,
        // مضاعف التسارع (1.0/1.25/1.5 حسب الموضع) + ضربة ×2 —
        // الأساس 3 للمعروفة و1 للفاشلة (نفس السلوك القديم).
        xp: RewardEngine.grantXp(
          base: knew ? 3 : 1,
          done: _index + 1,
          total: _cards.length,
          luckyStrike: lucky,
        ),
      );
    } catch (_) {
      // صمت مقصود — الجلسة لا تتوقف لفشل تسجيل.
    }

    setState(() {
      knew ? _known++ : _unknown++;
      _revealed = false;
      _luckyStrike = knew && lucky;
    });

    // شارة الضربة تتلاشى بعد لحظة.
    if (knew && lucky) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _luckyStrike = false);
      });
    }

    // آخر بطاقة: إنهاء الجلسة.
    if (_index + 1 >= _cards.length) {
      await _finishSession();
    } else {
      setState(() => _index++);
      // تحديث ويدجت الشاشة الرئيسية — تغيّر عدد المستحق.
      unawaited(HomeWidgetService.refresh());
    }
  }

  Future<void> _finishSession() async {
    // تمييز مجموعة البطاقات كمكتملة (مفتاح user_progress القياسي).
    try {
      await DatabaseHelper.instance.upsertProgress(UserProgress(
        itemType: ProgressItemType.flashcardSet,
        itemId: widget.unitId,
        status: ProgressStatus.completed,
        timesReviewed: 1,
        score: _cards.isEmpty
            ? null
            : ((_known / _cards.length) * 100).round(),
        lastPracticedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      await DatabaseHelper.instance.grantDailyStreakBonus();
      await DatabaseHelper.instance.unlockEarnedBadges();
    } catch (_) {
      // صمت مقصود.
    }

    // تحديث ويدجت الشاشة الرئيسية — إنجاز اليوم + المستحق الجديد.
    unawaited(HomeWidgetService.refresh());

    if (!mounted) return;
    Navigator.of(context).pop();
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
          '${_index + 1} / ${_cards.length}',
          textDirection: TextDirection.ltr,
          style: AppType.caption
              .copyWith(fontWeight: FontWeight.w800, color: AppColors.text(b)),
        ),
        centerTitle: true,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              child: Row(
                children: <Widget>[
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.success(b)),
                  const SizedBox(width: 2),
                  Text('$_known',
                      textDirection: TextDirection.ltr,
                      style: AppType.caption
                          .copyWith(color: AppColors.success(b))),
                  const SizedBox(width: AppSpacing.md),
                  Icon(Icons.cancel_rounded,
                      size: 16, color: AppColors.error(b)),
                  const SizedBox(width: 2),
                  Text('$_unknown',
                      textDirection: TextDirection.ltr,
                      style: AppType.caption
                          .copyWith(color: AppColors.error(b))),
                ],
              ),
            ),
          ),
        ],
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
                  ? const EmptyState(
                      icon: Icons.style_rounded,
                      title: 'لا بطاقات في هذه المحاضرة',
                      subtitle: 'ستظهر هنا متى توفر المحتوى',
                    )
                  : _buildCard(b),
    );
  }

  Widget _buildCard(Brightness b) {
    final Map<String, Object?> card = _cards[_index];

    return Column(
      children: <Widget>[
        // ── شريط التقدم — البداية المزيفة (يبدأ من 15%) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: ProgressBar(
            progress: RewardEngine.displayProgress(
              (_index + (_revealed ? 0.5 : 0)) / _cards.length,
            ),
            height: 6,
            color: AppColors.primary(b),
          ),
        ),

        // ── شارة الضربة الحمراء الومضية ──
        if (_luckyStrike)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppGradients.gold),
                borderRadius: BorderRadius.circular(AppRadius.pill),
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

        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _FlipCard(
                front: card['front_text']! as String,
                back: card['back_text']! as String,
                explanationAr: card['explanation_ar'] as String?,
                mnemonicAr: card['mnemonic_ar'] as String?,
                revealed: _revealed,
                onToggle: () {
                  AppHaptics.selection();
                  setState(() => _revealed = !_revealed);
                },
              ),
            ),
          ),
        ),

        // ── أزرار التقييم الذاتي ──
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

/// البطاقة القلابة: الوجه سؤال، الظهر إجابة + شرح عربي اختياري.
class _FlipCard extends StatelessWidget {
  const _FlipCard({
    required this.front,
    required this.back,
    required this.revealed,
    required this.onToggle,
    this.explanationAr,
    this.mnemonicAr,
  });

  final String front;
  final String back;
  final String? explanationAr;
  final String? mnemonicAr;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          color: revealed ? AppColors.successContainer(b) : AppColors.surface(b),
          borderRadius: BorderRadius.circular(AppRadius.card + 4),
          border: Border.all(
            color: revealed
                ? AppColors.success(b).withValues(alpha: 0.5)
                : AppColors.border(b),
            width: revealed ? 2 : 1,
          ),
          boxShadow: AppShadows.card(b),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!revealed) ...<Widget>[
              Center(
                child: Icon(Icons.help_outline_rounded,
                    size: 40, color: AppColors.primary(b)),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                front,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: AppType.termWord.copyWith(
                  fontSize: 21,
                  height: 1.5,
                  color: AppColors.text(b),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Text(
                  'انقر للكشف',
                  style: AppType.caption
                      .copyWith(color: AppColors.textSecondary(b)),
                ),
              ),
            ] else ...<Widget>[
              Text(
                back,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                style: AppType.body.copyWith(
                  fontSize: 16.5,
                  height: 1.7,
                  fontFamily: AppType.latinFamily,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text(b),
                ),
              ),
              if ((mnemonicAr ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Icon(Icons.lightbulb_rounded,
                        size: 18, color: AppColors.gold(b)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        mnemonicAr!,
                        style: AppType.body.copyWith(
                            fontSize: 13.5,
                            color: AppColors.textSecondary(b)),
                      ),
                    ),
                  ],
                ),
              ],
              if ((explanationAr ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  explanationAr!,
                  style: AppType.body.copyWith(
                      fontSize: 13.5,
                      height: 1.6,
                      color: AppColors.textSecondary(b)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
