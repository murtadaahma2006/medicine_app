# HANDOFF — منصة الطب الباطني (Internal Medicine Platform)
> وثيقة تسليم محدّثة — آخر تحديث: نهاية الجلسة الحالية. الغرض: استئناف العمل في محادثة جديدة بلا إعادة شرح.

---

## 1) سياق المشروع
- تطبيق Flutter في `D:\medicineApp\medicine_app` — كان تطبيق تعلّم الألمانية (A0–A2)، **حُوّل بالكامل** إلى منصة دراسة الطب الباطني.
- **أوفلاين 100%** — SQLite محلي، لا إنترنت.
- **لغة المحتوى: الإنجليزية** (المستخدم يدرس الطب بالإنجليزية). واجهة التطبيق عربية RTL. فقط الحقول المسماة `_ar` عربية (شروحات مساعدة).
- المحركات المُبقاة: SQLite Helper · SRS (Leitner صناديق 1–5، فواصل 1/2/4/8/16 يوم) · محرك أسئلة · تلعيب كامل (XP/مستويات/سلسلة/تقويم حراري/شارات) · ثيم فاتح/داكن + حركات.
- DB: `medical_app.db` — **databaseVersion = 16** (v15: محرّك القراءة · v16: عقد v2.1 + البوابة).

## 2) الحالة الحالية: ✅ محرّك القراءة العميقة كامل (الأسبوعان 1–3)
- `flutter analyze` = **No issues found**
- `flutter test` = **105/105 PASS** (… · fixation_spans · deep_reading_v15 · deep_reading_week23 · reward_engine · **today_goals**)

### ✅ أهداف اليوم الموحدة (v17 + checkTodayStatus) — آخر إنجاز:
- **المشكلة الحلّت**: كانت شاشة اليوم تعتمد على البطاقات المستحقة وحدها («مراجعة اليوم مكتملة» والمحاضرة المثبتة بانتظارك).
- **`getPinnedUnitsWithCompletion`** (database_helper): المحاضرات المثبتة + `is_completed` مشتق ديناميكياً (بلا هجرة): اجتياز `assess-<id>` **أو** كل الشروح لها `concept_reads.completed=1`. نفس معيار المسار + القراءة العميقة.
- **`TodayGoalsSnapshot`** (unit_repository.dart — نقي قابل للاختبار): `pinned/completedPinned/dueCards` + `pendingPinned` + `phase` (lectures→reviews→done) + `progress` (سهم لكل محاضرة + سهم حزمة البطاقات). هذا هو **checkTodayStatus**.
- **شاشة اليوم** (`today_page.dart`): بطاقة أهداف موحدة — الحلقة نسبة مئوية من الأسهم · الرسائل: «لديك محاضرات بانتظارك اليوم!» → «لديك مراجعات مستحقة» → «مهام اليوم مكتملة 🌟» · قائمة المحاضرات المثبتة بحالة إتمام لكل واحدة (✓/دائرة) + صف بطاقات المراجعة · النبضة الافتتاحية محفوظة · `_openUnit` يعيد الجلب عند العودة.
- **إلغاء التثبيت التلقائي**: `unpinUnit` (يدوي) + `unpinUnitIfCompleted` (ذرّة SQL — لا يُلمس التثبيت إلا إذا اكتملت فعلاً). يُستدعى من: اجتياز التقييم (`mcq_session_page._finish`) + إتمام قراءة الشروح (`concept_reader_page._finish`).
- الاختبارات: `test/today_goals_test.dart` (14 اختباراً — اشتقاق الإكمال بالحالتين + الإلغاء التلقائي + المراحل والحلقة النقية + لقطة القاعدة الكاملة).
- الـ Schema يتحقق آلياً ضد المثال (python `jsonschema` مثبتة على الجهاز — v4.26)
- محاضرة `L4_URTI_lecture_content.json` مزروعة عبر assets/MANIFEST (تختبرها بـ `flutter run`)

### الأسبوع 1 المُنفَّذ (تايبوغرافيا + مراسي + قارئ اللقطات + DB v15):
1. **خط Atkinson Hyperlegible** مضمّن (`assets/fonts/atkinson/` — TTF ×2، OFL) — أجسام الشروحات فقط (`AppType.focusFamily`).
2. **تايبوغرافيا التركيز**: 18sp · 1.7 · TextAlign.start · 460px · `#E6E6E6` داكن (منع Halation) — `focusBodyStyle/focusHeadingStyle`.
3. **مراسي التثبيت** (`fixation_spans.dart` نقية): تعريض بداية الكلمة اللاتينية (وزن 700) · <3 محارف لا تُجزأ · أرقام جزء من الكلمة · القراءة الأولى فقط.
4. **قارئ لقطات**: لقطة/شاشة · زر التالي الكبير · تسجيل أزمنة البقاء (concept_reads.sections_json).
5. **جلسات تدفق**: flow_sessions → «دقائق التركيز».
6. XP نوع `concept` (+10) + مكافأة السلسلة.
7. إعدادات «القراءة العميقة» (`fixation_settings.dart`): مفتاح + قوة (30/40/60%) + معاينة حية.

### الأسبوع 2 المُنفَّذ (بوابة + اعتراضيات + عقد v2.1):
8. **بوابة الشرح** (`concept_gate_sheet.dart`): قبل أول لقطة — سؤال MCQ من أسئلة الشرح نفسه (`getGateMcqForConcept` — `concept_id` موجود منذ v14 بصفر تأليف) + **مقياس ثقة 3 درجات** (خمنت/متأكد/متأكد جداً → `confidence_log`). الخطأ + `focus_sections` → **إطار كهرماني + شارة «هنا كان خطؤك»** على الأقسام المعنية في القارئ (قراءة قنص موجّه). إجابة صحيحة أول مرة → `gate_passed=1` (لا بوابة مجدداً). لا MCQ؟ fallback: بطاقة مسح مسبق بمصطلحات key_terms.
9. **نقاط الاعتراض** (`interception_sheet.dart`): كل لقطتين — بأولوية: سؤال `check` مدمج (v2.1) > MCQ غير مستهلك من الشرح > **استرجاع حر** «لخّص بثلاث نقاط» ثم مقارنة ذاتية بالنقاط الفعلية. التثبيت الختامي (Recite) عند آخر لقطة من كل شرح.
10. **عقد JSON v2.1** (توسعي اختياري — الملفات القديمة صالحة حرفياً): `focus_sections:[int]` + `hints:[string]` (mcq/steps) · `check:{prompt,options,correct_index,explanation_ar}` (sections — يعيش داخل sections_json فلا يمس seeder) · `is_vivid:bool` (flashcards). تحقق كامل في LectureImportService + زرع في أعمدة v16.

### الأسبوع 3 المُنفَّذ (كتل + كاشف + حارس + مقياس الشمال):
11. **كتل القراءة** (`reading_blocks_page.dart` — من شاشة اليوم): غوصة عميقة (3–4 شروح **متداخلة الأجهزة** — `_interleaveBySystem`: لا يتكرر الجهاز متتالياً — Schema تشخيصي تفريقي) + كتلة معيارية (شرح–شرحان). تختار من `getUnfinishedConcepts` (جلساتك دائماً إكمال — Ovsiankina).
12. **بوابة التنفس** (`breath_gate.dart`): 8 ثوان (4-2-2) قبل أول لقطة — الزر لا يتفعل قبل اكتمال النفس.
13. **حارس الجلسة** (`session_guard.dart`): خروج مبكر → بطاقة الحقيقة «بقيت N لقطات» + «أكمل — أستطيع» الكبير (البقاء افتراضي بصري) + إيقاف يحفظ التقدم.
14. **كاشف التصفح**: زمن لقطة < 40% من `averageSectionDwellSeconds` → الاعتراضية التالية فوراً.
15. **دقائق التركيز** (`focus_minutes_page.dart` — بطاقة بارزة في «ملفي» فوق XP): الرقم الكبير اليوم + رسم أعمدة 7 أيام + المجموع — **هذا مقياس الشمال، لا XP**.

### المقترح 4 المُنفَّذ (محرّك المكافأة الطبقي + قناة الـ 85%):
16. **قناة الـ 85%** (`lib/src/core/motivation/flow_channel_controller.dart` — نقي بلا Flutter): نافذة متحركة آخر 15 إجابة (Queue في الذاكرة — **صفر هجرة قاعدة**). >87% → harder · <70% → easier · بينهما stay · لا ضبط قبل 5 عينات (لا قرارات على ضوضاء).
17. **الضربة الحمراء ×2** (`lib/src/core/motivation/reward_engine.dart`): 12% لكل إجابة صحيحة (Variable Ratio — الوحيد الذي لا تنطفئ استجابته الدوبامينية). نمط لمسي مركب مميز (heavy→120ms→medium) + شارة «⚡ ضربة حظ ×2» ذهبية ومضية تتلاشى. لا تخزين ولا شراء — مفاجأة نقية.
18. **مضاعف التسارع** (Goal Gradient — Kivetz): XP يزداد قرب النهاية: ×1.0 حتى 70% · ×1.25 حتى 85% · ×1.5 بعدها. مطبّق في MCQ (`grantXp(base:5)`) والبطاقات (`base:3/1`) — قيد CHECK للأنواع محفوظ (القيم فقط تتغير).
19. **البداية المزيفة** (Illusion of Head Start — Nunes & Drèze): شريطا تقدم الجرعتين يبدآن من 15% ممتلئاً (`displayProgress`).
20. **وميض منطقة الاندفاع**: عبور 70% → حد أخضر خاطف 200ms + نبضة لمسية — مرة واحدة بالجرعة (لا إزعاج).
21. **الصعوبة التكيفية** (بلا إعلان): جلسة MCQ التدريبية تُرتَّب عبر `getMcqsForUnitAdaptive(unitId, difficultyOrderWeight(signal))` — CASE WHEN على عمود difficulty الموجود منذ v14 (بلا هجرة). harder→advanced أولاً، easier→core أولاً. **التقييم الرسمي مستثنى** (عناصر ثابتة). السلسلة الصحيحة ≥3 → mediumImpact إضافي.
22. **الصوت مؤجَّل** اختيارياً (audioplayers حُذف سابقاً) — عند إضافته: أصوات أصول <0.5s بلا كلمات.

### v16 — الأعمدة الجديدة (ALTER ADD تسامحي — لا فقد بيانات):
- `mcq_bank.hints_json` + `mcq_bank.focus_sections_json` · `clinical_case_steps.hints_json` · `flashcards.is_vivid` · `concept_reads.gate_passed`.
- API البوابة: `getGateMcqForConcept` · `getMcqsForConcept` · `markGatePassed`/`conceptGatePassed`.
- API الكتل: `getUnfinishedConcepts(limit)` · `averageSectionDwellSeconds` · `focusedMinutesRecent(days)`.

## 3) عقد البيانات (Data Contract) — v2.0.0 + امتداد v2.1 اختياري
**الملفات:**
- الـ Schema: `docs/schemas/medical_lecture.schema.json` (يشمل حقول v2.1 الاختيارية)
- المثال الصالح: `docs/examples/cardio_001.example.json`
- المواصفة النصية: `docs/medical_schema.md`

**القواعد الحرجة:**
| قاعدة | القيمة |
|---|---|
| `schema_version` | `"2.0.0"` حرفياً (حقول v2.1 اختيارية داخله — لا رقم إصدار جديد) |
| حقول إنجليزية محايدة | `title`, `front_text`, `back_text`, `question_stem`, `heading`, `body_text`, `scenario`, `prompt`, `chief_complaint`, `history`, `exam`, `imaging`, `term` |
| حقول عربية فقط | `explanation_ar`, `summary_ar`, `debriefing_ar`, `definition_ar`, `mnemonic_ar` |
| IDs | `^[a-zA-Z0-9_-]+$` — فريدة عالمياً وثابتة |
| options | **مصفوفة نصوص** (3–5 عناصر) — لا كائنات |
| `correct_index` | **صفري الأساس** (0 = الأول) في MCQ وcase steps معاً |
| مراجع الصفحات | **محظورة تماماً** — لا `references` ولا `source_pages`. فقط `source: {file_name, page_count}` إحصائياً في lecture |
| modules enum | cardiology · pulmonology · nephrology · gastroenterology · endocrinology · hematology · infectious · rheumatology · neurology · oncology |
| systems enum | cardiovascular · respiratory · renal · gastrointestinal · endocrine · immune · nervous · musculoskeletal · hematologic · integumentary |
| difficulty | core · advanced |
| card_type | `basic` فقط في v2.0 |
| أطوال دنيا | body_text ≥100 · front_text ≥10 · back_text ≥20 · question_stem ≥30 · explanation_ar ≥30 · scenario ≥50 · debriefing_ar ≥80 · steps ≥2 |
| الحصص لكل محاضرة | ≥1 concept · ≥3 flashcards · ≥3 mcqs · ≥1 case |

**حقول v2.1 الاختيارية (كلها بلا قيمة افتراضية — غيابها = ملف v2.0 صالح):**
| الحقل | أين | الغرض |
|---|---|---|
| `focus_sections: [int]` | mcqs | فهارس الأقسام التي تجيب السؤال → تمييز «هنا كان خطؤك» كهرمانياً في القارئ |
| `hints: [string]` (1–3) | mcqs + خطوات الحالات | جسر التلميح عند الإحباط — XP متناقص 70%/40%/10% |
| `check: {prompt, options(2–5), correct_index, explanation_ar?}` | sections | سؤال اعتراضي مدمج — يعيش داخل sections_json فلا يمس الـ seeder |
| `is_vivid: bool` | flashcards | نقاط القطع عند الذروة (Cliffhanger — Ovsiankina) |

**بنية الملف:** `{schema_version, lecture, concepts[], flashcards[], mcqs[], clinical_cases[]}` — كلها إلزامية.

**أوامر تحقق سريعة:**
```
python -c "import json; from jsonschema import Draft202012Validator; s=json.load(open('docs/schemas/medical_lecture.schema.json',encoding='utf-8')); d=json.load(open('<FILE>',encoding='utf-8')); es=list(Draft202012Validator(s).iter_errors(d)); [print(e.path,e.message) for e in es] or print('PASS')"
```

## 4) طريقة إضافة المحتوى (Workflow)
### (أ) استيراد من الهاتف — **للمستخدم النهائي** ⭐ جديد
- الإعدادات → قسم «المحتوى» → **«استيراد محاضرة»** (`lib/src/features/settings/presentation/pages/lecture_import_page.dart`)
- يختار JSON من الجهاز (file_picker) → **تحقق كامل من العقد v2.0.0** في `LectureImportService.validateMap` → معاينة (عنوان/تخصص/أعداد) → زرع داخل معاملة واحدة (INSERT OR IGNORE — idempotent، تخطي مهذب للموجود، لا يمس التقدم أبداً).
- الخدمة النقية: `lib/src/core/content/lecture_import_service.dart` — قابلة للاختبار على FFI (اختباراتها في `test/lecture_import_service_test.dart`).
- المحاضرة المستوردة تظهر فوراً في المسار/المكتبة/مراجعة اليوم — **بلا إعادة بناء**.

### (ب) الحقن عبر الأصول — للتجميع الافتراضي
1. ضع ملف المحاضرة في `assets/content/` (مثال: `assets/content/cardio_001.json`)
2. سجّله في `assets/content/MANIFEST.json`:
   ```json
   { "files": ["assets/content/cardio_001.json"] }
   ```
3. أعد بناء التطبيق — **ContentSeeder** (`lib/src/core/database/content_seeder.dart`) يزرع تلقائياً خلف شاشة البداية (idempotent عبر INSERT OR IGNORE — آمن عند كل تشغيل، لا يكرر ولا يحذف تقدم المستخدم).
4. التحقق قبل الحقن اختياري لكنه موصى به (الأمر أعلاه).

## 5) مخطط SQLite v16 (الجداول)
**المحتوى:** `units` (id, module, system, title, description_ar, order_index) · `concepts` (…, sections_json — يشمل check المدمج v2.1, key_terms_json, difficulty) · `flashcards` (…, card_type, front_text, back_text, mnemonic_ar, explanation_ar, tags_json, **is_vivid** v16) · `mcq_bank` (…, question_stem, options_json, **correct_index**, explanation_ar, difficulty, clinical_vignette, **hints_json/focus_sections_json** v16) · `clinical_cases` (…, title, scenario, vignette_json, debriefing_ar) · `clinical_case_steps` (case_id, prompt, options_json, correct_index, explanation_ar, xp, step_index, **hints_json** v16).
**المستخدم:** `user_progress` · `corrections` · `xp_events` · `unlocked_badges` · `srs_cards` (PK مركب: flashcard_id + card_type).
**v15 القراءة العميقة:** `concept_reads` (concept_id, read_count, completed, **gate_passed** v16, last_read_at, sections_json أزمنة البقاء) · `flow_sessions` (kind, ref_id, focused_seconds) · `confidence_log` (question_id, confidence, was_correct).

**اتفاقيات مفاتيح (مهمة):**
- مفاتيح drills في user_progress: `mcq-<unitId>` (جلسة أسئلة) · `case-<caseId>` (حالة) · `assess-<unitId>` (اختبار الوحدة — تقرأه شاشة المسار/اليوم عبر `item_id LIKE 'assess-%'`)
- تقدم مجموعة البطاقات: `item_type='flashcard_set'` + `item_id=<unitId>` **مجرداً بلا بادئة**
- أنواع XP المسموحة (CHECK constraint): `concept, flashcard, mcq, case_step, streak, assessment, drill, review`
- الترحيل v13→v14: يحذف كل الجداول الألمانية القديمة، **يحافظ على unlocked_badges فقط**، أحداث XP القديمة تُهدر عمداً.
- **حذف المحاضرة** `deleteLectureData(unitId)`: حذف متسلسل يدوي داخل **معاملة واحدة** — خطوات الحالات ← srs_cards (Leitner) ← corrections ← user_progress (كل المفاتيح: unitId مجرداً وflashcard_set-/mcq-/assess-/case-) ← xp_events (ref_id) ← الحالات ← البطاقات ← MCQ ← المفاهيم ← الوحدة. يُستدعى من زر الحذف في وضع «ترتيب يدوي» بعد حوار تأكيد صريح (repository: `deleteLecture` يعيد bool).
- **الاستعلامات الديناميكية للبنوك**: `getFlashcards/getMcqs/getCases({system, lectureId, isRandom, limit})` — JOIN مع units للفلترة حسب الجهاز، ترتيب المنهج (`u.order_index, u.id, …`) أو `RANDOM()`. **`getStudiedFlashcards({system, limit})`** — بطاقات عشوائية من المحاضرات ذات سجل تقدم فقط (EXISTS على user_progress: flashcard_set-<unitId> أو mcq-/assess-<unitId>). + `getUnitsBySystem(system?)` و`getDistinctSystems()` لتغذية القوائم المنسدلة.
- **v15/v16 القراءة العميقة** (انظر §2): `recordConceptRead/conceptReadCount/conceptGatePassed/markGatePassed` · `getGateMcqForConcept/getMcqsForConcept` · `startFlowSession/endFlowSession/focusedSecondsOnDay/focusedMinutesRecent` · `logConfidence` · `getUnfinishedConcepts` · `averageSectionDwellSeconds`. ترحيل v15→v16 أعمدة ALTER ADD **تسامحية** (تتحقق وجود الجدول/العمود أولاً — لا تفشل على قواعد جزئية).

## 6) الشاشات المبنية (كلها موصولة وتعمل)
| الشاشة | الملف | ملاحظات |
|---|---|---|
| **قارئ الشروحات v3 (محرّك القراءة الكامل)** | `lib/src/features/curriculum/presentation/pages/concept_reader_page.dart` | **الأسبوعان 1+2+3 مدمجة**: بوابة تنفس 8 ثوان → بوابة سؤال+ثقة (إطار كهرماني «هنا كان خطؤك» على focus_sections) → لقطات بمراسي Atkinson → اعتراضية كل لقطتين (check>MCQ>استرجاع حر) → تثبيت ختامي → حارس خروج (بقيت N لقطات) → كاشف تصفح (زمن<40% من المتوسط → اعتراضية فورية) → تسجيل concept_reads + flow_sessions + XP concept |
| **بوابة الشرح** | `…/widgets/concept_gate_sheet.dart` | سؤال MCQ من أسئلة الشرح نفسه + مقياس ثقة 3 درجات → confidence_log · gate_passed عند الصواب الأول |
| **نقطة الاعتراض** | `…/widgets/interception_sheet.dart` | 3 مصادر: check مدمج (v2.1) · MCQ غير مستهلك · استرجاع حر «لخّص بثلاث نقاط» |
| **بوابة التنفس** | `…/widgets/breath_gate.dart` | 8 ثوان (4-2-2) — الزر لا يتفعل قبل اكتمال النفس |
| **حارس الجلسة** | `…/widgets/session_guard.dart` | بطاقة الحقيقة عند الخروج المبكر — «أكمل» هو الفعل الكبير |
| **كتل القراءة** | `…/pages/reading_blocks_page.dart` | غوصة 3–4 شروح متداخلة الأجهزة + كتلة معيارية — من شاشة اليوم · تختار غير المكتمل (Ovsiankina) |
| **دقائق التركيز** | `lib/src/features/progress/presentation/pages/focus_minutes_page.dart` | الرقم الكبير اليوم + رسم 7 أيام — مقياس الشمال فوق XP في «ملفي» |
| **إعدادات القراءة العميقة** | `lib/src/features/settings/presentation/pages/fixation_settings.dart` | مفتاح المراسي + قوة المرساة (30/40/60%) + معاينة حية بنص طبي |
| جلسة بطاقات SRS | `…/flashcard_session_page.dart` | قلب بطاقة + تقييم ذاتي (عرفتها/لم أعرفها) → يغذي Leitner + XP |
| جلسة MCQ | `…/mcq_session_page.dart` | **نمطان**: تدريب حر (مفتاح `mcq-`, SnackBar) **و`isAssessment: true` تقييم رسمي (مفتاح `assess-` + اجتياز 70% + شاشة ExamResultScreen الموحدة + مكافأة +20 XP بنوع assessment)** — التقييم يغذي الخط الزمني |
| مشغل الحالات OSCE | `…/clinical_case_player_page.dart` | vignette كامل + خطوات قرار + XP فوري (case_step) + debriefing |
| مراجعة اليوم | `…/daily_review_page.dart` | بطاقات SRS المستحقة عبر كل الوحدات (RoutePaths.dailyReview) |
| **راجع أخطاءك** | `…/mistakes_review_page.dart` | **جديدة**: تحليل حقيقي من corrections (mcq-+assess-+case-) — أسوأ الأسئلة + آخر إجابة خاطئة مقابل الصحيحة + ملخص إحصائي |
| شاشة الوحدة | `…/unit_screen.dart` | 4 أقسام موصولة: تعلّم(شروحات+بطاقات) · تدرّب(حالات+أسئلة) · اختبر(**تقييم رسمي isAssessment=true**) · راجع(MistakesReviewPage) — يمرر flashcardsDone وassessmentDone للأنشطة |
| **المسار v2 (system-based)** | `…/curriculum_page.dart` | **أُعيد بناؤها**: تجميع حسب `system` (أكورديون `SystemExpansionTile` بشريط تقدم دائري + خطي) · `ReorderableListView` موحدة (سحب محاضرة فوق ترويسة جهاز آخر = نقل) · زر عائم «ترتيب يدوي» يظهر مقابض السحب + زر نقل + **زر حذف** لكل محاضرة (`SystemLectureTile`) · **الحفظ فوري**: `applyUnitArrangement` معاملة ذرّية تكتب `order_index` (+ `system` عند النقل) — محفوظ عند إعادة التشغيل · **الحذف**: حوار تأكيد صريح ثم `deleteLectureData` (حذف متسلسل كامل — انظر §5) |
| اليوم/المسار/المكتبة/ملفي | today/curriculum/library/profile | المكتبة تفتح شاشات البنوك الجديدة (أسفل) |
| **بنوك المكتبة (فلترة ذكية)** | `lib/src/features/library/presentation/pages/{flashcard_bank, mcq_bank, case_bank, concept_library, flashcard_bank_session}_page.dart` + `widgets/bank_filter_panel.dart` | كل بنك بلوحة تحكم: قائمة **الجهاز** (system) + **المحاضرة** (تتحدث ديناميكياً حسب الجهاز) + **مبدل ترتيب** (منهجي/عشوائي SegmentedButton). بنك البطاقات فيه زر **«مراجعة عشوائية لما تمت دراسته»** يفتح FlashcardBankSessionPage (يغذي Leitner+XP كالجلسة العادية). أي تغيير فلتر يعيد الاستعلام فوراً |
| الأونبوردنغ | يختار التخصص (cardiology…) + هدف يومي | `LearnerProfile.setPlacementModule` |
| الإعدادات/نسخ احتياطي/تذكير | settings/backup/reminder | بلا TTS — النسخ الاحتياطي في مجلد `MedicineApp/Backups` |

## 7) بنية الأصول والهوية
- الخطوط: `Cairo` (عربي) + `Nunito` = `AppType.latinFamily` (مصطلحات) + **`AtkinsonHyperlegible` = `AppType.focusFamily`** (أجسام الشروحات — ملفان TTF بوزنين 400/700 في `assets/fonts/atkinson/`). أسماء النصوص: `AppType.termWord` (كان germanWord).
- ألوان التخصصات: `AppColors.module(module, brightness)` + `AppColors.moduleNameAr(module)` — 10 تخصصات بألوان مميزة. + `AppColors.focusText(b)` (رمادي 90% داكناً — نص القراءة).
- شارة التخصص: `ModuleBadge` (بدل CefrBadge — حُذفت نهائياً).
- `assets_manifest.dart`: أيقونات طبية (`unit_cardio`, `icon_concept`, `icon_case`, `icon_quiz`, `badge_case_master`…) — **ملفات PNG لأيقونات units/badge_case_master غير موجودة فعلياً** → تعمل الـ fallbacks (إيموجي). الموجودة فعلياً: badges القديمة، levels، empty، onboarding، بعض misc.
- pubspec v1.0.0+1 — أُزيلت flutter_tts/record/audioplayers. assets تشمل `assets/content/`.

## 8) المتبقي / مقترحات للجلسة القادمة
### خطة «محرّك القراءة العميقة» (3 أسابيع) — **كلها ✅ منجزة**:
- ✅ **الأسبوع 1**: تايبوغرافيا + مراسي + قارئ اللقطات + DB v15.
- ✅ **الأسبوع 2**: بوابة الشرح + الثقة + التمييز الكهرماني + الاعتراضيات + التثبيت الختامي + عقد v2.1.
- ✅ **الأسبوع 3**: كتل القراءة المتداخلة + بوابة التنفس + حارس الجلسة + كاشف التصفح + شاشة «دقائق التركيز».

### مرحلة تالية مقترحة (من وثيقة التركيز — «5+»):
1. **حجز الأخطاء عالية الثقة +24h/+7d** (Butler 2011): قراءة confidence_log (confidence=2 + was_correct=0) وحقنها فوق جدول SRS عند بناء مراجعة اليوم — البيانات تُجمع الآن تلقائياً من بوابة الثقة.
2. **Elo لكل مفهوم** (§2.2): ينتظر تراكم flow_sessions/concept_reads — البنية جاهزة.
3. **Ghost Patients** (§5.3): قرار تأليف محتوى — إما تأليفها أو توليدها من clinical_cases.
4. **جسر التلميح hints** في جلسات MCQ/الحالات: العمود hints_json جاهز في v16 — يحتاج UI للخيارات الثلاثة (70%/40%/10% XP — عوامل RewardEngine جاهزة للتوسيع).
5. **أصوات المكافأة** (اختياري): إعادة audioplayers بأصوات أصول <0.5s بلا كلمات — earcons مميزة، نفس فلسفة الضربة الحمراء.
6. **حقن ملفات المستخدم الحقيقية**: عبر «استيراد محاضرة» أو assets/MANIFEST ثم `flutter run`.
2. ~~شاشة "راجع أخطائي"~~ ✅ **أُنجزت** (`mistakes_review_page.dart` — موصولة بالقسم 3 في شاشة الوحدة).
3. ~~اختبار المحاضرة الكامل (assess-)~~ ✅ **أُنجز** (McqSessionPage بوضع `isAssessment: true` — يسجل `assess-<unitId>` الذي يقرأه الخط الزمني + شاشة نتيجة موحدة + +20 XP).
4. ~~استيراد المحاضرات من الجهاز~~ ✅ **أُنجز** (LectureImportService + LectureImportPage — قسم «المحتوى» في الإعدادات).
5. المكتبة تفتح أول وحدة فقط — يمكن إضافة منتقي وحدات.
6. أيقونات طبية PNG (unit_cardio… badge_case_master) — أو الاكتفاء بالإيموجي fallbacks.
7. على iOS/النشر: icon التطبيق ما زال app_icon.png القديم في assets/brand/icon — يحتاج تصميماً طبياً عند النشر.
8. (اختياري) معاينة مبدئية بعد الحقن: قد تحتاج أول فتح للتطبيق ~ثواني إضافية إذا كانت محاضرات كثيرة — الزرع يتم خلف شاشة البداية (unawaited).

## 9) ملفات مرجعية سريعة
- النماذج: `lib/src/core/database/{database_helper, srs_repository, content_seeder, motivation_repository, xp_event, user_progress, correction, answer_checker, writing_stats}.dart` — **user_progress/correction نُقلا من features/practice المحذوف إلى core/database** (كان الاستيراد القديم من practice — حدّث أي استيراد قديم).
- التلعيب: `lib/src/core/motivation/motivation_model.dart` (LearnerLevel · BadgeDef · MotivationSnapshot مع badgeStates()).
- الجذر: `MedicalLearningApp` في `lib/src/app/app.dart` (كان GermanLearningApp).
- الاختبارات: `test/{answer_checker, database_helper, srs, motivation, content_seeder, lecture_import_service, curriculum_reorder, lecture_delete, bank_queries, home_widget_payload, fixation_spans, deep_reading_v15, deep_reading_week23, **today_goals**}_test.dart` — الاختبارات الألمانية القديمة محذوفة كلياً.
- الأصول المحذوفة: كل الرسومات الألمانية (avatars/exam/units الألمانية) وdocs/content_a1_a2_*.md (18 ملف) — حُذفت.
- الراوتر: `lib/src/routing/app_router.dart` — المسارات: `/`, `/home`, `/progress`, `/settings`, `/reminder`, `/daily-review`, `/onboarding`, `/dev/*`. شاشات الوحدة/الجلسات عبر Navigator.push مباشر.
- **ويدجت الشاشة الرئيسية** (home_widget ^0.7 + workmanager): `lib/src/core/widget/home_widget_service.dart` — حمولة `due_cards`/`daily_progress`/`medical_tip` (computePayload نقية + sync للـ native). تحديث فوري من نهاية جلسات البطاقات/الأسئلة + عند الإقلاع. الضغط يفتح `medicineapp://daily-review` (widgetClicked/initiallyLaunched → go_router). Android: `MedicineHomeWidgetProvider.kt` + layout XML + values-night (داكن تلقائي) + WorkManager كل 6 ساعات (`MedicineApp.kt`). iOS: كود Swift جاهز في `ios/MedicineWidget/` — **تركيب الـ Extension Target + AppGroup من Xcode** (خطوات كاملة في `docs/WIDGET_SETUP.md`).

## 10) PROMPT جاهز للصق في المحادثة الجديدة
```
لديّ تطبيق Flutter (منصة الطب الباطني) في D:\medicineApp\medicine_app — أُعيد هيكلته بالكامل من تطبيق تعلم الألمانية. أكملتُ «محرّك القراءة العميقة» كاملاً (3 أسابيع: قارئ لقطات + بوابة شرح بثقة + اعتراضيات + كتل متداخلة + دقائق التركيز) — analyze صفر أخطاء و77 اختباراً ناجحاً. اقرأ docs/HANDOFF.md أولاً — يحتوي كل السياق: عقد البيانات Schema v2.0.0 + امتداد v2.1 الاختياري، طريقة الحقن عبر assets/content/ + MANIFEST.json + ContentSeeder، مخطط SQLite v16، والشاشات المبنية. المهمة الآن: [وصف المهمة الجديدة هنا].
```
