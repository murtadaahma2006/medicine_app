# خطة إعادة الهيكلة — تقسيم DatabaseHelper إلى مستودعات

> الحالة الحالية: `lib/src/core/database/database_helper.dart` = **1831 سطراً** في كلاس واحد
> (singleton) يخلط: فتح/ترحيل القاعدة + 8 مجالات منطق مختلفة + استعلامات خام عامة.
> الهدف: تقسيمه إلى مستودعات (Repositories) بحدود واضحة مع **صفر كسر** للمستدعين الحاليين.

---

## المبدأ المعماري

```
DatabaseHelper (نواة رقيقة فقط)
 ├── فتح القاعدة + singleton + ترحيلات onCreate/onUpgrade (v14→v16)
 ├── أسماء الجداول الثابتة (tableXxx — تُشارك مع المستودعات)
 └── rawQueryParameterized / rawCount / transaction — منافذ عامة

المستودعات (تفتح عبر helper.database — لا تملك القاعدة):
 ContentRepository      → units/concepts/flashcards/mcqs/cases/steps (قراءة البنوك والفلترة)
 ProgressRepository     → user_progress + corrections (upsert/get/mistakes/weakest)
 MotivationRepository   → xp_events + unlocked_badges (موجودة أصلاً — تُبقى)
 SrsRepository          → srs_cards (موجودة أصلاً — تُبقى)
 DeepReadingRepository  → concept_reads/flow_sessions/confidence_log (v15/v16)
 LectureAdminRepository → deleteLectureData/applyUnitArrangement/unpin (كتابات إدارية)
```

## الخطوات (كل خطوة جذر مستقلة — قابلة للدمج بأمان)

| # | الخطوة | ملاحظات |
|---|---|---|
| 1 | **نقل الملف أولاً**: إنشاء `lib/src/core/database/repositories/` | مجلد فقط |
| 2 | **البدء بالأكبر**: نقل كل استعلامات المحتوى (getFlashcards/getMcqs/getCases/getStudiedFlashcards/getUnitsBySystem...) إلى `content_repository.dart` — ~350 سطراً | أكبر كتلة؛ المستدعون: بنوك المكتبة + الجلسات |
| 3 | نقل user_progress/corrections إلى `progress_repository.dart` — ~150 سطراً | يشمل finalizeSession |
| 4 | نقل concept_reads/flow_sessions/confidence_log إلى `deep_reading_repository.dart` — ~200 سطراً | مستدعون: قارئ الشروحات + كتل القراءة + دقائق التركيز |
| 5 | نقل deleteLectureData/applyUnitArrangement/togglePinned إلى `lecture_admin_repository.dart` — ~150 سطراً | معاملات ذرّية — تُنقل كما هي |
| 6 | نقل xp_events/unlockBadge إلى `motivation_repository.dart` الموجود | دمج لا إنشاء |
| 7 | **جسور توافق مؤقتة**: بعد كل نقل، تُبقى التوابع في DatabaseHelper كـ deprecated delegates تستدعي المستودع — ثم تُحذف بعد تحديث كل المستدعين | يمنع الكسر الكبير |
| 8 | **تحديث المستدعين تدريجياً**: شاشة بشاشة، ثم حذف الجسور | analyze بعد كل شاشة |

## القواعد الحافظة

- **لا تغيير SQL إطلاقاً** — نقل نصي حرفي (الاستعلامات مختبَرة 105 اختباراً).
- **لا singleton جديد لكل مستودع** — المستودعات عديمة الحالة (static أو كلاسات خفيفة) تأخذ `DatabaseHelper.instance.database` — نفس نمط SrsRepository/MotivationRepository الموجود.
- **أسماء الجداول الثابتة تبقى في DatabaseHelper** — المستودعات تستوردها (لا تكرار).
- **الاختبارات**: `test/database_helper_test.dart` وغيره تستدعي `openWith` — نواة الفتح تبقى؛ تُضاف اختبارات مستودع فقط إذا أضيف سلوك جديد.
- بعد اكتمال كل الخطوات: DatabaseHelper يجب أن ينحصر في ~350 سطراً (فتح + ترحيل + جداول + خام).

## لماذا هذا الترتيب؟

المحتوى (2) أولاً لأنه أكبر كتلة وأقل عرضة للكسر (قراءة فقط). الجسور (7) تجعل كل خطوة
قابلة للإصدار مستقلة — يمكن التوقف بعد أي خطوة والتطبيق يعمل بالكامل.

## الحالة: **خطة فقط** — لم يُنفَّذ أي نقل بعد. تنفَّذ في جلسة قادمة.
