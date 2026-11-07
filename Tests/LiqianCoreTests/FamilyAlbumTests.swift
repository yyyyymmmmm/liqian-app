import XCTest
@testable import LiqianCore

// MARK: - 家族汇册跨簿索引与印刷规格（v5）
final class FamilyAlbumTests: XCTestCase {
    private func ledger(_ id: UUID, _ title: String, _ date: String, _ names: [String]) -> FamilyAlbum.LedgerInput {
        FamilyAlbum.LedgerInput(ledgerID: id, title: title, date: date, personNames: names)
    }

    func testPersonIndexAggregatesAcrossLedgers() {
        let a = UUID(), b = UUID()
        let index = FamilyAlbum.personIndex(ledgers: [
            ledger(b, "父亲寿宴", "2025-05-01", ["大舅", "二姨"]),
            ledger(a, "婚礼礼簿", "2024-10-01", ["大舅", "大舅", "表哥"]),
        ])
        // 大舅总笔数 3 居首；appearances 按礼簿日期升序（婚礼在前）
        XCTAssertEqual(index.first?.name, "大舅")
        XCTAssertEqual(index.first?.totalCount, 3)
        XCTAssertEqual(index.first?.appearances.map(\.ledgerTitle), ["婚礼礼簿", "父亲寿宴"])
        XCTAssertEqual(index.first?.appearances.map(\.count), [2, 1])
        XCTAssertEqual(index.count, 3)
    }

    func testPersonIndexSkipsBlankNamesAndTrims() {
        let a = UUID()
        let index = FamilyAlbum.personIndex(ledgers: [
            ledger(a, "婚礼礼簿", "2024-10-01", ["  大舅 ", "", "   ", "大舅"]),
        ])
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.first?.name, "大舅")
        XCTAssertEqual(index.first?.totalCount, 2)
    }

    func testPersonIndexTieBreaksByName() {
        let a = UUID()
        let index = FamilyAlbum.personIndex(ledgers: [
            ledger(a, "簿", "2024-01-01", ["张三", "李四"]),
        ])
        XCTAssertEqual(index.map(\.name), ["张三", "李四"].sorted())
    }

    func testSpineWidthFormula() {
        // 44 页（300 笔礼谱量级）：44×0.05+4 = 6.2mm
        XCTAssertEqual(PrintBookSpec.spineWidthMM(pageCount: 44), 6.2, accuracy: 0.001)
        // 下限 6mm；空册回 6
        XCTAssertEqual(PrintBookSpec.spineWidthMM(pageCount: 4), 6)
        XCTAssertEqual(PrintBookSpec.spineWidthMM(pageCount: 0), 6)
        // 页数越多书脊越宽（单调）
        XCTAssertGreaterThan(
            PrintBookSpec.spineWidthMM(pageCount: 200),
            PrintBookSpec.spineWidthMM(pageCount: 100)
        )
        // 出血 3mm ≈ 8.504pt
        XCTAssertEqual(PrintBookSpec.bleedPoints, 8.5039, accuracy: 0.001)
    }
}
