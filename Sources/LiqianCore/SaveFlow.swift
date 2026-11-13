import Foundation

/// 保存反馈分发（v5.14.1）：「执行保存 → 按成败分发反馈」的纯逻辑。
///
/// 背景（审计 A5）：旧全链是 `try? save()` ＋成功反馈无条件触发——
/// save 间歇失败时记录从未落盘，用户却看到落印/关页/报数齐全的
/// 「成功」。本函数的契约只有一条：**onSuccess 只在 save 真成功后
/// 调用，失败必走 onFailure**；App 侧 SaveSupport 在此之上接真
/// ModelContext、记日志、出人话文案。纯闭包注入，单测可钉死。
public enum SaveFlow {
    /// 保存失败时用户看到的统一提示（人话定版，各入口共用一处）：
    /// 不提技术原因，只说清两件事——没存上、内容还在、可以再试。
    public static let failureMessage = "没存上，再试一次；内容都还在，没有丢。"

    /// 执行保存并按结果分发反馈；返回是否成功。
    @discardableResult
    public static func run(
        save: () throws -> Void,
        onSuccess: () -> Void = {},
        onFailure: (Error) -> Void = { _ in }
    ) -> Bool {
        do {
            try save()
        } catch {
            onFailure(error)
            return false
        }
        onSuccess()
        return true
    }
}
