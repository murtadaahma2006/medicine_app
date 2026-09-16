import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/profile/learner_profile.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة الترحيب — تظهر مرة واحدة فقط عند أول تشغيل بعد التثبيت.
///
/// تصميم بسيط وأنيق: شعار التطبيق + رسالة ترحيب + رسم توضيحي +
/// زر «ابدأ الآن» يوسم أول تشغيل ويوجه إلى الرئيسية مباشرة.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.15, 1, curve: Curves.easeOutCubic),
    );
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.1, 0.9, curve: Curves.easeOutCubic),
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _getStarted() async {
    if (_navigating) return;
    _navigating = true;

    // وسم أول تشغيل — لن تظهر الشاشة مجدداً.
    await LearnerProfile.markOnboarded();
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color primary = AppColors.primary(b);
    final double screenH = MediaQuery.sizeOf(context).height;
    final bool compact = screenH < 580;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              primary,
              primary.withValues(alpha: 0.88),
              primary.withValues(alpha: 0.72),
            ],
            stops: const <double>[0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                    vertical: AppSpacing.lg,
                  ),
                  child: Column(
                    children: <Widget>[
                      const Spacer(flex: 2),

                      // ── الشعار ──
                      const BrandLockup(animate: true),

                      SizedBox(height: compact ? AppSpacing.xl : 48.0),

                      // ── المحتوى المتحرك ──
                      FadeTransition(
                        opacity: _fadeIn,
                        child: SlideTransition(
                          position: _slideUp,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // ── العنوان ──
                              Text(
                                'أهلاً بك!',
                                style: AppType.screenTitle.copyWith(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: AppSpacing.md),

                              // ── العنوان الفرعي ──
                              Text(
                                'منصتك الطبية الشاملة — بطاقات تكرارية\n'
                                'ومعلومات يومية وتقدم ملموس',
                                style: AppType.body.copyWith(
                                  fontSize: 16,
                                  height: 1.7,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                                textAlign: TextAlign.center,
                              ),

                              // ── الرسم التوضيحي ──
                              if (!compact) ...<Widget>[
                                SizedBox(
                                  height: compact ? AppSpacing.lg : 32.0,
                                ),
                                Image.asset(
                                  'assets/illustrations/units/unit_cardio.png',
                                  height: (screenH * 0.22).clamp(120.0, 200.0),
                                  fit: BoxFit.contain,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const Spacer(flex: 3),

                      // ── زر البدء ──
                      FadeTransition(
                        opacity: _fadeIn,
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _getStarted,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.card),
                              ),
                              textStyle: AppType.body.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text('ابدأ الآن'),
                                SizedBox(width: AppSpacing.sm),
                                Icon(Icons.arrow_back_rounded, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      // ── شارة «يعمل دون إنترنت» ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Text(
                            'يعمل دون إنترنت 100%',
                            style: AppType.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
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
