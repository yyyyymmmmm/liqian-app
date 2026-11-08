import XCTest
@testable import LiqianCore

/// v5.4.1：麦克风面包屑——落步置未结束旗、close 清旗、诊断文案只在
/// 未结束时出现、close 后再 mark 重新武装。用独立 suite 不污染标准域。
final class MicTraceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.mictrace.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testNeverUsedHasNoSummary() {
        XCTAssertNil(MicTrace.unclosedSummary(defaults: defaults))
    }

    func testMarkOpensSessionAndSummaryNamesTheStep() {
        MicTrace.mark(
            step: 6, "麦克风已授权（同步快路）", defaults: defaults,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(defaults.bool(forKey: MicTrace.sessionOpenKey))
        let summary = MicTrace.unclosedSummary(defaults: defaults)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("#6") == true)
        XCTAssertTrue(summary?.contains("麦克风已授权") == true)
    }

    func testLatestMarkWins() {
        MicTrace.mark(step: 1, "点麦克风·开始启动", defaults: defaults)
        MicTrace.mark(step: 13, "已装 tap", defaults: defaults)
        let summary = MicTrace.unclosedSummary(defaults: defaults)
        XCTAssertTrue(summary?.contains("#13") == true)
        XCTAssertFalse(summary?.contains("#1 ") == true)
    }

    func testCloseClearsSummary() {
        MicTrace.mark(step: 14, "引擎已启动", defaults: defaults)
        MicTrace.close(reason: "会话正常结束", defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: MicTrace.sessionOpenKey))
        XCTAssertNil(MicTrace.unclosedSummary(defaults: defaults))
    }

    func testMarkAfterCloseReopens() {
        MicTrace.mark(step: 101, "祝福录音·点录制", defaults: defaults)
        MicTrace.close(reason: "录音正常结束", defaults: defaults)
        XCTAssertNil(MicTrace.unclosedSummary(defaults: defaults))
        MicTrace.mark(step: 104, "进入 beginRecording", defaults: defaults)
        XCTAssertNotNil(MicTrace.unclosedSummary(defaults: defaults))
    }

    func testDetailIsCarriedIntoEntry() {
        MicTrace.mark(
            step: 12, "读取输入格式", detail: "44100Hz/1ch", defaults: defaults
        )
        XCTAssertTrue(
            defaults.string(forKey: MicTrace.entryKey)?.contains("44100Hz/1ch") == true
        )
    }
}
