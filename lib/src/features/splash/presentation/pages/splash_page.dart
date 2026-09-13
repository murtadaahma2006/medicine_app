import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/content_seeder.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/profile/learner_profile.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة البداية — بوابة الدخول للتطبيق بهوية بصرية واضحة.
///
/// ثلاث مهام أثناء عرض الشعار:
/// 1) فحص أول تشغيل → Onboarding أو الرئيسية.
/// 2) **تحميل القاعدة مسبقاً + زرع المحتوى الطبي** من أصول JSON
///    المدمجة (assets/content/) — يتم هنا خلف الشعار.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _routeAfterDelay();
  }

  Future<void> _routeAfterDelay() async {
    // فحص أول تشغيل فوري — خفيف (SharedPreferences).
    final bool onboarded = await LearnerProfile.isOnboarded();

    // الزرع المسبق خلف الشعار: unawaited عمداً — لا يعلّق التوجيه.
    // database getter نفسه يضمن الاتصال، وContentSeeder يزرع أصول JSON
    // المدمجة (idempotent — آمن عند كل تشغيل).
    unawaited(() async {
      try {
        await DatabaseHelper.instance.openAndSeed();
        await ContentSeeder.seedAll();
      } catch (_) {
        // صمت مقصود — الزرع الخلفي تحسين جاهزية فقط.
      }
    }());

    // حد أدنى لعرض الشعار ثم التوجيه الفوري.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    context.go(onboarded ? '/home' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = AppColors.primary(b);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              primary,
              primary.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // --- الشعار الرئيسي للتطبيق ---
                const BrandLockup(animate: true),
                const SizedBox(height: AppSpacing.xxxl + AppSpacing.sm),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white.withValues(alpha: 0.8),
                    strokeWidth: 2.5,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: AppSpacing.xs + 2),
                      Text(
                        'يعمل دون إنترنت 100%',
                        style: AppType.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
