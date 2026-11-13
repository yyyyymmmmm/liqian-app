import XCTest
@testable import LiqianCore

/// 预设金额映射单测（v5.14.4）：小签点选落值必须逐一对应自身面值——
/// 「点哪个都变成末位 1000」以测试形态钉死：任一档的落值文本只许
/// 等于它自己的面值，不许全等末位、不许互相重复。
final class PresetAmountsTests: XCTestCase {

    func testRecordFormPresetsExactList() {
        XCTAssertEqual(PresetAmounts.recordForm, [100, 200, 300, 500, 800, 1000])
        XCTAssertEqual(PresetAmounts.recordForm.count, 6)
    }

    func testScenePresetsExactList() {
        XCTAssertEqual(PresetAmounts.scene, [100, 200, 300, 500, 800, 1000, 2000])
        XCTAssertEqual(PresetAmounts.scene.count, 7)
    }

    /// 逐一对应：第 i 颗小签的落值文本只许是第 i 档自己的面值
    func testEachPresetMapsToItsOwnValue() {
        for list in [PresetAmounts.recordForm, PresetAmounts.scene] {
            for (index, value) in list.enumerated() {
                XCTAssertEqual(
                    PresetAmounts.amountText(forPreset: value),
                    "\(list[index])",
                    "第 \(index) 档（\(value)）的落值必须是它自己的面值"
                )
            }
        }
    }

    /// 不许全等末位：六/七档落值互不相同，首档落值绝不等于末档
    func testPresetsAreDistinctAndNotAllLast() {
        for list in [PresetAmounts.recordForm, PresetAmounts.scene] {
            XCTAssertEqual(Set(list).count, list.count, "预设面值不得重复")
            let texts = list.map { PresetAmounts.amountText(forPreset: $0) }
            XCTAssertEqual(Set(texts).count, texts.count, "落值文本不得全等/重复")
            XCTAssertNotEqual(texts.first, texts.last, "首档落值不许等于末档（末位吞并）")
        }
    }
}
