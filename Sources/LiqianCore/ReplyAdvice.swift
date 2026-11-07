import Foundation

// MARK: - 回礼建议区间模型（v4.3，依据品类已验证的祈灵/随礼记账簿规则）
//
// 旧版 returnGiftSuggestion 只有「锚 ×1.2 取整」一条糙规则，给不出理由。
// 本模型四步，每步在 reasons 里留一条人话依据，只给区间、不当裁判：
// 1. 锚：与此人最近一笔「他给我的」（收礼）金额；
// 2. 年涨幅：按距今年数复利，年率由设置给（0/3/5%，默认 3%）；
// 3. 场合系数：按这次要回的场合（礼簿事由）折算，映射表写死在 coefficient(for:)；
// 4. 取整：红事取吉利数（优先整百，其次尾 6/8），白事取单数（整百加 1）。
//
// 锚的回退序（pickAnchor）：
//   最近一笔（日期合法者）→ 历史最大 → 历史中位。
//   当前数据模型下日期由表单保证为 yyyy-MM-dd、金额恒 > 0，
//   最大/中位两档是防御性兜底（日期损坏时不至于给不出参考），
//   对应档位命中时 reasons 会如实说明来源，不假装是最近一笔。
//
// 无任何收礼记录返回 nil：没依据不瞎给，界面出回退文案。

public struct ReplyAdvice: Sendable, Equatable {
    /// 锚的来源档位
    public enum AnchorSource: String, Sendable, Equatable {
        case latest
        case maximum
        case median
    }

    /// 区间下限（分，红事为整百、白事为单数）
    public var lowerCents: Int
    /// 区间上限（分）
    public var upperCents: Int
    /// 建议填入值（分）：取整后的锚定值，落在区间内
    public var suggestedCents: Int
    /// 理由条目（已拼好的人话，View 直接逐行展示；顺序即阅读顺序）
    public var reasons: [String]
    /// 锚金额（分）
    public var anchorAmountCents: Int
    /// 锚日期 yyyy-MM-dd（中位档无单一锚时为 ""）
    public var anchorDate: String
    /// 锚事由（所属礼簿类型；无时为 ""）
    public var anchorType: String
    public var anchorSource: AnchorSource
    /// 锚距今整年数（按年份差，与全 App 口径一致）
    public var yearsAgo: Int
    /// 本次场合是否白事（取单数规则与文案免责都据此）
    public var isBai: Bool

    public init(
        lowerCents: Int,
        upperCents: Int,
        suggestedCents: Int,
        reasons: [String],
        anchorAmountCents: Int,
        anchorDate: String,
        anchorType: String,
        anchorSource: AnchorSource,
        yearsAgo: Int,
        isBai: Bool
    ) {
        self.lowerCents = lowerCents
        self.upperCents = upperCents
        self.suggestedCents = suggestedCents
        self.reasons = reasons
        self.anchorAmountCents = anchorAmountCents
        self.anchorDate = anchorDate
        self.anchorType = anchorType
        self.anchorSource = anchorSource
        self.yearsAgo = yearsAgo
        self.isBai = isBai
    }
}

public enum ReplyAdvisor {
    /// 年涨幅设置键（App 层 @AppStorage 同键读写）：存年率百分数 0/3/5
    public static let annualRateKey = "replyAnnualRatePercent"
    public static let defaultAnnualRatePercent = 3

    /// 场合系数映射（写死，依据通行份量：婚礼是红事基准；
    /// 满月/周岁是孩子事、份量最轻 0.8；乔迁/升学略轻 0.9；
    /// 寿宴/开业与婚礼同级 1.0；白事不走系数、走单数规则；
    /// 未知/自定义事由按 1.0 不折算）。
    public static func coefficient(for occasionType: String) -> Double {
        switch occasionType {
        case "婚礼", "寿宴", "开业":
            return 1.0
        case "乔迁", "升学":
            return 0.9
        case "满月", "周岁":
            return 0.8
        default:
            return 1.0
        }
    }

    /// 锚的选择（回退序见文件头）：三档候选给齐时按序取第一个可用者。
    /// 返回（金额分, 来源）；全无候选返回 nil。
    public static func pickAnchor(
        latest: (amountCents: Int, date: String, type: String)?,
        maximumCents: Int?,
        medianCents: Int?
    ) -> (amountCents: Int, date: String, type: String, source: ReplyAdvice.AnchorSource)? {
        if let latest, latest.amountCents > 0 {
            return (latest.amountCents, latest.date, latest.type, .latest)
        }
        if let maximumCents, maximumCents > 0 {
            return (maximumCents, "", "", .maximum)
        }
        if let medianCents, medianCents > 0 {
            return (medianCents, "", "", .median)
        }
        return nil
    }

    /// 主入口：算这个人「这次场合」的回礼建议区间。无收礼记录返回 nil。
    /// - occasionType：这次要回的场合（记一笔时为当前礼簿事由；
    ///   人物页无具体场合时传锚所属事由，与「按上次场合估」的直觉一致）。
    /// - annualRatePercent：年涨幅设置（0/3/5），负数按 0 处理。
    public static func advice(
        from entries: [EntrySnapshot],
        person: String,
        occasionType: String,
        today: String,
        annualRatePercent: Int = defaultAnnualRatePercent
    ) -> ReplyAdvice? {
        // 收礼无待送出概念，isPendingSend 只可能出现在随礼上，这里无需过滤
        let received = entries.filter {
            $0.person == person && $0.direction == LiqianConstants.received && $0.amountCents > 0
        }
        guard !received.isEmpty else { return nil }

        // 最近一笔：日期合法（yyyy 前缀可解析）者里取日期最大；
        // 同日按传入顺序（约定新→旧）取先出现者，与旧版口径一致
        var latest: (amountCents: Int, date: String, type: String)?
        for e in received where Int(e.date.prefix(4)) != nil {
            if let cur = latest {
                if e.date > cur.date { latest = (e.amountCents, e.date, e.ledgerType) }
            } else {
                latest = (e.amountCents, e.date, e.ledgerType)
            }
        }
        let amounts = received.map { $0.amountCents }.sorted()
        let maximum = amounts.last
        let median = amounts.isEmpty ? nil : amounts[amounts.count / 2]

        guard let picked = pickAnchor(latest: latest, maximumCents: maximum, medianCents: median) else {
            return nil
        }

        let isBai = occasionType == LiqianConstants.baiType
        let anchorYuan = Double(picked.amountCents) / 100.0
        let anchorYear = Int(picked.date.prefix(4))
        let todayYear = Int(today.prefix(4)) ?? anchorYear ?? 0
        let yearsAgo = anchorYear.map { max(0, todayYear - $0) } ?? 0

        // 年涨幅复利
        let rate = Double(max(0, annualRatePercent)) / 100.0
        let grownYuan = anchorYuan * pow(1.0 + rate, Double(yearsAgo))
        // 场合系数（白事不折算：奠仪按对等单数，不打折）
        let coef = isBai ? 1.0 : coefficient(for: occasionType)
        let baseYuan = grownYuan * coef

        let range: (lower: Int, suggested: Int, upper: Int) = isBai
            ? baiRange(baseYuan: baseYuan)
            : hongRange(baseYuan: baseYuan)

        // —— 理由条目：只陈述事实与算法，不下裁判 ——
        var reasons: [String] = []
        switch picked.source {
        case .latest:
            let year = String(picked.date.prefix(4))
            let typePart = picked.type.isEmpty ? "" : " · \(picked.type)"
            reasons.append("上次他随你 \(LedgerMath.fmtMoney(cents: picked.amountCents))（\(year) 年\(typePart)）")
        case .maximum:
            reasons.append("没有可用的最近记录，按他给过你的最高一笔 \(LedgerMath.fmtMoney(cents: picked.amountCents)) 算")
        case .median:
            reasons.append("按他给过你的中间数 \(LedgerMath.fmtMoney(cents: picked.amountCents)) 算")
        }
        if yearsAgo >= 1, rate > 0 {
            reasons.append("过去 \(yearsAgo) 年，按年涨幅 \(annualRatePercent)% 折算约 \(LedgerMath.fmtMoney(cents: Int(grownYuan.rounded()) * 100))")
        }
        if !isBai, coef != 1.0 {
            reasons.append("这次是\(occasionType)，通常略轻于婚礼，已按\(chengText(coef))折算")
        }
        if isBai {
            reasons.append("白事取单数 \(LedgerMath.fmtMoney(cents: range.suggested * 100))；各地习俗不同，以当地为准")
        } else {
            reasons.append("红事取整到 \(LedgerMath.fmtMoney(cents: range.suggested * 100))")
        }

        return ReplyAdvice(
            lowerCents: range.lower * 100,
            upperCents: range.upper * 100,
            suggestedCents: range.suggested * 100,
            reasons: reasons,
            anchorAmountCents: picked.amountCents,
            anchorDate: picked.date,
            anchorType: picked.type,
            anchorSource: picked.source,
            yearsAgo: yearsAgo,
            isBai: isBai
        )
    }

    /// 系数→成数文案（0.8 八成、0.9 九成；其余回退「系数 X」表述）
    private static func chengText(_ coef: Double) -> String {
        switch coef {
        case 0.8: return "八成"
        case 0.9: return "九成"
        default: return "系数 \(coef)"
        }
    }

    /// 红事取整（单位：元）：优先整百——建议值＝折算值向上取整到百；
    /// 区间＝[向下整百, 建议值]，锚恰为整百时区间上延一档留出「略添」空间。
    /// 折算不足百元时整百过头，改用尾 6/8 吉数档（66/88/100）。
    static func hongRange(baseYuan: Double) -> (lower: Int, suggested: Int, upper: Int) {
        if baseYuan < 100 {
            if baseYuan <= 66 { return (66, 66, 88) }
            if baseYuan <= 88 { return (66, 88, 100) }
            return (88, 100, 200)
        }
        let floor100 = Int(baseYuan / 100.0) * 100
        let ceil100 = Int((baseYuan / 100.0).rounded(.up)) * 100
        let suggested = max(ceil100, 100)
        let lower = max(floor100, 100)
        let upper = suggested > lower ? suggested : suggested + 100
        return (lower, suggested, upper)
    }

    /// 白事取单数（单位：元）：整百加 1（501/301 式）——
    /// 建议值＝折算值向上取整百再加 1；区间下限＝向下整百加 1；
    /// 折算恰为整百时建议值就是整百加 1（如 500 → 501）。
    /// 折算不足百元时下限/建议都取 101。
    static func baiRange(baseYuan: Double) -> (lower: Int, suggested: Int, upper: Int) {
        let floor100 = Int(baseYuan / 100.0) * 100
        if floor100 == 0 {
            return (101, 101, 201)
        }
        let lower = floor100 + 1
        let suggested = baseYuan <= Double(lower) ? lower : Int((baseYuan / 100.0).rounded(.up)) * 100 + 1
        let upper = suggested > lower ? suggested : suggested + 100
        return (lower, suggested, upper)
    }
}
