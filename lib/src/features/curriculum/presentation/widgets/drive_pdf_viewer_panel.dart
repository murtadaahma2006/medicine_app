import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/google_drive_service.dart';
import '../../../../theme/tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DrivePdfViewerPanel — نسخة Curriculum
// ─────────────────────────────────────────────────────────────────────────────
//
// تُستخدم داخل لوحة جانبية ضيقة (landscape) بجانب ConceptReaderPage.
//
// 4 حالات منفصلة:
//  [login]      — زر «تسجيل الدخول بـ Google Drive».
//  [list]       — قائمة ملفات PDF المُستردَّة من Drive.
//  [downloading]— شاشة كاملة مع CircularProgressIndicator وقيمة النسبة.
//  [viewer]     — SfPdfViewer.file() مع شريط تنقل علوي وزر «Back».
//
// مبدأ الأمان:
//  • التنزيل بـ Stream مجزَّء → IOSink (لا RAM spike).
//  • SfPdfViewer.file() بدلاً من .memory() للقراءة من القرص.
//  • تحقق مسبق: إذا كان الملف موجوداً بالحجم الصحيح يُفتح مباشرة.
// ─────────────────────────────────────────────────────────────────────────────

// ── حالات اللوحة الأربع ──────────────────────────────────────────────────────

enum _PanelState { login, list, downloading, viewer }

// ─────────────────────────────────────────────────────────────────────────────
// Widget الجذر
// ─────────────────────────────────────────────────────────────────────────────

class DrivePdfViewerPanel extends StatefulWidget {
  const DrivePdfViewerPanel({super.key, this.onClose});

  /// اختياري — يُستدعى عند الضغط على × لإغلاق اللوحة من الخارج.
  final VoidCallback? onClose;

  @override
  State<DrivePdfViewerPanel> createState() => _DrivePdfViewerPanelState();
}

class _DrivePdfViewerPanelState extends State<DrivePdfViewerPanel> {
  final GoogleDriveService _drive = GoogleDriveService.instance;

  // ── الحالة العامة ──────────────────────────────────────────────────────────
  _PanelState _state = _PanelState.login;

  // ── stacks التنقل بين المجلدات ──────────────────────────────────────────
  List<String> _folderIdStack = <String>['root'];
  List<String> _folderNameStack = <String>['ملفاتي'];

  // ── بيانات القائمة ─────────────────────────────────────────────────────────
  List<drive.File> _files = <drive.File>[];
  bool _isListLoading = false;
  bool _isAuthLoading = false;
  String? _authError;
  String? _listError;

  // ── بيانات التنزيل ─────────────────────────────────────────────────────────
  drive.File? _downloadingFile; // الملف المُنزَّل حالياً
  int _downloadPercent = 0; // 0-100 | -1 = غير معروف
  String? _downloadError;

  // ── بيانات العارض ──────────────────────────────────────────────────────────
  io.File? _localFile;
  String? _viewingName;

  // ─────────────────────────────────────────────────────────────────────────
  // Auth
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    setState(() {
      _isAuthLoading = true;
      _authError = null;
    });
    try {
      await _drive.signIn();
      await _loadFolderState();
      await _loadList();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = _friendly(e);
        _isAuthLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await _drive.signOut();
    if (!mounted) return;
    setState(() {
      _state = _PanelState.login;
      _files = <drive.File>[];
      _folderIdStack.clear();
      _folderIdStack.add('root');
      _folderNameStack.clear();
      _folderNameStack.add('ملفاتي');
      _localFile = null;
      _downloadingFile = null;
    });
    _saveFolderState();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // List & Folder Navigation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadFolderState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList('drive_folder_ids');
      final names = prefs.getStringList('drive_folder_names');
      if (ids != null &&
          names != null &&
          ids.isNotEmpty &&
          names.isNotEmpty &&
          ids.length == names.length) {
        _folderIdStack = ids;
        _folderNameStack = names;
      }
    } catch (_) {}
  }

  Future<void> _saveFolderState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('drive_folder_ids', _folderIdStack);
      await prefs.setStringList('drive_folder_names', _folderNameStack);
    } catch (_) {}
  }

  Future<void> _loadList() async {
    if (!mounted) return;
    setState(() {
      _isAuthLoading = false;
      _isListLoading = true;
      _listError = null;
      _state = _PanelState.list;
    });
    try {
      final String currentFolderId = _folderIdStack.last;
      final List<drive.File> items = await _drive.listDriveItems(
        folderId: currentFolderId,
      );
      if (!mounted) return;
      setState(() {
        _files = items;
        _isListLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = _friendly(e);
        _isListLoading = false;
      });
    }
  }

  void _openFolder(drive.File folder) {
    if (folder.id == null) return;
    setState(() {
      _folderIdStack.add(folder.id!);
      _folderNameStack.add(folder.name ?? 'مجلد');
    });
    _saveFolderState();
    _loadList();
  }

  void _popFolder() {
    if (_folderIdStack.length > 1) {
      setState(() {
        _folderIdStack.removeLast();
        _folderNameStack.removeLast();
      });
      _saveFolderState();
      _loadList();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Download — حالة مستقلة بشاشتها الخاصة
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startDownload(drive.File file) async {
    if (!mounted) return;
    setState(() {
      _downloadingFile = file;
      _downloadPercent = 0;
      _downloadError = null;
      _state = _PanelState.downloading;
    });

    try {
      final io.File local = await _drive.downloadPdfToTemp(
        file,
        onProgress: (DriveDownloadProgress p) {
          if (!mounted) return;
          setState(() => _downloadPercent = p.percent ?? -1);
        },
      );

      if (!mounted) return;
      setState(() {
        _localFile = local;
        _viewingName = file.name ?? 'PDF';
        _downloadingFile = null;
        _state = _PanelState.viewer;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadError = _friendly(e);
        // البقاء في حالة التنزيل لعرض الخطأ مع زر الإعادة
      });
    }
  }

  void _cancelDownload() {
    // لا يوجد cancel حقيقي في googleapis Media Stream —
    // نعود للقائمة والتنزيل يكمل في الخلفية بلا تأثير على UI.
    setState(() {
      _downloadingFile = null;
      _downloadError = null;
      _state = _PanelState.list;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Viewer
  // ─────────────────────────────────────────────────────────────────────────

  void _closeViewer() => setState(() {
    _state = _PanelState.list;
    _localFile = null;
    _viewingName = null;
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _friendly(Object e) {
    // أولاً: الاستثناء المكتوب من الخدمة — أدق رسالة ممكنة.
    if (e is GoogleSignInException) return e.arabicMessage;

    final String s = e.toString().toLowerCase();
    if (s.contains('network') || s.contains('socket') || s.contains('host')) {
      return 'تعذَّر الاتصال بالشبكة. تحقق من الإنترنت.';
    }
    if (s.contains('cancel') || s.contains('ملغى')) return 'تم إلغاء العملية.';
    if (s.contains('quota') || s.contains('429')) {
      return 'تجاوزت حد الطلبات — انتظر لحظة وأعد المحاولة.';
    }
    if (s.contains('403') || s.contains('unauthorized')) {
      return 'لا يوجد إذن. تأكد من مشاركة الملف معك.';
    }
    return 'حدث خطأ غير متوقع. يرجى إعادة المحاولة.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _PanelState.login => _buildLoginState(),
      _PanelState.list => _buildListState(),
      _PanelState.downloading => _buildDownloadingState(),
      _PanelState.viewer => _buildViewerState(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // State 1 — Login
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLoginState() {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return _PanelShell(
      onClose: widget.onClose,
      title: 'مكتبة Drive',
      titleIcon: Icons.cloud_rounded,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // أيقونة كبيرة
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint(b),
                  borderRadius: BorderRadius.circular(AppRadius.sheet),
                ),
                child: Icon(Icons.cloud_rounded, size: 40, color: primary),
              ),

              const SizedBox(height: AppSpacing.xl),

              Text(
                'اقرأ كتبك الطبية',
                style: AppType.cardTitle.copyWith(
                  color: AppColors.text(b),
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.sm),

              Text(
                'سجِّل دخولك بـ Google للوصول إلى ملفات\nPDF الطبية المحفوظة على Drive.',
                style: AppType.body.copyWith(
                  color: AppColors.textSecondary(b),
                  height: 1.65,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xxl),

              // زر تسجيل الدخول
              if (_isAuthLoading)
                CircularProgressIndicator(color: primary)
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('تسجيل الدخول بـ Google'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      textStyle: AppType.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.field),
                      ),
                    ),
                  ),
                ),

              if (_authError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _ErrorBanner(message: _authError!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // State 2 — List
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildListState() {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool canGoBack = _folderIdStack.length > 1;
    final String currentFolderName = _folderNameStack.last;

    return _PanelShell(
      onClose: widget.onClose,
      title: currentFolderName,
      titleIcon: canGoBack ? Icons.folder_open_rounded : Icons.cloud_rounded,
      leading:
          canGoBack
              ? IconButton(
                tooltip: 'المجلد السابق',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                onPressed: _isListLoading ? null : _popFolder,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
              : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: Icon(
              Icons.refresh_rounded,
              size: 18,
              color: AppColors.textSecondary(b),
            ),
            onPressed: _isListLoading ? null : _loadList,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: Icon(
              Icons.logout_rounded,
              size: 18,
              color: AppColors.textSecondary(b),
            ),
            onPressed: _signOut,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
      child: _buildListBody(b),
    );
  }

  Widget _buildListBody(Brightness b) {
    if (_isListLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_listError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: AppColors.textSecondary(b),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _listError!,
                style: AppType.body.copyWith(
                  color: AppColors.textSecondary(b),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _loadList,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_files.isEmpty) {
      final bool isSubFolder = _folderIdStack.length > 1;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: AppColors.textSecondary(b),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isSubFolder ? 'هذا المجلد فارغ' : 'لا توجد مجلدات أو ملفات PDF',
              style: AppType.body.copyWith(
                color: AppColors.textSecondary(b),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadList,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        itemCount: _files.length,
        separatorBuilder:
            (_, __) => Divider(height: 1, color: AppColors.border(b)),
        itemBuilder: (BuildContext ctx, int i) {
          final drive.File item = _files[i];
          final bool isFolder =
              item.mimeType == GoogleDriveService.driveFolderMimeType;
          final int? sizeKb =
              (!isFolder && item.size != null)
                  ? (int.tryParse(item.size!) ?? 0) ~/ 1024
                  : null;
          return _FileListTile(
            file: item,
            isFolder: isFolder,
            sizeKb: sizeKb,
            onTap: () {
              if (isFolder) {
                _openFolder(item);
              } else {
                _startDownload(item);
              }
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // State 3 — Downloading (شاشة كاملة مستقلة)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDownloadingState() {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;
    final String fileName = _downloadingFile?.name ?? 'الملف';
    final bool hasError = _downloadError != null;

    return _PanelShell(
      onClose: widget.onClose,
      title: 'جارٍ التنزيل',
      titleIcon: Icons.download_rounded,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // حلقة التقدم
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value:
                            (!hasError && _downloadPercent >= 0)
                                ? _downloadPercent / 100
                                : null,
                        strokeWidth: 5,
                        color: primary,
                        backgroundColor: AppColors.border(b),
                      ),
                    ),
                    if (!hasError && _downloadPercent >= 0)
                      Text(
                        '$_downloadPercent٪',
                        style: AppType.caption.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      )
                    else if (!hasError)
                      Icon(Icons.downloading_rounded, color: primary, size: 28),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              Text(
                hasError ? 'فشل التنزيل' : 'جارٍ تنزيل الكتاب الطبي…',
                style: AppType.body.copyWith(
                  color: AppColors.text(b),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.sm),

              Text(
                fileName,
                style: AppType.caption.copyWith(
                  color: AppColors.textSecondary(b),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              if (hasError) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _ErrorBanner(message: _downloadError!),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: _cancelDownload,
                      child: const Text('عودة'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton(
                      onPressed:
                          _downloadingFile != null
                              ? () => _startDownload(_downloadingFile!)
                              : null,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ] else ...<Widget>[
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'قد تستغرق الكتب الكبيرة عدة دقائق\nحسب سرعة الإنترنت.',
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary(b),
                    fontSize: 11,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: _cancelDownload,
                  child: const Text('إلغاء والعودة'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // State 4 — Viewer
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildViewerState() {
    return _PdfViewerBody(
      file: _localFile!,
      fileName: _viewingName ?? 'PDF',
      onBack: _closeViewer,
      onClose: widget.onClose,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PanelShell — غلاف موحد لكل الحالات (header + content)
// ─────────────────────────────────────────────────────────────────────────────

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.title,
    required this.titleIcon,
    required this.child,
    this.leading,
    this.trailing,
    this.onClose,
  });

  final String title;
  final IconData titleIcon;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: <Widget>[
        // ── شريط العنوان ──────────────────────────────────────────────
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface(b),
            border: Border(
              bottom: BorderSide(color: AppColors.border(b), width: 1),
            ),
          ),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: AppSpacing.xs),
              ],
              Icon(titleIcon, size: 16, color: primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: AppType.caption.copyWith(
                    color: AppColors.text(b),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing!,
              if (onClose != null)
                IconButton(
                  tooltip: 'إغلاق',
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textSecondary(b),
                  ),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
        ),

        // ── المحتوى ───────────────────────────────────────────────────
        Expanded(child: child),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FileListTile — صف ملف واحد في القائمة
// ─────────────────────────────────────────────────────────────────────────────

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.file,
    required this.onTap,
    this.isFolder = false,
    this.sizeKb,
  });

  final drive.File file;
  final bool isFolder;
  final int? sizeKb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final IconData iconData =
        isFolder ? Icons.folder_rounded : Icons.picture_as_pdf_rounded;

    final Color iconColor =
        isFolder ? Colors.amber.shade700 : AppColors.error(b);

    final Color bgColor =
        isFolder
            ? Colors.amber.withValues(alpha: 0.12)
            : AppColors.errorContainer(b);

    final String subtitleText =
        isFolder ? 'مجلد' : (sizeKb != null ? _formatSize(sizeKb!) : 'ملف PDF');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.xs,
      ),
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Icon(iconData, color: iconColor, size: 22),
      ),
      title: Text(
        file.name ?? '—',
        style: AppType.body.copyWith(
          color: AppColors.text(b),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitleText,
        style: AppType.caption.copyWith(color: AppColors.textSecondary(b)),
      ),
      trailing: Icon(
        isFolder ? Icons.chevron_left_rounded : Icons.download_rounded,
        size: 18,
        color: AppColors.textSecondary(b),
      ),
    );
  }

  String _formatSize(int kb) {
    if (kb < 1024) return '$kb كيلوبايت';
    return '${(kb / 1024).toStringAsFixed(1)} ميجابايت';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PdfViewerBody — عارض PDF مع شريط تحكم علوي وزر Back
// ─────────────────────────────────────────────────────────────────────────────

class _PdfViewerBody extends StatefulWidget {
  const _PdfViewerBody({
    required this.file,
    required this.fileName,
    required this.onBack,
    this.onClose,
  });

  final io.File file;
  final String fileName;
  final VoidCallback onBack;
  final VoidCallback? onClose;

  @override
  State<_PdfViewerBody> createState() => _PdfViewerBodyState();
}

class _PdfViewerBodyState extends State<_PdfViewerBody> {
  final PdfViewerController _ctrl = PdfViewerController();
  int _page = 1;
  int _total = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: <Widget>[
        // ── شريط التحكم ───────────────────────────────────────────────
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surface(b),
            border: Border(
              bottom: BorderSide(color: AppColors.border(b), width: 1),
            ),
          ),
          child: Row(
            children: <Widget>[
              // ← Back
              IconButton(
                tooltip: 'عودة إلى القائمة',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                color: AppColors.text(b),
                onPressed: widget.onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),

              // عنوان + رقم الصفحة
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.fileName,
                      style: AppType.caption.copyWith(
                        color: AppColors.text(b),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_total > 0)
                      Text(
                        '$_page / $_total',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),

              // تنقل: ← ↑ ↓ →
              IconButton(
                tooltip: 'أول صفحة',
                icon: const Icon(Icons.first_page_rounded, size: 18),
                color: AppColors.textSecondary(b),
                onPressed: () => _ctrl.firstPage(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                tooltip: 'سابقة',
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: AppColors.textSecondary(b),
                onPressed: () => _ctrl.previousPage(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                tooltip: 'تالية',
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                color: AppColors.textSecondary(b),
                onPressed: () => _ctrl.nextPage(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                tooltip: 'آخر صفحة',
                icon: const Icon(Icons.last_page_rounded, size: 18),
                color: AppColors.textSecondary(b),
                onPressed: () => _ctrl.lastPage(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),

              // × إغلاق اللوحة بالكامل
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'إغلاق',
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textSecondary(b),
                  ),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
            ],
          ),
        ),

        // ── SfPdfViewer ───────────────────────────────────────────────
        Expanded(
          child: SfPdfViewer.file(
            widget.file,
            controller: _ctrl,
            pageLayoutMode: PdfPageLayoutMode.continuous,
            scrollDirection: PdfScrollDirection.vertical,
            onDocumentLoaded: (PdfDocumentLoadedDetails d) {
              setState(() {
                _total = d.document.pages.count;
                _page = 1;
              });
            },
            onPageChanged: (PdfPageChangedDetails d) {
              setState(() => _page = d.newPageNumber);
            },
            onDocumentLoadFailed: (PdfDocumentLoadFailedDetails d) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تعذَّر فتح الملف: ${d.error}'),
                  duration: const Duration(seconds: 5),
                ),
              );
              widget.onBack();
            },
            currentSearchTextHighlightColor: primary.withValues(alpha: 0.4),
            otherSearchTextHighlightColor: primary.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ErrorBanner — شريط خطأ بسيط قابل للإعادة
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.errorContainer(b),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.error(b).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 15,
            color: AppColors.error(b),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppType.caption.copyWith(
                color: AppColors.error(b),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
