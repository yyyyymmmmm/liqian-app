import XCTest
@testable import LiqianCore

// MARK: - 年度之最（v5.11：纯函数派生，无数据整项为 nil，不编造）

final class AnnualHighlightsTests: XCTestCase {
    private func entry(
        _ person: String, cents: Int, direction: String = LiqianConstants.received,
        date: String, type: String = "婚礼", status: String = LiqianConstants.sentStatus
    ) -> EntrySnapshot {
        EntrySnapshot(
            person: person, amountCents: cents, direction: direction,
            date: date, status: status, ledgerType: type
        )
    }

    func testEmptyEntriesYieldNoHighlights() {
        let h = LedgerMath.annualHighlights(from: [])
        XCTAssertNil(h.biggest)
        XCTAssertNil(h.busiestMonth)
        XCTAssertNil(h.topPerson)
    }

    func testBiggestPicksMaxAmountAcrossDirections() {
        let h = LedgerMath.annualHighlights(from: [
            entry("甲", cents: 50_000, date: "2026-03-01"),
            entry("乙", cents: 80_000, direction: LiqianConstants.given, date: "2026-05-01", type: "满月"),
            entry("丙", cents: 20_000, date: "2026-06-01"),
        ])
        XCTAssertEqual(h.biggest?.person, "乙")
        XCTAssertEqual(h.biggest?.amountCents, 80_000)
        XCTAssertEqual(h.biggest?.ledgerType, "满月")
        XCTAssertEqual(h.biggest?.direction, LiqianConstants.given)
    }

    func testPendingSendExcludedEverywhere() {
        let h = LedgerMath.annualHighlights(from: [
            entry("甲", cents: 10_000, date: "2026-03-01"),
            entry("乙", cents: 999_900, direction: LiqianConstants.given,
                  date: "2026-09-01", status: LiqianConstants.pendingStatus),
        ])
        XCTAssertEqual(h.biggest?.person, "甲")
        XCTAssertEqual(h.busiestMonth, 3)
        XCTAssertEqual(h.topPerson?.name, "甲")
    }

    func testBusiestMonthTieBreaksToEarlierMonth() {
        let h = LedgerMath.annualHighlights(from: [
            entry("甲", cents: 10_000, date: "2026-08-03"),
            entry("乙", cents: 10_000, date: "2026-08-20"),
            entry("丙", cents: 10_000, date: "2026-02-03"),
            entry("丁", cents: 10_000, date: "2026-02-18"),
            entry("戊", cents: 10_000, date: "2026-05-01"),
        ])
        XCTAssertEqual(h.busiestMonth, 2)
        XCTAssertEqual(h.busiestMonthCount, 2)
    }

    func testTopPersonByTotalCarriesBalance() {
        let h = LedgerMath.annualHighlights(from: [
            entry("甲", cents: 100_000, date: "2026-03-01"),
            entry("甲", cents: 30_000, direction: LiqianConstants.given, date: "2026-04-01"),
            entry("乙", cents: 50_000, date: "2026-05-01"),
        ])
        XCTAssertEqual(h.topPerson?.name, "甲")
        XCTAssertEqual(h.topPerson?.received, 100_000)
        XCTAssertEqual(h.topPerson?.given, 30_000)
        XCTAssertEqual(h.topPerson?.balance, 70_000)
        XCTAssertEqual(h.topPerson?.pendingCents, 70_000)
    }
}

// MARK: - 年度总结句（规则版：主导事由 ≥30% 点名主角，否则落回规模句）

final class AnnualClosingLineTests: XCTestCase {
    func testDominantTypeNamedWithShare() {
        let line = LedgerMath.annualClosingLine(
            dominantType: "婚礼", dominantShare: 0.46, peopleCount: 12
        )
        XCTAssertTrue(line.contains("婚礼"))
        XCTAssertTrue(line.contains("46%"))
    }

    func testBelowThresholdFallsBack() {
        let line = LedgerMath.annualClosingLine(
            dominantType: "婚礼", dominantShare: 0.29, peopleCount: 12
        )
        XCTAssertFalse(line.contains("主角"))
        XCTAssertTrue(line.contains("12 位亲友"))
    }

    func testNoPeopleYieldsEmpty() {
        XCTAssertEqual(
            LedgerMath.annualClosingLine(dominantType: nil, dominantShare: 0, peopleCount: 0),
            ""
        )
    }
}
