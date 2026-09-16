class LabReference {
  final String test;
  final String normalRange;

  LabReference({
    required this.test,
    required this.normalRange,
  });

  factory LabReference.fromJson(Map<String, dynamic> json) {
    return LabReference(
      test: json['test'] as String? ?? 'Unknown Test',
      normalRange: json['normal_range'] as String? ?? 'N/A',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'test': test,
      'normal_range': normalRange,
    };
  }
}
