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
    /// 未回金额：最后一笔「已送出」随礼之后的收礼合计（自动规则 FR-04.1）
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
    /// 金额输出与 Dart fmtMoney 一致：整数输出 ¥N，有分输出两位小数
    public static func fmtMoney(cents: Int) -> String {
        if cents % 100 == 0 { return "¥\(cents / 100)" }
        return String(format: "¥%.2f", Double(cents) / 100.0)
    }

    public static func sum(_ entries: [EntrySnapshot]) -> Int {
        entries.reduce(0) { $0 + $1.amountCents }
    }

    /// 按人聚合（跨账本），语义与 Flutter store.people() 一致：
    /// - 差额：收礼全计；随礼只计已送出，待送出不计金额与笔数（只更新最近日期）。
    /// - 未回（自动规则）：把一个人的记录按时间正序排（日期升序；同日时序号大的
    ///   视为更早——即约定传入顺序为「新→旧」，与 Flutter records 列表一致），
    ///   每遇到一笔已送出随礼就把未回清零，其后的收礼累计为未回金额。
    /// - relation 取时间上最近一笔的关系（同日取正序排列的最后一笔）。
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
            var pending = 0
            for item in chrono {
                let r = item.entry
                if r.direction == LiqianConstants.given && !r.isPendingSend {
                    pending = 0 // 已送出一次，之前的收礼视为已回
                } else if r.direction == LiqianConstants.received {
                    pending += r.amountCents
                }
            }
            summaries[name]?.pendingCents = pending
            if let latest = chrono.last {
                summaries[name]?.relation = latest.entry.relation
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
