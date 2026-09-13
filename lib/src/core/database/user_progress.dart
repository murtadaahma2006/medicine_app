/// أنواع عناصر التقدم في جدول user_progress.
enum ProgressItemType { lesson, flashcardSet, drill }

String progressItemTypeToCode(ProgressItemType type) => switch (type) {
      ProgressItemType.lesson => 'lesson',
      ProgressItemType.flashcardSet => 'flashcard_set',
      ProgressItemType.drill => 'drill',
    };

ProgressItemType progressItemTypeFromCode(String code) => switch (code) {
      'lesson' => ProgressItemType.lesson,
      'flashcard_set' => ProgressItemType.flashcardSet,
      _ => ProgressItemType.drill,
    };

/// حالات التقدم.
enum ProgressStatus { notStarted, inProgress, completed }

String progressStatusToCode(ProgressStatus status) => switch (status) {
      ProgressStatus.notStarted => 'not_started',
      ProgressStatus.inProgress => 'in_progress',
      ProgressStatus.completed => 'completed',
    };

ProgressStatus progressStatusFromCode(String code) => switch (code) {
      'completed' => ProgressStatus.completed,
      'in_progress' => ProgressStatus.inProgress,
      _ => ProgressStatus.notStarted,
    };

/// سطر تقدم المستخدم لعنصر واحد (درس/مجموعة بطاقات/جلسة تدريب).
class UserProgress {
  const UserProgress({
    required this.itemType,
    required this.itemId,
    required this.status,
    required this.timesReviewed,
    this.score,
    this.lastPracticedAt,
    this.updatedAt,
  });

  final ProgressItemType itemType;
  final String itemId;
  final ProgressStatus status;
  final int? score;
  final int timesReviewed;
  final String? lastPracticedAt;
  final String? updatedAt;

  factory UserProgress.fromMap(Map<String, Object?> map) {
    return UserProgress(
      itemType: progressItemTypeFromCode(map['item_type']! as String),
      itemId: map['item_id']! as String,
      status: progressStatusFromCode(map['status']! as String),
      score: (map['score'] as num?)?.toInt(),
      timesReviewed: (map['times_reviewed'] as num?)?.toInt() ?? 0,
      lastPracticedAt: map['last_practiced_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'item_type': progressItemTypeToCode(itemType),
      'item_id': itemId,
      'status': progressStatusToCode(status),
      'score': score,
      'times_reviewed': timesReviewed,
      'last_practiced_at': lastPracticedAt,
      'updated_at': updatedAt,
    };
  }
}
