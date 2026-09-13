import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// مراسي التثبيت (Fixation Anchors) — نسخة عامة من مفهوم «تثبيت أول
/// المقطع» للنصوص اللاتينية الطبية حصراً.
///
/// الآلية: تعريض أول نسبة من حروف كل كلمة (الافتراضي 40%) يجعل العين
/// تقفز كلمات كاملة (Saccade Grouping) بدلاً من مسحها حرفاً حرفاً —
/// تسريع الاكتساب الأول للنص الجديد.
///
/// القواعد الحرجة:
/// - **لاتيني فقط**: أجسام الشروحات إنجليزية (body_text) — تقسيم
///   الكلمة اللاتينية إلى TextSpans آمن تماماً. العربية محظورة هنا
///   (كسر اتصال الحروف) — انظر [buildAnchoredSpansArabic] للحل
///   المتناوب الآمن إن لزم لاحقاً.
/// - **القراءة الأولى فقط**: النص المألوف مع المراسي تشويش لا مساعدة
///   — المستدعي يقرر التفعيل حسب سجل concept_reads.
/// - دالة نقية بلا حالة — قابلة للاختبار المباشر.
/// ─────────────────────────────────────────────────────────────────────

/// مستويات قوة المرساة المتاحة للمستخدم (نسبة طول الكلمة المعرَّض).
enum FixationStrength {
  gentle(0.30),
  standard(0.40),
  strong(0.60);

  const FixationStrength(this.ratio);

  /// نسبة حروف الكلمة التي تُعرَّض كمرساة (0.30/0.40/0.60).
  final double ratio;

  /// الرمز المخزن في SharedPreferences.
  String get code => switch (this) {
        FixationStrength.gentle => '30',
        FixationStrength.standard => '40',
        FixationStrength.strong => '60',
      };

  static FixationStrength fromCode(String? code) => switch (code) {
        '30' => FixationStrength.gentle,
        '60' => FixationStrength.strong,
        _ => FixationStrength.standard,
      };

  /// الاسم العربي للإعدادات.
  String get labelAr => switch (this) {
        FixationStrength.gentle => 'خفيفة',
        FixationStrength.standard => 'متوازنة',
        FixationStrength.strong => 'قوية',
      };
}

/// هل الحرف جزء من كلمة لاتينية قابلة للمرساة؟
///
/// نقبل: الحروف a-z/A-Z والأرقام (المصطلحات مثل T2DM، HbA1c، NSAIDs).
/// الفواصل (شرطة/نقطة/شرطة مائلة) تقسم الكلمة — hyphen-kalemia تُعالج
/// كل جزء على حدة لأن العين تثبت على المقاطع لا الشرطة.
bool _isLatinWordChar(String ch) {
  final int c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x30 && c <= 0x39); // 0-9
}

/// تبني مرساة كلمة واحدة: [partBold + partRest].
///
/// كلمات أقصر من 3 حروف لا تُمرساة (لا تُجزأ أصلاً — كلمة من حرفين
/// مرساتها كاملة تلغي الغرض وتشوه الإيقاع البصري).
List<TextSpan> _anchorWord(String word, TextStyle base, double ratio) {
  if (word.length < 3) {
    return <TextSpan>[TextSpan(text: word)];
  }
  final int cut =
      (word.length * ratio).round().clamp(1, word.length - 1);
  return <TextSpan>[
    TextSpan(
      text: word.substring(0, cut),
      style: base.copyWith(fontWeight: FontWeight.w700),
    ),
    TextSpan(text: word.substring(cut)),
  ];
}

/// البناء الأساسي — يمرس نصاً لاتينياً كاملاً إلى قائمة TextSpans.
///
/// [text] النص الإنجليزي (body_text / question / heading).
/// [base] نمط النص الأساسي (يجب أن يكون fontFamily =
/// AppType.focusFamily).
/// [strength] قوة المرساة (نسبة التعريض).
///
/// المرساة بوزن 700 فقط — بلا تغيير لون أو حجم كي يبقى التتبع
/// الساكادي سلساً عبر حدود المرساة. مسح خطي واحد: مقاطع الكلمات
/// تُمرسى، والفواصل بينها تمر كما هي.
List<TextSpan> buildAnchoredSpans(
  String text,
  TextStyle base, {
  FixationStrength strength = FixationStrength.standard,
}) {
  if (text.isEmpty) return <TextSpan>[TextSpan(text: text)];

  final List<TextSpan> out = <TextSpan>[];
  int i = 0;
  while (i < text.length) {
    final bool wordStart = _isLatinWordChar(text[i]);
    int j = i;
    while (j < text.length && _isLatinWordChar(text[j]) == wordStart) {
      j++;
    }
    final String segment = text.substring(i, j);
    i = j;
    if (wordStart) {
      out.addAll(_anchorWord(segment, base, strength.ratio));
    } else {
      out.add(TextSpan(text: segment));
    }
  }
  return out;
}

/// الحل الآمن للنص العربي (إن استُخدم مستقبلاً): تظليل الكلمات
/// بالتناوب (زوجية عريضة) — تجميع بصري بلا أي تقسيم داخل كلمة.
List<TextSpan> buildAnchoredSpansArabic(
  String text,
  TextStyle base,
) {
  if (text.isEmpty) return <TextSpan>[TextSpan(text: text)];
  final List<String> parts = text.split(' ');
  return <TextSpan>[
    for (int i = 0; i < parts.length; i++) ...<TextSpan>[
      TextSpan(
        text: parts[i],
        style: i.isEven
            ? base.copyWith(fontWeight: FontWeight.w700)
            : base,
      ),
      if (i < parts.length - 1) const TextSpan(text: ' '),
    ],
  ];
}

/// نمط جسم القراءة العميقة الموحد — 18sp · ارتفاع 1.7 · Atkinson ·
/// رمادي 90% داكناً (منع Halation) · بلا Justify (TextAlign.start).
TextStyle focusBodyStyle(Brightness b) => TextStyle(
      fontFamily: AppType.focusFamily,
      fontSize: 18,
      height: 1.7,
      letterSpacing: 0.2,
      color: AppColors.focusText(b),
    );

/// نمط عنوان القسم (heading) داخل قارئ اللقطات — أثقل قليلاً.
TextStyle focusHeadingStyle(Brightness b) => TextStyle(
      fontFamily: AppType.focusFamily,
      fontSize: 20,
      height: 1.4,
      fontWeight: FontWeight.w700,
      color: AppColors.focusText(b),
    );

/// ─────────────────────────────────────────────────────────────────────
/// القراءة العميقة العربية — للحالات السريرية والنصوص العربية الطويلة.
///
/// فلسفة الراحة: تباعد أسطر 1.8 (الحروف العربية المتصلة تحتاج
/// «تنفساً» عمودياً أكثر) + 17sp (المحتوى السريري يُقرأ بعناية
/// مرة واحدة لا مسحاً بصرياً) + حد أقصى 65-75 حرفاً بالسطر.
/// ─────────────────────────────────────────────────────────────────────

/// نمط جسم القراءة العربية العميقة.
TextStyle focusBodyArStyle(Brightness b) => TextStyle(
      fontFamily: AppType.arabicFamily,
      fontSize: 17,
      height: 1.8,
      letterSpacing: 0.1,
      color: AppColors.focusText(b),
    );

/// نمط المصطلح الطبي اللاتيني داخل نص عربي — Nunito 700 بلون
/// التخصص (يُمرر عند الاستخدام) — العين تعرف أين تعود.
TextStyle focusTermStyle(Brightness b, {Color? termColor}) => TextStyle(
      fontFamily: AppType.latinFamily,
      fontWeight: FontWeight.w700,
      color: termColor ?? AppColors.primary(b),
    );

/// بطاقة فقرة سريرية — شريط جانبي عمودي رفيع (2px) بلون التخصص
/// يوجّه العين عمودياً كـ«مسار قراءة» ويمنع الضياع بين الفقرات.
class ClinicalParagraph extends StatelessWidget {
  const ClinicalParagraph({
    required this.text,
    this.accent,
    super.key,
  });

  /// نص الفقرة — عربي غالباً مع مصطلحات لاتينية محتملة.
  final String text;

  /// لون شريط المسار — لون تخصص الحالة عادة.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color barColor =
        accent ?? AppColors.primary(b);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // شريط مسار القراءة — 2px بلون التخصص.
            Container(
              width: 2,
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.start, // لا Justify أبداً.
                style: focusBodyArStyle(b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
