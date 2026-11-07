import XCTest
@testable import LiqianCore

// MARK: - 金额中文大写（v2 礼谱）

final class MoneyTextTests: XCTestCase {
    func testUppercaseSamples() {
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 0), "零元整")
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 50000), "伍佰元整")
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 166600), "壹仟陆佰陆拾陆元整")
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 1000000), "壹万元整") // 1 万元
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 105), "壹元零伍分")
        // 1000010 元：节间前导零补「零」
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 100001000), "壹佰万零壹拾元整")
    }

    func testUppercaseSubYuanNoZheng() {
        // 固定口径：元为 0 时不带「整」
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 50), "伍角")
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 5), "伍分")
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 55), "伍角伍分")
    }

    func testUppercaseJiaoOnlyWithYuanGetsZheng() {
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 150), "壹元伍角整")
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 10000000), "壹拾万元整") // 10 万元
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 100000000), "壹佰万元整") // 100 万元
    }
}

// MARK: - 回礼参考区间（v2）已由 v4.3 的 ReplyAdviceTests 替换（新模型见 ReplyAdvice.swift）

// MARK: - 批量粘贴解析（v2）

final class LedgerTextParserTests: XCTestCase {
    func testSpaceSeparated() {
        let r = LedgerTextParser.parse("张三 500")
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].result, .success(name: "张三", amountCents: 50000, relation: nil))
    }

    func testChineseCommaAndYuanSuffix() {
        let r = LedgerTextParser.parse("李四，200元")
        XCTAssertEqual(r[0].result, .success(name: "李四", amountCents: 20000, relation: nil))
    }

    func testYenPrefixAndRelation() {
        let r = LedgerTextParser.parse("王五 ¥800 亲戚")
        XCTAssertEqual(r[0].result, .success(name: "王五", amountCents: 80000, relation: "亲戚"))
    }

    func testDecimalYuanRoundsToCents() {
        let r = LedgerTextParser.parse("赵六 66.5")
        XCTAssertEqual(r[0].result, .success(name: "赵六", amountCents: 6650, relation: nil))
    }

    func testBadLineFails() {
        let r = LedgerTextParser.parse("坏行 abc")
        XCTAssertEqual(r.count, 1)
        if case .failure = r[0].result {} else {
            XCTFail("应解析失败")
        }
    }

    func testEmptyLinesSkippedButLineNoPreserved() {
        let r = LedgerTextParser.parse("张三 500\n\n\n李四 200")
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].lineNo, 1)
        XCTAssertEqual(r[1].lineNo, 4)
    }

    func testTwoCharArbitraryRelationAccepted() {
        let r = LedgerTextParser.parse("钱七\t300\t战友")
        XCTAssertEqual(r[0].result, .success(name: "钱七", amountCents: 30000, relation: "战友"))
    }

    func testZeroAmountFails() {
        let r = LedgerTextParser.parse("张三 0")
        if case .failure = r[0].result {} else {
            XCTFail("金额 0 应失败")
        }
    }
}

// MARK: - 干支纪年与月份雅称（礼谱 v3）

final class GanzhiTests: XCTestCase {
    func testGanzhiYearAssertions() {
        // 规范断言（LIBU-V3-SPEC §2）：以农历年推干支
        XCTAssertEqual(LiqianDate.ganzhiYear(for: "2026-11-16"), "丙午")
        XCTAssertEqual(LiqianDate.ganzhiYear(for: "2025-01-29"), "乙巳")
        XCTAssertEqual(LiqianDate.ganzhiYear(for: "2024-02-10"), "甲辰")
        // 锚点：2023 年春节（癸卯年正月初一）
        XCTAssertEqual(LiqianDate.ganzhiYear(for: "2023-01-22"), "癸卯")
    }

    func testGanzhiFullDate() {
        XCTAssertEqual(LiqianDate.ganzhiFullDate(for: "2026-11-16"), "丙午年十月初八")
    }

    func testLunarMonthAlias() {
        // 2026-11-16 是农历十月 → 冬月
        XCTAssertEqual(LiqianDate.lunarMonthAlias(for: "2026-11-16"), "冬月")
        XCTAssertEqual(LiqianDate.lunarMonthAlias(month: 1), "端月")
        XCTAssertEqual(LiqianDate.lunarMonthAlias(month: 12), "腊月")
    }
}
