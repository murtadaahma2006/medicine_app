import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_svg_icon.dart';

/// ─────────────────────────────────────────────────────────────────────
/// شارة إنجاز من طقم الميداليات SVG — درع سداسي + ريبط + رمز داخلي.
///
/// حالتان:
/// - مقفلة: **Silhouette صامتة** — نفس الرسمة بدرجات رمادية شفافة
///   15% + المخطط الداخلي فقط. سيكولوجية «الجمع» تدفع للمطاردة
///   دون أن تكسر انسجام الشبكة البصرية.
/// - مفتوحة: كاملة الألوان بمعدنها (برونز/فضة/ذهب).
///
/// البديل الآمن: إيموجي الشارة عند غياب الـSVG — لا انهيار أبداً.
///
/// **أداء**: لا FutureBuilder ولا قراءة قرص عند كل rebuild — فحص
/// الوجود عبر errorBuilder المتزامن + كاش للأصول المفقودة (نفس
/// نمط AppSvgIcon): أول frame يعرض الميدالية أو البديل فوراً.
/// ─────────────────────────────────────────────────────────────────────
class BadgeIcon extends StatelessWidget {
  const BadgeIcon(
    this.badgeId, {
    this.size = 64,
    this.locked = false,
    this.emojiFallback,
    super.key,
  });

  /// معرف الشارة — يطابق معرفات BadgeDef (first-concept، streak-3...).
  final String badgeId;

  /// الحجم (مربع).
  final double size;

  /// مقفلة؟ → silhouette رمادية.
  final bool locked;

  /// إيموجي بديل عند فشل تحميل SVG (من BadgeDef.emoji).
  final String? emojiFallback;

  /// خريطة معرف الشارة → مسار SVG.
  /// الأصول بدرجات معدنية محددة لكل شارة (لا تلوين ديناميكي —
  /// المعدن جزء من معنى الشارة).
  static const Map<String, String> _assetOf = <String, String>{
    'first-concept': 'badges/badge_first_step',
    'concepts-3': 'badges/badge_triad',
    'flashcards-25': 'badges/badge_vocabulary',
    'perfect-mcq': 'badges/badge_full_mark',
    'case-master': 'badges/badge_case_master',
    'streak-3': 'badges/badge_streak3',
    'streak-7': 'badges/badge_week_streak',
    'xp-500': 'badges/badge_xp_star',
  };

  /// أصول فشل تحميلها — لا يُعاد فحصها في كل بناء.
  static final Set<String> _missingAssets = <String>{};

  @override
  Widget build(BuildContext context) {
    final String? path = _assetOf[badgeId] == null
        ? null
        : AppSvgIcon.resolve(_assetOf[badgeId]!);

    // مقفلة بلا أصل → إيموجي مكسوف.
    if (locked) {
      return _LockedSilhouette(
        path: path,
        size: size,
        emoji: emojiFallback,
        onMissing: _markMissing,
        isMissing: _isMissing,
      );
    }

    if (path == null) {
      return _emojiBox(context, opacity: 1);
    }

    return _SvgBadge(
      path: path,
      size: size,
      emoji: emojiFallback,
      onMissing: _markMissing,
      isMissing: _isMissing,
    );
  }

  static void _markMissing(String path) => _missingAssets.add(path);
  static bool _isMissing(String path) => _missingAssets.contains(path);

  Widget _emojiBox(BuildContext context, {required double opacity}) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          emojiFallback ?? '🏅',
          style: TextStyle(fontSize: size * 0.55),
        ),
      ),
    );
  }
}

/// يعرض ميدالية SVG مع بديل إيموجي آمن — بلا FutureBuilder: خطأ
/// التحميل يظهر البديل في نفس الـ frame عبر errorBuilder.
class _SvgBadge extends StatelessWidget {
  const _SvgBadge({
    required this.path,
    required this.size,
    required this.onMissing,
    required this.isMissing,
    this.emoji,
  });

  final String path;
  final double size;
  final String? emoji;
  final void Function(String path) onMissing;
  final bool Function(String path) isMissing;

  @override
  Widget build(BuildContext context) {
    // فشل سابق معروف؟ → البديل مباشرة (صفر عمل).
    if (isMissing(path)) {
      return _emojiBox();
    }

    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      errorBuilder: (BuildContext context, Object error, StackTrace? st) {
        onMissing(path);
        return _emojiBox();
      },
    );
  }

  Widget _emojiBox() => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(emoji ?? '🏅', style: TextStyle(fontSize: size * 0.55)),
        ),
      );
}

/// الظل الصامت — شارة مقفلة: 15% رمادي + قفل صغير إن توفر رمز.
class _LockedSilhouette extends StatelessWidget {
  const _LockedSilhouette({
    required this.path,
    required this.size,
    required this.onMissing,
    required this.isMissing,
    this.emoji,
  });

  final String? path;
  final double size;
  final String? emoji;
  final void Function(String path) onMissing;
  final bool Function(String path) isMissing;

  @override
  Widget build(BuildContext context) {
    final String? resolvedPath = path;
    if (resolvedPath == null || isMissing(resolvedPath)) {
      return _emojiBox();
    }

    return Opacity(
      // Silhouette: نفس الرسمة مسطحة رمادياً بشفافية 15%.
      opacity: 0.15,
      child: SvgPicture.asset(
        resolvedPath,
        width: size,
        height: size,
        // توحيد رمادي كامل فوق ألوان المعدن.
        colorFilter: const ColorFilter.mode(
          Color(0xFF5B6879),
          BlendMode.srcIn,
        ),
        errorBuilder: (BuildContext context, Object error, StackTrace? st) {
          onMissing(resolvedPath);
          return _emojiBox();
        },
      ),
    );
  }

  Widget _emojiBox() => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Opacity(
            opacity: 0.22,
            child: Text(emoji ?? '🏅', style: TextStyle(fontSize: size * 0.55)),
          ),
        ),
      );
}
