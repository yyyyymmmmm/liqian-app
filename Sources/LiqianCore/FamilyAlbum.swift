import Foundation

// MARK: - 家族汇册聚合（v5 成书做实，纯逻辑层）
// 汇册 PDF 的装配在 App 层（PDFKit），但「谁在哪本簿出现过几次」这份
// 跨簿索引是纯聚合，收敛到 Core 可单测：口径与礼谱成册一致——调用侧
// 传入的人名必须已排除待送出（成册口径），本层只负责合并与排序。

public enum FamilyAlbum {
    /// 输入：一本礼簿在汇册中的样子（人名逐笔，顺序不敏感）
    public struct LedgerInput: Sendable {
        public let ledgerID: UUID
        public let title: String
        /// yyyy-MM-dd（汇册按此升序编章与排序）
        public let date: String
        public let personNames: [String]

        public init(ledgerID: UUID, title: String, date: String, personNames: [String]) {
            self.ledgerID = ledgerID
            self.title = title
            self.date = date
            self.personNames = personNames
        }
    }

    /// 索引条目里的一次「出现」：在哪本簿、几笔
    public struct Appearance: Equatable, Sendable {
        public let ledgerID: UUID
        public let ledgerTitle: String
        public let count: Int

        public init(ledgerID: UUID, ledgerTitle: String, count: Int) {
            self.ledgerID = ledgerID
            self.ledgerTitle = ledgerTitle
            self.count = count
        }
    }

    /// 跨簿人物总索引条目
    public struct PersonIndexEntry: Equatable, Sendable {
        public let name: String
        /// 按礼簿日期升序
        public let appearances: [Appearance]
        public var totalCount: Int { appearances.reduce(0) { $0 + $1.count } }

        public init(name: String, appearances: [Appearance]) {
            self.name = name
            self.appearances = appearances
        }
    }

    /// 跨簿人物总索引：同名即同人（与全 App 人名口径一致）。
    /// 排序：总笔数多者在前，同笔数按姓名升序——卷末索引先见常来往的人。
    /// 空名（去空白后为空）不入索引。
    public static func personIndex(ledgers: [LedgerInput]) -> [PersonIndexEntry] {
        let ordered = ledgers.sorted { ($0.date, $0.title) < ($1.date, $1.title) }
        var byName: [String: [Appearance]] = [:]
        for ledger in ordered {
            var counts: [String: Int] = [:]
            for raw in ledger.personNames {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                counts[name, default: 0] += 1
            }
            for (name, count) in counts {
                byName[name, default: []].append(
                    Appearance(ledgerID: ledger.ledgerID, ledgerTitle: ledger.title, count: count)
                )
            }
        }
        return byName
            .map { PersonIndexEntry(name: $0.key, appearances: $0.value) }
            .sorted {
                if $0.totalCount != $1.totalCount { return $0.totalCount > $1.totalCount }
                return $0.name < $1.name
            }
    }
}

// MARK: - 印刷规格（v5 印刷版礼谱）
// 数值口径来自 POD 调研（research_notes/liqian-pod-vendors-20261108）：
// 3mm 出血、右开本、书脊宽按页数估算且做成可见参数（导出页可调）。

public enum PrintBookSpec {
    /// A4 成品尺寸 @72dpi（与 GiftBookPDF 同值）
    public static let trimWidthPoints: Double = 595.28
    public static let trimHeightPoints: Double = 841.89

    /// 出血：3mm 换算 pt（1mm = 72/25.4 pt）
    public static let bleedMM: Double = 3
    public static var bleedPoints: Double { bleedMM / 25.4 * 72 }

    /// 书脊宽估算（毫米）：页数 × 单页纸厚 + 装订余量，下限 6mm。
    /// 默认纸厚 0.05mm/页（约 80g 胶版纸双面一页的量级）与余量 4mm
    /// 只是下单前估算——终值以印厂按实际纸张回确认为准，导出页可手调。
    public static func spineWidthMM(
        pageCount: Int,
        paperPerPageMM: Double = 0.05,
        allowanceMM: Double = 4
    ) -> Double {
        guard pageCount > 0 else { return 6 }
        return max(6, Double(pageCount) * paperPerPageMM + allowanceMM)
    }

    /// 印刷版内页页数（v5.11.5 修复口径）：屏幕版第 0 页是封面，已进
    /// 封面展开图左区，不算内页。此前装配循环从第 0 页起全嵌、参数页
    /// 与书脊估算也按全页数计，封面在印刷版里出现两次且页数多算 1。
    /// 这里是唯一事实源——装配循环、参数页、书脊估算全取自此处，
    /// 单测在此层钉死，装配层不许再自己数页。
    public static func interiorPageCount(sourcePageCount: Int) -> Int {
        max(0, sourcePageCount - 1)
    }

    /// 印刷版内页要嵌回的屏幕版页序号：从第 1 页起（跳过封面页）
    public static func interiorSourceIndices(sourcePageCount: Int) -> [Int] {
        guard sourcePageCount > 1 else { return [] }
        return Array(1..<sourcePageCount)
    }

    /// 印刷版总页数＝封面展开图 1＋内页＋参数页 1；
    /// 源为空时装配直接失败（makePrintPDF 返回 nil），总页数记 0
    public static func assembledPageCount(sourcePageCount: Int) -> Int {
        guard sourcePageCount > 0 else { return 0 }
        return 1 + interiorPageCount(sourcePageCount: sourcePageCount) + 1
    }

    /// 毫米 → pt
    public static func points(fromMM mm: Double) -> Double {
        mm / 25.4 * 72
    }
}
