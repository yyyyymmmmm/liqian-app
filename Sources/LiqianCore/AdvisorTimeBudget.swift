import Foundation

// MARK: - 问账全链总时限（v5.8）：45 秒总预算与分腿分配
//
// 背景（审计 #11 定版）：旧管线回复只在串行链全部跑完后一次性落地，
// 最坏时延＝工具 ≤4 轮 ×30 秒＋意图 30 秒＋通用 lane 30 秒 ≈ 180 秒，
// 用户席上就是「还不回信息」。本预算给整条链设 45 秒总顶，并把总顶
// 预先切给三段，保证每段都有自己的份额、任何一段都不能把后面吃光：
//
//   工具阶段（≤4 轮合计封顶 27 秒）→ 意图腿（封顶 8 秒）→ 通用 lane
//   （吃满总剩余，按上两段封顶算最坏也有 45−27−8＝10 秒）。
//
// 每腿的实际超时＝min(该腿/该阶段封顶, 总剩余)，由 App 层在起腿前用
// 「已经过去多久」来问本类型；返回 nil 表示预算已尽、这一腿不要再起
// （工具阶段回 nil 即结束工具循环落降级；意图回 nil 即跳过 AI 解码
// 直接规则兜底；通用 lane 回 nil 即不调用、交收敛器落兜底回复）。
// 纯函数、无状态，elapsed 由调用方用单调时钟量好传入，可单测。
public enum AdvisorTimeBudget {
    /// 全链总预算（秒）：任何一次提问从发出到落回复的网络等待上界
    public static let totalSeconds: TimeInterval = 45
    /// 工具阶段封顶（秒）：≤4 轮工具往返合计不许超过它
    public static let toolPhaseSeconds: TimeInterval = 27
    /// 意图腿封顶（秒）：意图 JSON 小请求，8 秒足够，超时落规则兜底
    public static let intentSeconds: TimeInterval = 8
    /// 单请求既有上限（秒）：v5.7 以前每腿的固定超时，保留为天花板
    public static let perRequestSeconds: TimeInterval = 30

    /// 工具阶段再起一轮的可用秒数：min(单请求上限, 工具阶段剩余,
    /// 总剩余)；任一剩余 ≤0 返回 nil（不再起新一轮）。
    /// - elapsedTotal: 提问至今总耗时
    /// - elapsedToolPhase: 工具阶段至今耗时（阶段开始时清零计）
    public static func toolRoundTimeout(
        elapsedTotal: TimeInterval, elapsedToolPhase: TimeInterval
    ) -> TimeInterval? {
        let budget = min(
            perRequestSeconds,
            toolPhaseSeconds - elapsedToolPhase,
            totalSeconds - elapsedTotal
        )
        return budget > 0 ? budget : nil
    }

    /// 意图腿可用秒数：min(意图封顶, 总剩余)；总剩余 ≤0 返回 nil
    public static func intentTimeout(elapsedTotal: TimeInterval) -> TimeInterval? {
        let budget = min(intentSeconds, totalSeconds - elapsedTotal)
        return budget > 0 ? budget : nil
    }

    /// 通用 lane 可用秒数：总剩余（它前面两段都有封顶，最坏情形下
    /// 仍剩 totalSeconds − toolPhaseSeconds − intentSeconds＝10 秒）；
    /// 总剩余 ≤0 返回 nil
    public static func generalTimeout(elapsedTotal: TimeInterval) -> TimeInterval? {
        let budget = totalSeconds - elapsedTotal
        return budget > 0 ? budget : nil
    }
}
