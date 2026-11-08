import SwiftUI
import WidgetKit
import LiqianCore

// MARK: - 待回礼组件（桌面三尺寸＋锁屏两款）
// kind 沿用 "LiqianWidget"，老版本已摆到桌面的组件原地升级。
// v5.1 按专业组件信息架构重排（调研见 docs/V51-NOTES.md）：
// 小＝英雄数（待回总额）＋支撑行（人数）＋第一待回人＋新鲜度；
// 中＝左英雄区＋右前三名逐行直达；大＝本月收/送顶栏＋待回前三＋下一场条
// ＋底部记一笔真按钮；锁屏圆形＝待回人数仪表、矩形＝总额＋第一待回人。
// 整卡点按落 liqian://pending（待回页，与快捷菜单「查看待回礼」同落点），
// 点人走 liqian://person 直达——深链分层与 HIG「deep link to the right
// location」一致。金额一律 .privacySensitive()：组件出现在锁屏/遮蔽场景
// 时系统自动打码。

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
        if entry.isPlaceholder {
            WidgetSkeletonView()
        } else {
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
}

/// 待回页整卡落点（锁屏两款沿用各自的人物直达，不走这里）
private var pendingPageURL: URL? { URL(string: LiqianDeepLink.pendingURL()) }

/// 待回逐人行（中/大共用）：姓名＋收向带符号金额（朱砂），点行直达该人；
/// 示例行不挂深链（名字是编的，点了也找不到人）
@ViewBuilder
private func pendingPersonRow(
    _ person: WPendingPerson, isDemo: Bool, font: Font.TextStyle
) -> some View {
    let row = HStack(spacing: 6) {
        Text(person.name)
            .font(.system(font))
            .foregroundStyle(WPalette.ink)
            .lineLimit(1)
        Spacer(minLength: 4)
        Text(signedMoneyText(cents: person.pendingCents, direction: LiqianConstants.received))
            .font(.system(font, weight: .semibold).monospacedDigit())
            .foregroundStyle(WPalette.primary)
            .privacySensitive()
    }
    .contentShape(Rectangle())
    if isDemo {
        row
    } else {
        Link(destination: URL(string: LiqianDeepLink.personURL(name: person.name))!) {
            row
        }
    }
}

/// 卡头：组件名＋示例标（各尺寸共用，保证语义与 App 内一致）
private struct WidgetHeader: View {
    let title: String
    let isDemo: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WPalette.primary)
            if isDemo { DemoTag() }
            Spacer(minLength: 0)
        }
    }
}

/// 无快照（App Group 未通/App 还没写过）的引导空态：不编数据，指条明路
private struct WidgetNoDataView: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WPalette.ink)
            Text(hint)
                .font(.caption)
                .foregroundStyle(WPalette.stone)
                .lineSpacing(3)
        }
    }
}

// MARK: 小尺寸：英雄数＝待回总额，支撑＝人数，第一待回人＋新鲜度

private struct PendingSmallView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(title: "待回礼", isDemo: entry.isDemo)
            if let s = entry.summary {
                if s.pendingCount > 0 {
                    Text(fmtMoney(cents: s.pendingAmountCents))
                        .font(.system(.title, weight: .bold).monospacedDigit())
                        .foregroundStyle(WPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .privacySensitive()
                    Text("共 \(s.pendingCount) 人待回")
                        .font(.footnote)
                        .foregroundStyle(WPalette.stone)
                    if let top = s.pendingTop?.first {
                        Divider()
                        pendingPersonRow(top, isDemo: entry.isDemo, font: .subheadline)
                    } else if !s.topName.isEmpty {
                        Text("最多的是 \(s.topName)")
                            .font(.caption)
                            .foregroundStyle(WPalette.stone)
                            .lineLimit(1)
                    }
                } else {
                    clearedBody(s)
                }
                Spacer(minLength: 0)
                Text(WidgetText.freshness(s.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(WPalette.stone)
            } else {
                WidgetNoDataView(title: "打开礼记", hint: "记下第一笔人情，\n待回礼会汇总到这里")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .widgetURL(pendingPageURL)
        .containerBackground(WPalette.paper, for: .widget)
    }

    /// 暂无人待回的体面空态：不是空白，是「账清了」的结论＋本月收一笔支撑数
    private func clearedBody(_ s: WPendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(WPalette.primary)
                Text("暂无人情待回")
                    .font(.headline)
                    .foregroundStyle(WPalette.ink)
            }
            Text("收送都对上了")
                .font(.footnote)
                .foregroundStyle(WPalette.stone)
            if let received = s.monthReceivedCents {
                Text("本月收 \(signedMoneyText(cents: received, direction: LiqianConstants.received))")
                    .font(.caption)
                    .foregroundStyle(WPalette.stone)
                    .privacySensitive()
            }
        }
    }
}

// MARK: 中尺寸：左英雄区（总额＋人数）＋右前三名逐行直达

private struct PendingMediumView: View {
    let entry: SummaryEntry

    var body: some View {
        HStack(spacing: 14) {
            hero
                .frame(width: 118, alignment: .leading)
            Divider()
            list
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .widgetURL(pendingPageURL)
        .containerBackground(WPalette.paper, for: .widget)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(title: "待回礼", isDemo: entry.isDemo)
            if let s = entry.summary {
                if s.pendingCount > 0 {
                    Text(fmtMoney(cents: s.pendingAmountCents))
                        .font(.system(.title3, weight: .bold).monospacedDigit())
                        .foregroundStyle(WPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                    Text("\(s.pendingCount) 人待回")
                        .font(.footnote)
                        .foregroundStyle(WPalette.stone)
                } else {
                    Text("暂无人情待回")
                        .font(.headline)
                        .foregroundStyle(WPalette.ink)
                    Text("账都清了")
                        .font(.footnote)
                        .foregroundStyle(WPalette.stone)
                }
                Spacer(minLength: 0)
                Text(WidgetText.freshness(s.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(WPalette.stone)
            } else {
                Text("打开礼记查看")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WPalette.ink)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if let s = entry.summary, s.pendingCount > 0, let top = s.pendingTop, !top.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(top.prefix(3).enumerated()), id: \.offset) { _, person in
                    pendingPersonRow(person, isDemo: entry.isDemo, font: .subheadline)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        } else if let s = entry.summary {
            // 无待回时右列给本月收/送，不留空
            VStack(alignment: .leading, spacing: 7) {
                monthLine("本月收礼", cents: s.monthReceivedCents, direction: LiqianConstants.received)
                monthLine("本月送礼", cents: s.monthGivenCents, direction: LiqianConstants.given)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("待回名单会列在这里")
                    .font(.subheadline)
                    .foregroundStyle(WPalette.stone)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private func monthLine(_ label: String, cents: Int?, direction: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(WPalette.stone)
            Spacer(minLength: 4)
            Text(cents.map { signedMoneyText(cents: $0, direction: direction) } ?? "—")
                .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(direction == LiqianConstants.received ? WPalette.primary : WPalette.moneyGiven)
                .privacySensitive()
        }
    }
}

// MARK: 大尺寸：迷你仪表盘——本月收/送顶栏＋待回前三＋下一场条＋记一笔

private struct PendingLargeView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = entry.summary {
                monthBand(s)
                Divider()
                pendingHeader(s)
                if let top = s.pendingTop, !top.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(Array(top.prefix(3).enumerated()), id: \.offset) { _, person in
                            pendingPersonRow(person, isDemo: entry.isDemo, font: .callout)
                        }
                    }
                } else {
                    Text("暂无人情待回，账都清了")
                        .font(.subheadline)
                        .foregroundStyle(WPalette.stone)
                }
                Divider()
                nextEventStrip(s)
                Spacer(minLength: 0)
                quickRecordButton
            } else {
                WidgetHeader(title: "待回礼", isDemo: entry.isDemo)
                WidgetNoDataView(title: "打开礼记", hint: "记下第一笔人情，待回汇总、本月收送和下一个重要日子会汇总到这里")
                Spacer(minLength: 0)
                quickRecordButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .widgetURL(pendingPageURL)
        .containerBackground(WPalette.paper, for: .widget)
    }

    /// 顶栏：本月收/送两块并排，符号＋语义双色齐全
    private func monthBand(_ s: WPendingSummary) -> some View {
        HStack(spacing: 16) {
            monthBlock("本月收礼", cents: s.monthReceivedCents, direction: LiqianConstants.received)
            monthBlock("本月送礼", cents: s.monthGivenCents, direction: LiqianConstants.given)
            Spacer(minLength: 0)
            if entry.isDemo { DemoTag() }
        }
    }

    private func monthBlock(_ label: String, cents: Int?, direction: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(WPalette.stone)
            Text(cents.map { signedMoneyText(cents: $0, direction: direction) } ?? "—")
                .font(.system(.headline, weight: .semibold).monospacedDigit())
                .foregroundStyle(direction == LiqianConstants.received ? WPalette.primary : WPalette.moneyGiven)
                .privacySensitive()
        }
    }

    /// 待回区头：左标题＋人数，右总额（这一区的英雄数）
    private func pendingHeader(_ s: WPendingSummary) -> some View {
        HStack(spacing: 6) {
            Text("待回礼")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WPalette.primary)
            if s.pendingCount > 0 {
                Text("\(s.pendingCount) 人")
                    .font(.footnote)
                    .foregroundStyle(WPalette.stone)
            }
            Spacer(minLength: 4)
            if s.pendingCount > 0 {
                Text(fmtMoney(cents: s.pendingAmountCents))
                    .font(.system(.headline, weight: .bold).monospacedDigit())
                    .foregroundStyle(WPalette.ink)
                    .privacySensitive()
            }
        }
    }

    /// 下一场条：与首页倒计时卡、倒计时组件同一份快照字段（nextReminder），
    /// 天数在视图里按今天现算，不另算一套
    private func nextEventStrip(_ s: WPendingSummary) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar.badge.clock")
                .font(.caption)
                .foregroundStyle(WPalette.primary)
            if let next = s.nextReminder {
                Text("\(next.title) · \(ReminderText.daysText(until: next.occurrence)) · \(ReminderText.dateText(next.occurrence))")
                    .font(.caption)
                    .foregroundStyle(WPalette.stone)
                    .lineLimit(1)
            } else {
                Text("近期没有重要日子")
                    .font(.caption)
                    .foregroundStyle(WPalette.stone)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(WidgetText.freshness(s.updatedAt))
                .font(.caption2)
                .foregroundStyle(WPalette.stone)
        }
    }

    /// 记一笔真按钮：沿用既有 AppIntent（落标记＋唤起 App 弹表单），不是深链假按钮
    private var quickRecordButton: some View {
        Button(intent: OpenQuickRecordIntent()) {
            Label("记一笔", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(WPalette.primaryFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: 锁屏·圆形：待回人数仪表
// 环形进口径（v5.1 定版）：待回人数 ÷ 全部往来人数——「往来的人里还有
// 几成的人情没回」；分母来自快照 peopleCount，旧快照缺失时降级无环版式。

private struct PendingCircularView: View {
    let entry: SummaryEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let s = entry.summary {
                if let fraction = WidgetText.pendingFraction(
                    count: s.pendingCount, peopleCount: s.peopleCount
                ) {
                    Gauge(value: fraction) {
                        Text("待回")
                    } currentValueLabel: {
                        VStack(spacing: -1) {
                            Text("\(s.pendingCount)")
                                .font(.system(.title2, weight: .bold))
                                .minimumScaleFactor(0.6)
                            Text("待回")
                                .font(.caption2)
                        }
                    }
                    .gaugeStyle(.accessoryCircular)
                } else {
                    VStack(spacing: -1) {
                        Text("\(s.pendingCount)")
                            .font(.system(.title2, weight: .bold))
                            .minimumScaleFactor(0.6)
                        Text("待回")
                            .font(.caption2)
                    }
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

// MARK: 锁屏·矩形：待回总额一行＋第一待回人一行
// 隐私口径与现状一致：金额只出现在矩形内这两行、且全部挂
// .privacySensitive()（锁定/遮蔽时系统打码）；第一行由旧版「N 人」改为
// 待回总额属本次版式定版，第二行维持现状（姓名＋其待回额）。

private struct PendingRectangularView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let s = entry.summary {
                HStack(spacing: 5) {
                    Text("待回礼")
                        .font(.headline)
                    Text(fmtMoney(cents: s.pendingAmountCents))
                        .font(.system(.headline, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .privacySensitive()
                }
                if s.pendingCount == 0 {
                    Text("暂无人情待回")
                        .font(.subheadline)
                } else if let top = s.pendingTop?.first {
                    Text("\(top.name) \(signedMoneyText(cents: top.pendingCents, direction: LiqianConstants.received))")
                        .font(.subheadline)
                        .lineLimit(1)
                        .privacySensitive()
                } else if !s.topName.isEmpty {
                    Text(s.topName)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text("\(s.pendingCount) 人待回")
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
