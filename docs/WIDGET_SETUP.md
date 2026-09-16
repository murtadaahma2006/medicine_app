# تركيب ويدجت الشاشة الرئيسية (Home Screen Widget)

> ويدجت تفاعلية تعرض: عدد البطاقات المستحقة اليوم (`due_cards`) ·
> الإنجاز اليومي (`daily_progress`) · معلومة طبية سريعة (`medical_tip`).
> الضغط عليها يفتح «المراجعة اليومية» مباشرة. تحديث خلفي كل ~6 ساعات.

**حالة الكود في هذا المشروع:**
- ✅ Dart: `lib/src/core/widget/home_widget_service.dart` (الحمولة + المزامنة + الخلفية) — مكتمل ومُختبر (4 اختبارات).
- ✅ Android: كل الملفات مكتوبة (Provider + XML + Manifest + WorkManager) — جاهزة للبناء مباشرة.
- ✅ iOS: كود Swift/WidgetKit جاهز في `ios/MedicineWidget/` — لكن **إنشاء الـ Extension Target يتم من Xcode** (لا يمكن تعديل project.pbxproj يدوياً بشكل موثوق من ويندوز).

---

## 1) Android — لا شيء إضافي، كل شيء جاهز

الملفات المكتوبة:
| الملف | الدور |
|---|---|
| `android/app/src/main/kotlin/com/example/medicine_app/MedicineHomeWidgetProvider.kt` | قراءة البيانات من SharedPreferences (مفاتيح Dart نفسها) وبناء RemoteViews |
| `android/app/src/main/kotlin/com/example/medicine_app/MedicineApp.kt` | تسجيل مهمة WorkManager الدورية (كل 6 ساعات) |
| `android/app/src/main/res/layout/medicine_home_widget.xml` | تصميم الويدجت (رقم كبير + شريط تقدم + معلومة) |
| `android/app/src/main/res/drawable/widget_background.xml` | زوايا مستديرة 20dp + حد 1px |
| `android/app/src/main/res/values/colors.xml` + `values-night/widget_colors.xml` | الوضعان الفاتح/الداكن تلقائياً |
| `android/app/src/main/res/xml/medicine_home_widget_info.xml` | مواصفات الويدجت (4×2، قابل للتحجيم) |
| `AndroidManifest.xml` | تسجيل `<receiver>` + `android:name=".MedicineApp"` |
| `build.gradle.kts` | `androidx.work:work-runtime-ktx` للتحديث الخلفي |

**للاختبار:** `flutter run` على جهاز أندرويد → اضغط مطولاً على الشاشة الرئيسية → Widgets → اسحب «منصة الطب الباطني».

**ملاحظة:** `android:label` في Manifest لا يزال «تعلّم الألمانية» (قديم) — غيّره عند النشر إلى «منصة الطب الباطني».

---

## 2) iOS — خطوات Xcode (مرة واحدة على جهاز Mac)

الويدجت في iOS تحتاج **Extension Target** منفصلاً لا يمكن إضافته إلا من Xcode:

### أ) إنشاء الـ Widget Extension
1. افتح `ios/Runner.xcworkspace` في Xcode.
2. `File → New → Target… → Widget Extension` → اسمه **`MedicineWidget`** (بالضبط — نفس `iosWidgetName` في Dart).
3. اللغة: **Swift**، واجهة: **SwiftUI Configuration**. ☑️ **Include Configuration Intent** غير مطلوب (StaticConfiguration يكفي).
4. Xcode سينشئ ملفات قالب — **استبدل محتوى `MedicineWidget.swift`** بملفنا في `ios/MedicineWidget/MedicineWidget.swift` (اسحب الملف للمشروع أو انسخ محتواه).
5. احذف ملفات القالب الزائدة إن وُجدت، وأضف `ios/MedicineWidget/WidgetBridge.swift` للـ Target نفسه.

### ب) إعداد AppGroup (مشاركة البيانات)
1. Apple Developer Portal (أو Xcode → Signing & Capabilities):
   أنشئ App Group باسم: **`group.medicine_app.shared`** (حرفياً — نفس `appGroupId` في Dart).
2. **للـ Runner (التطبيق الرئيسي)**: Target Runner → Signing & Capabilities → `+ Capability` → **App Groups** → أضف `group.medicine_app.shared`.
3. **للـ MedicineWidget (الـ Extension)**: نفس الخطوة — أضف الـ App Group نفسه.

> home_widget يكتب بياناته في `UserDefaults(suiteName: "group.medicine_app.shared")` — نفس المعرف في `PayloadReader` داخل ملف Swift.

### ج) URL Scheme (Deep Link)
الويدجت يستعمل `widgetURL` مع `medicineapp://daily-review`:
1. `Runner → Info` → **URL Types** → أضف:
   - Identifier: `com.medicineapp`
   - URL Schemes: `medicineapp`
> **مهم**: التسجيل ضروري فعلاً — بدونه لا يستجيب iOS لفتح `medicineapp://` (v19.1: مضاف فعلاً في `ios/Runner/Info.plist` عبر `CFBundleURLTypes` — تحقق منه فقط إن أعاد Xcode توليد الملف).

### د) النشر
- Builda التطبيق عادي (`flutter build ios`) — الـ Extension يُبنى تلقائياً معه.
- جهاز الاختبار: أضف الويدجت من معرض الويدجتس (اضغط مطولاً على الشاشة الرئيسية → + → ابحث «منصة الطب الباطني»).

---

## 3) كيف تعمل البيانات (العقد الموحد)

| المفتاح | Dart (الكاتب) | Android (القارئ) | iOS (القارئ) | العرض في v19 |
|---|---|---|---|---|
| `pinned_titles` | `keyPinnedTitles` | `prefs.getString("pinned_titles")` | `defaults.string(forKey: "pinned_titles")` | أسطر «أهدافي» (سقف 3) |
| `pinned_count` | `keyPinnedCount` | (احتياطي — طول القائمة المقطوعة) | fallback رجعي لـ `pinned_total` | — |
| `pinned_total` | `keyPinnedTotal` | `prefs.getString("pinned_total")` | `defaults.string(forKey: "pinned_total")` | عدّاد «+N أخرى» |
| `clinical_pearl` | `keyClinicalPearl` | `prefs.getString("clinical_pearl")` | `defaults.string(forKey: "clinical_pearl")` | «لؤلؤة اليوم» |
| `due_cards` | `HomeWidgetService.keyDueCards` | (احتياطي v1) | (احتياطي v1) | لا يُعرض حالياً |
| `daily_progress` | `keyDailyProgress` | (احتياطي v1) | (احتياطي v1) | لا يُعرض حالياً |
| `medical_tip` | `keyMedicalTip` | (احتياطي v1) | (احتياطي v1) | لا يُعرض حالياً |
| `completed_today` | `keyCompletedToday` | (احتياطي) | (احتياطي) | — |

**عقد v19.1 (تحديث الإصلاحات):**
- **عدّاد «+N أخرى»**: `pinned_total` = إجمالي المثبتات غير المكتملة **بلا سقف** (`countPendingPinnedLectures`) — لا تخلطه مع `pinned_count` (طول قائمة العناوين المقطوعة بـ 3). Native يحسب الزائد عن `MAX_LINES=3`.
- **حد اليوم محلي**: أحداث اليوم تُحصى منذ منتصف الليل **بتوقيت الجهاز** (كانت UTC فتتصفر العدادات 3 فجراً بتوقيت UTC+3).
- **تحصين الفواصل**: عنوان محاضرة يحوي `|` يُستبدل بـ `⁄` قبل الدمج كي لا ينشق سطر «أهدافي» خطياً.
- **نقرة الإقلاع البارد**: نية تسجَّل في `HomeWidgetService` إذا وصلت قبل جهوزية الراوتر، وتستهلكها شاشة البداية (`consumePendingNavigation`) فتوجّه للمراجعة اليومية بدل وجهتها الافتراضية — بعد التهيئة الأولى فقط. بعدها (`markStartupFinished`) النقرات توجيه فوري.
- **تحديث عند التثبيت/الفك**: `curriculum_page._togglePin` + `concept_reader._finish` (فك التثبيت التلقائي) يستدعيان `refresh()` — «أهدافي» في الويدجت تتغير لحظياً.
- **Android manifest**: `HomeWidgetBackgroundReceiver` + `HomeWidgetBackgroundService` مصرَّحان في manifest التطبيق (بدونهما بث التحديث الخلفي لا يصل أحداً — تصريح الحزمة نفسها فارغ).

- **التحديث الفوري**: بعد كل إجابة بطاقة/إنهاء جلسة (flashcard_session / mcq_session / bank_session / concept_reader) + عند تثبيت/فك تثبيت محاضرة → `HomeWidgetService.refresh()`.
- **عند فتح التطبيق**: `main.dart` يستدعي `refresh()`.
- **الخلفية**: Android = WorkManager كل 6 ساعات (يبث لـ HomeWidgetBackgroundReceiver) · iOS = TimelinePolicy `.after(6h)` + `WidgetCenter.reloadTimelines`.
- **الضغط**: `medicineapp://daily-review` → `initiallyLaunchedFromHomeWidget` (إقلاع بارد — عبر نية شاشة البداية) أو `widgetClicked` (تطبيق حي) → `go_router.go('/daily-review')`. iOS يتطلب `CFBundleURLTypes` في Info.plist (مسجل فعلاً).

## 4) التحقق
- اختبارات Dart: `test/home_widget_payload_test.dart` (11 اختباراً — الحمولة النقية + العدد الكلي + تحصين الفواصل + استهلاك النية المعلّقة).
- لاختبار التحديث الخلفي في أندرويد: `adb shell am broadcast -a es.antonborri.home_widget.action.BACKGROUND -n com.example.medicine_app/es.antonborri.home_widget.HomeWidgetBackgroundReceiver` أو انتظر دورة WorkManager.
