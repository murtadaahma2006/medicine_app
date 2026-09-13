import WidgetKit
import SwiftUI

/// بيانات ويدجت الشاشة الرئيسية — منصة الطب الباطني.
///
/// تُقرأ من AppGroup UserDefaults (group.medicine_app.shared) —
/// نفس المفاتيح التي يكتبها Dart عبر home_widget:
/// due_cards / daily_progress / medical_tip / completed_today.
struct MedicineWidgetEntry: TimelineEntry {
    let date: Date
    let dueCards: Int
    let dailyProgress: Int
    let medicalTip: String
}

// MARK: - قراءة البيانات (AppGroup)

/// قراءة الحمولة من AppGroup UserDefaults.
struct PayloadReader {
    static let appGroupId = "group.medicine_app.shared"
    static let highDueThreshold = 15

    static func read() -> MedicineWidgetEntry {
        // AppGroup محدد عبر HomeWidget.setAppGroupId في Dart —
        // home_widget يكتب القيم في UserDefaults الخاصة بالمجموعة.
        let defaults = UserDefaults(suiteName: appGroupId)

        let due = defaults?.string(forKey: "due_cards").flatMap(Int.init) ?? 0
        let progress =
            defaults?.string(forKey: "daily_progress").flatMap(Int.init) ?? 0
        let tip = defaults?.string(forKey: "medical_tip") ?? ""

        return MedicineWidgetEntry(
            date: Date(),
            dueCards: due,
            dailyProgress: progress,
            medicalTip: tip
        )
    }
}

// MARK: - TimelineProvider (التحديث الخلفي)

struct MedicineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedicineWidgetEntry {
        MedicineWidgetEntry(
            date: Date(), dueCards: 8, dailyProgress: 40,
            medicalTip: "لا تعطِ Beta-blockers لمريض الربو"
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

// MARK: - تصميم الويدجت (Clean UI + داكن/فاتح تلقائي)

struct MedicineWidgetEntryView: View {
    var entry: MedicineWidgetEntry

    /// لون رقم المستحق: أحمر عند التراكم ≥ 15، أساسي خلافه.
    private var dueColor: Color {
        entry.dueCards >= PayloadReader.highDueThreshold
            ? Color(red: 0.84, green: 0.27, blue: 0.27)  // #D64545
            : Color(red: 0.11, green: 0.24, blue: 0.43)  // #1B3C6E
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── الرأس ──
            HStack(spacing: 6) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("منصة الطب الباطني")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 14) {
                // ── الرقم الكبير ──
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(entry.dueCards)")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(dueColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("بطاقة مستحقة اليوم")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                // ── الإنجاز اليومي ──
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: Double(entry.dailyProgress), total: 100)
                        .tint(Color(red: 0.24, green: 0.43, blue: 0.71))
                    Text("إنجاز اليوم: \(entry.dailyProgress)%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // ── المعلومة الطبية ──
            Text(
                entry.medicalTip.isEmpty
                    ? "افتح التطبيق لبدء المراجعة اليومية"
                    : entry.medicalTip
            )
            .font(.system(size: 12))
            .lineLimit(3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .description("عدد البطاقات المستحقة وإنجازك اليومي — والمعلومة الطبية.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
