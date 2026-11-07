import Foundation
import SwiftData
import LiqianCore

/// 示例数据：两本以「示例」开头的礼簿，让新用户先看懂聚合口径再上手。
/// 刻意埋了三个演示点：
/// - 同名并列：王建国在婚礼簿里有两笔（同人同簿不合并，与正式口径一致）；
/// - 跨簿差额：赵国强、马小东在两本簿都有往来，往来页能看到汇总与差额；
/// - 待送出：王建国一笔待送出，演示备礼清单与「未回」自动规则。
///
/// 身份口径（PRO-AUDIT-2 诊断三定版）：示例身份＝生成时记录的账本 ID 集合
/// （UserDefaults 键 sampleLedgerIDs，不进备份），hasSamples/清除/防重/统计隔离
/// 全部按「ID 集合 ∩ 现存账本」判定——改名不再脱钩。旧版按标题前缀生成的示例
/// 没有 ID 记录，sampleIDs(ledgers:) 一并认领其 ID，保证旧示例同样可清、可隔离。
enum SampleData {
    private static let idsKey = "sampleLedgerIDs"

    /// UserDefaults 里存的示例账本 ID 集合（账本删掉后残留 ID 无害，求交时自然失效）
    private static var storedIDs: Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        return Set(raw.compactMap { UUID(uuidString: $0) })
    }

    private static func storeIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: idsKey)
    }

    /// 当前实际存在的示例账本 ID：存储集合 ∩ 现存账本 ∪ 旧版标题前缀认领
    static func sampleIDs(ledgers: [Ledger]) -> Set<UUID> {
        var ids = storedIDs.intersection(Set(ledgers.map(\.id)))
        ids.formUnion(ledgers.filter { $0.title.hasPrefix("示例") }.map(\.id))
        return ids
    }

    static func hasSamples(ledgers: [Ledger]) -> Bool {
        !sampleIDs(ledgers: ledgers).isEmpty
    }

    /// 已生成过就不再重复生成。返回 true 表示这次真的生成了（调用方据此给回执）
    @discardableResult
    static func generate(into context: ModelContext) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<Ledger>())) ?? []
        guard !hasSamples(ledgers: existing) else { return false }

        let weddingDate = dateString(daysFromToday: -12)
        let wedding = Ledger(
            title: "示例·表哥婚礼",
            type: "婚礼",
            date: weddingDate,
            note: "示例数据，可在「我的」里一键清除"
        )
        context.insert(wedding)

        let weddingReceived: [(String, String, Int, String, String)] = [
            // 姓名, 关系, 金额（分）, 方式, 备注
            ("王建国", "亲戚", 60_000, "现金", ""),
            ("王建国", "亲戚", 80_000, "微信", "示例：同一个人分两次给，并列两笔"),
            ("李秀英", "亲戚", 100_000, "现金", ""),
            ("赵国强", "亲戚", 200_000, "现金", ""),
            ("张伟", "朋友", 50_000, "微信", ""),
            ("马小东", "同事", 30_000, "微信", ""),
            ("陈静", "同学", 40_000, "支付宝", ""),
            ("孙丽", "朋友", 60_000, "现金", ""),
            ("周建军", "邻居", 20_000, "现金", ""),
            ("吴晓梅", "同事", 80_000, "微信", ""),
        ]
        for (name, relation, cents, method, note) in weddingReceived {
            context.insert(
                GiftRecord(
                    ledgerID: wedding.id,
                    person: name,
                    relation: relation,
                    amountCents: cents,
                    direction: LiqianConstants.received,
                    method: method,
                    note: note,
                    date: weddingDate
                )
            )
        }
        // 待送出一笔：进备礼清单，且按规则不计入差额
        context.insert(
            GiftRecord(
                ledgerID: wedding.id,
                person: "王建国",
                relation: "亲戚",
                amountCents: 100_000,
                direction: LiqianConstants.given,
                method: "微信",
                note: "示例：备着他家孩子满月时送",
                date: dateString(daysFromToday: 5),
                status: LiqianConstants.pendingStatus
            )
        )

        let movingDate = dateString(daysFromToday: -40)
        let moving = Ledger(
            title: "示例·乔迁",
            type: "乔迁",
            date: movingDate,
            note: "示例数据，可在「我的」里一键清除"
        )
        context.insert(moving)
        // 赵国强跨簿同人：两本簿加起来看总额与差额
        context.insert(
            GiftRecord(
                ledgerID: moving.id,
                person: "赵国强",
                relation: "亲戚",
                amountCents: 100_000,
                direction: LiqianConstants.received,
                method: "现金",
                date: movingDate
            )
        )
        // 马小东跨簿有随礼：往来页能看到「我多给」的差额
        context.insert(
            GiftRecord(
                ledgerID: moving.id,
                person: "马小东",
                relation: "同事",
                amountCents: 60_000,
                direction: LiqianConstants.given,
                method: "微信",
                note: "示例：他乔迁时我随的礼",
                date: movingDate
            )
        )
        context.insert(
            GiftRecord(
                ledgerID: moving.id,
                person: "徐文博",
                relation: "同事",
                amountCents: 50_000,
                direction: LiqianConstants.received,
                method: "微信",
                date: movingDate
            )
        )

        try? context.save()
        storeIDs(storedIDs.union([wedding.id, moving.id]))
        return true
    }

    /// 按 ID 清掉示例礼簿及其记录（改过名的也照清；真实数据不受影响）
    static func clearSamples(ledgers: [Ledger], records: [GiftRecord], in context: ModelContext) {
        let ids = sampleIDs(ledgers: ledgers)
        guard !ids.isEmpty else { return }
        for r in records where ids.contains(r.ledgerID) {
            context.delete(r)
        }
        for l in ledgers where ids.contains(l.id) {
            context.delete(l)
        }
        try? context.save()
        storeIDs(storedIDs.subtracting(ids))
    }

    private static func dateString(daysFromToday offset: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return LiqianDate.string(from: d)
    }
}
