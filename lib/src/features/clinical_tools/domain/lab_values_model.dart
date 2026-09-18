class LabTest {
  const LabTest({
    required this.name,
    required this.normalRangeMale,
    required this.normalRangeFemale,
    required this.highIndication,
    required this.lowIndication,
  });

  final String name;
  final String normalRangeMale;
  final String normalRangeFemale;
  final String highIndication;
  final String lowIndication;

  factory LabTest.fromJson(Map<String, dynamic> json) {
    return LabTest(
      name: json['name'] as String? ?? '',
      normalRangeMale: json['normal_range_male'] as String? ?? '',
      normalRangeFemale: json['normal_range_female'] as String? ?? '',
      highIndication: json['high_indication'] as String? ?? '',
      lowIndication: json['low_indication'] as String? ?? '',
    );
  }
}

class LabCategory {
  const LabCategory({
    required this.category,
    required this.tests,
  });

  final String category;
  final List<LabTest> tests;

  factory LabCategory.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? testsJson = json['tests'] as List<dynamic>?;
    return LabCategory(
      category: json['category'] as String? ?? '',
      tests: testsJson
              ?.map((dynamic t) => LabTest.fromJson(t as Map<String, dynamic>))
              .toList() ??
          <LabTest>[],
    );
  }
}
