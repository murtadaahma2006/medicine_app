import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/google_drive_service.dart';
import '../../../../theme/tokens.dart';

enum _PickerState { login, list, downloading }

class DriveFilePickerSheet extends StatefulWidget {
  const DriveFilePickerSheet({super.key});

  @override
  State<DriveFilePickerSheet> createState() => _DriveFilePickerSheetState();
}

class _DriveFilePickerSheetState extends State<DriveFilePickerSheet> {
  final GoogleDriveService _drive = GoogleDriveService.instance;

  _PickerState _state = _PickerState.login;

  List<String> _folderIdStack = <String>['root'];
  List<String> _folderNameStack = <String>['ملفاتي'];

  List<drive.File> _files = <drive.File>[];
  bool _isListLoading = false;
  bool _isAuthLoading = false;
  String? _authError;
  String? _listError;

  drive.File? _downloadingFile;
  int _downloadPercent = 0;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
  }

  Future<void> _checkInitialAuth() async {
    setState(() => _isAuthLoading = true);
    bool signedIn = false;
    
    if (_drive.isSignedIn) {
      signedIn = true;
    } else {
      signedIn = await _drive.signInSilently();
    }
    
    if (signedIn) {
      await _loadFolderState();
      await _loadList();
    } else {
      if (mounted) {
        setState(() => _isAuthLoading = false);
      }
    }
  }

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
      _state = _PickerState.login;
      _files = <drive.File>[];
      _folderIdStack.clear();
      _folderIdStack.add('root');
      _folderNameStack.clear();
      _folderNameStack.add('ملفاتي');
      _downloadingFile = null;
    });
    _saveFolderState();
  }

  Future<void> _loadFolderState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList('drive_folder_ids');
      final names = prefs.getStringList('drive_folder_names');
      if (ids != null && names != null && ids.isNotEmpty && names.isNotEmpty && ids.length == names.length) {
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
      _state = _PickerState.list;
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

  Future<void> _startDownload(drive.File file) async {
    if (!mounted) return;
    setState(() {
      _downloadingFile = file;
      _downloadPercent = 0;
      _downloadError = null;
      _state = _PickerState.downloading;
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
      // بدلاً من العرض، نعود بالملف لصفحة القارئ!
      Navigator.pop(context, {'file': local, 'id': file.id, 'name': file.name});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadError = _friendly(e);
      });
    }
  }

  void _cancelDownload() {
    setState(() {
      _downloadingFile = null;
      _downloadError = null;
      _state = _PickerState.list;
    });
  }

  String _friendly(Object e) {
    final String s = e.toString().toLowerCase();
    if (s.contains('network') || s.contains('socket') || s.contains('host')) return 'تعذَّر الاتصال بالشبكة.';
    if (s.contains('cancel') || s.contains('ملغى')) return 'تم إلغاء العملية.';
    if (s.contains('403') || s.contains('unauthorized')) return 'لا يوجد إذن. تأكد من المشاركة.';
    return 'حدث خطأ غير متوقع.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: switch (_state) {
        _PickerState.login => _buildLoginState(),
        _PickerState.list => _buildListState(),
        _PickerState.downloading => _buildDownloadingState(),
      },
    );
  }

  Widget _buildLoginState() {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;

    return _PanelShell(
      title: 'مكتبة Drive',
      titleIcon: Icons.cloud_rounded,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
              Text('اقرأ كتبك الطبية', style: AppType.cardTitle.copyWith(color: AppColors.text(b), fontSize: 18), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text('سجِّل دخولك بـ Google للوصول إلى ملفات\nPDF الطبية المحفوظة على Drive.', style: AppType.body.copyWith(color: AppColors.textSecondary(b), height: 1.65, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xxl),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
                    ),
                  ),
                ),
              if (_authError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_authError!, style: TextStyle(color: AppColors.error(b))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListState() {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool canGoBack = _folderIdStack.length > 1;
    final String currentFolderName = _folderNameStack.last;

    return _PanelShell(
      title: currentFolderName,
      titleIcon: canGoBack ? Icons.folder_open_rounded : Icons.cloud_rounded,
      leading: canGoBack
          ? IconButton(
              tooltip: 'المجلد السابق',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
              onPressed: _isListLoading ? null : _popFolder,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: Icon(Icons.refresh_rounded, size: 18, color: AppColors.textSecondary(b)),
            onPressed: _isListLoading ? null : _loadList,
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: Icon(Icons.logout_rounded, size: 18, color: AppColors.textSecondary(b)),
            onPressed: _signOut,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.textSecondary(b)),
            const SizedBox(height: AppSpacing.md),
            Text(_listError!, style: AppType.body.copyWith(color: AppColors.textSecondary(b))),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(onPressed: _loadList, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.folder_open_rounded, size: 48, color: AppColors.textSecondary(b)),
            const SizedBox(height: AppSpacing.md),
            Text('المجلد فارغ أو لا توجد ملفات PDF', style: AppType.body.copyWith(color: AppColors.textSecondary(b))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadList,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        itemCount: _files.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border(b)),
        itemBuilder: (BuildContext ctx, int i) {
          final drive.File item = _files[i];
          final bool isFolder = item.mimeType == GoogleDriveService.driveFolderMimeType;
          return ListTile(
            onTap: () {
              if (isFolder) {
                _openFolder(item);
              } else {
                _startDownload(item);
              }
            },
            leading: Icon(isFolder ? Icons.folder_rounded : Icons.picture_as_pdf_rounded, color: isFolder ? Colors.amber.shade700 : AppColors.error(b)),
            title: Text(item.name ?? '—', style: AppType.body.copyWith(color: AppColors.text(b), fontWeight: FontWeight.w600)),
            trailing: Icon(isFolder ? Icons.chevron_left_rounded : Icons.download_rounded, size: 18, color: AppColors.textSecondary(b)),
          );
        },
      ),
    );
  }

  Widget _buildDownloadingState() {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool hasError = _downloadError != null;

    return _PanelShell(
      title: 'جارٍ التنزيل',
      titleIcon: Icons.download_rounded,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(
                value: (!hasError && _downloadPercent >= 0) ? _downloadPercent / 100 : null,
                color: primary,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(hasError ? 'فشل التنزيل' : 'جارٍ تنزيل الملف...', style: AppType.body.copyWith(color: AppColors.text(b))),
              if (hasError) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_downloadError!, style: TextStyle(color: AppColors.error(b))),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(onPressed: _cancelDownload, child: const Text('عودة')),
              ] else ...[
                const SizedBox(height: AppSpacing.lg),
                TextButton(onPressed: _cancelDownload, child: const Text('إلغاء')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.title,
    required this.titleIcon,
    required this.child,
    this.leading,
    this.trailing,
  });

  final String title;
  final IconData titleIcon;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Column(
      children: <Widget>[
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(color: AppColors.surface(b), border: Border(bottom: BorderSide(color: AppColors.border(b)))),
          child: Row(
            children: <Widget>[
              if (leading != null) leading!,
              const SizedBox(width: AppSpacing.xs),
              Icon(titleIcon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(title, style: AppType.caption.copyWith(color: AppColors.text(b)))),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
