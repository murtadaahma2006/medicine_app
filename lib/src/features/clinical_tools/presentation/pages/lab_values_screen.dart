import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../data/lab_values_repository.dart';
import '../../domain/lab_values_model.dart';

class LabValuesScreen extends StatefulWidget {
  const LabValuesScreen({super.key});

  @override
  State<LabValuesScreen> createState() => _LabValuesScreenState();
}

class _LabValuesScreenState extends State<LabValuesScreen> {
  List<LabCategory> _categories = <LabCategory>[];
  List<LabCategory> _filteredCategories = <LabCategory>[];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final List<LabCategory> data = await LabValuesRepository.loadLabValues();
    if (mounted) {
      setState(() {
        _categories = data;
        _filteredCategories = data;
        _loading = false;
      });
    }
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredCategories = _categories;
      } else {
        _filteredCategories = _categories.map((LabCategory category) {
          final List<LabTest> filteredTests = category.tests.where((LabTest test) {
            return test.name.toLowerCase().contains(_searchQuery);
          }).toList();
          return LabCategory(category: category.category, tests: filteredTests);
        }).where((LabCategory category) => category.tests.isNotEmpty).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Scaffold(
      appBar: AppBar(
        title: const Text('القيم المخبرية'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: CupertinoSearchTextField(
              placeholder: 'ابحث عن تحليل (مثال: Hb, K+)...',
              style: AppType.body.copyWith(color: AppColors.text(b)),
              onChanged: _onSearch,
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filteredCategories.isEmpty
              ? Center(
                  child: Text(
                    'لا توجد نتائج مطابقة',
                    style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  itemCount: _filteredCategories.length,
                  itemBuilder: (BuildContext context, int index) {
                    final LabCategory category = _filteredCategories[index];
                    return _CategoryTile(category: category);
                  },
                ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final LabCategory category;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          category.category,
          style: AppType.cardTitle.copyWith(color: AppColors.primary(b)),
          textDirection: TextDirection.ltr,
        ),
        children: category.tests.map((LabTest test) => _TestItem(test: test)).toList(),
      ),
    );
  }
}

class _TestItem extends StatelessWidget {
  const _TestItem({required this.test});

  final LabTest test;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            test.name,
            style: AppType.cardTitle.copyWith(fontSize: 16),
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: _RangePill(
                  label: 'Male',
                  range: test.normalRangeMale,
                  icon: Icons.male_rounded,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _RangePill(
                  label: 'Female',
                  range: test.normalRangeFemale,
                  icon: Icons.female_rounded,
                  color: Colors.pink.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _IndicationRow(
            icon: Icons.arrow_upward_rounded,
            color: AppColors.error(b),
            title: 'High (↑)',
            text: test.highIndication,
          ),
          const SizedBox(height: AppSpacing.xs),
          _IndicationRow(
            icon: Icons.arrow_downward_rounded,
            color: Colors.blue.shade400,
            title: 'Low (↓)',
            text: test.lowIndication,
          ),
        ],
      ),
    );
  }
}

class _RangePill extends StatelessWidget {
  const _RangePill({
    required this.label,
    required this.range,
    required this.icon,
    required this.color,
  });

  final String label;
  final String range;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppType.caption.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            range,
            style: AppType.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text(b),
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

class _IndicationRow extends StatelessWidget {
  const _IndicationRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: AppType.caption.copyWith(color: color, fontWeight: FontWeight.w700),
                textDirection: TextDirection.ltr,
              ),
              Text(
                text,
                style: AppType.body.copyWith(fontSize: 13, color: AppColors.textSecondary(b)),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
