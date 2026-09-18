import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../theme/tokens.dart';
import '../pages/concept_reader_page.dart';

class GlobalSearchDelegate extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => 'ابحث عن أي مصطلح أو موضوع...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: AppColors.surface(b),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(fontSize: 16),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return <Widget>[
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchBody(query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SearchBody(query: query);
  }
}

class _SearchBody extends StatefulWidget {
  final String query;
  const _SearchBody({required this.query});

  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  Timer? _debounce;
  List<Map<String, dynamic>>? _results;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _executeSearch(widget.query);
  }

  @override
  void didUpdateWidget(_SearchBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _executeSearch(widget.query);
    }
  }

  void _executeSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _results = <Map<String, dynamic>>[];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final List<Map<String, dynamic>> results = await DatabaseHelper.instance.searchConcepts(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _extractSnippet(String sectionsJson, String query) {
    try {
      final List<dynamic> sections = jsonDecode(sectionsJson) as List<dynamic>;
      for (final dynamic s in sections) {
        if (s is! Map<String, dynamic>) continue;
        final String bodyText = (s['body_text'] as String?) ?? '';
        final String lowerBody = bodyText.toLowerCase();
        final String lowerQuery = query.toLowerCase();
        final int index = lowerBody.indexOf(lowerQuery);
        
        if (index != -1) {
          final int start = (index - 40).clamp(0, bodyText.length);
          final int end = (index + query.length + 40).clamp(0, bodyText.length);
          String snippet = bodyText.substring(start, end).replaceAll('\n', ' ');
          // إزالة علامات الخط العريض إن وجدت للتنظيف
          snippet = snippet.replaceAll('**', '');
          if (start > 0) snippet = '...$snippet';
          if (end < bodyText.length) snippet = '$snippet...';
          return snippet;
        }
      }
    } catch (_) {}
    return '';
  }

  IconData _getSpecialtyIcon(String specialty) {
    switch (specialty) {
      case 'surgery':
        return Icons.healing_rounded;
      case 'obgyn':
        return Icons.pregnant_woman_rounded;
      case 'internal_medicine':
      default:
        return Icons.monitor_heart_rounded;
    }
  }

  Color _getSpecialtyColor(String specialty, Brightness b) {
    switch (specialty) {
      case 'surgery':
        return Colors.red.shade400;
      case 'obgyn':
        return Colors.pink.shade400;
      case 'internal_medicine':
      default:
        return AppColors.primary(b);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results == null || _results!.isEmpty) {
      if (widget.query.trim().isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.search_rounded, size: 64, color: AppColors.border(b)),
              const SizedBox(height: AppSpacing.md),
              Text(
                'ابحث عن أي مرض، عَرَض، أو مصطلح',
                style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Text(
          'لا توجد نتائج مطابقة لبحثك.',
          style: AppType.body.copyWith(color: AppColors.textSecondary(b)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      itemCount: _results!.length,
      separatorBuilder: (_, __) => Divider(color: AppColors.border(b), height: 1),
      itemBuilder: (BuildContext context, int index) {
        final Map<String, dynamic> item = _results![index];
        final String title = item['concept_title'] as String;
        final String unitTitle = item['unit_title'] as String;
        final String specialty = (item['specialty'] as String?) ?? 'internal_medicine';
        final String sectionsJson = item['sections_json'] as String;
        final String snippet = _extractSnippet(sectionsJson, widget.query.trim());

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          leading: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: _getSpecialtyColor(specialty, b).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getSpecialtyIcon(specialty),
              color: _getSpecialtyColor(specialty, b),
              size: 24,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: _getSpecialtyColor(specialty, b).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: _getSpecialtyColor(specialty, b).withValues(alpha: 0.2)),
                ),
                child: Text(
                  unitTitle,
                  style: AppType.caption.copyWith(
                    color: _getSpecialtyColor(specialty, b),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                title,
                style: AppType.cardTitle.copyWith(fontSize: 16),
              ),
            ],
          ),
          subtitle: snippet.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    snippet,
                    style: AppType.caption.copyWith(color: AppColors.textSecondary(b)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : null,
          onTap: () {
            // توجيه ذكي يتخطى حالة الاستئناف بحركة iPad الأصلية
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ConceptReaderPage(
                  unitId: item['unit_id'] as String,
                  unitTitle: unitTitle,
                  initialConceptId: item['concept_id'] as String, // المعرّف السحري للقفز
                ),
              ),
            );
          },
        );
      },
    );
  }
}
