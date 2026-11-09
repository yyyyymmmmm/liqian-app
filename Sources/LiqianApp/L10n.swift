import Foundation
import LiqianCore

/// 本地化取串（v5.13）：SwiftUI 的 Text/Label 字面量由系统按环境
/// locale 自动查 Localizable 表；代码拼装的串（汇总句、状态文案等）
/// 走这里，按当前解析语言显式取对应 .lproj 的表值。
/// 表缺条目时回退键本身（简体原文），不丢字、不崩。
enum L10n {
    /// 当前解析语言（偏好＋系统首选语言，口径在 Core AppLanguage）
    static var resolved: ResolvedLanguage { AppLanguage.resolved() }

    /// 取串只发生在主线程的界面/导出路径；Swift 6 下用
    /// nonisolated(unsafe) 承接缓存（同 CloudSync 既定先例）。
    nonisolated(unsafe) private static var bundleCache: [String: Bundle] = [:]

    /// 按当前语言取串：key 为简体原文（与 Localizable 表键一致）
    static func string(_ key: String) -> String {
        let lang = resolved
        if let bundle = lprojBundle(for: lang) {
            return bundle.localizedString(forKey: key, value: key, table: "Localizable")
        }
        return key
    }

    /// 带格式参数取串（表内为 %@/%lld 形式）
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), arguments: args)
    }

    private static func lprojBundle(for lang: ResolvedLanguage) -> Bundle? {
        if let cached = bundleCache[lang.lprojName] { return cached }
        guard let path = Bundle.main.path(forResource: lang.lprojName, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        bundleCache[lang.lprojName] = bundle
        return bundle
    }
}
