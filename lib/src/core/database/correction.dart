/// أنواع أخطاء الإجابة في سجل corrections — عام لأي مجال محتوى.
enum MistakeType { exact, spelling, wrong }

String mistakeTypeToCode(MistakeType type) => switch (type) {
      MistakeType.exact => 'exact',
      MistakeType.spelling => 'spelling',
      MistakeType.wrong => 'wrong',
    };

MistakeType mistakeTypeFromCode(String code) => switch (code) {
      'exact' => MistakeType.exact,
      'spelling' => MistakeType.spelling,
      _ => MistakeType.wrong,
    };

/// محاولة إجابة واحدة مسجلة (صحيحة أو خاطئة) — سجل الأخطاء والتحليلات.
class Correction {
  const Correction({
    required this.drillId,
    required this.questionId,
    required this.userAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.mistakeType,
    required this.attemptedAt,
  });

  final String drillId;
  final String questionId;
  final String userAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final MistakeType mistakeType;
  final String attemptedAt;

  factory Correction.fromMap(Map<String, Object?> map) {
    return Correction(
      drillId: map['drill_id']! as String,
      questionId: map['question_id']! as String,
      userAnswer: map['user_answer']! as String,
      correctAnswer: map['correct_answer']! as String,
      isCorrect: ((map['is_correct'] as num?)?.toInt() ?? 0) == 1,
      mistakeType: mistakeTypeFromCode(map['mistake_type'] as String? ?? 'wrong'),
      attemptedAt: map['attempted_at']! as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'drill_id': drillId,
      'question_id': questionId,
      'user_answer': userAnswer,
      'correct_answer': correctAnswer,
      'is_correct': isCorrect ? 1 : 0,
      'mistake_type': mistakeTypeToCode(mistakeType),
      'attempted_at': attemptedAt,
    };
  }
}
