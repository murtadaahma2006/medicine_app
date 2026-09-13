import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../core/profile/learner_profile.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../widgets/breath_gate.dart';
import '../widgets/concept_gate_sheet.dart';
import '../widgets/fixation_spans.dart';
import '../widgets/interception_sheet.dart';
import '../widgets/session_guard.dart';

/// ─────────────────────────────────────────────────────────────────────
/// قارئ الشروحات — نسخة «اللقطات» (Chunked Reading) — محرّك القراءة
/// العميقة. الأسبوعان 1+2+3 مدمجة:
///
/// - **بوابة الشرح** (أسبوع 2): قبل أول لقطة، سؤال MCQ من أسئلة
///   الشرح نفسه + مقياس ثقة. الخطأ يعلّم الأقسام التي تجيب السؤال
///   بإطار كهرماني + شارة «هنا كان خطؤك» — القراءة تصبح صيداً موجهاً.
///   الإجابة الصحيحة من أول مرة → وسم gate_passed (لا بوابة لاحقاً).
///   لا MCQ مرتبط؟ fallback: بطاقة مسح مسبق بمصطلحات key_terms.
/// - **نقاط الاعتراض** (أسبوع 2): كل لقطتين، شاشة استرجاع كاملة —
///   سؤال MCQ غير مستهلك من الشرح، أو سؤال check مدمج (عقد v2.1)،
///   أو استرجاع حر «لخّص بثلاث نقاط».
/// - **بوابة التنفس** (أسبوع 3): قبل أول لقطة.
/// - **حارس الجلسة** (أسبوع 3): محاولة الخروج المبكر تعرض بطاقة
///   الحقيقة (كم لقطة تبقت) — البقاء هو الفعل الكبير.
/// - **كاشف التصفح** (أسبوع 3): زمن لقطة أقل بكثير من متوسطك →
///   الاعتراضية التالية تُقدَّم فوراً («تثبّت — سؤال سريع»).
/// - الأسبوع 1 كما هو: لقطة/شاشة · زر التالي الكبير · Atkinson
///   18sp/1.7/460px/#E6E6E6 داكن · مراسي التثبيت (قراءة أولى فقط)
///   · أزمنة البقاء · جلسة تدفق · XP concept.
/// ─────────────────────────────────────────────────────────────────────
class ConceptReaderPage extends StatefulWidget {
  const ConceptReaderPage({required this.unitId, super.key});

  final String unitId;

  @override
  State<ConceptReaderPage> createState() => _ConceptReaderPageState();
}

/// لقطة عرض واحدة — قسم واحد من شرح واحد.
class _Shot {
  const _Shot({
    required this.conceptId,
    required this.conceptTitle,
    required this.conceptIndex,
    required this.conceptCount,
    required this.summaryAr,
    required this.heading,
    required this.body,
    required this.keyPoints,
    required this.keyTerms,
    required this.isConceptStart,
    required this.isLastShot,
    required this.sectionIndex,
    required this.check,
  });

  final String conceptId;
  final String conceptTitle;
  final int conceptIndex;
  final int conceptCount;
  final String? summaryAr;
  final String heading;
  final String body;
  final List<String> keyPoints;
  final List<Map<String, Object?>> keyTerms;
  final bool isConceptStart;
  final bool isLastShot;

  /// فهرس القسم داخل شرحه (0-based) — للتمييز الكهرماني.
  final int sectionIndex;

  /// سؤال check مدمج من sections_json (عقد v2.1) — null = لا يوجد.
  final Map<String, Object?>? check;
}

class _ConceptReaderPageState extends State<ConceptReaderPage> {
  bool _loading = true;
  String? _error;
  String _unitTitle = '';

  List<_Shot> _shots = <_Shot>[];
  int _index = 0;

  // أزمنة البقاء (ms) لكل لقطة — تُسجَّل عند كل «التالي».
  final Map<int, int> _dwellMs = <int, int>{};
  DateTime _shotStart = DateTime.now();

  // مراسي التثبيت.
  bool _anchorsEnabled = true;
  FixationStrength _anchorStrength = FixationStrength.standard;
  bool _isFirstRead = true;

  // البوابة (أسبوع 2).
  List<int> _gateWrongSections = const <int>[];
  String? _gateWrongConceptId;

  // الاعتراضيات (أسبوع 2): أسئلة MCQ غير مستهلكة لكل شرح.
  final Map<String, List<Map<String, Object?>>> _conceptMcqs =
      <String, List<Map<String, Object?>>>{};
  int _interceptsPassed = 0;
  int _interceptsCorrect = 0;

  // كاشف التصفح (أسبوع 3).
  double _baselineDwellSeconds = 0;
  bool _rushingDetected = false;

  // جلسة التدفق.
  int? _flowSessionId;
  DateTime _sessionStart = DateTime.now();
  bool _conceptXpGiven = false;

  // التثبيت الختامي (Recite) — آخر شرح.
  bool _finalReciteShown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final Map<String, Object?>? unit =
          await db.getUnitById(widget.unitId);
      final List<Map<String, Object?>> concepts =
          await db.getConceptsForUnit(widget.unitId);

      // إعدادات المراسي + خط الأساس.
      final bool anchors = await LearnerProfile.anchorsEnabled();
      final String strengthCode = await LearnerProfile.anchorStrengthCode();
      final double baseline = await db.averageSectionDwellSeconds();

      // بناء اللقطات + أسئلة الاعتراض لكل شرح.
      final List<_Shot> shots = <_Shot>[];
      for (int c = 0; c < concepts.length; c++) {
        final Map<String, Object?> concept = concepts[c];
        final String conceptId = concept['id']! as String;
        final List<Map<String, Object?>> sections =
            _decodeSections(concept['sections_json'] as String?);
        final List<Map<String, Object?>> keyTerms =
            _decodeKeyTerms(concept['key_terms_json'] as String?);

        // أسئلة الاعتراض: MCQ غير مستهلك من أسئلة الشرح — نسخة قابلة
        // للتعديل (نتيجة sqflite QueryResultSet للقراءة فقط وremoveAt
        // يفشل عليها بـ «Unsupported operation: read-only»).
        final List<Map<String, Object?>> conceptMcqs =
            await db.getMcqsForConcept(conceptId);
        if (conceptMcqs.isNotEmpty) {
          _conceptMcqs[conceptId] =
              List<Map<String, Object?>>.of(conceptMcqs);
        }

        if (sections.isEmpty) {
          shots.add(_Shot(
            conceptId: conceptId,
            conceptTitle: (concept['title'] as String?) ?? '',
            conceptIndex: c,
            conceptCount: concepts.length,
            summaryAr: concept['summary_ar'] as String?,
            heading: (concept['title'] as String?) ?? '',
            body: '',
            keyPoints: const <String>[],
            keyTerms: keyTerms,
            isConceptStart: true,
            isLastShot: c == concepts.length - 1,
            sectionIndex: 0,
            check: null,
          ));
          continue;
        }
        for (int s = 0; s < sections.length; s++) {
          shots.add(_Shot(
            conceptId: conceptId,
            conceptTitle: (concept['title'] as String?) ?? '',
            conceptIndex: c,
            conceptCount: concepts.length,
            summaryAr: s == 0 ? concept['summary_ar'] as String? : null,
            heading: (sections[s]['heading'] as String?) ?? '',
            body: (sections[s]['body_text'] as String?) ?? '',
            keyPoints: _keyPointsOf(sections[s]),
            keyTerms: s == sections.length - 1 ? keyTerms : const [],
            isConceptStart: s == 0,
            isLastShot:
                c == concepts.length - 1 && s == sections.length - 1,
            sectionIndex: s,
            check: _checkOf(sections[s]),
          ));
        }
      }

      // أول قراءة؟ (أي شرح في المحاضرة من قبل → إعادة قراءة).
      bool firstRead = true;
      if (shots.isNotEmpty) {
        final int reads = await db.conceptReadCount(shots.first.conceptId);
        firstRead = reads == 0;
      }

      if (!mounted) return;
      setState(() {
        _unitTitle = (unit?['title'] as String?) ?? '';
        _shots = shots;
        _anchorsEnabled = anchors;
        _anchorStrength = FixationStrength.fromCode(strengthCode);
        _isFirstRead = firstRead;
        _baselineDwellSeconds = baseline;
        _loading = false;
      });

      // بوابة التنفس (أسبوع 3) ثم بوابة الشرح (أسبوع 2).
      if (shots.isNotEmpty) {
        await _runBreathGate();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الشروحات.';
        _loading = false;
      });
    }
  }

  /// بوابة التنفس — 8 ثوان قبل أول لقطة (كلاهما يفتح جلسة التدفق).
  Future<void> _runBreathGate() async {
    await BreathGatePage.show(
      context,
      sessionTitle: 'جلسة قراءة — $_unitTitle',
      onReady: () {
        // فتح جلسة التدفق عند البدء الفعلي.
        _startFlowSession();
        _runConceptGate();
      },
    );
  }

  Future<void> _startFlowSession() async {
    try {
      _flowSessionId = await DatabaseHelper.instance.startFlowSession(
        kind: 'reading',
        refId: widget.unitId,
      );
      _sessionStart = DateTime.now();
      _shotStart = DateTime.now();
    } catch (_) {
      // صمت مقصود.
    }
  }

  /// بوابة الشرح الأول (أسبوع 2) — قبل أول لقطة.
  Future<void> _runConceptGate() async {
    if (_shots.isEmpty) return;
    final _Shot first = _shots.first;
    final DatabaseHelper db = DatabaseHelper.instance;

    // مجتازة من قبل؟ → افتح مباشرة.
    if (await db.conceptGatePassed(first.conceptId)) return;
    if (!mounted) return;

    final Map<String, Object?>? gateMcq =
        await db.getGateMcqForConcept(first.conceptId);

    if (gateMcq != null) {
      // بوابة MCQ + ثقة.
      if (!mounted) return;
      final Map<String, Object?>? result =
          await ConceptGateSheet.show(
        context,
        conceptTitle: first.conceptTitle,
        mcq: gateMcq,
      );
      if (result == null) return; // أُغلقت (isDismissible=false — نادر).
      final bool wasCorrect = result['was_correct'] == true;
      final List<int> focus =
          (result['focus_sections'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<num>()
              .map((num n) => n.toInt())
              .toList();
      if (!mounted) return;
      setState(() {
        if (!wasCorrect && focus.isNotEmpty) {
          _gateWrongSections = focus;
          _gateWrongConceptId = first.conceptId;
        }
      });
      // إجابة صحيحة من أول مرة → وسم البوابة (لا تظهر مجدداً).
      if (wasCorrect) {
        await db.markGatePassed(first.conceptId);
      }
      return;
    }

    // fallback: بطاقة مسح مسبق بمصطلحات key_terms (Advance Organizer).
    if (!mounted) return;
    await _showAdvanceOrganizer(first);
  }

  /// بطاقة المسح المسبق — مصطلحات الشرح لمدة لحظة قبل القراءة.
  Future<void> _showAdvanceOrganizer(_Shot shot) async {
    if (shot.keyTerms.isEmpty) return;
    final Brightness b = Theme.of(context).colorScheme.brightness;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface(b),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('مسح مسبق — مصطلحات ستقابلها',
                  style: AppType.cardTitle.copyWith(fontSize: 17)),
              const SizedBox(height: AppSpacing.sm),
              for (final Map<String, Object?> term in shot.keyTerms)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: Text(
                          (term['term'] as String?) ?? '',
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: AppType.body.copyWith(
                            fontFamily: AppType.focusFamily,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary(b),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 3,
                        child: Text(
                          (term['definition_ar'] as String?) ?? '',
                          style: AppType.body.copyWith(
                            fontSize: 12.5,
                            color: AppColors.textSecondary(b),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('ابدأ القراءة',
                      style:
                          AppType.body.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<Map<String, Object?>> _decodeSections(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, Object?>> _decodeKeyTerms(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<String> _keyPointsOf(Map<String, Object?> section) {
    final dynamic raw = section['key_points'];
    if (raw is! List) return const [];
    return raw.map((dynamic s) => s.toString()).toList();
  }

  static Map<String, Object?>? _checkOf(Map<String, Object?> section) {
    final dynamic raw = section['check'];
    if (raw is! Map) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  /// هل هذه اللقطة معلَّمة بإطار كهرماني (هنا كان خطؤك — أسبوع 2)؟
  bool _isGateWrong(_Shot shot) =>
      _gateWrongConceptId == shot.conceptId &&
      _gateWrongSections.contains(shot.sectionIndex);

  /// التقدم للقطة التالية — مع الاعتراضية كل لقطتين.
  Future<void> _next() async {
    final DateTime now = DateTime.now();
    final int dwell = now.difference(_shotStart).inMilliseconds;
    _dwellMs[_index] = dwell;
    _shotStart = now;

    // كاشف التصفح: زمن أقل بكثير من خط الأساس → تسارع الاعتراضية.
    if (_baselineDwellSeconds > 0) {
      final double seconds = dwell / 1000;
      if (seconds < _baselineDwellSeconds * 0.4) {
        _rushingDetected = true;
      } else {
        _rushingDetected = false;
      }
    }

    if (_index >= _shots.length - 1) {
      await _finish();
      return;
    }

    // ── نقطة الاعتراض: كل لقطتين (أو فوراً عند كشف التصفح) ──
    final bool dueIntercept = (_index + 1) % 2 == 0 || _rushingDetected;
    final bool isBoundary =
        _shots[_index].conceptId != _shots[_index + 1].conceptId;
    final bool lastOfConcept = _index + 1 < _shots.length &&
        _shots[_index].conceptId != _shots[_index + 1].conceptId;

    if (dueIntercept && !isBoundary) {
      await _runInterception();
    }

    // آخر لقطة من شرح وليست الأخيرة كلياً → تثبيت ختامي (Recite).
    if (lastOfConcept && _index + 1 < _shots.length) {
      await _runFinalRecite();
    }

    if (!mounted) return;
    setState(() => _index++);
  }

  /// نقطة الاعتراض (أسبوع 2): MCQ غير مستهلك > check مدمج > استرجاع حر.
  Future<void> _runInterception() async {
    final _Shot shot = _shots[_index];

    // (أ) سؤال check مدمج في القسم الحالي (عقد v2.1) — الأولوية.
    final Map<String, Object?>? check = shot.check;
    if (check != null) {
      final Map<String, Object?>? result = await _showIntercept(
        InterceptionSheet(
          source: InterceptionSource.check,
          prompt: (check['prompt'] as String?) ?? '',
          options: (check['options'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic s) => s.toString())
              .toList(),
          correctIndex: (check['correct_index'] as num?)?.toInt() ?? 0,
          explanationAr: check['explanation_ar'] as String?,
          freeKeyPoints: const <String>[],
        ),
      );
      _recordIntercept(result);
      return;
    }

    // (ب) MCQ غير مستهلك من أسئلة الشرح.
    final List<Map<String, Object?>>? pool = _conceptMcqs[shot.conceptId];
    if (pool != null && pool.isNotEmpty) {
      final Map<String, Object?> mcq = pool.removeAt(0);
      final Map<String, Object?>? result = await _showIntercept(
        InterceptionSheet(
          source: InterceptionSource.mcq,
          prompt: mcq['question_stem']! as String,
          options: _optionsOf(mcq),
          correctIndex: (mcq['correct_index'] as num?)?.toInt() ?? 0,
          explanationAr: mcq['explanation_ar']! as String,
          mcqId: mcq['id'] as String?,
          freeKeyPoints: const <String>[],
        ),
      );
      _recordIntercept(result);
      return;
    }

    // (ج) استرجاع حر — لخّص بثلاث نقاط ثم قارن.
    if (shot.keyPoints.isNotEmpty) {
      final Map<String, Object?>? result = await _showIntercept(
        InterceptionSheet(
          source: InterceptionSource.free,
          prompt: '',
          options: const <String>[],
          correctIndex: 0,
          freeKeyPoints: shot.keyPoints,
        ),
      );
      _recordIntercept(result, free: true);
    }
  }

  Future<Map<String, Object?>?> _showIntercept(Widget sheet) {
    return InterceptionSheet.show(context, sheet: sheet);
  }

  void _recordIntercept(Map<String, Object?>? result, {bool free = false}) {
    if (result == null) return;
    _interceptsPassed++;
    if (result['was_correct'] == true && !free) _interceptsCorrect++;
  }

  /// التثبيت الختامي (Recite — آخر شرح): لخّص بثلاث نقاط + المسرد.
  Future<void> _runFinalRecite() async {
    if (_finalReciteShown) return;
    final _Shot lastOfConcept = _shots[_index];
    if (lastOfConcept.keyPoints.isEmpty) return;
    _finalReciteShown = true;
    await _showIntercept(
      InterceptionSheet(
        source: InterceptionSource.free,
        prompt: '',
        options: const <String>[],
        correctIndex: 0,
        freeKeyPoints: lastOfConcept.keyPoints,
      ),
    );
  }

  static List<String> _optionsOf(Map<String, Object?> q) {
    try {
      final dynamic decoded = jsonDecode(q['options_json']! as String);
      if (decoded is List) {
        return decoded.map((dynamic s) => s.toString()).toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  /// إتمام القراءة: تسجيل concept_reads + إغلاق الجلسة + XP.
  Future<void> _finish() async {
    try {
      final DatabaseHelper db = DatabaseHelper.instance;

      final Map<String, int> dwellSeconds = <String, int>{
        for (final MapEntry<int, int> e in _dwellMs.entries)
          e.key.toString(): (e.value / 1000).round(),
      };

      final Set<String> seenConcepts = <String>{
        for (final _Shot s in _shots) s.conceptId,
      };
      for (final String conceptId in seenConcepts) {
        await db.recordConceptRead(
          conceptId: conceptId,
          completed: true,
          sectionDwellSeconds: dwellSeconds,
        );
      }

      // أهداف اليوم: إن كانت المحاضرة مثبتة وقد اكتملت قراءتها
      // كاملة (كل شروحها) → إلغاء التثبيت تلقائياً — الإتمام يُشتق
      // ديناميكياً في القاعدة فلا نكرر المنطق هنا.
      await db.unpinUnitIfCompleted(widget.unitId);

      if (_flowSessionId != null) {
        final int focused =
            DateTime.now().difference(_sessionStart).inSeconds;
        await db.endFlowSession(_flowSessionId!, focused);
      }

      if (!_conceptXpGiven && _shots.isNotEmpty) {
        _conceptXpGiven = true;
        await db.addXpEvent(
          kind: XpEventKind.concept,
          refId: widget.unitId,
          xp: 10,
        );
        await db.grantDailyStreakBonus();
      }
    } catch (_) {
      // صمت مقصود.
    }

    if (!mounted) return;
    // ملخص الاعتراضيات إن وُجدت — ثم إغلاق.
    if (_interceptsPassed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success(Brightness.light),
          content: Text(
            'أتممت الجلسة — $_interceptsPassed نقطة استرجاع'
            ' ($_interceptsCorrect صحيحة) 🌊',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    Navigator.of(context).pop();
  }

  /// خروج مبكر — حارس الجلسة أولاً (أسبوع 3) ثم تسجيل جزئي.
  Future<void> _exitEarly() async {
    // حارس: البقاء هو الافتراضي البصري.
    final bool stay = await SessionGuard.confirmStay(
      context,
      remaining: _shots.length - 1 - _index,
      unitLabel: _unitTitle,
    );
    if (stay) return;

    final DateTime now = DateTime.now();
    _dwellMs[_index] = now.difference(_shotStart).inMilliseconds;
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final Map<String, int> dwellSeconds = <String, int>{
        for (final MapEntry<int, int> e in _dwellMs.entries)
          e.key.toString(): (e.value / 1000).round(),
      };
      if (_shots.isNotEmpty) {
        await db.recordConceptRead(
          conceptId: _shots[_index.clamp(0, _shots.length - 1)].conceptId,
          completed: false,
          sectionDwellSeconds: dwellSeconds,
        );
      }
      if (_flowSessionId != null) {
        final int focused =
            DateTime.now().difference(_sessionStart).inSeconds;
        await db.endFlowSession(_flowSessionId!, focused);
      }
    } catch (_) {
      // صمت مقصود.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _exitEarly();
      },
      child: Scaffold(
        backgroundColor: AppColors.background(b),
        appBar: AppBar(
          backgroundColor: AppColors.background(b),
          title: Text(
            _unitTitle,
            textDirection: TextDirection.ltr,
            style: AppType.caption.copyWith(
                fontSize: 14, color: AppColors.textSecondary(b)),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'إنهاء القراءة',
            onPressed: _exitEarly,
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: _error!,
                    actionLabel: 'إعادة المحاولة',
                    onAction: _load,
                  )
                : _shots.isEmpty
                    ? const EmptyState(
                        icon: Icons.menu_book_rounded,
                        title: 'لا شروحات في هذه المحاضرة',
                        subtitle: 'ستظهر هنا متى توفر المحتوى',
                      )
                    : _buildShotView(context),
      ),
    );
  }

  Widget _buildShotView(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final _Shot shot = _shots[_index];
    final bool useAnchors = _anchorsEnabled && _isFirstRead;
    final bool isGateWrong = _isGateWrong(shot);

    return Column(
      children: <Widget>[
        // ── شريط التقدم الرفيع ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Row(
            children: <Widget>[
              Text(
                '${_index + 1}/${_shots.length}',
                textDirection: TextDirection.ltr,
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary(b),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _shots.length,
                    minHeight: 3,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── اللقطة ──
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AnimatedSwitcher(
                duration: AppMotion.scaled(context, AppMotion.transition),
                switchInCurve: AppMotion.ease,
                switchOutCurve: AppMotion.out,
                transitionBuilder: (Widget child, Animation<double> anim) =>
                    FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey<int>(_index),
                  child: _ShotContent(
                    shot: shot,
                    useAnchors: useAnchors,
                    anchorStrength: _anchorStrength,
                    gateWrong: isGateWrong,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── زر التالي الكبير الوحيد ──
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.lg),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _next,
                child: Text(
                  shot.isLastShot ? 'إنهاء الشرح' : 'التالي',
                  style: AppType.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// محتوى لقطة واحدة — مع التمييز الكهرماني عند «هنا كان خطؤك».
class _ShotContent extends StatelessWidget {
  const _ShotContent({
    required this.shot,
    required this.useAnchors,
    required this.anchorStrength,
    this.gateWrong = false,
  });

  final _Shot shot;
  final bool useAnchors;
  final FixationStrength anchorStrength;

  /// تمييز «هنا كان خطؤك» — إطار كهرماني رقيق + شارة (أسبوع 2).
  final bool gateWrong;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color amber = AppColors.gold(b);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      child: Container(
        // ── الإطار الكهرماني: هنا كان خطؤك ──
        padding: gateWrong
            ? const EdgeInsets.all(AppSpacing.lg)
            : EdgeInsets.zero,
        decoration: gateWrong
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: amber, width: 1.5),
                color: amber.withValues(alpha: 0.06),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ── شارة الخطأ ──
            if (gateWrong) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.my_location_rounded,
                      size: 16, color: amber),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'هنا كان خطؤك — اقرأ بتمعّن',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: amber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── ترويسة المفهوم عند بدايته ──
            if (shot.isConceptStart) ...<Widget>[
              Text(
                shot.conceptTitle,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                style: AppType.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              if (shot.conceptCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'شرح ${shot.conceptIndex + 1} من ${shot.conceptCount}',
                    style: AppType.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                ),
              if ((shot.summaryAr ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  shot.summaryAr!,
                  style: AppType.body.copyWith(
                    fontSize: 13.5,
                    height: 1.6,
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── عنوان القسم ──
            if (shot.heading.isNotEmpty) ...<Widget>[
              Text.rich(
                TextSpan(
                  children: buildAnchoredSpans(
                    shot.heading,
                    focusHeadingStyle(b).copyWith(
                      color: AppColors.text(b),
                    ),
                    strength: anchorStrength,
                  ),
                ),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── جسم النص ──
            if (shot.body.isNotEmpty)
              Text.rich(
                TextSpan(
                  style: focusBodyStyle(b),
                  children: useAnchors
                      ? buildAnchoredSpans(
                          shot.body,
                          focusBodyStyle(b),
                          strength: anchorStrength,
                        )
                      : <TextSpan>[TextSpan(text: shot.body)],
                ),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start, // لا Justify أبداً
              ),

            // ── النقاط المفتاحية ──
            if (shot.keyPoints.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint(b),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border(b)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'النقاط المفتاحية',
                      style: AppType.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary(b),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final String point in shot.keyPoints)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Icon(Icons.bolt_rounded,
                                  size: 14, color: AppColors.gold(b)),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                point,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.start,
                                style: AppType.body.copyWith(
                                  fontSize: 13,
                                  height: 1.55,
                                  fontFamily: AppType.focusFamily,
                                  color: AppColors.focusText(b),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // ── مسرد المصطلحات — آخر قسم من المفهوم ──
            if (shot.keyTerms.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              Text(
                'المصطلحات الأساسية',
                style: AppType.caption.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary(b),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final Map<String, Object?> term in shot.keyTerms)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: Text(
                          (term['term'] as String?) ?? '',
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: AppType.body.copyWith(
                            fontFamily: AppType.focusFamily,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary(b),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 3,
                        child: Text(
                          (term['definition_ar'] as String?) ?? '',
                          style: AppType.body.copyWith(
                            fontSize: 13,
                            color: AppColors.textSecondary(b),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
