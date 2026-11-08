import Foundation

/// 默认礼簿决策（v5.8.1 片二 #10）：新建记账时默认选哪本礼簿的唯一口径。
///
/// 顺序（用户拍板「默认是上一次的礼簿」）：
/// 1. **上次使用**——上次成功记账所记的礼簿（保存时回写，键见
///    `lastUsedKey`），前提：仍存在，且不是示例礼簿（示例约束沿
///    v4.2 定版：有真礼簿时默认绝不落示例簿——示例数据统计隔离，
///    记进去等于白记）；
/// 2. **日期最新的非示例礼簿**——v4.2 起的现行兜底口径；
/// 3. **日期最新的礼簿**（只剩示例簿时才轮到，与现行口径一致）；
/// 4. 一本都没有 → nil（表单走「先建一本礼簿」文案）。
///
/// 纯函数：调用方传按日期倒序的礼簿 ID 列表与示例 ID 集合，决策
/// 只看这三样，便于单测钉死（DefaultLedgerPickerTests）。
public enum DefaultLedgerPicker {
    /// 「上次使用礼簿」的持久化键：App 侧以 @AppStorage 存 UUID 字符串，
    /// RecordFormView 在新建记账成功保存后回写。
    public static let lastUsedKey = "lastUsedLedgerID"

    public static func pick(
        lastUsedID: UUID?,
        ledgerIDsByDateDescending: [UUID],
        sampleIDs: Set<UUID>
    ) -> UUID? {
        if let lastUsedID,
           ledgerIDsByDateDescending.contains(lastUsedID),
           !sampleIDs.contains(lastUsedID) {
            return lastUsedID
        }
        return ledgerIDsByDateDescending.first { !sampleIDs.contains($0) }
            ?? ledgerIDsByDateDescending.first
    }
}
