import 'dart:async';

/// رسالة سجل واحدة في خط الوكلاء.
class AgentLogEntry {
  const AgentLogEntry({
    required this.id,
    required this.message,
    required this.timestamp,
  });

  final String id;
  final String message;
  final DateTime timestamp;

  String get formattedTime {
    final String h = timestamp.hour.toString().padLeft(2, '0');
    final String m = timestamp.minute.toString().padLeft(2, '0');
    final String s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// خدمة سجل الرسائل المباشرة لخط الوكلاء (AgentLogService).
///
/// Singleton يحتفظ بقائمة رسائل كل مهمة في الذاكرة ويبثّها
/// عبر [StreamController] للـ UI لعرضها في الوقت الحقيقي.
///
/// الرسائل مؤقتة: تُمسح عند إعادة تشغيل التطبيق أو حذف المهمة.
class AgentLogService {
  AgentLogService._();
  static final AgentLogService instance = AgentLogService._();

  // خريطة: taskId → قائمة الرسائل المتراكمة
  final Map<String, List<AgentLogEntry>> _logs =
      <String, List<AgentLogEntry>>{};

  // خريطة: taskId → StreamController للبث المباشر
  final Map<String, StreamController<List<AgentLogEntry>>> _controllers =
      <String, StreamController<List<AgentLogEntry>>>{};

  // ── API ──────────────────────────────────────────────────────────────────

  /// إضافة رسالة جديدة لسجل المهمة وإخطار المستمعين. يُرجع معرّف الرسالة.
  String log(String taskId, String message) {
    _logs.putIfAbsent(taskId, () => <AgentLogEntry>[]);

    final String logId = DateTime.now().millisecondsSinceEpoch.toString() + '_' + _logs[taskId]!.length.toString();
    final AgentLogEntry entry = AgentLogEntry(
      id: logId,
      message: message,
      timestamp: DateTime.now(),
    );
    _logs[taskId]!.add(entry);

    _broadcast(taskId);
    return logId;
  }

  /// يضيف نصاً إلى رسالة محددة عبر الـ ID (يُستخدم للتدفق البصري الموازي).
  void appendLog(String taskId, String logId, String chunk) {
    final List<AgentLogEntry>? taskLogs = _logs[taskId];
    if (taskLogs == null || taskLogs.isEmpty) return;

    final int index = taskLogs.indexWhere((e) => e.id == logId);
    if (index == -1) return;

    final AgentLogEntry target = taskLogs[index];
    taskLogs[index] = AgentLogEntry(
      id: target.id,
      message: target.message + chunk,
      timestamp: target.timestamp,
    );

    _broadcast(taskId);
  }

  void _broadcast(String taskId) {
    final StreamController<List<AgentLogEntry>>? ctrl = _controllers[taskId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(List<AgentLogEntry>.unmodifiable(_logs[taskId]!));
    }
  }

  /// الاستماع لتحديثات سجل مهمة محددة.
  Stream<List<AgentLogEntry>> watchLogs(String taskId) {
    _controllers.putIfAbsent(
      taskId,
      () => StreamController<List<AgentLogEntry>>.broadcast(),
    );
    // أرسل القائمة الحالية فوراً إن وُجدت
    final StreamController<List<AgentLogEntry>> ctrl =
        _controllers[taskId]!;
    final List<AgentLogEntry> existing =
        _logs[taskId] ?? <AgentLogEntry>[];
    if (existing.isNotEmpty) {
      Future<void>.microtask(() {
        if (!ctrl.isClosed) {
          ctrl.add(List<AgentLogEntry>.unmodifiable(existing));
        }
      });
    }
    return ctrl.stream;
  }

  /// استرجاع قائمة الرسائل الحالية بدون Stream.
  List<AgentLogEntry> getLogs(String taskId) =>
      List<AgentLogEntry>.unmodifiable(_logs[taskId] ?? <AgentLogEntry>[]);

  /// مسح سجل مهمة محددة (عند الحذف مثلاً).
  void clearLogs(String taskId) {
    _logs.remove(taskId);
    final StreamController<List<AgentLogEntry>>? ctrl =
        _controllers.remove(taskId);
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.close();
    }
  }

  /// مسح كل السجلات (عند إعادة التشغيل).
  void clearAll() {
    for (final StreamController<List<AgentLogEntry>> ctrl
        in _controllers.values) {
      if (!ctrl.isClosed) ctrl.close();
    }
    _controllers.clear();
    _logs.clear();
  }
}
