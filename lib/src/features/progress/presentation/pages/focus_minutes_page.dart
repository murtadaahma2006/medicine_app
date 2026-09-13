import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// ─────────────────────────────────────────────────────────────────────
/// شاشة «دقائق التركيز» — مقياس الشمال (North Star Metric).
///
/// **دقائق القراءة المركّزة — لا XP — هي الرقم المهم.**
/// زمن البقاء داخل كتلة قراءة/بطاقات بلا خروج من التطبيق، من جدول
/// flow_sessions. يعرض: اليوم + آخر 7 أيام (رسم أعمدة بسيط) + المجموع.
/// ─────────────────────────────────────────────────────────────────────
class FocusMinutesPage extends StatefulWidget {
  const FocusMinutesPage({super.key});

  @override
  State<FocusMinutesPage> createState() => _FocusMinutesPageState();
}

class _FocusMinutesPageState extends State<FocusMinutesPage> {
  bool _loading = true;
  String? _error;

  int _todayMinutes = 0;
  int _weekTotalMinutes = 0;
  List<MapEntry<String, int>> _recent = const <MapEntry<String, int>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final String today =
          DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final int todaySeconds = await db.focusedSecondsOnDay(today);
      final List<MapEntry<String, int>> recent =
          await db.focusedMinutesRecent(7);

      final Map<String, int> byDay = <String, int>{
        for (final MapEntry<String, int> e in recent) e.key: e.value,
      };
      // ملء الأيام الغائبة بأصفار (7 أيام حتى اليوم).
      final List<MapEntry<String, int>> filled =
          <MapEntry<String, int>>[];
      for (int i = 6; i >= 0; i--) {
        final String day = DateTime.now()
            .toUtc()
            .subtract(Duration(days: i))
            .toIso8601String()
            .substring(0, 10);
        filled.add(MapEntry<String, int>(day, byDay[day] ?? 0));
      }

      if (!mounted) return;
      setState(() {
        _todayMinutes = (todaySeconds / 60).floor();
        _weekTotalMinutes = filled
            .map((MapEntry<String, int> e) => e.value)
            .fold(0, (int a, int b) => a + b);
        _recent = filled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل دقائق التركيز.';
        _loading = false;
      });
    }
  }

  String _dayLabel(String isoDate) {
    final DateTime d = DateTime.parse(isoDate);
    const List<String> days = <String>[
      'أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت',
    ];
    final DateTime today = DateTime.now().toUtc();
    if (d.day == today.day && d.month == today.month) return 'اليوم';
    return days[d.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('دقائق التركيز')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  actionLabel: 'إعادة المحاولة',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: <Widget>[
                      // ── الرقم الكبير: اليوم ──
                      AppCard(
                        accent: AppColors.success(b),
                        child: Column(
                          children: <Widget>[
                            Text(
                              'تركيزك اليوم',
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.textSecondary(b),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '$_todayMinutes',
                              textDirection: TextDirection.ltr,
                              style: AppType.cardTitle.copyWith(
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                                color: AppColors.success(b),
                              ),
                            ),
                            Text(
                              'دقيقة قراءة مركّزة',
                              style: AppType.body.copyWith(
                                color: AppColors.textSecondary(b),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'هذا هو الرقم المهم — ليس XP: دقائق البقاء'
                              ' داخل جلساتك بلا خروج من التطبيق.',
                              textAlign: TextAlign.center,
                              style: AppType.body.copyWith(
                                fontSize: 12,
                                height: 1.6,
                                color: AppColors.textSecondary(b),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // ── رسم آخر 7 أيام ──
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  'آخر 7 أيام',
                                  style: AppType.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text(b),
                                  ),
                                ),
                                Text(
                                  'المجموع: $_weekTotalMinutes د',
                                  style: AppType.caption.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.success(b),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SizedBox(
                              height: 140,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  for (int i = 0; i < _recent.length; i++) ...<Widget>[
                                    Expanded(
                                      child: _DayBar(
                                        label: _dayLabel(_recent[i].key),
                                        minutes: _recent[i].value,
                                        maxMinutes: _maxMinutes,
                                        isToday: i == _recent.length - 1,
                                      ),
                                    ),
                                    if (i < _recent.length - 1)
                                      const SizedBox(width: AppSpacing.sm),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
    );
  }

  int get _maxMinutes {
    int max = 0;
    for (final MapEntry<String, int> e in _recent) {
      if (e.value > max) max = e.value;
    }
    return max == 0 ? 1 : max;
  }
}

/// عمود يوم واحد في الرسم.
class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.label,
    required this.minutes,
    required this.maxMinutes,
    required this.isToday,
  });

  final String label;
  final int minutes;
  final int maxMinutes;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final double ratio = (minutes / maxMinutes).clamp(0.0, 1.0);
    final Color color = isToday
        ? AppColors.success(b)
        : AppColors.primary(b).withValues(alpha: 0.45);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (minutes > 0)
          Text(
            '$minutes',
            textDirection: TextDirection.ltr,
            style: AppType.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary(b),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: 4 + 100 * ratio,
          decoration: BoxDecoration(
            color: minutes == 0
                ? AppColors.surfaceAlt(b)
                : color,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppType.caption.copyWith(
            fontSize: 9.5,
            color: isToday
                ? AppColors.text(b)
                : AppColors.textSecondary(b),
          ),
        ),
      ],
    );
  }
}
