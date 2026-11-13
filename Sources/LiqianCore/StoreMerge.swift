import Foundation

// MARK: - 搁浅数据救援·合并计划（v5.14.2 纯逻辑）
//
// 背景（四线会诊定因）：v5.14.1 及更早的启动决策每启重判存储模式，
// CloudKit 与本地两份配置都没显式指定 store URL、没有模式锁定，
// 用户数据可能写进了一个店面、后续启动读另一个店面而「消失」。
// 修复版锁定模式＋显式 URL 之后，还必须把可能搁浅在其他店面的
// 数据并回来——本文件只负责「比对与去重」的纯决策：给定主店与
// 源店的 ID 快照，算出源店里哪些实体该复制进主店。真打开店面、
// 真复制实体在 App 层 StoreRescue；本层无副作用、单测钉死。
//
// 并入规则（全部按 UUID 去重，主店已有的绝不重复并入）：
// - 礼簿：源店有、主店没有的整本并入；
// - 记录：ID 主店没有、且所属礼簿在主店已有或本次一并并入；
// - 成员/签名/场次绑定/宾客回执：同记录口径（靠 ledgerID 挂礼簿）；
// - 语音祝福：ID 主店没有、且所属记录在主店已有或本次一并并入；
// - 重要日子（ReminderDay）：不挂礼簿，ID 主店没有即并入。
// 孤儿（所属礼簿/记录在两边都不存在）不并入——并进来也是悬空数据。

/// 靠 ledgerID 挂礼簿的实体引用（记录与各子实体共用形态）
public struct StoreChildRef: Equatable, Hashable {
    public var id: UUID
    public var ledgerID: UUID

    public init(id: UUID, ledgerID: UUID) {
        self.id = id
        self.ledgerID = ledgerID
    }
}

/// 靠 recordID 挂记录的实体引用（语音祝福）
public struct StoreBlessingRef: Equatable, Hashable {
    public var id: UUID
    public var recordID: UUID

    public init(id: UUID, recordID: UUID) {
        self.id = id
        self.recordID = recordID
    }
}

/// 一个店面的 ID 快照（只含身份与外键，不含业务字段）
public struct StoreSnapshotIDs: Equatable {
    public var ledgerIDs: Set<UUID> = []
    public var records: [StoreChildRef] = []
    public var members: [StoreChildRef] = []
    public var signatures: [StoreChildRef] = []
    public var bindings: [StoreChildRef] = []
    public var receipts: [StoreChildRef] = []
    public var blessings: [StoreBlessingRef] = []
    public var reminderIDs: Set<UUID> = []

    public init(
        ledgerIDs: Set<UUID> = [],
        records: [StoreChildRef] = [],
        members: [StoreChildRef] = [],
        signatures: [StoreChildRef] = [],
        bindings: [StoreChildRef] = [],
        receipts: [StoreChildRef] = [],
        blessings: [StoreBlessingRef] = [],
        reminderIDs: Set<UUID> = []
    ) {
        self.ledgerIDs = ledgerIDs
        self.records = records
        self.members = members
        self.signatures = signatures
        self.bindings = bindings
        self.receipts = receipts
        self.blessings = blessings
        self.reminderIDs = reminderIDs
    }
}

/// 合并计划：源店中应复制进主店的实体 ID 集（按实体类型分列）
public struct StoreMergePlan: Equatable {
    public var ledgerIDs: Set<UUID> = []
    public var recordIDs: Set<UUID> = []
    public var memberIDs: Set<UUID> = []
    public var signatureIDs: Set<UUID> = []
    public var bindingIDs: Set<UUID> = []
    public var receiptIDs: Set<UUID> = []
    public var blessingIDs: Set<UUID> = []
    public var reminderIDs: Set<UUID> = []

    public var isEmpty: Bool {
        ledgerIDs.isEmpty && recordIDs.isEmpty && memberIDs.isEmpty
            && signatureIDs.isEmpty && bindingIDs.isEmpty && receiptIDs.isEmpty
            && blessingIDs.isEmpty && reminderIDs.isEmpty
    }

    public init() {}
}

public enum StoreMergePlanner {
    /// 算合并计划：源店相对主店多出、且挂靠关系成立的实体 ID。
    /// 幂等：把计划并入主店后，以并入后的主店快照再算，必得空计划。
    public static func plan(main: StoreSnapshotIDs, source: StoreSnapshotIDs) -> StoreMergePlan {
        var plan = StoreMergePlan()
        plan.ledgerIDs = source.ledgerIDs.subtracting(main.ledgerIDs)
        // 记录/子实体可挂靠的礼簿全集：主店已有 ∪ 本次并入
        let availableLedgers = main.ledgerIDs.union(plan.ledgerIDs)

        let mainRecordIDs = Set(main.records.map(\.id))
        plan.recordIDs = Set(
            source.records
                .filter { !mainRecordIDs.contains($0.id) && availableLedgers.contains($0.ledgerID) }
                .map(\.id)
        )
        // 祝福可挂靠的记录全集：主店已有 ∪ 本次并入
        let availableRecords = mainRecordIDs.union(plan.recordIDs)

        plan.memberIDs = childIDs(source: source.members, main: main.members, availableLedgers: availableLedgers)
        plan.signatureIDs = childIDs(source: source.signatures, main: main.signatures, availableLedgers: availableLedgers)
        plan.bindingIDs = childIDs(source: source.bindings, main: main.bindings, availableLedgers: availableLedgers)
        plan.receiptIDs = childIDs(source: source.receipts, main: main.receipts, availableLedgers: availableLedgers)

        let mainBlessingIDs = Set(main.blessings.map(\.id))
        plan.blessingIDs = Set(
            source.blessings
                .filter { !mainBlessingIDs.contains($0.id) && availableRecords.contains($0.recordID) }
                .map(\.id)
        )
        plan.reminderIDs = source.reminderIDs.subtracting(main.reminderIDs)
        return plan
    }

    /// 挂礼簿子实体的统一口径：ID 主店没有、且礼簿在可挂靠全集内
    private static func childIDs(
        source: [StoreChildRef], main: [StoreChildRef], availableLedgers: Set<UUID>
    ) -> Set<UUID> {
        let mainIDs = Set(main.map(\.id))
        return Set(
            source
                .filter { !mainIDs.contains($0.id) && availableLedgers.contains($0.ledgerID) }
                .map(\.id)
        )
    }
}
