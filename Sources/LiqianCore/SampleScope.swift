import Foundation

// MARK: - 示例身份与统计空态口径（v5.13 B 案收口）

/// 示例礼簿的身份判定与统计页空态分档，纯函数单点收敛、可测。
/// 背景（sample-report-diag）：统计隔离是 PRO-AUDIT-2 定版（示例不
/// 计入任何统计，过滤逻辑本身不动）；v5.13 只修两点呈现与认领——
/// ①标题认领误伤：旧版 sampleIDs 除存储 ID 外还认领「标题以『示例』
/// 开头」的账本，用户自建的真礼簿若恰以示例开头会被静默吞进隔离。
/// v5.13 起只认生成时记录的 ID 集合 ∩ 现存账本，标题永不参与判定。
/// ②统计页空态误导：示例-only 用户打开总览/报告只见「还没有记录」，
/// 与往来页（不隔离、示例可见）自相矛盾；空态按本分档出示例版明示。
public enum SampleScope {
    /// 示例账本 ID ＝ 存储集合 ∩ 现存账本（删除后残留的存储 ID
    /// 求交时自然失效）。判定只看 ID，用户数据（标题）永不参与。
    public static func sampleIDs(
        storedIDs: Set<UUID>, existingIDs: Set<UUID>
    ) -> Set<UUID> {
        storedIDs.intersection(existingIDs)
    }

    /// 统计页空态三档
    public enum StatsEmptyKind: Sendable {
        /// 有真实记录（页面非空，不出空态）
        case none
        /// 无任何记录、无示例簿：普通空态
        case realEmpty
        /// 有示例簿但无真实记录：示例版空态（明示不计入统计）
        case sampleOnly
    }

    /// - realRecordCount：统计隔离过滤后的记录数（真实记录）
    public static func statsEmptyKind(
        hasSamples: Bool, realRecordCount: Int
    ) -> StatsEmptyKind {
        if realRecordCount > 0 { return .none }
        return hasSamples ? .sampleOnly : .realEmpty
    }
}
