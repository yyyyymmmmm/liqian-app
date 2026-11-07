import Foundation
import SwiftData
import LiqianCore

/// 最近删除条目（快照式）：删除时把模型转成 Backup 快照存进 trash.json，
/// 不动 SwiftData 现有 schema。恢复时按快照重新 insert，保留原始 UUID，
/// 人物聚合（按姓名）自然恢复。
struct TrashItem: Codable, Identifiable {
    enum Kind: String, Codable {
        case record
        case ledger
    }

    var id: UUID
    var kind: Kind
    var deletedAt: Date
    /// kind == .ledger：礼簿快照
    var ledger: BackupLedger? = nil
    /// kind == .ledger：该簿全部记录快照
    var ledgerRecords: [BackupRecord]? = nil
    /// kind == .record：记录快照
    var record: BackupRecord? = nil
    /// kind == .record：所属礼簿 id（与 record.ledgerId 同值，单列方便展示与校验）
    var ledgerID: String? = nil

    /// 还能留几天（满 30 天自动清理）
    var daysLeft: Int {
        let days = Int(Date().timeIntervalSince(deletedAt) / 86_400)
        return max(0, 30 - days)
    }
}

enum TrashStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("trash.json")
    }

    // MARK: - 读写

    static func list() -> [TrashItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = (try? decoder.decode([TrashItem].self, from: data)) ?? []
        return items.sorted { $0.deletedAt > $1.deletedAt }
    }

    private static func save(_ items: [TrashItem]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - 归档（删除前调用）

    static func archive(record: GiftRecord) {
        var items = list()
        items.append(
            TrashItem(
                id: UUID(),
                kind: .record,
                deletedAt: Date(),
                record: backupRecord(from: record),
                ledgerID: record.ledgerID.uuidString
            )
        )
        save(items)
    }

    static func archive(ledger: Ledger, records: [GiftRecord]) {
        var items = list()
        items.append(
            TrashItem(
                id: UUID(),
                kind: .ledger,
                deletedAt: Date(),
                ledger: BackupLedger(
                    id: ledger.id.uuidString,
                    title: ledger.title,
                    type: ledger.type,
                    date: ledger.date,
                    note: ledger.note,
                    hostName: ledger.hostName,
                    scribe: ledger.scribe,
                    verifier: ledger.verifier,
                    location: ledger.location
                ),
                ledgerRecords: records.map { backupRecord(from: $0) }
            )
        )
        save(items)
    }

    private static func backupRecord(from r: GiftRecord) -> BackupRecord {
        BackupRecord(
            id: r.id.uuidString,
            ledgerId: r.ledgerID.uuidString,
            person: r.person,
            relation: r.relation,
            amountCents: r.amountCents,
            direction: r.direction,
            method: r.method,
            note: r.note,
            date: r.date,
            returned: r.returned,
            status: r.status
        )
    }

    // MARK: - 恢复 / 清理

    /// 把快照重新 insert 回数据库（保留原始 UUID），成功后条目自动移出最近删除。
    /// 记录恢复要求所属礼簿还在，避免产生挂空的孤儿记录。
    @discardableResult
    static func restore(id: UUID, into context: ModelContext) -> Bool {
        guard let item = list().first(where: { $0.id == id }) else { return false }
        let ok: Bool
        switch item.kind {
        case .record:
            ok = restoreRecord(item, into: context)
        case .ledger:
            ok = restoreLedger(item, into: context)
        }
        guard ok else { return false }
        try? context.save()
        purge(id: id)
        return true
    }

    private static func restoreRecord(_ item: TrashItem, into context: ModelContext) -> Bool {
        guard let br = item.record, let lid = br.ledgerUUID else { return false }
        let ledgers = (try? context.fetch(FetchDescriptor<Ledger>())) ?? []
        guard ledgers.contains(where: { $0.id == lid }) else { return false }
        let records = (try? context.fetch(FetchDescriptor<GiftRecord>())) ?? []
        if records.contains(where: { $0.id == br.idUUID }) { return true }
        context.insert(giftRecord(from: br, ledgerID: lid))
        return true
    }

    private static func restoreLedger(_ item: TrashItem, into context: ModelContext) -> Bool {
        guard let bl = item.ledger else { return false }
        let lid = bl.idUUID ?? UUID()
        let ledgers = (try? context.fetch(FetchDescriptor<Ledger>())) ?? []
        if !ledgers.contains(where: { $0.id == lid }) {
            context.insert(
                Ledger(
                    id: lid, title: bl.title, type: bl.type, date: bl.date, note: bl.note,
                    hostName: bl.hostName, scribe: bl.scribe,
                    verifier: bl.verifier, location: bl.location
                )
            )
        }
        let records = (try? context.fetch(FetchDescriptor<GiftRecord>())) ?? []
        let existingIDs = Set(records.map(\.id))
        for br in item.ledgerRecords ?? [] {
            if let rid = br.idUUID, existingIDs.contains(rid) { continue }
            context.insert(giftRecord(from: br, ledgerID: lid))
        }
        return true
    }

    private static func giftRecord(from br: BackupRecord, ledgerID: UUID) -> GiftRecord {
        GiftRecord(
            id: br.idUUID ?? UUID(),
            ledgerID: ledgerID,
            person: br.person,
            relation: br.relation,
            amountCents: br.amountCents,
            direction: br.direction,
            method: br.method,
            note: br.note,
            date: br.date,
            status: br.status,
            returned: br.returned
        )
    }

    /// 彻底删除一条（不进数据库，纯粹丢弃快照）
    static func purge(id: UUID) {
        save(list().filter { $0.id != id })
    }

    /// 清掉超过 30 天的条目（App 启动时调用）
    static func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        save(list().filter { $0.deletedAt > cutoff })
    }

    static func clearAll() {
        save([])
    }
}
