import Foundation

/// 评分引导（v4.5）：只在正向时刻出现一次性的系统评分请求，其余时间彻底沉默。
/// 触发点唯一：礼谱 PDF 生成成功后（LibuExportView 调用），且同时满足——
/// - 累计真实记录（排除示例账本）≥ minRecords 笔：用得够深才开口；
/// - 距上次请求 ≥ minIntervalDays 天：系统本身也会节流，这里再加一道自己的账。
/// 失败/错误路径永远不调用本工具，About 页也不放任何诱导评分的文案。
enum ReviewPrompt {
    static let lastRequestAtKey = "lastReviewRequestAt"
    static let minRecords = 20
    static let minIntervalDays = 120

    static func shouldRequest(
        totalRecords: Int,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard totalRecords >= minRecords else { return false }
        let last = defaults.double(forKey: lastRequestAtKey)
        guard last > 0 else { return true }
        let days = Calendar.current.dateComponents(
            [.day], from: Date(timeIntervalSince1970: last), to: now
        ).day ?? 0
        return days >= minIntervalDays
    }

    static func markRequested(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: lastRequestAtKey)
    }
}
