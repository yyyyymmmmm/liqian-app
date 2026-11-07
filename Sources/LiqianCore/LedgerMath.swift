import Foundation
import SwiftData

// MARK: - 纯函数账务规则（不碰 SwiftData，可单测；口径与 Flutter store.dart 一致）

/// 一笔记录的纯值快照。ledgerType 为所属账本的事由（找不到账本时传 ""，typeSummary 会跳过）。
public struct EntrySnapshot: Sendable, Equatable {
    public var person: String
    public var relation: String
    public var amountCents: Int
    public var direction: String
    /// yyyy-MM-dd
    public var date: String
    public var status: String
    public var ledgerType: String

    public init(
        person: String,
        relation: String = "朋友",
        amountCents: Int,
        direction: String,
        date: String,
        status: String = LiqianConstants.sentStatus,
        ledgerType: String = ""
    ) {
        self.person = person
        self.relation = relation
        self.amountCents = amountCents
        self.direction = direction
        self.date = date
        self.status = status
        self.ledgerType = ledgerType
    }

    public var isPendingSend: Bool {
        direction == LiqianConstants.given && status == LiqianConstants.pendingStatus
    }
}

public struct PersonSummary: Sendable, Equatable, Identifiable {
    public var name: String
    public var relation: String
    /// 收礼合计（别人给我）
    public var received: Int
    /// 随礼合计（我送出去，仅已送出）
    public var given: Int
    /// 待回金额（v2.4 定版）：＝ max(收 − 随差额, 0)，与 balance 同源——
    /// balance > 0 ⇔ pendingCents == balance；balance ≤ 0 时为 0。
    /// （旧口径「最后一笔已送出随礼之后的收礼合计」与差额是两套账，
    /// 会出现「我多给却挂着待回」的自相矛盾，已废止。）
    public var pendingCents: Int
    /// 笔数（不含待送出）
    public var count: Int
    public var lastDate: String

    public var id: String { name }
    /// 正数＝对方多给，我欠人情
    public var balance: Int { received - given }
    public var hasPending: Bool { pendingCents > 0 }

    public init(
        name: String,
        relation: String = "朋友",
        received: Int = 0,
        given: Int = 0,
        pendingCents: Int = 0,
        count: Int = 0,
        lastDate: String = ""
    ) {
        self.name = name
        self.relation = relation
        self.received = received
        self.given = given
        self.pendingCents = pendingCents
        self.count = count
        self.lastDate = lastDate
    }
}

public struct RelationSummary: Sendable, Equatable, Identifiable {
    public var relation: String
    public var received: Int
    public var given: Int
    public var count: Int

    public var id: String { relation }
    /// 往来总额（收+随），关系分布与排行的排序依据
    public var total: Int { received + given }

    public init(relation: String, received: Int = 0, given: Int = 0, count: Int = 0) {
        self.relation = relation
        self.received = received
        self.given = given
        self.count = count
    }
}

public struct YearSummary: Sendable, Equatable {
    public var recv: Int
    public var given: Int
    public var count: Int

    public init(recv: Int = 0, given: Int = 0, count: Int = 0) {
        self.recv = recv
        self.given = given
        self.count = count
    }
}

public struct TypeSummary: Sendable, Equatable, Identifiable {
    public var type: String
    public var received: Int
    public var given: Int
    public var count: Int

    public var id: String { type }

    public init(type: String, received: Int = 0, given: Int = 0, count: Int = 0) {
        self.type = type
        self.received = received
        self.given = given
        self.count = count
    }
}

public enum LedgerMath {
    /// 金额输出：¥ + 千分位（PRO-AUDIT §1.5 定版，如 ¥10,000 / ¥66.50）；
    /// 整数不带小数，非整保留两位；负数沿用旧口径 ¥-N。
    public static func fmtMoney(cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absCents = abs(cents)
        let yuan = absCents / 100
        let rem = absCents % 100
        var head = String(yuan)
        var grouped = ""
        while head.count > 3 {
            grouped = "," + head.suffix(3) + grouped
            head = String(head.dropLast(3))
        }
        grouped = head + grouped
        if rem == 0 { return "¥\(sign)\(grouped)" }
        return "¥\(sign)\(grouped).\(rem < 10 ? "0" : "")\(rem)"
    }

    public static func sum(_ entries: [EntrySnapshot]) -> Int {
        entries.reduce(0) { $0 + $1.amountCents }
    }

    /// 按人聚合（跨账本），差额语义与 Flutter store.people() 一致：
    /// - 差额：收礼全计；随礼只计已送出，待送出不计金额与笔数（只更新最近日期）。
    /// - 待回（v2.4 定版）：待回金额恒等于 max(差额, 0)，与差额同源同值，
    ///   不再另算一套「最近一笔随礼之后的收礼」（旧自动规则会与差额互相矛盾）。
    /// - relation 取时间上最近一笔的关系：把记录按时间正序排（日期升序；同日时
    ///   序号大的视为更早——即约定传入顺序为「新→旧」，与 Flutter records 列表一致）。
    /// - 结果按 lastDate 倒序。
    public static func people(from entries: [EntrySnapshot]) -> [PersonSummary] {
        var summaries: [String: PersonSummary] = [:]
        var byPerson: [String: [(index: Int, entry: EntrySnapshot)]] = [:]

        for (i, e) in entries.enumerated() {
            if summaries[e.person] == nil {
                summaries[e.person] = PersonSummary(name: e.person)
            }
            byPerson[e.person, default: []].append((i, e))
            if e.date > (summaries[e.person]?.lastDate ?? "") {
                summaries[e.person]?.lastDate = e.date
            }
            if e.isPendingSend { continue }
            if e.direction == LiqianConstants.received {
                summaries[e.person]?.received += e.amountCents
            } else {
                summaries[e.person]?.given += e.amountCents
            }
            summaries[e.person]?.count += 1
        }

        for (name, list) in byPerson {
            let chrono = list.sorted { a, b in
                if a.entry.date != b.entry.date { return a.entry.date < b.entry.date }
                return a.index > b.index // 同日：序号大＝创建更早（传入顺序为新→旧）
            }
            if let latest = chrono.last {
                summaries[name]?.relation = latest.entry.relation
            }
            // 待回与差额同源（v2.4 定版）：收多于随的差额即待回，我多给时为 0
            if let s = summaries[name] {
                summaries[name]?.pendingCents = max(s.balance, 0)
            }
        }

        return summaries.values.sorted { $0.lastDate > $1.lastDate }
    }

    /// 某年收/随汇总（待送出不计），与 Flutter yearSummary 一致
    public static func yearSummary(from entries: [EntrySnapshot], year: String) -> YearSummary {
        var s = YearSummary()
        for e in entries {
            if !e.date.hasPrefix(year) || e.isPendingSend { continue }
            if e.direction == LiqianConstants.received {
                s.recv += e.amountCents
            } else {
                s.given += e.amountCents
            }
            s.count += 1
        }
        return s
    }

    /// 按事由分布（待送出不计），按收+随总额倒序，与 Flutter typeSummary 一致。
    /// 差异：Flutter 会为「有账本但零记录」的事由也建一行（count=0），
    /// 本函数只按快照聚合，展示层与 Flutter 一样过滤 count>0，两边看到的一致。
    public static func typeSummary(from entries: [EntrySnapshot]) -> [TypeSummary] {
        var map: [String: TypeSummary] = [:]
        for e in entries {
            if e.ledgerType.isEmpty { continue }
            if map[e.ledgerType] == nil { map[e.ledgerType] = TypeSummary(type: e.ledgerType) }
            if e.isPendingSend { continue }
            if e.direction == LiqianConstants.received {
                map[e.ledgerType]?.received += e.amountCents
            } else {
                map[e.ledgerType]?.given += e.amountCents
            }
            map[e.ledgerType]?.count += 1
        }
        return map.values.sorted { ($0.received + $0.given) > ($1.received + $1.given) }
    }

    /// 按关系分布（待送出不计），按往来总额倒序。给「我的」页关系分布图用。
    public static func relationSummary(from entries: [EntrySnapshot]) -> [RelationSummary] {
        var map: [String: RelationSummary] = [:]
        for e in entries {
            if map[e.relation] == nil { map[e.relation] = RelationSummary(relation: e.relation) }
            if e.isPendingSend { continue }
            if e.direction == LiqianConstants.received {
                map[e.relation]?.received += e.amountCents
            } else {
                map[e.relation]?.given += e.amountCents
            }
            map[e.relation]?.count += 1
        }
        return map.values.sorted { $0.total > $1.total }
    }

    /// 回礼参考区间：只用本人历史——取这个人最近一笔收礼为锚，
    /// 给「对等略添」的整数区间。无收礼记录返回 nil（没依据不瞎给）。
    /// 区间（先按元算再转分）：
    /// - 下限 = 锚点金额向下取整到百元，不足百元按 100 元；
    /// - 上限 = 锚点 ×1.2 向上取整到百元。
    /// 例：500 元 → [500, 600]；450 元 → [400, 600]。
    public static func returnGiftSuggestion(
        from entries: [EntrySnapshot],
        person: String,
        today: String
    ) -> ReturnGiftSuggestion? {
        // 收礼无待送出概念，isPendingSend 只可能出现在随礼上，这里无需过滤
        let received = entries.filter {
            $0.person == person && $0.direction == LiqianConstants.received
        }
        // 最近一笔：日期最大；同日按传入顺序（约定新→旧）取先出现者
        var latest: EntrySnapshot?
        for e in received {
            if let cur = latest {
                if e.date > cur.date { latest = e }
            } else {
                latest = e
            }
        }
        guard let anchor = latest else { return nil }

        let baseYuan = Double(anchor.amountCents) / 100.0
        var lowerYuan = Int((baseYuan / 100.0).rounded(.down)) * 100
        if lowerYuan < 100 { lowerYuan = 100 }
        let upperYuan = Int((baseYuan * 1.2 / 100.0).rounded(.up)) * 100

        let anchorYear = Int(anchor.date.prefix(4)) ?? 0
        let todayYear = Int(today.prefix(4)) ?? anchorYear
        return ReturnGiftSuggestion(
            lowerCents: lowerYuan * 100,
            upperCents: upperYuan * 100,
            lastAmountCents: anchor.amountCents,
            lastDate: anchor.date,
            lastType: anchor.ledgerType,
            yearsAgo: max(0, todayYear - anchorYear)
        )
    }
}

/// 回礼参考区间的结果 + 依据素材（View 层拼文案，Core 只给事实）
public struct ReturnGiftSuggestion: Sendable, Equatable {
    public var lowerCents: Int
    public var upperCents: Int
    /// 锚点：最近一笔收礼金额（分）
    public var lastAmountCents: Int
    /// 锚点日期 yyyy-MM-dd
    public var lastDate: String
    /// 锚点事由（所属礼簿类型，如「婚礼」；无账本信息时为 ""）
    public var lastType: String
    /// 锚点距今整年数（按年份差）
    public var yearsAgo: Int

    public init(
        lowerCents: Int,
        upperCents: Int,
        lastAmountCents: Int,
        lastDate: String,
        lastType: String,
        yearsAgo: Int
    ) {
        self.lowerCents = lowerCents
        self.upperCents = upperCents
        self.lastAmountCents = lastAmountCents
        self.lastDate = lastDate
        self.lastType = lastType
        self.yearsAgo = yearsAgo
    }
}

public extension GiftRecord {
    /// 转纯值快照喂给 LedgerMath；ledgerType 由调用方按 ledgerID 查所属账本传入
    func snapshot(ledgerType: String) -> EntrySnapshot {
        EntrySnapshot(
            person: person,
            relation: relation,
            amountCents: amountCents,
            direction: direction,
            date: date,
            status: status,
            ledgerType: ledgerType
        )
    }
}
