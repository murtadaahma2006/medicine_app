import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../domain/lab_values_model.dart';

abstract final class LabValuesRepository {
  /// Loads and parses the lab values JSON from assets.
  static Future<List<LabCategory>> loadLabValues() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/content/normal_lab_values.json');
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((dynamic c) => LabCategory.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Return empty list if asset fails to load
      return <LabCategory>[];
    }
  }
}
