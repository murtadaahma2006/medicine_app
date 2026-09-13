import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/database/srs_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  /// فتح قاعدة في الذاكرة + إدراج وحدة وبطاقتين (هيكل فقط).
  Future<void> openWithCards() async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.openWith(databaseFactoryFfi, inMemoryDatabasePath);

    await helper.insertUnit(<String, Object?>{
      'id': 'cardio-001',
      'module': 'cardiology',
      'system': 'cardiovascular',
      'title': 'Heart Failure',
      'order_index': 1,
    });
    await helper.insertFlashcard(<String, Object?>{
      'id': 'cardio-001-f1',
      'unit_id': 'cardio-001',
      'card_type': 'basic',
      'front_text': 'What defines HFpEF?',
      'back_text': 'EF >= 50% with filling impairment and congestion signs.',
    });
    await helper.insertFlashcard(<String, Object?>{
      'id': 'cardio-001-f2',
      'unit_id': 'cardio-001',
      'card_type': 'basic',
      'front_text': 'What does NYHA class IV mean?',
      'back_text': 'Symptoms at rest.',
    });
  }

  group('Leitner algorithm (pure)', () {
    test('correct answer promotes a box up to 5 max', () {
      expect(SrsRepository.nextBoxAfter(1, true), 2);
      expect(SrsRepository.nextBoxAfter(2, true), 3);
      expect(SrsRepository.nextBoxAfter(4, true), 5);
      expect(SrsRepository.nextBoxAfter(5, true), 5, reason: 'no box above 5');
    });

    test('wrong answer always demotes to box 1', () {
      expect(SrsRepository.nextBoxAfter(5, false), 1);
      expect(SrsRepository.nextBoxAfter(3, false), 1);
    });
  });

  group('SRS on a real database', () {
    test('first correct answer creates the card in box 2', () async {
      await openWithCards();

      expect(await SrsRepository.totalCards(), 0);
      await SrsRepository.recordAnswer('cardio-001-f1', true);

      expect(await SrsRepository.totalCards(), 1);
      final Map<int, int> dist = await SrsRepository.boxDistribution();
      expect(dist[2], 1, reason: 'first correct = box 2');
    });

    test('wrong answer creates the card in box 1, due tomorrow',
        () async {
      await openWithCards();

      await SrsRepository.recordAnswer('cardio-001-f1', false);

      final Map<int, int> dist = await SrsRepository.boxDistribution();
      expect(dist[1], 1);

      // next_due is one day away — nothing due today.
      expect(await SrsRepository.dueTodayCount(), 0);
    });

    test('promotion and demotion across an answer chain', () async {
      await openWithCards();

      // correct x3: box 2 -> 3 -> 4.
      await SrsRepository.recordAnswer('cardio-001-f1', true);
      await SrsRepository.recordAnswer('cardio-001-f1', true);
      await SrsRepository.recordAnswer('cardio-001-f1', true);
      Map<int, int> dist = await SrsRepository.boxDistribution();
      expect(dist[4], 1);

      // wrong: demote to box 1.
      await SrsRepository.recordAnswer('cardio-001-f1', false);
      dist = await SrsRepository.boxDistribution();
      expect(dist[1], 1);
      expect(dist.containsKey(4), isFalse);
    });

    test('dueToday fetches only due cards', () async {
      await openWithCards();

      // f1 answered wrong: due tomorrow (box 1, one-day interval).
      await SrsRepository.recordAnswer('cardio-001-f1', false);
      expect(await SrsRepository.dueTodayCount(), 0);

      // Manually insert an SRS card for f2 that is overdue now
      // (simulating an old card) — f2 has no row yet so the insert
      // does not collide with the composite primary key.
      final db = await DatabaseHelper.instance.database;
      await db.insert(DatabaseHelper.tableSrsCards, <String, Object?>{
        'flashcard_id': 'cardio-001-f2',
        'box': 3,
        'streak_ok': 2,
        'streak_bad': 0,
        'last_review': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 5))
            .toIso8601String(),
        'next_due': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'card_type': 'basic',
      });

      expect(await SrsRepository.dueTodayCount(), 1);
      final List<SrsCard> due = await SrsRepository.dueToday();
      expect(due.length, 1);
      expect(due.first.cardId, 'cardio-001-f2');
      expect(due.first.frontText, 'What does NYHA class IV mean?');
    });
  });
}
