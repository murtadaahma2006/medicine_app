import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../domain/calculators_logic.dart';

class CalculatorChildPughScreen extends StatefulWidget {
  const CalculatorChildPughScreen({super.key});

  @override
  State<CalculatorChildPughScreen> createState() => _CalculatorChildPughScreenState();
}

class _CalculatorChildPughScreenState extends State<CalculatorChildPughScreen> {
  String _encephalopathy = 'None';
  String _ascites = 'None';
  
  final TextEditingController _biliCtrl = TextEditingController();
  final TextEditingController _albuminCtrl = TextEditingController();
  final TextEditingController _ptInrCtrl = TextEditingController();

  int _score = 0;
  String _interpretation = '';

  @override
  void dispose() {
    _biliCtrl.dispose();
    _albuminCtrl.dispose();
    _ptInrCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final double bili = double.tryParse(_biliCtrl.text) ?? 0;
    final double alb = double.tryParse(_albuminCtrl.text) ?? 0;
    final double inr = double.tryParse(_ptInrCtrl.text) ?? 0;

    if (bili > 0 && alb > 0 && inr > 0) {
      int s = 0;
      s += CalculatorsLogic.getChildPughPointsEncephalopathy(_encephalopathy);
      s += CalculatorsLogic.getChildPughPointsAscites(_ascites);
      s += CalculatorsLogic.getChildPughPointsBilirubin(bili);
      s += CalculatorsLogic.getChildPughPointsAlbumin(alb);
      s += CalculatorsLogic.getChildPughPointsPTINR(inr);

      setState(() {
        _score = s;
        _interpretation = CalculatorsLogic.interpretChildPugh(_score);
      });
    } else {
      setState(() {
        _score = 0;
        _interpretation = 'Enter valid lab values to calculate.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    return Scaffold(
      appBar: AppBar(title: const Text('Child-Pugh Score')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                DropdownButtonFormField<String>(
                  value: _encephalopathy,
                  decoration: const InputDecoration(labelText: 'Encephalopathy', border: OutlineInputBorder()),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'None', child: Text('None (1 pt)')),
                    DropdownMenuItem<String>(value: 'Grade 1-2', child: Text('Grade 1-2 (2 pts)')),
                    DropdownMenuItem<String>(value: 'Grade 3-4', child: Text('Grade 3-4 (3 pts)')),
                  ],
                  onChanged: (String? val) {
                    if (val != null) {
                      setState(() => _encephalopathy = val);
                      _calculate();
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _ascites,
                  decoration: const InputDecoration(labelText: 'Ascites', border: OutlineInputBorder()),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'None', child: Text('None (1 pt)')),
                    DropdownMenuItem<String>(value: 'Mild/Moderate (Diuretic-responsive)', child: Text('Mild/Moderate (2 pts)')),
                    DropdownMenuItem<String>(value: 'Severe (Diuretic-refractory)', child: Text('Severe (3 pts)')),
                  ],
                  onChanged: (String? val) {
                    if (val != null) {
                      setState(() => _ascites = val);
                      _calculate();
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _biliCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Total Bilirubin (mg/dL)', border: OutlineInputBorder()),
                  onChanged: (_) => _calculate(),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _albuminCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Albumin (g/dL)', border: OutlineInputBorder()),
                  onChanged: (_) => _calculate(),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _ptInrCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'PT INR', border: OutlineInputBorder()),
                  onChanged: (_) => _calculate(),
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
