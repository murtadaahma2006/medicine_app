import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../widgets/bank_filter_panel.dart';
import 'flashcard_bank_session_page.dart';

/// ─────────────────────────────────────────────────────────────────────
/// بنك البطاقات — تصفح كل البطاقات بفلترة ذكية.
///
/// لوحة تحكم: (جهاز × محاضرة) + ترتيب (منهجي/عشوائي) + زر «مراجعة
/// عشوائية لما تمت دراسته» يفتح FlashcardBankSessionPage ببطاقات
/// المحاضرات المدروسة فقط.
///
/// أي تغيير فلتر يعيد الاستعلام فوراً (setState → _loadItems).
/// ─────────────────────────────────────────────────────────────────────
class FlashcardBankPage extends StatefulWidget {
  const FlashcardBankPage({super.key});

  @override
  State<FlashcardBankPage> createState() => _FlashcardBankPageState();
}

class _FlashcardBankPageState extends State<FlashcardBankPage> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // ── حالة الفلترة ──
  List<String> _systems = const <String>[];
  List<Map<String, Object?>> _lectures = const <Map<String, Object?>>[];
  String? _selectedSystem;
  String? _selectedLectureId;
  bool _isRandom = false;

  // ── نتائج العرض ──
  List<Map<String, Object?>> _cards = const <Map<String, Object?>>[];
  int _studiedCount = 0;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// تحميل القوائم المساعدة (الأجهزة + محاضرات الجهاز المختار)
  /// ثم العناصر الفلترة.
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<String> systems = await _db.getDistinctSystems();
      final List<Map<String, Object?>> lectures =
          await _db.getUnitsBySystem(_selectedSystem);
      final int studied = (await _db.getStudiedFlashcards(
        system: _selectedSystem,
      ))
          .length;

      if (!mounted) return;
      setState(() {
        _systems = systems;
        _lectures = lectures;
        _studiedCount = studied;
      });

      await _loadItems();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل بنك البطاقات.';
        _loading = false;
      });
    }
  }

  /// الاستعلام الفلتري الفعلي — يعاد عند كل تغيير فلتر.
  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final List<Map<String, Object?>> cards = await _db.getFlashcards(
        system: _selectedSystem,
        lectureId: _selectedLectureId,
        isRandom: _isRandom,
      );
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل البطاقات.';
        _loading = false;
      });
    }
  }

  // ─────────────────── معالجات الفلترة (تحدّث فوراً) ───────────────────

  Future<void> _onSystemChanged(String? system) async {
    // تغيير الجهاز يعيد ضبط المحاضرة (قائمتها ستتغير).
    _selectedSystem = system;
    _selectedLectureId = null;
    await _loadAll();
  }

  Future<void> _onLectureChanged(String? lectureId) async {
    _selectedLectureId = lectureId;
    await _loadItems();
  }

  Future<void> _onSortChanged(bool random) async {
    _isRandom = random;
    await _loadItems();
  }

  Future<void> _openStudiedReview() async {
    if (_studiedCount == 0) return;
    await Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) => FlashcardBankSessionPage(
        system: _selectedSystem,
      ),
    ));
    // عند العودة — قد تغيّرت حالة «المدروس» (سجل تقدم جديد).
    await _loadAll();
  }

  // ───────────────────────────── البناء ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بنك البطاقات')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _cards.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _cards.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'إعادة المحاولة',
        onAction: _loadAll,
      );
    }

    return Column(
      children: <Widget>[
        // ── لوحة التحكم (فوق القائمة، ثابتة) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0,
          ),
          child: BankFilterPanel(
            systems: _systems,
            selectedSystem: _selectedSystem,
            lectures: _lectures,
            selectedLectureId: _selectedLectureId,
            isRandom: _isRandom,
            onSystemChanged: _onSystemChanged,
            onLectureChanged: _onLectureChanged,
            onSortChanged: _onSortChanged,
            showStudiedReviewButton: true,
            studiedCount: _studiedCount,
            onStudiedReview: _openStudiedReview,
          ),
        ),

        // ── عدّاد النتائج ──
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Text(
                '${_cards.length} بطاقة',
                style: AppType.caption.copyWith(
                  color: Theme.of(context).colorScheme.brightness == Brightness.dark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_isRandom) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.shuffle_rounded, size: 14,
                    color: AppColors.gold(
                        Theme.of(context).colorScheme.brightness)),
                const SizedBox(width: AppSpacing.xs),
                Text('ترتيب عشوائي',
                    style: AppType.caption.copyWith(
                      color: AppColors.gold(
                          Theme.of(context).colorScheme.brightness),
                      fontSize: 11,
                    )),
              ],
            ],
          ),
        ),

        // ── قائمة البطاقات ──
        Expanded(
          child: _cards.isEmpty
              ? const EmptyState(
                  icon: Icons.style_rounded,
                  mascot: 'puzzled',
                  title: 'لا بطاقات ضمن هذا الفلتر',
                  subtitle: 'جرّب جهازاً أو محاضرة أخرى',
                )
              : RefreshIndicator(
                  onRefresh: _loadItems,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl,
                    ),
                    itemCount: _cards.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (BuildContext context, int index) =>
                        _FlashcardRow(card: _cards[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// صف بطاقة واحدة — قابل للتوسيع: عند التوسعة يظهر **وجه البطاقة
/// كاملاً** ثم تحته ظهرها (الإجابة) — بلا قصّ للنصوص.
class _FlashcardRow extends StatelessWidget {
  const _FlashcardRow({required this.card});

  final Map<String, Object?> card;

  String get _front => (card['front_text'] as String?) ?? '';
  String get _back => (card['back_text'] as String?) ?? '';
  String? get _mnemonic => card['mnemonic_ar'] as String?;
  String? get _explanation => card['explanation_ar'] as String?;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
          iconColor: AppColors.textSecondary(b),
          collapsedIconColor: AppColors.textSecondary(b),
          title: Text(
            _front,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.text(b),
            ),
          ),
          subtitle: Text(
            _lectureTitle(),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: AppType.caption.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary(b),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(b),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // ── وجه البطاقة كاملاً (بلا قصّ) ──
                    Text(
                      _front,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                      style: AppType.body.copyWith(
                        fontSize: 13.5,
                        height: 1.55,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text(b),
                      ),
                    ),
                    // ── فاصل بصري بين الوجهين ──
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Container(
                              height: 1,
                              color:
                                  AppColors.border(b),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm),
                            child: Icon(Icons.swap_vert_rounded,
                                size: 14,
                                color: AppColors.textSecondary(b)
                                    .withValues(alpha: 0.7)),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: AppColors.border(b),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── ظهر البطاقة (الإجابة) ──
                    Text(
                      _back,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                      style: AppType.body.copyWith(
                        fontSize: 13,
                        height: 1.55,
                        color: AppColors.text(b),
                      ),
                    ),
                    if (_mnemonic != null || _explanation != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      if (_mnemonic != null)
                        Text(
                          'حيلة الحفظ: $_mnemonic',
                          style: AppType.body.copyWith(
                            fontSize: 12.5,
                            color: AppColors.goldText(b),
                          ),
                        ),
                      if (_explanation != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _explanation!,
                          style: AppType.body.copyWith(
                            fontSize: 12.5,
                            color: AppColors.textSecondary(b),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _lectureTitle() {
    final String? unitTitle = card['unit_title'] as String?;
    return (unitTitle ?? card['unit_id'] as String?) ?? '';
  }
}
