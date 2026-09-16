import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/backup/backup_service.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة «نسخة احتياطية / استعادة».
///
/// - **تصدير**: كل تقدم المستخدم إلى ملف .db (قاعدة شاملة) في مجلد
///   المستندات + زر مشاركة الملف عبر تطبيقات الجهاز (share_plus).
/// - **استعادة**: اختيار ملف (file_picker) → تحذير صريح أن الاستيراد
///   **يستبدل التقدم الحالي** → استبدال فيزيائي للقاعدة + إعادة تشغيل التطبيق.
///
/// ملاحظة عقدية: فشل أي عملية يعرض رسالة مهذبة فقط (لا انهيار).
/// file_picker حزمة جديدة تُدار عند أول استخدام — غيابها على منصة
/// يعرض رسالة ولا يعطل الشاشة.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // ربط مزوّد مجلد المستندات الحقيقي (path_provider) — قبل أي تصدير.
    documentsDirProvider = getApplicationDocumentsDirectory;
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final Map<String, Object?> prefs = await _collectPreferences();
      final BackupExportResult result =
          await BackupService.export(preferences: prefs);
      if (!mounted) return;

      if (result.ok) {
        final bool? share = await showDialog<bool>(
          context: context,
          // تجاوب: على التابلت يُقيد عرض الحوار (موبايل: بلا أثر).
          builder: (BuildContext ctx) => ResponsiveDialog(
            title: const Text('تم إنشاء النسخة الاحتياطية'),
            content: Text(
              'حُفظ الملف بنجاح (${result.itemCount} عنصراً).\n'
              '${result.filePath}\n\nهل تريد مشاركته الآن؟',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('لاحقاً'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('مشاركة'),
              ),
            ],
          ),
        );
        if (share == true && result.filePath != null && mounted) {
          await Share.shareXFiles(
            <XFile>[XFile(result.filePath!)],
            text: 'نسخة احتياطية — MedOS',
          );
        }
      } else {
        _toast(result.messageAr ?? 'تعذّر التصدير.');
      }
    } catch (_) {
      _toast('تعذّر التصدير — تحقق من صلاحيات التخزين.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<Map<String, Object?>> _collectPreferences() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, Object?> raw = <String, Object?>{};
      for (final String key in prefs.getKeys()) {
        raw[key] = prefs.get(key);
      }
      return raw;
    } catch (_) {
      return const <String, Object?>{}; // تفضيلات غير حرجة.
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // تم تغيير type إلى FileType.any لحل مشكلة iOS التي تمنع اختيار ملفات غير قياسية
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (picked == null || picked.files.single.path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      
      final String path = picked.files.single.path!;
      
      // تحقق برمجي يدوي لتجنب مشاكل FilePicker على iOS
      final String extension = path.split('.').last.toLowerCase();
      if (extension != 'db' && extension != 'json') {
        if (mounted) {
          _toast('عذراً، الرجاء اختيار ملف بصيغة .db أو .json فقط');
          setState(() => _busy = false);
        }
        return;
      }

      if (!mounted) return;
      // تحذير الاستبدال الصريح (قرار المواصفة — تأكيد المستخدم).
      final bool? confirmed = await showDialog<bool>(
        context: context,
        // تجاوب: على التابلت يُقيد عرض الحوار (موبايل: بلا أثر).
        builder: (BuildContext ctx) => ResponsiveDialog(
          title: const Text('تحذير: استبدال التقدم'),
          content: const Text(
            'الاستعادة **تحذف تقدمك الحالي** (سجل الإجابات، البطاقات، '
            'النقاط والشارات) وتستبدله بمحتوى الملف.\n\n'
            'هل أنت متأكد؟',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final BackupImportResult result = await BackupService.importFromFile(
        path,
        onPreferences: (Map<String, Object?> prefs) async {
          // إعادة تطبيق التفضيلات خارج القاعدة.
          try {
            final SharedPreferences sp =
                await SharedPreferences.getInstance();
            for (final MapEntry<String, Object?> e in prefs.entries) {
              if (e.value is bool) {
                await sp.setBool(e.key, e.value! as bool);
              } else if (e.value is int) {
                await sp.setInt(e.key, e.value! as int);
              } else if (e.value is double) {
                await sp.setDouble(e.key, e.value! as double);
              } else if (e.value is String) {
                await sp.setString(e.key, e.value! as String);
              }
            }
          } catch (_) {
            // صمت مقصود — التفضيلات غير حرجة.
          }
        },
      );

      if (!mounted) return;
      _toast(result.messageAr);
      
      // فور الانتهاء والنجاح، نرسل المستخدم لشاشة البداية لإعادة بناء بيئة التطبيق
      if (result.ok) {
        // تأخير بسيط ليقرأ المستخدم رسالة النجاح
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (mounted) context.go('/');
      }
    } catch (_) {
      _toast('تعذّر فتح منتقي الملفات — تحقق من الأذونات.');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('نسخة احتياطية / استعادة')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint(b),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border(b)),
                  ),
                  child: Column(
                    children: <Widget>[
                      AppIllustration('icon_backup', size: 56, borderRadius: BorderRadius.circular(14),),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'بياناتك ملكك — احفظها أو انقلها لجهاز آخر',
                        style: AppType.cardTitle.copyWith(
                          fontSize: 17,
                          color: AppColors.text(b),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'النسخة تحفظ: التقدم، سجل الإجابات، بطاقات المراجعة، '
                        'نقاط الخبرة، الشارات، والإعدادات',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  onTap: _export,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.backup_rounded,
                          color: AppColors.primary(b)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('إنشاء نسخة احتياطية',
                                style: AppType.body.copyWith(
                                    fontWeight: FontWeight.w700)),
                            Text('حفظ في مجلد المستندات + مشاركة',
                                style: AppType.caption.copyWith(
                                    color: AppColors.textSecondary(b))),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded,
                          color: AppColors.textSecondary(b)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  onTap: _import,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.restore_rounded,
                          color: AppColors.primary(b)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('استعادة من ملف',
                                style: AppType.body.copyWith(
                                    fontWeight: FontWeight.w700)),
                            Text('استبدال التقدم الحالي بنسخة محفوظة',
                                style: AppType.caption.copyWith(
                                    color: AppColors.textSecondary(b))),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded,
                          color: AppColors.textSecondary(b)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FutureBuilder<Directory>(
                  future: documentsDirProvider(),
                  builder: (BuildContext ctx,
                      AsyncSnapshot<Directory> snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final String dirPath =
                        '${snap.data!.path}${Platform.pathSeparator}'
                        'MedicineApp${Platform.pathSeparator}Backups';
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm),
                      child: Text(
                        'مجلد النسخ: $dirPath',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
