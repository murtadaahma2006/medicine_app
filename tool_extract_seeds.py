#!/usr/bin/env python3
# مُستخرِج محتوى الوثائق → ملفات seed_*.dart (مرحلة 5 تكملة).
# يقرأ docs/content_<unit>.md ويولّد lib/.../seed/seed_<suffix>.dart بنمط موحّد.
import os, re, glob

BASE = r"D:\newMedicineApp\medicine_app"
DOCS = os.path.join(BASE, "docs")
SEED = os.path.join(BASE, "lib", "src", "core", "database", "seed")

# (doc_file, seed_suffix, unit_id, level, title_ar, title_de, order_index, class_name, fn_name)
UNITS = [
    ("content_a1_2_family.md",     "a1_2_family",     "a1-2-family",     "A1", "العائلة",            "Familie",             2, "A1Unit2Ids", "seedA1Unit2"),
    ("content_a1_3_numbers_time.md","a1_3_numbers_time","a1-3-numbers-time","A1","الأعداد والوقت",     "Zahlen und Uhrzeit",  3, "A1Unit3Ids", "seedA1Unit3"),
    ("content_a1_4_food.md",       "a1_4_food",       "a1-4-food",       "A1", "الطعام",             "Essen und Trinken",   4, "A1Unit4Ids", "seedA1Unit4"),
    ("content_a1_5_shopping.md",   "a1_5_shopping",   "a1-5-shopping",   "A1", "التسوّق",            "Einkaufen",           5, "A1Unit5Ids", "seedA1Unit5"),
    ("content_a1_6_home.md",       "a1_6_home",       "a1-6-home",       "A1", "البيت",              "Zuhause",             6, "A1Unit6Ids", "seedA1Unit6"),
    ("content_a1_7_transport.md",  "a1_7_transport",  "a1-7-transport",  "A1", "المواصلات",          "Verkehr",             7, "A1Unit7Ids", "seedA1Unit7"),
    ("content_a1_8_free_time.md",  "a1_8_free_time",  "a1-8-free-time",  "A1", "وقت الفراغ",         "Freizeit",            8, "A1Unit8Ids", "seedA1Unit8"),
    ("content_a2_1_past.md",       "a2_1_past",       "a2-1-past",       "A2", "الماضي",             "Vergangenheit (Perfekt)", 1, "A2Unit1Ids", "seedA2Unit1"),
    ("content_a2_2_dativ.md",      "a2_2_dativ",      "a2-2-dativ",      "A2", "المجرور (Dativ)",   "Dativ",               2, "A2Unit2Ids", "seedA2Unit2"),
    ("content_a2_3_genitive.md",   "a2_3_genitive",   "a2-3-genitive",   "A2", "المضاف إليه (Genitiv)", "Genitiv",          3, "A2Unit3Ids", "seedA2Unit3"),
    ("content_a2_4_conjunctions.md","a2_4_conjunctions","a2-4-conjunctions","A2","أدوات الربط",      "Konjunktionen",       4, "A2Unit4Ids", "seedA2Unit4"),
    ("content_a2_5_comparison.md", "a2_5_comparison", "a2-5-comparison", "A2", "المقارنة",           "Vergleich",           5, "A2Unit5Ids", "seedA2Unit5"),
    ("content_a2_6_health.md",     "a2_6_health",     "a2-6-health",     "A2", "الصحة",             "Gesundheit",          6, "A2Unit6Ids", "seedA2Unit6"),
]

def dq(s):
    """تُهرب علامة الاقتباس المفردة للنص الحرفي Dart."""
    return (s or "").replace("\\", "\\\\").replace("'", "\\'")

def parse_table_row(line):
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    return cells

def is_sep(cells):
    return all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c != "")

def extract_vocab(lines):
    items = []
    raw = 0
    for ln in lines:
        if not ln.strip().startswith("|"):
            continue
        cells = parse_table_row(ln)
        if len(cells) != 6:
            continue
        if cells[0] == "german_word":
            continue
        if all(re.fullmatch(r":?-{2,}:?", c) for c in cells):
            continue
        raw += 1
        gw, tr, exd, exa, pl, pos = cells
        items.append((gw, tr, exd, exa, pl, pos))
    return items, raw

def extract_grammar(lines, unit_class):
    """يُرجع قائمة (title_ar, title_de, explanation_ar, examples)."""
    rules = []
    i = 0
    n = len(lines)
    while i < n:
        m = re.match(r"^###\s*القاعدة:\s*(.+)$", lines[i].strip())
        if m:
            title_ar = m.group(1).strip()
            title_de = None
            explanation_parts = []
            examples = []
            i += 1
            # اجمع حتى القاعدة/الحوار التالية أو فاصل --- أو نهاية القواعد
            while i < n and not re.match(r"^###\s*(القاعدة|حوار):", lines[i]) \
                  and not lines[i].strip().startswith("## (ج)") \
                  and not lines[i].strip().startswith("---"):
                line = lines[i]
                if line.strip().startswith("- **title_de:**"):
                    title_de = line.split("**title_de:**", 1)[1].strip()
                elif line.strip().startswith("|") and not is_sep(parse_table_row(line)):
                    cells = parse_table_row(line)
                    if len(cells) >= 2 and cells[0] not in ("الضمير", "german_word", "الجملة الألمانية", "الكلمة", "الموقف"):
                        de = cells[0]
                        ar = cells[-1]
                        if de and ar and de != "---":
                            examples.append((de, ar))
                elif line.strip().startswith("- **أمثلة") or line.strip().startswith("**"):
                    # عنوان جدول أو نص عريض ضمن الشرح
                    if line.strip().startswith("- **أمثلة") or line.strip().startswith("**فعل") or "التصريف" in line:
                        pass
                    else:
                        explanation_parts.append(line.strip().lstrip("- ").strip())
                elif line.strip().startswith("- "):
                    explanation_parts.append(line.strip()[2:].strip())
                elif line.strip() and not line.strip().startswith("#"):
                    explanation_parts.append(line.strip())
                i += 1
            explanation_ar = " ".join(p for p in explanation_parts if p).strip()
            if not explanation_ar and examples:
                explanation_ar = title_ar
            rules.append((title_ar, title_de, explanation_ar, examples))
        else:
            i += 1
    return rules

def extract_dialogues(lines):
    dialogues = []
    i = 0
    n = len(lines)
    while i < n:
        m = re.match(r"^###\s*حوار:\s*(.+)$", lines[i].strip())
        if m:
            title_ar = m.group(1).strip()
            lines_rows = []
            i += 1
            while i < n and not re.match(r"^###\s*(القاعدة|حوار):", lines[i]) \
                  and not lines[i].strip().startswith("## (د)") \
                  and not lines[i].strip().startswith("---"):
                line = lines[i]
                if line.strip().startswith("|") and not is_sep(parse_table_row(line)) and not line.strip().startswith("| speaker"):
                    cells = parse_table_row(line)
                    if len(cells) >= 3 and cells[0] not in ("speaker",) and cells[0] != "---":
                        lines_rows.append((cells[0], cells[1], cells[2]))
                i += 1
            if lines_rows:
                dialogues.append((title_ar, lines_rows))
        else:
            i += 1
    return dialogues

def gen_vocab_dart(items, vprefix, class_name):
    out = ["const List<VocabularyItem> %sVocabulary = <VocabularyItem>[" % vprefix]
    for gw, tr, exd, exa, pl, pos in items:
        out.append("  VocabularyItem(")
        out.append("    lessonId: %s.unit," % class_name)
        out.append("    germanWord: '%s'," % dq(gw))
        out.append("    translationAr: '%s'," % dq(tr))
        if exd:
            out.append("    exampleDe: '%s'," % dq(exd))
        if exa:
            out.append("    exampleAr: '%s'," % dq(exa))
        if pl:
            out.append("    pluralForm: '%s'," % dq(pl))
        if pos:
            out.append("    partOfSpeech: '%s'," % dq(pos))
        out.append("  ),")
    out.append("];")
    return "\n".join(out)

def gen_grammar_dart(rules, vprefix):
    out = ["const List<Map<String, Object?>> %sGrammarRules = <Map<String, Object?>>[" % vprefix]
    for title_ar, title_de, explanation_ar, examples in rules:
        out.append("  <String, Object?>{")
        out.append("    'title_ar': '%s'," % dq(title_ar))
        if title_de:
            out.append("    'title_de': '%s'," % dq(title_de))
        out.append("    'explanation_ar': '%s'," % dq(explanation_ar))
        out.append("    'examples': <Map<String, String>>[")
        for de, ar in examples:
            out.append("      <String, String>{'de': '%s', 'ar': '%s'}," % (dq(de), dq(ar)))
        out.append("    ],")
        out.append("  },")
    out.append("];")
    return "\n".join(out)

def gen_dialogues_dart(dialogues, vprefix):
    out = ["const List<Map<String, Object?>> %sDialogues = <Map<String, Object?>>[" % vprefix]
    for title_ar, lines_rows in dialogues:
        out.append("  <String, Object?>{")
        out.append("    'title_ar': '%s'," % dq(title_ar))
        out.append("    'lines': <Map<String, String>>[")
        for sp, de, ar in lines_rows:
            out.append("      <String, String>{'speaker': '%s', 'de': '%s', 'ar': '%s'}," % (dq(sp), dq(de), dq(ar)))
        out.append("    ],")
        out.append("  },")
    out.append("];")
    return "\n".join(out)

def gen_file(doc_file, suffix, unit_id, level, title_ar, title_de, order_index, class_name, fn_name):
    path = os.path.join(DOCS, doc_file)
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    vocab, raw = extract_vocab(lines)
    grammar = extract_grammar(lines, class_name)
    dialogues = extract_dialogues(lines)
    const_prefix = class_name[0].lower() + class_name[1:]  # a1Unit2
    body = []
    body.append("import 'dart:convert';")
    body.append("")
    body.append("import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;")
    body.append("import 'package:sqflite/sqflite.dart';")
    body.append("")
    body.append("import '../../../features/vocabulary/domain/models/vocabulary_item.dart';")
    body.append("import '../database_helper.dart';")
    body.append("")
    body.append("/// محتوى وحدة %s — %s." % (unit_id, title_ar))
    body.append("/// مصدر رسمي: docs\\%s (وثيقة خبير المحتوى المعتمدة) — مُنسوخ حرفياً." % doc_file)
    body.append("")
    body.append("abstract final class %s {" % class_name)
    body.append("  /// الوحدة: %s." % title_ar)
    body.append("  static const String unit = '%s';" % unit_id)
    body.append("}")
    body.append("")
    body.append("const Map<String, Object?> %sUnit = <String, Object?>{" % const_prefix)
    body.append("  'id': %s.unit," % class_name)
    body.append("  'level': '%s'," % level)
    body.append("  'title_ar': '%s'," % dq(title_ar))
    body.append("  'title_de': '%s'," % dq(title_de))
    body.append("  'order_index': %d," % order_index)
    body.append("  'description_ar': 'وحدة %s من منهج A1/A2: %s.'" % (unit_id, title_ar))
    body.append("};")
    body.append("")
    body.append("const Map<String, Object?> %sLesson = <String, Object?>{" % const_prefix)
    body.append("  'id': %s.unit," % class_name)
    body.append("  'level': '%s'," % level)
    body.append("  'title_ar': '%s'," % dq(title_ar))
    body.append("  'title_de': '%s'," % dq(title_de))
    body.append("  'order_index': %d," % order_index)
    body.append("  'description_ar': 'وحدة %s من منهج A1/A2: %s.'" % (unit_id, title_ar))
    body.append("};")
    body.append("")
    body.append(gen_vocab_dart(vocab, const_prefix, class_name))
    body.append("")
    body.append(gen_grammar_dart(grammar, const_prefix))
    body.append("")
    body.append(gen_dialogues_dart(dialogues, const_prefix))
    body.append("")
    body.append("/// يزرع وحدة %s (وحدة + درس موازٍ + مفردات + قواعد + حوارات)." % unit_id)
    body.append("/// transaction + INSERT OR IGNORE + COUNT (idempotent).")
    body.append("Future<int> %s() async {" % fn_name)
    body.append("  final Database db = await DatabaseHelper.instance.database;")
    body.append("  int inserted = 0;")
    body.append("  await db.transaction((Transaction txn) async {")
    body.append("    inserted += await _insertOrIgnore(txn, DatabaseHelper.tableUnits, %sUnit);" % const_prefix)
    body.append("    if (%sVocabulary.isNotEmpty) {" % const_prefix)
    body.append("      inserted += await _insertOrIgnore(txn, DatabaseHelper.tableLessons, %sLesson);" % const_prefix)
    body.append("    }")
    body.append("    for (final VocabularyItem item in %sVocabulary) {" % const_prefix)
    body.append("      inserted += await _insertOrIgnore(")
    body.append("        txn,")
    body.append("        DatabaseHelper.tableVocabulary,")
    body.append("        <String, Object?>{")
    body.append("          'unit_id': %s.unit," % class_name)
    body.append("          ...item.toMap(searchTerm: item.germanWord.toLowerCase().trim()),")
    body.append("        },")
    body.append("      );")
    body.append("    }")
    body.append("    final int grammarCount = Sqflite.firstIntValue(await txn.rawQuery(")
    body.append("          'SELECT COUNT(*) FROM ${DatabaseHelper.tableGrammarRules} WHERE unit_id = ?',")
    body.append("          <Object?>[%s.unit])) ?? 0;" % class_name)
    body.append("    if (grammarCount == 0) {")
    body.append("      for (final Map<String, Object?> rule in %sGrammarRules) {" % const_prefix)
    body.append("        final List<Map<String, String>> examples =")
    body.append("            (rule['examples']! as List<Map<String, String>>);")
    body.append("        inserted += await _insertOrIgnore(")
    body.append("          txn,")
    body.append("          DatabaseHelper.tableGrammarRules,")
    body.append("          <String, Object?>{")
    body.append("            'unit_id': %s.unit," % class_name)
    body.append("            'title_ar': rule['title_ar']!,")
    body.append("            'title_de': rule['title_de'],")
    body.append("            'explanation_ar': rule['explanation_ar']!,")
    body.append("            'examples_json': jsonEncode(examples),")
    body.append("            'order_index': 0,")
    body.append("          },")
    body.append("        );")
    body.append("      }")
    body.append("    }")
    body.append("    final int dialogueCount = Sqflite.firstIntValue(await txn.rawQuery(")
    body.append("          'SELECT COUNT(*) FROM ${DatabaseHelper.tableDialogues} WHERE unit_id = ?',")
    body.append("          <Object?>[%s.unit])) ?? 0;" % class_name)
    body.append("    if (dialogueCount == 0) {")
    body.append("      for (final Map<String, Object?> dialogue in %sDialogues) {" % const_prefix)
    body.append("        final List<Map<String, String>> lines =")
    body.append("            (dialogue['lines']! as List<Map<String, String>>);")
    body.append("        inserted += await _insertOrIgnore(")
    body.append("          txn,")
    body.append("          DatabaseHelper.tableDialogues,")
    body.append("          <String, Object?>{")
    body.append("            'unit_id': %s.unit," % class_name)
    body.append("            'title_ar': dialogue['title_ar'],")
    body.append("            'lines_json': jsonEncode(lines),")
    body.append("            'order_index': 0,")
    body.append("          },")
    body.append("        );")
    body.append("      }")
    body.append("    }")
    body.append("  });")
    body.append("  if (inserted > 0 && kDebugMode) {")
    body.append("    debugPrint('DatabaseHelper: زُرع %s ($inserted صفاً جديداً)');" % unit_id)
    body.append("  }")
    body.append("  return inserted;")
    body.append("}")
    body.append("")
    body.append("Future<int> _insertOrIgnore(DatabaseExecutor txn, String table, Map<String, Object?> row) async {")
    body.append("  final int? before = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM $table'));")
    body.append("  await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);")
    body.append("  final int? after = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM $table'));")
    body.append("  return (after ?? 0) - (before ?? 0);")
    body.append("}")
    content = "\n".join(body) + "\n"
    out_path = os.path.join(SEED, "seed_%s.dart" % suffix)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)
    return len(vocab), len(grammar), len(dialogues), raw, out_path

if __name__ == "__main__":
    totals = []
    for u in UNITS:
        nv, ng, nd, raw, p = gen_file(*u)
        totals.append((u[1], nv, ng, nd))
        print("OK", u[1], "raw=%d vocab=%d grammar=%d dialogues=%d" % (raw, nv, ng, nd))
    print("TOTAL vocab =", sum(t[1] for t in totals))
