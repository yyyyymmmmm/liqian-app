import SwiftUI
import WidgetKit
import LiqianCore

// MARK: - 重要日子倒计时组件
// 数据与待回礼共用同一份快照（nextReminder 字段）。剩余天数在视图里按
// 「今天」现算，时间线隔夜刷新前也不会显示昨天的数字。

enum ReminderText {
    /// 距 occurrence（当天 0 点）的整天数；负数按 0（日子已到/已过，快照未刷新）
    static func daysLeft(until occurrence: Date, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: now)
        let to = cal.startOfDay(for: occurrence)
        return max(0, cal.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    static func daysText(until occurrence: Date, now: Date = Date()) -> String {
        let days = daysLeft(until: occurrence, now: now)
        return days == 0 ? "就是今天" : "还有 \(days) 天"
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}

struct ReminderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiqianReminderWidget", provider: ReminderProvider()) { entry in
            ReminderWidgetView(entry: entry)
        }
        .configurationDisplayName("重要日子")
        .description("下一个重要日子倒计时")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ReminderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    private var reminder: WNextReminder? { entry.summary?.nextReminder }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumBody
            } else {
                smallBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .widgetURL(personURL)
        .containerBackground(WPalette.paper, for: .widget)
    }

    private var personURL: URL? {
        guard let r = reminder, !entry.isDemo else { return nil }
        return URL(string: LiqianDeepLink.personURL(name: r.person))
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("重要日子")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WPalette.primary)
                if entry.isDemo { DemoTag() }
                Spacer(minLength: 0)
            }
            if let r = reminder {
                Text(r.title)
                    .font(.headline)
                    .foregroundStyle(WPalette.ink)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    let days = ReminderText.daysLeft(until: r.occurrence)
                    if days == 0 {
                        Text("今天")
                            .font(.system(.largeTitle, weight: .bold))
                            .foregroundStyle(WPalette.primary)
                    } else {
                        Text("\(days)")
                            .font(.system(.largeTitle, weight: .bold))
                            .foregroundStyle(WPalette.ink)
                        Text("天后")
                            .font(.footnote)
                            .foregroundStyle(WPalette.stone)
                    }
                }
                Text(ReminderText.dateText(r.occurrence))
                    .font(.caption)
                    .foregroundStyle(WPalette.stone)
            } else {
                Text("还没有重要日子\n打开礼记添加")
                    .font(.subheadline)
                    .foregroundStyle(WPalette.ink)
                    .lineSpacing(4)
            }
            Spacer(minLength: 0)
        }
    }

    private var mediumBody: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("下一个重要日子")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WPalette.primary)
                    if entry.isDemo { DemoTag() }
                    Spacer(minLength: 0)
                }
                if let r = reminder {
                    Text(r.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WPalette.ink)
                        .lineLimit(2)
                    Text("\(ReminderText.dateText(r.occurrence)) · \(ReminderText.daysText(until: r.occurrence))")
                        .font(.subheadline)
                        .foregroundStyle(WPalette.stone)
                } else {
                    Text("还没有重要日子\n打开礼记添加")
                        .font(.subheadline)
                        .foregroundStyle(WPalette.ink)
                        .lineSpacing(4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let r = reminder {
                VStack(spacing: 0) {
                    let days = ReminderText.daysLeft(until: r.occurrence)
                    Text(days == 0 ? "今天" : "\(days)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(WPalette.ink)
                    if days > 0 {
                        Text("天后")
                            .font(.footnote)
                            .foregroundStyle(WPalette.stone)
                    }
                }
                .frame(minWidth: 64)
            }
        }
    }
}
