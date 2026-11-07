import Foundation

// MARK: - App Group 标识解析（侧载重签兜底）
//
// 背景（v4.5 真机实证）：IPA 经 SideStore 的 AltSign 重签时，AltSign 以
// provisioning profile 为准重建 entitlements，并把真实 App Group 名
// （原组名 + "." + TeamID）写入宿主 App 的 Info.plist 的 ALTAppGroups 数组。
// 代码若只认硬编码的原始组名，suite 永远对不上、共享数据静默失效。
//
// 解析口径：优先读当前进程 Bundle 的 Info.plist 里 ALTAppGroups 的首项，
// 读不到（正规签名 / 未重签 / 扩展进程自身 plist 无此键）时回退原始组名常量。
// 本解析只决定「往哪个 suite 读写」，不改变任何一处调用方的 nil 降级语义：
// UserDefaults(suiteName:) 拿不到共享容器时调用方仍按原逻辑静默回退。
public enum AppGroupResolver {
    /// 原始组名（Project.swift 三个 target 的 application-groups 声明同值）
    public static let fallbackGroupID = "group.site.didichou.liqian"

    /// AltSign 写入宿主 App Info.plist 的键名（AltStore 工具链约定）
    public static let altAppGroupsKey = "ALTAppGroups"

    /// 当前进程应使用的 App Group 标识
    public static var groupID: String {
        groupID(from: Bundle.main)
    }

    /// 可注入 Bundle 的纯解析（单测与特殊场景用）
    public static func groupID(from bundle: Bundle) -> String {
        if let groups = bundle.object(forInfoDictionaryKey: altAppGroupsKey) as? [String],
           let first = groups.first(where: { !$0.isEmpty }) {
            return first
        }
        return fallbackGroupID
    }

    /// 当前进程的共享 UserDefaults（suite 不可用时为 nil，语义同 UserDefaults(suiteName:)）
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }
}
