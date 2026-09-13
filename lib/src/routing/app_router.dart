import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/main_screen.dart';
import '../features/curriculum/presentation/pages/daily_review_page.dart';
import '../features/dev/brand_preview_page.dart';
import '../features/dev/error_log_page.dart';
import '../features/dev/style_preview_page.dart';
import '../features/onboarding/presentation/pages/onboarding_page.dart';
import '../features/progress/presentation/pages/progress_page.dart';
import '../features/settings/presentation/pages/reminder_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/splash/presentation/pages/splash_page.dart';

/// مسارات التطبيق — مصدر الحقيقة الوحيد لأسماء المسارات.
abstract final class RoutePaths {
  static const String splash = '/';
  static const String home = '/home';
  static const String progress = '/progress';
  static const String settings = '/settings';
  static const String reminder = '/reminder';
  static const String dailyReview = '/daily-review';
  static const String onboarding = '/onboarding';
  // debug فقط — سجل الأخطاء ومعاينة الهوية ودليل التصميم
  static const String devErrorLog = '/dev/error-log';
  static const String devBrandPreview = '/dev/brand_preview';
  static const String devStylePreview = '/dev/style_preview';
}

/// مفتاح الجذر العالمي — يسمح بالتنقل من أي مكان في التطبيق.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// انتقال الصفحات الموحد — fade-through 300ms.
CustomTransitionPage<void> fadeThroughPage({
  required Widget child,
  Object? arguments,
}) {
  return CustomTransitionPage<void>(
    child: child,
    arguments: arguments,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder:
        (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation, Widget child) {
      // احترام تعطيل الحركات: قفز فوري.
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final CurvedAnimation fade = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
      );
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      );
    },
  );
}

/// نظام التوجيه المركزي (declarative) عبر go_router.
///
/// ملاحظة معمارية: شاشات الوحدة والدروس تُفتح عبر Navigator.push
/// المباشر (underlay من الشاشة الرئيسية) — راجع main_screen.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: RoutePaths.splash,
  routes: <RouteBase>[
    GoRoute(
      path: RoutePaths.splash,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(child: const SplashPage()),
    ),
    GoRoute(
      path: RoutePaths.home,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(child: const MainScreen()),
    ),
    GoRoute(
      path: RoutePaths.progress,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(child: const ProgressPage()),
    ),
    GoRoute(
      path: RoutePaths.settings,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(child: const SettingsPage()),
    ),
    GoRoute(
      path: RoutePaths.reminder,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(child: const ReminderPage()),
    ),
    GoRoute(
      path: RoutePaths.dailyReview,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(child: const DailyReviewPage()),
    ),
    GoRoute(
      path: RoutePaths.onboarding,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(child: const OnboardingPage()),
    ),
    // ─── debug فقط: سجل الأخطاء والمعاينة البصرية ───
    GoRoute(
      path: RoutePaths.devErrorLog,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(
        child: kDebugMode
            ? const ErrorLogPage()
            : const Scaffold(
                body: Center(child: Text('غير متاح في الإنتاج')),
              ),
      ),
    ),
    GoRoute(
      path: RoutePaths.devBrandPreview,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(
        child: kDebugMode
            ? const BrandPreviewPage()
            : const Scaffold(
                body: Center(child: Text('غير متاح في الإنتاج')),
              ),
      ),
    ),
    GoRoute(
      path: RoutePaths.devStylePreview,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          fadeThroughPage(
        child: kDebugMode
            ? const StylePreviewPage()
            : const Scaffold(
                body: Center(child: Text('غير متاح في الإنتاج')),
              ),
      ),
    ),
  ],
);
