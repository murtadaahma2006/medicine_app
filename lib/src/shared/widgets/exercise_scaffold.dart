import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'app_button.dart';
import 'feedback_banner.dart';
import 'progress.dart';

/// ─────────────────────────────────────────────────────────────────────
/// الهيكل الموحد لكل شاشات التمارين — المكان الواحد الذي تشترك فيه
/// كل جلسات التدريب (MCQ، كتابة، ملء فراغ، إملاء، بناء جملة، أرقام،
/// أفعال، حالات، مراجعة، علاجية، تقييم) من المرحلة 4.
///
/// البنية:
/// ─ رأس: زر إغلاق + عنوان اختياري + شريط تقدم مجزأ متحرك.
/// ─ جسم: منطقة سؤال (Scrollable) + منطقة إجابة.
/// ─ أسفل: FeedbackBanner (إن وُجد) + زر رئيسي ثابت.
///
/// نسخة المؤقت: [timed] يعطي شارة وقت حية (تصفرّ آخر دقيقة).
/// ─────────────────────────────────────────────────────────────────────
class ExerciseScaffold extends StatelessWidget {
  const ExerciseScaffold({
    required this.current,
    required this.total,
    required this.body,
    this.title,
    this.onClose,
    this.feedback,
    this.primaryLabel,
    this.primaryIcon,
    this.primaryOnTap,
    this.primaryLoading = false,
    this.primaryDisabled = false,
    this.footerExtra,
    this.bottomSheetPhysics = const ClampingScrollPhysics(),
    super.key,
  });

  /// سؤال تقدم الجلسة (0-based: عدد المكتمل).
  final int current;

  /// عدد أسئلة الجلسة.
  final int total;

  /// جسم التمرين: سؤال + منطقة إجابة (مسؤولية الشاشة).
  final Widget body;

  /// عنوان الجلسة في الرأس (اختياري — «تدريب الأفعال» مثلاً).
  final String? title;

  /// زر الإغلاق — null = إغلاق افتراضي (pop).
  final VoidCallback? onClose;

  /// شريط التغذية الراجعة — null أثناء الإجابة.
  final FeedbackData? feedback;

  /// الزر الرئيسي (تحقق/التالي/متابعة).
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? primaryOnTap;
  final bool primaryLoading;
  final bool primaryDisabled;

  /// عنصر إضافي فوق الزر (صف أزرار مساعدة مثلاً: تلميح/استماع).
  final Widget? footerExtra;

  /// فيزياء التمرير أسفل الشاشة.
  final ScrollPhysics bottomSheetPhysics;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) (onClose ?? () => Navigator.of(context).pop()).call();
      },
      child: Scaffold(
        backgroundColor: AppColors.background(b),
        appBar: AppBar(
          title: title == null
              ? null
              : Text(title!, style: AppType.caption.copyWith(
                  fontSize: 14, color: AppColors.textSecondary(b))),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'إغلاق الجلسة',
            onPressed: onClose ?? () => Navigator.of(context).pop(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
              child: SegmentedProgressBar(
                current: current,
                total: total,
                height: 6,
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              // جسم السؤال — يتمدد ويتمرر.
              Expanded(
                child: feedback == null
                    ? body
                    : _DismissibleBody(
                        key: ValueKey<String>('fb-$current'),
                        body: body,
                      ),
              ),
              // أسفل ثابت: تغذية راجعة + زر.
              _Footer(
                feedback: feedback,
                primaryLabel: primaryLabel,
                primaryIcon: primaryIcon,
                primaryOnTap: primaryOnTap,
                primaryLoading: primaryLoading,
                primaryDisabled: primaryDisabled,
                footerExtra: footerExtra,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// يبني الجسم مع حركة دخول لطيفة عند سؤال جديد.
class _DismissibleBody extends StatelessWidget {
  const _DismissibleBody({required this.body, required super.key});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final bool animOn = !MediaQuery.disableAnimationsOf(context);
    if (!animOn) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.scaled(context, AppMotion.standard),
      curve: AppMotion.ease,
      builder: (BuildContext context, double v, Widget? child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - v)),
          child: child,
        ),
      ),
      child: body,
    );
  }
}

/// منطقة الأسفل الثابتة — التغذية الراجعة ثم الزر الرئيسي.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.feedback,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryOnTap,
    required this.primaryLoading,
    required this.primaryDisabled,
    required this.footerExtra,
  });

  final FeedbackData? feedback;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? primaryOnTap;
  final bool primaryLoading;
  final bool primaryDisabled;
  final Widget? footerExtra;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.standard,
      curve: AppMotion.ease,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background(b),
          border: Border(
            top: BorderSide(color: AppColors.border(b)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (footerExtra != null) ...<Widget>[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: footerExtra!,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (feedback != null) ...<Widget>[
              FeedbackBanner(
                key: ValueKey<String>('feedback-${feedback!.hashCode}'),
                correct: feedback!.correct,
                message: feedback!.message,
                correctAnswer: feedback!.correctAnswer,
                explanation: feedback!.explanation,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (primaryLabel != null)
              AppButton(
                label: primaryLabel!,
                icon: primaryIcon,
                onPressed: primaryDisabled || primaryLoading
                    ? null
                    : primaryOnTap,
                loading: primaryLoading,
              ),
          ],
        ),
      ),
    );
  }
}

/// بيانات التغذية الراجعة — تمرَّر للـScaffold من الشاشة.
class FeedbackData {
  const FeedbackData({
    required this.correct,
    required this.message,
    this.correctAnswer,
    this.explanation,
  });

  final bool correct;
  final String message;
  final String? correctAnswer;
  final String? explanation;
}
