import Foundation
import WidgetKit
import LiqianCore

/// 小组件数据通道：把待回礼速览写进 App Group 的 UserDefaults，
/// Widget 扩展读同一份数据。结构定义在 Widget 文件里有一份镜像，改字段要两边同步。
enum WidgetSummaryWriter {
    /// suite 名走 AppGroupResolver（v4.6）：SideStore/AltSign 重签后真实组名
    /// 带 TeamID 后缀、写在 Info.plist 的 ALTAppGroups 里，硬编码原组名对不上
    static var suiteName: String { AppGroupResolver.groupID }
    static let summaryKey = "pendingSummary"
    static let quickRecordKey = "openQuickRecord"
    // —— 小组件数据自检（v5.11.1，见 docs/V5111-NOTES.md）——
    // 诊断元键与快照同 suite（写侧自报）；回执键由 Widget 在命中候选时
    // 写回（读侧自报），键名与 WidgetShared.SummaryStore 镜像，改键两边同步。
    static let diagWrittenAtKey = "widgetDiagWrittenAt"
    static let diagBytesKey = "widgetDiagBytes"
    static let diagReadbackKey = "widgetDiagReadbackOK"
    static let receiptGroupKey = "widgetReceiptGroup"
    static let receiptAtKey = "widgetReceiptAt"
    // standard 镜像键（suite 不可用/失败时自检行仍能显示「上次尝试」）
    static let mirrorAttemptAtKey = "widgetDiag.attemptAt"
    static let mirrorResultKey = "widgetDiag.result"
    static let mirrorGroupKey = "widgetDiag.group"
    static let mirrorWrittenAtKey = "widgetDiag.writtenAt"
    static let mirrorBytesKey = "widgetDiag.bytes"
    static let mirrorReadbackKey = "widgetDiag.readbackOK"

    /// 写入结果口径（镜像里的字符串值，自检行按此翻译成人话）
    enum DiagResult {
        static let ok = "ok"
        static let suiteNil = "suiteNil"
        static let encodeFailed = "encodeFailed"
    }
    // —— 分享导入（v4.5）：键与 LiqianShare 扩展的 ShareChannel 对齐，改键两边同步 ——
    /// 礼簿清单快照（扩展选目标礼簿用）
    static let ledgerListKey = "ledgerList"
    /// 分享暂存：扩展写、ContentView.checkShareImport 读后即清
    static let shareTextKey = "shareImportText"
    static let shareLedgerIDKey = "shareImportLedgerID"

    /// 礼簿清单快照项：只放 id/title/date，不带任何金额与记录
    struct LedgerListItem: Codable {
        var id: UUID
        var title: String
        var date: String
    }

    /// 写礼簿清单快照：顺序与入参一致（ContentView 传日期倒序，
    /// 第一本即最近一本，扩展默认选中它）
    static func writeLedgerList(ledgers: [Ledger]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(
                ledgers.map { LedgerListItem(id: $0.id, title: $0.title, date: $0.date) }
              ) else { return }
        defaults.set(data, forKey: ledgerListKey)
    }

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
        /// 全部往来人数（v5.1）：锁屏圆形组件环形进度的分母——待回人数占
        /// 全部往来人数之比；旧快照无此字段，Widget 解码为 nil 后降级无环版式
        var peopleCount: Int?
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
            nextReminder: nextReminder,
            peopleCount: people.count
        )
        // 可观测化（v5.11.1）：先记「尝试」，失败不再静默——原因落
        // UserDefaults.standard 镜像，设置页「小组件数据」自检行呈现；
        // 写入时机与 reload 口径不变（仍只在成功路径 reloadAllTimelines）。
        let attemptedAt = Date()
        let standard = UserDefaults.standard
        standard.set(attemptedAt.timeIntervalSince1970, forKey: mirrorAttemptAtKey)
        standard.set(suiteName, forKey: mirrorGroupKey)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            standard.set(DiagResult.suiteNil, forKey: mirrorResultKey)
            return
        }
        guard let data = try? JSONEncoder().encode(summary) else {
            standard.set(DiagResult.encodeFailed, forKey: mirrorResultKey)
            return
        }
        defaults.set(data, forKey: summaryKey)
        defaults.set(attemptedAt.timeIntervalSince1970, forKey: diagWrittenAtKey)
        defaults.set(data.count, forKey: diagBytesKey)
        // 写后立即回读：字节与刚写的完全一致才算命中
        let readbackOK = defaults.data(forKey: summaryKey) == data
        defaults.set(readbackOK, forKey: diagReadbackKey)
        standard.set(DiagResult.ok, forKey: mirrorResultKey)
        standard.set(attemptedAt.timeIntervalSince1970, forKey: mirrorWrittenAtKey)
        standard.set(data.count, forKey: mirrorBytesKey)
        standard.set(readbackOK, forKey: mirrorReadbackKey)
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

// MARK: - 小组件数据自检（v5.11.1：设置页「小组件数据」行的数据源）
//
// 设计原则：每个数字都来自真实探活/镜像，不推测。suite 读不到时用
// UserDefaults.standard 镜像兜底显示「上次尝试」，探活逐候选列明哪家
// 有数据——真机截图对着 docs/V5111-NOTES.md 的对照表即可定案子情形。
enum WidgetDiag {
    /// 单个候选组名的探活结果
    struct CandidateProbe {
        var groupID: String
        /// UserDefaults(suiteName:) 能否拿到（弱判据）
        var suiteAvailable: Bool
        /// containerURL 严口径（Share 扩展同款）：组在本进程配发里真存在
        var containerAvailable: Bool
        /// 这家 suite 里有 pendingSummary 数据
        var hasSummary: Bool
        var summaryBytes: Int
        /// 写侧在该 suite 里自报的写入时间（元键，可能缺失）
        var writtenAt: Date?
    }

    struct Status {
        /// App 侧解析出的组名全文
        var resolvedGroup: String
        var suiteAvailable: Bool
        var containerAvailable: Bool
        /// 最近一次尝试写入的时间（成功失败都算，从未尝试为 nil）
        var attemptAt: Date?
        /// 最近一次尝试结果：DiagResult 的值，从未尝试为 nil
        var result: String?
        /// 最近一次成功写入的时间/字节数/回读结论（镜像优先、suite 元键补）
        var writtenAt: Date?
        var bytes: Int
        var readbackOK: Bool?
        /// 全部候选的探活（顺序＝Widget 读取的尝试顺序）
        var probes: [CandidateProbe]
        /// 组件回执：Widget 实际命中的组名与回执时间（无回执为 nil）
        var receiptGroup: String?
        var receiptAt: Date?

        /// 设置页入口行的一句摘要
        var summaryLine: String {
            guard let result else { return "尚无写入记录，打开一次礼记后生成" }
            switch result {
            case WidgetSummaryWriter.DiagResult.ok:
                if let writtenAt {
                    return "最近写入 \(WidgetDiag.timeText(writtenAt)) · 回读\(readbackOK == true ? "命中" : "未命中")"
                }
                return "已写入"
            case WidgetSummaryWriter.DiagResult.suiteNil:
                return "数据通道不可用（组未建成或未配发）"
            case WidgetSummaryWriter.DiagResult.encodeFailed:
                return "最近一次写入编码失败"
            default:
                return "状态未知"
            }
        }
    }

    static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return "今天 \(f.string(from: date))"
        }
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }

    static func status() -> Status {
        let resolved = AppGroupResolver.groupID
        let standard = UserDefaults.standard
        func date(forKey key: String) -> Date? {
            let raw = standard.double(forKey: key)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
        }
        var writtenAt = date(forKey: WidgetSummaryWriter.mirrorWrittenAtKey)
        var bytes = standard.integer(forKey: WidgetSummaryWriter.mirrorBytesKey)
        var readbackOK: Bool? =
            standard.object(forKey: WidgetSummaryWriter.mirrorReadbackKey) as? Bool
        var probes: [CandidateProbe] = []
        var receiptGroup: String?
        var receiptAt: Date?
        for candidate in AppGroupResolver.candidateGroupIDs {
            let defaults = UserDefaults(suiteName: candidate)
            let data = defaults?.data(forKey: WidgetSummaryWriter.summaryKey)
            let probeWrittenAt: Date? = {
                guard let raw = defaults?.double(
                    forKey: WidgetSummaryWriter.diagWrittenAtKey), raw > 0
                else { return nil }
                return Date(timeIntervalSince1970: raw)
            }()
            probes.append(CandidateProbe(
                groupID: candidate,
                suiteAvailable: defaults != nil,
                containerAvailable: AppGroupResolver.containerAvailable(candidate),
                hasSummary: data != nil,
                summaryBytes: data?.count ?? 0,
                writtenAt: probeWrittenAt
            ))
            // 解析名这家的 suite 元键最权威，镜像缺失时用它补成功三元组
            if candidate == resolved, let defaults {
                if writtenAt == nil { writtenAt = probeWrittenAt }
                if bytes == 0 {
                    bytes = defaults.integer(forKey: WidgetSummaryWriter.diagBytesKey)
                }
                if readbackOK == nil {
                    readbackOK = defaults.object(
                        forKey: WidgetSummaryWriter.diagReadbackKey) as? Bool
                }
            }
            // 回执可能落在任一候选家里：Widget 命中的是哪家就写在哪家
            if receiptGroup == nil, let defaults,
               let group = defaults.string(forKey: WidgetSummaryWriter.receiptGroupKey) {
                receiptGroup = group
                let raw = defaults.double(forKey: WidgetSummaryWriter.receiptAtKey)
                receiptAt = raw > 0 ? Date(timeIntervalSince1970: raw) : nil
            }
        }
        return Status(
            resolvedGroup: resolved,
            suiteAvailable: UserDefaults(suiteName: resolved) != nil,
            containerAvailable: AppGroupResolver.containerAvailable(resolved),
            attemptAt: date(forKey: WidgetSummaryWriter.mirrorAttemptAtKey),
            result: standard.string(forKey: WidgetSummaryWriter.mirrorResultKey),
            writtenAt: writtenAt,
            bytes: bytes,
            readbackOK: readbackOK,
            probes: probes,
            receiptGroup: receiptGroup,
            receiptAt: receiptAt
        )
    }
}
