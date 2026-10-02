import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/agent/agent_log_service.dart';
import '../../../../core/agent/agent_runtime.dart';
import '../../../../core/agent/models/models.dart';
import '../../../../core/agent/task_repository.dart';
import '../../../../core/content/lecture_import_service.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/models/ai_provider.dart';
import '../../../../core/services/ai_model_manager.dart';
import '../../../../core/services/ai_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import 'ai_task_history_page.dart';

/// لوحة التحكم ومتابعة خط الوكلاء لتحويل ملفات PDF إلى محتوى طبي معتمد (MedOS Content Factory).
class AiTaskManagerPage extends StatefulWidget {
  const AiTaskManagerPage({
    super.key,
    TaskRepository? repository,
    AgentRuntime? runtime,
  })  : _repository = repository,
        _runtime = runtime;

  final TaskRepository? _repository;
  final AgentRuntime? _runtime;

  @override
  State<AiTaskManagerPage> createState() => _AiTaskManagerPageState();
}

class _AiTaskManagerPageState extends State<AiTaskManagerPage> {
  late final TaskRepository _repository;
  late final AgentRuntime _runtime;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? TaskRepository();
    _runtime = widget._runtime ?? AgentRuntime(repository: _repository);
  }

  Future<Map<String, dynamic>> _analyzePdf(String filePath) async {
    try {
      final File f = File(filePath);
      if (!await f.exists()) return {'pages': 0, 'chars': 0, 'tokens': 0, 'estTime': 'غير معروف'};
      final bytes = await f.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final int pages = document.pages.count;
      final String text = PdfTextExtractor(document).extractText();
      document.dispose();
      final int chars = text.length;
      final int tokens = (chars / 4).round(); // تقدير: 4 حروف لكل توكن
      
      // تقدير الوقت: افترض 100 توكن في الثانية كسرعة معالجة لخط الوكلاء، أدنى حد 30 ثانية
      int seconds = (tokens / 100).round();
      if (seconds < 30) seconds = 30;
      
      String estTime = '${seconds ~/ 60} دقيقة و ${seconds % 60} ثانية';
      if (seconds < 60) estTime = '$seconds ثانية';
      
      return {'pages': pages, 'chars': chars, 'tokens': tokens, 'estTime': estTime};
    } catch (e) {
      return {'pages': 0, 'chars': 0, 'tokens': 0, 'estTime': 'خطأ في التحليل'};
    }
  }

  /// إنشاء مهمة جديدة من ملف PDF محدد
  Future<void> _createNewTask() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
      );

      String filePath = '/storage/pdfs/medical_lecture.pdf';
      String title = 'محاضرة طبية جديدة';

      if (result != null && result.files.isNotEmpty) {
        final PlatformFile file = result.files.first;
        filePath = file.path ?? filePath;
        title = file.name.replaceAll('.pdf', '');
      } else {
        return; // User canceled
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏳ جاري تحليل ملف الـ PDF...'), duration: Duration(seconds: 1)),
      );
      
      final Map<String, dynamic> stats = await _analyzePdf(filePath);

      if (!mounted) return;
      // ignore: use_build_context_synchronously
      final Map<String, dynamic>? config = await _showTaskConfigDialog(context, title, stats);
      if (config == null) return; // User canceled the dialog

      title = config['title'] as String;
      final String payloadJson = jsonEncode(config);

      final String taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';

      final initialSteps = <AgentStep>[
        AgentStep(
          id: '${taskId}_step_1',
          taskId: taskId,
          sequenceIndex: 0,
          type: AgentStepType.extractConcepts,
        ),
        AgentStep(
          id: '${taskId}_step_2',
          taskId: taskId,
          sequenceIndex: 1,
          type: AgentStepType.generateMcqs,
        ),
        AgentStep(
          id: '${taskId}_step_3',
          taskId: taskId,
          sequenceIndex: 2,
          type: AgentStepType.generateFlashcards,
        ),
        AgentStep(
          id: '${taskId}_step_4',
          taskId: taskId,
          sequenceIndex: 3,
          type: AgentStepType.generateCases,
        ),
        AgentStep(
          id: '${taskId}_step_5',
          taskId: taskId,
          sequenceIndex: 4,
          type: AgentStepType.validateOutput,
        ),
      ];

      final AgentTask task = await _repository.createTask(
        id: taskId,
        filePath: filePath,
        title: title,
        status: AgentTaskStatus.queued,
        currentStatusText: 'في الانتظار...',
        initialSteps: initialSteps,
        payload: payloadJson,
        supervisorConfig: config['supervisorConfig'] as String?,
        workerConfig: config['workerConfig'] as String?,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة المهمة "$title" إلى خط المعالجة'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? AppColors.primaryDark
                : AppColors.primaryLight,
          ),
        );
      }

      // بدء المعالجة فوراً في الخلفية
      unawaited(_runtime.runTask(task));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر اختيار الملف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static const String _prefKeySupBaseUrl = 'dual_agent_sup_base_url';
  static const String _prefKeySupApiKey = 'dual_agent_sup_api_key';
  static const String _prefKeySupModel = 'dual_agent_sup_model';
  static const String _prefKeyWrkBaseUrl = 'dual_agent_wrk_base_url';
  static const String _prefKeyWrkApiKey = 'dual_agent_wrk_api_key';
  static const String _prefKeyWrkModel = 'dual_agent_wrk_model';

  static const String _prefKeySupProviderId = 'dual_agent_sup_provider_id';
  static const String _prefKeyWrkProviderId = 'dual_agent_wrk_provider_id';

  Future<Map<String, dynamic>?> _showTaskConfigDialog(
      BuildContext context, String initialTitle, Map<String, dynamic> stats) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final TextEditingController titleController = TextEditingController(text: initialTitle);
    String selectedModule = 'باطنية';
    final List<String> modules = ['باطنية', 'جراحة', 'نسائية'];

    List<AiProvider> models = [];
    AiProvider? selectedSup;
    AiProvider? selectedWrk;
    final AiProvider activeModel = await AiModelManager.getActiveProvider();

    Future<void> loadModels() async {
      final loaded = await AiModelManager.getSavedProviders();
      final supId = prefs.getString(_prefKeySupProviderId);
      final wrkId = prefs.getString(_prefKeyWrkProviderId);
      models = loaded;
      selectedSup = loaded.where((p) => p.id == supId).firstOrNull ?? activeModel;
      selectedWrk = loaded.where((p) => p.id == wrkId).firstOrNull ?? activeModel;
    }

    await loadModels();
    if (!context.mounted) return null;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool isDualExpanded = false;

            return StatefulBuilder(
              builder: (context, setInnerState) {
                return AlertDialog(
                  title: const Text('إعدادات المهمة الذكية'),
                  contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  content: Container(
                    width: double.maxFinite,
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.analytics_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text('تحليل ذكي للملف', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('📄 الصفحات: ${stats['pages']} صفحة', style: const TextStyle(fontSize: 13)),
                                Text('🧠 التوكنز المقدرة: ~${stats['tokens']}', style: const TextStyle(fontSize: 13)),
                                Text('⏱️ الوقت المتوقع للمعالجة: ${stats['estTime']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: titleController,
                            decoration: const InputDecoration(labelText: 'عنوان المحاضرة', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          DropdownButtonFormField<String>(
                            value: selectedModule,
                            decoration: const InputDecoration(labelText: 'القسم (Module)', border: OutlineInputBorder()),
                            items: modules.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                            onChanged: (v) => setState(() => selectedModule = v!),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppRadius.chip),
                              onTap: () => setInnerState(() => isDualExpanded = !isDualExpanded),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(AppRadius.chip),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.smart_toy_rounded, size: 18),
                                    const SizedBox(width: 8),
                                    const Expanded(child: Text('⚡ إعداد المحركين (مشرف + عامل)', style: TextStyle(fontWeight: FontWeight.w600))),
                                    Icon(isDualExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (isDualExpanded) ...[
                            const SizedBox(height: AppSpacing.md),
                            _AiProviderSelector(
                              title: 'المشرف (Supervisor)',
                              subtitle: 'يقرأ الـ PDF ويتحقق من الجودة. يفضل Gemini.',
                              icon: Icons.supervisor_account_rounded,
                              color: Colors.blue,
                              models: models,
                              selectedProvider: selectedSup,
                              onChanged: (p) => setInnerState(() => selectedSup = p),
                              onAddNew: () => _showQuickAddProviderDialog(context, () async {
                                await loadModels();
                                setInnerState(() {});
                              }),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _AiProviderSelector(
                              title: 'العامل (Worker)',
                              subtitle: 'يولد MCQs/Flashcards/Cases. يدعم OpenRouter وغيرها.',
                              icon: Icons.precision_manufacturing_rounded,
                              color: Colors.purple,
                              models: models,
                              selectedProvider: selectedWrk,
                              onChanged: (p) => setInnerState(() => selectedWrk = p),
                              onAddNew: () => _showQuickAddProviderDialog(context, () async {
                                await loadModels();
                                setInnerState(() {});
                              }),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (titleController.text.trim().isEmpty) return;
                        
                        if (selectedSup != null) await prefs.setString(_prefKeySupProviderId, selectedSup!.id);
                        if (selectedWrk != null) await prefs.setString(_prefKeyWrkProviderId, selectedWrk!.id);

                        if (context.mounted) {
                          Navigator.pop(context, {
                            'title': titleController.text.trim(),
                            'module': _uiCategoryToModule(selectedModule),
                            'system': _uiCategoryToSystem(selectedModule),
                            'aiProvider': activeModel.toJson(),
                            'specialty': _moduleToSpecialty(selectedModule),
                            if (selectedSup != null) 'supervisorConfig': jsonEncode(selectedSup!.toJson()),
                            if (selectedWrk != null) 'workerConfig': jsonEncode(selectedWrk!.toJson()),
                          });
                        }
                      },
                      child: const Text('بدء المعالجة الذكية'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  static String _moduleToSpecialty(String module) {
    switch (module) {
      case 'جراحة':
        return 'surgery';
      case 'نسائية':
        return 'obgyn';
      default:
        return 'internal_medicine';
    }
  }

  static String _uiCategoryToModule(String category) {
    switch (category) {
      case 'جراحة':
        return 'general_surgery';
      case 'نسائية':
        return 'gynecology';
      default:
        return 'cardiology';
    }
  }

  static String _uiCategoryToSystem(String category) {
    switch (category) {
      case 'جراحة':
        return 'gastrointestinal';
      case 'نسائية':
        return 'reproductive';
      default:
        return 'cardiovascular';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        title: Text(
          'مصنع المحتوى (MedOS Factory)',
          style: AppType.screenTitle.copyWith(
            fontSize: 20,
            color: AppColors.text(b),
          ),
        ),
        backgroundColor: AppColors.surface(b),
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'سجل العمليات',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AiTaskHistoryPage(repository: _repository),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_task_rounded),
            tooltip: 'إضافة مهمة جديدة',
            onPressed: _createNewTask,
          ),
        ],
      ),
      body: StreamBuilder<List<AgentTask>>(
        stream: _repository.watchTasks(),
        initialData: const <AgentTask>[],
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<AgentTask> allTasks = snapshot.data ?? <AgentTask>[];
          final List<AgentTask> tasks = allTasks.where((t) => t.status != AgentTaskStatus.done).toList();

          if (tasks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: EmptyState(
                  icon: Icons.precision_manufacturing_rounded,
                  title: 'لا توجد مهام معالجة حالياً',
                  subtitle: 'اضغط على زر الإضافة لمعالجة ملف PDF جديد وتحويله تلقائياً إلى مفاهيم وأسئلة وبطاقات.',
                  actionLabel: 'معالجة ملف PDF جديد',
                  onAction: _createNewTask,
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: tasks.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final AgentTask task = tasks[index];
                  return TaskCard(
                    task: task,
                    repository: _repository,
                    runtime: _runtime,
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewTask,
        backgroundColor: AppColors.primary(b),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.picture_as_pdf_rounded),
        label: Text(
          'إضافة ملف PDF',
          style: AppType.caption.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// بطاقة التفاعل ومتابعة حالة المهمة الفردية (TaskCard Widget).
class TaskCard extends StatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.repository,
    required this.runtime,
  });

  final AgentTask task;
  final TaskRepository repository;
  final AgentRuntime runtime;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _isProcessingAction = false;
  Timer? _timer;
  late int _elapsedSeconds;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = widget.task.elapsedSeconds;
    _checkTimer();
  }

  @override
  void didUpdateWidget(TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.status != oldWidget.task.status || widget.task.elapsedSeconds != oldWidget.task.elapsedSeconds) {
      if (widget.task.status == AgentTaskStatus.running && oldWidget.task.status == AgentTaskStatus.running) {
        _elapsedSeconds = _elapsedSeconds > widget.task.elapsedSeconds ? _elapsedSeconds : widget.task.elapsedSeconds;
      } else {
        _elapsedSeconds = widget.task.elapsedSeconds;
      }
      _checkTimer();
    }
  }

  void _checkTimer() {
    if (widget.task.status == AgentTaskStatus.running) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _elapsedSeconds++;
          });
        }
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final int minutes = _elapsedSeconds ~/ 60;
    final int seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// استئناف تنفيذ المهمة المتوقفة
  Future<void> _resumeTask() async {
    setState(() => _isProcessingAction = true);
    try {
      unawaited(widget.runtime.runTask(widget.task));
    } finally {
      if (mounted) {
        setState(() => _isProcessingAction = false);
      }
    }
  }

  /// إعادة توليد خطوة محددة
  Future<void> _regenerateStep(AgentStep step) async {
    setState(() => _isProcessingAction = true);
    try {
      final db = await DatabaseHelper.instance.database;
      
      // إرجاع الخطوة إلى حالة الانتظار ومسح المخرجات القديمة
      await db.update(
        DatabaseHelper.tableAgentSteps,
        {
          'status': AgentStepStatus.pending.name,
          'output_payload': null,
          'last_error': null,
        },
        where: 'id = ?',
        whereArgs: [step.id],
      );

      // إعادة حالة المهمة ككل إلى قيد المعالجة لتتمكن من إكمال السير
      await db.update(
        DatabaseHelper.tableAgentTasks,
        {
          'status': AgentTaskStatus.running.name,
          'progress': (widget.task.progress - 0.2).clamp(0.0, 1.0),
          'current_status_text': 'إعادة تنفيذ خطوة محددة...',
        },
        where: 'id = ?',
        whereArgs: [widget.task.id],
      );

      // استئناف المعالجة
      final AgentTask? updatedTask = await widget.repository.getTaskById(widget.task.id);
      if (updatedTask != null) {
        unawaited(widget.runtime.runTask(updatedTask));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingAction = false);
      }
    }
  }

  /// اعتماد واستيراد النواتج إلى بنك قاعدة البيانات الطبية
  Future<void> _approveAndImport() async {
    setState(() => _isProcessingAction = true);

    try {
      final String? rawPayload = widget.task.payload;

      if (rawPayload == null || rawPayload.trim().isEmpty) {
        throw Exception('لا توجد مخرجات معالجة في المهمة للاعتماد.');
      }

      String jsonToImport = rawPayload;

      // التأكد من تطابق الهيكل مع عقد البيانات v2.0.0
      try {
        final Map<String, dynamic> decoded = jsonDecode(rawPayload) as Map<String, dynamic>;
        if (!decoded.containsKey('schema_version')) {
          jsonToImport = _buildStandardLectureJson(widget.task, decoded);
        }
      } catch (_) {
        jsonToImport = _buildStandardLectureJson(widget.task, {});
      }

      final LectureImportResult result =
          await LectureImportService.importFromJsonString(
        jsonToImport,
        dbHelper: widget.repository.dbHelper,
      );

      if (result.ok) {
        await widget.repository.updateTaskStatus(
          widget.task.id,
          AgentTaskStatus.done,
          statusText: result.messageAr,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.messageAr),
              backgroundColor: AppColors.success(Theme.of(context).colorScheme.brightness),
            ),
          );
        }
      } else {
        throw Exception(result.messageAr);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل اعتماد واستيراد المحاضرة: $e'),
            backgroundColor: AppColors.error(Theme.of(context).colorScheme.brightness),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingAction = false);
      }
    }
  }

  /// معاينة وتعديل المخرجات قبل الاعتماد النهائي
  Future<void> _previewAndEdit() async {
    final String? rawPayload = widget.task.payload;
    if (rawPayload == null || rawPayload.trim().isEmpty) return;

    String formattedJson = '';
    try {
      final Map<String, dynamic> decoded = jsonDecode(rawPayload) as Map<String, dynamic>;
      if (!decoded.containsKey('schema_version')) {
        formattedJson = _buildStandardLectureJson(widget.task, decoded);
      } else {
        formattedJson = rawPayload;
      }
      final parsed = jsonDecode(formattedJson);
      formattedJson = const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      formattedJson = _buildStandardLectureJson(widget.task, {});
    }

    final TextEditingController jsonController = TextEditingController(text: formattedJson);

    final bool? result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, anim1, anim2) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('معاينة وتعديل المحاضرة 📝'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context, false),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  try {
                    jsonDecode(jsonController.text);
                    Navigator.pop(context, true);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ في صيغة JSON: $e'), backgroundColor: Colors.red),
                    );
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('حفظ التعديلات'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              )
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: jsonController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Edit JSON Data here...',
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (result == true) {
      final String updatedPayload = jsonController.text;
      try {
        final db = await DatabaseHelper.instance.database;
        await db.update(
          DatabaseHelper.tableAgentTasks,
          {'payload': updatedPayload},
          where: 'id = ?',
          whereArgs: [widget.task.id],
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حفظ التعديلات بنجاح. يمكنك الآن اعتماد المحاضرة.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// بناء هيكل JSON متوافق مع schema 2.0.0 عند الاعتماد
  List<dynamic> _extractList(dynamic value) {
    if (value is List) return value;
    if (value is Map) {
      // If it's a map, try to find the first value that is a List
      for (final v in value.values) {
        if (v is List) return v;
      }
    }
    return [];
  }

  String _buildStandardLectureJson(AgentTask task, Map<String, dynamic> raw) {
    final String cleanId = task.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    final List<dynamic> concepts = _extractList(raw['concepts'] ?? raw['extract_concepts'] ?? raw['extractConcepts']);
    final List<dynamic> flashcards = _extractList(raw['flashcards'] ?? raw['generate_flashcards'] ?? raw['generateFlashcards']);
    final List<dynamic> mcqs = _extractList(raw['mcqs'] ?? raw['generate_mcqs'] ?? raw['generateMcqs']);
    final List<dynamic> cases = _extractList(raw['clinical_cases'] ?? raw['generate_cases'] ?? raw['generateCases']);

    final Map<String, dynamic> lectureJson = {
      'schema_version': '2.0.0',
      'lecture': {
        'id': 'unit_$cleanId',
        'specialty': raw['specialty'] ?? 'internal_medicine',
        'module': raw['module'] ?? 'unknown',
        'system': raw['system'] ?? 'unknown',
        'title': raw['title'] ?? task.title,
        'summary_ar': task.currentStatusText ?? 'محاضرة مستخرجة بواسطة خط الوكلاء الذكي.',
        'order_index': 1,
        'source': {
          'file_name': task.filePath.split('/').last,
          'page_count': 10, // Default fallback
        },
      },
      'concepts': concepts.isNotEmpty ? concepts : [],
      'flashcards': flashcards.isNotEmpty ? flashcards : [],
      'mcqs': mcqs.isNotEmpty ? mcqs : [],
      'clinical_cases': cases.isNotEmpty ? cases : [],
    };

    return jsonEncode(lectureJson);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final AgentTask task = widget.task;

    final Color statusColor = _getStatusColor(task.status, b);
    final String statusLabel = _getStatusLabel(task.status);
    final IconData statusIcon = _getStatusIcon(task.status);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── رأس البطاقة: العنوان والحالة ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(statusIcon, color: statusColor, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: AppType.cardTitle.copyWith(
                        fontSize: 17,
                        color: AppColors.text(b),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.filePath.split('/').last,
                      style: AppType.caption.copyWith(
                        color: AppColors.textSecondary(b),
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // شريحة الحالة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  statusLabel,
                  style: AppType.caption.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── شريط التقدم والنسبة مع العداد الزمني ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  task.currentStatusText ?? 'جاهز للمعالجة',
                  style: AppType.body.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary(b),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: AppColors.textSecondary(b)),
                  const SizedBox(width: 4),
                  Text(
                    _formattedTime,
                    style: AppType.caption.copyWith(
                      color: AppColors.textSecondary(b),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    '${(task.progress * 100).toInt()}%',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AgentStepsChecklist(
            task: task,
            repository: widget.repository,
            onRegenerateStep: (step) => _regenerateStep(step),
          ),

          // ── سجل الرسائل المباشرة (Live Log) ──────────────────────
          LiveLogPanel(task: task),

          const SizedBox(height: AppSpacing.md),

          // ── الأزرار والإجراءات التفاعلية حسب حالة المهمة ──
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // زر الإلغاء/الحذف يظهر دائماً
              TextButton.icon(
                onPressed: () {
                  AgentLogService.instance.clearLogs(task.id);
                  widget.repository.deleteTask(task.id);
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('إلغاء'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error(b),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: AppType.caption.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              if (task.status == AgentTaskStatus.running) ...[
                Expanded(child: _LiveAiIndicator(task: task, b: b, repository: widget.repository)),
              ] else if (task.status == AgentTaskStatus.paused || task.status == AgentTaskStatus.failed) ...[
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isProcessingAction ? null : _resumeTask,
                  icon: _isProcessingAction
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('استئناف ⏯️'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary(b),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: AppType.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ] else if (task.status == AgentTaskStatus.pendingApproval) ...[
                ElevatedButton.icon(
                  onPressed: _isProcessingAction ? null : _previewAndEdit,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('معاينة وتعديل 📝'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold(b),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: AppType.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isProcessingAction ? null : _approveAndImport,
                  icon: _isProcessingAction
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('اعتماد واستيراد ✔'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success(b),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: AppType.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ] else if (task.status == AgentTaskStatus.done) ...[
                const SizedBox.shrink(), // No extra actions for done state
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(AgentTaskStatus status, Brightness b) {
    switch (status) {
      case AgentTaskStatus.queued:
        return AppColors.textSecondary(b);
      case AgentTaskStatus.running:
        return AppColors.primary(b);
      case AgentTaskStatus.paused:
      case AgentTaskStatus.failed:
        return AppColors.error(b);
      case AgentTaskStatus.pendingApproval:
        return AppColors.gold(b);
      case AgentTaskStatus.done:
        return AppColors.success(b);
    }
  }

  String _getStatusLabel(AgentTaskStatus status) {
    switch (status) {
      case AgentTaskStatus.queued:
        return 'في الانتظار';
      case AgentTaskStatus.running:
        return 'قيد المعالجة';
      case AgentTaskStatus.paused:
        return 'متوقف مؤقتاً';
      case AgentTaskStatus.pendingApproval:
        return 'بانتظار الموافقة';
      case AgentTaskStatus.done:
        return 'مكتمل ومستورد';
      case AgentTaskStatus.failed:
        return 'فشلت المعالجة';
    }
  }

  IconData _getStatusIcon(AgentTaskStatus status) {
    switch (status) {
      case AgentTaskStatus.queued:
        return Icons.hourglass_empty_rounded;
      case AgentTaskStatus.running:
        return Icons.sync_rounded;
      case AgentTaskStatus.paused:
        return Icons.pause_circle_filled_rounded;
      case AgentTaskStatus.pendingApproval:
        return Icons.rate_review_rounded;
      case AgentTaskStatus.done:
        return Icons.task_alt_rounded;
      case AgentTaskStatus.failed:
        return Icons.error_outline_rounded;
    }
  }
}

// ── Live Log Panel — سجل رسائل الوكيل المباشرة ─────────────────────────────
class LiveLogPanel extends StatefulWidget {
  const LiveLogPanel({super.key, required this.task});
  final AgentTask task;

  @override
  State<LiveLogPanel> createState() => _LiveLogPanelState();
}

class _LiveLogPanelState extends State<LiveLogPanel> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _isExpanded = true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool isDark = b == Brightness.dark;

    // استخراج أسماء النماذج من المهمة
    String supervisorModel = 'المشرف الافتراضي';
    if (widget.task.supervisorConfig != null) {
      try {
        final Map<String, dynamic> sc = jsonDecode(widget.task.supervisorConfig!) as Map<String, dynamic>;
        supervisorModel = (sc['modelName'] as String?) ?? supervisorModel;
      } catch (_) {}
    }

    String workerModel = 'العامل الافتراضي';
    if (widget.task.workerConfig != null) {
      try {
        final Map<String, dynamic> wc = jsonDecode(widget.task.workerConfig!) as Map<String, dynamic>;
        workerModel = (wc['modelName'] as String?) ?? workerModel;
      } catch (_) {}
    }

    return StreamBuilder<List<AgentLogEntry>>(
      stream: AgentLogService.instance.watchLogs(widget.task.id),
      initialData: AgentLogService.instance.getLogs(widget.task.id),
      builder: (context, snapshot) {
        final List<AgentLogEntry> logs = snapshot.data ?? [];

        // لا تُظهر اللوحة إن كانت فارغة
        if (logs.isEmpty) return const SizedBox.shrink();

        // مرر للأسفل تلقائياً عند وصول رسالة جديدة
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            // ── رأس السجل: عنوان + زر الطي ─────────────────────────
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade900
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal_rounded,
                      size: 14,
                      color: AppColors.primary(b),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'سجل العمليات الحية (${logs.length})',
                      style: AppType.caption.copyWith(
                        color: AppColors.primary(b),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.textSecondary(b),
                    ),
                  ],
                ),
              ),
            ),

            // ── قائمة الرسائل ──────────────────────────────────────
            if (_isExpanded) ...[
              const SizedBox(height: 4),
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0D1117)
                      : const Color(0xFFF6F8FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade300,
                  ),
                ),
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final AgentLogEntry entry = logs[index];
                    final bool isLast = index == logs.length - 1;
                    final Color textColor = _logColor(entry.message, isDark);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // الوقت
                          Text(
                            entry.formattedTime,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // النبضة للرسالة الأخيرة
                          if (isLast)
                            Padding(
                              padding: const EdgeInsets.only(top: 2, left: 2, right: 4),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.primary(b),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 12),
                          // نص الرسالة
                          Expanded(
                            child: Text(
                              entry.message,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: textColor,
                                fontWeight: isLast
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              // ── المؤشر الذكي للنموذج الحالي ──────────────────────
              if (logs.isNotEmpty) Builder(
                builder: (context) {
                  final String lastMessage = logs.last.message;
                  String activeText = '';
                  Color activeColor = Colors.grey;

                  if (lastMessage.contains('المشرف') || lastMessage.contains('تخطيط') || lastMessage.contains('صادق')) {
                    activeText = '🧠 المشرف يعمل الآن: $supervisorModel';
                    activeColor = Colors.blue;
                  } else if (lastMessage.contains('العامل') || lastMessage.contains('يولد') || lastMessage.contains('ينفذ')) {
                    activeText = '⚙️ العامل يعمل الآن: $workerModel';
                    activeColor = Colors.purple;
                  }

                  if (activeText.isEmpty && widget.task.status == AgentTaskStatus.running) {
                    activeText = '🤖 جاري المعالجة...';
                    activeColor = AppColors.primary(b);
                  }

                  if (activeText.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: activeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: activeColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                activeText,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? activeColor.withValues(alpha: 0.9) : activeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ],
        );
      },
    );
  }

  /// اختيار لون الرسالة بناءً على محتواها
  Color _logColor(String message, bool isDark) {
    if (message.startsWith('✅') || message.startsWith('🎉')) {
      return isDark ? Colors.greenAccent.shade400 : Colors.green.shade700;
    }
    if (message.startsWith('⚠️') || message.startsWith('❌')) {
      return isDark ? Colors.orange.shade300 : Colors.orange.shade800;
    }
    if (message.startsWith('🔁') || message.startsWith('♻️')) {
      return isDark ? Colors.yellow.shade300 : Colors.amber.shade800;
    }
    if (message.startsWith('⏸️')) {
      return isDark ? Colors.redAccent.shade100 : Colors.red.shade700;
    }
    if (message.startsWith('🧠') || message.startsWith('🔍')) {
      return isDark ? Colors.cyan.shade300 : Colors.blue.shade700;
    }
    return isDark ? Colors.grey.shade300 : Colors.grey.shade800;
  }
}

// ── Live AI Indicator: نبضة + نص الحالة المباشر + زر إيقاف ─────────────────
class _LiveAiIndicator extends StatelessWidget {
  const _LiveAiIndicator({
    required this.task,
    required this.b,
    required this.repository,
  });

  final AgentTask task;
  final Brightness b;
  final TaskRepository repository;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PulsingDot(color: AppColors.primary(b)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            task.currentStatusText ?? 'الذكاء الاصطناعي يعمل...',
            style: AppType.caption.copyWith(
              color: AppColors.primary(b),
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => repository.updateTaskStatus(
            task.id,
            AgentTaskStatus.paused,
            statusText: '⏸️ أُوقف بواسطة المستخدم — اضغط استئناف للمتابعة',
          ),
          icon: const Icon(Icons.pause_rounded, size: 16),
          label: const Text('إيقاف'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: AppType.caption
                .copyWith(fontWeight: FontWeight.w800, fontSize: 12),
            elevation: 6,
            shadowColor: Colors.red.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
          ),
        ),
      ],
    );
  }
}

// ── النبضة الحية ─────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({this.color});
  final Color? color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color dotColor =
        widget.color ?? AppColors.primary(Theme.of(context).colorScheme.brightness);
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: dotColor.withValues(alpha: 0.6),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class AgentStepsChecklist extends StatefulWidget {
  const AgentStepsChecklist({
    super.key,
    required this.task,
    required this.repository,
    this.onRegenerateStep,
  });

  final AgentTask task;
  final TaskRepository repository;
  final Future<void> Function(AgentStep step)? onRegenerateStep;

  @override
  State<AgentStepsChecklist> createState() => _AgentStepsChecklistState();
}

Future<void> _showQuickAddProviderDialog(BuildContext context, VoidCallback onAdded) async {
  final nameCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  final keyCtrl = TextEditingController();
  final modelCtrl = TextEditingController();

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('إضافة نموذج جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم العرض (مثال: Gemini 1.5 Pro)')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://generativelanguage.googleapis.com/v1beta')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'اسم النموذج الفعلي (مثال: gemini-1.5-pro)')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: keyCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'API Key')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty || keyCtrl.text.isEmpty || modelCtrl.text.isEmpty) return;
            final provider = AiProvider(
              id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
              name: nameCtrl.text.trim(),
              baseUrl: urlCtrl.text.trim(),
              apiKey: keyCtrl.text.trim(),
              modelName: modelCtrl.text.trim(),
            );
            await AiModelManager.addOrUpdateProvider(provider);
            onAdded();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

class _AgentStepsChecklistState extends State<AgentStepsChecklist> {
  List<AgentStep> _steps = [];
  bool _isLoading = true;

  static const Map<String, String> _stepNames = {
    AgentStepType.extractConcepts: 'استخراج المفاهيم الأساسية (Concepts)',
    AgentStepType.generateFlashcards: 'بناء بطاقات الاستذكار (Flashcards)',
    AgentStepType.generateMcqs: 'بناء أسئلة التقييم (MCQs)',
    AgentStepType.generateCases: 'بناء الحالات السريرية (Clinical Cases)',
    AgentStepType.validateOutput: 'تجميع وتدقيق المحتوى (Validate Schema)',
  };

  @override
  void initState() {
    super.initState();
    _fetchSteps();
  }

  @override
  void didUpdateWidget(AgentStepsChecklist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.progress != oldWidget.task.progress ||
        widget.task.status != oldWidget.task.status ||
        widget.task.currentStatusText != oldWidget.task.currentStatusText) {
      _fetchSteps();
    }
  }

  Future<void> _fetchSteps() async {
    final steps = await widget.repository.getStepsForTask(widget.task.id);
    if (mounted) {
      setState(() {
        _steps = steps;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool isTaskDone = widget.task.status == AgentTaskStatus.pendingApproval ||
        widget.task.status == AgentTaskStatus.done;

    final List<String> coreTypes = [
      AgentStepType.extractConcepts,
      AgentStepType.generateFlashcards,
      AgentStepType.generateMcqs,
      AgentStepType.generateCases,
      AgentStepType.validateOutput,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: coreTypes.map((type) {
        final AgentStep step = _steps.firstWhere(
          (s) => s.type == type,
          orElse: () => AgentStep(
            id: '',
            taskId: widget.task.id,
            type: type,
            sequenceIndex: 0,
            status: isTaskDone ? AgentStepStatus.done : AgentStepStatus.pending,
          ),
        );

        bool isDone = step.status == AgentStepStatus.done || isTaskDone;
        bool isFailed = step.status == AgentStepStatus.failed;
        
        // Infer running status for pending steps
        bool isRunning = false;
        if (!isDone && !isFailed && widget.task.status == AgentTaskStatus.running) {
          final int doneCount = _steps.where((s) => s.status == AgentStepStatus.done).length;
          final int currentIndex = coreTypes.indexOf(type);
          if (currentIndex == doneCount) {
            isRunning = true;
          }
        }

        Color iconColor;
        Widget iconWidget;
        TextStyle textStyle;

        if (isDone) {
          iconColor = AppColors.success(b);
          iconWidget = Icon(Icons.check_circle, color: iconColor, size: 20);
          textStyle = AppType.body.copyWith(
            color: AppColors.textSecondary(b).withValues(alpha: 0.6),
            decoration: TextDecoration.lineThrough,
          );
        } else if (isFailed) {
          iconColor = AppColors.error(b);
          iconWidget = Icon(Icons.error, color: iconColor, size: 20);
          textStyle = AppType.body.copyWith(
            color: iconColor,
            fontWeight: FontWeight.w700,
          );
        } else if (isRunning) {
          iconColor = AppColors.text(b);
          iconWidget = SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary(b)),
          );
          textStyle = AppType.body.copyWith(
            color: iconColor,
            fontWeight: FontWeight.w700,
          );
        } else {
          // Pending
          iconColor = AppColors.textSecondary(b).withValues(alpha: 0.4);
          iconWidget = Icon(Icons.radio_button_unchecked, color: iconColor, size: 20);
          textStyle = AppType.body.copyWith(
            color: AppColors.textSecondary(b),
            fontWeight: FontWeight.normal,
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _stepNames[type] ?? type,
                  style: textStyle,
                ),
              ),
              if ((isDone || isFailed) && step.id.isNotEmpty && widget.onRegenerateStep != null)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'إعادة توليد هذه الخطوة',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('إعادة التوليد؟'),
                        content: Text('هل أنت متأكد من إعادة توليد خطوة (${_stepNames[type]})؟ سيتم استهلاك توكنز إضافية.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(c);
                              widget.onRegenerateStep!(step);
                            },
                            child: const Text('نعم، أعد التوليد'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AiProviderSelector extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<AiProvider> models;
  final AiProvider? selectedProvider;
  final void Function(AiProvider?) onChanged;
  final VoidCallback onAddNew;

  const _AiProviderSelector({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.models,
    required this.selectedProvider,
    required this.onChanged,
    required this.onAddNew,
  });

  @override
  State<_AiProviderSelector> createState() => _AiProviderSelectorState();
}

class _AiProviderSelectorState extends State<_AiProviderSelector> {
  bool _isTesting = false;
  bool? _testSuccess;

  Future<void> _testConnection() async {
    if (widget.selectedProvider == null) return;
    setState(() {
      _isTesting = true;
      _testSuccess = null;
    });
    final success = await AIService.testConnection(widget.selectedProvider!);
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = success;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AiProviderSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProvider?.id != widget.selectedProvider?.id) {
      _testSuccess = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: widget.color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 16, color: widget.color),
              const SizedBox(width: 6),
              Text(widget.title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: widget.color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AiProvider>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'النموذج (Model)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  value: widget.selectedProvider,
                  items: [
                    ...widget.models.map((provider) => DropdownMenuItem(
                          value: provider,
                          child: Text(provider.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                    const DropdownMenuItem<AiProvider>(
                      value: null,
                      child: Text('➕ إضافة نموذج جديد...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  onChanged: (AiProvider? value) {
                    if (value == null) {
                      widget.onAddNew();
                    } else {
                      widget.onChanged(value);
                    }
                  },
                ),
              ),
              if (widget.selectedProvider != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isTesting ? null : _testConnection,
                  tooltip: 'اختبار الاتصال',
                  icon: _isTesting
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          _testSuccess == true
                              ? Icons.check_circle
                              : _testSuccess == false
                                  ? Icons.error
                                  : Icons.sensors,
                          color: _testSuccess == true
                              ? Colors.green
                              : _testSuccess == false
                                  ? Colors.red
                                  : Colors.grey,
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
