import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../assets_manifest.dart';

/// مكون الرسوم التوضيحية الديناميكي — يقرأ الصور من assets بدون حزم خارجية.
class AppIllustration extends StatelessWidget {
  const AppIllustration(
    this.id, {
    this.size = 180,
    this.borderRadius,
    super.key,
  });

  /// معرّف الصورة الموجود في AssetManifest.
  final String id;

  /// الحجم (العرض والارتفاع معاً ليكونا مربعاً).
  final double size;

  /// قص الزوايا (اختياري).
  final BorderRadius? borderRadius;

  static final Set<String> _availablePaths = <String>{};

  /// [للاختبار فقط] تجاوز المانيفست بمجموعة مسارات وهمية.
  // ignore: invalid_use_of_visible_for_testing_member
  static void overrideManifestForTest(Set<String> paths) {
    _availablePaths
      ..clear()
      ..addAll(paths);
  }

  /// [للاختبار فقط] مسح التجاوز وإعادة الحالة الفارغة.
  static void clearManifestOverride() {
    _availablePaths.clear();
  }

  /// يقرأ AssetManifest ويحفظ المسارات المتاحة (يستدعى مرة عند إقلاع التطبيق).
  static Future<void> initManifest() async {
    try {
      final String manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
      _availablePaths.clear();
      _availablePaths.addAll(manifestMap.keys);
    } catch (e) {
      debugPrint('Error loading AssetManifest: $e');
    }
  }

  /// دالة تفحص توفر المسار للمعاينة.
  static bool hasResolvedPath(String id, Brightness brightness) {
    final AssetManifestEntry entry = AppAssetsManifest.items.firstWhere(
      (AssetManifestEntry e) => e.id == id,
      orElse: () => AssetManifestEntry(id: id, group: 'unknown', fallback: '?'),
    );
    final String group = entry.group;
    final String basePath = 'assets/illustrations/$group/$id';
    final List<String> pathsToTry = <String>[];

    if (brightness == Brightness.dark) {
      pathsToTry.add('${basePath}_dark.webp');
      pathsToTry.add('${basePath}_dark.png');
    }
    
    pathsToTry.add('$basePath.webp');
    pathsToTry.add('$basePath.png');

    for (final String path in pathsToTry) {
      if (_availablePaths.contains(path)) {
        return true;
      }
    }
    return false;
  }
  
  /// للحصول على المسار المتوقع للمعاينة.
  static String getExpectedFilename(String id, Brightness b) {
    return b == Brightness.dark ? '${id}_dark.webp / .png' : '$id.webp / .png';
  }

  /// إيجاد المسار المناسب للصورة حسب توفرها والوضع الفاتح/الداكن.
  String? _resolvePath(String group, Brightness brightness) {
    final String basePath = 'assets/illustrations/$group/$id';
    final List<String> pathsToTry = <String>[];

    if (brightness == Brightness.dark) {
      pathsToTry.add('${basePath}_dark.webp');
      pathsToTry.add('${basePath}_dark.png');
    }
    
    pathsToTry.add('$basePath.webp');
    pathsToTry.add('$basePath.png');

    for (final String path in pathsToTry) {
      if (_availablePaths.contains(path)) {
        return path;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    
    final AssetManifestEntry entry = AppAssetsManifest.items.firstWhere(
      (AssetManifestEntry e) => e.id == id,
      orElse: () => AssetManifestEntry(id: id, group: 'unknown', fallback: '?'),
    );

    final String? resolvedPath = _resolvePath(entry.group, b);
    final BorderRadius radius = borderRadius ?? BorderRadius.circular(AppRadius.card);

    if (resolvedPath != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          resolvedPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    // Fallback
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(b),
        borderRadius: radius,
        border: Border.all(color: AppColors.border(b)),
      ),
      alignment: Alignment.center,
      child: Text(
        entry.fallback,
        style: TextStyle(fontSize: size * 0.4),
      ),
    );
  }
}
