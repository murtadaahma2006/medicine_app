import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/assets_manifest.dart';
import '../../shared/widgets/app_illustration.dart';
import '../../theme/tokens.dart';

class StylePreviewPage extends StatelessWidget {
  const StylePreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('غير متاح في الإنتاج')),
      );
    }

    // Group items
    final Map<String, List<AssetManifestEntry>> grouped = <String, List<AssetManifestEntry>>{};
    for (final AssetManifestEntry entry in AppAssetsManifest.items) {
      grouped.putIfAbsent(entry.group, () => <AssetManifestEntry>[]).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('معاينة الإليستريشن (المرحلة 1)'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: grouped.length,
        itemBuilder: (BuildContext context, int index) {
          final String group = grouped.keys.elementAt(index);
          final List<AssetManifestEntry> items = grouped[group]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  'المجموعة: $group',
                  style: AppType.screenTitle,
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.65,
                ),
                itemCount: items.length,
                itemBuilder: (BuildContext context, int idx) {
                  return _PreviewCard(entry: items[idx]);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.entry});
  final AssetManifestEntry entry;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool isLoaded = AppIllustration.hasResolvedPath(entry.id, b);
    final String expectedFile = AppIllustration.getExpectedFilename(entry.id, b);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border(b)),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // شارة الحالة
          Align(
            alignment: Alignment.topLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isLoaded ? Icons.check_circle : Icons.crop_square,
                  color: isLoaded ? AppColors.success(b) : AppColors.textSecondary(b),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  isLoaded ? '✅ محمل' : '⬜ بديل',
                  style: AppType.caption.copyWith(
                    color: isLoaded ? AppColors.success(b) : AppColors.textSecondary(b),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // الصورة
          Expanded(
            child: Center(
              child: AppIllustration(
                entry.id,
                size: 80,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // المعرّف
          Text(
            entry.id,
            style: AppType.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          // اسم الملف المتوقع
          Text(
            expectedFile,
            style: AppType.caption.copyWith(fontSize: 10, color: AppColors.textSecondary(b)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
