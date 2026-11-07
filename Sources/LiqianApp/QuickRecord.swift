import AppIntents
import Foundation

/// 快捷指令「记一笔」：只负责把 App 唤起来记一笔，
/// 本身不写数据（金额姓名要在表单里当面填，避免误记）。
/// openAppWhenRun = true：perform 在 App 进程外先跑，只落一个标记，
/// ContentView 在 scenePhase 变 .active 时读标记弹出记一笔表单。
struct QuickRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "记一笔"
    static let description = IntentDescription("打开礼钱账本，记一笔新的人情往来。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WidgetSummaryWriter.suiteName)?
            .set(true, forKey: WidgetSummaryWriter.quickRecordKey)
        return .result()
    }
}

struct LiqianShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickRecordIntent(),
            phrases: ["用 \(.applicationName) 记一笔"],
            shortTitle: "记一笔",
            systemImageName: "square.and.pencil"
        )
    }
}
