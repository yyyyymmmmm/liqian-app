import Foundation
import SwiftData

// MARK: - 扫码随礼（v5.12）：宾客回执云端同步的本地模型与纯逻辑
//
// 形态（用户 2026-11-09 拍板转正）：每本礼簿生成绑定自身的宾客码，
// 主家分享出去，宾客扫码自填（姓名/祝福/金额选填），回执自动同步
// 回 App 先落「待确认」区，主家点确认才入账——防假数据直写账本。
// 云端契约见 liqian-guest/API.md（Base https://sui.inkroot.cn）：
// 无账号体系，安全全靠三把随机令牌——publicToken 进二维码、
// hostSecret 是主家拉数凭证（只存 Keychain、本文件不落）、
// ISSUE_KEY 是 App 配发键（CI 注入、只存服务端 Secret 与生成文件）。
//
// CloudKit 兼容口径与全仓模型一致：无 @Attribute(.unique)，
// 每个存储属性可选或带声明默认值，模型间靠 UUID/字符串外键关联。

/// 宾客回执处理状态：待确认 / 已处理（入账或已阅）/ 已忽略
public enum GuestReceiptStatus: String, Equatable {
    case pending
    case accepted
    case dismissed
}

/// 礼簿与云端场次的绑定（一本礼簿至多一个当前场次；重新生成＝换绑新场次，
/// 旧场次的回执按 ledgerID 留在本机，不随绑定删除）。
/// hostSecret 不在此模型——只存 Keychain（见 App 层 GuestKeychain）。
@Model
public final class GuestEventBinding {
    public var id: UUID = UUID()
    public var ledgerID: UUID = UUID()
    /// 服务端场次主键（ev_ 开头）
    public var eventID: String = ""
    /// 进二维码的公开令牌
    public var publicToken: String = ""
    /// 二维码内容（完整宾客页地址）
    public var guestURL: String = ""
    /// 建场次时的场次名/日期/类型快照（宾客页同款显示，本地展示用）
    public var eventTitle: String = ""
    public var eventDate: String = ""
    /// red / white（契约口径）
    public var eventType: String = "red"
    /// 收集是否已关闭（本地缓存，同步时以服务端 closed 为准回写）
    public var closed: Bool = false
    /// 增量同步游标：上次拉到的最后一条 createdAt 原文（ISO 8601 带毫秒与时区），
    /// nil＝从未同步（首次全量）。原样回传即增量，禁止本地重格式化。
    public var lastSince: String?
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        ledgerID: UUID,
        eventID: String,
        publicToken: String,
        guestURL: String,
        eventTitle: String,
        eventDate: String,
        eventType: String,
        closed: Bool = false,
        lastSince: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.eventID = eventID
        self.publicToken = publicToken
        self.guestURL = guestURL
        self.eventTitle = eventTitle
        self.eventDate = eventDate
        self.eventType = eventType
        self.closed = closed
        self.lastSince = lastSince
        self.createdAt = createdAt
    }
}

/// 宾客回执：一条云端提交在本机的镜像。serverID 是场次内自增 id，
/// 与 eventID 组成去重键；状态机 pending → accepted（入账/已阅）/ dismissed。
@Model
public final class GuestReceipt {
    public var id: UUID = UUID()
    public var ledgerID: UUID = UUID()
    public var eventID: String = ""
    /// 服务端场次内自增 id（单调递增、唯一）
    public var serverID: Int = 0
    public var name: String = ""
    /// 金额（分）；未填/白事为 nil
    public var amountCents: Int?
    public var blessing: String = ""
    /// 服务端 createdAt 原文（ISO 8601 北京时间），展示时解析、排序按 serverID
    public var createdAtRaw: String = ""
    public var statusRaw: String = GuestReceiptStatus.pending.rawValue
    /// 入账后关联的 GiftRecord id；已阅（无金额确认）为空
    public var linkedRecordID: UUID?
    /// 处理时间（入账/已阅/忽略时回写）
    public var handledAt: Date?

    public init(
        id: UUID = UUID(),
        ledgerID: UUID,
        eventID: String,
        serverID: Int,
        name: String,
        amountCents: Int?,
        blessing: String,
        createdAtRaw: String,
        statusRaw: String = GuestReceiptStatus.pending.rawValue,
        linkedRecordID: UUID? = nil,
        handledAt: Date? = nil
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.eventID = eventID
        self.serverID = serverID
        self.name = name
        self.amountCents = amountCents
        self.blessing = blessing
        self.createdAtRaw = createdAtRaw
        self.statusRaw = statusRaw
        self.linkedRecordID = linkedRecordID
        self.handledAt = handledAt
    }

    public var status: GuestReceiptStatus {
        get { GuestReceiptStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// 能否走「入账」：待确认且带金额（无金额只有已阅/忽略）
    public var canBook: Bool {
        status == .pending && amountCents != nil
    }

    public var createdAtDate: Date? {
        GuestTime.parse(createdAtRaw)
    }
}

// MARK: - 契约 DTO

/// 建场次响应（POST /api/events 201）
public struct GuestEventCreatedDTO: Codable, Equatable {
    public var ok: Bool
    public var eventId: String
    public var publicToken: String
    public var hostSecret: String
    public var guestUrl: String

    public init(ok: Bool, eventId: String, publicToken: String, hostSecret: String, guestUrl: String) {
        self.ok = ok
        self.eventId = eventId
        self.publicToken = publicToken
        self.hostSecret = hostSecret
        self.guestUrl = guestUrl
    }
}

/// 一条宾客提交（GET submissions 的元素）
public struct GuestSubmissionDTO: Codable, Equatable {
    public var id: Int
    public var name: String
    public var amountCents: Int?
    public var blessing: String
    public var source: String?
    public var createdAt: String

    public init(id: Int, name: String, amountCents: Int?, blessing: String, source: String? = "guest", createdAt: String) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.blessing = blessing
        self.source = source
        self.createdAt = createdAt
    }
}

/// 拉取响应（GET /api/events/<id>/submissions）
public struct GuestSubmissionsResponseDTO: Codable, Equatable {
    public var ok: Bool
    public var eventId: String
    public var closed: Bool
    public var submissions: [GuestSubmissionDTO]

    public init(ok: Bool, eventId: String, closed: Bool, submissions: [GuestSubmissionDTO]) {
        self.ok = ok
        self.eventId = eventId
        self.closed = closed
        self.submissions = submissions
    }
}

// MARK: - 时间解析（契约时间形如 2026-11-09T07:48:50.070+08:00）

public enum GuestTime {
    /// 带毫秒优先、无毫秒兜底；解析不了返回 nil（原文仍在 createdAtRaw，不丢数据）。
    /// formatter 每次现构造：ISO8601DateFormatter 非 Sendable，Swift 6 下
    /// 不许做静态共享属性；本函数只在展示/同步落库时低频调用，现构造成本可忽略。
    public static func parse(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

// MARK: - 同步规划（去重＋游标，纯函数单测钉死）

public enum GuestSyncPlanner {
    public struct Plan: Equatable {
        /// 真正要新落库的提交（已排除本地已有与批次内重复）
        public var newSubmissions: [GuestSubmissionDTO]
        /// 推进后的游标；批次为空时保持原游标
        public var newCursor: String?

        public init(newSubmissions: [GuestSubmissionDTO], newCursor: String?) {
            self.newSubmissions = newSubmissions
            self.newCursor = newCursor
        }
    }

    /// 增量合并：服务端按 id 升序返回、createdAt 严格晚于游标。
    /// 游标口径＝批次最后一条的 createdAt 原文——哪怕整批都是本地已有的
    /// 重复（崩溃后重拉等），游标也照常推进，避免反复全量重拉；
    /// 批次为空则游标不动。本函数不重排批次（信任契约升序）。
    public static func plan(
        existingServerIDs: Set<Int>,
        incoming: [GuestSubmissionDTO],
        currentCursor: String?
    ) -> Plan {
        guard let last = incoming.last else {
            return Plan(newSubmissions: [], newCursor: currentCursor)
        }
        var seen = existingServerIDs
        var fresh: [GuestSubmissionDTO] = []
        for sub in incoming where !seen.contains(sub.id) {
            seen.insert(sub.id)
            fresh.append(sub)
        }
        return Plan(newSubmissions: fresh, newCursor: last.createdAt)
    }

    /// since 进 query 的编码：契约明示 + 必须编成 %2B（否则被解析成空格）。
    /// 只放行字母数字与 -._~，其余一律百分号编码（含 : 与 +）。
    public static func encodeSince(_ raw: String) -> String {
        var allowed = CharacterSet()
        allowed.formUnion(.alphanumerics)
        allowed.insert(charactersIn: "-._~")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}

// MARK: - 映射口径（场次类型 / 入账预填）

public enum GuestReceiptMapping {
    /// 礼簿红白 → 契约场次类型：白事簿 white（宾客页不显示金额），其余 red
    public static func apiEventType(isBai: Bool) -> String {
        isBai ? "white" : "red"
    }

    /// 入账备注：来源＋祝福原文（宾客原文照原样，严禁改写/繁简转换，与全谱口径一致）
    public static func recordNote(blessing: String) -> String {
        let trimmed = blessing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "宾客扫码随礼" : "宾客扫码随礼：\(trimmed)"
    }
}
