import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../core/database/database_helper.dart';
import '../../core/database/srs_repository.dart';
import '../../core/database/xp_event.dart';
import '../../core/motivation/celebration_queue.dart';
import '../../core/motivation/reward_engine.dart';
import '../../core/utils/app_haptics.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/responsive_layout.dart';
import '../../core/widget/home_widget_service.dart';
import '../../theme/tokens.dart';
import 'widgets.dart';

/// ─────────────────────────────────────────────────────────────────────
/// المضيف الموحّد لجلسات البطاقات — القلب المشترك للشاشات الثلاث:
/// · [FlashcardSessionPage] جلسة وحدة (منهج)
/// · [DailyReviewPage] مراجعة اليوم (SRS مستحق)
/// · [FlashcardBankSessionPage] مراجعة ما دُرس (بنك المكتبة)
///
/// يوفر كامل دورة الجلسة: التحميل → قلب البطاقة → التقييم الذاتي
/// (يغذي Leitner + XP بمضاعف التسارع والضربة الحمراء) → الختام
/// (تقدم اختياري + سلسلة + شارات + احتفالات في معاملة واحدة) →
/// تحديث ويدجت الشاشة الرئيسية.
///
/// الشاشة المضيفة توفر فقط:
/// - [title] عنوان التطبيق.
/// - [loadCards] مصدر البطاقات (row map: id/front_text/back_text/
///   explanation_ar?/mnemonic_ar?).
/// - [onAnswer] رد نداء إجابة (SRS/XP) — الافتراضي معظم الجلسات.
/// - [emptyIcon/emptyTitle/emptySubtitle] حالة الفراغ.
/// - [onFinish] كتابات ختامية إضافية (progress للوحدة مثلاً) —
///   تُدمج مع السلسلة والشارات في معاملة finalizeSession.
/// ─────────────────────────────────────────────────────────────────────
class FlashcardSessionHost extends StatefulWidget {
  const FlashcardSessionHost({
    required this.title,
    required this.loadCards,
    this.onAnswer,
    this.onFinish,
    this.emptyIcon = Icons.style_rounded,
    this.emptyTitle = 'لا بطاقات',
    this.emptySubtitle,
    this.useRewardEngine = true,
    this.showBoxChip = false,
    this.progressColor,
    super.key,
  });

  /// عنوان شريط التطبيق.
  final String title;

  /// مصدر البطاقات — يُستدعى عند التحميل وإعادة المحاولة.
  final Future<List<Map<String, Object?>>> Function() loadCards;

  /// يسجّل إجابة بطاقة (SRS + XP). null = الافتراضي الموحد:
  /// SrsRepository.recordAnswer + XP 3/1 (بمضاعف التسارع إن فعّلناه).
  final Future<void> Function(String cardId, bool knew, bool lucky)? onAnswer;

  /// كتابات ختامية إضافية (progress مستخدم محدَّد) — تُستدعى داخل
  /// مسار الختام قبل السلسلة والشارات.
  final Future<void> Function()? onFinish;

  /// حالة الفراغ.
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptySubtitle;

  /// هل محرّك المكافأة مفعّل (ضربة حمراء + مضاعف تسارع)؟
  /// مراجعة اليوم SRS تعطّله (البطاقة تُراجع لا تُزرع).
  final bool useRewardEngine;

  /// عرض شارة «Box n/5» على البطاقة (جلسة SRS).
  final bool showBoxChip;

  /// لون شريط التقدم — الافتراضي primary.
  final Color? progressColor;

  @override
  State<FlashcardSessionHost> createState() => _FlashcardSessionHostState();
}

class _FlashcardSessionHostState extends State<FlashcardSessionHost> {
  bool _loading = true;
  String? _error;

  List<Map<String, Object?>> _cards = const <Map<String, Object?>>[];
  int _index = 0;
  bool _revealed = false;
  int _known = 0;
  int _unknown = 0;

  // ── محرّك المكافأة الطبقي ──
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
      final List<Map<String, Object?>> cards = await widget.loadCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
      });
    } catch (error) {
      AppErrorLogger.instance.record(
        type: 'FlashcardSessionHost',
        error: error,
      );
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل البطاقات.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _answer(bool knew) async {
    final Map<String, Object?> card = _cards[_index];
    final String cardId = (card['id'] as String?) ?? '';

    // ── محرّك المكافأة: لمسيات + ضربة حمراء (على «عرفتها» فقط) ──
    bool lucky = false;
    if (knew) {
      lucky =
          widget.useRewardEngine
              ? RewardEngine.onAnswer(correct: true, streak: _streak)
              : false;
      _streak++;
    } else {
      _streak = 0;
      AppHaptics.light();
    }

    // (أ) تغذية SRS فوراً + XP بمضاعف التسارع والضربة.
    try {
      if (widget.onAnswer != null) {
        await widget.onAnswer!(cardId, knew, lucky);
      } else {
        await SrsRepository.recordAnswer(cardId, knew);
        await DatabaseHelper.instance.addXpEvent(
          kind: XpEventKind.flashcard,
          refId: cardId,
          xp:
              widget.useRewardEngine
                  ? RewardEngine.grantXp(
                    base: knew ? 3 : 1,
                    done: _index + 1,
                    total: _cards.length,
                    luckyStrike: lucky,
                  )
                  : (knew ? 3 : 1),
        );
      }
    } catch (error) {
      // فشل التسجيل لا يوقف الجلسة — لكن يُشخَّص بدل الضياع.
      AppErrorLogger.instance.record(type: 'FlashcardAnswer', error: error);
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
    final int beforeXp = await Motivator.currentXp();

    // كتابات ختامية إضافية من الشاشة المضيفة (progress محدَّد).
    if (widget.onFinish != null) {
      try {
        await widget.onFinish!();
      } catch (error) {
        AppErrorLogger.instance.record(
          type: 'FlashcardSessionFinish',
          error: error,
        );
      }
    }

    // السلسلة + الشارات في معاملة واحدة (Batching).
    try {
      final List<String> newBadges =
          await DatabaseHelper.instance.finalizeSession();
      await Motivator.detectLevelUp(beforeXp, newBadgeIds: newBadges);
    } catch (error) {
      AppErrorLogger.instance.record(
        type: 'FlashcardSessionFinalize',
        error: error,
      );
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
          widget.title,
          style: AppType.caption.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.text(b),
          ),
        ),
        centerTitle: true,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppColors.success(b),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$_known',
                    textDirection: TextDirection.ltr,
                    style: AppType.caption.copyWith(
                      color: AppColors.success(b),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(
                    Icons.cancel_rounded,
                    size: 16,
                    color: AppColors.error(b),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$_unknown',
                    textDirection: TextDirection.ltr,
                    style: AppType.caption.copyWith(color: AppColors.error(b)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body:
          _loading
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
                icon: widget.emptyIcon,
                title: widget.emptyTitle,
                subtitle: widget.emptySubtitle,
              )
              : _buildBody(b),
    );
  }

  Widget _buildBody(Brightness b) {
    final Map<String, Object?> card = _cards[_index];
    // شارة Box (جلسات SRS) — تأتي من حقل __box في الـrow إن وُجد.
    final int? box =
        widget.showBoxChip ? (card['__box'] as num?)?.toInt() : null;

    // توافق الآيباد: عمود الجلسة لا يتمدد على الشاشات الواسعة —
    // ResponsiveReadingColumn الموحد (موبايل: بلا أي أثر).
    return ResponsiveReadingColumn(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ProgressBar(
                    progress:
                        widget.useRewardEngine
                            ? RewardEngine.displayProgress(
                              (_index + (_revealed ? 0.5 : 0)) / _cards.length,
                            )
                            : (_index + (_revealed ? 0.5 : 0)) / _cards.length,
                    height: 6,
                    color: widget.progressColor ?? AppColors.primary(b),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${_index + 1}/${_cards.length}',
                  textDirection: TextDirection.ltr,
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text(b),
                  ),
                ),
              ],
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
                    const Icon(
                      Icons.bolt_rounded,
                      size: 16,
                      color: AppColors.onGold,
                    ),
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
                child: _HostFlipCard(
                  front: (card['front_text'] as String?) ?? 'بدون سؤال',
                  back: (card['back_text'] as String?) ?? 'بدون إجابة',
                  explanationAr: card['explanation_ar'] as String?,
                  mnemonicAr: card['mnemonic_ar'] as String?,
                  box: box,
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
          SafeArea(
            bottom: true,
            top: false,
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child:
                  _revealed
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
          ),
        ],
      ),
    );
  }
}

/// البطاقة القلابة الموحدة: الوجه سؤال، الظهر إجابة + شروح عربية
/// اختيارية + شارة Box (جلسات SRS).
class _HostFlipCard extends StatelessWidget {
  const _HostFlipCard({
    required this.front,
    required this.back,
    required this.revealed,
    required this.onToggle,
    this.explanationAr,
    this.mnemonicAr,
    this.box,
  });

  final String front;
  final String back;
  final String? explanationAr;
  final String? mnemonicAr;
  final int? box;
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
          color:
              revealed ? AppColors.successContainer(b) : AppColors.surface(b),
          borderRadius: BorderRadius.circular(AppRadius.card + 4),
          border: Border.all(
            color:
                revealed
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
            if (box != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.layers_rounded,
                    size: 14,
                    color: AppColors.gold(b),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Box ${box!}/5',
                    textDirection: TextDirection.ltr,
                    style: AppType.caption.copyWith(
                      fontFamily: AppType.latinFamily,
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (!revealed) ...<Widget>[
              Center(
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 40,
                  color: AppColors.primary(b),
                ),
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
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary(b),
                  ),
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
                    Icon(
                      Icons.lightbulb_rounded,
                      size: 18,
                      color: AppColors.gold(b),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        mnemonicAr!,
                        style: AppType.body.copyWith(
                          fontSize: 13.5,
                          color: AppColors.textSecondary(b),
                        ),
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
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
