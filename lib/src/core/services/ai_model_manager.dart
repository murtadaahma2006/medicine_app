import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_provider.dart';
import '../utils/ai_constants.dart';

/// المدير المركزي لنماذج الذكاء الاصطناعي (AiModelManager).
///
/// يتيح حفظ وإدارة عدة نماذج مخصصة (Multiple AI Models) مع اختيار النموذج النشط عالمياً
/// وتطبيق التغييرات تلقائياً على كل شاشات ومحادثات التطبيق (ConceptReader, Sidekick, Chat, Content Factory).
abstract final class AiModelManager {
  static const String _savedProvidersKey = 'saved_ai_providers_v2';
  static const String _activeProviderIdKey = 'active_ai_provider_id_v2';

  /// النموذج الافتراضي المدمج (Gemini)
  static final AiProvider defaultGeminiProvider = AiProvider(
    id: 'default_gemini',
    name: 'Gemini (الافتراضي)',
    baseUrl: AIConstants.defaultBaseUrl,
    apiKey: AIConstants.defaultApiKey,
    modelName: AIConstants.defaultModel,
    isDefault: true,
  );

  /// جلب جميع نماذج الذكاء الاصطناعي المسجلة (الافتراضي + المخصصة)
  static Future<List<AiProvider>> getSavedProviders() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<AiProvider> providers = <AiProvider>[defaultGeminiProvider];

    final String legacyKey = prefs.getString('custom_api_key') ?? '';
    final String legacyUrl = prefs.getString('custom_base_url') ?? '';
    final String legacyModel = prefs.getString('custom_model') ?? '';

    final String? storedJson = prefs.getString(_savedProvidersKey);

    if (storedJson != null && storedJson.trim().isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(storedJson) as List<dynamic>;
        final List<AiProvider> customProviders = decoded
            .map((dynamic e) => AiProvider.fromJson(e as Map<String, dynamic>))
            .where((AiProvider p) => p.id != 'default_gemini')
            .toList();
        providers.addAll(customProviders);
      } catch (_) {}
    } else if (legacyKey.isNotEmpty && legacyUrl.isNotEmpty && legacyModel.isNotEmpty) {
      // ترحيل التكوين القديم تلقائياً إن وجد
      final AiProvider legacyProvider = AiProvider(
        id: 'custom_legacy',
        name: 'المخصص ($legacyModel)',
        baseUrl: legacyUrl,
        apiKey: legacyKey,
        modelName: legacyModel,
        isDefault: false,
      );
      providers.add(legacyProvider);
      await saveProviders(providers);
    }

    return providers;
  }

  /// حفظ قائمة النماذج المخصصة في SharedPreferences
  static Future<void> saveProviders(List<AiProvider> providers) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<AiProvider> customOnly =
        providers.where((AiProvider p) => !p.isDefault).toList();
    final String encoded =
        jsonEncode(customOnly.map((AiProvider p) => p.toJson()).toList());
    await prefs.setString(_savedProvidersKey, encoded);
  }

  /// إضافة نموذج جديد أو تحديث نموذج موجود
  static Future<void> addOrUpdateProvider(AiProvider provider) async {
    final List<AiProvider> providers = await getSavedProviders();
    final int existingIndex =
        providers.indexWhere((AiProvider p) => p.id == provider.id);

    if (existingIndex >= 0) {
      providers[existingIndex] = provider;
    } else {
      providers.add(provider);
    }

    await saveProviders(providers);
  }

  /// حذف نموذج مخصص
  static Future<void> deleteProvider(String providerId) async {
    if (providerId == 'default_gemini') return; // عدم حذف الافتراضي
    final List<AiProvider> providers = await getSavedProviders();
    providers.removeWhere((AiProvider p) => p.id == providerId);
    await saveProviders(providers);

    final String activeId = await getActiveProviderId();
    if (activeId == providerId) {
      await setActiveProviderId('default_gemini');
    }
  }

  /// جلب معرف النموذج النشط حالياً
  static Future<String> getActiveProviderId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProviderIdKey) ?? 'default_gemini';
  }

  /// تعيين النموذج النشط افتراضياً للتطبيق
  static Future<void> setActiveProviderId(String providerId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProviderIdKey, providerId);

    final bool isCustom = providerId != 'default_gemini';
    await prefs.setBool('use_custom_ai_provider', isCustom);
  }

  /// جلب كائن النموذج النشط حالياً في التطبيق
  static Future<AiProvider> getActiveProvider() async {
    final List<AiProvider> providers = await getSavedProviders();
    final String activeId = await getActiveProviderId();
    return providers.firstWhere(
      (AiProvider p) => p.id == activeId,
      orElse: () => defaultGeminiProvider,
    );
  }
}
