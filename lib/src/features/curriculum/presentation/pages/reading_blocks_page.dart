import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';
import '../../../curriculum/presentation/pages/concept_reader_page.dart';

/// ─────────────────────────────────────────────────────────────────────
/// كتل القراءة العميقة (المقترح D — أسبوع 3).
///
/// | الكتلة | المحتوى | المدة |
/// |---|---|---|
/// | غوصة عميقة | 3–4 شروح متسلسلة (بوابة → لقطات → اعتراضيات → تثبيت) | ~25 د |
/// | كتلة معيارية | شرح–شرحان | ~10 د |
///
/// **التداخل على مستوى الشروح**: الغوصة تخلط شروحاً من جهازين
/// (system موجود في القاعدة) — «اقرأ شرح قلب ثم شرح كلى» — بناء
/// الـ Schema التشخيصي التفريقي (Bjork: صعوبة مرغوبة بأرخص تنفيذ:
/// ترتيب قائمة). الشروح تُختار من غير المكتمل قراءتها أولاً —
/// جلستك دائماً «إكمال» لا «بداية» (Ovsiankina).
/// ─────────────────────────────────────────────────────────────────────
class DeepReadingBlock {
  const DeepReadingBlock({
    required this.id,
    required this.titleAr,
    required this.subtitleAr,
    required this.emoji,
    required this.conceptCount,
    required this.unitIds,
    required this.estimatedMinutes,
  });

  final String id;
  final String titleAr;
  final String subtitleAr;
  final String emoji;
  final int conceptCount;
  final List<String> unitIds;
  final int estimatedMinutes;
}

/// يبني كتلتَي القراءة العميقة من الشروح غير المكتملة.
///
/// [concepts]: صفوف getUnfinishedConcepts (مع unit_id/unit_title/
/// unit_system). إن خلت القاعدة من شروح غير مكتملة → غوصة من أول
/// شروح المحتوى (إعادة فتح = مراجعة بنية).
Future<List<DeepReadingBlock>> buildReadingBlocks(
  DatabaseHelper db,
) async {
  List<Map<String, Object?>> concepts =
      await db.getUnfinishedConcepts(limit: 6);

  // لا غير مكتمل؟ → كل الشروح (وضع مراجعة البنية).
  if (concepts.isEmpty) {
    concepts = await db.rawQueryParameterized('''
      SELECT c.*, u.title AS unit_title, u.system AS unit_system
      FROM ${DatabaseHelper.tableConcepts} c
      INNER JOIN ${DatabaseHelper.tableUnits} u ON u.id = c.unit_id
      ORDER BY RANDOM()
      LIMIT 6
    ''');
  }
  // نسخة قابلة للتعديل — نتيجة sqflite للقراءة فقط.
  concepts = List<Map<String, Object?>>.of(concepts);

  if (concepts.isEmpty) return const <DeepReadingBlock>[];

  // غوصة: 3–4 شروح بتداخل أجهزة (تناوب الأجهزة قدر الإمكان).
  final List<Map<String, Object?>> dive = _interleaveBySystem(concepts, 4);
  // معيارية: شرح–شرحان مما تبقى (أو من الغوصة إن قلّت).
  final List<Map<String, Object?>> remaining = concepts
      .where((Map<String, Object?> c) => !dive.contains(c))
      .toList();
  final List<Map<String, Object?>> standard = remaining.take(2).toList();

  final Set<String> diveSystems = <String>{
    for (final Map<String, Object?> c in dive)
      (c['unit_system'] as String?) ?? '',
  };

  return <DeepReadingBlock>[
    DeepReadingBlock(
      id: 'dive',
      titleAr: 'غوصة عميقة',
      subtitleAr: diveSystems.length > 1
          ? '${dive.length} شروح متداخلة الأجهزة — ${diveSystems.length} أجهزة'
          : '${dive.length} شروح متسلسلة',
      emoji: '🌊',
      conceptCount: dive.length,
      unitIds: <String>[
        for (final Map<String, Object?> c in dive)
          c['unit_id']! as String,
      ],
      estimatedMinutes: dive.length * 6,
    ),
    if (standard.isNotEmpty)
      DeepReadingBlock(
        id: 'standard',
        titleAr: 'كتلة معيارية',
        subtitleAr: '${standard.length} ${standard.length == 1 ? 'شرح' : 'شروح'} سريعة',
        emoji: '📖',
        conceptCount: standard.length,
        unitIds: <String>[
          for (final Map<String, Object?> c in standard)
            c['unit_id']! as String,
        ],
        estimatedMinutes: standard.length * 6,
      ),
  ];
}

/// تناوب الأجهزة: يرتب الشروح بحيث لا يتكرر الجهاز متتالياً إن أمكن —
/// التدريب التمييزي «أي جهاز أفكر فيه أولاً» (جوهر التشخيص السريري).
List<Map<String, Object?>> _interleaveBySystem(
  List<Map<String, Object?>> concepts,
  int limit,
) {
  // تجميع حسب الجهاز.
  final Map<String, List<Map<String, Object?>>> bySystem =
      <String, List<Map<String, Object?>>>{};
  for (final Map<String, Object?> c in concepts) {
    final String system = (c['unit_system'] as String?) ?? 'other';
    bySystem.putIfAbsent(system, () => <Map<String, Object?>>[]).add(c);
  }

  // دمج متناوب: جهاز مختلف كل مرة.
  final List<Map<String, Object?>> out = <Map<String, Object?>>[];
  final List<List<Map<String, Object?>>> pools =
      bySystem.values.toList()..shuffle();
  while (out.length < limit) {
    bool tookAny = false;
    for (final List<Map<String, Object?>> pool in pools) {
      if (pool.isEmpty || out.length >= limit) continue;
      // لا تكرار نفس الجهاز متتالياً (إن أمكن).
      if (out.isNotEmpty) {
        final String lastSystem =
            (out.last['unit_system'] as String?) ?? 'other';
        final String thisSystem = (pool.first['unit_system'] as String?) ?? 'other';
        if (thisSystem == lastSystem && pools.any((p) => p.isNotEmpty && (p.first['unit_system'] as String?) != lastSystem)) {
          continue;
        }
      }
      out.add(pool.removeAt(0));
      tookAny = true;
    }
    if (!tookAny) break;
  }
  return out;
}

/// ─────────────────────────────────────────────────────────────────────
/// شاشة كتل القراءة — «اختر جرعتك القرائية».
///
/// تفتح من شاشة اليوم. كل كتلة تفتح ConceptReaderPage لأول محاضرة
/// فيها (القارئ يغطي محاضرة كاملة). الغرض الأولي: كسر جدار البدء —
/// «أصغر وحدة تُقاوَم نفسياً».
/// ─────────────────────────────────────────────────────────────────────
class ReadingBlocksPage extends StatefulWidget {
  const ReadingBlocksPage({super.key});

  @override
  State<ReadingBlocksPage> createState() => _ReadingBlocksPageState();
}

class _ReadingBlocksPageState extends State<ReadingBlocksPage> {
  bool _loading = true;
  String? _error;
  List<DeepReadingBlock> _blocks = const <DeepReadingBlock>[];

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
      final List<DeepReadingBlock> blocks =
          await buildReadingBlocks(DatabaseHelper.instance);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل كتل القراءة.';
        _loading = false;
      });
    }
  }

  void _openBlock(DeepReadingBlock block) {
    Navigator.of(context).push(MaterialPageRoute<Widget>(
      builder: (_) => ConceptReaderPage(unitId: block.unitIds.first),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('كتل القراءة العميقة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  actionLabel: 'إعادة المحاولة',
                  onAction: _load,
                )
              : _blocks.isEmpty
                  ? const EmptyState(
                      icon: Icons.menu_book_rounded,
                      mascot: 'puzzled',
                      title: 'لا شروح متاحة بعد',
                      subtitle: 'استورد محاضرة ثم عد إلى هنا',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        children: <Widget>[
                          Text(
                            'اختر جرعتك القرائية',
                            style: AppType.screenTitle
                                .copyWith(color: AppColors.text(b)),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'كل كتلة تمر عبر بوابة تنفس ثم بوابة سؤال ثم'
                            ' لقطات القراءة بنقاط استرجاع — البطاقات تبقى'
                            ' ذيلاً في مراجعة اليوم.',
                            style: AppType.body.copyWith(
                              height: 1.7,
                              color: AppColors.textSecondary(b),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          for (final DeepReadingBlock block in _blocks)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.md),
                              child: _BlockCard(
                                block: block,
                                onTap: () => _openBlock(block),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.xxxl),
                        ],
                      ),
                    ),
    );
  }
}

/// بطاقة كتلة واحدة.
class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block, required this.onTap});

  final DeepReadingBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final Color accent = Theme.of(context).colorScheme.primary;

    return AppCard(
      onTap: onTap,
      accent: accent,
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryTint(b),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Center(
              child: Text(block.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  block.titleAr,
                  style: AppType.cardTitle.copyWith(
                    fontSize: 17,
                    color: AppColors.text(b),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  block.subtitleAr,
                  style: AppType.body.copyWith(
                    fontSize: 12.5,
                    color: AppColors.textSecondary(b),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    Icon(Icons.schedule_rounded,
                        size: 13, color: AppColors.textSecondary(b)),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '~${block.estimatedMinutes} دقيقة',
                      style: AppType.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.textSecondary(b),
                      ),
                    ),
                  ],
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
