import SwiftUI

/// ملف دعم عند الضغط على الويدجت: يفتح التطبيق عبر widgetURL
/// medicineapp://daily-review — يصل Dart عبر
/// initiallyLaunchedFromHomeWidget/widgetClicked فيوجّه go_router.
///
/// الخيار الأنظف: ضبط widgetURL على الويدجت كله في MedicineWidget.swift
/// (انظر widgetURL في EntryView) — هذا الملف يجمع إعدادات النقرة
/// والتحديث الخلفي (reloadTimelines).

import WidgetKit

enum WidgetBridge {
    static let appGroupId = "group.medicine_app.shared"
    static let dailyReviewURL = URL(string: "medicineapp://daily-review")!

    /// يطلب من نظام iOS إعادة بناء تايملاين الويدجت — يستدعيه native
    /// عند التغييرات الخلفية (يستعمله home_widget تلقائياً بعد
    /// updateWidget من Dart، ونضيفه هنا للتحديث الخلفي الإضافي).
    static func reloadTimeline() {
        WidgetCenter.shared.reloadTimelines(
            ofKind: "MedicineWidget"
        )
    }
}
