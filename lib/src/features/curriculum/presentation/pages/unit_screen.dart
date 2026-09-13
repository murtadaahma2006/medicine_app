import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/markdown_cleaner.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../data/unit_repository.dart';
import '../../domain/unit.dart';
import 'clinical_case_player_page.dart';
import 'concept_reader_page.dart';
import 'flashcard_session_page.dart';
import 'mcq_session_page.dart';
import 'mistakes_review_page.dart';

/// شاشة الوحدة (المحاضرة الطبية):
/// - رأس بطولي: تدرّج tint بلون التخصص + إيموجي كبير + شارة + العنوان.
/// - بطاقة «التالي الموصى به» أعلى الشاشة: أول نشاط غير مكتمل.
/// - 4 أقسام SegmentedButton: تعلّم · تدرّب · اختبر · راجع.
/// - بطاقات أنشطة مضغوطة (صف واحد) بعلامة ✓ مصغرة عند الإكمال.
/// - دخول متدرج 30ms للعنصر عند أول بناء فقط.
///
/// ملاحظة معمارية: شاشات الأنشطة التفاعلية (البطاقات/الأسئلة/الحالات)
/// تُبنى في المرحلة التالية فوق جداول flashcards/mcq_bank/clinical_cases —
/// هذه الشاشة تعرض جرد الوحدة وحالاتها من user_progress.
class UnitScreen extends StatefulWidget {
  const UnitScreen({required this.unitId, super.key});

  final String unitId;

  @override
  State<UnitScreen> createState() => _UnitScreenState();
}

class _UnitScreenState extends State<UnitScreen> {
  late final UnitRepository _units;

  Unit? _unit;
  bool _loading = true;
  String? _error;

  int _conceptCount = 0;
  int _flashcardCount = 0;
  int _mcqCount = 0;
  int _caseCount = 0;

  // حالة الأنشطة المكتملة (مفاتيح user_progress القياسية).
  bool _flashcardsDone = false;
  bool _assessmentDone = false;

  // القسم المختار: 0 تعلّم · 1 تدرّب · 2 اختبر · 3 راجع.
  int _section = 0;

  // دخول متدرج — أول بناء فقط.
  bool _entranceDone = false;

  @override
  void initState() {
    super.initState();
    _units = const UnitRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final Unit? unit = await _units.getById(widget.unitId);

      // جرد محتوى الوحدة من الجداول الطبية.
      final int concepts =
          (await db.getConceptsForUnit(widget.unitId)).length;
      final int flashcards =
          (await db.getFlashcardsForUnit(widget.unitId)).length;
      final int mcqs = (await db.getMcqsForUnit(widget.unitId)).length;
      final int cases = (await db.getCasesForUnit(widget.unitId)).length;

      // حالة البطاقات: flashcard_set × unitId.
      final Map<String, Object?>? flashProgress = await db
          .rawQueryParameterized(
        'SELECT status FROM ${DatabaseHelper.tableUserProgress} '
        "WHERE item_type = 'flashcard_set' AND item_id = ? LIMIT 1",
        <Object?>[widget.unitId],
      ).then((List<Map<String, Object?>> rows) =>
          rows.isEmpty ? null : rows.first);

      // حالة اختبار الوحدة: assess-<unitId>.
      final Map<String, Object?>? assessProgress =
          await db.rawQueryParameterized(
        'SELECT status FROM ${DatabaseHelper.tableUserProgress} '
        "WHERE item_type = 'drill' AND item_id = ? LIMIT 1",
        <Object?>['assess-${widget.unitId}'],
      ).then((List<Map<String, Object?>> rows) =>
          rows.isEmpty ? null : rows.first);

      if (!mounted) return;
      setState(() {
        _unit = unit;
        _conceptCount = concepts;
        _flashcardCount = flashcards;
        _mcqCount = mcqs;
        _caseCount = cases;
        _flashcardsDone = flashProgress?['status'] == 'completed';
        _assessmentDone = assessProgress?['status'] == 'completed';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل المحاضرة.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _unit == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: _error ?? 'المحاضرة غير موجودة',
          actionLabel: 'إعادة المحاولة',
          onAction: _load,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background(b),
      body: CustomScrollView(
        slivers: <Widget>[
          // ═══ الرأس البطولي ═══
          SliverAppBar(
            pinned: false,
            expandedHeight: 150,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'عودة',
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _HeroHeader(unit: _unit!),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
              child: _RecommendedCard(
                unitId: widget.unitId,
                flashcardCount: _flashcardCount,
                mcqCount: _mcqCount,
                caseCount: _caseCount,
                flashcardsDone: _flashcardsDone,
                assessmentDone: _assessmentDone,
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _SectionTabs(
                current: _section,
                onChanged: (int i) => setState(() => _section = i),
              ),
            ),
          ),

           _SectionBody(
             section: _section,
             unit: _unit!,
             playEntrance: !_entranceDone,
             onEntranceConsumed: () => _entranceDone = true,
             conceptCount: _conceptCount,
             flashcardCount: _flashcardCount,
             mcqCount: _mcqCount,
             caseCount: _caseCount,
             flashcardsDone: _flashcardsDone,
             assessmentDone: _assessmentDone,
           ),

          const SliverToBoxAdapter(
            child: SizedBox(height: AppSpacing.xxxl),
          ),
        ],
      ),
    );
  }
}

/// الرأس البطولي — تدرّج tint بلون التخصص + إيموجي + شارة + عنوان.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.unit});

  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[
            AppColors.moduleContainer(unit.module, b),
            AppColors.background(b),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // أيقونة التخصص من الطقم المخصص — هوية مملوكة.
                  ModuleIcon(unit.module, size: 56),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            ModuleBadge(unit.module, large: true),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: Text(
                                MarkdownCleaner.clean(unit.title),
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.start,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.screenTitle
                                    .copyWith(color: AppColors.text(b)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((unit.descriptionAr ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  MarkdownCleaner.clean(unit.descriptionAr!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppType.body.copyWith(color: AppColors.textSecondary(b)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة «التالي الموصى به» — أول نشاط غير مكتمل.
class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({
    required this.unitId,
    required this.flashcardCount,
    required this.mcqCount,
    required this.caseCount,
    required this.flashcardsDone,
    required this.assessmentDone,
  });

  final String unitId;
  final int flashcardCount;
  final int mcqCount;
  final int caseCount;
  final bool flashcardsDone;
  final bool assessmentDone;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final (String, String) next = !flashcardsDone && flashcardCount > 0
        ? ('راجع بطاقات المحاضرة', '$flashcardCount بطاقة تنتظرك')
        : !assessmentDone && mcqCount > 0
            ? ('اختبر نفسك', 'اختبار المحاضرة — $mcqCount سؤالاً')
            : caseCount > 0
                ? ('حالة سريرية', '$caseCount حالة بقرار سريري')
                : ('أتمت المحاضرة!', 'راجع أخطاءك أو تقدّم للمحاضرة التالية');

    return AppCard(
      accent: Theme.of(context).colorScheme.primary,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('التالي الموصى به',
                    style: AppType.caption
                        .copyWith(color: AppColors.textSecondary(b))),
                const SizedBox(height: AppSpacing.xs),
                Text(next.$1,
                    style: AppType.cardTitle.copyWith(
                        fontSize: 17, color: AppColors.text(b))),
                const SizedBox(height: 2),
                Text(
                  next.$2,
                  style: AppType.body.copyWith(
                      fontSize: 12.5, color: AppColors.textSecondary(b)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ألسنة الأقسام الأربعة.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.current,
    required this.onChanged,
  });

  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: <ButtonSegment<int>>[
          ButtonSegment<int>(
            value: 0,
            icon: Icon(Icons.menu_book_rounded,
                size: 18, color: _iconColor(0, b, context)),
            label: const Text('تعلّم'),
          ),
          ButtonSegment<int>(
            value: 1,
            icon: Icon(Icons.fitness_center_rounded,
                size: 18, color: _iconColor(1, b, context)),
            label: const Text('تدرّب'),
          ),
          ButtonSegment<int>(
            value: 2,
            icon: Icon(Icons.verified_rounded,
                size: 18, color: _iconColor(2, b, context)),
            label: const Text('اختبر'),
          ),
          ButtonSegment<int>(
            value: 3,
            icon: Icon(Icons.replay_rounded,
                size: 18, color: _iconColor(3, b, context)),
            label: const Text('راجع'),
          ),
        ],
        selected: <int>{current},
        onSelectionChanged: (Set<int> s) => onChanged(s.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStatePropertyAll(
              BorderSide(color: AppColors.border(b))),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          )),
        ),
      ),
    );
  }

  Color _iconColor(int i, Brightness b, BuildContext context) =>
      i == current
          ? Theme.of(context).colorScheme.primary
          : AppColors.textSecondary(b);
}

/// بيانات نشاط واحد داخل الأقسام.
class _ActivityData {
  const _ActivityData(
    this.emoji,
    this.title,
    this.subtitle, {
    this.done = false,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onTap;
}

/// جسم القسم المختار — قائمة بطاقات مضغوطة بدخول متدرج 30ms/عنصر.
class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.unit,
    required this.playEntrance,
    required this.onEntranceConsumed,
    required this.conceptCount,
    required this.flashcardCount,
    required this.mcqCount,
    required this.caseCount,
    required this.flashcardsDone,
    required this.assessmentDone,
  });

  final int section;
  final Unit unit;
  final bool playEntrance;
  final VoidCallback onEntranceConsumed;
  final int conceptCount;
  final int flashcardCount;
  final int mcqCount;
  final int caseCount;
  final bool flashcardsDone;
  final bool assessmentDone;

  List<_ActivityData> _activities(BuildContext context) {
    switch (section) {
      case 0: // ── تعلّم ──
        return <_ActivityData>[
          _ActivityData(
            'icon_concept',
            'الشروحات المفصلة',
            '$conceptCount شرحاً فسيولوجياً وسريرياً',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
              builder: (_) => ConceptReaderPage(unitId: unit.id),
            )),
          ),
          _ActivityData(
            'icon_flashcards',
            'البطاقات الغنية',
            '$flashcardCount بطاقة استرجاعية — قلب وتعلّم',
            done: flashcardsDone,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
              builder: (_) => FlashcardSessionPage(unitId: unit.id),
            )),
          ),
        ];

      case 1: // ── تدرّب ──
        return <_ActivityData>[
          if (caseCount > 0)
            _ActivityData(
              'icon_case',
              'الحالات السريرية',
              '$caseCount حالة OSCE — قرارات سريرية متسلسلة',
              onTap: () => _openFirstCase(context),
            ),
          _ActivityData(
            'icon_quiz',
            'أسئلة سريعة',
            'جرعة مركزة من بنك الأسئلة',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
              builder: (_) => McqSessionPage(unitId: unit.id),
            )),
          ),
        ];

      case 2: // ── اختبر (التقييم الرسمي — يغذي الخط الزمني) ──
        return <_ActivityData>[
          _ActivityData(
            'icon_graduation',
            'اختبار المحاضرة',
            '$mcqCount سؤال MCQ — اجتياز من 70٪',
            done: assessmentDone,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
              builder: (_) => McqSessionPage(
                unitId: unit.id,
                isAssessment: true,
              ),
            )),
          ),
        ];

      case 3: // ── راجع (تحليل الأخطاء الحقيقي) ──
        return <_ActivityData>[
          _ActivityData(
            'icon_analyze',
            'أخطاء جلسات المحاضرة',
            'تحليل مفصل لقراراتك هنا',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
              builder: (_) => MistakesReviewPage(unitId: unit.id),
            )),
          ),
        ];
    }
    return const <_ActivityData>[];
  }

  /// يفتح أول حالة سريرية للوحدة (المشغل يتصفح داخل الحالة نفسها).
  Future<void> _openFirstCase(BuildContext context) async {
    try {
      final List<Map<String, Object?>> cases =
          await DatabaseHelper.instance.getCasesForUnit(unit.id);
      if (cases.isEmpty || !context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<Widget>(
        builder: (_) =>
            ClinicalCasePlayerPage(caseId: cases.first['id']! as String),
      ));
    } catch (_) {
      // صمت مقصود.
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_ActivityData> activities = _activities(context);
    final bool animate =
        playEntrance && !MediaQuery.disableAnimationsOf(context);

    if (playEntrance) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onEntranceConsumed());
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      sliver: SliverList.builder(
        itemCount: activities.length,
        itemBuilder: (BuildContext context, int index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _ActivityTile(
              data: activities[index],
              delay: animate ? index * 30 : 0,
              animate: animate,
            ),
          );
        },
      ),
    );
  }
}

/// بطاقة نشاط مضغوطة — صف واحد: أيقونة + عنوان + ✓/chevron.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.data,
    required this.delay,
    this.animate = false,
  });

  final _ActivityData data;

  /// تأخير الدخول بالمللي ثانية (30ms × index).
  final int delay;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final Widget tile = AppCard(
      onTap: data.onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(b),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Center(
              child: AppIllustration(
                data.emoji,
                size: 44,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(data.title,
                    style: AppType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.text(b))),
                const SizedBox(height: 2),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                      fontSize: 12, color: AppColors.textSecondary(b)),
                ),
              ],
            ),
          ),
          if (data.done)
            Icon(Icons.check_circle_rounded,
                size: 20, color: AppColors.success(b))
          else
            Icon(Icons.chevron_left_rounded,
                color: AppColors.textSecondary(b)),
        ],
      ),
    );

    if (!animate) return tile;

    // دخول متدرج: تأخير delay ثم ظهور + انزلاق خافت — 220ms.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delay),
      curve: AppMotion.ease,
      builder: (BuildContext context, double v, Widget? child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - v.clamp(0.0, 1.0))),
          child: child,
        ),
      ),
      child: tile,
    );
  }
}
