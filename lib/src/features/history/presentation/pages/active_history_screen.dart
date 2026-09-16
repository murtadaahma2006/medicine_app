import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../data/models/history_field.dart';
import '../../data/models/history_section.dart';
import '../../data/models/history_template.dart';
import '../../data/models/lab_reference.dart';
import '../../data/services/history_template_service.dart';

class ActiveHistoryScreen extends StatefulWidget {
  const ActiveHistoryScreen({
    super.key,
    this.templatePath = 'assets/data/history_template.json',
  });

  final String templatePath;

  @override
  State<ActiveHistoryScreen> createState() => _ActiveHistoryScreenState();
}

class _ActiveHistoryScreenState extends State<ActiveHistoryScreen> {
  HistoryTemplate? _template;
  bool _isLoading = true;
  String? _error;

  final Map<String, dynamic> _currentAnswers = <String, dynamic>{};
  final HistoryTemplateService _service = HistoryTemplateService();

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    try {
      final HistoryTemplate template = await _service.loadTemplate(widget.templatePath);
      setState(() {
        _template = template;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveHistory() async {
    final TextEditingController aliasController = TextEditingController();
    
    final String? alias = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Save Patient Record'),
        content: TextField(
          controller: aliasController,
          decoration: const InputDecoration(
            labelText: 'Patient Alias / Initials',
            hintText: 'e.g., J.D. or Bed 4',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final String text = aliasController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(context, text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (alias != null && alias.isNotEmpty && mounted) {
      final String responsesJson = jsonEncode(_currentAnswers);
      await DatabaseHelper.instance.insertPatientRecord(alias, responsesJson);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Record saved successfully!')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('New History')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New History')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Error loading template: $_error', style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    if (_template == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New History')),
        body: const Center(child: Text('Template not found.')),
      );
    }

    return DefaultTabController(
      length: _template!.sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New History'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _template!.sections.map((HistorySection s) => Tab(text: s.title)).toList(),
          ),
          actions: <Widget>[
            Builder(
              builder: (BuildContext context) {
                return IconButton(
                  icon: const Icon(Icons.science),
                  tooltip: 'Lab References',
                  onPressed: () {
                    Scaffold.of(context).openEndDrawer();
                  },
                );
              }
            ),
            TextButton.icon(
              onPressed: _saveHistory,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        endDrawer: _buildLabValuesDrawer(),
        body: TabBarView(
          children: _template!.sections.map((HistorySection section) {
            return ListView.separated(
              padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
              itemCount: section.fields.length,
              separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 24),
              itemBuilder: (BuildContext context, int index) {
                final HistoryField field = section.fields[index];
                return _buildFieldWidget(field);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLabValuesDrawer() {
    final List<LabReference> labs = _template!.labReferences;
    return Drawer(
      child: Column(
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: const Center(
              child: Text(
                'Lab References',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: labs.isEmpty
                ? const Center(child: Text('No lab references available.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: labs.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (BuildContext context, int index) {
                      final LabReference lab = labs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              flex: 2,
                              child: Text(
                                lab.test,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                lab.normalRange,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// The Brain of the UI: dynamically renders the correct widget based on JSON type.
  Widget _buildFieldWidget(HistoryField field) {
    final dynamic currentValue = _currentAnswers[field.name];

    switch (field.type) {
      case 'group':
        final List<HistoryField> subFields = field.subFields ?? <HistoryField>[];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(field.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            children: subFields.map((HistoryField subField) {
              return Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                child: _buildFieldWidget(subField),
              );
            }).toList(),
          ),
        );

      case 'boolean':
        return CheckboxListTile(
          title: Text(field.label, style: const TextStyle(fontWeight: FontWeight.w500)),
          value: (currentValue as bool?) ?? false,
          onChanged: (bool? value) {
            setState(() {
              _currentAnswers[field.name] = value;
            });
          },
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        );

      case 'dropdown':
        final List<String> options = field.options ?? <String>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              field.label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: options.map((String option) {
                final bool isSelected = currentValue == option;
                return ChoiceChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      // Allow un-selecting by setting to null if it was already selected
                      _currentAnswers[field.name] = selected ? option : null;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        );

      case 'text':
      default:
        return TextFormField(
          decoration: InputDecoration(
            labelText: field.label,
            border: const UnderlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
            alignLabelWithHint: true,
          ),
          initialValue: currentValue as String?,
          maxLines: null, // allows multiline notes
          keyboardType: TextInputType.multiline,
          onChanged: (String value) {
            _currentAnswers[field.name] = value;
            // No need to setState for every keystroke unless we are displaying it elsewhere immediately.
          },
        );
    }
  }
}
