import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/srs_repository.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/widget/home_widget_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// جلسة «المراجعة العشوائية المدروسة» — بطاقات عشوائية من المحاضرات
/// التي **دُرست فعلاً** فقط (getStudiedFlashcards).
///
/// مثل FlashcardSessionPage تماماً: قلب البطاقة + تقييم ذاتي
/// يغذي Leitner + XP — لكن المجموعة عبر الأجهزة/المحاضرات المدروسة،
/// لا وحدة واحدة.
class FlashcardBankSessionPage extends StatefulWidget {
  const FlashcardBankSessionPage({this.system, super.key});

  /// حصر المراجعة على جهاز معين (null = كل الأجهزة).
  final String? system;

  @override
  State<FlashcardBankSessionPage> createState() =>
      _FlashcardBankSessionPageState();
}

class _FlashcardBankSessionPageState extends State<FlashcardBankSessionPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, Object?>> _cards = const <Map<String, Object?>>[];
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
      final List<Map<String, Object?>> cards =
          await DatabaseHelper.instance.getStudiedFlashcards(
        system: widget.system,
      );
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل بطاقات المراجعة.';
        _loading = false;
      });
    }
  }

  Future<void> _answer(bool knew) async {
    final Map<String, Object?> card = _cards[_index];
    final String cardId = card['id']! as String;

    // تغذية SRS (Leitner) + XP — مثل الجلسة العادية تماماً.
    try {
      await SrsRepository.recordAnswer(cardId, knew);
      await DatabaseHelper.instance.addXpEvent(
        kind: XpEventKind.flashcard,
        refId: cardId,
        xp: knew ? 3 : 1,
      );
    } catch (_) {
      // صمت مقصود — الجلسة لا تتوقف لفشل تسجيل.
    }

    setState(() {
      knew ? _known++ : _unknown++;
      _revealed = false;
    });

    // تحديث ويدجت الشاشة الرئيسية — تغيّر عدد المستحق.
    unawaited(HomeWidgetService.refresh());

    if (_index + 1 >= _cards.length) {
      await _finish();
    } else {
      setState(() => _index++);
    }
  }

  Future<void> _finish() async {
    try {
      await DatabaseHelper.instance.grantDailyStreakBonus();
      await DatabaseHelper.instance.unlockEarnedBadges();
    } catch (_) {
      // صمت مقصود.
    }
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
                      title: 'لا بطاقات مدروسة بعد',
                      subtitle:
                          'أكمل أي جلسة بطاقات أولاً ثم عد للمراجعة الذكية',
                    )
                  : _buildCard(b),
    );
  }

  Widget _buildCard(Brightness b) {
    final Map<String, Object?> card = _cards[_index];

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: ProgressBar(
            progress: (_index + (_revealed ? 0.5 : 0)) / _cards.length,
            height: 6,
            color: AppColors.primary(b),
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
                      if (!_revealed) ...<Widget>[
                        Center(
                          child: Icon(Icons.auto_awesome_rounded,
                              size: 40, color: AppColors.primary(b)),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          card['front_text']! as String,
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
                                color: AppColors.textSecondary(b)),
                          ),
                        ),
                      ] else ...<Widget>[
                        Text(
                          card['back_text']! as String,
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
                        if ((card['mnemonic_ar'] as String?)
                                ?.isNotEmpty ??
                            false) ...<Widget>[
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: <Widget>[
                              Icon(Icons.lightbulb_rounded,
                                  size: 18, color: AppColors.gold(b)),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  card['mnemonic_ar']! as String,
                                  style: AppType.body.copyWith(
                                      fontSize: 13.5,
                                      color: AppColors.textSecondary(b)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if ((card['explanation_ar'] as String?)
                                ?.isNotEmpty ??
                            false) ...<Widget>[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            card['explanation_ar']! as String,
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
