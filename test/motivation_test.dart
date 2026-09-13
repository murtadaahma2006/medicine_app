import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/motivation_repository.dart';
import 'package:medicine_app/src/core/motivation/motivation_model.dart';

void main() {
  group('حساب السلاسل (دوال نقية)', () {
    test('قائمة فارغة = صفر', () {
      expect(MotivationRepository.longestRun(<String>[]), 0);
      expect(
        MotivationRepository.streakEndingAt(
            <String>[], <String>['2026-09-11']),
        0,
      );
    });

    test('أطول تتابع متصل يُكتشف', () {
      final List<String> days = <String>[
        '2026-09-01',
        '2026-09-02',
        '2026-09-03',
        '2026-09-06', // فجوة
        '2026-09-07',
      ];
      expect(MotivationRepository.longestRun(days), 3);
    });

    test('السلسلة الحية تنتهي عند اليوم أو الأمس', () {
      final List<String> allowedEnds = <String>['2026-09-11', '2026-09-10'];
      final List<String> days = <String>[
        '2026-09-09',
        '2026-09-10',
        '2026-09-11',
      ];
      expect(
        MotivationRepository.streakEndingAt(days, allowedEnds),
        3,
      );
    });

    test('سلسلة انتهت قديماً = 0 عند فحصها اليوم', () {
      final List<String> allowedEnds = <String>['2026-09-11', '2026-09-10'];
      final List<String> days = <String>[
        '2026-09-01',
        '2026-09-02',
      ];
      expect(
        MotivationRepository.streakEndingAt(days, allowedEnds),
        0,
      );
    });
  });

  group('LearnerLevel من XP', () {
    test('حدود المستويات', () {
      expect(LearnerLevel.forXp(0), LearnerLevel.beginner);
      expect(LearnerLevel.forXp(99), LearnerLevel.beginner);
      expect(LearnerLevel.forXp(100), LearnerLevel.explorer);
      expect(LearnerLevel.forXp(1500), LearnerLevel.advanced);
    });

    test('التقدم نحو المستوى التالي', () {
      expect(LearnerLevel.beginner.progressToNext(0), 0.0);
      expect(LearnerLevel.beginner.progressToNext(100), 1.0);
      // المستوى الأقصى: تقدم كامل دائماً.
      expect(LearnerLevel.advanced.progressToNext(9999), 1.0);
    });
  });
}
