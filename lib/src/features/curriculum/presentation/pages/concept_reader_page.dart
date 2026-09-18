import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:confetti/confetti.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/inline_note.dart';
import '../../../../core/database/xp_event.dart';
import '../../../../core/motivation/celebration_queue.dart';
import '../../../../core/notifications/pin_expiry_service.dart';
import '../../../../core/profile/learner_profile.dart';
import '../../../../core/services/ai_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../../../core/widget/home_widget_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../widgets/breath_gate.dart';
import '../widgets/concept_gate_sheet.dart';
import '../widgets/fixation_spans.dart';
import '../widgets/inline_note_spans.dart';
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

enum TtsState { playing, paused, stopped }

class ConceptReaderPage extends StatefulWidget {
  const ConceptReaderPage({
    required this.unitId,
    this.unitTitle,
    this.initialConceptId,
    super.key,
  });

  final String unitId;
  final String? unitTitle;
  final String? initialConceptId;

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

class _ConceptReaderPageState extends State<ConceptReaderPage>
    with WidgetsBindingObserver {
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

  // الملاحظات المضمّنة (v22): كل مفهوم → ملاحظاته المحفوظة. تُحمَّل
  // عند بناء اللقطات وتُحدَّث عند إضافة/حذف ملاحظة.
  final Map<String, List<InlineNote>> _inlineNotes =
      <String, List<InlineNote>>{};


  // كاشف التصفح (أسبوع 3).
  double _baselineDwellSeconds = 0;
  bool _rushingDetected = false;

  // جلسة التدفق.
  int? _flowSessionId;
  DateTime _sessionStart = DateTime.now();
  bool _conceptXpGiven = false;

  // التثبيت الختامي (Recite) — آخر شرح.
  bool _finalReciteShown = false;
  
  bool _didResumeSession = false;
  bool _didJumpFromSearch = false;

  final FlutterTts flutterTts = FlutterTts();
  TtsState _ttsState = TtsState.stopped;
  String _currentSpokenWord = '';
  int _currentWordOccurrence = 0;
  double _ttsRate = 0.45;
  
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    WidgetsBinding.instance.addObserver(this);
    _initTts();
    _load();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(_ttsRate);
    await flutterTts.setPitch(1.0);
    await flutterTts.setVolume(1.0);
    await flutterTts.awaitSpeakCompletion(true);
    flutterTts.setProgressHandler((String text, int startOffset, int endOffset, String word) {
      if (mounted) {
        final String preText = text.substring(0, startOffset);
        final String escapedWord = RegExp.escape(word);
        final RegExp exp = RegExp('\\b$escapedWord\\b', caseSensitive: false);
        final int occurrenceIndex = exp.allMatches(preText).length;
        
        setState(() {
          _currentSpokenWord = word;
          _currentWordOccurrence = occurrenceIndex;
        });
      }
    });
    flutterTts.setCompletionHandler(() {
      if (mounted) {
          setState(() {
            _ttsState = TtsState.stopped;
            _currentSpokenWord = '';
            _currentWordOccurrence = 0;
          });
      }
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    flutterTts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _speak() async {
    if (_shots.isEmpty) return;
    
    if (_ttsState == TtsState.paused) {
      if (mounted) {
        setState(() {
          _ttsState = TtsState.playing;
        });
      }
      final _Shot currentShot = _shots[_index];
      String textToRead = currentShot.body.replaceAll(RegExp(r'[\u0600-\u06FF]'), '');
      textToRead = textToRead.replaceAll(RegExp(r'[*#_`]'), '');
      try {
        await flutterTts.speak(textToRead);
      } catch (e) {
        print('TTS Error: $e');
      }
      return;
    }

    final _Shot currentShot = _shots[_index];
    String textToRead = currentShot.body.replaceAll(RegExp(r'[\u0600-\u06FF]'), '');
    textToRead = textToRead.replaceAll(RegExp(r'[*#_`]'), '');
    
    try {
      if (mounted) {
        setState(() {
          _ttsState = TtsState.playing;
          _currentSpokenWord = '';
        });
      }
      await flutterTts.speak(textToRead);
    } catch (e) {
      print('TTS Error: $e');
      if (mounted) {
        setState(() {
          _ttsState = TtsState.stopped;
        });
      }
    }
  }

  Future<void> _pauseTts() async {
    await flutterTts.pause();
    if (mounted) {
      setState(() {
        _ttsState = TtsState.paused;
      });
    }
  }

  Future<void> _stop() async {
    await flutterTts.stop();
    if (mounted) {
      setState(() {
        _ttsState = TtsState.stopped;
        _currentSpokenWord = '';
      });
    }
  }

  Future<void> _stopTtsOnNavigation() async {
    if (_ttsState != TtsState.stopped) {
      await _stop();
    }
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

      // استعادة مكان التوقف السابق أو القفز لمصطلح محدد (من البحث)
      int initialIndex = 0;
      if (widget.initialConceptId != null) {
        initialIndex = shots.indexWhere((_Shot s) => s.conceptId == widget.initialConceptId);
        if (initialIndex == -1) initialIndex = 0;
      } else {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final int savedIndex = prefs.getInt('last_index_${widget.unitId}') ?? 0;
        initialIndex = savedIndex.clamp(0, shots.isEmpty ? 0 : shots.length - 1);
      }

      if (!mounted) return;
      setState(() {
        _unitTitle = widget.unitTitle ?? (unit?['title'] as String?) ?? '';
        _shots = shots;
        _index = initialIndex;
        _anchorsEnabled = anchors;
        _anchorStrength = FixationStrength.fromCode(strengthCode);
        _isFirstRead = firstRead;
        _baselineDwellSeconds = baseline;
        _loading = false;
      });

      if (widget.initialConceptId != null) {
        _didJumpFromSearch = true;
      } else if (initialIndex > 0) {
        _didResumeSession = true;
      }

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
        _runConceptGate().then((_) {
          if (_didResumeSession && mounted) {
            _didResumeSession = false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'عدنا بك إلى حيث توقفت في جلستك السابقة 📍',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          } else if (_didJumpFromSearch && mounted) {
            _didJumpFromSearch = false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'تم الانتقال إلى نتيجة البحث 📍',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
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
    final _Shot currentShot = _shots[_index];
    final DatabaseHelper db = DatabaseHelper.instance;

    // مجتازة من قبل؟ → افتح مباشرة.
    if (await db.conceptGatePassed(currentShot.conceptId)) return;
    if (!mounted) return;

    final Map<String, Object?>? gateMcq =
        await db.getGateMcqForConcept(currentShot.conceptId);

    if (gateMcq != null) {
      // بوابة MCQ + ثقة.
      if (!mounted) return;
      final Map<String, Object?>? result =
          await ConceptGateSheet.show(
        context,
        conceptTitle: currentShot.conceptTitle,
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
          _gateWrongConceptId = currentShot.conceptId;
        }
      });
      // إجابة صحيحة من أول مرة → وسم البوابة (لا تظهر مجدداً).
      if (wasCorrect) {
        await db.markGatePassed(currentShot.conceptId);
      }
      return;
    }

    // fallback: بطاقة مسح مسبق بمصطلحات key_terms (Advance Organizer).
    if (!mounted) return;
    await _showAdvanceOrganizer(currentShot);
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
      builder: (BuildContext ctx) => ResponsiveSheet(
        child: SafeArea(
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
),
      );
  }

  /// يجلّب الملاحظات المضمّنة لمفهوم ويخزّنها في الكاش (النداء عند
  /// أول عرض لكل مفهوم — لا في كل بناء).
  Future<void> _loadInlineNotes(String conceptId) async {
    try {
      final List<Map<String, Object?>> rows =
          await DatabaseHelper.instance.getInlineNotesForConcept(conceptId);
      if (!mounted) return;
      setState(() {
        _inlineNotes[conceptId] = <InlineNote>[
          for (final Map<String, Object?> r in rows)
            InlineNote.fromMap(r),
        ];
      });
    } catch (_) {
      // فشل القراءة لا يعطّل القراءة — يُتجاهل بهدوء.
    }
  }

  /// يلتقط النص المحدَّد داخل اللقطة (v22) — يُخزَّن لحين الضغط على
  /// «إضافة ملاحظة» في القائمة المخصصة، إذ لا يملك SelectionArea في
  /// هذه النسخة طريقاً عمومياً لقراءة النص المحدَّد حالياً.
  void _onSelectionChanged(Object? content) {}

  /// النقر على نص مميَّز — شيت صغير يعرض الملاحظة الشخصية مع أزرار
  /// «تعديل» و«حذف».
  void _onTapInlineNote(InlineNote note) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    AppSheet.show<void>(
      context,
      title: 'ملاحظتك',
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // النص المحدَّد مسبّقاً — قابل للنسخ، مصوّر بخط القراءة.
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(b),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              '"${note.selectedText}"',
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              style: AppType.body.copyWith(
                fontSize: 13,
                height: 1.55,
                fontFamily: AppType.focusFamily,
                color: AppColors.text(b),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // الملاحظة الشخصية.
          if (note.hasNote)
            Text(
              note.personalNote,
              style: AppType.body.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.6,
                color: AppColors.text(b),
              ),
            )
          else
            Text(
              'بلا ملاحظة — حدّد النص فقط.',
              style: AppType.body.copyWith(
                color: AppColors.textSecondary(b),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          // تعديل الملاحظة — يُغلق الشيت العرضي ويفتح شيت الإدخال
          // بمحتوى الملاحظة الحالية محمّلاً مسبقاً.
          FilledButton.icon(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              unawaited(_onEditInlineNote(note));
            },
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('تعديل الملاحظة'),
          ),
          const SizedBox(height: AppSpacing.sm),
          // حذف الملاحظة (زر ثانوي متواضع).
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              unawaited(_deleteInlineNote(note));
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('حذف الملاحظة'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteInlineNote(InlineNote note) async {
    try {
      await DatabaseHelper.instance.deleteInlineNote(note.remarkId);
      if (!mounted) return;
      setState(() {
        _inlineNotes[note.conceptId]?.removeWhere(
          (InlineNote n) => n.remarkId == note.remarkId,
        );
      });
    } catch (_) {
      // صمت — فشل الحذف لا يعطّل القراءة.
    }
  }

/// تحديد نص داخل اللقطة + «إضافة ملاحظة» — شيت إدخال الملاحظة.
  Future<void> _onAddInlineNote(
    String selectedText,
    int startIndex,
    int endIndex,
    String conceptId,
  ) async {
    final String trimmed = selectedText.trim();
    if (trimmed.isEmpty) return;

    await _showNoteEditor(
      title: 'إضافة ملاحظة',
      contextText: trimmed,
      initialNote: '',
      onSave: (String noteText) async {
        await DatabaseHelper.instance.addInlineNote(
          conceptId: conceptId,
          selectedText: trimmed,
          startIndex: startIndex,
          endIndex: endIndex,
          personalNote: noteText,
        );
      },
      conceptId: conceptId,
    );
  }

  /// «تعديل الملاحظة» — يُفتح شيت الإدخال معبّأً بمحتوى الملاحظة
  /// الحالية ويحدَّث الصف في القاعدة (UPDATE) عند الحفظ.
  Future<void> _onEditInlineNote(InlineNote note) async {
    await _showNoteEditor(
      title: 'تعديل الملاحظة',
      contextText: note.selectedText,
      initialNote: note.personalNote,
      onSave: (String noteText) async {
        await DatabaseHelper.instance.updateInlineNote(
          id: note.remarkId,
          personalNote: noteText,
        );
      },
      conceptId: note.conceptId,
    );
  }

  /// شيت موحّد لتأليف/تعديل ملاحظة مضمّنة. يعرض النص المحدَّد كسياق،
  /// حقل ملاحظة (معبّأً بـ [initialNote] عند التعديل)، وزر حفظ يستدعي
  /// [onSave] ثم يعيد تحميل ملاحظات الشرح ليظهر التغيير فوراً.
  Future<void> _showNoteEditor({
    required String title,
    required String contextText,
    required String initialNote,
    required Future<void> Function(String noteText) onSave,
    required String conceptId,
  }) async {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final TextEditingController controller =
        TextEditingController(text: initialNote);
    // نضع المؤشر في نهاية النص عند التعديل ليتابع التحرير بسرعة.
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    final bool? saved = await AppSheet.show<bool>(
      context,
      title: title,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // النص المحدَّد — للسياق.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.inlineNoteHighlight(b),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: AppColors.border(b)),
            ),
            child: Text(
              contextText,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              style: AppType.body.copyWith(
                fontSize: 13,
                height: 1.5,
                fontFamily: AppType.focusFamily,
                color: AppColors.text(b),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // حقل الملاحظة.
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'اكتب ملاحظتك هنا...',
              hintStyle: AppType.body.copyWith(
                color: AppColors.textSecondary(b),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // حفظ.
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: const Text('حفظ الملاحظة'),
            ),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;
    final String noteText = controller.text.trim();
    if (noteText.isEmpty) return;
    try {
      await onSave(noteText);
      // إعادة تحميل ملاحظات المفهوم ليعرض التغيير فوراً.
      await _loadInlineNotes(conceptId);
    } catch (_) {
      // صمت — فشل الحفظ لا يعطّل القراءة.
    }
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

  Future<void> _saveIndex() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_index_${widget.unitId}', _index);
    } catch (_) {}
  }

  Future<void> _clearIndex() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_index_${widget.unitId}');
    } catch (_) {}
  }

  /// العودة للقطة السابقة.
  Future<void> _previous() async {
    await _stopTtsOnNavigation();
    if (_index <= 0) return;
    final DateTime now = DateTime.now();
    _dwellMs[_index] = now.difference(_shotStart).inMilliseconds;
    setState(() => _index--);
    _shotStart = DateTime.now();
    unawaited(_saveIndex());
  }

  /// التقدم للقطة التالية — مع الاعتراضية كل لقطتين.
  Future<void> _next() async {
    await _stopTtsOnNavigation();
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
    unawaited(_saveIndex());
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
    // مسح موضع التوقف لأن المحاضرة اكتملت.
    await _clearIndex();
    // لقطة XP قبل الكتابات — ل كشف رفع المستوى (Motivator).
    final int beforeXp = await Motivator.currentXp();

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
      // ديناميكياً في القاعدة فلا نكرر المنطق هنا. مع إلغاء إشعار
      // الانتهاء المجدول (+48h) لأن الهدف تحقق قبل انتهائه.
      final bool wasPinned = (await db.getUnitById(widget.unitId))
              ?['pinned_at'] !=
          null;
      await db.unpinUnitIfCompleted(widget.unitId);
      if (wasPinned) {
        await PinExpiryService.cancelExpiryNotification(widget.unitId);
      }

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

      // الاحتفالات: شارات جديدة + رفع مستوى إن عُبر حدٌّ.
      final List<String> newBadges =
          await db.unlockEarnedBadges();
      await Motivator.detectLevelUp(beforeXp, newBadgeIds: newBadges);
    } catch (error) {
      AppErrorLogger.instance.record(
        type: 'ConceptReader',
        error: error,
      );
    }

    // تحديث ويدجت الشاشة الرئيسية — فك التثبيت التلقائي أعلاه قد غيّر
    // «أهدافي» (unawaited: الويدجت تحسين غير حركي).
    unawaited(HomeWidgetService.refresh());

    if (!mounted) return;

    // رسالة الختام عبر رسنجر الشاشة الأم — يُحفظ قبل pop
    // (استخدام context بعد pop = عنصر مهدم).
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    final int interceptsPassed = _interceptsPassed;
    final int interceptsCorrect = _interceptsCorrect;

    // ملخص الاعتراضيات إن وُجدت — ثم إغلاق.
    if (interceptsPassed > 0) {
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success(Brightness.light),
          content: Text(
            'أتممت الجلسة — $interceptsPassed نقطة استرجاع'
            ' ($interceptsCorrect صحيحة) 🌊',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    _confettiController.play();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop();
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
          actions: <Widget>[
            IconButton(
              icon: Icon(_ttsState != TtsState.stopped ? Icons.stop : Icons.volume_up),
              tooltip: _ttsState != TtsState.stopped ? 'إيقاف الاستماع' : 'استمع للشرح',
              onPressed: () {
                if (_ttsState != TtsState.stopped) {
                  _stop();
                } else {
                  _speak();
                }
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            _loading
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
                        : Column(
                            children: [
                              _buildTtsSettingsBar(b),
                              Expanded(child: _buildShotView(context)),
                            ],
                          ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.05,
                numberOfParticles: 50,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTtsSettingsBar(Brightness b) {
    if (_ttsState == TtsState.stopped) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface(b),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_ttsState == TtsState.playing ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              if (_ttsState == TtsState.playing) {
                _pauseTts();
              } else {
                _speak();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _stop,
          ),
          const SizedBox(width: 16),
          const Text('السرعة:', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Slider(
              value: _ttsRate,
              min: 0.2,
              max: 1.0,
              onChanged: (val) {
                setState(() => _ttsRate = val);
                flutterTts.setSpeechRate(val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShotView(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final _Shot shot = _shots[_index];
    final bool useAnchors = _anchorsEnabled && _isFirstRead;
    final bool isGateWrong = _isGateWrong(shot);

    // تحميل الملاحظات المضمّنة عند إظهار مفهوم أول مرة (كاش خفيف).
    if (!_inlineNotes.containsKey(shot.conceptId)) {
      unawaited(_loadInlineNotes(shot.conceptId));
    }
    final List<InlineNote> notes =
        _inlineNotes[shot.conceptId] ?? const <InlineNote>[];

    // توافق الآيباد: عمود القراءة لا يتمدد على الشاشات الواسعة —
    // ResponsiveReadingColumn الموحد (موبايل: بلا أي أثر).
    return ResponsiveReadingColumn(
      child: Column(
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
                        inlineNotes: notes,
                        spokenWord: _currentSpokenWord,
                        spokenWordOccurrence: _currentWordOccurrence,
                        onAddNote: (int start, int end) {
                          final String selectedString = shot.body.substring(start, end);
                          _onAddInlineNote(selectedString, start, end, shot.conceptId);
                        },
                        onTapNote: _onTapInlineNote,
                        onSelectionChanged: _onSelectionChanged,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── أزرار التنقل ──
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.lg),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: _index > 0 ? _previous : null,
                          child: Text(
                            'السابق',
                            style: AppType.body.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 3,
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  }
}

/// محتوى لقطة واحدة — مع التمييز الكهرماني عند «هنا كان خطؤك».
///
/// **v22 — النسخ والتحديد**: كامل نص اللقطة قابل للتحديد والنسخ
/// (SelectionArea) — الجسم، العنوان، النقاط المفتاحية، والمسرد.
/// هؤلاء طلبة طب ينسخون جرعات دواء ومعايير تشخيص إلى ملاحظاتهم؛
/// منع التحديد هنا عائق تعليمي حقيقي. النطاق محصور بهذه الشاشة
/// فقط — بقية التطبيق (أزرار/بطاقات/أسئلة) سلوكه التاريخي:
/// النقر يمر بلا أثر تحديد.
class _ShotContent extends StatelessWidget {
  const _ShotContent({
    required this.shot,
    required this.useAnchors,
    required this.anchorStrength,
    this.gateWrong = false,
    this.inlineNotes = const <InlineNote>[],
    this.onAddNote,
    this.onTapNote,
    this.onSelectionChanged,
    this.spokenWord,
    this.spokenWordOccurrence,
  });

  final _Shot shot;
  final bool useAnchors;
  final FixationStrength anchorStrength;

  /// تمييز «هنا كان خطؤك» — إطار كهرماني رقيق + شارة (أسبوع 2).
  final bool gateWrong;

  /// الملاحظات المضمّنة لهذا الشرح (v22) — تُظهر التمييز الصفري.
  final List<InlineNote> inlineNotes;

  /// تحديد نص داخل اللقطة ثم «إضافة ملاحظة» (مرفوع للصفحة) — يقرأ
  /// النص المحدَّد الملتقط عبر [onSelectionChanged].
  final void Function(int startIndex, int endIndex)? onAddNote;


  /// النقر على نص مميَّز — عرض الملاحظة.
  final void Function(InlineNote note)? onTapNote;

  /// تغيير التحديد داخل اللقطة — تُلتقط النص المحدَّد إلى الصفحة
  /// ليستخدمه زر «إضافة ملاحظة» في القائمة المخصصة. (النوع Object?
  /// لأن SelectedContent غير مصدَّر علناً في هذه النسخة من Flutter.)
  final ValueChanged<Object?>? onSelectionChanged;
  
  final String? spokenWord;
  final int? spokenWordOccurrence;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color amber = AppColors.gold(b);

    // v22: SelectionArea يغلّف محتوى اللقطة كلها — أي نص داخلها
    // قابل للتحديد والنسخ (سلوك المنصة: زر النسخ/المشاركة من
    // النظام). لف SingleChildScrollView لا العكس — كي يعمل
    // التحديد عبر التمرير كاملاً.
    //
    // القائمة المخصصة: نضيف زر «إضافة ملاحظة» إلى أدوات التحديد
    // الافتراضية (نسخ/تحديد الكل) — يمسك النص المحدَّد ويرفعه للصفحة.
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
                _sanitizeBidi(shot.conceptTitle),
                textDirection: _isArabic(shot.conceptTitle) ? TextDirection.rtl : TextDirection.ltr,
                textAlign: _isArabic(shot.conceptTitle) ? TextAlign.start : TextAlign.left,
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
                  _sanitizeBidi(shot.summaryAr!),
                  textDirection: _isArabic(shot.summaryAr!) ? TextDirection.rtl : TextDirection.ltr,
                  textAlign: _isArabic(shot.summaryAr!) ? TextAlign.start : TextAlign.left,
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
                    _sanitizeBidi(shot.heading),
                    focusHeadingStyle(b).copyWith(
                      color: AppColors.text(b),
                    ),
                    strength: anchorStrength,
                  ),
                ),
                textDirection: _isArabic(shot.heading) ? TextDirection.rtl : TextDirection.ltr,
                textAlign: _isArabic(shot.heading) ? TextAlign.start : TextAlign.left,
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── جسم النص ──
            // v22: يدمج المراسي (قراءة أولى) مع تمييز الملاحظات
            // المضمّنة — أي نص محفوظ يظهر بأصفر فاتح وقابل للنقر.
            if (shot.body.isNotEmpty)
              SelectableText.rich(
                TextSpan(
                  style: focusBodyStyle(b),
                  children: _buildBodySpans(shot, b),
                ),
                textDirection: _isArabic(shot.body) ? TextDirection.rtl : TextDirection.ltr,
                textAlign: _isArabic(shot.body) ? TextAlign.start : TextAlign.left, // لا Justify أبداً
                contextMenuBuilder: (BuildContext ctx, EditableTextState state) {
                  final List<ContextMenuButtonItem> items =
                      List<ContextMenuButtonItem>.of(state.contextMenuButtonItems);
                  
                  items.insert(
                    0,
                    ContextMenuButtonItem(
                      label: 'ترجمة',
                      onPressed: () {
                        // 1. التقاط النص قبل إخفاء القائمة لتفادي فقدان الحالة
                        final TextSelection selection = state.textEditingValue.selection;
                        final int start = selection.baseOffset < selection.extentOffset 
                                          ? selection.baseOffset 
                                          : selection.extentOffset;
                        final int end = selection.baseOffset > selection.extentOffset 
                                          ? selection.baseOffset 
                                          : selection.extentOffset;
                        final String selectedString = state.textEditingValue.text
                            .substring(start, end)
                            .replaceAll('**', '');
                        
                        print('Translate tapped for: $selectedString');
                        
                        // 2. إخفاء القائمة وإزالة التحديد والتركيز لمنع تكرار الأحداث (UI Event Loop)
                        state.hideToolbar();
                        FocusManager.instance.primaryFocus?.unfocus();
                        state.userUpdateTextEditingValue(
                          state.textEditingValue.copyWith(
                            selection: const TextSelection.collapsed(offset: 0),
                          ),
                          null,
                        );
                        
                        // 3. عرض النافذة باستخدام (context) الخاص بالصفحة وليس (ctx) الخاص بالقائمة
                        if (selectedString.trim().isNotEmpty) {
                          try {
                            _showTranslationSheet(context, selectedString);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('حدث خطأ أثناء فتح الترجمة: $e')),
                            );
                          }
                        }
                      },
                    ),
                  );

                  items.insert(
                    1,
                    ContextMenuButtonItem(
                      label: '🤖 شرح ذكي',
                      onPressed: () {
                        final TextSelection selection = state.textEditingValue.selection;
                        final int start = selection.baseOffset < selection.extentOffset 
                                          ? selection.baseOffset 
                                          : selection.extentOffset;
                        final int end = selection.baseOffset > selection.extentOffset 
                                          ? selection.baseOffset 
                                          : selection.extentOffset;
                        final String selectedString = state.textEditingValue.text
                            .substring(start, end)
                            .replaceAll('**', '');
                        
                        state.hideToolbar();
                        FocusManager.instance.primaryFocus?.unfocus();
                        state.userUpdateTextEditingValue(
                          state.textEditingValue.copyWith(
                            selection: const TextSelection.collapsed(offset: 0),
                          ),
                          null,
                        );
                        
                        if (selectedString.trim().isNotEmpty) {
                          _showAIExplainSheet(context, selectedString);
                        }
                      },
                    ),
                  );

                  items.insert(
                    2,
                    ContextMenuButtonItem(
                      label: 'إضافة ملاحظة',
                      onPressed: () {
                        state.hideToolbar();
                        if (onAddNote != null) {
                          final TextSelection selection = state.textEditingValue.selection;
                          final int start = selection.baseOffset < selection.extentOffset 
                                            ? selection.baseOffset 
                                            : selection.extentOffset;
                          final int end = selection.baseOffset > selection.extentOffset 
                                            ? selection.baseOffset 
                                            : selection.extentOffset;
                          onAddNote!(start, end);
                        }
                      },
                    ),
                  );
                  
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: state.contextMenuAnchors,
                    buttonItems: items,
                  );
                },
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
                                _sanitizeBidi(point),
                                textDirection: _isArabic(point) ? TextDirection.rtl : TextDirection.ltr,
                                textAlign: _isArabic(point) ? TextAlign.start : TextAlign.left,
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
                          _sanitizeBidi((term['term'] as String?) ?? ''),
                          textDirection: _isArabic((term['term'] as String?) ?? '') ? TextDirection.rtl : TextDirection.ltr,
                          textAlign: _isArabic((term['term'] as String?) ?? '') ? TextAlign.start : TextAlign.left,
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
                          _sanitizeBidi((term['definition_ar'] as String?) ?? ''),
                          textDirection: _isArabic((term['definition_ar'] as String?) ?? '') ? TextDirection.rtl : TextDirection.ltr,
                          textAlign: _isArabic((term['definition_ar'] as String?) ?? '') ? TextAlign.start : TextAlign.left,
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

  bool _isArabic(String text) {
    return RegExp(r'^[\s\W]*[\u0600-\u06FF]').hasMatch(text);
  }

  /// حقن علامة التوجيه المناسبة لنهاية النصوص لضمان تنسيق علامات الترقيم والأقواس.
  String _sanitizeBidi(String text) {
    if (text.isEmpty) return text;
    if (_isArabic(text)) {
      if (text.endsWith('\u200F')) return text;
      return '$text\u200F';
    } else {
      if (text.endsWith('\u200E')) return text;
      return '$text\u200E';
    }
  }

  /// يبني أجزاء جسم النص — يدمج مراسي التثبيت (قراءة أولى) مع تمييز
  /// الملاحظات المضمّنة (v22).
  ///
  /// عند توفر ملاحظات للشرح: نمسح النص بحثاً عن التمييز أجزاءً، مع
  /// تطبيق المراسي على المقاطع غير المميّزة فقط (حتى لا نكسر خلفية
  /// التمييز)؛ بدونه يبقى السلوك التاريخي (مراسي فقط أو نص مسطح).
  List<TextSpan> _buildBodySpans(_Shot shot, Brightness b) {
    final TextStyle base = focusBodyStyle(b);
    final String sanitizedBody = _sanitizeBidi(shot.body);
    // نعتمد دائماً على buildInlineNoteSpans لأنه يتولى الآن معالجة الخط العريض `**` 
    // والمراسي والتحديد معاً.
    return buildInlineNoteSpans(
      sanitizedBody,
      inlineNotes,
      base: base,
      onTap: onTapNote,
      brightness: b,
      useAnchors: useAnchors,
      anchorStrength: anchorStrength,
      spokenWord: spokenWord,
      spokenWordOccurrence: spokenWordOccurrence,
    );
  }
}

/// ── أداة الترجمة ──
Future<void> _showTranslationSheet(BuildContext context, String textToTranslate) async {
  final Brightness b = Theme.of(context).colorScheme.brightness;
  
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface(b),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (BuildContext ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          top: AppSpacing.lg,
          bottom: MediaQuery.paddingOf(ctx).bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border(b),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'الترجمة',
              textAlign: TextAlign.center,
              style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
            ),
            const SizedBox(height: AppSpacing.xl),
            
            // النص الأصلي
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt(b),
                borderRadius: BorderRadius.circular(AppRadius.field),
                border: Border.all(color: AppColors.border(b)),
              ),
              child: Text(
                textToTranslate,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: AppType.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary(b),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            
            // الترجمة
            FutureBuilder<Translation>(
              future: GoogleTranslator().translate(textToTranslate, to: 'ar'),
              builder: (BuildContext context, AsyncSnapshot<Translation> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Center(
                      child: Text(
                        'تعذّر الاتصال بخدمة الترجمة. تأكد من اتصالك بالإنترنت.',
                        textAlign: TextAlign.center,
                        style: AppType.body.copyWith(color: AppColors.error(b)),
                      ),
                    ),
                  );
                }
                
                final String translated = snapshot.data?.text ?? '';
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint(b),
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    translated,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.start,
                    style: AppType.body.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

/// ── الشرح الذكي (AI) ──
Future<void> _showAIExplainSheet(BuildContext context, String textToExplain) async {
  final Brightness b = Theme.of(context).colorScheme.brightness;
  
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface(b),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (BuildContext ctx) {
      bool isRequested = false;
      bool isLoading = true;
      String? explanationResult;
      String? errorMessage;

      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          if (!isRequested) {
            isRequested = true;
            AIService.explainMedicalText(textToExplain).then((result) {
              setState(() {
                if (result != null && result.isNotEmpty) {
                  explanationResult = result;
                } else {
                  errorMessage = 'فشل الحصول على الشرح. يرجى التحقق من إعدادات الذكاء الاصطناعي.';
                }
                isLoading = false;
              });
            }).catchError((e) {
              setState(() {
                errorMessage = 'حدث خطأ غير متوقع: $e';
                isLoading = false;
              });
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              top: AppSpacing.lg,
              bottom: MediaQuery.paddingOf(ctx).bottom + AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(b),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: AppColors.gold(b)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'شرح ذكي',
                      textAlign: TextAlign.center,
                      style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                
                // النص الأصلي
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt(b),
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    border: Border.all(color: AppColors.border(b)),
                  ),
                  child: Text(
                    textToExplain,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: AppType.body.copyWith(
                      fontSize: 13,
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                
                // حالة التحميل
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'يجري تحليل النص السريري...',
                          style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
                        ),
                      ],
                    ),
                  ),
                
                // حالة الخطأ
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Center(
                      child: Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: AppType.body.copyWith(color: AppColors.error(b)),
                      ),
                    ),
                  ),
                
                // حالة النتيجة
                if (explanationResult != null)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint(b),
                          borderRadius: BorderRadius.circular(AppRadius.field),
                          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          explanationResult!,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.start,
                          style: AppType.body.copyWith(
                            fontSize: 15,
                            color: AppColors.text(b),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}
