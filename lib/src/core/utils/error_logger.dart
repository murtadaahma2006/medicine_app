import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// ─────────────────────────────────────────────────────────────────────
/// سجل الأخطاء العالمي — المرحلة 0 من جولة الاستقرار.
///
/// يُسجّل كل استثناء من:
///   • FlutterError.onError   (خطأ ويدجت / بناء / مؤقت)
///   • PlatformDispatcher.instance.onError  (خطأ Dart خارج الإطار)
///
/// التخزين:
///   • حلقة ذاكرة حتى 100 سجل (الأقدم يُستبعد تلقائياً).
///   • ملف محلي يُحفظ الخطأ سطراً سطراً (debug فقط لتوفير البطارية).
///
/// الوصول:
///   • [AppErrorLogger.instance] — singleton آمن.
///   • [AppErrorLogger.entries]  — قائمة السجلات.
///   • [AppErrorLogger.clear]    — مسح الحلقة (زر الصفحة).
/// ─────────────────────────────────────────────────────────────────────
class AppErrorLogger {
  AppErrorLogger._();
  static final AppErrorLogger instance = AppErrorLogger._();

  static const int _maxEntries = 100;
  static const String _fileName = 'app_error_log.txt';

  final List<ErrorEntry> _entries = <ErrorEntry>[];

  /// الاستماع للتحديثات من [errorLogPage].
  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// قائمة السجلات (نسخة غير قابلة للتعديل من الخارج).
  List<ErrorEntry> get entries => List<ErrorEntry>.unmodifiable(_entries);

  /// تهيئة الخطّافات — يُستدعى مرة واحدة في [main] قبل [runApp].
  void init() {
    // خطأ Flutter (ويدجت / بناء / تشخيص)
    FlutterError.onError = (FlutterErrorDetails details) {
      _record(
        type: 'FlutterError',
        error: details.exceptionAsString(),
        stack: details.stack,
      );
      // في debug: نطبع بشكل كامل كما في الافتراضي.
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };

    // خطأ Dart غير معالج خارج الإطار (isolate الرئيسي)
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _record(
        type: 'PlatformError',
        error: error.toString(),
        stack: stack,
      );
      if (kDebugMode) {
        debugPrint('[AppErrorLogger] PlatformError: $error\n$stack');
      }
      return true; // الخطأ معالَج — لا إنهاء التطبيق
    };
  }

  /// يسجّل خطأً يدوياً (مثلاً من اختبار متعمد).
  void record({required String type, required Object error, StackTrace? stack}) {
    _record(type: type, error: error.toString(), stack: stack);
  }

  void _record({
    required String type,
    required String error,
    StackTrace? stack,
  }) {
    final ErrorEntry entry = ErrorEntry(
      timestamp: DateTime.now(),
      type: type,
      message: error,
      stackSummary: _summarizeStack(stack),
    );

    // حلقة: الأقدم يُستبعد عند امتلاء الحلقة
    if (_entries.length >= _maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(entry);

    // إشعار المستمعين (صفحة السجل)
    changeNotifier.value++;

    // حفظ في الملف المحلي (debug فقط — لا يعطل أبداً)
    if (kDebugMode) {
      unawaited(_appendToFile(entry));
    }
  }

  /// أول 8 أسطر من الـstack فقط — كافية للتشخيص وموفِّرة للمساحة.
  String _summarizeStack(StackTrace? stack) {
    if (stack == null) return '';
    final List<String> lines = stack.toString().split('\n');
    return lines.take(8).join('\n');
  }

  Future<void> _appendToFile(ErrorEntry entry) async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File('${dir.path}/$_fileName');
      final String line =
          '[${entry.timestamp.toIso8601String()}] [${entry.type}]\n'
          '${entry.message}\n'
          '${entry.stackSummary}\n'
          '─────\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // صمت مقصود — الكتابة إلى الملف لا يجب أن تُعطل أي شيء
    }
  }

  /// مسح الحلقة وإشعار المستمعين.
  void clear() {
    _entries.clear();
    changeNotifier.value++;
    if (kDebugMode) {
      unawaited(_clearFile());
    }
  }

  Future<void> _clearFile() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File('${dir.path}/$_fileName');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // صمت مقصود
    }
  }
}

/// سجل خطأ واحد.
class ErrorEntry {
  const ErrorEntry({
    required this.timestamp,
    required this.type,
    required this.message,
    required this.stackSummary,
  });

  final DateTime timestamp;
  final String type;
  final String message;
  final String stackSummary;

  /// النص الكامل للنسخ (المرحلة 0: زر نسخ لكل خطأ).
  String get fullText =>
      '[${timestamp.toIso8601String()}] [$type]\n$message\n$stackSummary';
}
