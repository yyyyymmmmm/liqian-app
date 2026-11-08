import XCTest
@testable import LiqianCore

// MARK: - 默认礼簿决策（v5.8.1 片二 #10）
// 顺序钉死：上次使用（存在且非示例）→ 日期最新非示例 → 日期最新 → nil。

final class DefaultLedgerPickerTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let sample = UUID()
    private let ghost = UUID()

    /// 上次使用仍在且非示例 → 就是它，哪怕不是日期最新
    func testLastUsedWinsOverNewest() {
        let picked = DefaultLedgerPicker.pick(
            lastUsedID: b,
            ledgerIDsByDateDescending: [a, b],
            sampleIDs: []
        )
        XCTAssertEqual(picked, b)
    }

    /// 上次使用已被删除（不在列表里）→ 落日期最新非示例
    func testDeletedLastUsedFallsBackToNewestReal() {
        let picked = DefaultLedgerPicker.pick(
            lastUsedID: ghost,
            ledgerIDsByDateDescending: [a, b],
            sampleIDs: []
        )
        XCTAssertEqual(picked, a)
    }

    /// 上次使用是示例礼簿且有真礼簿 → 示例约束优先，跳过它落真礼簿
    func testSampleLastUsedSkippedWhenRealLedgersExist() {
        let picked = DefaultLedgerPicker.pick(
            lastUsedID: sample,
            ledgerIDsByDateDescending: [sample, a],
            sampleIDs: [sample]
        )
        XCTAssertEqual(picked, a)
    }

    /// 只剩示例礼簿时，上次使用（示例）不命中第一档，但兜底仍落它
    /// ——与现行「没有真礼簿时才落到示例簿」口径一致
    func testOnlySamplesFallBackToFirst() {
        let picked = DefaultLedgerPicker.pick(
            lastUsedID: sample,
            ledgerIDsByDateDescending: [sample],
            sampleIDs: [sample]
        )
        XCTAssertEqual(picked, sample)
    }

    /// 从没记过账（无上次使用）→ 日期最新非示例（现行 v4.2 口径）
    func testNoLastUsedPicksNewestReal() {
        let picked = DefaultLedgerPicker.pick(
            lastUsedID: nil,
            ledgerIDsByDateDescending: [sample, a, b],
            sampleIDs: [sample]
        )
        XCTAssertEqual(picked, a)
    }

    /// 无上次使用且全是示例 → 日期最新（第一本）
    func testNoLastUsedOnlySamples() {
        let picked = DefaultLedgerPicker.pick(
            lastUsedID: nil,
            ledgerIDsByDateDescending: [sample],
            sampleIDs: [sample]
        )
        XCTAssertEqual(picked, sample)
    }

    /// 一本礼簿都没有 → nil（表单提示先建礼簿）
    func testEmptyReturnsNil() {
        XCTAssertNil(
            DefaultLedgerPicker.pick(
                lastUsedID: a,
                ledgerIDsByDateDescending: [],
                sampleIDs: []
            )
        )
    }
}
