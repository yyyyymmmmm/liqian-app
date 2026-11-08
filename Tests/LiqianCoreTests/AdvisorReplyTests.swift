import XCTest
@testable import LiqianCore

/// v5.7：问账「永不沉默」硬保证的收敛裁决——任何一次提问的最终出口
/// 只能是三者之一：通用作答 / 未开通兜底卡 / 真故障致歉，不存在
/// 「什么都不落」的第四种结果。
final class AdvisorReplyTests: XCTestCase {

    /// AI 就绪＋通用 lane 拿到回答 → 出回答（账外问题正常作答）
    func testGeneralAnswerWinsWhenReady() {
        let outcome = AdvisorReplyConvergence.resolve(
            aiReady: true, generalAnswer: "明天我拿不到实时天气，出门记得看一眼预报。"
        )
        XCTAssertEqual(
            outcome, .generalAnswer("明天我拿不到实时天气，出门记得看一眼预报。")
        )
    }

    /// 通用回答带首尾空白 → 落库文本已修整，不带空白上屏
    func testGeneralAnswerIsTrimmed() {
        let outcome = AdvisorReplyConvergence.resolve(
            aiReady: true, generalAnswer: "  随礼一般看关系亲疏。\n"
        )
        XCTAssertEqual(outcome, .generalAnswer("随礼一般看关系亲疏。"))
    }

    /// AI 就绪但通用 lane 没拿到（网络失败等）→ 真故障致歉，不是装不会
    func testReadyButNoAnswerIsFailureApology() {
        XCTAssertEqual(
            AdvisorReplyConvergence.resolve(aiReady: true, generalAnswer: nil),
            .failureApology
        )
    }

    /// 通用 lane 返回纯空白等同没拿到 → 同样落致歉（空文本不许上屏）
    func testReadyButBlankAnswerIsFailureApology() {
        XCTAssertEqual(
            AdvisorReplyConvergence.resolve(aiReady: true, generalAnswer: "  \n "),
            .failureApology
        )
    }

    /// AI 未就绪且规则兜不住 → 既有 .unsupported 卡（卡内自带开通引导）
    func testNotReadyFallsToUnsupported() {
        XCTAssertEqual(
            AdvisorReplyConvergence.resolve(aiReady: false, generalAnswer: nil),
            .unsupportedWithoutAI
        )
    }

    /// 防御：未就绪却意外拿到通用回答（正常管线不会发生）→ 有答出答，
    /// 仍守「永不沉默」，不硬吞掉一条现成回复
    func testAnswerWinsEvenWhenNotReady() {
        XCTAssertEqual(
            AdvisorReplyConvergence.resolve(aiReady: false, generalAnswer: "在的。"),
            .generalAnswer("在的。")
        )
    }

    /// 致歉文案单点：非空、点明可能原因并给出重试出路（不是终结性拒绝）
    func testFailureApologyTextIsActionable() {
        let text = AdvisorReplyConvergence.failureApologyText
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("网络"))
        XCTAssertTrue(text.contains("再问"))
    }
}
