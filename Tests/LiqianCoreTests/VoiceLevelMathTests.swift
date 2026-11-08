import XCTest
@testable import LiqianCore

/// v5.6：语音面板电平口径——dB 映射（−50dB 地板、0dB 满格）、
/// 惯性（attack 即时、decay 滑落不跌破目标）、推送节流阈值。
final class VoiceLevelMathTests: XCTestCase {

    func testSilenceIsZero() {
        XCTAssertEqual(VoiceLevelMath.normalizedLevel(rms: 0), 0)
        XCTAssertEqual(VoiceLevelMath.normalizedLevel(rms: -0.5), 0)
    }

    func testBelowFloorIsZero() {
        // −80 dB（rms=0.0001）远低于 −50 dB 地板
        XCTAssertEqual(VoiceLevelMath.normalizedLevel(rms: 0.0001), 0)
    }

    func testFullScaleIsOne() {
        XCTAssertEqual(VoiceLevelMath.normalizedLevel(rms: 1), 1, accuracy: 0.0001)
        // 超过满量程钳制到 1
        XCTAssertEqual(VoiceLevelMath.normalizedLevel(rms: 2), 1)
    }

    func testSpeechRangeMapping() {
        // −20 dB（rms=0.1）→ 0.6；−40 dB（rms=0.01）→ 0.2
        XCTAssertEqual(VoiceLevelMath.normalizedLevel(rms: 0.1), 0.6, accuracy: 0.001)
        XCTAssertEqual(VoiceLevelMath.normalizedLevel(rms: 0.01), 0.2, accuracy: 0.001)
    }

    func testAttackIsInstant() {
        XCTAssertEqual(VoiceLevelMath.ballistic(previous: 0.2, target: 0.9), 0.9)
        XCTAssertEqual(VoiceLevelMath.ballistic(previous: 0, target: 0.5), 0.5)
    }

    func testDecayGlides() {
        // 从满格停口：一步衰减到 0.72，而不是直接跳到 0
        XCTAssertEqual(VoiceLevelMath.ballistic(previous: 1, target: 0), 0.72, accuracy: 0.0001)
        let step2 = VoiceLevelMath.ballistic(previous: 0.72, target: 0)
        XCTAssertEqual(step2, 0.72 * 0.72, accuracy: 0.0001)
    }

    func testDecayNeverUndershootsTarget() {
        // 衰减值低于目标时停在目标（小声持续说话不被衰减吃掉）
        XCTAssertEqual(VoiceLevelMath.ballistic(previous: 0.5, target: 0.4), 0.4)
    }

    func testMinimumPushFrames() {
        XCTAssertEqual(VoiceLevelMath.minimumPushFrames(sampleRate: 48000), 1600)
        XCTAssertEqual(VoiceLevelMath.minimumPushFrames(sampleRate: 44100), 1470)
        XCTAssertEqual(VoiceLevelMath.minimumPushFrames(sampleRate: 0), 0)
        XCTAssertEqual(VoiceLevelMath.minimumPushFrames(sampleRate: -1), 0)
    }
}
