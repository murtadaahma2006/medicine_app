import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/inline_note.dart';
import '../../../../theme/tokens.dart';
import 'fixation_spans.dart';

/// ─────────────────────────────────────────────────────────────────────
/// بناء أجزاء النص المميَّز (Inline Highlights) لشروحات القراءة العميقة.
///
/// الآلية (نمط Kindle/Apple Books):
/// 1. يمسح النص الكامل (body) بحثاً عن أي `selected_text` محفوظ.
/// 2. كل جزء يطابق نصاً محفوظاً (حساس لحالة الأحرف — صيغة طبية
///    لاتينية دقيقة) يُلبس خلفية تمييز ناعمة + مقبض نقر.
/// 3. النقر على الجزء المميَّز يعرض ملاحظة المستخدم الشخصية.
/// 4. المقاطع غير المميّزة تُعاد كما هي بصيغة [base] المحفوظة.
///
/// التكرارات: يُعالج كل ظهور منفصلاً مع استهلاك مؤشر المسح — لا
/// تضييع لنص ولا تداخل أبداً (المسح خطي يحافظ على النص كاملاً).
/// ─────────────────────────────────────────────────────────────────────

/// تظليل التمييز في **الوضع الفاتح** — أصفر ذهبي ناعم بشفافية ≈30%.
/// يُستخدم افتراضياً في هذه الأداة عندما لا يُمرَّر سطوع الثيم، وفي
/// شيت «إضافة ملاحظة». في صفحة القارئ يُعتمد
/// [AppColors.inlineNoteHighlight] الحسّاس لسطوع الثيم (الدالة
/// [buildInlineNoteSpans] تقبله عبر وسيط [brightness]).
const Color kInlineNoteHighlight = Color(0x4DFFF1A6);

/// مسار النقر على نص مميَّز — يُمرّر للمعالج الخارجي ليعرض الملاحظة.
typedef InlineNoteTapCallback = void Function(InlineNote note);

/// يبني قائمة أجزاء النص لنص كامل مع تمييز الملاحظات المضمّنة.
///
/// [text] نص القسم/الجسم الكامل (body_text).
/// [notes] الملاحظات المحفوظة لهذا الشرح (قد تحتوي نصوصاً غير
///        موجودة فعلاً في نص القسم الحالي — تُتجاهل بأمان).
/// [base] النمط الأساسي (يُحفظ لكل جزء تلقائياً عبر شجرة الأجزاء).
/// [onTap] معالج النقر على جزء مميَّز (اختياري — بدونه لا يُضاف
///        معرّف نقر والتمييز يظهر فقط للقراءة).
/// [brightness] سطوع الثيم — لاختيار لون التظليل (أصفر ناعم نهاراً،
///        كهرماني خافت ليلاً). يُغفل افتراضياً فيُستخدم لون الفاتح.
/// [useAnchors] تطبيق مراسي التثبيت على المقاطع **غير المميّزة** فقط
///        (حتى لا نكسر أنماط التمييز).
/// [anchorStrength] قوة المرساة عند [useAnchors].
///
/// يرجع قائمة [TextSpan] — تُسلَّم مباشرة لـ [TextSpan.children]
/// (نفس عقد buildAnchoredSpans القائم).
List<TextSpan> buildInlineNoteSpans(
  String text,
  List<InlineNote> notes, {
  required TextStyle base,
  InlineNoteTapCallback? onTap,
  Brightness? brightness,
  bool useAnchors = false,
  FixationStrength anchorStrength = FixationStrength.standard,
}) {
  if (text.isEmpty) return <TextSpan>[TextSpan(text: text, style: base)];

  final Color highlight = brightness == null || brightness == Brightness.light
      ? kInlineNoteHighlight
      : AppColors.inlineNoteHighlight(Brightness.dark);

  // 1. Filter valid notes and migrate legacy notes dynamically
  final List<InlineNote> applicable = <InlineNote>[];
  for (final InlineNote n in notes) {
    int start = n.startIndex;
    int end = n.endIndex;

    // Legacy fallback: if note was created before v24, endIndex will be 0.
    if (end == 0 && n.selectedText.isNotEmpty) {
      final int foundIdx = text.indexOf(n.selectedText);
      if (foundIdx != -1) {
        start = foundIdx;
        end = foundIdx + n.selectedText.length;
      }
    }

    if (start >= 0 && end <= text.length && start < end) {
      // Create a temporary note with the resolved coordinates for rendering
      applicable.add(InlineNote(
        remarkId: n.remarkId,
        conceptId: n.conceptId,
        selectedText: n.selectedText,
        startIndex: start,
        endIndex: end,
        personalNote: n.personalNote,
        colorCode: n.colorCode,
        createdAt: n.createdAt,
      ));
    }
  }

  // 2. Sort strictly by Start Index (Left-to-Right rendering)
  applicable.sort((a, b) => a.startIndex.compareTo(b.startIndex));

  final List<TextSpan> out = <TextSpan>[];
  int currentIndex = 0;

  for (final InlineNote note in applicable) {
    // Prevent overlapping crashes (if a user somehow highlights over an existing highlight)
    if (currentIndex > note.startIndex) continue;

    // 3. Add plain text BEFORE the highlight
    if (note.startIndex > currentIndex) {
      out.addAll(_plainSegment(
        text.substring(currentIndex, note.startIndex),
        base,
        useAnchors: useAnchors,
        anchorStrength: anchorStrength,
      ));
    }

    // 4. Add the Highlight EXACTLY at the saved indices
    // Slicing the actual text guarantees a UI match even if selectedText had whitespace differences
    final String exactHighlightText = text.substring(note.startIndex, note.endIndex);
    out.add(_highlightedSpan(note, base, exactHighlightText, highlight: highlight, onTap: onTap));

    // 5. Advance the cursor past the highlight
    currentIndex = note.endIndex;
  }

  // 6. Add any remaining plain text AFTER the final highlight
  if (currentIndex < text.length) {
    out.addAll(_plainSegment(
      text.substring(currentIndex),
      base,
      useAnchors: useAnchors,
      anchorStrength: anchorStrength,
    ));
  }

  return out;
}

/// جزء مميَّز — خلفية تمييز ناعمة + مقبض نقر (عند توفر معالج).
TextSpan _highlightedSpan(
  InlineNote note,
  TextStyle base,
  String displayText, {
  required Color highlight,
  InlineNoteTapCallback? onTap,
}) {
  final TextStyle style = base.copyWith(
    backgroundColor: highlight,
  );
  if (onTap == null) {
    return TextSpan(text: displayText, style: style);
  }
  return TextSpan(
    text: displayText,
    style: style,
    recognizer: TapGestureRecognizer()..onTap = () => onTap(note),
  );
}


/// مقطع عادي (غير مميَّز) — يطبّق مراسي التثبيت عند الطلب.
List<TextSpan> _plainSegment(
  String segment,
  TextStyle base, {
  required bool useAnchors,
  required FixationStrength anchorStrength,
}) {
  if (!useAnchors) {
    return <TextSpan>[TextSpan(text: segment)];
  }
  return buildAnchoredSpans(segment, base, strength: anchorStrength);
}