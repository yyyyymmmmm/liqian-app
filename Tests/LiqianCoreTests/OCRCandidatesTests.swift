import XCTest
@testable import LiqianCore

// MARK: - OCR 文本 → 待确认候选组装（v2.9：拍照识别礼单的 Vision 文本走
// 与粘贴导入共用的 LedgerTextParser，组装层把成功行与跳过行分开，明示不吞行）

final class OCRCandidatesTests: XCTestCase {
    /// 多行礼单文本 → 多笔候选：金额换算、关系带入、原文行与行号保留
    func testMultiLineGiftListBuildsCandidates() {
        let text = """
        张三 500
        李四 1000 亲戚
        王五 ¥200
        """
        let outcome = OCRCandidateBuilder.build(from: text)
        XCTAssertEqual(outcome.candidates.count, 3)
        XCTAssertTrue(outcome.skipped.isEmpty)
        XCTAssertFalse(outcome.isEmpty)

        XCTAssertEqual(outcome.candidates[0].name, "张三")
        XCTAssertEqual(outcome.candidates[0].amountCents, 50_000)
        XCTAssertNil(outcome.candidates[0].relation)
        XCTAssertEqual(outcome.candidates[0].lineNo, 1)
        XCTAssertEqual(outcome.candidates[0].raw, "张三 500")

        XCTAssertEqual(outcome.candidates[1].name, "李四")
        XCTAssertEqual(outcome.candidates[1].amountCents, 100_000)
        XCTAssertEqual(outcome.candidates[1].relation, "亲戚")

        // ¥ 前缀金额照常读出
        XCTAssertEqual(outcome.candidates[2].name, "王五")
        XCTAssertEqual(outcome.candidates[2].amountCents, 20_000)
    }

    /// 含噪声行：标题/合计/中文数字金额等读不出的行进 skipped 并带原因，
    /// 不混进候选；空行不计入任何一堆，行号仍是原文真实行号
    func testNoiseLinesAreSkippedWithReasons() {
        let text = """
        婚礼礼单

        赵六 300
        钱七 五百
        合计
        """
        let outcome = OCRCandidateBuilder.build(from: text)
        XCTAssertEqual(outcome.candidates.count, 1)
        XCTAssertEqual(outcome.candidates[0].name, "赵六")
        XCTAssertEqual(outcome.candidates[0].amountCents, 30_000)
        // 第 2 行是空行（跳过不计），赵六在原文第 3 行
        XCTAssertEqual(outcome.candidates[0].lineNo, 3)

        XCTAssertEqual(outcome.skipped.count, 3)
        XCTAssertEqual(outcome.skipped.map(\.lineNo), [1, 4, 5])
        XCTAssertEqual(outcome.skipped[0].raw, "婚礼礼单")
        XCTAssertEqual(outcome.skipped[0].reason, "未识别到金额")
        // 规则解析只认阿拉伯数字金额：中文数字「五百」读不出（AI 增强负责这类）
        XCTAssertEqual(outcome.skipped[1].raw, "钱七 五百")
        // 「合计」没有金额成不了候选，进 skipped 而不是静默丢掉
        XCTAssertEqual(outcome.skipped[2].raw, "合计")
        XCTAssertEqual(outcome.skipped[2].reason, "未识别到金额")
    }

    /// 空文本 / 只有空行 → 两堆皆空，isEmpty 为真（调用方据此进「没认出」提示态）
    func testEmptyTextYieldsEmptyOutcome() {
        let empty = OCRCandidateBuilder.build(from: "")
        XCTAssertTrue(empty.candidates.isEmpty)
        XCTAssertTrue(empty.skipped.isEmpty)
        XCTAssertTrue(empty.isEmpty)

        let blankLines = OCRCandidateBuilder.build(from: "\n  \n")
        XCTAssertTrue(blankLines.isEmpty)
        XCTAssertTrue(blankLines.skipped.isEmpty)
    }
}
