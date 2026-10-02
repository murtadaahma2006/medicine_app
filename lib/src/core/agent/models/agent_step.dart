import 'package:flutter/foundation.dart';
import 'agent_enums.dart';

/// نموذج بيانات الخطوة التنفيذية (AgentStep) داخل مهمة خط المعالجة الموزع.
@immutable
class AgentStep {
  const AgentStep({
    required this.id,
    required this.taskId,
    required this.sequenceIndex,
    required this.type,
    this.status = AgentStepStatus.pending,
    this.inputPayload,
    this.outputPayload,
    this.attempts = 0,
    this.lastError,
  });

  /// المعرف الفريد للخطوة.
  final String id;

  /// معرف المهمة التابعة لها.
  final String taskId;

  /// تسلسل وترتيب الخطوة داخل المهمة.
  final int sequenceIndex;

  /// نوع الخطوة (extract_concepts, generate_mcqs, generate_flashcards, etc.).
  final String type;

  /// حالة الخطوة (pending, done, failed).
  final AgentStepStatus status;

  /// المدخلات الخاصة بهذه الخطوة (JSON / String).
  final String? inputPayload;

  /// المخرجات الناتجة عن تنفيذ الخطوة (JSON / String).
  final String? outputPayload;

  /// عدد محاولات التنفيذ عند الإخفاق أو التكرار.
  final int attempts;

  /// نص آخر خطأ تم تسجيله عند فشل المحاولة.
  final String? lastError;

  AgentStep copyWith({
    String? id,
    String? taskId,
    int? sequenceIndex,
    String? type,
    AgentStepStatus? status,
    String? inputPayload,
    String? outputPayload,
    int? attempts,
    String? lastError,
  }) {
    return AgentStep(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      sequenceIndex: sequenceIndex ?? this.sequenceIndex,
      type: type ?? this.type,
      status: status ?? this.status,
      inputPayload: inputPayload ?? this.inputPayload,
      outputPayload: outputPayload ?? this.outputPayload,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'task_id': taskId,
      'sequence_index': sequenceIndex,
      'type': type,
      'status': status.toDbString(),
      'input_payload': inputPayload,
      'output_payload': outputPayload,
      'attempts': attempts,
      'last_error': lastError,
    };
  }

  factory AgentStep.fromMap(Map<String, dynamic> map) {
    return AgentStep(
      id: map['id'] as String,
      taskId: map['task_id'] as String,
      sequenceIndex: map['sequence_index'] as int,
      type: map['type'] as String,
      status: AgentStepStatus.fromDbString(map['status'] as String),
      inputPayload: map['input_payload'] as String?,
      outputPayload: map['output_payload'] as String?,
      attempts: map['attempts'] as int? ?? 0,
      lastError: map['last_error'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentStep &&
        other.id == id &&
        other.taskId == taskId &&
        other.sequenceIndex == sequenceIndex &&
        other.type == type &&
        other.status == status &&
        other.inputPayload == inputPayload &&
        other.outputPayload == outputPayload &&
        other.attempts == attempts &&
        other.lastError == lastError;
  }

  @override
  int get hashCode => Object.hash(
        id,
        taskId,
        sequenceIndex,
        type,
        status,
        inputPayload,
        outputPayload,
        attempts,
        lastError,
      );

  @override
  String toString() {
    return 'AgentStep(id: $id, taskId: $taskId, sequenceIndex: $sequenceIndex, type: $type, status: $status, attempts: $attempts)';
  }
}
