import Foundation

// MARK: - 批量粘贴解析（整本旧账文字 → 逐行结构化，纯函数可单测）
// 行格式：「姓名 金额 [关系]」，分隔容错：空格/制表符/逗号/中文逗号/顿号/分号。
// 金额可带 ¥/￥ 前缀、「元」后缀、小数（元→分四舍五入）。
// 关系第三段：已知关系词，或任意 2 字词。空行跳过（不产出行、也不算错），
// 但 lineNo 始终是原文里的真实行号（从 1 起），方便用户回原文定位。

public struct ParsedLine: Sendable, Equatable, Identifiable {
    public var lineNo: Int
    public var raw: String
    public var result: Result

    public enum Result: Sendable, Equatable {
        case success(name: String, amountCents: Int, relation: String?)
        case failure(reason: String)
    }

    public var id: Int { lineNo }

    public init(lineNo: Int, raw: String, result: Result) {
        self.lineNo = lineNo
        self.raw = raw
        self.result = result
    }

    public var isSuccess: Bool {
        if case .success = result { return true }
        return false
    }
}

public enum LedgerTextParser {
    private static let separators = CharacterSet(charactersIn: " \t,，、;；")

    public static func parse(_ text: String) -> [ParsedLine] {
        var out: [ParsedLine] = []
        let lines = text.components(separatedBy: .newlines)
        for (i, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue } // 空行跳过
            out.append(ParsedLine(lineNo: i + 1, raw: line, result: parseLine(line)))
        }
        return out
    }

    private static func parseLine(_ line: String) -> ParsedLine.Result {
        let tokens = line.components(separatedBy: separators).filter { !$0.isEmpty }
        if tokens.isEmpty { return .failure(reason: "空行") }

        // 先定位金额 token（第一个能读成金额的）
        var amountIndex: Int?
        var amountCents = 0
        for (idx, tok) in tokens.enumerated() {
            if let cents = amountValue(of: tok) {
                amountIndex = idx
                amountCents = cents
                break
            }
        }
        guard let ai = amountIndex else {
            return .failure(reason: "没找到金额")
        }
        if amountCents <= 0 {
            return .failure(reason: "金额不对")
        }

        let rest = tokens.enumerated().filter { $0.offset != ai }.map { $0.element }
        guard let name = rest.first else {
            return .failure(reason: "缺姓名")
        }
        if name.rangeOfCharacter(from: .decimalDigits) != nil {
            return .failure(reason: "姓名里有数字，看不懂")
        }

        // 剩余 token 只允许一段关系：已知关系词或任意 2 字
        var relation: String?
        let extras = Array(rest.dropFirst())
        if extras.count == 1 {
            let r = extras[0]
            if LiqianConstants.relations.contains(r) || r.count == 2 {
                relation = r
            } else {
                return .failure(reason: "「\(r)」看不懂，只认关系词")
            }
        } else if extras.count > 1 {
            return .failure(reason: "内容太多，一行只记一笔")
        }

        return .success(name: name, amountCents: amountCents, relation: relation)
    }

    /// 能读成金额则返回分：可选 ¥/￥ 前缀、「元」后缀，其余必须是数字+至多一个小数点
    private static func amountValue(of token: String) -> Int? {
        var t = token
        if t.hasPrefix("¥") || t.hasPrefix("￥") {
            t.removeFirst()
        }
        if t.hasSuffix("元") {
            t.removeLast()
        }
        if t.isEmpty { return nil }
        var dotSeen = false
        for ch in t {
            if ch == "." {
                if dotSeen { return nil }
                dotSeen = true
            } else if !ch.isNumber {
                return nil
            }
        }
        guard let v = Double(t) else { return nil }
        return Int((v * 100.0).rounded())
    }
}
