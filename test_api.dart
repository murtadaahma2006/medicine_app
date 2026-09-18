import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final apiKey = "";
  final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions");

  final models = ["gemini-1.5-flash", "gemini-1.5-flash-latest", "gemini-1.5-pro", "gemini-pro"];

  for (final model in models) {
    print("Testing $model...");
    final body = jsonEncode({
      "model": model,
      "messages": [{"role": "user", "content": "hello"}]
    });

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $apiKey"
      },
      body: body,
    );

    print("$model -> Status: ${response.statusCode}");
    if (response.statusCode != 200) {
      print("Response: ${response.body}");
    } else {
      print("Success!");
    }
    print("---");
  }
}
