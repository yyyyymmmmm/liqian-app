import SwiftUI
import UIKit
import LiqianCore
import LiqianDesign

/// App 图标变体（v5.9，审计 #2 方案 A）：白底与构图不变，只换礼结颜色。
/// 系统不许运行时给图标染色——每款都是一张随包预置的完整图标
/// （生产脚本 scripts/make_alt_icons.py 对主图做覆盖率投影换色，
/// 清单与色值以脚本内 VARIANTS 表为单一事实源，与此处逐项对应）。
///
/// 构成（用户拍板）：5 个预置主题同色（白天＝默认朱砂，不单列）
/// ＋独立色 4 款（大厂红/蓝/黑/黄）。朱砂红与默认同色，按审计口径去重。
enum AppIconVariant: String, CaseIterable, Identifiable {
    /// 默认（朱砂）：资源目录主图标，切换时传 nil
    case primary
    case night
    case tencentBlue
    case graphite
    case amber
    case jdRed
    case appleBlue
    case black
    case brightYellow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primary: return "朱砂（默认）"
        case .night: return "夜晚"
        case .tencentBlue: return "腾讯蓝"
        case .graphite: return "石墨灰"
        case .amber: return "琥珀"
        case .jdRed: return "大厂红"
        case .appleBlue: return "蓝"
        case .black: return "黑"
        case .brightYellow: return "黄"
        }
    }

    /// 礼结颜色（与生产脚本 VARIANTS 表同值）
    var knotHex: UInt32 {
        switch self {
        case .primary: return 0xA62B1F
        case .night: return 0xD96A5C
        case .tencentBlue: return 0x0052D9
        case .graphite: return 0x4E5969
        case .amber: return 0xA16207
        case .jdRed: return 0xE1251B
        case .appleBlue: return 0x007AFF
        case .black: return 0x232323
        case .brightYellow: return 0xE8A20C
        }
    }

    /// setAlternateIconName 的注册名（Info.plist CFBundleAlternateIcons 的键）；
    /// 主图标传 nil 回默认
    var alternateName: String? {
        self == .primary ? nil : "AltIcon-\(rawValue)"
    }

    /// 包内图标文件基名（@2x/@3x 两档随包，UIImage 按名解析）；
    /// 主图标的同名文件是脚本一并生成的预览图（只作设置页缩略图，
    /// 不在 plist 声明里——桌面默认图标仍走资源目录主图标）
    var resourceName: String { "AltIcon-\(rawValue)" }

    var thumbnail: UIImage? { UIImage(named: resourceName) }

    /// 主题 → 图标的联动映射：预置主题一一同色；自定义主题按基色
    /// 在全部变体里就近匹配（Core 纯函数裁决）
    static func variant(for theme: AppTheme) -> AppIconVariant {
        switch theme {
        case .day: return .primary
        case .night: return .night
        case .tencentBlue: return .tencentBlue
        case .graphite: return .graphite
        case .amber: return .amber
        case .custom:
            let nearest = CustomTheme.nearestHex(
                baseHex: AppTheme.customBaseHex,
                candidates: AppIconVariant.allCases.map(\.knotHex)
            )
            return AppIconVariant.allCases.first { $0.knotHex == nearest } ?? .primary
        }
    }
}

/// 备用图标切换的单点封装
enum AppIconManager {
    /// 「图标跟随主题」@AppStorage 键
    static let followStorageKey = "iconFollowsTheme"

    /// 当前生效变体（读系统 alternateIconName 反查）
    static var currentVariant: AppIconVariant {
        guard let name = UIApplication.shared.alternateIconName else { return .primary }
        return AppIconVariant.allCases.first { $0.alternateName == name } ?? .primary
    }

    /// 切换图标。completion 传 nil——不给框架留回调（本项目有框架回调
    /// 隔离击杀的前科，见 docs/V551-NOTES）；成败由系统弹窗与桌面图标
    /// 本身确认。设备不支持备用图标时静默不动。
    static func apply(_ variant: AppIconVariant) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = variant.alternateName
        guard UIApplication.shared.alternateIconName != target else { return }
        UIApplication.shared.setAlternateIconName(target, completionHandler: nil)
    }

    /// 跟随主题：把图标切到当前主题的对应变体
    static func applyFollowingTheme() {
        apply(AppIconVariant.variant(for: AppTheme.current))
    }
}
