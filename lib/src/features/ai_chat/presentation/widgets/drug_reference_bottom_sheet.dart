import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/tokens.dart';
import '../../../../core/services/fda_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// DrugReferenceBottomSheet — Premium OpenFDA drug reference panel.
///
/// Shows a searchable, color-coded drug label in a scrollable BottomSheet.
/// Entry point: [DrugReferenceBottomSheet.show(context)].
// ─────────────────────────────────────────────────────────────────────────────
class DrugReferenceBottomSheet extends StatefulWidget {
  const DrugReferenceBottomSheet._();

  /// Opens the drug reference panel from any [BuildContext].
  ///
  /// Usage (e.g., in AIChatPage AppBar):
  /// ```dart
  /// IconButton(
  ///   icon: const Icon(Icons.medical_information_rounded),
  ///   tooltip: 'مرجع الأدوية (FDA)',
  ///   onPressed: () => DrugReferenceBottomSheet.show(context),
  /// )
  /// ```
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DrugReferenceBottomSheet._(),
    );
  }

  @override
  State<DrugReferenceBottomSheet> createState() =>
      _DrugReferenceBottomSheetState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────
class _DrugReferenceBottomSheetState
    extends State<DrugReferenceBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  _ViewState _state = const _IdleState();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Search trigger ─────────────────────────────────────────────────────────

  Future<void> _search() async {
    final String query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    _searchFocus.unfocus();
    setState(() => _state = const _LoadingState());

    try {
      final DrugLabel label = await FdaService.search(query);
      if (!mounted) return;
      setState(() => _state = _ResultState(label));
    } on FdaNotFoundException {
      if (!mounted) return;
      setState(() => _state = const _ErrorState(
            message:
                'لم يتم العثور على الدواء.\nتأكد من الكتابة الإنجليزية الصحيحة.',
            icon: Icons.search_off_rounded,
          ));
    } on FdaServiceException catch (e) {
      if (!mounted) return;
      setState(() => _state = _ErrorState(
            message: e.message,
            icon: Icons.cloud_off_rounded,
          ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _ErrorState(
            message: 'خطأ غير متوقع: $e',
            icon: Icons.error_outline_rounded,
          ));
    }
  }

  void _clear() {
    _searchCtrl.clear();
    setState(() => _state = const _IdleState());
    _searchFocus.requestFocus();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Brightness b = scheme.brightness;
    final double sheetHeight = MediaQuery.of(context).size.height * 0.92;

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.5 : 0.15),
            blurRadius: 32,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          // ── Handle ──────────────────────────────────────────────────────
          const _SheetHandle(),

          // ── Header ──────────────────────────────────────────────────────
          _Header(scheme: scheme, b: b),

          // ── Search bar ──────────────────────────────────────────────────
          _SearchBar(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            scheme: scheme,
            b: b,
            onSearch: _search,
            onClear: _clear,
          ),

          const SizedBox(height: 8),

          // ── Content ─────────────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _buildBody(scheme, b),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme, Brightness b) {
    final _ViewState s = _state;
    return switch (s) {
      _IdleState() => _IdleView(scheme: scheme, b: b),
      _LoadingState() => const _LoadingView(),
      _ErrorState(message: final String msg, icon: final IconData ico) =>
        _ErrorView(message: msg, icon: ico, scheme: scheme, b: b),
      _ResultState(label: final DrugLabel label) =>
        _ResultView(label: label, scheme: scheme, b: b),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sealed view-state hierarchy
// ─────────────────────────────────────────────────────────────────────────────
sealed class _ViewState {
  const _ViewState();
}

final class _IdleState extends _ViewState {
  const _IdleState();
}

final class _LoadingState extends _ViewState {
  const _LoadingState();
}

final class _ErrorState extends _ViewState {
  const _ErrorState({required this.message, required this.icon});
  final String message;
  final IconData icon;
}

final class _ResultState extends _ViewState {
  const _ResultState(this.label);
  final DrugLabel label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scheme, required this.b});
  final ColorScheme scheme;
  final Brightness b;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.medication_rounded,
              color: scheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'مرجع الأدوية',
                  style: AppType.cardTitle.copyWith(
                    color: AppColors.text(b),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'مدعوم بقاعدة بيانات FDA الرسمية',
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ],
            ),
          ),
          // FDA badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.successContainerLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.verified_rounded,
                    size: 12, color: AppColors.successLight),
                const SizedBox(width: 4),
                Text(
                  'FDA',
                  style: AppType.caption.copyWith(
                    color: AppColors.successLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.scheme,
    required this.b,
    required this.onSearch,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ColorScheme scheme;
  final Brightness b;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt(b),
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: AppColors.border(b)),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 14),
            Icon(Icons.search_rounded,
                color: AppColors.primary(b), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                style: AppType.body.copyWith(
                  color: AppColors.text(b),
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم الإنجليزي (e.g., Metformin)',
                  hintStyle: AppType.body.copyWith(
                    color: AppColors.textSecondary(b),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            // Clear button
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, TextEditingValue v, __) => v.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 18,
                          color: AppColors.textSecondary(b)),
                      onPressed: onClear,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
            ),
            // Search button
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton(
                onPressed: onSearch,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('بحث',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Body states ──────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  const _IdleView({required this.scheme, required this.b});
  final ColorScheme scheme;
  final Brightness b;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.medication_liquid_rounded,
                  size: 52, color: scheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'ابحث عن أي دواء',
              style: AppType.cardTitle.copyWith(
                  color: AppColors.text(b), fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              'أدخل الاسم الجنيسي أو التجاري بالإنجليزية\nللحصول على بيانة الأمان الرسمية من FDA.',
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(
                  color: AppColors.textSecondary(b), height: 1.6),
            ),
            const SizedBox(height: 24),
            // Quick examples
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: const <String>[
                'Metformin', 'Warfarin', 'Amoxicillin',
                'Lisinopril', 'Omeprazole',
              ]
                  .map((String name) => _ExampleChip(name: name))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return InkWell(
      onTap: () {
        // Bubble up through context to fill the search field.
        final _DrugReferenceBottomSheetState? state = context
            .findAncestorStateOfType<_DrugReferenceBottomSheetState>();
        if (state == null) return;
        state._searchCtrl.text = name;
        state._search();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border(b)),
          borderRadius: BorderRadius.circular(20),
          color: AppColors.surfaceAlt(b),
        ),
        child: Text(name,
            style: AppType.caption.copyWith(
                color: AppColors.primary(b),
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'جاري الاستعلام من قاعدة بيانات FDA...',
            style: AppType.body.copyWith(
              color: AppColors.textSecondary(
                  Theme.of(context).colorScheme.brightness),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.icon,
    required this.scheme,
    required this.b,
  });
  final String message;
  final IconData icon;
  final ColorScheme scheme;
  final Brightness b;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(
                color: AppColors.textSecondary(b),
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result View — the main clinical display
// ─────────────────────────────────────────────────────────────────────────────
class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.label,
    required this.scheme,
    required this.b,
  });

  final DrugLabel label;
  final ColorScheme scheme;
  final Brightness b;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: <Widget>[
        // ── Drug identity card ────────────────────────────────────────────
        _IdentityCard(label: label, scheme: scheme, b: b),
        const SizedBox(height: 12),

        // ── 🔴 Boxed Warning (shown first — highest priority) ─────────────
        if (label.hasBoxedWarning) ...<Widget>[
          _ClinicalSection(
            icon: Icons.warning_rounded,
            title: 'تحذير مُعلَّب (Boxed Warning)',
            content: label.boxedWarning,
            accentColor: AppColors.error(b),
            containerColor: b == Brightness.dark
                ? AppColors.errorContainerDark
                : AppColors.errorContainerLight,
            initiallyExpanded: true,
            isCritical: true,
          ),
          const SizedBox(height: 10),
        ],

        // ── 🔵 Indications ────────────────────────────────────────────────
        _ClinicalSection(
          icon: Icons.check_circle_outline_rounded,
          title: 'دواعي الاستخدام (Indications)',
          content: label.indicationsAndUsage,
          accentColor: AppColors.primary(b),
          containerColor: b == Brightness.dark
              ? AppColors.primaryTintDark
              : AppColors.primaryTintLight,
        ),
        const SizedBox(height: 10),

        // ── 🔵 Dosage ─────────────────────────────────────────────────────
        _ClinicalSection(
          icon: Icons.medication_rounded,
          title: 'الجرعة والإعطاء (Dosage & Administration)',
          content: label.dosageAndAdministration,
          accentColor: AppColors.primary(b),
          containerColor: b == Brightness.dark
              ? AppColors.primaryTintDark
              : AppColors.primaryTintLight,
        ),
        const SizedBox(height: 10),

        // ── 🔴 Contraindications ──────────────────────────────────────────
        _ClinicalSection(
          icon: Icons.block_rounded,
          title: 'موانع الاستخدام (Contraindications)',
          content: label.contraindications,
          accentColor: AppColors.error(b),
          containerColor: b == Brightness.dark
              ? AppColors.errorContainerDark
              : AppColors.errorContainerLight,
        ),
        const SizedBox(height: 10),

        // ── 🟡 Drug Interactions ──────────────────────────────────────────
        _ClinicalSection(
          icon: Icons.compare_arrows_rounded,
          title: 'التفاعلات الدوائية (Drug Interactions)',
          content: label.drugInteractions,
          accentColor: AppColors.gold(b),
          containerColor: b == Brightness.dark
              ? const Color(0xFF3A3019)
              : const Color(0xFFFFF8E7),
        ),

        const SizedBox(height: 8),
        _FdaDisclaimer(b: b),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.label,
    required this.scheme,
    required this.b,
  });
  final DrugLabel label;
  final ColorScheme scheme;
  final Brightness b;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Brand name (large)
          Text(
            label.brandName,
            style: AppType.screenTitle.copyWith(
              color: AppColors.primary(b),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (label.genericName != label.brandName &&
              label.genericName != FdaService.notAvailable) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              label.genericName,
              style: AppType.body.copyWith(
                color: AppColors.textSecondary(b),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Divider(color: AppColors.border(b), height: 1),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(Icons.business_rounded,
                  size: 14, color: AppColors.textSecondary(b)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.manufacturer,
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary(b),
                  ),
                ),
              ),
              // Copy button
              InkWell(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: label.genericName),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('تم نسخ الاسم الجنيسي'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded,
                      size: 14,
                      color: AppColors.textSecondary(b)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClinicalSection extends StatelessWidget {
  const _ClinicalSection({
    required this.icon,
    required this.title,
    required this.content,
    required this.accentColor,
    required this.containerColor,
    this.initiallyExpanded = false,
    this.isCritical = false,
  });

  final IconData icon;
  final String title;
  final String content;
  final Color accentColor;
  final Color containerColor;
  final bool initiallyExpanded;
  final bool isCritical;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final bool isNotAvailable = content == FdaService.notAvailable;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Theme(
        // Override ExpansionTile divider color to be invisible.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          backgroundColor: containerColor,
          collapsedBackgroundColor: containerColor,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          title: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: AppType.body.copyWith(
                    color: AppColors.text(b),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isCritical)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'تحذير',
                    style: AppType.caption.copyWith(
                        color: accentColor, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          children: <Widget>[
            if (isNotAvailable)
              Text(
                'لا توجد بيانات في قاعدة FDA لهذا القسم.',
                style: AppType.body.copyWith(
                  color: AppColors.textSecondary(b),
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              )
            else
              SelectableText(
                content,
                style: AppType.body.copyWith(
                  color: AppColors.text(b),
                  height: 1.65,
                  fontSize: 13.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FdaDisclaimer extends StatelessWidget {
  const _FdaDisclaimer({required this.b});
  final Brightness b;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded,
              size: 14, color: AppColors.textSecondary(b)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'البيانات مصدرها OpenFDA الرسمي. لا تعتمد عليها منفردةً '
              'في القرار السريري — راجع دائماً المرجع الدوائي المؤسسي.',
              style: AppType.caption.copyWith(
                color: AppColors.textSecondary(b),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
