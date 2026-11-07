import Foundation

// MARK: - 金额中文大写（金融口径）

public enum MoneyText {
    /// 一套字表：数字、节单位、节内位单位、框架字（元/圆、角、分、整、负）
    private struct Tables {
        let digits: [Character]
        let sectionUnits: [String]
        let innerUnits: [String]
        let yuan: String
        let jiao: String
        let fen: String
        let zheng: String
        let negative: String
    }

    /// 简体版（App 内显示与既有口径）：贰/叁/陆 + 元
    private static let simplifiedTables = Tables(
        digits: ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"],
        sectionUnits: ["", "万", "亿", "兆"],
        innerUnits: ["", "拾", "佰", "仟"],
        yuan: "元", jiao: "角", fen: "分", zheng: "整", negative: "负"
    )

    /// 繁体正式财务版（礼谱 PDF 专用）：貳/參/陸 + 圓，负作負
    private static let traditionalTables = Tables(
        digits: ["零", "壹", "貳", "參", "肆", "伍", "陸", "柒", "捌", "玖"],
        sectionUnits: ["", "萬", "億", "兆"],
        innerUnits: ["", "拾", "佰", "仟"],
        yuan: "圓", jiao: "角", fen: "分", zheng: "整", negative: "負"
    )

    /// 白事奠儀版（v2.10 礼制）：字表同繁体正式版，唯不缀「整」字
    /// （奠儀金额写「伍佰圓」不写「伍佰圓整」，零额作「零圓」）。
    private static let traditionalBaiTables = Tables(
        digits: ["零", "壹", "貳", "參", "肆", "伍", "陸", "柒", "捌", "玖"],
        sectionUnits: ["", "萬", "億", "兆"],
        innerUnits: ["", "拾", "佰", "仟"],
        yuan: "圓", jiao: "角", fen: "分", zheng: "", negative: "負"
    )

    /// 分 → 金融大写（简体）。口径（银行写法）：
    /// - 整数部分按 4 位分节读，节内零只读一个、节尾零不读；
    ///   低节不足仟位（有前导零）且高节已读时，节间补一个「零」
    ///   （例：1000010 元 → 壹佰万零壹拾元整）。
    /// - 小数部分：角分依次读；元不为 0 而角为 0、分不为 0 时补「零」
    ///   （例：105 分 → 壹元零伍分）。
    /// - 「整」只在元不为 0 且分位为 0 时收尾（例：伍佰元整、壹元伍角整）；
    ///   元为 0 时不带「整」（例：50 分 → 伍角、5 分 → 伍分）。
    /// - 0 分 → 「零元整」；负数加「负」前缀（账本里用不到，防御性支持）。
    public static func chineseUppercase(cents: Int) -> String {
        uppercase(cents: cents, tables: simplifiedTables)
    }

    /// 分 → 正式财务繁体大写（礼谱 PDF 专用，如「壹仟圓整」）。
    /// 读法规则与简体版完全一致，只换字表；App 内显示仍用简体版，互不影响。
    public static func chineseUppercaseTraditional(cents: Int) -> String {
        uppercase(cents: cents, tables: traditionalTables)
    }

    /// 分 → 白事奠儀繁体大写（礼谱 PDF 白事专用）：读法同上，唯不缀「整」字。
    public static func chineseUppercaseTraditionalBai(cents: Int) -> String {
        uppercase(cents: cents, tables: traditionalBaiTables)
    }

    private static func uppercase(cents: Int, tables: Tables) -> String {
        if cents < 0 { return tables.negative + uppercase(cents: -cents, tables: tables) }
        let yuan = cents / 100
        let jiao = (cents % 100) / 10
        let fen = cents % 10

        if yuan == 0 && jiao == 0 && fen == 0 { return "零" + tables.yuan + tables.zheng }

        var out = ""
        if yuan > 0 {
            out += integerUppercase(yuan, tables: tables) + tables.yuan
        }
        if jiao > 0 {
            out += String(tables.digits[jiao]) + tables.jiao
        } else if fen > 0 && yuan > 0 {
            out += "零"
        }
        if fen > 0 {
            out += String(tables.digits[fen]) + tables.fen
        }
        if yuan > 0 && fen == 0 {
            out += tables.zheng
        }
        return out
    }

    /// 正整数 → 大写（不含单位「元/圓」）。按节处理，规则见 chineseUppercase 注释。
    private static func integerUppercase(_ value: Int, tables: Tables) -> String {
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
            out += sectionUppercase(v, tables: tables)
            if idx < tables.sectionUnits.count {
                out += tables.sectionUnits[idx]
            }
            higherRendered = true
        }
        return out
    }

    /// 一节（1...9999）的大写：节内连续零只读一个，节首/节尾零不读。
    private static func sectionUppercase(_ v: Int, tables: Tables) -> String {
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
                out += String(tables.digits[d]) + tables.innerUnits[pos]
            }
        }
        return out
    }
}
