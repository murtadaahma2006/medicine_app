import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motivation/celebration_queue.dart';
import '../../core/motivation/motivation_model.dart';
import '../../core/utils/app_haptics.dart';
import '../../theme/tokens.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'badge_icon.dart';
import 'confetti.dart';
import 'progress.dart';

/// ─────────────────────────────────────────────────────────────────────
/// طبقة التحفيز الحركية (المرحلة 6) — كل احتفالات التطبيق من هنا.
///
/// [CelebrationHost] يُركَّب في جذر التطبيق فوق كل شيء، يستهلك أحداث
/// [CelebrationQueue] واحداً واحداً: لا يظهر احتفالان فوق بعضهما أبداً.
///
/// العروض:
/// - [XpChipView]: رقاقة «+N ⚡» تصعد وتتلاشى (900ms) عند أي كسب.
/// - [BadgeCard]: بطاقة شارة منفردة تدخل بترتيب + haptic متوسط.
/// - [LevelUpView]: شاشة كاملة — تعتيم يدخل، إيموجي المستوى بـeaseOutBack
///   + كونفيتي + زر «متابعة».
///
/// XpGained أحداث خفيفة لا توقف الطابور (تعمل بالتوازي فوق الاحتفالات
/// الكبيرة) — رقاقة واحدة فقط في كل لحظة.
/// ─────────────────────────────────────────────────────────────────────
class CelebrationHost extends StatefulWidget {
  const CelebrationHost({required this.child, super.key});

  final Widget child;

  @override
  State<CelebrationHost> createState() => _CelebrationHostState();
}

class _CelebrationHostState extends State<CelebrationHost> {
  final OverlayPortalController _controller = OverlayPortalController();
  final CelebrationQueue _queue = CelebrationQueue.instance;

  /// الحدث الكبير الجاري عرضه (شارة/ترقية) — null بين الأحداث.
  CelebrationEvent? _current;

  /// رقاقة XP الجارية (حدث خفيف لا يحتل الطابور).
  XpGained? _xp;

  /// هل الحركات مفعّلة؟ (يُحدَّث في didChangeDependencies — MediaQuery
  /// لا يُقرأ في initState).
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _queue.addListener(_drain);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled = !MediaQuery.disableAnimationsOf(context);
    _drain();
  }

  @override
  void dispose() {
    _queue.removeListener(_drain);
    _queue.complete();
    super.dispose();
  }

  /// حاول سحب الحدث التالي إن لم يكن جارٍ شيء.
  void _drain() {
    if (_current == null && !_controller.isShowing) {
      // الحدث الكبير التالي من الطابور (يستولي عليه عبر busy).
      final CelebrationEvent? next = _queue.takeNext();
      if (next != null && _animationsEnabled) {
        if (mounted) setState(() => _current = next);
      } else if (next != null) {
        // حركات معطلة — الحدث يُستهلك بلا عرض.
        _queue.complete();
      }
    }
    // أحداث XP خفيفة: أول واحدة معلقة فقط.
    if (_xp == null) {
      for (int i = 0; i < _queue.pendingCount; i++) {
        final CelebrationEvent e = _queue.peekAt(i);
        if (e is XpGained) {
          if (_animationsEnabled && mounted) {
            setState(() => _xp = e);
          }
          _queue.removeAt(i);
          break;
        }
      }
    }
    // البورتال يظهر عند أي عرض نشط (حدث كبير أو رقاقة XP).
    if ((_current != null || _xp != null) && !_controller.isShowing) {
      _controller.show();
    }
  }

  void _onXpDone() {
    if (!mounted) return;
    setState(() => _xp = null);
    if (_current == null) _controller.hide();
    _drain();
  }

  void _onCelebrationDone() {
    if (!mounted) return;
    _controller.hide();
    setState(() => _current = null);
    _queue.complete();
    _drain();
    if ((_current != null || _xp != null) && !_controller.isShowing) {
      _controller.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (BuildContext overlayContext) {
        final CelebrationEvent? event = _current;
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (event is BadgeEarned)
              BadgeCard(
                badge: event.badge,
                onDone: _onCelebrationDone,
              )
            else if (event is LevelUp)
              LevelUpView(
                level: event.level,
                totalXp: event.totalXp,
                onDone: _onCelebrationDone,
              ),
            if (_xp != null)
              XpChipView(
                event: _xp!,
                onDone: _onXpDone,
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// رقاقة «+N ⚡» — تصعد 64px وتتلاشى خلال 900ms ثم تُبلّغ [onDone].
class XpChipView extends StatefulWidget {
  const XpChipView({required this.event, required this.onDone, super.key});

  final XpGained event;
  final VoidCallback onDone;

  @override
  State<XpChipView> createState() => _XpChipViewState();
}

class _XpChipViewState extends State<XpChipView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    // whenComplete يمكن أن يُطلق callback بعد dispose — نستخدم StatusListener
    // الذي يُزال في dispose فلا يُستدعى أبداً بعده.
    _controller.addStatusListener(_onAnimDone);
  }

  void _onAnimDone(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimDone);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Positioned(
      // فوق منتصف الشاشة قليلاً — أسفل الرأس، مكان يستحق الانتباه.
      top: MediaQuery.sizeOf(context).height * 0.30,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                final double t = _controller.value;
                // ظهور سريع (أول 20%) ثم صعود وتلاشٍ.
                final double opacity =
                    t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8;
                // الطيران القوسي: يصعد مع انحراف أفقي لطيف (منحنى
                // نابض باتجاه اليسار حيث عداد XP غالباً) ثم يعود —
                // «XP الطائر» يترك أثراً حياً لا مساراً ميكانيكياً.
                final double dx = -18 * math.sin(t * math.pi);
                final double dy = -64 * t;
                final double scale =
                    0.85 + 0.15 * AppMotion.popIn.transform(t.clamp(0.0, 1.0));
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.scale(
                      scale: scale,
                      child: child,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  // التدرج الذهبي المقدس — رقاقة XP مكانه الطبيعي.
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: AppGradients.gold,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppShadows.floating(b),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.bolt_rounded,
                        size: 18, color: Colors.white),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '+${widget.event.xp}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontFamily: AppType.arabicFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Text(
                      'نقطة',
                      style: TextStyle(
                        fontFamily: AppType.arabicFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة شارة واحدة — تظهر فوق تعتيم خفيف، تنتظر «متابعة».
class BadgeCard extends StatefulWidget {
  const BadgeCard({required this.badge, required this.onDone, super.key});

  final BadgeDef badge;
  final VoidCallback onDone;

  @override
  State<BadgeCard> createState() => _BadgeCardState();
}

class _BadgeCardState extends State<BadgeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    AppHaptics.celebrate();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.celebration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    final bool animOn = !MediaQuery.disableAnimationsOf(context);
    if (!animOn) {
      widget.onDone();
      return;
    }
    _controller.reverse().whenCompleteOrCancel(widget.onDone);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool animOn = !MediaQuery.disableAnimationsOf(context);

    return Positioned.fill(
      child: GestureDetector(
        // نقر خارج البطاقة يغلقها أيضاً.
        onTap: _dismiss,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double t = _controller.value;
            return Container(
              color: AppColors.bgDark.withValues(alpha: 0.55 * t),
              child: Center(
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    // دخول مرح: easeOutBack إلى 1.
                    scale: animOn ? 0.4 + 0.6 * AppMotion.popIn.transform(t) : 1,
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: AppCard(
              radius: AppRadius.sheet,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // ميدالية SVG التوقيعية — أو إيموجي بديل آمن.
                  BadgeIcon(
                    widget.badge.id,
                    size: 120,
                    emojiFallback: widget.badge.emoji,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'شارة جديدة!',
                    style: AppType.caption.copyWith(
                      color: AppColors.gold(b),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.badge.titleAr,
                    style: AppType.screenTitle.copyWith(
                      color: AppColors.text(b),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.badge.descriptionAr,
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(
                      color: AppColors.textSecondary(b),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'متابعة',
                    expanded: false,
                    onPressed: _dismiss,
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

/// شاشة رفع المستوى الكاملة — السيناريو الدرامي:
///
/// 1. حلقة ذهبية تمتلئ (حتى 50% من المدة) ورقم المستوى يعدّ تصاعدياً
///    داخلها، وتعتيم الشاشة يدخل معها.
/// 2. توقف درامي عند الاكتمال (الجمهور يلهث).
/// 3. عند 72% «انكسار» الحلقة: ومضة ذهبية + انفجار كونفيتي + haptic
///    ثلاثي (نقرة-نقرة-صدمة) + الحلقة تتمدد وتتلاشى وكأنها تتفتت.
/// 4. إيموجي المستوى يدخل بـeaseOutBack + شارة «مستوى جديد» بتدرج
///    ذهبي (مكان مقدس للتدرج).
/// 5. زر «متابعة» فقط — لا إغلاق بالنقر (لحظة تستحق التأمل).
class LevelUpView extends StatefulWidget {
  const LevelUpView({
    required this.level,
    required this.totalXp,
    required this.onDone,
    super.key,
  });

  final LearnerLevel level;
  final int totalXp;
  final VoidCallback onDone;

  @override
  State<LevelUpView> createState() => _LevelUpViewState();
}

class _LevelUpViewState extends State<LevelUpView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// مراحل السيناريو — مشتقة من قيمة الـcontroller (0→1).
  static const double _fillEnd = 0.5; // امتلاء الحلقة (800ms)
  static const double _burstAt = 0.72; // لحظة الانكسار

  bool _burstFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() => widget.onDone();

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool animOn = !MediaQuery.disableAnimationsOf(context);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double t = animOn ? _controller.value : 1.0;

          // ── المرحلة 3: الانكسار — مرة واحدة ──
          if (animOn && !_burstFired && t >= _burstAt) {
            _burstFired = true;
            AppHaptics.levelUpTriple();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) ConfettiBurst.show(context);
            });
          }

          // التعتيم يدخل مع الامتلاء.
          final double dim = animOn
              ? (t / _fillEnd).clamp(0.0, 1.0) * 0.74
              : 0.74;

          // الحلقة تمتلئ حتى _fillEnd ثم تبقى ممتلئة حتى الانكسار.
          final double ringT = (t / _fillEnd).clamp(0.0, 1.0);

          // الانكسار: تمدد وتلاشي بعد _burstAt.
          final double breakT = t < _burstAt
              ? 0
              : ((t - _burstAt) / (1 - _burstAt)).clamp(0.0, 1.0);
          final double ringOpacity =
              t < _burstAt ? 1 : (1 - breakT * 2).clamp(0.0, 1.0);
          final double burstScale = 1 + breakT * 0.35;

          // العد التصاعدي داخل الحلقة — يتجمد عند رقم المستوى.
          final double countT = (t / _fillEnd).clamp(0.0, 1.0);
          final int levelIndex = widget.level.index;
          final int shown =
              (countT * levelIndex).round().clamp(0, levelIndex);

          // ومضة الانفجار الذهبية.
          final double flashOpacity =
              _burstFired && breakT < 0.5 ? breakT * 2 : (1 - breakT) * 1.4;

          return Container(
            color: AppColors.bgDark.withValues(alpha: dim),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // ── ومضة الانفجار خلف كل شيء ──
                  if (animOn && _burstFired)
                    IgnorePointer(
                      child: Opacity(
                        opacity: flashOpacity.clamp(0.0, 1.0),
                        child: Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: AppColors.gold(b)
                                    .withValues(alpha: 0.5 * (1 - breakT)),
                                blurRadius: 120,
                                spreadRadius: 60,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // ── محتوى البطاقة (child ثابت — لا يُعاد بناؤه) ──
                  child!,

                  // ── الحلقة الذهبية فوق المحتوى المركزي ──
                  // تُرسم كطبقة مستقلة حتى تنكسر دون مساس بالنص.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: ringOpacity,
                          child: Transform.scale(
                            scale: burstScale,
                            child: ProgressRing(
                              progress: ringT,
                              size: 110,
                              stroke: 7,
                              color: AppColors.gold(b),
                              child: const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── العداد التصاعدي في مركز الحلقة ──
                  IgnorePointer(
                    child: Opacity(
                      opacity: ringOpacity,
                      child: SizedBox(
                        width: 110,
                        height: 110,
                        child: Center(
                          child: Text(
                            '$shown',
                            textDirection: TextDirection.ltr,
                            style: AppType.screenTitle.copyWith(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: AppColors.gold(b),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // مساحة الحلقة — المحتوى يبدأ تحتها.
            const SizedBox(height: 110),
            const SizedBox(height: AppSpacing.lg),

            // ── إيموجي المستوى يدخل بعد الانكسار ──
            _EmojiBurstIn(
              controller: _controller,
              burstAt: _burstAt,
              animOn: animOn,
              emoji: widget.level.emoji,
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── شارة «مستوى جديد» بتدرج ذهبي مقدس ──
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.xs + 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: AppGradients.gold,
                ),
              ),
              child: const Text(
                'مستوى جديد',
                style: TextStyle(
                  fontFamily: AppType.arabicFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onGold,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.level.titleAr,
              style: AppType.screenTitle.copyWith(
                fontSize: 30,
                color: AppColors.text(b),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${widget.totalXp} نقطة خبرة',
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(
                color: AppColors.textSecondary(b),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppButton(
              label: 'متابعة',
              expanded: false,
              onPressed: _continue,
            ),
          ],
        ),
      ),
    );
  }
}

/// إيموجي المستوى — يظهر بعد الانكسار بـeaseOutBack.
class _EmojiBurstIn extends StatelessWidget {
  const _EmojiBurstIn({
    required this.controller,
    required this.burstAt,
    required this.animOn,
    required this.emoji,
  });

  final AnimationController controller;
  final double burstAt;
  final bool animOn;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        if (!animOn) return child!;
        final double t = controller.value;
        final double e = t < burstAt
            ? 0
            : ((t - burstAt) / (1 - burstAt)).clamp(0.0, 1.0);
        return Opacity(
          opacity: e.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.4 + 0.6 * AppMotion.popIn.transform(e),
            child: child,
          ),
        );
      },
      child: Text(emoji, style: const TextStyle(fontSize: 56)),
    );
  }
}
