import Foundation
import UserNotifications
import LiqianCore

/// 人情提醒的系统通知薄封装（v3.0）：排期计算全在 Core 的 ReminderPlanner，
/// 这里只做三件事——查/请求授权、把计划翻译成 UNNotificationRequest、
/// 数据或设置变化时全量重排（先清本 App 提醒前缀的旧请求，再按新计划添加）。
/// 设置存 UserDefaults（与 MeView 的 @AppStorage 同键）。
enum ReminderScheduler {
    static let pendingEnabledKey = "pendingReminderEnabled"
    static let pendingDaysKey = "pendingReminderDays"
    static let defaultPendingDays = 30

    static var pendingEnabled: Bool {
        UserDefaults.standard.bool(forKey: pendingEnabledKey)
    }

    static var pendingDays: Int {
        let v = UserDefaults.standard.integer(forKey: pendingDaysKey)
        return v > 0 ? v : defaultPendingDays
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 请求授权，返回是否已授权（系统只真正弹窗一次，之后直接返回现状）
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorizationStatus() == .authorized
    }

    /// 全量重排：清掉旧的提醒请求，按 Core 计划重新添加未来 12 个月的触发。
    /// 未授权时调用也安全（请求加得上但不投递，下次授权后启动校准会重排）。
    static func reschedule(days: [ReminderDayValue], snapshots: [EntrySnapshot]) {
        let planned = ReminderPlanner.plan(
            days: days,
            entries: snapshots,
            pendingEnabled: pendingEnabled,
            pendingThresholdDays: pendingDays,
            now: Date()
        )
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ours = requests
                .map(\.identifier)
                .filter {
                    $0.hasPrefix(ReminderPlanner.dayIdentifierPrefix)
                        || $0.hasPrefix(ReminderPlanner.pendingIdentifierPrefix)
                }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            let cal = Calendar(identifier: .gregorian)
            for item in planned {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                let comps = cal.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: item.fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(
                    identifier: item.identifier, content: content, trigger: trigger
                ))
            }
        }
    }
}
