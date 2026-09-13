import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// أيقونة SVG موحدة بطقم مخصص (هوية ECG) — عبر flutter_svg.
///
/// المزايا فوق Icon المادية:
/// - طقم مملوك: نفس سماكة الخط (1.8px)، نفس حواف الالتقاء، نفس
///   لغة الأشكال الهندسية المدوّرة — هوية لا تُستعارة من مكتبة.
/// - currentColor في طقم التنقل: تتلوّن فورياً مع الحالة
///   (selected/unselected) بلا نسختين لكل وضع سطوع.
/// - أطقم ثنائية اللون (وحدات/تمائم): تُعرض بألوانها الأصلية في
///   الفاتح، وتُوحَّد بلون واحد readable في الداكن (recolor).
/// - fallback آمن: ملف مفقود/خطأ تحميل → أيقونة مادية بديلة، لا
///   انهيار أبداً — والأصول الفاشلة تُخزَّن فلا يُعاد محاولتها.
///
/// **أداء**: لا FutureBuilder هنا عمداً — فحص الوجود عبر errorBuilder
/// المتزامن + كاش للأصول المفقودة. أيقونة تختفي frame واحد عند كل
/// setState (وميض النبضة سابقاً) صار مستحيلاً: أول frame يعرض
/// الصورة أو البديل، بلا async gap.
/// ─────────────────────────────────────────────────────────────────────
class AppSvgIcon extends StatelessWidget {
  const AppSvgIcon(
    this.asset, {
    this.size = 24,
    this.color,
    this.fallback,
    this.recolor = true,
    super.key,
  });

  /// مسار الأصل: assets/icons/... (كامل أو اسم مجرد من المجموعات).
  final String asset;

  /// الحجم (مربع).
  final double size;

  /// اللون — يُطبق كـcurrentColor عندما [recolor] مفعّل.
  final Color? color;

  /// أيقونة مادية بديلة عند فشل تحميل SVG (أمان لا انهيار).
  final IconData? fallback;

  /// هل نُعيد تلوين الـSVG بالكامل بلون [color]؟
  /// - true (افتراضي): لطقم currentColor (التنقل) أو للتوحيد داكناً.
  /// - false: أطقم ثنائية اللون تُعرض بألوانها الأصلية (duotone).
  final bool recolor;

  /// أصول فشل تحميلها — لا يُعاد فحصها/تحليلها في كل بناء.
  static final Set<String> _missingAssets = <String>{};

  /// يحل مساراً مجرداً إلى مسار أصول كامل —
  /// 'nav/today' → 'assets/icons/nav/today.svg'.
  static String resolve(String name) =>
      name.startsWith('assets/') ? name : 'assets/icons/$name.svg';

  @override
  Widget build(BuildContext context) {
    final String path = resolve(asset);
    final Color tint =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    // فشل سابق معروف؟ → البديل مباشرة (صفر عمل متزامن).
    if (_missingAssets.contains(path)) {
      return _fallbackWidget(tint);
    }

    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      colorFilter: (recolor && color != null)
          ? ColorFilter.mode(tint, BlendMode.srcIn)
          : null,
      // فشل التحميل/التحليل → بديل مادي فوري + وسم الأصل كي لا يُعاد.
      errorBuilder: (BuildContext context, Object error, StackTrace? st) {
        _missingAssets.add(path);
        return _fallbackWidget(tint);
      },
    );
  }

  Widget _fallbackWidget(Color tint) => fallback != null
      ? Icon(fallback, size: size, color: tint)
      : Icon(Icons.circle_outlined, size: size * 0.8, color: tint);
}

/// ─────────────────────────────────────────────────────────────────────
/// أيقونة تخصص طبي من الطقم المخصص — تعرض رمز الجهاز بأسلوب duotone:
/// خط كحلي + تعبئة/لمسات بلون التخصص، داخل حاوية دائرية بالتخصص.
///
/// التكيف مع السطوع:
/// - فاتح: الـSVG يُعرض بألوانه الأصلية (كحلي + لون التخصص) —
///   الدو تون مصمم للخلفيات الفاتحة.
/// - داكن: يُوحَّد كله بلون التخصص الفاتح (recolor) لأن كحلي SVG
///   غير مرئي على الأسطح الداكنة — نظيف ومقروء.
///
/// يستبدل الإيموجي المؤقت (❤️ 🫁 🧠...) بهوية مملوكة.
/// ─────────────────────────────────────────────────────────────────────
class ModuleIcon extends StatelessWidget {
  const ModuleIcon(
    this.module, {
    this.size = 48,
    this.showContainer = true,
    super.key,
  });

  /// رمز التخصص: cardiology / pulmonology / ...
  final String module;

  /// حجم الحاوية الكلية.
  final double size;

  /// true = داخل حاوية بلون التخصص (بطاقات المحاضرات) ·
  /// false = الرمز مجرداً (أماكن ضيقة/شريط التنقل).
  final bool showContainer;

  /// مسار SVG لكل تخصص — طقم duotone موحد بذات الجلسة.
  static const Map<String, String> _assetOf = <String, String>{
    'cardiology': 'units/unit_cardio',
    'pulmonology': 'units/unit_pulmo',
    'nephrology': 'units/unit_nephro',
    'gastroenterology': 'units/unit_gastro',
    'endocrinology': 'units/unit_endo',
    'hematology': 'units/unit_hema',
    'infectious': 'units/unit_infect',
    'rheumatology': 'units/unit_rheuma',
    'neurology': 'units/unit_neuro',
    'oncology': 'units/unit_onco',
  };

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool dark = b == Brightness.dark;
    final Color color = AppColors.module(module, b);

    final Widget icon = AppSvgIcon(
      _assetOf[module.toLowerCase()] ?? 'units/unit_cardio',
      size: size * 0.58,
      color: color,
      // فاتح: duotone أصلي · داكن: توحيد بلون التخصص الفاتح.
      recolor: dark,
      fallback: Icons.local_hospital_rounded,
    );

    if (!showContainer) return icon;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // حاوية التخصص الممزوجة بالسطح — قلب نظام «الحاوية أولاً».
        color: AppColors.moduleContainer(module, b),
        borderRadius: BorderRadius.circular(size * 0.29),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}
