# مواصفة نموذج البيانات الطبي (Medical Content JSON Schema) — v2.0.0

> **الإصدار:** 2.0.0 — العقد النهائي بين خط استخراج البيانات (Python) والتطبيق (Flutter/SQLite).
> أي ملف JSON لا يحقق `medical_lecture.schema.json` يُرفض وقت الحقن.
>
> **قاعدة اللغة (v2):** لغة المحتوى الأساسية **الإنجليزية** — كل الحقول المحايدة (`title`, `front_text`, `question_stem`...) إنجليزية دائماً. فقط الحقول المساعدة المسماة صراحةً `_ar` (مثل `explanation_ar`, `debriefing_ar`) عربية.

---

## 1) الخريطة: قديم ← جديد

| مكوّن التطبيق القديم (ألماني) | البديل الطبي | جدول SQLite المستهدف |
|---|---|---|
| `units` (وحدات A0–A2) | المحاضرات الطبية | `units` |
| `grammar_rules` (قواعد النحو) | الشروحات المفصلة (Concepts) | `concepts` |
| `vocabulary` + `srs_cards` | البطاقات الغنية (SRS) | `flashcards` + `srs_cards` |
| `exam_bank` / `assessment` | بنك أسئلة MCQ | `mcq_bank` |
| `dialogues` + `dialogue_choices` | الحالات السريرية (OSCE) | `clinical_cases` + `clinical_case_steps` |

**المحركات المُعادة الاستخدام:** SQLite Helper · SRS (Leitner 1–5) · Quiz Engine · Gamification (XP/Levels/Streak/Heatmap/Badges) · Theme (Light/Dark + Animations).

---

## 2) هيكل الملف (Lecture File)

```json
{
  "schema_version": "2.0.0",
  "lecture": { ... },
  "concepts": [ ... ],
  "flashcards": [ ... ],
  "mcqs": [ ... ],
  "clinical_cases": [ ... ]
}
```

- الحقول الخمسة بعد `schema_version` كلها **إلزامية** (مصفوفة فارغة `[]` مقبولة إن لم يوجد محتوى).
- الترتيب داخل المصفوفات = `order_index` في القاعدة.
- **المعرفات (IDs):** أي نص أبجدي رقمي مع شرطات وسفلات — `^[a-zA-Z0-9_-]+$` (مبسط لتجنب أخطاء التحقق عند التوليد الآلي). كل `id` فريد عالمياً وثابت.
- الترميز UTF-8. التواريخ ISO-8601 UTC (استخدام التطبيق الداخلي).

---

## 3) العنصر 1 — البيانات الوصفية `lecture`

```json
{
  "id": "cardio-001",
  "title": "Heart Failure",
  "module": "cardiology",
  "system": "cardiovascular",
  "source": {
    "file_name": "heart_failure_lecture.pdf",
    "page_count": 48
  },
  "tags": ["heart failure", "HFrEF", "NYHA"],
  "order_index": 3
}
```

| حقل | النوع | إلزامي | قواعد |
|---|---|---|---|
| `id` | string | نعم | `^[a-zA-Z0-9_-]+$`، فريد عالمياً |
| `title` | string | نعم | إنجليزي، ≥ 3 أحرف |
| `module` | enum | نعم | من قائمة التخصصات (§8) |
| `system` | enum | نعم | من قائمة الأجهزة (§8) |
| `source.file_name` | string | نعم | اسم الـ PDF الأصلي |
| `source.page_count` | integer | نعم | > 0 (إحصائي فقط — لا مراجع صفحات في المحتوى) |
| `tags` | string[] | لا | كلمات مفتاحية إنجليزية |
| `order_index` | integer | نعم | ≥ 0 |

> **ملاحظة:** لا يوجد `source_pages` أو أي مرجع صفحات — المخطط يركز على المحتوى التعليمي فقط.

---

## 4) العنصر 2 — الشروحات المفصلة `concepts`

```json
{
  "id": "cardio-001-c1",
  "lecture_id": "cardio-001",
  "title": "Pathophysiology of Heart Failure: From Reduced Output to the Vicious Cycle",
  "summary_ar": "ملخص عربي اختياري يظهر في البطاقة التمهيدية",
  "sections": [
    {
      "heading": "The Neurohormonal Vicious Cycle",
      "body_text": "English narrative, >= 100 chars. Simplified Markdown only: headings, **bold**, lists. No HTML, no links, no images.",
      "key_points": ["Sympathetic + RAAS: rescue in minutes, ruin in months"]
    }
  ],
  "key_terms": [
    { "term": "Ejection Fraction (EF)", "definition_ar": "نسبة حجم الدم المقذوف..." }
  ],
  "difficulty": "core",
  "order_index": 1
}
```

| حقل | النوع | إلزامي | قواعد |
|---|---|---|---|
| `id` | string | نعم | فريد وثابت |
| `lecture_id` | string | نعم | يجب أن يطابق `lecture.id` في نفس الملف |
| `title` | string | نعم | إنجليزي |
| `summary_ar` | string | لا | ملخص عربي مساعد |
| `sections` | array | نعم | ≥ 1؛ كل عنصر: `heading` (إنجليزي) + `body_text` (إنجليزي، ≥ 100 حرف) + `key_points` (اختياري) |
| `key_terms` | array | لا | `term` إنجليزي + `definition_ar` عربي |
| `difficulty` | enum | نعم | `core` \| `advanced` |
| `order_index` | integer | نعم | ≥ 0 |

---

## 5) العنصر 3 — البطاقات الغنية `flashcards` (SRS)

```json
{
  "id": "cardio-001-f1",
  "lecture_id": "cardio-001",
  "concept_id": "cardio-001-c1",
  "card_type": "basic",
  "front_text": "What is the fundamental physiological difference between HFrEF and HFpEF?",
  "back_text": "HFrEF: a systolic problem — ... (detailed answer)",
  "mnemonic_ar": "انقباضي = «فرّغ أقل» — امتلائي = «املأ أصعب»",
  "explanation_ar": "شرح عربي مساعد يظهر بعد قلب البطاقة",
  "tags": ["HFrEF", "HFpEF"]
}
```

| حقل | النوع | إلزامي | قواعد |
|---|---|---|---|
| `id` | string | نعم | فريد |
| `concept_id` | string | لا | ربط اختياري بالشرح |
| `card_type` | enum | نعم | `'basic'` فقط في v2.0 |
| `front_text` | string | نعم | إنجليزي، ≥ 10 أحرف — سؤال استرجاعي واحد واضح |
| `back_text` | string | نعم | إنجليزي، ≥ 20 حرفاً — إجابة تفصيلية دسمة |
| `mnemonic_ar` | string | لا | حيلة حفظ عربية |
| `explanation_ar` | string | لا | شرح عربي مساعد بعد قلب البطاقة |
| `tags` | string[] | لا | إنجليزية |

> **لا يوجد كائن `references`** — حُذف بالكامل في v2 لتسريع التوليد. لا مراجع صفحات ولا slideRef.

---

## 6) العنصر 4 — بنك أسئلة MCQ `mcqs`

```json
{
  "id": "cardio-001-q1",
  "lecture_id": "cardio-001",
  "concept_id": "cardio-001-c1",
  "question_stem": "A 68-year-old woman presents with exertional dyspnea and ankle edema. ECG is normal; echo shows EF 58% with LVH and E/e' of 16...",
  "options": [
    "Heart failure with reduced ejection fraction (HFrEF)",
    "Heart failure with preserved ejection fraction (HFpEF)",
    "Silent ischemic heart disease",
    "Constrictive pericarditis"
  ],
  "correct_index": 1,
  "explanation_ar": "أعراض احتقانية مع EF ≥ 50% واضطراب امتلاء = HFpEF...",
  "difficulty": "core",
  "clinical_vignette": true
}
```

| حقل | النوع | إلزامي | قواعد |
|---|---|---|---|
| `id` | string | نعم | فريد |
| `question_stem` | string | نعم | إنجليزي، ≥ 30 حرفاً |
| `options` | string[] | نعم | **مصفوفة نصوص مباشرة** — 3 إلى 5 عناصر إنجليزية |
| `correct_index` | integer | نعم | **صفري الأساس** (0 = الخيار الأول)؛ يجب أن يكون < عدد الخيارات |
| `explanation_ar` | string | نعم | عربي، ≥ 30 حرفاً — لماذا الصحيح ولماذا الآخرون خطأ |
| `difficulty` | enum | نعم | `core` \| `advanced` |
| `clinical_vignette` | bool | نعم | هل السؤال سيناريو مريض أم نظري |

---

## 7) العنصر 5 — الحالات السريرية `clinical_cases` (OSCE)

```json
{
  "id": "cardio-001-case1",
  "lecture_id": "cardio-001",
  "title": "3 AM Emergency: Sudden Dyspnea in a 55-Year-Old Smoker",
  "scenario": "A 55-year-old man, smoker with type 2 diabetes, is brought to the ED at 3 AM with sudden-onset breathlessness...",
  "vignette": {
    "age": 55, "sex": "male",
    "chief_complaint": "Sudden dyspnea at rest with drenching sweats",
    "history": "Type 2 diabetes for 10 years, 30 pack-year smoking...",
    "vitals": { "bp": "95/60", "hr": "118", "rr": "28", "temp": "36.9", "spo2": "89% on room air" },
    "exam": "Diaphoretic, cold grayish skin, wet bilateral basal crackles, S3...",
    "labs": [ { "name": "Troponin I", "value": "3.2 ng/mL", "flag": "critical" } ],
    "imaging": "ECG: ST elevation in II, III, aVF..."
  },
  "steps": [
    {
      "id": "cardio-001-case1-s1",
      "prompt": "First minutes in the ED: which single workup must not wait a minute?",
      "options": ["ECG within 10 minutes", "Immediate chest X-ray", "Full bedside echocardiogram"],
      "correct_index": 0,
      "explanation_ar": "ضيق نفس حاد + عوامل خطر = احتمال احتشاء حتى يثبت العكس...",
      "xp": 5
    }
  ],
  "debriefing_ar": "الحالة كانت احتشاءً سفلياً مقنّعاً بضغط منخفض...",
  "difficulty": "advanced",
  "order_index": 1
}
```

| حقل | النوع | إلزامي | قواعد |
|---|---|---|---|
| `id` | string | نعم | فريد |
| `title` | string | نعم | إنجليزي |
| `scenario` | string | نعم | إنجليزي، ≥ 50 حرفاً |
| `vignette` | object | نعم | `age`(1–120) · `sex` · `chief_complaint` · `history` · `vitals`(bp/hr/rr/temp/spo2 نص حر) · `exam` · `labs`[](`name`,`value`,`flag`∈`normal`\|`high`\|`low`\|`critical`) · `imaging` — كل النصوص إنجليزية |
| `steps` | array | نعم | ≥ 2؛ كل خطوة: `prompt` إنجليزي + `options` **مصفوفة نصوص** (3–5) + `correct_index` صفري الأساس + `explanation_ar` عربي + `xp` (1–20، افتراضي 5) |
| `debriefing_ar` | string | نعم | عربي، ≥ 80 حرفاً |
| `difficulty` | enum | نعم | `core` \| `advanced` |
| `order_index` | integer | نعم | ≥ 0 |

**قاعدة XP:** كل خطوة صحيحة تُكافأ بنوع حدث `case_step` عبر محرك XP.

---

## 8) القوائم المسموحة (Enums)

```text
modules: cardiology · pulmonology · nephrology · gastroenterology
  · endocrinology · hematology · infectious · rheumatology · neurology · oncology
systems: cardiovascular · respiratory · renal · gastrointestinal · endocrine
  · immune · nervous · musculoskeletal · hematologic · integumentary
difficulty: core · advanced
flashcard.card_type: basic (v2.0) — reverse, case_anchored محجوزة
xp event kinds: concept · flashcard · mcq · case_step · streak · assessment · drill · review
```

## 9) قواعد التحقق العامة (Validation Rules)

1. **التطابق المرجعي:** كل `lecture_id` يجب أن يساوي `lecture.id` في نفس الملف.
2. **تفرد المعرفات:** كل `id` فريد عالمياً — الحقن عبر `INSERT OR IGNORE` idempotent.
3. **سؤال اللغة:** الحقول المحايدة إنجليزية حصراً؛ الحقول `_ar` عربية حصراً. ملف يخلط اللغات في حقل محايد يُرفض.
4. **الأطوال الدنيا:** كما في كل جدول أعلاه — بطاقات دسمة لا أسطر جافة.
5. **Markdown فقط في `body_text`:** بلا HTML أو روابط أو صور.
6. **`correct_index` صفري الأساس** في mcqs وsteps معاً — انتبه في سكربت بايثون.
7. **`options` مصفوفة نصوص** — لا كائنات `{key, text}` بعد الآن.
8. **لا مراجع صفحات** — لا `references` ولا `source_pages` ولا `page` في أي عنصر.
9. **الحصص الدنيا لكل محاضرة (لتستحق الحقن):** ≥ 1 concept · ≥ 3 flashcards · ≥ 3 mcqs · ≥ 1 clinical_case (مصفوفات فارغة مسموحة للملفات التمهيدية فقط).

## 10) مثال ملف كامل

`docs/examples/cardio_001.example.json` — مثال كامل مطابق لـ v2.0.0، تم التحقق منه آلياً ضد الـ Schema.

## 11) خريطة الحقن في SQLite (Injection Map)

| JSON | جدول القاعدة | ملاحظات |
|---|---|---|
| `lecture` | `units` | `id`, `module`, `title` (إنجليزي), `order_index` |
| `concepts` | `concepts` | `sections` + `key_terms` تُخزنان JSON كما هما |
| `flashcards` | `flashcards` + `srs_cards` | بطاقة SRS تُنشأ عند أول مراجعة |
| `mcqs` | `mcq_bank` | `options` تُخزن JSON array + `correct_index` |
| `clinical_cases` | `clinical_cases` + `clinical_case_steps` | الخطوات بجدول مناظر لـ `dialogue_choices` القديم |
