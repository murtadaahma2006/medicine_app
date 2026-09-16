## خطة: تسليط الضوء + حاشية ملاحظة داخل النص (Inline Highlight & Annotate)

### السياق المعتمد
شاشة العرض هي `concept_reader_page.dart` — الجسم يُعرض عبر `_ShotContent` (StatelessWidget) مغلّفاً بـ `SelectionArea`، ويبني الـ body عبر `Text.rich(TextSpan(children: buildAnchoredSpans(...)))`. كل `_Shot` يحمل `conceptId` و`body`. الإصدار Flutter 3.29. قاعدة البيانات الآن v21.

الهدف: تحديد سطر/نص، إرفاق ملاحظة به، تمييزه (أصفر فاتح)، وعند النقر عليه تُعرض الملاحظة (نمط Kindle/Apple Books). بلا ملاحظة واحدة سفلية.

### 1) قاعدة البيانات — جدول `inline_notes` (+ ترحيل v22)
- رفع `databaseVersion` من `21` إلى `22`.
- جدول جديد (في `_onCreate` + كتلة `if (oldV < 22)` في `_onUpgrade` بنمط CREATE TABLE IF NOT EXISTS):
  ```sql
  CREATE TABLE inline_notes (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    concept_id     TEXT NOT NULL REFERENCES concepts(id) ON DELETE CASCADE,
    selected_text  TEXT NOT NULL,
    personal_note  TEXT NOT NULL,
    color_code     TEXT,               -- اختياري (مستقبلي لألوان التمييز)
    created_at     TEXT NOT NULL
  );
  CREATE INDEX idx_inline_notes_concept ON inline_notes(concept_id);
  ```
- ثابت `tableInlineNotes = 'inline_notes'`.

**دوال CRUD** داخل `DatabaseHelper` (parameterized):
- `addInlineNote({conceptId, selectedText, personalNote, colorCode?})` → INSERT، يرجع id.
- `deleteInlineNote(int id)` → حذف (اختياري لاحقاً).
- `getInlineNotesForConcept(String conceptId)` → قائمة صفوف `inline_notes` مرتبة بـ id.

### 2) أداة تحويل النص → TextSpans مع التمييز (دالة نقية جديدة)
ملف جديد `lib/src/features/curriculum/presentation/widgets/inline_note_spans.dart`:
- `List<InlineNoteSpan> buildInlineNoteSpans(String text, List<InlineNote> notes, TextStyle base, {void Function(InlineNote)? onTap})`.
- تكرار نصي (scan) لتقسيم `text` إلى مقاطع: كل مقطع إمّا عادي أو مطابق `selected_text` لأحد الملاحظات (مطابقة حساسة، مع تعامل مع التكرارات عبر فهرس).
- المقطع المطابق يُلبس `TextStyle(backgroundColor: Color(0xFFFFF3B0))` (أصفر فاتح) + `TapGestureRecognizer` يستدعي `onTap(note)`.
- يدعم تعدد الملاحظات ونفس النص المكرر.
- **مع دمج المراسي**: سأجعل الأداة تنتج نصاً موحداً يحافظ على خط focusFamily — التمييز يضاف فوق `base` (نمط المرساة مطبّق خارجياً). الفصل: المراسي تُبني أولاً على المقاطع العادية، والتمييز يغلفها. (تفصيل تنفيذي في الكود — أحافظ على buildAnchoredSpans القائم للقراءة الأولى، والملاحظات تُدمج في كلا الوضعين.)

### 3) قائمة السياق المخصصة على `SelectionArea`
في `_ShotContent.build` — تخصيص `SelectionArea(contextMenuBuilder: ...)`:
- `contextMenuBuilder` يبني `SelectableRegionState` بإضافة `ContextMenuButtonItem(label: 'إضافة ملاحظة', onPressed: ...)` إلى `state.contextMenuButtonItems`، ويعيد القائمة عبر `AdaptiveTextSelectionToolbar.buttonItems`.
- في `onPressed`: `final sel = selectableRegionState.getSelectedContent()?.plainText` → يمسك النص المحدد، يُجمع نص `shot.body`/`heading` للتأكد أنه داخل المنطقة... ثم يستدعي callback for المعالج الخارجي.
- **تمرير المعالج**: `_ShotContent` يتلقى callback `onAddNote(String selectedText)` للرفع إلى `_ConceptReaderPageState` (الذي يملك `conceptId` الحالي والـ DB). يُطوّر.

### 4) دمج في `_ShotContent` (تحميل + عرض)
- `_ConceptReaderPageState` عند بناء الشوت الحالي (و`_load`) يستدعي `getInlineNotesForConcept(shot.conceptId)` ويخزّن `_notes` للحقل التفاعل الحالي.
- `_ShotContent` يتلقى `notes` + `onTapNote(InlineNote)`.
- نص `body` يُبنى الآن عبر `buildInlineNoteSpans(...)` مع خلفية صفراء للملاحظات ومقبض نقر.
- **عند النقر على نص مميَّز**: callback → يعرض `showModalBottomSheet` (عبر `AppSheet`) تعرض `personal_note` + النص المحدد المصوّر، مع زر حذف إن أردنا.

### 5) الشيت: إضافة ملاحظة
- `onAddNote(selectedText)`: يفتح `showModalBottomSheet` (نمط AppSheet) بحقل نص للملاحظة + زر حفظ.
- عند الحفظ: `addInlineNote(...)` ثم إعادة تحميل الملاحظات للشوت الحالي (setState) → يظهر التمييز فوراً.

### خارج النطاق (سأقرّر في الكود، هذه قيود):
- التمييز يُطبق على `body` الواقعي لكل شوت (لا على heading/keyPoints/keyTerms) — يكفي كنموذج Kindle.
- `color_code` مخزّن لكن بلا منتقي ألوان الآن (مستقبلي) — القيمة null/أصفر ثابت.
- لن ألمس محرك القراءة/الاعتراضيات/المراسي إلا للدمج اللازم فقط.

### الاختبارات
- `test/inline_notes_test.dart` (نمط database_helper_test):
  - الجدول يُنشأ (المخطط v22).
  - `addInlineNote` يخزن و`getInlineNotesForConcept` يجلبها بمعرف المفهوم.
  - الترحيل v21→v22 يُضيف الجدول (أنماط migration).
  - أداة `buildInlineNoteSpans`: نص بلا ملاحظات يُعاد كما هو؛ ملاحظة مطابقة تُلبس خلفية اصفر؛ نص مكرر يُعالَج؛ المقاطع العادية غير المميّزة تبقى.

### التحقق النهائي
`flutter analyze` (نطاقي نظيف؛ الموجودة بالفعل lecture_template_service غير ملتزم غير تابع لي) + `flutter test` (134+ اختبار) — تأكد أن الملفات المعطوبة مسبقة الوجود تُستثنى إن بقيت.

ملاحظة تقنية: أنا مقيّد بتخصيص قائمة سياق `SelectionArea` المتوفر في Flutter 3.29 (`contextMenuBuilder` + `state.getSelectedContent()`)، وهو المسلك الرسمي — لا حلول خارجية/غير مدعومة.