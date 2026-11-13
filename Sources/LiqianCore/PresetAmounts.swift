import Foundation

// MARK: - 预设金额单一数据源（v5.14.4）

/// 记账快捷金额小签的唯一列表来源：小签「自带值」——点哪颗落哪个值，
/// 映射恒等（面值即落值），由单测逐一钉死（六个值逐一对应、不许全等末位）。
///
/// v5.14.4 前列表字面量散在各视图（记一笔六档、现场七档各写一份）；
/// 本版收敛到此单点，视图只许引用、不许再写字面量（源码守卫钉死）。
/// 「点哪个都落 1000」事故的定因不在此映射而在容器命中路由，
/// 见 docs/V5144-NOTES.md。
public enum PresetAmounts {
    /// 记一笔快捷金额（元）
    public static let recordForm: [Int] = [100, 200, 300, 500, 800, 1000]
    /// 现场模式常用金额（元）：同记一笔六档加 2000 大额档
    public static let scene: [Int] = [100, 200, 300, 500, 800, 1000, 2000]

    /// 小签点选 → 金额输入框文本：恒为该小签自身面值
    public static func amountText(forPreset value: Int) -> String { "\(value)" }
}
