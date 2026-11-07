import WidgetKit

// MARK: - 小组件套件入口（v4.5）
// 待回礼（桌面三尺寸＋锁屏两款，kind 沿用 "LiqianWidget" 保住老用户已摆放的组件）
// ＋重要日子倒计时＋现场模式 Live Activity。共享底座在 WidgetShared.swift。
@main
struct LiqianWidgets: WidgetBundle {
    var body: some Widget {
        PendingWidget()
        ReminderWidget()
        SceneLiveActivityWidget()
    }
}
