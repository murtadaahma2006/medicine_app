import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../curriculum/presentation/pages/mcq_session_page.dart';
import '../widgets/bank_filter_panel.dart';

/// ─────────────────────────────────────────────────────────────────────
/// بنك الأسئلة — تصفح أسئلة MCQ بفلترة ذكية (جهاز × محاضرة × ترتيب).
///
/// كل سؤال صف قابل للتوسيع يعرض الخيارات + الصحيح + الشرح العربي.
/// زر «ابدأ اختباراً» يشغّل جلسة MCQ على المحاضرة المختارة (أو
/// أول محاضرات الفلتر إن اختار «الكل»).
/// ─────────────────────────────────────────────────────────────────────
class McqBankPage extends StatefulWidget {
  const McqBankPage({this.specialty, super.key});

  /// v20: حصر البنك داخل تخصص سريري واحد (null = كل التخصصات).
  final String? specialty;

  @override
  State<McqBankPage> createState() => _McqBankPageState();
}

class _McqBankPageState extends State<McqBankPage> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  String? get _specialty => widget.specialty;

  List<String> _systems = const <String>[];
  List<Map<String, Object?>> _lectures = const <Map<String, Object?>>[];
  String? _selectedSystem;
  String? _selectedLectureId;
  bool _isRandom = false;

  List<Map<String, Object?>> _mcqs = const <Map<String, Object?>>[];

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
        _error = 'تعذّر تحميل بنك الأسئلة.';
        _loading = false;
      });
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final List<Map<String, Object?>> mcqs = await _db.getMcqs(
        specialty: _specialty,
        system: _selectedSystem,
        lectureId: _selectedLectureId,
        isRandom: _isRandom,
      );
      if (!mounted) return;
      setState(() {
        _mcqs = mcqs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الأسئلة.';
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

  Future<void> _startDrill() async {
    // اختبار الفلتر الحالي: على المحاضرة المختارة أو أول محاضرة
    // ضمن الجهاز (أو أول محاضرة إطلاقاً عند «كل الأجهزة»).
    final String? unitId =
        _selectedLectureId ?? (_lectures.isEmpty ? null : _lectures.first['id']! as String);
    if (unitId == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) => McqSessionPage(unitId: unitId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بنك الأسئلة')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _mcqs.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _mcqs.isEmpty) {
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
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${_mcqs.length} سؤالاً',
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary(
                        Theme.of(context).colorScheme.brightness),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _lectures.isEmpty ? null : _startDrill,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('ابدأ اختباراً'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _mcqs.isEmpty
              ? const EmptyState(
                  icon: Icons.quiz_rounded,
                  mascot: 'puzzled',
                  title: 'لا أسئلة ضمن هذا الفلتر',
                  subtitle: 'جرّب جهازاً أو محاضرة أخرى',
                )
              : RefreshIndicator(
                  onRefresh: _loadItems,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl,
                    ),
                    itemCount: _mcqs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (BuildContext context, int index) =>
                        _McqRow(mcq: _mcqs[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// صف سؤال MCQ — قابل للتوسيع: الخيارات + الصحيح + الشرح.
class _McqRow extends StatelessWidget {
  const _McqRow({required this.mcq});

  final Map<String, Object?> mcq;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    final String stem = (mcq['question_stem'] as String?) ?? '';
    final List<dynamic> options =
        (jsonDecode((mcq['options_json'] as String?) ?? '[]') as List)
            .cast<dynamic>();
    final int correct = ((mcq['correct_index'] as num?)?.toInt()) ?? 0;
    final String? explanation = mcq['explanation_ar'] as String?;
    final bool isVignette = ((mcq['clinical_vignette'] as num?)?.toInt()) == 1;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding:
              const EdgeInsets.only(bottom: AppSpacing.md, left: 4),
          iconColor: AppColors.textSecondary(b),
          collapsedIconColor: AppColors.textSecondary(b),
          title: Text(
            stem,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: AppColors.text(b),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: <Widget>[
                if (isVignette) ...<Widget>[
                  Icon(Icons.medical_services_rounded,
                      size: 13,
                      color: AppColors.module('infectious', b)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'سيناريو سريري',
                    style: AppType.caption.copyWith(
                      fontSize: 10.5,
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  '${options.length} خيارات',
                  style: AppType.caption.copyWith(
                    fontSize: 10.5,
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
            ),
          ),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // الخيارات — الصحيح مميز.
                for (int i = 0; i < options.length; i++)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          i == correct
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 17,
                          color: i == correct
                              ? AppColors.success(b)
                              : AppColors.textSecondary(b)
                                  .withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            options[i].toString(),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                            style: AppType.body.copyWith(
                              fontSize: 13,
                              fontWeight: i == correct
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: i == correct
                                  ? AppColors.success(b)
                                  : AppColors.text(b),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // الشرح العربي.
                if (explanation != null && explanation.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint(b),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      explanation,
                      style: AppType.body.copyWith(
                        fontSize: 12.5,
                        height: 1.6,
                        color: AppColors.text(b),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
