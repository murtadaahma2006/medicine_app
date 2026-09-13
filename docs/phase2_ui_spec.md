# المرحلة الثانية — مواصفة الواجهات والبنية (معتمدة v1)

> مرجع التنفيذ الرسمي لمهندس الواجهات. أي خروج عن هذه المواصفة يحتاج اعتماد المنسّق أولاً.

## 1) هيكل المجلدات المستهدف

```
lib/
├── main.dart                      (كما هو — لا تغيير جوهري)
└── src/
    ├── app/
    │   └── app.dart               MaterialApp.router — يبقى نقطة الدخول
    ├── core/
    │   ├── theme/
    │   │   ├── app_colors.dart    لوحة الألوان (Flat Design)
    │   │   ├── app_spacing.dart   مقياس التباعد ونصف الأقطار
    │   │   ├── app_typography.dart أنواع النصوص + fontFamily مركزي
    │   │   └── app_theme.dart     ThemeData.light/dark (نقل من src/theme/)
    │   └── layout/
    │       ├── breakpoints.dart   ثوابت نقاط التوقف
    │       └── responsive_scaffold.dart غلاف التجاوب المشترك
    ├── routing/
    │   └── app_router.dart        StatefulShellRoute + مسارات التفاصيل
    └── features/
        ├── learn/      تبويب التعلم (الدروس)
        ├── cards/      تبويب البطاقات
        ├── quiz/       تبويب الاختبار
        ├── stats/      تبويب الإحصائيات
        ├── dictionary/ تبويب القاموس
        └── splash/     شاشة البداية (خارج الـ Shell)
```

- كل ميزة: `presentation/pages/` الآن، وعند الحاجة لاحقاً `domain/` و`data/`.
- حذف `src/theme/` القديمة بعد النقل، وحذف `features/home` و`features/progress` بعد دمجهما (استبدال نظيف — لا مستخدمون بعد).

## 2) نظام الثيم

- **Flat Design**: بلا ظلال ثقيلة، ارتفاعات عبر اللون والحدود، نصف أقطار موحدة.
- **نصف الأقطار** (AppSpacing): صغير 8 · متوسط 12 · كبير 16 · دائري كامل للأزرار الحبّية.
- **مقياس التباعد**: أساس 4px → 4, 8, 12, 16, 24, 32, 48.
- **الألوان** (Flat): Primary أزرق-نيلي هادئ مناسب للتعلم، Secondary أخضر للنجاح، سطح محايد فاتح/داكن، Error أحمر قياسي. تُعرَّف كأسماء دلالية (primary, onPrimary, surface, background...) وليس كألوان خام داخل الشاشات.
- **الثيمين معاً من اليوم الأول**: ThemeData.light + ThemeData.dark، useMaterial3: true.
- **الخطوط**: fontFamily واحد مركزي في AppTypography (افتراضي مؤقت)، وعند إضافة TTF لاحقاً يتغير سطر واحد فقط.

## 3) الاتجاه والتجاوب

- **RTL افتراضي** للتطبيق كله؛ مقاطع النص الألماني داخل البطاقات `<Directionality ltr>` أو `TextDirection.ltr` على مستوى العنصر فقط.
- **نقاط التوقف** (Breakpoints): `<600` هاتف عمود واحد · `600–840` لوح عمودان/شبكة · `≥840` عرض موسع مع حد أقصى لعرض المحتوى 640–720 مُتوسَّط.
- الغلاف الموحد `ResponsiveScaffold` يلف محتوى كل تبويب ويقرر الشبكة/العمود.

## 4) التنقل — StatefulShellRoute.indexedStack

| # | التبويب | المسار | الأيقونة المقترحة |
|---|---------|--------|--------------------|
| 1 | تعلم | `/learn` | school_outlined |
| 2 | بطاقات | `/cards` | style_outlined (أو crop_square) |
| 3 | اختبار | `/quiz` | quiz_outlined |
| 4 | إحصائيات | `/stats` | insights_outlined |
| 5 | قاموس | `/dictionary` | menu_book_outlined |

- شريط سفلي Material 3 `NavigationBar` داخل الـ Shell فقط، بحالة محفوظة لكل فرع (IndexedStack).
- **خارج الـ Shell (بلا شريط سفلي — وضع تركيز)**:
  - `/lesson/:lessonId` — شاشة الدرس
  - `/cards/review/:deckId` — جلسة مراجعة بطاقات
  - `/quiz/session/:setId` — جلسة اختبار فعليّة
  - `/settings` — تُفتح من أيقونة الترس في AppBar بتبويبي "تعلم" و"إحصائيات"
  - `/` — splash كما هو
- RoutePaths يبقى مصدر الحقيقة الوحيد + دوال البناء الآمنة ذات المعاملات.

## 5) معايير القبول لكل تسليم

1. `flutter analyze` → صفر مشاكل.
2. تحديث `test/smoke_test.dart`: يتحقق من الـ 5 تبويبات والتنقل بينها.
3. لا ألوان/تباعد خام داخل الشاشات — كل شيء من core/theme.
4. تجاوب فعلي: لا overflow على 360×640 ولا على عرض لوح 800.
5. تسليم المرحلة = تقرير موجز + قائمة ملفات فقط (قاعدة المستخدم الدائمة).

## 6) ترتيب التنفيذ عند إشارة الانطلاق

1. نقل/بناء core/theme + core/layout.
2. تحويل app_router إلى StatefulShellRoute بهياكل صفحات فارغة (Scaffolds).
3. تعبئة الشاشات الخمس بمحتوى Placeholder منظم (هيكل حقيقي، بيانات ثابتة).
4. تحديث الاختبارات + تحليل نهائي + تقرير.
