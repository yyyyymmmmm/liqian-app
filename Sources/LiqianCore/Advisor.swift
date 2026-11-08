import Foundation

// MARK: - 对话管家（v4.4）：混合架构，数字零幻觉
//
// 分工铁律：
// - LLM 只做意图解析，把问题转成结构化意图（类型＋人名/年份/方向/事由）；
//   解码结构里**不声明任何金额字段**——模型就算输出数字也没有落点，直接被丢弃。
// - 所有金额由 AdvisorEngine 在本地用 LedgerMath 口径计算，模型不碰账目数据。
// - AI 未就绪/解析失败时，AdvisorRules 用关键词规则兜底常见问法。

/// 意图类型（LLM 输出与规则兜底共用同一套）
public enum AdvisorIntentKind: String, Sendable, Equatable {
    /// 差额查询：我和某人谁欠谁
    case balance
    /// 某人往来：与某人的全部往来明细
    case person
    /// 待回名单：谁还没回礼
    case pending
    /// 时段汇总：某年/全部一共收了多少、随了多少
    case period
    /// 事由统计：婚礼一共收了多少
    case type
    /// 听不懂（模型给了表外值/结构缺失），调用方落规则兜底或明示不会
    case unknown
}

/// 结构化意图：只有筛选参数，没有金额——金额永远本地算。
public struct AdvisorIntent: Equatable, Sendable {
    public var kind: AdvisorIntentKind
    /// 人名（照问题原文；与账上人名的匹配在执行层做）
    public var person: String?
    /// 绝对年份（解码/规则层已把「今年/去年」换算好）；nil = 不限年份
    public var year: Int?
    /// LiqianConstants.received / .given；nil = 不限方向
    public var direction: String?
    /// 事由（LiqianConstants.ledgerTypes 之一）；nil = 不限事由
    public var ledgerType: String?

    public init(
        kind: AdvisorIntentKind,
        person: String? = nil,
        year: Int? = nil,
        direction: String? = nil,
        ledgerType: String? = nil
    ) {
        self.kind = kind
        self.person = person
        self.year = year
        self.direction = direction
        self.ledgerType = ledgerType
    }
}

// MARK: - 意图解码（DeepSeek 返回的意图 JSON → AdvisorIntent）

public enum AdvisorIntentParse {
    public enum ParseError: Error {
        /// 返回内容不是约定的 JSON 结构，整体无法解析
        case unreadable
    }

    /// 宽容解码：year 可能是数字 2025、字符串 "2025"/"this"/"last"、或缺失；
    /// 单个字段格式不对按 nil 落，不拖垮整条意图。
    /// 注意 RawIntent 故意不声明任何金额键——模型输出的数字键会被 Decodable 直接忽略。
    private struct RawIntent: Decodable {
        var intent: String?
        var person: String?
        var year: YearValue?
        var direction: String?
        var type: String?

        enum YearValue: Decodable {
            case number(Int)
            case text(String)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let n = try? container.decode(Int.self) {
                    self = .number(n)
                } else if let s = try? container.decode(String.self) {
                    self = .text(s)
                } else {
                    throw DecodingError.dataCorruptedError(
                        in: container, debugDescription: "year 只接受数字或字符串"
                    )
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case intent, person, year, direction, type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            intent = try container.decodeIfPresent(String.self, forKey: .intent)
            person = try container.decodeIfPresent(String.self, forKey: .person)
            year = try container.decodeIfPresent(YearValue.self, forKey: .year)
            direction = try container.decodeIfPresent(String.self, forKey: .direction)
            type = try container.decodeIfPresent(String.self, forKey: .type)
        }
    }

    /// currentYear 由调用方传入（「今年/去年」的换算基准，保证可单测）
    public static func decode(_ data: Data, currentYear: Int) throws -> AdvisorIntent {
        let raw: RawIntent
        do {
            raw = try JSONDecoder().decode(RawIntent.self, from: data)
        } catch {
            throw ParseError.unreadable
        }

        let kind = raw.intent.flatMap { AdvisorIntentKind(rawValue: $0) } ?? .unknown

        let person: String? = {
            let trimmed = raw.person?.trimmingCharacters(in: .whitespaces)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }()

        let year: Int? = {
            switch raw.year {
            case .number(let n):
                return (n >= 1900 && n <= 2100) ? n : nil
            case .text(let s):
                let t = s.trimmingCharacters(in: .whitespaces)
                if t == "this" || t == "今年" { return currentYear }
                if t == "last" || t == "去年" { return currentYear - 1 }
                if let n = Int(t), n >= 1900, n <= 2100 { return n }
                return nil
            case nil:
                return nil
            }
        }()

        let direction: String? = {
            switch raw.direction {
            case "given": return LiqianConstants.given
            case "received": return LiqianConstants.received
            default: return nil
            }
        }()

        let ledgerType: String? = raw.type.flatMap {
            LiqianConstants.ledgerTypes.contains($0) ? $0 : nil
        }

        return AdvisorIntent(
            kind: kind,
            person: person,
            year: year,
            direction: direction,
            ledgerType: ledgerType
        )
    }
}

// MARK: - 规则兜底（无 key / 未启用 / 模型失败时，关键词匹配常见问法）

public enum AdvisorRules {
    /// 关键词 → 意图。people 是账上全部人名（人名匹配靠它）；
    /// 兜不住返回 nil，调用方呈现明示文案，不硬编答案。
    public static func intent(from question: String, people: [String], currentYear: Int) -> AdvisorIntent? {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        let person = matchPerson(in: q, people: people)
        let year = parseYear(in: q, currentYear: currentYear)

        // 1) 带人名：优先差额，其次往来明细
        if let person {
            if containsAny(q, ["欠", "差额", "谁多", "多了", "结清", "两清", "回多少", "该回"]) {
                return AdvisorIntent(kind: .balance, person: person)
            }
            // 「XX随了多少」也走明细：卡片同时给收/随小计，用户自己读两边，不预设方向
            return AdvisorIntent(kind: .person, person: person, year: year)
        }

        // 2) 待回名单（不带人名时才问「谁」）
        if containsAny(q, ["待回", "没回", "未回", "还没回", "没有回", "谁欠", "欠我的", "该回礼"]) {
            return AdvisorIntent(kind: .pending)
        }

        // 3) 事由统计：命中事由词表且带统计语气
        if let type = LiqianConstants.ledgerTypes.first(where: { q.contains($0) }),
           containsAny(q, ["多少", "一共", "总共", "统计", "收了", "随了"]) {
            let direction: String? = q.contains("随") && !q.contains("收")
                ? LiqianConstants.given
                : (q.contains("收") && !q.contains("随") ? LiqianConstants.received : nil)
            return AdvisorIntent(kind: .type, year: year, direction: direction, ledgerType: type)
        }

        // 4) 时段汇总：有统计语气即可（年份可有可无，无年份 = 全部）
        if containsAny(q, ["一共", "总共", "汇总", "收了多少", "随了多少", "送了多少", "收多少", "随多少"]) {
            let direction: String? = containsAny(q, ["随了多少", "送了多少", "随多少"])
                ? LiqianConstants.given
                : (containsAny(q, ["收了多少", "收多少"]) ? LiqianConstants.received : nil)
            return AdvisorIntent(kind: .period, year: year, direction: direction)
        }

        return nil
    }

    /// 人名匹配：账上人名是问题子串即命中；多个命中取最长的（更具体）
    private static func matchPerson(in question: String, people: [String]) -> String? {
        people
            .filter { !$0.isEmpty && question.contains($0) }
            .max { $0.count < $1.count }
    }

    /// 年份解析：「去年」/「今年」/四位年份（19xx、20xx）
    private static func parseYear(in question: String, currentYear: Int) -> Int? {
        if question.contains("去年") { return currentYear - 1 }
        if question.contains("今年") { return currentYear }
        // 手工扫四位数字，避免正则在 Core 里引入额外依赖
        let chars = Array(question)
        guard chars.count >= 4 else { return nil }
        for i in 0...(chars.count - 4) {
            let slice = chars[i..<(i + 4)]
            if slice.allSatisfy({ $0.isNumber }), let n = Int(String(slice)),
               n >= 1900, n <= 2100 {
                return n
            }
        }
        return nil
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - 执行层（本地计算，金额只出自这里）

/// 一笔明细行（某人往来卡用）：字段全来自本地快照
public struct AdvisorEntryLine: Equatable, Sendable, Identifiable, Codable {
    public var person: String
    public var ledgerType: String
    public var direction: String
    public var amountCents: Int
    /// yyyy-MM-dd
    public var date: String

    public var id: String { "\(date)|\(direction)|\(amountCents)|\(ledgerType)|\(person)" }

    public init(person: String, ledgerType: String, direction: String, amountCents: Int, date: String) {
        self.person = person
        self.ledgerType = ledgerType
        self.direction = direction
        self.amountCents = amountCents
        self.date = date
    }
}

/// 结构化回答：UI 层按 case 渲染原生卡片，文案与数字都由事实拼
public enum AdvisorResult: Equatable, Sendable, Codable {
    /// 差额卡：命中的人物汇总（收/随/差额都在 PersonSummary 里）
    case balance(PersonSummary)
    /// 某人往来卡：人物小计 + 明细（日期倒序，已排除待送出，与全 App 口径一致）
    case personHistory(summary: PersonSummary, entries: [AdvisorEntryLine])
    /// 待回名单卡：pendingCents > 0 的人，金额大者靠前
    case pendingList([PersonSummary])
    /// 时段汇总卡：year=nil 表示全部时段；focusDirection 是问题侧重方向（可为 nil）
    case periodSummary(year: Int?, focusDirection: String?, received: Int, given: Int, count: Int)
    /// 事由统计卡：rows 为命中的事由行（指定事由时只有一行，未指定为全部）
    case typeSummary(rows: [TypeSummary], focusType: String?)
    /// 账上没有这个人
    case personNotFound(name: String)
    /// 差额/往来类意图没带人名
    case needPerson
    /// 意图听不懂（unknown）：UI 给明示文案
    case unsupported
}

public enum AdvisorEngine {
    /// 意图 + 本地快照 → 结构化结果。entries 顺序遵循 AppSupport.snapshots 约定（新→旧）。
    public static func execute(_ intent: AdvisorIntent, entries: [EntrySnapshot]) -> AdvisorResult {
        switch intent.kind {
        case .balance:
            guard let name = intent.person, !name.isEmpty else { return .needPerson }
            guard let hit = matchSummary(name: name, in: LedgerMath.people(from: entries)) else {
                return .personNotFound(name: name)
            }
            return .balance(hit)

        case .person:
            guard let name = intent.person, !name.isEmpty else { return .needPerson }
            let people = LedgerMath.people(from: entries)
            guard let hit = matchSummary(name: name, in: people) else {
                return .personNotFound(name: name)
            }
            let scoped = entries.filter { $0.person == hit.name && !$0.isPendingSend }
            let yearScoped = intent.year.map { y in scoped.filter { $0.date.hasPrefix(String(y)) } } ?? scoped
            let lines = yearScoped
                .sorted { $0.date > $1.date }
                .map {
                    AdvisorEntryLine(
                        person: $0.person, ledgerType: $0.ledgerType,
                        direction: $0.direction, amountCents: $0.amountCents, date: $0.date
                    )
                }
            // 限定年份时小计也要跟着年份走，不能拿全时段数字冒充
            let scopedSummary: PersonSummary
            if intent.year != nil {
                scopedSummary = LedgerMath.people(from: yearScoped).first { $0.name == hit.name }
                    ?? PersonSummary(name: hit.name, relation: hit.relation)
            } else {
                scopedSummary = hit
            }
            return .personHistory(summary: scopedSummary, entries: lines)

        case .pending:
            let list = LedgerMath.people(from: entries)
                .filter { $0.pendingCents > 0 }
                .sorted {
                    if $0.pendingCents != $1.pendingCents { return $0.pendingCents > $1.pendingCents }
                    return $0.lastDate > $1.lastDate
                }
            return .pendingList(list)

        case .period:
            let (received, given, count) = totals(entries: entries, year: intent.year)
            return .periodSummary(
                year: intent.year, focusDirection: intent.direction,
                received: received, given: given, count: count
            )

        case .type:
            let all = LedgerMath.typeSummary(from: entries)
            if let focus = intent.ledgerType {
                let rows = all.filter { $0.type == focus }
                // 该事由一笔没有时也要出行（0 值事实），不能装作没这回事
                return .typeSummary(
                    rows: rows.isEmpty ? [TypeSummary(type: focus)] : rows,
                    focusType: focus
                )
            }
            return .typeSummary(rows: all, focusType: nil)

        case .unknown:
            return .unsupported
        }
    }

    /// 人名匹配（与规则层故意不同）：精确 > 包含（账上名含问名，或问名含账上名）；
    /// 多个包含命中取最近往来者，结果回带命中的账上名，UI 展示的是命中名不是问名。
    private static func matchSummary(name: String, in people: [PersonSummary]) -> PersonSummary? {
        if let exact = people.first(where: { $0.name == name }) { return exact }
        let fuzzy = people.filter { $0.name.contains(name) || name.contains($0.name) }
        return fuzzy.max { $0.lastDate < $1.lastDate }
    }

    /// 时段合计（排除待送出，与 LedgerMath 全局口径一致）
    private static func totals(entries: [EntrySnapshot], year: Int?) -> (received: Int, given: Int, count: Int) {
        var received = 0
        var given = 0
        var count = 0
        let yearPrefix = year.map { String($0) }
        for e in entries {
            if e.isPendingSend { continue }
            if let yearPrefix, !e.date.hasPrefix(yearPrefix) { continue }
            if e.direction == LiqianConstants.received {
                received += e.amountCents
            } else {
                given += e.amountCents
            }
            count += 1
        }
        return (received, given, count)
    }
}
