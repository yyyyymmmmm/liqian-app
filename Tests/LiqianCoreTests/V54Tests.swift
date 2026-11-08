import XCTest
@testable import LiqianCore

// MARK: - v5.4：记账工具组装 / 对话持久化 / 金额滚动策略

final class V54Tests: XCTestCase {
    private let ledgerA = UUID()
    private let ledgerB = UUID()

    /// 大舅：在 A 簿（敏杰婚礼）收 2000、B 簿（小宝满月）随 300 → 最近往来在 B
    /// 王五：只在 A 簿收 800
    private func fixture() -> [EntrySnapshot] {
        [
            EntrySnapshot(person: "大舅", relation: "亲戚", amountCents: 30_000,
                          direction: LiqianConstants.given, date: "2026-06-01",
                          ledgerType: "满月", ledgerID: ledgerB),
            EntrySnapshot(person: "大舅", relation: "亲戚", amountCents: 200_000,
                          direction: LiqianConstants.received, date: "2026-03-01",
                          ledgerType: "婚礼", ledgerID: ledgerA),
            EntrySnapshot(person: "王五", relation: "朋友", amountCents: 80_000,
                          direction: LiqianConstants.received, date: "2026-02-01",
                          ledgerType: "婚礼", ledgerID: ledgerA),
        ]
    }

    private func context(entries: [EntrySnapshot]? = nil) -> AdvisorToolContext {
        AdvisorToolContext(
            entries: entries ?? fixture(),
            ledgers: [
                .init(id: ledgerA, title: "敏杰婚礼", type: "婚礼", date: "2026-03-01"),
                .init(id: ledgerB, title: "小宝满月", type: "满月", date: "2026-06-01"),
            ],
            today: "2026-11-08"
        )
    }

    private func draftCard(_ args: String, ctx: AdvisorToolContext? = nil) -> AdvisorDraftRecordCard? {
        let outcome = AdvisorToolEngine.executeDetailed(
            AdvisorToolCall(name: AdvisorTools.draftRecord, argumentsJSON: args),
            context: ctx ?? context()
        )
        guard case .draftRecord(let card)? = outcome.card else { return nil }
        return card
    }

    private func draftJSON(_ args: String, ctx: AdvisorToolContext? = nil) throws -> [String: Any] {
        let text = AdvisorToolEngine.execute(
            AdvisorToolCall(name: AdvisorTools.draftRecord, argumentsJSON: args),
            context: ctx ?? context()
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: draft_record 组装

    func testDraftAssemblesReceivedWithSuggestedLedger() throws {
        // 大舅最近往来在 B 簿 → 建议记入 B；关系取账上已知「亲戚」
        let card = try XCTUnwrap(draftCard(#"{"name":"大舅","direction":"received","amountYuan":500}"#))
        XCTAssertEqual(card.person, "大舅")
        XCTAssertEqual(card.relation, "亲戚")
        XCTAssertEqual(card.direction, LiqianConstants.received)
        XCTAssertEqual(card.amountCents, 50_000)
        XCTAssertEqual(card.date, "2026-11-08") // 没给日期 → 今天
        XCTAssertEqual(card.suggestedLedgerID, ledgerB)
        XCTAssertEqual(card.suggestedLedgerTitle, "小宝满月")
        XCTAssertEqual(card.state, .pending)
        let json = try draftJSON(#"{"name":"大舅","direction":"received","amountYuan":500}"#)
        XCTAssertEqual(json["ok"] as? Bool, true)
    }

    func testDraftAssemblesGivenDecimalAndExplicitFields() throws {
        let card = try XCTUnwrap(draftCard(
            #"{"name":"王五","direction":"given","amountYuan":800.5,"date":"2026-11-01","ledgerType":"寿宴"}"#
        ))
        XCTAssertEqual(card.direction, LiqianConstants.given) // 回礼落 given
        XCTAssertEqual(card.amountCents, 80_050)
        XCTAssertEqual(card.date, "2026-11-01")
        XCTAssertEqual(card.ledgerType, "寿宴")
        XCTAssertEqual(card.suggestedLedgerID, ledgerA)
    }

    func testDraftNewPersonHasNoSuggestion() throws {
        let card = try XCTUnwrap(draftCard(#"{"name":"赵六","direction":"received","amountYuan":200}"#))
        XCTAssertEqual(card.person, "赵六")
        XCTAssertEqual(card.relation, "")
        XCTAssertNil(card.suggestedLedgerID)
    }

    func testDraftRejectsMissingPieces() throws {
        // 缺人名 / 缺金额 / 金额为 0 / 方向非法：一律 ok:false 且不出卡（让模型追问，不猜数）
        for args in [
            #"{"direction":"received","amountYuan":500}"#,
            #"{"name":"大舅","direction":"received"}"#,
            #"{"name":"大舅","direction":"received","amountYuan":0}"#,
            #"{"name":"大舅","direction":"sideways","amountYuan":500}"#,
        ] {
            let json = try draftJSON(args)
            XCTAssertEqual(json["ok"] as? Bool, false, args)
            XCTAssertNil(draftCard(args), args)
        }
    }

    func testDraftAmountAsStringAndBadTypeIgnored() throws {
        let card = try XCTUnwrap(draftCard(
            #"{"name":"王五","direction":"received","amountYuan":"300","ledgerType":"不存在的场合"}"#
        ))
        XCTAssertEqual(card.amountCents, 30_000)
        XCTAssertEqual(card.ledgerType, "") // 非法场合不落卡
    }

    // MARK: 对话持久化（存/读/清/上限）

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("advisor-chat-test-\(UUID().uuidString).json")
    }

    func testChatStoreRoundtripPreservesDraftState() throws {
        let url = tempURL()
        defer { AdvisorChatStore.clear(from: url) }
        var draft = AdvisorDraftRecordCard(
            person: "大舅", relation: "亲戚", direction: LiqianConstants.given,
            amountCents: 80_000, date: "2026-11-08",
            suggestedLedgerID: ledgerA, suggestedLedgerTitle: "敏杰婚礼"
        )
        draft.state = .saved
        draft.chosenLedgerID = ledgerA
        draft.savedRecordID = UUID()
        let messages: [AdvisorChatMessage] = [
            .init(kind: .user("给大舅回礼800")),
            .init(kind: .answer(text: "给你拟了一笔。", cards: [.draftRecord(draft)])),
            .init(kind: .result(.pendingList([]))),
            .init(kind: .note("账里查不到")),
        ]
        AdvisorChatStore.save(messages, to: url)
        let loaded = AdvisorChatStore.load(from: url)
        XCTAssertEqual(loaded, messages)
        AdvisorChatStore.clear(from: url)
        XCTAssertEqual(AdvisorChatStore.load(from: url), [])
    }

    func testChatStoreCapsHistory() {
        let url = tempURL()
        defer { AdvisorChatStore.clear(from: url) }
        let many = (0..<(AdvisorChatStore.maxMessages + 20)).map {
            AdvisorChatMessage(kind: .note("第 \($0) 条"))
        }
        AdvisorChatStore.save(many, to: url)
        let loaded = AdvisorChatStore.load(from: url)
        XCTAssertEqual(loaded.count, AdvisorChatStore.maxMessages)
        XCTAssertEqual(loaded.last?.kind, .note("第 \(AdvisorChatStore.maxMessages + 19) 条"))
    }

    // MARK: 滚动策略

    func testRollPlan() {
        // 从没存过 → 从 0 滚（首见入场）
        let first = RollingMoneyStore.plan(storedCents: nil, currentCents: 100_00)
        XCTAssertTrue(first.rolls)
        XCTAssertEqual(first.fromCents, 0)
        // 没变 → 不滚
        let same = RollingMoneyStore.plan(storedCents: 100_00, currentCents: 100_00)
        XCTAssertFalse(same.rolls)
        // 变了 → 从存档旧值滚
        let changed = RollingMoneyStore.plan(storedCents: 100_00, currentCents: 250_00)
        XCTAssertTrue(changed.rolls)
        XCTAssertEqual(changed.fromCents, 100_00)
    }

    func testRollStoreRoundtrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "liqian-test-\(UUID().uuidString)"))
        XCTAssertNil(RollingMoneyStore.storedCents(metricKey: "charts.net.all", defaults: defaults))
        RollingMoneyStore.store(cents: 42_00, metricKey: "charts.net.all", defaults: defaults)
        XCTAssertEqual(
            RollingMoneyStore.storedCents(metricKey: "charts.net.all", defaults: defaults), 42_00)
        // 另一指标键互不串扰
        XCTAssertNil(RollingMoneyStore.storedCents(metricKey: "charts.net.year-2026", defaults: defaults))
        let plan = RollingMoneyStore.plan(
            metricKey: "charts.net.all", currentCents: 42_00, defaults: defaults)
        XCTAssertFalse(plan.rolls)
    }
}
