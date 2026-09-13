import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/error_logger.dart';
import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// صفحة سجل الأخطاء — debug فقط (المرحلة 0 من جولة الاستقرار).
///
/// الوصول: المسار [RoutePaths.devErrorLog] — لا تظهر في نسخة الإنتاج.
///
/// تعرض:
/// • قائمة كل الأخطاء المسجلة (نص + وقت + نوع).
/// • زر «نسخ» لكل خطأ (يضع النص الكامل في الحافظة).
/// • زر «مسح الكل» في الـAppBar.
/// ─────────────────────────────────────────────────────────────────────
class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({super.key});

  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  final AppErrorLogger _logger = AppErrorLogger.instance;

  @override
  void initState() {
    super.initState();
    _logger.changeNotifier.addListener(_onNewEntry);
  }

  @override
  void dispose() {
    _logger.changeNotifier.removeListener(_onNewEntry);
    super.dispose();
  }

  void _onNewEntry() {
    if (mounted) setState(() {});
  }

  void _clearAll() {
    _logger.clear();
  }

  Future<void> _copyEntry(ErrorEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.fullText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('نُسخ نص الخطأ'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final List<ErrorEntry> entries = _logger.entries.reversed.toList();

    return Scaffold(
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        backgroundColor: AppColors.background(b),
        title: Text(
          'سجل الأخطاء [dev] — ${entries.length}',
          style: AppType.caption.copyWith(color: AppColors.textSecondary(b)),
        ),
        centerTitle: true,
        actions: <Widget>[
          if (entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'مسح الكل',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                'لا أخطاء مسجلة ✅',
                style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (BuildContext context, int i) {
                final ErrorEntry entry = entries[i];
                return _ErrorCard(
                  entry: entry,
                  onCopy: () => _copyEntry(entry),
                  brightness: b,
                );
              },
            ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.entry,
    required this.onCopy,
    required this.brightness,
  });

  final ErrorEntry entry;
  final VoidCallback onCopy;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final Brightness b = brightness;
    final String timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer(b),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.error(b).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline_rounded,
                  size: 16, color: AppColors.error(b)),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '[$timeStr] ${entry.type}',
                  style: AppType.caption.copyWith(
                    color: AppColors.error(b),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'نسخ',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: onCopy,
                color: AppColors.textSecondary(b),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.message,
            style: AppType.caption.copyWith(
              color: AppColors.text(b),
              fontFamily: 'monospace',
              fontWeight: FontWeight.w400,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
          if (entry.stackSummary.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              entry.stackSummary,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary(b).withValues(alpha: 0.75),
                fontFamily: 'monospace',
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
