import 'correction.dart';

/// نتيجة تصحيح إجابة واحدة.
class AnswerCheckResult {
  const AnswerCheckResult({
    required this.isCorrect,
    required this.mistakeType,
    this.normalizedUserAnswer,
    this.normalizedCorrectAnswer,
  });

  final bool isCorrect;
  final MistakeType mistakeType;

  /// الصيغ المنقحة بعد تنظيف المسافات — للتسجيل في السجل.
  final String? normalizedUserAnswer;
  final String? normalizedCorrectAnswer;
}

/// المصحح التلقائي للإجابات الكتابية القصيرة — عام لأي مجال محتوى.
///
/// - يتجاهل حالة الأحرف والمسافات وعلامات الترقيم الختامية.
/// - يقبل البدائل المصرح بها مفصولة بـ "/" أو "،" أو "," أو ";".
///   مثال: "تسرع القلب / Tachycardia" تقبل كليهما.
/// - لا تخصيص لغوي: المصطلح الطبي العربي أو اللاتيني يعامل معاملة
///   موحدة (طي المسافات فقط، بلا قواعد إملائية لغة معينة).
abstract final class AnswerChecker {
  /// يصحح [userAnswer] مقابل [correctAnswer] وقد يحتوي الأخيرة بدائل.
  static AnswerCheckResult check({
    required String userAnswer,
    required String correctAnswer,
  }) {
    final String user = normalize(userAnswer);
    final String expectedRaw = normalize(correctAnswer);

    // 0) مطابقة تامة للنص المرجعي كاملاً.
    if (user == expectedRaw) {
      return AnswerCheckResult(
        isCorrect: true,
        mistakeType: MistakeType.exact,
        normalizedUserAnswer: user,
        normalizedCorrectAnswer: expectedRaw,
      );
    }

    // قائمة البدائل المقبولة من صيغة الإجابة المرجعية.
    final List<String> accepted = expectedRaw
        .split(RegExp(r'\s*/\s*|\s*[،,;]\s*'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();

    if (accepted.isEmpty) accepted.add(expectedRaw);

    // 1) تطابق تام مع أي بديل.
    if (accepted.contains(user)) {
      return AnswerCheckResult(
        isCorrect: true,
        mistakeType: MistakeType.exact,
        normalizedUserAnswer: user,
        normalizedCorrectAnswer: expectedRaw,
      );
    }

    // 2) تسامح إملائي خفيف: طي المسافات الداخلية والمقاطع الوصلية
    //    (مصطلحات مثل "ارتفاع ضغط" مقابل "ارتفاع الضغط").
    final bool tolerantMatch = accepted.any(
      (String a) => _foldSpacing(a) == _foldSpacing(user),
    );
    if (tolerantMatch) {
      return AnswerCheckResult(
        isCorrect: false,
        mistakeType: MistakeType.spelling,
        normalizedUserAnswer: user,
        normalizedCorrectAnswer: expectedRaw,
      );
    }

    // 3) إجابة خاطئة تماماً.
    return AnswerCheckResult(
      isCorrect: false,
      mistakeType: MistakeType.wrong,
      normalizedUserAnswer: user,
      normalizedCorrectAnswer: expectedRaw,
    );
  }

  /// التنقيح: trim + طي المسافات + إزالة علامات النهاية + حالة دنيا.
  static String normalize(String input) {
    final String trimmed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed
        .replaceFirst(RegExp(r'[.!?،,؛;:]+$'), '')
        .toLowerCase();
  }

  /// طي تقريبي إضافي: إزالة كل المسافات و«ال» التعريف لمقارنة تقريبية.
  static String _foldSpacing(String input) =>
      input.replaceAll(' ', '').replaceAll('ال', '');
}
