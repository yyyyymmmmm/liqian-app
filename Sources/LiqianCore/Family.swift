import Foundation
import SwiftData

// MARK: - 家族协作与传承（v4.5 第一期）
//
// 「礼簿班子」：一本礼簿的经手人名单——主家、书记（记账人）、核实人、只读。
// 班子是协作与传承的组织基础：共享邀请按角色映射权限；交接时班子随礼簿走。
//
// 与礼簿既有字段（hostName / scribe / verifier）的关系（双向同步，口径见
// docs/V45-FAMILY-NOTES.md）：
// - 书记 / 核实：班子是唯一真源。班子变更后，字段由班子推导覆盖
//   （MemberSync.fields）；班子中没有该角色 → 字段清空。
// - 主家：字段是「这本簿的主家」，还兼全局落款回退与建簿预填语义；
//   班子里有主家成员时字段跟随班子，没有时字段保持不变（不清空）。
// - 反向：班子为空而字段已设值时（老数据/只用过表单的用户），按字段
//   生成种子成员（MemberSync.seed），让班子页第一次打开就反映现状。

/// 班子角色（存储用中文串，与全 App 的词表口径一致）
public enum MemberRole: String, CaseIterable, Sendable {
    case host = "主家"
    case scribe = "书记"
    case verifier = "核实"
    case viewer = "只读"

    /// 展示与排序口径：主家 → 书记 → 核实 → 只读
    public var sortOrder: Int {
        switch self {
        case .host: return 0
        case .scribe: return 1
        case .verifier: return 2
        case .viewer: return 3
        }
    }

    /// 是否可编辑礼簿内容（只读成员不可）
    public var canEdit: Bool { self != .viewer }

    /// CloudKit 共享参与者权限映射（owner 不经参与者表达，单独标出）：
    /// 主家＝所有者；书记/核实＝可读写；只读＝只读。
    public var sharePermission: SharePermission {
        switch self {
        case .host: return .owner
        case .scribe, .verifier: return .readWrite
        case .viewer: return .readOnly
        }
    }
}

/// 共享权限（与 CloudKit CKShare.ParticipantPermission 对应的自有枚举，
/// App 层桥接时再翻译，避免 Core 依赖 CloudKit）
public enum SharePermission: String, Sendable, Equatable {
    case owner
    case readWrite
    case readOnly
}

/// 班子成员（独立模型，靠 ledgerID 挂礼簿，与 GiftRecord 同口径，不用关系宏，
/// 保证备份/回收站的快照式处理方式一致）
@Model
public final class LedgerMember {
    @Attribute(.unique) public var id: UUID
    public var ledgerID: UUID
    public var name: String
    /// MemberRole 的 rawValue（主家/书记/核实/只读）；词表外值按只读兜底
    public var role: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        ledgerID: UUID,
        name: String,
        role: String = MemberRole.viewer.rawValue,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.name = name
        self.role = role
        self.createdAt = createdAt
    }

    public var roleValue: MemberRole {
        MemberRole(rawValue: role) ?? .viewer
    }

    /// 纯值快照（同步计算与单测走它，不直接碰模型）
    public var value: LedgerMemberValue {
        LedgerMemberValue(
            id: id, ledgerID: ledgerID, name: name,
            role: roleValue, createdAt: createdAt
        )
    }
}

/// 班子成员纯值形态
public struct LedgerMemberValue: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var ledgerID: UUID
    public var name: String
    public var role: MemberRole
    public var createdAt: Date

    public init(
        id: UUID = UUID(), ledgerID: UUID, name: String,
        role: MemberRole, createdAt: Date = Date()
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.name = name
        self.role = role
        self.createdAt = createdAt
    }
}

// MARK: - 班子 ↔ 礼簿字段同步（纯函数，口径见文件头）

public enum MemberSync {
    /// 字段三元组（与 Ledger.hostName / scribe / verifier 对应）
    public struct FieldValues: Equatable, Sendable {
        public var hostName: String?
        public var scribe: String?
        public var verifier: String?

        public init(hostName: String? = nil, scribe: String? = nil, verifier: String? = nil) {
            self.hostName = hostName
            self.scribe = scribe
            self.verifier = verifier
        }
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return nil
        }
        return t
    }

    /// 某角色的代表成员：同角色多人时取最早加入的一位（createdAt 升序，
    /// 并列时按姓名定序，保证结果确定）
    public static func representative(
        of role: MemberRole, in members: [LedgerMemberValue]
    ) -> LedgerMemberValue? {
        members
            .filter { $0.role == role && trimmed($0.name) != nil }
            .sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
            .first
    }

    /// 班子 → 字段。current 是礼簿现有字段值：
    /// - scribe / verifier：完全由班子推导（无此角色成员 → nil）；
    /// - hostName：班子有主家成员 → 跟随班子；没有 → 保持 current 不变。
    public static func fields(
        from members: [LedgerMemberValue],
        current: FieldValues
    ) -> FieldValues {
        FieldValues(
            hostName: representative(of: .host, in: members).map { trimmed($0.name)! }
                ?? current.hostName,
            scribe: representative(of: .scribe, in: members).flatMap { trimmed($0.name) },
            verifier: representative(of: .verifier, in: members).flatMap { trimmed($0.name) }
        )
    }

    /// 字段 → 班子种子：班子为空时，按现有字段生成成员（顺序：主家、书记、核实；
    /// 同名同人多角色时按多个成员生成，与「一人多职」的实情一致）。
    /// createdAt 由调用方按序递增赋值以保证代表推导稳定，这里只产出 (name, role)。
    public static func seed(from fields: FieldValues) -> [(name: String, role: MemberRole)] {
        var out: [(name: String, role: MemberRole)] = []
        if let h = trimmed(fields.hostName) { out.append((h, .host)) }
        if let s = trimmed(fields.scribe) { out.append((s, .scribe)) }
        if let v = trimmed(fields.verifier) { out.append((v, .verifier)) }
        return out
    }

    /// 班子列表展示排序：角色序 → 加入序 → 姓名
    public static func sorted(_ members: [LedgerMemberValue]) -> [LedgerMemberValue] {
        members.sorted {
            ($0.role.sortOrder, $0.createdAt, $0.name) < ($1.role.sortOrder, $1.createdAt, $1.name)
        }
    }
}
