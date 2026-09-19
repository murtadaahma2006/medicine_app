import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/ai_provider.dart';
import '../utils/ai_constants.dart';

class AIService {
  static final http.Client _client = http.Client();

  /// Fetches the current active API Key, Base URL, and Model from SharedPreferences.
  ///
  /// The [use_custom_ai_provider] boolean is the single source of truth.
  /// Custom credentials are always stored in prefs but only used when the
  /// flag is [true] — toggling it off never loses the saved values.
  static Future<Map<String, String>> _getAICredentials() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final bool useCustom = prefs.getBool('use_custom_ai_provider') ?? false;

    final String apiKey = useCustom
        ? (prefs.getString('custom_api_key')  ?? AIConstants.defaultApiKey)
        : AIConstants.defaultApiKey;

    final String baseUrl = useCustom
        ? (prefs.getString('custom_base_url') ?? AIConstants.defaultBaseUrl)
        : AIConstants.defaultBaseUrl;

    final String model = useCustom
        ? (prefs.getString('custom_model')    ?? AIConstants.defaultModel)
        : AIConstants.defaultModel;

    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
    };
  }

  /// Sends a request to the AI provider using the standard OpenAI-compatible
  /// `/chat/completions` endpoint format.
  static Future<String?> generateContent(String systemPrompt, String userMessage) async {
    try {
      final Map<String, String> credentials = await _getAICredentials();
      
      final String baseUrl = credentials['baseUrl']!;
      final String apiKey = credentials['apiKey']!;
      final String model = credentials['model']!;

      // Ensure baseUrl does not have a trailing slash before appending endpoint
      final String formattedBaseUrl = baseUrl.endsWith('/') 
          ? baseUrl.substring(0, baseUrl.length - 1) 
          : baseUrl;
          
      final Uri uri = Uri.parse('$formattedBaseUrl/chat/completions');

      final Map<String, dynamic> body = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
      };

      final http.Response response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('choices') && (data['choices'] as List).isNotEmpty) {
          final String content = (data['choices'][0]['message']['content'] ?? '') as String;
          return content;
        }
      } else {
        print('API Error: ${response.statusCode} - ${response.body}');
        throw Exception('AI Request Failed: ${response.statusCode} - ${response.body}');
      }
      return null;
    } on TimeoutException {
      throw Exception('انتهى وقت الاتصال. يبدو أن مزود الذكاء الاصطناعي يواجه ضغطاً عالياً، يرجى المحاولة لاحقاً.');
    } catch (e) {
      // Return null or rethrow based on app error handling requirements.
      // For now we log it and return null.
      print('AIService Error: $e');
      return null;
    }
  }

  /// Sends a request to the AI provider with full conversation history.
  static Future<String?> generateChatCompletion(List<Map<String, String>> messages) async {
    try {
      final Map<String, String> credentials = await _getAICredentials();
      
      final String baseUrl = credentials['baseUrl']!;
      final String apiKey = credentials['apiKey']!;
      final String model = credentials['model']!;

      final String formattedBaseUrl = baseUrl.endsWith('/') 
          ? baseUrl.substring(0, baseUrl.length - 1) 
          : baseUrl;
          
      final Uri uri = Uri.parse('$formattedBaseUrl/chat/completions');

      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final String body = jsonEncode({
        'model': model,
        'messages': messages,
      });

      final http.Response response = await _client.post(
        uri,
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['choices'][0]['message']['content'] ?? '') as String;
      } else {
        print('CRITICAL API ERROR: Status ${response.statusCode}');
        print('ERROR BODY: ${response.body}'); // WE NEED TO SEE THIS
        throw Exception('فشل الوصول للـ AI: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('انتهى وقت الاتصال. يبدو أن مزود الذكاء الاصطناعي يواجه ضغطاً عالياً، يرجى المحاولة لاحقاً.');
    } catch (e) {
      print('AIService Chat Error: $e');
      rethrow;
    }
  }

  /// Sends a streaming request to the AI provider.
  static Stream<String> generateChatStream(List<Map<String, dynamic>> messages, {AiProvider? provider}) async* {
    try {
      final String baseUrl;
      final String apiKey;
      final String model;

      if (provider != null) {
        baseUrl = provider.baseUrl;
        apiKey = provider.apiKey;
        model = provider.modelName;
      } else {
        final Map<String, String> credentials = await _getAICredentials();
        baseUrl = credentials['baseUrl']!;
        apiKey = credentials['apiKey']!;
        model = credentials['model']!;
      }

      final String formattedBaseUrl = baseUrl.endsWith('/') 
          ? baseUrl.substring(0, baseUrl.length - 1) 
          : baseUrl;
          
      final Uri uri = Uri.parse('$formattedBaseUrl/chat/completions');

      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      // Format messages for Vision if base64Image exists
      final List<Map<String, dynamic>> formattedMessages = messages.map((msg) {
        final Map<String, dynamic> formattedMsg = {'role': msg['role']};
        if (msg['role'] == 'user' && msg.containsKey('base64Image') && msg['base64Image'] != null) {
          formattedMsg['content'] = [
            { 'type': 'text', 'text': msg['content'] ?? '' },
            { 'type': 'image_url', 'image_url': { 'url': 'data:image/jpeg;base64,${msg['base64Image']}' } }
          ];
        } else {
          formattedMsg['content'] = msg['content'];
        }
        return formattedMsg;
      }).toList();

      final String body = jsonEncode({
        'model': model,
        'messages': formattedMessages,
        'stream': true,
      });

      final http.Request request = http.Request('POST', uri);
      request.headers.addAll(headers);
      request.body = body;

      final http.StreamedResponse response = await _client.send(request).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        final String errorBody = await response.stream.bytesToString();
        print('CRITICAL API ERROR: Status ${response.statusCode}');
        print('ERROR BODY: $errorBody');
        throw Exception('فشل الوصول للـ AI: ${response.statusCode}');
      }

      await for (final String line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        if (line.startsWith('data: ')) {
          final String dataStr = line.substring(6).trim();
          if (dataStr == '[DONE]') return;
          
          try {
            final Map<String, dynamic> data = jsonDecode(dataStr) as Map<String, dynamic>;
            if (data.containsKey('choices') && (data['choices'] as List).isNotEmpty) {
              final dynamic delta = data['choices'][0]['delta'];
              if (delta != null && delta is Map && delta.containsKey('content')) {
                yield (delta['content'] ?? '') as String;
              }
            }
          } catch (e) {
            print('JSON Parse error in stream: $e, line: $line');
          }
        }
      }
    } on TimeoutException {
      throw Exception('انتهى وقت الاتصال. يبدو أن مزود الذكاء الاصطناعي يواجه ضغطاً عالياً، يرجى المحاولة لاحقاً.');
    } catch (e) {
      print('AIService Stream Error: $e');
      rethrow;
    }
  }

  /// Explains the provided medical text using the AI provider.
  ///
  /// Cache-first strategy (v27):
  ///   1. Checks [DatabaseHelper.getCachedExplanation] for an exact-match hit.
  ///      If found, returns the cached explanation instantly — zero API cost.
  ///   2. If not cached, makes the standard HTTP request to the LLM.
  ///   3. On a successful response, writes it to the local cache via
  ///      [DatabaseHelper.cacheExplanation] BEFORE returning to the UI,
  ///      so the next identical request is served from disk.
  static Future<String?> explainMedicalText(String selectedText) async {
    const String systemPrompt =
        'You are an expert internal medicine academic mentor. The user is a 4th-year medical student. Briefly explain the following medical text, simplify the underlying mechanism, and provide one high-yield clinical pearl. Respond primarily in clear Arabic (with English medical terms kept in English). Keep it under 3 short paragraphs.';

    // ── Step 1: Cache lookup ──────────────────────────────────────────────
    try {
      final String? cached =
          await DatabaseHelper.instance.getCachedExplanation(selectedText);
      if (cached != null && cached.isNotEmpty) {
        debugPrint('AIService: cache HIT for "${selectedText.substring(0, selectedText.length.clamp(0, 40))}..."');
        return cached;
      }
    } catch (e) {
      // Cache read failure is non-fatal — fall through to the API.
      debugPrint('AIService: cache read error (non-fatal) — $e');
    }

    // ── Step 2: API call ──────────────────────────────────────────────────
    debugPrint('AIService: cache MISS — calling API.');
    final String? response =
        await generateContent(systemPrompt, selectedText);

    // ── Step 3: Persist to cache ──────────────────────────────────────────
    if (response != null && response.isNotEmpty) {
      try {
        await DatabaseHelper.instance.cacheExplanation(selectedText, response);
        debugPrint('AIService: explanation cached successfully.');
      } catch (e) {
        // Cache write failure is non-fatal — the UI still gets the response.
        debugPrint('AIService: cache write error (non-fatal) — $e');
      }
    }

    return response;
  }

  /// Generates a critical history-taking checklist based on the chief complaint.
  static Future<List<String>> generateHistoryChecklist(String chiefComplaint) async {
    if (chiefComplaint.trim().isEmpty) return [];

    final String systemPrompt = 
        "You are an expert clinical physician. The patient presents with: '$chiefComplaint'. Reply ONLY with a concise list of 4 to 6 critical history-taking questions or red flags the medical student MUST ask (e.g., related to DDx or emergencies). Provide the output in Arabic. Do not use Markdown formatting. Put each question on a new line starting with a dash (-).";
    
    try {
      final String? response = await generateContent(systemPrompt, chiefComplaint);
      if (response == null || response.trim().isEmpty) return [];

      return response
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => line.startsWith('-') ? line.substring(1).trim() : line)
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Error generating history checklist: $e');
      return [];
    }
  }
}
