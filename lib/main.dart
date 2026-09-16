import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'src/app/app.dart';
import 'src/core/utils/error_logger.dart';
import 'src/core/widget/home_widget_service.dart';
import 'src/routing/app_router.dart';
import 'src/shared/widgets/app_illustration.dart';

Future<void> main() async {
  // ضمان جاهزية ربط المحرك قبل أي إعداد للخدمات (التخزين المحلي لاحقاً).
  WidgetsFlutterBinding.ensureInitialized();

  // المرحلة 0: خطّاف الأخطاء العالمي — يجب قبل runApp.
  AppErrorLogger.instance.init();

  // اكتشاف الملفات من AssetManifest
  await AppIllustration.initManifest();

  // تجربة استخدام عمودية فقط — نمط مناسب لتطبيق تعليمي على الهاتف.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // شاشة خطأ ذكية: في debug تبقى الشاشة الحمراء الافتراضية (ليراها المطور)،
  // في release رسالة ودّية بدل الشاشة الرمادية.
  if (!kDebugMode) {
    ErrorWidget.builder = _buildFriendlyError;
  }

  // ويدجت الشاشة الرئيسية: تسجيل الخلفية + توجيه الضغط
  // (يفتح «المراجعة اليومية») + تحديث البيانات عند الإقلاع.
  unawaited(() async {
    try {
      // قبل كل شيء: معالج النقرة — قد تصل نقرة الإقلاع البارد في
      // أي لحظة بعد هذا السطر. إن سبقت بناء الـ navigator تُسجَّل
      // نيةً تستهلكها شاشة البداية (لا توجيه إلى فراغ).
      HomeWidgetService.setClickHandler(() {
        final NavigatorState? navigator = rootNavigatorKey.currentState;
        if (navigator != null && navigator.context.mounted) {
          navigator.context.go(RoutePaths.dailyReview);
        } else {
          // الراوتر لم يُبنَ بعد — نية تستهلكها شاشة البداية.
          HomeWidgetService.setPendingDailyReview();
        }
      });
      await HomeWidgetService.registerBackgroundTask();
      await HomeWidgetService.initClickRouting();
      await HomeWidgetService.refresh();
    } catch (_) {
      // الويدجت تحسين غير حركي — فشلها لا يعيق الإقلاع.
    }
  }());

  runApp(const MedicalLearningApp());
}

Widget _buildFriendlyError(FlutterErrorDetails details) {
  return const Material(
    color: Color(0xFFFAFAFA),
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: Color(0xFFB00020)),
            SizedBox(height: 16),
            Text(
              'حدث خطأ غير متوقع.\nيرجى إعادة فتح الشاشة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.6),
            ),
          ],
        ),
      ),
    ),
  );
}
