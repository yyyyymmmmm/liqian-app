import Foundation

// MARK: - App 语言（v5.13 语言全跟随，用户定版）

/// 语言偏好三档：跟随系统／简体／繁體。存储键由本文件持有，
/// 设置页（外观）写、根视图与导出链读，口径单点收敛于此。
public enum AppLanguagePreference: String, CaseIterable, Sendable {
    case system
    case simplified
    case traditional

    public static let storageKey = "appLanguagePreference"

    public init(storedRaw: String?) {
        self = AppLanguagePreference(rawValue: storedRaw ?? "") ?? .system
    }
}

/// 解析后的实际语言：本 App 只做中文两系，其他系统语言一律回落简体
/// （用户定版：系统语言非中时界面回落简体）。
public enum ResolvedLanguage: String, Sendable {
    case simplified
    case traditional

    /// SwiftUI 环境 locale：简体沿用历史的 zh_CN（日期控件格式与旧版一致），
    /// 繁体用 zh-Hant（按字系而非地区，港台通用）。
    public var localeIdentifier: String {
        switch self {
        case .simplified: return "zh_CN"
        case .traditional: return "zh-Hant"
        }
    }

    /// 包内 .lproj 目录名（L10n 按此名取串）
    public var lprojName: String {
        switch self {
        case .simplified: return "zh-Hans"
        case .traditional: return "zh-Hant"
        }
    }

    /// 礼谱脚本：界面语言即谱面语言（用户定版：导出全跟随）
    public var libuScript: LibuScript {
        switch self {
        case .simplified: return .simplified
        case .traditional: return .traditional
        }
    }
}

public enum AppLanguage {
    /// 当前偏好（读 UserDefaults；无存储＝跟随系统）
    public static func preference(defaults: UserDefaults = .standard) -> AppLanguagePreference {
        AppLanguagePreference(storedRaw: defaults.string(forKey: AppLanguagePreference.storageKey))
    }

    /// 当前解析语言（偏好＋系统首选语言）
    public static func resolved(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ResolvedLanguage {
        resolve(preference: preference(defaults: defaults), preferredLanguages: preferredLanguages)
    }

    /// 纯解析（可测）：显式档直接定；跟随系统看首选语言——
    /// 简繁判定只认「中文且为繁体字系」：标识含 Hant，或中文标识的
    /// 地区为 TW/HK/MO；其余（简体中文、非中文、空）一律简体。
    public static func resolve(
        preference: AppLanguagePreference,
        preferredLanguages: [String]
    ) -> ResolvedLanguage {
        switch preference {
        case .simplified: return .simplified
        case .traditional: return .traditional
        case .system:
            guard let first = preferredLanguages.first else { return .simplified }
            return isTraditionalChinese(identifier: first) ? .traditional : .simplified
        }
    }

    /// BCP 47 / ICU 标识是否繁体中文：zh-Hant、zh-TW、zh-HK、zh-MO、
    /// zh-Hant-TW 等为真；zh-Hans、zh-CN、zh-SG、en 等为假。
    public static func isTraditionalChinese(identifier: String) -> Bool {
        let parts = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { $0.lowercased() }
        guard parts.first == "zh" else { return false }
        if parts.contains("hant") { return true }
        // 无字系标记时按地区推断（旧式 zh-TW 写法）
        let traditionalRegions: Set<String> = ["tw", "hk", "mo"]
        return parts.contains { traditionalRegions.contains($0) }
    }
}
