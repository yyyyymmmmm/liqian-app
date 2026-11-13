import Foundation

/// 礼簿倒计时（v5.14.1）：距事由日的天数与文案，纯函数单测钉死。
///
/// 口径（用户拍板）：未来显「还有 N 天」、当天显「就是今天」、红事
/// 已过显「已过 N 天」；**白事一律不显**——未来、当天、已过全抑制
/// （丧事讲倒计时不合礼俗）。呈现只两处：礼簿卡副标题与礼簿详情
/// 头部；不进小组件、不进首页倒计时卡（口径见 V5141-NOTES）。
public enum LedgerCountdown {
    /// 距事由日天数：未来为正、当天 0、已过为负；白事恒 nil（不显）
    public static func daysUntil(
        eventDate: String, today: String = LiqianDate.todayString(), isBai: Bool
    ) -> Int? {
        guard !isBai else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let from = cal.startOfDay(for: LiqianDate.date(from: today))
        let to = cal.startOfDay(for: LiqianDate.date(from: eventDate))
        return cal.dateComponents([.day], from: from, to: to).day
    }

    /// 倒计时文案；不显（白事）时返回 nil
    public static func text(
        eventDate: String, today: String = LiqianDate.todayString(), isBai: Bool
    ) -> String? {
        guard let days = daysUntil(eventDate: eventDate, today: today, isBai: isBai)
        else { return nil }
        if days > 0 { return "还有 \(days) 天" }
        if days == 0 { return "就是今天" }
        return "已过 \(-days) 天"
    }
}
