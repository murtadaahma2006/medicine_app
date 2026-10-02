import 'package:flutter/material.dart';
import '../../../../core/models/ai_provider.dart';
import '../../../../core/services/ai_model_manager.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  bool _loading = true;
  List<AiProvider> _providers = <AiProvider>[];
  String _activeProviderId = 'default_gemini';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<AiProvider> providers = await AiModelManager.getSavedProviders();
    final String activeId = await AiModelManager.getActiveProviderId();

    if (mounted) {
      setState(() {
        _providers = providers;
        _activeProviderId = activeId;
        _loading = false;
      });
    }
  }

  Future<void> _setActive(String providerId) async {
    await AiModelManager.setActiveProviderId(providerId);
    setState(() {
      _activeProviderId = providerId;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعيين النموذج النشط بنجاح وتعميمه على كافة المحادثات'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteProvider(AiProvider provider) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نموذج الذكاء الاصطناعي'),
        content: Text('هل أنت تأكد من رغبتك في حذف "${provider.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AiModelManager.deleteProvider(provider.id);
      await _load();
    }
  }

  Future<void> _showAddOrEditDialog([AiProvider? providerToEdit]) async {
    final bool isEdit = providerToEdit != null;
    final TextEditingController nameController =
        TextEditingController(text: isEdit ? providerToEdit.name : '');
    final TextEditingController urlController =
        TextEditingController(text: isEdit ? providerToEdit.baseUrl : '');
    final TextEditingController keyController =
        TextEditingController(text: isEdit ? providerToEdit.apiKey : '');
    final TextEditingController modelController =
        TextEditingController(text: isEdit ? providerToEdit.modelName : '');

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(isEdit ? 'تعديل نموذج الذكاء الاصطناعي' : 'إضافة نموذج ذكاء اصطناعي جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المزود (مثل: Claude 3.5 Sonnet)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'الرابط الأساسي (Base URL)',
                    hintText: 'https://openrouter.ai/api/v1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'مفتاح الـ API (API Key)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: modelController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المحرك/النموذج (Model Name)',
                    hintText: 'anthropic/claude-3.5-sonnet',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final String name = nameController.text.trim();
                final String url = urlController.text.trim();
                final String key = keyController.text.trim();
                final String model = modelController.text.trim();

                if (name.isEmpty || url.isEmpty || key.isEmpty || model.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى ملء جميع الحقول المطلوبة')),
                  );
                  return;
                }

                final AiProvider provider = AiProvider(
                  id: isEdit ? providerToEdit.id : 'provider_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  baseUrl: url,
                  apiKey: key,
                  modelName: model,
                  isDefault: false,
                );

                await AiModelManager.addOrUpdateProvider(provider);
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة النموذج'),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      await _load();
    }
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
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        title: const Text('إعدادات الذكاء الاصطناعي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث القائمة',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOrEditDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة نموذج جديد'),
        backgroundColor: AppColors.primary(b),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          // ── بطاقة الإرشاد التوضيحية ──
          AppCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint(b),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_awesome, color: AppColors.primary(b), size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إدارة النماذج والوصول الشامل',
                        style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'يمكنك إضافة عدة نماذج للذكاء الاصطناعي (Gemini, Claude, Llama 3, DeepSeek) وتعميمها فوراً على كل محادثات الشروحات وSidekick وخط الوكلاء.',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary(b),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text(
            'نماذج الذكاء الاصطناعي المتاحة (${_providers.length})',
            style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── قائمة النماذج ──
          ..._providers.map((AiProvider provider) {
            final bool isActive = provider.id == _activeProviderId;

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Radio<String>(
                          value: provider.id,
                          groupValue: _activeProviderId,
                          onChanged: (String? value) {
                            if (value != null) _setActive(value);
                          },
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      provider.name,
                                      style: AppType.cardTitle.copyWith(
                                        color: AppColors.text(b),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.success(b).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(AppRadius.pill),
                                      ),
                                      child: Text(
                                        'نشط حالياً',
                                        style: AppType.caption.copyWith(
                                          color: AppColors.success(b),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'النموذج: ${provider.modelName}',
                                style: AppType.caption.copyWith(
                                  color: AppColors.primary(b),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!provider.isDefault) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 20),
                            tooltip: 'تعديل',
                            onPressed: () => _showAddOrEditDialog(provider),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 20, color: Colors.red),
                            tooltip: 'حذف',
                            onPressed: () => _deleteProvider(provider),
                          ),
                        ],
                      ],
                    ),
                    const Divider(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Row(
                        children: [
                          Icon(Icons.link_rounded,
                              size: 16, color: AppColors.textSecondary(b)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              provider.baseUrl.isEmpty
                                  ? 'https://generativelanguage.googleapis.com'
                                  : provider.baseUrl,
                              style: AppType.caption.copyWith(
                                color: AppColors.textSecondary(b),
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isActive)
                            TextButton(
                              onPressed: () => _setActive(provider.id),
                              child: const Text('تفعيل كنموذج رئيسي'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
