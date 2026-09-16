import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../curriculum/presentation/pages/clinical_case_player_page.dart';
import '../widgets/bank_filter_panel.dart';

/// ─────────────────────────────────────────────────────────────────────
/// بنك الحالات السريرية — تصفح حالات OSCE بفلترة ذكية.
///
/// كل حالة صف يعرض عنوانها + سيناريو مختصراً؛ النقر يفتح مشغل
/// الحالة (ClinicalCasePlayerPage) مباشرة.
/// ─────────────────────────────────────────────────────────────────────
class CaseBankPage extends StatefulWidget {
  const CaseBankPage({this.specialty, super.key});

  /// v20: حصر البنك داخل تخصص سريري واحد (null = كل التخصصات).
  final String? specialty;

  @override
  State<CaseBankPage> createState() => _CaseBankPageState();
}

class _CaseBankPageState extends State<CaseBankPage> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  String? get _specialty => widget.specialty;

  List<String> _systems = const <String>[];
  List<Map<String, Object?>> _lectures = const <Map<String, Object?>>[];
  String? _selectedSystem;
  String? _selectedLectureId;
  bool _isRandom = false;

  List<Map<String, Object?>> _cases = const <Map<String, Object?>>[];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<String> systems =
          await _db.getDistinctSystems(specialty: _specialty);
      final List<Map<String, Object?>> lectures =
          await _db.getUnitsBySystem(
        _selectedSystem,
        specialty: _specialty,
      );

      if (!mounted) return;
      setState(() {
        _systems = systems;
        _lectures = lectures;
      });
      await _loadItems();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الحالات السريرية.';
        _loading = false;
      });
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final List<Map<String, Object?>> cases = await _db.getCases(
        specialty: _specialty,
        system: _selectedSystem,
        lectureId: _selectedLectureId,
        isRandom: _isRandom,
      );
      if (!mounted) return;
      setState(() {
        _cases = cases;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الحالات.';
        _loading = false;
      });
    }
  }

  Future<void> _onSystemChanged(String? system) async {
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

  Future<void> _openCase(String caseId) async {
    await Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) => ClinicalCasePlayerPage(caseId: caseId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الحالات السريرية')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _cases.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _cases.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'إعادة المحاولة',
        onAction: _loadAll,
      );
    }

    return Column(
      children: <Widget>[
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
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_cases.length} حالة',
              style: AppType.caption.copyWith(
                color: AppColors.textSecondary(
                    Theme.of(context).colorScheme.brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Expanded(
          child: _cases.isEmpty
              ? const EmptyState(
                  icon: Icons.medical_information_rounded,
                  mascot: 'puzzled',
                  title: 'لا حالات ضمن هذا الفلتر',
                  subtitle: 'جرّب جهازاً أو محاضرة أخرى',
                )
              : RefreshIndicator(
                  onRefresh: _loadItems,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl,
                    ),
                    itemCount: _cases.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (BuildContext context, int index) =>
                        _CaseRow(
                      caseRow: _cases[index],
                      onTap: () => _openCase(
                          _cases[index]['id']! as String),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// صف حالة سريرية — عنوان + سيناريو مختصر + فتح المشغل.
class _CaseRow extends StatelessWidget {
  const _CaseRow({required this.caseRow, required this.onTap});

  final Map<String, Object?> caseRow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final String title = (caseRow['title'] as String?) ?? '';
    final String scenario = (caseRow['scenario'] as String?) ?? '';

    return AppCard(
      accent: AppColors.error(b),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.error(b).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(Icons.medical_services_rounded,
                size: 21, color: AppColors.error(b)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text(b),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  scenario,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded,
              color: AppColors.textSecondary(b).withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}
