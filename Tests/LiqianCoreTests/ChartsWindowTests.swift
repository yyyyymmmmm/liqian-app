import XCTest
@testable import LiqianCore

/// v4.7.1 图表窗口与轴标：自适应月份窗口（稀疏数据收敛）与短轴标格式。
/// 动机是真机实证：近 12 个月仅 1 个月有数时，12 个空槽 + 长标签挤成糊。
final class ChartsWindowTests: XCTestCase {
    private let base12 = (1...12).map { String(format: "2026-%02d", $0) }

    // MARK: adaptiveMonthKeys

    func testAdaptiveWindowSingleDataMonthPadsOneEachSide() {
        let keys = LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: ["2026-10"])
        XCTAssertEqual(keys, ["2026-09", "2026-10", "2026-11"])
    }

    func testAdaptiveWindowClampsAtEdges() {
        XCTAssertEqual(
            LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: ["2026-01"]),
            ["2026-01", "2026-02"]
        )
        XCTAssertEqual(
            LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: ["2026-12"]),
            ["2026-11", "2026-12"]
        )
    }

    func testAdaptiveWindowSpanFourStillShrinks() {
        let data: Set<String> = ["2026-03", "2026-04", "2026-05", "2026-06"]
        XCTAssertEqual(
            LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: data),
            ["2026-02", "2026-03", "2026-04", "2026-05", "2026-06", "2026-07"]
        )
    }

    func testAdaptiveWindowSpanFiveKeepsBase() {
        let data: Set<String> = ["2026-03", "2026-04", "2026-05", "2026-06", "2026-07"]
        XCTAssertEqual(LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: data), base12)
    }

    func testAdaptiveWindowNoDataOrForeignMonthsKeepsBase() {
        XCTAssertEqual(LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: []), base12)
        XCTAssertEqual(
            LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: ["2024-05"]),
            base12
        )
    }

    func testAdaptiveWindowIgnoresGapsInsideSpan() {
        // 跨度按首末数据月算（中间空月不缩短跨度）：1 月与 4 月有数、跨度 4 → 收敛
        let keys = LedgerMath.adaptiveMonthKeys(baseKeys: base12, dataMonths: ["2026-01", "2026-04"])
        XCTAssertEqual(keys, ["2026-01", "2026-02", "2026-03", "2026-04", "2026-05"])
    }

    // MARK: monthAxisLabel

    func testMonthAxisLabelSameYearShortForm() {
        XCTAssertEqual(LedgerMath.monthAxisLabel(key: "2026-03", multiYear: false), "3月")
        XCTAssertEqual(LedgerMath.monthAxisLabel(key: "2026-01", multiYear: false), "1月")
        XCTAssertEqual(LedgerMath.monthAxisLabel(key: "2026-12", multiYear: false), "12月")
    }

    func testMonthAxisLabelCrossYearOnlyJanuaryCarriesYear() {
        XCTAssertEqual(LedgerMath.monthAxisLabel(key: "2026-01", multiYear: true), "26年1月")
        XCTAssertEqual(LedgerMath.monthAxisLabel(key: "2025-01", multiYear: true), "25年1月")
        XCTAssertEqual(LedgerMath.monthAxisLabel(key: "2025-12", multiYear: true), "12月")
        XCTAssertEqual(LedgerMath.monthAxisLabel(key: "2026-11", multiYear: true), "11月")
    }
}
