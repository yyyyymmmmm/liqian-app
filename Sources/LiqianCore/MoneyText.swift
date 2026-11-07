import Foundation

// MARK: - 金额中文大写（金融口径，礼谱 PDF 与落款用）

public enum MoneyText {
    private static let digitChars: [Character] = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
    /// 节（4 位一组）单位：个节、万节、亿节、兆节
    private static let sectionUnits = ["", "万", "亿", "兆"]
    /// 节内位单位：个、拾、佰、仟
    private static let innerUnits = ["", "拾", "佰", "仟"]

    /// 分 → 金融大写。口径（银行写法）：
    /// - 整数部分按 4 位分节读，节内零只读一个、节尾零不读；
    ///   低节不足仟位（有前导零）且高节已读时，节间补一个「零」
    ///   （例：1000010 元 → 壹佰万零壹拾元整）。
    /// - 小数部分：角分依次读；元不为 0 而角为 0、分不为 0 时补「零」
    ///   （例：105 分 → 壹元零伍分）。
    /// - 「整」只在元不为 0 且分位为 0 时收尾（例：伍佰元整、壹元伍角整）；
    ///   元为 0 时不带「整」（例：50 分 → 伍角、5 分 → 伍分）。
    /// - 0 分 → 「零元整」；负数加「负」前缀（账本里用不到，防御性支持）。
    public static func chineseUppercase(cents: Int) -> String {
        if cents < 0 { return "负" + chineseUppercase(cents: -cents) }
        let yuan = cents / 100
        let jiao = (cents % 100) / 10
        let fen = cents % 10

        if yuan == 0 && jiao == 0 && fen == 0 { return "零元整" }

        var out = ""
        if yuan > 0 {
            out += integerUppercase(yuan) + "元"
        }
        if jiao > 0 {
            out += String(digitChars[jiao]) + "角"
        } else if fen > 0 && yuan > 0 {
            out += "零"
        }
        if fen > 0 {
            out += String(digitChars[fen]) + "分"
        }
        if yuan > 0 && fen == 0 {
            out += "整"
        }
        return out
    }

    /// 正整数 → 大写（不含单位「元」）。按节处理，规则见 chineseUppercase 注释。
    private static func integerUppercase(_ value: Int) -> String {
        // 低节在前切分
        var sections: [Int] = []
        var rest = value
        while rest > 0 {
            sections.append(rest % 10000)
            rest /= 10000
        }
        var out = ""
        var higherRendered = false
        for idx in stride(from: sections.count - 1, through: 0, by: -1) {
            let v = sections[idx]
            if v == 0 { continue }
            // 低节带前导零（不足仟位）且高节已读出 → 节间补零（壹佰万零壹拾）
            if higherRendered && v < 1000 && !out.hasSuffix("零") {
                out += "零"
            }
            out += sectionUppercase(v)
            if idx < sectionUnits.count {
                out += sectionUnits[idx]
            }
            higherRendered = true
        }
        return out
    }

    /// 一节（1...9999）的大写：节内连续零只读一个，节首/节尾零不读。
    private static func sectionUppercase(_ v: Int) -> String {
        var out = ""
        var zeroPending = false
        var digits: [Int] = []
        var rest = v
        for _ in 0..<4 {
            digits.append(rest % 10)
            rest /= 10
        }
        // digits 低位在前；从仟位（下标 3）往个位（下标 0）读
        for pos in stride(from: 3, through: 0, by: -1) {
            let d = digits[pos]
            if d == 0 {
                // 已有读出内容、且后面还有非零位时，记一个待读的零
                if !out.isEmpty {
                    let hasNonZeroAfter = (0..<pos).contains { digits[$0] != 0 }
                    if hasNonZeroAfter { zeroPending = true }
                }
            } else {
                if zeroPending {
                    out += "零"
                    zeroPending = false
                }
                out += String(digitChars[d]) + innerUnits[pos]
            }
        }
        return out
    }
}
