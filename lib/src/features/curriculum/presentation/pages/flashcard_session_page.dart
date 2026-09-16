import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/user_progress.dart';
import '../../../../shared/widgets/widgets.dart';

/// جلسة بطاقات وحدة واحدة — قشرة رقيقة فوق [FlashcardSessionHost]:
/// تمرر بطاقات الوحدة + كتابة التقدم الختامية (flashcard_set × unitId).
///
/// القلب والتقييم الذاتي وXP وSRS والاحتفالات — كلها في المضيف.
class FlashcardSessionPage extends StatelessWidget {
  const FlashcardSessionPage({required this.unitId, super.key});

  final String unitId;

  @override
  Widget build(BuildContext context) {
    return FlashcardSessionHost(
      title: 'جلسة البطاقات',
      loadCards: () =>
          DatabaseHelper.instance.getFlashcardsForUnit(unitId),
      emptyTitle: 'لا بطاقات في هذه المحاضرة',
      emptySubtitle: 'ستظهر هنا متى توفر المحتوى',
      onFinish: () async {
        // تمييز مجموعة البطاقات كمكتملة (مفتاح user_progress القياسي).
        await DatabaseHelper.instance.upsertProgress(UserProgress(
          itemType: ProgressItemType.flashcardSet,
          itemId: unitId,
          status: ProgressStatus.completed,
          timesReviewed: 1,
          score: null,
          lastPracticedAt: DateTime.now().toUtc().toIso8601String(),
        ));
      },
    );
  }
}
