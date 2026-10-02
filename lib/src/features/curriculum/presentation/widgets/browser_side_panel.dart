import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// المتصفح الجانبي المدمج (v30) — لوحة WebView تُعرض في فتحة اللوحة
/// الجانبية بصفحة المفاهيم (بجانب لوحة المساعد الذكي).
///
/// - شريط علوي بلون Surface متوافق مع الوضعين الداكن والفاتح.
/// - أزرار تحكم: رجوع، تقدم، تحديث، إغلاق.
/// - مؤشر تحميل LinearProgressIndicator أثناء جلب الصفحة.
/// - المتحكم [WebViewController] يُملَك من الصفحة الحاضنة (وليس من
///   هنا) كي يبقى تاريخ التنقل حياً عبر تبديل الوضعين AI/متصفح.
/// ─────────────────────────────────────────────────────────────────────
class BrowserSidePanel extends StatefulWidget {
  const BrowserSidePanel({
    required this.controller,
    this.progress,
    this.currentUrl,
    this.onClose,
    super.key,
  });

  /// متحكم مشترك تملكه الصفحة — يُعاد ربطه عند كل فتح للوحة.
  final WebViewController controller;

  /// تقدم التحميل (0..1) — null يخفي المؤشر.
  final ValueNotifier<double>? progress;

  /// عنوان URL الحالي — يُحدَّث من مفوّض التنقل.
  final ValueNotifier<String>? currentUrl;

  final VoidCallback? onClose;

  @override
  State<BrowserSidePanel> createState() => BrowserSidePanelState();
}

class BrowserSidePanelState extends State<BrowserSidePanel> {
  /// يحمّل رابط بحث جديد داخل اللوحة — يُستدعى من الصفحة عند
  /// «🌐 بحث في Google» واللوحة مفتوحة أصلاً.
  Future<void> loadUrl(String url) async {
    await widget.controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(
          left: BorderSide(color: AppColors.border(b), width: 1),
        ),
      ),
      child: Column(
        children: <Widget>[
          // ── شريط التحكم ──
          _buildToolbar(b, scheme),

          // ── مؤشر التحميل ──
          if (widget.progress != null)
            ValueListenableBuilder<double>(
              valueListenable: widget.progress!,
              builder: (BuildContext context, double value, _) {
                final bool busy = value > 0 && value < 1;
                return SizedBox(
                  height: 2,
                  child: busy
                      ? LinearProgressIndicator(
                          value: value,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),

          // ── محتوى الويب ──
          // WebViewWidget مربوط دائماً — حالة الفراغ طبقة فوقه كي لا
          // ينكسر ربط المتحكم عند أول فتح قبل أي تحميل.
          Expanded(
            child: Stack(
              children: <Widget>[
                WebViewWidget(controller: widget.controller),
                ValueListenableBuilder<String>(
                  valueListenable:
                      widget.currentUrl ?? ValueNotifier<String>(''),
                  builder: (BuildContext context, String url, _) {
                    if (url.isNotEmpty) return const SizedBox.shrink();
                    return Container(
                      color: AppColors.surface(b),
                      alignment: Alignment.center,
                      child: _buildEmptyState(b, scheme),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(Brightness b, ColorScheme scheme) {
    final WebViewController c = widget.controller;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(
          bottom: BorderSide(color: AppColors.border(b), width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: AppColors.text(b)),
            tooltip: 'رجوع',
            visualDensity: VisualDensity.compact,
            constraints:
                const BoxConstraints(minWidth: 34, minHeight: 34),
            onPressed: () async {
              if (await c.canGoBack()) await c.goBack();
            },
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppColors.text(b)),
            tooltip: 'تقدم',
            visualDensity: VisualDensity.compact,
            constraints:
                const BoxConstraints(minWidth: 34, minHeight: 34),
            onPressed: () async {
              if (await c.canGoForward()) await c.goForward();
            },
          ),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable:
                  widget.currentUrl ?? ValueNotifier<String>(''),
              builder: (BuildContext context, String url, _) => Text(
                Uri.tryParse(url)?.host ?? 'ابحث من نص المفهوم',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary(b),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                size: 18, color: AppColors.text(b)),
            tooltip: 'تحديث',
            visualDensity: VisualDensity.compact,
            constraints:
                const BoxConstraints(minWidth: 34, minHeight: 34),
            onPressed: c.reload,
          ),
          if (widget.onClose != null)
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textSecondary(b)),
              tooltip: 'إغلاق المتصفح',
              visualDensity: VisualDensity.compact,
              constraints:
                  const BoxConstraints(minWidth: 34, minHeight: 34),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Brightness b, ColorScheme scheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.public_rounded,
                  size: 32, color: scheme.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'ابحث في جوجل مباشرة',
              textAlign: TextAlign.center,
              style: AppType.cardTitle.copyWith(
                color: AppColors.text(b),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'أو حدد نصاً من الشرح واختر «🌐 بحث في Google»',
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary(b),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              decoration: InputDecoration(
                hintText: 'اكتب مصطلحاً للبحث...',
                hintStyle: TextStyle(color: AppColors.textSecondary(b), fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary(b)),
                filled: true,
                fillColor: AppColors.background(b),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(color: AppColors.border(b)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(color: AppColors.border(b)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(color: scheme.primary, width: 1.5),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (String query) {
                if (query.trim().isNotEmpty) {
                  loadUrl('https://www.google.com/search?q=${Uri.encodeComponent(query.trim())}');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
