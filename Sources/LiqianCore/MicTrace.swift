import Foundation

/// 麦克风启动面包屑（v5.4.1 取证）：语音链路的每一步落一个持久化标记，
/// 万一在某一步闪退，下次打开 App 时标记还停在那一步——AI 管家设置页
/// 底部的「语音诊断」行会把它显示出来，定位不再靠猜。
///
/// 设计约束（不许引入新崩溃面）：
/// - 只用 UserDefaults 同步写：set 后立即 synchronize()，保证进程被杀前
///   标记已落盘（面包屑的全部意义就在崩溃后还能读到）；
/// - 纯字符串拼装，无任何可失败的 IO/解包；
/// - 会话正常结束（stop/录完）必须 close()，否则设置页会误报诊断行。
public enum MicTrace {
    /// 最新一步的标记文本（步号＋名称＋详情＋时间）
    public static let entryKey = "micTrace"
    /// 会话是否未正常结束（true = 上次语音流程中途没了，多半是闪退）
    public static let sessionOpenKey = "micTraceOpen"

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// 落一步标记：覆盖最新步、会话置为未结束。
    public static func mark(
        step: Int, _ name: String, detail: String = "",
        defaults: UserDefaults = .standard, now: Date = Date()
    ) {
        var text = "#\(step) \(name)"
        if !detail.isEmpty { text += "｜\(detail)" }
        text += "｜\(timeFormatter.string(from: now))"
        defaults.set(text, forKey: entryKey)
        defaults.set(true, forKey: sessionOpenKey)
        defaults.synchronize()
    }

    /// 会话正常结束：清未结束旗，最新步改记结束原因。
    public static func close(
        reason: String,
        defaults: UserDefaults = .standard, now: Date = Date()
    ) {
        defaults.set(
            "已结束｜\(reason)｜\(timeFormatter.string(from: now))",
            forKey: entryKey
        )
        defaults.set(false, forKey: sessionOpenKey)
        defaults.synchronize()
    }

    /// 设置页诊断行文案：上次会话未正常结束时返回「停在哪一步」，
    /// 正常结束或从未用过语音时返回 nil（设置页据此决定显不显示）。
    public static func unclosedSummary(defaults: UserDefaults = .standard) -> String? {
        guard defaults.bool(forKey: sessionOpenKey),
              let entry = defaults.string(forKey: entryKey),
              !entry.isEmpty
        else { return nil }
        return "上次用麦克风时，流程停在 \(entry)，没能正常走完。"
    }
}
