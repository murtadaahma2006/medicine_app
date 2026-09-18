import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../domain/calculators_logic.dart';

class CalculatorCrClScreen extends StatefulWidget {
  const CalculatorCrClScreen({super.key});

  @override
  State<CalculatorCrClScreen> createState() => _CalculatorCrClScreenState();
}

class _CalculatorCrClScreenState extends State<CalculatorCrClScreen> {
  final TextEditingController _ageCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _crCtrl = TextEditingController();
  bool _isFemale = false;
  
  double _crCl = 0.0;
  String _interpretation = '';

  @override
  void dispose() {
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _crCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final double age = double.tryParse(_ageCtrl.text) ?? 0;
    final double weight = double.tryParse(_weightCtrl.text) ?? 0;
    final double cr = double.tryParse(_crCtrl.text) ?? 0;

    setState(() {
      if (age > 0 && weight > 0 && cr > 0) {
        _crCl = CalculatorsLogic.calculateCrCl(
          age: age,
          weight: weight,
          serumCr: cr,
          isFemale: _isFemale,
        );
        _interpretation = CalculatorsLogic.interpretCrCl(_crCl);
      } else {
        _crCl = 0.0;
        _interpretation = 'Please enter valid values.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Scaffold(
      appBar: AppBar(title: const Text('Creatinine Clearance')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                TextFormField(
                  controller: _ageCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Age (years)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _calculate(),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _calculate(),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _crCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Serum Creatinine (mg/dL)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _calculate(),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  title: const Text('Female Patient'),
                  value: _isFemale,
                  onChanged: (bool val) {
                    setState(() {
                      _isFemale = val;
                      _calculate();
                    });
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: AppShadows.card(b),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: <Widget>[
                  Text(
                    'CrCl: ${_crCl.toStringAsFixed(1)} mL/min',
                    style: AppType.screenTitle.copyWith(color: AppColors.primary(b)),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _interpretation,
                    style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
