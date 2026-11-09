import SwiftUI
import LiqianCore

// MARK: - 方向签：收礼＝朱砂底签（白事内用素灰蓝），随礼＝素蓝灰底签

public struct DirectionTag: View {
    public let direction: String
    public let bai: Bool

    public init(direction: String, bai: Bool = false) {
        self.direction = direction
        self.bai = bai
    }

    public var body: some View {
        let isReceived = direction == LiqianConstants.received
        // 浅签口径（对标大厂列表）：实心填充每行一枚会把强调色摊成底纹；
        // 改浅底＋同色文字，方向靠色相区分，白事/随礼统一素灰蓝
        let fg = isReceived ? (bai ? Palette.baiPrimary : Palette.primary) : Palette.baiPrimary
        // 对比度定版（v4.4，WCAG 公式逐组合实算，文字色对合成底）：
        // 旧浅底 0.13 时夜晚主题收礼签仅 4.13:1、黄色主题 4.16:1，未过 AA 4.5
        // （审计登记的「随礼签深色约 2.6:1」是更早的实心填充口径遗留数，
        // 实心白字对 #93A1AD = 2.64:1，现行浅签下随礼签实测 5.07:1 已达标，
        // 本轮把全部组合一并提到 ≥4.5）。浅底降到 0.06＋同色描边 0.45 保签形：
        // 五主题 × 两方向最低 4.53:1（夜晚收礼），随礼/白事签最低 5.36:1。
        let bg = fg.opacity(0.06)
        Text(direction)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(fg)
            // 签内边距为签形控件内部微调字面量（PRO-AUDIT §4.1 豁免口径），不走梯队
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner))
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner)
                    .stroke(fg.opacity(0.45), lineWidth: 1)
            )
    }
}

// MARK: - 待送出素签：描边小签

public struct PendingTag: View {
    public let bai: Bool

    public init(bai: Bool = false) {
        self.bai = bai
    }

    public var body: some View {
        let color = bai ? Palette.baiPrimary : Palette.stone
        Text("待送出")
            .font(.caption2)
            .foregroundStyle(color)
            // 同 DirectionTag：签内边距字面量豁免
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner)
                    .stroke(color, lineWidth: 1)
            )
    }
}

// MARK: - 礼簿封面卡（列表行）
// 左：事由小签（朱砂/白事素灰蓝窄签，竖排事由 + 印点）——PRO-AUDIT #6 定版：
// 封面满块是唯一记忆点，只出现在礼簿详情页头部一次；列表逐行重复会把记忆点摊成底纹
// 右：标题、日期备注、收/随小计与笔数（金额一律墨色，v3 纪律）

public struct LedgerCoverCard: View {
    public let ledger: Ledger
    public let receivedCents: Int
    public let givenCents: Int
    public let count: Int

    public init(ledger: Ledger, receivedCents: Int, givenCents: Int, count: Int) {
        self.ledger = ledger
        self.receivedCents = receivedCents
        self.givenCents = givenCents
        self.count = count
    }

    private var isBai: Bool { ledger.isBai }

    public var body: some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            coverBlock
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(ledger.title)
                    .font(.headline)
                    .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                    .lineLimit(1)
                subtitleRow
                HStack(spacing: 0) {
                    Text("收礼")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    // 大字号（Dynamic Type）防溢出（v4.4）：金额单行＋下限缩放，
                    // 宁可略小不换行撑破卡面；正常字号下不触发
                    Text(LedgerMath.fmtMoney(cents: receivedCents))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer().frame(width: 14)
                    Text("随礼")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: givenCents))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer()
                    Text("\(count) 笔")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.top, LiqianMetrics.spacingS)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
        }
        .padding(LiqianMetrics.cardPadding)
        .frame(minHeight: LiqianMetrics.minTapTarget)
        .background(
            isBai ? Palette.baiCard : Palette.card,
            in: RoundedRectangle(cornerRadius: LiqianMetrics.coverCorner)
        )
        .contentShape(RoundedRectangle(cornerRadius: LiqianMetrics.coverCorner))
    }

    /// 副标题分段排布（PRO-AUDIT §4.4：弃用中点拼接的元信息串）：
    /// 公历（displayString 定版格式）/ 农历 / 备注各成一段，备注超长截断
    private var subtitleRow: some View {
        HStack(spacing: LiqianMetrics.spacingXS) {
            // 公历/农历两段优先保全（大字号时先缩后截），备注最后让位
            Text(LiqianDate.displayString(for: ledger.date))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(LiqianDate.lunarString(for: ledger.date))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !ledger.note.isEmpty {
                Text(ledger.note)
                    .lineLimit(1)
            }
        }
        .font(.footnote)
        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
    }

    /// 事由小签（PRO-AUDIT #6）：30×64 朱砂窄签、竖排事由、无高光拟物；
    /// 满块封面移交礼簿详情页头部（LedgerDetailView 自有封面块）。
    /// 小签圆角 v5.14 改走 iOS 26 系统 ConcentricRectangle：本签是卡面
    /// 内边距内嵌元素（容器 coverCorner、四边 cardPadding），正是系统
    /// 同心机制的适用场景，圆角由系统按实际边距推导，不再手算。
    private var coverBlock: some View {
        let base = isBai ? Palette.baiPrimaryFill : Palette.primaryFill
        return ZStack {
            ConcentricRectangle()
                .fill(base)
            VStack(spacing: LiqianMetrics.spacingXS) {
                Text(ledger.type.map { String($0) }.joined(separator: "\n"))
                    .font(.liqianSerifFixed(size: 15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 30, height: 64)
    }
}

// MARK: - 统一卡片表面：卡面色与页面底的微色阶分层（v4.6 质感审计第 1 条起
// 去描边：分层靠 Palette.card vs pageBG 约 ΔL*2 的色阶 + 间距，不画 hairline；
// 白事传 bai: true 换白事令牌。功能性描边不在此列——方向签（对比度 ≥4.5:1）、
// 白事素蓝线、金额键盘键面线各有其保留理由，见 docs/V46-NOTES.md 质感审计节）

public extension View {
    func liqianCardSurface(bai: Bool = false, padding: CGFloat = LiqianMetrics.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                bai ? Palette.baiCard : Palette.card,
                in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
            )
    }
}

// MARK: - 印章：纯朱砂圆角方印、白字衬线、无金边（v3；礼谱 PDF 封面/汇总页用同款造型绘制）
// PDF 与分享图卡是静态绘制，那边按此规格复刻：圆角 8、朱砂底、白字、内细框。

// MARK: - 金额文本组件（质感审计第 2 条）：内部读 colorScheme，暗色自动降字重一档

public struct LiqianMoneyText: View {
    @Environment(\.colorScheme) private var colorScheme

    private let text: String
    private let style: Font.TextStyle
    private let color: Color

    public init(_ text: String, style: Font.TextStyle = .title3, color: Color = Palette.ink) {
        self.text = text
        self.style = style
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.liqianMoney(style, dark: colorScheme == .dark))
            .foregroundStyle(color)
    }
}

// MARK: - 逐笔金额组件（v5.0.2）：符号＋语义双色的唯一呈现点
// 全 App 每一处「逐笔收/送金额」只许用本组件：文本走
// LedgerMath.signedMoney（收 +¥N / 送 −¥N / 零 ¥0），颜色走
// MoneyTone（收主题强调、送黛青、白事降饱和、零回墨），字阶走
// liqianMoney（暗色自动降字重，与 LiqianMoneyText 同口径）。
// VoiceOver 读方向词＋金额（signedMoneyAccessibility），不读符号。
// 汇总数字（合计/差额/待回）禁用本组件——仍走 fmtMoney＋墨色。

public struct SignedMoneyText: View {
    @Environment(\.colorScheme) private var colorScheme

    private let cents: Int
    private let direction: String
    private let bai: Bool
    private let style: Font.TextStyle

    public init(
        cents: Int,
        direction: String,
        bai: Bool = false,
        style: Font.TextStyle = .title3
    ) {
        self.cents = cents
        self.direction = direction
        self.bai = bai
        self.style = style
    }

    private var foreground: Color {
        if cents == 0 { return MoneyTone.neutralColor(bai: bai) }
        return MoneyTone.tone(direction: direction).color(bai: bai)
    }

    public var body: some View {
        Text(LedgerMath.signedMoney(cents: cents, direction: direction))
            .font(.liqianMoney(style, dark: colorScheme == .dark))
            .foregroundStyle(foreground)
            .accessibilityLabel(LedgerMath.signedMoneyAccessibility(cents: cents, direction: direction))
    }
}

public struct SealStampView: View {
    /// 印面字（通常取礼簿名首字）
    public let char: String
    public let size: CGFloat
    public let bai: Bool
    /// 静态成品（分享图卡）传 true：印章恒朱砂定版，不跟随 App 主题（v2.5 包 6）
    public let fixedBrand: Bool

    public init(char: String, size: CGFloat = 56, bai: Bool = false, fixedBrand: Bool = false) {
        self.char = char
        self.size = size
        self.bai = bai
        self.fixedBrand = fixedBrand
    }

    public var body: some View {
        let bg = bai ? Palette.baiPrimaryFill : (fixedBrand ? Palette.brandFillFixed : Palette.primaryFill)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16)
                .fill(bg)
            // 印面内框：白文印的内细线
            RoundedRectangle(cornerRadius: size * 0.10)
                .stroke(.white.opacity(0.55), lineWidth: 1)
                .padding(size * 0.09)
            Text(char)
                .font(.liqianSerifFixed(size: size * 0.52))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 落印呈现：盖印动画（放大落下→回正停留→淡出），Reduce Motion 时只淡入淡出
// 用法：父视图维护 presented 布尔，true 时 overlay 本视图；动画时长约 1 秒，
// 父视图在 ~1.05 秒后置回 false 或执行后续动作（如 dismiss）。

public struct SealStampOverlay: View {
    public let char: String
    public let bai: Bool
    public let presented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    public init(char: String, bai: Bool = false, presented: Bool) {
        self.char = char
        self.bai = bai
        self.presented = presented
    }

    public var body: some View {
        ZStack {
            if presented {
                SealStampView(char: char, size: 84, bai: bai)
                    .scaleEffect(reduceMotion ? 1 : (landed ? 1 : 1.7))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (landed ? 0 : -8)))
                    .opacity(landed ? 1 : 0)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .onAppear {
                        landed = false
                        if reduceMotion {
                            withAnimation(.easeIn(duration: 0.2)) { landed = true }
                        } else {
                            // v5.14（第 3 期用户提前拍板）：落印曲线由自研
                            // MotionTokens.sealIn 换系统 .bouncy 预设弹簧——
                            // 缩放落下＋回正的盖印观感由系统弹簧拼装，
                            // 印章图形本体不动（品牌内容）
                            withAnimation(.bouncy) { landed = true }
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 右下角浮动添加按钮（FAB，v2.4 添加模型定版；v5 改玻璃主按钮）
// 全 App 新增动作收敛到这一个入口：圆形 56pt 玻璃钮（Mat.tinted：
// glassProminent＋主题强调染色），高光与按压形变由系统渲染。
// 用法：挂在页面根视图的 .overlay(alignment: .bottomTrailing)，
// bottomPadding 由调用方传 tabBarClearance 避让浮动 Tab 栏——
// v2.5 包 4 起全 App 不再隐藏 Tab 栏，详情页与列表页同口径。

public struct AddFloatingButton: View {
    /// 无障碍与提示文案，如「新建礼簿」「记一笔」
    public let label: String
    public let bottomPadding: CGFloat
    public let action: () -> Void

    /// Tab 栏避让量（v4.2 下调）：浮钮贴着浮动 Tab 栏上沿悬停，像钱迹那样
    /// 压在栏上方一点点（92pt 时明显飘得太高，用户真机指出）；62pt 时
    /// 56 圆钮下沿距屏底 62、与栏上沿轻微交叠，栏内各项仍可点。
    public static let tabBarClearance: CGFloat = 62

    public init(
        label: String,
        bottomPadding: CGFloat = LiqianMetrics.spacingM,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.bottomPadding = bottomPadding
        self.action = action
    }

    @State private var tapPulse = 0

    public var body: some View {
        Button {
            tapPulse += 1
            action()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                // 符号动效枚举点：FAB 点按 .bounce 一次（审计 §3.5）
                .symbolEffect(.bounce, value: tapPulse)
        }
        // v5 设计一期：玻璃主按钮（Mat.tinted）——系统玻璃自带按压形变，
        // 取代旧 ScaleOnPress＋自绘投影；Reduce Transparency 时系统自动
        // 回退实色，Reduce Motion 时符号动效由系统抑制。
        .liqianGlassButton(.tinted)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .padding(.trailing, LiqianMetrics.spacingM)
        .padding(.bottom, bottomPadding)
    }
}

// MARK: - 统计格（v5.3.2 统一定版）：多指标统计块的唯一排法
// 病根（用户圈图实锤）：旧各页统计格按内容宽度撑开——HStack 里几个
// 内容宽 VStack 前挤后散、起始线不齐、标签与数字各行其是，看着乱。
// 定版四条：①等宽分栏（每格 maxWidth .infinity 等分容器）；②格内
// 数字在上、标签在下，全 App 统一（旧图表总览/问账卡的「标签在上」
// 一并翻正）；③数字与标签均居中，中线对齐；④行列间距走
// LiqianMetrics 令牌、数字等宽字（liqianMoney 自带 monospacedDigit）。
// 口径红线：汇总数字颜色与字重沿用各页现状（默认墨色，v5.0.2 分界
// 不破——本组件只是排版，不许借套组件改色）；逐笔列表行、条形图、
// 静态成品（分享图卡固定画布）不是统计格，不入本组件。

/// 统计格单元：数字（上）＋标签（下），居中，等宽分栏由本格
/// maxWidth .infinity 与 StatRow/StatGrid 配合达成。
public struct StatCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ValueKind {
        /// 纯文本数字：走 liqianMoney 字阶（暗色降字重）＋可选单位小字
        case text(value: String, unit: String?, style: Font.TextStyle, color: Color)
        /// 自定义数字视图（如图表总览的滚动金额）：调用方自备，
        /// spokenValue 供 VoiceOver 读法（格子 combine 后默认读不到语义）
        case custom(view: AnyView, spoken: String)
    }

    private let label: String
    private let kind: ValueKind

    public init(
        label: String,
        value: String,
        unit: String? = nil,
        style: Font.TextStyle = .title3,
        color: Color = Palette.ink
    ) {
        self.label = label
        self.kind = .text(value: value, unit: unit, style: style, color: color)
    }

    public init<V: View>(
        label: String,
        spokenValue: String,
        @ViewBuilder value: () -> V
    ) {
        self.label = label
        self.kind = .custom(view: AnyView(value()), spoken: spokenValue)
    }

    private var spokenValue: String {
        switch kind {
        case .text(let value, let unit, _, _):
            return unit.map { "\(value)\($0)" } ?? value
        case .custom(_, let spoken):
            return spoken
        }
    }

    public var body: some View {
        VStack(spacing: LiqianMetrics.spacingXS) {
            valueView
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(spokenValue)")
    }

    @ViewBuilder
    private var valueView: some View {
        switch kind {
        case .text(let value, let unit, let style, let color):
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.liqianMoney(style, dark: colorScheme == .dark))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    // 大数字（六位数）防挤爆格子：单行下限缩放，与
                    // 礼簿封面卡金额同口径（0.7–0.75 带取下限更稳）
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    // 数值变更过渡（旧人物/礼簿头部 headerStat 既有行为，
                    // 随组件收敛进来；Reduce Motion 时关闭）
                    .animation(reduceMotion ? nil : .snappy, value: value)
                if let unit {
                    Text(unit)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
        case .custom(let view, _):
            view
        }
    }
}

/// 统计单行：横排等分（格子自带 maxWidth .infinity，HStack 内自动等宽）
public struct StatRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: LiqianMetrics.spacingM) { content }
    }
}

/// 统计网格：多行等宽分栏（列数由调用方按页面定版，行列间距同令牌）
public struct StatGrid<Content: View>: View {
    private let columns: Int
    private let content: Content

    public init(columns: Int, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.content = content()
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: LiqianMetrics.spacingM),
                count: columns
            ),
            spacing: LiqianMetrics.spacingM
        ) { content }
    }
}

