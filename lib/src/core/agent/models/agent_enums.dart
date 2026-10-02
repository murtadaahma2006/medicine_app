/// حالات مهام وخطوات معالجة ملفات PDF في خط الوكلاء (Agentic Pipeline).
library;

/// حالة المهمة المعالجة بواسطة الوكيل.
enum AgentTaskStatus {
  queued,
  running,
  paused,
  pendingApproval,
  done,
  failed;

  String toDbString() => switch (this) {
        AgentTaskStatus.pendingApproval => 'pending_approval',
        _ => name,
      };

  static AgentTaskStatus fromDbString(String code) => switch (code) {
        'queued' => AgentTaskStatus.queued,
        'running' => AgentTaskStatus.running,
        'paused' => AgentTaskStatus.paused,
        'pending_approval' => AgentTaskStatus.pendingApproval,
        'done' => AgentTaskStatus.done,
        'failed' => AgentTaskStatus.failed,
        _ => throw ArgumentError('Unknown AgentTaskStatus: $code'),
      };
}

/// حالة الخطوة التفصيلية داخل مهمة المعالجة.
enum AgentStepStatus {
  pending,
  done,
  failed;

  String toDbString() => name;

  static AgentStepStatus fromDbString(String code) => switch (code) {
        'pending' => AgentStepStatus.pending,
        'done' => AgentStepStatus.done,
        'failed' => AgentStepStatus.failed,
        _ => throw ArgumentError('Unknown AgentStepStatus: $code'),
      };
}

/// الأنواع المحددة مسبقاً لخطوات معالجة المنهج.
abstract final class AgentStepType {
  static const String extractConcepts = 'extract_concepts';
  static const String generateMcqs = 'generate_mcqs';
  static const String generateFlashcards = 'generate_flashcards';
  static const String generateCases = 'generate_cases';
  static const String validateOutput = 'validate_output';
}
