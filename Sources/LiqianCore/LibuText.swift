import Foundation

// MARK: - 礼谱 PDF 专用繁体处理

/// 礼谱 PDF 的固定文字一律繁体（見 GiftBookPDF 与 docs/V28-NOTES.md）。
/// 本文件只负责「程序生成的定式串」——干支日期、农历月日这类由 Core 函数
/// 拼出的文本：其中个别字在 Core 里是简体字形（闰、腊），在 PDF 里换繁体。
///
/// 红线：此映射**禁止**作用于用户数据（人名、礼簿名、事由、关系、备注），
/// 用户数据在礼谱中一律照原样输出。写死的固定串（如欄題、落款用语）直接
/// 在 GiftBookPDF 里以繁体字面量书写，不走这里。
public enum LibuText {
    /// 仅含「生成定式串里可能出现的简体字」→ 繁体，两字：
    /// 闰（闰月）→ 閏、腊（腊月）→ 臘。其余干支/月名/日名字形繁简相同。
    private static let generatedCharMap: [Character: Character] = [
        "闰": "閏",
        "腊": "臘",
    ]

    /// 把程序生成的日期定式串（如 ganzhiFullDate、lunarMonthDay、lunarMonthAlias
    /// 的输出）转为繁体字形。只许喂生成串，严禁喂用户数据。
    public static func traditionalGenerated(_ s: String) -> String {
        String(s.map { generatedCharMap[$0] ?? $0 })
    }

    /// 笔数 → 汉字数字（v3.1 段题签用，如「拾貳筆」）。字表用财务大写数字
    /// （壹貳參肆伍陸柒捌玖，繁简同形偏繁式），读法同 MoneyText 的整数读法
    /// （按节读、节内零只读一个、节间补零）；唯账簿计数式起头省「壹」：
    /// 全串以「壹拾」起头时省去首字（12 → 拾貳、10 → 拾、100000 → 拾萬）。
    /// n ≤ 0 返回「零」（题签不会出现，防御性兜底）。
    public static func chineseCount(_ n: Int) -> String {
        guard n > 0 else { return "零" }
        let digits: [Character] = ["零", "壹", "貳", "參", "肆", "伍", "陸", "柒", "捌", "玖"]
        let smallUnits: [Character?] = [nil, "拾", "佰", "仟"] // 下标＝节内位权（个/拾/佰/仟）
        let sectionUnits = ["", "萬", "億", "兆"]

        var sections: [Int] = []
        var rest = n
        while rest > 0 {
            sections.append(rest % 10000)
            rest /= 10000
        }

        var out = ""
        var higherRendered = false
        for idx in stride(from: sections.count - 1, through: 0, by: -1) {
            let v = sections[idx]
            if v == 0 { continue }
            // 低节不足仟位（有前导零）且高节已读出 → 节间补零（壹萬零壹拾貳）
            if higherRendered && v < 1000 && !out.hasSuffix("零") {
                out.append("零")
            }
            var d = [Int](repeating: 0, count: 4)
            var t = v
            for i in 0..<4 {
                d[i] = t % 10
                t /= 10
            }
            var started = false
            var zeroPending = false
            for pos in stride(from: 3, through: 0, by: -1) {
                let digit = d[pos]
                if digit == 0 {
                    if started { zeroPending = true }
                } else {
                    if zeroPending {
                        out.append("零")
                        zeroPending = false
                    }
                    out.append(digits[digit])
                    if let unit = smallUnits[pos] { out.append(unit) }
                    started = true
                }
            }
            if idx < sectionUnits.count {
                out += sectionUnits[idx]
            }
            higherRendered = true
        }
        if out.hasPrefix("壹拾") { out.removeFirst() }
        return out
    }
}
