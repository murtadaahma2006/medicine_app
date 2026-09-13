import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import 'motivation_model.dart';

/// ─────────────────────────────────────────────────────────────────────
/// أحداث طبقة التحفيز (المرحلة 6) — نموذج واحد لكل ما يظهر المستخدم.
/// ─────────────────────────────────────────────────────────────────────
sealed class CelebrationEvent {
  const CelebrationEvent();
}

/// رقاقة «+N ⚡» تطفو وتتلاشى عند أي كسب نقاط.
class XpGained extends CelebrationEvent {
  const XpGained(this.xp);

  /// عدد النقاط المكتسبة (يظهر في الرقاقة).
  final int xp;
}

/// شارة جديدة — بطاقة احتفالية منفردة لكل شارة.
class BadgeEarned extends CelebrationEvent {
  const BadgeEarned(this.badge);

  final BadgeDef badge;
}

/// رفع مستوى — شاشة كاملة بتعتيم وكونفيتي.
class LevelUp extends CelebrationEvent {
  const LevelUp({required this.level, required this.totalXp});

  final LearnerLevel level;

  /// مجموع النقاط بعد العبور (يعرض في شاشة الاحتفال).
  final int totalXp;
}

/// ─────────────────────────────────────────────────────────────────────
/// طابور أحداث التحفيز — يضمن ألا يظهر احتفالان فوق بعضهما أبداً.
///
/// لا حزمة حالة: أحداث المتحكمات (بلا BuildContext) تدفع هنا، والمضيف
/// [CelebrationHost] المركّب في جذر التطبيق يستهلكها بالترتيب.
/// ─────────────────────────────────────────────────────────────────────
class CelebrationQueue {
  CelebrationQueue._();

  static final CelebrationQueue instance = CelebrationQueue._();

  final Queue<CelebrationEvent> _events = Queue<CelebrationEvent>();
  final List<VoidCallback> _listeners = <VoidCallback>[];

  /// هل هناك حدث احتفالي جارٍ الآن؟ (يمنع كونفيتي شاشة النتيجة من
  /// التداخل مع احتفالات الطابور).
  bool busy = false;

  /// هل توجد أحداث كبيرة معلقة/جارية (شارة أو ترقية)؟ — شاشة النتيجة
  /// تؤجل كونفيتي التميز عندها كي لا يظهر احتفالان فوق بعضهما.
  bool get hasBigEventsPending =>
      busy || _events.any((CelebrationEvent e) => e is! XpGained);

  /// الأحداث المعلقة (للاختبار).
  int get pendingCount => _events.length;

  /// حدث معلّق عند فهرس دون استخراجه (قراءة فقط).
  CelebrationEvent peekAt(int index) => _events.elementAt(index);

  /// يحذف حدثاً معلقاً عند فهرس (رقاقة XP المستهلكة خفيفة).
  void removeAt(int index) {
    if (index < 0 || index >= _events.length) return;
    final List<CelebrationEvent> rest =
        _events.skip(index + 1).toList(growable: false);
    while (_events.length > index) {
      _events.removeLast();
    }
    _events.addAll(rest);
    _notify();
  }

  /// يدفع حدثاً — يُستدعى من المتحكمات بعد نجاح كتابات القاعدة.
  void add(CelebrationEvent event) {
    _events.addLast(event);
    _notify();
  }

  /// يدفع عدة أحداث معاً (شارات متعددة مثلاً).
  void addAll(Iterable<CelebrationEvent> events) {
    for (final CelebrationEvent e in events) {
      _events.addLast(e);
    }
    if (events.isNotEmpty) _notify();
  }

  /// يستخرج الحدث الكبير التالي (شارة/ترقية) — null إن فاض الطابور أو
  /// حدث جارٍ. أحداث XP الخفيفة تُتخطى (تُستهلك من المضيف مباشرة).
  CelebrationEvent? takeNext() {
    if (busy) return null;
    for (int i = 0; i < _events.length; i++) {
      final CelebrationEvent e = _events.elementAt(i);
      if (e is XpGained) continue; // خفيفة — ليست حدثاً كبيراً.
      // حذف e من موضعها (نمط Queue بلا removeAt).
      final List<CelebrationEvent> rest =
          _events.skip(i + 1).toList(growable: false);
      while (_events.length > i) {
        _events.removeLast();
      }
      _events.addAll(rest);
      busy = true;
      return e;
    }
    return null;
  }

  /// يعلن اكتمال الحدث الجاري — يسمح بالتالي.
  void complete() {
    busy = false;
    _notify();
  }

  /// يهدم كل الأحداث المعلقة (اختبارات).
  @visibleForTesting
  void resetForTest() {
    _events.clear();
    busy = false;
    _notify();
  }

  /// تسجيل/إلغاء مستمع — المضيف يسجل نفسه عند البناء.
  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    final List<VoidCallback> snapshot = List<VoidCallback>.of(_listeners);
    for (final VoidCallback l in snapshot) {
      l();
    }
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// كاشف رفع المستوى — يقارن المستوى قبل/بعد كسب نقاط.
///
/// نمط الاستخدام الموحد داخل نقاط الإنهاء في المتحكمات:
///   final int beforeXp = await Motivator.previewXp();
///   ... كتابات XP ...
///   await Motivator.detectLevelUp(beforeXp);
/// ─────────────────────────────────────────────────────────────────────
abstract final class Motivator {
  /// مجموع النقاط الحالي (قبل الكسب) — لقطة خفيفة SELECT SUM.
  static Future<int> currentXp() => DatabaseHelper.instance.sumXp();

  /// يقرأ النقاط الحالية ويقارنها بما قبل الكسب: إن عبر المستوى حدّة
  /// يدفع حدث [LevelUp] لطابور الاحتفالات. يعيد كذلك أي شارات جديدة
  /// تمريرها [newBadgeIds] كأحداث (تُستدعى بعد unlockEarnedBadges).
  static Future<void> detectLevelUp(
    int beforeXp, {
    List<String> newBadgeIds = const <String>[],
  }) async {
    final CelebrationQueue queue = CelebrationQueue.instance;

    // شارات جديدة — حدث لكل شارة (تُعرض منفردة).
    for (final String id in newBadgeIds) {
      final BadgeDef? def = _badgeById(id);
      if (def != null) queue.add(BadgeEarned(def));
    }

    // رفع المستوى — أعلى الأحداث قيمة فلا يُسبقه شارة في الظهور؟
    // القرار: الشارات أولاً (هي نتيجة الجلسة) ثم الترقية تتصدر النهاية.
    int afterXp;
    try {
      afterXp = await DatabaseHelper.instance.sumXp();
    } catch (_) {
      return; // قراءة القاعدة فشلت — الاحتفال غير حرج.
    }
    final LearnerLevel before = LearnerLevel.forXp(beforeXp);
    final LearnerLevel after = LearnerLevel.forXp(afterXp);
    if (after.index > before.index) {
      queue.add(LevelUp(level: after, totalXp: afterXp));
    }
  }

  static BadgeDef? _badgeById(String id) {
    for (final BadgeDef b in BadgeDef.all) {
      if (b.id == id) return b;
    }
    return null;
  }
}
