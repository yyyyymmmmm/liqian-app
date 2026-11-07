import Foundation
import WidgetKit
import LiqianCore

/// 小组件数据通道：把待回礼速览写进 App Group 的 UserDefaults，
/// Widget 扩展读同一份数据。结构定义在 Widget 文件里有一份镜像，改字段要两边同步。
enum WidgetSummaryWriter {
    static let suiteName = "group.site.didichou.liqian"
    static let summaryKey = "pendingSummary"
    static let quickRecordKey = "openQuickRecord"

    struct PendingSummary: Codable {
        var pendingCount: Int
        var pendingAmountCents: Int
        /// 待回金额最大的一位（速览里点名提醒）
        var topName: String
        var updatedAt: Date
    }

    static func write(people: [PersonSummary]) {
        let pending = people.filter { $0.hasPending }
        let summary = PendingSummary(
            pendingCount: pending.count,
            pendingAmountCents: pending.reduce(0) { $0 + $1.pendingCents },
            topName: pending.max(by: { $0.pendingCents < $1.pendingCents })?.name ?? "",
            updatedAt: Date()
        )
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: summaryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
