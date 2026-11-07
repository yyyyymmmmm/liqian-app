import SwiftData
import SwiftUI
import LiqianCore

@main
struct LiqianApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 全 App 固定中文区域：DatePicker 等系统控件跟随显示中文日期
                // （v2.4 必修：此前日期选择器显示 "Nov 7, 2026" 英文格式）
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .modelContainer(for: [Ledger.self, GiftRecord.self, ReminderDay.self, LedgerMember.self])
    }
}
