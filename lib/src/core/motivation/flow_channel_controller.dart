import 'dart:collection';

/// ─────────────────────────────────────────────────────────────────────
/// محرّك قناة التدفق — قاعدة الـ 85% (Wilson et al., 2019, Nature Comms).
///
/// سرعة التعلم تتعاظم عندما تكون دقة الأداء ~85% (خطأ ~15%):
/// - دقة > 87% فوق نافذة كاملة → الملل → إشارة رفع الصعوبة.
/// - دقة < 70% → الإحباط → إشارة خفض الصعوبة + جسر التلميح.
/// - بينهما = داخل القناة — لا تلمس شيئاً.
///
/// نافذة متحركة آخر 15 إجابة في الذاكرة (Queue) — **صفر هجرة قاعدة**.
/// null من [signal] حتى اكتمال 5 إجابات: لا ضبط مبكر على ضوضاء قليلة.
///
/// نقي تماماً (بلا Dart:io/Flutter) — قابل للاختبار المباشر.
/// ─────────────────────────────────────────────────────────────────────
enum FlowSignal { harder, easier, stay }

class FlowChannelController {
  FlowChannelController({
    int windowSize = defaultWindowSize,
    double boredomCeiling = defaultBoredomCeiling,
    double frustrationFloor = defaultFrustrationFloor,
  })  : assert(windowSize >= 2),
        _windowSize = windowSize,
        _boredomCeiling = boredomCeiling,
        _frustrationFloor = frustrationFloor;

  static const int defaultWindowSize = 15;
  static const double defaultBoredomCeiling = 0.87;
  static const double defaultFrustrationFloor = 0.70;

  /// الحد الأدنى من الإجابات قبل أي ضبط (5 = بلا قرارات على ضوضاء).
  static const int minSamples = 5;

  final int _windowSize;
  final double _boredomCeiling;
  final double _frustrationFloor;
  final Queue<bool> _window = Queue<bool>();

  /// سجل إجابة واحدة في النافذة المتحركة.
  void record(bool correct) {
    _window.addLast(correct);
    if (_window.length > _windowSize) _window.removeFirst();
  }

  /// دقة النافذة الحالية — null قبل اكتمال [minSamples].
  double? get accuracy {
    if (_window.length < minSamples) return null;
    int correct = 0;
    for (final bool c in _window) {
      if (c) correct++;
    }
    return correct / _window.length;
  }

  /// عدد الإجابات المسجلة حتى الآن.
  int get samples => _window.length;

  /// إشارة الضبط الحالية — [FlowSignal.stay] داخل القناة أو قبل اكتمال
  /// العينات (لا ضبط مبكر).
  FlowSignal get signal {
    final double? a = accuracy;
    if (a == null) return FlowSignal.stay;
    if (a > _boredomCeiling) return FlowSignal.harder;
    if (a < _frustrationFloor) return FlowSignal.easier;
    return FlowSignal.stay;
  }

  /// هل المستخدم داخل القناة الآن؟ (للعرض الاختياري/التشخيص).
  bool get inChannel => signal == FlowSignal.stay && accuracy != null;

  /// تفريغ النافذة — عند بدء جلسة جديدة كلياً (نوع مختلف من النشاط).
  void reset() => _window.clear();
}
