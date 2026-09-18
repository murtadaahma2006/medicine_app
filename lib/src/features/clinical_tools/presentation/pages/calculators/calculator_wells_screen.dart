import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../domain/calculators_logic.dart';

class CalculatorWellsScreen extends StatefulWidget {
  const CalculatorWellsScreen({super.key});

  @override
  State<CalculatorWellsScreen> createState() => _CalculatorWellsScreenState();
}

class _CalculatorWellsScreenState extends State<CalculatorWellsScreen> {
  final Map<String, bool> _selections = <String, bool>{};
  double _score = 0.0;
  String _interpretation = '';

  @override
  void initState() {
    super.initState();
    for (final String key in CalculatorsLogic.wellsPeCriteria.keys) {
      _selections[key] = false;
    }
    _calculate();
  }

  void _calculate() {
    setState(() {
      _score = CalculatorsLogic.calculateWellsPe(_selections);
      _interpretation = CalculatorsLogic.interpretWellsPe(_score);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Scaffold(
      appBar: AppBar(title: const Text('Wells Score (PE)')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: CalculatorsLogic.wellsPeCriteria.keys.map((String key) {
                return CheckboxListTile(
                  title: Text(
                    key,
                    style: AppType.body.copyWith(color: AppColors.text(b)),
                    textDirection: TextDirection.ltr,
                  ),
                  subtitle: Text(
                    '+${CalculatorsLogic.wellsPeCriteria[key]} Points',
                    style: AppType.caption.copyWith(color: AppColors.primary(b)),
                    textDirection: TextDirection.ltr,
                  ),
                  value: _selections[key],
                  onChanged: (bool? val) {
                    _selections[key] = val ?? false;
                    _calculate();
                  },
                );
              }).toList(),
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
                    'Score: $_score',
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
