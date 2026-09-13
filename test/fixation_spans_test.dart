import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/features/curriculum/presentation/widgets/fixation_spans.dart';
import 'package:medicine_app/src/theme/tokens.dart';

void main() {
  const TextStyle base = TextStyle(
    fontFamily: AppType.focusFamily,
    fontSize: 18,
    height: 1.7,
  );

  group('بناء مراسي التثبيت (لاتيني)', () {
    test('النص الفارغ → span واحد فارغ', () {
      final List<TextSpan> spans =
          buildAnchoredSpans('', base, strength: FixationStrength.standard);
      expect(spans.length, 1);
      expect(spans.first.text, '');
    });

    test('كلمة واحدة تُقسم مرساة + بقية — النص الكامل محفوظ', () {
      final String word = 'hyperkalemia';
      for (final FixationStrength s in FixationStrength.values) {
        final List<TextSpan> spans =
            buildAnchoredSpans(word, base, strength: s);
        expect(
          spans.map((TextSpan s) => s.text ?? '').join(),
          word,
          reason: 'قوة ${s.labelAr}: النص يجب أن يُحفظ حرفياً',
        );
        // المرساة (الجزء الأول) عريضة دائماً.
        expect(spans.first.style?.fontWeight, FontWeight.w700);
      }
    });

    test('قوة المرساة تحدد نقطة القطع', () {
      final List<TextSpan> spans40 = buildAnchoredSpans(
        'cardiology',
        base,
        strength: FixationStrength.standard,
      );
      // 10 حروف × 0.4 = 4 حروف معرَّضة.
      expect(spans40.first.text, 'card');
      expect(spans40[1].text, 'iology');

      final List<TextSpan> spans60 = buildAnchoredSpans(
        'cardiology',
        base,
        strength: FixationStrength.strong,
      );
      // 10 حروف × 0.6 = 6.
      expect(spans60.first.text, 'cardio');
      expect(spans60[1].text, 'logy');
    });

    test('جملة كاملة: كل الكلمات تُمرسى والفواصل تمر كما هي', () {
      const String text = 'Heart failure causes volume overload.';
      final List<TextSpan> spans = buildAnchoredSpans(
        text,
        base,
        strength: FixationStrength.standard,
      );
      // الحفظ الحرفي الكامل — لا فقد ولا تكرار.
      expect(spans.map((TextSpan s) => s.text ?? '').join(), text);
      // الفاصلة والنقطة (غير كلمات) ليست عريضة.
      final TextSpan dot = spans.last;
      expect(dot.text, '.');
      expect(dot.style?.fontWeight, isNot(FontWeight.w700));
    });

    test('الكلمات القصيرة (<3 حروف) لا تُجزأ', () {
      const String text = 'of T wave';
      final List<TextSpan> spans = buildAnchoredSpans(
        text,
        base,
        strength: FixationStrength.standard,
      );
      // 'of' (2) و'T' (1) كلمات قصيرة — span واحد غير عريض لكل منها.
      final TextSpan of = spans.firstWhere((TextSpan s) => s.text == 'of');
      expect(of.style?.fontWeight, isNot(FontWeight.w700));
      final TextSpan t = spans.firstWhere((TextSpan s) => s.text == 'T');
      expect(t.style?.fontWeight, isNot(FontWeight.w700));
      // 'wave' (4 حروف) تُمرسى: round(4×0.4)=2 → 'wa' عريضة + 've'.
      final TextSpan wa = spans.firstWhere((TextSpan s) => s.text == 'wa');
      expect(wa.style?.fontWeight, FontWeight.w700);
      expect(spans.map((TextSpan s) => s.text ?? '').join(), text);
    });

    test('المصطلحات المختلطة بالأرقام تُمرسى (T2DM, HbA1c)', () {
      const String text = 'T2DM HbA1c 5.9';
      final List<TextSpan> spans = buildAnchoredSpans(
        text,
        base,
        strength: FixationStrength.standard,
      );
      expect(spans.map((TextSpan s) => s.text ?? '').join(), text);
      // T2DM (4 محارف × 0.4 = 1.6 → 2) — الجزء الأول عريض.
      expect(spans.first.text, 'T2');
      expect(spans.first.style?.fontWeight, FontWeight.w700);
    });

    test('الشرطة تقسم الكلمة — كل جزء يُمرسى على حدة', () {
      const String text = 'sino-atrial';
      final List<TextSpan> spans = buildAnchoredSpans(
        text,
        base,
        strength: FixationStrength.standard,
      );
      expect(spans.map((TextSpan s) => s.text ?? '').join(), text);
      // 'sino' (4 حروف × 0.4 = 1.6 → round = 2): 'si' عريضة + 'no'.
      expect(spans.first.text, 'si');
      expect(spans.first.style?.fontWeight, FontWeight.w700);
      expect(spans[1].text, 'no');
      expect(spans[1].style?.fontWeight, isNot(FontWeight.w700));
      // الفواصل مقاطع مستقلة عادية.
      expect(spans[2].text, '-');
      expect(spans[2].style?.fontWeight, isNot(FontWeight.w700));
      // 'atrial' (6 × 0.4 = 2.4 → round = 2): 'at' عريضة + 'rial'.
      expect(spans[3].text, 'at');
      expect(spans[3].style?.fontWeight, FontWeight.w700);
      expect(spans[4].text, 'rial');
    });
  });

  group('قوة المرساة (enum)', () {
    test('الرموز: 30/40/60 ذهاب وعودة', () {
      expect(FixationStrength.fromCode('30'), FixationStrength.gentle);
      expect(FixationStrength.fromCode('40'), FixationStrength.standard);
      expect(FixationStrength.fromCode('60'), FixationStrength.strong);
      // رمز مجهول → الافتراضي متوازنة.
      expect(FixationStrength.fromCode(null), FixationStrength.standard);
      expect(FixationStrength.fromCode('xx'), FixationStrength.standard);
    });

    test('النسب صحيحة', () {
      expect(FixationStrength.gentle.ratio, 0.30);
      expect(FixationStrength.standard.ratio, 0.40);
      expect(FixationStrength.strong.ratio, 0.60);
    });
  });

  group('مراسي العربية (الحل المتناوب الآمن)', () {
    test('التناوب الزوجي عريض والكلمات لا تُقسم أبداً', () {
      const String text = 'ارتفاع البوتاسيوم في الدم';
      final List<TextSpan> spans = buildAnchoredSpansArabic(text, base);
      // كل كلمة span واحد كامل — لا تقسيم داخل كلمة إطلاقاً.
      final List<String> words = text.split(' ');
      for (int i = 0; i < words.length; i++) {
        final TextSpan span = spans
            .whereType<TextSpan>()
            .firstWhere((TextSpan s) => s.text == words[i]);
        // الكلمة كاملة داخل span واحد (عدا الفواصل ' ' المنفصلة).
        if (i.isEven) {
          expect(span.style?.fontWeight, FontWeight.w700);
        } else {
          expect(span.style?.fontWeight, isNot(FontWeight.w700));
        }
      }
    });
  });
}
