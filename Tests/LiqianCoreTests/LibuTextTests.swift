import XCTest
@testable import LiqianCore

// MARK: - 金额大写·正式财务繁体（v2.8 礼谱 PDF 专用）

final class MoneyTextTraditionalTests: XCTestCase {
    func testZero() {
        XCTAssertEqual(MoneyText.chineseUppercaseTraditional(cents: 0), "零圓整")
    }

    func testWholeHundreds() {
        XCTAssertEqual(MoneyText.chineseUppercaseTraditional(cents: 50000), "伍佰圓整")
    }

    func testWithJiaoFen() {
        // 1666.55 元：带角分不收「整」
        XCTAssertEqual(
            MoneyText.chineseUppercaseTraditional(cents: 166655),
            "壹仟陸佰陸拾陸圓伍角伍分"
        )
        // 元不为 0、角为 0、分不为 0：补零（读法与简体版一致）
        XCTAssertEqual(MoneyText.chineseUppercaseTraditional(cents: 105), "壹圓零伍分")
        // 元为 0 不带整
        XCTAssertEqual(MoneyText.chineseUppercaseTraditional(cents: 50), "伍角")
    }

    func testWanLevel() {
        XCTAssertEqual(MoneyText.chineseUppercaseTraditional(cents: 1000000), "壹萬圓整")
        // 节间前导零补「零」：1000010 元
        XCTAssertEqual(
            MoneyText.chineseUppercaseTraditional(cents: 100001000),
            "壹佰萬零壹拾圓整"
        )
    }

    func testYiLevel() {
        XCTAssertEqual(MoneyText.chineseUppercaseTraditional(cents: 10000000000), "壹億圓整")
        // 123,456,789 元
        XCTAssertEqual(
            MoneyText.chineseUppercaseTraditional(cents: 12345678900),
            "壹億貳仟參佰肆拾伍萬陸仟柒佰捌拾玖圓整"
        )
    }

    func testNegative() {
        XCTAssertEqual(MoneyText.chineseUppercaseTraditional(cents: -50000), "負伍佰圓整")
    }

    /// 简体版不得被繁体改造污染（App 内显示口径独立）
    func testSimplifiedUnaffected() {
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 166600), "壹仟陆佰陆拾陆元整")
        XCTAssertEqual(MoneyText.chineseUppercase(cents: 1000000), "壹万元整")
    }
}

// MARK: - 农历月日（v2.8 礼谱逐笔日期）

final class LunarMonthDayTests: XCTestCase {
    func testMonthDay() {
        // 2026-11-16 = 农历十月初八（婚礼请柬定版口径）
        XCTAssertEqual(LiqianDate.lunarMonthDay(for: "2026-11-16"), "十月初八")
    }

    func testLeapMonth() {
        // 2020-05-23 = 闰四月初一（2020 年闰四月）
        XCTAssertEqual(LiqianDate.lunarMonthDay(for: "2020-05-23"), "闰四月初一")
    }
}

// MARK: - 生成串繁体映射（v2.8；只许喂程序生成串）

final class LibuTextTests: XCTestCase {
    func testGeneratedMapping() {
        XCTAssertEqual(LibuText.traditionalGenerated("闰四月"), "閏四月")
        XCTAssertEqual(LibuText.traditionalGenerated("丙午腊月"), "丙午臘月")
        // 繁简同形字不动
        XCTAssertEqual(LibuText.traditionalGenerated("丙午年十月初八"), "丙午年十月初八")
    }
}
