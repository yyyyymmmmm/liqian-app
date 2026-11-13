import XCTest
@testable import LiqianCore

// MARK: - v5.14.1 保存链热修：纯逻辑单测
// ① SaveFlow 成败分发——失败绝不触发成功反馈（审计 A5 的契约）；
// ② LedgerCountdown 天数/文案边界——今天/昨天/明天/跨月/白事抑制。

final class SaveChainTests: XCTestCase {

    private struct StubError: Error {}

    // MARK: SaveFlow

    /// 保存成功：只走 onSuccess，返回 true
    func testSaveFlowSuccessRunsSuccessOnly() {
        var success = 0
        var failure = 0
        let ok = SaveFlow.run(
            save: {},
            onSuccess: { success += 1 },
            onFailure: { _ in failure += 1 }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(success, 1)
        XCTAssertEqual(failure, 0)
    }

    /// 保存抛错：只走 onFailure 且把原错误交出去，返回 false——
    /// 成功反馈（落印/关页/报数）在这一档绝不许触发
    func testSaveFlowFailureRunsFailureOnlyWithError() {
        var success = 0
        var received: Error?
        let ok = SaveFlow.run(
            save: { throw StubError() },
            onSuccess: { success += 1 },
            onFailure: { received = $0 }
        )
        XCTAssertFalse(ok)
        XCTAssertEqual(success, 0, "保存失败时成功反馈不得触发")
        XCTAssertTrue(received is StubError, "原错误必须原样交给失败侧（记日志用）")
    }

    /// 失败文案定版：人话、无技术词、各入口共用这一句
    func testSaveFailureMessageWording() {
        XCTAssertEqual(SaveFlow.failureMessage, "没存上，再试一次；内容都还在，没有丢。")
    }

    // MARK: LedgerCountdown（today 钉在 2026-11-13）

    private let today = "2026-11-13"

    func testCountdownTomorrow() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-11-14", today: today, isBai: false), 1)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-11-14", today: today, isBai: false),
            "还有 1 天")
    }

    func testCountdownToday() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-11-13", today: today, isBai: false), 0)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-11-13", today: today, isBai: false),
            "就是今天")
    }

    func testCountdownYesterday() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-11-12", today: today, isBai: false), -1)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-11-12", today: today, isBai: false),
            "已过 1 天")
    }

    /// 跨月：11-30 → 12-03 是 3 天（按日历日差，不按 30 天月估）
    func testCountdownCrossMonth() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-12-03", today: "2026-11-30", isBai: false),
            3)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-12-03", today: "2026-11-30", isBai: false),
            "还有 3 天")
    }

    /// 跨年已过：2026-12-31 → 2027-01-02 已过 2 天
    func testCountdownPastCrossYear() {
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-12-31", today: "2027-01-02", isBai: false),
            "已过 2 天")
    }

    /// 白事抑制：未来/当天/已过全不显（天数与文案同为 nil）
    func testCountdownBaiSuppressed() {
        for event in ["2026-11-14", "2026-11-13", "2026-11-12"] {
            XCTAssertNil(
                LedgerCountdown.daysUntil(eventDate: event, today: today, isBai: true),
                "白事 \(event) 不应给出天数")
            XCTAssertNil(
                LedgerCountdown.text(eventDate: event, today: today, isBai: true),
                "白事 \(event) 不应给出倒计时文案")
        }
    }
}
