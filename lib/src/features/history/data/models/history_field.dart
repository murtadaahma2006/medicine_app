class HistoryField {
  final String name;
  final String label;
  final String type;
  final List<String>? options;
  final List<HistoryField>? subFields;

  HistoryField({
    required this.name,
    required this.label,
    required this.type,
    this.options,
    this.subFields,
  });

  factory HistoryField.fromJson(Map<String, dynamic> json) {
    return HistoryField(
      name: json['name'] as String? ?? 'unknown',
      label: json['label'] as String? ?? 'Unknown Field',
      type: json['type'] as String? ?? 'text',
      options: (json['options'] as List<dynamic>?)
          ?.map((dynamic e) => e?.toString() ?? '')
          .toList(),
      subFields: (json['sub_fields'] as List<dynamic>?)
          ?.map((dynamic e) => HistoryField.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'label': label,
      'type': type,
      if (options != null) 'options': options,
      if (subFields != null) 'sub_fields': subFields!.map((e) => e.toJson()).toList(),
    };
  }
}
