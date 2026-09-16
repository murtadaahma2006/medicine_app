import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────
/// نظام التصميم — المصدر الوحيد للحقيقة (Design Tokens).
///
/// كل قيمة بصرية في التطبيق تخرج من هنا: ألوان، مسافات، أنصاف، ظلال،
/// حركة، وطباعة. لا لون/مسافة/مدة hardcoded في أي شاشة بعد الآن.
///
/// المبدأ الحاكم للهوية: «حدود لا ظلال» — حد 1px دائم + ظل ناعم جداً.
/// ─────────────────────────────────────────────────────────────────────

/// ألوان الهوية — نسختان (فاتح/داكن) تُختاران حسب سطوع الثيم.
abstract final class AppColors {
  // ── الأزرق الأساسي (كحلي طبي) ──
  static const Color primaryLight = Color(0xFF1B3C6E);
  static const Color primaryDark = Color(0xFF3E6DB5);
  static const Color primaryTintLight = Color(0xFFE9F0FA);
  static const Color primaryTintDark = Color(0xFF1C2C46);

  // ── الذهبي — الإنجاز والتحفيز (XP/سلسلة/شارات) ──
  static const Color goldLight = Color(0xFFE8A33D);
  static const Color goldDark = Color(0xFFF0B45A);
  static const Color onGold = Color(0xFF3D2A08);

  /// ذهبي النصوص على الخلفية الفاتحة — داكن أكثر لتباين AA.
  static const Color goldTextLight = Color(0xFF8A5E10);
  static const Color goldTextDark = Color(0xFFF0B45A);

  /// الأسطح والنصوص ──
  static const Color bgLight = Color(0xFFF6F8FB);
  static const Color bgDark = Color(0xFF0F1520);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1A2332);
  // دفء محافظ: السطح البديل (حقول/رؤوس) كريمي دافئ بدل المزرقة الباردة —
  // يعكس خلفية الرسوم المرساة بدون مما يرفه خلفية الصفحة الأساسية.
  static const Color surfaceAltLight = Color(0xFFF3EDE4);
  static const Color surfaceAltDark = Color(0xFF242C36);

  /// لون نص القراءة العميقة في الداكن — رمادي فاتح 90% بدل الأبيض
  /// النقي (منع Halation — توهج الحروف الذي يجعلها «تنزف»).
  static const Color focusTextDark = Color(0xFFE6E6E6);

  static const Color textLight = Color(0xFF17202E);
  static const Color textDark = Color(0xFFEAF0F8);
  static const Color textSecondaryLight = Color(0xFF5B6879);
  static const Color textSecondaryDark = Color(0xFF9AA7B8);

  static const Color borderLight = Color(0xFFE3E9F0);
  static const Color borderDark = Color(0xFF2C3A50);

  // ── الحالة ──
  static const Color successLight = Color(0xFF1E8E4E);
  static const Color successDark = Color(0xFF4CC17E);
  static const Color errorLight = Color(0xFFD64545);
  static const Color errorDark = Color(0xFFE46B6B);
  static const Color successContainerLight = Color(0xFFE6F5EC);
  static const Color successContainerDark = Color(0xFF143524);
  static const Color errorContainerLight = Color(0xFFFBEAEA);
  static const Color errorContainerDark = Color(0xFF3A1A1A);

  // ── التخصصات الطبية — نظام «الحاوية أولاً» (Container-First) ──
  //
  // الفلسفة: لكل تخصص مستويين فقط بدل اللون الخام:
  //   accent (النص/الأيقونة) + container (الخلفية 12-14%) — التمييز
  //   يأتي من درجة اللون (Hue) لا من بريقه.
  //
  // في الفاتح: ألوان أنقى «نظافة طبية» (إضاءة مضبوطة، ليست درجات
  //   ماتيريال الثقيلة 700).
  // في الداكن: كل الألوان بنفس السطوح تقريباً (L≈72%) — العين لا
  //   تتعب لأنها لا تكافح سطوعاً متفاوتاً؛ باستيل واعٍ لا باهت.
  //
  // قلب أحمر • تنفس سماوي • كلى كهرماني • هضم زيتوني • غدد بنفسجي
  // دم قرمزي • عدوى برتقالي • رثوية تركوازي • عصب نيلي • أورام وردي
  static const Color moduleCardio = Color(0xFFE14B4B);
  static const Color modulePulmo = Color(0xFF1E96C8);
  static const Color moduleNephro = Color(0xFFC77F1E);
  static const Color moduleGastro = Color(0xFF5F9E3E);
  static const Color moduleEndo = Color(0xFF8B5CC9);
  static const Color moduleHema = Color(0xFFB33939);
  static const Color moduleInfect = Color(0xFFF28436);
  static const Color moduleRheuma = Color(0xFF1FA8A0);
  static const Color moduleNeuro = Color(0xFF4A67C4);
  static const Color moduleOnco = Color(0xFFD4568D);

  /// نسخ الداكن — سطوع موحد (L≈72%): تدرجات الإضاءة نفسها لكل
  /// التخصصات فلا صراع سطوع على العين المتكيفة مع الظلام.
  static const Color moduleCardioDark = Color(0xFFE8837E);
  static const Color modulePulmoDark = Color(0xFF7EC3E8);
  static const Color moduleNephroDark = Color(0xFFE8B478);
  static const Color moduleGastroDark = Color(0xFF9ACB7E);
  static const Color moduleEndoDark = Color(0xFFC0A0E0);
  static const Color moduleHemaDark = Color(0xFFE08A87);
  static const Color moduleInfectDark = Color(0xFFF0A878);
  static const Color moduleRheumaDark = Color(0xFF7CCFC9);
  static const Color moduleNeuroDark = Color(0xFF9FB0E5);
  static const Color moduleOncoDark = Color(0xFFEE93BC);

  // ── نسخ «نص» للتخصصات — أغمق لاجتياز تباين AA على الفاتح ──
  // (نفس فلسفة goldText: لون العرض ≠ لون النص على الأبيض).
  static const Color moduleCardioText = Color(0xFFB02828);
  static const Color modulePulmoText = Color(0xFF146A94);
  static const Color moduleNephroText = Color(0xFF8F5B0F);
  static const Color moduleGastroText = Color(0xFF3D6E26);
  static const Color moduleEndoText = Color(0xFF653B9E);
  static const Color moduleHemaText = Color(0xFF8A2323);
  static const Color moduleInfectText = Color(0xFFB85F13);
  static const Color moduleRheumaText = Color(0xFF0F7A73);
  static const Color moduleNeuroText = Color(0xFF2F4A9E);
  static const Color moduleOncoText = Color(0xFFAD2F68);

  // ── حاويات التخصصات — خلفية امتزاج بالسطح لا اللون الخام ──
  static const Color moduleCardioContainerLight = Color(0xFFFDECEC);
  static const Color modulePulmoContainerLight = Color(0xFFE8F3FA);
  static const Color moduleNephroContainerLight = Color(0xFFFBF1E2);
  static const Color moduleGastroContainerLight = Color(0xFFF0F6EA);
  static const Color moduleEndoContainerLight = Color(0xFFF2EDFA);
  static const Color moduleHemaContainerLight = Color(0xFFFBEBEB);
  static const Color moduleInfectContainerLight = Color(0xFFFEF2E9);
  static const Color moduleRheumaContainerLight = Color(0xFFE6F5F4);
  static const Color moduleNeuroContainerLight = Color(0xFFEBEFF9);
  static const Color moduleOncoContainerLight = Color(0xFFFCEBF3);

  static const Color moduleCardioContainerDark = Color(0xFF3A2325);
  static const Color modulePulmoContainerDark = Color(0xFF20313F);
  static const Color moduleNephroContainerDark = Color(0xFF3B3021);
  static const Color moduleGastroContainerDark = Color(0xFF263423);
  static const Color moduleEndoContainerDark = Color(0xFF302741);
  static const Color moduleHemaContainerDark = Color(0xFF3A2422);
  static const Color moduleInfectContainerDark = Color(0xFF3D2E22);
  static const Color moduleRheumaContainerDark = Color(0xFF1F3836);
  static const Color moduleNeuroContainerDark = Color(0xFF262E44);
  static const Color moduleOncoContainerDark = Color(0xFF3A2532);

  /// مرجاني «Energy» — لون الحيوية الثاني (مع الذهبي) للتفاعلات
  /// الإيجابية الخفيفة. لا يظهر إلا في لحظات الفعل.
  static const Color coralLight = Color(0xFFFF6B6B);
  static const Color coralDark = Color(0xFFFF8787);

  // ── التخصصات السريرية الكبرى (v20) — ألوان الهوية الأساسية ──
  //
  // فلسفة «حدود لا ظلال» نفسها: primary للنص/الأيقونة + container
  // للخلفية (امتزاج بالسطح) — التمييز بدرجة اللون لا ببريقه.
  //   باطنية = الكحلي التاريخي للمنصة · جراحة = أخضر العقال ·
  //   نسائية = أرجواني وردّي.

  /// باطنية — الكحلي الأساسي نفسه (primaryLight/Dark).
  static Color specialtyPrimary(
    String specialty,
    Brightness b,
  ) => switch (specialty) {
        'surgery' =>
          b == Brightness.dark ? surgeryPrimaryDark : surgeryPrimary,
        'obgyn' => b == Brightness.dark ? obgynPrimaryDark : obgynPrimary,
        _ => b == Brightness.dark ? primaryDark : primaryLight,
      };

  /// حاوية التخصص — خلفية تظليل خفيفة للرؤوس والشرائح.
  static Color specialtyContainer(
    String specialty,
    Brightness b,
  ) => switch (specialty) {
        'surgery' => b == Brightness.dark
            ? surgeryContainerDark
            : surgeryContainer,
        'obgyn' =>
          b == Brightness.dark ? obgynContainerDark : obgynContainer,
        _ => b == Brightness.dark
            // الدفء المحافظ: كحلي الباطنية يصبغه دفء كريمي خفيف.
            ? const Color(0xFF232E3F)
            : const Color(0xFFE9E7DF),
      };

  /// نص فوق حاوية التخصص — داكن لاجتياز AA فاتحاً وفاتح داكناً
  /// (نفس عقد onPrimaryContainer في الثيم).
  static Color specialtyOnContainer(
    String specialty,
    Brightness b,
  ) => switch (specialty) {
        'surgery' => b == Brightness.dark
            ? const Color(0xFFCDEBDD)
            : const Color(0xFF0A3D28),
        'obgyn' => b == Brightness.dark
            ? const Color(0xFFEBD5F1)
            : const Color(0xFF3D1448),
        _ => b == Brightness.dark
            ? const Color(0xFFD7E5FA)
            : const Color(0xFF0A2A55),
      };

  /// أخضر الجراحة (scrub green) — أنقى من زيتوني الهضمي: هوية غرفة
  /// العمليات. النسخة الداكنة بنفس سطوح باقي التخصصات (L≈72%).
  static const Color surgeryPrimary = Color(0xFF1E7A5A);
  static const Color surgeryPrimaryDark = Color(0xFF66C79E);
  static const Color surgeryContainer = Color(0xFFE4F3ED);
  static const Color surgeryContainerDark = Color(0xFF1E382E);

  /// أرجواني النسائية — بنفسجي دافئ بلمسة وردّية.
  static const Color obgynPrimary = Color(0xFF8E4B9E);
  static const Color obgynPrimaryDark = Color(0xFFC99BD6);
  static const Color obgynContainer = Color(0xFFF5ECF8);
  static const Color obgynContainerDark = Color(0xFF38223F);

  // ── شريط التوقيع الثلاثي (رمادي/أحمر/ذهبي) ──
  static const Color signatureGray = Color(0xFF9AA7B8);
  static const Color signatureRed = Color(0xFFD64545);
  static const Color signatureGold = Color(0xFFE8A33D);

  // ── اختيار حسب السطوع ──

  /// الأساسي (كحلي) حسب السطوع.
  static Color primary(Brightness b) =>
      b == Brightness.dark ? primaryDark : primaryLight;

  /// تنت الأساسي (خلفية بطاقات/ترويسات لطيفة).
  static Color primaryTint(Brightness b) =>
      b == Brightness.dark ? primaryTintDark : primaryTintLight;

  /// الذهبي (XP/إنجاز) حسب السطوع.
  static Color gold(Brightness b) =>
      b == Brightness.dark ? goldDark : goldLight;

  /// ذهبي **للنص** حسب السطوع — يجتاز AA على الخلفيتين.
  static Color goldText(Brightness b) =>
      b == Brightness.dark ? goldTextDark : goldTextLight;

  /// تظليل نص الملاحظة المضمّنة (Inline Highlight) — أصفر ذهبي ناعم
  /// بشفافية منخفضة (≈30%) كي يبقى النص تحته مقروءاً بوضوح (نمط
  /// Kindle). في الداكن: لمعة كهرمانية خافتة بدل الأصفر الصارخ — منع
  /// وهج خلفية ساطعة يرتد على القارئ المكيّف مع الظلام.
  static Color inlineNoteHighlight(Brightness b) => b == Brightness.dark
      ? const Color(0x3DE0A93E)
      : const Color(0x4DFFF1A6);

  /// خلفية الصفحات.
  static Color background(Brightness b) =>
      b == Brightness.dark ? bgDark : bgLight;

  /// السطح (بطاقات/أشرطة).
  static Color surface(Brightness b) =>
      b == Brightness.dark ? surfaceDark : surfaceLight;

  /// سطح ثانوي (حقول/رقاقات داخل بطاقة).
  static Color surfaceAlt(Brightness b) =>
      b == Brightness.dark ? surfaceAltDark : surfaceAltLight;

  /// نص أساسي.
  static Color text(Brightness b) =>
      b == Brightness.dark ? textDark : textLight;

  /// نص ثانوي.
  static Color textSecondary(Brightness b) =>
      b == Brightness.dark ? textSecondaryDark : textSecondaryLight;

  /// لون نص القراءة العميقة — نفس النص الأساسي فاتحاً، ورمادي فاتح
  /// (90%) داكناً بدل الأبيض النقي (منع Halation).
  static Color focusText(Brightness b) =>
      b == Brightness.dark ? focusTextDark : textLight;

  /// حدود 1px.
  static Color border(Brightness b) =>
      b == Brightness.dark ? borderDark : borderLight;

  /// نجاح (صحيح) حسب السطوع.
  static Color success(Brightness b) =>
      b == Brightness.dark ? successDark : successLight;

  /// خطأ (غلط) حسب السطوع.
  static Color error(Brightness b) =>
      b == Brightness.dark ? errorDark : errorLight;

  /// حاوية النجاح.
  static Color successContainer(Brightness b) =>
      b == Brightness.dark ? successContainerDark : successContainerLight;

  /// حاوية الخطأ.
  static Color errorContainer(Brightness b) =>
      b == Brightness.dark ? errorContainerDark : errorContainerLight;

  /// لون التخصص الطبي حسب السطوع — cardiology/pulmonology/...
  /// v21: المواد الجراحية تستعير أخضر الجراحة، والنسائية أرجوانيتها
  /// (specialtyPrimary) — تمييز بصري فوري لأصل المحاضرة.
  static Color module(String module, Brightness b) {
    final bool dark = b == Brightness.dark;
    switch (module.toLowerCase()) {
      case 'cardiology':
        return dark ? moduleCardioDark : moduleCardio;
      case 'pulmonology':
        return dark ? modulePulmoDark : modulePulmo;
      case 'nephrology':
        return dark ? moduleNephroDark : moduleNephro;
      case 'gastroenterology':
        return dark ? moduleGastroDark : moduleGastro;
      case 'endocrinology':
        return dark ? moduleEndoDark : moduleEndo;
      case 'hematology':
        return dark ? moduleHemaDark : moduleHema;
      case 'infectious':
        return dark ? moduleInfectDark : moduleInfect;
      case 'rheumatology':
        return dark ? moduleRheumaDark : moduleRheuma;
      case 'neurology':
        return dark ? moduleNeuroDark : moduleNeuro;
      case 'oncology':
        return dark ? moduleOncoDark : moduleOnco;
      // ── v21: مواد الجراحة — عائلة الأخضر الجراحي ──
      case 'general_surgery':
      case 'orthopedics':
      case 'neurosurgery':
      case 'pediatric_surgery':
      case 'surgical_oncology':
      case 'trauma':
        return specialtyPrimary('surgery', b);
      case 'urology':
      case 'plastic_surgery':
        return dark ? moduleNephroDark : moduleNephro;
      // ── v21: مواد النسائية — عائلة الأرجواني ──
      case 'obstetrics':
      case 'gynecology':
      case 'gynecologic_oncology':
      case 'reproductive_endocrinology':
      case 'maternal_fetal_medicine':
        return specialtyPrimary('obgyn', b);
      default:
        return primary(b);
    }
  }

  /// لون «نص» التخصص — أغمق في الفاتح لاجتياز AA (كما goldText).
  /// في الداكن = لون العرض نفسه (السطوع الموحد يكفي).
  static Color moduleText(String module, Brightness b) {
    if (b == Brightness.dark) return AppColors.module(module, b);
    switch (module.toLowerCase()) {
      case 'cardiology':
        return moduleCardioText;
      case 'pulmonology':
        return modulePulmoText;
      case 'nephrology':
        return moduleNephroText;
      case 'gastroenterology':
        return moduleGastroText;
      case 'endocrinology':
        return moduleEndoText;
      case 'hematology':
        return moduleHemaText;
      case 'infectious':
        return moduleInfectText;
      case 'rheumatology':
        return moduleRheumaText;
      case 'neurology':
        return moduleNeuroText;
      case 'oncology':
        return moduleOncoText;
      default:
        return primaryLight;
    }
  }

  /// حاوية التخصص — خلفية البطاقات/الرقاقات بلون التخصص ممزوجاً
  /// بالسطح (12-14%) — قلب نظام «الحاوية أولاً».
  static Color moduleContainer(String module, Brightness b) {
    final bool dark = b == Brightness.dark;
    switch (module.toLowerCase()) {
      case 'cardiology':
        return dark ? moduleCardioContainerDark : moduleCardioContainerLight;
      case 'pulmonology':
        return dark ? modulePulmoContainerDark : modulePulmoContainerLight;
      case 'nephrology':
        return dark ? moduleNephroContainerDark : moduleNephroContainerLight;
      case 'gastroenterology':
        return dark ? moduleGastroContainerDark : moduleGastroContainerLight;
      case 'endocrinology':
        return dark ? moduleEndoContainerDark : moduleEndoContainerLight;
      case 'hematology':
        return dark ? moduleHemaContainerDark : moduleHemaContainerLight;
      case 'infectious':
        return dark ? moduleInfectContainerDark : moduleInfectContainerLight;
      case 'rheumatology':
        return dark ? moduleRheumaContainerDark : moduleRheumaContainerLight;
      case 'neurology':
        return dark ? moduleNeuroContainerDark : moduleNeuroContainerLight;
      case 'oncology':
        return dark ? moduleOncoContainerDark : moduleOncoContainerLight;
      default:
        return primaryTint(b);
    }
  }

  /// اسم عربي للتخصص الطبي.
  static String moduleNameAr(String module) => switch (module.toLowerCase()) {
        'cardiology' => 'القلب',
        'pulmonology' => 'التنفس',
        'nephrology' => 'الكلى',
        'gastroenterology' => 'الهضمي',
        'endocrinology' => 'الغدد',
        'hematology' => 'الدم',
        'infectious' => 'العدوى',
        'rheumatology' => 'الرثوية',
        'neurology' => 'الأعصاب',
        'oncology' => 'الأورام',
        // v21: مواد الجراحة.
        'general_surgery' => 'الجراحة العامة',
        'orthopedics' => 'العظام',
        'neurosurgery' => 'جراحة الأعصاب',
        'urology' => 'المسالك',
        'plastic_surgery' => 'التجميل',
        'pediatric_surgery' => 'جراحة الأطفال',
        'surgical_oncology' => 'جراحة الأورام',
        'trauma' => 'الرضوض',
        // v21: مواد النسائية والتوليد.
        'obstetrics' => 'التوليد',
        'gynecology' => 'النسائية',
        'gynecologic_oncology' => 'أورام النسائية',
        'reproductive_endocrinology' => 'غدد التناسل',
        'maternal_fetal_medicine' => 'الأم والجنين',
        _ => 'عام',
      };

  /// اسم عربي للتخصص السريري الكبير (v20) — لشريط التبديل والرؤوس.
  static String specialtyNameAr(String specialty) =>
      switch (specialty) {
        'surgery' => 'الجراحة',
        'obgyn' => 'النسائية',
        _ => 'الباطنية',
      };

  /// أيقونة التخصص السريري الكبير — لشريط التبديل.
  static IconData specialtyIcon(String specialty) => switch (specialty) {
        'surgery' => Icons.healing_rounded,
        'obgyn' => Icons.child_friendly_rounded,
        _ => Icons.local_hospital_rounded,
      };
}

/// شبكة المسافات — مضاعفات 4:
/// هامش شاشة 20 · padding بطاقة 16 · فراغ بين البطاقات 12.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// هامش حواف الشاشة الموحد.
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: xl);

  /// padding البطاقة القياسي.
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// فاصل قياسي بين البطاقات.
  static const double betweenCards = md;
}

/// أنصاف الزوايا:
/// 12 لرقائق/حقول · 16 لبطاقات · 20 لبطاقات كبيرة/شيتات · pill للشرائح.
abstract final class AppRadius {
  static const double chip = 12;
  static const double field = 12;
  static const double card = 16;
  static const double sheet = 20;
  static const double pill = 999;
}

/// الظلال — هويةً «حدود لا ظلال»، لكن بعمق مادي من طبقتين:
/// طبقة قريبة تعطي «الوزن» + طبقة بعيدة تعطي «الطفو» — دون كسر
/// مبدأ الحد 1px.
abstract final class AppShadows {
  /// الظل القياسي للبطاقات — طبقتان (قريبة 2/4 + بعيدة 6/16).
  static List<BoxShadow> card(Brightness b) => <BoxShadow>[
        BoxShadow(
          color: b == Brightness.dark
              ? const Color(0x1A000000)
              : const Color(0x08144070),
          offset: const Offset(0, 2),
          blurRadius: 4,
        ),
        BoxShadow(
          color: b == Brightness.dark
              ? const Color(0x1A102030)
              : const Color(0x14144070),
          offset: const Offset(0, 6),
          blurRadius: 16,
        ),
      ];

  /// ظل أعمق قليلاً للعناصر العائمة (شيتات/أزرار بارزة).
  static List<BoxShadow> floating(Brightness b) => <BoxShadow>[
        BoxShadow(
          color: b == Brightness.dark
              ? const Color(0x24000000)
              : const Color(0x0C144070),
          offset: const Offset(0, 3),
          blurRadius: 6,
        ),
        BoxShadow(
          color: b == Brightness.dark
              ? const Color(0x29102030)
              : const Color(0x1F144070),
          offset: const Offset(0, 8),
          blurRadius: 24,
        ),
      ];

  /// الحد الداخلي المضيء — داكن فقط: خط أبيض 4-6% أعلى السطح
  /// يجعل البطاقة تبدو «مضاءة من الأعلى» (سر عمق التطبيقات
  /// الداكنة الراقية — Notion/Apple). في الفاتح: بلا أثر.
  static Border? innerGlow(Brightness b) => b == Brightness.dark
      ? Border(top: BorderSide(color: const Color(0x0DFFFFFF)))
      : null;
}

/// التدرجات المقدسة — الأماكن الثلاثة الوحيدة المسموح فيها تدرج
/// لوني في التطبيق كله (بطاقة الهدف اليومية، رفع المستوى، شريط XP).
/// في كل ما عداها: ألوان مسطحة صافية.
abstract final class AppGradients {
  /// تدرج الذهبي الاحتفالي — 165 درجة، ذهبي إلى كهرماني أدكن.
  static const List<double> goldStops = <double>[0.0, 1.0];
  static const List<Color> gold = <Color>[
    Color(0xFFF0B45A), // ذهبي فاتح
    Color(0xFFD98E1F), // كهرماني
  ];

  /// تدرج الحلقة عند اكتمال الهدف اليومي — أخضر نابض.
  static const List<Color> success = <Color>[
    Color(0xFF4CC17E),
    Color(0xFF1E8E4E),
  ];

  /// تدرج الهوية الدافئ — ذهبي مرساة الرسوم إلى كهرماني أدكن.
  /// للرؤوس/البطاقات البارزة (مرساة illustrations/units).
  static const List<Color> warmGold = <Color>[
    Color(0xFFE5A055),
    Color(0xFFC9822A),
  ];

  /// تدرج نحاسي–مرجاني — لبطاقات الحالات/الإنجازات الحية.
  static const List<Color> warmCoral = <Color>[
    Color(0xFFDC715A),
    Color(0xFFB24E3C),
  ];

  /// تدرج حكيم هادئ — لبطاقات الشروحات/التعلّم.
  static const List<Color> warmSage = <Color>[
    Color(0xFF75A088),
    Color(0xFF51725F),
  ];
}

/// الحركة — المدد والمنحنيات القياسية:
/// 120ms ردود فعل · 220ms قياسي · 300ms انتقالات · 500ms احتفالات.
abstract final class AppMotion {
  static const Duration feedback = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration transition = Duration(milliseconds: 300);
  static const Duration celebration = Duration(milliseconds: 500);

  /// الظهور المرح (عناصر تدخل بثقة).
  static const Curve popIn = Cubic(0.34, 1.56, 0.64, 1); // easeOutBack

  /// الافتراضي لكل شيء تقريباً.
  static const Curve ease = Curves.easeOutCubic;

  /// الخروج — أسرع وأهدأ.
  static const Curve out = Curves.easeIn;

  /// هل الحركات مفعّلة على هذا الجهاز؟ (احترام إعداد النظام).
  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);

  /// تُطبَّق على أي مدة: تُقصَّر لصفر عند تعطيل الحركة.
  static Duration scaled(BuildContext context, Duration d) =>
      enabled(context) ? d : Duration.zero;
}

/// الطباعة — Cairo للعربية، بأحجام الهوية.
abstract final class AppType {
  static const String arabicFamily = 'Cairo';

  /// الخط اللاتيني للمصطلحات الطبية الإنجليزية داخل النص العربي.
  static const String latinFamily = 'Nunito';

  // أوزان وأحجام موحدة:
  static const TextStyle screenTitle = TextStyle(
    fontFamily: arabicFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: arabicFamily,
    fontSize: 19,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle body = TextStyle(
    fontFamily: arabicFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: arabicFamily,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );

  /// المصطلح الطبي الكبير داخل البطاقات — 34/800 Nunito.
  static const TextStyle termWord = TextStyle(
    fontFamily: latinFamily,
    fontSize: 34,
    fontWeight: FontWeight.w800,
  );

  /// الخط اللاتيني للقراءة العميقة — أجسام الشروحات الطويلة.
  ///
  /// Atkinson Hyperlegible: أشكال حروف متمايزة جذرياً (i/l/1، 0/O،
  /// b/d/p/q) — مصمم مختبرياً لسوء القراءة، مثالي للمصطلحات
  /// الطبية اللاتينية المتشابهة (hyperkalemia/hypokalemia).
  static const String focusFamily = 'AtkinsonHyperlegible';

  /// نمط القراءة العميقة **العربية** — للحالات السريرية الطويلة.
  ///
  /// فلسفة الراحة: تباعد أسطر أوسع (1.8) لأن الحروف العربية
  /// المتصلة تحتاج «تنفساً» عمودياً أكثر من اللاتينية + مقاس أكبر
  /// (17) لأن السريرية تُقرأ بعناية مرة واحدة لا مسحاً بصرياً.
  static const TextStyle focusBodyAr = TextStyle(
    fontFamily: arabicFamily,
    fontSize: 17,
    height: 1.8,
    letterSpacing: 0.1,
  );

  /// نمط المصطلح الطبي داخل النص العربي (LTR inline) — Nunito بوزن
  /// 700 + لون التخصص يُمرر عند الاستخدام.
  static const TextStyle focusTermInline = TextStyle(
    fontFamily: latinFamily,
    fontWeight: FontWeight.w700,
  );
}

/// درجات السلسلة 🔥 — لون اللهب يتدرج مع طول السلسلة نحو الذهبي.
abstract final class AppFlame {
  /// لون شريحة السلسلة حسب طولها — يبدأ كهرمانياً هادئاً ويشتعل
  /// ذهبياً عند المعالم (7 = أسبوع، 30 = شهر).
  static Color forStreak(int streak, Brightness b) {
    if (streak <= 0) return AppColors.textSecondary(b);
    if (streak >= 30) return AppColors.goldDark;
    if (streak >= 7) return AppColors.gold(b);
    // 1-6: كهرماني ينضج تدريجياً نحو الذهبي.
    final double t = (streak - 1) / 6.0;
    final Color amber = b == Brightness.dark
        ? const Color(0xFFF0A878)
        : const Color(0xFFF28436);
    return Color.lerp(amber, AppColors.gold(b), t)!;
  }
}
