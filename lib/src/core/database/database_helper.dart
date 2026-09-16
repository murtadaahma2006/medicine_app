import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../motivation/motivation_model.dart';
import 'correction.dart';
import 'motivation_repository.dart';
import 'user_progress.dart';
import 'xp_event.dart';

/// المستودع المركزي لقاعدة البيانات المحلية (SQLite) — MedOS.
///
/// - ملف واحد: medical_app.db
/// - جداول المحتوى: units · concepts · flashcards · mcq_bank
///   · clinical_cases · clinical_case_steps
/// - جداول المستخدم: user_progress · corrections · xp_events · srs_cards
///   · unlocked_badges
/// - جميع الاستعلامات parameterized (حماية من SQL Injection).
/// - الترقيم الإصداري عبر [databaseVersion] و onUpgrade.
class DatabaseHelper {
  DatabaseHelper._internal();

  /// النسخة الموحدة (Singleton) — اتصال واحد لكل التطبيق.
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String databaseName = 'medical_app.db';

  /// v14: إعادة هيكلة طبية كاملة — مخطط جديد بعد تجريد نسخة تعلم الألمانية.
  /// v15: محرّك القراءة العميقة — concept_reads · flow_sessions ·
  ///   confidence_log (جداول جديدة فقط، لا لمس لأي جدول قائم).
  /// v16: عقد v2.1 + البوابة — أعمدة اختيارية فقط:
  ///   mcq_bank.hints_json/focus_sections_json ·
  ///   clinical_case_steps.hints_json · flashcards.is_vivid ·
  ///   concept_reads.gate_passed.
  /// v17: أهداف اليوم — units.is_pinned_today (تثبيت محاضرة لجدول
  ///   اليوم الذي يبنيه المستخدم بنفسه).
  /// v18: تثبيت ذكي ذاتي التنظيف — units.pinned_at (طابع زمني ISO
  ///   UTC لحظة التثبيت، null = غير مثبتة) بديلاً عن البولياني:
  ///   إلغاء تلقائي للمكتملة فوراً وللمهملة بعد 48 ساعة + إشعار
  ///   انتهاء مجدول (PinExpiryService). العمود القديم لا يُحذف
  ///   (ALTER TABLE DROP ممنوع هنا: عمود داخل CHECK وجدول عليه
  ///   مفاتيح أجنبية) — يتوقف استخدامه نهائياً.
  /// v19: لؤلؤة اليوم — units.golden_tip (نص اختياري): أهم معلومة/
  ///   فخ امتحاني بالمحاضرة (عقد JSON v2.2) — يعرضه الويدجت عشوائياً.
  /// v20: التوسع متعدد التخصصات — units.specialty (نص): التخصص
  ///   الافتراضية 'internal_medicine' تعبّئ كل المحاضرات القائمة
  ///   لحظة الترقية (سلوك ADD COLUMN مع NOT NULL DEFAULT) فلا يضيع
  ///   محتوى الباطنية ولا يتعطل استعلام.
  /// v24: إضافة start_index و end_index إلى الملاحظات المضمنة.
  static const int databaseVersion = 24;

  // ── جداول المحتوى الطبي ──
  static const String tableUnits = 'units';
  static const String tableConcepts = 'concepts';
  static const String tableFlashcards = 'flashcards';
  static const String tableMcqBank = 'mcq_bank';
  static const String tableClinicalCases = 'clinical_cases';
  static const String tableClinicalCaseSteps = 'clinical_case_steps';

  // ── التخصصات السريرية (v20) ──

  /// القيمة الافتراضية للمحاضرات القائمة — الباطنية تاريخ المنصة
  /// كله، فترحيل v20 يسندها إليها تلقائياً.
  static const String defaultSpecialty = 'internal_medicine';

  /// التخصصات المسموح بها في عقد البيانات (كود التأليف JSON).
  static const List<String> specialties = <String>[
    'internal_medicine',
    'surgery',
    'obgyn',
  ];

  // ── جداول المستخدم والتقدم ──
  static const String tableUserProgress = 'user_progress';
  static const String tableCorrections = 'corrections';
  static const String tableXpEvents = 'xp_events';
  static const String tableUnlockedBadges = 'unlocked_badges';
  static const String tableSrsCards = 'srs_cards';

  // ── v15: جداول محرّك القراءة العميقة ──
  static const String tableConceptReads = 'concept_reads';
  static const String tableFlowSessions = 'flow_sessions';
  static const String tableConfidenceLog = 'confidence_log';

  // ── v21: إحصاءات يومية لزمن الدراسة (إجمالي وقت استخدام التطبيق) ──
  static const String tableDailyStats = 'daily_stats';

  // ── v22: ملاحظات داخلية مضمّنة في نص الشروحات (Inline Highlight) ──
  static const String tableInlineNotes = 'inline_notes';

  // ── v23: سجلات المرضى لنموذج أخذ القصة السريرية ──
  static const String tablePatientRecords = 'patient_records';

  /// أنواع أحداث XP المسموحة في قيد CHECK — مصدر الحقيقة الوحيد.
  static const List<String> xpEventKinds = <String>[
    'concept',
    'flashcard',
    'mcq',
    'case_step',
    'streak',
    'assessment',
    'drill',
    'review',
  ];

  static String get xpKindsCheckSql =>
      "kind IN (${xpEventKinds.map((String k) => "'$k'").join(', ')})";

  Database? _db;

  /// يفتح الاتصال عند أول استخدام ثم يعيد نفس الاتصال دائماً.
  /// لا زرع هنا — المحتوى الطبي يُحقن من ملفات JSON عبر سكربت خارجي.
  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  /// يفتح القاعدة ويضمن جاهزيتها (يُستدعى من مسارات الإنتاج).
  Future<Database> openAndSeed() async => database;

  /// نقطة حقن للاختبارات (sqflite_common_ffi) دون لمس كود الإنتاج.
  @visibleForTesting
  Future<Database> openWith(DatabaseFactory factory, String dbPath) async {
    await close();
    final Database opened = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final String dirPath = await getDatabasesPath();
    final String path = p.join(dirPath, databaseName);
    return openDatabase(
      path,
      version: databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// ضروري جداً: في sqflite قيود المفاتيح الأجنبية معطّلة افتراضياً على
  /// مستوى SQLite — بدون هذا السطر يعمل ON DELETE CASCADE صامتاً بلا أثر.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // ─────────────────────────────── المخطط ───────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    final Batch batch = db.batch();

    // ── الوحدات (المحاضرات الطبية) ──
    batch.execute('''
      CREATE TABLE $tableUnits (
        id              TEXT PRIMARY KEY,
        specialty       TEXT NOT NULL DEFAULT 'internal_medicine'
                        CHECK (specialty IN ('internal_medicine','surgery','obgyn')),
        module          TEXT NOT NULL,
        system          TEXT NOT NULL,
        title           TEXT NOT NULL,
        description_ar  TEXT,
        order_index     INTEGER NOT NULL DEFAULT 0,
        is_pinned_today INTEGER NOT NULL DEFAULT 0
                        CHECK (is_pinned_today IN (0,1)),
        pinned_at       TEXT,
        golden_tip      TEXT
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_units_specialty_order '
      'ON $tableUnits(specialty, order_index)',
    );
    batch.execute(
      'CREATE INDEX idx_units_module_order ON $tableUnits(module, order_index)',
    );

    // ── الشروحات المفصلة (Concepts) ──
    batch.execute('''
      CREATE TABLE $tableConcepts (
        id             TEXT PRIMARY KEY,
        unit_id        TEXT NOT NULL REFERENCES $tableUnits(id) ON DELETE CASCADE,
        title          TEXT NOT NULL,
        summary_ar     TEXT,
        sections_json  TEXT NOT NULL,
        key_terms_json TEXT,
        difficulty     TEXT NOT NULL DEFAULT 'core'
                       CHECK (difficulty IN ('core','advanced')),
        order_index    INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('CREATE INDEX idx_concepts_unit ON $tableConcepts(unit_id)');

    // ── البطاقات الغنية (SRS) ──
    batch.execute('''
      CREATE TABLE $tableFlashcards (
        id             TEXT PRIMARY KEY,
        unit_id        TEXT NOT NULL REFERENCES $tableUnits(id) ON DELETE CASCADE,
        concept_id     TEXT REFERENCES $tableConcepts(id) ON DELETE SET NULL,
        card_type      TEXT NOT NULL DEFAULT 'basic'
                       CHECK (card_type IN ('basic')),
        front_text     TEXT NOT NULL,
        back_text      TEXT NOT NULL,
        mnemonic_ar    TEXT,
        explanation_ar TEXT,
        tags_json      TEXT,
        is_vivid       INTEGER NOT NULL DEFAULT 0
                       CHECK (is_vivid IN (0,1))
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_flashcards_unit ON $tableFlashcards(unit_id)',
    );

    // ── بنك أسئلة MCQ ──
    batch.execute('''
      CREATE TABLE $tableMcqBank (
        id                  TEXT PRIMARY KEY,
        unit_id             TEXT NOT NULL REFERENCES $tableUnits(id) ON DELETE CASCADE,
        concept_id          TEXT REFERENCES $tableConcepts(id) ON DELETE SET NULL,
        question_stem       TEXT NOT NULL,
        options_json        TEXT NOT NULL,
        correct_index       INTEGER NOT NULL
                            CHECK (correct_index >= 0),
        explanation_ar      TEXT NOT NULL,
        difficulty          TEXT NOT NULL DEFAULT 'core'
                            CHECK (difficulty IN ('core','advanced')),
        clinical_vignette   INTEGER NOT NULL DEFAULT 0
                            CHECK (clinical_vignette IN (0,1)),
        hints_json          TEXT,
        focus_sections_json TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_mcq_bank_unit ON $tableMcqBank(unit_id)');
    batch.execute(
      'CREATE INDEX idx_mcq_bank_difficulty ON $tableMcqBank(difficulty)',
    );

    // ── الحالات السريرية (OSCE) ──
    batch.execute('''
      CREATE TABLE $tableClinicalCases (
        id             TEXT PRIMARY KEY,
        unit_id        TEXT NOT NULL REFERENCES $tableUnits(id) ON DELETE CASCADE,
        title          TEXT NOT NULL,
        scenario       TEXT NOT NULL,
        vignette_json  TEXT NOT NULL,
        debriefing_ar  TEXT NOT NULL,
        difficulty     TEXT NOT NULL DEFAULT 'core'
                       CHECK (difficulty IN ('core','advanced')),
        order_index    INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_clinical_cases_unit ON $tableClinicalCases(unit_id)',
    );

    // ── خطوات الحالات السريرية (قرارات OSCE) ──
    batch.execute('''
      CREATE TABLE $tableClinicalCaseSteps (
        id             TEXT PRIMARY KEY,
        case_id        TEXT NOT NULL REFERENCES $tableClinicalCases(id)
                       ON DELETE CASCADE,
        prompt         TEXT NOT NULL,
        options_json   TEXT NOT NULL,
        correct_index  INTEGER NOT NULL
                       CHECK (correct_index >= 0),
        explanation_ar TEXT NOT NULL,
        xp             INTEGER NOT NULL DEFAULT 5
                       CHECK (xp BETWEEN 1 AND 20),
        step_index     INTEGER NOT NULL DEFAULT 0,
        hints_json     TEXT
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_case_steps_case ON $tableClinicalCaseSteps(case_id)',
    );

    // ── تقدم المستخدم ──
    batch.execute('''
      CREATE TABLE $tableUserProgress (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        item_type         TEXT NOT NULL
                          CHECK (item_type IN ('lesson','flashcard_set','drill')),
        item_id           TEXT NOT NULL,
        status            TEXT NOT NULL DEFAULT 'not_started'
                          CHECK (status IN ('not_started','in_progress','completed')),
        score             INTEGER,
        times_reviewed    INTEGER NOT NULL DEFAULT 0,
        last_practiced_at TEXT,
        updated_at        TEXT
      )
    ''');
    batch.execute('''
      CREATE UNIQUE INDEX idx_progress_item
        ON $tableUserProgress(item_type, item_id)
    ''');
    batch.execute(
      'CREATE INDEX idx_progress_status ON $tableUserProgress(status)',
    );

    // ── سجل الإجابات (corrections) ──
    batch.execute('''
      CREATE TABLE $tableCorrections (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        drill_id       TEXT NOT NULL,
        question_id    TEXT NOT NULL,
        user_answer    TEXT NOT NULL,
        correct_answer TEXT NOT NULL,
        is_correct     INTEGER NOT NULL CHECK (is_correct IN (0,1)),
        mistake_type   TEXT CHECK (mistake_type IN ('exact','spelling','wrong')),
        attempted_at   TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_corrections_drill ON $tableCorrections(drill_id)',
    );
    batch.execute(
      'CREATE INDEX idx_corrections_time ON $tableCorrections(attempted_at)',
    );
    batch.execute('''
      CREATE INDEX idx_corrections_wrong
        ON $tableCorrections(drill_id) WHERE is_correct = 0
    ''');

    // ── التلعيب: نقاط الخبرة + الشارات ──
    batch.execute('''
      CREATE TABLE $tableXpEvents (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        kind       TEXT NOT NULL
                   CHECK ($xpKindsCheckSql),
        ref_id     TEXT,
        xp         INTEGER NOT NULL CHECK (xp > 0),
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_xp_events_time ON $tableXpEvents(created_at)',
    );
    batch.execute('''
      CREATE TABLE $tableUnlockedBadges (
        badge_id    TEXT PRIMARY KEY,
        unlocked_at TEXT NOT NULL
      )
    ''');

    // ── بطاقات التكرار المتباعد (خوارزمية Leitner) ──
    batch.execute('''
      CREATE TABLE $tableSrsCards (
        flashcard_id TEXT NOT NULL
                     REFERENCES $tableFlashcards(id) ON DELETE CASCADE,
        box         INTEGER NOT NULL CHECK (box BETWEEN 1 AND 5),
        streak_ok   INTEGER NOT NULL DEFAULT 0,
        streak_bad  INTEGER NOT NULL DEFAULT 0,
        last_review TEXT,
        next_due    TEXT NOT NULL,
        card_type   TEXT NOT NULL DEFAULT 'basic'
                    CHECK (card_type IN ('basic')),
        PRIMARY KEY (flashcard_id, card_type)
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_srs_due ON $tableSrsCards(next_due)
    ''');

    // ── v15: محرّك القراءة العميقة ──

    // سجل قراءة الشروحات — أزمنة البقاء لكل قسم + عدد مرات القراءة
    // (يغذي: تعطيل المراسي في إعادة القراءة + كاشف التصفح §2.3).
    // gate_passed (v16): اجتياز بوابة الشرح (تُتخطى في الزيارات التالية).
    batch.execute('''
      CREATE TABLE $tableConceptReads (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        concept_id      TEXT NOT NULL
                        REFERENCES $tableConcepts(id) ON DELETE CASCADE,
        read_count      INTEGER NOT NULL DEFAULT 0,
        completed       INTEGER NOT NULL DEFAULT 0
                        CHECK (completed IN (0,1)),
        gate_passed     INTEGER NOT NULL DEFAULT 0
                        CHECK (gate_passed IN (0,1)),
        last_read_at    TEXT NOT NULL,
        sections_json   TEXT
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_concept_reads_concept ON $tableConceptReads(concept_id)',
    );

    // جلسات التدفق — زمن البقاء داخل كتلة قراءة/بطاقات بلا خروج من
    // التطبيق. أساس «دقائق التركيز» (مقياس الشمال — لا XP).
    batch.execute('''
      CREATE TABLE $tableFlowSessions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        kind            TEXT NOT NULL
                        CHECK (kind IN ('reading','flashcards','mcq','case')),
        ref_id          TEXT,
        started_at      TEXT NOT NULL,
        ended_at        TEXT,
        focused_seconds INTEGER NOT NULL DEFAULT 0
                        CHECK (focused_seconds >= 0)
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_flow_sessions_time ON $tableFlowSessions(started_at)',
    );

    // سجل الثقة — كل إجابة بدرجة ثقة (خمنت/متأكد/متأكد جداً).
    // الأخطاء عالية الثقة تُحجز لمراجعة +24h/+7d فوق جدول SRS
    // (Butler 2011 — أثمن البطاقات وأول ما «يعود» للظهور).
    batch.execute('''
      CREATE TABLE $tableConfidenceLog (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id     TEXT NOT NULL,
        confidence      INTEGER NOT NULL
                        CHECK (confidence BETWEEN 0 AND 2),
        was_correct     INTEGER NOT NULL CHECK (was_correct IN (0,1)),
        answered_at     TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_confidence_time ON $tableConfidenceLog(answered_at)',
    );
    batch.execute('''
      CREATE INDEX idx_confidence_question
        ON $tableConfidenceLog(question_id)
    ''');

    // إحصاءات يومية لزمن الدراسة (v21) — جدول خفيف نحوّل فيه
    // تجمّعات وقت استخدام التطبيق يومياً (UTC). date مفتاح أساسي —
    // صف واحد لكل يوم، تتجمّع قيمته بالتكرار.
    batch.execute('''
      CREATE TABLE IF NOT EXISTS $tableDailyStats (
        date            TEXT PRIMARY KEY,
        study_seconds   INTEGER NOT NULL DEFAULT 0
                        CHECK (study_seconds >= 0)
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_stats_date '
      'ON $tableDailyStats(date)',
    );

    // ملاحظات داخلية مضمّنة في نص الشروحات (Inline Highlight — v22):
    // المستخدم يحدّد نصاً/سطراً داخل الشرح ويرفق به ملاحظة شخصية،
    // ثم يظهر النص مميَّزاً وخلفيته صفراء — النقر عليه يعرض الملاحظة.
    batch.execute('''
      CREATE TABLE IF NOT EXISTS $tableInlineNotes (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        concept_id     TEXT NOT NULL
                       REFERENCES $tableConcepts(id) ON DELETE CASCADE,
        selected_text  TEXT NOT NULL,
        start_index    INTEGER DEFAULT 0,
        end_index      INTEGER DEFAULT 0,
        personal_note  TEXT NOT NULL,
        color_code     TEXT,
        created_at     TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_inline_notes_concept '
      'ON $tableInlineNotes(concept_id)',
    );

    // v23: سجلات المرضى (نموذج أخذ القصة)
    batch.execute('''
      CREATE TABLE IF NOT EXISTS $tablePatientRecords (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_alias   TEXT NOT NULL,
        responses_json  TEXT NOT NULL,
        created_at      TEXT NOT NULL,
        updated_at      TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_patient_records_time '
      'ON $tablePatientRecords(created_at)',
    );

    await batch.commit(noResult: true);
  }

  /// ترحيلات النسخ.
  ///
  /// v13 → v14 (إعادة الهيكلة الطبية): القاعدة الألمانية القديمة لا
  /// تُرحَّل — تغيّر الجذور كامل (جداول محتوى جديدة كلياً). القرار
  /// الموثق: حذف كل جداول المحتوى اللغوية القديمة وجداول SRS
  /// المرتبطة بها، وإنشاء المخطط الطبي الجديد. بيانات المستخدم
  /// القديمة (xp/badges) تُنسخ لأنها مستقلة عن المحتوى.
  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // أداة ترحيل الأعمدة التسامحية — مشتركة بين كل الإصدارات:
    // تتحقق وجود الجدول والعمود قبل ALTER ADD (لا تفشل على قواعد
    // مصغرة/جزئية ولا على إعادة فتح بنفس الإصدار) — إضافة صرفة
    // بلا فقد بيانات أبداً.
    Future<void> addColumnIfTable(
      String table,
      String column,
      String definition,
    ) async {
      final int exists =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM sqlite_master '
              "WHERE type = 'table' AND name = ?",
              <Object?>[table],
            ),
          ) ??
          0;
      if (exists == 0) return;
      // العمود موجود أصلاً؟ (إعادة فتح بنفس الإصدار) — تجاهل.
      final List<Map<String, Object?>> cols = await db.rawQuery(
        'PRAGMA table_info($table)',
      );
      final bool present = cols.any(
        (Map<String, Object?> c) => c['name'] == column,
      );
      if (present) return;
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }

    if (oldV < 14) {
      // (أ) جداول التحفيز القديمة — نحفظ أحداث XP والشارات إن وُجدت.
      final List<Map<String, Object?>> xpRows = <Map<String, Object?>>[];
      final List<Map<String, Object?>> badgeRows = <Map<String, Object?>>[];
      try {
        xpRows.addAll(await db.query('xp_events'));
        badgeRows.addAll(await db.query('unlocked_badges'));
      } catch (_) {
        // قاعدة بلا جداول التحفيز — بداية نظيفة.
      }

      // (ب) حذف كل الجداول القديمة (محتوى لغوي + تقدم مرتبط به).
      const List<String> legacyTables = <String>[
        'vocabulary',
        'lessons',
        'units',
        'grammar_rules',
        'dialogues',
        'dialogue_choices',
        'verb_forms',
        'case_drills',
        'reading_texts',
        'exam_bank',
        'tts_settings',
        'srs_cards',
        'user_progress',
        'corrections',
        'xp_events',
        'unlocked_badges',
      ];
      for (final String table in legacyTables) {
        await db.execute('DROP TABLE IF EXISTS $table');
      }

      // (ج) إنشاء المخطط الطبي الجديد.
      await _onCreate(db, 14);

      // (د) استرجاع أحداث XP القديمة الصالحة لأنواعها ما زالت معرفة،
      //     والشارات كلها (مستقلة عن المحتوى).
      final Batch batch = db.batch();
      for (final Map<String, Object?> row in badgeRows) {
        batch.insert(
          'unlocked_badges',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
      // ملاحظة: أحداث XP القديمة (lesson/vocabulary/...) أنواع لم تعد
      // موجودة في قيد CHECK — تُهدر عمداً. التقدم الطبي يبدأ من الصفر
      // مع بقاء الشارات المفتوحة كإنجازات تاريخية.
      if (kDebugMode && badgeRows.isNotEmpty) {
        debugPrint(
          'DatabaseHelper: v14 — استُعيدت ${badgeRows.length} شارة تاريخية',
        );
      }
    }
    if (oldV < 15) {
      // v15: محرّك القراءة العميقة — جداول جديدة فقط فوق v14 القائم.
      // لا حذف ولا تعديل لأي جدول قائم — إضافة صرفة آمنة للتقدم.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableConceptReads (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          concept_id      TEXT NOT NULL
                          REFERENCES $tableConcepts(id) ON DELETE CASCADE,
          read_count      INTEGER NOT NULL DEFAULT 0,
          completed       INTEGER NOT NULL DEFAULT 0
                          CHECK (completed IN (0,1)),
          last_read_at    TEXT NOT NULL,
          sections_json   TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_concept_reads_concept '
        'ON $tableConceptReads(concept_id)',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableFlowSessions (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          kind            TEXT NOT NULL
                          CHECK (kind IN ('reading','flashcards','mcq','case')),
          ref_id          TEXT,
          started_at      TEXT NOT NULL,
          ended_at        TEXT,
          focused_seconds INTEGER NOT NULL DEFAULT 0
                          CHECK (focused_seconds >= 0)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_flow_sessions_time '
        'ON $tableFlowSessions(started_at)',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableConfidenceLog (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id     TEXT NOT NULL,
          confidence      INTEGER NOT NULL
                          CHECK (confidence BETWEEN 0 AND 2),
          was_correct     INTEGER NOT NULL CHECK (was_correct IN (0,1)),
          answered_at     TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_confidence_time '
        'ON $tableConfidenceLog(answered_at)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_confidence_question '
        'ON $tableConfidenceLog(question_id)',
      );
    }
    if (oldV < 16) {
      // v16: عقد v2.1 + البوابة — أعمدة اختيارية فقط (ALTER ADD COLUMN
      // الآمنة: قيم افتراضية، لا إعادة بناء، لا فقد بيانات).
      // تقيّد وجود الجدول أولاً: الترحيل تسامحي مع القواعد المصغرة
      // (اختبارات/بيئات جزئية) — لا يفشل افتتاح القاعدة أبداً.
      await addColumnIfTable(tableMcqBank, 'hints_json', 'TEXT');
      await addColumnIfTable(tableMcqBank, 'focus_sections_json', 'TEXT');
      await addColumnIfTable(tableClinicalCaseSteps, 'hints_json', 'TEXT');
      await addColumnIfTable(
        tableFlashcards,
        'is_vivid',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await addColumnIfTable(
        tableConceptReads,
        'gate_passed',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldV < 17) {
      // v17: أهداف اليوم — تثبيت المحاضرات لجدول يومي يبنيه المستخدم.
      await addColumnIfTable(
        tableUnits,
        'is_pinned_today',
        'INTEGER NOT NULL DEFAULT 0 '
            'CHECK (is_pinned_today IN (0,1))',
      );
    }
    if (oldV < 18) {
      // v18: التثبيت الذكي — طابع زمني لحظة التثبيت (null = غير
      // مثبتة). المثبتات القائمة (is_pinned_today=1) تُرحَّل إلى
      // «مثبتة الآن» كي لا يفقدها المستخدم — ثم يسري عليها عدّاد
      // الـ 48 ساعة كأي تثبيت جديد.
      try {
        await addColumnIfTable(tableUnits, 'pinned_at', 'TEXT');
        final int exists =
            Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM sqlite_master '
                "WHERE type = 'table' AND name = ?",
                <Object?>[tableUnits],
              ),
            ) ??
            0;
        if (exists > 0) {
          await db.execute(
            'UPDATE $tableUnits SET pinned_at = ? '
            'WHERE is_pinned_today = 1 AND pinned_at IS NULL',
            <Object?>[DateTime.now().toUtc().toIso8601String()],
          );
        }
      } catch (_) {
        // حزام أمان — فشل الترحيل لا يمنع فتح القاعدة.
      }
    }
    if (oldV < 19) {
      // v19: لؤلؤة اليوم — units.golden_tip (عقد v2.2 اختياري).
      try {
        await addColumnIfTable(tableUnits, 'golden_tip', 'TEXT');
      } catch (_) {
        // حزام أمان — فشل الترحيل لا يمنع فتح القاعدة.
      }
    }
    if (oldV < 20) {
      // v20: التوسع متعدد التخصصات — specialty لكل محاضرة. القيمة
      // الافتراضية في تعريف العمود تسند الباطنية لكل الصفوف القائمة
      // تلقائياً (ADD COLUMN NOT NULL DEFAULT يعبّئ القديم والجديد
      // معاً) — المحتوى الحالي لا يضيع ولا يتعطل.
      //
      // addColumnIfTable متسامح أصلاً (فحص PRAGMA table_info قبل
      // ALTER — لا يفشل إن كان العمود موجوداً)؛ الـ try-catch هنا
      // حزام أمان إضافي: فشل الترقية لأي سبب شاذ (قاعدة جزئية،
      // إصدار SQLite غريب) لا يمنع فتح التطبيق — التطبيق يعمل
      // والتخصص يبقى على الباطنية حتى الإصلاح.
      try {
        await addColumnIfTable(
          tableUnits,
          'specialty',
          "TEXT NOT NULL DEFAULT 'internal_medicine' "
              "CHECK (specialty IN ('internal_medicine','surgery','obgyn'))",
        );
      } catch (_) {
        // صمت مقصود — فشل إضافة العمود لا يُسقط فتح القاعدة أبداً.
      }
    }
    if (oldV < 21) {
      // v21: جدول الإحصاءات اليومية لزمن الدراسة — إنشاء صرف لا فقد
      // بيانات. CREATE TABLE IF NOT EXISTS متسامح مع القواعد المصغرة
      // (اختبارات/بيئات جزئية) — لا يفشل افتتاح القاعدة أبداً.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableDailyStats (
          date            TEXT PRIMARY KEY,
          study_seconds   INTEGER NOT NULL DEFAULT 0
                          CHECK (study_seconds >= 0)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_daily_stats_date '
        'ON $tableDailyStats(date)',
      );
    }
    if (oldV < 22) {
      // v22: جدول الملاحظات المضمّنة — إنشاء صرف لا فقد بيانات.
      // CREATE TABLE IF NOT EXISTS متسامح مع القواعد المصغرة/الجزئية
      // (اختبارات/بيئات) — لا يفشل افتتاح القاعدة أبداً.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableInlineNotes (
          id             INTEGER PRIMARY KEY AUTOINCREMENT,
          concept_id     TEXT NOT NULL
                         REFERENCES $tableConcepts(id) ON DELETE CASCADE,
          selected_text  TEXT NOT NULL,
          start_index    INTEGER DEFAULT 0,
          end_index      INTEGER DEFAULT 0,
          personal_note  TEXT NOT NULL,
          color_code     TEXT,
          created_at     TEXT NOT NULL
        )
      ''');
      // If the table already exists from an older v22 build without indices,
      // we add them to avoid breaking the DB for users upgrading from that specific build.
      try {
        await db.execute('ALTER TABLE $tableInlineNotes ADD COLUMN start_index INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE $tableInlineNotes ADD COLUMN end_index INTEGER DEFAULT 0');
      } catch (_) {}
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inline_notes_concept '
        'ON $tableInlineNotes(concept_id)',
      );
    }
    if (oldV < 23) {
      // v23: جدول سجلات المرضى لنموذج أخذ القصة (History Module)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tablePatientRecords (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          patient_alias   TEXT NOT NULL,
          responses_json  TEXT NOT NULL,
          created_at      TEXT NOT NULL,
          updated_at      TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_patient_records_time '
        'ON $tablePatientRecords(created_at)',
      );
    }
    if (oldV < 24) {
      // v24: إضافة أعمدة الإحداثيات الدقيقة للملاحظات المضمنة.
      try {
        await db.execute('ALTER TABLE $tableInlineNotes ADD COLUMN start_index INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE $tableInlineNotes ADD COLUMN end_index INTEGER DEFAULT 0');
      } catch (_) {}
    }
  }

  // ─────────────────── الوحدات (المحاضرات الطبية) ───────────────────

  /// كل الوحدات (أو حسب التخصص الفرعي module) مرتبة حسب التخصص ثم
  /// الترتيب.
  Future<List<Map<String, Object?>>> getAllUnits({String? module}) async {
    final Database db = await database;
    return module == null
        ? db.query(tableUnits, orderBy: 'module, order_index')
        : db.query(
          tableUnits,
          where: 'module = ?',
          whereArgs: <Object?>[module],
          orderBy: 'order_index',
        );
  }

  /// وحدات تخصص سريري كامل — v20: أساس شريط (باطنية|جراحة|نسائية)
  /// في شاشتي المسار والمكتبة. null = كل التخصصات (كل المحتوى).
  Future<List<Map<String, Object?>>> getUnitsBySpecialty(
    String? specialty,
  ) async {
    final Database db = await database;
    return db.query(
      tableUnits,
      where: 'specialty = ?',
      whereArgs: <Object?>[specialty],
      orderBy: 'order_index, id',
    );
  }

  /// التخصصات السريرية الموجودة فعلاً في المحتوى (بترتيب العقد).
  /// القاعدة قد تحوي واحداً أو أكثر — الواجهة تخفي شريط التبديل
  /// عند وجود تخصص واحد (بلا فائدة للتبديل).
  Future<List<String>> getDistinctSpecialties() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT DISTINCT specialty FROM $tableUnits',
    );
    final Set<String> present = <String>{
      for (final Map<String, Object?> r in rows) r['specialty']! as String,
    };
    // ترتيب العقد (internal_medicine أولاً) لا الترتيب الأبجدي.
    return <String>[
      for (final String s in specialties)
        if (present.contains(s)) s,
    ];
  }

  /// وحدة واحدة بمعرّفها.
  Future<Map<String, Object?>?> getUnitById(String unitId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableUnits,
      where: 'id = ?',
      whereArgs: <Object?>[unitId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ─────────────────── أهداف اليوم (v18: التثبيت الذكي) ───────────────────

  /// عتبة إهمال التثبيت — 48 ساعة من لحظة التثبيت (v18).
  static const Duration stalePinThreshold = Duration(hours: 48);

  /// يثبّت/يفكّ تثبيت محاضرة لأهداف اليوم — يرجع الحالة الجديدة
  /// (true = مثبتة). التثبيت يسجّل لحظة الآن في pinned_at (مفتاح عدّاد
  /// الـ 48 ساعة)؛ الفك يمسحه إلى null. لا استثناءات: عند الفشل
  /// تُرجع الحالة القديمة.
  Future<bool> toggleUnitPinnedToday(String unitId) async {
    final Database db = await database;
    try {
      final Map<String, Object?>? row = await getUnitById(unitId);
      if (row == null) return false;
      final bool nowPinned = row['pinned_at'] == null;
      await db.rawUpdate(
        'UPDATE $tableUnits SET pinned_at = ? WHERE id = ?',
        <Object?>[
          nowPinned ? DateTime.now().toUtc().toIso8601String() : null,
          unitId,
        ],
      );
      return nowPinned;
    } catch (_) {
      // الحالة القديمة عند الفشل — الواجهة تعيد القراءة.
      return (await getUnitById(unitId))?['pinned_at'] != null;
    }
  }

  /// المحاضرات المثبتة لأهداف اليوم — بترتيب المنهج (system ثم
  /// order_index) كي يظهر «جدول اليوم» بترتيب دراسة منطقي.
  Future<List<Map<String, Object?>>> getPinnedUnits() async {
    final Database db = await database;
    return db.query(
      tableUnits,
      where: 'pinned_at IS NOT NULL',
      orderBy: 'system, order_index',
    );
  }

  /// عدد المحاضرات المثبتة (لشارة سريعة دون جلب الصفوف).
  Future<int> pinnedUnitsCount() async {
    final Database db = await database;
    final int? result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $tableUnits WHERE pinned_at IS NOT NULL',
      ),
    );
    return result ?? 0;
  }

  /// المحاضرات المثبتة لأهداف اليوم **مع حالة إكمالها** — checkTodayStatus
  /// في طبقة البيانات. الإكمال مشتق ديناميكياً من التقدم القائم (بلا
  /// هجرة ولا عمود جديد) فيتحدّث تلقائياً لحظة إتمام المحاضرة:
  ///
  /// - اجتياز تقييمها الرسمي: `user_progress(drill, assess-(id)) =
  ///   completed` — نفس معيار شاشة المسار.
  /// - **أو** قراءة كل شروحها كاملة: كل concept له سطر concept_reads
  ///   مكتمل (إتمام القراءة العميقة).
  ///
  /// العمود المُرفق: `is_completed` (1/0). الوحدة بلا شروح وبلا تقييم
  /// مجتاز تبقى غير مكتملة.
  Future<List<Map<String, Object?>>> getPinnedUnitsWithCompletion() async {
    final Database db = await database;
    return db.rawQuery('''
      SELECT u.*,
             (EXISTS(SELECT 1 FROM $tableUserProgress p
                     WHERE p.item_type = 'drill'
                       AND p.item_id = 'assess-' || u.id
                       AND p.status = 'completed')
              OR ((SELECT COUNT(*) FROM $tableConcepts c
                   WHERE c.unit_id = u.id) > 0
                  AND NOT EXISTS(SELECT 1 FROM $tableConcepts c
                     WHERE c.unit_id = u.id
                       AND NOT EXISTS(SELECT 1 FROM $tableConceptReads r
                           WHERE r.concept_id = c.id
                             AND r.completed = 1)))
             ) AS is_completed
      FROM $tableUnits u
      WHERE u.pinned_at IS NOT NULL
      ORDER BY u.system, u.order_index
    ''');
  }

  /// إلغاء تثبيت محاضرة من أهداف اليوم — يُستدعى يدوياً (فك المستخدم)
  /// أو تلقائياً عند إتمامها (auto-unpin) فتختفي من جدول اليوم وتقفز
  /// نسبة الإنجاز.
  Future<void> unpinUnit(String unitId) async {
    final Database db = await database;
    await db.rawUpdate(
      'UPDATE $tableUnits SET pinned_at = NULL WHERE id = ?',
      <Object?>[unitId],
    );
  }

  /// إلغاء التثبيت **فقط إن كانت المحاضرة مكتملة** (نفس معيار
  /// is_completed أعلاه) — ذرّة واحدة: إن لم تكتمل بعد لا يُلمس
  /// التثبيت. تُستدعى بعد تسجيل أي تقدم داخل المحاضرة (قراءة
  /// شروح/تقييم) فيكتمل الهدف لحظة تحققه لا بعده.
  Future<void> unpinUnitIfCompleted(String unitId) async {
    final Database db = await database;
    await db.rawUpdate(
      '''
      UPDATE $tableUnits SET pinned_at = NULL
      WHERE id = ? AND pinned_at IS NOT NULL
        AND (EXISTS(SELECT 1 FROM $tableUserProgress p
                   WHERE p.item_type = 'drill'
                     AND p.item_id = 'assess-' || ?
                     AND p.status = 'completed')
             OR ((SELECT COUNT(*) FROM $tableConcepts c
                  WHERE c.unit_id = ?) > 0
                 AND NOT EXISTS(SELECT 1 FROM $tableConcepts c
                    WHERE c.unit_id = ?
                      AND NOT EXISTS(SELECT 1 FROM $tableConceptReads r
                          WHERE r.concept_id = c.id
                            AND r.completed = 1))))
    ''',
      <Object?>[unitId, unitId, unitId, unitId],
    );
  }

  /// ─────────────── التنظيف التلقائي (v18) ───────────────
  ///
  /// قلب التثبيت الذكي — يُستدعى عند إقلاع التطبيق وعند دخول شاشة
  /// «اليوم». مسحور واحد ذرّي يفك تثبيت فئتين معاً:
  ///
  /// (أ) **المكتملة**: مثبتة واكتملت (اجتياز التقييم أو كل الشروح
  ///     مقروءة) → فك فوري — المستخدم يرى إنجازه ولا تتراكم أهداف
  ///     منجزة في جدول اليوم.
  /// (ب) **المهملة**: مثبتة غير مكتملة ومر على تثبيتها أكثر من
  ///     [stalePinThreshold] (48 ساعة) → فك تلقائي — لا يتراكم
  ///     «دين منجزات» قديم يشعر المستخدم بالعجز أمامه.
  ///
  /// يعيد معرفات المحاضرات التي فُكّ تثبيتها (لإلغاء إشعاراتها
  /// المجدولة — انظر PinExpiryService). الترتيب ضمان داخل معاملة
  /// واحدة: أي فشل يتراجع كلياً فلا حالة وسطية.
  Future<List<String>> cleanUpStalePins() async {
    final Database db = await database;
    final String cutoff =
        DateTime.now().toUtc().subtract(stalePinThreshold).toIso8601String();

    final List<String> unpinned = <String>[];
    await db.transaction((Transaction txn) async {
      // المعرفات أولاً (لإلغاء الإشعارات خارج المعاملة) ثم المسح.
      // ملاحظة SQL: كل مرجع لعمود الوحدة داخل الاستعلامات الفرعية
      // يجب تأهيله باسم الجدول — `id` وحده يحل إلى p.id الداخلي.
      final List<Map<String, Object?>> rows = await txn.rawQuery(
        'SELECT id FROM $tableUnits WHERE pinned_at IS NOT NULL '
        'AND (EXISTS(SELECT 1 FROM $tableUserProgress p '
        '            WHERE p.item_type = ? AND p.item_id = ? || $tableUnits.id '
        '              AND p.status = ?) '
        '     OR ((SELECT COUNT(*) FROM $tableConcepts c '
        '          WHERE c.unit_id = $tableUnits.id) > 0 '
        '         AND NOT EXISTS(SELECT 1 FROM $tableConcepts c '
        '            WHERE c.unit_id = $tableUnits.id '
        '              AND NOT EXISTS(SELECT 1 FROM $tableConceptReads r '
        '                  WHERE r.concept_id = c.id '
        '                    AND r.completed = 1))) '
        '     OR pinned_at < ?)',
        <Object?>['drill', 'assess-', 'completed', cutoff],
      );
      unpinned.addAll(rows.map((Map<String, Object?> r) => r['id']! as String));
      if (unpinned.isNotEmpty) {
        await txn.rawUpdate(
          'UPDATE $tableUnits SET pinned_at = NULL WHERE id IN '
          '(${unpinned.map((_) => '?').join(',')})',
          unpinned,
        );
      }
    });
    return unpinned;
  }

  // ─────────────────── ويدجت الشاشة الرئيسية (v19) ───────────────────

  /// عناوين المحاضرات المثبتة **غير المكتملة** — الجزء «أهدافي» في
  /// الويدجت (pinned_at قائمة + is_completed مشتق ديناميكياً = 0).
  /// سقف [limit] عناوين (الافتراضي 3 — سعة الويدجت) بترتيب المنهج.
  Future<List<String>> getPendingPinnedLectureTitles({int limit = 3}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT u.title FROM $tableUnits u
      WHERE u.pinned_at IS NOT NULL
        AND NOT (EXISTS(SELECT 1 FROM $tableUserProgress p
                        WHERE p.item_type = 'drill'
                          AND p.item_id = 'assess-' || u.id
                          AND p.status = 'completed')
                 OR ((SELECT COUNT(*) FROM $tableConcepts c
                      WHERE c.unit_id = u.id) > 0
                     AND NOT EXISTS(SELECT 1 FROM $tableConcepts c
                        WHERE c.unit_id = u.id
                          AND NOT EXISTS(SELECT 1 FROM $tableConceptReads r
                              WHERE r.concept_id = c.id
                                AND r.completed = 1))))
      ORDER BY u.system, u.order_index
      LIMIT ?
    ''',
      <Object?>[limit],
    );
    return <String>[
      for (final Map<String, Object?> r in rows) r['title']! as String,
    ];
  }

  /// إجمالي المحاضرات المثبتة **غير المكتملة** بلا سقف — عدّاد
  /// «+N أخرى» في الويدجت (العدد الكلي مقابل عناوين [limit] فقط).
  /// نفس معيار عدم الإكمال في [getPendingPinnedLectureTitles] حرفياً.
  Future<int> countPendingPinnedLectures() async {
    final Database db = await database;
    final int? count = Sqflite.firstIntValue(
      await db.rawQuery('''
      SELECT COUNT(*) FROM $tableUnits u
      WHERE u.pinned_at IS NOT NULL
        AND NOT (EXISTS(SELECT 1 FROM $tableUserProgress p
                        WHERE p.item_type = 'drill'
                          AND p.item_id = 'assess-' || u.id
                          AND p.status = 'completed')
                 OR ((SELECT COUNT(*) FROM $tableConcepts c
                      WHERE c.unit_id = u.id) > 0
                     AND NOT EXISTS(SELECT 1 FROM $tableConcepts c
                        WHERE c.unit_id = u.id
                          AND NOT EXISTS(SELECT 1 FROM $tableConceptReads r
                              WHERE r.concept_id = c.id
                                AND r.completed = 1))))
    '''),
    );
    return count ?? 0;
  }

  /// لؤلؤة اليوم — golden_tip واحدة عشوائية من أي محاضرة (مثبتة أو
  /// لا). null إن لم تُزرع أي لؤلؤة بعد (الويدجت يعرض عندها بنك
  /// المعلومات الثابت في Dart).
  Future<String?> getRandomGoldenTip() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT golden_tip FROM $tableUnits '
      'WHERE golden_tip IS NOT NULL AND TRIM(golden_tip) <> "" '
      'ORDER BY RANDOM() LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return rows.first['golden_tip']! as String;
  }

  /// إدراج وحدة (idempotent).
  Future<void> insertUnit(Map<String, Object?> unit) async {
    final Database db = await database;
    await db.insert(
      tableUnits,
      unit,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// تطبيق ترتيب/نقل وحدة — القلب الحاسوبي لمسار التعلم القائم على
  /// الأجهزة (system-based curriculum).
  ///
  /// - [orders]: خريطة unitId → order_index الجديدة لكل وحدات الجهاز
  ///   المعني (ترقيم تسلسلي 0..n-1).
  /// - [newSystem]: إن أُريد نقل الوحدة إلى جهاز آخر (تُحدّث system) —
  ///   null = إعادة ترتيب داخل نفس الجهاز فقط.
  /// - [unitId]: الوحدة التي سحبها المستخدم (تُحدَّث دائماً).
  ///
  /// كل شيء داخل **معاملة واحدة ذرّية** — أي فشل يتراجع كلياً
  /// فلا يضيع ترتيب المستخدم المخصص عند إعادة تشغيل التطبيق.
  Future<void> applyUnitArrangement({
    required String unitId,
    required Map<String, int> orders,
    String? newSystem,
  }) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      // (1) النقل بين الأجهزة إن طُلب — نظام الوحدة المسحوبة.
      if (newSystem != null) {
        await txn.update(
          tableUnits,
          <String, Object?>{'system': newSystem},
          where: 'id = ?',
          whereArgs: <Object?>[unitId],
        );
      }

      // (2) كتابة الترتيب التسلسلي الجديد لكل وحدات الجهاز المعني.
      for (final MapEntry<String, int> e in orders.entries) {
        await txn.update(
          tableUnits,
          <String, Object?>{'order_index': e.value},
          where: 'id = ?',
          whereArgs: <Object?>[e.key],
        );
      }
    });
  }

  /// حذف محاضرة بالكامل (حذف متسلسل يدوي) — الوحدة وكل ما يتصل بها:
  ///
  /// **المحتوى**: concepts · flashcards · mcq_bank · clinical_cases
  /// (+ خطواتها clinical_case_steps).
  ///
  /// **تقدم المستخدم**: سطور user_progress للمفاتيح المرتبطة
  /// (flashcard_set/mcq/assess-unitId وcase-caseId) · corrections
  /// (drill_id) · srs_cards لبطاقات المحاضرة (Leitner) · xp_events
  /// التي تشير لعناصرها (ref_id).
  ///
  /// ملاحظة معمارية: FKs مع ON DELETE CASCADE مفعّلة (PRAGMA
  /// foreign_keys = ON في _onConfigure) — الحذف الصريح للجداول
  /// الفرعية أولاً ثم الجدول الرئيسي داخل **معاملة واحدة** هو ضمان
  /// إضافي يعمل حتى لو اختلفت إعدادات FK على منصة ما، ويغطي جداول
  /// المستخدم التي لا تحمل FK أصلاً (item_id/drill_id/ref_id مفاتيح
  /// منطقية لا قيود قاعدة).
  ///
  /// ذرّية كاملة: أي فشل يتراجع كلياً — لا يبقى حذف جزئي.
  Future<void> deleteLectureData(String unitId) async {
    final Database db = await database;

    await db.transaction((Transaction txn) async {
      // (أ) جمع حالات الحالات السريرية قبل حذفها (لمفاتيح progress).
      final List<Map<String, Object?>> caseRows = await txn.query(
        tableClinicalCases,
        columns: <String>['id'],
        where: 'unit_id = ?',
        whereArgs: <Object?>[unitId],
      );
      final List<String> caseIds = <String>[
        for (final Map<String, Object?> r in caseRows) r['id']! as String,
      ];

      // (ب) جمع معرفات البطاقات قبل حذفها (لمفاتيح srs_cards).
      final List<Map<String, Object?>> cardRows = await txn.query(
        tableFlashcards,
        columns: <String>['id'],
        where: 'unit_id = ?',
        whereArgs: <Object?>[unitId],
      );
      final List<String> flashcardIds = <String>[
        for (final Map<String, Object?> r in cardRows) r['id']! as String,
      ];

      // (ب-2) جمع معرفات المفاهيم وأسئلة MCQ (لتنظيف جداول v15:
      // concept_reads بالـ FK المنطقي · confidence_log بالسؤال ·
      // flow_sessions بمراجع القراءة).
      final List<String> conceptIds = <String>[
        for (final Map<String, Object?> r in await txn.query(
          tableConcepts,
          columns: <String>['id'],
          where: 'unit_id = ?',
          whereArgs: <Object?>[unitId],
        ))
          r['id']! as String,
      ];
      final List<String> mcqIds = <String>[
        for (final Map<String, Object?> r in await txn.query(
          tableMcqBank,
          columns: <String>['id'],
          where: 'unit_id = ?',
          whereArgs: <Object?>[unitId],
        ))
          r['id']! as String,
      ];

      // (ج) مفاتيح user_progress المنطقية المرتبطة بالمحاضرة:
      //     مجموعة البطاقات: item_id = unitId مجرداً (type flashcard_set)
      //     · mcq/assess-<unitId> · case-<caseId> لكل حالة.
      //     (الشكلان للبطاقات تحوطياً — تعايش إصدارات المفاتيح.)
      final List<String> progressKeys = <String>[
        unitId, // صف flashcard_set-<unitId>
        'flashcard_set-$unitId', // تحوطي لشكل مسبوق
        'mcq-$unitId',
        'assess-$unitId',
        for (final String caseId in caseIds) 'case-$caseId',
      ];

      // (د) مفاتيح corrections (drill_id) المرتبطة بالمحاضرة.
      final List<String> drillKeys = <String>[
        'mcq-$unitId',
        'assess-$unitId',
        for (final String caseId in caseIds) 'case-$caseId',
      ];

      // (هـ) مفاتيح xp_events (ref_id) — نفس مفاتيح التقدم + البطاقات.
      final List<String> xpRefKeys = <String>[...progressKeys, ...flashcardIds];

      // (هـ-2) v15: تنظيف جداول محرّك القراءة المرتبطة بالمحاضرة.
      // flow_sessions: جلسات القراءة على مفاهيمها (ref_id) + جلسات
      // البطاقات/الأسئلة على مفاتيح المحاضرة نفسها.
      final List<String> flowRefKeys = <String>[
        ...conceptIds,
        ...progressKeys,
        ...flashcardIds,
      ];

      // ── الحذف: الجداول الفرعية أولاً ثم الجدول الرئيسي ──

      // (1) خطوات الحالات السريرية (تعتمد على الحالات).
      await txn.delete(
        tableClinicalCaseSteps,
        where: 'case_id IN (${caseIds.map((_) => '?').join(',')})',
        whereArgs: caseIds.isEmpty ? null : caseIds,
      );

      // (2) بطاقات التكرار المتباعد (تقدم Leitner للمحاضرة).
      await _deleteByValues(txn, tableSrsCards, 'flashcard_id', flashcardIds);

      // (3) سجل الإجابات (تحليل الأخطاء).
      await _deleteByValues(txn, tableCorrections, 'drill_id', drillKeys);

      // (4) تقدم المستخدم على أنشطة المحاضرة.
      await _deleteByValues(txn, tableUserProgress, 'item_id', progressKeys);

      // (5) أحداث XP المرتبطة بعناصر المحاضرة (يحتفظ بغيرها —
      //     مجموع XP العام لا يتأثر سوى بأحداث هذه المحاضرة).
      await _deleteByValues(txn, tableXpEvents, 'ref_id', xpRefKeys);

      // (5-2) v15: جداول محرّك القراءة العميقة.
      await _deleteByValues(txn, tableConceptReads, 'concept_id', conceptIds);
      await _deleteByValues(txn, tableConfidenceLog, 'question_id', mcqIds);
      await _deleteByValues(txn, tableFlowSessions, 'ref_id', flowRefKeys);

      // (6) الحالات السريرية.
      await txn.delete(
        tableClinicalCases,
        where: 'unit_id = ?',
        whereArgs: <Object?>[unitId],
      );

      // (7) البطاقات الاسترجاعية.
      await txn.delete(
        tableFlashcards,
        where: 'unit_id = ?',
        whereArgs: <Object?>[unitId],
      );

      // (8) أسئلة MCQ.
      await txn.delete(
        tableMcqBank,
        where: 'unit_id = ?',
        whereArgs: <Object?>[unitId],
      );

      // (9) المفاهيم (الشروحات).
      await txn.delete(
        tableConcepts,
        where: 'unit_id = ?',
        whereArgs: <Object?>[unitId],
      );

      // (10) المحاضرة نفسها (الجدول الرئيسي).
      await txn.delete(
        tableUnits,
        where: 'id = ?',
        whereArgs: <Object?>[unitId],
      );
    });
  }

  /// حذف صفوف عمود معين بقائمة قيم — IN (...) ديناميكي آمن
  /// (معاملات مربوطة، بلا استعلام مركّب نصياً).
  static Future<void> _deleteByValues(
    DatabaseExecutor txn,
    String table,
    String column,
    List<String> values,
  ) async {
    if (values.isEmpty) return;
    await txn.delete(
      table,
      where: '$column IN (${values.map((_) => '?').join(',')})',
      whereArgs: values,
    );
  }

  // ─────────────────── الشروحات (Concepts) ───────────────────

  Future<List<Map<String, Object?>>> getConceptsForUnit(String unitId) async {
    final Database db = await database;
    return db.query(
      tableConcepts,
      where: 'unit_id = ?',
      whereArgs: <Object?>[unitId],
      orderBy: 'order_index',
    );
  }

  Future<Map<String, Object?>?> getConceptById(String conceptId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableConcepts,
      where: 'id = ?',
      whereArgs: <Object?>[conceptId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> insertConcept(Map<String, Object?> concept) async {
    final Database db = await database;
    await db.insert(
      tableConcepts,
      concept,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ─────────────────── البطاقات (Flashcards) ───────────────────

  Future<List<Map<String, Object?>>> getFlashcardsForUnit(String unitId) async {
    final Database db = await database;
    return db.query(
      tableFlashcards,
      where: 'unit_id = ?',
      whereArgs: <Object?>[unitId],
      orderBy: 'id',
    );
  }

  // ─────────────── الاستعلامات الديناميكية (Smart Filtering) ───────────────

  /// بطاقات بفلترة ديناميكية وترتيب ذكي — قلب بنك البطاقات.
  ///
  /// - [specialty]: التخصص السريري (v20) — null = كل التخصصات.
  /// - [system]: رمز الجهاز (cardiovascular, ...) — null = كل الأجهزة.
  /// - [lectureId]: محاضرة محددة داخل الجهاز — null = كل المحاضرات.
  /// - [isRandom]: false (افتراضي) = ترتيب المنهج: order_index المحاضرة
  ///   ثم ترتيب البطاقة داخلها (id). true = ORDER BY RANDOM() خلط كامل.
  /// - [limit]: سقف عدد النتائج (null = بلا سقف).
  ///
  /// كل الشروط مركّبة بمعاملات مربوطة (؟) — لا تركيب نصي للقيم.
  Future<List<Map<String, Object?>>> getFlashcards({
    String? specialty,
    String? system,
    String? lectureId,
    bool isRandom = false,
    int? limit,
  }) async {
    final Database db = await database;

    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];

    if (specialty != null) {
      where.add('u.specialty = ?');
      args.add(specialty);
    }
    if (lectureId != null) {
      where.add('f.unit_id = ?');
      args.add(lectureId);
    } else if (system != null) {
      where.add('u.system = ?');
      args.add(system);
    }

    final String whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final String orderSql = isRandom ? 'RANDOM()' : 'u.order_index, u.id, f.id';
    final String limitSql = limit == null ? '' : 'LIMIT $limit';

    return db.rawQuery('''
      SELECT f.*, u.title AS unit_title
      FROM $tableFlashcards f
      INNER JOIN $tableUnits u ON u.id = f.unit_id
      $whereSql
      ORDER BY $orderSql
      $limitSql
    ''', args);
  }

  /// أسئلة MCQ بنفس عقد الفلترة الديناميكية — لبنك الأسئلة.
  Future<List<Map<String, Object?>>> getMcqs({
    String? specialty,
    String? system,
    String? lectureId,
    bool isRandom = false,
    int? limit,
  }) async {
    final Database db = await database;

    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];

    if (specialty != null) {
      where.add('u.specialty = ?');
      args.add(specialty);
    }
    if (lectureId != null) {
      where.add('m.unit_id = ?');
      args.add(lectureId);
    } else if (system != null) {
      where.add('u.system = ?');
      args.add(system);
    }

    final String whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final String orderSql = isRandom ? 'RANDOM()' : 'u.order_index, u.id, m.id';
    final String limitSql = limit == null ? '' : 'LIMIT $limit';

    return db.rawQuery('''
      SELECT m.*
      FROM $tableMcqBank m
      INNER JOIN $tableUnits u ON u.id = m.unit_id
      $whereSql
      ORDER BY $orderSql
      $limitSql
    ''', args);
  }

  /// أسئلة MCQ لوحدة مرجّحة بإشارة قناة التدفق (قاعدة الـ 85%).
  ///
  /// [signal] من FlowChannelController — يعاد ترتيب الأسئلة داخل
  /// الوحدة حسب الصعوبة: harder = advanced أولاً، easier = core أولاً،
  /// stay = الترتيب الطبيعي. **بلا هجرة** — يعمل على عمود difficulty
  /// الموجود منذ v14؛ الجرعة «تحس» بالصعوبة ولا تعلنها.
  Future<List<Map<String, Object?>>> getMcqsForUnitAdaptive(
    String unitId,
    String difficultyWeightSql,
  ) async {
    final Database db = await database;
    return db.rawQuery(
      '''
      SELECT * FROM $tableMcqBank
      WHERE unit_id = ?
      ORDER BY $difficultyWeightSql id
    ''',
      <Object?>[unitId],
    );
  }

  /// الحالات السريرية بنفس عقد الفلترة الديناميكية.
  Future<List<Map<String, Object?>>> getCases({
    String? specialty,
    String? system,
    String? lectureId,
    bool isRandom = false,
    int? limit,
  }) async {
    final Database db = await database;

    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];

    if (specialty != null) {
      where.add('u.specialty = ?');
      args.add(specialty);
    }
    if (lectureId != null) {
      where.add('c.unit_id = ?');
      args.add(lectureId);
    } else if (system != null) {
      where.add('u.system = ?');
      args.add(system);
    }

    final String whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final String orderSql =
        isRandom ? 'RANDOM()' : 'u.order_index, u.id, c.order_index, c.id';
    final String limitSql = limit == null ? '' : 'LIMIT $limit';

    return db.rawQuery('''
      SELECT c.*
      FROM $tableClinicalCases c
      INNER JOIN $tableUnits u ON u.id = c.unit_id
      $whereSql
      ORDER BY $orderSql
      $limitSql
    ''', args);
  }

  /// **المراجعة العشوائية المدروسة** — بطاقات عشوائية من المحاضرات
  /// التي **دُرست فعلاً** فقط (لها سجل أي نشاط في user_progress:
  /// جلسة بطاقات/أسئلة/تقييم/حالة — أي بدأها المستخدم).
  ///
  /// الربط عبر EXISTS بدل JOIN — يضمن عدم تكرار البطاقة إذا كانت
  /// المحاضرة عليها عدة سجلات تقدم.
  Future<List<Map<String, Object?>>> getStudiedFlashcards({
    String? specialty,
    String? system,
    int? limit,
  }) async {
    final Database db = await database;

    final List<String> where = <String>[
      // المحاضرة لها أي سجل تقدم مستخدم (flashcard_set/drill).
      '''
      EXISTS (
        SELECT 1 FROM $tableUserProgress p
        WHERE (p.item_type = 'flashcard_set' AND p.item_id = f.unit_id)
           OR (p.item_type = 'drill'
               AND (p.item_id = 'mcq-' || f.unit_id
                    OR p.item_id = 'assess-' || f.unit_id))
      )
      ''',
    ];
    final List<Object?> args = <Object?>[];

    if (specialty != null) {
      where.add('u.specialty = ?');
      args.add(specialty);
    }
    if (system != null) {
      where.add('u.system = ?');
      args.add(system);
    }

    final String limitSql = limit == null ? '' : 'LIMIT $limit';

    return db.rawQuery('''
      SELECT f.*
      FROM $tableFlashcards f
      INNER JOIN $tableUnits u ON u.id = f.unit_id
      WHERE ${where.join(' AND ')}
      ORDER BY RANDOM()
      $limitSql
    ''', args);
  }

  /// وحدات (محاضرات) بفلترة الجهاز — لتغذية القائمة المنسدلة
  /// الثانية في لوحة التحكم (محاضرات الجهاز المختار فقط).
  /// [specialty] (v20): حصر الجهاز داخل تخصص سريري واحد.
  Future<List<Map<String, Object?>>> getUnitsBySystem(
    String? system, {
    String? specialty,
  }) async {
    final Database db = await database;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (system != null) {
      where.add('system = ?');
      args.add(system);
    }
    if (specialty != null) {
      where.add('specialty = ?');
      args.add(specialty);
    }
    return db.query(
      tableUnits,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'order_index, id',
    );
  }

  /// الأجهزة الموجودة فعلاً في المحتوى (لأجهزة بلا محاضرات فارغة
  /// في القائمة المنسدلة الأولى). [specialty] (v20): أجهزة تخصص واحد.
  Future<List<String>> getDistinctSystems({String? specialty}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows =
        specialty == null
            ? await db.rawQuery(
              'SELECT DISTINCT system FROM $tableUnits ORDER BY system',
            )
            : await db.rawQuery(
              'SELECT DISTINCT system FROM $tableUnits '
              'WHERE specialty = ? ORDER BY system',
              <Object?>[specialty],
            );
    return <String>[
      for (final Map<String, Object?> r in rows) r['system']! as String,
    ];
  }

  Future<Map<String, Object?>?> getFlashcardById(String cardId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableFlashcards,
      where: 'id = ?',
      whereArgs: <Object?>[cardId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// بحث محلي في البطاقات (السؤال أو الجواب).
  Future<List<Map<String, Object?>>> searchFlashcards(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return <Map<String, Object?>>[];
    final String q = '%$trimmed%';
    final Database db = await database;
    return db.query(
      tableFlashcards,
      where: 'front_text LIKE ? OR back_text LIKE ?',
      whereArgs: <Object?>[q, q],
      limit: 50,
    );
  }

  Future<void> insertFlashcard(Map<String, Object?> card) async {
    final Database db = await database;
    await db.insert(
      tableFlashcards,
      card,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ─────────────────── بنك أسئلة MCQ ───────────────────

  Future<List<Map<String, Object?>>> getMcqsForUnit(String unitId) async {
    final Database db = await database;
    return db.query(
      tableMcqBank,
      where: 'unit_id = ?',
      whereArgs: <Object?>[unitId],
      orderBy: 'id',
    );
  }

  Future<Map<String, Object?>?> getMcqById(String mcqId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableMcqBank,
      where: 'id = ?',
      whereArgs: <Object?>[mcqId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> insertMcq(Map<String, Object?> mcq) async {
    final Database db = await database;
    await db.insert(
      tableMcqBank,
      mcq,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ─────────────────── الحالات السريرية ───────────────────

  Future<List<Map<String, Object?>>> getCasesForUnit(String unitId) async {
    final Database db = await database;
    return db.query(
      tableClinicalCases,
      where: 'unit_id = ?',
      whereArgs: <Object?>[unitId],
      orderBy: 'order_index',
    );
  }

  Future<Map<String, Object?>?> getCaseById(String caseId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableClinicalCases,
      where: 'id = ?',
      whereArgs: <Object?>[caseId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> getStepsForCase(String caseId) async {
    final Database db = await database;
    return db.query(
      tableClinicalCaseSteps,
      where: 'case_id = ?',
      whereArgs: <Object?>[caseId],
      orderBy: 'step_index',
    );
  }

  Future<void> insertClinicalCase(Map<String, Object?> caseRow) async {
    final Database db = await database;
    await db.insert(
      tableClinicalCases,
      caseRow,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> insertCaseStep(Map<String, Object?> step) async {
    final Database db = await database;
    await db.insert(
      tableClinicalCaseSteps,
      step,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ─────────────────── نقاط الخبرة (xp_events) ───────────────────

  /// يسجّل حدث نقاط خبرة (XP) واحداً في سجل التدفق append-only.
  Future<void> addXpEvent({
    required XpEventKind kind,
    String? refId,
    required int xp,
  }) async {
    final Database db = await database;
    await db.insert(tableXpEvents, <String, Object?>{
      'kind': xpEventKindToCode(kind),
      'ref_id': refId,
      'xp': xp,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// إجمالي نقاط الخبرة التراكمية (0 إن كان السجل فارغاً).
  Future<int> sumXp() async {
    final Database db = await database;
    final int? result = Sqflite.firstIntValue(
      await db.rawQuery('SELECT SUM(xp) FROM $tableXpEvents'),
    );
    return result ?? 0;
  }

  /// أحداث الخبرة منذ لحظة زمنية (ISO UTC) — للإحصاءات الزمنية.
  Future<List<Map<String, Object?>>> xpEventsSince(String isoUtc) async {
    final Database db = await database;
    return db.query(
      tableXpEvents,
      where: 'created_at >= ?',
      whereArgs: <Object?>[isoUtc],
      orderBy: 'created_at DESC',
    );
  }

  /// إدراج حدث خبرة بطابع زمني صريح — أداة اختبار فقط.
  @visibleForTesting
  Future<void> dbInsertXpEventForTest({
    required XpEventKind kind,
    required int xp,
    required String createdAtIso,
    String? refId,
  }) async {
    final Database db = await database;
    await db.insert(tableXpEvents, <String, Object?>{
      'kind': xpEventKindToCode(kind),
      'ref_id': refId,
      'xp': xp,
      'created_at': createdAtIso,
    });
  }

  /// هل حصل المتعلم على مكافأة السلسلة اليوم؟
  Future<bool> hasStreakBonusToday() async {
    final Database db = await database;
    final String today = _utcDateToday();
    final int? result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $tableXpEvents '
        'WHERE substr(created_at, 1, 10) = ?',
        <Object?>[today],
      ),
    );
    return (result ?? 0) > 0;
  }

  /// يفتح شارة (idempotent).
  Future<void> unlockBadge(String badgeId) async {
    final Database db = await database;
    await db.insert(tableUnlockedBadges, <String, Object?>{
      'badge_id': badgeId,
      'unlocked_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// معرفات كل الشارات المفتوحة سابقاً.
  Future<Set<String>> getUnlockedBadgeIds() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableUnlockedBadges,
      columns: <String>['badge_id'],
    );
    return <String>{
      for (final Map<String, Object?> row in rows) row['badge_id']! as String,
    };
  }

  String _utcDateToday() =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  /// يمنح مكافأة السلسلة اليومية (+10 XP) مرة واحدة يومياً.
  Future<void> grantDailyStreakBonus() async {
    try {
      if (await hasStreakBonusToday()) return;
      await addXpEvent(
        kind: XpEventKind.streak,
        refId: _utcDateToday(),
        xp: 10,
      );
    } catch (_) {
      // صمت مقصود — المكافأة غير حرجة.
    }
  }

  /// يقيّم كل تعريفات الشارات ويفتح المستحق منها.
  Future<List<String>> unlockEarnedBadges() async {
    try {
      final MotivationSnapshot snapshot = await MotivationRepository.snapshot();
      final List<String> newlyEarned =
          snapshot.newlyEarned().map((BadgeDef badge) => badge.id).toList();
      for (final String badgeId in newlyEarned) {
        await unlockBadge(badgeId);
      }
      return newlyEarned;
    } catch (_) {
      return const <String>[];
    }
  }

  /// ─────────────── تجميع كتابات نهاية الجلسة (Batching) ───────────────
  ///
  /// كل كتابات ختام جلسة تدريب في **معاملة واحدة**: سجل الإجابات +
  /// علامة التقدم + XP التقييم (اختياري) + مكافأة السلسلة + الشارات.
  /// ذرّي: إما تُكتب كلها أو لا شيء — ولا فتح معاملة لكل استعلام.
  ///
  /// يعيد معرفات الشارات المفتوحة حديثاً (لأحداث الاحتفال).
  Future<List<String>> finalizeSession({
    List<Correction> corrections = const <Correction>[],
    UserProgress? progress,
    XpEventKind? bonusKind,
    String? bonusRefId,
    int bonusXp = 0,
  }) async {
    final Database db = await database;
    final List<String> newBadges = <String>[];

    await db.transaction((Transaction txn) async {
      final Batch batch = txn.batch();

      // سجل الإجابات دفعة واحدة.
      for (final Correction correction in corrections) {
        batch.insert(tableCorrections, correction.toMap());
      }

      // علامة التقدم (UPSERT يدوي داخل المعاملة).
      if (progress != null) {
        final Map<String, Object?> map = progress.toMap()..remove('id');
        batch.update(
          tableUserProgress,
          <String, Object?>{
            'status': map['status'],
            'score': map['score'],
            'times_reviewed': map['times_reviewed'],
            'last_practiced_at': map['last_practiced_at'],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'item_type = ? AND item_id = ?',
          whereArgs: <Object?>[
            progressItemTypeToCode(progress.itemType),
            progress.itemId,
          ],
        );
        // INSERT OR REPLACE semantics عبر upsert يدوي: ندرج بعد
        // التحديث — الصف الموجود حُدّث أعلاه؛ الجديد يُدرج الآن.
        // ConflictAlgorithm.ignore يمنع التكرار إن سبق التحديث صفاً.
        batch.insert(
          tableUserProgress,
          map,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // مكافأة اجتياز التقييم (اختيارية).
      if (bonusKind != null && bonusXp > 0) {
        batch.insert(tableXpEvents, <String, Object?>{
          'kind': xpEventKindToCode(bonusKind),
          'ref_id': bonusRefId,
          'xp': bonusXp,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      // مكافأة السلسلة اليومية — مرة واحدة يومياً (فحص ثم إدراج
      // داخل نفس المعاملة: التزامن محفوظ بفتح المعاملة).
      final String today = _utcDateToday();
      final int? already = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM $tableXpEvents '
          'WHERE substr(created_at, 1, 10) = ? AND kind = ?',
          <Object?>[today, xpEventKindToCode(XpEventKind.streak)],
        ),
      );
      if ((already ?? 0) == 0) {
        batch.insert(tableXpEvents, <String, Object?>{
          'kind': xpEventKindToCode(XpEventKind.streak),
          'ref_id': today,
          'xp': 10,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      await batch.commit(noResult: true);
    });

    // الشارات تُقيّم بعد نجاح المعاملة (تعتمد قراءة القرارات) —
    // تُعاد لتغذية أحداث الاحتفال.
    try {
      final MotivationSnapshot snapshot = await MotivationRepository.snapshot();
      newBadges.addAll(
        snapshot.newlyEarned().map((BadgeDef badge) => badge.id),
      );
      for (final String badgeId in newBadges) {
        await unlockBadge(badgeId);
      }
    } catch (_) {
      // الشارات غير حرجة — لا تُسقط الجلسة.
    }
    return newBadges;
  }

  // ─────────────── استعلامات مساعدة (قراءة) ───────────────

  /// عدد عناصر مكتملة لنوع واحد من جدول التقدم.
  Future<int> countCompletedByType(ProgressItemType type) async {
    final Database db = await database;
    final int? result = Sqflite.firstIntValue(
      await db.query(
        tableUserProgress,
        columns: <String>['COUNT(*) AS c'],
        where: 'item_type = ? AND status = ?',
        whereArgs: <Object?>[
          progressItemTypeToCode(type),
          progressStatusToCode(ProgressStatus.completed),
        ],
      ),
    );
    return result ?? 0;
  }

  /// عدّ عام من استعلام SELECT COUNT(*) خام بمعاملات مربوطة.
  Future<int> rawCount(String sql, [List<Object?>? args]) async {
    final Database db = await database;
    final int? result = Sqflite.firstIntValue(await db.rawQuery(sql, args));
    return result ?? 0;
  }

  /// استعلام خام عام بمعاملات مربوطة.
  Future<List<Map<String, Object?>>> rawQueryParameterized(
    String sql, [
    List<Object?>? args,
  ]) async {
    final Database db = await database;
    return db.rawQuery(sql, args);
  }

  // ─────────────────────── تقدم المستخدم (UPSERT يدوي) ───────────────────────

  /// يُنشئ أو يحدّث سطر التقدم لعنصر واحد في عملية ذرّية واحدة.
  Future<void> upsertProgress(UserProgress progress) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      final Map<String, Object?> map = progress.toMap()..remove('id');

      final int updated = await txn.update(
        tableUserProgress,
        <String, Object?>{
          'status': map['status'],
          'score': map['score'],
          'times_reviewed': map['times_reviewed'],
          'last_practiced_at': map['last_practiced_at'],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'item_type = ? AND item_id = ?',
        whereArgs: <Object?>[
          progressItemTypeToCode(progress.itemType),
          progress.itemId,
        ],
      );

      if (updated == 0) {
        await txn.insert(tableUserProgress, map);
      }
    });
  }

  /// يجلب حالة تقدم عنصر واحد أو null إن لم يبدأ بعد.
  Future<UserProgress?> getProgress(
    ProgressItemType itemType,
    String itemId,
  ) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableUserProgress,
      where: 'item_type = ? AND item_id = ?',
      whereArgs: <Object?>[progressItemTypeToCode(itemType), itemId],
      limit: 1,
    );
    return rows.isEmpty ? null : UserProgress.fromMap(rows.first);
  }

  // ─────────────────────── سجل الإجابات ───────────────────────

  /// يسجّل محاولة إجابة واحدة (لتحليل الأخطاء).
  Future<void> insertCorrection(Correction correction) async {
    final Database db = await database;
    await db.insert(tableCorrections, correction.toMap());
  }

  /// يسجّل مجموعة محاولات دفعة واحدة.
  Future<void> insertCorrections(List<Correction> corrections) async {
    if (corrections.isEmpty) return;
    final Database db = await database;
    final Batch batch = db.batch();
    for (final Correction correction in corrections) {
      batch.insert(tableCorrections, correction.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// إحصاء الأخطاء المجمعة حسب نوعها.
  Future<Map<MistakeType, int>> mistakeCounts({String? drillId}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableCorrections,
      columns: <String>['mistake_type', 'COUNT(*) AS c'],
      where: 'is_correct = 0${drillId == null ? '' : ' AND drill_id = ?'}',
      whereArgs: drillId == null ? null : <Object?>[drillId],
      groupBy: 'mistake_type',
    );
    return <MistakeType, int>{
      for (final Map<String, Object?> row in rows)
        mistakeTypeFromCode(row['mistake_type'] as String? ?? 'wrong'):
            row['c']! as int,
    };
  }

  /// يجلب أسوأ الأسئلة (الأكثر خطأً) مع عدد مرات الخطأ.
  Future<List<MapEntry<String, int>>> weakestQuestions(
    String drillId, {
    int limit = 10,
  }) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT question_id, COUNT(*) AS c FROM $tableCorrections '
      'WHERE drill_id = ? AND is_correct = 0 '
      'GROUP BY question_id ORDER BY c DESC, question_id ASC LIMIT ?',
      <Object?>[drillId, limit],
    );
    return <MapEntry<String, int>>[
      for (final Map<String, Object?> row in rows)
        MapEntry<String, int>(row['question_id']! as String, row['c']! as int),
    ];
  }

  /// آخر محاولة خاطئة لكل سؤال لجلسة واحدة.
  Future<List<Map<String, Object?>>> latestWrongAttempts(
    String drillId, {
    int limit = 10,
  }) async {
    final Database db = await database;
    return db.rawQuery(
      'SELECT question_id, user_answer, correct_answer, mistake_type, '
      'MAX(attempted_at) AS attempted_at FROM $tableCorrections '
      'WHERE drill_id = ? AND is_correct = 0 '
      'GROUP BY question_id ORDER BY attempted_at DESC LIMIT ?',
      <Object?>[drillId, limit],
    );
  }

  // ─────────────────── محرّك القراءة العميقة (v15) ───────────────────

  /// يسجّل (أو يحدّث) إتمام قراءة شرح — يرجع عدد القراءات السابق.
  ///
  /// - `readCount` القيمة السابقة (0 = قراءة أولى ← المراسي مفعّلة).
  /// - `sectionsJson`: خريطة {sectionIndex: dwellSeconds} لأزمنة
  ///   البقاء (تغذي كاشف التصفح/التصارع في المرحلة القادمة).
  /// - `completed`: هل أُتمت كل الأقسام (وصل زر التالي لآخر لقطة).
  Future<int> recordConceptRead({
    required String conceptId,
    required bool completed,
    Map<String, int>? sectionDwellSeconds,
  }) async {
    final Database db = await database;
    final String now = DateTime.now().toUtc().toIso8601String();

    int previousReads = 0;
    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        tableConceptReads,
        where: 'concept_id = ?',
        whereArgs: <Object?>[conceptId],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert(tableConceptReads, <String, Object?>{
          'concept_id': conceptId,
          'read_count': 1,
          'completed': completed ? 1 : 0,
          'last_read_at': now,
          'sections_json':
              sectionDwellSeconds == null
                  ? null
                  : jsonEncodeSorted(sectionDwellSeconds),
        });
      } else {
        previousReads = rows.first['read_count']! as int;
        await txn.update(
          tableConceptReads,
          <String, Object?>{
            'read_count': previousReads + 1,
            'completed':
                (rows.first['completed']! as int == 1 || completed) ? 1 : 0,
            'last_read_at': now,
            'sections_json':
                sectionDwellSeconds == null
                    ? rows.first['sections_json']
                    : jsonEncodeSorted(sectionDwellSeconds),
          },
          where: 'concept_id = ?',
          whereArgs: <Object?>[conceptId],
        );
      }
    });
    return previousReads;
  }

  /// سجل قراءة شرح واحد (null = لم يُقرأ بعد).
  Future<Map<String, Object?>?> getConceptRead(String conceptId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableConceptReads,
      where: 'concept_id = ?',
      whereArgs: <Object?>[conceptId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// عدد مرات قراءة شرح (0 = أول قراءة).
  Future<int> conceptReadCount(String conceptId) async {
    final Map<String, Object?>? row = await getConceptRead(conceptId);
    return (row?['read_count'] as int?) ?? 0;
  }

  /// هل اجتزت بوابة هذا الشرح من قبل؟ (تُتخطى في الزيارات التالية).
  Future<bool> conceptGatePassed(String conceptId) async {
    final Map<String, Object?>? row = await getConceptRead(conceptId);
    return (row?['gate_passed'] as int?) == 1;
  }

  /// وسْم بوابة الشرح مجتازة (بعد إجابة صحيحة من أول مرة أو أي إجابة —
  /// القرار في الشاشة؛ هنا مجرد تسجيل).
  Future<void> markGatePassed(String conceptId) async {
    final Database db = await database;
    final String now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((Transaction txn) async {
      final int updated = await txn.update(
        tableConceptReads,
        <String, Object?>{'gate_passed': 1},
        where: 'concept_id = ?',
        whereArgs: <Object?>[conceptId],
      );
      if (updated == 0) {
        await txn.insert(tableConceptReads, <String, Object?>{
          'concept_id': conceptId,
          'read_count': 0,
          'completed': 0,
          'gate_passed': 1,
          'last_read_at': now,
        });
      }
    });
  }

  /// سؤال بوابة الشرح: أول MCQ مرتبط بالمفهوم (concept_id) غير مستهلك —
  /// الصدفة المعمارية الذهبية: الحقل موجود منذ v14 بصفر تأليف محتوى.
  Future<Map<String, Object?>?> getGateMcqForConcept(String conceptId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableMcqBank,
      where: 'concept_id = ?',
      whereArgs: <Object?>[conceptId],
      orderBy: 'id',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// كل أسئلة المفهوم (لنقاط الاعتراض داخل القارئ — المقترح B).
  Future<List<Map<String, Object?>>> getMcqsForConcept(String conceptId) async {
    final Database db = await database;
    return db.query(
      tableMcqBank,
      where: 'concept_id = ?',
      whereArgs: <Object?>[conceptId],
      orderBy: 'id',
    );
  }

  /// يفتح جلسة تدفق جديدة ويرجّع معرّفها.
  Future<int> startFlowSession({required String kind, String? refId}) async {
    final Database db = await database;
    return db.insert(tableFlowSessions, <String, Object?>{
      'kind': kind,
      'ref_id': refId,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'focused_seconds': 0,
    });
  }

  /// ينهي جلسة تدفق بكتابة زمن البقاء المركّز بالثواني.
  Future<void> endFlowSession(int sessionId, int focusedSeconds) async {
    final Database db = await database;
    await db.update(
      tableFlowSessions,
      <String, Object?>{
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'focused_seconds': focusedSeconds < 0 ? 0 : focusedSeconds,
      },
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
  }

  /// مجموع دقائق التركيز المنجزة في يوم (UTC) — مقياس الشمال.
  Future<int> focusedSecondsOnDay(String utcDate) async {
    final Database db = await database;
    final int? result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT SUM(focused_seconds) FROM $tableFlowSessions '
        'WHERE substr(started_at, 1, 10) = ? AND ended_at IS NOT NULL',
        <Object?>[utcDate],
      ),
    );
    return result ?? 0;
  }

  /// يسجّل إجابة بدرجة ثقة (قبلة الثقة — المقترح A لاحقاً).
  Future<void> logConfidence({
    required String questionId,
    required int confidence,
    required bool wasCorrect,
  }) async {
    final Database db = await database;
    await db.insert(tableConfidenceLog, <String, Object?>{
      'question_id': questionId,
      'confidence': confidence.clamp(0, 2),
      'was_correct': wasCorrect ? 1 : 0,
      'answered_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// مجموع دقائق التركيز لآخر [days] يوماً (لشاشة «دقائق التركيز»).
  /// يرجع قائمة {date, seconds} تصاعدية.
  Future<List<MapEntry<String, int>>> focusedMinutesRecent(int days) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT substr(started_at, 1, 10) AS day,
             CAST(SUM(focused_seconds) / 60 AS INTEGER) AS minutes
      FROM $tableFlowSessions
      WHERE ended_at IS NOT NULL
        AND started_at >= ?
      GROUP BY day
      ORDER BY day ASC
    ''',
      <Object?>[
        DateTime.now()
            .toUtc()
            .subtract(Duration(days: days - 1))
            .toIso8601String()
            .substring(0, 10),
      ],
    );
    return <MapEntry<String, int>>[
      for (final Map<String, Object?> r in rows)
        MapEntry<String, int>(r['day']! as String, r['minutes']! as int),
    ];
  }

  // ─────────────── الإحصاءات اليومية لزمن الدراسة (v21) ───────────────

  /// يضيف زمناً (ثواني) إلى إحصاء اليوم الحالي (UTC) — تجميع idempotent.
  ///
  /// إذا لم يوجد صف لهذا اليوم ينشئه بالزمن المعطى؛ وإلا يضيف إلى
  /// قيمته. يُستدعى من مدير دورة حياة التطبيق عند كل خروج/إيقاف.
  Future<void> recordStudySeconds(int seconds) async {
    if (seconds <= 0) return;
    final Database db = await database;
    final String today = DateTime.now().toUtc().toIso8601String().substring(
      0,
      10,
    );

    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        tableDailyStats,
        where: 'date = ?',
        whereArgs: <Object?>[today],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert(tableDailyStats, <String, Object?>{
          'date': today,
          'study_seconds': seconds,
        });
      } else {
        final int existing = rows.first['study_seconds']! as int;
        await txn.update(
          tableDailyStats,
          <String, Object?>{'study_seconds': existing + seconds},
          where: 'date = ?',
          whereArgs: <Object?>[today],
        );
      }
    });
  }

  /// زمن الدراسة (ثواني) ليوم محدد (UTC) — 0 لليوم الغائب.
  Future<int> getStudySecondsOnDay(String utcDate) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableDailyStats,
      columns: <String>['study_seconds'],
      where: 'date = ?',
      whereArgs: <Object?>[utcDate],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['study_seconds']! as int);
  }

  /// زمن الدراسة بالثواني لآخر [days] يوماً (تصاعدياً) — لإطعام تقويم
  /// النشاط بالمدد اليومية.
  Future<List<MapEntry<String, int>>> getStudySecondsRecent(int days) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT date AS day, study_seconds AS seconds
      FROM $tableDailyStats
      WHERE date >= ?
      ORDER BY day ASC
    ''',
      <Object?>[
        DateTime.now()
            .toUtc()
            .subtract(Duration(days: days - 1))
            .toIso8601String()
            .substring(0, 10),
      ],
    );
    return <MapEntry<String, int>>[
      for (final Map<String, Object?> r in rows)
        MapEntry<String, int>(r['day']! as String, r['seconds']! as int),
    ];
  }

  // ─────────── الملاحظات المضمّنة في نص الشروحات (v22) ───────────

  /// يضيف ملاحظة داخلية مرتبطة بنص محدَّد داخل شرح (concept).
  ///
  /// [selectedText] النص الحرفي الذي حدّده المستخدم، [personalNote]
  /// ملاحظته الشخصية. [colorCode] اختياري (مستقبلي لألوان التمييز).
  /// يرجع معرف الصف الجديد.
  Future<int> addInlineNote({
    required String conceptId,
    required String selectedText,
    required int startIndex,
    required int endIndex,
    required String personalNote,
    String? colorCode,
  }) async {
    final Database db = await database;
    return db.insert(tableInlineNotes, <String, Object?>{
      'concept_id': conceptId,
      'selected_text': selectedText,
      'start_index': startIndex,
      'end_index': endIndex,
      'personal_note': personalNote,
      'color_code': colorCode,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// تحديث نص الملاحظة الشخصية لصفّ موجود (يتحدَّد بمعرفه).
  Future<void> updateInlineNote({
    required int id,
    required String personalNote,
  }) async {
    final Database db = await database;
    await db.update(
      tableInlineNotes,
      <String, Object?>{'personal_note': personalNote},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// حذف ملاحظة داخلية بمعرفها.
  Future<void> deleteInlineNote(int id) async {
    final Database db = await database;
    await db.delete(
      tableInlineNotes,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// كل الملاحظات المضمّنة لشرح معيّن (بترتيب الإضافة).
  Future<List<Map<String, Object?>>> getInlineNotesForConcept(
    String conceptId,
  ) async {
    final Database db = await database;
    return db.query(
      tableInlineNotes,
      where: 'concept_id = ?',
      whereArgs: <Object?>[conceptId],
      orderBy: 'id ASC',
    );
  }

  /// متوسط زمن البقاء التاريخي على الأقسام (ثواني) عبر كل الشروح
  /// المقروءة — خط الأساس لكاشف التصفح/التصارع (المقترح D).
  Future<double> averageSectionDwellSeconds() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      tableConceptReads,
      columns: <String>['sections_json'],
      where: 'sections_json IS NOT NULL',
    );
    final List<int> all = <int>[];
    for (final Map<String, Object?> row in rows) {
      final String? raw = row['sections_json'] as String?;
      if (raw == null) continue;
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        for (final Object? v in decoded.values) {
          if (v is num && v > 0) all.add(v.toInt());
        }
      } catch (_) {
        // سجل تالف — تجاهل.
      }
    }
    if (all.isEmpty) return 0;
    final int sum = all.reduce((int a, int b) => a + b);
    return sum / all.length;
  }

  /// شروح غير مكتملة القراءة (completed=0) — بناء «غوصة عميقة»
  /// (كتلة القراءة المتداخلة الأجهزة، المقترح D). ترتيب عشوائي
  /// لتوزيع الأجهزة، مع استبعاد الشروح المجتازة إن نُصب.
  Future<List<Map<String, Object?>>> getUnfinishedConcepts({
    int limit = 4,
    String? specialty,
    String? system,
  }) async {
    final Database db = await database;
    final String specialtyFilter = specialty != null ? 'AND u.specialty = ?' : '';
    final String systemFilter = system != null ? 'AND u.system = ?' : '';
    
    final List<Object?> args = <Object?>[];
    if (specialty != null) args.add(specialty);
    if (system != null) args.add(system);
    args.add(limit);

    return db.rawQuery(
      '''
      SELECT c.*, u.title AS unit_title, u.system AS unit_system, u.specialty AS unit_specialty
      FROM $tableConcepts c
      INNER JOIN $tableUnits u ON u.id = c.unit_id
      WHERE NOT EXISTS (
        SELECT 1 FROM $tableConceptReads r
        WHERE r.concept_id = c.id AND r.completed = 1
      )
      $specialtyFilter
      $systemFilter
      ORDER BY RANDOM()
      LIMIT ?
    ''',
      args,
    );
  }

  /// ترميز JSON بمفاتيح مرتبة — خرج حتمي قابل للاختبار.
  static String jsonEncodeSorted(Map<String, int> map) {
    final List<String> keys = map.keys.toList()..sort();
    final Map<String, int> sorted = <String, int>{
      for (final String k in keys) k: map[k]!,
    };
    return jsonEncode(sorted);
  }

  // ─────────────────── سجلات المرضى (Clinical History) ───────────────────

  /// إضافة سجل مريض جديد
  Future<int> insertPatientRecord(
    String patientAlias,
    String responsesJson,
  ) async {
    final Database db = await database;
    final String now = DateTime.now().toUtc().toIso8601String();
    return db.insert(tablePatientRecords, <String, Object?>{
      'patient_alias': patientAlias,
      'responses_json': responsesJson,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// جلب كل سجلات المرضى (مرتبة حسب الأحدث)
  Future<List<Map<String, Object?>>> getPatientRecords() async {
    final Database db = await database;
    return db.query(
      tablePatientRecords,
      orderBy: 'created_at DESC',
    );
  }

  /// تحديث سجل مريض موجود
  Future<int> updatePatientRecord(
    int id,
    String patientAlias,
    String responsesJson,
  ) async {
    final Database db = await database;
    final String now = DateTime.now().toUtc().toIso8601String();
    return db.update(
      tablePatientRecords,
      <String, Object?>{
        'patient_alias': patientAlias,
        'responses_json': responsesJson,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// حذف سجل مريض
  Future<int> deletePatientRecord(int id) async {
    final Database db = await database;
    return db.delete(
      tablePatientRecords,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ─────────────────────────── الصيانة ───────────────────────────

  /// يغلق الاتصال (للاختبارات).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// حذف القاعدة نهائياً — أداة تطوير فقط.
  Future<void> deleteDatabaseFile() async {
    await close();
    final String dirPath = await getDatabasesPath();
    await deleteDatabase(p.join(dirPath, databaseName));
  }
}
