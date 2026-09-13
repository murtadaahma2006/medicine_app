import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/motivation/flow_channel_controller.dart';
import 'package:medicine_app/src/core/motivation/reward_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  group('FlowChannelController — قناة الـ 85%', () {
    test('نافذة فارغة وقصيرة: accuracy = null وsignal = stay', () {
      final FlowChannelController c = FlowChannelController();
      expect(c.accuracy, isNull);
      expect(c.signal, FlowSignal.stay);
      expect(c.samples, 0);

      c.record(true);
      c.record(true);
      c.record(true);
      c.record(true);
      // 4 إجابات < الحد الأدنى 5 — لا ضبط مبكر على ضوضاء قليلة.
      expect(c.accuracy, isNull);
      expect(c.signal, FlowSignal.stay);
    });

    test('5/5 صحيحة (> 87%) → إشارة harder', () {
      final FlowChannelController c = FlowChannelController();
      for (int i = 0; i < 5; i++) {
        c.record(true);
      }
      expect(c.accuracy, 1.0);
      expect(c.signal, FlowSignal.harder);
    });

    test('دقة 80% (12/15) → داخل القناة (stay)', () {
      final FlowChannelController c = FlowChannelController();
      for (int i = 0; i < 12; i++) {
        c.record(true);
      }
      for (int i = 0; i < 3; i++) {
        c.record(false);
      }
      expect(c.accuracy, 0.8);
      expect(c.signal, FlowSignal.stay);
      expect(c.inChannel, isTrue);
    });

    test('دقة 60% (< 70%) → إشارة easier', () {
      final FlowChannelController c = FlowChannelController();
      for (int i = 0; i < 3; i++) {
        c.record(true);
      }
      for (int i = 0; i < 2; i++) {
        c.record(false);
      }
      expect(c.accuracy, 0.6);
      expect(c.signal, FlowSignal.easier);
    });

    test('النافذة المتحركة: الإجابات القديمة تتساقط عند 15', () {
      final FlowChannelController c = FlowChannelController();
      // 15 خطأ ثم 15 صواب — النافذة تعرض آخر 15 فقط = 100%.
      for (int i = 0; i < 15; i++) {
        c.record(false);
      }
      expect(c.accuracy, 0.0);
      for (int i = 0; i < 15; i++) {
        c.record(true);
      }
      expect(c.samples, 15);
      expect(c.accuracy, 1.0);
      expect(c.signal, FlowSignal.harder);
    });

    test('reset يفرغ النافذة', () {
      final FlowChannelController c = FlowChannelController();
      for (int i = 0; i < 10; i++) {
        c.record(true);
      }
      c.reset();
      expect(c.samples, 0);
      expect(c.accuracy, isNull);
    });

    test('حدود قابلة للتخصيص (قناة أضيق للاختبار)', () {
      final FlowChannelController c = FlowChannelController(
        windowSize: 6,
        boredomCeiling: 0.95,
        frustrationFloor: 0.5,
      );
      // 4/5 = 80% — داخل القناة المخصصة (0.5..0.95).
      for (int i = 0; i < 4; i++) {
        c.record(true);
      }
      c.record(false);
      expect(c.signal, FlowSignal.stay);
    });
  });

  group('RewardEngine — تدرج الهدف (Goal Gradient)', () {
    test('مضاعف XP حسب الموضع في الجرعة', () {
      // أول 70%: ×1.0.
      expect(RewardEngine.xpMultiplier(0.0), 1.0);
      expect(RewardEngine.xpMultiplier(0.5), 1.0);
      expect(RewardEngine.xpMultiplier(0.69), 1.0);
      // 70–85%: ×1.25.
      expect(RewardEngine.xpMultiplier(0.70), 1.25);
      expect(RewardEngine.xpMultiplier(0.80), 1.25);
      // 85%+: ×1.5.
      expect(RewardEngine.xpMultiplier(0.85), 1.5);
      expect(RewardEngine.xpMultiplier(1.0), 1.5);
    });

    test('grantXp: الأساس × المضاعف — مقرّب لأسفل', () {
      // أول الجرعة: 5 × 1.0 = 5.
      expect(
        RewardEngine.grantXp(base: 5, done: 1, total: 10),
        5,
      );
      // 70%: 5 × 1.25 = 6.25 → 6.
      expect(
        RewardEngine.grantXp(base: 5, done: 7, total: 10),
        6,
      );
      // 85%: 5 × 1.5 = 7.5 → 7.
      expect(
        RewardEngine.grantXp(base: 5, done: 9, total: 10),
        7,
      );
    });

    test('grantXp: الضربة الحمراء تضاعف الناتج النهائي', () {
      final int normal = RewardEngine.grantXp(
        base: 5,
        done: 9,
        total: 10,
      ); // 7
      final int lucky = RewardEngine.grantXp(
        base: 5,
        done: 9,
        total: 10,
        luckyStrike: true,
      );
      expect(lucky, normal * 2);
      expect(lucky, 14);
    });

    test('grantXp: حواف آمنة (صفر/سالب)', () {
      expect(RewardEngine.grantXp(base: 0, done: 1, total: 10), 0);
      expect(RewardEngine.grantXp(base: -3, done: 1, total: 10), 0);
      expect(RewardEngine.grantXp(base: 5, done: 1, total: 0), 0);
    });
  });

  group('RewardEngine — البداية المزيفة (Head Start)', () {
    test('شريط الجرعة يبدأ من 15% لا من صفر', () {
      // Nunes & Drèze: نفس المكافأة، بداية أسهل = إكمال أسرع.
      expect(RewardEngine.headStart, 0.15);
      expect(RewardEngine.displayProgress(0), 0);
      // منتصف الجرعة الخام يظهر ~57.5%.
      expect(
        RewardEngine.displayProgress(0.5),
        closeTo(0.15 + 0.5 * 0.85, 0.0001),
      );
      // النهاية = 1 دائماً.
      expect(RewardEngine.displayProgress(1.0), 1.0);
      // لا تجاوز للواحد أبداً.
      expect(RewardEngine.displayProgress(0.999), lessThanOrEqualTo(1.0));
    });
  });

  group('RewardEngine — ترجيح صعوبة قناة التدفق', () {
    test('harder = advanced أولاً · easier = core أولاً · stay = بلا ترجيح',
        () {
      expect(
        RewardEngine.difficultyOrderWeight(FlowSignal.harder),
        contains('advanced'),
      );
      expect(
        RewardEngine.difficultyOrderWeight(FlowSignal.easier),
        contains("'core'"),
      );
      expect(
        RewardEngine.difficultyOrderWeight(FlowSignal.stay),
        '',
      );
    });
  });

  group('getMcqsForUnitAdaptive — الصعوبة التكيفية (بلا هجرة)', () {
    test('إشارة harder تقدم advanced · easier تقدم core', () async {
      final DatabaseHelper helper = DatabaseHelper.instance;
      await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

      await helper.insertUnit(<String, Object?>{
        'id': 'u1',
        'module': 'cardiology',
        'system': 'cardiovascular',
        'title': 'HF',
        'order_index': 0,
      });
      await helper.insertMcq(<String, Object?>{
        'id': 'q_core',
        'unit_id': 'u1',
        'question_stem': 'Core question stem long enough for rules?',
        'options_json': '["a","b","c"]',
        'correct_index': 0,
        'explanation_ar': 'شرح عربي طويل بما يكفي لاجتياز التحقق.',
        'difficulty': 'core',
        'clinical_vignette': 0,
      });
      await helper.insertMcq(<String, Object?>{
        'id': 'q_adv',
        'unit_id': 'u1',
        'question_stem': 'Advanced question stem long enough for rules?',
        'options_json': '["a","b","c"]',
        'correct_index': 0,
        'explanation_ar': 'شرح عربي طويل بما يكفي لاجتياز التحقق.',
        'difficulty': 'advanced',
        'clinical_vignette': 0,
      });

      // harder → advanced أولاً.
      final List<Map<String, Object?>> harder =
          await helper.getMcqsForUnitAdaptive(
        'u1',
        RewardEngine.difficultyOrderWeight(FlowSignal.harder),
      );
      expect(harder.first['id'], 'q_adv');

      // easier → core أولاً.
      final List<Map<String, Object?>> easier =
          await helper.getMcqsForUnitAdaptive(
        'u1',
        RewardEngine.difficultyOrderWeight(FlowSignal.easier),
      );
      expect(easier.first['id'], 'q_core');

      // stay → الترتيب الطبيعي (id).
      final List<Map<String, Object?>> stay =
          await helper.getMcqsForUnitAdaptive(
        'u1',
        RewardEngine.difficultyOrderWeight(FlowSignal.stay),
      );
      expect(stay.first['id'], 'q_adv'); // id تصاعدي.
    });
  });
}
