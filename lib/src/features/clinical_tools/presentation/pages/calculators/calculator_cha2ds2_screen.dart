import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../domain/calculators_logic.dart';

class CalculatorCha2ds2Screen extends StatefulWidget {
  const CalculatorCha2ds2Screen({super.key});

  @override
  State<CalculatorCha2ds2Screen> createState() => _CalculatorCha2ds2ScreenState();
}

class _CalculatorCha2ds2ScreenState extends State<CalculatorCha2ds2Screen> {
  final Map<String, bool> _selections = <String, bool>{};
  int _score = 0;
  String _interpretation = '';

  @override
  void initState() {
    super.initState();
    for (final String key in CalculatorsLogic.cha2ds2VascCriteria.keys) {
      _selections[key] = false;
    }
    _calculate();
  }

  void _calculate() {
    setState(() {
      _score = CalculatorsLogic.calculateCha2ds2Vasc(_selections);
      _interpretation = CalculatorsLogic.interpretCha2ds2Vasc(_score);
    });
  }

  void _onChanged(String key, bool val) {
    setState(() {
      _selections[key] = val;
      // Mutually exclusive logic for Age
      if (key == 'Age ≥ 75 years' && val) {
        _selections['Age 65-74 years'] = false;
      }
      if (key == 'Age 65-74 years' && val) {
        _selections['Age ≥ 75 years'] = false;
      }
      _calculate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Scaffold(
      appBar: AppBar(title: const Text('CHA2DS2-VASc Score')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: CalculatorsLogic.cha2ds2VascCriteria.keys.map((String key) {
                return CheckboxListTile(
                  title: Text(
                    key,
                    style: AppType.body.copyWith(color: AppColors.text(b)),
                    textDirection: TextDirection.ltr,
                  ),
                  subtitle: Text(
                    '+${CalculatorsLogic.cha2ds2VascCriteria[key]} Points',
                    style: AppType.caption.copyWith(color: AppColors.primary(b)),
                    textDirection: TextDirection.ltr,
                  ),
                  value: _selections[key],
                  onChanged: (bool? val) {
                    _onChanged(key, val ?? false);
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
