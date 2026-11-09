import Foundation

// MARK: - 界面字号三档（v5.13，长辈刚需）

/// 字号偏好三档：标准／大／特大。在系统 Dynamic Type 之上叠加——
/// 档位只设「保底」，系统字号本来就更大时尊重系统，绝不把字改小。
/// 导出（礼谱 PDF、分享图卡）是静态成品、字号由版式决定，一律不
/// 跟随本档位（设置页文案明示）。
public enum AppTextSizeTier: String, CaseIterable, Sendable {
    case standard
    case large
    case extraLarge

    public static let storageKey = "appTextSizeTier"

    public init(storedRaw: String?) {
        self = AppTextSizeTier(rawValue: storedRaw ?? "") ?? .standard
    }

    /// DynamicTypeSize 全序（xSmall=0, small=1, medium=2, large=3,
    /// xLarge=4, xxLarge=5, xxxLarge=6, accessibility1=7 … 5=11）
    /// 中的保底下标：标准不设保底；大＝xxLarge；特大＝accessibility1
    /// （封在辅助功能一档，是「不撑爆主要布局」的克制上限）。
    public var floorIndex: Int? {
        switch self {
        case .standard: return nil
        case .large: return 5
        case .extraLarge: return 7
        }
    }
}

public enum TextSizeScale {
    /// 目标字号下标＝max(系统下标， 档位保底）；标准档恒等返回系统值
    public static func targetIndex(systemIndex: Int, tier: AppTextSizeTier) -> Int {
        guard let floor = tier.floorIndex else { return systemIndex }
        return max(systemIndex, floor)
    }
}
