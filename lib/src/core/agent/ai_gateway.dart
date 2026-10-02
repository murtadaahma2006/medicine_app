import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/ai_provider.dart';
import '../services/ai_service.dart';
import 'models/models.dart';
import 'system_prompts.dart';

/// استثناء خاص بأخطاء بوابة الذكاء الاصطناعي (AiGatewayException).
class AiGatewayException implements Exception {
  AiGatewayException(this.message, {this.statusCode, this.originalError});

  final String message;
  final int? statusCode;
  final Object? originalError;

  @override
  String toString() => 'AiGatewayException: $message (StatusCode: $statusCode)';
}

/// توقيع المعالج التعددي (Multimodal API Call Handler) الداعم لإرسال المستندات والصور.
typedef AiMultimodalApiCall = Future<String?> Function(
  String systemPrompt,
  String userMessage, {
  String? filePath,
  List<int>? fileBytes,
  AiProvider? provider,
});

/// بوابة الاتصال بمزودات الذكاء الاصطناعي (AiGateway — Planner-Executor Dual Architecture).
///
/// نمط المخطط–المنفذ (Planner-Executor):
///   • المشرف (Supervisor/Planner): يُخطط، يُفوّض، يراجع، ويُصادق.
///   • العامل (Worker/Executor): يُنفذ تعليمات المشرف حرفياً.
///   • كلاهما يمكن أن يكون أي نموذج (Gemini, GLM, Llama, Claude, إلخ).
///
/// Dart يعمل كـ State Tracker: يمرر الرسائل، يحفظ النقاط في SQLite.
class AiGateway {
  AiGateway({
    this.maxRetries = 3,
    this.initialBackoff = const Duration(seconds: 5),
    this.backoffMultiplier = 2.0,
    AiMultimodalApiCall? apiCallHandler,
    void Function(Duration duration)? sleepHandler,
  })  : _apiCallHandler = apiCallHandler ?? _defaultMultimodalCall,
        _sleepHandler = sleepHandler;

  final int maxRetries;
  final Duration initialBackoff;
  final double backoffMultiplier;
  final AiMultimodalApiCall _apiCallHandler;
  final void Function(Duration duration)? _sleepHandler;

  // ─────────────────────────────────────────────────────────────────────────
  // PLANNER PRIMITIVES — دوال الاتصال المباشر بالمشرف والعامل
  // ─────────────────────────────────────────────────────────────────────────

  /// اتصال مباشر بالمشرف (Supervisor call) مع دعم Multimodal.
  ///
  /// يُستخدم للتخطيط، توليد التعليمات، مراجعة مخرجات العامل، وإصدار أحكام.
  Future<String> callSupervisor({
    required String systemPrompt,
    required String userMessage,
    String? filePath,
    List<int>? fileBytes,
    AiProvider? supervisorProvider,
  }) async {
    debugPrint(
      'AiGateway[SUPERVISOR]: Calling provider '
      '${supervisorProvider?.name ?? "default"} | '
      'filePath: ${filePath != null ? "attached" : "none"}',
    );

    final String? result = await _withRetry(() => _apiCallHandler(
          systemPrompt,
          userMessage,
          filePath: filePath,
          fileBytes: fileBytes,
          provider: supervisorProvider,
        ));

    if (result == null || result.trim().isEmpty) {
      throw AiGatewayException('Supervisor returned empty response');
    }
    return result.trim();
  }

  /// اتصال مباشر بالعامل (Worker call) — نصي بحت، بدون Multimodal.
  ///
  /// يُستخدم لتنفيذ التعليمات الصادرة من المشرف.
  Future<String> callWorker({
    required String systemPrompt,
    required String workerPrompt,
    AiProvider? workerProvider,
    AiProvider? supervisorProvider, // fallback إن لم يُحدَّد عامل
  }) async {
    final AiProvider? effective = workerProvider ?? supervisorProvider;
    debugPrint(
      'AiGateway[WORKER]: Calling provider '
      '${effective?.name ?? "default"}',
    );

    final String? result = await _withRetry(() => _apiCallHandler(
          systemPrompt,
          workerPrompt,
          provider: effective,
        ));

    if (result == null || result.trim().isEmpty) {
      throw AiGatewayException('Worker returned empty response');
    }
    return result.trim();
  }

  /// اتصال مباشر بالعامل مع تدفق البيانات (Streaming Worker call).
  ///
  /// يُرجع البيانات على شكل تيار من القطع (Chunks) فور توفرها.
  Stream<String> callWorkerStream({
    required String systemPrompt,
    required String workerPrompt,
    AiProvider? workerProvider,
    AiProvider? supervisorProvider, // fallback إن لم يُحدَّد عامل
  }) async* {
    final AiProvider? effective = workerProvider ?? supervisorProvider;
    debugPrint(
      'AiGateway[WORKER_STREAM]: Calling provider '
      '${effective?.name ?? "default"}',
    );

    yield* _apiCallHandlerStream(
      systemPrompt,
      workerPrompt,
      provider: effective,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEGACY COMPAT — executeStep (يحافظ على توافق الاختبارات القديمة)
  // ─────────────────────────────────────────────────────────────────────────

  /// [LEGACY] تنفيذ خطوة ثابتة عبر البوابة الثنائية.
  ///
  /// محفوظ للتوافق مع اختبارات الوحدة الموجودة.
  /// في التشغيل الجديد يُستخدم [callSupervisor] و [callWorker] مباشرةً.
  Future<AgentStep> executeStep(
    AgentStep step, {
    String? filePath,
    String? specialty,
    AiProvider? supervisorProvider,
    AiProvider? workerProvider,
    AiProvider? provider,
  }) async {
    final AiProvider? effectiveSupervisor = supervisorProvider ?? provider;
    final AiProvider? effectiveWorker = workerProvider;

    const Set<String> supervisorSteps = {
      AgentStepType.extractConcepts,
      AgentStepType.validateOutput,
    };
    final bool isSupervisorStep = supervisorSteps.contains(step.type);

    final AiProvider? resolvedProvider = isSupervisorStep
        ? effectiveSupervisor
        : (effectiveWorker ?? effectiveSupervisor);

    final String baseSystemPrompt =
        SystemPrompts.getPromptForSpecialty(specialty ?? 'internal_medicine');
    final String stepInstruction = _buildStepInstruction(step.type);
    final String fullSystemPrompt =
        '$baseSystemPrompt\n\n[Step Task: $stepInstruction]';
    final String userMessage =
        step.inputPayload ?? 'Process input data for step: ${step.type}';

    List<int>? fileBytes;
    if (filePath != null && filePath.isNotEmpty && isSupervisorStep) {
      try {
        final File file = File(filePath);
        if (await file.exists()) {
          fileBytes = await file.readAsBytes();
        }
      } catch (e) {
        debugPrint('AiGateway: File read warning for $filePath: $e');
      }
    }

    final String? result = await _withRetry(() => _apiCallHandler(
          fullSystemPrompt,
          userMessage,
          filePath: filePath,
          fileBytes: fileBytes,
          provider: resolvedProvider,
        ));

    if (result == null || result.trim().isEmpty) {
      throw AiGatewayException('Empty output from provider for step ${step.type}');
    }

    return step.copyWith(
      status: AgentStepStatus.done,
      outputPayload: result.trim(),
      attempts: step.attempts + 1,
      lastError: null,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SELF-HEALING — إصلاح JSON التالف عبر المشرف
  // ─────────────────────────────────────────────────────────────────────────

  /// طلب إصلاح وتصحيح نصوص JSON التالفة (Self-Healing JSON Repair).
  Future<String?> repairJson(
    String invalidJson,
    String errorDetails, {
    AiProvider? provider,
    AiProvider? supervisorProvider,
  }) async {
    const String systemPrompt =
        'You are an expert JSON syntax repair bot. The user will provide invalid or '
        'truncated JSON output along with syntax error details.\n'
        'Your SOLE TASK is to fix all JSON syntax errors, restore missing quotes/brackets, '
        'complete any truncated keys/values, and return ONLY valid parsable JSON.\n'
        'Do NOT surround output in markdown codeblocks (```json). Return raw JSON only.';

    final String userMessage =
        'The following JSON is invalid and failed with error:\n$errorDetails\n\n'
        'Invalid JSON Output:\n$invalidJson\n\n'
        'Please repair and return ONLY valid, complete JSON.';

    debugPrint('AiGateway: Self-healing JSON via supervisor...');
    return _apiCallHandler(
      systemPrompt,
      userMessage,
      provider: supervisorProvider ?? provider,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// إعادة المحاولة مع Exponential Backoff.
  Future<String?> _withRetry(
    Future<String?> Function() fn,
  ) async {
    int attemptsMade = 0;
    Duration currentBackoff = initialBackoff;
    Object? lastException;

    while (attemptsMade < maxRetries) {
      attemptsMade++;
      try {
        return await fn();
      } catch (e) {
        lastException = e;
        debugPrint('AiGateway: Attempt $attemptsMade/$maxRetries failed: $e');

        if (attemptsMade >= maxRetries) break;

        final Duration delay = currentBackoff;
        currentBackoff = Duration(
          milliseconds: (currentBackoff.inMilliseconds * backoffMultiplier).round(),
        );
        debugPrint('AiGateway: Retrying in ${delay.inSeconds}s...');

        final void Function(Duration)? sleeper = _sleepHandler;
        if (sleeper != null) {
          sleeper(delay);
        } else {
          await Future<void>.delayed(delay);
        }
      }
    }

    throw AiGatewayException(
      'فشل استدعاء API بعد $attemptsMade محاولات: ${lastException?.toString()}',
      originalError: lastException,
    );
  }

  static Future<String?> _defaultMultimodalCall(
    String systemPrompt,
    String userMessage, {
    String? filePath,
    List<int>? fileBytes,
    AiProvider? provider,
  }) async {
    final String enrichedMessage = (filePath != null && filePath.isNotEmpty)
        ? '$userMessage\n[Multimodal PDF Document Attached: $filePath '
            '(${fileBytes?.length ?? 0} bytes)]'
        : userMessage;
    return AIService.generateContent(systemPrompt, enrichedMessage,
        provider: provider);
  }

  static Stream<String> _apiCallHandlerStream(
    String systemPrompt,
    String userMessage, {
    AiProvider? provider,
  }) async* {
    yield* AIService.generateContentStream(systemPrompt, userMessage, provider: provider);
  }

  bool _isRateLimitError(Object error) {
    final String str = error.toString().toLowerCase();
    return str.contains('429') ||
        str.contains('rate limit') ||
        str.contains('too many requests') ||
        str.contains('quota');
  }

  // ignore: unused_element
  bool _isRateLimit(Object e) => _isRateLimitError(e);

  String _buildStepInstruction(String stepType) {
    switch (stepType) {
      case AgentStepType.extractConcepts:
        return 'Extract all medical concepts, pathophysiology, clinical features, '
            'and management protocols in full detail (Zero Data Loss).';
      case AgentStepType.generateMcqs:
        return 'Generate high-yield clinical MCQs with detailed Arabic explanations.';
      case AgentStepType.generateFlashcards:
        return 'Generate active recall flashcards with short prompts and answers.';
      case AgentStepType.generateCases:
        return 'Generate a realistic clinical case with vitals, labs, and sequential steps.';
      case AgentStepType.validateOutput:
        return 'Validate and output the final valid JSON schema v2.0.0.';
      default:
        return 'Process step $stepType for the lecture.';
    }
  }
}
