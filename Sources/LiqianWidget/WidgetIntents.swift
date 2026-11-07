import AppIntents
import Foundation

/// 组件内「记一笔」真按钮（iOS 17+ Button(intent:)）：
/// 与快捷指令的 QuickRecordIntent 同机制——perform 在 App 进程外先跑，
/// 只往 App Group 落一个标记并唤起 App（openAppWhenRun），App 回前台时
/// ContentView.checkQuickRecord 读标记弹出记一笔表单。
/// 键名与 App 侧 WidgetSummaryWriter 的 suiteName/quickRecordKey 镜像，改名两边同步。
struct OpenQuickRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "记一笔"
    static let description = IntentDescription("打开礼记，记一笔新的人情往来。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.site.didichou.liqian")?
            .set(true, forKey: "openQuickRecord")
        return .result()
    }
}
