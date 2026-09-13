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
الويدجت يستعمل `widgetURL` مع `medicineapp://daily-review` (home_widget يعترضه — **لا تحتاج تسجيل scheme يدوياً**، لكن لضمان عمله من حالة الإقلاع البارد):
1. `Runner → Info` → **URL Types** → أضف:
   - Identifier: `com.medicineapp`
   - URL Schemes: `medicineapp`

### د) النشر
- Builda التطبيق عادي (`flutter build ios`) — الـ Extension يُبنى تلقائياً معه.
- جهاز الاختبار: أضف الويدجت من معرض الويدجتس (اضغط مطولاً على الشاشة الرئيسية → + → ابحث «منصة الطب الباطني»).

---

## 3) كيف تعمل البيانات (العقد الموحد)

| المفتاح | Dart (الكاتب) | Android (القارئ) | iOS (القارئ) |
|---|---|---|---|
| `due_cards` | `HomeWidgetService.keyDueCards` | `prefs.getString("due_cards")` | `defaults.string(forKey: "due_cards")` |
| `daily_progress` | `keyDailyProgress` | `"daily_progress"` | `"daily_progress"` |
| `medical_tip` | `keyMedicalTip` | `"medical_tip"` | `"medical_tip"` |
| `completed_today` | `keyCompletedToday` | (احتياطي) | (احتياطي) |

- **التحديث الفوري**: بعد كل إجابة بطاقة/إنهاء جلسة (flashcard_session / mcq_session / bank_session) → `HomeWidgetService.refresh()`.
- **عند فتح التطبيق**: `main.dart` يستدعي `refresh()`.
- **الخلفية**: Android = WorkManager كل 6 ساعات (يبث لـ HomeWidgetBackgroundReceiver) · iOS = TimelinePolicy `.after(6h)` + `WidgetCenter.reloadTimelines`.
- **الضغط**: `medicineapp://daily-review` → `initiallyLaunchedFromHomeWidget` (إقلاع بارد) أو `widgetClicked` (تطبيق حي) → `go_router.go('/daily-review')`.

## 4) التحقق
- اختبارات Dart: `test/home_widget_payload_test.dart` (4 اختبارات — الحمولة النقية).
- لاختبار التحديث الخلفي في أندرويد: `adb shell am broadcast -a es.antonborri.home_widget.action.BACKGROUND -n com.example.medicine_app/.MedicineWidgetWorker` أو انتظر دورة WorkManager.
