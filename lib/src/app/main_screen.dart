import 'package:flutter/material.dart';

import '../features/curriculum/presentation/pages/curriculum_page.dart';
import '../features/curriculum/presentation/pages/library_page.dart';
import '../features/curriculum/presentation/pages/today_page.dart';
import '../features/profile/presentation/pages/profile_page.dart';
import '../shared/widgets/widgets.dart';
import '../theme/tokens.dart';

/// الشاشة الجذرية — شريط تنقل سفلي بأربعة ألسنة (IndexedStack).
///
/// الهوية البصرية: طقم أيقونات مملوك بهوية ECG (نبضة قلب تخترق
/// كل أيقونة) — لا أيقونات مكتبات مستعارة.
///
/// - غير محدد: خط SVG مجرد بسماكة 1.8 بلون ثانوي هادئ.
/// - محدد: يتمدد داخل كبسولة بنت الكحلي بحركة **ضمنية موحّدة**
///   (140ms — أيقونة تكبر 12% + كبسولة تتمدد + لون يتماهاى) —
///   سريعة، صامتة، بلا Stateful ولا متحكمات تُدار يدوياً.
///
/// التنقل سلس: تبديل المؤشر يبدّل الشاشة داخل [IndexedStack] بلا
/// إعادة بناء، مع الحفاظ على حالة كل لسان.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  /// الشاشات الأربع — تُبنى مرة واحدة فلا تُعاد عند التبديل.
  final List<Widget> _screens = const <Widget>[
    TodayPage(),
    CurriculumPage(),
    LibraryPage(),
    ProfilePage(),
  ];

  /// عناوين الألسنة العربية (للـAppBar أعلى كل شاشة).
  static const List<String> _titles = <String>[
    'اليوم',
    'المسار',
    'المكتبة',
    'ملفّي',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_currentIndex])),
      body: IndexedStack(
        index: _currentIndex,
        children: <Widget>[
          // TickerMode يوقف حلقات اللسان غير المرئي (نبض السلسلة 🔥
          // مثلاً) — لا حركة تعمل على شاشة غير معروضة.
          for (int i = 0; i < _screens.length; i++)
            TickerMode(
              enabled: i == _currentIndex,
              child: _screens[i],
            ),
        ],
      ),
      bottomNavigationBar: _PulsingNavBar(
        currentIndex: _currentIndex,
        onTap: (int index) {
          if (index == _currentIndex) return;
          setState(() => _currentIndex = index);
        },
        items: const <_NavItem>[
          _NavItem(
            svg: 'nav/nav_today',
            fallbackIcon: Icons.wb_sunny_rounded,
            label: 'اليوم',
          ),
          _NavItem(
            svg: 'nav/nav_path',
            fallbackIcon: Icons.route_rounded,
            label: 'المسار',
          ),
          _NavItem(
            svg: 'nav/nav_library',
            fallbackIcon: Icons.local_library_rounded,
            label: 'المكتبة',
          ),
          _NavItem(
            svg: 'nav/nav_profile',
            fallbackIcon: Icons.person_rounded,
            label: 'ملفّي',
          ),
        ],
      ),
    );
  }
}

/// عنصر لسان — أيقونة SVG المخصصة + بديل مادي آمن.
class _NavItem {
  const _NavItem({
    required this.svg,
    required this.fallbackIcon,
    required this.label,
  });

  final String svg;
  final IconData fallbackIcon;
  final String label;
}

/// ─────────────────────────────────────────────────────────────────────
/// شريط التنقل النابض — بأيقونات مملوكة وحد علوي وكبسولات تنت.
///
/// بنية كل لسان: كبسولة بلون تنت الكحلي تحت الأيقونة عند التحديد،
/// والأيقونة SVG خطي بلون الثيم (selected/unselected).
/// ─────────────────────────────────────────────────────────────────────
class _PulsingNavBar extends StatelessWidget {
  const _PulsingNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Brightness b = scheme.brightness;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline)),
        boxShadow: AppShadows.floating(b),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _PulsingTab(
                    item: items[i],
                    selected: i == currentIndex,
                    selectedColor: scheme.primary,
                    unselectedColor: scheme.onSurfaceVariant,
                    indicatorColor: AppColors.primaryTint(b),
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// لسان واحد — انتقال سلس بلا Stateful: كل الخصائص تتحول عبر
/// TweenAnimationBuilder الضمني (المتزامن — أول frame صحيح دائماً،
/// لا async gap ولا FutureBuilder وميض).
///
/// - الأيقونة: تكبير 1 → 1.12 عند التحديد (140ms easeOutCubic) —
///   أسرع وألطف من النبضة القديمة 220ms.
/// - الكبسولة: تتقلص/تتمدد مع الحشو (140ms) — انتقال الحجم مدمج
///   في نفس الحركة لا حاوية ثابتة.
/// - اللون والنص: 140ms — كل شيء يتحرك معاً فيتماهى.
class _PulsingTab extends StatelessWidget {
  const _PulsingTab({
    required this.item,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.indicatorColor,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final Color indicatorColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool animate = !MediaQuery.disableAnimationsOf(context);
    final Duration dur =
        animate ? const Duration(milliseconds: 140) : Duration.zero;

    final Color color =
        selected ? selectedColor : unselectedColor;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 1),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: selected ? 1.0 : 0.0),
              duration: dur,
              curve: AppMotion.ease,
              builder: (BuildContext context, double t, _) {
                // t: 0 = غير محدد · 1 = محدد — مزج كل الخصائص منه.
                final double scale = 1.0 + 0.12 * t;

                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Transform.scale(
                        scale: scale,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg + 8 * t,
                            vertical: AppSpacing.xs + 1,
                          ),
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              Colors.transparent,
                              indicatorColor,
                              t,
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: AppSvgIcon(
                            item.svg,
                            size: 26,
                            color: color,
                            fallback: item.fallbackIcon,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: AppType.caption.copyWith(
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
