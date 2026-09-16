import 'history_field.dart';

class HistorySection {
  final String sectionId;
  final String title;
  final List<HistoryField> fields;

  HistorySection({
    required this.sectionId,
    required this.title,
    required this.fields,
  });

  factory HistorySection.fromJson(Map<String, dynamic> json) {
    return HistorySection(
      sectionId: json['section_id'] as String? ?? 'unknown_section',
      title: json['title'] as String? ?? 'Untitled Section',
      fields: (json['fields'] as List<dynamic>?)
              ?.map((dynamic e) =>
                  HistoryField.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <HistoryField>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'section_id': sectionId,
      'title': title,
      'fields': fields.map((HistoryField e) => e.toJson()).toList(),
    };
  }
}
