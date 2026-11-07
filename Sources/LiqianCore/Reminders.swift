import Foundation

// MARK: - 人情提醒（v3.0）
// 两类本地通知：重要日子（生日/结婚纪念日/其他，公历或农历、每年重复）与
// 待回礼超期汇总。本文件只做纯计算（下一次日子、触发时刻、待回判定、
// 通知文案与排期），不碰 SwiftData 与 UNUserNotificationCenter——
// App 层 ReminderScheduler 把这里的计划翻译成系统通知请求。
// 文案纪律：只陈述事实，不煽情、不催债；标题恒为 App 名。

/// 一个提醒日子的纯值快照（ReminderDay 模型的镜像，供计算与单测）
public struct ReminderDayValue: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var person: String
    /// 关系（RelationCatalog 目录内的值：系统词表或用户自定义），未选为 ""
    public var relation: String
    /// 生日 / 结婚纪念日 / 其他
    public var kind: String
    /// 公历 / 农历
    public var calendarKind: String
    public var month: Int
    public var day: Int
    /// 提前天数：0（当天）/ 1 / 3 / 7
    public var leadDays: Int
    public var enabled: Bool
    public var note: String

    public init(
        id: UUID = UUID(),
        person: String,
        relation: String = "",
        kind: String,
        calendarKind: String,
        month: Int,
        day: Int,
        leadDays: Int = 3,
        enabled: Bool = true,
        note: String = ""
    ) {
        self.id = id
        self.person = person
        self.relation = relation
        self.kind = kind
        self.calendarKind = calendarKind
        self.month = month
        self.day = day
        self.leadDays = leadDays
        self.enabled = enabled
        self.note = note
    }

    public var isLunar: Bool { calendarKind == LiqianConstants.calendarLunar }
}

public enum ReminderMath {
    private static var gregorian: Calendar { Calendar(identifier: .gregorian) }

    /// 下一次日子（公历当天 0 点）：公历按年找；农历逐日换算（见 lunarNext）。
    /// from 当天若正是日子，返回当天（不跳到下一年）。
    public static func nextOccurrence(calendarKind: String, month: Int, day: Int, from: Date) -> Date {
        if calendarKind == LiqianConstants.calendarLunar {
            return lunarNext(month: month, day: day, from: from)
        }
        let cal = gregorian
        let start = cal.startOfDay(for: from)
        let year = cal.component(.year, from: start)
        for y in year...(year + 2) {
            let candidate = gregorianDate(year: y, month: month, day: day)
            if candidate >= start { return candidate }
        }
        return start // 理论不可达（两年内必有一次）
    }

    /// 公历某年月日（日超出当月天数时收敛到月末：2 月 29 日在平年按 2 月 28 日）
    private static func gregorianDate(year: Int, month: Int, day: Int) -> Date {
        let cal = gregorian
        var comps = DateComponents(year: year, month: month, day: 1)
        let first = cal.date(from: comps) ?? Date()
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        comps.day = min(max(day, 1), daysInMonth)
        return cal.date(from: comps) ?? first
    }

    /// 农历下一次：从 from 起逐日步进，用 .chinese 日历分量匹配月/日。
    /// 口径（与既有农历函数的行为一致，写进 V30-NOTES）：
    /// - 只认正月（isLeapMonth == false）：闰月里设的日子（现实中多为闰月出生）
    ///   按同名正月过；目标月当年是闰月时，正月在前、先命中正月。
    /// - 日为 30 而该农历月只有 29 天（小月）时，按该月最后一天（廿九）算。
    /// 农历一年最长约 385 天，步进上限 800 天足够覆盖「今年已过 → 明年」。
    private static func lunarNext(month: Int, day: Int, from: Date) -> Date {
        let cal = gregorian
        let chinese = Calendar(identifier: .chinese)
        var cursor = cal.startOfDay(for: from)
        for _ in 0..<800 {
            let c = chinese.dateComponents([.month, .day, .isLeapMonth], from: cursor)
            if c.month == month, c.isLeapMonth != true, let lunarDay = c.day {
                if lunarDay == day { return cursor }
                if lunarDay < day {
                    // 是否已到该月最后一天：看次日是否离开本月（换月或进闰月）
                    let next = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
                    let n = chinese.dateComponents([.month, .isLeapMonth], from: next)
                    if n.month != month || n.isLeapMonth == true {
                        return cursor // 小月无 30 日，按月末算
                    }
                }
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return cal.startOfDay(for: from) // 理论不可达
    }

    /// 触发时刻：日子当天往前推 leadDays 天，上午 9 点
    public static func fireDate(occurrence: Date, leadDays: Int) -> Date {
        let cal = gregorian
        let base = cal.date(byAdding: .day, value: -leadDays, to: cal.startOfDay(for: occurrence)) ?? occurrence
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }

    /// 距下一次日子还有几天（按自然日，from 当天命中为 0）
    public static func daysUntil(_ occurrence: Date, from: Date) -> Int {
        let cal = gregorian
        return cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: from),
            to: cal.startOfDay(for: occurrence)
        ).day ?? 0
    }

    /// 日子的人话注记：农历「农历十月初八」；公历「11月16日」
    public static func dateNote(calendarKind: String, occurrence: Date) -> String {
        if calendarKind == LiqianConstants.calendarLunar {
            return LiqianDate.lunarString(for: LiqianDate.string(from: occurrence))
        }
        let cal = gregorian
        return "\(cal.component(.month, from: occurrence))月\(cal.component(.day, from: occurrence))日"
    }
}

/// 一位待回礼已超期的人（判定结果，含事实字段供文案与单测）
public struct OverduePerson: Sendable, Equatable {
    public var name: String
    public var pendingCents: Int
    /// 最近一笔收礼日期 yyyy-MM-dd
    public var lastReceivedDate: String
    /// 截至 today 已收下多少天
    public var daysSince: Int

    public init(name: String, pendingCents: Int, lastReceivedDate: String, daysSince: Int) {
        self.name = name
        self.pendingCents = pendingCents
        self.lastReceivedDate = lastReceivedDate
        self.daysSince = daysSince
    }
}

/// 一条待排期的通知（App 层翻译成 UNNotificationRequest）
public struct PlannedNotification: Sendable, Equatable, Identifiable {
    public var identifier: String
    public var fireDate: Date
    public var title: String
    public var body: String

    public var id: String { identifier }

    public init(identifier: String, fireDate: Date, title: String, body: String) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

public enum ReminderPlanner {
    /// 通知标题恒为 App 名（不带营销词）
    public static let title = "礼钱账本"
    /// 重要日子通知标识前缀（App 层按前缀清理旧排期）
    public static let dayIdentifierPrefix = "liqian.reminder.day."
    /// 待回礼汇总通知标识前缀
    public static let pendingIdentifierPrefix = "liqian.reminder.pending."
    /// 系统待发通知上限 64，合并排期封顶留余量
    public static let maxPlanned = 60

    // MARK: - 重要日子

    /// 日子的通知正文：「3 天后是 大舅 的生日（农历十月初八）。」
    public static func dayBody(day: ReminderDayValue, occurrence: Date) -> String {
        let subject: String
        switch day.kind {
        case LiqianConstants.reminderBirthday:
            subject = "的生日"
        case LiqianConstants.reminderAnniversary:
            subject = "的结婚纪念日"
        default:
            subject = day.note.isEmpty ? "的重要日子" : "的\(day.note)"
        }
        let note = ReminderMath.dateNote(calendarKind: day.calendarKind, occurrence: occurrence)
        if day.leadDays <= 0 {
            return "今天是 \(day.person) \(subject)（\(note)）。"
        }
        return "\(day.leadDays) 天后是 \(day.person) \(subject)（\(note)）。"
    }

    /// 全部启用日子在未来 horizonMonths 内的排期：每人只排下一次
    /// （触发已过——如提前量大于距今天数——顺延到下一年那一次）。
    public static func planDays(_ days: [ReminderDayValue], now: Date, horizonMonths: Int = 12) -> [PlannedNotification] {
        let cal = Calendar(identifier: .gregorian)
        let horizonEnd = cal.date(byAdding: .month, value: horizonMonths, to: now) ?? now
        var planned: [PlannedNotification] = []
        for day in days where day.enabled {
            var occurrence = ReminderMath.nextOccurrence(
                calendarKind: day.calendarKind, month: day.month, day: day.day, from: now
            )
            var fire = ReminderMath.fireDate(occurrence: occurrence, leadDays: day.leadDays)
            var tries = 0
            while fire <= now, tries < 4 {
                let nextFrom = cal.date(byAdding: .day, value: 1, to: occurrence) ?? occurrence
                occurrence = ReminderMath.nextOccurrence(
                    calendarKind: day.calendarKind, month: day.month, day: day.day, from: nextFrom
                )
                fire = ReminderMath.fireDate(occurrence: occurrence, leadDays: day.leadDays)
                tries += 1
            }
            guard fire > now, fire <= horizonEnd else { continue }
            planned.append(PlannedNotification(
                identifier: dayIdentifierPrefix + day.id.uuidString,
                fireDate: fire,
                title: title,
                body: dayBody(day: day, occurrence: occurrence)
            ))
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - 待回礼

    /// 待回超期判定：待回金额 > 0（LedgerMath.people 口径）且距最近一笔
    /// 收礼已达到 thresholdDays 天（「超过 X 天未动」按达到 X 天起算）。
    /// 按超期天数倒序（最久的在前）。
    public static func overduePeople(
        from entries: [EntrySnapshot], thresholdDays: Int, today: Date
    ) -> [OverduePerson] {
        let cal = Calendar(identifier: .gregorian)
        let todayStart = cal.startOfDay(for: today)
        var lastReceived: [String: String] = [:]
        for e in entries where e.direction == LiqianConstants.received {
            if e.date > (lastReceived[e.person] ?? "") {
                lastReceived[e.person] = e.date
            }
        }
        var result: [OverduePerson] = []
        for person in LedgerMath.people(from: entries) where person.pendingCents > 0 {
            guard let last = lastReceived[person.name] else { continue }
            let days = cal.dateComponents(
                [.day],
                from: cal.startOfDay(for: LiqianDate.date(from: last)),
                to: todayStart
            ).day ?? 0
            if days >= thresholdDays {
                result.append(OverduePerson(
                    name: person.name,
                    pendingCents: person.pendingCents,
                    lastReceivedDate: last,
                    daysSince: days
                ))
            }
        }
        return result.sorted { $0.daysSince > $1.daysSince }
    }

    /// 某人在 slot 日那天的超期投影（假设此后没有新往来，纯日期推演）
    private static func projectedOverdue(
        from entries: [EntrySnapshot], thresholdDays: Int, on slotDate: Date
    ) -> [OverduePerson] {
        overduePeople(from: entries, thresholdDays: thresholdDays, today: slotDate)
    }

    /// 待回礼汇总排期：最多每月一条。首条时机——已有人超期则明天 9 点，
    /// 否则在最早一人达到超期那天 9 点；此后逐月一条，直到 horizon。
    /// 每条正文按其触发日投影的超期名单写（只陈述事实）。
    public static func planPendingReturns(
        from entries: [EntrySnapshot], thresholdDays: Int, now: Date, horizonMonths: Int = 12
    ) -> [PlannedNotification] {
        let cal = Calendar(identifier: .gregorian)
        let horizonEnd = cal.date(byAdding: .month, value: horizonMonths, to: now) ?? now
        let pending = LedgerMath.people(from: entries).filter { $0.pendingCents > 0 }
        guard !pending.isEmpty else { return [] }

        // 每人的「达到超期」日 = 最近收礼日 + thresholdDays
        var lastReceived: [String: String] = [:]
        for e in entries where e.direction == LiqianConstants.received {
            if e.date > (lastReceived[e.person] ?? "") {
                lastReceived[e.person] = e.date
            }
        }
        var crossingDates: [Date] = []
        for person in pending {
            guard let last = lastReceived[person.name] else { continue }
            let base = cal.startOfDay(for: LiqianDate.date(from: last))
            if let cross = cal.date(byAdding: .day, value: thresholdDays, to: base) {
                crossingDates.append(cross)
            }
        }
        guard let earliestCross = crossingDates.min() else { return [] }

        let todayStart = cal.startOfDay(for: now)
        var slotDay: Date
        if earliestCross <= todayStart {
            slotDay = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart // 已超期：明天
        } else {
            slotDay = earliestCross
        }

        var planned: [PlannedNotification] = []
        var index = 0
        while index < 12 {
            let fire = ReminderMath.fireDate(occurrence: slotDay, leadDays: 0)
            if fire > horizonEnd { break }
            if fire > now {
                let people = projectedOverdue(from: entries, thresholdDays: thresholdDays, on: slotDay)
                if !people.isEmpty {
                    planned.append(PlannedNotification(
                        identifier: pendingIdentifierPrefix + "\(index)",
                        fireDate: fire,
                        title: title,
                        body: pendingBody(people: people)
                    ))
                }
            }
            guard let next = cal.date(byAdding: .month, value: 1, to: slotDay) else { break }
            slotDay = next
            index += 1
        }
        return planned
    }

    /// 待回汇总正文：只报事实——谁、收下多少天、还没回；多人时点最久的一位＋余数。
    public static func pendingBody(people: [OverduePerson]) -> String {
        guard let first = people.first else { return "" }
        if people.count == 1 {
            return "\(first.name) 的礼已收下 \(first.daysSince) 天，还没回。"
        }
        return "\(first.name) 的礼已收下 \(first.daysSince) 天，还没回；另有 \(people.count - 1) 位亲友的礼也待回。"
    }

    // MARK: - 合并

    /// 全量排期：日子＋待回汇总，按时间合并排序并封顶
    public static func plan(
        days: [ReminderDayValue],
        entries: [EntrySnapshot],
        pendingEnabled: Bool,
        pendingThresholdDays: Int,
        now: Date,
        horizonMonths: Int = 12
    ) -> [PlannedNotification] {
        var all = planDays(days, now: now, horizonMonths: horizonMonths)
        if pendingEnabled {
            all += planPendingReturns(
                from: entries, thresholdDays: pendingThresholdDays,
                now: now, horizonMonths: horizonMonths
            )
        }
        return Array(all.sorted { $0.fireDate < $1.fireDate }.prefix(maxPlanned))
    }
}
