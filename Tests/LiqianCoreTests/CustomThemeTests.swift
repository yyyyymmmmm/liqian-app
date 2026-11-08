import XCTest
@testable import LiqianCore

/// v5.9：自定义主题派生引擎——对比度护栏、原样保留、金额防撞、
/// 就近匹配。断言以不变量为主（达标线、切换值、色相保持），
/// 精确值只钉已实算过的定版口径。
final class CustomThemeTests: XCTestCase {

    // MARK: 色彩数学基础

    func testContrastBlackWhiteIs21() {
        XCTAssertEqual(CustomTheme.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.1)
        // 对称性
        XCTAssertEqual(CustomTheme.contrastRatio(0xFFFFFF, 0x000000), 21, accuracy: 0.1)
    }

    func testHSLRoundTrip() {
        for hexValue: UInt32 in [0xA62B1F, 0x14665A, 0x007AFF, 0xE8A20C, 0x232323, 0xFAF9F7] {
            let hsl = CustomTheme.hsl(of: hexValue)
            let back = CustomTheme.hex(h: hsl.h, s: hsl.s, l: hsl.l)
            XCTAssertEqual(back, hexValue, "HSL 往返应无损：\(String(hexValue, radix: 16))")
        }
    }

    func testHueDistanceWrapsAround() {
        XCTAssertEqual(CustomTheme.hueDistance(350, 10), 20, accuracy: 0.001)
        XCTAssertEqual(CustomTheme.hueDistance(0, 180), 180, accuracy: 0.001)
        XCTAssertEqual(CustomTheme.hueDistance(171, 171), 0, accuracy: 0.001)
    }

    func testDaiqingHueAndBackupContrast() {
        // 防撞规则的两个锚点：黛青色相 ≈171°；备用黛紫靛对白达标有余量
        XCTAssertEqual(CustomTheme.hsl(of: CustomTheme.standardMoneyGivenHex).h, 171, accuracy: 2)
        XCTAssertGreaterThanOrEqual(
            CustomTheme.contrastRatio(CustomTheme.backupMoneyGivenHex, 0xFFFFFF), 4.5)
        // 备用色与黛青的色相夹角须明显大于撞色阈值（否则换了也白换）
        let gap = CustomTheme.hueDistance(
            CustomTheme.hsl(of: CustomTheme.backupMoneyGivenHex).h,
            CustomTheme.hsl(of: CustomTheme.standardMoneyGivenHex).h)
        XCTAssertGreaterThan(gap, CustomTheme.collisionHueThreshold * 2)
    }

    // MARK: 派生护栏（不变量：一组代表性基色全过）

    func testDerivedTokensAlwaysPassGuardrails() {
        let bases: [UInt32] = [
            0xA62B1F, 0xE1251B, 0x007AFF, 0x0052D9, 0x232323, 0xE8A20C,
            0x1F9E8A, 0x2E9E5B, 0xD96A5C, 0xF5C6D6, 0xFFF200, 0x7C4DBE,
        ]
        for base in bases {
            let t = CustomTheme.tokens(baseHex: base)
            let label = String(base, radix: 16)
            XCTAssertGreaterThanOrEqual(CustomTheme.contrastRatio(t.primary, t.pageBG), 4.5, label)
            XCTAssertGreaterThanOrEqual(CustomTheme.contrastRatio(t.primary, t.surface), 4.5, label)
            XCTAssertGreaterThanOrEqual(CustomTheme.contrastRatio(0xFFFFFF, t.primaryFill), 4.5, label)
            XCTAssertGreaterThanOrEqual(CustomTheme.contrastRatio(t.moneyGiven, t.pageBG), 4.5, label)
            XCTAssertGreaterThanOrEqual(CustomTheme.contrastRatio(t.moneyGiven, t.surface), 4.5, label)
            // fill 必须比 primary 更深（填充深档口径）
            XCTAssertLessThan(
                CustomTheme.relativeLuminance(t.primaryFill),
                CustomTheme.relativeLuminance(t.primary), label)
            // tint 必须比 primary 更浅（衬底口径）
            XCTAssertGreaterThan(
                CustomTheme.relativeLuminance(t.primaryTint),
                CustomTheme.relativeLuminance(t.primary), label)
        }
    }

    func testCompliantBaseKeptVerbatim() {
        // 朱砂、腾讯蓝、石墨灰、黑：本身全达标，primary 一分不动
        for base: UInt32 in [0xA62B1F, 0x0052D9, 0x4E5969, 0x232323] {
            XCTAssertEqual(CustomTheme.tokens(baseHex: base).primary, base,
                           String(base, radix: 16))
            XCTAssertFalse(CustomTheme.isAdjusted(baseHex: base))
        }
    }

    func testLightBaseIsDarkenedKeepingHue() {
        // 亮黄直接当文字色必然不达标：护栏调深、色相保持、如实标记已调整
        let base: UInt32 = 0xE8A20C
        let t = CustomTheme.tokens(baseHex: base)
        XCTAssertNotEqual(t.primary, base)
        XCTAssertTrue(CustomTheme.isAdjusted(baseHex: base))
        XCTAssertEqual(
            CustomTheme.hsl(of: t.primary).h,
            CustomTheme.hsl(of: base).h, accuracy: 1.5)
        XCTAssertGreaterThanOrEqual(CustomTheme.contrastRatio(t.primary, t.surface), 4.5)
    }

    func testNeutralsReuseDayScaffold() {
        // 中性脚手架与页面底口径：ink/sub/line 复用白天，surface 纯白
        let t = CustomTheme.tokens(baseHex: 0x007AFF)
        XCTAssertEqual(t.ink, 0x1C1917)
        XCTAssertEqual(t.sub, 0x6B6660)
        XCTAssertEqual(t.line, 0xE9E4DE)
        XCTAssertEqual(t.surface, 0xFFFFFF)
    }

    // MARK: 金额防撞

    func testMoneyGivenStaysDaiqingForDistantHues() {
        // 红（夹角 ≈166°）、蓝（≈40°）、紫（≈94°）都不撞
        for base: UInt32 in [0xA62B1F, 0x007AFF, 0x7C4DBE] {
            XCTAssertEqual(CustomTheme.tokens(baseHex: base).moneyGiven,
                           CustomTheme.standardMoneyGivenHex, String(base, radix: 16))
        }
    }

    func testMoneyGivenSwitchesForTealAndGreen() {
        // 青绿（夹角 ≈1°）与草绿（≈27°）都落进 <30° 撞色窗 → 备用色
        for base: UInt32 in [0x1F9E8A, 0x2E9E5B] {
            XCTAssertEqual(CustomTheme.tokens(baseHex: base).moneyGiven,
                           CustomTheme.backupMoneyGivenHex, String(base, radix: 16))
        }
    }

    func testMoneyGivenIgnoresHueForLowSaturation() {
        // 黑/灰饱和度≈0：色相无意义，不触发切换（与黛青靠明度天然可分）
        for base: UInt32 in [0x232323, 0x8A8A8A] {
            XCTAssertEqual(CustomTheme.tokens(baseHex: base).moneyGiven,
                           CustomTheme.standardMoneyGivenHex, String(base, radix: 16))
        }
    }

}
