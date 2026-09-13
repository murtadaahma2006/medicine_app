/// تنظيف نصوص المحتوى التعليمي من بقايا Markdown الخام.
///
/// شروح القواعد نُسخت حرفياً من وثائق markdown، فتسربت إليها رؤوس
/// (مثل `**explanation_ar:**`) وبقايا فواصل جداول (مثل `|---|---|`).
/// القاعدة الذهبية: لا نعدّل البذور (قواعد المستخدمين المزروعة تحمل
/// النسخ القديمة أصلاً) — ننظف عند العرض فقط، في مكان واحد.
abstract final class MarkdownCleaner {
  /// ينظف نص شرح واحد من بقايا Markdown.
  static String clean(String raw) {
    String text = raw;

    // رؤوس حقول تسربت من استخراج الوثائق: **explanation_ar:** أو أي
    // رأس **xxx:** في البداية — نزيله إن كان مفتاح استخراج لا نصاً تعليمياً.
    text = text.replaceFirst(
      RegExp(r'^\s*\*\*\s*\w+\s*:\s*\*\*\s*'),
      '',
    );

    // بقايا فواصل جداول markdown: |---|---| (مع مسافات حولها).
    text = text.replaceAll(RegExp(r'\s*\|?-{2,}\|+'), ' ');

    // أسطر جدول متبقية منفردة: | ich | habe |
    text = text.replaceAll(
      RegExp(r'\s\|\s*(?:-{2,}\s*)?\|'),
      ' ',
    );

    // نجوم الت Bold المتناثرة.
    text = text.replaceAll('**', '');

    // تقليم ناتج نهایی: مسافات مزدوجة + أطراف.
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    return text;
  }
}
