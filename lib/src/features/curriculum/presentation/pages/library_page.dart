import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../library/presentation/pages/case_bank_page.dart';
import '../../../library/presentation/pages/concept_library_page.dart';
import '../../../library/presentation/pages/flashcard_bank_page.dart';
import '../../../library/presentation/pages/mcq_bank_page.dart';

/// شاشة «المكتبة» — اللسان الثالث: كل الأقسام المرجعية للتطبيق
/// في مكان واحد ببطاقات موحدة (أيقونة + عنوان + وصف + عدّاد).
///
/// كل قسم يفتح نشاطه على أول وحدة مزروعة (تبسيط المرحلة الأولى؛
/// اختيار الوحدة التفصيلي من شاشة المسار).
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _loading = true;
  String? _error;

  // العدّادات الحقيقية لكل قسم.
  int _conceptCount = 0;
  int _flashcardCount = 0;
  int _mcqCount = 0;
  int _caseCount = 0;

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
      final int concepts = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableConcepts}',
      );
      final int flashcards = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableFlashcards}',
      );
      final int mcqs = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableMcqBank}',
      );
      final int cases = await db.rawCount(
        'SELECT COUNT(*) FROM ${DatabaseHelper.tableClinicalCases}',
      );

      if (!mounted) return;
      setState(() {
        _conceptCount = concepts;
        _flashcardCount = flashcards;
        _mcqCount = mcqs;
        _caseCount = cases;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل المكتبة.';
        _loading = false;
      });
    }
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
    final Brightness b = Theme.of(context).colorScheme.brightness;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'إعادة المحاولة',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        children: <Widget>[
          const SectionHeader(
            'المكتبة',
            subtitle: 'كل مراجعك الطبية في مكان واحد',
          ),

          // ── الشروحات ──
          _LibraryCard(
            emoji: 'icon_concept',
            title: 'مكتبة الشروحات',
            subtitle: 'الشروحات الفسيولوجية والسريرية المفصلة',
            count: _conceptCount,
            countLabel: 'شرحاً',
            accent: AppColors.success(b),
            onTap: () => _push(const ConceptLibraryPage()),
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── البطاقات ──
          _LibraryCard(
            emoji: 'icon_flashcards',
            title: 'بنك البطاقات',
            subtitle: 'فلترة ذكية (جهاز/محاضرة) + مراجعة عشوائية لما دُرس',
            count: _flashcardCount,
            countLabel: 'بطاقة',
            accent: AppColors.gold(b),
            onTap: () => _push(const FlashcardBankPage()),
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── بنك الأسئلة ──
          _LibraryCard(
            emoji: 'icon_quiz',
            title: 'بنك الأسئلة',
            subtitle: 'أسئلة MCQ بفلترة وترتيب ذكي مع الشرح',
            count: _mcqCount,
            countLabel: 'سؤالاً',
            accent: AppColors.primary(b),
            onTap: () => _push(const McqBankPage()),
          ),

          const SizedBox(height: AppSpacing.betweenCards),

          // ── الحالات السريرية ──
          _LibraryCard(
            emoji: 'icon_case',
            title: 'الحالات السريرية',
            subtitle: 'حالات OSCE بفلترة ذكية — انقر أي حالة لبدئها',
            count: _caseCount,
            countLabel: 'حالة',
            accent: AppColors.error(b),
            onTap: () => _push(const CaseBankPage()),
          ),

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

/// بطاقة قسم موحدة — أيقونة + عنوان + وصف + عدّاد + شريط جانبي.
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.countLabel,
    required this.accent,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final int count;
  final String countLabel;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AppCard(
      onTap: onTap,
      accent: accent,
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip + 2),
            ),
            child: Center(
              child: AppIllustration(
                emoji,
                size: 52,
                borderRadius: BorderRadius.circular(AppRadius.chip + 2),
              ),
            ),
          ),
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
          Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary(b)),
        ],
      ),
    );
  }
}
