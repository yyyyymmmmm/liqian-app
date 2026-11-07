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
        // 活礼谱（v4.2）：GuestSignature/VoiceBlessing 追加注册（合并注意：
        // 若 feat/icloud 等分支也改了这一行，以并集为准，勿互相覆盖）
        .modelContainer(for: [
            Ledger.self, GiftRecord.self, ReminderDay.self,
            GuestSignature.self, VoiceBlessing.self
        ])
    }
}
