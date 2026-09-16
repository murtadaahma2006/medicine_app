import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────
/// أساس التجاوب — مصدر واحد للحقيقة لأحجام الشاشات والتكيف.
///
/// **نقاط الكسر (Material 3 Adaptive)**:
/// - compact  : < 600  → الموبايل (وضع اليوم — لا يتغير شيء إطلاقاً).
/// - medium   : ≥ 600  → التابلت الطولي (iPad 10 portrait).
/// - expanded : ≥ 840  → التابلت العرضي/الشاشات الواسعة (iPad landscape).
///
/// القاعدة الحاكمة: كل تغيير تجاوبي **إضافي فقط** — أي سلوك على
/// الموبايل يبقى حرفياً كما هو. الشاشات الضيقة لا ترى هذه الأدوات
/// أصلاً (القيود لا تعمل تحتها).
///
/// الاستخدام:
/// ```dart
/// // 1) تغليف عمود القراءة (الأكثر شيوعاً):
/// child: ResponsiveReadingColumn(child: body)
///
/// // 2) تغيير جذري حسب الفئة:
/// child: ResponsiveBuilder(mobile: a, tablet: b)
///
/// // 3) عدد أعمدة الشبكة ديناميكياً:
/// child: ResponsiveLayout.gridColumns(context) // 1/2/3
/// ```
/// ─────────────────────────────────────────────────────────────────────
abstract final class ResponsiveLayout {
  /// نقاط الكسر — Material 3 window size classes حرفياً.
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 840;

  /// أقصى عرض لعمود القراءة/الجلسة على الشاشات الواسعة.
  /// (قارئ المقالات: عمود أنيق بالمنتصف — مثل ما طُبق يدوياً سابقاً
  /// بقيمة 720؛ توحيد القيمة هنا كمصدر واحد).
  static const double readingMaxWidth = 720;

  /// أقصى عرض للنوافذ المنبثقة والقوائم السفلية.
  static const double sheetMaxWidth = 400;

  // ───────────────────────── الفئة الحالية ─────────────────────────

  /// فئة الشاشة من عرضها المنطقي.
  static WindowSizeClass of(double width) {
    if (width < mobileBreakpoint) return WindowSizeClass.compact;
    if (width < tabletBreakpoint) return WindowSizeClass.medium;
    return WindowSizeClass.expanded;
  }

  /// فئة الشاشة الحالية — `ResponsiveLayout.of(context)` مع
  /// MediaQuery آمن (بلا inheritExactWidgetErrors).
  static WindowSizeClass ofContext(BuildContext context) =>
      of(MediaQuery.sizeOf(context).width);

  /// هل هذه شاشة موبايل؟ (< 600 — الوضع الحالي المحمي).
  static bool isMobile(double width) => width < mobileBreakpoint;

  /// هل هذه شاشة تابلت؟ (≥ 600 — طولياً أو عرضياً).
  static bool isTablet(double width) => width >= mobileBreakpoint;

  // ───────────────────────── الشبكات ─────────────────────────

  /// عدد أعمدة الشبكة الديناميكي:
  /// - موبايل: 1 (قائمة كما هي — لا تغيير).
  /// - تابلت طولي (600–839): 2.
  /// - تابلت عرضي/واسع (≥ 840): 3.
  static int gridColumns(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    if (width < mobileBreakpoint) return 1;
    if (width < tabletBreakpoint) return 2;
    return 3;
  }

  /// نسبة أبعاد بطاقة الشبكة حسب عدد الأعمدة (عرض/ارتفاع).
  /// موبايل (قائمة): نسبة القائمة الأصلية 1.0 · شبكة: بطاقة أعرض قليلاً.
  static double gridChildAspectRatio(int columns) =>
      columns == 1 ? 2.2 : 1.05;

  /// تباعد خلايا الشبكة الأفقية — ثابت المشروع.
  static const double gridSpacing = 12.0;
}

/// فئات حجم النافذة — Material 3 window size classes.
enum WindowSizeClass {
  /// موبايل < 600 — كل السلوكيات الحالية محفوظة حرفياً.
  compact,

  /// تابلت طولي 600–839 (iPad 10 portrait).
  medium,

  /// تابلت عرضي/شاشة واسعة ≥ 840 (iPad landscape).
  expanded,
}

/// ─────────────────────────────────────────────────────────────────────
/// [ResponsiveBuilder] — تبديل جذري بين موبايل/تابلت.
///
/// للشاشات التي تتطلب بنية مختلفة كلياً (لا مجرد توسيط). الشاشات
/// الضيقة ترى [mobile] حصراً — صفر خطر على تصميم الموبايل الحالي.
/// ─────────────────────────────────────────────────────────────────────
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    required this.mobile,
    this.tablet,
    super.key,
  });

  /// البناء للموبايل (< 600) — **هذا هو التطبيق الحالي**.
  final WidgetBuilder mobile;

  /// البناء للتابلت (≥ 600) — اختياري: غيابه = استخدام [mobile]
  /// (التغييرات الطفيفة تُدار عبر تغليف القراءة لا هنا).
  final WidgetBuilder? tablet;

  @override
  Widget build(BuildContext context) {
    final bool isTablet =
        ResponsiveLayout.isTablet(MediaQuery.sizeOf(context).width);
    if (isTablet && tablet != null) {
      return tablet!(context);
    }
    return mobile(context);
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// [ResponsiveReadingColumn] — عمود القراءة/الجلسة الموحد.
///
/// الحل الأساسي لشاشات القراءة والجلسات على الآيباد: النص لا يتمدد
/// من أقصى اليمين لأقصى اليسار بل يظهر كعمود أنيق بالمنتصف.
///
/// السلوك:
/// - موبايل (< 600): الطفل كما هو حرفياً — القيد لا يعمل تحت 720
///   أصلاً (الشاشة أضيق منه) → **صفر أثر على الموبايل**.
/// - تابلت (≥ 600): الطفل مقيد بـ maxWidth 720 وموسّط أفقياً —
///   مثل قارئ المقالات.
/// ─────────────────────────────────────────────────────────────────────
class ResponsiveReadingColumn extends StatelessWidget {
  const ResponsiveReadingColumn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.readingMaxWidth,
        ),
        child: child,
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// [ResponsiveSheet] — قياس القوائم السفلية والحوارات.
///
/// القائمة السفلية على الآيباد بلا قيد تمتد بعرض الشاشة كاملاً —
/// مشوهة. هذه تحصرها بمركز أنيق:
/// - موبايل: عادي تماماً (القيد لا يعمل).
/// - تابلت: maxWidth 400 موسّطة.
///
/// الاستخدام داخل builder الـ showModalBottomSheet:
/// ```dart
/// builder: (context) => ResponsiveSheet(child: MySheetContent())
/// ```
/// ─────────────────────────────────────────────────────────────────────
class ResponsiveSheet extends StatelessWidget {
  const ResponsiveSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.sheetMaxWidth,
        ),
        child: child,
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// [ResponsiveDialog] — حوار موحّد القياس على الشاشات الواسعة.
///
/// استبدال مباشر لـ AlertDialog داخل showDialog: نفس الحوار لكن
/// مقيداً بموسّط على التابلت. الموبايل: لا يتغير شيء.
///
/// ```dart
/// final bool? ok = await showDialog<bool>(
///   context: context,
///   builder: (ctx) => ResponsiveDialog(
///     title: 'تأكيد',
///     content: Text('...'),
///     actions: [...],
///   ),
/// );
/// ```
/// ─────────────────────────────────────────────────────────────────────
class ResponsiveDialog extends StatelessWidget {
  const ResponsiveDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ResponsiveSheet(
      child: AlertDialog(
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }
}
