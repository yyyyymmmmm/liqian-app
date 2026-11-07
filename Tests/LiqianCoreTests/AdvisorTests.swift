import XCTest
@testable import LiqianCore

// MARK: - 对话管家（v4.4）：意图解析只出参数不出数字、金额全走本地执行层

final class AdvisorTests: XCTestCase {
    private let currentYear = 2026

    // MARK: 夹具（顺序新→旧，与 AppSupport.snapshots 约定一致）
    // 大舅：收 2000（2026 婚礼）、随 500（2026 寿宴）→ 差额 +1500 待回
    // 张三：收 1000（2025 满月）、随 1000（2025 乔迁）→ 两清
    // 李四：随 300 待送出（不计入任何合计）
    // 王五：收 800（2026 婚礼）→ 待回 800
    private func fixture() -> [EntrySnapshot] {
        [
            EntrySnapshot(person: "李四", amountCents: 30_000, direction: LiqianConstants.given,
                          date: "2026-01-01", status: LiqianConstants.pendingStatus, ledgerType: "寿宴"),
            EntrySnapshot(person: "大舅", amountCents: 50_000, direction: LiqianConstants.given,
                          date: "2026-04-01", ledgerType: "寿宴"),
            EntrySnapshot(person: "大舅", amountCents: 200_000, direction: LiqianConstants.received,
                          date: "2026-03-01", ledgerType: "婚礼"),
            EntrySnapshot(person: "王五", amountCents: 80_000, direction: LiqianConstants.received,
                          date: "2026-02-01", ledgerType: "婚礼"),
            EntrySnapshot(person: "张三", amountCents: 100_000, direction: LiqianConstants.given,
                          date: "2025-06-01", ledgerType: "乔迁"),
            EntrySnapshot(person: "张三", amountCents: 100_000, direction: LiqianConstants.received,
                          date: "2025-05-01", ledgerType: "满月"),
        ]
    }

    // MARK: - 意图解码

    /// 模型夹带金额数字 → 解码结构无此字段，直接丢弃；意图参数照常落地
    func testDecodeDropsModelNumbers() throws {
        let json = """
        {"intent":"balance","person":"大舅","amount":999999,"amountYuan":12345,"totalCents":1}
        """
        let intent = try AdvisorIntentParse.decode(Data(json.utf8), currentYear: currentYear)
        XCTAssertEqual(intent.kind, .balance)
        XCTAssertEqual(intent.person, "大舅")
        XCTAssertNil(intent.year)
        XCTAssertNil(intent.direction)
    }

    /// 年份三种写法：数字、"last"、"this" 都换算成绝对年份
    func testDecodeYearVariants() throws {
        let byNumber = try AdvisorIntentParse.decode(
            Data(#"{"intent":"period","year":2024}"#.utf8), currentYear: currentYear)
        XCTAssertEqual(byNumber.year, 2024)

        let byLast = try AdvisorIntentParse.decode(
            Data(#"{"intent":"period","year":"last"}"#.utf8), currentYear: currentYear)
        XCTAssertEqual(byLast.year, 2025)

        let byThis = try AdvisorIntentParse.decode(
            Data(#"{"intent":"period","year":"this"}"#.utf8), currentYear: currentYear)
        XCTAssertEqual(byThis.year, 2026)
    }

    /// 表外意图 → unknown（不抛错，留给规则兜底/明示）；表外事由被过滤
    func testDecodeWhitelistFiltering() throws {
        let unknown = try AdvisorIntentParse.decode(
            Data(#"{"intent":"weather","person":"大舅"}"#.utf8), currentYear: currentYear)
        XCTAssertEqual(unknown.kind, .unknown)

        let badType = try AdvisorIntentParse.decode(
            Data(#"{"intent":"type","type":"打牌"}"#.utf8), currentYear: currentYear)
        XCTAssertEqual(badType.kind, .type)
        XCTAssertNil(badType.ledgerType)
    }

    /// 整体不是约定 JSON → 抛 unreadable
    func testDecodeGarbageThrows() {
        XCTAssertThrowsError(
            try AdvisorIntentParse.decode(Data("不是 JSON".utf8), currentYear: currentYear)
        ) { error in
            XCTAssertTrue(error is AdvisorIntentParse.ParseError)
        }
    }

    // MARK: - 规则兜底

    func testRulesPending() {
        let intent = AdvisorRules.intent(from: "谁还没回礼", people: ["大舅"], currentYear: currentYear)
        XCTAssertEqual(intent?.kind, .pending)
    }

    func testRulesBalanceWithPerson() {
        let intent = AdvisorRules.intent(
            from: "我和大舅谁欠谁", people: ["大舅", "张三"], currentYear: currentYear)
        XCTAssertEqual(intent?.kind, .balance)
        XCTAssertEqual(intent?.person, "大舅")
    }

    func testRulesPersonHistory() {
        let intent = AdvisorRules.intent(
            from: "张三随了多少", people: ["张三"], currentYear: currentYear)
        XCTAssertEqual(intent?.kind, .person)
        XCTAssertEqual(intent?.person, "张三")
    }

    func testRulesPeriodLastYear() {
        let intent = AdvisorRules.intent(
            from: "去年一共收了多少", people: ["大舅"], currentYear: currentYear)
        XCTAssertEqual(intent?.kind, .period)
        XCTAssertEqual(intent?.year, 2025)
        XCTAssertEqual(intent?.direction, LiqianConstants.received)
    }

    func testRulesTypeSummary() {
        let intent = AdvisorRules.intent(
            from: "婚礼一共收了多少", people: [], currentYear: currentYear)
        XCTAssertEqual(intent?.kind, .type)
        XCTAssertEqual(intent?.ledgerType, "婚礼")
    }

    func testRulesUnsupportedReturnsNil() {
        XCTAssertNil(AdvisorRules.intent(
            from: "今天天气怎么样", people: ["大舅"], currentYear: currentYear))
    }

    // MARK: - 执行层（金额只从本地快照算）

    func testEngineBalance() {
        let result = AdvisorEngine.execute(
            AdvisorIntent(kind: .balance, person: "大舅"), entries: fixture())
        guard case .balance(let summary) = result else {
            return XCTFail("应为差额结果，实际 \(result)")
        }
        XCTAssertEqual(summary.received, 200_000)
        XCTAssertEqual(summary.given, 50_000)
        XCTAssertEqual(summary.balance, 150_000)
        XCTAssertEqual(summary.pendingCents, 150_000)
    }

    /// 差额匹配：问名是账上名的子串也能命中，结果回带账上名
    func testEngineBalanceFuzzyMatch() {
        let result = AdvisorEngine.execute(
            AdvisorIntent(kind: .balance, person: "舅"), entries: fixture())
        guard case .balance(let summary) = result else {
            return XCTFail("应为差额结果，实际 \(result)")
        }
        XCTAssertEqual(summary.name, "大舅")
    }

    func testEnginePersonNotFoundAndNeedPerson() {
        let missing = AdvisorEngine.execute(
            AdvisorIntent(kind: .balance, person: "赵六"), entries: fixture())
        guard case .personNotFound(let name) = missing else {
            return XCTFail("应为未找到，实际 \(missing)")
        }
        XCTAssertEqual(name, "赵六")

        let noName = AdvisorEngine.execute(AdvisorIntent(kind: .balance), entries: fixture())
        XCTAssertEqual(noName, .needPerson)
    }

    func testEnginePendingList() {
        let result = AdvisorEngine.execute(AdvisorIntent(kind: .pending), entries: fixture())
        guard case .pendingList(let list) = result else {
            return XCTFail("应为待回名单，实际 \(result)")
        }
        XCTAssertEqual(list.map(\.name), ["大舅", "王五"]) // 按待回金额降序
        XCTAssertEqual(list.map(\.pendingCents), [150_000, 80_000])
    }

    /// 时段过滤：只算目标年份；待送出不计（李四 2026 那笔不进 2026 合计）
    func testEnginePeriodYearFilter() {
        let result2025 = AdvisorEngine.execute(
            AdvisorIntent(kind: .period, year: 2025), entries: fixture())
        guard case .periodSummary(_, _, let recv2025, let given2025, let count2025) = result2025 else {
            return XCTFail("应为时段汇总，实际 \(result2025)")
        }
        XCTAssertEqual(recv2025, 100_000)
        XCTAssertEqual(given2025, 100_000)
        XCTAssertEqual(count2025, 2)

        let resultAll = AdvisorEngine.execute(
            AdvisorIntent(kind: .period), entries: fixture())
        guard case .periodSummary(_, _, let recvAll, let givenAll, let countAll) = resultAll else {
            return XCTFail("应为时段汇总，实际 \(resultAll)")
        }
        XCTAssertEqual(recvAll, 380_000)
        XCTAssertEqual(givenAll, 150_000)
        XCTAssertEqual(countAll, 5)
    }

    func testEnginePersonHistory() {
        let result = AdvisorEngine.execute(
            AdvisorIntent(kind: .person, person: "张三"), entries: fixture())
        guard case .personHistory(let summary, let lines) = result else {
            return XCTFail("应为某人往来，实际 \(result)")
        }
        XCTAssertEqual(summary.balance, 0)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first?.date, "2025-06-01") // 日期倒序
        XCTAssertEqual(lines.first?.ledgerType, "乔迁")
    }

    func testEngineTypeSummary() {
        let result = AdvisorEngine.execute(
            AdvisorIntent(kind: .type, ledgerType: "婚礼"), entries: fixture())
        guard case .typeSummary(let rows, let focus) = result else {
            return XCTFail("应为事由统计，实际 \(result)")
        }
        XCTAssertEqual(focus, "婚礼")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.received, 280_000)
        XCTAssertEqual(rows.first?.count, 2)
    }
}
