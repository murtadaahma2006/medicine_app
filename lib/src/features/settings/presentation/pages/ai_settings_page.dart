import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/ai_constants.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  bool _loading = true;
  bool _useCustom = false;

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Read the explicit toggle flag — does NOT infer it from key existence.
    final bool useCustom = prefs.getBool('use_custom_ai_provider') ?? false;

    // Always load saved credentials into the controllers regardless of the
    // toggle state, so they're visible when the user re-enables the toggle.
    final String apiKey  = prefs.getString('custom_api_key')  ?? '';
    final String baseUrl = prefs.getString('custom_base_url') ?? '';
    final String model   = prefs.getString('custom_model')    ?? '';

    setState(() {
      _useCustom = useCustom;
      _apiKeyController.text  = apiKey;
      _baseUrlController.text = baseUrl;
      _modelController.text   = model;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Validate only when the user intends to USE the custom provider.
    if (_useCustom) {
      final String apiKey  = _apiKeyController.text.trim();
      final String baseUrl = _baseUrlController.text.trim();
      final String model   = _modelController.text.trim();

      if (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء تعبئة جميع الحقول')),
        );
        return;
      }
    }

    // ALWAYS persist the text values — never remove them.
    // This lets the user toggle off and back on without re-entering credentials.
    await prefs.setString('custom_api_key',  _apiKeyController.text.trim());
    await prefs.setString('custom_base_url', _baseUrlController.text.trim());
    await prefs.setString('custom_model',    _modelController.text.trim());

    // The single source of truth for which provider is active.
    await prefs.setBool('use_custom_ai_provider', _useCustom);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الإعدادات بنجاح')),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('إعدادات الذكاء الاصطناعي')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الذكاء الاصطناعي')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          AppCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint(b),
                    borderRadius: BorderRadius.circular(AppRadius.chip + 2),
                  ),
                  child: Icon(
                    Icons.api_rounded,
                    color: AppColors.primary(b),
                  ),
                ),
                const SizedBox(width: AppSpacing.md + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('المزود المخصص',
                          style: AppType.cardTitle
                              .copyWith(color: AppColors.text(b))),
                      Text(
                        _useCustom
                            ? 'تجاوز الإعدادات الافتراضية'
                            : 'استخدام المدمج الافتراضي',
                        style: AppType.body
                            .copyWith(color: AppColors.textSecondary(b)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _useCustom,
                  onChanged: (bool value) {
                    setState(() {
                      _useCustom = value;
                    });
                  },
                ),
              ],
            ),
          ),
          
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppMotion.standard,
            curve: AppMotion.ease,
            child: _useCustom
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: _apiKeyController,
                            decoration: const InputDecoration(
                              labelText: 'مفتاح API (API Key)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            controller: _baseUrlController,
                            decoration: InputDecoration(
                              labelText: 'الرابط الأساسي (Base URL)',
                              hintText: AIConstants.defaultBaseUrl,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            controller: _modelController,
                            decoration: InputDecoration(
                              labelText: 'اسم النموذج (Model)',
                              hintText: AIConstants.defaultModel,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'حفظ الإعدادات',
            icon: Icons.save_rounded,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
