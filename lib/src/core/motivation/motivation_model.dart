import 'package:flutter/foundation.dart';

/// مستويات المتعلم — تُشتق من مجموع نقاط الخبرة.
enum LearnerLevel {
  beginner(0, 'مبتدئ', '🌱'),
  explorer(100, 'مستكشف', '🧭'),
  builder(300, 'باني المهارة', '🧱'),
  confident(700, 'واثق', '💪'),
  advanced(1500, 'متقدم', '🚀');

  const LearnerLevel(this.minXp, this.titleAr, this.emoji);

  /// الحد الأدنى لنقاط الخبرة للوصول لهذا المستوى.
  final int minXp;
  final String titleAr;
  final String emoji;

  static LearnerLevel forXp(int xp) {
    LearnerLevel result = LearnerLevel.beginner;
    for (final LearnerLevel level in LearnerLevel.values) {
      if (xp >= level.minXp) result = level;
    }
    return result;
  }

  /// المستوى التالي أو null إن كان هذا هو الأقصى.
  LearnerLevel? get next {
    final List<LearnerLevel> all = LearnerLevel.values;
    final int i = all.indexOf(this);
    return i + 1 < all.length ? all[i + 1] : null;
  }

  /// التقدم نحو المستوى التالي (0.0–1.0). 1.0 عند المستوى الأقصى.
  double progressToNext(int xp) {
    final LearnerLevel? nxt = next;
    if (nxt == null) return 1.0;
    final int span = nxt.minXp - minXp;
    return ((xp - minXp) / span).clamp(0.0, 1.0);
  }
}

/// تعريفات الشارات — شروطها تُقيَّم على [MotivationSnapshot].
@immutable
class BadgeDef {
  const BadgeDef({
    required this.id,
    required this.titleAr,
    required this.descriptionAr,
    required this.emoji,
    required this.condition,
  });

  final String id;
  final String titleAr;
  final String descriptionAr;
  final String emoji;

  /// هل تحقق شرط الشارة على اللقطة الحالية؟
  final bool Function(MotivationSnapshot snapshot) condition;

  // الإغلاقات لا تقبل const — لذا القائمة نهائية لا ثابتة.
  static final List<BadgeDef> all = <BadgeDef>[
    BadgeDef(
      id: 'first-concept',
      titleAr: 'الخطوة الأولى',
      descriptionAr: 'أكملت أول شرح طبي',
      emoji: '👣',
      condition: (MotivationSnapshot s) => s.completedLessons >= 1,
    ),
    BadgeDef(
      id: 'concepts-3',
      titleAr: 'ثلاثية الفهم',
      descriptionAr: 'أكملت 3 شروحات',
      emoji: '📚',
      condition: (MotivationSnapshot s) => s.completedLessons >= 3,
    ),
    BadgeDef(
      id: 'flashcards-25',
      titleAr: 'جامع البطاقات',
      descriptionAr: 'راجعت حتى اكتملت 25 بطاقة',
      emoji: '🃏',
      condition: (MotivationSnapshot s) => s.completedVocabSets >= 5,
    ),
    BadgeDef(
      id: 'perfect-mcq',
      titleAr: 'علامة كاملة',
      descriptionAr: 'جلسة أسئلة بنسبة 100%',
      emoji: '💯',
      condition: (MotivationSnapshot s) => s.perfectMcqSessions >= 1,
    ),
    BadgeDef(
      id: 'case-master',
      titleAr: 'طبيب الحالات',
      descriptionAr: '10 قرارات سريرية صحيحة',
      emoji: '🩺',
      condition: (MotivationSnapshot s) => s.correctCaseSteps >= 10,
    ),
    BadgeDef(
      id: 'streak-3',
      titleAr: 'شرارة الثلاثة',
      descriptionAr: 'درست في 3 أيام متتابعة',
      emoji: '🔥',
      condition: (MotivationSnapshot s) => s.currentStreak >= 3,
    ),
    BadgeDef(
      id: 'streak-7',
      titleAr: 'أسبوع بلا انقطاع',
      descriptionAr: 'درست في 7 أيام متتابعة',
      emoji: '⚡',
      condition: (MotivationSnapshot s) => s.longestStreak >= 7,
    ),
    BadgeDef(
      id: 'xp-500',
      titleAr: 'نجم الخبرة',
      descriptionAr: 'جمعت 500 نقطة خبرة',
      emoji: '⭐',
      condition: (MotivationSnapshot s) => s.totalXp >= 500,
    ),
  ];
}

/// لقطة لحالة تحفيز المتعلم في لحظة ما — مدخل تقييم الشارات.
@immutable
class MotivationSnapshot {
  const MotivationSnapshot({
    required this.totalXp,
    required this.currentStreak,
    required this.longestStreak,
    required this.completedLessons,
    required this.completedVocabSets,
    required this.perfectMcqSessions,
    required this.correctCaseSteps,
    required this.unlockedBadgeIds,
  });

  final int totalXp;

  /// السلسلة اليومية الحالية (أيام متتابعة فيها نشاط).
  final int currentStreak;

  /// أطول سلسلة في التاريخ.
  final int longestStreak;

  final int completedLessons;
  final int completedVocabSets;

  /// جلسات اختيار من متعدد اكتملت بنسبة 100%.
  final int perfectMcqSessions;

  /// القرارات السريرية الصحيحة تراكمياً.
  final int correctCaseSteps;

  final Set<String> unlockedBadgeIds;

  /// الشارات المستحقة وغير المفتوحة بعد.
  Iterable<BadgeDef> newlyEarned() => BadgeDef.all
      .where((BadgeDef b) => !unlockedBadgeIds.contains(b.id))
      .where((BadgeDef b) => b.condition(this));

  /// كل الشارات مع حالة الفتح (مفتوحة/مقفلة) — لشبكة الشارات.
  List<(BadgeDef, bool)> badgeStates() => BadgeDef.all
      .map((BadgeDef b) => (b, unlockedBadgeIds.contains(b.id)))
      .toList();
}
