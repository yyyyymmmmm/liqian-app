import XCTest
@testable import LiqianCore

// MARK: - 字号三档（v5.13）
//
// 口径：档位只设保底、不封顶也不压低——系统已更大时尊重系统；
// 标准档＝完全跟随系统。下标序与 DynamicTypeSize.allCases 一致。
final class TextSizeTierTests: XCTestCase {

    func testStoredParsing() {
        XCTAssertEqual(AppTextSizeTier(storedRaw: nil), .standard)
        XCTAssertEqual(AppTextSizeTier(storedRaw: "bogus"), .standard)
        XCTAssertEqual(AppTextSizeTier(storedRaw: "large"), .large)
        XCTAssertEqual(AppTextSizeTier(storedRaw: "extraLarge"), .extraLarge)
    }

    func testStandardFollowsSystemExactly() {
        for sys in [0, 3, 6, 11] {
            XCTAssertEqual(
                TextSizeScale.targetIndex(systemIndex: sys, tier: .standard), sys)
        }
    }

    func testLargeRaisesFloorToXXLarge() {
        // 系统默认 large(3) 与更小 → 拉到 xxLarge(5)
        XCTAssertEqual(TextSizeScale.targetIndex(systemIndex: 3, tier: .large), 5)
        XCTAssertEqual(TextSizeScale.targetIndex(systemIndex: 0, tier: .large), 5)
        // 系统已更大 → 尊重系统，不压低
        XCTAssertEqual(TextSizeScale.targetIndex(systemIndex: 6, tier: .large), 6)
        XCTAssertEqual(TextSizeScale.targetIndex(systemIndex: 9, tier: .large), 9)
    }

    func testExtraLargeRaisesFloorToAccessibility1() {
        XCTAssertEqual(
            TextSizeScale.targetIndex(systemIndex: 3, tier: .extraLarge), 7)
        XCTAssertEqual(
            TextSizeScale.targetIndex(systemIndex: 5, tier: .extraLarge), 7)
        XCTAssertEqual(
            TextSizeScale.targetIndex(systemIndex: 10, tier: .extraLarge), 10)
    }
}
