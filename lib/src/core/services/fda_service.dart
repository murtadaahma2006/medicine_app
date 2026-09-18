import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// DrugLabel — a strongly typed, null-safe model for an FDA drug label record.
// Every field is pre-cleaned and guaranteed non-null: callers never check null.
// ─────────────────────────────────────────────────────────────────────────────
class DrugLabel {
  const DrugLabel({
    required this.brandName,
    required this.genericName,
    required this.manufacturer,
    required this.boxedWarning,
    required this.indicationsAndUsage,
    required this.dosageAndAdministration,
    required this.contraindications,
    required this.drugInteractions,
  });

  final String brandName;
  final String genericName;
  final String manufacturer;

  // ── Clinical fields ──
  final String boxedWarning;           // 🔴 BLACK BOX — highest safety priority
  final String indicationsAndUsage;    // 🔵 Why to use it
  final String dosageAndAdministration;// 🔵 How to use it
  final String contraindications;      // 🔴 When NOT to use it
  final String drugInteractions;       // 🟡 What it clashes with

  bool get hasBoxedWarning =>
      boxedWarning != FdaService.notAvailable && boxedWarning.isNotEmpty;

  @override
  String toString() => 'DrugLabel($genericName / $brandName)';
}

// ─────────────────────────────────────────────────────────────────────────────
// FdaService — stateless service; uses a shared http.Client for connection
// pooling across multiple searches in the same session.
// ─────────────────────────────────────────────────────────────────────────────
class FdaService {
  FdaService._();

  static final http.Client _client = http.Client();

  /// Arabic placeholder returned when a field is absent from the FDA response.
  static const String notAvailable = 'غير متوفر';

  /// OpenFDA base endpoint for drug labels.
  static const String _baseUrl = 'https://api.fda.gov/drug/label.json';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Searches the OpenFDA drug label database for [drugName].
  ///
  /// Strategy:
  ///   - Searches both generic_name and brand_name in a single request.
  ///   - Fetches only 1 result (limit=1) — the best match is always first.
  ///   - Safely extracts every clinical field; missing fields get [_notAvailable].
  ///
  /// Throws a [FdaNotFoundException] if no result matches.
  /// Throws a [FdaServiceException] on network / parse failures.
  static Future<DrugLabel> search(String drugName) async {
    final String query = Uri.encodeQueryComponent(
      'openfda.generic_name:"$drugName" openfda.brand_name:"$drugName"',
    );
    final Uri uri = Uri.parse('$_baseUrl?search=$query&limit=1');

    debugPrint('FdaService: GET $uri');

    late http.Response response;
    try {
      response = await _client
          .get(uri, headers: <String, String>{'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw FdaServiceException('انتهت مهلة الاتصال. تحقق من الإنترنت.');
    } catch (e) {
      throw FdaServiceException('فشل الاتصال بـ OpenFDA: $e');
    }

    if (response.statusCode == 404) {
      throw FdaNotFoundException(drugName);
    }
    if (response.statusCode != 200) {
      throw FdaServiceException(
          'خطأ من الخادم: ${response.statusCode}');
    }

    late Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw FdaServiceException('تعذّر تحليل استجابة OpenFDA: $e');
    }

    final List<dynamic>? results = json['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw FdaNotFoundException(drugName);
    }

    return _parseLabel(results.first as Map<String, dynamic>);
  }

  // ── Parsing helpers ────────────────────────────────────────────────────────

  static DrugLabel _parseLabel(Map<String, dynamic> raw) {
    // openfda is a nested map with arrays of values.
    final Map<String, dynamic> openfda =
        (raw['openfda'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return DrugLabel(
      brandName: _firstString(openfda['brand_name']),
      genericName: _firstString(openfda['generic_name']),
      manufacturer: _firstString(openfda['manufacturer_name']),
      boxedWarning: _firstString(raw['boxed_warning']),
      indicationsAndUsage: _firstString(raw['indications_and_usage']),
      dosageAndAdministration:
          _firstString(raw['dosage_and_administration']),
      contraindications: _firstString(raw['contraindications']),
      drugInteractions: _firstString(raw['drug_interactions']),
    );
  }

  /// Safely extracts the first string from an FDA field.
  ///
  /// FDA fields are almost always `List<String>` with a single long string
  /// inside. Handles null, empty lists, non-list values, and weird whitespace.
  static String _firstString(dynamic field) {
    if (field == null) return notAvailable;

    String raw;
    if (field is List && field.isNotEmpty) {
      raw = field.first?.toString() ?? '';
    } else if (field is String) {
      raw = field;
    } else {
      return notAvailable;
    }

    // Clean up FDA formatting artifacts:
    //   - Strip excessive blank lines (≥3 consecutive newlines → 2).
    //   - Trim leading/trailing whitespace.
    raw = raw
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();

    return raw.isEmpty ? notAvailable : raw;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom exceptions — callers pattern-match on type instead of parsing strings.
// ─────────────────────────────────────────────────────────────────────────────

class FdaNotFoundException implements Exception {
  const FdaNotFoundException(this.query);
  final String query;

  @override
  String toString() =>
      'FdaNotFoundException: no results for "$query"';
}

class FdaServiceException implements Exception {
  const FdaServiceException(this.message);
  final String message;

  @override
  String toString() => 'FdaServiceException: $message';
}
