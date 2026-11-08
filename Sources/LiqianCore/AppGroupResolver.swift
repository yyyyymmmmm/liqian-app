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

    // MARK: - 候选组名集（v5.11.1：读取侧加固）

    /// TeamID 后缀的形状：AltSign 追加的 TeamID 是 10 位大写字母/数字。
    /// 仅作变体构造的启发式判据，不参与组名解析本身。
    public static func isTeamIDShaped(_ suffix: String) -> Bool {
        suffix.count == 10
            && suffix.allSatisfy { ($0.isLetter && $0.isUppercase) || $0.isNumber }
    }

    /// 若 name 形如「base + "." + TeamID」返回该 TeamID，否则 nil
    public static func teamIDSuffix(of name: String, base: String) -> String? {
        guard name.hasPrefix(base + ".") else { return nil }
        let suffix = String(name.dropFirst(base.count + 1))
        return isTeamIDShaped(suffix) ? suffix : nil
    }

    /// 候选组名集（纯函数，可单测）：读取侧逐个尝试、命中哪家用哪家。
    /// 构造规则（顺序即优先级，去重保序）：
    /// 1. 当前进程解析名（resolved）打头——正常路径行为与单组名读完全一致；
    /// 2. ALTAppGroups 的全部项（不只首项：两侧 plist 写入项序可能不同）；
    /// 3. 原始组名 fallback（解析名带后缀时，它同时就是「去后缀」变体）；
    /// 4. TeamID 变体：从以上任一已知名里提取到的 TeamID 后缀，补到
    ///    原始组名之后（「补后缀」变体），防 plist 缺项但后缀可推知。
    public static func candidateGroupIDs(
        resolved: String, altGroups: [String], fallback: String = fallbackGroupID
    ) -> [String] {
        var result: [String] = []
        func add(_ name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !result.contains(trimmed) { result.append(trimmed) }
        }
        add(resolved)
        for group in altGroups { add(group) }
        add(fallback)
        var teamIDs: [String] = []
        for name in result {
            if let teamID = teamIDSuffix(of: name, base: fallback),
               !teamIDs.contains(teamID) {
                teamIDs.append(teamID)
            }
        }
        for teamID in teamIDs { add(fallback + "." + teamID) }
        return result
    }

    /// 当前进程的候选组名集（Bundle 注入点在此收口）
    public static var candidateGroupIDs: [String] {
        let groups = Bundle.main.object(forInfoDictionaryKey: altAppGroupsKey) as? [String] ?? []
        return candidateGroupIDs(resolved: groupID, altGroups: groups)
    }

    /// 组容器是否真可用（Share 扩展同款严口径，见 ShareChannel.groupDefaults）：
    /// UserDefaults(suiteName:) 本身不足以判共享是否成立，containerURL 非 nil
    /// 才表示这个组在本进程的配发里真实存在。
    public static func containerAvailable(_ groupID: String) -> Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) != nil
    }
}
