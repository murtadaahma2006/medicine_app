import 'package:flutter/material.dart';

import '../../../../core/utils/responsive_layout.dart';
import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// حارس الجلسة (Session Guard — طبقة داخل التطبيق).
///
/// إيماءة الرجوع أثناء جلسة القراءة لا تخرج مباشرة — تعرض بطاقة
/// الحقيقة (Completion Urgency — استغلال إنهاء الحلقة المفتوحة):
///
/// «بقيت لقطتان فقط لإكمال الجلسة» + زر كبير «أكمل» (الافتراضي
/// البصري) + زر نصي صغير «إيقاف الجلسة».
///
/// عند الإيقاف: الجلسة تُحفظ كمقطوعة — لا عقاب XP — الجلسة ستنتظر
/// عودتك من نفس اللقطة (Ovsiankina).
/// ─────────────────────────────────────────────────────────────────────
class SessionGuard {
  SessionGuard._();

  /// يعرض حوار الاستمرار. يرجع:
  /// - true  = أكمل (البقاء في الجلسة).
  /// - false = أوقف الجلسة (حفظ وخروج).
  static Future<bool> confirmStay(
    BuildContext context, {
    required int remaining,
    required String unitLabel,
  }) async {
    final bool? stay = await showDialog<bool>(
      context: context,
      // تجاوب: على التابلت يُقيد عرض الحوار (موبايل: بلا أثر).
      builder: (BuildContext ctx) => ResponsiveDialog(
        title: Text(
          remaining <= 0
              ? 'لقطة واحدة تفصلك عن الإكمال!'
              : 'بقيت $remaining لقطة${remaining == 1 ? '' : 'ات'} فقط',
          textAlign: TextAlign.center,
          style: AppType.cardTitle.copyWith(fontSize: 18),
        ),
        content: Text(
          remaining <= 0
              ? 'إكمال هذه اللقطة يختم جلسة قراءة «$unitLabel» كاملة.'
              : 'الخروج الآن يحفظ تقدمك — وعند عودتك تستأنف من نفس اللقطة.',
          textAlign: TextAlign.center,
          style: AppType.body.copyWith(
            height: 1.7,
            fontSize: 13.5,
            color: AppColors.textSecondary(
                Theme.of(ctx).colorScheme.brightness),
          ),
        ),
        actions: <Widget>[
          // البقاء هو الفعل الكبير البصري.
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.sm + 2,
              ),
            ),
            child: Text(
              'أكمل — أستطيع',
              style: AppType.body.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'إيقاف الجلسة',
              style: AppType.caption.copyWith(
                color: AppColors.textSecondary(
                    Theme.of(ctx).colorScheme.brightness),
              ),
            ),
          ),
        ],
      ),
    );
    return stay ?? true; // الافتراضي: البقاء.
  }
}
