import XCTest
@testable import LiqianCore

// MARK: - 对话管家 v5.3：工具结果 → UI 卡片模型映射
// 卡片必须与回给模型的 JSON 出自同一次计算：同一夹具下逐项对数
//（卡片是分口径、JSON 是元口径，换算关系 1 元 = 100 分）。

final class AdvisorCardsTests: XCTestCase {
    // 夹具同 AdvisorToolsTests 口径（新→旧）：
    // 大舅 收 2000（2026 婚礼）/ 随 500（2026 寿宴）→ 待回 1500
    // 王五 收 800（2026 婚礼）→ 待回 800；张三 2025 收/随各 1000 → 两清
    // 李四 随 300 待送出（备礼，不计汇总）
    private let ledgerID = UUID()

    private func fixture() -> [EntrySnapshot] {
        [
            EntrySnapshot(person: "李四", amountCents: 30_000, direction: LiqianConstants.given,
                          date: "2026-11-20", status: LiqianConstants.pendingStatus, ledgerType: "寿宴"),
            EntrySnapshot(person: "大舅", amountCents: 50_000, direction: LiqianConstants.given,
                          date: "2026-04-01", ledgerType: "寿宴"),
            EntrySnapshot(person: "大舅", amountCents: 200_000, direction: LiqianConstants.received,
                          date: "2026-03-01", ledgerType: "婚礼", ledgerID: ledgerID),
            EntrySnapshot(person: "王五", amountCents: 80_000, direction: LiqianConstants.received,
                          date: "2026-02-01", ledgerType: "婚礼", ledgerID: ledgerID),
            EntrySnapshot(person: "张三", amountCents: 100_000, direction: LiqianConstants.given,
                          date: "2025-06-01", ledgerType: "乔迁"),
            EntrySnapshot(person: "张三", amountCents: 100_000, direction: LiqianConstants.received,
                          date: "2025-05-01", ledgerType: "满月"),
        ]
    }

    private func context(entries: [EntrySnapshot]? = nil) -> AdvisorToolContext {
        AdvisorToolContext(
            entries: entries ?? fixture(),
            ledgers: [
                .init(id: ledgerID, title: "敏杰婚礼", type: "婚礼", date: "2026-03-01"),
                .init(title: "小宝满月", type: "满月", date: "2026-11-16"),
            ],
            today: "2026-11-08"
        )
    }

    private func run(_ name: String, _ args: String, ctx: AdvisorToolContext? = nil) -> AdvisorToolOutcome {
        AdvisorToolEngine.executeDetailed(
            AdvisorToolCall(name: name, argumentsJSON: args), context: ctx ?? context()
        )
    }

    /// JSON 与 v5.2 的 execute 语义一致（卡片是加挂，不能改模型侧口径）。
    /// 注意比对的是解析后的对象而非原文字符串：JSONSerialization 的键序
    /// 每次序列化随机，逐字比对必然 flaky——模型消费的是对象语义。
    func testDetailedJSONMatchesExecute() throws {
        let cases: [(String, String)] = [
            (AdvisorTools.queryPerson, #"{"name":"大舅"}"#),
            (AdvisorTools.queryRecords, #"{"ledgerType":"婚礼"}"#),
            (AdvisorTools.aggregate, #"{"groupBy":"type"}"#),
            (AdvisorTools.pendingList, #"{}"#),
            (AdvisorTools.upcomingEvents, #"{}"#),
            ("fly_to_moon", #"{}"#),
        ]
        for (name, args) in cases {
            let call = AdvisorToolCall(name: name, argumentsJSON: args)
            let detailed = AdvisorToolEngine.executeDetailed(call, context: context()).json
            let plain = AdvisorToolEngine.execute(call, context: context())
            let a = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(detailed.utf8)) as? NSDictionary)
            let b = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(plain.utf8)) as? NSDictionary)
            XCTAssertEqual(a, b, "工具 \(name) 的 JSON 不应因卡片加挂而变化")
        }
    }

    // MARK: query_person → 人物卡

    func testPersonCard() throws {
        let outcome = run(AdvisorTools.queryPerson, #"{"name":"大舅"}"#)
        guard case .person(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("应出人物卡，实际 \(String(describing: outcome.card))")
        }
        XCTAssertEqual(card.summary.name, "大舅")
        XCTAssertEqual(card.summary.received, 200_000)
        XCTAssertEqual(card.summary.given, 50_000)
        XCTAssertEqual(card.summary.pendingCents, 150_000)
        XCTAssertEqual(card.recent.count, 2)
        XCTAssertEqual(card.recent.first?.amountCents, 50_000) // 日期倒序：2026-04-01 在前
    }

    func testPersonCardNilWhenNotFound() {
        let outcome = run(AdvisorTools.queryPerson, #"{"name":"赵六"}"#)
        XCTAssertNil(outcome.card)
    }

    // MARK: query_records → 流水卡

    func testRecordsCard() throws {
        let outcome = run(AdvisorTools.queryRecords, #"{"ledgerType":"婚礼"}"#)
        guard case .records(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("应出流水卡")
        }
        XCTAssertEqual(card.totalCount, 2)
        XCTAssertEqual(card.rows.count, 2)
        XCTAssertEqual(Set(card.rows.map(\.person)), ["大舅", "王五"])
        XCTAssertEqual(card.rows.first?.ledgerTitle, "敏杰婚礼")
        XCTAssertEqual(card.rows.first?.amountCents, 200_000)
    }

    func testRecordsCardNilWhenEmpty() {
        let outcome = run(AdvisorTools.queryRecords, #"{"person":"赵六"}"#)
        XCTAssertNil(outcome.card)
    }

    // MARK: aggregate → 对比卡 / 分组卡 / 汇总卡

    func testComparisonCard() throws {
        let outcome = run(
            AdvisorTools.aggregate,
            #"{"groupBy":"none","dateFrom":"2026-01-01","dateTo":"2026-12-31","compareFrom":"2025-01-01","compareTo":"2025-12-31"}"#
        )
        guard case .comparison(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("应出对比卡")
        }
        XCTAssertEqual(card.main.receivedCents, 280_000)
        XCTAssertEqual(card.main.givenCents, 50_000)
        XCTAssertEqual(card.other.receivedCents, 100_000)
        XCTAssertEqual(card.deltaReceivedCents, 180_000)
        XCTAssertEqual(card.deltaNetCents, 230_000)
        XCTAssertEqual(card.main.rangeLabel, "2026-01-01 至 2026-12-31")
    }

    func testGroupsCard() throws {
        let outcome = run(AdvisorTools.aggregate, #"{"groupBy":"type"}"#)
        guard case .groups(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("应出分组卡")
        }
        XCTAssertEqual(card.dimension, "type")
        let wedding = try XCTUnwrap(card.rows.first { $0.key == "婚礼" })
        XCTAssertEqual(wedding.receivedCents, 280_000)
        XCTAssertEqual(wedding.recordCount, 2)
    }

    func testTotalsCard() throws {
        let outcome = run(AdvisorTools.aggregate, #"{"dateFrom":"2026-01-01","dateTo":"2026-12-31"}"#)
        guard case .totals(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("应出汇总卡")
        }
        XCTAssertEqual(card.totals.receivedCents, 280_000)
        XCTAssertEqual(card.totals.givenCents, 50_000)
        XCTAssertEqual(card.totals.netCents, 230_000)
        XCTAssertEqual(card.totals.recordCount, 3)
    }

    /// 对比与分组同时存在时对比卡优先（定版优先级）
    func testComparisonWinsOverGroups() throws {
        let outcome = run(
            AdvisorTools.aggregate,
            #"{"groupBy":"month","dateFrom":"2026-01-01","dateTo":"2026-12-31","compareFrom":"2025-01-01","compareTo":"2025-12-31"}"#
        )
        guard case .comparison = try XCTUnwrap(outcome.card) else {
            return XCTFail("对比与分组并存时应对出对比卡")
        }
    }

    // MARK: pending_list → 名单卡

    func testPendingCard() throws {
        let outcome = run(AdvisorTools.pendingList, #"{}"#)
        guard case .pending(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("应出名单卡")
        }
        XCTAssertEqual(card.totalPeople, 2)
        XCTAssertEqual(card.totalPendingCents, 230_000)
        XCTAssertEqual(card.people.first?.name, "大舅")
        XCTAssertEqual(card.people.first?.pendingCents, 150_000)
    }

    func testPendingCardEmptyStillCards() throws {
        let only = [EntrySnapshot(person: "张三", amountCents: 100_000, direction: LiqianConstants.given,
                                   date: "2025-06-01", ledgerType: "乔迁")]
        let outcome = run(AdvisorTools.pendingList, #"{}"#, ctx: context(entries: only))
        guard case .pending(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("空名单也应出卡（都结清了的空态）")
        }
        XCTAssertEqual(card.totalPeople, 0)
        XCTAssertTrue(card.people.isEmpty)
    }

    // MARK: upcoming_events → 场次卡

    func testEventsCard() throws {
        let outcome = run(AdvisorTools.upcomingEvents, #"{}"#)
        guard case .events(let card) = try XCTUnwrap(outcome.card) else {
            return XCTFail("应出场次卡")
        }
        XCTAssertEqual(card.events.count, 1)
        XCTAssertEqual(card.events.first?.title, "小宝满月")
        XCTAssertEqual(card.events.first?.daysUntil, 8)
        XCTAssertEqual(card.prepTotalCount, 1)
        XCTAssertEqual(card.prep.first?.person, "李四")
        XCTAssertEqual(card.prep.first?.isPendingSend, true)
    }

    // MARK: 未知工具不出卡

    func testUnknownToolNoCard() {
        let outcome = run("fly_to_moon", #"{}"#)
        XCTAssertNil(outcome.card)
    }
}
