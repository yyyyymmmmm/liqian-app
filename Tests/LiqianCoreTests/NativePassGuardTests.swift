import XCTest
@testable import LiqianCore

/// v5.14 全原生整改源码守卫＋金额输入净化单测。
/// 守卫口径与 PrintBookAssemblyTests 的 repoSource 同款：仓库源码不在
/// 预期路径时跳过（XCTSkip），在时逐条钉死防回潮。
final class NativePassGuardTests: XCTestCase {

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

    /// 全 Sources 拼接（守卫「全仓零引用」类断言用）
    private func allSourcesText() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: dir.path) else {
            throw XCTSkip("Sources 目录不在预期路径，守卫跳过")
        }
        var out = ""
        for case let file as String in walker where file.hasSuffix(".swift") {
            if let text = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) {
                out += text + "\n"
            }
        }
        guard !out.isEmpty else { throw XCTSkip("Sources 为空，守卫跳过") }
        return out
    }

    // MARK: - 图表页：无自绘分段残留、占比条已 Charts 化

    func testChartsRangeSelectorIsSystemSegmentedPicker() throws {
        let charts = try repoSource("Sources/LiqianApp/ChartsView.swift")
        let start = try XCTUnwrap(charts.range(of: "private var rangeSelector")?.lowerBound)
        let end = try XCTUnwrap(charts.range(of: "// MARK: - 空态")?.lowerBound)
        let window = String(charts[start..<end])
        XCTAssertTrue(window.contains("Picker("), "范围选择器必须走系统 Picker")
        XCTAssertTrue(window.contains(".pickerStyle(.segmented)"), "范围选择器必须是 segmented 样式")
        XCTAssertFalse(window.contains("matchedGeometryEffect"), "自绘胶囊指示器不得回潮")
        XCTAssertFalse(charts.contains("rangePill"), "rangePill 标识不得回潮")
        XCTAssertNil(charts.range(of: "matchedGeometryEffect"), "ChartsView 全文不得再有 matchedGeometry 手搓指示器")
    }

    func testChartsShareBarIsChartsStack() throws {
        let charts = try repoSource("Sources/LiqianApp/ChartsView.swift")
        XCTAssertFalse(charts.contains("private struct ShareBar"), "自绘 ShareBar 已退役，不得回潮")
        XCTAssertTrue(charts.contains("private struct ShareStackBar"), "占比条应为 ShareStackBar")
        let start = try XCTUnwrap(charts.range(of: "private struct ShareStackBar")?.lowerBound)
        let window = String(charts[start...])
        XCTAssertTrue(window.contains("BarMark("), "占比条必须由 Swift Charts BarMark 实现")
    }

    // MARK: - 大场模式：无写死字号，走 dynamicTypeSize

    func testBatchEntryHasNoFixedPointFonts() throws {
        let batch = try repoSource("Sources/LiqianApp/BatchEntryView.swift")
        XCTAssertFalse(batch.contains(".system(size:"), "大场模式写死 pt 必须清零")
        XCTAssertTrue(batch.contains(".dynamicTypeSize(effectiveTypeSize)"), "大字必须走 dynamicTypeSize 环境注入")
        XCTAssertTrue(batch.contains("TextSizeScale.bigModeTargetIndex"), "保底档必须走 Core TextSizeScale 口径")
    }

    // MARK: - 人物详情：已 List 化

    func testPersonDetailIsListBased() throws {
        let person = try repoSource("Sources/LiqianApp/PersonDetailView.swift")
        XCTAssertTrue(person.contains("List {"), "人物详情必须 List 化")
        XCTAssertTrue(person.contains(".listStyle(.insetGrouped)"), "人物详情须与其余详情页同为 insetGrouped")
        XCTAssertFalse(person.contains("ScrollView {"), "手堆 ScrollView 不得回潮")
        XCTAssertFalse(person.contains("liqianCardSurface"), "手绘卡面已随 List 归位退役")
        XCTAssertTrue(person.contains(".swipeActions("), "记录行须带系统左滑操作")
        XCTAssertTrue(person.contains(".contextMenu {"), "记录行长按菜单不得丢失")
    }

    // MARK: - 动效：ScaleOnPress 与自研曲线令牌全仓零引用

    func testNoScaleOnPressOrMotionTokensAnywhere() throws {
        let all = try allSourcesText()
        XCTAssertFalse(all.contains("ScaleOnPressButtonStyle"), "自研按压样式已退役，全仓不得再引用")
        XCTAssertFalse(all.contains("MotionTokens"), "自研动效令牌层已整层退役，全仓不得再引用")
    }

    // MARK: - 记一笔：无自绘键盘残留、系统 decimalPad＋Form

    func testRecordFormUsesSystemKeyboardAndForm() throws {
        let form = try repoSource("Sources/LiqianApp/RecordFormView.swift")
        XCTAssertTrue(form.contains("Form {"), "记一笔容器必须走系统 Form")
        XCTAssertTrue(form.contains(".keyboardType(.decimalPad)"), "金额必须走系统 decimalPad 键盘")
        XCTAssertFalse(form.contains("amountKeypad"), "自绘金额键盘不得回潮")
        XCTAssertFalse(form.contains("keypadInput"), "自绘键盘输入函数不得回潮")
        XCTAssertFalse(form.contains("AmountCaret"), "自绘金额光标不得回潮")
        XCTAssertFalse(form.contains(".system(size: 44"), "金额写死 44pt 不得回潮")
        XCTAssertTrue(form.contains("liqianMoney(.largeTitle)"), "金额字阶须回自家语义金额口径")
        XCTAssertTrue(form.contains("AmountInputText.sanitized"), "输入合法性须由 Core 净化函数承接")
        // 宾客回执预填 init 链（v5.12）不得回归
        XCTAssertTrue(form.contains("receiptAmountCents: Int"), "宾客回执预填 init 必须保留")
        XCTAssertTrue(form.contains("onSavedNewRecord"), "回执入账回调必须保留")
    }

    // MARK: - 落印：无自研曲线字面量，走系统 .bouncy

    func testSealInUsesSystemBouncy() throws {
        let components = try repoSource("Sources/LiqianDesign/Components.swift")
        let start = try XCTUnwrap(components.range(of: "struct SealStampOverlay")?.lowerBound)
        let window = String(components[start...])
        XCTAssertTrue(window.contains("withAnimation(.bouncy)"), "落印须走系统 .bouncy 预设弹簧")
        XCTAssertFalse(window.contains("extraBounce"), "落印不得再有自研曲线参数")
        XCTAssertFalse(window.contains("interactiveSpring"), "落印不得再有自研弹簧参数")
        let tokens = try repoSource("Sources/LiqianDesign/DesignTokens.swift")
        XCTAssertFalse(tokens.contains("sealIn"), "DesignTokens 不得再定义 sealIn 令牌")
    }

    // MARK: - 金额输入净化（纯函数）

    func testAmountInputSanitized() {
        let s = AmountInputText.sanitized
        XCTAssertEqual(s(""), "")
        XCTAssertEqual(s("0"), "0")
        XCTAssertEqual(s("."), "0.")
        XCTAssertEqual(s("0."), "0.")
        XCTAssertEqual(s("05"), "5")
        XCTAssertEqual(s("00"), "0")
        XCTAssertEqual(s("0.05"), "0.05")
        XCTAssertEqual(s("1.234"), "1.23")
        XCTAssertEqual(s("1.2.3"), "1.23")
        XCTAssertEqual(s("12345678"), "1234567")
        XCTAssertEqual(s("9999999.99"), "9999999.99")
        XCTAssertEqual(s("12a3"), "123")
        XCTAssertEqual(s(" 500 "), "500")
    }

    // MARK: - 大场保底（纯函数）

    func testBigModeTargetIndex() {
        XCTAssertEqual(TextSizeScale.bigModeTargetIndex(systemIndex: 3, bigMode: false), 3)
        XCTAssertEqual(TextSizeScale.bigModeTargetIndex(systemIndex: 3, bigMode: true), 8)
        XCTAssertEqual(TextSizeScale.bigModeTargetIndex(systemIndex: 10, bigMode: true), 10)
    }
}
