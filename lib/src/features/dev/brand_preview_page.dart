import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/widgets.dart';
import '../../theme/tokens.dart';

/// صفحة معاينة تفاعلية لمفاهيم الهوية البصرية (تظهر فقط في وضع التطوير kDebugMode).
class BrandPreviewPage extends StatefulWidget {
  const BrandPreviewPage({super.key});

  @override
  State<BrandPreviewPage> createState() => _BrandPreviewPageState();
}

class _BrandPreviewPageState extends State<BrandPreviewPage> {
  int _selectedConceptIndex = 0;
  List<String> _logos = <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  Future<void> _loadManifest() async {
    try {
      final String manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
      
      final List<String> logos = manifestMap.keys
          .where((String path) => path.startsWith('assets/brand/logo/'))
          .toList();
          
      setState(() {
        _logos = logos;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      debugPrint('Error loading AssetManifest: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('صفحة للمعاينة في وضع التطوير فقط.')),
      );
    }

    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'معاينة الهوية البصرية والشعارات',
          style: TextStyle(fontFamily: AppType.arabicFamily, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logos.isEmpty
              ? const EmptyState(
                  icon: Icons.image_not_supported_outlined,
                  title: 'لا يوجد شعارات',
                  subtitle: 'قم بإسقاط ملفات الصور في assets/brand/logo/ وأعد بناء التطبيق',
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'اختر المفهوم لاستعراض الشعار بأحجام مختلفة:',
                        style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List<Widget>.generate(_logos.length, (int index) {
                            final bool isSelected = _selectedConceptIndex == index;
                            final String filename = _logos[index].split('/').last;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isSelected
                                      ? AppColors.primary(b).withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  side: BorderSide(
                                    color: isSelected
                                        ? AppColors.primary(b)
                                        : AppColors.border(b),
                                    width: isSelected ? 2 : 1,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.sm, horizontal: AppSpacing.md),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.card),
                                  ),
                                ),
                                onPressed: () => setState(() => _selectedConceptIndex = index),
                                child: Text(
                                  filename,
                                  style: TextStyle(
                                    fontFamily: AppType.arabicFamily,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isSelected
                                        ? AppColors.primary(b)
                                        : AppColors.textSecondary(b),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // --- بطاقة المعاينة الرئيسية ---
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: AppColors.surface(b),
                          borderRadius: BorderRadius.circular(AppRadius.sheet),
                          border: Border.all(color: AppColors.border(b)),
                          boxShadow: AppShadows.card(b),
                        ),
                        child: Column(
                          children: <Widget>[
                            Text(
                              _logos[_selectedConceptIndex].split('/').last,
                              style: AppType.cardTitle.copyWith(color: AppColors.text(b)),
                            ),
                            const SizedBox(height: AppSpacing.xl),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: <Widget>[
                                // شعار كبير
                                Column(
                                  children: <Widget>[
                                    Image.asset(
                                      _logos[_selectedConceptIndex],
                                      width: 192,
                                      height: 192,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text('حجم كبير (192px)', style: AppType.caption),
                                  ],
                                ),
                                // متوسط
                                Column(
                                  children: <Widget>[
                                    Image.asset(
                                      _logos[_selectedConceptIndex],
                                      width: 96,
                                      height: 96,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text('متوسط (96px)', style: AppType.caption),
                                  ],
                                ),
                                // صغير
                                Column(
                                  children: <Widget>[
                                    Image.asset(
                                      _logos[_selectedConceptIndex],
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text('صغير (48px)', style: AppType.caption),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),

                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary(b),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'اللوغو المختار هو: ${_logos[_selectedConceptIndex].split('/').last}\nيرجى نسخه إلى مجلد assets/brand/final/logo_mark.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text(
                          'اعتماد هذا الشعار',
                          style: TextStyle(
                              fontFamily: AppType.arabicFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
