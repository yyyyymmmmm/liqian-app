import Foundation
import WidgetKit
import LiqianCore

/// 小组件数据通道：把待回礼速览写进 App Group 的 UserDefaults，
/// Widget 扩展读同一份数据。结构定义在 Widget 文件里有一份镜像，改字段要两边同步。
enum WidgetSummaryWriter {
    static let suiteName = "group.site.didichou.liqian"
    static let summaryKey = "pendingSummary"
    static let quickRecordKey = "openQuickRecord"

    /// 待回礼前列一位（中/大尺寸列表行与锁屏组件用）
    struct PendingPerson: Codable {
        var name: String
        var pendingCents: Int
    }

    /// 下一个重要日子（倒计时组件用）：occurrence 为下一次日子的公历当天 0 点，
    /// 剩余天数由 Widget 侧按当天日期现算，快照隔夜也不会显错数。
    struct NextReminder: Codable {
        /// 展示标题，如「大舅的生日」（subject 口径与 ReminderMath.dayBody 一致）
        var title: String
        var person: String
        var occurrence: Date
    }

    struct PendingSummary: Codable {
        var pendingCount: Int
        var pendingAmountCents: Int
        /// 待回金额最大的一位（速览里点名提醒）
        var topName: String
        var updatedAt: Date
        // —— v4.5 小组件套件扩展：全部可选 ——
        // 旧版 App 写的快照没有这些字段，Widget 解码为 nil 后降级到旧版式；
        // 新版 App 写的快照被旧版 Widget 读时多余字段被忽略。双向兼容。
        /// 待回礼前 5 位（按待回金额降序）
        var pendingTop: [PendingPerson]?
        /// 本月收礼合计（分；与速览同源：全部记录口径，与旧字段一致）
        var monthReceivedCents: Int?
        /// 本月随礼合计（分；只计已送出，待送出不算，口径同 PersonSummary.given）
        var monthGivenCents: Int?
        /// 下一个重要日子（没有启用中的日子时为 nil）
        var nextReminder: NextReminder?
    }

    static func write(
        people: [PersonSummary],
        monthReceivedCents: Int,
        monthGivenCents: Int,
        nextReminder: NextReminder?
    ) {
        let pending = people.filter { $0.hasPending }
        let sorted = pending.sorted { $0.pendingCents > $1.pendingCents }
        let summary = PendingSummary(
            pendingCount: pending.count,
            pendingAmountCents: pending.reduce(0) { $0 + $1.pendingCents },
            topName: sorted.first?.name ?? "",
            updatedAt: Date(),
            pendingTop: sorted.prefix(5).map {
                PendingPerson(name: $0.name, pendingCents: $0.pendingCents)
            },
            monthReceivedCents: monthReceivedCents,
            monthGivenCents: monthGivenCents,
            nextReminder: nextReminder
        )
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: summaryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 下一个重要日子：全部启用日子中下一次 occurrence 最早的一个（与提醒排期
    /// 同一 ReminderMath.nextOccurrence 口径，农历在 Core 内逐日换算）。
    static func nextReminder(from days: [ReminderDayValue], now: Date = Date()) -> NextReminder? {
        var best: (day: ReminderDayValue, occurrence: Date)?
        for day in days where day.enabled {
            let occ = ReminderMath.nextOccurrence(
                calendarKind: day.calendarKind, month: day.month, day: day.day, from: now
            )
            if best == nil || occ < best!.occurrence { best = (day, occ) }
        }
        guard let best else { return nil }
        let subject: String
        switch best.day.kind {
        case LiqianConstants.reminderBirthday:
            subject = "的生日"
        case LiqianConstants.reminderAnniversary:
            subject = "的结婚纪念日"
        default:
            subject = best.day.note.isEmpty ? "的重要日子" : "的\(best.day.note)"
        }
        return NextReminder(
            title: "\(best.day.person)\(subject)",
            person: best.day.person,
            occurrence: best.occurrence
        )
    }
}
