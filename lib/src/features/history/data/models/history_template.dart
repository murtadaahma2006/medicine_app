import 'history_section.dart';
import 'lab_reference.dart';

class HistoryTemplate {
  final List<HistorySection> sections;
  final List<LabReference> labReferences;

  HistoryTemplate({
    required this.sections,
    required this.labReferences,
  });

  factory HistoryTemplate.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? module =
        json['history_taking_module'] as Map<String, dynamic>?;
    if (module == null) {
      throw const FormatException('Missing history_taking_module in JSON');
    }

    return HistoryTemplate(
      sections: (module['sections'] as List<dynamic>?)
              ?.map((dynamic e) =>
                  HistorySection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <HistorySection>[],
      labReferences: (module['lab_references'] as List<dynamic>?)
              ?.map((dynamic e) =>
                  LabReference.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <LabReference>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'history_taking_module': <String, dynamic>{
        'sections': sections.map((HistorySection e) => e.toJson()).toList(),
        'lab_references':
            labReferences.map((LabReference e) => e.toJson()).toList(),
      }
    };
  }
}
