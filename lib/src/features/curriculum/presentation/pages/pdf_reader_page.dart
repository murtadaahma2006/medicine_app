import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';

import '../../../../theme/tokens.dart';
import '../widgets/sidekick_chat_panel.dart';
import '../widgets/browser_side_panel.dart';
import 'concept_reader_page.dart' show PanelMode;
import '../../../../core/services/google_drive_service.dart';

Future<String> _extractTextTask(String filePath) async {
  final io.File file = io.File(filePath);
  final bytes = await file.readAsBytes();
  final PdfDocument document = PdfDocument(inputBytes: bytes);
  final PdfTextExtractor extractor = PdfTextExtractor(document);
  final String text = extractor.extractText();
  document.dispose();
  return text;
}

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key});

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  io.File? _pdfFile;
  String _pdfName = 'قارئ الـ PDF';
  String? _driveFileId; // معرّف الملف في درايف إذا كان متاحاً
  bool _isSyncing = false;

  // ── الصفحات ──
  int _currentPage = 1;
  int _totalPages = 0;

  // ── البحث ──
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  PdfTextSearchResult _searchResult = PdfTextSearchResult();

  // ── حالة اللوحة الجانبية ──
  bool _isSidePanelOpen = false;
  PanelMode _panelMode = PanelMode.ai;

  // ── أدوات التظليل والملاحظات ──
  PdfAnnotationMode _annotationMode = PdfAnnotationMode.none;

  // ── متحكم المتصفح ──
  WebViewController? _browserController;
  final ValueNotifier<double> _browserProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<String> _browserUrl = ValueNotifier<String>('');

  // ── متحكم الـ PDF ──
  final PdfViewerController _pdfViewerController = PdfViewerController();
  OverlayEntry? _selectionOverlay;

  // ── نص الشرح المعلق ──
  String? _pendingExplainText;

  @override
  void dispose() {
    _pdfViewerController.dispose();
    _removeSelectionOverlay();
    _browserProgress.dispose();
    _browserUrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _removeSelectionOverlay() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
  }

  WebViewController _ensureBrowserController() {
    if (_browserController != null) return _browserController!;
    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            _browserProgress.value = progress / 100.0;
          },
          onPageStarted: (_) {
            _browserProgress.value = 0.01;
          },
          onPageFinished: (String url) {
            _browserProgress.value = 0.0;
            _browserUrl.value = url;
          },
        ),
      );
    _browserController = controller;
    return controller;
  }

  void _explainSelectedText(String text) {
    _removeSelectionOverlay();
    _pdfViewerController.clearSelection();
    
    final bool isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      setState(() {
        _pendingExplainText = text;
        _isSidePanelOpen = true;
        _panelMode = PanelMode.ai;
      });
    } else {
      _pendingExplainText = text;
      _showChatBottomSheet();
    }
  }

  void _searchSelectedTextOnWeb(String text) {
    _removeSelectionOverlay();
    _pdfViewerController.clearSelection();

    final String query = Uri.encodeComponent(text.trim());
    final String url = 'https://www.google.com/search?q=$query';

    final bool isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      setState(() {
        _isSidePanelOpen = true;
        _panelMode = PanelMode.browser;
      });
      _ensureBrowserController().loadRequest(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المتصفح الجانبي متاح في الوضع العرضي (أو الأيباد) فقط.')),
      );
    }
  }

  void _translateSelectedText(String text) {
    _removeSelectionOverlay();
    _pdfViewerController.clearSelection();

    final bool isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      final String query = Uri.encodeComponent(text.trim());
      final String url = 'https://translate.google.com/?sl=auto&tl=ar&text=$query&op=translate';
      setState(() {
        _isSidePanelOpen = true;
        _panelMode = PanelMode.browser;
      });
      _ensureBrowserController().loadRequest(Uri.parse(url));
    } else {
      _showTranslationSheet(context, text);
    }
  }

  Future<void> _showTranslationSheet(BuildContext context, String textToTranslate) async {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(b),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            top: AppSpacing.lg,
            bottom: MediaQuery.paddingOf(ctx).bottom + AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border(b),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'الترجمة',
                textAlign: TextAlign.center,
                style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
              ),
              const SizedBox(height: AppSpacing.xl),
              
              // النص الأصلي
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(b),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  border: Border.all(color: AppColors.border(b)),
                ),
                child: Text(
                  textToTranslate,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: AppType.body.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              
              // الترجمة
              FutureBuilder<Translation>(
                future: GoogleTranslator().translate(textToTranslate, to: 'ar'),
                builder: (BuildContext context, AsyncSnapshot<Translation> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Center(
                        child: Text(
                          'تعذّر الاتصال بخدمة الترجمة. تأكد من اتصالك بالإنترنت.',
                          textAlign: TextAlign.center,
                          style: AppType.body.copyWith(color: AppColors.error(b)),
                        ),
                      ),
                    );
                  }
                  
                  final String translated = snapshot.data?.text ?? '';
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint(b),
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      translated,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.start,
                      style: AppType.body.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _handleUploadPdfToAI() async {
    if (_pdfFile == null) return null;
    
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'جاري تحليل المستند لاستخراج النص... قد يستغرق هذا بعض الوقت للملفات الكبيرة.',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    ));

    try {
      final String extractedText = await compute(_extractTextTask, _pdfFile!.path);
      if (!mounted) return null;
      Navigator.pop(context); // Close loading dialog
      
      String finalContext = extractedText;
      // Truncate to a reasonable character limit (e.g., 300,000 chars roughly 60k-80k tokens)
      if (finalContext.length > 300000) {
        finalContext = '${finalContext.substring(0, 300000)}\n\n[ملاحظة: تم اقتطاع النص لأن الملف كبير جداً وتجاوز الحد المسموح]';
      }

      return finalContext;
    } catch (e) {
      if (!mounted) return null;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحليل المستند: $e')));
      return null;
    }
  }

  void _showChatBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, ScrollController sc) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
              ),
              child: SidekickChatPanel(
                unitId: _driveFileId ?? _pdfFile?.path ?? 'pdf_reader',
                unitTitle: _pdfName,
                scrollController: sc,
                autoExplainText: _pendingExplainText,
                onClose: () => Navigator.pop(ctx),
                onUploadDocumentRequested: _pdfFile != null ? _handleUploadPdfToAI : null,
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _pendingExplainText = null;
    });
  }

  void _showSelectionMenu(BuildContext context, PdfTextSelectionChangedDetails details) {
    _removeSelectionOverlay();
    
    final selectedText = details.selectedText;
    if (selectedText == null || selectedText.trim().isEmpty) return;

    final OverlayState overlayState = Overlay.of(context);
    final position = details.globalSelectedRegion?.topCenter ?? Offset.zero;

    _selectionOverlay = OverlayEntry(
      builder: (context) {
        final Brightness b = Theme.of(context).colorScheme.brightness;
        return Positioned(
          bottom: 120, // أعلى شريط التمرير والأدوات
          left: 20,
          right: 20,
          child: Center(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        _removeSelectionOverlay();
                        _explainSelectedText(selectedText);
                      },
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('شرح ذكي'),
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    Container(width: 1, height: 24, color: AppColors.border(b).withOpacity(0.5)),
                    TextButton.icon(
                      onPressed: () {
                        _removeSelectionOverlay();
                        _translateSelectedText(selectedText);
                      },
                      icon: const Icon(Icons.translate_rounded, size: 18),
                      label: const Text('ترجمة'),
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    Container(width: 1, height: 24, color: AppColors.border(b).withOpacity(0.5)),
                    IconButton(
                      icon: const Icon(Icons.public_rounded, size: 20),
                      tooltip: 'بحث في الويب',
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      onPressed: () {
                        _removeSelectionOverlay();
                        _searchSelectedTextOnWeb(selectedText);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      onPressed: _removeSelectionOverlay,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlayState.insert(_selectionOverlay!);
  }

  Future<void> _pickLocalPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pdfFile = io.File(result.files.single.path!);
        _pdfName = result.files.single.name;
      });
    }
  }

  Future<void> _saveLastPage(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pdf_page_$_pdfName', page);
    } catch (_) {}
  }

  Future<void> _loadLastPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? lastPage = prefs.getInt('pdf_page_$_pdfName');
      if (lastPage != null && lastPage > 1) {
        _pdfViewerController.jumpToPage(lastPage);
      }
    } catch (_) {}
  }

  void _setAnnotationMode(PdfAnnotationMode mode) {
    setState(() {
      _annotationMode = mode;
      _pdfViewerController.annotationMode = mode;
    });
  }

  Future<void> _saveAndSyncToDrive() async {
    if (_pdfFile == null) return;
    
    setState(() => _isSyncing = true);
    
    try {
      // 1. استخراج الملف المعدل (بايتات الـ PDF مع التظليلات)
      final List<int> bytes = await _pdfViewerController.saveDocument();
      
      // 2. الكتابة فوق الملف المحلي (Temp File)
      await _pdfFile!.writeAsBytes(bytes, flush: true);
      
      // 3. المزامنة مع غوغل درايف إذا كان الملف قادماً منه
      if (_driveFileId != null && _driveFileId!.isNotEmpty) {
        await GoogleDriveService.instance.updatePdfInDrive(_driveFileId!, _pdfFile!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الحفظ والمزامنة مع Google Drive بنجاح! ☁️✓')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حفظ التعديلات محلياً بنجاح! (للمزامنة، افتح الملف من درايف)')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        title: _isSearchMode
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: AppColors.text(b)),
                decoration: InputDecoration(
                  hintText: 'ابحث في الملف...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppColors.textSecondary(b)),
                ),
                onSubmitted: (val) async {
                  _searchResult = await _pdfViewerController.searchText(val);
                  setState(() {});
                },
              )
            : Text(_pdfName),
        centerTitle: !_isSearchMode,
        actions: [
          if (_isSearchMode && _searchResult.hasResult) ...[
            Center(
              child: Text(
                '${_searchResult.currentInstanceIndex} / ${_searchResult.totalInstanceCount}',
                style: AppType.body.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: () {
                _searchResult.previousInstance();
                setState(() {});
              },
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: () {
                _searchResult.nextInstance();
                setState(() {});
              },
            ),
          ],
          IconButton(
            icon: Icon(_isSearchMode ? Icons.close_rounded : Icons.search_rounded),
            tooltip: 'بحث',
            onPressed: () {
              setState(() {
                _isSearchMode = !_isSearchMode;
                if (!_isSearchMode) {
                  _searchResult.clear();
                  _searchController.clear();
                }
              });
            },
          ),
          if (_pdfFile != null && !_isSearchMode) ...[
            if (_isSyncing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.cloud_sync_rounded),
                tooltip: 'حفظ ومزامنة السحابة',
                onPressed: _saveAndSyncToDrive,
              ),
            IconButton(
              icon: Icon(
                _isSidePanelOpen && _panelMode == PanelMode.ai
                    ? Icons.auto_awesome
                    : Icons.auto_awesome_outlined,
                color: _isSidePanelOpen && _panelMode == PanelMode.ai
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: 'المساعد الذكي',
              onPressed: () {
                if (isLandscape) {
                  if (_isSidePanelOpen && _panelMode == PanelMode.ai) {
                    setState(() => _isSidePanelOpen = false);
                  } else {
                    setState(() {
                      _isSidePanelOpen = true;
                      _panelMode = PanelMode.ai;
                    });
                  }
                } else {
                  _showChatBottomSheet();
                }
              },
            ),
            IconButton(
              icon: Icon(
                _isSidePanelOpen && _panelMode == PanelMode.browser
                    ? Icons.public_rounded
                    : Icons.public_outlined,
                color: _isSidePanelOpen && _panelMode == PanelMode.browser
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: 'المتصفح',
              onPressed: () {
                if (isLandscape) {
                  if (_isSidePanelOpen && _panelMode == PanelMode.browser) {
                    setState(() => _isSidePanelOpen = false);
                  } else {
                    setState(() {
                      _isSidePanelOpen = true;
                      _panelMode = PanelMode.browser;
                    });
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('المتصفح الجانبي متاح في الوضع العرضي فقط.')),
                  );
                }
              },
            ),
          ],
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: _pdfFile == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, size: 64, color: AppColors.textSecondary(b)),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'اختر ملف PDF للقراءة',
                          style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        FilledButton.icon(
                          onPressed: _pickLocalPdf,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('تصفح ملفات الجهاز'),
                        ),
                      ],
                    ),
                  )
                : SfPdfViewer.file(
                    _pdfFile!,
                    controller: _pdfViewerController,
                    canShowScrollHead: true,
                    onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                      setState(() {
                        _totalPages = details.document.pages.count;
                      });
                      _loadLastPage();
                    },
                    onPageChanged: (PdfPageChangedDetails details) {
                      setState(() {
                        _currentPage = details.newPageNumber;
                      });
                      _saveLastPage(details.newPageNumber);
                    },
                    onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
                      // لا نعرض قائمة الشرح الذكي إذا كنا في وضع التظليل
                      if (_annotationMode != PdfAnnotationMode.none) return;

                      if (details.selectedText == null) {
                        _removeSelectionOverlay();
                      } else {
                        _showSelectionMenu(context, details);
                      }
                    },
                  ),
          ),
          if (isLandscape && _isSidePanelOpen && _pdfFile != null)
            Container(
              width: 380,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border(b))),
              ),
              child: _panelMode == PanelMode.ai
                  ? SidekickChatPanel(
                      unitId: _driveFileId ?? _pdfFile?.path ?? 'pdf_reader',
                      unitTitle: _pdfName,
                      autoExplainText: _pendingExplainText,
                      onUploadDocumentRequested: _pdfFile != null ? _handleUploadPdfToAI : null,
                      onClose: () => setState(() => _isSidePanelOpen = false),
                    )
                  : BrowserSidePanel(
                      controller: _ensureBrowserController(),
                      progress: _browserProgress,
                      currentUrl: _browserUrl,
                      onClose: () => setState(() => _isSidePanelOpen = false),
                    ),
            ),
        ],
      ),
      floatingActionButton: _pdfFile == null
          ? null
          : _buildAnnotationToolbar(b),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }



  Widget _buildAnnotationToolbar(Brightness b) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      color: AppColors.surface(b),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolIconButton(
              icon: Icons.pan_tool_rounded,
              tooltip: 'تصفح (إلغاء التحديد)',
              isSelected: _annotationMode == PdfAnnotationMode.none,
              onTap: () => _setAnnotationMode(PdfAnnotationMode.none),
            ),
            Container(width: 1, height: 24, color: AppColors.border(b), margin: const EdgeInsets.symmetric(horizontal: 4)),
            _ToolIconButton(
              icon: Icons.border_color_rounded,
              tooltip: 'تظليل (Highlighter)',
              isSelected: _annotationMode == PdfAnnotationMode.highlight,
              onTap: () => _setAnnotationMode(PdfAnnotationMode.highlight),
            ),
            _ToolIconButton(
              icon: Icons.format_underline_rounded,
              tooltip: 'تسطير (Underline)',
              isSelected: _annotationMode == PdfAnnotationMode.underline,
              onTap: () => _setAnnotationMode(PdfAnnotationMode.underline),
            ),
            _ToolIconButton(
              icon: Icons.note_add_rounded,
              tooltip: 'ملاحظة (Sticky Note)',
              isSelected: _annotationMode == PdfAnnotationMode.stickyNote,
              onTap: () => _setAnnotationMode(PdfAnnotationMode.stickyNote),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolIconButton extends StatelessWidget {
  const _ToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      style: IconButton.styleFrom(
        backgroundColor: isSelected ? theme.colorScheme.primaryContainer : Colors.transparent,
      ),
      onPressed: onTap,
    );
  }
}
