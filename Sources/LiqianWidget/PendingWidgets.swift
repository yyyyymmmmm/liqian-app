import SwiftUI
import WidgetKit
import LiqianCore

// MARK: - 待回礼组件（桌面三尺寸＋锁屏两款）
// kind 沿用 "LiqianWidget"，老版本已摆到桌面的组件原地升级。
// 金额一律 .privacySensitive()：组件出现在锁屏/遮蔽场景时系统自动打码。

struct PendingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiqianWidget", provider: PendingProvider()) { entry in
            PendingWidgetView(entry: entry)
        }
        .configurationDisplayName("待回礼")
        .description("待回礼汇总、名单与本月往来")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular,
        ])
    }
}

struct PendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    var body: some View {
        switch family {
        case .systemMedium:
            PendingMediumView(entry: entry)
        case .systemLarge:
            PendingLargeView(entry: entry)
        case .accessoryCircular:
            PendingCircularView(entry: entry)
        case .accessoryRectangular:
            PendingRectangularView(entry: entry)
        default:
            PendingSmallView(entry: entry)
        }
    }
}

// MARK: 小尺寸：总览（人数＋总金额＋待回最多一位）

private struct PendingSmallView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("待回礼")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WPalette.primary)
                if entry.isDemo { DemoTag() }
                Spacer(minLength: 0)
            }
            if let s = entry.summary {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(s.pendingCount)")
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundStyle(WPalette.ink)
                    Text("人待回礼")
                        .font(.footnote)
                        .foregroundStyle(WPalette.stone)
                }
                Text("共 \(fmtMoney(cents: s.pendingAmountCents))")
                    .font(.system(.callout, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WPalette.ink)
                    .privacySensitive()
                if !s.topName.isEmpty {
                    Text("最多的是 \(s.topName)")
                        .font(.caption)
                        .foregroundStyle(WPalette.stone)
                        .lineLimit(1)
                }
            } else {
                Text("打开礼记\n查看待回礼")
                    .font(.subheadline)
                    .foregroundStyle(WPalette.ink)
                    .lineSpacing(4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .widgetURL(URL(string: "liqian://quick-record"))
        .containerBackground(WPalette.paper, for: .widget)
    }
}

// MARK: 中尺寸：前 3 人列表（点行直达人物）＋记一笔真按钮

private struct PendingMediumView: View {
    let entry: SummaryEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("待回礼")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WPalette.primary)
                    if let s = entry.summary {
                        Text("\(s.pendingCount) 人")
                            .font(.footnote)
                            .foregroundStyle(WPalette.stone)
                    }
                    if entry.isDemo { DemoTag() }
                    Spacer(minLength: 0)
                }
                if let s = entry.summary, let top = s.pendingTop, !top.isEmpty {
                    ForEach(Array(top.prefix(3).enumerated()), id: \.offset) { _, person in
                        pendingRow(person)
                    }
                } else if entry.hasData {
                    Text("暂无待回礼，账都清了")
                        .font(.subheadline)
                        .foregroundStyle(WPalette.ink)
                        .padding(.top, 4)
                } else {
                    Text("打开礼记\n查看待回礼")
                        .font(.subheadline)
                        .foregroundStyle(WPalette.ink)
                        .lineSpacing(4)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                Spacer(minLength: 0)
                Button(intent: OpenQuickRecordIntent()) {
                    Label("记一笔", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(WPalette.primaryFill, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .containerBackground(WPalette.paper, for: .widget)
    }

    @ViewBuilder
    private func pendingRow(_ person: WPendingPerson) -> some View {
        let row = HStack(spacing: 6) {
            Text(person.name)
                .font(.subheadline)
                .foregroundStyle(WPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(fmtMoney(cents: person.pendingCents))
                .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(WPalette.ink)
                .privacySensitive()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        if entry.isDemo {
            row // 示例行不挂深链（名字是编的，点了也找不到人）
        } else {
            Link(destination: URL(string: LiqianDeepLink.personURL(name: person.name))!) {
                row
            }
        }
    }
}

// MARK: 大尺寸：名单前 5＋本月收/送概览＋下一个重要日子

private struct PendingLargeView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("待回礼")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WPalette.primary)
                if let s = entry.summary {
                    Text("共 \(s.pendingCount) 人 · \(fmtMoney(cents: s.pendingAmountCents))")
                        .font(.footnote)
                        .foregroundStyle(WPalette.stone)
                        .privacySensitive()
                }
                if entry.isDemo { DemoTag() }
                Spacer(minLength: 0)
            }
            if let s = entry.summary, let top = s.pendingTop, !top.isEmpty {
                ForEach(Array(top.prefix(5).enumerated()), id: \.offset) { _, person in
                    pendingRow(person)
                }
            } else if entry.hasData {
                Text("暂无待回礼，账都清了")
                    .font(.subheadline)
                    .foregroundStyle(WPalette.ink)
                    .padding(.top, 2)
            } else {
                Text("打开礼记查看待回礼")
                    .font(.subheadline)
                    .foregroundStyle(WPalette.ink)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if let s = entry.summary {
                Divider()
                HStack(spacing: 16) {
                    monthBlock("本月收礼", cents: s.monthReceivedCents)
                    monthBlock("本月送礼", cents: s.monthGivenCents)
                    Spacer(minLength: 0)
                }
                if let next = s.nextReminder {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(WPalette.primary)
                        Text("\(next.title) · \(ReminderText.daysText(until: next.occurrence))")
                            .font(.caption)
                            .foregroundStyle(WPalette.stone)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .containerBackground(WPalette.paper, for: .widget)
    }

    @ViewBuilder
    private func pendingRow(_ person: WPendingPerson) -> some View {
        let row = HStack(spacing: 6) {
            Text(person.name)
                .font(.callout)
                .foregroundStyle(WPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(fmtMoney(cents: person.pendingCents))
                .font(.system(.callout, weight: .semibold).monospacedDigit())
                .foregroundStyle(WPalette.ink)
                .privacySensitive()
        }
        .contentShape(Rectangle())
        if entry.isDemo {
            row
        } else {
            Link(destination: URL(string: LiqianDeepLink.personURL(name: person.name))!) {
                row
            }
        }
    }

    @ViewBuilder
    private func monthBlock(_ label: String, cents: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(WPalette.stone)
            Text(cents.map { fmtMoney(cents: $0) } ?? "—")
                .font(.system(.headline, weight: .semibold).monospacedDigit())
                .foregroundStyle(WPalette.ink)
                .privacySensitive()
        }
    }
}

// MARK: 锁屏·圆形：待回人数

private struct PendingCircularView: View {
    let entry: SummaryEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let s = entry.summary {
                VStack(spacing: -1) {
                    Text("\(s.pendingCount)")
                        .font(.system(.title2, weight: .bold))
                        .minimumScaleFactor(0.6)
                    Text("待回")
                        .font(.caption2)
                }
            } else {
                Text("礼")
                    .font(.system(.title3, weight: .bold))
            }
        }
        .widgetURL(topPersonURL)
    }

    private var topPersonURL: URL? {
        guard let s = entry.summary, !entry.isDemo, !s.topName.isEmpty else { return nil }
        return URL(string: LiqianDeepLink.personURL(name: s.topName))
    }
}

// MARK: 锁屏·矩形：最近（待回最多）一位＋金额

private struct PendingRectangularView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let s = entry.summary {
                Text("待回礼 \(s.pendingCount) 人")
                    .font(.headline)
                    .lineLimit(1)
                if let top = s.pendingTop?.first {
                    Text("\(top.name) \(fmtMoney(cents: top.pendingCents))")
                        .font(.subheadline)
                        .lineLimit(1)
                        .privacySensitive()
                } else if !s.topName.isEmpty {
                    Text(s.topName)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text("暂无待回礼")
                        .font(.subheadline)
                }
            } else {
                Text("待回礼")
                    .font(.headline)
                Text("打开礼记查看")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(topPersonURL)
    }

    private var topPersonURL: URL? {
        guard let s = entry.summary, !entry.isDemo, !s.topName.isEmpty else { return nil }
        return URL(string: LiqianDeepLink.personURL(name: s.topName))
    }
}
