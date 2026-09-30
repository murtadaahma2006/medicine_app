import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GoogleSignInException — خطأ مكتوب يُعيد سبباً قابلاً للعرض للمستخدم.
// ─────────────────────────────────────────────────────────────────────────────

enum GoogleSignInFailure {
  cancelled,      // المستخدم أغلق نافذة OAuth
  network,        // لا إنترنت
  configuration,  // خطأ في الإعداد (clientId، Info.plist، ...)
  unknown,        // أي خطأ آخر
}

class GoogleSignInException implements Exception {
  const GoogleSignInException(this.failure, {this.message, this.original});

  final GoogleSignInFailure failure;
  final String? message;
  final Object? original;

  /// رسالة جاهزة للعرض للمستخدم بالعربية.
  String get arabicMessage {
    switch (failure) {
      case GoogleSignInFailure.cancelled:
        return 'تم إلغاء تسجيل الدخول.';
      case GoogleSignInFailure.network:
        return 'تعذَّر الاتصال بالشبكة. تحقق من الإنترنت وأعد المحاولة.';
      case GoogleSignInFailure.configuration:
        return 'خطأ في إعداد Google Sign-In. تواصل مع المطوِّر.';
      case GoogleSignInFailure.unknown:
        return 'حدث خطأ غير متوقع. يرجى إعادة المحاولة.';
    }
  }

  @override
  String toString() => 'GoogleSignInException(${failure.name}): $message';
}

//
// مسؤوليات:
//  • تسجيل الدخول بـ Google Sign-In (نطاق القراءة فقط).
//  • سرد ملفات PDF في Drive الخاص بالمستخدم.
//  • تنزيل الملف مجزَّءاً إلى مجلد مؤقت مع نشر تقدم البايتات.
//
// مبدأ الأمان للـ iPad المُثبَّت يدوياً (Sideloaded):
//  • نستخدم GoogleSignIn.signInSilently أولاً — يُعيد الجلسة القديمة بلا
//    نافذة إذا كانت المصادقة مُخزَّنة بعد (بلا Keychain-sharing بحاجة).
//  • عند فشل الصامت نفتح نافذة OAuth الكاملة.
//  • لا نخزّن access-token يدوياً — GoogleSignIn يُجدِّده تلقائياً.
//
// مبدأ الأمان للـ RAM:
//  • نستخدم MediaStream من googleapis مباشرة ونكتبه بايتاً بايتاً
//    (Stream<List<int>>) إلى ملف مؤقت — لا نجمع الـ Uint8List كله
//    في الذاكرة أبداً مهما كان حجم الكتاب الطبي.
// ─────────────────────────────────────────────────────────────────────────────

/// تقدم التنزيل — البايتات المُستقبَلة والإجمالية.
/// [total] = -1 إذا لم يُعرف الحجم مسبقاً.
class DriveDownloadProgress {
  const DriveDownloadProgress({
    required this.received,
    required this.total,
  });

  final int received;
  final int total;

  /// نسبة الإنجاز [0.0 → 1.0]، أو null إذا كانت [total] مجهولة.
  double? get fraction =>
      (total > 0) ? (received / total).clamp(0.0, 1.0) : null;

  /// نسبة مئوية [0 → 100]، أو null إذا كانت [total] مجهولة.
  int? get percent => fraction != null ? (fraction! * 100).round() : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// _GoogleAuthClient — غلاف بسيط يُرفق Authorization header لكل طلب.
// ─────────────────────────────────────────────────────────────────────────────

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// GoogleDriveService
// ─────────────────────────────────────────────────────────────────────────────

class GoogleDriveService {
  GoogleDriveService._();

  static final GoogleDriveService instance = GoogleDriveService._();

  // ── إعداد google_sign_in ──────────────────────────────────────────────────

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '488954400037-noj5aj0ch4v9cc8o284s8kd5lfipqfov.apps.googleusercontent.com',
    scopes: <String>[drive.DriveApi.driveReadonlyScope],
  );

  GoogleSignInAccount? _currentUser;

  /// الحساب المسجَّل حالياً، أو null إذا لم يُسجَّل دخول بعد.
  GoogleSignInAccount? get currentUser => _currentUser;

  bool get isSignedIn => _currentUser != null;

  // ── تسجيل الدخول ─────────────────────────────────────────────────────────

  /// يحاول استعادة الجلسة بصمت أولاً، وإلا يفتح نافذة OAuth.
  ///
  /// عند الفشل يرمي [GoogleSignInException] بدلاً من الـ crash:
  ///  • [GoogleSignInFailure.cancelled]     ← إغلاق نافذة OAuth
  ///  • [GoogleSignInFailure.network]       ← لا إنترنت
  ///  • [GoogleSignInFailure.configuration] ← خطأ إعداد iOS (Info.plist / clientId)
  ///  • [GoogleSignInFailure.unknown]       ← أي خطأ آخر
  Future<GoogleSignInAccount> signIn() async {
    // ── 1. محاولة صامتة (إعادة استخدام Token مُخزَّن) ──────────────────────
    try {
      final GoogleSignInAccount? silent =
          await _googleSignIn.signInSilently();
      if (silent != null) {
        _currentUser = silent;
        debugPrint(
            'GoogleDriveService ✓ صامت — ${silent.email}');
        return silent;
      }
    } on PlatformException catch (e) {
      // فشل صامت غير مُعطِّل — نتابع للتفاعلي.
      debugPrint('GoogleDriveService: signInSilently PlatformException: '
          '${e.code} — ${e.message}');
    } catch (e) {
      debugPrint('GoogleDriveService: signInSilently error: $e');
    }

    // ── 2. تسجيل دخول تفاعلي عبر نافذة Google OAuth ──────────────────────
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account == null) {
        // المستخدم أغلق النافذة بدون اختيار حساب.
        debugPrint('GoogleDriveService: ألغى المستخدم تسجيل الدخول.');
        throw const GoogleSignInException(
          GoogleSignInFailure.cancelled,
          message: 'User dismissed the sign-in dialog.',
        );
      }

      _currentUser = account;
      debugPrint(
          'GoogleDriveService ✓ تفاعلي — ${account.email}');
      return account;
    } on GoogleSignInException {
      // أعِد رمي الاستثناء المكتوب دون تعديل.
      rethrow;
    } on PlatformException catch (e, st) {
      debugPrint(
          'GoogleDriveService ✗ PlatformException: ${e.code} — ${e.message}\n$st');
      // رموز خطأ شائعة على iOS:
      //  sign_in_failed         ← خطأ عام في الإعداد
      //  sign_in_canceled       ← إلغاء المستخدم
      //  network_error          ← لا إنترنت
      //  developer_error        ← clientId خاطئ أو مفقود من Info.plist
      final String code = e.code.toLowerCase();
      if (code.contains('cancel')) {
        throw GoogleSignInException(
          GoogleSignInFailure.cancelled,
          message: e.message,
          original: e,
        );
      } else if (code.contains('network')) {
        throw GoogleSignInException(
          GoogleSignInFailure.network,
          message: e.message,
          original: e,
        );
      } else if (code.contains('developer') ||
          code.contains('configuration') ||
          code.contains('failed')) {
        throw GoogleSignInException(
          GoogleSignInFailure.configuration,
          message: '${e.code}: ${e.message}',
          original: e,
        );
      }
      throw GoogleSignInException(
        GoogleSignInFailure.unknown,
        message: '${e.code}: ${e.message}',
        original: e,
      );
    } catch (e, st) {
      debugPrint('GoogleDriveService ✗ unexpected: $e\n$st');
      throw GoogleSignInException(
        GoogleSignInFailure.unknown,
        message: e.toString(),
        original: e,
      );
    }
  }

  /// تسجيل الخروج وتنظيف الجلسة — محمي بالكامل.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      debugPrint('GoogleDriveService: تم تسجيل الخروج.');
    } catch (e) {
      debugPrint('GoogleDriveService: signOut error (متجاهَل): $e');
    } finally {
      _currentUser = null;
    }
  }

  // ── بناء عميل Drive مُوثَّق ──────────────────────────────────────────────

  /// يُنشئ [DriveApi] مُرتبطاً بالحساب المُوثَّق الحالي.
  ///
  /// إذا انتهت صلاحية Token يُجدِّدها تلقائياً عبر [authHeaders].
  /// إذا فشل التجديد يُحاول signInSilently مرة واحدة كاحتياطي.
  Future<drive.DriveApi> _buildDriveApi() async {
    GoogleSignInAccount? user = _currentUser;
    if (user == null) {
      throw const GoogleSignInException(
        GoogleSignInFailure.unknown,
        message: 'يجب تسجيل الدخول أولاً.',
      );
    }

    try {
      final Map<String, String> headers = await user.authHeaders;
      return drive.DriveApi(_GoogleAuthClient(headers));
    } on PlatformException catch (e) {
      debugPrint('GoogleDriveService: authHeaders PlatformException: '
          '${e.code} — ${e.message}. محاولة تجديد الجلسة...');
      // احتياطي: تجديد صامت
      try {
        final GoogleSignInAccount? refreshed =
            await _googleSignIn.signInSilently();
        if (refreshed != null) {
          _currentUser = refreshed;
          user = refreshed;
          final Map<String, String> headers = await user.authHeaders;
          return drive.DriveApi(_GoogleAuthClient(headers));
        }
      } catch (_) {}
      // لم ينجح التجديد — يجب إعادة تسجيل الدخول.
      _currentUser = null;
      throw const GoogleSignInException(
        GoogleSignInFailure.unknown,
        message: 'انتهت الجلسة — يرجى تسجيل الدخول مجدداً.',
      );
    } catch (e) {
      debugPrint('GoogleDriveService: _buildDriveApi error: $e');
      throw GoogleSignInException(
        GoogleSignInFailure.unknown,
        message: e.toString(),
        original: e,
      );
    }
  }

  // ── ثابتات أنواع الملفات (MIME types) ───────────────────────────────────
  static const String driveFolderMimeType =
      'application/vnd.google-apps.folder';
  static const String pdfMimeType = 'application/pdf';

  // ── استعلام عن عناصر Drive الهيكلية (مجلدات وملفات PDF) ────────────────────

  /// يُعيد قائمة العناصر (مجلدات فرعية وملفات PDF) داخل مجلد محدد [folderId].
  ///
  /// المجلد الافتراضي: `'root'` (مجلد ملفاتي الرئيسي).
  /// الاستعلام: `'folderId' in parents AND (mimeType = folder OR pdf) AND trashed = false`
  /// الترتيب: المجلدات تتصدر القائمة أولاً، ثم ملفات PDF، مرتبة أبجدياً.
  Future<List<drive.File>> listDriveItems({String folderId = 'root'}) async {
    final drive.DriveApi api = await _buildDriveApi();

    final String query =
        "'$folderId' in parents and (mimeType = '$driveFolderMimeType' or mimeType = '$pdfMimeType') and trashed = false";

    final drive.FileList result = await api.files.list(
      q: query,
      orderBy: 'name asc',
      pageSize: 500,
      $fields: 'files(id,name,size,modifiedTime,mimeType)',
    );

    final List<drive.File> items = result.files ?? <drive.File>[];

    // ترتيب: المجلدات أولاً (أبجدياً)، ثم الملفات (أبجدياً)
    items.sort((drive.File a, drive.File b) {
      final bool aIsFolder = a.mimeType == driveFolderMimeType;
      final bool bIsFolder = b.mimeType == driveFolderMimeType;

      if (aIsFolder && !bIsFolder) return -1;
      if (!aIsFolder && bIsFolder) return 1;
      return (a.name ?? '').compareTo(b.name ?? '');
    });

    debugPrint(
        'GoogleDriveService: وُجد ${items.length} عنصر داخل المجلد ($folderId).');
    return items;
  }

  /// يُعيد قائمة جميع ملفات PDF (استعلام سطحي شامل) — احتياطي للتوافق.
  Future<List<drive.File>> listPdfFiles() async {
    final drive.DriveApi api = await _buildDriveApi();

    final drive.FileList result = await api.files.list(
      q: "mimeType='$pdfMimeType' and trashed=false",
      orderBy: 'modifiedTime desc',
      pageSize: 200,
      $fields: 'files(id,name,size,modifiedTime,mimeType)',
    );

    final List<drive.File> files = result.files ?? <drive.File>[];
    debugPrint('GoogleDriveService: وُجد ${files.length} ملف PDF.');
    return files;
  }

  // ── تنزيل ملف PDF ────────────────────────────────────────────────────────

  /// ينزّل [driveFile] إلى مجلد مؤقت محلي.
  ///
  /// يُرسل تقدم التنزيل عبر [onProgress] (آمن للاستدعاء على main isolate).
  ///
  /// الأمان:
  ///  • يتحقق من وجود النسخة المُخزَّنة محلياً أولاً لتجنب إعادة التنزيل.
  ///  • يكتب إلى io.File بـ IOSink مفتوح — لا يُجمَّع المحتوى كله في RAM.
  Future<io.File> downloadPdfToTemp(
    drive.File driveFile, {
    void Function(DriveDownloadProgress)? onProgress,
  }) async {
    final String fileId = driveFile.id ?? '';
    final String fileName = driveFile.name ?? 'document.pdf';
    final int totalBytes = int.tryParse(driveFile.size ?? '') ?? -1;

    if (fileId.isEmpty) throw ArgumentError('معرّف الملف فارغ.');

    // ── مسار الملف المؤقت ──
    final io.Directory tempDir = await getTemporaryDirectory();
    // اسم آمن للملف: نزيل الرموز الغريبة ونبقي الأحرف والأرقام والنقطة.
    final String safeFileName =
        fileName.replaceAll(RegExp(r'[^\w\s\-.]'), '_');
    final io.File localFile = io.File('${tempDir.path}/drive_${fileId}_$safeFileName');

    // ── تحقق مسبق: إذا كان الملف موجوداً بالحجم الصحيح نرجعه مباشرة ──
    if (await localFile.exists()) {
      final int existingSize = await localFile.length();
      if (totalBytes > 0 && existingSize == totalBytes) {
        debugPrint('GoogleDriveService: الملف مُخزَّن محلياً — تخطي التنزيل.');
        onProgress?.call(DriveDownloadProgress(
          received: totalBytes,
          total: totalBytes,
        ));
        return localFile;
      }
      // حجم مختلف = ملف جزئي أو تالف — نُعيد تنزيله.
      await localFile.delete();
    }

    debugPrint('GoogleDriveService: بدء تنزيل "$fileName" (${totalBytes ~/ 1024} كيلوبايت)...');

    final drive.DriveApi api = await _buildDriveApi();

    // ── تنزيل عبر Media Stream ──
    // alt='media' تُعيد ملف ثنائياً خاماً (لا JSON للملفات الحقيقية).
    final drive.Media media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final io.IOSink sink = localFile.openWrite();
    int received = 0;

    try {
      await for (final List<int> chunk in media.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DriveDownloadProgress(
          received: received,
          total: totalBytes,
        ));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    debugPrint('GoogleDriveService: اكتمل التنزيل → ${localFile.path}');
    return localFile;
  }

  // ── حذف ملف مؤقت واحد (اختياري — تنظيف يدوي) ───────────────────────────

  /// يحذف النسخة المحلية المؤقتة لـ [driveFile] إذا كانت موجودة.
  Future<void> deleteLocalCache(drive.File driveFile) async {
    final String fileId = driveFile.id ?? '';
    final String fileName = driveFile.name ?? 'document.pdf';
    if (fileId.isEmpty) return;
    final io.Directory tempDir = await getTemporaryDirectory();
    final String safeFileName =
        fileName.replaceAll(RegExp(r'[^\w\s\-.]'), '_');
    final io.File localFile =
        io.File('${tempDir.path}/drive_${fileId}_$safeFileName');
    if (await localFile.exists()) {
      await localFile.delete();
      debugPrint('GoogleDriveService: حُذفت النسخة المحلية لـ "$fileName".');
    }
  }
}
