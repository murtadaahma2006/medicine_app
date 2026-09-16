import 'dart:convert';
import '../data/models/history_field.dart';
import '../data/models/history_section.dart';
import '../data/models/history_template.dart';

class PresentationGenerator {
  /// Generates a cohesive clinical case presentation paragraph.
  static String generate(
    String responsesJson,
    HistoryTemplate template,
    String patientAlias,
  ) {
    if (responsesJson.isEmpty) return 'No data available.';

    final Map<String, dynamic> answers;
    try {
      answers = jsonDecode(responsesJson) as Map<String, dynamic>;
    } catch (_) {
      return 'Error parsing patient data.';
    }

    if (answers.isEmpty) return 'The patient history is empty.';

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('Patient $patientAlias presented to the clinic/ward.');
    buffer.writeln();

    for (final HistorySection section in template.sections) {
      final List<String> sectionDetails = <String>[];
      
      // Track standalone booleans for normal fields
      final List<String> standalonePositives = <String>[];
      final List<String> standaloneNegatives = <String>[];

      for (final HistoryField field in section.fields) {
        if (field.type == 'group' && field.subFields != null) {
          final List<String> groupPositives = <String>[];
          
          for (final HistoryField subField in field.subFields!) {
            if (!answers.containsKey(subField.name) || answers[subField.name] == null) {
              continue;
            }
            
            final dynamic val = answers[subField.name];
            if (subField.type == 'boolean') {
              if (val == true) {
                groupPositives.add(subField.label.toLowerCase());
              }
            } else {
              if (val is String && val.trim().isNotEmpty) {
                groupPositives.add('${subField.label.toLowerCase()}: $val');
              }
            }
          }
          
          if (groupPositives.isNotEmpty) {
            sectionDetails.add('On ${field.label} review, positive for ${groupPositives.join(', ')}.');
          }
        } else {
          if (!answers.containsKey(field.name) || answers[field.name] == null) {
            continue;
          }
          
          final dynamic val = answers[field.name];
          if (field.type == 'boolean') {
            if (val == true) {
              standalonePositives.add(field.label.toLowerCase());
            } else if (val == false) {
              standaloneNegatives.add(field.label.toLowerCase());
            }
          } else {
            if (val is String && val.trim().isNotEmpty) {
              sectionDetails.add('${field.label}: $val.');
            }
          }
        }
      }

      if (standalonePositives.isNotEmpty && standaloneNegatives.isNotEmpty) {
        sectionDetails.add('Patient reported ${standalonePositives.join(', ')}, but denied ${standaloneNegatives.join(', ')}.');
      } else if (standalonePositives.isNotEmpty) {
        sectionDetails.add('Patient reported positive ${standalonePositives.join(', ')}.');
      } else if (standaloneNegatives.isNotEmpty) {
        sectionDetails.add('Patient denied ${standaloneNegatives.join(', ')}.');
      }

      if (sectionDetails.isNotEmpty) {
        buffer.writeln('${section.title}: ${sectionDetails.join(' ')}');
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }
}
