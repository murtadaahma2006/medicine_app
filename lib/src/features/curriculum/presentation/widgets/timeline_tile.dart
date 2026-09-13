import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';
import '../../domain/unit.dart';
import 'unit_card.dart';

/// ─────────────────────────────────────────────────────────────────────
/// الخط الزمني للرحلة — عرض المسار كخط رحلة متصل.
///
/// لكل تخصص عمود جانبي رأسي بلون التخصص تتصل به عقد الوحدات:
/// عقدة مكتملة (ممتلئة بعلامة ✓) · عقدة حالية (حلقة نابضة «أنت هنا») ·
/// عقدة مقبلة (حد فقط). الخط متصل بصرياً بين كل عقدتين متتاليتين
/// ويصل حتى آخر عقدة في التخصص — رحلة لا تنتهي عند الوحدة الحالية.
/// ─────────────────────────────────────────────────────────────────────

/// حالة عقدة وحدة داخل الخط الزمني.
enum TimelineNodeState { completed, current, locked }

/// عرض وحدة واحدة داخل الخط الزمني — العقدة + البطاقة.
class TimelineUnitTile extends StatelessWidget {
  const TimelineUnitTile({
    required this.unit,
    required this.state,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    super.key,
  });

  final Unit unit;

  /// حالة الوحدة (مكتملة/حالية/مقبلة).
  final TimelineNodeState state;

  /// أول عقدة في مستواها؟ (يبدأ الخط تحتها لا فوقها).
  final bool isFirst;

  /// آخر عقدة في مستواها؟ (ينتهي الخط عندها).
  final bool isLast;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color levelColor = _levelColor(b);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── عمود الخط الزمني: العقدة + الخط المتصل ──
          SizedBox(
            width: 40,
            child: Column(
              children: <Widget>[
                // خط علوي — يظهر فقط لغير الأولى (يصلها بما فوقها).
                if (!isFirst)
                  Expanded(
                    child: Container(width: 3, color: levelColor),
                  )
                else
                  const Spacer(),
                _NodeDot(
                  state: state,
                  color: levelColor,
                ),
                // خط سفلي — حتى آخر عقدة (الخط يكمل الرحلة).
                if (!isLast)
                  Expanded(
                    child: Container(width: 3, color: levelColor),
                  )
                else
                  const Spacer(),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // ── بطاقة الوحدة ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: UnitCard(
                unitId: unit.id,
                module: unit.module,
                title: _cleanTitle(unit.title),
                progress: state == TimelineNodeState.completed ? 1.0 : null,
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// لون تخصص الوحدة من نظام الألوان.
  Color _levelColor(Brightness b) {
    return AppColors.module(unit.module, b);
  }

  static String _cleanTitle(String raw) {
    // تنظيف بسيط للعناوين المخزنة بتنسيق markdown ([..] والأغصان).
    String t = raw;
    if (t.startsWith('[') && t.contains(']')) {
      t = t.substring(1, t.indexOf(']'));
    }
    return t.trim();
  }
}

/// عقدة الخط الزمني — دائرة 26px حسب الحالة.
class _NodeDot extends StatelessWidget {
  const _NodeDot({required this.state, required this.color});

  final TimelineNodeState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool animOn = !MediaQuery.disableAnimationsOf(context);
    final Color surface = Theme.of(context).colorScheme.surface;

    Widget dot;
    switch (state) {
      // مكتملة: ممتلئة بلون المستوى + علامة ✓ بيضاء.
      case TimelineNodeState.completed:
        dot = Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: AppShadows.card(
                Theme.of(context).colorScheme.brightness),
          ),
          child: const Icon(Icons.check_rounded,
              size: 16, color: Colors.white),
        );

      // الحالية: حلقة «أنت هنا» — نابضة عند تفعيل الحركات، وإلا
      // حلقة ساكنة بنقطة مركزية (احترام disableAnimations).
      case TimelineNodeState.current:
        dot = animOn
            ? _PulsingDot(color: color)
            : Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: surface,
                  border: Border.all(color: color, width: 3),
                ),
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );

      // مقبلة: حد فقط بلون المستوى على سطح الخلفية.
      case TimelineNodeState.locked:
        dot = Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surface,
            border: Border.all(color: color, width: 2.4),
          ),
        );
    }

    return RepaintBoundary(child: dot);
  }
}

/// حلقة «أنت هنا» النابضة — نبض خافت مستمر 1.6s.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          // نبض خافت: 1.0 → 1.18 بمنحنى تنفسي.
          final double t = Curves.easeInOut.transform(_controller.value);
          final double scale = 1 + 0.18 * t;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: widget.color, width: 3),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
