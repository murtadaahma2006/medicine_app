import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import 'case_bank_page.dart';
import 'concept_library_page.dart';
import 'flashcard_bank_page.dart';
import 'mcq_bank_page.dart';

/// شاشة «المكتبة» — اللسان الثالث: كل الأقسام المرجعية للتطبيق
/// في مكان واحد ببطاقات موحدة (أيقونة + عنوان + وصف + عدّاد).
///
/// **v20 — نطاق التخصص**: شريط التبديل أعلى الشاشة (من SpecialtyScope
/// المشترك مع المسار) يفلتر العدّادات ومحتوى كل بنك بالتخصص
/// المختار — البنية والأقسام كما هي تماماً.
///
/// كل قسم يفتح نشاطه مارّاً التخصص النشط (تبدأ البنوك مفلترة
/// به مباشرة — وفلاترها الداخلية تعمل داخله).
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _loading = true;
  String? _error;

  // العدّادات الحقيقية لكل قسم — داخل التخصص النشط.
  int _conceptCount = 0;
  int _flashcardCount = 0;
  int _mcqCount = 0;
  int _caseCount = 0;

  /// آخر تخصص عُدّت بنوكه فعلاً — حراسة didChangeDependencies:
  /// التحميل عند أول فتح ثم عند تبديل التخصص فقط (لا عند كل بناء).
  String? _loadedSpecialty;

  /// عدّاد تحميلات متوازية: تبديل سريع أثناء عدّ جارٍ يجعل النتيجة
  /// القديمة تصل متأخرة — تجاهل أي نتيجة غير آخر تحميل.
  int _loadEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // هنا (لا initState): السياق مكتمل فيُقرأ التخصص المحفوظ من
    // الجلسة السابقة منذ أول فتح، والتبديل يعيد العدّ فوراً.
    final String specialty = SpecialtyScope.effectiveOf(context);
    if (specialty != _loadedSpecialty) _load();
  }

  Future<void> _load() async {
    // رقم هذا التحميل — يُقارن في النجاح والفشل معاً: فشل تحميل
    // قديم بعد بدء أحدث يُتجاهل (لا يعرض خطأ زائفاً).
    final int epoch = ++_loadEpoch;
    try {
      // v20: التخصص النشط — القراءة في سياق صالح دائماً والعدّ داخل
      // try-catch كامل: أي فشل استعلام يعطّل `_loading` حتماً. التحميل
      // صامت عند التبديل (لا وميض سبينر): البطاقات القديمة تبقى حتى
      // وصول الأعداد الجديدة.
      final String specialty = SpecialtyScope.effectiveOf(context);
      _loadedSpecialty = specialty;
      final DatabaseHelper db = DatabaseHelper.instance;
      // v20: كل عدّ داخل تخصص واحد — جملة عد واحدة لكل قسم عبر
      // INNER JOIN units (استعلامات العد تمر بنفس مسار البنوك).
      final int concepts = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableConcepts} c '
        'INNER JOIN ${DatabaseHelper.tableUnits} u ON u.id = c.unit_id '
        'WHERE u.specialty = ?',
        <Object?>[specialty],
      );
      final int flashcards = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableFlashcards} f '
        'INNER JOIN ${DatabaseHelper.tableUnits} u ON u.id = f.unit_id '
        'WHERE u.specialty = ?',
        <Object?>[specialty],
      );
      final int mcqs = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableMcqBank} m '
        'INNER JOIN ${DatabaseHelper.tableUnits} u ON u.id = m.unit_id '
        'WHERE u.specialty = ?',
        <Object?>[specialty],
      );
      final int cases = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableClinicalCases} cs '
        'INNER JOIN ${DatabaseHelper.tableUnits} u ON u.id = cs.unit_id '
        'WHERE u.specialty = ?',
        <Object?>[specialty],
      );

      // تحديث قائمة التخصصات في الجذر (استيراد جديد قد يظهرها).
      final List<String> specialties =
          await db.getDistinctSpecialties();

      if (!mounted || epoch != _loadEpoch) return;
      SpecialtyScope.maybeUpdateRoot(context, specialties);
      setState(() {
        _conceptCount = concepts;
        _flashcardCount = flashcards;
        _mcqCount = mcqs;
        _caseCount = cases;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _error = 'تعذّر تحميل المكتبة.';
        _loading = false;
      });
    }
  }

  Future<void> _reloadFromScratch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
  }

  /// فتح شاشة بنك (بلا وحدة — الشاشة تدير فلترتها بنفسها).
  Future<void> _push(Widget page) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<Widget>(builder: (_) => page),
    );
    // عند العودة — تحديث العدّادات (استيراد/حذف محاضرة مثلاً).
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'إعادة المحاولة',
        onAction: _reloadFromScratch,
      );
    }

    // v20: التخصص النشط — يمرر للبنوك ويكتب حاوية العدادات بلونه.
    // القراءة محمية داخل SpecialtyScope — أي طور مبكر يسقط للباطنية.
    final String specialty = SpecialtyScope.effectiveOf(context);
    final SpecialtyScope? scope = SpecialtyScope.of(context);
    final bool showBar = scope != null && scope.specialties.length > 1;

    return RefreshIndicator(
      onRefresh: _load,
      // تجاوب: قائمة على الموبايل (عمود واحد) — شبكة 2/3 أعمدة
      // على التابلت الطولي/العرضي (gridColumns الديناميكي).
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (showBar) ...<Widget>[
                    SpecialtySegmentBar(
                      specialty: scope.specialty,
                      specialties: scope.specialties,
                      onChanged: SpecialtyScope.changeOf(context),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SectionHeader(
                    'المكتبة',
                    subtitle:
                        'مراجع ${AppColors.specialtyNameAr(specialty)} في مكان واحد',
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ResponsiveLayout.gridColumns(context),
                mainAxisSpacing: ResponsiveLayout.gridSpacing,
                crossAxisSpacing: ResponsiveLayout.gridSpacing,
                childAspectRatio: ResponsiveLayout.gridChildAspectRatio(
                  ResponsiveLayout.gridColumns(context),
                ),
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  final Brightness b =
                      Theme.of(context).colorScheme.brightness;
                  return <Widget>[
                    // ── الشروحات ──
                    _LibraryCard(
                      emoji: 'icon_concept',
                      title: 'مكتبة الشروحات',
                      subtitle: 'الشروحات الفسيولوجية والسريرية المفصلة',
                      count: _conceptCount,
                      countLabel: 'شرحاً',
                      accent: AppColors.success(b),
                      warmAccent: AppGradients.warmSage,
                      onTap: () => _push(ConceptLibraryPage(
                        specialty: specialty,
                      )),
                    ),

                    // ── البطاقات ──
                    _LibraryCard(
                      emoji: 'icon_flashcards',
                      title: 'بنك البطاقات',
                      subtitle:
                          'فلترة ذكية (جهاز/محاضرة) + مراجعة عشوائية لما دُرس',
                      count: _flashcardCount,
                      countLabel: 'بطاقة',
                      accent: AppColors.gold(b),
                      warmAccent: AppGradients.warmGold,
                      onTap: () => _push(FlashcardBankPage(
                        specialty: specialty,
                      )),
                    ),

                    // ── بنك الأسئلة ──
                    _LibraryCard(
                      emoji: 'icon_quiz',
                      title: 'بنك الأسئلة',
                      subtitle: 'أسئلة MCQ بفلترة وترتيب ذكي مع الشرح',
                      count: _mcqCount,
                      countLabel: 'سؤالاً',
                      accent: AppColors.specialtyPrimary(specialty, b),
                      warmAccent: AppGradients.warmGold,
                      onTap: () => _push(McqBankPage(
                        specialty: specialty,
                      )),
                    ),

                    // ── الحالات السريرية ──
                    _LibraryCard(
                      emoji: 'icon_case',
                      title: 'الحالات السريرية',
                      subtitle: 'حالات OSCE بفلترة ذكية — انقر أي حالة لبدئها',
                      count: _caseCount,
                      countLabel: 'حالة',
                      accent: AppColors.error(b),
                      warmAccent: AppGradients.warmCoral,
                      onTap: () => _push(CaseBankPage(
                        specialty: specialty,
                      )),
                    ),
                  ][index];
                },
                childCount: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة قسم موحدة — تتكيف مع الشبكة: عمودية (أيقونة فوق والمحتوى
/// تحت) على الشاشات الواسعة، وصفية على الموبايل (سطر واحد أنيق).
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.countLabel,
    required this.accent,
    this.warmAccent,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final int count;
  final String countLabel;
  final Color accent;

  /// تدرّج الهوية الدافئ (ذهبي/مرجاني/حكيم) — خلفية أيقونة مميزة
  /// تعكس ألوان الرسوم المرساة بدل اللون المفرد (اختياري، محافظ).
  final List<Color>? warmAccent;

  final VoidCallback onTap;

  /// ظرف الأيقونة — إمّا خلفية اللون المفرد النمطية، أو تدرّج الهوية
  /// الدافئ المختار لتسليط الضوء على القسم دون كسر التماسك.
  Widget _iconContainer(Brightness b, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: warmAccent != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: warmAccent!,
              )
            : null,
        color: warmAccent == null
            ? accent.withValues(alpha: 0.12)
            : null,
        borderRadius: BorderRadius.circular(AppRadius.chip + 2),
      ),
      child: Center(
        child: AppIllustration(
          emoji,
          size: size,
          borderRadius: BorderRadius.circular(AppRadius.chip + 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    // تجاوب: صف واحد على الموبايل — عمودي داخل شبكة التابلت.
    final bool asGrid =
        ResponsiveLayout.gridColumns(context) > 1;

    return AppCard(
      onTap: onTap,
      accent: accent,
      child: asGrid
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _iconContainer(b, 44),
                    const Spacer(),
                    Icon(Icons.chevron_left_rounded,
                        color: AppColors.textSecondary(b)),
                  ],
                ),
                const Spacer(),
                Text(title,
                    style: AppType.cardTitle.copyWith(
                        fontSize: 16, color: AppColors.text(b))),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppType.body.copyWith(
                      fontSize: 11.5,
                      color: AppColors.textSecondary(b)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  '$count $countLabel',
                  style: AppType.caption.copyWith(
                      color: accent, fontWeight: FontWeight.w800),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                _iconContainer(b, 52),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: AppType.cardTitle.copyWith(
                              fontSize: 17, color: AppColors.text(b))),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppType.body.copyWith(
                            fontSize: 12.5, color: AppColors.textSecondary(b)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$count $countLabel',
                        style: AppType.caption.copyWith(
                            color: accent, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded,
                    color: AppColors.textSecondary(b)),
              ],
            ),
    );
  }
}
