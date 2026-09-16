import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/history_template.dart';

class HistoryTemplateService {
  /// Asynchronously loads and parses the history template from assets.
  /// Uses an isolate (`compute`) to prevent UI stutter since the JSON is large.
  Future<HistoryTemplate> loadTemplate([String path = 'assets/data/history_template.json']) async {
    final String jsonString = await rootBundle.loadString(path);
    return compute(_parseTemplate, jsonString);
  }

  static HistoryTemplate _parseTemplate(String jsonString) {
    final Map<String, dynamic> jsonMap =
        jsonDecode(jsonString) as Map<String, dynamic>;
    return HistoryTemplate.fromJson(jsonMap);
  }
}
