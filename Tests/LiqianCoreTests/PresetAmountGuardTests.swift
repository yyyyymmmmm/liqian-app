import XCTest
@testable import LiqianCore

/// v5.14.4 预设金额/命中路由源码守卫：定因＝记一笔整卡挤进 Form 的
/// 单个单元格，行级命中路由吞并同行多颗默认样式 Button（落末位值）、
/// 抢走 Picker 同行控件的点选。修法两条结构纪律钉死防回潮：
/// ①小签只许引用 Core 单一数据源＋必须 .borderless 自带命中；
/// ②巨无霸单卡 formCard 不得回潮，关系/方式 Picker 必须待在
/// supplementsRows（逐行独占区）里。口径与 StoreLockGuardTests 同款：
/// 源码不在预期路径时跳过。
final class PresetAmountGuardTests: XCTestCase {

    private func repoSource(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("仓库源码不在预期路径，守卫跳过：\(relative)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 记一笔小签：Core 单一数据源＋borderless 自带命中，字面量不许回潮
    func testRecordFormChipsUseCorePresetsWithBorderlessStyle() throws {
        let form = try repoSource("Sources/LiqianApp/RecordFormView.swift")
        XCTAssertTrue(form.contains("PresetAmounts.recordForm"), "记一笔小签必须引用 Core 预设列表")
        XCTAssertTrue(form.contains("PresetAmounts.amountText(forPreset:"), "小签落值必须走 Core 恒等映射")
        XCTAssertTrue(form.contains(".buttonStyle(.borderless)"), "小签必须 .borderless 自带命中，不许默认样式混行")
        XCTAssertFalse(
            form.contains("ForEach([100, 200, 300, 500, 800, 1000]"),
            "预设字面量不得在视图里回潮")
    }

    /// 结构守卫：整卡单单元格不得回潮；Picker 必须在逐行独占区内
    func testPickersLiveInDedicatedRowsNotInOneGiantCell() throws {
        let form = try repoSource("Sources/LiqianApp/RecordFormView.swift")
        XCTAssertFalse(
            form.contains("private var formCard"),
            "v5.14 的整卡单单元格 formCard 不得回潮（两症状同根）")
        XCTAssertTrue(form.contains("supplementsRows"), "补充信息内容必须拆为逐行独占区")
        guard
            let rowsRange = form.range(of: "private var supplementsRows"),
            let relationRange = form.range(of: "Picker(\"关系\""),
            let methodRange = form.range(of: "Picker(\"方式\"")
        else {
            XCTFail("关系/方式 Picker 必须存在且位于 supplementsRows 之后")
            return
        }
        XCTAssertTrue(relationRange.lowerBound > rowsRange.lowerBound, "关系 Picker 必须在 supplementsRows 区内")
        XCTAssertTrue(methodRange.lowerBound > rowsRange.lowerBound, "方式 Picker 必须在 supplementsRows 区内")
    }

    /// 现场模式：同走 Core 单一数据源，字面量不许回潮（其容器为
    /// ScrollView＋.bordered，本就免疫，本条只钉数据源收敛）
    func testSceneModeUsesCorePresets() throws {
        let scene = try repoSource("Sources/LiqianApp/SceneModeView.swift")
        XCTAssertTrue(scene.contains("PresetAmounts.scene"), "现场常用金额必须引用 Core 预设列表")
        XCTAssertFalse(
            scene.contains("[100, 200, 300, 500, 800, 1000, 2000]"),
            "现场预设字面量不得回潮")
    }
}
