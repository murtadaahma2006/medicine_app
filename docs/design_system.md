# نظام التصميم — Deutsch Lernen

> المرجع الوحيد للهوية البصرية. أي فيتشر جديد يتبع هذا الملف حرفياً —
> لا لون/مسافة/مدة/زر خارج ما هو موثق هنا. بُني عبر المراحل 1–8
> (الهوية، التنقل، الوحدة، التمارين، التوقيعية، التحفيز، الداكن، الجرد).

## 1) المبادئ الحاكمة

1. **حدود لا ظلال** — كل سطح بحد 1px + ظل ناعم جداً. لا ظلال كبيرة أبداً.
2. **الألوان التعليمية مقدسة** — der أزرق / die أحمر / das أخضر وA0 أخضر / A1 كحلي / A2 بنفسجي. لغة تعلّمها المستخدم — لا تُغيَّر.
3. **طبقة عرض فقط** — الحركات والتنسيق في الشاشات؛ المنطق في المتحكمات. لا يتغير سلوك أي فيتشر.
4. **العربية RTL بخط Cairo، وكل ألمانية عبر Nunito + LTR** — لا ألماني خارج LTR أبداً (GermanText أو AppType.germanFamily).
5. **حركة محترمة** — 60fps، RepaintBoundary للمناطق المتحركة، لا حلقة أنيميشن على شاشة غير مرئية، واحترام `MediaQuery.disableAnimationsOf`.

## 2) Tokens — المصدر الوحيد (`lib/src/theme/tokens.dart`)

### الألوان (AppColors — فاتح / داكن)

| الرمز | الفاتح | الداكن | الاستخدام |
|---|---|---|---|
| `primary` | `#1B3C6E` | `#3E6DB5` | الأساسي الكحلي |
| `primaryTint` | `#E9F0FA` | `#1C2C46` | خلفية بطاقات/ترويسات لطيفة |
| `gold` | `#E8A33D` | `#F0B45A` | XP/سلسلة/شارات — **رسومات فقط** |
| `goldText` | `#8A5E10` | `#F0B45A` | XP/شارات **كنص** (AA على الخلفيتين) |
| `bg` | `#F6F8FB` | `#0F1520` | خلفية الصفحات |
| `surface` | `#FFFFFF` | `#1A2332` | بطاقات/أشرطة |
| `surfaceAlt` | `#EEF2F7` | `#232E42` | حقول/رقاقات داخل بطاقة |
| `text` | `#17202E` | `#EAF0F8` | نص أساسي |
| `textSecondary` | `#5B6879` | `#9AA7B8` | نص ثانوي |
| `border` | `#E3E9F0` | `#2C3A50` | الحد 1px الدائم |
| `success` / `successContainer` | `#1E8E4E` / `#E6F5EC` | `#4CC17E` / `#143524` | صحيح |
| `error` / `errorContainer` | `#D64545` / `#FBEAEA` | `#E46B6B` / `#3A1A1A` | خطأ |
| `der` / `die` / `das` | `#1565C0` / `#C62828` / `#2E7D32` | `#64B5F6` / `#EF9A9A` / `#81C784` | الأدوات المقدسة |
| `levelA0/A1/A2` (+Containers) | أخضر/كحلي/بنفسجي | نسخ فاتحة | CEFR |

**الوصول عبر دوال السطوع**: `AppColors.primary(b)`, `AppColors.gold(b)`… — `b = Theme.of(context).colorScheme.brightness`. لا تُستخدم قيم ثابتة في الشاشات.

**تباين AA محسوب**: أزواج النص/الخلفية كلها ≥4.5:1 في الوضعين (der/die/das وCEFR: 5.1–11:1). الاستثناء الوحيد: `gold` كنص على فاتح (2.16) — لذلك وُجد `goldText`.

### المسافات (AppSpacing) — شبكة 4

`xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · xxxl 32 · huge 48`
- `screenH` = هامش أفقي 20 (كل الشاشات)
- `card` = padding بطاقة 16
- `betweenCards` = 12 (فاصل البطاقات)

### الأنصاف (AppRadius)

`chip 12 · field 12 · card 16 · sheet 20 · pill 999`

### الحركة (AppMotion)

| المدة | القيمة | الاستخدام |
|---|---|---|
| `feedback` | 120ms | ردود فعل الأزرار (انكماش 0.97) |
| `standard` | 220ms | تغييرات الحالة |
| `transition` | 300ms | انتقالات الصفحات/الأسئلة |
| `celebration` | 500ms | دخول الاحتفالات |

المنحنيات: `popIn` (easeOutBack) للظهور المرح · `ease` (easeOutCubic) افتراضي · `out` (easeIn) للخروج.
مساعدات: `AppMotion.enabled(context)` و`AppMotion.scaled(context, d)` — **كل حركة تمر بهما**.

### الطباعة (AppType)

| النمط | الحجم/الوزن | الاستخدام |
|---|---|---|
| `screenTitle` | 24/700 Cairo | عناوين الشاشات |
| `cardTitle` | 19/700 Cairo | عناوين البطاقات |
| `body` | 15/400 Cairo | المتن |
| `caption` | 12.5/600 Cairo | تسميات صغيرة |
| `germanWord` | 34/800 **Nunito** | الكلمة الألمانية في البطاقات |

الخطوط: `AppType.arabicFamily = 'Cairo'` · `AppType.germanFamily = 'Nunito'`.

## 3) مكتبة المكونات (`lib/src/shared/widgets/` — استورد من `widgets.dart`)

| المكوّن | الدور | قواعد |
|---|---|---|
| **AppButton** | **كل زر في التطبيق** | primary/secondary/ghost/danger · loading · انكماش + haptic خفيف · `minHeight ≥ 48` |
| **AppCard** | كل بطاقة/سطح | حد 1px + ظل ناعم · `accent` شريط جانبي بلون CEFR · `onTap` اختياري |
| **GermanText** | كل نص ألماني | Nunito + LTR إجباري · `speakButton: true` يضيف 🔊 48px |
| **ArticleChip** | عرض الأداة الملوّنة | يستخرج der/die/das ويصبغها بألوانها المقدسة |
| **CefrBadge** | شارة A0/A1/A2 | بلون المستوى |
| **SectionHeader** | رأس قسم | مع شريط التوقيع الثلاثي (رمادي/أحمر/ذهبي) — التوقيع في العناوين الرئيسية والشعار فقط |
| **ProgressRing / ProgressBar / SegmentedProgressBar** | مؤشرات تقدم | تمتلئ بحركة (لا قفز) |
| **StatTile** | خلية إحصائية | أيقونة tint + قيمة + تسمية |
| **EmptyState** | حالة فراغ/خطأ | أيقونة + عنوان + وصف + زر — **بلا Center يدوي** |
| **AppSheet** | BottomSheet | مقبض سحب · `AppSheet.show()` موحدة |
| **FeedbackBanner** | تغذية كل تمرين | صحيح: أخضر ScaleIn + haptic خفيف · خطأ: أحمر يهتز + haptic قوي + الصواب Nunito LTR |
| **ExerciseScaffold** | هيكل كل جلسة تمرين | رأس إغلاق + شريط مجزأ → جسم → أسفل FeedbackBanner + زر |
| **ExerciseResultScreen / ExamResultScreen** | شاشات النتائج | حلقة + عدادات + كونفيتي ≥90% (واعٍ بالطابور) + رقاقة XP |
| **ConfettiBurst** | الكونفيتي الموحد | 120 جزيئاً · 2s · حارس static — **مشهد واحد في التطبيق** |
| **CelebrationHost** | طبقة التحفيز | انظر §5 |
| **StreakChip** | شريحة السلسلة 🔥 | نبض 1→1.06/2.4s عند streak>0 فقط |
| **TimerBadge** | شارة مؤقت الامتحان | تصفرّ آخر دقيقة |

## 4) قواعد Do / Don't

**Do:**
- `final b = Theme.of(context).colorScheme.brightness;` أول سطر في كل build
- هامش شاشة `AppSpacing.xl` · padding بطاقة `AppSpacing.card` · بين البطاقات `betweenCards`
- كل زر عبر AppButton · كل ألماني عبر GermanText/Nunito · كل لون عبر AppColors
- `RepaintBoundary` حول أي حلقة أنيميشن · `TickerMode` للألسنة المخفية
- كل تكرار قائمة طويلة عبر `ListView.builder/separated`
- tooltip لكل IconButton · semanticLabel للأيقونات التعليمية الحرجة

**Don't:**
- ❌ `Color(0x...)` أو `Colors.blue` في الشاشات (استثناء موثق واحد: ألوان علم ألمانيا في شعار Splash)
- ❌ Card/ElevatedButton/FilledButton خام (استثناء موثق: أزرار AlertDialog في backup_page)
- ❌ SnackBar للاحتفالات (عبر CelebrationHost فقط) — SnackBar مسموح للرسائل التقنية فقط (backup/pronunciation)
- ❌ نص ألماني بلا Nunito أو بلا LTR — حتى المدموج: افصل العربية عن الألمانية في Texts متجاورة
- ❌ ظل بلا حد · زر < 48px · حركة بلا `disableAnimations` check
- ❌ `fontSize:` خارج AppType (المقبول: تعديل copyWith لغرض صُغر موثق)
- ❌ `withOpacity` (المهجورة) — استخدم `withValues(alpha:)`

## 5) طبقة التحفيز (المرحلة 6)

- **CelebrationQueue** (مفردة): أحداث `XpGained` (خفيفة) و`BadgeEarned`/`LevelUp` (كبيرة، FIFO عبر `busy`).
- **Motivator.detectLevelUp(beforeXp, newBadgeIds:)**: تُستدعى من نقاط إنهاء الجلسات **داخل `_enqueue`** — تقارن `LearnerLevel.forXp` قبل/بعد.
- **CelebrationHost** في `MaterialApp.builder`: يستهلك الأحداث واحداً واحداً — **لا احتفالان فوق بعضهما أبداً**. رقاقات XP تعمل بالتوازي (واحدة في اللحظة).
- **AppHaptics** (`core/utils/`): `light` أزرار/صحيح · `celebrate` (متوسط) شارات/ترقية · `selection` قلب بطاقة/اختيار · `error` خطأ. لا استدعاء مباشر لـHapticFeedback.
- **sessionXp**: كل متحكم يقيس كسب جلسته الحقيقي (فرق `sumXp` حول الإنهاء) — شاشات النتائج تعرضه بدل قيم ثابتة.
- **تصدير الأحداث من المتحكمات**: بعد كل `addXpEvent` ناجح → `CelebrationQueue.instance.add(XpGained(n))`؛ عند الإنهاء → `Motivator.detectLevelUp(...)` ثم `notifyListeners()` أخيراً.

## 6) كتالوج الحركات

| الحركة | المواصفات | أين |
|---|---|---|
| انتقال صفحات | fade-through 300ms | كل 27 مساراً (pageBuilder موحد) |
| دخول سؤال جديد | fade + translate 8px، 220ms | ExerciseScaffold |
| نبضة صحيح | ScaleIn easeOutBack 500ms | FeedbackBanner |
| اهتزاز خطأ | sin(3·2π·t)·8·(1-t)، 420ms | FeedbackBanner |
| شريط تقدم الجلسة | يمتلئ بحركة بين الأسئلة | SegmentedProgressBar |
| قلب بطاقة 3D | دوران Y 0.9 راد + fade، 450ms | Flashcard |
| دخول متدرج | 30ms للعنصر (الوحدة) · 40ms للعمود (التقويم) | unit_screen/progress |
| رقاقة XP | تصعد 64px وتتلاشى، 900ms | XpChipView |
| بطاقة شارة | ScaleIn easeOutBack + تعتيم، 500ms | BadgeCard |
| رفع مستوى | إيموجي easeOutBack + كونفيتي | LevelUpView |
| وميض السلسلة | scale 1→1.06، 2.4s repeat | StreakChip |
| نبض «أنت هنا» | scale 1→1.18، 1.6s | TimelineUnitTile |
| كونفيتي | 120 جزيئاً، 2000ms، ألوان الهوية | ConfettiBurst |
| «يكتب…» | 3 نقاط تنبض، 600ms/سطر | dialogue_screen |

## 7) الوصولية

- تباين AA محسوب لكل أزواج النص/الخلفية (انظر §2) — خاصة der/die/das وCEFR في الداكن.
- كل عنصر تفاعلي ≥ **48px** منطقة لمس.
- tooltip لكل IconButton · semanticLabel للأيقونات · Semantics للأزرار الأيقونية الكبيرة (استماع).
- `MediaQuery.disableAnimationsOf` مسؤول في كل حركة — الحدث الاحتفالي يُستهلك بلا عرض عند التعطيل.

## 8) الأداء

- IndexedStack للألسنة الأربعة + `TickerMode(enabled: i == current)` — لا حلقة على لسان مخفي.
- RepaintBoundary: العقد النابضة، صفوف التقويم، الرقاقات الطافية، بطاقة السحب، الكونفيتي.
- القوائم الطويلة builder-based · البذور الثقيلة (1300+ مفردة) خلف Splash.
- const حيث أمكن · لا كائنات تُبنى في build دون داعٍ.

## 9) الاستثناءات الموثقة (كل ما خرج عن القواعد وسببه)

| الموضع | الاستثناء | السبب |
|---|---|---|
| `backup_page` | TextButton/FilledButton داخل AlertDialog | أزرار حوار نظام قياسية — AppButton مصمم للأزرار الرئيسية الممتدة، والحوار يحتاج أزرار نصية مضغوطة |
| `backup_page`/`pronunciation_compare_page` | SnackBar للرسائل التقنية | رسائل نتيجة عملية (نجاح/فشل ملف) — ليست احتفالات |
| خلايا التقويم `circular(4)` | نصف قطر أصغر من chips | خلية يوم 34px — نصف 12 سيبدو دائرة كاملة |
