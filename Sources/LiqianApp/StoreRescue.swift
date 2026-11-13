import Foundation
import SwiftData
import LiqianCore
import os

/// 搁浅数据救援（v5.14.2，本版最要紧的一件）：修复版首次启动时，
/// 在主店之外依次打开候选店面——带 CloudKit 选项的默认配置、
/// 无选项的默认配置（旧本地店面）、显式 URL 的本地店面——把主店
/// 没有的礼簿连同记录与关联实体按 ID 去重复制并入主店。
///
/// 纪律：
/// - 源店只读：只 fetch、从不 delete/save 源 context，源数据原样留着；
/// - 比对/去重的纯决策在 Core 的 StoreMergePlanner（单测钉死），
///   本文件只负责真开店、真取实体、真复制；
/// - 与主店同一物理文件的候选跳过（同店重开，读到的就是主店自己）；
/// - 全部候选扫完才统一 save 一次；save 失败返回 completed=false，
///   调用方不置救援完成标志，下次启动重试（按 ID 去重，重试安全）。
/// - CloudKit 候选只许经全仓唯一入口 CloudSyncManager
///   .makeCloudKitContainer 建（v5.14.3 收口，入口内含 entitlement
///   门禁），且调用方判定门关着（allowCloudKit=false）时直接跳过：
///   无 entitlement 强建 CloudKit 容器是不可捕获异常，do/catch
///   接不住——v5.14.2 本文件直建正是装机每启必崩的崩点。
/// - 触发时机自 v5.14.3 起在 ContentView 首帧之后（调用方
///   CloudSyncManager.runRescueIfNeeded 承接尝试计数防死循环），
///   不压启动关键路径。
enum StoreRescue {
    private static let logger = Logger(subsystem: "site.didichou.liqian", category: "store")

    struct Outcome {
        var ledgersMerged = 0
        var recordsMerged = 0
        var completed = false
    }

    @MainActor
    static func run(main: ModelContainer, schema: Schema, allowCloudKit: Bool) -> Outcome {
        var outcome = Outcome()
        let mainContext = ModelContext(main)
        guard var mainSnapshot = try? snapshot(of: mainContext) else {
            logger.error("rescue aborted: main store snapshot failed")
            return outcome
        }
        let mainURL = main.configurations.first?.url

        // 候选只记名字、逐个现开（CloudKit 候选必须经唯一入口拿
        // 容器，不能像本地候选这样先把配置摆出来——摆配置再直建
        // 正是 v5.14.2 的绕门写法）
        let candidateNames = ["cloudKitDefault", "localDefault", "localExplicit"]

        var insertedAny = false
        for name in candidateNames {
            // 显式 URL 候选文件不存在就不必开（开了只是造一个空文件）；
            // 主店正是它时更不用开。默认位置两候选无法预知路径，开后比对。
            if name == "localExplicit" {
                if mainURL == CloudSyncManager.localStoreURL { continue }
                if !FileManager.default.fileExists(atPath: CloudSyncManager.localStoreURL.path) { continue }
            }
            let container: ModelContainer
            if name == "cloudKitDefault" {
                // 门禁：调用方判定不过（无 entitlement 或锁定依据
                // 记着 CloudKit 走不通）→ 直接跳过，连入口都不进；
                // 进了入口也要再过探针，拒建/抛错同样跳过
                guard allowCloudKit,
                      let opened = CloudSyncManager.makeCloudKitContainer(schema: schema).container
                else {
                    logger.info("rescue candidate cloudKitDefault skipped: gateway closed")
                    continue
                }
                container = opened
            } else {
                let config = name == "localDefault"
                    ? ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                    : ModelConfiguration(
                        schema: schema, url: CloudSyncManager.localStoreURL,
                        cloudKitDatabase: .none)
                do {
                    container = try ModelContainer(for: schema, configurations: [config])
                } catch {
                    // 本地候选打不开：记一行日志跳过，不挡其余候选
                    logger.error(
                        "rescue candidate \(name, privacy: .public) open failed: \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }
            if let url = container.configurations.first?.url, let mainURL, url == mainURL {
                continue
            }
            let sourceContext = ModelContext(container)
            guard let sourceSnapshot = try? snapshot(of: sourceContext) else { continue }
            guard !sourceSnapshot.ledgerIDs.isEmpty || !sourceSnapshot.records.isEmpty else { continue }
            let plan = StoreMergePlanner.plan(main: mainSnapshot, source: sourceSnapshot)
            if plan.isEmpty { continue }
            do {
                try copy(plan: plan, from: sourceContext, into: mainContext)
            } catch {
                logger.error(
                    "rescue copy from \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
            insertedAny = true
            outcome.ledgersMerged += plan.ledgerIDs.count
            outcome.recordsMerged += plan.recordIDs.count
            logger.info(
                "rescue merged from \(name, privacy: .public): ledgers=\(plan.ledgerIDs.count, privacy: .public) records=\(plan.recordIDs.count, privacy: .public)")
            // 主店快照随并入更新（未 save 的插入对同 context 的 fetch
            // 可见），下一个候选按新快照去重，不会重复并入
            if let updated = try? snapshot(of: mainContext) {
                mainSnapshot = updated
            }
        }

        if insertedAny {
            do {
                try mainContext.save()
            } catch {
                logger.error(
                    "rescue main save failed, will retry next launch: \(error.localizedDescription, privacy: .public)")
                return outcome
            }
        }
        outcome.completed = true
        return outcome
    }

    /// 一个店面的 ID 快照（身份＋外键，口径见 Core StoreSnapshotIDs）
    private static func snapshot(of context: ModelContext) throws -> StoreSnapshotIDs {
        var snap = StoreSnapshotIDs()
        snap.ledgerIDs = Set(try context.fetch(FetchDescriptor<Ledger>()).map(\.id))
        snap.records = try context.fetch(FetchDescriptor<GiftRecord>())
            .map { StoreChildRef(id: $0.id, ledgerID: $0.ledgerID) }
        snap.members = try context.fetch(FetchDescriptor<LedgerMember>())
            .map { StoreChildRef(id: $0.id, ledgerID: $0.ledgerID) }
        snap.signatures = try context.fetch(FetchDescriptor<GuestSignature>())
            .map { StoreChildRef(id: $0.id, ledgerID: $0.ledgerID) }
        snap.bindings = try context.fetch(FetchDescriptor<GuestEventBinding>())
            .map { StoreChildRef(id: $0.id, ledgerID: $0.ledgerID) }
        snap.receipts = try context.fetch(FetchDescriptor<GuestReceipt>())
            .map { StoreChildRef(id: $0.id, ledgerID: $0.ledgerID) }
        snap.blessings = try context.fetch(FetchDescriptor<VoiceBlessing>())
            .map { StoreBlessingRef(id: $0.id, recordID: $0.recordID) }
        snap.reminderIDs = Set(try context.fetch(FetchDescriptor<ReminderDay>()).map(\.id))
        return snap
    }

    /// 按计划把源店实体逐字段复制进主店（同 ID 新实例；不 save，
    /// 由 run 在全部候选处理完后统一落盘）
    private static func copy(
        plan: StoreMergePlan, from source: ModelContext, into main: ModelContext
    ) throws {
        if !plan.ledgerIDs.isEmpty {
            for ledger in try source.fetch(FetchDescriptor<Ledger>())
            where plan.ledgerIDs.contains(ledger.id) {
                main.insert(Ledger(
                    id: ledger.id, title: ledger.title, type: ledger.type,
                    date: ledger.date, note: ledger.note,
                    hostName: ledger.hostName, scribe: ledger.scribe,
                    verifier: ledger.verifier, location: ledger.location
                ))
            }
        }
        if !plan.recordIDs.isEmpty {
            for record in try source.fetch(FetchDescriptor<GiftRecord>())
            where plan.recordIDs.contains(record.id) {
                main.insert(GiftRecord(
                    id: record.id, ledgerID: record.ledgerID,
                    person: record.person, relation: record.relation,
                    amountCents: record.amountCents, direction: record.direction,
                    method: record.method, note: record.note, date: record.date,
                    status: record.status, returned: record.returned
                ))
            }
        }
        if !plan.memberIDs.isEmpty {
            for member in try source.fetch(FetchDescriptor<LedgerMember>())
            where plan.memberIDs.contains(member.id) {
                main.insert(LedgerMember(
                    id: member.id, ledgerID: member.ledgerID, name: member.name,
                    role: member.role, createdAt: member.createdAt
                ))
            }
        }
        if !plan.signatureIDs.isEmpty {
            for signature in try source.fetch(FetchDescriptor<GuestSignature>())
            where plan.signatureIDs.contains(signature.id) {
                main.insert(GuestSignature(
                    id: signature.id, ledgerID: signature.ledgerID,
                    recordID: signature.recordID, person: signature.person,
                    imageData: signature.imageData, createdAt: signature.createdAt
                ))
            }
        }
        if !plan.blessingIDs.isEmpty {
            for blessing in try source.fetch(FetchDescriptor<VoiceBlessing>())
            where plan.blessingIDs.contains(blessing.id) {
                main.insert(VoiceBlessing(
                    id: blessing.id, recordID: blessing.recordID,
                    fileName: blessing.fileName, duration: blessing.duration,
                    transcript: blessing.transcript, createdAt: blessing.createdAt
                ))
            }
        }
        if !plan.bindingIDs.isEmpty {
            for binding in try source.fetch(FetchDescriptor<GuestEventBinding>())
            where plan.bindingIDs.contains(binding.id) {
                main.insert(GuestEventBinding(
                    id: binding.id, ledgerID: binding.ledgerID,
                    eventID: binding.eventID, publicToken: binding.publicToken,
                    guestURL: binding.guestURL, eventTitle: binding.eventTitle,
                    eventDate: binding.eventDate, eventType: binding.eventType,
                    closed: binding.closed, lastSince: binding.lastSince,
                    createdAt: binding.createdAt
                ))
            }
        }
        if !plan.receiptIDs.isEmpty {
            for receipt in try source.fetch(FetchDescriptor<GuestReceipt>())
            where plan.receiptIDs.contains(receipt.id) {
                main.insert(GuestReceipt(
                    id: receipt.id, ledgerID: receipt.ledgerID,
                    eventID: receipt.eventID, serverID: receipt.serverID,
                    name: receipt.name, amountCents: receipt.amountCents,
                    blessing: receipt.blessing, createdAtRaw: receipt.createdAtRaw,
                    statusRaw: receipt.statusRaw, linkedRecordID: receipt.linkedRecordID,
                    handledAt: receipt.handledAt
                ))
            }
        }
        if !plan.reminderIDs.isEmpty {
            for day in try source.fetch(FetchDescriptor<ReminderDay>())
            where plan.reminderIDs.contains(day.id) {
                main.insert(ReminderDay(
                    id: day.id, person: day.person, relation: day.relation,
                    kind: day.kind, calendarKind: day.calendarKind,
                    month: day.month, day: day.day, leadDays: day.leadDays,
                    enabled: day.enabled, note: day.note
                ))
            }
        }
    }
}
