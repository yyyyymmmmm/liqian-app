import Foundation

// MARK: - 礼谱内页分段（v3.1：按关系分段登记，纯计算可单测）

/// 礼谱内页的一段：同一关系的一批记录，段内顺序即入参顺序。
public struct LibuRelationSection<Element> {
    public let relation: String
    public let records: [Element]

    public init(relation: String, records: [Element]) {
        self.relation = relation
        self.records = records
    }
}

public enum LibuSections {
    /// 按关系分段（保序）：段序按 LiqianConstants.relations 枚举序
    /// （亲戚/朋友/同事/同学/邻居/其他）；枚举外的关系附后、按字面升序
    /// （与汇总页「按關係小計」同口径）；关系为空串者归入「其他」。
    /// 段内保持入参相对顺序——调用方先按现行成册口径
    /// （日期升序、同日姓名）排好再喂进来，本函数不重排段内。
    public static func groupByRelation<Element>(
        _ records: [Element],
        relation: (Element) -> String
    ) -> [LibuRelationSection<Element>] {
        var grouped: [String: [Element]] = [:]
        var seen: [String] = []
        for record in records {
            let raw = relation(record).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = raw.isEmpty ? "其他" : raw
            if grouped[key] == nil { seen.append(key) }
            grouped[key, default: []].append(record)
        }
        let known = LiqianConstants.relations.filter { grouped[$0] != nil }
        let unknown = seen.filter { !LiqianConstants.relations.contains($0) }.sorted()
        return (known + unknown).map {
            LibuRelationSection(relation: $0, records: grouped[$0] ?? [])
        }
    }
}
