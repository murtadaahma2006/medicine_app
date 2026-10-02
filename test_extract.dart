import 'dart:convert';
void main() {
  dynamic extractArrayLocal(dynamic data, String expectedKey) {
    if (data is List) return data;
    if (data is Map) {
      if (data.containsKey(expectedKey) && data[expectedKey] is List) {
        return data[expectedKey] as List;
      }
      for (final value in data.values) {
        if (value is List) return value;
      }
    }
    return null;
  }
  
  var payload = {"Pathophysiology": "text", "Treatment": "text"};
  var extracted = extractArrayLocal(payload, 'concepts');
  print('extracted: $extracted');
}
