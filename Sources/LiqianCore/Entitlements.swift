import Foundation

// MARK: - Pro 权益判定（v5 买断闭环，纯逻辑层）
// 权益判断全 App 收敛到 App 层的 EntitlementCenter，它内部只问本枚举：
// 输入＝StoreKit 已验证（.verified 且未撤销）交易的 productID 集合＋
// 机主构建旗。判定收敛成纯函数是为了可单测——四个门控面（Excel 导出、
// 纪念版礼谱、家族汇册、印刷版礼谱）不许各自拼判定，口径漂移过一次
// 就是事故。基础礼谱 PDF 与机器可读备份（JSON 全量备份）永远免费，
// 不在门控清单内（尖刀引流口径，竞品审计定版）。

/// 受 Pro 门控的导出面（仅此四处）
public enum ProFeature: CaseIterable, Sendable {
    /// 「我的 → 数据」的 CSV 表格导出（可用 Excel 打开）
    case excelExport
    /// 传承包内的纪念版礼谱
    case memorialBook
    /// 家族汇册（多簿合并成册）
    case familyAlbum
    /// 印刷版礼谱（出血＋封面展开图＋印刷参数页）
    case printBook
}

public enum ProEntitlement {
    /// 是否已开通 Pro：
    /// - 机主构建（LIQIAN_OWNER_BUILD，CI 侧载专用）：恒真——机主自用机
    ///   不放行，婚礼当天连自己的纪念版都导不出；App Store 构建不带此旗。
    /// - 否则：已验证交易集合含 Pro 产品 id 即已购。
    public static func isPro(verifiedProductIDs: Set<String>, ownerBuild: Bool) -> Bool {
        if ownerBuild { return true }
        return verifiedProductIDs.contains(LiqianConstants.proProductID)
    }

    /// 某门控面是否可用（当前所有门控面同属一个买断，不分档）
    public static func canUse(_ feature: ProFeature, verifiedProductIDs: Set<String>, ownerBuild: Bool) -> Bool {
        isPro(verifiedProductIDs: verifiedProductIDs, ownerBuild: ownerBuild)
    }
}
