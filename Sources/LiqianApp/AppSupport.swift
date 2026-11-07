import Foundation
import LiqianCore
import UniformTypeIdentifiers

/// App 层共用小工具：快照组装、CSV 导出、备份文档类型
enum AppSupport {
    /// @Query 的记录按存储顺序传入，这里倒序成「新→旧」，
    /// 与 Flutter records 列表顺序一致（LedgerMath 的同日口径依赖此约定）。
    static func snapshots(records: [GiftRecord], ledgers: [Ledger]) -> [EntrySnapshot] {
        let typeByID = Dictionary(ledgers.map { ($0.id, $0.type) }, uniquingKeysWith: { first, _ in first })
        return records.reversed().map { $0.snapshot(ledgerType: typeByID[$0.ledgerID] ?? "") }
    }

    /// CSV 与 Flutter exportCsv 完全同构（列序、引号转义、状态列口径一致）
    static func csvText(records: [GiftRecord], ledgers: [Ledger]) -> String {
        let byID = Dictionary(ledgers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func esc(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines: [String] = ["日期,账本,事由,姓名,关系,方向,金额(元),方式,状态,备注"]
        for r in records.reversed() {
            let l = byID[r.ledgerID]
            let amount = String(format: "%.2f", Double(r.amountCents) / 100.0)
            let status = r.direction == LiqianConstants.given ? r.status : "-"
            lines.append([
                r.date,
                esc(l?.title ?? ""),
                esc(l?.type ?? ""),
                esc(r.person),
                esc(r.relation),
                r.direction,
                amount,
                esc(r.method),
                status,
                esc(r.note),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func writeTempFile(name: String, content: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// fileExporter 用的 JSON 备份文档
struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
