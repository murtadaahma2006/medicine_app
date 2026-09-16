import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/content_seeder.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/notifications/pin_expiry_service.dart';
import '../../../../core/profile/learner_profile.dart';
import '../../../../core/widget/home_widget_service.dart';
import '../../../../theme/tokens.dart';

/// شاشة البداية — بوابة الدخول اليومية للتطبيق بهوية بصرية نظيفة
/// ومحايدة تناسب منصة طبية متعددة التخصصات.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    
    _fadeController.forward();
    _routeAfterDelay();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _routeAfterDelay() async {
    final bool onboarded = await LearnerProfile.isOnboarded();

    unawaited(() async {
      try {
        await DatabaseHelper.instance.openAndSeed();
        await ContentSeeder.seedAll();
        await PinExpiryService.runAppCleanup();
      } catch (_) {}
    }());

    // حد أدنى لعرض الشاشة بشكل أنيق
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    HomeWidgetService.markStartupFinished();

    final bool widgetLaunch =
        onboarded && HomeWidgetService.consumePendingNavigation();
    if (widgetLaunch) {
      context.go('/daily-review');
    } else {
      context.go(onboarded ? '/home' : '/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = AppColors.primary(b);
    final Color surface = AppColors.surface(b);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              primary,
              Color.lerp(primary, AppColors.bgDark, b == Brightness.dark ? 0.45 : 0.18)!,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // ── العلامة المركزية (Generic Brand Lockup Icon) ──
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: surface,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.05),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(26),
                    child: Image.asset(
                      'assets/brand/icon/app_icon_foreground_new.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.health_and_safety_rounded,
                        size: 64,
                        color: primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),

                  // ── نص تحميل محايد ──
                  Text(
                    'جاري تجهيز بيئة التعلم...',
                    style: AppType.cardTitle.copyWith(
                      fontSize: 22,
                      color: Colors.white,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── مؤشر نشاط مصقول ──
                  const CupertinoActivityIndicator(
                    color: Colors.white,
                    radius: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}