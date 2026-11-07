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

    // 与 Palette v3 同步（纸白打底、墨色中性化，朱砂不变）
    static let paper = dyn(0xFAF9F6, 0x171716)
    static let ink = dyn(0x262520, 0xEBE9E3)
    static let stone = dyn(0x6F6C64, 0xA6A29A)
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
    if cents % 100 == 0 { return "¥\(cents / 100)" }
    return String(format: "¥%.2f", Double(cents) / 100.0)
}

struct PendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PendingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("待回礼")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WPalette.primary)
            if entry.hasData {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.count)")
                        .font(.system(size: family == .systemMedium ? 40 : 34, weight: .bold, design: .serif))
                        .foregroundStyle(WPalette.ink)
                    Text("人还没回")
                        .font(.system(size: 13))
                        .foregroundStyle(WPalette.stone)
                }
                Text("共 \(fmtMoney(cents: entry.amountCents))")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(WPalette.ink)
                if !entry.topName.isEmpty {
                    Text("最多的是 \(entry.topName)")
                        .font(.system(size: 12))
                        .foregroundStyle(WPalette.stone)
                        .lineLimit(1)
                }
                if family == .systemMedium {
                    Text("点一下打开，记一笔新的")
                        .font(.system(size: 12))
                        .foregroundStyle(WPalette.stone)
                }
            } else {
                Text("打开礼钱账本\n查看待回礼")
                    .font(.system(size: 14))
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
        .description("还没回的礼，一眼看清。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
