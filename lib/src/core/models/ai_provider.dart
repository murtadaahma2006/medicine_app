class AiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String modelName;
  final bool isDefault;

  AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.modelName,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'modelName': modelName,
      'isDefault': isDefault,
    };
  }

  factory AiProvider.fromJson(Map<String, dynamic> json) {
    return AiProvider(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      modelName: json['modelName'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}
