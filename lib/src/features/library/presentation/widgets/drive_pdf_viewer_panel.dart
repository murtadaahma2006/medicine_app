import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../../core/services/google_drive_service.dart';
import '../../../../theme/tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DrivePdfViewerPanel
// ─────────────────────────────────────────────────────────────────────────────
//
// لوحة ثلاثية المراحل:
//  1. زر «تسجيل الدخول إلى Drive» عند أول فتح.
//  2. قائمة ملفات PDF المُدرَجة بعد المصادقة.
//  3. عارض PDF (SfPdfViewer) بعد اكتمال تنزيل الملف.
//
// مبدأ الأمان:
//  • التنزيل مجزَّء (Stream) — لا يُحمَّل الكتاب الطبي الضخم كاملاً
//    في الذاكرة قبل الكتابة على القرص.
//  • SfPdfViewer.file() يُقرأ من الملف المحلي لا من الذاكرة — أكثر
//    أماناً للـ iPad من SfPdfViewer.memory().
// ─────────────────────────────────────────────────────────────────────────────

class DrivePdfViewerPanel extends StatefulWidget {
  const DrivePdfViewerPanel({super.key});

  @override
  State<DrivePdfViewerPanel> createState() => _DrivePdfViewerPanelState();
}

class _DrivePdfViewerPanelState extends State<DrivePdfViewerPanel> {
  // ── حالة التطبيق ──────────────────────────────────────────────────────────
  _PanelView _view = _PanelView.login;

  List<drive.File> _pdfFiles = <drive.File>[];

  bool _isAuthLoading = false;
  bool _isListLoading = false;
  String? _authError;
  String? _listError;

  // ── حالة التنزيل ──────────────────────────────────────────────────────────
  String? _downloadingId; // ID الملف الذي يُنزَّل حالياً
  int _downloadPercent = 0; // 0-100 (أو -1 = غير معروف)

  // ── الملف المُحمَّل للعرض ─────────────────────────────────────────────────
  io.File? _localPdfFile;
  String? _viewingFileName;

  final GoogleDriveService _driveService = GoogleDriveService.instance;

  // ── تسجيل الدخول ──────────────────────────────────────────────────────────

  Future<void> _handleSignIn() async {
    setState(() {
      _isAuthLoading = true;
      _authError = null;
    });

    try {
      await _driveService.signIn();
      await _fetchPdfList();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = _friendlyError(e);
        _isAuthLoading = false;
      });
    }
  }

  // ── سرد ملفات PDF ──────────────────────────────────────────────────────────

  Future<void> _fetchPdfList() async {
    if (!mounted) return;
    setState(() {
      _isAuthLoading = false;
      _isListLoading = true;
      _listError = null;
      _view = _PanelView.list;
    });

    try {
      final List<drive.File> files = await _driveService.listPdfFiles();
      if (!mounted) return;
      setState(() {
        _pdfFiles = files;
        _isListLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = _friendlyError(e);
        _isListLoading = false;
      });
    }
  }

  // ── تنزيل ملف ─────────────────────────────────────────────────────────────

  Future<void> _handleFileTap(drive.File file) async {
    if (_downloadingId != null) return; // تنزيل آخر جارٍ
    if (!mounted) return;

    setState(() {
      _downloadingId = file.id;
      _downloadPercent = 0;
    });

    try {
      final io.File localFile = await _driveService.downloadPdfToTemp(
        file,
        onProgress: (DriveDownloadProgress p) {
          if (!mounted) return;
          setState(() => _downloadPercent = p.percent ?? -1);
        },
      );

      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _localPdfFile = localFile;
        _viewingFileName = file.name ?? 'PDF';
        _view = _PanelView.viewer;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadingId = null);
      _showSnackError(_friendlyError(e));
    }
  }

  // ── العودة من العارض ──────────────────────────────────────────────────────

  void _closeViewer() => setState(() {
        _view = _PanelView.list;
        _localPdfFile = null;
        _viewingFileName = null;
      });

  // ── تسجيل الخروج ──────────────────────────────────────────────────────────

  Future<void> _handleSignOut() async {
    await _driveService.signOut();
    if (!mounted) return;
    setState(() {
      _view = _PanelView.login;
      _pdfFiles = <drive.File>[];
      _localPdfFile = null;
    });
  }

  // ── مساعدات ──────────────────────────────────────────────────────────────

  String _friendlyError(Object e) {
    final String msg = e.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'تعذَّر الاتصال بالشبكة. تحقق من الإنترنت وحاول مجدداً.';
    }
    if (msg.contains('cancel') || msg.contains('ملغى')) {
      return 'تم إلغاء تسجيل الدخول.';
    }
    if (msg.contains('quota') || msg.contains('429')) {
      return 'تجاوزت حد الطلبات — انتظر لحظة ثم أعد المحاولة.';
    }
    if (msg.contains('403') || msg.contains('unauthorized')) {
      return 'لا يوجد إذن وصول للملف. تأكد من مشاركته معك.';
    }
    return 'حدث خطأ غير متوقع. يرجى إعادة المحاولة.';
  }

  void _showSnackError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_view) {
      _PanelView.login => _LoginView(
          isLoading: _isAuthLoading,
          error: _authError,
          onSignIn: _handleSignIn,
        ),
      _PanelView.list => _PdfListView(
          files: _pdfFiles,
          isLoading: _isListLoading,
          error: _listError,
          downloadingId: _downloadingId,
          downloadPercent: _downloadPercent,
          onFileTap: _handleFileTap,
          onRefresh: _fetchPdfList,
          onSignOut: _handleSignOut,
        ),
      _PanelView.viewer => _PdfViewerView(
          file: _localPdfFile!,
          fileName: _viewingFileName ?? 'PDF',
          onClose: _closeViewer,
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// مراحل اللوحة
// ─────────────────────────────────────────────────────────────────────────────

enum _PanelView { login, list, viewer }

// ─────────────────────────────────────────────────────────────────────────────
// 1. شاشة تسجيل الدخول
// ─────────────────────────────────────────────────────────────────────────────

class _LoginView extends StatelessWidget {
  const _LoginView({
    required this.isLoading,
    required this.onSignIn,
    this.error,
  });

  final bool isLoading;
  final String? error;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // أيقونة Drive
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primaryTint(b),
                borderRadius: BorderRadius.circular(AppRadius.sheet),
              ),
              child: Icon(
                Icons.cloud_rounded,
                size: 44,
                color: primary,
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            Text(
              'مكتبة الـ Drive',
              style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.sm),

            Text(
              'سجِّل دخولك إلى حساب Google للوصول\nإلى كتبك الطبية المخزَّنة على Drive.',
              style: AppType.body.copyWith(
                color: AppColors.textSecondary(b),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.xxxl),

            if (isLoading)
              CircularProgressIndicator(color: primary)
            else
              FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.login_rounded),
                label: const Text('تسجيل الدخول بـ Google'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                ),
              ),

            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _ErrorChip(message: error!),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. قائمة ملفات PDF
// ─────────────────────────────────────────────────────────────────────────────

class _PdfListView extends StatelessWidget {
  const _PdfListView({
    required this.files,
    required this.isLoading,
    required this.onFileTap,
    required this.onRefresh,
    required this.onSignOut,
    this.error,
    this.downloadingId,
    this.downloadPercent = 0,
  });

  final List<drive.File> files;
  final bool isLoading;
  final String? error;
  final String? downloadingId;
  final int downloadPercent; // -1 = مجهول
  final Future<void> Function() onRefresh;
  final void Function(drive.File) onFileTap;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: <Widget>[
        // ── شريط علوي ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface(b),
            border: Border(
              bottom: BorderSide(color: AppColors.border(b)),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.picture_as_pdf_rounded, color: primary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'ملفات PDF على Drive',
                  style: AppType.cardTitle.copyWith(
                    fontSize: 17,
                    color: AppColors.text(b),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث القائمة',
                icon: const Icon(Icons.refresh_rounded),
                color: AppColors.textSecondary(b),
                onPressed: isLoading ? null : onRefresh,
              ),
              IconButton(
                tooltip: 'تسجيل الخروج',
                icon: const Icon(Icons.logout_rounded),
                color: AppColors.textSecondary(b),
                onPressed: onSignOut,
              ),
            ],
          ),
        ),

        // ── المحتوى ────────────────────────────────────────────────────
        Expanded(
          child: _buildBody(context, b, primary),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, Brightness b, Color primary) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_off_rounded,
                  size: 48, color: AppColors.textSecondary(b)),
              const SizedBox(height: AppSpacing.md),
              Text(
                error!,
                style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.folder_open_rounded,
                size: 56, color: AppColors.textSecondary(b)),
            const SizedBox(height: AppSpacing.md),
            Text(
              'لا توجد ملفات PDF في Drive',
              style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        itemCount: files.length,
        separatorBuilder: (_, __) =>
            Divider(color: AppColors.border(b), height: 1),
        itemBuilder: (BuildContext context, int index) {
          final drive.File file = files[index];
          final bool isDownloading = downloadingId == file.id;
          final int? sizeKb = file.size != null
              ? (int.tryParse(file.size!) ?? 0) ~/ 1024
              : null;

          return _PdfFileRow(
            file: file,
            sizeKb: sizeKb,
            isDownloading: isDownloading,
            downloadPercent: isDownloading ? downloadPercent : 0,
            primaryColor: primary,
            onTap: isDownloading || downloadingId != null
                ? null
                : () => onFileTap(file),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// صف ملف PDF واحد
// ─────────────────────────────────────────────────────────────────────────────

class _PdfFileRow extends StatelessWidget {
  const _PdfFileRow({
    required this.file,
    required this.isDownloading,
    required this.downloadPercent,
    required this.primaryColor,
    this.sizeKb,
    this.onTap,
  });

  final drive.File file;
  final int? sizeKb;
  final bool isDownloading;
  final int downloadPercent; // 0-100 أو -1
  final Color primaryColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 0, vertical: AppSpacing.xs),
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.errorContainer(b),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Icon(
          Icons.picture_as_pdf_rounded,
          color: AppColors.error(b),
          size: 22,
        ),
      ),
      title: Text(
        file.name ?? '—',
        style: AppType.body.copyWith(
          color: AppColors.text(b),
          fontWeight: FontWeight.w600,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: isDownloading
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  LinearProgressIndicator(
                    value: downloadPercent >= 0 ? downloadPercent / 100 : null,
                    backgroundColor: AppColors.border(b),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(primaryColor),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    downloadPercent >= 0
                        ? 'جارٍ التنزيل… $downloadPercent٪'
                        : 'جارٍ التنزيل…',
                    style: AppType.caption
                        .copyWith(color: AppColors.textSecondary(b)),
                  ),
                ],
              ),
            )
          : sizeKb != null
              ? Text(
                  _formatSize(sizeKb!),
                  style: AppType.caption
                      .copyWith(color: AppColors.textSecondary(b)),
                )
              : null,
      trailing: isDownloading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryColor,
              ),
            )
          : Icon(
              Icons.chevron_left_rounded,
              color: AppColors.textSecondary(b),
            ),
    );
  }

  String _formatSize(int kb) {
    if (kb < 1024) return '$kb كيلوبايت';
    final double mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} ميجابايت';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. عارض PDF
// ─────────────────────────────────────────────────────────────────────────────

class _PdfViewerView extends StatefulWidget {
  const _PdfViewerView({
    required this.file,
    required this.fileName,
    required this.onClose,
  });

  final io.File file;
  final String fileName;
  final VoidCallback onClose;

  @override
  State<_PdfViewerView> createState() => _PdfViewerViewState();
}

class _PdfViewerViewState extends State<_PdfViewerView> {
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: <Widget>[
        // ── شريط أعلى العارض ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface(b),
            border: Border(
              bottom: BorderSide(color: AppColors.border(b)),
            ),
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'عودة إلى القائمة',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                color: AppColors.text(b),
                onPressed: widget.onClose,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.fileName,
                      style: AppType.body.copyWith(
                        color: AppColors.text(b),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_totalPages > 0)
                      Text(
                        'صفحة $_currentPage من $_totalPages',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
                        ),
                      ),
                  ],
                ),
              ),
              // أزرار التنقل السريع
              IconButton(
                tooltip: 'الصفحة الأولى',
                icon: const Icon(Icons.first_page_rounded, size: 20),
                color: AppColors.textSecondary(b),
                onPressed: () => _pdfController.firstPage(),
              ),
              IconButton(
                tooltip: 'صفحة سابقة',
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                color: AppColors.textSecondary(b),
                onPressed: () => _pdfController.previousPage(),
              ),
              IconButton(
                tooltip: 'صفحة تالية',
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                color: AppColors.textSecondary(b),
                onPressed: () => _pdfController.nextPage(),
              ),
              IconButton(
                tooltip: 'الصفحة الأخيرة',
                icon: const Icon(Icons.last_page_rounded, size: 20),
                color: AppColors.textSecondary(b),
                onPressed: () => _pdfController.lastPage(),
              ),
            ],
          ),
        ),

        // ── عارض الـ PDF ──────────────────────────────────────────────
        Expanded(
          child: SfPdfViewer.file(
            widget.file,
            controller: _pdfController,
            // القراءة من الملف المحلي — أكثر أماناً للذاكرة من memory()
            pageLayoutMode: PdfPageLayoutMode.continuous,
            scrollDirection: PdfScrollDirection.vertical,
            onDocumentLoaded: (PdfDocumentLoadedDetails details) {
              setState(() {
                _totalPages = details.document.pages.count;
                _currentPage = 1;
              });
            },
            onPageChanged: (PdfPageChangedDetails details) {
              setState(() => _currentPage = details.newPageNumber);
            },
            onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'تعذَّر فتح الملف: ${details.error}',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
              widget.onClose();
            },
            // لون مؤشر التقدم عند بدء تحميل صفحات كبيرة
            currentSearchTextHighlightColor: primary.withValues(alpha: 0.4),
            otherSearchTextHighlightColor: primary.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// شريحة خطأ صغيرة — مُعاد الاستخدام
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorContainer(b),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.error(b).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.error(b)),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              message,
              style: AppType.caption.copyWith(color: AppColors.error(b)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
