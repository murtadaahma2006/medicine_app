import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/content/lecture_import_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة «استيراد محاضرة» — اختيار ملف JSON من الجهاز
/// (Downloads أو أي مسار) → تحقق فوري من العقد v2.0.0 →
/// معاينة المحتوى (عدد الشروحات/البطاقات/الأسئلة/الحالات) →
/// زراعة idempotent داخل معاملة واحدة.
///
/// - المحاضرات المستوردة تظهر فوراً في المسار/المكتبة/اليوم.
/// - لا يمس التقدم أو XP أو البطاقات المُراجَعة إطلاقاً.
/// - إعادة استيراد محاضرة موجودة = تخطٍ مهذب بلا تكرار.
class LectureImportPage extends StatefulWidget {
  const LectureImportPage({super.key});

  @override
  State<LectureImportPage> createState() => _LectureImportPageState();
}

class _LectureImportPageState extends State<LectureImportPage> {
  bool _busy = false;

  // نتيجة التحقق الأخيرة (قبل الزرع) — تعرض كبطاقة معاينة.
  LectureValidationResult? _preview;

  // مسار الملف المُتحقق منه حديثاً (للزرع بعد التأكيد).
  String? _pickedPath;

  // نتيجة آخر استيراد ناجح.
  LectureImportResult? _result;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _preview = null;
      _pickedPath = null;
      _result = null;
    });
    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        allowMultiple: false,
      );
      if (picked == null || picked.files.single.path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final String path = picked.files.single.path!;
      final LectureValidationResult validation =
          await LectureImportService.validateFile(path);
      if (!mounted) return;
      setState(() {
        _preview = validation;
        _pickedPath = validation.ok ? path : null;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preview = const LectureValidationResult(
          ok: false,
          messageAr: 'تعذّر فتح منتقي الملفات — تحقق من الأذونات.',
        );
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    final String? path = _pickedPath;
    if (path == null || _busy) return;
    setState(() => _busy = true);
    final LectureImportResult result =
        await LectureImportService.importFile(path);
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
      if (result.ok) {
        // نجاح — إخفاء المعاينة لعرض شاشة النتيجة فقط.
        _preview = null;
        _pickedPath = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('استيراد محاضرة')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                // ── بطاقة الشرح ──
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint(b),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border(b)),
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.download_rounded,
                          size: 48, color: AppColors.primary(b)),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'أضف محاضرات جديدة من ملفات JSON',
                        style: AppType.cardTitle.copyWith(
                          fontSize: 17,
                          color: AppColors.text(b),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'اختر ملف محاضرة بصيغة JSON من جهازك — يتحقق التطبيق '
                        'من مطابقتها للعقد v2.0.0 ثم يزرعها فوراً.\n'
                        'لن يتأثر تقدمك الحالي، والمحاضرة الموجودة لا تُكرر.',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── زر اختيار الملف ──
                AppButton(
                  label: _pickedPath == null && _result == null
                      ? 'اختيار ملف JSON'
                      : 'اختيار ملف آخر',
                  icon: Icons.folder_open_rounded,
                  onPressed: _pick,
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── معاينة التحقق ──
                if (_preview != null) ...<Widget>[
                  if (_preview!.ok) _buildPreviewCard(context, _preview!)
                    else _buildErrorCard(context, _preview!.messageAr!),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── نتيجة الاستيراد ──
                if (_result != null) ...<Widget>[
                  if (_result!.ok)
                    _buildSuccessCard(context, _result!)
                  else
                    _buildErrorCard(context, _result!.messageAr),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── نصائح ──
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt(b),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border(b)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: AppColors.textSecondary(b)),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'أين تظهر المحاضرة بعد الاستيراد؟',
                            style: AppType.body.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'تظهر فوراً في شاشة «المسار» حسب تخصصها، وتُضاف '
                        'بطاقاتها إلى «مراجعة اليوم» وأسئلتها إلى جلسات '
                        'التدريب والاختبار.',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// بطاقة معاينة ما سيزرع — قبل التأكيد.
  Widget _buildPreviewCard(
    BuildContext context,
    LectureValidationResult preview,
  ) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool exists = preview.alreadyExists;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                exists
                    ? Icons.check_circle_outline_rounded
                    : Icons.task_alt_rounded,
                color: exists ? AppColors.textSecondary(b) : AppColors.primary(b),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  exists
                      ? 'هذه المحاضرة موجودة مسبقاً'
                      : 'الملف صالح — جاهز للاستيراد',
                  style: AppType.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (preview.title != null)
            _PreviewRow(label: 'العنوان', value: preview.title!),
          if (preview.module != null)
            _PreviewRow(
                label: 'التخصص', value: _moduleAr(preview.module!)),
          _PreviewRow(label: 'شروحات', value: '${preview.conceptCount}'),
          _PreviewRow(label: 'بطاقات', value: '${preview.flashcardCount}'),
          _PreviewRow(label: 'أسئلة', value: '${preview.mcqCount}'),
          _PreviewRow(label: 'حالات سريرية', value: '${preview.caseCount}'),
          if (!exists) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'استيراد الآن',
              icon: Icons.download_done_rounded,
              onPressed: _import,
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'إعادة استيرادها لن يكرر المحتوى (الزرع آمن) — لكن لا حاجة.',
                style: AppType.caption.copyWith(
                  color: AppColors.textSecondary(b),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// بطاقة نجاح الاستيراد.
  Widget _buildSuccessCard(BuildContext context, LectureImportResult result) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.successContainer(b),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.success(b)),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.check_circle_rounded,
              size: 44, color: AppColors.success(b)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            result.title ?? 'تم الاستيراد',
            style: AppType.cardTitle.copyWith(
              fontSize: 17,
              color: AppColors.text(b),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            result.messageAr,
            style: AppType.body.copyWith(
              color: AppColors.textSecondary(b),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (!result.skipped) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'استيراد محاضرة أخرى',
              type: AppButtonType.secondary,
              icon: Icons.add_rounded,
              onPressed: _pick,
              minHeight: 46,
            ),
          ],
        ],
      ),
    );
  }

  /// بطاقة خطأ (ملف تالف أو لا يطابق العقد).
  Widget _buildErrorCard(BuildContext context, String message) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(b),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.error_outline_rounded,
              size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'رفض الملف',
            style: AppType.cardTitle.copyWith(
              fontSize: 16,
              color: AppColors.text(b),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: AppType.body.copyWith(
              color: AppColors.textSecondary(b),
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'اختيار ملف آخر',
            type: AppButtonType.secondary,
            icon: Icons.folder_open_rounded,
            onPressed: _pick,
            minHeight: 46,
          ),
        ],
      ),
    );
  }

  String _moduleAr(String module) => switch (module) {
        'cardiology' => 'قلب وأوعية',
        'pulmonology' => 'صدر',
        'nephrology' => 'كلى',
        'gastroenterology' => 'هضمي',
        'endocrinology' => 'غدد صماء',
        'hematology' => 'دم',
        'infectious' => 'عدوى',
        'rheumatology' => 'روماتيزم',
        'neurology' => 'أعصاب',
        'oncology' => 'أورام',
        _ => module,
      };
}

/// صف «عنوان: قيمة» في بطاقة المعاينة.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AppType.caption
                  .copyWith(color: AppColors.textSecondary(b)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textDirection:
                  isLatin(value) ? TextDirection.ltr : TextDirection.rtl,
              textAlign:
                  isLatin(value) ? TextAlign.left : TextAlign.right,
              style: AppType.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  static bool isLatin(String s) =>
      RegExp(r'^[a-zA-Z0-9 ,.\-]+').hasMatch(s.trim());
}
