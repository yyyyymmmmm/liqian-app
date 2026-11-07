import XCTest
@testable import LiqianCore

final class LedgerMathTests: XCTestCase {
    private func entry(
        _ person: String,
        _ direction: String,
        _ cents: Int,
        _ date: String,
        status: String = "已送出",
        relation: String = "朋友",
        type: String = "婚礼"
    ) -> EntrySnapshot {
        EntrySnapshot(
            person: person,
            relation: relation,
            amountCents: cents,
            direction: direction,
            date: date,
            status: status,
            ledgerType: type
        )
    }

    // MARK: fmtMoney

    func testFmtMoney() {
        XCTAssertEqual(LedgerMath.fmtMoney(cents: 100_00), "¥100")
        XCTAssertEqual(LedgerMath.fmtMoney(cents: 100_50), "¥100.50")
        XCTAssertEqual(LedgerMath.fmtMoney(cents: 0), "¥0")
        XCTAssertEqual(LedgerMath.fmtMoney(cents: 5), "¥0.05")
        // 千分位（PRO-AUDIT §1.5）：万元整数、带分大额、负数
        XCTAssertEqual(LedgerMath.fmtMoney(cents: 1_000_000), "¥10,000")
        XCTAssertEqual(LedgerMath.fmtMoney(cents: 123_456_789), "¥1,234,567.89")
        XCTAssertEqual(LedgerMath.fmtMoney(cents: -1_000_000), "¥-10,000")
        XCTAssertEqual(LedgerMath.fmtMoney(cents: -100_50), "¥-100.50")
    }

    // MARK: displayString（界面日期显示定版：当年 M月d日 / 跨年 yyyy年M月d日）

    func testDisplayString() {
        XCTAssertEqual(LiqianDate.displayString(for: "2026-11-16", today: "2026-11-07"), "11月16日")
        XCTAssertEqual(LiqianDate.displayString(for: "2025-01-29", today: "2026-11-07"), "2025年1月29日")
        XCTAssertEqual(LiqianDate.displayString(for: "bad", today: "2026-11-07"), "bad")
    }

    func testSum() {
        let entries = [
            entry("A", "收礼", 100, "2025-01-01"),
            entry("A", "收礼", 250, "2025-01-02"),
        ]
        XCTAssertEqual(LedgerMath.sum(entries), 350)
    }

    // MARK: 差额（待送出不计）

    func testBalanceExcludesPendingSend() {
        let entries = [
            entry("张三", "收礼", 1000_00, "2025-01-01"),
            entry("张三", "随礼", 500_00, "2025-02-01", status: "待送出"),
        ]
        let people = LedgerMath.people(from: entries)
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people[0].received, 1000_00)
        XCTAssertEqual(people[0].given, 0)
        XCTAssertEqual(people[0].balance, 1000_00)
        XCTAssertEqual(people[0].count, 1) // 待送出不计笔数
        XCTAssertEqual(people[0].lastDate, "2025-02-01") // 但更新最近日期（同 Dart）
    }

    // MARK: 未回自动规则（FR-04.1）

    func testPendingOnlyReceived() {
        let people = LedgerMath.people(from: [
            entry("李四", "收礼", 600_00, "2025-03-01"),
        ])
        XCTAssertEqual(people[0].pendingCents, 600_00)
        XCTAssertTrue(people[0].hasPending)
    }

    func testPendingClearedByLaterSent() {
        let people = LedgerMath.people(from: [
            entry("李四", "收礼", 600_00, "2024-01-01"),
            entry("李四", "随礼", 600_00, "2024-06-01"),
        ])
        XCTAssertEqual(people[0].pendingCents, 0)
        XCTAssertFalse(people[0].hasPending)
    }

    func testPendingSendFirstThenReceive() {
        let people = LedgerMath.people(from: [
            entry("王五", "随礼", 500_00, "2024-01-01"),
            entry("王五", "收礼", 800_00, "2024-06-01"),
        ])
        XCTAssertEqual(people[0].pendingCents, 800_00)
    }

    func testPendingPartialSendThenReceiveAgain() {
        // 收 1000 → 送出 400 → 再收 300：规则按「最后一笔已送出之后」算，
        // 送出一次即把此前的未回清零，剩余未回只有后收的 300
        let people = LedgerMath.people(from: [
            entry("赵六", "收礼", 1000_00, "2024-01-01"),
            entry("赵六", "随礼", 400_00, "2024-02-01"),
            entry("赵六", "收礼", 300_00, "2024-03-01"),
        ])
        XCTAssertEqual(people[0].pendingCents, 300_00)
    }

    func testPendingNotClearedByPendingSend() {
        // 待送出不算「已送出」，不清未回
        let people = LedgerMath.people(from: [
            entry("赵六", "收礼", 600_00, "2024-01-01"),
            entry("赵六", "随礼", 600_00, "2024-02-01", status: "待送出"),
        ])
        XCTAssertEqual(people[0].pendingCents, 600_00)
    }

    // MARK: people 分组 / 排序 / relation

    func testPeopleGroupingCountAndLastDate() {
        let people = LedgerMath.people(from: [
            entry("张三", "收礼", 100_00, "2023-05-01"),
            entry("张三", "随礼", 100_00, "2025-01-02"),
            entry("李四", "收礼", 100_00, "2024-06-06"),
        ])
        XCTAssertEqual(people.count, 2)
        XCTAssertEqual(people.first?.name, "张三") // lastDate 最新排前
        let zhang = people.first { $0.name == "张三" }
        XCTAssertEqual(zhang?.count, 2)
        XCTAssertEqual(zhang?.lastDate, "2025-01-02")
        XCTAssertEqual(zhang?.balance, 0)
    }

    func testRelationFromLatestRecord() {
        let people = LedgerMath.people(from: [
            entry("张三", "收礼", 100_00, "2023-01-01", relation: "朋友"),
            entry("张三", "收礼", 100_00, "2025-01-01", relation: "亲戚"),
        ])
        XCTAssertEqual(people[0].relation, "亲戚")
    }

    // MARK: yearSummary

    func testYearSummaryExcludesPendingAndOtherYears() {
        let y = LedgerMath.yearSummary(from: [
            entry("A", "收礼", 100_00, "2025-01-01"),
            entry("A", "随礼", 40_00, "2025-02-01"),
            entry("A", "随礼", 999_00, "2025-03-01", status: "待送出"),
            entry("A", "收礼", 777_00, "2024-01-01"),
        ], year: "2025")
        XCTAssertEqual(y.recv, 100_00)
        XCTAssertEqual(y.given, 40_00)
        XCTAssertEqual(y.count, 2)
    }

    // MARK: typeSummary

    func testTypeSummary() {
        let types = LedgerMath.typeSummary(from: [
            entry("A", "收礼", 100_00, "2025-01-01", type: "婚礼"),
            entry("B", "收礼", 200_00, "2025-01-02", type: "婚礼"),
            entry("A", "随礼", 50_00, "2025-01-03", type: "白事"),
            entry("A", "随礼", 999_00, "2025-01-04", status: "待送出", type: "白事"),
        ])
        let wedding = types.first { $0.type == "婚礼" }
        let bai = types.first { $0.type == "白事" }
        XCTAssertEqual(wedding?.received, 300_00)
        XCTAssertEqual(wedding?.given, 0)
        XCTAssertEqual(wedding?.count, 2)
        XCTAssertEqual(bai?.given, 50_00) // 待送出 999 不计
        XCTAssertEqual(bai?.count, 1)
        XCTAssertEqual(types.first?.type, "婚礼") // 按收+随总额倒序
    }

    // MARK: 备份

    func testBackupRoundTrip() throws {
        let file = BackupFile(
            ledgers: [BackupLedger(id: "abc", title: "我的婚礼", type: "婚礼", date: "2026-11-16", note: "")],
            records: [BackupRecord(
                id: "r1", ledgerId: "abc", person: "张三", relation: "亲戚",
                amountCents: 100_00, direction: "收礼", method: "现金",
                note: "", date: "2026-11-16", returned: false, status: "已送出"
            )]
        )
        let data = try JSONEncoder().encode(file)
        let parsed = try LiqianBackup.parseBackup(data)
        XCTAssertEqual(parsed.ledgers.count, 1)
        XCTAssertEqual(parsed.ledgers.first?.title, "我的婚礼")
        XCTAssertEqual(parsed.records.first?.person, "张三")
        XCTAssertEqual(parsed.records.first?.amountCents, 100_00)
    }

    func testBackupDecodesFlutterShapeWithMissingOptionalFields() throws {
        // Flutter 旧导出：记录可能缺 status/returned/method，解码要兜底而不是整单失败
        let json = """
        {"ledgers":[{"id":"1730000000000000","title":"我的婚礼","type":"婚礼","date":"2026-11-16"}],
         "records":[{"id":"1730000000000001","ledgerId":"1730000000000000","person":"大舅","amountCents":100000,"direction":"收礼","date":"2026-11-16"}]}
        """
        let parsed = try LiqianBackup.parseBackup(Data(json.utf8))
        XCTAssertEqual(parsed.ledgers.first?.note, "")
        XCTAssertEqual(parsed.records.first?.status, "已送出")
        XCTAssertEqual(parsed.records.first?.returned, false)
        XCTAssertEqual(parsed.records.first?.relation, "朋友")
        XCTAssertEqual(parsed.records.first?.method, "现金")
        XCTAssertNil(parsed.records.first?.idUUID) // 时间戳 id 不是 UUID，导入时新发
    }

    // MARK: 关系分布（v1.1）

    func testRelationSummaryAggregatesAndExcludesPending() {
        let entries = [
            entry("张三", "收礼", 1000_00, "2025-01-01", relation: "亲戚"),
            entry("张三", "随礼", 500_00, "2025-02-01", relation: "亲戚"),
            entry("李四", "收礼", 300_00, "2025-03-01", relation: "朋友"),
            // 待送出不计入关系分布（金额与笔数都不算）
            entry("李四", "随礼", 900_00, "2025-04-01", status: "待送出", relation: "朋友"),
        ]
        let rels = LedgerMath.relationSummary(from: entries)
        XCTAssertEqual(rels.count, 2)
        // 按往来总额倒序：亲戚 1500 在前，朋友 300 在后
        XCTAssertEqual(rels[0].relation, "亲戚")
        XCTAssertEqual(rels[0].received, 1000_00)
        XCTAssertEqual(rels[0].given, 500_00)
        XCTAssertEqual(rels[0].total, 1500_00)
        XCTAssertEqual(rels[0].count, 2)
        XCTAssertEqual(rels[1].relation, "朋友")
        XCTAssertEqual(rels[1].total, 300_00)
        XCTAssertEqual(rels[1].count, 1)
    }

    func testRelationSummaryEmpty() {
        XCTAssertTrue(LedgerMath.relationSummary(from: []).isEmpty)
    }

    // MARK: 农历（v1.1）

    func testLunarString() {
        // 2026-11-16 是用户婚礼日，请柬口径：农历十月初八
        XCTAssertEqual(LiqianDate.lunarString(for: "2026-11-16"), "农历十月初八")
        // 2025 年春节：公历 1 月 29 日 = 正月初一
        XCTAssertEqual(LiqianDate.lunarString(for: "2025-01-29"), "农历正月初一")
        // 廿日名：2025-02-17 = 正月二十
        XCTAssertEqual(LiqianDate.lunarString(for: "2025-02-17"), "农历正月二十")
    }
}
