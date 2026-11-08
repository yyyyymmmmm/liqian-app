import Foundation

// MARK: - 对话管家 v5.3：工具结果的结构化卡片模型（UI 侧呈现）
//
// v5.2 的工具路径只把结果以 JSON 文本回给模型组织语言，视图层只剩一堵
// 文字墙——工具明明查到的是结构化数据，呈现却退化回纯文本（连 Markdown
// 标记都原样露在屏上，用户截图实锤）。
//
// v5.3 在 AdvisorToolEngine 的同一条执行路径上挂一份 UI 侧结果：
// 每次工具执行在算出数据的同一作用域里，顺手把同一份数据组装成卡片
// 模型（AdvisorCard），视图层直接渲染原生卡片；模型文字退为卡片上方
// 的一句结论引子。不是另查一遍账——卡片与回给模型的 JSON 出自同一次
// 计算，数字口径（LedgerMath，金额以「分」记）完全一致。
//
// 失败/查不到（ok == false）不出卡：模型按问答纪律如实说明即可，
// 不拿空卡凑数。例外是 pending_list 与 upcoming_events：查通了但名单
// 为空本身就是结论（都结清了/近期没安排），照常出卡由视图给体面空态。

/// 一次工具执行的双份产物：给模型的 JSON 原文＋给视图的结构化卡片
public struct AdvisorToolOutcome: Sendable, Equatable {
    /// 回给模型的 JSON 文本（与 v5.2 的 AdvisorToolEngine.execute 返回逐字一致）
    public var json: String
    /// UI 侧结构化卡片；失败/查不到时为 nil
    public var card: AdvisorCard?

    public init(json: String, card: AdvisorCard?) {
        self.json = json
        self.card = card
    }
}

/// 工具卡片：一种工具一张卡（aggregate 按有无对比/分组分三形）。
/// 一次回答可带多卡（多工具/多轮），视图按调用顺序依次呈现。
public enum AdvisorCard: Sendable, Equatable, Codable {
    /// query_person：人物卡（汇总在 summary 里，附最近往来）
    case person(AdvisorPersonCard)
    /// query_records：逐笔流水卡（rows 是限量子集，totalCount 是全量）
    case records(AdvisorRecordsCard)
    /// aggregate 带两时段对比：对比卡
    case comparison(AdvisorComparisonCard)
    /// aggregate 带分组：分组条卡
    case groups(AdvisorGroupsCard)
    /// aggregate 只给总计：汇总卡
    case totals(AdvisorTotalsCard)
    /// pending_list：待回名单卡
    case pending(AdvisorPendingCard)
    /// upcoming_events：场次卡（近期场次＋备礼进度）
    case events(AdvisorEventsCard)
    /// draft_record：待确认记账卡（v5.4；用户点确认才真正入账）
    case draftRecord(AdvisorDraftRecordCard)
}

// MARK: - 共用小件

/// 一段时段的收/随/笔数合计（金额单位：分，与 LedgerMath 全线一致）
public struct AdvisorMoneyTotals: Sendable, Equatable, Codable {
    /// 时段人话标签（引擎 rangeText 口径，如「2026-01-01 至 2026-12-31」/「全部时段」）
    public var rangeLabel: String
    public var receivedCents: Int
    public var givenCents: Int
    public var recordCount: Int

    public var netCents: Int { receivedCents - givenCents }

    public init(rangeLabel: String, receivedCents: Int, givenCents: Int, recordCount: Int) {
        self.rangeLabel = rangeLabel
        self.receivedCents = receivedCents
        self.givenCents = givenCents
        self.recordCount = recordCount
    }
}

/// 一行逐笔（流水卡与备礼清单共用）：字段全来自本地快照
public struct AdvisorRecordRow: Sendable, Equatable, Identifiable, Codable {
    public var person: String
    public var relation: String
    /// LiqianConstants.received / .given
    public var direction: String
    public var amountCents: Int
    /// yyyy-MM-dd
    public var date: String
    public var ledgerType: String
    /// 所属礼簿标题（查不到归属时为空串）
    public var ledgerTitle: String
    /// 待送出（备礼）：不计汇总，视图挂素签区分
    public var isPendingSend: Bool

    public var id: String {
        "\(date)|\(person)|\(direction)|\(amountCents)|\(ledgerTitle)|\(isPendingSend)"
    }

    public init(
        person: String, relation: String, direction: String, amountCents: Int,
        date: String, ledgerType: String, ledgerTitle: String = "", isPendingSend: Bool = false
    ) {
        self.person = person
        self.relation = relation
        self.direction = direction
        self.amountCents = amountCents
        self.date = date
        self.ledgerType = ledgerType
        self.ledgerTitle = ledgerTitle
        self.isPendingSend = isPendingSend
    }
}

// MARK: - 各卡负载

/// 人物卡：summary 是 LedgerMath 的人物汇总（收/随/差额/待回都在里面），
/// recent 是最近若干笔（日期倒序，与回给模型的 recentRecords 同一份）
public struct AdvisorPersonCard: Sendable, Equatable, Codable {
    public var summary: PersonSummary
    public var recent: [AdvisorEntryLine]

    public init(summary: PersonSummary, recent: [AdvisorEntryLine]) {
        self.summary = summary
        self.recent = recent
    }
}

/// 逐笔流水卡：rows 为限量返回的子集，totalCount 为符合条件总笔数
public struct AdvisorRecordsCard: Sendable, Equatable, Codable {
    public var totalCount: Int
    public var rows: [AdvisorRecordRow]

    public init(totalCount: Int, rows: [AdvisorRecordRow]) {
        self.totalCount = totalCount
        self.rows = rows
    }
}

/// 对比卡：主时段 vs 对比时段，差值口径＝主 − 对比（与回模型的 delta 同源）
public struct AdvisorComparisonCard: Sendable, Equatable, Codable {
    public var main: AdvisorMoneyTotals
    public var other: AdvisorMoneyTotals

    public var deltaReceivedCents: Int { main.receivedCents - other.receivedCents }
    public var deltaGivenCents: Int { main.givenCents - other.givenCents }
    public var deltaNetCents: Int { main.netCents - other.netCents }

    public init(main: AdvisorMoneyTotals, other: AdvisorMoneyTotals) {
        self.main = main
        self.other = other
    }
}

/// 分组条卡：一行一组（收/随/净/笔数），dimension 是 aggregate 的
/// groupBy 原始值（month/year/type/relation/ledger），中文名由视图映射
public struct AdvisorGroupsCard: Sendable, Equatable, Codable {
    public var dimension: String
    public var rangeLabel: String
    public var rows: [AdvisorGroupRow]

    public init(dimension: String, rangeLabel: String, rows: [AdvisorGroupRow]) {
        self.dimension = dimension
        self.rangeLabel = rangeLabel
        self.rows = rows
    }
}

public struct AdvisorGroupRow: Sendable, Equatable, Identifiable, Codable {
    public var key: String
    public var receivedCents: Int
    public var givenCents: Int
    public var recordCount: Int

    public var netCents: Int { receivedCents - givenCents }
    public var id: String { key }

    public init(key: String, receivedCents: Int, givenCents: Int, recordCount: Int) {
        self.key = key
        self.receivedCents = receivedCents
        self.givenCents = givenCents
        self.recordCount = recordCount
    }
}

/// 汇总卡：单时段总计（aggregate 不分组、无对比时）
public struct AdvisorTotalsCard: Sendable, Equatable, Codable {
    public var totals: AdvisorMoneyTotals

    public init(totals: AdvisorMoneyTotals) {
        self.totals = totals
    }
}

/// 待回名单卡：people 是按待回额降序的限量子集（PersonSummary 原样），
/// totalPeople/totalPendingCents 是全量口径（与回模型的 JSON 同源）
public struct AdvisorPendingCard: Sendable, Equatable, Codable {
    public var totalPeople: Int
    public var totalPendingCents: Int
    public var people: [PersonSummary]

    public init(totalPeople: Int, totalPendingCents: Int, people: [PersonSummary]) {
        self.totalPeople = totalPeople
        self.totalPendingCents = totalPendingCents
        self.people = people
    }
}

/// 场次卡：近期场次＋备礼清单（prep 是限量子集，prepTotalCount 是全量）
public struct AdvisorEventsCard: Sendable, Equatable, Codable {
    public var events: [AdvisorEventItem]
    public var prepTotalCount: Int
    public var prep: [AdvisorRecordRow]

    public init(events: [AdvisorEventItem], prepTotalCount: Int, prep: [AdvisorRecordRow]) {
        self.events = events
        self.prepTotalCount = prepTotalCount
        self.prep = prep
    }
}

public struct AdvisorEventItem: Sendable, Equatable, Identifiable, Codable {
    public var title: String
    public var type: String
    /// yyyy-MM-dd
    public var date: String
    /// 距今天数（日期解析失败时为 -1，与回模型的 daysUntil 同口径，视图据此决定是否显示）
    public var daysUntil: Int

    public var id: String { "\(date)|\(title)" }

    public init(title: String, type: String, date: String, daysUntil: Int) {
        self.title = title
        self.type = type
        self.date = date
        self.daysUntil = daysUntil
    }
}

// MARK: - 待确认记账卡（v5.4 新增：AI 只起草，用户确认才入账）

/// draft_record 组装出的待确认记账草稿：字段全部来自用户原话经模型解析、
/// 本地校验后的结果（金额只用原话里的数，缺人名/金额在工具层就回 ok:false
/// 让模型追问，不会走到组卡这一步）。
/// 卡片自带交互状态（pending/saved/discarded＋选定礼簿＋已存记录 id），
/// 随对话一起持久化：退出重进，待确认的卡仍可确认、已入账的回执仍在。
public struct AdvisorDraftRecordCard: Sendable, Equatable, Codable {
    public enum State: String, Sendable, Equatable, Codable {
        /// 待用户确认（可改礼簿、点确认入账或算了）
        case pending
        /// 已确认并写入账本（savedRecordID 指向那笔 GiftRecord）
        case saved
        /// 用户点了「算了」：丢弃不留痕（账本里不会有这笔）
        case discarded
    }

    /// 草稿唯一 id（同一回答多张草稿卡时靠它定位回写状态）
    public var draftID: UUID
    public var person: String
    /// 账上已知此人时的关系（查不到给空串，入账时视图回退表单默认「朋友」）
    public var relation: String
    /// LiqianConstants.received / .given（随礼、回礼都落 given）
    public var direction: String
    public var amountCents: Int
    /// yyyy-MM-dd（用户没说日期时为今天）
    public var date: String
    /// 场合（事由）：参数给了合法值才有，否则空串（视图不展示此行）
    public var ledgerType: String
    /// 建议目标礼簿：与此人最近往来的礼簿；无往来时为 nil（视图回退
    /// 日期最新非示例簿）。只是建议，卡上可改选。
    public var suggestedLedgerID: UUID?
    public var suggestedLedgerTitle: String

    public var state: State = .pending
    /// 用户在卡上选定的礼簿（确认时以它为准；nil 表示用建议/兜底）
    public var chosenLedgerID: UUID?
    /// 入账后那笔 GiftRecord 的 id（回执卡据此打开记录详情）
    public var savedRecordID: UUID?

    public init(
        draftID: UUID = UUID(),
        person: String,
        relation: String = "",
        direction: String,
        amountCents: Int,
        date: String,
        ledgerType: String = "",
        suggestedLedgerID: UUID? = nil,
        suggestedLedgerTitle: String = ""
    ) {
        self.draftID = draftID
        self.person = person
        self.relation = relation
        self.direction = direction
        self.amountCents = amountCents
        self.date = date
        self.ledgerType = ledgerType
        self.suggestedLedgerID = suggestedLedgerID
        self.suggestedLedgerTitle = suggestedLedgerTitle
    }
}
