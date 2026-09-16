import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/history_template.dart';
import '../../data/services/history_template_service.dart';
import '../../utils/presentation_generator.dart';

class RecordDetailsScreen extends StatefulWidget {
  const RecordDetailsScreen({
    super.key,
    required this.record,
  });

  final Map<String, dynamic> record;

  @override
  State<RecordDetailsScreen> createState() => _RecordDetailsScreenState();
}

class _RecordDetailsScreenState extends State<RecordDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  String _generatedPresentation = '';

  final HistoryTemplateService _service = HistoryTemplateService();

  @override
  void initState() {
    super.initState();
    _generatePresentation();
  }

  Future<void> _generatePresentation() async {
    try {
      final HistoryTemplate template = await _service.loadTemplate();
      final String alias = widget.record['patient_alias'] as String;
      final String responsesJson = widget.record['responses_json'] as String;
      
      final String result = PresentationGenerator.generate(
        responsesJson,
        template,
        alias,
      );

      setState(() {
        _generatedPresentation = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _copyToClipboard() async {
    if (_generatedPresentation.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _generatedPresentation));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presentation copied to clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String alias = widget.record['patient_alias'] as String;

    return Scaffold(
      appBar: AppBar(
        title: Text('$alias - Case Presentation'),
        actions: <Widget>[
          if (!_isLoading && _error == null)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy to Clipboard',
              onPressed: _copyToClipboard,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: SelectableText(
        _generatedPresentation,
        style: TextStyle(
          fontSize: 16,
          height: 1.6, // Medical typography spacing
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
