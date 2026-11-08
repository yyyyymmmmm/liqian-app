import XCTest
@testable import LiqianCore

// MARK: - 成书旗舰卡落点决策（v5.11.6 成书路径缩层）
// 两态落点钉死：升位→成书说明/登记页，常驻→导出礼谱页；
// 礼簿 ID 原样透传，不许串簿。

final class BookFlagshipRouteTests: XCTestCase {
    private let ledgerA = UUID()
    private let ledgerB = UUID()

    /// 升位态（场次已过＋笔数达标）：直达成书说明/登记页
    func testPromotedGoesStraightToBookBinding() {
        let dest = BookFlagshipRouter.destination(state: .promoted, ledgerID: ledgerA)
        XCTAssertEqual(dest, .bookBinding(ledgerID: ledgerA))
    }

    /// 常驻态：直达导出礼谱页（装订成书行就在该页内）
    func testStandingGoesStraightToExport() {
        let dest = BookFlagshipRouter.destination(state: .standing, ledgerID: ledgerA)
        XCTAssertEqual(dest, .export(ledgerID: ledgerA))
    }

    /// 落点跟着传入的礼簿走：换一本簿，目的地里的 ID 必须跟着换
    func testDestinationCarriesTheGivenLedger() {
        XCTAssertEqual(
            BookFlagshipRouter.destination(state: .promoted, ledgerID: ledgerB),
            .bookBinding(ledgerID: ledgerB)
        )
        XCTAssertEqual(
            BookFlagshipRouter.destination(state: .standing, ledgerID: ledgerB),
            .export(ledgerID: ledgerB)
        )
    }

    /// 两态落点必须不同（防回归到「两态同落点」的旧 4 层路径）
    func testTwoStatesNeverShareDestination() {
        let promoted = BookFlagshipRouter.destination(state: .promoted, ledgerID: ledgerA)
        let standing = BookFlagshipRouter.destination(state: .standing, ledgerID: ledgerA)
        XCTAssertNotEqual(promoted, standing)
    }
}
