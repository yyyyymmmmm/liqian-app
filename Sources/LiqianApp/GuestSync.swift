import Combine
import Foundation
import SwiftData
import LiqianCore

/// 扫码随礼同步中心（v5.12）：建/关场次、增量拉回执、状态行。
/// 状态口径学小组件自检：同步结果必须落成一句人看得懂的状态
/// （已同步几点几分／失败是什么），不静默吞错、不假装成功。
@MainActor
final class GuestSyncCenter: ObservableObject {
    static let shared = GuestSyncCenter()

    /// 每本礼簿最近一次同步状态（人话一行），键＝礼簿 id
    @Published private(set) var statusByLedger: [UUID: String] = [:]
    @Published private(set) var syncingLedgers: Set<UUID> = []

    private let client = GuestAPIClient()

    private init() {}

    func status(for ledgerID: UUID) -> String? {
        statusByLedger[ledgerID]
    }

    func isSyncing(_ ledgerID: UUID) -> Bool {
        syncingLedgers.contains(ledgerID)
    }

    // MARK: - 绑定查询

    static func binding(for ledgerID: UUID, in context: ModelContext) -> GuestEventBinding? {
        let descriptor = FetchDescriptor<GuestEventBinding>(
            predicate: #Predicate { $0.ledgerID == ledgerID }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - 建场次 / 关场次 / 重新生成

    /// 给礼簿建场次并绑定：场次名＝礼簿标题、日期＝礼簿日期、
    /// 类型由红白属性决定（白事簿 white，宾客页不出现金额框）。
    /// hostSecret 落 Keychain 后才落绑定行——凭证丢了整场作废，
    /// 顺序保证「有绑定必曾有凭证」。
    @discardableResult
    func createEvent(for ledger: Ledger, in context: ModelContext) async throws -> GuestEventBinding {
        let created = try await client.createEvent(
            title: ledger.title,
            date: ledger.date,
            type: GuestReceiptMapping.apiEventType(isBai: ledger.isBai)
        )
        GuestKeychain.save(created.hostSecret, eventID: created.eventId)
        let binding = GuestEventBinding(
            ledgerID: ledger.id,
            eventID: created.eventId,
            publicToken: created.publicToken,
            guestURL: created.guestUrl,
            eventTitle: ledger.title,
            eventDate: ledger.date,
            eventType: GuestReceiptMapping.apiEventType(isBai: ledger.isBai)
        )
        context.insert(binding)
        try? context.save()
        statusByLedger[ledger.id] = "宾客码已生成，还没收到回执"
        return binding
    }

    /// 关闭收集：服务端幂等、无重开接口。关后回执仍可拉取。
    func closeEvent(binding: GuestEventBinding, in context: ModelContext) async throws {
        guard let secret = GuestKeychain.read(eventID: binding.eventID) else {
            throw GuestAPIError.unauthorized
        }
        try await client.closeEvent(eventID: binding.eventID, hostSecret: secret)
        binding.closed = true
        try? context.save()
        statusByLedger[binding.ledgerID] = "已关闭收集"
    }

    /// 重新生成＝先建新场次、再关旧场次（best-effort）、换绑。
    /// 旧回执按 ledgerID 留在本机（待确认区照常处理）；旧凭证随换绑删除，
    /// 旧场次已关收集，云端留底归用户自有 D1，不再同步。
    @discardableResult
    func regenerate(for ledger: Ledger, in context: ModelContext) async throws -> GuestEventBinding {
        let old = Self.binding(for: ledger.id, in: context)
        let fresh = try await createEvent(for: ledger, in: context)
        if let old {
            if let secret = GuestKeychain.read(eventID: old.eventID), !old.closed {
                try? await client.closeEvent(eventID: old.eventID, hostSecret: secret)
            }
            GuestKeychain.delete(eventID: old.eventID)
            context.delete(old)
            try? context.save()
        }
        return fresh
    }

    // MARK: - 同步

    /// 同步一本礼簿的回执：按游标增量拉取 → 去重落 pending → 推进游标。
    /// 无绑定直接返回（不是错误）；凭证缺失落明确状态行。
    func sync(ledgerID: UUID, in context: ModelContext) async {
        guard let binding = Self.binding(for: ledgerID, in: context) else { return }
        guard !syncingLedgers.contains(ledgerID) else { return }
        guard let secret = GuestKeychain.read(eventID: binding.eventID) else {
            statusByLedger[ledgerID] = "凭证缺失，没能同步（重新生成宾客码可恢复）"
            return
        }
        syncingLedgers.insert(ledgerID)
        defer { syncingLedgers.remove(ledgerID) }
        do {
            let response = try await client.fetchSubmissions(
                eventID: binding.eventID, hostSecret: secret, since: binding.lastSince
            )
            let eventID = binding.eventID
            let existingDescriptor = FetchDescriptor<GuestReceipt>(
                predicate: #Predicate { $0.ledgerID == ledgerID && $0.eventID == eventID }
            )
            let existing = (try? context.fetch(existingDescriptor)) ?? []
            let plan = GuestSyncPlanner.plan(
                existingServerIDs: Set(existing.map(\.serverID)),
                incoming: response.submissions,
                currentCursor: binding.lastSince
            )
            for sub in plan.newSubmissions {
                context.insert(GuestReceipt(
                    ledgerID: ledgerID,
                    eventID: binding.eventID,
                    serverID: sub.id,
                    name: sub.name,
                    amountCents: sub.amountCents,
                    blessing: sub.blessing,
                    createdAtRaw: sub.createdAt
                ))
            }
            binding.lastSince = plan.newCursor
            binding.closed = response.closed
            try? context.save()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            statusByLedger[ledgerID] = plan.newSubmissions.isEmpty
                ? "已同步 \(formatter.string(from: Date())) · 没有新回执"
                : "已同步 \(formatter.string(from: Date())) · 新到 \(plan.newSubmissions.count) 条"
        } catch let error as GuestAPIError {
            statusByLedger[ledgerID] = "同步没成功：\(error.userMessage)"
        } catch {
            statusByLedger[ledgerID] = "同步没成功：\(GuestAPIError.network.userMessage)"
        }
    }

    /// 回前台全量同步：所有已绑定的礼簿各拉一次增量。
    func syncAll(in context: ModelContext) async {
        let descriptor = FetchDescriptor<GuestEventBinding>()
        let bindings = (try? context.fetch(descriptor)) ?? []
        for binding in bindings {
            await sync(ledgerID: binding.ledgerID, in: context)
        }
    }

    /// 忽略回执时同步删云端（best-effort）：绑定已换绑/凭证不在时只删本地，
    /// 不报错——本地状态已落定，云端留底在用户自有库里无害。
    func deleteOnServer(receipt: GuestReceipt, in context: ModelContext) async {
        guard let binding = Self.binding(for: receipt.ledgerID, in: context),
              binding.eventID == receipt.eventID,
              let secret = GuestKeychain.read(eventID: receipt.eventID) else { return }
        try? await client.deleteSubmission(
            eventID: receipt.eventID, hostSecret: secret, submissionID: receipt.serverID
        )
    }
}
