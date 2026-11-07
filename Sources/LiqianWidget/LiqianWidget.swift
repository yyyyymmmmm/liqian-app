import SwiftUI
import UIKit
import WidgetKit

// MARK: - 待回礼速览小组件
// 数据来自 App 侧 WidgetSummaryWriter 写入 App Group 的 "pendingSummary"。
// 色值直接在本文件按 docs/DESIGN.md 令牌重声明（浅/深两套），不依赖 LiqianDesign。

private enum WPalette {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? WUIColor(hex: dark) : WUIColor(hex: light)
        }))
    }

    // 与 App 同步（PRO-AUDIT-2 §3.1/§3.2）：背景走系统分组底；primary 为品牌值；
    // ink/stone 与 App 同口径走系统语义色；金额/计数一律 sans（衬线只留 App 内 moment）
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let ink = Color.primary
    static let stone = Color.secondary
    static let primary = dyn(0xA62B1F, 0xD96A5C)
}

private typealias WUIColor = UIColor

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

/// 与 App 侧 WidgetSummaryWriter.PendingSummary 镜像的解码结构（改字段两边同步）
private struct PendingSummary: Codable {
    var pendingCount: Int
    var pendingAmountCents: Int
    var topName: String
    var updatedAt: Date
}

struct PendingEntry: TimelineEntry {
    let date: Date
    let count: Int
    let amountCents: Int
    let topName: String
    /// 读到了 App 写的数据（false 显示占位文案）
    let hasData: Bool

    static let placeholder = PendingEntry(
        date: Date(), count: 0, amountCents: 0, topName: "", hasData: false
    )
}

struct Provider: TimelineProvider {
    private static let suiteName = "group.site.didichou.liqian"
    private static let summaryKey = "pendingSummary"

    func placeholder(in context: Context) -> PendingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (PendingEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PendingEntry>) -> Void) {
        let entry = load()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> PendingEntry {
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              let data = defaults.data(forKey: Self.summaryKey),
              let summary = try? JSONDecoder().decode(PendingSummary.self, from: data)
        else { return .placeholder }
        return PendingEntry(
            date: Date(),
            count: summary.pendingCount,
            amountCents: summary.pendingAmountCents,
            topName: summary.topName,
            hasData: true
        )
    }
}

/// 金额格式与 App 内 LedgerMath.fmtMoney 同口径（整数不带小数）
private func fmtMoney(cents: Int) -> String {
    let sign = cents < 0 ? "-" : ""
    let absCents = abs(cents)
    let yuan = absCents / 100
    let rem = absCents % 100
    var head = String(yuan)
    var grouped = ""
    while head.count > 3 {
        grouped = "," + head.suffix(3) + grouped
        head = String(head.dropLast(3))
    }
    grouped = head + grouped
    if rem == 0 { return "¥\(sign)\(grouped)" }
    return "¥\(sign)\(grouped).\(rem < 10 ? "0" : "")\(rem)"
}

struct PendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PendingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("待回礼")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WPalette.primary)
            if entry.hasData {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.count)")
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundStyle(WPalette.ink)
                    Text("人待回礼")
                        .font(.footnote)
                        .foregroundStyle(WPalette.stone)
                }
                Text("共 \(fmtMoney(cents: entry.amountCents))")
                    .font(.system(.callout, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WPalette.ink)
                if !entry.topName.isEmpty {
                    Text("最多的是 \(entry.topName)")
                        .font(.caption)
                        .foregroundStyle(WPalette.stone)
                        .lineLimit(1)
                }
                if family == .systemMedium {
                    Text("点按打开，记一笔")
                        .font(.caption)
                        .foregroundStyle(WPalette.stone)
                }
            } else {
                Text("打开礼钱账本\n查看待回礼")
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

@main
struct LiqianWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiqianWidget", provider: Provider()) { entry in
            PendingWidgetView(entry: entry)
        }
        .configurationDisplayName("待回礼")
        .description("待回礼汇总")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
