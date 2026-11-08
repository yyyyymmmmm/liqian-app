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
    /// 金额语义双色（v5.1，与 App v5.0.2 MoneyTone 镜像）：收＝主题强调令牌
    /// （默认主题即朱砂，用 primary）；送＝黛青（浅 #14665A / 夜 #4FB3A6，
    /// v5.0.2 五主题对比度实测 ≥4.5:1 的定值）。组件进程读不到 App 的五主题
    /// 设置，恒走默认主题这一对——与既有 WPalette 镜像口径一致（见文件尾注）。
    static let moneyGiven = dyn(0x14665A, 0x4FB3A6)
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
    /// 全部往来人数（v5.1，旧快照为 nil）：锁屏圆形环形进度的分母
    var peopleCount: Int?
}

/// 两个桌面组件共用同一条时间线条目（都只读同一份快照）。
struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WPendingSummary?
    /// 组件库预览用的示例数据（真实快照缺失且处于预览上下文时才出现，
    /// 视图会打「示例」标，绝不冒充真实数据）
    let isDemo: Bool
    /// 系统占位（placeholder(in:)）专用：视图渲染骨架屏，不出文字数据
    var isPlaceholder: Bool = false

    var hasData: Bool { summary != nil }

    static let empty = SummaryEntry(date: Date(), summary: nil, isDemo: false)

    static let placeholder = SummaryEntry(
        date: Date(), summary: nil, isDemo: false, isPlaceholder: true
    )

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
                ),
                peopleCount: 8
            ),
            isDemo: true
        )
    }
}

/// 快照读取：App Group 不通（重签剥组）或 App 还没写过时返回 nil → 空态引导。
enum SummaryStore {
    /// suite 名走 AppGroupResolver（v4.6，与 App 侧 WidgetSummaryWriter 同口径）
    static var suiteName: String { AppGroupResolver.groupID }
    static let summaryKey = "pendingSummary"
    // 回执键：命中哪家就往哪家写回组名＋时间，App 侧自检行据此呈现
    // 「组件实际读到的组名」；键名与 App 侧 WidgetSummaryWriter 镜像，改键两边同步
    static let receiptGroupKey = "widgetReceiptGroup"
    static let receiptAtKey = "widgetReceiptAt"

    /// 多候选读取（v5.11.1）：两侧进程对组名的解析可能不一致（各自 plist
    /// 的 ALTAppGroups 写入情况不同），逐个候选试 suite＋键，命中哪家用
    /// 哪家；App 侧仍只往解析名一家写，不多点群发，避免数据分叉。
    /// 候选首项恒为本进程解析名——通道正常时行为与单组名读完全一致。
    static func load() -> WPendingSummary? {
        for candidate in AppGroupResolver.candidateGroupIDs {
            guard let defaults = UserDefaults(suiteName: candidate),
                  let data = defaults.data(forKey: summaryKey),
                  let summary = try? JSONDecoder().decode(WPendingSummary.self, from: data)
            else { continue }
            defaults.set(candidate, forKey: receiptGroupKey)
            defaults.set(Date().timeIntervalSince1970, forKey: receiptAtKey)
            return summary
        }
        return nil
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
    func placeholder(in context: Context) -> SummaryEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryStore.entry(isPreview: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        completion(SummaryStore.timeline())
    }
}

struct ReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .placeholder }
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

/// 带符号金额（v5.1）：直接调 Core 的 signedMoney，与 App 内 SignedMoneyText
/// 同一口径——收 `+¥N`、送 `−¥N`。组件里的待回金额属收向（对方欠我的人情、
/// 等着回进来），逐笔呈现按 received 带正号；汇总口径差异见 V51-NOTES。
func signedMoneyText(cents: Int, direction: String) -> String {
    LedgerMath.signedMoney(cents: cents, direction: direction)
}

/// 数据新鲜度文案：快照 updatedAt →「今天 14:30 更新」/「11月3日 09:12 更新」。
/// 组件是快照不是实时数，把数据时间摆在面上是专业口径（HIG：timely 之外
/// 还要诚实）——用户一眼能判断这数有多新。
enum WidgetText {
    static func freshness(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return "今天 \(f.string(from: date)) 更新"
        }
        f.dateFormat = "M月d日 HH:mm"
        return "\(f.string(from: date)) 更新"
    }

    /// 锁屏圆形环形进度的口径（v5.1 定版）：待回人数 ÷ 全部往来人数，
    /// 即「往来的人里还有几成的人情没回」。分母缺失（旧快照）或为 0 时
    /// 返回 nil，视图降级为无环版式，绝不编一个比例出来。
    static func pendingFraction(count: Int, peopleCount: Int?) -> Double? {
        guard let total = peopleCount, total > 0 else { return nil }
        return min(1, max(0, Double(count) / Double(total)))
    }
}

/// 占位骨架屏（placeholder 专用）：灰块层级与正式版式同构（大数块＋两行），
/// 系统加载/重签过渡期桌面上不出现空白或假数据。
struct WidgetSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().frame(width: 44, height: 10)
            Capsule().frame(width: 108, height: 26)
            Capsule().frame(width: 72, height: 10)
            Capsule().frame(width: 88, height: 10)
            Spacer(minLength: 0)
        }
        .foregroundStyle(WPalette.stone.opacity(0.3))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
        .redacted(reason: .placeholder)
        .containerBackground(WPalette.paper, for: .widget)
    }
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
