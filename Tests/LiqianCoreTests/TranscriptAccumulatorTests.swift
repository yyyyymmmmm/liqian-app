import XCTest
@testable import LiqianCore

/// v5.5：SpeechAnalyzer 结果累积口径——volatile 整体替换、
/// final 顺序拼接并清 volatile、对外全文 = 定稿 + 临时。
final class TranscriptAccumulatorTests: XCTestCase {

    func testVolatileReplacesRatherThanAppends() {
        var acc = TranscriptAccumulator()
        acc.consume(text: "大舅", isFinal: false)
        acc.consume(text: "大舅二千", isFinal: false)
        XCTAssertEqual(acc.text, "大舅二千")
        XCTAssertEqual(acc.finalizedText, "")
        XCTAssertEqual(acc.volatileText, "大舅二千")
    }

    func testFinalCommitsAndClearsVolatile() {
        var acc = TranscriptAccumulator()
        acc.consume(text: "大舅二千", isFinal: false)
        acc.consume(text: "大舅二千，", isFinal: true)
        XCTAssertEqual(acc.text, "大舅二千，")
        XCTAssertEqual(acc.finalizedText, "大舅二千，")
        XCTAssertEqual(acc.volatileText, "")
    }

    func testMultiplePhrasesAccumulateInOrder() {
        var acc = TranscriptAccumulator()
        acc.consume(text: "大舅二千，", isFinal: true)
        acc.consume(text: "二姨", isFinal: false)
        XCTAssertEqual(acc.text, "大舅二千，二姨")
        acc.consume(text: "二姨一千", isFinal: false)
        acc.consume(text: "二姨一千。", isFinal: true)
        XCTAssertEqual(acc.text, "大舅二千，二姨一千。")
    }

    func testFinalWithoutPriorVolatile() {
        var acc = TranscriptAccumulator()
        acc.consume(text: "张三五百", isFinal: true)
        XCTAssertEqual(acc.text, "张三五百")
    }

    func testResetClearsEverything() {
        var acc = TranscriptAccumulator()
        acc.consume(text: "大舅二千", isFinal: true)
        acc.consume(text: "二姨", isFinal: false)
        acc.reset()
        XCTAssertEqual(acc.text, "")
        XCTAssertEqual(acc.finalizedText, "")
        XCTAssertEqual(acc.volatileText, "")
    }

    func testEmptyVolatileAfterFinalKeepsText() {
        var acc = TranscriptAccumulator()
        acc.consume(text: "大舅二千", isFinal: true)
        acc.consume(text: "", isFinal: false)
        XCTAssertEqual(acc.text, "大舅二千")
    }
}
