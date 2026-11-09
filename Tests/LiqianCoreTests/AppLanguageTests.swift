import XCTest
@testable import LiqianCore

// MARK: - 语言全跟随（v5.13 用户定版）
//
// 三档偏好（跟随系统／简体／繁體）单点解析在 Core AppLanguage；
// 谱面固定文案走 LibuBookText（繁体为历史定版字面、简体查表），
// 用户数据永不转换。本组钉死解析口径与谱面分档。
final class AppLanguageTests: XCTestCase {

    // MARK: 偏好解析

    func testExplicitPreferenceWins() {
        XCTAssertEqual(
            AppLanguage.resolve(preference: .simplified, preferredLanguages: ["zh-Hant-TW"]),
            .simplified)
        XCTAssertEqual(
            AppLanguage.resolve(preference: .traditional, preferredLanguages: ["zh-Hans-CN"]),
            .traditional)
    }

    func testSystemFollowsTraditionalChinese() {
        for id in ["zh-Hant", "zh-Hant-TW", "zh-TW", "zh-HK", "zh-MO", "zh_Hant"] {
            XCTAssertEqual(
                AppLanguage.resolve(preference: .system, preferredLanguages: [id]),
                .traditional, id)
        }
    }

    func testSystemFallsBackToSimplified() {
        for id in ["zh-Hans", "zh-Hans-CN", "zh-CN", "zh-SG", "en-US", "ja-JP"] {
            XCTAssertEqual(
                AppLanguage.resolve(preference: .system, preferredLanguages: [id]),
                .simplified, id)
        }
        XCTAssertEqual(
            AppLanguage.resolve(preference: .system, preferredLanguages: []),
            .simplified)
    }

    func testStoredPreferenceParsing() {
        XCTAssertEqual(AppLanguagePreference(storedRaw: nil), .system)
        XCTAssertEqual(AppLanguagePreference(storedRaw: "bogus"), .system)
        XCTAssertEqual(AppLanguagePreference(storedRaw: "traditional"), .traditional)
    }

    func testResolvedLanguageMapping() {
        XCTAssertEqual(ResolvedLanguage.simplified.localeIdentifier, "zh_CN")
        XCTAssertEqual(ResolvedLanguage.traditional.localeIdentifier, "zh-Hant")
        XCTAssertEqual(ResolvedLanguage.traditional.libuScript, .traditional)
        XCTAssertEqual(ResolvedLanguage.simplified.libuScript, .simplified)
    }

    // MARK: 谱面固定文案分档

    func testLibuFixedTextByScript() {
        XCTAssertEqual(LibuBookText.fixed("隨禮", script: .traditional), "隨禮")
        XCTAssertEqual(LibuBookText.fixed("隨禮", script: .simplified), "随礼")
        XCTAssertEqual(LibuBookText.fixed("彙總", script: .simplified), "汇总")
        XCTAssertEqual(LibuBookText.fixed("主家謹識", script: .simplified), "主家谨识")
        XCTAssertEqual(LibuBookText.fixed("賀儀", script: .simplified), "贺仪")
        XCTAssertEqual(LibuBookText.fixed("奠儀", script: .simplified), "奠仪")
        // 表外固定串原样返回（不丢字）
        XCTAssertEqual(LibuBookText.fixed("某新固定串", script: .simplified), "某新固定串")
        XCTAssertEqual(
            LibuBookText.pageLabel(index: 3, script: .traditional), "第 3 頁")
        XCTAssertEqual(
            LibuBookText.pageLabel(index: 3, script: .simplified), "第 3 页")
    }

    func testChineseCountByScript() {
        XCTAssertEqual(LibuText.chineseCount(2, script: .simplified), "贰")
        XCTAssertEqual(LibuText.chineseCount(2, script: .traditional), "貳")
        XCTAssertEqual(LibuText.chineseCount(12, script: .simplified), "拾贰")
    }

    /// 用户数据永不转换：答谢辞模板双写只换固定句，
    /// 插值的主家名（用户填写，繁体原字）必须原样保留。
    func testThanksTextKeepsUserDataVerbatim() {
        let simp = LibuBookText.thanksText(
            bai: false, hostName: "楊府", type: "婚礼", script: .simplified)
        XCTAssertTrue(simp.contains("楊府"))
        XCTAssertTrue(simp.contains("谨汇此谱"))
        let trad = LibuBookText.thanksText(
            bai: true, hostName: "杨府", type: "白事", script: .traditional)
        XCTAssertTrue(trad.contains("杨府"))
        XCTAssertTrue(trad.contains("謹彙此譜"))
    }

    /// 白事大写简体版：读法同简体正式版、唯不缀「整」
    func testBaiUppercaseSimplifiedOmitsZheng() {
        let bai = MoneyText.chineseUppercaseBai(cents: 100_00)
        XCTAssertFalse(bai.hasSuffix("整"))
        XCTAssertTrue(MoneyText.chineseUppercase(cents: 100_00).hasSuffix("整"))
    }
}
