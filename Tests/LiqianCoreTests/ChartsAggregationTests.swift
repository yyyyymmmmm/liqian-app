import XCTest
@testable import LiqianCore

/// v4.7 图表补全聚合：月度净额/累计、金额分桶、红白汇总、年度整表。
/// 口径同 LedgerMath 既有汇总：待送出不计金额/笔数；场次按 ledgerID 去重。
final class ChartsAggregationTests: XCTestCase {
    private func entry(
        _ direction: String,
        _ cents: Int,
        _ date: String,
        status: String = "已送出",
        type: String = "婚礼",
        ledgerID: UUID? = nil
    ) -> EntrySnapshot {
        EntrySnapshot(
            person: "某人",
            amountCents: cents,
            direction: direction,
            date: date,
            status: status,
            ledgerType: type,
            ledgerID: ledgerID
        )
    }

    // MARK: monthlyAggregates

    func testMonthlyAggregatesSortsAndAccumulates() {
        let rows = LedgerMath.monthlyAggregates(from: [
            entry("收礼", 100_00, "2026-03-05"),
            entry("随礼", 40_00, "2026-03-20"),
            entry("收礼", 50_00, "2026-01-11"),
            entry("随礼", 80_00, "2026-01-25"),
        ])
        XCTAssertEqual(rows.map(\.month), ["2026-01", "2026-03"])
        XCTAssertEqual(rows[0].net, -30_00)
        XCTAssertEqual(rows[0].cumulativeNet, -30_00)
        XCTAssertEqual(rows[1].net, 60_00)
        XCTAssertEqual(rows[1].cumulativeNet, 30_00)
        XCTAssertEqual(rows[1].count, 2)
    }

    func testMonthlyAggregatesSkipsPendingSend() {
        let rows = LedgerMath.monthlyAggregates(from: [
            entry("收礼", 100_00, "2026-03-05"),
            entry("随礼", 999_00, "2026-03-06", status: "待送出"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].given, 0)
        XCTAssertEqual(rows[0].count, 1)
    }

    // MARK: amountBuckets

    func testAmountBucketsBoundaries() {
        let buckets = LedgerMath.amountBuckets(from: [
            entry("收礼", 199_99, "2026-01-01"),   // 200 元以下
            entry("收礼", 200_00, "2026-01-01"),   // 200–499（下界含）
            entry("随礼", 499_99, "2026-01-01"),   // 200–499
            entry("收礼", 500_00, "2026-01-01"),   // 500–999
            entry("收礼", 1000_00, "2026-01-01"),  // 1000–1999
            entry("收礼", 2000_00, "2026-01-01"),  // 2000 以上
            entry("随礼", 888_00, "2026-01-01", status: "待送出"), // 不计
        ])
        XCTAssertEqual(buckets.map(\.count), [1, 2, 1, 1, 1])
        XCTAssertEqual(buckets[1].totalCents, 200_00 + 499_99)
        XCTAssertEqual(buckets[4].totalCents, 2000_00)
    }

    func testAmountBucketsEmptyKeepsFiveRows() {
        let buckets = LedgerMath.amountBuckets(from: [])
        XCTAssertEqual(buckets.count, 5)
        XCTAssertTrue(buckets.allSatisfy { $0.count == 0 && $0.totalCents == 0 })
    }

    // MARK: kindSummary

    func testKindSummarySplitsBaiAndCountsOccasions() {
        let wedding = UUID()
        let funeral = UUID()
        let rows = LedgerMath.kindSummary(from: [
            entry("收礼", 300_00, "2026-01-01", type: "婚礼", ledgerID: wedding),
            entry("收礼", 200_00, "2026-01-02", type: "婚礼", ledgerID: wedding),
            entry("随礼", 100_00, "2026-02-01", type: "白事", ledgerID: funeral),
            entry("收礼", 500_00, "2026-02-01", type: "白事", ledgerID: funeral),
        ])
        XCTAssertEqual(rows.count, 2)
        let hong = rows[0]
        let bai = rows[1]
        XCTAssertFalse(hong.isBai)
        XCTAssertEqual(hong.received, 500_00)
        XCTAssertEqual(hong.occasions, 1) // 同一礼簿两笔只算一场
        XCTAssertTrue(bai.isBai)
        XCTAssertEqual(bai.given, 100_00)
        XCTAssertEqual(bai.received, 500_00)
        XCTAssertEqual(bai.net, 400_00)
        XCTAssertEqual(bai.occasions, 1)
    }

    func testKindSummaryNilLedgerIDCountsAmountsNotOccasions() {
        let rows = LedgerMath.kindSummary(from: [
            entry("收礼", 100_00, "2026-01-01", type: "婚礼"),
        ])
        XCTAssertEqual(rows[0].received, 100_00)
        XCTAssertEqual(rows[0].occasions, 0)
    }

    // MARK: yearlyAggregates

    func testYearlyAggregatesDeltaAndOccasions() {
        let a = UUID()
        let b = UUID()
        let rows = LedgerMath.yearlyAggregates(from: [
            entry("收礼", 100_00, "2025-05-01", ledgerID: a),
            entry("随礼", 30_00, "2025-06-01", ledgerID: a),
            entry("收礼", 200_00, "2026-05-01", ledgerID: b),
            entry("随礼", 50_00, "2026-06-01", ledgerID: b),
        ])
        XCTAssertEqual(rows.map(\.year), ["2026", "2025"]) // 倒序
        XCTAssertEqual(rows[1].net, 70_00)
        XCTAssertNil(rows[1].netDelta) // 最早一年无对比
        XCTAssertEqual(rows[0].net, 150_00)
        XCTAssertEqual(rows[0].netDelta, 80_00) // 150 − 70
        XCTAssertEqual(rows[0].occasions, 1)
        XCTAssertEqual(rows[0].count, 2)
    }

    func testYearlyAggregatesGapYearDeltaUsesPreviousDataYear() {
        let rows = LedgerMath.yearlyAggregates(from: [
            entry("收礼", 100_00, "2024-01-01"),
            entry("收礼", 160_00, "2026-01-01"),
        ])
        XCTAssertEqual(rows[0].netDelta, 60_00) // 与上一个有数据的年份（2024）比
    }
}
