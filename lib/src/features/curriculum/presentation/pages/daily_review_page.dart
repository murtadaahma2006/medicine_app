import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/srs_repository.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة «مراجعة اليوم» — قشرة رقيقة فوق [FlashcardSessionHost]:
/// جرعة البطاقات المستحقة عبر كل الوحدات (SRS Leitner).
///
/// بلا محرّك المكافأة (البطاقة تُراجع لا تُزرع) + شارة Box n/5
/// على البطاقة — سلوك جلسة SRS الخالصة.
class DailyReviewPage extends StatelessWidget {
  const DailyReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return FlashcardSessionHost(
      title: 'مراجعة اليوم',
      loadCards: () async {
        // المضيف يعمل على rows — نحول بطاقات SRS إلى نفس العقد.
        final List<SrsCard> cards = await SrsRepository.dueToday();
        return <Map<String, Object?>>[
          for (final SrsCard card in cards)
            <String, Object?>{
              'id': card.cardId,
              'front_text': card.frontText,
              'back_text': card.backText,
              'explanation_ar': null,
              'mnemonic_ar': null,
              '__box': card.box,
            },
        ];
      },
      onAnswer: (String cardId, bool knew, bool lucky) async {
        await SrsRepository.recordAnswer(cardId, knew);
        await DatabaseHelper.instance.addXpEvent(
          kind: XpEventKind.review,
          refId: cardId,
          xp: knew ? 3 : 1,
        );
      },
      emptyIcon: Icons.celebration_rounded,
      emptyTitle: 'عقلك رتّب كل شيء اليوم! 🧠',
      emptySubtitle: 'لا بطاقات مستحقة للمراجعة — التثبيت يعمل بصمت'
          ' خلف الكواليس، والذاكرة تبني نفسها الآن.',
      useRewardEngine: false,
      showBoxChip: true,
      progressColor: AppColors.gold(b),
    );
  }
}
