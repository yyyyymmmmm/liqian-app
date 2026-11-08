import XCTest
@testable import LiqianCore

// MARK: - 对话管家 v5.2 工具层：每工具至少两例（正常＋空/错），金额口径同 LedgerMath

final class AdvisorToolsTests: XCTestCase {
    // 夹具同 AdvisorTests 口径（新→旧）：
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

    private func run(_ name: String, _ args: String, ctx: AdvisorToolContext? = nil) throws -> [String: Any] {
        let text = AdvisorToolEngine.execute(
            AdvisorToolCall(name: name, argumentsJSON: args), context: ctx ?? context()
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: query_person

    func testQueryPersonFound() throws {
        let r = try run(AdvisorTools.queryPerson, #"{"name":"大舅"}"#)
        XCTAssertEqual(r["ok"] as? Bool, true)
        XCTAssertEqual(r["name"] as? String, "大舅")
        XCTAssertEqual(r["receivedYuan"] as? Double, 2000)
        XCTAssertEqual(r["givenYuan"] as? Double, 500)
        XCTAssertEqual(r["pendingYuan"] as? Double, 1500)
        XCTAssertEqual(r["recordCount"] as? Int, 2)
        XCTAssertEqual((r["recentRecords"] as? [[String: Any]])?.count, 2)
    }

    func testQueryPersonNotFoundAndMissingName() throws {
        let miss = try run(AdvisorTools.queryPerson, #"{"name":"赵六"}"#)
        XCTAssertEqual(miss["ok"] as? Bool, false)
        XCTAssertEqual(miss["found"] as? Bool, false)
        let noName = try run(AdvisorTools.queryPerson, #"{}"#)
        XCTAssertEqual(noName["ok"] as? Bool, false)
    }

    // MARK: query_records

    func testQueryRecordsByTypeAndDateRange() throws {
        let r = try run(
            AdvisorTools.queryRecords,
            #"{"ledgerType":"婚礼","dateFrom":"2026-01-01","dateTo":"2026-12-31"}"#
        )
        XCTAssertEqual(r["totalCount"] as? Int, 2)
        let rows = try XCTUnwrap(r["records"] as? [[String: Any]])
        XCTAssertEqual(Set(rows.compactMap { $0["person"] as? String }), ["大舅", "王五"])
        XCTAssertEqual(rows.first?["ledgerTitle"] as? String, "敏杰婚礼")
    }

    func testQueryRecordsEmptyResult() throws {
        let r = try run(AdvisorTools.queryRecords, #"{"person":"赵六"}"#)
        XCTAssertEqual(r["ok"] as? Bool, true)
        XCTAssertEqual(r["totalCount"] as? Int, 0)
        XCTAssertEqual((r["records"] as? [[String: Any]])?.count, 0)
    }

    // MARK: aggregate

    func testAggregateComparePeriods() throws {
        let r = try run(
            AdvisorTools.aggregate,
            #"{"groupBy":"none","dateFrom":"2026-01-01","dateTo":"2026-12-31","compareFrom":"2025-01-01","compareTo":"2025-12-31"}"#
        )
        let totals = try XCTUnwrap(r["totals"] as? [String: Any])
        XCTAssertEqual(totals["receivedYuan"] as? Double, 2800)
        XCTAssertEqual(totals["givenYuan"] as? Double, 500)
        let cmp = try XCTUnwrap(r["comparison"] as? [String: Any])
        let cmpTotals = try XCTUnwrap(cmp["totals"] as? [String: Any])
        XCTAssertEqual(cmpTotals["receivedYuan"] as? Double, 1000)
        XCTAssertEqual(cmp["deltaReceivedYuan"] as? Double, 1800)
    }

    func testAggregateGroupByTypeAndEmpty() throws {
        let r = try run(AdvisorTools.aggregate, #"{"groupBy":"type"}"#)
        let groups = try XCTUnwrap(r["groups"] as? [[String: Any]])
        let wedding = try XCTUnwrap(groups.first { $0["group"] as? String == "婚礼" })
        XCTAssertEqual(wedding["receivedYuan"] as? Double, 2800)
        let empty = try run(AdvisorTools.aggregate, #"{"groupBy":"month"}"#, ctx: context(entries: []))
        XCTAssertEqual((empty["groups"] as? [[String: Any]])?.count, 0)
        let totals = try XCTUnwrap(empty["totals"] as? [String: Any])
        XCTAssertEqual(totals["recordCount"] as? Int, 0)
    }

    // MARK: pending_list

    func testPendingListSortedAndTotals() throws {
        let r = try run(AdvisorTools.pendingList, #"{}"#)
        XCTAssertEqual(r["totalPeople"] as? Int, 2)
        XCTAssertEqual(r["totalPendingYuan"] as? Double, 2300)
        let people = try XCTUnwrap(r["people"] as? [[String: Any]])
        XCTAssertEqual(people.first?["name"] as? String, "大舅")
        XCTAssertEqual(people.first?["pendingYuan"] as? Double, 1500)
    }

    func testPendingListEmpty() throws {
        let only = [EntrySnapshot(person: "张三", amountCents: 100_000, direction: LiqianConstants.given,
                                   date: "2025-06-01", ledgerType: "乔迁")]
        let r = try run(AdvisorTools.pendingList, #"{}"#, ctx: context(entries: only))
        XCTAssertEqual(r["totalPeople"] as? Int, 0)
        XCTAssertEqual((r["people"] as? [[String: Any]])?.count, 0)
    }

    // MARK: upcoming_events

    func testUpcomingEvents() throws {
        let r = try run(AdvisorTools.upcomingEvents, #"{}"#)
        let events = try XCTUnwrap(r["upcomingEvents"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1) // 婚礼（2026-03-01）已过，只剩满月
        XCTAssertEqual(events.first?["title"] as? String, "小宝满月")
        XCTAssertEqual(events.first?["daysUntil"] as? Int, 8)
        XCTAssertEqual(r["prepPendingCount"] as? Int, 1) // 李四待送出
    }

    func testUpcomingEventsEmpty() throws {
        let ctx = AdvisorToolContext(entries: [], ledgers: [], today: "2026-11-08")
        let r = try run(AdvisorTools.upcomingEvents, #"{}"#, ctx: ctx)
        XCTAssertEqual((r["upcomingEvents"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(r["prepPendingCount"] as? Int, 0)
    }

    // MARK: 未知工具 / 定义清单

    func testUnknownToolReturnsReadableError() throws {
        let r = try run("fly_to_moon", #"{}"#)
        XCTAssertEqual(r["ok"] as? Bool, false)
        XCTAssertNotNil(r["error"] as? String)
    }

    func testDefinitionsCoverAllTools() throws {
        let data = Data(AdvisorTools.definitionsJSON().utf8)
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(Set(names), Set(AdvisorTools.allNames))
    }
}
