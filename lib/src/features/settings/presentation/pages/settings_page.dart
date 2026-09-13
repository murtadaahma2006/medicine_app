import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app.dart';
import '../../../../core/profile/learner_profile.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import 'backup_page.dart';
import 'fixation_settings.dart';
import 'lecture_import_page.dart';
import 'reminder_page.dart';

/// شاشة الإعدادات — مبنية بالكامل من مكتبة المكونات المشتركة
/// (SectionHeader · AppCard · AppButton · EmptyState) وtokens التصميم.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  String? _error;

  String _themeMode = 'system';
  int _dailyGoal = 10;

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
      final String theme = await LearnerProfile.themeMode();
      final int goal = await LearnerProfile.dailyGoal();
      if (!mounted) return;
      setState(() {
        _themeMode = theme;
        _dailyGoal = goal;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الإعدادات.';
        _loading = false;
      });
    }
  }

  Future<void> _changeTheme(String mode) async {
    final LearnerTheme? channel = LearnerTheme.of(context);
    setState(() => _themeMode = mode);
    await LearnerProfile.setThemeMode(mode);
    channel?.notifier();
  }

  Future<void> _changeGoal(int goal) async {
    setState(() => _dailyGoal = goal);
    await LearnerProfile.setDailyGoal(goal);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: EmptyState(
          icon: Icons.error_outline_rounded,
          title: _error!,
          actionLabel: 'إعادة المحاولة',
          onAction: _load,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      children: <Widget>[
        // ── قسم المظهر ──
        const SectionHeader('المظهر'),
        AppCard(
          child: Row(
            children: <Widget>[
              for (final String mode in const <String>['light', 'dark', 'system'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: _ThemeOption(
                      mode: mode,
                      selected: _themeMode == mode,
                      onTap: () => _changeTheme(mode),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xxl),

        // ── قسم الهدف اليومي ──
        const SectionHeader('الهدف اليومي'),
        AppCard(
          child: Row(
            children: <Widget>[
              for (final int goal in const <int>[5, 10, 15, 20])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: _GoalOption(
                      value: goal,
                      selected: _dailyGoal == goal,
                      onTap: () => _changeGoal(goal),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            'عدد البطاقات المستحقة يومياً في «مراجعة اليوم»',
            style: AppType.caption.copyWith(color: AppColors.textSecondary(Theme.of(context).colorScheme.brightness)),
          ),
        ),

        const SizedBox(height: AppSpacing.xxl),

        // ── قسم القراءة العميقة ──
        const SectionHeader('القراءة العميقة'),
        _NavTile(
          icon: Icons.center_focus_strong_rounded,
          title: 'مراسي التثبيت والتايبوغرافيا',
          subtitle: 'تسريع قراءة الشروحات الطويلة — قوة المرساة والمعاينة',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
            builder: (_) => const FixationSettingsPage(),
          )),
        ),

        const SizedBox(height: AppSpacing.xxl),

        // ── قسم التذكير ──
        const SectionHeader('التذكير اليومي'),
        _NavTile(
          icon: Icons.alarm_rounded,
          title: 'وقت التذكير اليومي',
          subtitle: 'تذكير محلي على هذا الجهاز — بلا إنترنت',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
            builder: (_) => const ReminderPage(),
          )),
        ),

        const SizedBox(height: AppSpacing.xxl),

        // ── قسم المحتوى ──
        const SectionHeader('المحتوى'),
        _NavTile(
          icon: Icons.download_rounded,
          title: 'استيراد محاضرة',
          subtitle: 'إضافة محاضرة جديدة من ملف JSON على الجهاز',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
            builder: (_) => const LectureImportPage(),
          )),
        ),

        const SizedBox(height: AppSpacing.xxl),

        // ── قسم النسخ الاحتياطي ──
        const SectionHeader('نسخة احتياطية'),
        _NavTile(
          icon: Icons.backup_rounded,
          title: 'نسخة احتياطية / استعادة',
          subtitle: 'تصدير تقدمك كملف قابل للمشاركة واستعادته',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<Widget>(
            builder: (_) => const BackupPage(),
          )),
        ),

        const SizedBox(height: AppSpacing.xxxl),

        // ── سطر التطبيق ──
        Center(
          child: Text(
            'منصة الطب الباطني · نسخة 1.0.0 · أوفلاين 100%',
            style: AppType.caption.copyWith(
                color: AppColors.textSecondary(Theme.of(context).colorScheme.brightness)),
          ),
        ),

        // ── أدوات التطوير (debug فقط) ──
        if (kDebugMode) ...<Widget>[
          const SizedBox(height: AppSpacing.xxl),
          _NavTile(
            icon: Icons.palette_rounded,
            title: 'معاينة الهوية البصرية واللوغو [dev]',
            subtitle: 'استعراض المفاهيم والشعارات والتغذية الراجعة',
            onTap: () => context.push(RoutePaths.devBrandPreview),
          ),
          const SizedBox(height: AppSpacing.md),
          _NavTile(
            icon: Icons.style_rounded,
            title: 'دليل الهوية ونظام التصميم [dev]',
            subtitle: 'معاينة الرسوم التوضيحية والرموز والخطوط',
            onTap: () => context.push(RoutePaths.devStylePreview),
          ),
          const SizedBox(height: AppSpacing.md),
          _NavTile(
            icon: Icons.bug_report_rounded,
            title: 'سجل الأخطاء [dev]',
            subtitle: 'الأخطاء العابرة والتفاصيل الكاملة',
            onTap: () => context.push(RoutePaths.devErrorLog),
          ),
        ],
      ],
    );
  }
}

/// صف انتقال — بطاقة قابلة للنقر بأيقونة وchevron.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return AppCard(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryTint(b),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(icon,
                size: 22, color: AppColors.primary(b), semanticLabel: title),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: AppType.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppType.body.copyWith(
                      fontSize: 12.5, color: AppColors.textSecondary(b)),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded,
              color: AppColors.textSecondary(b)),
        ],
      ),
    );
  }
}

/// خيار وضع مظهر واحد (فاتح/داكن/تلقائي).
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final String mode;
  final bool selected;
  final VoidCallback onTap;

  String get _label => switch (mode) {
        'light' => 'فاتح',
        'dark' => 'داكن',
        _ => 'تلقائي',
      };

  IconData get _icon => switch (mode) {
        'light' => Icons.light_mode_rounded,
        'dark' => Icons.dark_mode_rounded,
        _ => Icons.brightness_auto_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;
    final Color primary = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: 'المظهر: $_label',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.scaled(context, AppMotion.feedback),
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primaryTint(b) : AppColors.surfaceAlt(b),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? primary : AppColors.border(b),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_icon,
                  size: 22,
                  color: selected ? primary : AppColors.textSecondary(b)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _label,
                style: AppType.caption.copyWith(
                  color: selected ? primary : AppColors.textSecondary(b),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// خيار هدف يومي واحد (5/10/15/20).
class _GoalOption extends StatelessWidget {
  const _GoalOption({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness b = theme.colorScheme.brightness;
    final Color primary = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: 'الهدف اليومي: $value بطاقة',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.scaled(context, AppMotion.feedback),
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primaryTint(b) : AppColors.surfaceAlt(b),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? primary : AppColors.border(b),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            '$value',
            textDirection: TextDirection.ltr,
            style: AppType.cardTitle.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: selected ? primary : AppColors.textSecondary(b),
            ),
          ),
        ),
      ),
    );
  }
}
