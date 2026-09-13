import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/answer_checker.dart';
import 'package:medicine_app/src/core/database/correction.dart';

void main() {
  group('AnswerChecker (نواة عامة)', () {
    test('مطابقة تامة = صحيح', () {
      final AnswerCheckResult r = AnswerChecker.check(
        userAnswer: 'Torsades de Pointes',
        correctAnswer: 'Torsades de Pointes',
      );
      expect(r.isCorrect, isTrue);
      expect(r.mistakeType, MistakeType.exact);
    });

    test('المسافات وحالة الأحرف وعلامات النهاية لا تكسر المطابقة', () {
      final AnswerCheckResult r = AnswerChecker.check(
        userAnswer: '  torsades de pointes. ',
        correctAnswer: 'Torsades de Pointes',
      );
      expect(r.isCorrect, isTrue);
    });

    test('البدائل المفصولة بشرطة مائلة كلها مقبولة', () {
      for (final String alt in <String>['HFpEF', 'Diastolic HF']) {
        final AnswerCheckResult r = AnswerChecker.check(
          userAnswer: alt,
          correctAnswer: 'HFpEF / Diastolic HF',
        );
        expect(r.isCorrect, isTrue, reason: 'البديل «$alt» يجب أن يُقبل');
      }
    });

    test('اختلاف بسيط في المسافات الداخلية = spelling لا wrong', () {
      final AnswerCheckResult r = AnswerChecker.check(
        userAnswer: 'torsadesdepointes',
        correctAnswer: 'Torsades de Pointes',
      );
      expect(r.isCorrect, isFalse);
      expect(r.mistakeType, MistakeType.spelling);
    });

    test('إجابة مختلفة تماماً = wrong', () {
      final AnswerCheckResult r = AnswerChecker.check(
        userAnswer: 'Atrial fibrillation',
        correctAnswer: 'Torsades de Pointes',
      );
      expect(r.isCorrect, isFalse);
      expect(r.mistakeType, MistakeType.wrong);
    });
  });

  group('Correction.toMap / fromMap (round-trip)', () {
    test('الخريطة تعود ككائن مكافئ', () {
      final Correction original = Correction(
        drillId: 'mcq-cardio-001',
        questionId: 'cardio-001-q1',
        userAnswer: 'HFrEF',
        correctAnswer: 'HFpEF',
        isCorrect: false,
        mistakeType: MistakeType.wrong,
        attemptedAt: '2026-09-11T10:00:00.000Z',
      );

      final Correction restored = Correction.fromMap(original.toMap());

      expect(restored.drillId, original.drillId);
      expect(restored.questionId, original.questionId);
      expect(restored.isCorrect, original.isCorrect);
      expect(restored.mistakeType, original.mistakeType);
    });
  });
}
