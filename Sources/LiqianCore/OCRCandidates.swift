import Foundation

// MARK: - OCR 文本 → 待确认候选组装层（v2.9 拍照识别礼单）
// Vision OCR 出的是纯文本，这里喂给与粘贴导入共用的 LedgerTextParser
// 规则解析，再组装成确认页要的两堆：可导入候选（解析成功行）与
// 跳过行（失败行连同原文和原因）。任何一行都不静默吞——标题、合计、
// 噪声行都会以 skipped 的形式在确认页计数并可对照原文。
// 纯函数、无 UI 依赖，可单测；方向不在本层处理（导入方固定按收礼记）。

public enum OCRCandidateBuilder {
    /// 一条可导入候选（来自一行 OCR 文本）
    public struct Candidate: Sendable, Equatable, Identifiable {
        /// 原文真实行号（从 1 起，与 LedgerTextParser 口径一致）
        public var lineNo: Int
        public var name: String
        public var amountCents: Int
        public var relation: String?
        /// 命中的 OCR 原文行，确认页对照原图核对用
        public var raw: String

        public var id: Int { lineNo }

        public init(lineNo: Int, name: String, amountCents: Int, relation: String?, raw: String) {
            self.lineNo = lineNo
            self.name = name
            self.amountCents = amountCents
            self.relation = relation
            self.raw = raw
        }
    }

    /// 没读成候选的行（原文与原因都保留，确认页明示）
    public struct SkippedLine: Sendable, Equatable, Identifiable {
        public var lineNo: Int
        public var raw: String
        public var reason: String

        public var id: Int { lineNo }

        public init(lineNo: Int, raw: String, reason: String) {
            self.lineNo = lineNo
            self.raw = raw
            self.reason = reason
        }
    }

    public struct Outcome: Sendable, Equatable {
        public var candidates: [Candidate]
        public var skipped: [SkippedLine]

        public var isEmpty: Bool { candidates.isEmpty }

        public init(candidates: [Candidate], skipped: [SkippedLine]) {
            self.candidates = candidates
            self.skipped = skipped
        }
    }

    /// OCR 多行文本 → 候选组装。空行由 LedgerTextParser 跳过且不计入两堆，
    /// 但 lineNo 始终是原文真实行号，确认页可按行号回原文定位。
    public static func build(from ocrText: String) -> Outcome {
        var candidates: [Candidate] = []
        var skipped: [SkippedLine] = []
        for line in LedgerTextParser.parse(ocrText) {
            switch line.result {
            case .success(let name, let cents, let relation):
                candidates.append(
                    Candidate(lineNo: line.lineNo, name: name, amountCents: cents, relation: relation, raw: line.raw)
                )
            case .failure(let reason):
                skipped.append(SkippedLine(lineNo: line.lineNo, raw: line.raw, reason: reason))
            }
        }
        return Outcome(candidates: candidates, skipped: skipped)
    }
}
