import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// نطاق التخصص السريري (v20) — ناقل التخصص النشط عبر شجرتي المسار
/// والمكتبة معاً.
///
/// **العقد**: اختيار واحد يفترض المستخدم في كل التطبيق (لا يدرس
/// الجراحة في المسار والباطنية في المكتبة بالوقت نفسه). الشريط
/// أعلى الشاشتين يكتب إلى [LearnerProfile] فيثبت بين الجلسات،
/// ويعاد بناء الشاشتين فوراً عبر setState في مستدعيهما.
///
/// يخفي الشريط نفسه تلقائياً عند وجود تخصص واحد فقط في القاعدة —
/// التبديل بلا بديل ضجيج بصري بلا فائدة.
/// ─────────────────────────────────────────────────────────────────────
class SpecialtyScope extends InheritedWidget {
  const SpecialtyScope({
    required this.specialty,
    required this.specialties,
    required this.onChanged,
    required super.child,
    super.key,
  });

  /// التخصص النشط — 'internal_medicine' | 'surgery' | 'obgyn'.
  final String specialty;

  /// التخصصات الموجودة فعلاً في المحتوى (من getDistinctSpecialties)
  /// بترتيب العقد — يبني الشريط ويحدد إظهاره (تخصص واحد = إخفاء).
  final List<String> specialties;

  /// نداء تغيير التخصص من أي شاشة داخل النطاق — يحفظ ويعيد البناء
  /// (المالك: MainScreen).
  final ValueChanged<String> onChanged;

  /// التخصص النشط من أقرب نطاق — null إن لم يُلف بشيء (شاشات
  /// خارج نطاق التبديل تعمل بالسلوك التاريخي الكامل).
  static SpecialtyScope? of(BuildContext context) {
    try {
      return context.dependOnInheritedWidgetOfExactType<SpecialtyScope>();
    } catch (_) {
      // أطوار مبكرة (context قبل اكتمال الجبل) — لا نطاق بعد.
      return null;
    }
  }

  /// التخصص الفعلي: نطاق مغلق أو قراءة مبكرة؟ الباطنية (توافق
  /// رجعي كامل — لا استثناء يصعد أبداً).
  static String effectiveOf(BuildContext context) =>
      of(context)?.specialty ?? 'internal_medicine';

  /// نداء تغيير التخصص من أقرب نطاق — لا-op بلا نطاق (أمان).
  static ValueChanged<String> changeOf(BuildContext context) =>
      of(context)?.onChanged ?? (_) {};

  /// هل نعرض شريط التبديل أصلاً؟ (تخصصان+ في القاعدة).
  static bool barVisibleOf(BuildContext context) =>
      (of(context)?.specialties.length ?? 1) > 1;

  /// إخبار الجذر (MainScreen) بقائمة التخصصات الموجودة — يستدعيه
  /// لسانا المسار والمكتبة بعد كل تحميل: استيراد محاضرة جراحية قد
  /// يُظهر شريط التبديل لأول مرة. محمية بالكامل: أي حالة مبكرة أو
  /// شجرة بلا جذر استضافة = تجاهل صامت.
  static void maybeUpdateRoot(
    BuildContext context,
    List<String> specialties,
  ) {
    try {
      final SpecialtyRootHostState? host =
          context.findAncestorStateOfType<SpecialtyRootHostState>();
      host?.updateSpecialties(specialties);
    } catch (_) {
      // شجرة غير مكتملة — التحديث القادم يتكفل.
    }
  }

  @override
  bool updateShouldNotify(SpecialtyScope oldWidget) =>
      oldWidget.specialty != specialty ||
      !listEquals(oldWidget.specialties, specialties);
}

/// مالك حالة التخصص في جذر الشاشات — تفتحه MainScreen ويستدعي
/// شاشات الأبناء [SpecialtyScope.maybeUpdateRoot] لإخباره بتغيّر
/// قائمة التخصصات المتاحة.
class SpecialtyRootHost extends StatefulWidget {
  const SpecialtyRootHost({required this.child, super.key});

  final Widget child;

  @override
  State<SpecialtyRootHost> createState() => SpecialtyRootHostState();
}

class SpecialtyRootHostState extends State<SpecialtyRootHost> {
  List<String> _specialties = const <String>['internal_medicine'];

  /// القائمة الحالية للقراءة (يستهلكها بنّاء الجذر).
  List<String> get specialties => _specialties;

  /// استقبال قائمة التخصصات الموجودة من أي لسان محمّل — تحديث
  /// الحالة فقط عند التغيّر الفعلي (بلا إعادة بناء عابثة).
  void updateSpecialties(List<String> specialties) {
    if (!mounted) return;
    if (listEquals(specialties, _specialties)) return;
    setState(() => _specialties = specialties);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// شريط تبديل التخصصات — (الباطنية | الجراحة | النسائية).
///
/// تصميم «حدود لا ظلال» المطابق للهوية: كبسولة بحاوية التخصص
/// المختار، والمقطع النشط يحمل لونه واسمه. عند تخصص واحد فقط
/// يُخفى كلياً (يعرض [SizedBox.shrink] — بلا فراغ محجوز).
class SpecialtySegmentBar extends StatelessWidget {
  const SpecialtySegmentBar({
    required this.specialty,
    required this.specialties,
    required this.onChanged,
    super.key,
  });

  /// التخصص النشط حالياً.
  final String specialty;

  /// التخصصات المتاحة (من القاعدة — قد تكون واحداً).
  final List<String> specialties;

  /// نداء تغيير الاختيار — المستدعي يحفظ ويعيد البناء.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (specialties.length < 2) return const SizedBox.shrink();

    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(b),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(b)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < specialties.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                specialty: specialties[i],
                selected: specialties[i] == specialty,
                onTap: () => onChanged(specialties[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// مقطع واحد في الشريط — كبسولة بلون تخصصه عند التحديد، ثانوي خلافه.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.specialty,
    required this.selected,
    required this.onTap,
  });

  final String specialty;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color accent = AppColors.specialtyPrimary(specialty, b);
    final Color container = AppColors.specialtyContainer(specialty, b);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.ease,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? container : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            AppColors.specialtyIcon(specialty),
            size: 15,
            color: selected ? accent : AppColors.textSecondary(b),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              AppColors.specialtyNameAr(specialty),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? accent : AppColors.textSecondary(b),
              ),
            ),
          ),
        ],
      ),
    )
        .marginWithTap(onTap);
  }
}

/// امتداد صغير: لف بمصدر نقر بلا Material إضافي — InkWell شفاف.
extension _TapMargin on Widget {
  Widget marginWithTap(VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: this,
      );
}
