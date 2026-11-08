import Foundation

/// 语音转写结果累积（v5.5，SpeechAnalyzer 新链的纯逻辑部分）。
///
/// 新框架的结果分两种语义（苹果文档 SpeechTranscriber.Result）：
/// - volatile（isFinal == false）：当前短语的临时猜测，后续结果会把
///   同一短语整体改写，只能替换、不能拼接；
/// - final（isFinal == true）：短语定稿，只增不改，顺序拼接。
///
/// 对外文本 = 定稿拼接 + 当前 volatile，与旧 SFSpeechRecognizer 链
/// 「每次回调都给全量文本」的 onText 语义一致，两个调用方
/// （一句话记账、AI 问账）因此零改动。纯值类型、无 IO，可单测。
public struct TranscriptAccumulator: Sendable {
    /// 已定稿文本（各短语 final 结果顺序拼接）
    public private(set) var finalizedText = ""
    /// 当前短语的临时文本（volatile 结果整体替换）
    public private(set) var volatileText = ""

    /// 当前应显示的全文：定稿在前、临时在后
    public var text: String { finalizedText + volatileText }

    public init() {}

    /// 消费一条结果：final 拼进定稿并清掉临时；volatile 整体替换临时。
    public mutating func consume(text newText: String, isFinal: Bool) {
        if isFinal {
            finalizedText += newText
            volatileText = ""
        } else {
            volatileText = newText
        }
    }

    /// 新会话开始时清空。
    public mutating func reset() {
        finalizedText = ""
        volatileText = ""
    }
}
