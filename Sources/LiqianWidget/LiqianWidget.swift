import SwiftUI
import UIKit
import WidgetKit
import LiqianCore

// MARK: - 待回礼速览小组件
// 数据来自 App 侧 WidgetSummaryWriter 写入 App Group 的 "pendingSummary"。
//
// 单点化口径（v4.4）：
// - 金额格式已收敛：直接用 LiqianCore 的 LedgerMath.fmtMoney（本 target
//   本就链接 LiqianCore），本文件不再自带一份实现，口径永不漂移。
// - 色值仍为镜像常量、未收敛到 LiqianDesign.Palette，原因有二：① Palette 的
//   界面令牌是「主题令牌表」驱动的——解析时读 App 进程的 UserDefaults
//   （AppTheme.current），小组件扩展进程读不到 App 的主题设置，硬接只会
//   恒定回到白天主题，反而错版；② 本 target 未链接 LiqianDesign（其
//   Components 还依赖模型层），为两个色值引入整包不划算。镜像值与
//   AppTheme 白天/夜晚两套 primary 定值保持一致（A62B1F / D96A5C），
//   改品牌色时两处同改——这是保留的唯一手工同步点。

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

/// 金额格式（v4.4 单点化）：直接用 LiqianCore 的定版实现，不再本地复刻
private func fmtMoney(cents: Int) -> String {
    LedgerMath.fmtMoney(cents: cents)
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
