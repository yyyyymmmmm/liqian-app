import XCTest
@testable import LiqianCore

/// v5.5.1：AnalyzerFeeder.convertBuffer 的容量口径——帧数 × 采样率比
/// 截断 +1 余量；非法入参返回 0（调用方放弃本帧）。
final class AudioConvertMathTests: XCTestCase {

    func testDownsample48kTo16k() {
        // tap 典型值：4096 帧 @48k → 16k，比 1/3，4096/3 = 1365.33 → 1365 + 1
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 4096, inputSampleRate: 48_000, outputSampleRate: 16_000
            ),
            1366
        )
    }

    func testExactDivisionStillAddsOneFrameMargin() {
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 3000, inputSampleRate: 48_000, outputSampleRate: 16_000
            ),
            1001
        )
    }

    func testUpsample() {
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 1024, inputSampleRate: 16_000, outputSampleRate: 48_000
            ),
            3073
        )
    }

    func testEqualRates() {
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 2048, inputSampleRate: 48_000, outputSampleRate: 48_000
            ),
            2049
        )
    }

    func testTinyBufferKeepsAtLeastOneFrame() {
        // 1 帧重下采样：Int(0.125) = 0，+1 余量保证容量为 1、不为 0
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 1, inputSampleRate: 48_000, outputSampleRate: 8_000
            ),
            1
        )
    }

    func testInvalidInputsReturnZero() {
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 0, inputSampleRate: 48_000, outputSampleRate: 16_000
            ),
            0
        )
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: -5, inputSampleRate: 48_000, outputSampleRate: 16_000
            ),
            0
        )
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 100, inputSampleRate: 0, outputSampleRate: 16_000
            ),
            0
        )
        XCTAssertEqual(
            AudioConvertMath.outputFrameCapacity(
                inputFrameCount: 100, inputSampleRate: 48_000, outputSampleRate: 0
            ),
            0
        )
    }
}
