import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';
import 'calculators/calculator_cha2ds2_screen.dart';
import 'calculators/calculator_child_pugh_screen.dart';
import 'calculators/calculator_crcl_screen.dart';
import 'calculators/calculator_wells_screen.dart';

class MedicalCalculatorsScreen extends StatelessWidget {
  const MedicalCalculatorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حاسبات طبية (Medical Calculators)')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          _CalculatorTile(
            title: 'Wells Score for PE',
            subtitle: 'Clinical prediction rule for pulmonary embolism',
            icon: Icons.monitor_heart_rounded,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute<Widget>(
                builder: (_) => const CalculatorWellsScreen(),
              ));
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _CalculatorTile(
            title: 'CHA2DS2-VASc Score',
            subtitle: 'Stroke risk in atrial fibrillation',
            icon: Icons.favorite_rounded,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute<Widget>(
                builder: (_) => const CalculatorCha2ds2Screen(),
              ));
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _CalculatorTile(
            title: 'Creatinine Clearance (Cockcroft-Gault)',
            subtitle: 'Estimates GFR from serum creatinine',
            icon: Icons.water_drop_rounded,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute<Widget>(
                builder: (_) => const CalculatorCrClScreen(),
              ));
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _CalculatorTile(
            title: 'Child-Pugh Score',
            subtitle: 'Cirrhosis mortality risk assessment',
            icon: Icons.local_drink_rounded,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute<Widget>(
                builder: (_) => const CalculatorChildPughScreen(),
              ));
            },
          ),
        ],
      ),
    );
  }
}

class _CalculatorTile extends StatelessWidget {
  const _CalculatorTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card(b),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppType.body.copyWith(
                        fontSize: 13, color: AppColors.textSecondary(b)),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary(b)),
          ],
        ),
      ),
    );
  }
}
