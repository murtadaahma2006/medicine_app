import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// [CountUp] — عدّاد تصاعدي موحّد: من 0 إلى value خلال 900ms بأرقام
/// جدولية (tabular figures لا تتقفز عرضاً).
///
/// **الدرس المؤدّي إليه**: النسخ القديمة مرّرت `int` لـ
/// TweenAnimationBuilder — و`int` لا يدعم `lerp` في Flutter (فقط
/// double عبر lerpDouble)، فيرمي «Cannot lerp between "0" and "N"»
/// كل frame ويعرض شاشة حمراء لحظية. الحل: الحركة على `double`
/// (lerp سليم) والعرض مقرّب لأسفل `v.floor()`.
///
/// تجاوب الحركة: `disableAnimations` على الجهاز → القيمة فوراً بلا
/// حركة (نفس سلوك النسخ القديمة).
/// ─────────────────────────────────────────────────────────────────────
class CountUp extends StatelessWidget {
  const CountUp({
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 900),
    super.key,
  });

  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;

  /// مدة التصاعد (قابلة للتخصيص).
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text('$prefix$value$suffix',
          textDirection: TextDirection.ltr, style: style);
    }
    // lerp على double (سليم) — العرض مقرّب لأسفل.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppMotion.ease,
      builder: (BuildContext context, double v, Widget? _) => Text(
        '$prefix${v.floor()}$suffix',
        textDirection: TextDirection.ltr,
        style: style,
      ),
    );
  }
}
