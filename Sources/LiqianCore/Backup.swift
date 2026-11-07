import Foundation

// MARK: - JSON 全量备份（FR-08）
// 结构与 Flutter 版导出完全一致：{"ledgers":[...],"records":[...]}
// 字段名与 Dart toJson 一一对应；id 在 Dart 侧是字符串（原生为 UUID、
// Flutter 旧版为时间戳字符串），故备份层一律用 String 承载，导入时再映射。

public struct BackupLedger: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var type: String
    public var date: String
    public var note: String
    // v2.10 礼谱属性（可选键）：旧备份无此四键 → 解码为 nil；新备份带键时
    // 值为 null 或缺席都不影响旧版 App 解码（旧版按未知键忽略）。
    public var hostName: String?
    public var scribe: String?
    public var verifier: String?
    public var location: String?

    public init(
        id: String, title: String, type: String, date: String, note: String = "",
        hostName: String? = nil, scribe: String? = nil,
        verifier: String? = nil, location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.date = date
        self.note = note
        self.hostName = hostName
        self.scribe = scribe
        self.verifier = verifier
        self.location = location
    }

    /// 原生备份里 id 是 UUID 字符串；Flutter 旧备份是时间戳字符串，返回 nil
    public var idUUID: UUID? { UUID(uuidString: id) }
}

extension BackupLedger {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        type = try c.decode(String.self, forKey: .type)
        date = try c.decode(String.self, forKey: .date)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        hostName = try c.decodeIfPresent(String.self, forKey: .hostName)
        scribe = try c.decodeIfPresent(String.self, forKey: .scribe)
        verifier = try c.decodeIfPresent(String.self, forKey: .verifier)
        location = try c.decodeIfPresent(String.self, forKey: .location)
    }
}

public struct BackupRecord: Codable, Sendable, Equatable {
    public var id: String
    public var ledgerId: String
    public var person: String
    public var relation: String
    public var amountCents: Int
    public var direction: String
    public var method: String
    public var note: String
    public var date: String
    public var returned: Bool
    public var status: String

    public init(
        id: String,
        ledgerId: String,
        person: String,
        relation: String = "朋友",
        amountCents: Int,
        direction: String,
        method: String = "现金",
        note: String = "",
        date: String,
        returned: Bool = false,
        status: String = LiqianConstants.sentStatus
    ) {
        self.id = id
        self.ledgerId = ledgerId
        self.person = person
        self.relation = relation
        self.amountCents = amountCents
        self.direction = direction
        self.method = method
        self.note = note
        self.date = date
        self.returned = returned
        self.status = status
    }

    public var idUUID: UUID? { UUID(uuidString: id) }
    public var ledgerUUID: UUID? { UUID(uuidString: ledgerId) }
}

extension BackupRecord {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ledgerId = try c.decode(String.self, forKey: .ledgerId)
        person = try c.decode(String.self, forKey: .person)
        relation = try c.decodeIfPresent(String.self, forKey: .relation) ?? "朋友"
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        direction = try c.decode(String.self, forKey: .direction)
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? "现金"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        date = try c.decode(String.self, forKey: .date)
        returned = try c.decodeIfPresent(Bool.self, forKey: .returned) ?? false
        // 旧数据无此字段，兜底为已送出（同 Dart fromJson）
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? LiqianConstants.sentStatus
    }
}

public struct BackupFile: Codable, Sendable, Equatable {
    public var ledgers: [BackupLedger]
    public var records: [BackupRecord]

    public init(ledgers: [BackupLedger], records: [BackupRecord]) {
        self.ledgers = ledgers
        self.records = records
    }
}

public enum LiqianBackup {
    /// SwiftData 模型 → 备份 JSON（键序固定，便于 diff 与人工检查）
    public static func makeBackup(ledgers: [Ledger], records: [GiftRecord]) -> Data {
        let file = BackupFile(
            ledgers: ledgers.map {
                BackupLedger(
                    id: $0.id.uuidString, title: $0.title, type: $0.type,
                    date: $0.date, note: $0.note,
                    hostName: $0.hostName, scribe: $0.scribe,
                    verifier: $0.verifier, location: $0.location
                )
            },
            records: records.map {
                BackupRecord(
                    id: $0.id.uuidString,
                    ledgerId: $0.ledgerID.uuidString,
                    person: $0.person,
                    relation: $0.relation,
                    amountCents: $0.amountCents,
                    direction: $0.direction,
                    method: $0.method,
                    note: $0.note,
                    date: $0.date,
                    returned: $0.returned,
                    status: $0.status
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(file)) ?? Data()
    }

    /// 解析备份；格式不对抛错，调用方提示用户且不动现有数据
    public static func parseBackup(_ data: Data) throws -> (ledgers: [BackupLedger], records: [BackupRecord]) {
        let file = try JSONDecoder().decode(BackupFile.self, from: data)
        return (file.ledgers, file.records)
    }

    /// 导入确认前预览规模（同 Dart countJson）
    public static func counts(in data: Data) throws -> (ledgers: Int, records: Int) {
        let parsed = try parseBackup(data)
        return (parsed.ledgers.count, parsed.records.count)
    }
}
