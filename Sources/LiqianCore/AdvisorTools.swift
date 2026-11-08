import Foundation

// MARK: - 对话管家 v5.2：工具调用（function calling）层
//
// v4.4 的架构是「模型只解析意图（5 类枚举）→ 本地引擎算数」：数字零幻觉，
// 但问题空间被意图枚举锁死——具体到人/时段/场合的组合、两时段对比、
// 趋势、下一场安排都表达不出来（见 docs/V52-NOTES.md 盘点）。
//
// v5.2 升级为工具调用：模型自己决定查什么，本地工具层对账目快照执行
// 查询、只把查到的结果回给模型组织语言。纪律不变且更硬：
// - 金额只出自本文件的本地计算（口径全走 LedgerMath，待回 = max(balance,0)）；
// - 工具没查到的，系统提示词要求模型明说「账里查不到」，禁止凭印象编数；
// - 每次回答只把「本次问题用到的查询结果」发给模型，不带全量账目
//   （隐私收益：对比旧解析模式无增量泄露，对比「塞全量上下文」大幅减少）。

/// 工具执行上下文：账目快照＋礼簿元信息（标题/事由/日期，EntrySnapshot
/// 只有 ledgerID，下一场与按簿筛选要靠它）＋今天（yyyy-MM-dd，注入以便单测）。
public struct AdvisorToolContext: Sendable {
    public struct LedgerInfo: Sendable, Equatable {
        public var id: UUID?
        public var title: String
        public var type: String
        /// yyyy-MM-dd
        public var date: String

        public init(id: UUID? = nil, title: String, type: String, date: String) {
            self.id = id
            self.title = title
            self.type = type
            self.date = date
        }
    }

    public var entries: [EntrySnapshot]
    public var ledgers: [LedgerInfo]
    /// yyyy-MM-dd
    public var today: String

    public init(entries: [EntrySnapshot], ledgers: [LedgerInfo] = [], today: String) {
        self.entries = entries
        self.ledgers = ledgers
        self.today = today
    }
}

/// 一次工具调用：name + 原始参数 JSON（模型给的字符串，解码在本层宽容处理）
public struct AdvisorToolCall: Sendable, Equatable {
    public var name: String
    public var argumentsJSON: String

    public init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public enum AdvisorTools {
    /// 工具名常量（与 definitionsJSON、系统提示词三处必须同步）
    public static let queryPerson = "query_person"
    public static let queryRecords = "query_records"
    public static let aggregate = "aggregate"
    public static let pendingList = "pending_list"
    public static let upcomingEvents = "upcoming_events"

    public static let allNames = [queryPerson, queryRecords, aggregate, pendingList, upcomingEvents]

    /// 给 DeepSeek 的 tools 参数（官方 function calling 格式）：
    /// [{"type":"function","function":{"name":…,"description":…,"parameters":{JSON Schema}}}]
    /// 金额单位在描述里写死为「元」，参数里只有筛选条件、没有任何金额入参。
    public static func definitionsJSON() -> String {
        let tools: [[String: Any]] = [
            tool(
                name: queryPerson,
                description: "查某一个人的往来汇总：收礼总额、随礼总额、差额、待回金额、笔数、最近往来日期、关系，并附最近 5 笔往来。问某人欠谁、和某人往来、某人随了/收了多少时用。金额单位为元。",
                properties: [
                    "name": strProp("要查的人名，照用户问题原文，如「大舅」"),
                ],
                required: ["name"]
            ),
            tool(
                name: queryRecords,
                description: "按条件筛逐笔记录：可组合人名、场合（事由）、礼簿标题、日期范围、方向（收礼/随礼）。返回符合条件的总笔数与最近的若干笔（日期、姓名、方向、金额、场合）。问「某段时间都有谁随了礼」「某场婚礼的名单」这类逐笔问题时用。金额单位为元。",
                properties: [
                    "person": strProp("人名筛选，可空"),
                    "ledgerType": strProp("场合/事由筛选，只能是 婚礼/满月/周岁/乔迁/寿宴/升学/开业/白事/其他，可空"),
                    "ledgerTitle": strProp("礼簿标题关键词筛选，可空"),
                    "dateFrom": strProp("起始日期 yyyy-MM-dd（含），如今年三月应换算成 2026-03-01，可空"),
                    "dateTo": strProp("结束日期 yyyy-MM-dd（含），可空"),
                    "direction": [
                        "type": "string",
                        "enum": ["received", "given"],
                        "description": "方向：received=收礼，given=随礼；不限就不要传",
                    ] as [String: Any],
                    "limit": intProp("最多返回几笔，默认 20，上限 50"),
                ],
                required: []
            ),
            tool(
                name: aggregate,
                description: "分组汇总与时段对比：按 month（月）/year（年）/type（场合）/relation（关系）/ledger（礼簿）分组给出每组的收礼、随礼、净额、笔数；也可不分组只给某时段总计。若用户要对比两个时段（如今年 vs 去年），传 compareFrom/compareTo 给第二个时段，结果会附两段总计与差值。问趋势、对比、某类场合统计时用。金额单位为元。",
                properties: [
                    "groupBy": [
                        "type": "string",
                        "enum": ["month", "year", "type", "relation", "ledger", "none"],
                        "description": "分组维度，默认 none（只给总计）",
                    ] as [String: Any],
                    "dateFrom": strProp("主时段起始日期 yyyy-MM-dd（含），可空=不限"),
                    "dateTo": strProp("主时段结束日期 yyyy-MM-dd（含），可空=不限"),
                    "compareFrom": strProp("对比时段起始日期 yyyy-MM-dd（含），不对比就不要传"),
                    "compareTo": strProp("对比时段结束日期 yyyy-MM-dd（含），不对比就不要传"),
                ],
                required: []
            ),
            tool(
                name: pendingList,
                description: "待回礼名单：谁收了我的礼还没回、每人待回多少。按待回金额从大到小返回，附总人数与待回总额。问谁还没回礼、待回最多的是谁时用。金额单位为元。",
                properties: [
                    "limit": intProp("最多返回几人，默认 10，上限 30"),
                ],
                required: []
            ),
            tool(
                name: upcomingEvents,
                description: "近期安排：从今天起最近的礼簿场次（标题、事由、日期、还有几天）与待送出的备礼清单（给谁、多少、计划日期）。问下一场是什么、近期有什么安排、备礼备了哪些时用。金额单位为元。",
                properties: [
                    "limit": intProp("最多返回几场/几笔备礼，默认 5，上限 10"),
                ],
                required: []
            ),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: tools),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private static func tool(
        name: String, description: String,
        properties: [String: Any], required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    private static func strProp(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func intProp(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }
}

// MARK: - 参数宽容解码（模型给的参数 JSON 格式飘忽，单字段坏了按缺失落）

struct AdvisorToolArgs {
    private var raw: [String: Any] = [:]

    init(json: String) {
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            raw = obj
        }
    }

    func string(_ key: String) -> String? {
        if let s = raw[key] as? String {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        if let n = raw[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = raw[key] as? NSNumber { return n.intValue }
        if let s = raw[key] as? String { return Int(s) }
        return nil
    }

    /// 方向参数：只认 received/given（也兼容中文「收礼/随礼」），其余按不限
    func direction(_ key: String) -> String? {
        switch string(key) {
        case "received", LiqianConstants.received: return LiqianConstants.received
        case "given", LiqianConstants.given: return LiqianConstants.given
        default: return nil
        }
    }

    /// 日期参数：必须是 yyyy-MM-dd 形状才认（字符串比较即日期序）
    func date(_ key: String) -> String? {
        guard let s = string(key), s.count == 10 else { return nil }
        let parts = s.split(separator: "-")
        guard parts.count == 3, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return s
    }
}

// MARK: - 执行层（本地计算，结果以 JSON 文本回给模型）

public enum AdvisorToolEngine {
    /// 执行一次工具调用，返回给模型的 JSON 文本。
    /// 失败（未知工具、参数缺失、查无此人）也返回 JSON：{"ok":false,"error":"…"}
    /// ——错误信息写成模型能读懂的人话，让它换问法或如实告知用户，不抛异常中断对话。
    public static func execute(_ call: AdvisorToolCall, context: AdvisorToolContext) -> String {
        let args = AdvisorToolArgs(json: call.argumentsJSON)
        switch call.name {
        case AdvisorTools.queryPerson:
            return queryPerson(args: args, context: context)
        case AdvisorTools.queryRecords:
            return queryRecords(args: args, context: context)
        case AdvisorTools.aggregate:
            return aggregate(args: args, context: context)
        case AdvisorTools.pendingList:
            return pendingList(args: args, context: context)
        case AdvisorTools.upcomingEvents:
            return upcomingEvents(args: args, context: context)
        default:
            return errorJSON("没有叫「\(call.name)」的查账工具")
        }
    }

    // MARK: query_person

    private static func queryPerson(args: AdvisorToolArgs, context: AdvisorToolContext) -> String {
        guard let name = args.string("name") else {
            return errorJSON("query_person 需要人名参数")
        }
        let people = LedgerMath.people(from: context.entries)
        guard let hit = matchPerson(name: name, in: people) else {
            return json(["ok": false, "found": false, "error": "账上没有叫「\(name)」的人"])
        }
        let recent = context.entries
            .filter { $0.person == hit.name && !$0.isPendingSend }
            .sorted { $0.date > $1.date }
            .prefix(5)
            .map { entryDict($0) }
        return json([
            "ok": true,
            "found": true,
            "name": hit.name,
            "relation": hit.relation,
            "receivedYuan": yuan(hit.received),
            "givenYuan": yuan(hit.given),
            "balanceYuan": yuan(hit.balance),
            "balanceMeaning": hit.balance > 0 ? "对方多给，待回" : (hit.balance < 0 ? "我多随" : "已结清"),
            "pendingYuan": yuan(hit.pendingCents),
            "recordCount": hit.count,
            "lastDate": hit.lastDate,
            "recentRecords": Array(recent),
        ])
    }

    // MARK: query_records

    private static func queryRecords(args: AdvisorToolArgs, context: AdvisorToolContext) -> String {
        let person = args.string("person")
        let ledgerType = args.string("ledgerType").flatMap {
            LiqianConstants.ledgerTypes.contains($0) ? $0 : nil
        }
        let ledgerTitle = args.string("ledgerTitle")
        let dateFrom = args.date("dateFrom")
        let dateTo = args.date("dateTo")
        let direction = args.direction("direction")
        let limit = min(max(args.int("limit") ?? 20, 1), 50)

        let titleByID: [UUID: String] = Dictionary(
            context.ledgers.compactMap { info in info.id.map { ($0, info.title) } },
            uniquingKeysWith: { first, _ in first }
        )

        let matched = context.entries.filter { e in
            if let person, !(e.person == person || e.person.contains(person) || person.contains(e.person)) {
                return false
            }
            if let ledgerType, e.ledgerType != ledgerType { return false }
            if let ledgerTitle {
                let title = e.ledgerID.flatMap { titleByID[$0] } ?? ""
                if !title.contains(ledgerTitle) { return false }
            }
            if let dateFrom, e.date < dateFrom { return false }
            if let dateTo, e.date > dateTo { return false }
            if let direction, e.direction != direction { return false }
            return true
        }
        let sorted = matched.sorted { $0.date > $1.date }
        let rows = sorted.prefix(limit).map { e -> [String: Any] in
            var d = entryDict(e)
            d["ledgerTitle"] = e.ledgerID.flatMap { titleByID[$0] } ?? ""
            if e.isPendingSend { d["status"] = "待送出（备礼，还没送出，不计入汇总）" }
            return d
        }
        return json([
            "ok": true,
            "totalCount": matched.count,
            "returnedCount": rows.count,
            "records": Array(rows),
        ])
    }

    // MARK: aggregate

    private static func aggregate(args: AdvisorToolArgs, context: AdvisorToolContext) -> String {
        let groupBy = args.string("groupBy") ?? "none"
        let dateFrom = args.date("dateFrom")
        let dateTo = args.date("dateTo")

        let scoped = scope(context.entries, from: dateFrom, to: dateTo)
        var result: [String: Any] = [
            "ok": true,
            "range": rangeText(from: dateFrom, to: dateTo),
            "totals": totalsDict(scoped),
        ]

        if groupBy != "none" {
            result["groupBy"] = groupBy
            result["groups"] = groupRows(scoped, groupBy: groupBy, context: context)
        }

        if let compareFrom = args.date("compareFrom"), let compareTo = args.date("compareTo") {
            let other = scope(context.entries, from: compareFrom, to: compareTo)
            let a = totals(scoped)
            let b = totals(other)
            result["comparison"] = [
                "range": rangeText(from: compareFrom, to: compareTo),
                "totals": totalsDict(other),
                "deltaReceivedYuan": yuan(a.received - b.received),
                "deltaGivenYuan": yuan(a.given - b.given),
                "deltaNetYuan": yuan((a.received - a.given) - (b.received - b.given)),
            ]
        }
        return json(result)
    }

    /// 主时段过滤（待送出不计，与全 App 口径一致）
    private static func scope(_ entries: [EntrySnapshot], from: String?, to: String?) -> [EntrySnapshot] {
        entries.filter { e in
            if e.isPendingSend { return false }
            if let from, e.date < from { return false }
            if let to, e.date > to { return false }
            return true
        }
    }

    private static func totals(_ entries: [EntrySnapshot]) -> (received: Int, given: Int, count: Int) {
        var received = 0
        var given = 0
        for e in entries {
            if e.direction == LiqianConstants.received { received += e.amountCents } else { given += e.amountCents }
        }
        return (received, given, entries.count)
    }

    private static func totalsDict(_ entries: [EntrySnapshot]) -> [String: Any] {
        let t = totals(entries)
        return [
            "receivedYuan": yuan(t.received),
            "givenYuan": yuan(t.given),
            "netYuan": yuan(t.received - t.given),
            "recordCount": t.count,
        ]
    }

    private static func groupRows(
        _ entries: [EntrySnapshot], groupBy: String, context: AdvisorToolContext
    ) -> [[String: Any]] {
        func key(_ e: EntrySnapshot) -> String {
            switch groupBy {
            case "month": return String(e.date.prefix(7))
            case "year": return String(e.date.prefix(4))
            case "type": return e.ledgerType.isEmpty ? "未分类" : e.ledgerType
            case "relation": return e.relation
            case "ledger":
                if let id = e.ledgerID,
                   let info = context.ledgers.first(where: { $0.id == id }) {
                    return info.title
                }
                return e.ledgerType.isEmpty ? "未归簿" : e.ledgerType
            default: return ""
            }
        }
        var groups: [String: [EntrySnapshot]] = [:]
        for e in entries { groups[key(e), default: []].append(e) }
        let chronological = groupBy == "month" || groupBy == "year"
        return groups
            .map { (k, rows) in (key: k, totals: totals(rows)) }
            .sorted {
                chronological
                    ? $0.key < $1.key
                    : ($0.totals.received + $0.totals.given) > ($1.totals.received + $1.totals.given)
            }
            .map { row in
                [
                    "group": row.key,
                    "receivedYuan": yuan(row.totals.received),
                    "givenYuan": yuan(row.totals.given),
                    "netYuan": yuan(row.totals.received - row.totals.given),
                    "recordCount": row.totals.count,
                ] as [String: Any]
            }
    }

    // MARK: pending_list

    private static func pendingList(args: AdvisorToolArgs, context: AdvisorToolContext) -> String {
        let limit = min(max(args.int("limit") ?? 10, 1), 30)
        let list = LedgerMath.people(from: context.entries)
            .filter { $0.pendingCents > 0 }
            .sorted {
                if $0.pendingCents != $1.pendingCents { return $0.pendingCents > $1.pendingCents }
                return $0.lastDate > $1.lastDate
            }
        let rows = list.prefix(limit).map { p -> [String: Any] in
            [
                "name": p.name,
                "relation": p.relation,
                "pendingYuan": yuan(p.pendingCents),
                "receivedYuan": yuan(p.received),
                "givenYuan": yuan(p.given),
                "lastDate": p.lastDate,
            ]
        }
        return json([
            "ok": true,
            "totalPeople": list.count,
            "totalPendingYuan": yuan(list.reduce(0) { $0 + $1.pendingCents }),
            "returnedCount": rows.count,
            "people": Array(rows),
        ])
    }

    // MARK: upcoming_events

    private static func upcomingEvents(args: AdvisorToolArgs, context: AdvisorToolContext) -> String {
        let limit = min(max(args.int("limit") ?? 5, 1), 10)
        let upcoming = context.ledgers
            .filter { $0.date >= context.today }
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { info -> [String: Any] in
                [
                    "title": info.title,
                    "type": info.type,
                    "date": info.date,
                    "daysUntil": daysBetween(from: context.today, to: info.date) ?? -1,
                ]
            }
        let prep = context.entries
            .filter { $0.isPendingSend }
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { e -> [String: Any] in
                var d = entryDict(e)
                d["status"] = "待送出（备礼）"
                return d
            }
        return json([
            "ok": true,
            "today": context.today,
            "upcomingEvents": Array(upcoming),
            "prepPendingCount": context.entries.filter { $0.isPendingSend }.count,
            "prepList": Array(prep),
        ])
    }

    // MARK: - 共用小件

    /// 人名匹配：与 AdvisorEngine.matchSummary 同语义（精确 > 包含，多命中取最近往来者）
    private static func matchPerson(name: String, in people: [PersonSummary]) -> PersonSummary? {
        if let exact = people.first(where: { $0.name == name }) { return exact }
        let fuzzy = people.filter { $0.name.contains(name) || name.contains($0.name) }
        return fuzzy.max { $0.lastDate < $1.lastDate }
    }

    private static func entryDict(_ e: EntrySnapshot) -> [String: Any] {
        [
            "person": e.person,
            "relation": e.relation,
            "direction": e.direction == LiqianConstants.received ? "收礼" : "随礼",
            "amountYuan": yuan(e.amountCents),
            "date": e.date,
            "ledgerType": e.ledgerType,
        ]
    }

    /// 分 → 元数值（整数元给整数、小数给两位），模型读数与比较都直接
    private static func yuan(_ cents: Int) -> Double {
        (Double(cents) / 100 * 100).rounded() / 100
    }

    private static func rangeText(from: String?, to: String?) -> String {
        switch (from, to) {
        case (nil, nil): return "全部时段"
        case let (f?, nil): return "\(f) 起"
        case let (nil, t?): return "\(t) 之前"
        case let (f?, t?): return "\(f) 至 \(t)"
        }
    }

    /// 两日相差天数（yyyy-MM-dd 解析失败返回 nil）
    private static func daysBetween(from: String, to: String) -> Int? {
        let f = LiqianDate.formatter
        guard let a = f.date(from: from), let b = f.date(from: to) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day
    }

    private static func errorJSON(_ message: String) -> String {
        json(["ok": false, "error": message])
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"结果序列化失败\"}"
        }
        return text
    }
}
