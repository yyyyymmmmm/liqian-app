import XCTest
@testable import LiqianCore

// MARK: - 人情提醒（v3.0）：调度计算与待回判定

final class ReminderTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    /// yyyy-MM-dd + 小时 → 本地时间（默认正午，避开 0 点边界）
    private func date(_ s: String, hour: Int = 12) -> Date {
        let base = LiqianDate.date(from: s)
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    private func ymd(_ d: Date) -> String { LiqianDate.string(from: d) }

    // MARK: 公历下一次

    func testGregorianBirthdayNext() {
        let next = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarGregorian, month: 11, day: 16,
            from: date("2026-11-07")
        )
        XCTAssertEqual(ymd(next), "2026-11-16")
        // 当天命中不跳年
        let sameDay = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarGregorian, month: 11, day: 16,
            from: date("2026-11-16", hour: 18)
        )
        XCTAssertEqual(ymd(sameDay), "2026-11-16")
        // 已过跳明年
        let nextYear = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarGregorian, month: 11, day: 16,
            from: date("2026-11-17")
        )
        XCTAssertEqual(ymd(nextYear), "2027-11-16")
    }

    func testGregorianFeb29FallsBackToFeb28() {
        let in2027 = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarGregorian, month: 2, day: 29,
            from: date("2026-03-01")
        )
        XCTAssertEqual(ymd(in2027), "2027-02-28") // 2027 平年，按 28 日
        let in2028 = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarGregorian, month: 2, day: 29,
            from: date("2027-03-01")
        )
        XCTAssertEqual(ymd(in2028), "2028-02-29") // 2028 闰年，用回 29 日
    }

    // MARK: 农历换算

    func testLunarBirthdayConversion() {
        // 已知锚点：2026-11-16 是农历十月初八（用户婚期）
        let next = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarLunar, month: 10, day: 8,
            from: date("2026-11-07")
        )
        XCTAssertEqual(ymd(next), "2026-11-16")
        XCTAssertEqual(LiqianDate.lunarString(for: ymd(next)), "农历十月初八")
    }

    func testLunarLeapYearUsesRegularMonth() {
        // 2025 年闰六月：六月十五应落在正六月（2025-06-25 为六月初一），
        // 不落进闰六月——闰月出生按正月过的口径。
        let next = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarLunar, month: 6, day: 15,
            from: date("2025-01-01")
        )
        XCTAssertEqual(ymd(next), "2025-07-09")
        let comps = Calendar(identifier: .chinese)
            .dateComponents([.month, .day, .isLeapMonth], from: next)
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.isLeapMonth, false)
    }

    func testLunarDay30FallsBackToMonthEndInSmallMonth() throws {
        // 在 2026 年内动态找一个只有 29 天的正月（小月），断言 30 日回退到 29 日
        let chinese = Calendar(identifier: .chinese)
        var cursor = date("2026-01-01", hour: 0)
        var smallMonth: (month: Int, firstDay: Date)?
        for _ in 0..<400 {
            let c = chinese.dateComponents([.month, .day, .isLeapMonth], from: cursor)
            if c.day == 1, c.isLeapMonth != true, let m = c.month {
                // 量这个月的长度
                var probe = cursor
                var length = 0
                while chinese.component(.month, from: probe) == m,
                      chinese.dateComponents([.isLeapMonth], from: probe).isLeapMonth != true {
                    length += 1
                    probe = cal.date(byAdding: .day, value: 1, to: probe) ?? probe
                    if length > 31 { break }
                }
                if length == 29 {
                    smallMonth = (m, cursor)
                    break
                }
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        let found = try XCTUnwrap(smallMonth, "2026 年应能找到一个 29 天的农历月")
        let next = ReminderMath.nextOccurrence(
            calendarKind: LiqianConstants.calendarLunar, month: found.month, day: 30,
            from: found.firstDay
        )
        let comps = chinese.dateComponents([.month, .day, .isLeapMonth], from: next)
        XCTAssertEqual(comps.month, found.month)
        XCTAssertEqual(comps.day, 29)
        XCTAssertEqual(comps.isLeapMonth, false)
    }

    // MARK: 触发时刻与文案

    func testDayPlanFireDateAndBody() {
        let day = ReminderDayValue(
            person: "大舅", kind: LiqianConstants.reminderBirthday,
            calendarKind: LiqianConstants.calendarLunar, month: 10, day: 8, leadDays: 3
        )
        let planned = ReminderPlanner.planDays([day], now: date("2026-11-07", hour: 10))
        XCTAssertEqual(planned.count, 1)
        let item = planned[0]
        let fire = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
        XCTAssertEqual(fire.year, 2026)
        XCTAssertEqual(fire.month, 11)
        XCTAssertEqual(fire.day, 13) // 十月初八（11-16）提前 3 天
        XCTAssertEqual(fire.hour, 9)
        XCTAssertEqual(fire.minute, 0)
        XCTAssertEqual(item.title, "礼记")
        XCTAssertEqual(item.body, "3 天后是 大舅 的生日（农历十月初八）。")
        XCTAssertTrue(item.identifier.hasPrefix(ReminderPlanner.dayIdentifierPrefix))
    }

    func testDayPlanSkipsDisabledAndMissedLead() {
        // 已停用不排
        let off = ReminderDayValue(
            person: "大舅", kind: LiqianConstants.reminderBirthday,
            calendarKind: LiqianConstants.calendarGregorian, month: 11, day: 16,
            leadDays: 3, enabled: false
        )
        XCTAssertTrue(ReminderPlanner.planDays([off], now: date("2026-11-07")).isEmpty)
        // 提前 7 天但日子只剩 2 天：今年这次触发已过，顺延到明年；
        // 明年触发 2027-11-02 距今 360 天、在 12 个月窗口内，应排出（原期望误算为窗口外，已纠正）
        let missed = ReminderDayValue(
            person: "大舅", kind: LiqianConstants.reminderBirthday,
            calendarKind: LiqianConstants.calendarGregorian, month: 11, day: 9, leadDays: 7
        )
        let planned = ReminderPlanner.planDays([missed], now: date("2026-11-07", hour: 10))
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.fireDate, date("2027-11-02", hour: 9))
    }

    // MARK: 待回判定与排期

    private func entriesFixture() -> [EntrySnapshot] {
        [
            EntrySnapshot(person: "张三", amountCents: 100_000,
                          direction: LiqianConstants.received, date: "2026-10-05"),
            EntrySnapshot(person: "李四", amountCents: 50_000,
                          direction: LiqianConstants.received, date: "2026-11-01"),
            EntrySnapshot(person: "王五", amountCents: 30_000,
                          direction: LiqianConstants.received, date: "2026-09-01"),
            EntrySnapshot(person: "王五", amountCents: 30_000,
                          direction: LiqianConstants.given, date: "2026-09-02"),
        ]
    }

    func testOverduePeople() {
        let overdue = ReminderPlanner.overduePeople(
            from: entriesFixture(), thresholdDays: 30, today: date("2026-11-07")
        )
        // 张三：待回 ¥1,000、收下 33 天 → 超期；李四只 6 天；王五已两清不算
        XCTAssertEqual(overdue.map(\.name), ["张三"])
        XCTAssertEqual(overdue.first?.daysSince, 33)
        XCTAssertEqual(overdue.first?.lastReceivedDate, "2026-10-05")
    }

    func testPendingPlanMonthlySummary() {
        let planned = ReminderPlanner.planPendingReturns(
            from: entriesFixture(), thresholdDays: 30, now: date("2026-11-07", hour: 10)
        )
        XCTAssertEqual(planned.count, 12) // 每月一条，排满 12 个月窗口
        let first = planned[0]
        let fire = cal.dateComponents([.year, .month, .day, .hour], from: first.fireDate)
        XCTAssertEqual(fire.year, 2026)
        XCTAssertEqual(fire.month, 11)
        XCTAssertEqual(fire.day, 8) // 已超期 → 明天 9 点首报
        XCTAssertEqual(fire.hour, 9)
        XCTAssertEqual(first.body, "张三 的礼已收下 34 天，还没回。")
        // 第二条在一个月后（李四届时也超期，正文变汇总口径）
        let second = planned[1]
        XCTAssertEqual(cal.component(.month, from: second.fireDate), 12)
        XCTAssertTrue(second.body.contains("另有 1 位亲友的礼也待回"))
        // 没人待回时不排
        XCTAssertTrue(ReminderPlanner.planPendingReturns(
            from: [], thresholdDays: 30, now: date("2026-11-07")
        ).isEmpty)
    }

    // MARK: 备份兼容

    func testBackupRemindersRoundTrip() throws {
        let day = ReminderDay(
            person: "大舅", relation: "亲戚", kind: LiqianConstants.reminderBirthday,
            calendarKind: LiqianConstants.calendarLunar, month: 10, day: 8,
            leadDays: 7, enabled: true, note: ""
        )
        let data = LiqianBackup.makeBackup(ledgers: [], records: [], reminders: [day])
        let parsed = try LiqianBackup.parseBackupFull(data)
        XCTAssertEqual(parsed.reminders.count, 1)
        let bd = try XCTUnwrap(parsed.reminders.first)
        XCTAssertEqual(bd.person, "大舅")
        XCTAssertEqual(bd.calendarKind, LiqianConstants.calendarLunar)
        XCTAssertEqual(bd.month, 10)
        XCTAssertEqual(bd.day, 8)
        XCTAssertEqual(bd.leadDays, 7)
        XCTAssertEqual(bd.id, day.id.uuidString)
    }

    func testOldBackupWithoutRemindersParsesEmpty() throws {
        let json = """
        {"ledgers":[{"id":"1730000000000000","title":"我的婚礼","type":"婚礼","date":"2026-11-16","note":""}],
         "records":[]}
        """
        let parsed = try LiqianBackup.parseBackupFull(Data(json.utf8))
        XCTAssertEqual(parsed.reminders.count, 0)
        XCTAssertEqual(parsed.ledgers.count, 1)
    }
}
