import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../curriculum/presentation/pages/concept_reader_page.dart';
import '../widgets/bank_filter_panel.dart';

/// ─────────────────────────────────────────────────────────────────────
/// مكتبة الشروحات — تصفح المفاهيم (Concepts) بفلترة ذكية.
///
/// كل شرح صف يعرض عنوانه؛ النقر يفتح قارئ الشروحات للمحاضرة
/// المعنية على الشرح المختار.
/// ─────────────────────────────────────────────────────────────────────
class ConceptLibraryPage extends StatefulWidget {
  const ConceptLibraryPage({super.key});

  @override
  State<ConceptLibraryPage> createState() => _ConceptLibraryPageState();
}

class _ConceptLibraryPageState extends State<ConceptLibraryPage> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<String> _systems = const <String>[];
  List<Map<String, Object?>> _lectures = const <Map<String, Object?>>[];
  String? _selectedSystem;
  String? _selectedLectureId;
  bool _isRandom = false;

  List<Map<String, Object?>> _concepts = const <Map<String, Object?>>[];

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
      final List<String> systems = await _db.getDistinctSystems();
      final List<Map<String, Object?>> lectures =
          await _db.getUnitsBySystem(_selectedSystem);

      if (!mounted) return;
      setState(() {
        _systems = systems;
        _lectures = lectures;
      });
      await _loadItems();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الشروحات.';
        _loading = false;
      });
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final Database db = await _db.database;
      final List<String> where = <String>[];
      final List<Object?> args = <Object?>[];
      if (_selectedLectureId != null) {
        where.add('c.unit_id = ?');
        args.add(_selectedLectureId);
      } else if (_selectedSystem != null) {
        where.add('u.system = ?');
        args.add(_selectedSystem);
      }
      final String whereSql =
          where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final String orderSql =
          _isRandom ? 'RANDOM()' : 'u.order_index, u.id, c.order_index, c.id';

      final List<Map<String, Object?>> concepts = await db.rawQuery('''
        SELECT c.*, u.title AS unit_title
        FROM ${DatabaseHelper.tableConcepts} c
        INNER JOIN ${DatabaseHelper.tableUnits} u ON u.id = c.unit_id
        $whereSql
        ORDER BY $orderSql
      ''', args);

      if (!mounted) return;
      setState(() {
        _concepts = concepts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الشروحات.';
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

  Future<void> _openConcept(Map<String, Object?> concept) async {
    await Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) =>
          ConceptReaderPage(unitId: concept['unit_id']! as String),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مكتبة الشروحات')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _concepts.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _concepts.isEmpty) {
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
              '${_concepts.length} شرحاً',
              style: AppType.caption.copyWith(
                color: AppColors.textSecondary(
                    Theme.of(context).colorScheme.brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Expanded(
          child: _concepts.isEmpty
              ? const EmptyState(
                  icon: Icons.menu_book_rounded,
                  mascot: 'puzzled',
                  title: 'لا شروحات ضمن هذا الفلتر',
                  subtitle: 'جرّب جهازاً أو محاضرة أخرى',
                )
              : RefreshIndicator(
                  onRefresh: _loadItems,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl,
                    ),
                    itemCount: _concepts.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (BuildContext context, int index) =>
                        _ConceptRow(
                      concept: _concepts[index],
                      onTap: () => _openConcept(_concepts[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// صف شرح — عنوان + محاضرته + الصعوبة.
class _ConceptRow extends StatelessWidget {
  const _ConceptRow({required this.concept, required this.onTap});

  final Map<String, Object?> concept;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final String title = (concept['title'] as String?) ?? '';
    final String unitTitle =
        ((concept['unit_title'] as String?) ?? '').trim();
    final String difficulty = (concept['difficulty'] as String?) ?? 'core';
    final bool advanced = difficulty == 'advanced';

    return AppCard(
      accent: AppColors.success(b),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.success(b).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(Icons.menu_book_rounded,
                size: 20, color: AppColors.success(b)),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text(b),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  unitTitle,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
            ),
          ),
          if (advanced)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Text(
                'متقدم',
                style: AppType.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.module('oncology', b),
                ),
              ),
            ),
          Icon(Icons.chevron_left_rounded,
              color: AppColors.textSecondary(b).withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}
