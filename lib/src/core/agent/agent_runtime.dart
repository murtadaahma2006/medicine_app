import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:medicine_app/src/core/agent/models/agent_enums.dart';
import 'package:medicine_app/src/core/agent/models/agent_step.dart';
import 'package:medicine_app/src/core/agent/models/agent_task.dart';
import 'package:medicine_app/src/core/agent/task_repository.dart';
import 'package:medicine_app/src/core/agent/ai_gateway.dart';
import 'package:medicine_app/src/core/agent/agent_log_service.dart';
import 'package:medicine_app/src/core/agent/system_prompts.dart';
import 'package:medicine_app/src/core/models/ai_provider.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/notifications/task_notification_service.dart';

class _ReviewResult {
  final bool isApproved;
  final String? finalizedJson;
  final String? correctionPrompt;

  _ReviewResult.approved(this.finalizedJson) : isApproved = true, correctionPrompt = null;
  _ReviewResult.retry(this.correctionPrompt) : isApproved = false, finalizedJson = null;
}

class AgentRuntime {
  final TaskRepository _repository;
  final AiGateway _gateway;
  static const Duration _backoffBase = Duration(seconds: 2);

  AgentRuntime({
    required TaskRepository repository,
    AiGateway? gateway,
  })  : _repository = repository,
        _gateway = gateway ?? AiGateway();

  static final Set<String> _pausedTasks = <String>{};

  static void pauseTask(String taskId) {
    _pausedTasks.add(taskId);
  }

  static void resumeTask(String taskId) {
    _pausedTasks.remove(taskId);
  }

  Future<bool> _isPaused(String taskId) async {
    return _pausedTasks.contains(taskId);
  }

  static Future<void> resumeOrphanTasks() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> orphans = await db.query(
        DatabaseHelper.tableAgentTasks,
        where: 'status = ?',
        whereArgs: [AgentTaskStatus.running],
      );
      for (final task in orphans) {
        await db.update(
          DatabaseHelper.tableAgentTasks,
          {
            'status': AgentTaskStatus.paused,
            'currentStatusText': 'توقفت المهمة لإغلاق التطبيق. يمكنك استئنافها.'
          },
          where: 'id = ?',
          whereArgs: [task['id']],
        );
      }
    } catch (_) {}
  }

  Future<void> runTask(
    AgentTask task, {
    AiProvider? supervisorProvider,
    AiProvider? workerProvider,
  }) async {
    final String taskId = task.id;
    resumeTask(taskId);

    await _stream(taskId, '🚀 بدء تنفيذ المهمة: ${task.title}');
    await _repository.updateTaskStatus(taskId, AgentTaskStatus.running, statusText: 'جاري بدء التنفيذ...');

    try {
      List<AgentStep> steps = await _repository.getStepsForTask(taskId);
      if (steps.isEmpty) {
        steps = await _planningPhase(task, supervisorProvider);
        if (steps.isEmpty) return;
      }
      await _executionLoop(task, steps, supervisorProvider, workerProvider);
    } catch (e) {
      debugPrint('AgentRuntime: Task failed -> $e');
      await _repository.updateTaskStatus(taskId, AgentTaskStatus.failed, statusText: '❌ حدث خطأ: $e');
    }
  }

  Future<List<AgentStep>> _planningPhase(AgentTask task, AiProvider? supervisorProvider) async {
    final String taskId = task.id;
    final String specialty = _extractSpecialty(task);
    final String domainPrompt = SystemPrompts.getPromptForSpecialty(specialty);
    final String? filePath = task.filePath.isNotEmpty ? task.filePath : null;
    List<int>? pdfBytes;

    if (filePath != null) {
      try {
        final File f = File(filePath);
        if (await f.exists()) pdfBytes = await f.readAsBytes();
      } catch (e) {
        await _stream(taskId, '⚠️ تحذير: تعذر قراءة PDF — $e');
      }
    }

    const String plannerSystem = '''
You are the Project Manager AI for a medical content factory.
Generate a sequential execution plan for the provided medical lecture PDF.

Return ONLY this exact JSON array (no other text, no markdown):
["extract_concepts","generate_flashcards","generate_mcqs","generate_cases"]
''';

    int attempt = 0;
    Duration backoff = _backoffBase;

    while (true) {
      if (await _isPaused(taskId)) {
        await _stream(taskId, '⏸️ أُوقف التخطيط بناءً على طلب المستخدم');
        return [];
      }

      attempt++;
      try {
        await _stream(taskId, '🧠 المشرف يُنشئ الخطة (محاولة $attempt)...');
        final String planJson = await _gateway.callSupervisor(
          systemPrompt: plannerSystem,
          userMessage:
              'Specialty: $specialty | Domain: ${domainPrompt.substring(0, 80)}... '
              '| PDF: ${pdfBytes?.length ?? 0} bytes. Generate the plan now.',
          filePath: filePath,
          fileBytes: pdfBytes,
          supervisorProvider: supervisorProvider,
        );

        final List<String> stepTypes = _parsePlanJson(planJson);
        if (stepTypes.isNotEmpty) {
          await _stream(taskId, '✅ خطة المشرف: ${stepTypes.join(" → ")}');
          return await _persistSteps(taskId, stepTypes);
        }

        await _stream(taskId, '⚠️ استجابة غير متوقعة من المشرف — سيُستخدم الخط الافتراضي');
        return await _createDefaultSteps(task);
      } catch (e) {
        final String errMsg = _classifyError(e);
        await _stream(taskId, '⚠️ $errMsg — إعادة محاولة التخطيط في ${backoff.inSeconds}ث...');
        debugPrint('AgentRuntime: [PLANNING] $e');
        await Future<void>.delayed(backoff);
        backoff = _nextBackoff(backoff);
      }
    }
  }

  Future<void> _executionLoop(
    AgentTask task,
    List<AgentStep> steps,
    AiProvider? supervisorProvider,
    AiProvider? workerProvider,
  ) async {
    final String taskId = task.id;
    final Map<String, dynamic> assembled = <String, dynamic>{};

    for (final AgentStep s in steps) {
      if (s.status == AgentStepStatus.done && s.outputPayload != null) {
        _accumulate(assembled, s.type, s.outputPayload!);
      }
    }

    final AgentStep? extractStep = steps.where((s) => s.type == AgentStepType.extractConcepts).firstOrNull;
    if (extractStep != null) {
      await _executeSingleStep(extractStep, task, steps, assembled, supervisorProvider, workerProvider);
      if (await _isPaused(taskId)) return;
    }

    final List<AgentStep> middleSteps = steps.where((s) => 
      s.type != AgentStepType.extractConcepts && 
      s.type != AgentStepType.validateOutput
    ).toList();
    
    if (middleSteps.isNotEmpty) {
      final List<AgentStep> pendingMiddle = middleSteps.where((s) => s.status != AgentStepStatus.done).toList();
      if (pendingMiddle.isNotEmpty) {
        await _stream(taskId, '⚡ جاري تنفيذ المهام بالتسلسل (${pendingMiddle.length} مهام)...');
        for (final step in middleSteps) {
          await _executeSingleStep(step, task, steps, assembled, supervisorProvider, workerProvider);
          if (await _isPaused(taskId)) return;
        }
      }
    }

    final AgentStep? validateStep = steps.where((s) => s.type == AgentStepType.validateOutput).firstOrNull;
    if (validateStep != null) {
      await _executeSingleStep(validateStep, task, steps, assembled, supervisorProvider, workerProvider);
      if (await _isPaused(taskId)) return;
    }

    await _finalizeTask(taskId, assembled);
  }

  Future<void> _executeSingleStep(
    AgentStep step,
    AgentTask task,
    List<AgentStep> steps,
    Map<String, dynamic> assembled,
    AiProvider? supervisorProvider,
    AiProvider? workerProvider,
  ) async {
    final int index = steps.indexOf(step);
    final String taskId = task.id;
    final int totalSteps = steps.length;

    if (step.status == AgentStepStatus.done) {
      debugPrint('AgentRuntime: ✅ Skip done [${step.type}] (${index + 1}/$totalSteps)');
      return;
    }

    if (await _isPaused(taskId)) {
      await _stream(taskId, '⏸️ أُوقف التنفيذ قبل بدء: ${_stepLabel(step.type)}');
      return;
    }

    await _repository.updateTaskProgress(
      taskId, index / totalSteps,
      statusText: _formatStatus(step.type, index + 1, totalSteps),
    );

    final AgentStep completed = await _relentlessDelegation(
      task: task,
      step: step,
      stepIndex: index,
      totalSteps: totalSteps,
      assembled: assembled,
      supervisorProvider: supervisorProvider,
      workerProvider: workerProvider,
    );

    if (completed.status == AgentStepStatus.failed && completed.lastError == 'PAUSED_BY_USER') {
      return;
    }

    await _repository.updateStep(completed);
    if (completed.outputPayload != null) {
      _accumulate(assembled, completed.type, completed.outputPayload!);
    }

    debugPrint('AgentRuntime: ✅ [${completed.type}] APPROVED & checkpointed');
  }

  Future<AgentStep> _relentlessDelegation({
    required AgentTask task,
    required AgentStep step,
    required int stepIndex,
    required int totalSteps,
    required Map<String, dynamic> assembled,
    required AiProvider? supervisorProvider,
    required AiProvider? workerProvider,
  }) async {
    final String taskId = task.id;
    final String specialty = _extractSpecialty(task);
    final String domainPrompt = SystemPrompts.getPromptForSpecialty(specialty);

    final bool needsPdf = step.type == AgentStepType.extractConcepts;
    List<int>? pdfBytes;
    String extractedPdfText = '';
    if (needsPdf && task.filePath.isNotEmpty) {
      try {
        final File f = File(task.filePath);
        if (await f.exists()) {
          pdfBytes = await f.readAsBytes();
          try {
            extractedPdfText = await compute(_extractPdfTextInIsolate, pdfBytes);
          } catch (e) {
            debugPrint('Failed to extract PDF text locally: $e');
          }
        }
      } catch (_) {}
    }

    if (needsPdf) {
      if (task.filePath.isEmpty) {
        await _stream(taskId, '❌ فشل المعالجة: لم يتم تحديد مسار لملف الـ PDF.');
        return step.copyWith(status: AgentStepStatus.failed, lastError: 'MISSING_PDF');
      }
      if (pdfBytes == null) {
        await _stream(taskId, '❌ فشل المعالجة: تعذر العثور على ملف الـ PDF المعين أو لا يمكن الوصول إليه.');
        return step.copyWith(status: AgentStepStatus.failed, lastError: 'PDF_NOT_FOUND');
      }
      if (extractedPdfText.trim().isEmpty) {
        await _stream(taskId, '❌ فشل المعالجة: ملف الـ PDF فارغ أو محمي ولا يمكن قراءة النصوص منه.');
        return step.copyWith(status: AgentStepStatus.failed, lastError: 'PDF_EMPTY_OR_UNREADABLE');
      }
    }

    final String workerInstruction = await _relentlessSupervisorInstruction(
      task: task,
      step: step,
      stepIndex: stepIndex,
      totalSteps: totalSteps,
      specialty: specialty,
      domainPrompt: domainPrompt,
      assembled: assembled,
      filePath: needsPdf ? task.filePath : null,
      pdfBytes: pdfBytes,
      supervisorProvider: supervisorProvider,
    );

    if (await _isPaused(taskId)) {
      await _stream(taskId, '⏸️ تم الإيقاف بعد توليد التعليمات');
      return step.copyWith(
        status: AgentStepStatus.failed,
        lastError: 'PAUSED_BY_USER',
      );
    }

    String currentWorkerPrompt = workerInstruction;
    int totalAttempts = 0;
    Duration backoff = _backoffBase;

    while (true) {
      totalAttempts++;

      if (await _isPaused(taskId)) {
        await _stream(
            taskId, '⏸️ أُوقف التنفيذ في محاولة $totalAttempts للخطوة: ${_stepLabel(step.type)}');
        return step.copyWith(
          status: AgentStepStatus.failed,
          lastError: 'PAUSED_BY_USER',
          attempts: step.attempts + totalAttempts,
        );
      }

      final String logId = await _stream(taskId,
          '⚙️ الجولة $totalAttempts — العامل يُنفذ: ${_stepLabel(step.type)}...');

      await _repository.updateTaskProgress(
        taskId,
        (stepIndex + 0.3) / totalSteps,
        statusText: '⚙️ الجولة $totalAttempts — العامل يُنفذ: ${_stepLabel(step.type)}...',
      );

      String finalWorkerPrompt = currentWorkerPrompt;
      if (needsPdf && extractedPdfText.isNotEmpty) {
        finalWorkerPrompt += '\n\n--- MEDICAL PDF TEXT TO EXTRACT FROM ---\n$extractedPdfText\n--- END OF TEXT ---';
      }

      String? workerOutput;
      try {
        final Stream<String> workerStream = _gateway.callWorkerStream(
          systemPrompt:
              'You are an expert medical content generator (Worker AI). '
              'Execute the following instruction exactly and return ONLY valid JSON. '
              'No markdown code blocks. No explanation. JSON only.',
          workerPrompt: finalWorkerPrompt,
          workerProvider: workerProvider,
          supervisorProvider: supervisorProvider,
        );

        final StringBuffer sb = StringBuffer();
        bool isFirstChunk = true;

        await for (final String chunk in workerStream) {
          sb.write(chunk);
          if (isFirstChunk) {
            AgentLogService.instance.appendLog(taskId, logId, '\n$chunk');
            isFirstChunk = false;
          } else {
            AgentLogService.instance.appendLog(taskId, logId, chunk);
          }
        }
        
        workerOutput = sb.toString().trim();
        final RegExp jsonBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
        final Match? match = jsonBlockRegex.firstMatch(workerOutput);
        if (match != null) {
          workerOutput = match.group(1)!.trim();
        } else {
          final int firstBrace = workerOutput.indexOf('{');
          final int firstBracket = workerOutput.indexOf('[');
          int start = -1;
          if (firstBrace != -1 && firstBracket != -1) {
            start = firstBrace < firstBracket ? firstBrace : firstBracket;
          } else if (firstBrace != -1) {
            start = firstBrace;
          } else if (firstBracket != -1) {
            start = firstBracket;
          }
          if (start != -1) {
            final int lastBrace = workerOutput.lastIndexOf('}');
            final int lastBracket = workerOutput.lastIndexOf(']');
            int end = -1;
            if (lastBrace != -1 && lastBracket != -1) {
              end = lastBrace > lastBracket ? lastBrace : lastBracket;
            } else if (lastBrace != -1) {
              end = lastBrace;
            } else if (lastBracket != -1) {
              end = lastBracket;
            }
            if (end != -1 && end >= start) {
              workerOutput = workerOutput.substring(start, end + 1).trim();
            }
          }
        }

        backoff = _backoffBase;
      } catch (workerErr) {
        final String errMsg = _classifyError(workerErr);
        await _stream(taskId,
            '⚠️ $errMsg — إعادة المحاولة في ${backoff.inSeconds}ث... (محاولة $totalAttempts)');

        if (await _isPaused(taskId)) {
          return step.copyWith(
            status: AgentStepStatus.failed,
            lastError: 'PAUSED_BY_USER',
            attempts: step.attempts + totalAttempts,
          );
        }

        await _stream(taskId,
            '🔄 محاولة $totalAttempts: المشرف يُعيد كتابة التعليمات للعامل...');
        try {
          final String fixedPrompt = await _gateway.callSupervisor(
            systemPrompt:
                'You are the Project Manager AI. Worker AI failed. '
                'Generate a corrected, simpler prompt for the Worker. Return ONLY the prompt.',
            userMessage:
                'Worker failed for step "${step.type}" with error:\n$workerErr\n\n'
                'Original prompt:\n$currentWorkerPrompt\n\n'
                'Write a corrected prompt now:',
            supervisorProvider: supervisorProvider,
          );
          currentWorkerPrompt = fixedPrompt;
          await _stream(taskId,
              '✏️ المشرف أصدر تعليمات إصلاحية — إعادة المحاولة...');
        } catch (_) {
          await _stream(taskId,
              '🔁 المشرف غير متاح — استخدام التعليمات المدمجة...');
          currentWorkerPrompt = _buildBuiltinWorkerPrompt(
              step.type, specialty, domainPrompt);
        }

        await Future<void>.delayed(backoff);
        backoff = _nextBackoff(backoff);
        continue;
      }

      if (await _isPaused(taskId)) {
        return step.copyWith(
          status: AgentStepStatus.failed,
          lastError: 'PAUSED_BY_USER',
          attempts: step.attempts + totalAttempts,
        );
      }

      await _stream(taskId,
          '🔍 محاولة $totalAttempts: المشرف يراجع مخرجات ${_stepLabel(step.type)}...');
      await _repository.updateTaskProgress(
        taskId,
        (stepIndex + 0.7) / totalSteps,
        statusText:
            '🔍 المشرف يراجع مخرجات ${_stepLabel(step.type)} (جولة $totalAttempts)...',
      );

      try {
        final _ReviewResult review = await _supervisorReview(
          step: step,
          workerOutput: workerOutput,
          domainPrompt: domainPrompt,
          supervisorProvider: supervisorProvider,
          pdfBytes: needsPdf ? pdfBytes : null,
          filePath: needsPdf ? task.filePath : null,
        );

        if (review.isApproved) {
          final String raw = review.finalizedJson ?? workerOutput;

          await _stream(taskId,
              '♻️ التحقق من صحة JSON للخطوة ${_stepLabel(step.type)}...');
          final String healed = await _selfHealJson(
              raw, supervisorProvider, taskId, step.type);

          await _stream(taskId,
              '✅ المشرف صادق على ${_stepLabel(step.type)} ($totalAttempts جولة)');

          return step.copyWith(
            status: AgentStepStatus.done,
            outputPayload: healed,
            inputPayload: workerInstruction,
            attempts: step.attempts + totalAttempts,
            lastError: null,
          );
        } else {
          final String correction = review.correctionPrompt ??
              'Regenerate the complete ${step.type} JSON correctly.';
          await _stream(taskId,
              '🔁 محاولة $totalAttempts: المشرف رفض المخرجات — إعادة توجيه العامل...');
          
          currentWorkerPrompt = '$workerInstruction\n\n'
              '=== SUPERVISOR REJECTION & CRITICAL CORRECTIONS ===\n'
              'Your previous output was REJECTED for the following reasons:\n'
              '$correction\n'
              '===================================================\n'
              'You MUST rewrite the ENTIRE JSON output from scratch, strictly adhering to the original instructions AND fixing the issues mentioned above. DO NOT include this rejection message in your JSON output. Only return the requested medical data.';
        }
      } catch (reviewErr) {
        await _stream(taskId,
            '⚠️ المراجعة فشلت ($reviewErr) — قبول المخرجات تلقائياً...');
        final String healed = await _selfHealJson(
            workerOutput, supervisorProvider, taskId, step.type);

        return step.copyWith(
          status: AgentStepStatus.done,
          outputPayload: healed,
          inputPayload: workerInstruction,
          attempts: step.attempts + totalAttempts,
          lastError: null,
        );
      }
    }
  }

  Future<String> _relentlessSupervisorInstruction({
    required AgentTask task,
    required AgentStep step,
    required int stepIndex,
    required int totalSteps,
    required String specialty,
    required String domainPrompt,
    required Map<String, dynamic> assembled,
    String? filePath,
    List<int>? pdfBytes,
    AiProvider? supervisorProvider,
  }) async {
    int attempt = 0;
    Duration backoff = _backoffBase;
    final String taskId = task.id;

    while (true) {
      if (await _isPaused(taskId)) return 'PAUSED';
      attempt++;

      try {
        await _stream(taskId, '🧠 المشرف يُولد تعليمات لـ ${_stepLabel(step.type)} (محاولة $attempt)...');
        
        final String prompt = await _gateway.callSupervisor(
          systemPrompt: 'You are the QA Supervisor AI. Generate strict instructions for the Worker AI to execute step "${step.type}".\n$domainPrompt',
          userMessage: 'Task: ${task.title}\nSpecialty: $specialty\n\nGenerate instruction for step: ${step.type}.',
          filePath: filePath,
          fileBytes: pdfBytes,
          supervisorProvider: supervisorProvider,
        );
        return prompt;
      } catch (e) {
        final String errMsg = _classifyError(e);
        await _stream(taskId, '⚠️ $errMsg — إعادة محاولة المشرف في ${backoff.inSeconds}ث...');
        await Future<void>.delayed(backoff);
        backoff = _nextBackoff(backoff);
      }
    }
  }

  Future<_ReviewResult> _supervisorReview({
    required AgentStep step,
    required String workerOutput,
    required String domainPrompt,
    required AiProvider? supervisorProvider,
    List<int>? pdfBytes,
    String? filePath,
  }) async {
    final String reviewSystem =
        'You are the QA Supervisor AI for a medical content factory.\n'
        'Review the Worker\'s JSON output for step "${step.type}".\n\n'
        'Approve if: valid JSON, correct schema, no truncation.\n'
        'Reject if: malformed, empty arrays, placeholder content.\n\n'
        '$domainPrompt';

    final String reviewRequest =
        'Review this Worker output for step "${step.type}":\n\n'
        '${workerOutput.length > 4000 ? "${workerOutput.substring(0, 4000)}\n...[truncated]" : workerOutput}\n\n'
        'Respond with EXACTLY:\n'
        'APPROVED:{finalized JSON}\n'
        'or\n'
        'RETRY:{corrected Worker prompt}\n\n'
        'Start with APPROVED: or RETRY: only.';

    final String response = await _gateway.callSupervisor(
      systemPrompt: reviewSystem,
      userMessage: reviewRequest,
      filePath: filePath,
      fileBytes: pdfBytes,
      supervisorProvider: supervisorProvider,
    );

    return _parseReview(response, workerOutput);
  }

  _ReviewResult _parseReview(String response, String workerOutput) {
    final String t = response.trim();
    if (t.startsWith('APPROVED:')) {
      final String content = t.substring('APPROVED:'.length).trim();
      return _ReviewResult.approved(content.isNotEmpty ? content : workerOutput);
    }
    if (t.startsWith('RETRY:')) {
      return _ReviewResult.retry(t.substring('RETRY:'.length).trim());
    }
    return _ReviewResult.approved(t.isNotEmpty ? t : workerOutput);
  }

  Future<String> _selfHealJson(
    String raw,
    AiProvider? supervisorProvider,
    String taskId,
    String stepType,
  ) async {
    String cleaned = raw.trim();
    final RegExp jsonBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final Match? match = jsonBlockRegex.firstMatch(cleaned);
    if (match != null) {
      cleaned = match.group(1)!.trim();
    } else {
      final int firstBrace = cleaned.indexOf('{');
      final int firstBracket = cleaned.indexOf('[');
      int start = -1;
      if (firstBrace != -1 && firstBracket != -1) {
        start = firstBrace < firstBracket ? firstBrace : firstBracket;
      } else if (firstBrace != -1) {
        start = firstBrace;
      } else if (firstBracket != -1) {
        start = firstBracket;
      }
      if (start != -1) {
        final int lastBrace = cleaned.lastIndexOf('}');
        final int lastBracket = cleaned.lastIndexOf(']');
        int end = -1;
        if (lastBrace != -1 && lastBracket != -1) {
          end = lastBrace > lastBracket ? lastBrace : lastBracket;
        } else if (lastBrace != -1) {
          end = lastBrace;
        } else if (lastBracket != -1) {
          end = lastBracket;
        }
        if (end != -1 && end >= start) {
          cleaned = cleaned.substring(start, end + 1).trim();
        }
      }
    }

    try {
      jsonDecode(cleaned);
      return cleaned;
    } on FormatException catch (fe) {
      await _stream(taskId, '♻️ JSON غير صالح في ${_stepLabel(stepType)} — المشرف يُصلح...');
      int attempt = 0;
      Duration backoff = _backoffBase;
      String current = cleaned;

      while (true) {
        if (await _isPaused(taskId)) return current;
        attempt++;
        try {
          final String fixed = await _gateway.callSupervisor(
            systemPrompt: 'You are a JSON fixing AI. Fix this JSON output. Return ONLY valid JSON block.',
            userMessage: 'Fix this JSON (error: $fe):\n$current',
            supervisorProvider: supervisorProvider,
          );
          
          String fixedCleaned = fixed.trim();
          final Match? m2 = jsonBlockRegex.firstMatch(fixedCleaned);
          if (m2 != null) fixedCleaned = m2.group(1)!.trim();

          jsonDecode(fixedCleaned);
          return fixedCleaned;
        } catch (_) {
          await Future<void>.delayed(backoff);
          backoff = _nextBackoff(backoff);
          if (attempt >= 3) return current;
        }
      }
    }
  }

  Future<void> _finalizeTask(
    String taskId,
    Map<String, dynamic> assembled,
  ) async {
    await _stream(taskId, '🎉 اكتملت جميع الخطوات — جاري التجميع النهائي...');

    final AgentTask? latest = await _repository.getTaskById(taskId);
    if (latest != null) {
      final Map<String, dynamic> finalPayload = {};
      
      if (latest.payload != null && latest.payload!.trim().isNotEmpty) {
        try {
          final original = jsonDecode(latest.payload!);
          if (original is Map) {
            finalPayload.addAll(original as Map<String, dynamic>);
          }
        } catch (_) {}
      }
      
      final Map<String, dynamic> freshAssembled = Map<String, dynamic>.from(assembled);
      try {
        final List<AgentStep> freshSteps = await _repository.getStepsForTask(taskId);
        for (final s in freshSteps) {
          if (s.status == AgentStepStatus.done && s.outputPayload != null && s.outputPayload!.trim().isNotEmpty) {
            if (!freshAssembled.containsKey(s.type)) {
              _accumulate(freshAssembled, s.type, s.outputPayload!);
            }
          }
        }
      } catch (e) {
        debugPrint('AgentRuntime: ⚠️ Could not re-fetch steps from DB: $e');
      }
      
      List<dynamic>? extractArrayLocal(dynamic data, String expectedKey) {
        if (data is List) return data;
        if (data is Map) {
          if (data.containsKey(expectedKey) && data[expectedKey] is List) {
            return data[expectedKey] as List;
          }
          for (final value in data.values) {
            if (value is List) return value;
          }
        }
        return null;
      }

      List<dynamic> ensureList(dynamic payload, String key) {
        final extracted = extractArrayLocal(payload, key);
        if (extracted != null) return extracted;
        
        if (payload is Map) {
          if (key == 'concepts') {
             return payload.entries.map((e) => {"title": e.key, "content": e.value.toString()}).toList();
          } else {
             return [payload];
          }
        } else if (payload is String) {
          return [{"title": "General", "content": payload}];
        }
        return [];
      }

      if (freshAssembled.containsKey(AgentStepType.extractConcepts)) {
        finalPayload['concepts'] = ensureList(freshAssembled[AgentStepType.extractConcepts], 'concepts');
      }
      if (freshAssembled.containsKey(AgentStepType.generateFlashcards)) {
        finalPayload['flashcards'] = ensureList(freshAssembled[AgentStepType.generateFlashcards], 'flashcards');
      }
      if (freshAssembled.containsKey(AgentStepType.generateMcqs)) {
        finalPayload['mcqs'] = ensureList(freshAssembled[AgentStepType.generateMcqs], 'mcqs');
      }
      if (freshAssembled.containsKey(AgentStepType.generateCases)) {
        finalPayload['clinical_cases'] = ensureList(freshAssembled[AgentStepType.generateCases], 'clinical_cases');
      }
      
      for (final entry in freshAssembled.entries) {
        if (!finalPayload.containsKey(entry.key)) {
          finalPayload[entry.key] = entry.value;
        }
      }
      
      final String payload = jsonEncode(finalPayload);

      final db = await DatabaseHelper.instance.database;
      await db.update(
        DatabaseHelper.tableAgentTasks,
        latest
            .copyWith(
              status: AgentTaskStatus.pendingApproval,
              progress: 1.0,
              currentStatusText: '✅ اكتملت جميع الخطوات — بانتظار الموافقة',
              payload: payload,
            )
            .toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[taskId],
      );
    }

    await _repository.updateTaskStatus(
      taskId,
      AgentTaskStatus.pendingApproval,
      statusText: '✅ اكتملت جميع الخطوات — بانتظار الموافقة',
    );
    
    unawaited(TaskNotificationService.showTaskCompleted(
      'اكتملت معالجة المحاضرة 🎉',
      'محاضرتك "${latest?.title ?? ''}" أصبحت جاهزة الآن للمراجعة والاعتماد!',
    ));
  }

  List<String> _parsePlanJson(String raw) {
    String cleaned = raw.trim();
    final RegExp jsonBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final Match? match = jsonBlockRegex.firstMatch(cleaned);
    if (match != null) {
      cleaned = match.group(1)!.trim();
    } else {
      final int firstBracket = cleaned.indexOf('[');
      if (firstBracket != -1) {
        final int lastBracket = cleaned.lastIndexOf(']');
        if (lastBracket != -1 && lastBracket >= firstBracket) {
          cleaned = cleaned.substring(firstBracket, lastBracket + 1).trim();
        }
      }
    }
    try {
      final dynamic decoded = jsonDecode(cleaned);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (e) {
      debugPrint('AgentRuntime: Plan JSON parse error: $e');
    }
    return [];
  }

  void _accumulate(Map<String, dynamic> c, String type, String raw) {
    try {
      c[type] = jsonDecode(raw);
    } catch (_) {
      c[type] = raw;
    }
  }

  String _extractSpecialty(AgentTask task) {
    if (task.payload != null && task.payload!.isNotEmpty) {
      try {
        final map = jsonDecode(task.payload!);
        if (map['specialty'] != null) return map['specialty'].toString();
      } catch (_) {}
    }
    return 'internal_medicine';
  }

  String _classifyError(dynamic e) {
    return 'تعذر الاتصال بالمزود (${e.toString().split('\n').first})';
  }

  Duration _nextBackoff(Duration current) {
    final next = current * 2;
    return next.inSeconds > 60 ? const Duration(seconds: 60) : next;
  }

  String _stepLabel(String type) {
    switch (type) {
      case AgentStepType.extractConcepts: return 'استخراج المفاهيم';
      case AgentStepType.generateMcqs: return 'توليد أسئلة MCQ';
      case AgentStepType.generateFlashcards: return 'توليد البطاقات';
      case AgentStepType.generateCases: return 'توليد الحالات السريرية';
      case AgentStepType.validateOutput: return 'التحقق النهائي';
      default: return type;
    }
  }

  String _formatStatus(String type, int current, int total) {
    return '⏳ خطوة $current من $total: ${_stepLabel(type)}...';
  }

  Future<String> _stream(String taskId, String message) async {
    final String logId = AgentLogService.instance.log(taskId, message);
    try {
      await _repository.updateTaskStatus(
        taskId,
        AgentTaskStatus.running,
        statusText: message,
      );
    } catch (_) {}
    return logId;
  }

  Future<List<AgentStep>> _persistSteps(String taskId, List<String> types) async {
    final List<AgentStep> created = [];
    for (int i = 0; i < types.length; i++) {
      final step = AgentStep(
        id: '${taskId}_step_$i',
        taskId: taskId,
        sequenceIndex: i,
        type: types[i],
      );
      await _repository.createStep(step);
      created.add(step);
    }
    return created;
  }

  Future<List<AgentStep>> _createDefaultSteps(AgentTask task) async {
    return _persistSteps(task.id, [
      AgentStepType.extractConcepts,
      AgentStepType.generateFlashcards,
      AgentStepType.generateMcqs,
      AgentStepType.generateCases,
    ]);
  }

  String _buildBuiltinWorkerPrompt(String type, String specialty, String domain) {
    return 'Execute step $type for $specialty. $domain. Return ONLY JSON.';
  }

  static Future<String> _extractPdfTextInIsolate(List<int> bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String text = extractor.extractText();
      document.dispose();
      return text;
    } catch (e) {
      return '';
    }
  }
}
