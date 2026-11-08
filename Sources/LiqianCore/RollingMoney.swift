import Foundation

// MARK: - 金额滚动策略（v5.4）
//
// v4.6 的 RollingMoneyText 每次进图表页都从 0 滚一遍（入场必滚），
// 与数值有没有真变无关——用户点名：有新纪录（数值真变了）才滚。
// 策略收敛到这里以便单测：按指标键在 UserDefaults 存「上次显示值」，
// 决策只有三种：
// - 从没存过（第一次见到这个指标）→ 从 0 滚（首见入场，滚完落档）；
// - 存档值 == 当前值 → 不滚，静态直出；
// - 存档值 != 当前值 → 从存档值滚到当前值，并更新存档。
// 筛选切换导致的值变化同样走此决策（调用方以「指标＋范围」作键时，
// 每个范围各有自己的存档，互不串扰）。

public enum RollingMoneyStore {
    private static func key(_ metricKey: String) -> String {
        "rollingMoney.lastShown.\(metricKey)"
    }

    public static func storedCents(
        metricKey: String, defaults: UserDefaults = .standard
    ) -> Int? {
        defaults.object(forKey: key(metricKey)) as? Int
    }

    public static func store(
        cents: Int, metricKey: String, defaults: UserDefaults = .standard
    ) {
        defaults.set(cents, forKey: key(metricKey))
    }

    /// 滚动决策：（rolls 是否滚动，fromCents 从哪个值起滚）
    public static func plan(storedCents: Int?, currentCents: Int) -> (rolls: Bool, fromCents: Int) {
        guard let storedCents else { return (true, 0) }
        guard storedCents != currentCents else { return (false, currentCents) }
        return (true, storedCents)
    }

    /// 读存档并决策的便捷口径（视图层 onAppear/onChange 共用）
    public static func plan(
        metricKey: String, currentCents: Int, defaults: UserDefaults = .standard
    ) -> (rolls: Bool, fromCents: Int) {
        plan(storedCents: storedCents(metricKey: metricKey, defaults: defaults), currentCents: currentCents)
    }
}
