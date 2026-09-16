import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';

/// جلسة «المراجعة العشوائية المدروسة» — قشرة رقيقة فوق
/// [FlashcardSessionHost]: بطاقات عشوائية من المحاضرات التي
/// **دُرست فعلاً** فقط (getStudiedFlashcards).
class FlashcardBankSessionPage extends StatelessWidget {
  const FlashcardBankSessionPage({
    this.system,
    this.specialty,
    super.key,
  });

  /// حصر المراجعة على جهاز معين (null = كل الأجهزة).
  final String? system;

  /// v20: حصر المراجعة داخل تخصص سريري واحد (null = الكل).
  final String? specialty;

  @override
  Widget build(BuildContext context) {
    return FlashcardSessionHost(
      title: 'مراجعة مدروسة',
      loadCards: () => DatabaseHelper.instance.getStudiedFlashcards(
        specialty: specialty,
        system: system,
      ),
      emptyTitle: 'لا بطاقات مدروسة بعد',
      emptySubtitle: 'أكمل أي جلسة بطاقات أولاً ثم عد للمراجعة الذكية',
    );
  }
}
