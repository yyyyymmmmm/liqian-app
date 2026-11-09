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

// MARK: - 礼谱脚本（v5.13 语言全跟随：谱面语言＝界面语言）

/// 礼谱文案脚本。历史口径（v2.8 定版）谱面恒繁体；v5.13 起跟随
/// App 语言设置：繁體档出繁体谱、简体档出简体谱，版式规矩不变。
public enum LibuScript: String, Sendable {
    case simplified
    case traditional
}

public extension LibuText {
    /// 生成定式串按脚本出字形：繁体走既有 traditionalGenerated；
    /// 简体反向还原（生成串在 Core 里本以简体拼出，只有被
    /// traditionalGenerated 换过的 閏/臘 两字需要换回——简体路径
    /// 直接返回原串即可，此处仍走显式映射以防上游先行繁化）。
    static func generated(_ s: String, script: LibuScript) -> String {
        switch script {
        case .traditional: return traditionalGenerated(s)
        case .simplified: return s
        }
    }

    /// 笔数汉字（题签/汇册用）：繁体为既有口径；简体只换字表里
    /// 繁简异形的五个字（貳參陸萬億），读法与省「壹」口径完全一致。
    static func chineseCount(_ n: Int, script: LibuScript) -> String {
        let trad = chineseCount(n)
        guard script == .simplified else { return trad }
        let map: [Character: Character] = [
            "貳": "贰", "參": "叁", "陸": "陆", "萬": "万", "億": "亿",
        ]
        return String(trad.map { map[$0] ?? $0 })
    }
}

/// 礼谱固定文案表（v5.13）：键为繁体字面（历史定版的书写形态），
/// 简体档查表换字。**只收固定文案**——用户数据（人名/礼簿名/事由/
/// 备注）永不入表、永不转换（与 LibuText 文件头红线一致）。
/// 带插值的整句走下方具名函数，逐句双写，不用逐字机转拼句。
public enum LibuBookText {
    private static let simplifiedForms: [String: String] = [
        "禮錢賬本 · 導出": "礼钱账本 · 导出",
        "百年好合": "百年好合",
        "福壽康寧": "福寿康宁",
        "喬遷之喜": "乔迁之喜",
        "平安喜樂": "平安喜乐",
        "金榜題名": "金榜题名",
        "開業大吉": "开业大吉",
        "吉祥如意": "吉祥如意",
        "紀念": "纪念",
        "於": "于",
        "謹識": "谨识",
        "主家謹識": "主家谨识",
        "譜序": "谱序",
        "（續）": "（续）",
        "銘謝": "铭谢",
        "答謝": "答谢",
        "奠儀": "奠仪",
        "賀儀": "贺仪",
        "聲": "声",
        "隨禮": "随礼",
        "隨": "随",
        "筆": "笔",
        "奠儀總計": "奠仪总计",
        "彙總": "汇总",
        "收禮合計": "收礼合计",
        "隨禮合計": "随礼合计",
        "大寫：": "大写：",
        "按方式": "按方式",
        "按日小計": "按日小计",
        "按關係小計": "按关系小计",
        "校對：": "校对：",
        "書記": "书记",
        "核實": "核实",
        "補記": "补记",
        "簽名": "签名",
        "祝福索引": "祝福索引",
        "掃碼聆聽來賓祝福（需安裝『禮錢賬本』App 方可打開）": "扫码聆听来宾祝福（需安装『礼钱账本』App 方可打开）",
        "家族禮譜": "家族礼谱",
        "總目": "总目",
        "總目（續）": "总目（续）",
        "人物總索引": "人物总索引",
        "人物總索引（續）": "人物总索引（续）",
        "按年份編章": "按年份编章",
        "姓名之後為其出現的禮簿與筆數；同名即同人（與 App 內口徑一致）。": "姓名之后为其出现的礼簿与笔数；同名即同人（与 App 内口径一致）。",
    ]

    /// 固定文案按脚本取字：繁体档原样，简体档查表（表外原样返回，
    /// 保证新增繁体固定串在简体档下只是字形未换、不会丢字）。
    public static func fixed(_ traditionalForm: String, script: LibuScript) -> String {
        switch script {
        case .traditional: return traditionalForm
        case .simplified: return simplifiedForms[traditionalForm] ?? traditionalForm
        }
    }

    /// 内页页签：「第 N 頁」/「第 N 页」
    public static func pageLabel(index: Int, script: LibuScript) -> String {
        script == .traditional ? "第 \(index) 頁" : "第 \(index) 页"
    }

    /// 汇总首行：「總人數 X 人 · 總筆數 Y 筆」
    public static func summaryPeopleLine(people: Int, count: Int, script: LibuScript) -> String {
        script == .traditional
            ? "總人數 \(people) 人 · 總筆數 \(count) 筆"
            : "总人数 \(people) 人 · 总笔数 \(count) 笔"
    }

    /// 汇总待送出注：「另有待送出 N 筆，未計入本譜。」
    public static func summaryPendingLine(count: Int, script: LibuScript) -> String {
        script == .traditional
            ? "另有待送出 \(count) 筆，未計入本譜。"
            : "另有待送出 \(count) 笔，未计入本谱。"
    }

    /// 答谢辞正文（固定模板双写）：只插值主家名与事由原文
    /// （均为用户数据，照原样、不转换）。白事版素语，不用賀/喜字眼。
    public static func thanksText(bai: Bool, hostName: String, type: String, script: LibuScript) -> String {
        switch (bai, script) {
        case (true, .traditional):
            return "諸位親朋，於家中有故之時，親臨弔唁，扶持相助，\(hostName)銘感五內。"
                + "哀痛之際，賴諸位慰藉，方得稍安。此恩此德，無以為報，唯銘諸心版。"
                + "謹彙此譜，非徒記數，實誌厚誼。他年展卷，當念今日諸位之情。"
        case (true, .simplified):
            return "诸位亲朋，于家中有故之时，亲临吊唁，扶持相助，\(hostName)铭感五内。"
                + "哀痛之际，赖诸位慰藉，方得稍安。此恩此德，无以为报，唯铭诸心版。"
                + "谨汇此谱，非徒记数，实志厚谊。他年展卷，当念今日诸位之情。"
        case (false, .traditional):
            return "諸位親朋，遠道而來，厚禮隆情，\(hostName)銘感於心。"
                + "\(type)之日，蓬蓽生輝，笑語盈堂；所記者非簿上之數，乃平生之厚誼也。"
                + "謹彙此譜，藏之箱篋，傳之子孫。他年展卷，猶見今日之盛；"
                + "諸位有用得著主家之處，但憑吩咐，必當竭誠以報。"
        case (false, .simplified):
            return "诸位亲朋，远道而来，厚礼隆情，\(hostName)铭感于心。"
                + "\(type)之日，蓬荜生辉，笑语盈堂；所记者非簿上之数，乃平生之厚谊也。"
                + "谨汇此谱，藏之箱箧，传之子孙。他年展卷，犹见今日之盛；"
                + "诸位有用得着主家之处，但凭吩咐，必当竭诚以报。"
        }
    }
}
