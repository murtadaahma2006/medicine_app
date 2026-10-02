import 'package:flutter/foundation.dart';
import 'agent_enums.dart';

/// نموذج بيانات مهمة المعالجة (AgentTask) لخط معالجة المنهج الموزع (MedOS Content Factory).
@immutable
class AgentTask {
  const AgentTask({
    required this.id,
    required this.filePath,
    required this.title,
    this.status = AgentTaskStatus.queued,
    this.payload,
    this.progress = 0.0,
    this.currentStatusText,
    required this.createdAt,
    this.elapsedSeconds = 0,
    this.supervisorConfig,
    this.workerConfig,
  });

  /// المعرف الفريد للمهمة.
  final String id;

  /// مسار ملف PDF الجاري معالجته.
  final String filePath;

  /// عنوان المهمة أو المحاضرة المعالجة.
  final String title;

  /// الحالة الحالية للمهمة (queued, running, paused, pending_approval, done, failed).
  final AgentTaskStatus status;

  /// نص الحمولات أو صيغة JSON المرجعية للمهمة.
  final String? payload;

  /// نسبة تقدم المهمة (من 0.0 إلى 1.0).
  final double progress;

  /// وصف كTEXT للمرحلة أو الخطوة الحالية.
  final String? currentStatusText;

  /// طابع وقت إنشاء المهمة.
  final DateTime createdAt;

  /// الثواني المنقضية أثناء التشغيل.
  final int elapsedSeconds;

  /// إعدادات المشرف (Supervisor AI) — JSON string يحتوي على {apiKey, modelName}.
  /// المشرف يقرأ PDF ويتحقق من الجودة (خطوات Multimodal).
  final String? supervisorConfig;

  /// إعدادات العامل (Worker AI) — JSON string يحتوي على {baseUrl, apiKey, modelName}.
  /// العامل ينجز التوليد الكثيف (MCQs, Flashcards, Cases).
  final String? workerConfig;

  AgentTask copyWith({
    String? id,
    String? filePath,
    String? title,
    AgentTaskStatus? status,
    String? payload,
    double? progress,
    String? currentStatusText,
    DateTime? createdAt,
    int? elapsedSeconds,
    String? supervisorConfig,
    String? workerConfig,
  }) {
    return AgentTask(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      status: status ?? this.status,
      payload: payload ?? this.payload,
      progress: progress ?? this.progress,
      currentStatusText: currentStatusText ?? this.currentStatusText,
      createdAt: createdAt ?? this.createdAt,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      supervisorConfig: supervisorConfig ?? this.supervisorConfig,
      workerConfig: workerConfig ?? this.workerConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'file_path': filePath,
      'title': title,
      'status': status.toDbString(),
      'payload': payload,
      'progress': progress,
      'current_status_text': currentStatusText,
      'created_at': createdAt.toUtc().toIso8601String(),
      'elapsed_seconds': elapsedSeconds,
      'supervisor_config': supervisorConfig,
      'worker_config': workerConfig,
    };
  }

  factory AgentTask.fromMap(Map<String, dynamic> map) {
    return AgentTask(
      id: map['id'] as String,
      filePath: map['file_path'] as String,
      title: map['title'] as String,
      status: AgentTaskStatus.fromDbString(map['status'] as String),
      payload: map['payload'] as String?,
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      currentStatusText: map['current_status_text'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      elapsedSeconds: map['elapsed_seconds'] as int? ?? 0,
      supervisorConfig: map['supervisor_config'] as String?,
      workerConfig: map['worker_config'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentTask &&
        other.id == id &&
        other.filePath == filePath &&
        other.title == title &&
        other.status == status &&
        other.payload == payload &&
        other.progress == progress &&
        other.currentStatusText == currentStatusText &&
        other.createdAt == createdAt &&
        other.elapsedSeconds == elapsedSeconds &&
        other.supervisorConfig == supervisorConfig &&
        other.workerConfig == workerConfig;
  }

  @override
  int get hashCode => Object.hash(
        id,
        filePath,
        title,
        status,
        payload,
        progress,
        currentStatusText,
        createdAt,
        elapsedSeconds,
        supervisorConfig,
        workerConfig,
      );

  @override
  String toString() {
    return 'AgentTask(id: $id, filePath: $filePath, title: $title, '
        'status: $status, progress: $progress, '
        'currentStatusText: $currentStatusText, createdAt: $createdAt, '
        'elapsedSeconds: $elapsedSeconds, '
        'hasSupervisor: ${supervisorConfig != null}, '
        'hasWorker: ${workerConfig != null})';
  }
}
