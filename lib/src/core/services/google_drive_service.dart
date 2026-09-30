import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GoogleDriveService
// ─────────────────────────────────────────────────────────────────────────────
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
    scopes: <String>[drive.DriveApi.driveReadonlyScope],
  );

  GoogleSignInAccount? _currentUser;

  /// الحساب المسجَّل حالياً، أو null إذا لم يُسجَّل دخول بعد.
  GoogleSignInAccount? get currentUser => _currentUser;

  bool get isSignedIn => _currentUser != null;

  // ── تسجيل الدخول ─────────────────────────────────────────────────────────

  /// يحاول استعادة الجلسة بصمت أولاً، وإلا يفتح نافذة OAuth.
  ///
  /// يُعيد الحساب المُوثَّق، أو يرمي [Exception] عند الفشل.
  Future<GoogleSignInAccount> signIn() async {
    // 1. محاولة صامتة أولاً (إعادة استخدام Token مُخزَّن).
    try {
      final GoogleSignInAccount? silent = await _googleSignIn.signInSilently();
      if (silent != null) {
        _currentUser = silent;
        debugPrint('GoogleDriveService: تسجيل دخول صامت بنجاح — ${silent.email}');
        return silent;
      }
    } catch (_) {
      // الصامت غير مُعطِّل — نتابع للتفاعلي.
    }

    // 2. تسجيل دخول تفاعلي عبر نافذة Google OAuth.
    final GoogleSignInAccount? account = await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('تسجيل الدخول إلى Google ملغى من المستخدم.');
    }
    _currentUser = account;
    debugPrint('GoogleDriveService: تسجيل دخول تفاعلي بنجاح — ${account.email}');
    return account;
  }

  /// تسجيل الخروج وتنظيف الجلسة.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    debugPrint('GoogleDriveService: تم تسجيل الخروج.');
  }

  // ── بناء عميل Drive مُوثَّق ──────────────────────────────────────────────

  /// يُنشئ [DriveApi] مُرتبطاً بالحساب المُوثَّق الحالي.
  ///
  /// يجدد الـ Token تلقائياً عبر [GoogleSignInAccount.authHeaders].
  Future<drive.DriveApi> _buildDriveApi() async {
    final GoogleSignInAccount? user = _currentUser;
    if (user == null) {
      throw StateError('يجب تسجيل الدخول أولاً.');
    }
    final Map<String, String> headers = await user.authHeaders;
    final _GoogleAuthClient authClient = _GoogleAuthClient(headers);
    return drive.DriveApi(authClient);
  }

  // ── سرد ملفات PDF ─────────────────────────────────────────────────────────

  /// يُعيد قائمة ملفات PDF من Drive الخاص بالمستخدم.
  ///
  /// الاستعلام: mimeType='application/pdf' AND trashed=false
  /// الترتيب: الأحدث تعديلاً أولاً.
  /// الحد الأقصى: 200 ملف للسرد الأول (قابل للتوسيع بـ nextPageToken).
  Future<List<drive.File>> listPdfFiles() async {
    final drive.DriveApi api = await _buildDriveApi();

    final drive.FileList result = await api.files.list(
      q: "mimeType='application/pdf' and trashed=false",
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
