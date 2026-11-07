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

// MARK: - 回礼参考区间（v2）

final class ReturnGiftSuggestionTests: XCTestCase {
    private func recv(_ person: String, _ cents: Int, _ date: String, type: String = "婚礼") -> EntrySnapshot {
        EntrySnapshot(
            person: person, amountCents: cents, direction: "收礼",
            date: date, ledgerType: type
        )
    }

    func testNilWhenNoReceived() {
        let entries = [
            EntrySnapshot(person: "张三", amountCents: 50000, direction: "随礼", date: "2024-01-01"),
        ]
        XCTAssertNil(LedgerMath.returnGiftSuggestion(from: entries, person: "张三", today: "2026-11-07"))
        XCTAssertNil(LedgerMath.returnGiftSuggestion(from: [], person: "张三", today: "2026-11-07"))
    }

    func testBase500() {
        let s = LedgerMath.returnGiftSuggestion(
            from: [recv("张三", 50000, "2023-05-01")], person: "张三", today: "2026-11-07"
        )
        XCTAssertEqual(s?.lowerCents, 50000)
        XCTAssertEqual(s?.upperCents, 60000)
        XCTAssertEqual(s?.lastAmountCents, 50000)
        XCTAssertEqual(s?.lastDate, "2023-05-01")
        XCTAssertEqual(s?.lastType, "婚礼")
        XCTAssertEqual(s?.yearsAgo, 3)
    }

    func testBase450() {
        // floor(450/100)*100=400；ceil(450*1.2/100)*100=ceil(5.4)*100=600
        let s = LedgerMath.returnGiftSuggestion(
            from: [recv("李四", 45000, "2025-01-01")], person: "李四", today: "2026-01-02"
        )
        XCTAssertEqual(s?.lowerCents, 40000)
        XCTAssertEqual(s?.upperCents, 60000)
    }

    func testUsesLatestReceived() {
        let s = LedgerMath.returnGiftSuggestion(
            from: [
                recv("王五", 20000, "2020-01-01"),
                recv("王五", 80000, "2024-06-01"),
                recv("王五", 30000, "2022-01-01"),
            ],
            person: "王五", today: "2026-11-07"
        )
        XCTAssertEqual(s?.lastAmountCents, 80000)
        XCTAssertEqual(s?.lowerCents, 80000)
        XCTAssertEqual(s?.upperCents, 100000) // ceil(960/100)*100 = 1000 元
    }

    func testSmallAmountLowerFloorsTo100() {
        let s = LedgerMath.returnGiftSuggestion(
            from: [recv("赵六", 5000, "2025-01-01")], person: "赵六", today: "2026-01-01"
        )
        XCTAssertEqual(s?.lowerCents, 10000) // 50 元 → 下限保底 100 元
        XCTAssertEqual(s?.upperCents, 10000) // ceil(60/100)*100 = 100 元
    }
}

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
