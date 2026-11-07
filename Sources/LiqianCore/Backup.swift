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

/// 人情提醒·重要日子（v3.0 可选段）：旧备份无此键 → 解码为 nil（视为无提醒）；
/// 新备份带此段时旧版 App 按未知键忽略，不影响礼簿与记录的恢复。
public struct BackupReminderDay: Codable, Sendable, Equatable {
    public var id: String
    public var person: String
    public var relation: String
    public var kind: String
    public var calendarKind: String
    public var month: Int
    public var day: Int
    public var leadDays: Int
    public var enabled: Bool
    public var note: String

    public init(
        id: String,
        person: String,
        relation: String = "",
        kind: String = LiqianConstants.reminderBirthday,
        calendarKind: String = LiqianConstants.calendarGregorian,
        month: Int,
        day: Int,
        leadDays: Int = 3,
        enabled: Bool = true,
        note: String = ""
    ) {
        self.id = id
        self.person = person
        self.relation = relation
        self.kind = kind
        self.calendarKind = calendarKind
        self.month = month
        self.day = day
        self.leadDays = leadDays
        self.enabled = enabled
        self.note = note
    }

    public var idUUID: UUID? { UUID(uuidString: id) }
}

extension BackupReminderDay {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        person = try c.decode(String.self, forKey: .person)
        relation = try c.decodeIfPresent(String.self, forKey: .relation) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? LiqianConstants.reminderBirthday
        calendarKind = try c.decodeIfPresent(String.self, forKey: .calendarKind) ?? LiqianConstants.calendarGregorian
        month = try c.decode(Int.self, forKey: .month)
        day = try c.decode(Int.self, forKey: .day)
        leadDays = try c.decodeIfPresent(Int.self, forKey: .leadDays) ?? 3
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// 礼簿班子成员（v4.5 可选段）：旧备份无此键 → 解码为 nil（视为无班子）；
/// 新备份带此段时旧版 App 按未知键忽略。ledgerId 与 BackupRecord 同口径用 String 承载。
public struct BackupMember: Codable, Sendable, Equatable {
    public var id: String
    public var ledgerId: String
    public var name: String
    /// MemberRole 的 rawValue（主家/书记/核实/只读）
    public var role: String
    /// ISO8601 字符串（备份文件的日期统一走字符串，不引入 Date 解码策略差异）
    public var createdAt: String

    public init(
        id: String,
        ledgerId: String,
        name: String,
        role: String = MemberRole.viewer.rawValue,
        createdAt: String = ""
    ) {
        self.id = id
        self.ledgerId = ledgerId
        self.name = name
        self.role = role
        self.createdAt = createdAt
    }

    public var idUUID: UUID? { UUID(uuidString: id) }
    public var ledgerUUID: UUID? { UUID(uuidString: ledgerId) }
}

extension BackupMember {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ledgerId = try c.decode(String.self, forKey: .ledgerId)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? MemberRole.viewer.rawValue
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

/// 活礼谱·签名元数据（v4.2 可选段）：只记元数据——签名 PNG 本体不进
/// JSON 备份（保存在本机与 iCloud），故本段是「谁在何时签过」的存档清单，
/// 恢复时不据此重建签名行（没有图，重建出来也是空行）。旧备份无此键 →
/// 解码为 nil；新备份带此段时旧版 App 按未知键忽略。
public struct BackupSignature: Codable, Sendable, Equatable {
    public var id: String
    public var ledgerId: String
    public var recordId: String?
    public var person: String
    /// ISO8601（如 2026-11-16T05:30:00Z）
    public var createdAt: String

    public init(
        id: String,
        ledgerId: String,
        recordId: String? = nil,
        person: String,
        createdAt: String
    ) {
        self.id = id
        self.ledgerId = ledgerId
        self.recordId = recordId
        self.person = person
        self.createdAt = createdAt
    }

    public var idUUID: UUID? { UUID(uuidString: id) }
}

extension BackupSignature {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ledgerId = try c.decode(String.self, forKey: .ledgerId)
        recordId = try c.decodeIfPresent(String.self, forKey: .recordId)
        person = try c.decodeIfPresent(String.self, forKey: .person) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

/// 活礼谱·语音祝福元数据（v4.2 可选段）：音频本体不进 JSON 备份（保存在
/// 本机与 iCloud），但转写文字是元数据的一部分、随段保存——恢复后即使
/// 录音文件不在新设备上，这段祝福的话还读得到（播放器会如实提示录音
/// 文件不在本机）。旧备份无此键 → 解码为 nil。
public struct BackupVoiceBlessing: Codable, Sendable, Equatable {
    public var id: String
    public var recordId: String
    public var fileName: String
    public var duration: Double
    public var transcript: String?
    /// ISO8601
    public var createdAt: String

    public init(
        id: String,
        recordId: String,
        fileName: String,
        duration: Double,
        transcript: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.recordId = recordId
        self.fileName = fileName
        self.duration = duration
        self.transcript = transcript
        self.createdAt = createdAt
    }

    public var idUUID: UUID? { UUID(uuidString: id) }
    public var recordUUID: UUID? { UUID(uuidString: recordId) }
}

extension BackupVoiceBlessing {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        recordId = try c.decode(String.self, forKey: .recordId)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

public struct BackupFile: Codable, Sendable, Equatable {
    public var ledgers: [BackupLedger]
    public var records: [BackupRecord]
    /// v3.0 可选段：nil 表示备份里没有提醒数据（旧备份恒为 nil）
    public var reminders: [BackupReminderDay]?
    /// v4.5 可选段：nil 表示备份里没有班子数据（旧备份恒为 nil）
    public var members: [BackupMember]?
    /// v4.2 可选段：签名元数据（无图）；nil 表示备份里没有（旧备份恒为 nil）
    public var signatures: [BackupSignature]?
    /// v4.2 可选段：语音祝福元数据（无音频本体，含转写文字）
    public var voiceBlessings: [BackupVoiceBlessing]?

    public init(
        ledgers: [BackupLedger], records: [BackupRecord],
        reminders: [BackupReminderDay]? = nil,
        members: [BackupMember]? = nil,
        signatures: [BackupSignature]? = nil,
        voiceBlessings: [BackupVoiceBlessing]? = nil
    ) {
        self.ledgers = ledgers
        self.records = records
        self.reminders = reminders
        self.members = members
        self.signatures = signatures
        self.voiceBlessings = voiceBlessings
    }
}

public enum LiqianBackup {
    /// 班子成员 createdAt 的备份字符串格式（与存储日期同为 ISO 口径、便于人工检查）
    private static var memberDateFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    public static func memberDateString(from date: Date) -> String {
        memberDateFormatter.string(from: date)
    }

    /// 解析备份里的成员日期；空串/坏值兜底为当前时间（不让一本班子的恢复失败）
    public static func memberDate(from string: String) -> Date {
        memberDateFormatter.date(from: string) ?? Date()
    }

    /// SwiftData 模型 → 备份 JSON（键序固定，便于 diff 与人工检查）
    /// 活礼谱（v4.2）：signatures/blessings 只带元数据段（二进制不进 JSON）；
    /// 两组都为空时写 nil 而不是空数组，没用过活礼谱的备份与旧格式同构。
    public static func makeBackup(
        ledgers: [Ledger], records: [GiftRecord], reminders: [ReminderDay] = [],
        members: [LedgerMember] = [],
        signatures: [GuestSignature] = [], blessings: [VoiceBlessing] = []
    ) -> Data {
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
            },
            reminders: reminders.map {
                BackupReminderDay(
                    id: $0.id.uuidString,
                    person: $0.person,
                    relation: $0.relation,
                    kind: $0.kind,
                    calendarKind: $0.calendarKind,
                    month: $0.month,
                    day: $0.day,
                    leadDays: $0.leadDays,
                    enabled: $0.enabled,
                    note: $0.note
                )
            },
            members: members.map {
                BackupMember(
                    id: $0.id.uuidString,
                    ledgerId: $0.ledgerID.uuidString,
                    name: $0.name,
                    role: $0.role,
                    createdAt: memberDateString(from: $0.createdAt)
                )
            },
            signatures: signatures.isEmpty ? nil : signatures.map {
                BackupSignature(
                    id: $0.id.uuidString,
                    ledgerId: $0.ledgerID.uuidString,
                    recordId: $0.recordID?.uuidString,
                    person: $0.person,
                    createdAt: LiqianISO8601.string(from: $0.createdAt)
                )
            },
            voiceBlessings: blessings.isEmpty ? nil : blessings.map {
                BackupVoiceBlessing(
                    id: $0.id.uuidString,
                    recordId: $0.recordID.uuidString,
                    fileName: $0.fileName,
                    duration: $0.duration,
                    transcript: $0.transcript,
                    createdAt: LiqianISO8601.string(from: $0.createdAt)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(file)) ?? Data()
    }

    /// 解析备份；格式不对抛错，调用方提示用户且不动现有数据
    public static func parseBackup(_ data: Data) throws -> (ledgers: [BackupLedger], records: [BackupRecord]) {
        let parsed = try parseBackupFull(data)
        return (parsed.ledgers, parsed.records)
    }

    /// 解析备份（含 v3.0 提醒段、v4.5 班子段）：旧备份无对应键时返回空数组
    public static func parseBackupFull(
        _ data: Data
    ) throws -> (
        ledgers: [BackupLedger], records: [BackupRecord],
        reminders: [BackupReminderDay], members: [BackupMember]
    ) {
        let file = try JSONDecoder().decode(BackupFile.self, from: data)
        return (file.ledgers, file.records, file.reminders ?? [], file.members ?? [])
    }

    /// 解析备份里的活礼谱元数据段（v4.2）：旧备份无此二键时返回空数组；
    /// 整段解码失败也回退空数组（元数据是附带信息，不拖垮主数据校验，
    /// 主段的严格校验在 parseBackupFull 里）。
    public static func parseBackupLive(
        _ data: Data
    ) -> (signatures: [BackupSignature], blessings: [BackupVoiceBlessing]) {
        guard let file = try? JSONDecoder().decode(BackupFile.self, from: data) else {
            return ([], [])
        }
        return (file.signatures ?? [], file.voiceBlessings ?? [])
    }

    /// 导入确认前预览规模（同 Dart countJson）
    public static func counts(in data: Data) throws -> (ledgers: Int, records: Int) {
        let parsed = try parseBackup(data)
        return (parsed.ledgers.count, parsed.records.count)
    }
}
