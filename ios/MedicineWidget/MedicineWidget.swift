import WidgetKit
import SwiftUI

/// بيانات ويدجت الشاشة الرئيسية — منصة الطب الباطني (v19).
///
/// تُقرأ من AppGroup UserDefaults (group.medicine_app.shared) —
/// نفس المفاتيح التي يكتبها Dart عبر home_widget:
/// pinned_titles / pinned_count / clinical_pearl (+ المفاتيح القديمة).
struct MedicineWidgetEntry: TimelineEntry {
    let date: Date
    /// عناوين المحاضرات المثبتة غير المكتملة (سقف 3 من Dart).
    let pinnedTitles: [String]
    /// العدد الكلي للمثبتات (لعرض «+N أخرى» عند تجاوز السقف).
    let totalPinned: Int
    /// لؤلؤة اليوم — معلومة طبية ذهبية عشوائية.
    let clinicalPearl: String
    /// (مفتاحان قديمان — يبقيان للتوافق إن رجع التصميم لاحقاً)
    let dueCards: Int
    let dailyProgress: Int
}

// MARK: - قراءة البيانات (AppGroup)

/// قراءة الحمولة من AppGroup UserDefaults.
struct PayloadReader {
    static let appGroupId = "group.medicine_app.shared"

    static func read() -> MedicineWidgetEntry {
        // AppGroup محدد عبر HomeWidget.setAppGroupId في Dart —
        // home_widget يكتب القيم في UserDefaults الخاصة بالمجموعة.
        let defaults = UserDefaults(suiteName: appGroupId)

        // pinned_titles نص مدمج بـ " | " — عقد الإرسال من Dart.
        let titlesRaw = defaults?.string(forKey: "pinned_titles") ?? ""
        let titles = titlesRaw
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let totalPinnedFromTotal =
            defaults?.string(forKey: "pinned_total").flatMap(Int.init) ?? 0
        // توافق رجعي: بيانات مكتوبة قبل مفتاح pinned_total (v19.1)
        // كانت تعتمد pinned_count المساوٍ لطول القائمة المقطوعة.
        let totalPinnedLegacy =
            defaults?.string(forKey: "pinned_count").flatMap(Int.init) ?? 0
        let totalPinned = max(totalPinnedFromTotal, totalPinnedLegacy, titles.count)
        let pearl = defaults?.string(forKey: "clinical_pearl") ?? ""
        let due = defaults?.string(forKey: "due_cards").flatMap(Int.init) ?? 0
        let progress =
            defaults?.string(forKey: "daily_progress").flatMap(Int.init) ?? 0

        return MedicineWidgetEntry(
            date: Date(),
            pinnedTitles: Array(titles.prefix(3)),
            totalPinned: totalPinned,
            clinicalPearl: pearl,
            dueCards: due,
            dailyProgress: progress
        )
    }
}

// MARK: - TimelineProvider (التحديث الخلفي)

struct MedicineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedicineWidgetEntry {
        MedicineWidgetEntry(
            date: Date(),
            pinnedTitles: [
                "Heart Failure", "Asthma Management", "COPD Exacerbation"
            ],
            totalPinned: 4,
            clinicalPearl: "لا تعطِ Beta-blockers لمريض الربو",
            dueCards: 8,
            dailyProgress: 40
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (MedicineWidgetEntry) -> Void
    ) {
        completion(PayloadReader.read())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<MedicineWidgetEntry>) -> Void
    ) {
        let entry = PayloadReader.read()
        // تحديث خلفي: نظام iOS يعيد طلب التايملاين كل 6 ساعات
        // (إطار التجديد النظامي) — الدارت يحدّث القيم عند فتح
        // التطبيق وبعد كل نشاط فيتكفل home_widget بالباقي.
        let nextUpdate = Calendar.current.date(
            byAdding: .hour, value: 6, to: Date()
        )!
        let timeline = Timeline(
            entries: [entry],
            policy: .after(nextUpdate)
        )
        completion(timeline)
    }
}

// MARK: - تصميم الويدجت (جزآن: أهدافي + لؤلؤة اليوم)

struct MedicineWidgetEntryView: View {
    var entry: MedicineWidgetEntry

    /// لؤلؤة اليوم: مسحة كهرمانية خفيفة تناسب الفاتح/الداكن.
    private var pearlBackground: Color {
        Color(red: 0.98, green: 0.92, blue: 0.72).opacity(0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ══ الجزء العلوي: أهدافي ══
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("📌")
                        .font(.system(size: 12))
                    Text("أهدافي")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if entry.pinnedTitles.isEmpty {
                    // لا مثبتات — دعوة للتثبيت.
                    Text("لا محاضرات مثبتة — افتح التطبيق وثبّت")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    // سطر أول بارز ثم أسطر ثانوية.
                    ForEach(
                        Array(entry.pinnedTitles.enumerated()),
                        id: \.offset
                    ) { index, title in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(index == 0
                                    ? Color(red: 0.24, green: 0.43, blue: 0.71)
                                    : Color.secondary.opacity(0.4))
                                .frame(width: 5, height: 5)
                            Text(title)
                                .font(.system(
                                    size: index == 0 ? 13 : 11.5,
                                    weight: index == 0 ? .bold : .regular
                                ))
                                .foregroundStyle(
                                    index == 0 ? .primary : .secondary
                                )
                                .lineLimit(1)
                        }
                    }

                    // زيادة على السقف: «+N أخرى».
                    let extra = entry.totalPinned - entry.pinnedTitles.count
                    if extra > 0 {
                        Text("+ \(extra) أخرى")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .layoutPriority(1)

            // فاصل خفيف بين الجزأين.
            Divider().opacity(0.5)

            // ══ الجزء السفلي: لؤلؤة اليوم ══
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("💡")
                        .font(.system(size: 12))
                    Text("لؤلؤة اليوم")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text(
                    entry.clinicalPearl.isEmpty
                        ? "افتح التطبيق لتظهر لؤلؤتك الطبية الأولى"
                        : entry.clinicalPearl
                )
                .font(.system(size: 12, weight: .medium))
                .lineSpacing(2)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(8)
                .background(pearlBackground, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(14)
        .widgetBackground()
        // الضغط على الويدجت كله يفتح «المراجعة اليومية» — يصل Dart
        // عبر initiallyLaunchedFromHomeWidget/widgetClicked.
        .widgetURL(URL(string: "medicineapp://daily-review"))
    }
}

// خلفية متوافقة مع iOS 17+ (ContainerBackground) وقبله (Color).
extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        } else {
            background(Color(.systemBackground))
        }
    }
}

// MARK: - تعريف الويدجت

@main
struct MedicineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "MedicineWidget",
            provider: MedicineWidgetProvider()
        ) { entry in
            MedicineWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("منصة الطب الباطني")
        .description("محاضراتك المثبتة + لؤلؤة طبية كل يوم.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
