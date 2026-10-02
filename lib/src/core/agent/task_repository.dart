import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'models/models.dart';

/// المستودع المسؤول عن التخزين المحلي واسترجاع وقائع مهام وخطوات المعالجة (TaskRepository).
///
/// يدعم التنسيق والتكامل مع خط وكلاء تحويل المنهج (MedOS Content Factory)
/// ويتيح الاستئناف التلقائي والدعم التفاعلي اللحظي (Stream-based reactive updates).
class TaskRepository {
  TaskRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// وصول مباشر لمرجع القاعدة المستخدم في المستودع
  DatabaseHelper get dbHelper => _dbHelper;

  /// مجرى البث المباشر الموزع لإشعار الواجهات أو الخدمات الفرعية بأي تعديل طرأ على المهام.
  final StreamController<List<AgentTask>> _tasksStreamController =
      StreamController<List<AgentTask>>.broadcast();

  /// إرجاع مجرى تفاعلي (Stream) للمهام الحالية والمستقبلية، مع إكانية التصفية.
  Stream<List<AgentTask>> watchTasks({AgentTaskStatus? statusFilter}) {
    // إرسال اللقطة الابتدائية فوراً عند بدء الاشتراك
    getTasks(statusFilter: statusFilter).then((tasks) {
      if (!_tasksStreamController.isClosed) {
        _tasksStreamController.add(tasks);
      }
    });

    if (statusFilter == null) {
      return _tasksStreamController.stream;
    } else {
      return _tasksStreamController.stream.map(
        (tasks) => tasks.where((t) => t.status == statusFilter).toList(),
      );
    }
  }

  /// إشعار كل المستمعين على مجرى Stream بإعادة تحميل القائمة
  Future<void> _notifyListeners() async {
    if (!_tasksStreamController.isClosed) {
      final tasks = await getTasks();
      _tasksStreamController.add(tasks);
    }
  }

  /// إنشاء مهمة جديدة وإضافتها إلى قاعدة البيانات.
  ///
  /// يمكن تمرير [initialSteps] لزرع خطوات المهمة الأولية في معاملة واحدة (Transaction).
  Future<AgentTask> createTask({
    required String id,
    required String filePath,
    required String title,
    AgentTaskStatus status = AgentTaskStatus.queued,
    String? payload,
    double progress = 0.0,
    String? currentStatusText,
    DateTime? createdAt,
    List<AgentStep>? initialSteps,
    String? supervisorConfig,
    String? workerConfig,
  }) async {
    final db = await _dbHelper.database;
    final task = AgentTask(
      id: id,
      filePath: filePath,
      title: title,
      status: status,
      payload: payload,
      progress: progress.clamp(0.0, 1.0),
      currentStatusText: currentStatusText,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      supervisorConfig: supervisorConfig,
      workerConfig: workerConfig,
    );

    await db.transaction((txn) async {
      await txn.insert(
        DatabaseHelper.tableAgentTasks,
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (initialSteps != null && initialSteps.isNotEmpty) {
        for (final step in initialSteps) {
          await txn.insert(
            DatabaseHelper.tableAgentSteps,
            step.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });

    await _notifyListeners();
    return task;
  }

  /// استرجاع قائمة المهام، مرتبة من الأحدث إلى الأقدم، مع إكانية التصفية بحالة المهمة.
  Future<List<AgentTask>> getTasks({AgentTaskStatus? statusFilter}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps;
    if (statusFilter != null) {
      maps = await db.query(
        DatabaseHelper.tableAgentTasks,
        where: 'status = ?',
        whereArgs: <Object?>[statusFilter.toDbString()],
        orderBy: 'created_at DESC',
      );
    } else {
      maps = await db.query(
        DatabaseHelper.tableAgentTasks,
        orderBy: 'created_at DESC',
      );
    }
    return maps.map((map) => AgentTask.fromMap(map)).toList();
  }

  /// استرجاع بيانات مهمة واحدة حسب معرفها.
  Future<AgentTask?> getTaskById(String taskId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableAgentTasks,
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AgentTask.fromMap(maps.first);
  }

  /// تحديث حالة المهمة، مع خيار تحديث الوصف النصي للحالة.
  Future<void> updateTaskStatus(
    String taskId,
    AgentTaskStatus status, {
    String? statusText,
  }) async {
    final db = await _dbHelper.database;
    final Map<String, dynamic> values = <String, dynamic>{
      'status': status.toDbString(),
    };
    if (statusText != null) {
      values['current_status_text'] = statusText;
    }

    await db.update(
      DatabaseHelper.tableAgentTasks,
      values,
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
    );
    await _notifyListeners();
  }

  /// تحديث نسبة التقدم للمهمة (من 0.0 إلى 1.0) ونص الحالة السريعة.
  /// يحافظ على أعلى نسبة تقدم للحد من تراجع المؤشر عند تنفيذ الخطوات الموازية.
  Future<void> updateTaskProgress(
    String taskId,
    double progress, {
    String? statusText,
  }) async {
    final db = await _dbHelper.database;
    final double clampedProgress = progress.clamp(0.0, 1.0);
    
    // استرجاع التقدم الحالي لتجنب تراجع النسبة
    final currentTask = await getTaskById(taskId);
    final double currentProgress = currentTask?.progress ?? 0.0;
    
    final Map<String, dynamic> values = <String, dynamic>{};
    
    if (clampedProgress > currentProgress) {
      values['progress'] = clampedProgress;
    }
    
    if (statusText != null) {
      values['current_status_text'] = statusText;
    }

    if (values.isNotEmpty) {
      await db.update(
        DatabaseHelper.tableAgentTasks,
        values,
        where: 'id = ?',
        whereArgs: <Object?>[taskId],
      );
      await _notifyListeners();
    }
  }

  /// استرجاع الخطوات الخاصة بمهمة معينة، مرتبة تصاعدياً حسب تسلسلها (sequence_index).
  Future<List<AgentStep>> getStepsForTask(String taskId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableAgentSteps,
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
      orderBy: 'sequence_index ASC',
    );
    return maps.map((map) => AgentStep.fromMap(map)).toList();
  }

  /// إضافة خطوة تنفيذية جديدة إلى مهمة قائمة.
  Future<void> createStep(AgentStep step) async {
    final db = await _dbHelper.database;
    await db.insert(
      DatabaseHelper.tableAgentSteps,
      step.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _notifyListeners();
  }

  /// تحديث خطوة تنفيذية قائمة (الحالة، مخرجات Payload، محاولات الإخفاق، نص الخطأ).
  Future<void> updateStep(AgentStep step) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseHelper.tableAgentSteps,
      step.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[step.id],
    );
    await _notifyListeners();
  }

  /// حذف مهمة برقم معرّفها (وتُحذف الخطوات المرتبطة تلقائياً بفعل ON DELETE CASCADE).
  Future<void> deleteTask(String taskId) async {
    final db = await _dbHelper.database;
    await db.delete(
      DatabaseHelper.tableAgentTasks,
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
    );
    await _notifyListeners();
  }

  /// إغلاق وتفريغ الموارد عند انتهاء دورة حياة المستودع.
  void dispose() {
    _tasksStreamController.close();
  }
}
