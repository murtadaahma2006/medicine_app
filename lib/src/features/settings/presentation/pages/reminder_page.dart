import 'package:flutter/material.dart';

import '../../../../core/notifications/daily_reminder_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

/// شاشة التذكير اليومي — تفعيل محلي بالكامل (بلا إنترنت).
///
/// الحالة تُقرأ من [DailyReminderService] مرة واحدة ثم تُحدَّث محلياً؛
/// الخدمة نفسها لا ترمي استثناءات فلا نحتاج معالجة أخطاء هنا.
/// مُرحّلة لهوية نظام التصميم (المرحلة 7): AppCard + tokens.
class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key});

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  bool _loading = true;
  bool _enabled = false;

  /// ساعة التذكير المفضلة (24h) — من الخدمة أو آخر قيمة محلية.
  int _hour = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool enabled = await DailyReminderService.isEnabled();
    final int hour = await DailyReminderService.scheduledHour();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _hour = hour;
      _loading = false;
    });
  }

  /// يبدّل التفعيل — عند التفعيل يعيد الجدولة بالساعة الحالية.
  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await DailyReminderService.setEnabled(enabled: value, hour: _hour);
  }

  /// يغيّر الساعة — الجدولة تعاد داخل الخدمة فقط إذا كان مفعّلاً.
  Future<void> _changeHour(double value) async {
    final int hour = value.round();
    setState(() => _hour = hour);
    await DailyReminderService.setHour(hour);
  }

  /// تنسيق الساعة بصيغة عربية تقريبية: «٨:٠٠ مساءً».
  static String formatHourArabic(int hour) {
    const List<String> arabicDigits = <String>[
      '٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩',
    ];
    String toArabicDigits(int n) =>
        n.toString().split('').map((String d) => arabicDigits[int.parse(d)]).join();

    final bool isPm = hour >= 12;
    final int display = hour % 12 == 0 ? 12 : hour % 12;
    return '${toArabicDigits(display)}:٠٠ ${isPm ? 'مساءً' : 'صباحاً'}';
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('التذكير اليومي')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('التذكير اليومي')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          // --- بطاقة التفعيل ---
          AppCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _enabled
                        ? AppColors.gold(b).withValues(
                            alpha: b == Brightness.dark ? 1 : 0.16)
                        : AppColors.surfaceAlt(b),
                    borderRadius: BorderRadius.circular(AppRadius.chip + 2),
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: _enabled
                        ? AppColors.goldText(b)
                        : AppColors.textSecondary(b),
                  ),
                ),
                const SizedBox(width: AppSpacing.md + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('تذكيري اليومي',
                          style: AppType.cardTitle
                              .copyWith(color: AppColors.text(b))),
                      Text(
                        _enabled
                            ? 'مفعّل — ${formatHourArabic(_hour)}'
                            : 'معطّل',
                        style: AppType.body
                            .copyWith(color: AppColors.textSecondary(b)),
                      ),
                    ],
                  ),
                ),
                Switch(value: _enabled, onChanged: _toggle),
              ],
            ),
          ),

          // --- منتقي الساعة (يظهر عند التفعيل فقط) ---
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppMotion.standard,
            curve: AppMotion.ease,
            child: _enabled
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.schedule_rounded,
                                  color: AppColors.primary(b), size: 22),
                              const SizedBox(width: AppSpacing.sm + 2),
                              Text('وقت التذكير',
                                  style: AppType.cardTitle
                                      .copyWith(color: AppColors.text(b))),
                              const Spacer(),
                              Text(
                                formatHourArabic(_hour),
                                style: AppType.cardTitle.copyWith(
                                  color: AppColors.primary(b),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _hour.toDouble(),
                            min: 5,
                            max: 23,
                            divisions: 18,
                            label: formatHourArabic(_hour),
                            onChanged: _changeHour,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text('٥ صباحاً',
                                    style: AppType.caption.copyWith(
                                        color: AppColors.textSecondary(b))),
                                Text('١١ مساءً',
                                    style: AppType.caption.copyWith(
                                        color: AppColors.textSecondary(b))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: AppSpacing.lg),

          // --- سطر الشرح ---
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.wifi_off_rounded,
                  size: 16, color: AppColors.textSecondary(b)),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                'تذكير محلي على هذا الجهاز — لا إنترنت مطلوب.',
                style: AppType.body
                    .copyWith(color: AppColors.textSecondary(b)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
