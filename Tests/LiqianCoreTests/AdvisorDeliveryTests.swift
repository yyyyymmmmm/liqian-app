import XCTest
@testable import LiqianCore

/// v5.8（片一 P0）：问账「半路丢单」的交付机制——全链 45 秒总时限的
/// 分腿分配（AdvisorTimeBudget）与在途占位（.pending）的落盘/收敛。
/// 持有者与管线在 App 层不可单测，这里钉死 Core 侧的纯规则：
/// 任何一次提问的网络等待被预算数学封在 45 秒内；从磁盘读回的
/// 遗孤占位必被收敛成文案，永不留死占位。
final class AdvisorDeliveryTests: XCTestCase {

    // MARK: - 时间预算：工具阶段

    /// 起点：第一轮拿工具阶段封顶（27 < 单请求上限 30 < 总预算 45）
    func testToolRoundAtStartGetsToolPhaseCap() {
        XCTAssertEqual(
            AdvisorTimeBudget.toolRoundTimeout(elapsedTotal: 0, elapsedToolPhase: 0),
            AdvisorTimeBudget.toolPhaseSeconds
        )
    }

    /// 工具阶段已用掉一部分：下一轮只剩阶段余额
    func testToolRoundShrinksWithPhaseElapsed() {
        XCTAssertEqual(
            AdvisorTimeBudget.toolRoundTimeout(elapsedTotal: 20, elapsedToolPhase: 20),
            7
        )
    }

    /// 工具阶段封顶用尽 → 不再起新一轮（回 nil 落降级）
    func testToolRoundNilWhenPhaseExhausted() {
        XCTAssertNil(
            AdvisorTimeBudget.toolRoundTimeout(elapsedTotal: 27, elapsedToolPhase: 27)
        )
        XCTAssertNil(
            AdvisorTimeBudget.toolRoundTimeout(elapsedTotal: 30, elapsedToolPhase: 30)
        )
    }

    /// 总剩余比阶段剩余更紧时，以总剩余为准（后段还要留份额）
    func testToolRoundBoundedByTotalRemaining() {
        XCTAssertEqual(
            AdvisorTimeBudget.toolRoundTimeout(elapsedTotal: 44, elapsedToolPhase: 0),
            1
        )
    }

    /// 总预算耗尽 → 任何腿都不许再起
    func testToolRoundNilWhenTotalExhausted() {
        XCTAssertNil(
            AdvisorTimeBudget.toolRoundTimeout(elapsedTotal: 45, elapsedToolPhase: 0)
        )
        XCTAssertNil(AdvisorTimeBudget.intentTimeout(elapsedTotal: 45))
        XCTAssertNil(AdvisorTimeBudget.generalTimeout(elapsedTotal: 45))
    }

    // MARK: - 时间预算：意图腿与通用 lane

    /// 意图腿封顶 8 秒；总剩余更少时按总剩余给
    func testIntentTimeoutCapsAndShrinks() {
        XCTAssertEqual(AdvisorTimeBudget.intentTimeout(elapsedTotal: 0), 8)
        XCTAssertEqual(AdvisorTimeBudget.intentTimeout(elapsedTotal: 40), 5)
        XCTAssertEqual(AdvisorTimeBudget.intentTimeout(elapsedTotal: 44.5), 0.5)
    }

    /// 通用 lane 吃满总剩余：前两段按封顶走完（27＋8）时它仍有 10 秒
    func testGeneralTimeoutGetsRemainder() {
        XCTAssertEqual(AdvisorTimeBudget.generalTimeout(elapsedTotal: 0), 45)
        XCTAssertEqual(AdvisorTimeBudget.generalTimeout(elapsedTotal: 35), 10)
    }

    /// 最坏链总账：三段按各自规则串行走满，总和恰为总预算 45 秒，
    /// 不再有旧链 4×30＋30＋30 ≈ 180 秒的叠加空间
    func testWorstCaseChainFitsTotalBudget() {
        let tool = AdvisorTimeBudget.toolPhaseSeconds
        let intent = AdvisorTimeBudget.intentTimeout(elapsedTotal: tool) ?? 0
        let general = AdvisorTimeBudget.generalTimeout(elapsedTotal: tool + intent) ?? 0
        XCTAssertEqual(intent, AdvisorTimeBudget.intentSeconds)
        XCTAssertEqual(general, 10)
        XCTAssertEqual(tool + intent + general, AdvisorTimeBudget.totalSeconds)
    }

    // MARK: - 占位落盘与收敛

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("advisor-delivery-test-\(UUID().uuidString).json")
    }

    /// pending 是普通可落盘 kind：与既有四种消息混排编解码不丢
    func testPendingCodableRoundTrip() throws {
        let messages: [AdvisorChatMessage] = [
            .init(kind: .user("明天天气咋样")),
            .init(kind: .pending),
            .init(kind: .note("旧消息")),
        ]
        let data = try JSONEncoder().encode(messages)
        let decoded = try JSONDecoder().decode([AdvisorChatMessage].self, from: data)
        XCTAssertEqual(decoded, messages)
    }

    /// 遗孤占位收敛：pending 原位变提示文案，id/顺序/其他消息不动
    func testReconcilePendingBecomesNote() {
        let pendingID = UUID()
        let messages: [AdvisorChatMessage] = [
            .init(kind: .user("我和大舅谁欠谁")),
            .init(id: pendingID, kind: .pending),
            .init(kind: .note("更早的一条")),
        ]
        let reconciled = AdvisorChatStore.reconcilingOrphanedPending(messages)
        XCTAssertEqual(reconciled.count, 3)
        XCTAssertEqual(reconciled[0], messages[0])
        XCTAssertEqual(reconciled[1].id, pendingID)
        XCTAssertEqual(
            reconciled[1].kind, .note(AdvisorChatStore.orphanedPendingNoteText)
        )
        XCTAssertEqual(reconciled[2], messages[2])
    }

    /// 没有占位时收敛是恒等变换（活进程正常读回历史不受扰）
    func testReconcileWithoutPendingIsIdentity() {
        let messages: [AdvisorChatMessage] = [
            .init(kind: .user("谁还没回礼")),
            .init(kind: .result(.pendingList([]))),
            .init(kind: .note("账里查不到")),
        ]
        XCTAssertEqual(AdvisorChatStore.reconcilingOrphanedPending(messages), messages)
    }

    /// 杀进程场景全程：占位随提问落盘 → 重启读回仍为 pending（存储层
    /// 不自作主张）→ 持有者收敛后是文案，且再落盘后读回不再有 pending
    func testKilledMidFlightPlaceholderConvergesAfterRelaunch() {
        let url = tempURL()
        defer { AdvisorChatStore.clear(from: url) }
        let messages: [AdvisorChatMessage] = [
            .init(kind: .user("明天天气咋样")),
            .init(kind: .pending),
        ]
        AdvisorChatStore.save(messages, to: url)
        let relaunched = AdvisorChatStore.load(from: url)
        XCTAssertEqual(relaunched, messages) // 原始读回：占位还在
        let reconciled = AdvisorChatStore.reconcilingOrphanedPending(relaunched)
        XCTAssertEqual(
            reconciled.last?.kind, .note(AdvisorChatStore.orphanedPendingNoteText)
        )
        AdvisorChatStore.save(reconciled, to: url)
        let reread = AdvisorChatStore.load(from: url)
        XCTAssertFalse(reread.contains { $0.kind == .pending })
    }

    // MARK: - 落地断言（v5.8.2）：空回复不许落盘/呈现

    /// 空 text＋无卡的 .answer 等于不存在 → 改落兜底 note
    func testEmptyAnswerWithoutCardsBecomesApologyNote() {
        XCTAssertEqual(
            AdvisorChatStore.ensuringNonEmpty(.answer(text: "", cards: [])),
            .note(AdvisorReplyConvergence.failureApologyText)
        )
        XCTAssertEqual(
            AdvisorChatStore.ensuringNonEmpty(.answer(text: "  \n ", cards: [])),
            .note(AdvisorReplyConvergence.failureApologyText)
        )
    }

    /// 有 text 的纯文本回复原样通过（账外回答的正常形态）
    func testTextOnlyAnswerPassesThrough() {
        let kind = AdvisorChatMessage.Kind.answer(text: "明天多云，记得添衣。", cards: [])
        XCTAssertEqual(AdvisorChatStore.ensuringNonEmpty(kind), kind)
    }

    /// text 为空但有卡片：卡片本身就是回复，原样通过
    func testEmptyTextWithCardsPassesThrough() {
        let card = AdvisorCard.totals(AdvisorTotalsCard(totals: AdvisorMoneyTotals(
            rangeLabel: "全部时段", receivedCents: 100, givenCents: 0, recordCount: 1
        )))
        let kind = AdvisorChatMessage.Kind.answer(text: "", cards: [card])
        XCTAssertEqual(AdvisorChatStore.ensuringNonEmpty(kind), kind)
    }

    /// 其余 kind 一律原样通过，断言只管 .answer
    func testOtherKindsPassThrough() {
        for kind in [
            AdvisorChatMessage.Kind.user("在吗"),
            .pending,
            .note("查不到这个人"),
        ] {
            XCTAssertEqual(AdvisorChatStore.ensuringNonEmpty(kind), kind)
        }
    }
}
