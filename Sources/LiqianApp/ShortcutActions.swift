import Foundation
import UIKit

extension Notification.Name {
    /// 长按快捷菜单已被点选（AppDelegate 写入标记后广播，ContentView 立即消费）
    static let liqianShortcutAction = Notification.Name("liqianShortcutAction")
}

/// 主屏长按快捷菜单（v4.5）：静态项在 Project.swift 的 UIApplicationShortcutItems
/// 声明（记一笔 / 查看待回礼），这里是唯一承接点。
///
/// 通道设计与小组件/快捷指令保持一致——不新造路径：
/// - 记一笔：写 App Group 的 quickRecordKey 标记（与 QuickRecord Intent、
///   小组件「记一笔」按钮同一条通道），ContentView 的 checkQuickRecord 消费，
///   隐私锁与无礼簿守卫都在那一侧，本处不重复判断。
/// - 查看待回礼：写 standard defaults 标记，ContentView 消费后切「往来」Tab
///   （待回礼汇总在该页）；隐私锁定时 ContentView 不承接（消费即丢弃，
///   与 liqian://person 深链的锁定口径一致）。
enum ShortcutActions {
    /// 与 Project.swift 中 UIApplicationShortcutItemType 字面量一一对应，改一处必改两处
    static let recordType = "site.didichou.liqian.shortcut.record"
    static let pendingType = "site.didichou.liqian.shortcut.pending"

    /// 查看待回礼的待消费标记（standard defaults）
    static let pendingTabKey = "shortcutShowPending"

    static func handle(_ item: UIApplicationShortcutItem) {
        switch item.type {
        case recordType:
            UserDefaults(suiteName: WidgetSummaryWriter.suiteName)?
                .set(true, forKey: WidgetSummaryWriter.quickRecordKey)
        case pendingType:
            UserDefaults.standard.set(true, forKey: pendingTabKey)
        default:
            return
        }
        NotificationCenter.default.post(name: .liqianShortcutAction, object: nil)
    }

    /// 消费「查看待回礼」标记：读到为 true 时清掉并返回 true（只消费一次）
    static func consumePendingTab() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: pendingTabKey) else { return false }
        defaults.set(false, forKey: pendingTabKey)
        return true
    }
}

/// 仅为承接快捷菜单而设的轻量 AppDelegate：SwiftUI 生命周期没有对应的
/// 系统回调，冷启动的 launchOptions.shortcutItem 与运行时的 performActionFor
/// 都只能从这里进。两条路都只落到 ShortcutActions.handle，不持有任何状态。
final class LiqianAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 冷启动点快捷项：此时界面未就绪，只写标记，
        // ContentView 出现后在 .task 里统一消费（与小组件标记同一时机）
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            ShortcutActions.handle(item)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        ShortcutActions.handle(shortcutItem)
        completionHandler(true)
    }
}
