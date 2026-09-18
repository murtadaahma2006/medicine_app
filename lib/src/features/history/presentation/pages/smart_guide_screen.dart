import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/ai_service.dart';

class SmartGuideScreen extends StatefulWidget {
  const SmartGuideScreen({super.key});

  @override
  State<SmartGuideScreen> createState() => _SmartGuideScreenState();
}

class _SmartGuideScreenState extends State<SmartGuideScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _isChecklistLoading = false;
  List<String> _suggestedChecklist = [];
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onComplaintChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _isChecklistLoading = false;
        _suggestedChecklist = [];
        _errorMessage = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 1500), () async {
      setState(() {
        _isChecklistLoading = true;
        _suggestedChecklist = [];
        _errorMessage = null;
      });

      try {
        final List<String> checklist = await AIService.generateHistoryChecklist(value);

        if (mounted) {
          setState(() {
            _suggestedChecklist = checklist;
            _isChecklistLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isChecklistLoading = false;
            _errorMessage = 'تعذر الاتصال بالمزود أو انقطع الاتصال بالإنترنت.\nيرجى التحقق من الشبكة والمحاولة مرة أخرى.';
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموجه الذكي'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'أدخل الشكوى الرئيسية للمريض، وسيقوم الموجه الذكي باقتراح أهم الأسئلة التي يجب طرحها (Red Flags).',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'الشكوى الرئيسية (Chief Complaint)',
                border: OutlineInputBorder(),
                isDense: true,
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              onChanged: _onComplaintChanged,
            ),
            if (_isChecklistLoading)
              const Padding(
                padding: EdgeInsets.only(top: 16.0, bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('يتم توليد الأسئلة الحرجة...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    SizedBox(height: 4),
                    LinearProgressIndicator(),
                  ],
                ),
              ),
            if (_errorMessage != null)
              Card(
                margin: const EdgeInsets.only(top: 24.0),
                elevation: 0,
                color: Theme.of(context).colorScheme.errorContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded, color: Theme.of(context).colorScheme.onErrorContainer, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_suggestedChecklist.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 24.0),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: [
                          Icon(Icons.lightbulb, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'أسئلة لا تنساها (Red Flags):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _suggestedChecklist.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              Expanded(
                                child: Text(
                                  _suggestedChecklist[index],
                                  style: const TextStyle(fontSize: 16, height: 1.5),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
