import Foundation
import SwiftData

// MARK: - 纯函数账务规则（不碰 SwiftData，可单测；口径与 Flutter store.dart 一致）

/// 一笔记录的纯值快照。ledgerType 为所属账本的事由（找不到账本时传 ""，typeSummary 会跳过）。
public struct EntrySnapshot: Sendable, Equatable, Codable {
    public var person: String
    public var relation: String
    public var amountCents: Int
    public var direction: String
    /// yyyy-MM-dd
    public var date: String
    public var status: String
    public var ledgerType: String
    /// 所属礼簿 id（v4.7 新增）：场次（去重礼簿数）类聚合需要它；
    /// 旧调用点不传时为 nil，该类聚合自动跳过 nil，不影响既有口径。
    public var ledgerID: UUID?

    public init(
        person: String,
        relation: String = "朋友",
        amountCents: Int,
        direction: String,
        date: String,
        status: String = LiqianConstants.sentStatus,
        ledgerType: String = "",
        ledgerID: UUID? = nil
    ) {
        self.person = person
        self.relation = relation
        self.amountCents = amountCents
        self.direction = direction
        self.date = date
        self.status = status
        self.ledgerType = ledgerType
        self.ledgerID = ledgerID
    }

    public var isPendingSend: Bool {
        direction == LiqianConstants.given && status == LiqianConstants.pendingStatus
    }
}

public struct PersonSummary: Sendable, Equatable, Identifiable, Codable {
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

public struct TypeSummary: Sendable, Equatable, Identifiable, Codable {
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

/// 关系用量（v5.10，关系管理页行内「N 人 · M 笔」）：人数＝带该关系
/// 记录的不重名人数，笔数＝该关系计入统计的记录数；口径与
/// relationSummary 一致（待送出不计）。同一人可出现在多个关系下
/// （关系是逐笔落的），各关系分别计数。
public struct RelationUsage: Sendable, Equatable, Identifiable {
    public var relation: String
    public var people: Int
    public var records: Int

    public var id: String { relation }

    public init(relation: String, people: Int = 0, records: Int = 0) {
        self.relation = relation
        self.people = people
        self.records = records
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

    /// 逐笔金额带符号文本（v5.0.2 用户改版定版）：收礼 `+¥N`、随礼 `−¥N`
    /// （减号为数学减号 U+2212，不用连字符），金额主体复用 fmtMoney 的
    /// 千分位口径；零金额中性呈现 `¥0`（不带符号、方向不显——组件层
    /// 同步回墨色）。全 App 逐笔金额只许走本函数＋SignedMoneyText 组件，
    /// 不许各页自拼符号。汇总数字（合计/差额/待回）不走本函数、仍用 fmtMoney。
    public static func signedMoney(cents: Int, direction: String) -> String {
        let absCents = abs(cents)
        if absCents == 0 { return fmtMoney(cents: 0) }
        let body = fmtMoney(cents: absCents)
        return direction == LiqianConstants.received ? "+\(body)" : "−\(body)"
    }

    /// 逐笔金额的 VoiceOver 读法（v5.0.2）：只读符号聋用户听不出方向，
    /// 必须读方向词＋金额读数——「收 500 元」/「送 500 元」；零金额
    /// 同样带方向（「收 0 元」），不让读屏用户丢方向信息。
    public static func signedMoneyAccessibility(cents: Int, direction: String) -> String {
        let word = direction == LiqianConstants.received ? "收" : "送"
        return "\(word) \(plainMoney(cents: abs(cents))) 元"
    }

    /// 无符号金额读数（VoiceOver 用）：千分位、非整两位、无 ¥ 符号，
    /// 如 1,000 / 66.50。仅供 signedMoneyAccessibility 拼读法。
    private static func plainMoney(cents: Int) -> String {
        String(fmtMoney(cents: cents).dropFirst())
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

    /// 按关系用量（v5.10）：人数（不重名）＋笔数，口径与 relationSummary
    /// 一致（待送出不计）。给关系管理页行内用量与改名/删除确认文案用——
    /// 确认弹窗里的笔数必须与级联真正会改写的范围一致，故笔数按
    /// 「全部记录（含待送出）」另由 relationReferenceCount 按原始关系值计。
    public static func relationUsage(from entries: [EntrySnapshot]) -> [RelationUsage] {
        var people: [String: Set<String>] = [:]
        var counts: [String: Int] = [:]
        for e in entries {
            if e.isPendingSend { continue }
            people[e.relation, default: []].insert(e.person)
            counts[e.relation, default: 0] += 1
        }
        return counts.keys.map {
            RelationUsage(relation: $0, people: people[$0]?.count ?? 0, records: counts[$0] ?? 0)
        }.sorted { $0.records > $1.records }
    }

    /// 关系被引用次数（v5.10）：不分待送出与否，数的是「值等于该关系的
    /// 记录条数」——改名级联与删除影响面按这个数说话（级联改写一切引用，
    /// 包括待送出记录）。入参是关系字符串数组（记录与提醒分开数、口径同理）。
    public static func relationReferenceCount(of name: String, in values: [String]) -> Int {
        values.reduce(0) { $0 + ($1 == name ? 1 : 0) }
    }

    // MARK: - v4.7 图表补全聚合（纯函数，口径与上列一致：待送出不计金额/笔数）

    /// 按月聚合行（key = yyyy-MM）；cumulativeNet 为自序列首月起的累计净额
    public struct MonthAggregate: Sendable, Equatable, Identifiable {
        public var month: String
        public var received: Int
        public var given: Int
        public var count: Int
        public var cumulativeNet: Int

        public var id: String { month }
        public var net: Int { received - given }

        public init(month: String, received: Int = 0, given: Int = 0, count: Int = 0, cumulativeNet: Int = 0) {
            self.month = month
            self.received = received
            self.given = given
            self.count = count
            self.cumulativeNet = cumulativeNet
        }
    }

    /// 月度序列：只含有数据的月份、按月升序，cumulativeNet 逐月滚算。
    /// 展示层的定长窗口（补零对齐）由视图按 key 取用，本函数不补空月。
    public static func monthlyAggregates(from entries: [EntrySnapshot]) -> [MonthAggregate] {
        var map: [String: MonthAggregate] = [:]
        for e in entries where !e.isPendingSend {
            let key = String(e.date.prefix(7))
            if map[key] == nil { map[key] = MonthAggregate(month: key) }
            if e.direction == LiqianConstants.received {
                map[key]?.received += e.amountCents
            } else {
                map[key]?.given += e.amountCents
            }
            map[key]?.count += 1
        }
        var rows = map.values.sorted { $0.month < $1.month }
        var running = 0
        for i in rows.indices {
            running += rows[i].net
            rows[i].cumulativeNet = running
        }
        return rows
    }

    // MARK: - v4.7.1 图表窗口与轴标（纯函数）

    /// 自适应月份窗口：在基础键序列（升序 yyyy-MM）上，按「有数据的月份」
    /// 收敛窗口——数据跨度（首个到末个数据月，含两端）≤ 4 个月时，只取
    /// 「跨度 + 两端各 1 个月填充」（填充在序列内截断）；跨度更大、没有
    /// 数据月、或数据月不在基础序列内时，原样返回基础序列。
    /// 动机：近 12 个月只有 1 个月有数时硬摆 12 个空槽，图面 90% 空白、
    /// 轴标还挤成一团（v4.7 真机实证）。
    public static func adaptiveMonthKeys(baseKeys: [String], dataMonths: Set<String>) -> [String] {
        let hits = baseKeys.indices.filter { dataMonths.contains(baseKeys[$0]) }
        guard let first = hits.first, let last = hits.last else { return baseKeys }
        let span = last - first + 1
        guard span <= 4 else { return baseKeys }
        let lo = max(0, first - 1)
        let hi = min(baseKeys.count - 1, last + 1)
        return Array(baseKeys[lo...hi])
    }

    /// 月份轴标签（短格式）：同年只写「N月」（无前导零）；窗口跨年时
    /// 仅 1 月带年份（「26年1月」），让跨年点可辨认又不把每个标签拉长。
    /// key 为 yyyy-MM；窗口 ≤ 12 个月时各月号至多出现一次，标签不重名。
    public static func monthAxisLabel(key: String, multiYear: Bool) -> String {
        let month = Int(key.suffix(2)) ?? 0
        if multiYear, month == 1 {
            return "\(String(key.prefix(4)).suffix(2))年1月"
        }
        return "\(month)月"
    }

    /// 单笔金额分桶（元界：200 / 500 / 1000 / 2000）：收、随不分开，
    /// 每笔（待送出除外）按金额落桶，给笔数与金额合计双口径。
    public struct AmountBucket: Sendable, Equatable, Identifiable {
        public var label: String
        /// 桶下界（分，含）；上界为下一桶下界，末桶无上界
        public var lowerCents: Int
        public var count: Int
        public var totalCents: Int

        public var id: String { label }

        public init(label: String, lowerCents: Int, count: Int = 0, totalCents: Int = 0) {
            self.label = label
            self.lowerCents = lowerCents
            self.count = count
            self.totalCents = totalCents
        }
    }

    public static func amountBuckets(from entries: [EntrySnapshot]) -> [AmountBucket] {
        var buckets = [
            AmountBucket(label: "200 元以下", lowerCents: 0),
            AmountBucket(label: "200–499 元", lowerCents: 20_000),
            AmountBucket(label: "500–999 元", lowerCents: 50_000),
            AmountBucket(label: "1000–1999 元", lowerCents: 100_000),
            AmountBucket(label: "2000 元以上", lowerCents: 200_000),
        ]
        for e in entries where !e.isPendingSend {
            let idx = buckets.lastIndex { e.amountCents >= $0.lowerCents } ?? 0
            buckets[idx].count += 1
            buckets[idx].totalCents += e.amountCents
        }
        return buckets
    }

    /// 红白汇总行：红事＝事由非「白事」的全部场次（与 Ledger.isBai 同一判定），
    /// 白事＝事由为「白事」。occasions 按 ledgerID 去重（nil 不计场次、金额照计）。
    public struct KindAggregate: Sendable, Equatable, Identifiable {
        public var isBai: Bool
        public var received: Int
        public var given: Int
        public var count: Int
        public var occasions: Int

        public var id: Bool { isBai }
        public var net: Int { received - given }
        public var name: String { isBai ? "白事" : "红事" }

        public init(isBai: Bool, received: Int = 0, given: Int = 0, count: Int = 0, occasions: Int = 0) {
            self.isBai = isBai
            self.received = received
            self.given = given
            self.count = count
            self.occasions = occasions
        }
    }

    /// 固定返回 [红事, 白事] 两行（无数据侧为全零行，展示层决定是否呈现）
    public static func kindSummary(from entries: [EntrySnapshot]) -> [KindAggregate] {
        var hong = KindAggregate(isBai: false)
        var bai = KindAggregate(isBai: true)
        var hongIDs: Set<UUID> = []
        var baiIDs: Set<UUID> = []
        for e in entries {
            let isBai = e.ledgerType == LiqianConstants.baiType
            if let id = e.ledgerID {
                if isBai { baiIDs.insert(id) } else { hongIDs.insert(id) }
            }
            if e.isPendingSend { continue }
            if e.direction == LiqianConstants.received {
                if isBai { bai.received += e.amountCents } else { hong.received += e.amountCents }
            } else {
                if isBai { bai.given += e.amountCents } else { hong.given += e.amountCents }
            }
            if isBai { bai.count += 1 } else { hong.count += 1 }
        }
        hong.occasions = hongIDs.count
        bai.occasions = baiIDs.count
        return [hong, bai]
    }

    /// 年度整表行；netDelta 为与「上一个有数据的年份」的净额差（首行为 nil）
    public struct YearAggregate: Sendable, Equatable, Identifiable {
        public var year: String
        public var received: Int
        public var given: Int
        public var count: Int
        public var occasions: Int
        public var netDelta: Int?

        public var id: String { year }
        public var net: Int { received - given }

        public init(
            year: String, received: Int = 0, given: Int = 0,
            count: Int = 0, occasions: Int = 0, netDelta: Int? = nil
        ) {
            self.year = year
            self.received = received
            self.given = given
            self.count = count
            self.occasions = occasions
            self.netDelta = netDelta
        }
    }

    /// 年度整表：按年倒序（近年在前），occasions 按 ledgerID 去重
    public static func yearlyAggregates(from entries: [EntrySnapshot]) -> [YearAggregate] {
        var map: [String: YearAggregate] = [:]
        var idsByYear: [String: Set<UUID>] = [:]
        for e in entries {
            let year = String(e.date.prefix(4))
            if map[year] == nil { map[year] = YearAggregate(year: year) }
            if let id = e.ledgerID { idsByYear[year, default: []].insert(id) }
            if e.isPendingSend { continue }
            if e.direction == LiqianConstants.received {
                map[year]?.received += e.amountCents
            } else {
                map[year]?.given += e.amountCents
            }
            map[year]?.count += 1
        }
        var rows = map.values.sorted { $0.year < $1.year } // 先升序算 delta
        for i in rows.indices {
            rows[i].occasions = idsByYear[rows[i].year]?.count ?? 0
            if i > 0 { rows[i].netDelta = rows[i].net - rows[i - 1].net }
        }
        return rows.sorted { $0.year > $1.year }
    }

    // MARK: - v5.11 年度报告「之最」（纯函数，口径同上：待送出不计金额/笔数）

    /// 年度之最的原料（年度报告叙事版）：三项全部从真实记录派生，
    /// 无数据的一项为 nil——展示层整项不出现，绝不编造。
    public struct AnnualHighlights: Sendable, Equatable {
        /// 最大一笔：金额最大的单笔（收/随同台比），并列取日期较晚者
        public struct Biggest: Sendable, Equatable {
            public var person: String
            /// 所属礼簿的事由（婚礼/满月…），快照无账本时为 ""
            public var ledgerType: String
            public var amountCents: Int
            public var direction: String
            public var date: String

            public init(person: String, ledgerType: String, amountCents: Int, direction: String, date: String) {
                self.person = person
                self.ledgerType = ledgerType
                self.amountCents = amountCents
                self.direction = direction
                self.date = date
            }
        }

        public var biggest: Biggest?
        /// 最忙的月份（笔数最多，并列取较早月份）；只有一个月有数据时仍返回该月
        public var busiestMonth: Int?
        public var busiestMonthCount: Int
        /// 往来最多的人（收+随总额最大，并列取最近往来者）；差额随 PersonSummary 带出
        public var topPerson: PersonSummary?

        public init(
            biggest: Biggest? = nil, busiestMonth: Int? = nil,
            busiestMonthCount: Int = 0, topPerson: PersonSummary? = nil
        ) {
            self.biggest = biggest
            self.busiestMonth = busiestMonth
            self.busiestMonthCount = busiestMonthCount
            self.topPerson = topPerson
        }
    }

    /// 入参应为单年快照（展示层按年份前缀过滤后传入）；本函数内再滤待送出。
    public static func annualHighlights(from entries: [EntrySnapshot]) -> AnnualHighlights {
        let counted = entries.filter { !$0.isPendingSend }
        guard !counted.isEmpty else { return AnnualHighlights() }

        let big = counted.max { a, b in
            if a.amountCents != b.amountCents { return a.amountCents < b.amountCents }
            return a.date < b.date
        }

        var monthCounts: [String: Int] = [:]
        for e in counted {
            monthCounts[String(e.date.prefix(7)), default: 0] += 1
        }
        // 并列取较早月份：max 的「更小」判定里同 count 时 key 较大者排后
        let busiest = monthCounts.max { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key > b.key
        }

        let top = people(from: entries).max { a, b in
            let ta = a.received + a.given
            let tb = b.received + b.given
            if ta != tb { return ta < tb }
            return a.lastDate < b.lastDate
        }

        return AnnualHighlights(
            biggest: big.map {
                AnnualHighlights.Biggest(
                    person: $0.person, ledgerType: $0.ledgerType,
                    amountCents: $0.amountCents, direction: $0.direction, date: $0.date
                )
            },
            busiestMonth: busiest.flatMap { Int($0.key.suffix(2)) },
            busiestMonthCount: busiest?.value ?? 0,
            topPerson: top
        )
    }

    /// 年度总结句（规则版，不调 AI）：主导事由（按收+随总额）占比 ≥ 30%
    /// 时点名它是这一年的「主角」；否则落回规模句。占比只在这里出现一次，
    /// 按事由行只给占比条不给百分比数字，避免同数多遍（v5.8 审计 #8）。
    public static func annualClosingLine(
        dominantType: String?, dominantShare: Double, peopleCount: Int
    ) -> String {
        if let t = dominantType, !t.isEmpty, dominantShare >= 0.3 {
            let pct = Int((dominantShare * 100).rounded())
            return "这一年，\(t)是你人情往来的主角，占了全年往来的 \(pct)%。"
        }
        if peopleCount > 0 {
            return "这一年的人情，分散在 \(peopleCount) 位亲友之间——记下来，就是给往后留个念想。"
        }
        return ""
    }

    // 回礼参考区间已由 v4.3 的 ReplyAdvisor（ReplyAdvice.swift）替换：
    // 旧版只有「锚 ×1.2 取整」一条糙规则、给不出理由，新模型为
    // 锚（最近收礼，回退最大/中位）×年涨幅复利×场合系数，再按红事整百/
    // 白事单数取整，并输出理由条目。旧函数与 ReturnGiftSuggestion 一并删除，
    // 调用方（人物详情卡、记一笔提示）已全部切换到 ReplyAdvisor.advice。
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
            ledgerType: ledgerType,
            ledgerID: ledgerID
        )
    }
}
