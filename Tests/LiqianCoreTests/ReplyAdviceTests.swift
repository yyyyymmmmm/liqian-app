import XCTest
@testable import LiqianCore

// MARK: - 回礼建议区间模型（v4.3：锚×年涨幅×场合系数×红白取整＋理由）

final class ReplyAdviceTests: XCTestCase {
    private func recv(_ person: String, _ cents: Int, _ date: String, type: String = "婚礼") -> EntrySnapshot {
        EntrySnapshot(
            person: person, amountCents: cents, direction: LiqianConstants.received,
            date: date, ledgerType: type
        )
    }

    // 无历史 → nil（两条回退路径都测：空集、只有随礼）
    func testNilWhenNoReceived() {
        let givenOnly = [
            EntrySnapshot(person: "张三", amountCents: 50000, direction: LiqianConstants.given, date: "2024-01-01"),
        ]
        XCTAssertNil(ReplyAdvisor.advice(from: givenOnly, person: "张三", occasionType: "婚礼", today: "2026-11-07"))
        XCTAssertNil(ReplyAdvisor.advice(from: [], person: "张三", occasionType: "婚礼", today: "2026-11-07"))
        XCTAssertNil(ReplyAdvisor.advice(
            from: [recv("李四", 50000, "2024-01-01")], person: "张三", occasionType: "婚礼", today: "2026-11-07"
        ))
    }

    // 红事取整：锚恰整百 → 区间 [锚, 锚+100]，建议值＝锚
    func testHongRoundHundredAnchor() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 50000, "2026-05-01")], person: "张三",
            occasionType: "婚礼", today: "2026-11-07"
        )
        XCTAssertEqual(s?.lowerCents, 50000)
        XCTAssertEqual(s?.suggestedCents, 50000)
        XCTAssertEqual(s?.upperCents, 60000)
        XCTAssertEqual(s?.anchorSource, .latest)
        XCTAssertTrue(s?.reasons.first?.contains("上次他随你 ¥500") ?? false)
        XCTAssertTrue(s?.reasons.last?.contains("红事取整到 ¥500") ?? false)
    }

    // 红事取整：非整百锚 → 建议值向上取整到百，区间 [向下整百, 建议值]
    func testHongRoundUpNonHundred() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 45000, "2026-05-01")], person: "张三",
            occasionType: "婚礼", today: "2026-11-07"
        )
        XCTAssertEqual(s?.lowerCents, 40000)
        XCTAssertEqual(s?.suggestedCents, 50000)
        XCTAssertEqual(s?.upperCents, 50000)
    }

    // 红事小额：尾 6/8 吉数档（50 → 66）
    func testHongSmallAmountLuckyTail() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 5000, "2026-05-01")], person: "张三",
            occasionType: "婚礼", today: "2026-11-07"
        )
        XCTAssertEqual(s?.suggestedCents, 6600)
        XCTAssertEqual(s?.lowerCents, 6600)
        XCTAssertEqual(s?.upperCents, 8800)
    }

    // 多年涨幅：500（2023）×1.03³ ≈ 546 → 建议 600，理由含折算数
    func testGrowthCompoundsByYears() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 50000, "2023-05-01")], person: "张三",
            occasionType: "婚礼", today: "2026-11-07", annualRatePercent: 3
        )
        XCTAssertEqual(s?.yearsAgo, 3)
        XCTAssertEqual(s?.lowerCents, 50000)
        XCTAssertEqual(s?.suggestedCents, 60000)
        XCTAssertEqual(s?.upperCents, 60000)
        XCTAssertTrue(s?.reasons.contains { $0.contains("年涨幅 3%") && $0.contains("¥546") } ?? false)
    }

    // 年率 0：不折算、无涨幅理由
    func testZeroRateSkipsGrowth() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 50000, "2023-05-01")], person: "张三",
            occasionType: "婚礼", today: "2026-11-07", annualRatePercent: 0
        )
        XCTAssertEqual(s?.suggestedCents, 50000)
        XCTAssertFalse(s?.reasons.contains { $0.contains("年涨幅") } ?? true)
    }

    // 白事单数：500 → 501（整百加 1），区间 [501, 601]，理由含免责
    func testBaiOddAmountFromHundred() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 50000, "2026-05-01", type: "白事")], person: "张三",
            occasionType: "白事", today: "2026-11-07"
        )
        XCTAssertEqual(s?.isBai, true)
        XCTAssertEqual(s?.lowerCents, 50100)
        XCTAssertEqual(s?.suggestedCents, 50100)
        XCTAssertEqual(s?.upperCents, 60100)
        XCTAssertEqual((s?.suggestedCents ?? 0) % 200, 100) // 元位为奇数百+1
        XCTAssertTrue(s?.reasons.contains { $0.contains("白事取单数") && $0.contains("以当地为准") } ?? false)
    }

    // 白事单数：450 → [401, 501]
    func testBaiOddAmountFromNonHundred() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 45000, "2026-05-01", type: "白事")], person: "张三",
            occasionType: "白事", today: "2026-11-07"
        )
        XCTAssertEqual(s?.lowerCents, 40100)
        XCTAssertEqual(s?.suggestedCents, 50100)
        XCTAssertEqual(s?.upperCents, 50100)
    }

    // 白事不打场合折：系数恒 1.0（映射表对白事也不折算）
    func testBaiCoefficientIsOne() {
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "白事"), 1.0)
    }

    // 场合系数映射：满月 0.8 / 乔迁 0.9 / 婚礼 1.0 / 未知 1.0
    func testCoefficientTable() {
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "婚礼"), 1.0)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "寿宴"), 1.0)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "开业"), 1.0)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "乔迁"), 0.9)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "升学"), 0.9)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "满月"), 0.8)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "周岁"), 0.8)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "其他"), 1.0)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: ""), 1.0)
        XCTAssertEqual(ReplyAdvisor.coefficient(for: "自定义事由"), 1.0)
    }

    // 系数落到金额：1000 满月 → 800 为锚定值
    func testOccasionCoefficientApplies() {
        let s = ReplyAdvisor.advice(
            from: [recv("张三", 100000, "2026-05-01")], person: "张三",
            occasionType: "满月", today: "2026-11-07"
        )
        XCTAssertEqual(s?.suggestedCents, 80000)
        XCTAssertEqual(s?.lowerCents, 80000)
        XCTAssertEqual(s?.upperCents, 90000)
        XCTAssertTrue(s?.reasons.contains { $0.contains("满月") && $0.contains("八成") } ?? false)
    }

    // 锚取最近一笔（不是最大笔）
    func testAnchorIsLatestNotMaximum() {
        let s = ReplyAdvisor.advice(
            from: [
                recv("王五", 80000, "2020-01-01"),
                recv("王五", 30000, "2026-01-01"),
                recv("王五", 50000, "2022-01-01"),
            ],
            person: "王五", occasionType: "婚礼", today: "2026-11-07"
        )
        XCTAssertEqual(s?.anchorAmountCents, 30000)
        XCTAssertEqual(s?.anchorDate, "2026-01-01")
        XCTAssertEqual(s?.anchorSource, .latest)
    }

    // 锚回退序（选择函数三档直测）：最近 → 最大 → 中位
    func testPickAnchorFallbackOrder() {
        let latest = ReplyAdvisor.pickAnchor(latest: (30000, "2026-01-01", "婚礼"), maximumCents: 80000, medianCents: 50000)
        XCTAssertEqual(latest?.amountCents, 30000)
        XCTAssertEqual(latest?.source, .latest)

        let byMax = ReplyAdvisor.pickAnchor(latest: nil, maximumCents: 80000, medianCents: 50000)
        XCTAssertEqual(byMax?.amountCents, 80000)
        XCTAssertEqual(byMax?.source, .maximum)

        let byMedian = ReplyAdvisor.pickAnchor(latest: nil, maximumCents: nil, medianCents: 50000)
        XCTAssertEqual(byMedian?.amountCents, 50000)
        XCTAssertEqual(byMedian?.source, .median)

        XCTAssertNil(ReplyAdvisor.pickAnchor(latest: nil, maximumCents: nil, medianCents: nil))
    }

    // 回退实景：收礼日期全部损坏（不可解析）→ 走历史最大，理由如实说明
    func testFallbackToMaximumWhenDatesBroken() {
        let s = ReplyAdvisor.advice(
            from: [
                recv("张三", 30000, ""),
                recv("张三", 80000, "未知"),
            ],
            person: "张三", occasionType: "婚礼", today: "2026-11-07"
        )
        XCTAssertEqual(s?.anchorSource, .maximum)
        XCTAssertEqual(s?.anchorAmountCents, 80000)
        XCTAssertTrue(s?.reasons.first?.contains("最高一笔") ?? false)
    }
}
