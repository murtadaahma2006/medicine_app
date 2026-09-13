import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// مكوّن اللوكب التعريفي (Logo Mark + النص الألماني + النص العربي).
/// يمكن استخدامه في شاشة البداية (بحجم كبير) أو في ترويسات الشاشات (بحجم صغير).
class BrandLockup extends StatefulWidget {
  const BrandLockup({
    this.size = 110,
    this.animate = false,
    super.key,
  });

  /// الحجم الأساسي لعلامة الشعار (Mark).
  final double size;

  /// تفعيل حركة الدخول Scale+Fade (لشاشة البداية).
  final bool animate;

  @override
  State<BrandLockup> createState() => _BrandLockupState();
}

class _BrandLockupState extends State<BrandLockup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AppMotion.popIn,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: AppMotion.ease),
      ),
    );
    // لا نقرأ MediaQuery هنا — التشغيل في didChangeDependencies (نمط StreakChip).
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery لا يُقرأ في initState — النمط المعتمد كما في StreakChip.
    _syncAnimation();
  }

  void _syncAnimation() {
    final bool shouldAnimate =
        widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate) {
      if (_controller.isDismissed) _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: widget.size * 0.3,
                    offset: Offset(0, widget.size * 0.1),
                  ),
                ],
              ),
              padding: EdgeInsets.all(widget.size * 0.15),
              child: Image.asset(
                'assets/brand/final/logo_mark.png',
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Text(
                '🩺',
                style: TextStyle(fontSize: widget.size * 0.5),
              ),
            ),
          ),
          SizedBox(height: widget.size * 0.25),
          Text(
            'منصة الطب الباطني',
            style: TextStyle(
              fontFamily: AppType.arabicFamily,
              fontSize: widget.size * 0.2,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: widget.size * 0.05),
          Text(
            'Internal Medicine',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: AppType.latinFamily,
              fontSize: widget.size * 0.12,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

