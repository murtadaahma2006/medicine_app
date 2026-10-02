import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../models/ai_provider.dart';
import 'ai_model_manager.dart';

class AIService {
  static final http.Client _client = http.Client();

  /// Tests the connection to an AI provider.
  static Future<bool> testConnection(AiProvider provider) async {
    try {
      final String? result = await generateContent(
        'You are a network testing bot.',
        'Reply EXACTLY with this valid JSON: {"status": "ok"}',
        provider: provider,
      );
      return result != null && result.contains('"ok"');
    } catch (_) {
      return false;
    }
  }

  /// Sends a request to the AI provider using the standard OpenAI-compatible
  /// `/chat/completions` endpoint format.
  static Future<String?> generateContent(String systemPrompt, String userMessage, {AiProvider? provider}) async {
    try {
      final AiProvider targetProvider = provider ?? await AiModelManager.getActiveProvider();
      final String baseUrl = targetProvider.baseUrl;
      final String apiKey = targetProvider.apiKey;
      final String model = targetProvider.modelName;

      // Ensure baseUrl does not have a trailing slash before appending endpoint
      final String formattedBaseUrl = baseUrl.endsWith('/') 
          ? baseUrl.substring(0, baseUrl.length - 1) 
          : baseUrl;
          
      final Uri uri = Uri.parse('$formattedBaseUrl/chat/completions');

      final Map<String, dynamic> body = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': '$systemPrompt\n\nCRITICAL: Return ONLY valid, raw JSON. Do not include markdown codeblocks (```json ... ```).'},
          {'role': 'user', 'content': userMessage},
        ],
        'response_format': {'type': 'json_object'},
      };

      final http.Response response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('choices') && (data['choices'] as List).isNotEmpty) {
          String content = (data['choices'][0]['message']['content'] ?? '') as String;
          content = content.trim();
          if (content.startsWith('```json')) {
            content = content.substring(7);
          } else if (content.startsWith('```')) {
            content = content.substring(3);
          }
          if (content.endsWith('```')) {
            content = content.substring(0, content.length - 3);
          }
          return content.trim();
        }
      } else {
        print('API Error: ${response.statusCode} - ${response.body}');
        throw Exception('AI Request Failed: ${response.statusCode} - ${response.body}');
      }
      return null;
    } on TimeoutException {
      throw Exception('انتهى وقت الاتصال (120 ثانية). يبدو أن مزود الذكاء الاصطناعي يواجه ضغطاً عالياً، يرجى المحاولة لاحقاً.');
    } catch (e) {
      print('AIService Error: $e');
      rethrow;
    }
  }

  /// Sends a streaming request to the AI provider using SSE (Server-Sent Events).
  /// Yields text chunks as they arrive.
  static Stream<String> generateContentStream(String systemPrompt, String userMessage, {AiProvider? provider}) async* {
    final AiProvider targetProvider = provider ?? await AiModelManager.getActiveProvider();
    final String baseUrl = targetProvider.baseUrl;
    final String apiKey = targetProvider.apiKey;
    final String model = targetProvider.modelName;

    final String formattedBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final Uri uri = Uri.parse('$formattedBaseUrl/chat/completions');

    final http.Request request = http.Request('POST', uri);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    });
    
    request.body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': '$systemPrompt\n\nCRITICAL: Return ONLY valid, raw JSON. Do not include markdown codeblocks (```json ... ```).'},
        {'role': 'user', 'content': userMessage},
      ],
      'stream': true,
    });

    final http.StreamedResponse response = await _client.send(request);
    
    if (response.statusCode != 200) {
      final errorStr = await response.stream.bytesToString();
      throw Exception('AI Stream Request Failed: ${response.statusCode} - $errorStr');
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      
      // OpenAI/OpenRouter SSE format: "data: {...}"
      if (line.startsWith('data: ')) {
        final dataStr = line.substring(6).trim();
        if (dataStr == '[DONE]') break;
        
        try {
          final data = jsonDecode(dataStr);
          if (data['choices'] != null && (data['choices'] as List).isNotEmpty) {
            final delta = data['choices'][0]['delta'];
            if (delta != null && delta['content'] != null) {
              yield delta['content'] as String;
            }
          }
        } catch (_) {
          // Ignore JSON parsing errors for partial/malformed chunks
        }
      }
    }
  }

  /// Sends a request to the AI provider with full conversation history.
  static Future<String?> generateChatCompletion(List<Map<String, String>> messages, {AiProvider? provider}) async {
    try {
      final AiProvider targetProvider = provider ?? await AiModelManager.getActiveProvider();
      final String baseUrl = targetProvider.baseUrl;
      final String apiKey = targetProvider.apiKey;
      final String model = targetProvider.modelName;

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
      ).timeout(const Duration(seconds: 120));

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
      final AiProvider targetProvider = provider ?? await AiModelManager.getActiveProvider();
      final String baseUrl = targetProvider.baseUrl;
      final String apiKey = targetProvider.apiKey;
      final String model = targetProvider.modelName;

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
