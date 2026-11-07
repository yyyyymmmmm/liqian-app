import SwiftUI
import UIKit
import WidgetKit
import LiqianCore

// MARK: - 共享底座：色板 / 快照镜像 / 时间线供给
// 数据来自 App 侧 WidgetSummaryWriter 写入 App Group 的 "pendingSummary"。
// 色值在本 target 按 docs/DESIGN.md 令牌重声明（浅/深两套），不依赖 LiqianDesign。

enum WPalette {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }))
    }

    // 与 App 同步（PRO-AUDIT-2 §3.1/§3.2）：背景走系统分组底；primary 为品牌值；
    // ink/stone 走系统语义色；金额/计数一律 sans（衬线只留 App 内 moment）
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let ink = Color.primary
    static let stone = Color.secondary
    static let primary = dyn(0xA62B1F, 0xD96A5C)
    /// 朱砂实底（记一笔按钮）：深色模式同品牌提亮值，保证白字对比
    static let primaryFill = dyn(0xA62B1F, 0xB8452F)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

/// 与 App 侧 WidgetSummaryWriter.PendingSummary 镜像的解码结构（改字段两边同步）。
/// v4.5 扩展字段全部可选：旧快照（老版本 App 写的）解码为 nil，视图降级旧版式。
struct WPendingPerson: Codable {
    var name: String
    var pendingCents: Int
}

struct WNextReminder: Codable {
    var title: String
    var person: String
    var occurrence: Date
}

struct WPendingSummary: Codable {
    var pendingCount: Int
    var pendingAmountCents: Int
    var topName: String
    var updatedAt: Date
    var pendingTop: [WPendingPerson]?
    var monthReceivedCents: Int?
    var monthGivenCents: Int?
    var nextReminder: WNextReminder?
}

/// 两个桌面组件共用同一条时间线条目（都只读同一份快照）。
struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WPendingSummary?
    /// 组件库预览用的示例数据（真实快照缺失且处于预览上下文时才出现，
    /// 视图会打「示例」标，绝不冒充真实数据）
    let isDemo: Bool

    var hasData: Bool { summary != nil }

    static let empty = SummaryEntry(date: Date(), summary: nil, isDemo: false)

    static var demo: SummaryEntry {
        let cal = Calendar.current
        let occurrence = cal.date(
            byAdding: .day, value: 12, to: cal.startOfDay(for: Date())
        ) ?? Date()
        return SummaryEntry(
            date: Date(),
            summary: WPendingSummary(
                pendingCount: 3,
                pendingAmountCents: 160_000,
                topName: "王小明",
                updatedAt: Date(),
                pendingTop: [
                    WPendingPerson(name: "王小明", pendingCents: 80_000),
                    WPendingPerson(name: "李小红", pendingCents: 50_000),
                    WPendingPerson(name: "张大舅", pendingCents: 30_000),
                ],
                monthReceivedCents: 240_000,
                monthGivenCents: 90_000,
                nextReminder: WNextReminder(
                    title: "妈妈的生日", person: "妈妈", occurrence: occurrence
                )
            ),
            isDemo: true
        )
    }
}

/// 快照读取：App Group 不通（重签剥组）或 App 还没写过时返回 nil → 空态引导。
enum SummaryStore {
    static let suiteName = "group.site.didichou.liqian"
    static let summaryKey = "pendingSummary"

    static func load() -> WPendingSummary? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: summaryKey),
              let summary = try? JSONDecoder().decode(WPendingSummary.self, from: data)
        else { return nil }
        return summary
    }

    static func entry(isPreview: Bool) -> SummaryEntry {
        if let summary = load() {
            return SummaryEntry(date: Date(), summary: summary, isDemo: false)
        }
        // 组件库预览给示例（带示例标）；真实桌面没数据只给空态，不编数据
        return isPreview ? .demo : .empty
    }

    static func timeline() -> Timeline<SummaryEntry> {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return Timeline(entries: [entry(isPreview: false)], policy: .after(next))
    }
}

struct PendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .empty }
    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryStore.entry(isPreview: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        completion(SummaryStore.timeline())
    }
}

struct ReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .empty }
    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryStore.entry(isPreview: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        completion(SummaryStore.timeline())
    }
}

/// 金额格式单点化（v4.4 打磨口径，合并时从旧单体文件移植）：直接调
/// LiqianCore 的 LedgerMath.fmtMoney（本 target 本就链接 LiqianCore），
/// 不再自带复刻实现，口径永不漂移。
/// 色值未单点化的原因（同口径）：Palette 令牌解析时读 App 进程的
/// UserDefaults 主题设置，扩展进程读不到、硬接会恒回白天主题；且本
/// target 未链接 LiqianDesign。WPalette 镜像值与 App 白天/夜晚定值
/// 保持一致，改品牌色时两处同改——保留的唯一手工同步点。
func fmtMoney(cents: Int) -> String {
    LedgerMath.fmtMoney(cents: cents)
}

/// 示例角标：只在组件库预览的示例数据上出现
struct DemoTag: View {
    var body: some View {
        Text("示例")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WPalette.stone)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(WPalette.stone.opacity(0.15), in: Capsule())
    }
}
