import SwiftUI
import LiqianCore

// MARK: - v5 设计一期令牌（docs/DESIGN.md 附录定版 / 前沿设计审计 §3）
// 定版融合句：「纸墨为体，玻璃为用。」内容层（卡/列表/图表/表单）永远
// 纸墨平面、零玻璃；玻璃只活在功能层（FAB、行动条、次按钮、指示器），
// 且染色只许走五主题强调令牌（Palette.primary / primaryFill），禁止写死
// 朱砂 hex——本 App 是五主题令牌表，写死必在其他主题下错版。
// 高光/同心圆角/滚动边缘一律系统渲染，禁止手工模仿（附录错令已撤销）。

// MARK: - Mat 材质三档（玻璃染色纪律）

/// 玻璃材质三档令牌：对应的系统 ButtonStyle / glassEffect 档位见下方扩展。
public enum Mat {
    /// 透明档：Sheet 抓手区一类极轻浮层（系统 .glass 的 .clear 变体口径）
    case clear
    /// 常规档：行动条、次按钮（系统 .glass / .regular）
    case regular
    /// 染色档：唯一主操作（系统 .glassProminent ＋主题强调染色）
    case tinted
}

public extension View {
    /// 玻璃按钮令牌入口：regular → .glass；tinted → .glassProminent 并以
    /// 主题强调令牌染色（跟随五主题，不写死色值）；clear 在按钮语境与
    /// regular 同档（系统按钮玻璃只有两档，透明档只用于浮层表面）。
    @ViewBuilder
    func liqianGlassButton(_ mat: Mat) -> some View {
        switch mat {
        case .tinted:
            self.buttonStyle(.glassProminent).tint(Palette.primary)
        case .regular, .clear:
            self.buttonStyle(.glass)
        }
    }

    /// 玻璃表面令牌入口（非按钮浮层）：tinted 以主题浅染令牌轻染，
    /// 不用主色满染——表面染色面积受控，守单强调纪律。
    @ViewBuilder
    func liqianGlassSurface(_ mat: Mat, in shape: some Shape) -> some View {
        switch mat {
        case .clear:
            self.glassEffect(.clear, in: shape)
        case .regular:
            self.glassEffect(.regular, in: shape)
        case .tinted:
            self.glassEffect(.regular.tint(Palette.primaryTint), in: shape)
        }
    }
}

// MARK: - Elevation（转正：替换全仓散落阴影字面量；v5.14 后仅剩卡档）

/// 阴影规格令牌：全仓阴影只许引用这两档（登记例外：落印浮层阴影属
/// 落印签名动效、年度报告分享图卡是静态成品绘制，均不在 UI 令牌口径内）。
public struct LiqianShadow: Sendable {
    public let opacity: Double
    public let radius: CGFloat
    public let y: CGFloat

    public init(opacity: Double, radius: CGFloat, y: CGFloat) {
        self.opacity = opacity
        self.radius = radius
        self.y = y
    }
}

public enum LiqianElevation {
    /// 卡档：贴面卡片的轻投影（原散落值 black 0.05–0.08 / r12 一带收敛于此）。
    /// v5.14 收敛后全仓仅剩一处在用——首开引导的礼谱封面意象（静态
    /// 内容意象、非列表卡面，系统无等价的静态意象投影），保留本档；
    /// 原「浮档」（floating）在 v5 玻璃收敛后已无调用点，本期随归位删除。
    public static let card = LiqianShadow(opacity: 0.06, radius: 12, y: 4)
}

public extension View {
    func liqianElevation(_ shadow: LiqianShadow) -> some View {
        self.shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}

// MARK: - 圆角同心机制（子圆角由容器推导，禁止手算）

public enum LiqianRadius {
    /// 同心圆角：内层元素圆角 = 容器圆角 − 内边距，下限 2pt。
    /// 旧手算个案（封面小签 20−16=4）自 v5 起一律走此推导。
    public static func concentric(container: CGFloat, padding: CGFloat) -> CGFloat {
        max(container - padding, 2)
    }
}

// MARK: - Motion 动效口径（v5.14 全原生整改后）
// 自研动效令牌四档曲线（press/liquidSpring/pageCrossfade/sealIn）
// 已整层退役：内容切换与入场一律系统默认动画（.default），落印走系统
// .bouncy 预设弹簧（见 Components.SealStampOverlay），玻璃按钮的按压
// 形变由系统玻璃自带。此处不再设任何自研曲线令牌——新动效先问系统
// 有没有，没有再议（全原生标准）。

// MARK: - 金额语义双色（v5.0.2 用户改版定版，docs/DESIGN.md 金额节）
// 记账软件式表达：逐笔金额 = 符号（LedgerMath.signedMoney）＋语义双色。
// 收礼走主题强调令牌（暖：朱砂/蓝/石墨/琥珀随主题），随礼走黛青（冷，
// 主题令牌 moneyGiven）——一暖一冷，扫一眼就分清方向。双色只染金额
// 数字本身：背景、图标、按钮、方向签一律不跟随染色，页面底色仍中性。
// 边界：合计/差额/净额/待回等「算出来的数」不入本口径，仍墨色；
// 礼谱 PDF 等导出排版不入本口径，纸墨形制不动。
public enum MoneyTone {
    case received
    case given

    /// 方向字符串（LiqianConstants）→ 语义向：收礼为 received，其余为 given
    public static func tone(direction: String) -> MoneyTone {
        direction == LiqianConstants.received ? .received : .given
    }

    /// 逐笔金额色：白事簿内走降饱和变体（白事克制），其余走主题令牌
    public func color(bai: Bool) -> Color {
        switch (self, bai) {
        case (.received, false): return Palette.moneyReceived
        case (.given, false): return Palette.moneyGiven
        case (.received, true): return Palette.moneyReceivedBai
        case (.given, true): return Palette.moneyGivenBai
        }
    }

    /// 零金额的中性色（与 LedgerMath.signedMoney 的 ¥0 中性呈现成对）：
    /// 零不带符号、也不着双色，回主文字墨（白事回白事墨）
    public static func neutralColor(bai: Bool) -> Color {
        bai ? Palette.baiInk : Palette.ink
    }
}
