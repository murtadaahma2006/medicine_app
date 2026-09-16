import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../routing/app_router.dart';

class PatientRecordsScreen extends StatefulWidget {
  const PatientRecordsScreen({super.key});

  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsScreenState();
}

class _PatientRecordsScreenState extends State<PatientRecordsScreen> {
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> records =
        await DatabaseHelper.instance.getPatientRecords();
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Records'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState()
              : _buildRecordsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showHistoryTypeSelector,
        icon: const Icon(Icons.add),
        label: const Text('New History'),
      ),
    );
  }

  void _showHistoryTypeSelector() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Select Form Type',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await context.push(RoutePaths.activeHistory, extra: 'assets/data/history_template.json');
                    await _loadRecords();
                  },
                  icon: const Icon(Icons.edit_document, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text('Comprehensive History (Wards)', style: TextStyle(fontSize: 16)),
                  ),
                  style: ElevatedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await context.push(RoutePaths.activeHistory, extra: 'assets/data/basic_history_template.json');
                    await _loadRecords();
                  },
                  icon: const Icon(Icons.flash_on, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text('Basic History (Clinic)', style: TextStyle(fontSize: 16)),
                  ),
                  style: ElevatedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.folder_open, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No patient records yet.',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create a new clinical history.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80), // for FAB
      itemCount: _records.length,
      itemBuilder: (BuildContext context, int index) {
        final Map<String, dynamic> record = _records[index];
        final String alias = record['patient_alias'] as String;
        final String createdAtStr = record['created_at'] as String;
        final DateTime createdAt = DateTime.parse(createdAtStr).toLocal();
        
        final String responsesJson = record['responses_json'] as String;
        int answersCount = 0;
        try {
          final Map<String, dynamic> decoded =
              jsonDecode(responsesJson) as Map<String, dynamic>;
          answersCount = decoded.length;
        } catch (_) {}

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () {
              // Pass the full record map as extra
              context.push(RoutePaths.recordDetails, extra: record);
            },
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                alias.isNotEmpty ? alias[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              alias,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.assignment, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '$answersCount fields',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _confirmDelete(record['id'] as int),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(int id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text('Are you sure you want to delete this patient record?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deletePatientRecord(id);
      await _loadRecords();
    }
  }
}
