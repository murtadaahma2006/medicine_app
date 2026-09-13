import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../utils/app_haptics.dart';
import 'flow_channel_controller.dart';

/// ─────────────────────────────────────────────────────────────────────
/// محرّك المكافأة الطبقي — دوبامين التوقع، لا دوبامين المكافأة.
///
/// ثلاث آليات نفسية موثقة:
///
/// 1. **الضربة الحمراء ×2 (Variable Ratio 12%)** — الاكتظاظ المتغير
///    هو الوحيد الذي لا تنطفئ استجابته الدوبامينية (Reward Prediction
///    Error). مفاجأة نقية: لا تخزين، لا شراء، لا صفقات.
/// 2. **مضاعف التسارع (Goal Gradient — Kivetz 2006)** — البشر
///    يتسارعون تلقائياً كلما اقتربوا من الهدف: 1.0 → 1.25 (70%) →
///    1.5 (85%+). نهاية الجرعة أسرع نفسياً من بدايتها.
/// 3. **البداية المزيفة (Illusion of Head Start — Nunes & Drèze
///    2006)** — شريط الجرعة يبدأ من 15% لا من صفر: النفس البشري
///    يكره إكمال 0→100 ويحب إكمال 15→100.
///
/// اللمسيات عبر AppHaptics الموحد — لا استدعاء HapticFeedback من
/// الشاشات. الصوت مؤجّل اختيارياً (bلا كلمات، < 0.5s عند إضافته).
/// ─────────────────────────────────────────────────────────────────────
abstract final class RewardEngine {
  /// احتمال الضربة الحمراء لكل إجابة صحيحة — 12% (Variable Ratio).
  static const double luckyStrikeChance = 0.12;

  static final math.Random _rng = math.Random();

  // ── سلسلة الإجابة الصحيحة ──

  /// استدعاء موحد لحظة الاختيار (قبل عرض النتيجة — اللمسية تسبق
  /// الإدراك الواعي). يرجع true إذا كانت **ضربة حظ ×2**.
  ///
  /// التسلسل اللمسي (متدرج بالحدث):
  /// - خطأ: light (لا شيء آخر — الخطأ لا يُكافأ).
  /// - صحيح: light + (streak≥3 → medium).
  /// - ضربة حمراء: نمط مركب مميز heavy ثم pause ثم medium — بصمة
  ///   جسدية يتعلّمها الدماغ «حدث استثنائي».
  static bool onAnswer({required bool correct, required int streak}) {
    if (!correct) {
      AppHaptics.light();
      return false;
    }
    AppHaptics.light();
    if (streak >= 3) AppHaptics.celebrate();

    if (_rng.nextDouble() < luckyStrikeChance) {
      // الضربة الحمراء — نمط مركب مميز (غير متزامن حتى لا يُحاكى
      // بالخطأ مع medium العادية).
      HapticFeedback.heavyImpact();
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        HapticFeedback.mediumImpact();
      });
      return true; // → XP ×2 عند المنحة.
    }
    return false;
  }

  /// علامة ضربة الحظ لعرض الشارة الومضية في الواجهة — «⚡ ×2» تتلاشى.
  static String get luckyStrikeLabel => 'ضربة حظ ×2';

  // ── تدرج الهدف (Goal Gradient) ──

  /// مضاعف XP حسب موقعك في الجرعة [progress] (0..1):
  /// - أول 70%: ×1.0.
  /// - 70–85% (منطقة الاندفاع): ×1.25.
  /// - 85%+ (اللقطة الأخيرة تساوي أكثر): ×1.5.
  static double xpMultiplier(double progress) {
    if (progress >= 0.85) return 1.5;
    if (progress >= 0.70) return 1.25;
    return 1.0;
  }

  /// يحسب XP النهائي لإجابة: (الأساس × مضاعف الموضع) × 2 عند ضربة
  /// الحظ — مقرّباً لأسفل (عدد صحيح دائماً، لا كسور XP).
  static int grantXp({
    required int base,
    required int done,
    required int total,
    bool luckyStrike = false,
  }) {
    if (base <= 0 || total <= 0) return 0;
    final double progress = (done / total).clamp(0.0, 1.0);
    final double multiplier = xpMultiplier(progress);
    final int xp = (base * multiplier).floor();
    return luckyStrike ? xp * 2 : xp;
  }

  // ── البداية المزيفة (Head Start) ──

  /// شريط تقدم الجرعة يبدأ من 15% ممتلئاً — «البطاقة الأولى على
  /// حساب البيت». [rawProgress] (0..1) → القيمة المعروضة (0.15..1).
  static const double headStart = 0.15;

  static double displayProgress(double rawProgress) {
    if (rawProgress <= 0) return 0;
    return headStart + rawProgress * (1 - headStart);
  }

  // ── منطقة الاندفاع ──

  /// هل دخل المستخدم منطقة الاندفاع (70%)؟ — نقطة إشارة فسيولوجية
  /// واحدة فقط (وميض حدّي + نبضة لمسية) ثم لا تتكرر.
  static bool enteredSprintZone(double progress, int previousDone) =>
      progress >= 0.70 && previousDone > 0
          ? (previousDone - 1) / previousDone < 0.70
          : progress >= 0.70 && previousDone == 0;

  /// نبضة منطقة الاندفاع — light واحدة خاطفة.
  static void onSprintZone() => AppHaptics.selection();

  // ── الصعوبة التكيفية (قناة 85% — تفضيل الترتيب) ──

  /// ترجيح ORDER BY حسب إشارة القناة — يُدمج في استعلام MCQ:
  /// - harder → الأسئلة advanced أولاً (CORE بعد ذلك).
  /// - easier → core أولاً.
  /// - stay → ترتيب طبيعي (لا ترجيح).
  ///
  /// بلا أي هجرة: يعمل على عمود difficulty الموجود منذ v14.
  static String difficultyOrderWeight(FlowSignal signal) {
    switch (signal) {
      case FlowSignal.harder:
        return "CASE WHEN difficulty = 'advanced' THEN 0 ELSE 1 END, ";
      case FlowSignal.easier:
        return "CASE WHEN difficulty = 'core' THEN 0 ELSE 1 END, ";
      case FlowSignal.stay:
        return '';
    }
  }
}
